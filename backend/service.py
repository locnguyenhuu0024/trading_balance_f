"""WSGI API and fail-closed position-action service."""

from __future__ import annotations

import base64
import binascii
from concurrent.futures import ThreadPoolExecutor, TimeoutError as FutureTimeoutError
import hmac
from http.cookies import CookieError, SimpleCookie
import ipaddress
import json
import os
import re
import threading
import time
from dataclasses import dataclass
from decimal import Decimal, InvalidOperation, ROUND_DOWN
from typing import Any, Callable
from urllib.parse import urlsplit

from .currency import CurrencyTransport
from .data_gateway import DataGateway, GatewayError
from .okx import OKXClient, OKXError, OKXTransportError, Transport, bounded_error_code
from .security import (
    matching_totp_counter,
    new_bearer_token,
    new_confirmation_token,
    new_operation_id,
    token_digest,
    verify_password,
)
from .store import SQLiteStore, decode_json, encode_json


SUPPORTED_TYPES = ("MARGIN", "SWAP", "FUTURES")
ACTION_TTL_SECONDS = 120
SESSION_TTL_SECONDS = 28_800
SESSION_COOKIE_NAME = "__Host-trade_session"
LOGIN_WINDOW_SECONDS = 900
LOGIN_FAILURE_LIMIT = 5
BODY_LIMIT_BYTES = 64 * 1024
ACTION_LIMIT_PER_MINUTE = 30
TERMINAL_OPERATION_STATES = {"SUCCEEDED", "PARTIAL", "FAILED", "CONFLICT", "EXPIRED"}


class APIError(Exception):
    def __init__(
        self,
        status: int,
        code: str,
        message: str,
        *,
        details: dict[str, Any] | None = None,
        headers: list[tuple[str, str]] | None = None,
    ):
        super().__init__(message)
        self.status = status
        self.code = code
        self.message = message
        self.details = details or {}
        self.headers = headers or []

    def response(self) -> dict[str, Any]:
        return {"error": self.code, "message": self.message, **self.details}


@dataclass(frozen=True)
class RuntimeSettings:
    okx_api_key: str
    okx_api_secret: str
    okx_api_passphrase: str
    admin_password_hash: str
    totp_secret: str
    session_signing_key: bytes
    allowed_web_origin: str
    operation_db_path: str

    @classmethod
    def from_environ(cls, environ: dict[str, str] | None = None) -> "RuntimeSettings":
        source = os.environ if environ is None else environ
        names = (
            "OKX_API_KEY", "OKX_API_SECRET", "OKX_API_PASSPHRASE",
            "ADMIN_PASSWORD_HASH", "TOTP_SECRET", "SESSION_SIGNING_KEY",
            "ALLOWED_WEB_ORIGIN", "OPERATION_DB_PATH",
        )
        values = {name: source.get(name, "") for name in names}
        if any(not value for value in values.values()):
            raise ValueError("runtime is not configured")
        origin = values["ALLOWED_WEB_ORIGIN"]
        parsed = urlsplit(origin)
        if (parsed.scheme != "https" or not parsed.netloc or parsed.path or parsed.query
                or parsed.fragment or parsed.username or parsed.password):
            raise ValueError("runtime is not configured")
        if not os.path.isabs(values["OPERATION_DB_PATH"]):
            raise ValueError("runtime is not configured")
        if not re.fullmatch(r"[0-9a-fA-F]{64}", values["SESSION_SIGNING_KEY"]):
            raise ValueError("runtime is not configured")
        try:
            totp = values["TOTP_SECRET"].replace(" ", "").upper()
            base64.b32decode(totp + "=" * ((8 - len(totp) % 8) % 8), casefold=True)
            password_parts = values["ADMIN_PASSWORD_HASH"].split("$")
            if len(password_parts) != 6 or password_parts[0] != "scrypt":
                raise ValueError
            n, r, p = (int(password_parts[index]) for index in (1, 2, 3))
            if not (2**12 <= n <= 2**18 and n & (n - 1) == 0 and 1 <= r <= 16 and 1 <= p <= 4):
                raise ValueError
        except (ValueError, binascii.Error):
            raise ValueError("runtime is not configured") from None
        return cls(
            okx_api_key=values["OKX_API_KEY"],
            okx_api_secret=values["OKX_API_SECRET"],
            okx_api_passphrase=values["OKX_API_PASSPHRASE"],
            admin_password_hash=values["ADMIN_PASSWORD_HASH"],
            totp_secret=values["TOTP_SECRET"],
            session_signing_key=bytes.fromhex(values["SESSION_SIGNING_KEY"]),
            allowed_web_origin=origin,
            operation_db_path=values["OPERATION_DB_PATH"],
        )


def decimal_value(value: Any) -> Decimal | None:
    if value is None or isinstance(value, bool):
        return None
    try:
        parsed = Decimal(str(value))
        if not parsed.is_finite():
            return None
        return parsed
    except (InvalidOperation, ValueError, TypeError):
        return None


def decimal_text(value: Decimal | None) -> str | None:
    if value is None:
        return None
    if value == 0:
        return "0"
    return format(value.normalize(), "f")


def floor_to_increment(value: Decimal, increment: Decimal) -> Decimal:
    return (value / increment).to_integral_value(rounding=ROUND_DOWN) * increment


def mask_identifier(value: Any) -> str | None:
    if value is None:
        return None
    text = str(value)
    return "••••" + text[-4:] if len(text) > 4 else "••••"


def _identity_key(identity: dict[str, Any]) -> str:
    if identity.get("ordId") and identity.get("instId"):
        return encode_json({"instId": identity["instId"], "ordId": identity["ordId"]})
    return encode_json(identity)


def _public_position(position: dict[str, Any]) -> dict[str, Any]:
    return {
        key: value for key, value in position.items()
        if not key.startswith("_")
    }


class TradeService:
    def __init__(
        self,
        settings: RuntimeSettings,
        *,
        transport: Transport | None = None,
        currency_transport: CurrencyTransport | None = None,
        clock: Callable[[], float] = time.time,
    ):
        self.settings = settings
        self.clock = clock
        self.store = SQLiteStore(settings.operation_db_path)
        self.okx = OKXClient(
            settings.okx_api_key,
            settings.okx_api_secret,
            settings.okx_api_passphrase,
            transport=transport,
            clock=clock,
        )
        self.data_gateway = DataGateway(
            self.okx,
            account_fingerprint=self._account_fingerprint,
            currency_transport=currency_transport,
            wall_clock=clock,
        )
        self._display_executor = ThreadPoolExecutor(
            max_workers=len(SUPPORTED_TYPES),
            thread_name_prefix="position-display",
        )
        self._display_admission = threading.BoundedSemaphore(2 * len(SUPPORTED_TYPES))
        from .strategy import StrategyService

        self.strategy = StrategyService(self)
        self._mutation_lock = threading.RLock()

    def dispatch(
        self,
        method: str,
        path: str,
        body: dict[str, Any],
        environ: dict[str, Any],
    ) -> tuple[int, dict[str, Any], list[tuple[str, str]]]:
        source = self._source_key(self._source_address(environ))
        if method == "POST" and path == "/v1/login":
            payload = self._login(body, source)
            return 200, payload, [("Set-Cookie", self._session_cookie(payload["token"]))]
        if method == "GET" and path == "/v1/session":
            return 200, self._restore_session(environ), []
        if method == "POST" and path == "/v1/logout":
            self._require_session(environ)
            self._logout(environ)
            return 200, {"status": "logged_out"}, [("Set-Cookie", self._cleared_session_cookie())]
        if method == "GET" and path == "/v1/positions":
            self._require_session(environ)
            snapshot = self._fetch_display_snapshot(environ)
            return 200, self._positions_response(snapshot), []
        if path.startswith("/v1/data/"):
            try:
                payload = self.data_gateway.handle(
                    method,
                    path[len("/v1/data/"):],
                    str(environ.get("QUERY_STRING", "")),
                    session_guard=lambda: self._require_session(environ),
                )
            except GatewayError as error:
                raise APIError(error.status, error.code, error.message, headers=error.headers) from None
            return 200, payload, []
        if path == "/v1/strategies" or path.startswith("/v1/strategies/"):
            self._require_session(environ)
            if method == "POST":
                self._check_action_rate("strategies", source)
            request_guard = lambda: self._require_session(environ)
            if method == "POST":
                try:
                    return 200, self.strategy.dispatch(method, path, body, request_guard=request_guard), []
                finally:
                    self.data_gateway.invalidate_private()
            return 200, self.strategy.dispatch(method, path, body, request_guard=request_guard), []
        if method == "POST" and path == "/v1/actions/prepare":
            self._require_session(environ)
            self._check_action_rate("prepare", source)
            return 200, self._prepare(body, source), []
        if method == "POST" and path == "/v1/actions/execute":
            self._require_session(environ)
            self._check_action_rate("execute", source)
            try:
                return 200, self._execute(body), []
            finally:
                self.data_gateway.invalidate_private()
        match = re.fullmatch(r"/v1/actions/result/([A-Za-z0-9_-]{8,64})", path)
        if method == "GET" and match:
            self._require_session(environ)
            return 200, self._get_result(match.group(1)), []
        raise APIError(404, "not_found", "The requested endpoint was not found.")

    def _source_key(self, source: str) -> str:
        return token_digest("source:" + source, self.settings.session_signing_key)

    def _account_fingerprint(self, uid: Any) -> str | None:
        if isinstance(uid, bool) or not isinstance(uid, (str, int)):
            return None
        normalized_uid = str(uid).strip()
        if not normalized_uid:
            return None
        return token_digest(
            "okx-account-uid:v1:" + normalized_uid,
            self.settings.session_signing_key,
        )

    @staticmethod
    def _valid_account_fingerprint(value: Any) -> bool:
        return isinstance(value, str) and re.fullmatch(r"[0-9a-f]{64}", value) is not None

    def _account_fingerprints_match(self, expected: Any, actual: Any) -> bool:
        return (
            self._valid_account_fingerprint(expected)
            and self._valid_account_fingerprint(actual)
            and hmac.compare_digest(expected, actual)
        )

    def _operation_account_matches(self, operation: dict[str, Any], snapshot: dict[str, Any]) -> bool:
        return self._account_fingerprints_match(
            operation.get("payload", {}).get("accountFingerprint"),
            snapshot.get("accountFingerprint"),
        )

    def _read_account_fingerprint(self) -> str | None:
        try:
            account = self.okx.account_config()
        except OKXError:
            return None
        return self._account_fingerprint(account.get("uid"))

    def _source_address(self, environ: dict[str, Any]) -> str:
        remote = str(environ.get("REMOTE_ADDR", "unknown"))
        forwarded = str(environ.get("HTTP_X_FORWARDED_FOR", ""))
        try:
            proxy_address = ipaddress.ip_address(remote)
            if proxy_address.is_loopback and forwarded and "," not in forwarded:
                candidate = ipaddress.ip_address(forwarded.strip())
                return candidate.compressed
        except ValueError:
            pass
        return remote

    def _login(self, body: dict[str, Any], source: str) -> dict[str, Any]:
        now = self.clock()
        with self.store.connection() as connection:
            row = connection.execute(
                "SELECT window_started, failures FROM login_attempts WHERE source_key=?", (source,)
            ).fetchone()
        if row and now - row["window_started"] < LOGIN_WINDOW_SECONDS and row["failures"] >= LOGIN_FAILURE_LIMIT:
            raise APIError(429, "rate_limited", "Too many login attempts. Try again later.")

        password = body.get("password")
        code = body.get("totp")
        password_ok = (
            isinstance(password, str)
            and len(password) <= 1024
            and verify_password(password, self.settings.admin_password_hash)
        )
        counter: int | None = None
        if password_ok and isinstance(code, str):
            with self.store.connection() as connection:
                auth_state = connection.execute(
                    "SELECT last_totp_counter FROM auth_state WHERE singleton=1"
                ).fetchone()
            last_counter = -1 if auth_state is None else int(auth_state["last_totp_counter"])
            counter = matching_totp_counter(self.settings.totp_secret, code, now, last_counter)

        denied = False
        bearer = ""
        expires_at = 0.0
        with self.store.transaction() as connection:
            row = connection.execute(
                "SELECT window_started, failures FROM login_attempts WHERE source_key=?", (source,)
            ).fetchone()
            if row and now - row["window_started"] < LOGIN_WINDOW_SECONDS and row["failures"] >= LOGIN_FAILURE_LIMIT:
                raise APIError(429, "rate_limited", "Too many login attempts. Try again later.")
            latest_state = connection.execute(
                "SELECT last_totp_counter FROM auth_state WHERE singleton=1"
            ).fetchone()
            latest_counter = -1 if latest_state is None else int(latest_state["last_totp_counter"])
            if not password_ok or counter is None or counter <= latest_counter:
                if row is None or now - row["window_started"] >= LOGIN_WINDOW_SECONDS:
                    connection.execute(
                        "INSERT INTO login_attempts(source_key, window_started, failures) VALUES (?, ?, 1) "
                        "ON CONFLICT(source_key) DO UPDATE SET window_started=excluded.window_started, failures=1",
                        (source, now),
                    )
                else:
                    connection.execute(
                        "UPDATE login_attempts SET failures=failures+1 WHERE source_key=?", (source,)
                    )
                denied = True
            else:
                bearer = new_bearer_token()
                expires_at = now + SESSION_TTL_SECONDS
                connection.execute(
                    "UPDATE auth_state SET last_totp_counter=? WHERE singleton=1", (counter,)
                )
                connection.execute("DELETE FROM login_attempts WHERE source_key=?", (source,))
                connection.execute(
                    "INSERT INTO sessions(token_hash, expires_at, created_at) VALUES (?, ?, ?)",
                    (token_digest(bearer, self.settings.session_signing_key), expires_at, now),
                )

        if denied:
            raise APIError(401, "invalid_credentials", "The password or verification code is invalid.")

        try:
            account = self.okx.account_config()
            account_identifier = mask_identifier(account.get("uid"))
        except OKXError:
            # Authentication does not depend on a read-only display label.
            account_identifier = "••••"
        return {
            "token": bearer,
            "expiresAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(expires_at)),
            "accountIdentifier": account_identifier,
        }

    def _require_session(self, environ: dict[str, Any]) -> str:
        authorization = str(environ.get("HTTP_AUTHORIZATION", ""))
        scheme, separator, bearer = authorization.partition(" ")
        if not separator or scheme.lower() != "bearer" or not bearer or len(bearer) > 256:
            raise APIError(401, "authentication_required", "A valid session is required.")
        return self._validate_session_token(bearer)

    def _validate_session_token(self, token: str) -> str:
        if not token or len(token) > 256:
            raise APIError(401, "authentication_required", "A valid session is required.")
        digest = token_digest(token, self.settings.session_signing_key)
        now = self.clock()
        with self.store.transaction() as connection:
            row = connection.execute(
                "SELECT token_hash, expires_at FROM sessions WHERE token_hash=?", (digest,)
            ).fetchone()
            if row is None or not hmac.compare_digest(row["token_hash"], digest) or row["expires_at"] <= now:
                if row is not None:
                    connection.execute("DELETE FROM sessions WHERE token_hash=?", (digest,))
                raise APIError(401, "authentication_required", "A valid session is required.")
        return digest

    def _restore_session(self, environ: dict[str, Any]) -> dict[str, Any]:
        raw_cookie = environ.get("HTTP_COOKIE", "")
        if not isinstance(raw_cookie, str) or len(raw_cookie) > 4096:
            raise APIError(401, "authentication_required", "A valid session is required.")
        cookies = SimpleCookie()
        try:
            cookies.load(raw_cookie)
        except CookieError:
            raise APIError(401, "authentication_required", "A valid session is required.") from None
        morsel = cookies.get(SESSION_COOKIE_NAME)
        token = "" if morsel is None else morsel.value
        if not token or len(token) > 256:
            raise APIError(401, "authentication_required", "A valid session is required.")
        digest = token_digest(token, self.settings.session_signing_key)
        now = self.clock()
        with self.store.connection() as connection:
            row = connection.execute(
                "SELECT expires_at FROM sessions WHERE token_hash=?", (digest,)
            ).fetchone()
        if row is None or row["expires_at"] <= now:
            raise APIError(401, "authentication_required", "A valid session is required.")
        try:
            account = self.okx.account_config()
            account_identifier = mask_identifier(account.get("uid"))
        except OKXError:
            account_identifier = "••••"
        return {
            "token": token,
            "expiresAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(row["expires_at"])),
            "accountIdentifier": account_identifier or "••••",
        }

    @staticmethod
    def _session_cookie(token: str) -> str:
        return (
            f"{SESSION_COOKIE_NAME}={token}; Path=/; Max-Age={SESSION_TTL_SECONDS}; "
            "Secure; HttpOnly; SameSite=Strict"
        )

    @staticmethod
    def _cleared_session_cookie() -> str:
        return f"{SESSION_COOKIE_NAME}=; Path=/; Max-Age=0; Secure; HttpOnly; SameSite=Strict"

    def _logout(self, environ: dict[str, Any]) -> None:
        authorization = str(environ.get("HTTP_AUTHORIZATION", ""))
        _, _, bearer = authorization.partition(" ")
        digest = token_digest(bearer, self.settings.session_signing_key)
        with self.store.transaction() as connection:
            connection.execute("DELETE FROM sessions WHERE token_hash=?", (digest,))

    def _check_action_rate(self, action: str, source: str) -> None:
        now = int(self.clock())
        window = now // 60
        key = f"{action}:{source}"
        with self.store.transaction() as connection:
            row = connection.execute(
                "SELECT window_started, count FROM rate_limits WHERE bucket_key=?", (key,)
            ).fetchone()
            if row is None or row["window_started"] != window:
                connection.execute(
                    "INSERT INTO rate_limits(bucket_key, window_started, count) VALUES (?, ?, 1) "
                    "ON CONFLICT(bucket_key) DO UPDATE SET window_started=excluded.window_started, count=1",
                    (key, window),
                )
                return
            if row["count"] >= ACTION_LIMIT_PER_MINUTE:
                raise APIError(429, "rate_limited", "Too many action requests. Try again later.")
            connection.execute("UPDATE rate_limits SET count=count+1 WHERE bucket_key=?", (key,))

    def _fetch_snapshot(self) -> dict[str, Any]:
        try:
            account = self.okx.account_config()
            pos_mode = account.get("posMode")
            positions_by_type = {instrument_type: self.okx.positions(instrument_type) for instrument_type in SUPPORTED_TYPES}
        except OKXError:
            raise APIError(502, "exchange_unavailable", "Current account data is unavailable.") from None

        instruments_by_type: dict[str, dict[str, dict[str, Any]]] = {}
        for instrument_type in SUPPORTED_TYPES:
            try:
                instruments = self.okx.instruments(instrument_type)
            except OKXError:
                instruments = []
            instruments_by_type[instrument_type] = {
                str(item.get("instId")): item for item in instruments if item.get("instId")
            }

        normalized: list[dict[str, Any]] = []
        for instrument_type in SUPPORTED_TYPES:
            instrument_map = instruments_by_type[instrument_type]
            for raw in positions_by_type[instrument_type]:
                position = self._normalize_position(raw, instrument_type, pos_mode, instrument_map)
                if position.get("size") == "0":
                    continue
                normalized.append(position)

        seen: set[str] = set()
        for position in normalized:
            identity = position["identity"]
            key = _identity_key(identity)
            if key in seen:
                position["identityAmbiguous"] = True
            else:
                position["identityAmbiguous"] = False
                seen.add(key)
        normalized.sort(key=lambda item: _identity_key(item["identity"]))
        return {
            "accountIdentifier": mask_identifier(account.get("uid")) or "••••",
            "accountFingerprint": self._account_fingerprint(account.get("uid")),
            "positionMode": pos_mode,
            "positions": normalized,
            "instruments": instruments_by_type,
        }

    def _fetch_display_snapshot(self, environ: dict[str, Any]) -> dict[str, Any]:
        request_guard = lambda: self._require_session(environ)

        def read_group(
            instrument_type: str,
        ) -> tuple[list[dict[str, Any]], dict[str, dict[str, Any]], float]:
            positions, positions_deadline = self.data_gateway.read_internal_with_deadline(
                "account/positions",
                {"instType": instrument_type},
                session_guard=request_guard,
            )
            instruments, instruments_deadline = self.data_gateway.read_internal_with_deadline(
                "public/instruments",
                {"instType": instrument_type},
            )
            instrument_map = {
                str(item.get("instId")): item for item in instruments if item.get("instId")
            }
            return positions, instrument_map, min(positions_deadline, instruments_deadline)

        admission_reserved = 0
        submitted_futures: dict[str, Future[Any]] = {}
        try:
            for attempt in range(2):
                before = self.data_gateway.identity_for_display(session_guard=request_guard)
                for _ in SUPPORTED_TYPES:
                    if not self._display_admission.acquire(blocking=False):
                        raise GatewayError(
                            503,
                            "data_unavailable",
                            "The requested data is temporarily unavailable.",
                        )
                    admission_reserved += 1
                submitted_futures = {}
                for instrument_type in SUPPORTED_TYPES:
                    future = self._display_executor.submit(read_group, instrument_type)
                    admission_reserved -= 1
                    future.add_done_callback(lambda _future: self._display_admission.release())
                    submitted_futures[instrument_type] = future

                positions_by_type: dict[str, list[dict[str, Any]]] = {}
                instruments_by_type: dict[str, dict[str, dict[str, Any]]] = {}
                deadlines: list[float] = []
                for instrument_type in SUPPORTED_TYPES:
                    positions, instruments, deadline = submitted_futures[instrument_type].result(timeout=45)
                    positions_by_type[instrument_type] = positions
                    instruments_by_type[instrument_type] = instruments
                    deadlines.append(deadline)
                after = self.data_gateway.identity_for_display(session_guard=request_guard, force=True)
                if before.fingerprint != after.fingerprint or before.generation != after.generation:
                    raise GatewayError(
                        409, "account_changed", "The active account changed during this request."
                    )
                if all(self.data_gateway.is_deadline_fresh(deadline) for deadline in deadlines):
                    break
                if attempt == 1:
                    raise GatewayError(
                        503,
                        "data_stale",
                        "The requested data became stale before it was ready.",
                    )
        except GatewayError as error:
            for future in submitted_futures.values():
                future.cancel()
            raise APIError(error.status, error.code, error.message, headers=error.headers) from None
        except FutureTimeoutError:
            for future in submitted_futures.values():
                future.cancel()
            raise APIError(503, "data_unavailable", "The requested data is temporarily unavailable.") from None
        except APIError:
            for future in submitted_futures.values():
                future.cancel()
            raise
        except Exception:
            for future in submitted_futures.values():
                future.cancel()
            raise APIError(502, "exchange_unavailable", "Current account data is unavailable.") from None
        finally:
            for _ in range(admission_reserved):
                self._display_admission.release()

        pos_mode = before.account.get("posMode")
        if not isinstance(pos_mode, str) or not pos_mode:
            raise APIError(502, "account_unavailable", "Current account data is unavailable.")
        normalized: list[dict[str, Any]] = []
        for instrument_type in SUPPORTED_TYPES:
            instrument_map = instruments_by_type[instrument_type]
            for raw in positions_by_type[instrument_type]:
                position = self._normalize_position(raw, instrument_type, pos_mode, instrument_map)
                if position.get("size") == "0":
                    continue
                normalized.append(position)

        seen: set[str] = set()
        for position in normalized:
            identity = position["identity"]
            key = _identity_key(identity)
            if key in seen:
                position["identityAmbiguous"] = True
            else:
                position["identityAmbiguous"] = False
                seen.add(key)
        normalized.sort(key=lambda item: _identity_key(item["identity"]))
        try:
            request_guard()
            published_identity = self.data_gateway.identity_for_display(
                session_guard=request_guard
            )
            if (
                before.fingerprint != published_identity.fingerprint
                or before.generation != published_identity.generation
            ):
                raise GatewayError(
                    409, "account_changed", "The active account changed during this request."
                )
            request_guard()
            if not all(self.data_gateway.is_deadline_fresh(deadline) for deadline in deadlines):
                raise GatewayError(
                    503,
                    "data_stale",
                    "The requested data became stale before it was ready.",
                )
        except GatewayError as error:
            raise APIError(error.status, error.code, error.message, headers=error.headers) from None
        return {
            "accountIdentifier": mask_identifier(before.account.get("uid")) or "••••",
            "accountFingerprint": before.fingerprint,
            "positionMode": pos_mode,
            "positions": normalized,
            "instruments": instruments_by_type,
        }

    def _normalize_position(
        self,
        raw: dict[str, Any],
        instrument_type: str,
        position_mode: Any,
        instrument_map: dict[str, dict[str, Any]],
    ) -> dict[str, Any]:
        inst_id = str(raw.get("instId", "")) or None
        pos_text = raw.get("pos")
        signed_size = decimal_value(pos_text)
        if signed_size is None:
            signed_text = None if pos_text is None else str(pos_text)
            size = None
        else:
            signed_text = decimal_text(signed_size)
            size = abs(signed_size)

        metadata = instrument_map.get(inst_id or "", {})
        margin_currency = str(raw.get("ccy") or raw.get("marginCcy") or "") or None
        raw_position_currency = str(raw.get("posCcy") or "") or None
        raw_pos_side = str(raw.get("posSide", "")).lower()
        if instrument_type == "MARGIN":
            base_currency = str(metadata.get("baseCcy") or "").upper()
            quote_currency = str(metadata.get("quoteCcy") or "").upper()
            position_currency = raw_position_currency
            direction = None
            if (
                signed_size is not None
                and signed_size > 0
                and base_currency
                and quote_currency
                and base_currency != quote_currency
                and raw_position_currency
            ):
                if raw_position_currency.upper() == base_currency:
                    direction = "long"
                elif raw_position_currency.upper() == quote_currency:
                    direction = "short"
            pos_side = "net" if raw_pos_side in ("", "net") else raw_pos_side
        elif position_mode == "net_mode":
            direction = None if signed_size in (None, Decimal(0)) else ("short" if signed_size < 0 else "long")
            pos_side = "net" if raw_pos_side in ("", "net") else raw_pos_side
        elif position_mode == "long_short_mode":
            pos_side = raw_pos_side or None
            direction = pos_side if pos_side in ("long", "short") else None
        else:
            pos_side = raw_pos_side or None
            direction = None

        if instrument_type != "MARGIN":
            position_currency = raw_position_currency or str(metadata.get("baseCcy") or "") or None
        margin_mode = str(raw.get("mgnMode", "")).lower() or None
        pos_id = str(raw.get("posId", "")) or None
        identity: dict[str, Any] = {"instrumentType": instrument_type, "instrumentId": inst_id}
        if pos_id is not None:
            identity["positionId"] = pos_id
        identity["positionSide"] = pos_side
        identity["marginMode"] = margin_mode
        if instrument_type == "MARGIN":
            identity["marginCurrency"] = margin_currency

        available = decimal_value(raw.get("availPos"))
        liability = decimal_value(raw.get("liab"))
        margin_value = decimal_value(raw.get("margin"))
        if margin_value is None:
            margin_value = decimal_value(raw.get("mgn"))
        return {
            "identity": identity,
            "instrumentType": instrument_type,
            "instrumentId": inst_id,
            "positionId": pos_id,
            "positionSide": pos_side,
            "positionMode": position_mode,
            "marginMode": margin_mode,
            "direction": direction,
            "signedSize": signed_text,
            "size": decimal_text(size),
            "avgPx": decimal_text(decimal_value(raw.get("avgPx"))),
            "markPx": decimal_text(decimal_value(raw.get("markPx"))),
            "liqPx": decimal_text(decimal_value(raw.get("liqPx"))),
            "upl": decimal_text(decimal_value(raw.get("upl"))),
            "uplRatio": decimal_text(decimal_value(raw.get("uplRatio"))),
            "notionalUsd": decimal_text(decimal_value(raw.get("notionalUsd"))),
            "lever": decimal_text(decimal_value(raw.get("lever"))),
            "marginCurrency": margin_currency,
            "positionCurrency": position_currency,
            "availableSize": decimal_text(abs(available)) if available is not None else None,
            "liability": decimal_text(abs(liability)) if liability is not None else None,
            "liabilityCurrency": str(raw.get("liabCcy") or "") or None,
            "margin": decimal_text(margin_value) if margin_value is not None else None,
            "_instrument": metadata,
            "_rawPositionSide": raw_pos_side,
        }

    def _eligibility(self, position: dict[str, Any], action: str) -> tuple[bool, str | None]:
        instrument_type = position.get("instrumentType")
        if position.get("identityAmbiguous"):
            return False, "ambiguous_position_identity"
        if not position.get("instrumentId") or decimal_value(position.get("size")) is None:
            return False, "incomplete_position_identity_or_size"
        if decimal_value(position.get("size")) <= 0:
            return False, "zero_size_position"
        if position.get("positionMode") not in ("net_mode", "long_short_mode"):
            return False, "unknown_position_mode"
        if position.get("marginMode") not in ("cross", "isolated"):
            return False, "unknown_margin_mode"
        side = position.get("positionSide")
        if position.get("positionMode") == "net_mode" and side != "net":
            return False, "ambiguous_net_side"
        if position.get("positionMode") == "long_short_mode" and side not in ("long", "short"):
            return False, "ambiguous_hedge_side"
        if position.get("direction") not in ("long", "short"):
            return False, "ambiguous_position_direction"

        if instrument_type == "MARGIN":
            if not position.get("marginCurrency"):
                return False, "margin_currency_metadata_missing"
            if position.get("positionMode") != "net_mode":
                return False, "unsupported_margin_position_mode"
        elif instrument_type not in ("SWAP", "FUTURES"):
            return False, "unsupported_instrument_type"

        if action in ("close_position", "close_all"):
            return True, None
        if action == "add_margin":
            if position.get("marginMode") != "isolated":
                return False, "isolated_margin_required"
            if not position.get("marginCurrency"):
                return False, "margin_currency_metadata_missing"
            return True, None
        if action in ("dca", "partial_close"):
            if instrument_type == "MARGIN":
                if action == "dca":
                    return False, "margin_dca_capacity_unverified"
                return False, "margin_partial_close_capacity_unverified"
            instrument = position.get("_instrument") or {}
            lot = decimal_value(instrument.get("lotSz"))
            minimum = decimal_value(instrument.get("minSz"))
            if lot is None or minimum is None or lot <= 0 or minimum <= 0:
                return False, "instrument_size_rules_missing"
            if instrument_type in ("SWAP", "FUTURES"):
                return True, None
        return False, "unsupported_action"

    def _positions_response(self, snapshot: dict[str, Any] | None = None) -> dict[str, Any]:
        if snapshot is None:
            snapshot = self._fetch_snapshot()
        positions: list[dict[str, Any]] = []
        for position in snapshot["positions"]:
            public = _public_position(position)
            action_names = {
                "addMargin": "add_margin",
                "dca": "dca",
                "partialClose": "partial_close",
                "closePosition": "close_position",
            }
            eligibility = {}
            for public_name, action_name in action_names.items():
                allowed, reason = self._eligibility(position, action_name)
                eligibility[public_name] = {"eligible": allowed, "reason": reason}
            public["eligibleActions"] = eligibility
            positions.append(public)
        return {"accountIdentifier": snapshot["accountIdentifier"], "positions": positions}

    def _position_by_identity(
        self, positions: list[dict[str, Any]], identity: dict[str, Any]
    ) -> dict[str, Any] | None:
        wanted = _identity_key(identity)
        matches = [position for position in positions if _identity_key(position["identity"]) == wanted]
        return matches[0] if len(matches) == 1 else None

    def _identity_from_request(self, value: Any) -> dict[str, Any]:
        if not isinstance(value, dict):
            raise APIError(400, "invalid_request", "A complete target identity is required.")
        mapping = {
            "instrumentType": "instrumentType",
            "instrumentId": "instrumentId",
            "positionId": "positionId",
            "positionSide": "positionSide",
            "marginMode": "marginMode",
            "marginCurrency": "marginCurrency",
        }
        identity = {key: value[key] for key in mapping if key in value}
        for required in ("instrumentType", "instrumentId", "positionSide", "marginMode"):
            if not identity.get(required):
                raise APIError(400, "invalid_request", "A complete target identity is required.")
        if identity["instrumentType"] == "MARGIN" and not identity.get("marginCurrency"):
            raise APIError(400, "invalid_request", "A complete target identity is required.")
        return identity

    def _material_signature(self, position: dict[str, Any]) -> dict[str, Any]:
        instrument = position.get("_instrument") or {}
        return {
            "identity": position["identity"],
            "signedSize": position.get("signedSize"),
            "positionMode": position.get("positionMode"),
            "marginMode": position.get("marginMode"),
            "marginCurrency": position.get("marginCurrency"),
            "positionCurrency": position.get("positionCurrency"),
            "availableSize": position.get("availableSize"),
            "liability": position.get("liability"),
            "liabilityCurrency": position.get("liabilityCurrency"),
            "margin": position.get("margin"),
            "lotSize": str(instrument.get("lotSz", "")) or None,
            "minimumSize": str(instrument.get("minSz", "")) or None,
        }

    def _build_target(
        self,
        action: str,
        position: dict[str, Any],
        body: dict[str, Any],
    ) -> tuple[dict[str, Any], dict[str, Any]]:
        allowed, reason = self._eligibility(position, action)
        if not allowed:
            raise APIError(
                422,
                "ineligible_target",
                "The selected position cannot use this action.",
                details={"target": _public_position(position), "reason": reason},
            )

        identity = position["identity"]
        request: dict[str, Any]
        summary: dict[str, Any] = {
            "identity": identity,
            "direction": position.get("direction"),
            "currentSize": position.get("size"),
        }
        if action == "close_position":
            request = self._close_request(position)
            summary["action"] = "close_position"
        elif action == "add_margin":
            amount = decimal_value(body.get("amount"))
            if amount is None or amount <= 0:
                raise APIError(400, "invalid_amount", "Enter a positive amount.")
            request = {
                "instId": position["instrumentId"],
                "type": "add",
                "amt": decimal_text(amount),
                "ccy": position["marginCurrency"],
            }
            if position.get("positionMode") == "long_short_mode":
                request["posSide"] = position["positionSide"]
            summary.update({"action": action, "amount": decimal_text(amount), "currency": position["marginCurrency"]})
        elif action in ("dca", "partial_close"):
            instrument = position.get("_instrument") or {}
            lot = decimal_value(instrument.get("lotSz"))
            minimum = decimal_value(instrument.get("minSz"))
            requested: Decimal
            if action == "dca":
                requested = decimal_value(body.get("size"))  # type: ignore[assignment]
                if requested is None or requested <= 0:
                    raise APIError(400, "invalid_size", "Enter a positive order size.")
                raw_requested = requested
            else:
                percentage = decimal_value(body.get("percentage"))
                if percentage is None or percentage <= 0 or percentage >= 100:
                    raise APIError(400, "invalid_percentage", "Percentage must be greater than zero and less than 100.")
                current = decimal_value(position.get("size"))
                if current is None:
                    raise APIError(422, "unknown_position_size", "The current position size is unavailable.")
                requested = current * percentage / Decimal(100)
                raw_requested = requested
            if lot is None or minimum is None or lot <= 0 or minimum <= 0:
                raise APIError(422, "instrument_size_rules_missing", "Instrument size rules are unavailable.")
            normalized = floor_to_increment(requested, lot)
            current_size = decimal_value(position.get("size"))
            if normalized <= 0 or normalized < minimum:
                raise APIError(422, "size_below_minimum", "The order size is below the instrument minimum.")
            if action == "partial_close":
                if current_size is None or normalized >= current_size:
                    raise APIError(422, "size_would_fully_close", "The rounded amount is not a valid partial close.")
                if position.get("instrumentType") == "MARGIN":
                    available = decimal_value(position.get("availableSize"))
                    if available is None or normalized > available:
                        raise APIError(422, "insufficient_available_size", "Available position size is insufficient.")
                    liability = decimal_value(position.get("liability"))
                    if liability is None or normalized > liability:
                        raise APIError(422, "size_exceeds_margin_debt", "The amount exceeds the verified margin debt.")
            if action == "dca" and position.get("instrumentType") == "MARGIN":
                available = decimal_value(position.get("availableSize"))
                if available is None or normalized > available:
                    raise APIError(422, "insufficient_available_size", "Available trade size is insufficient.")

            is_margin = position.get("instrumentType") == "MARGIN"
            if action == "dca":
                side = "buy" if position.get("direction") == "long" else "sell"
            else:
                side = "sell" if position.get("direction") == "long" else "buy"
            request = {
                "instId": position["instrumentId"],
                "tdMode": position["marginMode"],
                "side": side,
                "ordType": "market",
                "sz": decimal_text(normalized),
                "clOrdId": new_operation_id(),
            }
            if position.get("positionMode") == "long_short_mode":
                request["posSide"] = position["positionSide"]
            elif action == "partial_close":
                request["reduceOnly"] = True
            if is_margin:
                request["ccy"] = position["marginCurrency"]
            summary.update({
                "action": action,
                "requestedSize": decimal_text(raw_requested),
                "normalizedSize": decimal_text(normalized),
                "sizeUnit": "base" if is_margin else "contracts",
                "lotSize": decimal_text(lot),
                "minimumSize": decimal_text(minimum),
            })
            if action == "partial_close":
                summary["percentage"] = decimal_text(decimal_value(body.get("percentage")))
        else:
            raise APIError(400, "invalid_action", "The requested action is not supported.")

        journal_target = {
            "identity": identity,
            "snapshot": self._material_signature(position),
            "request": request,
            "summary": summary,
            "status": "PENDING",
            "outcome": None,
        }
        return journal_target, summary

    def _close_request(self, position: dict[str, Any]) -> dict[str, Any]:
        request: dict[str, Any] = {
            "instId": position["instrumentId"],
            "mgnMode": position["marginMode"],
            "autoCxl": True,
        }
        if position.get("positionSide"):
            request["posSide"] = position["positionSide"]
        if position.get("instrumentType") == "MARGIN":
            request["ccy"] = position["marginCurrency"]
        return request

    @staticmethod
    def _resolved_terminal_partial(result: dict[str, Any]) -> bool:
        if result.get("status") != "PARTIAL":
            return False
        outcome = result.get("outcome")
        if not isinstance(outcome, dict):
            return False
        return (
            outcome.get("orderState") in ("canceled", "rejected", "mmp_canceled")
            and outcome.get("terminalPartialResolved") is True
            and outcome.get("positionVerified") is True
        )

    def _pending_target_conflict(
        self,
        target_identities: list[dict[str, Any]],
        *,
        exclude_operation_id: str | None = None,
    ) -> bool:
        now = self.clock()
        wanted = {_identity_key(identity) for identity in target_identities}
        with self.store.connection() as connection:
            rows = connection.execute(
                "SELECT operation_id, status, expires_at, payload_json, results_json FROM operations "
                "WHERE status IN ('PREPARED','IN_PROGRESS','UNKNOWN','PARTIAL')"
            ).fetchall()
        for row in rows:
            if row["operation_id"] == exclude_operation_id:
                continue
            if row["status"] == "PREPARED" and row["expires_at"] <= now:
                continue
            payload = decode_json(row["payload_json"])
            results = decode_json(row["results_json"])
            unresolved = any(
                result.get("status") in ("PENDING", "ATTEMPT_STARTED", "UNKNOWN")
                or (
                    result.get("status") == "PARTIAL"
                    and not self._resolved_terminal_partial(result)
                )
                for result in results
            )
            if not unresolved:
                continue
            for target in [*payload.get("targets", []), *results]:
                identity = target.get("identity")
                if isinstance(identity, dict) and _identity_key(identity) in wanted:
                    return True
        return False

    @staticmethod
    def _cancel_identity(value: Any) -> dict[str, str]:
        keys = ("instType", "instId", "ordId", "ordType", "side", "px", "sz")
        if not isinstance(value, dict) or set(value) != set(keys):
            raise APIError(400, "invalid_order_identity", "A complete selected order identity is required.")
        if any(not isinstance(value[key], str) or not value[key] or len(value[key]) > 128
               or value[key] != value[key].strip() for key in keys):
            raise APIError(400, "invalid_order_identity", "The selected order identity is invalid.")
        if (value["instType"] not in ("SPOT", "MARGIN", "SWAP", "FUTURES")
                or value["ordType"] != "limit" or value["side"] not in ("buy", "sell")
                or any(decimal_value(value[key]) is None or decimal_value(value[key]) <= 0
                       for key in ("px", "sz"))):
            raise APIError(400, "invalid_order_identity", "Only active limit orders can be canceled.")
        return {key: value[key] for key in keys}

    @staticmethod
    def _cancel_order_matches(identity: dict[str, Any], order: Any) -> bool:
        if not isinstance(order, dict):
            return False
        for key, expected in identity.items():
            if key in ("px", "sz"):
                if decimal_value(order.get(key)) != decimal_value(expected):
                    return False
            elif order.get(key) != expected:
                return False
        return True

    @staticmethod
    def _cancel_snapshot(order: dict[str, Any]) -> dict[str, Any] | None:
        size, filled = decimal_value(order.get("sz")), decimal_value(order.get("accFillSz"))
        if size is None or size <= 0 or filled is None or filled < 0 or filled >= size:
            return None
        if order.get("state") not in ("live", "partially_filled"):
            return None
        return {"state": order["state"], "filledSize": decimal_text(filled),
                "remainingSize": decimal_text(size - filled)}

    def _read_cancel_order(self, identity: dict[str, Any], fingerprint: str) -> dict[str, Any] | None:
        # Bind both sides of the exchange read to the prepared account.
        if not self._account_fingerprints_match(fingerprint, self._read_account_fingerprint()):
            return None
        order = self.okx.order_details_by_id(identity["instId"], identity["ordId"])
        if (not self._account_fingerprints_match(fingerprint, self._read_account_fingerprint())
                or not self._cancel_order_matches(identity, order)):
            return None
        return order

    def _prepare_order_cancellation(self, body: dict[str, Any], source: str) -> dict[str, Any]:
        identity = self._cancel_identity(body.get("targetIdentity"))
        try:
            account = self.okx.account_config()
        except OKXError:
            raise APIError(
                502,
                "account_identity_unavailable",
                "The exchange account identity is unavailable.",
            ) from None
        fingerprint = self._account_fingerprint(account.get("uid"))
        if not self._valid_account_fingerprint(fingerprint):
            raise APIError(502, "account_identity_unavailable", "The exchange account identity is unavailable.")
        try:
            order = self._read_cancel_order(identity, fingerprint)
        except OKXError:
            raise APIError(502, "order_status_unavailable", "The selected order could not be verified.") from None
        snapshot = None if order is None else self._cancel_snapshot(order)
        if snapshot is None:
            raise APIError(409, "stale_target", "The selected limit order is no longer current.")
        if self._pending_target_conflict([identity]):
            raise APIError(409, "operation_pending", "A prior action for this order still needs reconciliation.")
        summary = {"identity": identity, "action": "cancel_order", "price": identity["px"],
                   "originalSize": identity["sz"], "filledSize": snapshot["filledSize"],
                   "remainingSize": snapshot["remainingSize"]}
        target = {"identity": identity, "snapshot": snapshot,
                  "request": {"instId": identity["instId"], "ordId": identity["ordId"]},
                  "summary": summary, "status": "PENDING", "outcome": None}
        now = self.clock()
        operation_id, confirmation = new_operation_id(), new_confirmation_token()
        expires_at = now + ACTION_TTL_SECONDS
        payload = {"action": "cancel_order", "targets": [target],
                   "accountIdentifier": mask_identifier(account.get("uid")),
                   "accountFingerprint": fingerprint, "createdFrom": source}
        results = [{"identity": identity, "status": "PENDING", "outcome": None}]
        with self.store.transaction() as connection:
            connection.execute(
                "INSERT INTO operations(operation_id, action, confirmation_hash, expires_at, status, "
                "payload_json, results_json, created_at, updated_at) VALUES (?, ?, ?, ?, 'PREPARED', ?, ?, ?, ?)",
                (operation_id, "cancel_order", token_digest(confirmation, self.settings.session_signing_key),
                 expires_at, encode_json(payload), encode_json(results), now, now),
            )
        return {"operationId": operation_id, "confirmationToken": confirmation, "status": "PREPARED",
                "action": "cancel_order", "expiresAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(expires_at)),
                "summary": {"targetCount": 1, "targets": [summary]}}

    def _cancellation_outcome(self, operation: dict[str, Any], target: dict[str, Any]) -> tuple[str, dict[str, Any]]:
        try:
            order = self._read_cancel_order(target["identity"], operation["payload"].get("accountFingerprint"))
        except OKXError:
            order = None
        if order is None:
            return "UNKNOWN", {"reason": "order_status_unavailable"}
        size, filled = decimal_value(order.get("sz")), decimal_value(order.get("accFillSz"))
        if size is None or filled is None or not (0 <= filled <= size):
            return "UNKNOWN", {"reason": "order_status_unavailable"}
        outcome = {"orderState": order.get("state"), "filledSize": decimal_text(filled),
                   "remainingSize": decimal_text(size - filled), "orderId": target["identity"]["ordId"]}
        if order.get("state") in ("canceled", "mmp_canceled"):
            return "SUCCEEDED", {**outcome, "reason": "order_cancellation_verified"}
        if order.get("state") == "filled":
            return "FAILED", {**outcome, "reason": "order_filled_before_cancellation"}
        return "UNKNOWN", {**outcome, "reason": "order_cancellation_not_confirmed"}

    def _execute_order_cancellation(self, operation: dict[str, Any]) -> dict[str, Any]:
        target = operation["payload"]["targets"][0]
        result = operation["targets"][0]
        if self._pending_target_conflict(
            [target["identity"]], exclude_operation_id=operation["operationId"]
        ):
            result.update(status="CONFLICT", outcome={"reason": "order_action_pending"})
        else:
            try:
                order = self._read_cancel_order(
                    target["identity"], operation["payload"]["accountFingerprint"]
                )
            except OKXError:
                order = None
        if result.get("status") == "PENDING" and (
            order is None or self._cancel_snapshot(order) != target["snapshot"]
        ):
            result.update(status="CONFLICT", outcome={"reason": "order_changed_before_cancellation"})
        elif result.get("status") == "PENDING":
            result.update(status="ATTEMPT_STARTED", outcome=None)
            self._save_operation(operation)
            try:
                response = self.okx.cancel_order(target["request"])
                accepted, code = self._mark_known_item_result(response)
                if not accepted:
                    status, outcome = self._write_ack_failure(bounded_error_code(code))
                elif response["data"][0].get("ordId") != target["identity"]["ordId"]:
                    status, outcome = "UNKNOWN", {"reason": "cancellation_acknowledgement_mismatch"}
                else:
                    status, outcome = self._cancellation_outcome(operation, target)
            except OKXTransportError:
                status, outcome = "UNKNOWN", {"reason": "exchange_outcome_unknown"}
            except OKXError as error:
                status, outcome = self._write_ack_failure(error.error_code)
            result.update(status=status, outcome=outcome)
        operation["status"] = self._overall_status(operation["targets"])
        self._save_operation(operation)
        return self._operation_response(operation)

    def _prepare(self, body: dict[str, Any], source: str) -> dict[str, Any]:
        action = body.get("action")
        if action == "cancel_order":
            with self._mutation_lock:
                return self._prepare_order_cancellation(body, source)
        if action not in ("add_margin", "dca", "partial_close", "close_position", "close_all"):
            raise APIError(400, "invalid_action", "The requested action is not supported.")
        snapshot = self._fetch_snapshot()
        if not self._valid_account_fingerprint(snapshot.get("accountFingerprint")):
            raise APIError(
                502,
                "account_identity_unavailable",
                "The exchange account identity is unavailable; prepare the action again later.",
            )
        targets: list[dict[str, Any]] = []
        summaries: list[dict[str, Any]] = []

        if action == "close_all":
            ineligible: list[dict[str, Any]] = []
            for position in snapshot["positions"]:
                allowed, reason = self._eligibility(position, "close_all")
                if not allowed:
                    ineligible.append({"identity": position["identity"], "reason": reason})
                    continue
                target = {
                    "identity": position["identity"],
                    "snapshot": self._material_signature(position),
                    "request": self._close_request(position),
                    "summary": {
                        "identity": position["identity"],
                        "direction": position.get("direction"),
                        "currentSize": position.get("size"),
                        "action": "close_position",
                    },
                    "status": "PENDING",
                    "outcome": None,
                }
                targets.append(target)
                summaries.append(target["summary"])
            if ineligible:
                raise APIError(
                    409,
                    "close_all_ineligible_targets",
                    "Close all is blocked because one or more positions cannot be closed safely.",
                    details={"ineligibleTargets": ineligible, "targetCount": len(snapshot["positions"])},
                )
        else:
            identity = self._identity_from_request(body.get("targetIdentity"))
            position = self._position_by_identity(snapshot["positions"], identity)
            if position is None:
                raise APIError(409, "stale_target", "The selected position is no longer current; prepare it again.")
            target, summary = self._build_target(action, position, body)
            targets = [target]
            summaries = [summary]

        target_identities = [target["identity"] for target in targets]
        if self._pending_target_conflict(target_identities):
            raise APIError(409, "operation_pending", "A prior action for this position still needs reconciliation.")

        now = self.clock()
        operation_id = new_operation_id()
        confirmation = new_confirmation_token()
        expires_at = now + ACTION_TTL_SECONDS
        payload = {
            "action": action,
            "targets": targets,
            "positionMode": snapshot["positionMode"],
            "accountIdentifier": snapshot["accountIdentifier"],
            "accountFingerprint": snapshot["accountFingerprint"],
            "createdFrom": source,
        }
        result_rows = [
            {"identity": target["identity"], "status": "PENDING", "outcome": None}
            for target in targets
        ]
        with self.store.transaction() as connection:
            connection.execute(
                "INSERT INTO operations(operation_id, action, confirmation_hash, expires_at, status, "
                "payload_json, results_json, created_at, updated_at) VALUES (?, ?, ?, ?, 'PREPARED', ?, ?, ?, ?)",
                (
                    operation_id,
                    action,
                    token_digest(confirmation, self.settings.session_signing_key),
                    expires_at,
                    encode_json(payload),
                    encode_json(result_rows),
                    now,
                    now,
                ),
            )
        return {
            "operationId": operation_id,
            "confirmationToken": confirmation,
            "status": "PREPARED",
            "action": action,
            "expiresAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(expires_at)),
            "summary": {"targetCount": len(summaries), "targets": summaries},
        }

    def _load_operation(self, operation_id: str) -> dict[str, Any]:
        with self.store.connection() as connection:
            row = connection.execute(
                "SELECT * FROM operations WHERE operation_id=?", (operation_id,)
            ).fetchone()
        if row is None:
            raise APIError(404, "operation_not_found", "The action result was not found.")
        return {
            "operationId": row["operation_id"],
            "action": row["action"],
            "confirmationHash": row["confirmation_hash"],
            "expiresAtEpoch": row["expires_at"],
            "status": row["status"],
            "payload": decode_json(row["payload_json"]),
            "targets": decode_json(row["results_json"]),
            "createdAt": row["created_at"],
            "updatedAt": row["updated_at"],
        }

    def _save_operation(self, operation: dict[str, Any]) -> None:
        with self.store.transaction() as connection:
            connection.execute(
                "UPDATE operations SET status=?, payload_json=?, results_json=?, updated_at=? WHERE operation_id=?",
                (
                    operation["status"],
                    encode_json(operation["payload"]),
                    encode_json(operation["targets"]),
                    self.clock(),
                    operation["operationId"],
                ),
            )

    def _operation_response(self, operation: dict[str, Any]) -> dict[str, Any]:
        return {
            "operationId": operation["operationId"],
            "action": operation["action"],
            "status": operation["status"],
            "targets": operation["targets"],
            "updatedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(operation["updatedAt"])),
        }

    def _execute(self, body: dict[str, Any]) -> dict[str, Any]:
        operation_id = body.get("operationId")
        confirmation = body.get("confirmationToken")
        if not isinstance(operation_id, str) or not isinstance(confirmation, str):
            raise APIError(400, "invalid_request", "Operation ID and confirmation token are required.")
        with self._mutation_lock:
            operation = self._load_operation(operation_id)
            presented_hash = token_digest(confirmation, self.settings.session_signing_key)
            if not hmac.compare_digest(operation["confirmationHash"], presented_hash):
                raise APIError(403, "invalid_confirmation", "The confirmation token is invalid.")
            if operation["status"] != "PREPARED":
                return self._operation_response(operation)
            if operation["expiresAtEpoch"] <= self.clock():
                operation["status"] = "EXPIRED"
                operation["targets"] = [
                    {**row, "status": "EXPIRED", "outcome": {"reason": "confirmation_expired"}}
                    for row in operation["targets"]
                ]
                self._save_operation(operation)
                return self._operation_response(operation)

            if not self._valid_account_fingerprint(
                operation.get("payload", {}).get("accountFingerprint")
            ):
                operation["status"] = "CONFLICT"
                operation["targets"] = [
                    {
                        **row,
                        "status": "CONFLICT",
                        "outcome": {"reason": "account_identity_unavailable"},
                    }
                    for row in operation["targets"]
                ]
                self._save_operation(operation)
                return self._operation_response(operation)

            operation["status"] = "IN_PROGRESS"
            self._save_operation(operation)
            if operation["action"] == "cancel_order":
                return self._execute_order_cancellation(operation)
            try:
                current = self._fetch_snapshot()
            except APIError:
                operation["status"] = "FAILED"
                operation["targets"] = [
                    {**row, "status": "FAILED", "outcome": {"reason": "preflight_unavailable"}}
                    for row in operation["targets"]
                ]
                self._save_operation(operation)
                raise

            if not self._operation_account_matches(operation, current):
                operation["status"] = "CONFLICT"
                operation["targets"] = [
                    {
                        **row,
                        "status": "CONFLICT",
                        "outcome": {"reason": "account_identity_changed_before_execution"},
                    }
                    for row in operation["targets"]
                ]
                self._save_operation(operation)
                return self._operation_response(operation)
            if not self._preflight_matches(operation, current):
                operation["status"] = "CONFLICT"
                operation["targets"] = [
                    {**row, "status": "CONFLICT", "outcome": {"reason": "position_changed"}}
                    for row in operation["targets"]
                ]
                self._save_operation(operation)
                return self._operation_response(operation)

            for index, journal_target in enumerate(operation["payload"]["targets"]):
                result = operation["targets"][index]
                try:
                    before_attempt = self._fetch_snapshot()
                except APIError:
                    result["status"] = "FAILED"
                    result["outcome"] = {"reason": "target_recheck_unavailable_before_write"}
                    operation["targets"][index] = result
                    self._save_operation(operation)
                    continue
                if not self._operation_account_matches(operation, before_attempt):
                    for remaining_index in range(index, len(operation["targets"])):
                        remaining = operation["targets"][remaining_index]
                        remaining["status"] = "CONFLICT"
                        remaining["outcome"] = {
                            "reason": "account_identity_changed_during_execution"
                        }
                        operation["targets"][remaining_index] = remaining
                    self._save_operation(operation)
                    break
                latest_position = self._position_by_identity(
                    before_attempt["positions"], journal_target["identity"]
                )
                if (
                    latest_position is None
                    or self._material_signature(latest_position) != journal_target["snapshot"]
                ):
                    result["status"] = "CONFLICT"
                    result["outcome"] = {"reason": "target_changed_during_execution"}
                    operation["targets"][index] = result
                    self._save_operation(operation)
                    continue
                result["status"] = "ATTEMPT_STARTED"
                result["outcome"] = None
                operation["targets"][index] = result
                self._save_operation(operation)
                status, outcome = self._perform_target(operation, journal_target)
                result["status"] = status
                result["outcome"] = outcome
                operation["targets"][index] = result
                self._save_operation(operation)

            if operation["action"] == "close_all":
                self._verify_close_all_final_state(operation)
            operation["status"] = self._overall_status(operation["targets"])
            self._save_operation(operation)
            return self._operation_response(operation)

    def _preflight_matches(self, operation: dict[str, Any], current: dict[str, Any]) -> bool:
        if not self._operation_account_matches(operation, current):
            return False
        expected_targets = operation["payload"].get("targets", [])
        current_positions = current["positions"]
        if operation["action"] == "close_all":
            expected = sorted(
                (encode_json(target["snapshot"]) for target in expected_targets)
            )
            observed = sorted(encode_json(self._material_signature(position)) for position in current_positions)
            return expected == observed
        if len(expected_targets) != 1:
            return False
        target = expected_targets[0]
        position = self._position_by_identity(current_positions, target["identity"])
        return position is not None and self._material_signature(position) == target["snapshot"]

    def _mark_known_item_result(self, response: dict[str, Any]) -> tuple[bool, str | None]:
        data = response.get("data", [])
        if not data:
            return False, None
        first = data[0]
        if not isinstance(first, dict):
            return False, None
        code = first.get("sCode")
        if code is None:
            return False, None
        if str(code) != "0":
            return False, str(code)
        return True, None

    @staticmethod
    def _write_ack_failure(error_code: str | None) -> tuple[str, dict[str, Any]]:
        if error_code is None:
            return "UNKNOWN", {"reason": "exchange_acknowledgement_unconfirmed"}
        return "FAILED", {"reason": "exchange_rejected", "exchangeCode": error_code}

    def _verify_order_position_change(
        self,
        action: str,
        target: dict[str, Any],
        expected_account_fingerprint: str | None = None,
    ) -> tuple[bool, str]:
        try:
            current = self._fetch_snapshot()
        except APIError:
            return False, "reconciliation_unavailable"
        if not self._account_fingerprints_match(
            expected_account_fingerprint, current.get("accountFingerprint")
        ):
            return False, "account_identity_changed_during_reconciliation"
        position = self._position_by_identity(current["positions"], target["identity"])
        before = decimal_value(target["snapshot"].get("signedSize"))
        after = Decimal(0) if position is None else decimal_value(position.get("signedSize"))
        if before is None or after is None:
            return False, "position_change_unavailable"
        before_size = abs(before)
        after_size = abs(after)
        changed = after_size > before_size if action == "dca" else after_size < before_size
        if not changed:
            return False, "position_change_not_confirmed"
        return True, "position_change_verified"

    def _order_details_outcome(
        self,
        action: str,
        target: dict[str, Any],
        details: dict[str, Any],
        expected_account_fingerprint: str | None = None,
    ) -> tuple[str, dict[str, Any]]:
        request = target["request"]
        client_order_id = request.get("clOrdId")
        state = str(details.get("state", "")).lower()
        filled = decimal_value(details.get("accFillSz"))
        fill_text = decimal_text(filled) if filled is not None else None
        common = {"orderState": state or None, "clientOrderId": client_order_id}
        if fill_text is not None:
            common["accFillSz"] = fill_text
        if state in ("canceled", "rejected", "mmp_canceled"):
            if filled is not None and filled > 0:
                position_verified, verification_reason = self._verify_order_position_change(
                    action, target, expected_account_fingerprint
                )
                return "PARTIAL", {
                    "reason": "partial_fill_canceled",
                    "positionVerified": position_verified,
                    "terminalPartialResolved": position_verified,
                    "positionVerificationReason": verification_reason,
                    **common,
                }
            return "FAILED", {
                "reason": "order_not_filled",
                **common,
            }
        if state not in ("filled", "partially_filled"):
            if filled is not None and filled > 0:
                return "PARTIAL", {
                    "reason": "partial_fill_pending",
                    **common,
                }
            return "UNKNOWN", {
                "reason": "order_pending",
                **common,
            }

        position_verified, verification_reason = self._verify_order_position_change(
            action, target, expected_account_fingerprint
        )
        if not position_verified:
            return "UNKNOWN", {
                "reason": verification_reason,
                **common,
            }
        if state == "partially_filled":
            return "PARTIAL", {
                "reason": "partial_fill_verified",
                "positionVerified": True,
                **common,
            }
        return "SUCCEEDED", {
            "reason": "filled_and_position_refreshed",
            "positionVerified": True,
            **common,
        }

    def _perform_target(
        self, operation: dict[str, Any], target: dict[str, Any]
    ) -> tuple[str, dict[str, Any]]:
        action = operation["action"]
        request = target["request"]
        try:
            if action == "add_margin":
                response = self.okx.add_margin(request)
                accepted, error_code = self._mark_known_item_result(response)
                if not accepted:
                    return self._write_ack_failure(error_code)
                try:
                    current = self._fetch_snapshot()
                except APIError:
                    return "UNKNOWN", {"reason": "reconciliation_unavailable"}
                if not self._operation_account_matches(operation, current):
                    return "UNKNOWN", {"reason": "account_identity_changed_during_reconciliation"}
                position = self._position_by_identity(current["positions"], target["identity"])
                old_margin = decimal_value(target["snapshot"].get("margin"))
                new_margin = None if position is None else decimal_value(position.get("margin"))
                amount = decimal_value(target["summary"].get("amount"))
                if old_margin is not None and new_margin is not None and amount is not None and new_margin >= old_margin + amount:
                    return "SUCCEEDED", {"reason": "margin_increase_verified", "amount": target["summary"]["amount"]}
                return "UNKNOWN", {"reason": "margin_change_not_confirmed"}

            if action == "close_position" or action == "close_all":
                response = self.okx.close_position(request)
                accepted, error_code = self._mark_known_item_result(response)
                if not accepted:
                    return self._write_ack_failure(error_code)
                try:
                    current = self._fetch_snapshot()
                except APIError:
                    return "UNKNOWN", {"reason": "reconciliation_unavailable"}
                if not self._operation_account_matches(operation, current):
                    return "UNKNOWN", {"reason": "account_identity_changed_during_reconciliation"}
                if self._position_by_identity(current["positions"], target["identity"]) is None:
                    return "SUCCEEDED", {"reason": "position_closed_verified"}
                return "UNKNOWN", {"reason": "position_still_open"}

            response = self.okx.place_order(request)
            accepted, error_code = self._mark_known_item_result(response)
            if not accepted:
                return self._write_ack_failure(error_code)
            client_order_id = request["clOrdId"]
            expected_fingerprint = operation.get("payload", {}).get("accountFingerprint")
            if not self._account_fingerprints_match(
                expected_fingerprint, self._read_account_fingerprint()
            ):
                return "UNKNOWN", {"reason": "account_identity_changed_during_reconciliation"}
            try:
                details = self.okx.order_details(request["instId"], client_order_id)
            except OKXError:
                return "UNKNOWN", {"reason": "order_status_unavailable", "clientOrderId": client_order_id}
            if details is None:
                return "UNKNOWN", {"reason": "order_not_yet_visible", "clientOrderId": client_order_id}
            return self._order_details_outcome(action, target, details, expected_fingerprint)
        except OKXTransportError:
            return "UNKNOWN", {"reason": "exchange_outcome_unknown"}
        except OKXError:
            return "FAILED", {"reason": "exchange_rejected"}

    def _verify_close_all_final_state(self, operation: dict[str, Any]) -> None:
        try:
            current = self._fetch_snapshot()
        except APIError:
            operation["targets"].append({
                "identity": None,
                "status": "UNKNOWN",
                "outcome": {"reason": "final_account_reconciliation_unavailable"},
            })
            return
        if not self._operation_account_matches(operation, current):
            operation["targets"].append({
                "identity": None,
                "status": "UNKNOWN",
                "outcome": {"reason": "account_identity_changed_during_final_reconciliation"},
            })
            return
        confirmed = {_identity_key(target["identity"]) for target in operation["payload"].get("targets", [])}
        for position in current["positions"]:
            key = _identity_key(position["identity"])
            if key in confirmed:
                for target_result in operation["targets"]:
                    if target_result.get("identity") and _identity_key(target_result["identity"]) == key:
                        if target_result.get("status") == "SUCCEEDED":
                            target_result["status"] = "UNKNOWN"
                            target_result["outcome"] = {"reason": "position_remains_open_after_batch"}
                        break
            else:
                operation["targets"].append({
                    "identity": position["identity"],
                    "status": "UNKNOWN",
                    "outcome": {"reason": "unconfirmed_position_remains_open"},
                })

    def _overall_status(self, targets: list[dict[str, Any]]) -> str:
        statuses = [target.get("status") for target in targets]
        if statuses and all(status == "CONFLICT" for status in statuses):
            return "CONFLICT"
        if not statuses or all(status == "SUCCEEDED" for status in statuses):
            return "SUCCEEDED"
        if all(status == "FAILED" for status in statuses):
            return "FAILED"
        if any(status in ("UNKNOWN", "ATTEMPT_STARTED", "PENDING") for status in statuses):
            return "PARTIAL" if any(status in ("SUCCEEDED", "PARTIAL") for status in statuses) else "UNKNOWN"
        return "PARTIAL"

    def _get_result(self, operation_id: str) -> dict[str, Any]:
        with self._mutation_lock:
            operation = self._load_operation(operation_id)
            changed = False
            journal_targets = operation["payload"].get("targets", [])
            for index, target_result in enumerate(list(operation["targets"])):
                if target_result.get("status") == "ATTEMPT_STARTED":
                    target_result["status"] = "UNKNOWN"
                    target_result["outcome"] = {"reason": "process_stopped_during_attempt"}
                    changed = True
                elif operation["status"] == "IN_PROGRESS" and target_result.get("status") == "PENDING":
                    target_result["status"] = "CONFLICT"
                    target_result["outcome"] = {"reason": "process_stopped_before_attempt"}
                    changed = True
                current_status = target_result.get("status")
                should_reconcile = current_status == "UNKNOWN" or (
                    current_status == "PARTIAL"
                    and operation["action"] in ("dca", "partial_close")
                )
                result_identity = target_result.get("identity")
                journal_target = next(
                    (
                        target
                        for target in journal_targets
                        if isinstance(result_identity, dict)
                        and _identity_key(target.get("identity", {})) == _identity_key(result_identity)
                    ),
                    None,
                )
                if should_reconcile and journal_target is not None:
                    reconciled_status, outcome = self._reconcile_unknown(
                        operation, journal_target
                    )
                    if current_status == "PARTIAL" and reconciled_status == "FAILED":
                        outcome = {
                            "reason": "partial_execution_previously_confirmed",
                            "orderState": outcome.get("orderState"),
                            "clientOrderId": journal_target.get("request", {}).get("clOrdId"),
                            "priorOutcome": target_result.get("outcome"),
                        }
                        reconciled_status = "PARTIAL"
                    if reconciled_status != "UNKNOWN" and (
                        reconciled_status != current_status or outcome != target_result.get("outcome")
                    ):
                        target_result["status"] = reconciled_status
                        target_result["outcome"] = outcome
                        changed = True
                elif should_reconcile and operation["action"] == "close_all":
                    reconciled_status, outcome, aggregate_changed = (
                        self._reconcile_close_all_aggregate(operation, target_result)
                    )
                    if reconciled_status != "UNKNOWN" and (
                        reconciled_status != current_status or outcome != target_result.get("outcome")
                    ):
                        target_result["status"] = reconciled_status
                        target_result["outcome"] = outcome
                        changed = True
                    changed = changed or aggregate_changed
            if (
                operation["status"] == "IN_PROGRESS"
                and operation["action"] == "close_all"
                and operation["targets"]
                and all(row.get("status") == "SUCCEEDED" for row in operation["targets"])
            ):
                # A crash can occur after the last per-position result is
                # journaled but before the account-wide final snapshot. Require
                # that same-account snapshot before exposing batch success.
                self._verify_close_all_final_state(operation)
                changed = True
            if operation["status"] == "IN_PROGRESS":
                operation["status"] = self._overall_status(operation["targets"])
                changed = True
            elif changed:
                operation["status"] = self._overall_status(operation["targets"])
            if changed:
                operation["updatedAt"] = self.clock()
                self._save_operation(operation)
            return self._operation_response(operation)

    def _reconcile_close_all_aggregate(
        self, operation: dict[str, Any], target_result: dict[str, Any]
    ) -> tuple[str, dict[str, Any], bool]:
        expected_fingerprint = operation.get("payload", {}).get("accountFingerprint")
        if not self._valid_account_fingerprint(expected_fingerprint):
            return "UNKNOWN", {"reason": "account_identity_unavailable"}, False
        try:
            snapshot = self._fetch_snapshot()
        except APIError:
            return "UNKNOWN", {"reason": "reconciliation_unavailable"}, False
        if not self._operation_account_matches(operation, snapshot):
            return "UNKNOWN", {"reason": "account_identity_changed"}, False

        changed = False
        for position in snapshot["positions"]:
            identity = position["identity"]
            key = _identity_key(identity)
            existing = next(
                (
                    row
                    for row in operation["targets"]
                    if isinstance(row.get("identity"), dict)
                    and _identity_key(row["identity"]) == key
                ),
                None,
            )
            if existing is None:
                operation["targets"].append(
                    {
                        "identity": identity,
                        "status": "UNKNOWN",
                        "outcome": {"reason": "unconfirmed_position_remains_open"},
                    }
                )
                changed = True
            elif existing.get("status") == "SUCCEEDED":
                existing["status"] = "UNKNOWN"
                existing["outcome"] = {"reason": "position_remains_open_after_batch"}
                changed = True

        identity = target_result.get("identity")
        if isinstance(identity, dict):
            position = self._position_by_identity(snapshot["positions"], identity)
            if position is not None:
                return "UNKNOWN", {"reason": "unconfirmed_position_remains_open"}, changed
            return "SUCCEEDED", {"reason": "unconfirmed_position_closed_verified_on_recheck"}, changed

        if snapshot["positions"]:
            return "UNKNOWN", {"reason": "positions_remain_after_batch_recheck"}, changed
        return "SUCCEEDED", {"reason": "final_account_state_verified"}, changed

    def _reconcile_unknown(
        self, operation: dict[str, Any], journal_target: dict[str, Any]
    ) -> tuple[str, dict[str, Any]]:
        action = operation["action"]
        if action == "cancel_order":
            return self._cancellation_outcome(operation, journal_target)
        expected_fingerprint = operation.get("payload", {}).get("accountFingerprint")
        if not self._valid_account_fingerprint(expected_fingerprint):
            return "UNKNOWN", {"reason": "account_identity_unavailable"}
        if not self._account_fingerprints_match(
            expected_fingerprint, self._read_account_fingerprint()
        ):
            return "UNKNOWN", {"reason": "account_identity_changed"}
        try:
            if action in ("close_position", "close_all"):
                snapshot = self._fetch_snapshot()
                if not self._operation_account_matches(operation, snapshot):
                    return "UNKNOWN", {"reason": "account_identity_changed"}
                if self._position_by_identity(snapshot["positions"], journal_target["identity"]) is None:
                    return "SUCCEEDED", {"reason": "position_closed_verified_on_recheck"}
                return "UNKNOWN", {"reason": "position_still_open"}

            if action == "add_margin":
                snapshot = self._fetch_snapshot()
                if not self._operation_account_matches(operation, snapshot):
                    return "UNKNOWN", {"reason": "account_identity_changed"}
                position = self._position_by_identity(snapshot["positions"], journal_target["identity"])
                old_margin = decimal_value(journal_target["snapshot"].get("margin"))
                new_margin = None if position is None else decimal_value(position.get("margin"))
                amount = decimal_value(journal_target["summary"].get("amount"))
                if old_margin is not None and new_margin is not None and amount is not None and new_margin >= old_margin + amount:
                    return "SUCCEEDED", {"reason": "margin_increase_verified_on_recheck"}
                return "UNKNOWN", {"reason": "margin_change_not_confirmed"}

            request = journal_target["request"]
            client_order_id = request.get("clOrdId")
            if not client_order_id:
                return "UNKNOWN", {"reason": "reconciliation_identifier_missing"}
            details = self.okx.order_details(request["instId"], client_order_id)
            if details is None:
                return "UNKNOWN", {"reason": "order_not_yet_visible", "clientOrderId": client_order_id}
            return self._order_details_outcome(
                action, journal_target, details, expected_fingerprint
            )
        except (APIError, OKXError):
            return "UNKNOWN", {"reason": "reconciliation_unavailable"}
