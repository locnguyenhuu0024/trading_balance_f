"""Allowlisted, bounded and cacheable reads from the configured OKX account."""

from __future__ import annotations

from collections import OrderedDict
from concurrent.futures import ThreadPoolExecutor
from copy import deepcopy
from dataclasses import dataclass, field
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
from math import ceil, isfinite
import re
import threading
import time
from typing import Any, Callable
from urllib.parse import parse_qsl

from .currency import CurrencyClient, CurrencyClientError, CurrencyTransport
from .okx import OKXClient, OKXError


SessionGuard = Callable[[], Any]
AccountFingerprint = Callable[[Any], str | None]

_INSTRUMENT_ID = re.compile(r"[A-Z0-9]+(?:-[A-Z0-9]+){1,3}\Z")
_CURRENCY = re.compile(r"[A-Z0-9]{1,20}\Z")
_DECIMAL_CURSOR = re.compile(r"[0-9]{1,32}\Z")
_LIMIT = re.compile(r"[0-9]{1,3}\Z")
_ALLOWED_BARS = frozenset({"1H", "4H", "6Hutc", "1Dutc", "1Wutc"})
_INSTRUMENT_TYPES = frozenset({"SPOT", "MARGIN", "SWAP", "FUTURES"})
_PRIVATE_INSTRUMENT_TYPES = frozenset({"MARGIN", "SWAP", "FUTURES"})
_RATE_LIMIT_CODES = frozenset({"50011", "50040"})
_DISPLAY_POSITION_BUNDLE = "$display/positions"


class GatewayError(Exception):
    """Sanitized public error raised by gateway validation and transport paths."""

    def __init__(
        self,
        status: int,
        code: str,
        message: str,
        *,
        headers: list[tuple[str, str]] | None = None,
        rate_limit_generation: int | None = None,
    ):
        super().__init__(message)
        self.status = status
        self.code = code
        self.message = message
        self.headers = headers or []
        self.rate_limit_generation = rate_limit_generation


@dataclass(frozen=True)
class GatewayIdentity:
    account: dict[str, Any]
    fingerprint: str
    generation: int


@dataclass(frozen=True)
class _Route:
    scope: str
    ttl_seconds: int
    upstream_path: str | None
    query_fields: frozenset[str]
    required_fields: frozenset[str] = frozenset()

    @property
    def private(self) -> bool:
        return self.scope == "private"


@dataclass(frozen=True)
class _CacheEntry:
    data: list[Any]
    fetched_at: float
    expires_at: float
    deadline: float
    private: bool


@dataclass
class _Flight:
    event: threading.Event = field(default_factory=threading.Event)
    value: Any = None
    error: GatewayError | None = None
    rate_limit_generation: int | None = None


_ROUTES: dict[str, _Route] = {
    "public/instruments": _Route(
        "public", 60, "/api/v5/public/instruments", frozenset({"instType", "instId"}), frozenset({"instType"})
    ),
    "market/ticker": _Route(
        "public", 1, "/api/v5/market/ticker", frozenset({"instId"}), frozenset({"instId"})
    ),
    "market/tickers": _Route(
        "public", 1, "/api/v5/market/tickers", frozenset({"instType"}), frozenset({"instType"})
    ),
    "market/quotes": _Route(
        "public", 1, None, frozenset({"instIds"}), frozenset({"instIds"})
    ),
    "market/candles": _Route(
        "public", 15, "/api/v5/market/candles",
        frozenset({"instId", "bar", "limit", "after", "before"}), frozenset({"instId"})
    ),
    "market/history-candles": _Route(
        "public", 15, "/api/v5/market/history-candles",
        frozenset({"instId", "bar", "limit", "after", "before"}), frozenset({"instId"})
    ),
    "public/funding-rate": _Route(
        "public", 15, "/api/v5/public/funding-rate", frozenset({"instId"}), frozenset({"instId"})
    ),
    "public/open-interest": _Route(
        "public", 15, "/api/v5/public/open-interest",
        frozenset({"instId", "instType"}), frozenset({"instId", "instType"})
    ),
    "account/balance": _Route(
        "private", 1, "/api/v5/account/balance", frozenset({"ccy"})
    ),
    "account/positions": _Route(
        "private", 1, "/api/v5/account/positions", frozenset({"instType", "instId"}), frozenset({"instType"})
    ),
    "trade/orders-pending": _Route(
        "private", 1, "/api/v5/trade/orders-pending", frozenset({"instType"}), frozenset({"instType"})
    ),
    "trade/orders-history": _Route(
        "private", 1, "/api/v5/trade/orders-history", frozenset({"instType"}), frozenset({"instType"})
    ),
    "account/config": _Route(
        "private", 1, "/api/v5/account/config", frozenset()
    ),
    "account/instruments": _Route(
        "private", 60, "/api/v5/account/instruments",
        frozenset({"instType", "instId"}), frozenset({"instType", "instId"})
    ),
    "account/trade-fee": _Route(
        "private", 60, "/api/v5/account/trade-fee",
        frozenset({"instType", "instId"}), frozenset({"instType", "instId"})
    ),
    "account/interest-rate": _Route(
        "private", 60, "/api/v5/account/interest-rate", frozenset({"ccy"}), frozenset({"ccy"})
    ),
    "account/interest-accrued": _Route(
        "private", 15, "/api/v5/account/interest-accrued",
        frozenset({"instId", "mgnMode", "ccy", "limit", "after", "before"}),
        frozenset({"instId", "mgnMode"})
    ),
    "currency/usdt-vnd": _Route(
        "public", 60, None, frozenset()
    ),
}

_AGGREGATE_TYPES: dict[str, tuple[str, ...]] = {
    "account/positions": ("MARGIN", "SWAP", "FUTURES"),
    "trade/orders-pending": ("SPOT", "MARGIN", "SWAP", "FUTURES"),
    "trade/orders-history": ("SPOT", "MARGIN", "SWAP", "FUTURES"),
}


class DataGateway:
    MAX_CACHE_ENTRIES = 256
    MAX_INFLIGHT_KEYS = 32
    MAX_CONCURRENT_READS = 4
    MAX_CONCURRENT_AGGREGATES = 4
    IDENTITY_TTL_SECONDS = 1.0
    READ_ACQUIRE_TIMEOUT_SECONDS = 10.0
    FLIGHT_WAIT_TIMEOUT_SECONDS = 45.0

    def __init__(
        self,
        okx: OKXClient,
        *,
        account_fingerprint: AccountFingerprint,
        currency_transport: CurrencyTransport | None = None,
        monotonic_clock: Callable[[], float] = time.monotonic,
        wall_clock: Callable[[], float] = time.time,
    ):
        self._okx = okx
        self._account_fingerprint = account_fingerprint
        self._currency = CurrencyClient(transport=currency_transport)
        self._monotonic = monotonic_clock
        self._wall_clock = wall_clock
        self._read_slots = threading.BoundedSemaphore(self.MAX_CONCURRENT_READS)
        self._aggregate_slots = threading.BoundedSemaphore(self.MAX_CONCURRENT_AGGREGATES)
        self._aggregate_executor = ThreadPoolExecutor(
            max_workers=self.MAX_CONCURRENT_READS,
            thread_name_prefix="data-gateway-read",
        )
        self._cache_lock = threading.RLock()
        self._cache: OrderedDict[tuple[Any, ...], _CacheEntry] = OrderedDict()
        self._inflight: dict[tuple[Any, ...], _Flight] = {}
        self._identity_condition = threading.Condition()
        self._identity: GatewayIdentity | None = None
        self._identity_deadline = 0.0
        self._identity_cooldown_deadline = 0.0
        self._identity_generation = 0
        self._identity_flight: _Flight | None = None

    def handle(
        self,
        method: str,
        suffix: str,
        query_string: str,
        *,
        session_guard: SessionGuard | None = None,
    ) -> dict[str, Any]:
        route = _ROUTES.get(suffix)
        if route is None:
            raise GatewayError(404, "not_found", "The requested endpoint was not found.")
        if route.private:
            self._require_session_guard(session_guard)
        try:
            if method.upper() != "GET":
                raise GatewayError(
                    405, "method_not_allowed", "This endpoint only accepts GET requests.",
                    headers=[("Allow", "GET")],
                )
            params = self._parse_query(route, query_string)
            identity = self._identity_snapshot() if route.private else None
            if route.private:
                self._require_session_guard(session_guard)

            if suffix in _AGGREGATE_TYPES and params.get("instType") == "ALL":
                entry, cache_hit = self._read_aggregate(suffix, params, identity, session_guard)
            elif suffix == "market/quotes":
                entry, cache_hit = self._read_quotes(params)
            elif suffix == "currency/usdt-vnd":
                entry, cache_hit = self._read_cached(suffix, params, None)
            else:
                entry, cache_hit = self._read_cached(suffix, params, identity)

            if route.private:
                self._require_session_guard(session_guard)
                if identity is None:
                    raise self._account_unavailable()
                self._current_identity_for(identity)
                if not self.is_deadline_fresh(entry.deadline):
                    if suffix in _AGGREGATE_TYPES and params.get("instType") == "ALL":
                        raise self._data_stale()
                    entry, cache_hit = self._read_cached(suffix, params, identity)
                    self._require_session_guard(session_guard)
                    self._current_identity_for(identity)
                    if not self.is_deadline_fresh(entry.deadline):
                        raise self._data_stale()
            return self._envelope(entry, cache_hit)
        except GatewayError as error:
            if route.private:
                self._require_session_guard(session_guard)
                error = self._supersede_rate_limit_after_invalidation(error)
            raise error from None

    def read_internal(
        self,
        suffix: str,
        params: dict[str, str],
        *,
        session_guard: SessionGuard | None = None,
    ) -> list[dict[str, Any]]:
        data, _deadline = self.read_internal_with_deadline(
            suffix, params, session_guard=session_guard
        )
        return data

    def read_internal_with_deadline(
        self,
        suffix: str,
        params: dict[str, str],
        *,
        session_guard: SessionGuard | None = None,
    ) -> tuple[list[dict[str, Any]], float]:
        route = _ROUTES.get(suffix)
        if route is None or route.upstream_path is None:
            raise GatewayError(404, "not_found", "The requested endpoint was not found.")
        if route.private:
            self._require_session_guard(session_guard)
        try:
            normalized = self._validate_params(route, dict(params))
            identity = self._identity_snapshot() if route.private else None
            if route.private:
                self._require_session_guard(session_guard)
            entry, _ = self._read_cached(suffix, normalized, identity)
            if route.private:
                self._require_session_guard(session_guard)
                if identity is None:
                    raise self._account_unavailable()
                self._current_identity_for(identity)
            if not self.is_deadline_fresh(entry.deadline):
                raise self._data_stale()
            return deepcopy(entry.data), entry.deadline
        except GatewayError as error:
            if route.private:
                self._require_session_guard(session_guard)
                error = self._supersede_rate_limit_after_invalidation(error)
            raise error from None

    def read_display_positions(
        self,
        *,
        session_guard: SessionGuard,
    ) -> tuple[GatewayIdentity, dict[str, list[dict[str, Any]]], float]:
        """Read the three private position groups as one staged display observation."""
        self._require_session_guard(session_guard)
        try:
            identity = self._identity_snapshot()
            self._require_session_guard(session_guard)
            entry, _cache_hit = self._read_display_position_bundle(identity)
            self._require_session_guard(session_guard)
            current = self._identity_snapshot()
            self._ensure_identity_matches(identity, current)
            self._require_session_guard(session_guard)
            if not self.is_deadline_fresh(entry.deadline):
                raise self._data_stale()
            return current, self._unpack_display_position_bundle(entry.data), entry.deadline
        except GatewayError as error:
            # Authorization belongs to each waiter, even when shared exchange work failed.
            self._require_session_guard(session_guard)
            raise self._supersede_rate_limit_after_invalidation(error) from None

    def is_deadline_fresh(self, deadline: float) -> bool:
        return deadline > self._monotonic()

    def identity_for_display(
        self,
        *,
        session_guard: SessionGuard,
        force: bool = False,
    ) -> GatewayIdentity:
        self._require_session_guard(session_guard)
        try:
            identity = self._identity_snapshot(force=force)
        except GatewayError as error:
            self._require_session_guard(session_guard)
            raise self._supersede_rate_limit_after_invalidation(error) from None
        self._require_session_guard(session_guard)
        return GatewayIdentity(
            account=deepcopy(identity.account),
            fingerprint=identity.fingerprint,
            generation=identity.generation,
        )

    def invalidate_private(self) -> None:
        """Fence all private observations after a potentially mutating action."""
        with self._identity_condition:
            self._identity_generation += 1
            self._identity = None
            self._identity_deadline = 0.0
            identity_flight = self._identity_flight
            self._identity_flight = None
            if identity_flight is not None:
                identity_flight.error = self._account_changed()
                identity_flight.event.set()
            self._identity_condition.notify_all()
            with self._cache_lock:
                for key, entry in list(self._cache.items()):
                    if entry.private:
                        self._cache.pop(key, None)
                for key, flight in list(self._inflight.items()):
                    if key and key[0] == "private":
                        flight.error = self._account_changed()
                        flight.event.set()
                        self._inflight.pop(key, None)

    @staticmethod
    def _require_session_guard(session_guard: SessionGuard | None) -> None:
        if session_guard is None:
            raise GatewayError(401, "authentication_required", "A valid session is required.")
        try:
            session_guard()
        except Exception as error:
            if (
                getattr(error, "status", None) == 401
                and getattr(error, "code", None) == "authentication_required"
            ):
                raise GatewayError(
                    401, "authentication_required", "A valid session is required."
                ) from None
            raise

    def _parse_query(self, route: _Route, query_string: str) -> dict[str, str]:
        if not isinstance(query_string, str):
            raise self._invalid_query()
        try:
            if len(query_string.encode("utf-8", "strict")) > 4096:
                raise self._invalid_query()
            pairs = parse_qsl(
                query_string,
                keep_blank_values=True,
                strict_parsing=True,
                encoding="utf-8",
                errors="strict",
                max_num_fields=32,
            )
        except (UnicodeError, ValueError):
            raise self._invalid_query() from None
        params: dict[str, str] = {}
        for key, value in pairs:
            if key in params:
                raise self._invalid_query()
            params[key] = value
        return self._validate_params(route, params)

    def _validate_params(self, route: _Route, params: dict[str, str]) -> dict[str, str]:
        if any(not isinstance(key, str) or not isinstance(value, str) for key, value in params.items()):
            raise self._invalid_query()
        if set(params) - route.query_fields or route.required_fields - set(params):
            raise self._invalid_query()
        for key, value in params.items():
            if not value:
                raise self._invalid_query()
            if key in {"instId"} and not self._valid_instrument_id(value):
                raise self._invalid_query()
            if key == "instIds":
                requested = value.split(",")
                if not requested or any(not self._valid_spot_id(item) for item in requested):
                    raise self._invalid_query()
                requested = list(dict.fromkeys(requested))
                if not 1 <= len(requested) <= 100:
                    raise self._invalid_query()
                params[key] = ",".join(requested)
            elif key == "ccy" and not _CURRENCY.fullmatch(value):
                raise self._invalid_query()
            elif key == "instType":
                allowed = _INSTRUMENT_TYPES
                if route.private and route.upstream_path == "/api/v5/account/positions":
                    allowed = _PRIVATE_INSTRUMENT_TYPES | {"ALL"}
                elif route.private and route.upstream_path in {
                    "/api/v5/trade/orders-pending", "/api/v5/trade/orders-history"
                }:
                    allowed = _INSTRUMENT_TYPES | {"ALL"}
                elif route.private and route.upstream_path in {
                    "/api/v5/account/instruments", "/api/v5/account/trade-fee"
                }:
                    allowed = frozenset({"MARGIN"})
                elif route.upstream_path == "/api/v5/market/tickers":
                    allowed = frozenset({"SPOT", "SWAP", "FUTURES"})
                elif route.upstream_path == "/api/v5/public/open-interest":
                    allowed = frozenset({"SWAP"})
                if value not in allowed:
                    raise self._invalid_query()
            elif key == "bar" and value not in _ALLOWED_BARS:
                raise self._invalid_query()
            elif key in {"after", "before"} and not _DECIMAL_CURSOR.fullmatch(value):
                raise self._invalid_query()
            elif key == "limit":
                max_limit = 100 if route.upstream_path == "/api/v5/account/interest-accrued" else 300
                if not _LIMIT.fullmatch(value) or not 1 <= int(value) <= max_limit:
                    raise self._invalid_query()
                params[key] = str(int(value))
            elif key == "mgnMode" and value != "isolated":
                raise self._invalid_query()
        if route.upstream_path in {
            "/api/v5/public/funding-rate", "/api/v5/public/open-interest"
        } and not params.get("instId", "").endswith("-SWAP"):
            raise self._invalid_query()
        return {key: params[key] for key in sorted(params)}

    @staticmethod
    def _valid_instrument_id(value: str) -> bool:
        return len(value) <= 100 and _INSTRUMENT_ID.fullmatch(value) is not None

    @classmethod
    def _valid_spot_id(cls, value: str) -> bool:
        return cls._valid_instrument_id(value) and value.count("-") == 1

    def _read_aggregate(
        self,
        suffix: str,
        params: dict[str, str],
        identity: GatewayIdentity | None,
        session_guard: SessionGuard | None,
    ) -> tuple[_CacheEntry, bool]:
        if not self._aggregate_slots.acquire(timeout=self.READ_ACQUIRE_TIMEOUT_SECONDS):
            raise self._busy()
        try:
            for attempt in range(2):
                def read_type(instrument_type: str) -> tuple[_CacheEntry, bool]:
                    self._require_session_guard(session_guard)
                    child_params = {"instType": instrument_type}
                    if suffix == "account/positions" and params.get("instId"):
                        child_params["instId"] = params["instId"]
                    result = self._read_cached(suffix, child_params, identity)
                    self._require_session_guard(session_guard)
                    return result

                futures = [
                    self._aggregate_executor.submit(read_type, instrument_type)
                    for instrument_type in _AGGREGATE_TYPES[suffix]
                ]
                results: list[tuple[_CacheEntry, bool] | None] = []
                failure: Exception | None = None
                for future in futures:
                    try:
                        results.append(future.result())
                    except Exception as error:
                        results.append(None)
                        if failure is None:
                            failure = error
                if failure is not None:
                    if isinstance(failure, GatewayError):
                        raise failure
                    raise self._unavailable() from None
                complete = [result for result in results if result is not None]
                entries = [result[0] for result in complete]
                combined = self._combine_entries(
                    [deepcopy(row) for entry in entries for row in entry.data],
                    entries,
                    private=True,
                )
                if identity is None:
                    raise self._account_unavailable()
                after = self._identity_snapshot(force=True)
                self._ensure_identity_matches(identity, after)
                if self.is_deadline_fresh(combined.deadline):
                    return combined, all(result[1] for result in complete)
                if attempt == 1:
                    raise self._data_stale()
            raise self._data_stale()
        finally:
            self._aggregate_slots.release()

    def _read_quotes(self, params: dict[str, str]) -> tuple[_CacheEntry, bool]:
        tickers, cache_hit = self._read_cached("market/tickers", {"instType": "SPOT"}, None)
        requested = set(params["instIds"].split(","))
        rows = [item for item in tickers.data if item.get("instId") in requested]
        return self._combine_entries(rows, [tickers], private=False), cache_hit

    def _read_cached(
        self,
        suffix: str,
        params: dict[str, str],
        identity: GatewayIdentity | None,
    ) -> tuple[_CacheEntry, bool]:
        route = _ROUTES[suffix]
        if route.private and identity is None:
            raise self._account_unavailable()
        key = self._cache_key(suffix, params, identity, route.private)
        now = self._monotonic()
        with self._cache_lock:
            cached = self._cache.get(key)
            if cached is not None and cached.deadline > now:
                self._cache.move_to_end(key)
                entry = cached
                is_hit = True
                flight = None
                leader = False
            else:
                if cached is not None:
                    self._cache.pop(key, None)
                flight = self._inflight.get(key)
                if flight is not None:
                    leader = False
                    entry = None
                    is_hit = False
                else:
                    if len(self._inflight) >= self.MAX_INFLIGHT_KEYS:
                        raise self._busy()
                    flight = _Flight()
                    self._inflight[key] = flight
                    leader = True
                    entry = None
                    is_hit = False

        if is_hit:
            if route.private and not self._identity_is_current(identity):
                raise self._account_changed()
            return deepcopy(entry), True
        if not leader:
            assert flight is not None
            return self._wait_for_flight(flight, identity, route.private), False

        assert flight is not None
        try:
            data = self._load_data(suffix, params)
            # Start TTL at acquisition, before post-read identity fencing.
            entry = self._new_entry(data, route)
            if route.private:
                after = self._identity_snapshot(force=True)
                self._ensure_identity_matches(identity, after)
            if not self.is_deadline_fresh(entry.deadline):
                raise self._data_stale()
            self._store_entry(key, entry, identity if route.private else None)
            if not self.is_deadline_fresh(entry.deadline):
                self._remove_entry_if_same(key, entry)
                raise self._data_stale()
            if flight.error is None:
                flight.value = entry
        except GatewayError as error:
            if flight.error is None:
                flight.error = error
                flight.rate_limit_generation = error.rate_limit_generation
        except Exception:
            if flight.error is None:
                flight.error = self._unavailable()
        finally:
            with self._cache_lock:
                self._inflight.pop(key, None)
                flight.event.set()
        if flight.error is not None:
            raise self._effective_flight_error(flight)
        if flight.value is None:
            raise self._unavailable()
        return deepcopy(flight.value), False

    def _read_display_position_bundle(
        self,
        identity: GatewayIdentity,
    ) -> tuple[_CacheEntry, bool]:
        key = self._cache_key(_DISPLAY_POSITION_BUNDLE, {}, identity, True)
        now = self._monotonic()
        with self._cache_lock:
            cached = self._cache.get(key)
            if cached is not None and cached.deadline > now:
                self._cache.move_to_end(key)
                flight = None
                leader = False
                entry = cached
                cache_hit = True
            else:
                if cached is not None:
                    self._cache.pop(key, None)
                flight = self._inflight.get(key)
                if flight is not None:
                    leader = False
                    entry = None
                    cache_hit = False
                else:
                    if len(self._inflight) >= self.MAX_INFLIGHT_KEYS:
                        raise self._busy()
                    flight = _Flight()
                    self._inflight[key] = flight
                    leader = True
                    entry = None
                    cache_hit = False

        if cache_hit:
            if not self._identity_is_current(identity):
                raise self._account_changed()
            if not self.is_deadline_fresh(entry.deadline):
                raise self._data_stale()
            return deepcopy(entry), True
        if not leader:
            assert flight is not None
            return self._wait_for_flight(flight, identity, True), False

        assert flight is not None
        aggregate_acquired = False
        try:
            if not self._aggregate_slots.acquire(timeout=self.READ_ACQUIRE_TIMEOUT_SECONDS):
                raise self._busy()
            aggregate_acquired = True

            futures = []
            submit_error: Exception | None = None
            for instrument_type in ("MARGIN", "SWAP", "FUTURES"):
                try:
                    futures.append(
                        self._aggregate_executor.submit(
                            self._load_display_position_group, instrument_type
                        )
                    )
                except Exception as error:
                    submit_error = error
                    break

            groups: dict[str, _CacheEntry] = {}
            failure: Exception | None = submit_error
            if submit_error is not None:
                for future in futures:
                    future.cancel()
            # Drain every submitted sibling before either returning an error or
            # starting the forced post-identity proof. Running reads retain the
            # aggregate slot and bundle flight until the underlying request ends.
            for index, future in enumerate(futures):
                try:
                    instrument_type, child_entry = future.result()
                    groups[instrument_type] = child_entry
                except Exception as error:
                    if failure is None:
                        failure = error
                        for sibling in futures[index + 1:]:
                            sibling.cancel()
            if failure is not None:
                if isinstance(failure, GatewayError):
                    raise failure
                raise self._unavailable() from None
            if set(groups) != set(_PRIVATE_INSTRUMENT_TYPES):
                raise self._unavailable()
            if flight.error is not None:
                raise self._effective_flight_error(flight)

            # This proof starts only after all three private reads have completed.
            after = self._identity_snapshot(force=True)
            self._ensure_identity_matches(identity, after)
            entry = self._display_position_bundle_entry(groups)
            if not self.is_deadline_fresh(entry.deadline):
                raise self._data_stale()
            self._publish_display_position_bundle(key, entry, identity, flight)
        except GatewayError as error:
            if flight.error is None:
                flight.error = error
                flight.rate_limit_generation = error.rate_limit_generation
        except Exception:
            if flight.error is None:
                flight.error = self._unavailable()
        finally:
            if aggregate_acquired:
                self._aggregate_slots.release()
            with self._cache_lock:
                if self._inflight.get(key) is flight:
                    self._inflight.pop(key, None)
                flight.event.set()

        if flight.error is not None:
            raise self._effective_flight_error(flight)
        if not isinstance(flight.value, _CacheEntry):
            raise self._unavailable()
        return deepcopy(flight.value), False

    def _load_display_position_group(
        self,
        instrument_type: str,
    ) -> tuple[str, _CacheEntry]:
        route = _ROUTES["account/positions"]
        params = self._validate_params(route, {"instType": instrument_type})
        data = self._load_data("account/positions", params)
        return instrument_type, self._new_entry(data, route)

    @staticmethod
    def _display_position_bundle_entry(
        groups: dict[str, _CacheEntry],
    ) -> _CacheEntry:
        entries = [groups[kind] for kind in ("MARGIN", "SWAP", "FUTURES")]
        return _CacheEntry(
            data=[
                {"instType": kind, "positions": deepcopy(groups[kind].data)}
                for kind in ("MARGIN", "SWAP", "FUTURES")
            ],
            fetched_at=min(entry.fetched_at for entry in entries),
            expires_at=min(entry.expires_at for entry in entries),
            deadline=min(entry.deadline for entry in entries),
            private=True,
        )

    @staticmethod
    def _unpack_display_position_bundle(
        data: list[Any],
    ) -> dict[str, list[dict[str, Any]]]:
        groups: dict[str, list[dict[str, Any]]] = {}
        for item in data:
            if (
                not isinstance(item, dict)
                or item.get("instType") not in {"MARGIN", "SWAP", "FUTURES"}
                or not isinstance(item.get("positions"), list)
            ):
                raise DataGateway._account_unavailable()
            groups[item["instType"]] = deepcopy(item["positions"])
        if set(groups) != {"MARGIN", "SWAP", "FUTURES"}:
            raise DataGateway._account_unavailable()
        return groups

    def _publish_display_position_bundle(
        self,
        key: tuple[Any, ...],
        entry: _CacheEntry,
        identity: GatewayIdentity,
        flight: _Flight,
    ) -> None:
        if not self.is_deadline_fresh(entry.deadline):
            raise self._data_stale()
        with self._identity_condition:
            current = self._identity
            if (
                current is None
                or self._identity_deadline <= self._monotonic()
                or current.fingerprint != identity.fingerprint
                or current.generation != identity.generation
            ):
                raise self._account_changed()
            with self._cache_lock:
                if flight.error is not None:
                    raise self._effective_flight_error(flight)
                if not self.is_deadline_fresh(entry.deadline):
                    raise self._data_stale()
                self._insert_cache_locked(key, entry)
                flight.value = deepcopy(entry)

    def _wait_for_flight(
        self,
        flight: _Flight,
        identity: GatewayIdentity | None,
        private: bool,
    ) -> _CacheEntry:
        if not flight.event.wait(self.FLIGHT_WAIT_TIMEOUT_SECONDS):
            raise self._busy()
        if flight.error is not None:
            raise self._effective_flight_error(flight)
        if not isinstance(flight.value, _CacheEntry):
            raise self._unavailable()
        if private and not self._identity_is_current(identity):
            raise self._account_changed()
        if not self.is_deadline_fresh(flight.value.deadline):
            raise self._data_stale()
        return deepcopy(flight.value)

    def _load_data(self, suffix: str, params: dict[str, str]) -> list[Any]:
        route = _ROUTES[suffix]
        if suffix == "currency/usdt-vnd":
            try:
                rate = self._upstream_read(self._currency.usdt_vnd_rate)
            except CurrencyClientError:
                raise GatewayError(502, "currency_unavailable", "The currency rate is unavailable.") from None
            return [{"instId": "USDT-VND", "rate": rate, "source": "CoinGecko"}]
        if route.upstream_path is None:
            raise self._unavailable()
        is_public = route.scope == "public"
        try:
            response = self._upstream_read(
                lambda: self._okx.request(
                    "GET",
                    route.upstream_path,
                    params=params or None,
                    private=not is_public,
                )
            )
        except OKXError as error:
            raise self._map_okx_error(error) from None
        except GatewayError:
            raise
        except Exception:
            raise GatewayError(502, "exchange_unavailable", "The requested data is unavailable.") from None
        if not isinstance(response, dict) or str(response.get("code", "")) != "0":
            raise GatewayError(502, "exchange_unavailable", "The requested data is unavailable.")
        data = response.get("data")
        if not isinstance(data, list):
            raise GatewayError(502, "exchange_unavailable", "The requested data is unavailable.")
        if suffix in {"market/candles", "market/history-candles"}:
            if any(
                not isinstance(row, list)
                or not row
                or any(not isinstance(value, (str, int, float)) or isinstance(value, bool) for value in row)
                for row in data
            ):
                raise GatewayError(502, "exchange_unavailable", "The requested data is unavailable.")
        elif any(not isinstance(row, dict) for row in data):
            raise GatewayError(502, "exchange_unavailable", "The requested data is unavailable.")
        if suffix == "account/config":
            if len(data) != 1 or not data[0].get("uid"):
                raise GatewayError(502, "exchange_unavailable", "The requested data is unavailable.")
            allowed = {"uid", "mgnIsoMode", "acctLv", "posMode", "autoLoan"}
            data = [{key: value for key, value in row.items() if key in allowed} for row in data]
        if suffix == "market/ticker" and len(data) != 1:
            raise GatewayError(502, "exchange_unavailable", "The requested data is unavailable.")
        if suffix in {
            "public/instruments", "market/ticker", "market/tickers", "account/positions",
            "trade/orders-pending", "trade/orders-history",
        } and any(not isinstance(row.get("instId"), str) or not row.get("instId") for row in data):
            raise GatewayError(502, "exchange_unavailable", "The requested data is unavailable.")
        return deepcopy(data)

    def _upstream_read(self, request: Callable[[], Any]) -> Any:
        if not self._read_slots.acquire(timeout=self.READ_ACQUIRE_TIMEOUT_SECONDS):
            raise self._busy()
        try:
            return request()
        finally:
            self._read_slots.release()

    def _effective_flight_error(self, flight: _Flight) -> GatewayError:
        error = flight.error or self._unavailable()
        generation = flight.rate_limit_generation
        if generation is None:
            generation = error.rate_limit_generation
        if error.status == 429 and generation is not None:
            with self._identity_condition:
                if self._identity_generation != generation:
                    return self._account_changed()
        return error

    def _supersede_rate_limit_after_invalidation(
        self,
        error: GatewayError,
    ) -> GatewayError:
        generation = error.rate_limit_generation
        if error.status == 429 and generation is not None:
            with self._identity_condition:
                if self._identity_generation != generation:
                    return self._account_changed()
        return error

    def _identity_cooldown_error_locked(self) -> GatewayError:
        remaining = max(0.0, self._identity_cooldown_deadline - self._monotonic())
        return GatewayError(
            429,
            "exchange_rate_limited",
            "The exchange is rate limited. Try again later.",
            headers=[("Retry-After", str(ceil(remaining)))],
            rate_limit_generation=self._identity_generation,
        )

    def _retry_after_seconds(self, value: str | None) -> float:
        if isinstance(value, str):
            token = value.strip()
            if re.fullmatch(r"[0-9]+", token):
                try:
                    duration = float(token)
                    if isfinite(duration):
                        return duration
                except (OverflowError, ValueError):
                    pass
            try:
                retry_at = parsedate_to_datetime(token)
                if retry_at.tzinfo is None:
                    retry_at = retry_at.replace(tzinfo=timezone.utc)
                remaining = (
                    retry_at - datetime.fromtimestamp(self._wall_clock(), tz=timezone.utc)
                ).total_seconds()
                if isfinite(remaining):
                    return max(0.0, remaining)
            except (TypeError, ValueError, OverflowError):
                pass
        return 1.0

    def _identity_snapshot(self, *, force: bool = False) -> GatewayIdentity:
        identity_generation: int | None = None
        if not force:
            with self._identity_condition:
                if self._identity_cooldown_deadline > self._monotonic():
                    raise self._identity_cooldown_error_locked()
                if self._identity is not None and self._identity_deadline > self._monotonic():
                    return self._copy_identity(self._identity)
                flight = self._identity_flight
                if flight is None:
                    flight = _Flight()
                    self._identity_flight = flight
                    leader = True
                else:
                    leader = False
                if leader:
                    identity_generation = self._identity_generation
        else:
            with self._identity_condition:
                if self._identity_cooldown_deadline > self._monotonic():
                    raise self._identity_cooldown_error_locked()
                while self._identity_flight is not None:
                    flight = self._identity_flight
                    self._identity_condition.wait(self.FLIGHT_WAIT_TIMEOUT_SECONDS)
                    if self._identity_flight is flight and not flight.event.is_set():
                        raise self._busy()
                    if self._identity_cooldown_deadline > self._monotonic():
                        raise self._identity_cooldown_error_locked()
                flight = _Flight()
                self._identity_flight = flight
                leader = True
                identity_generation = self._identity_generation

        if not leader:
            assert flight is not None
            if not flight.event.wait(self.FLIGHT_WAIT_TIMEOUT_SECONDS):
                raise self._busy()
            if flight.error is not None:
                raise self._effective_flight_error(flight)
            if flight.value is None:
                raise self._account_unavailable()
            return self._published_identity(flight.value)

        try:
            account = self._upstream_read(self._okx.account_config)
            fingerprint = self._account_fingerprint(account.get("uid")) if isinstance(account, dict) else None
            if not fingerprint:
                raise self._account_unavailable()
            changed = False
            with self._identity_condition:
                if (
                    identity_generation != self._identity_generation
                    or self._identity_flight is not flight
                ):
                    raise self._account_changed()
                if self._identity_cooldown_deadline > self._monotonic():
                    cooldown_error = self._identity_cooldown_error_locked()
                    flight.error = cooldown_error
                    flight.rate_limit_generation = cooldown_error.rate_limit_generation
                else:
                    prior = self._identity
                    if prior is not None and prior.fingerprint != fingerprint:
                        self._identity_generation += 1
                        changed = True
                    self._identity_cooldown_deadline = 0.0
                    identity = GatewayIdentity(
                        account=deepcopy(account),
                        fingerprint=fingerprint,
                        generation=self._identity_generation,
                    )
                    self._identity = identity
                    self._identity_deadline = self._monotonic() + self.IDENTITY_TTL_SECONDS
                    flight.value = identity
            if changed:
                self._clear_private_cache()
        except GatewayError as error:
            if flight.error is None:
                flight.error = error
            self._invalidate_identity(identity_generation)
        except OKXError as error:
            mapped = self._map_okx_error(error)
            if mapped.status == 429:
                cooldown_error = self._invalidate_identity(
                    identity_generation,
                    rate_limited=True,
                    retry_after=error.retry_after,
                )
                if flight.error is None:
                    flight.error = cooldown_error or self._account_changed()
                    flight.rate_limit_generation = flight.error.rate_limit_generation
            else:
                if flight.error is None:
                    flight.error = mapped
                self._invalidate_identity(identity_generation)
        except Exception:
            if flight.error is None:
                flight.error = self._account_unavailable()
            self._invalidate_identity(identity_generation)
        finally:
            with self._identity_condition:
                if self._identity_flight is flight:
                    self._identity_flight = None
                flight.event.set()
                self._identity_condition.notify_all()
        if flight.error is not None:
            raise self._effective_flight_error(flight)
        if flight.value is None:
            raise self._account_unavailable()
        return self._published_identity(flight.value)

    def _published_identity(self, value: Any) -> GatewayIdentity:
        if not isinstance(value, GatewayIdentity):
            raise self._account_unavailable()
        with self._identity_condition:
            current = self._identity
            if (
                current is None
                or self._identity_deadline <= self._monotonic()
                or current.fingerprint != value.fingerprint
                or current.generation != value.generation
            ):
                raise self._account_changed()
            return self._copy_identity(current)

    def _invalidate_identity(
        self,
        expected_generation: int | None = None,
        *,
        rate_limited: bool = False,
        retry_after: str | None = None,
    ) -> GatewayError | None:
        with self._identity_condition:
            if rate_limited:
                now = self._monotonic()
                delay = self._retry_after_seconds(retry_after)
                new_deadline = now + delay
                if not isfinite(new_deadline):
                    new_deadline = now + 1.0
                self._identity_cooldown_deadline = max(
                    self._identity_cooldown_deadline,
                    new_deadline,
                )
            if expected_generation is not None and self._identity_generation != expected_generation:
                return None
            rate_error: GatewayError | None = None
            self._identity_generation += 1
            self._identity = None
            self._identity_deadline = 0.0
            if rate_limited:
                rate_error = self._identity_cooldown_error_locked()
            with self._cache_lock:
                for key, entry in list(self._cache.items()):
                    if entry.private:
                        self._cache.pop(key, None)
                for key, flight in list(self._inflight.items()):
                    if key and key[0] == "private":
                        if rate_limited:
                            flight.error = self._identity_cooldown_error_locked()
                            flight.rate_limit_generation = self._identity_generation
                        else:
                            flight.error = self._account_changed()
                            flight.rate_limit_generation = None
                        flight.event.set()
                        if not rate_limited:
                            self._inflight.pop(key, None)
            return rate_error

    def _clear_private_cache(self) -> None:
        with self._cache_lock:
            for key, entry in list(self._cache.items()):
                if entry.private:
                    self._cache.pop(key, None)

    def _identity_current(self) -> GatewayIdentity | None:
        with self._identity_condition:
            if self._identity is None or self._identity_deadline <= self._monotonic():
                return None
            return self._copy_identity(self._identity)

    def _identity_is_current(self, identity: GatewayIdentity | None) -> bool:
        if identity is None:
            return False
        with self._identity_condition:
            current = self._identity
            return (
                current is not None
                and self._identity_deadline > self._monotonic()
                and current.fingerprint == identity.fingerprint
                and current.generation == identity.generation
            )

    def _current_identity_for(self, expected: GatewayIdentity) -> GatewayIdentity:
        current = self._identity_current()
        if current is None:
            current = self._identity_snapshot(force=True)
        self._ensure_identity_matches(expected, current)
        return current

    @staticmethod
    def _copy_identity(identity: GatewayIdentity) -> GatewayIdentity:
        return GatewayIdentity(
            account=deepcopy(identity.account),
            fingerprint=identity.fingerprint,
            generation=identity.generation,
        )

    def _ensure_identity_matches(
        self,
        expected: GatewayIdentity | None,
        actual: GatewayIdentity | None,
    ) -> None:
        if (
            expected is None
            or actual is None
            or expected.fingerprint != actual.fingerprint
            or expected.generation != actual.generation
        ):
            raise self._account_changed()

    def _store_entry(
        self,
        key: tuple[Any, ...],
        entry: _CacheEntry,
        identity: GatewayIdentity | None,
    ) -> None:
        if not self.is_deadline_fresh(entry.deadline):
            raise self._data_stale()
        if entry.private:
            with self._identity_condition:
                current = self._identity
                if (
                    identity is None
                    or current is None
                    or current.fingerprint != identity.fingerprint
                    or current.generation != identity.generation
                ):
                    raise self._account_changed()
                with self._cache_lock:
                    if not self.is_deadline_fresh(entry.deadline):
                        raise self._data_stale()
                    self._insert_cache_locked(key, entry)
            return
        with self._cache_lock:
            if not self.is_deadline_fresh(entry.deadline):
                raise self._data_stale()
            self._insert_cache_locked(key, entry)

    def _remove_entry_if_same(self, key: tuple[Any, ...], entry: _CacheEntry) -> None:
        with self._cache_lock:
            if self._cache.get(key) is entry:
                self._cache.pop(key, None)

    def _insert_cache_locked(self, key: tuple[Any, ...], entry: _CacheEntry) -> None:
        now = self._monotonic()
        for old_key, old_entry in list(self._cache.items()):
            if old_entry.deadline <= now:
                self._cache.pop(old_key, None)
        self._cache[key] = entry
        self._cache.move_to_end(key)
        while len(self._cache) > self.MAX_CACHE_ENTRIES:
            self._cache.popitem(last=False)

    def _cache_key(
        self,
        suffix: str,
        params: dict[str, str],
        identity: GatewayIdentity | None,
        private: bool,
    ) -> tuple[Any, ...]:
        normalized = tuple((key, params[key]) for key in sorted(params))
        if private:
            if identity is None:
                raise self._account_unavailable()
            return ("private", identity.fingerprint, identity.generation, suffix, normalized)
        return ("public", suffix, normalized)

    def _new_entry(self, data: list[Any], route: _Route) -> _CacheEntry:
        fetched = self._wall_clock()
        ttl = route.ttl_seconds
        return _CacheEntry(
            data=deepcopy(data),
            fetched_at=fetched,
            expires_at=fetched + ttl,
            deadline=self._monotonic() + ttl,
            private=route.private,
        )

    @staticmethod
    def _combine_entries(data: list[Any], entries: list[_CacheEntry], *, private: bool) -> _CacheEntry:
        if not entries:
            raise GatewayError(502, "exchange_unavailable", "The requested data is unavailable.")
        return _CacheEntry(
            data=deepcopy(data),
            fetched_at=min(entry.fetched_at for entry in entries),
            expires_at=min(entry.expires_at for entry in entries),
            deadline=min(entry.deadline for entry in entries),
            private=private,
        )

    def _envelope(self, entry: _CacheEntry, cache_hit: bool) -> dict[str, Any]:
        return {
            "code": "0",
            "msg": "",
            "data": deepcopy(entry.data),
            "dataMeta": {
                "fetchedAt": self._iso_time(entry.fetched_at),
                "expiresAt": self._iso_time(entry.expires_at),
                "source": "backend",
                "cacheHit": bool(cache_hit),
            },
        }

    @staticmethod
    def _iso_time(value: float) -> str:
        return datetime.fromtimestamp(value, tz=timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")

    @staticmethod
    def _invalid_query() -> GatewayError:
        return GatewayError(400, "invalid_request", "The data query is invalid.")

    @staticmethod
    def _busy() -> GatewayError:
        return GatewayError(503, "data_unavailable", "The requested data is temporarily unavailable.")

    @staticmethod
    def _unavailable() -> GatewayError:
        return GatewayError(502, "exchange_unavailable", "The requested data is unavailable.")

    @staticmethod
    def _account_unavailable() -> GatewayError:
        return GatewayError(502, "account_unavailable", "Current account data is unavailable.")

    @staticmethod
    def _account_changed() -> GatewayError:
        return GatewayError(409, "account_changed", "The active account changed during this request.")

    @staticmethod
    def _data_stale() -> GatewayError:
        return GatewayError(503, "data_stale", "The requested data became stale before it was ready.")

    @staticmethod
    def _map_okx_error(error: OKXError) -> GatewayError:
        if error.http_status == 429 or error.error_code in _RATE_LIMIT_CODES:
            return GatewayError(
                429,
                "exchange_rate_limited",
                "The exchange is rate limited. Try again later.",
                headers=[("Retry-After", error.retry_after or "1")],
            )
        return GatewayError(502, "exchange_unavailable", "The requested data is unavailable.")
