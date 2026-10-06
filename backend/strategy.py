"""Authenticated, durable position-strategy preview and application flow."""

from __future__ import annotations

import hmac
import math
import re
import secrets
import sqlite3
import threading
import time
from decimal import Decimal, InvalidOperation, ROUND_CEILING, ROUND_DOWN, ROUND_FLOOR
from typing import Any, Callable

from .okx import OKXError, OKXTransportError, bounded_error_code
from . import diagnostics
from .security import new_confirmation_token, new_operation_id, token_digest
from .service import APIError
from .store import decode_json, encode_json
from .strategy_automatic import AutomaticStrategyService
from .strategy_queue import (
    initial_results,
    new_queue,
    normalize_queue,
    parse_leverage_ack,
    progress as queue_progress,
)
from .strategy_retry import (
    RetryDataError,
    classify_row as _retry_classify_row,
    fixed_preview as _fixed_retry_preview,
    is_resubmission_contract,
    ordered_ids as _retry_ordered_ids,
    ordered_selection as _retry_ordered_selection,
    retry_metadata as _retry_metadata,
    selection_hash as _retry_selection_hash,
    source_revision as _retry_source_revision,
    source_rows as _retry_source_rows,
)
from .strategy_scope import (
    UNKNOWN_SCOPE,
    StrategyScope,
    extract_persisted_scope,
    reservation_scope,
    scope_for_sides,
    scopes_overlap,
    scoped_pending_rows,
    scoped_position_rows,
)


_INTERVALS = {"6Hutc", "12Hutc", "1Dutc", "1Wutc"}
_MAX_ORDERS = 20
_MAX_NEW_ORDERS = 10
_PREPARE_TTL_SECONDS = 120
_EXECUTION_LEASE_SECONDS = 120
_QUOTE_MAX_AGE_MS = 15_000
_ORDER_SCAN_INTERVAL_SECONDS = 5
_ORDER_SCAN_FRESH_SECONDS = 15
_ORDER_TERMINAL_STATES = frozenset({"rejected", "filled", "canceled", "mmp_canceled", "not_submitted"})
_DELETABLE_SUBMITTED_ORDER_STATES = frozenset({"filled", "canceled", "mmp_canceled"})
_DELETABLE_ORDER_STATES = _DELETABLE_SUBMITTED_ORDER_STATES | {"rejected", "not_submitted"}
_STRATEGY_ID = re.compile(r"[A-Za-z0-9_-]{8,64}\Z")
_DEFAULT_JEV_SCREENING_THRESHOLDS = {
    "minStructuralQuality": 4,
    "minEntrySuitabilityProbability": 0.6,
    "maxFailureRiskProbability": 0.4,
}
_JEV_SCREENING_THRESHOLD_KEYS = frozenset(_DEFAULT_JEV_SCREENING_THRESHOLDS)


def _decimal(value: Any) -> Decimal | None:
    if value is None or isinstance(value, (bool, float)):
        return None
    try:
        result = Decimal(str(value))
        return result if result.is_finite() else None
    except (InvalidOperation, ValueError, TypeError):
        return None


def _text(value: Decimal | None) -> str | None:
    if value is None:
        return None
    if value == 0:
        return "0"
    return format(value.normalize(), "f")


def _positive(value: Any) -> Decimal | None:
    parsed = _decimal(value)
    return parsed if parsed is not None and parsed > 0 else None


def _validated_order_update(
    instrument_id: str, row: dict[str, Any], details: Any
) -> dict[str, Any] | None:
    if not isinstance(details, dict):
        return None
    client_id = row.get("clientOrderId")
    expected_size = _decimal(row.get("contracts"))
    size = _decimal(details.get("sz"))
    if (
        details.get("instId") != instrument_id
        or details.get("clOrdId") != client_id
        or not isinstance(client_id, str)
        or not client_id
        or expected_size is None
        or size is None
        or size != expected_size
    ):
        return None
    filled = _decimal(details.get("accFillSz"))
    if filled is None or filled < 0 or filled > size:
        return None
    state = str(details.get("state", "")).lower()
    if state not in ("live", "partially_filled", "filled", "canceled", "mmp_canceled"):
        return None
    average = _positive(details.get("avgPx"))
    updated = {
        **row,
        "status": state,
        "exchangeOrderId": details.get("ordId") or row.get("exchangeOrderId"),
        "filledContracts": _text(filled),
        "averageFillPrice": _text(average),
    }
    if row.get("placementState") == "unknown":
        updated["placementState"] = "accepted"
    return updated


def _read_order_rows(
    strategy: dict[str, Any],
    okx: Any,
    *,
    recovering: bool = False,
    preserve_last_known: bool = False,
    max_reads: int | None = None,
    stop_after_failure: bool = False,
    before_order_call: Callable[[], None] | None = None,
) -> tuple[list[dict[str, Any]], str | None, int]:
    results = list(strategy["results"])
    failure: str | None = None
    reads = 0
    for index, row in enumerate(results):
        state = row.get("status")
        if row.get("placementState") in ("pending", "not_submitted"):
            continue
        if state in _ORDER_TERMINAL_STATES and not (recovering and state == "not_submitted"):
            continue
        client_id = row.get("clientOrderId")
        if not isinstance(client_id, str) or not client_id:
            if not preserve_last_known:
                results[index] = {**row, "status": "unknown"}
            failure = failure or "invalid_order_details"
            if stop_after_failure:
                break
            continue
        if max_reads is not None and reads >= max_reads:
            failure = failure or "order_limit_exceeded"
            break
        reads += 1
        if before_order_call is not None:
            before_order_call()
        try:
            details = okx.order_details(strategy["contract"]["instrumentId"], client_id)
        except OKXError:
            failure = failure or "exchange_unavailable"
            if recovering and not preserve_last_known:
                results[index] = {**row, "status": "unknown"}
            if stop_after_failure:
                break
            continue
        if details is None:
            failure = failure or "order_unavailable"
            if recovering and not preserve_last_known:
                results[index] = {**row, "status": "unknown"}
            if stop_after_failure:
                break
            continue
        update = _validated_order_update(strategy["contract"]["instrumentId"], row, details)
        if update is None:
            failure = failure or "invalid_order_details"
            if not preserve_last_known:
                results[index] = {**row, "status": "unknown"}
            if stop_after_failure:
                break
            continue
        results[index] = update
    return results, failure, reads


def _reconciled_strategy_state(
    strategy: dict[str, Any], results: list[dict[str, Any]], *, recovering: bool
) -> tuple[str, str | None]:
    states = {row.get("status") for row in results}
    new_status = strategy["status"]
    error: str | None = strategy["failureReason"]
    queue = strategy.get("queue")
    if isinstance(queue, dict) and queue.get("phase") == "stopped":
        if "unknown" in states:
            return "UNKNOWN", strategy.get("failureReason") or queue.get("stopReason")
        return "PARTIAL", strategy.get("failureReason") or queue.get("stopReason")
    if recovering:
        if "unknown" in states or "not_submitted" in states:
            return "UNKNOWN", "batch_reconciliation_incomplete"
        if states.intersection({"rejected", "canceled", "mmp_canceled"}):
            return "PARTIAL", "order_rejected_or_canceled"
        return "APPLIED", None
    if strategy["status"] == "UNKNOWN" and not (
        "unknown" in states or "not_submitted" in states or "accepted" in states
    ):
        new_status = "PARTIAL" if states.intersection({"rejected", "canceled", "mmp_canceled"}) else "APPLIED"
        error = None
    elif strategy["status"] == "APPLIED" and "unknown" in states:
        new_status = "UNKNOWN"
    elif strategy["status"] == "APPLIED" and states.intersection({"rejected", "canceled", "mmp_canceled"}):
        new_status = "PARTIAL"
    elif strategy["status"] == "PARTIAL" and "unknown" in states:
        new_status = "UNKNOWN"
    return new_status, error


def _round_up(value: Decimal, increment: Decimal) -> Decimal:
    return (value / increment).to_integral_value(rounding=ROUND_CEILING) * increment


def _round_down(value: Decimal, increment: Decimal) -> Decimal:
    return (value / increment).to_integral_value(rounding=ROUND_FLOOR) * increment


class StrategyService:
    def __init__(self, owner: Any):
        self.owner = owner
        self.store = owner.store
        self.okx = owner.okx
        self.clock = owner.clock
        self.automatic = AutomaticStrategyService(self)
        self._quote_cache: dict[str, tuple[float, dict[str, str]]] = {}
        self._quote_cache_lock = threading.Lock()
        self._quote_instrument_locks: dict[str, threading.Lock] = {}

    def dispatch(
        self,
        method: str,
        path: str,
        body: dict[str, Any],
        *,
        request_guard: Callable[[], Any] | None = None,
    ) -> dict[str, Any]:
        automatic_response = self.automatic.dispatch(
            method, path, body, request_guard=request_guard
        )
        if automatic_response is not None:
            return automatic_response
        if path == "/v1/strategies/settings":
            if method == "GET":
                return self._get_settings()
            if method == "POST":
                return self._save_settings(body)
            raise APIError(405, "method_not_allowed", "The requested method is not allowed.")
        if method == "POST" and path == "/v1/strategies/preview":
            return self._preview(body)
        if method == "POST" and path == "/v1/strategies":
            return self._save(body)
        if method == "GET" and path == "/v1/strategies":
            return self._list()
        match = re.fullmatch(
            r"/v1/strategies/([A-Za-z0-9_-]{8,64})/"
            r"(prepare-apply|execute-apply|result|delete|quote|retry-candidates|retry-preview|retry-drafts)",
            path,
        )
        if match is None:
            raise APIError(404, "not_found", "The requested endpoint was not found.")
        strategy_id, action = match.groups()
        if action == "retry-candidates" and method == "GET":
            return self._retry_candidates(strategy_id)
        if action == "retry-preview" and method == "POST":
            return self._retry_preview(strategy_id, body)
        if action == "retry-drafts" and method == "POST":
            return self._retry_draft(strategy_id, body)
        if action == "prepare-apply" and method == "POST":
            with diagnostics.strategy_context(strategy_id, component="api"):
                return self._prepare(strategy_id)
        if action == "execute-apply" and method == "POST":
            with diagnostics.strategy_context(strategy_id, component="api"):
                return self._execute(strategy_id, body)
        if action == "result" and method == "GET":
            return self._result(strategy_id)
        if action == "delete" and method == "POST":
            return self._delete(strategy_id)
        if action == "quote" and method == "GET":
            return self._quote(strategy_id)
        raise APIError(404, "not_found", "The requested endpoint was not found.")

    @staticmethod
    def _persisted_scope(
        strategy: dict[str, Any], *, require_prepared_mode: bool = True
    ) -> StrategyScope:
        return extract_persisted_scope(
            strategy.get("prepared"), strategy.get("snapshot"), strategy.get("orders"),
            require_prepared_mode=require_prepared_mode,
        )

    @staticmethod
    def _has_overlapping_reservation(
        connection: Any,
        fingerprint: str,
        instrument_id: str,
        scope: StrategyScope,
        *,
        exclude_ids: set[str] | None = None,
    ) -> bool:
        excluded = exclude_ids or set()
        reservations = connection.execute(
            "SELECT strategy_id, position_mode, side_scope FROM strategy_reservations "
            "WHERE account_fingerprint=? AND instrument_id=?",
            (fingerprint, instrument_id),
        ).fetchall()
        return any(
            row["strategy_id"] not in excluded
            and scopes_overlap(
                scope, reservation_scope(row["position_mode"], row["side_scope"])
            )
            for row in reservations
        )

    def _claim_reservation_in_connection(
        self,
        connection: Any,
        strategy: dict[str, Any],
        scope: StrategyScope,
        now: float,
    ) -> None:
        if self._has_overlapping_reservation(
            connection,
            strategy["accountFingerprint"],
            strategy["contract"]["instrumentId"],
            scope,
        ):
            raise APIError(
                409, "instrument_apply_in_progress",
                "Another strategy is applying or reconciling an overlapping position scope.",
            )
        connection.execute(
            "INSERT INTO strategy_reservations(account_fingerprint, instrument_id, strategy_id, "
            "position_mode, side_scope, created_at) VALUES (?, ?, ?, ?, ?, ?)",
            (
                strategy["accountFingerprint"], strategy["contract"]["instrumentId"],
                strategy["id"], scope.position_mode, scope.side_scope, now,
            ),
        )

    def _quote(self, strategy_id: str) -> dict[str, str]:
        strategy, _, _ = self._current_strategy(strategy_id)
        if strategy["status"] not in {"APPLIED", "PARTIAL", "UNKNOWN"}:
            raise APIError(409, "strategy_not_applied", "A quote is available only for an applied strategy.")
        instrument_id = strategy["contract"].get("instrumentId")
        if not isinstance(instrument_id, str) or not instrument_id:
            raise APIError(502, "quote_invalid", "The strategy instrument is invalid.")
        return self._quote_for_instrument(instrument_id)

    def _quote_for_instrument(self, instrument_id: str) -> dict[str, str]:
        now = self.clock()
        with self._quote_cache_lock:
            cached = self._quote_cache.get(instrument_id)
            if cached is not None and now < cached[0]:
                return dict(cached[1])
            instrument_lock = self._quote_instrument_locks.setdefault(
                instrument_id, threading.Lock()
            )

        with instrument_lock:
            now = self.clock()
            with self._quote_cache_lock:
                cached = self._quote_cache.get(instrument_id)
                if cached is not None and now < cached[0]:
                    return dict(cached[1])
            try:
                ticker = self.okx.ticker(instrument_id)
            except OKXError:
                raise APIError(502, "quote_unavailable", "The current market quote is unavailable.") from None

            last = _positive(ticker.get("last")) if isinstance(ticker, dict) else None
            timestamp = _decimal(ticker.get("ts")) if isinstance(ticker, dict) else None
            if (
                not isinstance(ticker, dict)
                or ticker.get("instId") != instrument_id
                or last is None
                or timestamp is None
                or timestamp <= 0
                or timestamp != timestamp.to_integral_value()
            ):
                raise APIError(502, "quote_invalid", "The current market quote is invalid.")

            timestamp_ms = int(timestamp)
            age_ms = int(self.clock() * 1000) - timestamp_ms
            if age_ms < 0 or age_ms > _QUOTE_MAX_AGE_MS:
                raise APIError(409, "quote_stale", "The current market quote is stale; try again shortly.")

            observed_at = (
                time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(timestamp_ms // 1000))
                + f".{timestamp_ms % 1000:03d}Z"
            )
            quote = {
                "instrumentId": instrument_id,
                "lastPrice": _text(last) or "0",
                "observedAt": observed_at,
            }
            with self._quote_cache_lock:
                self._quote_cache[instrument_id] = (self.clock() + 1, quote)
            return dict(quote)

    def _invalid(self, reason: str, message: str = "The strategy request is invalid.") -> APIError:
        return APIError(422, "invalid_strategy", message, details={"reason": reason})

    @staticmethod
    def _read_failure(
        error: OKXError,
        *,
        fallback_code: str,
        fallback_message: str,
    ) -> APIError:
        if error.http_status == 429:
            return APIError(
                429,
                "exchange_rate_limited",
                "The exchange is rate limiting requests; try again shortly.",
                headers=[("Retry-After", "2")],
            )
        return APIError(502, fallback_code, fallback_message)

    @staticmethod
    def _available_usdt(balance_rows: Any) -> Decimal | None:
        if not isinstance(balance_rows, list):
            return None
        matches = 0
        available: Decimal | None = None
        for row in balance_rows:
            if not isinstance(row, dict) or not isinstance(row.get("details"), list):
                return None
            for detail in row["details"]:
                if not isinstance(detail, dict) or not isinstance(detail.get("ccy"), str):
                    return None
                if detail["ccy"] == "USDT":
                    matches += 1
                    available = _decimal(detail.get("availBal"))
                    if available is None:
                        return None
        return available if matches == 1 else None

    def _account(
        self,
        account_snapshot: tuple[dict[str, Any], str] | None = None,
        *,
        fallback_code: str = "exchange_unavailable",
        fallback_message: str = "Current account data is unavailable.",
    ) -> tuple[dict[str, Any], str]:
        if account_snapshot is None:
            try:
                account = self.okx.account_config()
            except OKXError as exc:
                raise self._read_failure(
                    exc, fallback_code=fallback_code, fallback_message=fallback_message
                ) from None
        else:
            account, snapshot_fingerprint = account_snapshot
            if not isinstance(account, dict):
                raise APIError(502, "account_identity_unavailable", "The exchange account identity is unavailable.")
        if account_snapshot is not None and (
            not isinstance(snapshot_fingerprint, str)
            or not self.owner._valid_account_fingerprint(snapshot_fingerprint)
        ):
            raise APIError(502, "account_identity_unavailable", "The exchange account identity is unavailable.")
        fingerprint = self.owner._account_fingerprint(account.get("uid"))
        if not self.owner._valid_account_fingerprint(fingerprint):
            raise APIError(
                502, "account_identity_unavailable",
                "The exchange account identity is unavailable; try again later.",
            )
        if account_snapshot is not None and not hmac.compare_digest(fingerprint, snapshot_fingerprint):
            raise APIError(502, "account_identity_unavailable", "The exchange account identity is unavailable.")
        return account, fingerprint

    def _get_settings(self) -> dict[str, Any]:
        _, fingerprint = self._account()
        return self._settings_for_fingerprint(fingerprint)

    def _save_settings(self, body: dict[str, Any]) -> dict[str, Any]:
        allowed_keys = {"limitOrderSubmissionMode", "jevScreeningThresholds"}
        if not isinstance(body, dict) or not body or not set(body).issubset(allowed_keys):
            raise APIError(
                400, "invalid_strategy_settings",
                "The strategy settings request contains an unsupported field or no settings.",
            )

        mode_supplied = "limitOrderSubmissionMode" in body
        thresholds_supplied = "jevScreeningThresholds" in body
        requested_mode = body.get("limitOrderSubmissionMode")
        if mode_supplied and requested_mode not in ("sequential", "batch"):
            raise APIError(
                400, "invalid_submission_mode",
                "limitOrderSubmissionMode must be sequential or batch.",
            )
        requested_thresholds: dict[str, Any] | None = None
        if thresholds_supplied:
            requested_thresholds = self._parse_jev_screening_thresholds(
                body.get("jevScreeningThresholds")
            )
            if requested_thresholds is None:
                raise APIError(
                    400, "invalid_jev_screening_thresholds",
                    "jevScreeningThresholds must contain valid values for all three thresholds.",
                )

        _, fingerprint = self._account()
        with self.store.transaction() as connection:
            row = connection.execute(
                "SELECT * FROM strategy_account_preferences WHERE account_fingerprint=?",
                (fingerprint,),
            ).fetchone()
            current = self._settings_from_preference_row(row)
            mode = requested_mode if mode_supplied else current["limitOrderSubmissionMode"]
            thresholds = (
                requested_thresholds
                if thresholds_supplied
                else current["jevScreeningThresholds"]
            )
            connection.execute(
                "INSERT INTO strategy_account_preferences(account_fingerprint, limit_order_submission_mode, "
                "jev_min_structural_quality, jev_min_entry_suitability_probability, "
                "jev_max_failure_risk_probability, updated_at) VALUES (?, ?, ?, ?, ?, ?) "
                "ON CONFLICT(account_fingerprint) DO UPDATE SET "
                "limit_order_submission_mode=excluded.limit_order_submission_mode, "
                "jev_min_structural_quality=excluded.jev_min_structural_quality, "
                "jev_min_entry_suitability_probability=excluded.jev_min_entry_suitability_probability, "
                "jev_max_failure_risk_probability=excluded.jev_max_failure_risk_probability, "
                "updated_at=excluded.updated_at",
                (
                    fingerprint, mode, thresholds["minStructuralQuality"],
                    thresholds["minEntrySuitabilityProbability"],
                    thresholds["maxFailureRiskProbability"], self.clock(),
                ),
            )
        return {
            "limitOrderSubmissionMode": mode,
            "jevScreeningThresholds": thresholds,
        }

    @staticmethod
    def _parse_jev_screening_thresholds(value: Any) -> dict[str, int | float] | None:
        if not isinstance(value, dict) or set(value) != _JEV_SCREENING_THRESHOLD_KEYS:
            return None
        quality = value.get("minStructuralQuality")
        suitability = value.get("minEntrySuitabilityProbability")
        failure_risk = value.get("maxFailureRiskProbability")
        if type(quality) is not int or quality < 0 or quality > 5:
            return None
        probabilities = (suitability, failure_risk)
        if any(
            isinstance(probability, bool)
            or not isinstance(probability, (int, float))
            or probability < 0
            or probability > 1
            or not math.isfinite(probability)
            for probability in probabilities
        ):
            return None
        return {
            "minStructuralQuality": quality,
            "minEntrySuitabilityProbability": float(suitability),
            "maxFailureRiskProbability": float(failure_risk),
        }

    @classmethod
    def _settings_from_preference_row(cls, row: Any) -> dict[str, Any]:
        if row is None:
            return {
                "limitOrderSubmissionMode": "sequential",
                "jevScreeningThresholds": dict(_DEFAULT_JEV_SCREENING_THRESHOLDS),
            }
        mode = row["limit_order_submission_mode"]
        thresholds = cls._parse_jev_screening_thresholds({
            "minStructuralQuality": row["jev_min_structural_quality"],
            "minEntrySuitabilityProbability": row["jev_min_entry_suitability_probability"],
            "maxFailureRiskProbability": row["jev_max_failure_risk_probability"],
        })
        if mode not in ("sequential", "batch") or thresholds is None:
            raise APIError(
                500, "strategy_settings_unavailable",
                "The saved strategy settings are invalid.",
            )
        return {
            "limitOrderSubmissionMode": mode,
            "jevScreeningThresholds": thresholds,
        }

    def _settings_for_fingerprint(self, fingerprint: str) -> dict[str, Any]:
        with self.store.connection() as connection:
            row = connection.execute(
                "SELECT * FROM strategy_account_preferences WHERE account_fingerprint=?",
                (fingerprint,),
            ).fetchone()
        return self._settings_from_preference_row(row)

    def _jev_screening_thresholds(self, fingerprint: str) -> dict[str, Any]:
        return dict(self._settings_for_fingerprint(fingerprint)["jevScreeningThresholds"])

    def _limit_order_submission_mode(self, fingerprint: str) -> str:
        with self.store.connection() as connection:
            row = connection.execute(
                "SELECT limit_order_submission_mode FROM strategy_account_preferences "
                "WHERE account_fingerprint=?",
                (fingerprint,),
            ).fetchone()
        if row is None:
            return "sequential"
        mode = row["limit_order_submission_mode"]
        if mode not in ("sequential", "batch"):
            raise APIError(
                500, "strategy_settings_unavailable",
                "The saved strategy submission preference is invalid.",
            )
        return mode

    def _current_strategy(self, strategy_id: str) -> tuple[dict[str, Any], dict[str, Any], str]:
        if not _STRATEGY_ID.fullmatch(strategy_id):
            raise APIError(404, "strategy_not_found", "The strategy was not found.")
        account, fingerprint = self._account()
        with self.store.connection() as connection:
            row = connection.execute(
                "SELECT * FROM strategies WHERE strategy_id=?", (strategy_id,)
            ).fetchone()
        if row is None:
            raise APIError(404, "strategy_not_found", "The strategy was not found.")
        strategy = self._decode_row(row)
        if not hmac.compare_digest(strategy["accountFingerprint"], fingerprint):
            raise APIError(409, "account_changed", "This strategy belongs to a different OKX account.")
        self._expire_prepare(strategy)
        return strategy, account, fingerprint

    @staticmethod
    def _decode_row(row: Any) -> dict[str, Any]:
        prepared = None if row["prepared_json"] is None else decode_json(row["prepared_json"])
        raw_queue = row["queue_json"]
        queue = None
        queue_corrupt = False
        if raw_queue is not None:
            try:
                queue = normalize_queue(decode_json(raw_queue))
            except (TypeError, ValueError):
                queue = None
            queue_corrupt = queue is None
        batch_attempted = bool(row["batch_attempted"])
        raw_submission_mode = row["submission_mode"] or "batch"
        prepared_mode = prepared.get("submissionMode") if isinstance(prepared, dict) else None
        submission_mode_invalid = prepared_mode is not None and (
            prepared_mode not in ("sequential", "batch")
            or raw_submission_mode not in ("sequential", "batch")
            or raw_submission_mode != prepared_mode
        )
        if prepared is None and row["status"] == "DRAFT" and not bool(row["attempt_started"]):
            submission_mode = None
        elif prepared_mode in ("sequential", "batch"):
            submission_mode = prepared_mode
        else:
            submission_mode = raw_submission_mode if raw_submission_mode in ("sequential", "batch") else "batch"
        return {
            "id": row["strategy_id"],
            "accountFingerprint": row["account_fingerprint"],
            "status": row["status"],
            "contract": decode_json(row["contract_json"]),
            "snapshot": decode_json(row["snapshot_json"]),
            "orders": decode_json(row["orders_json"]),
            "results": decode_json(row["results_json"]),
            "previewHash": row["preview_hash"],
            "confirmationHash": row["confirmation_hash"],
            "preparedExpiresAt": row["prepared_expires_at"],
            "prepared": prepared,
            "attemptStarted": bool(row["attempt_started"]),
            "batchAttempted": batch_attempted,
            "submissionMode": submission_mode,
            "submissionModeInvalid": submission_mode_invalid,
            "orderPlacementAttempted": batch_attempted or bool(row["order_placement_attempted"]),
            "queue": queue,
            "queueCorrupt": queue_corrupt,
            "queueJsonRaw": raw_queue,
            "executionId": row["execution_id"],
            "executionLeaseUntil": row["execution_lease_until"],
            "replacementSourceId": row["replacement_source_id"],
            "leverageResults": decode_json(row["leverage_results_json"]),
            "failureReason": row["failure_reason"],
            "createdAt": row["created_at"],
            "updatedAt": row["updated_at"],
        }

    @staticmethod
    def _all_not_submitted(results: Any) -> bool:
        return (
            isinstance(results, list)
            and bool(results)
            and all(isinstance(row, dict) and row.get("status") == "not_submitted" for row in results)
        )

    @classmethod
    def _legacy_never_sent(cls, strategy: dict[str, Any]) -> bool:
        return (
            strategy["status"] == "COMPLETED"
            and not strategy["orderPlacementAttempted"]
            and cls._all_not_submitted(strategy["results"])
        )

    @staticmethod
    def _replacement_fully_accepted(
        status: str, results: Any, order_placement_attempted: bool
    ) -> bool:
        accepted_states = {
            "accepted", "live", "partially_filled", "filled", "canceled", "mmp_canceled"
        }
        return (
            order_placement_attempted
            and status in {"APPLIED", "COMPLETED"}
            and isinstance(results, list)
            and bool(results)
            and all(
                isinstance(row, dict)
                and row.get("status") in accepted_states
                and isinstance(row.get("exchangeOrderId"), str)
                and bool(row["exchangeOrderId"])
                for row in results
            )
        )

    @classmethod
    def _is_never_sent_record(
        cls, strategy: dict[str, Any], fingerprint: str, now: float
    ) -> bool:
        lease_until = strategy["executionLeaseUntil"]
        return (
            isinstance(strategy["accountFingerprint"], str)
            and hmac.compare_digest(strategy["accountFingerprint"], fingerprint)
            and not strategy["orderPlacementAttempted"]
            and cls._all_not_submitted(strategy["results"])
            and strategy["status"] != "APPLYING"
            and strategy["executionId"] is None
            and (lease_until is None or lease_until <= now)
        )

    @classmethod
    def _eligible_never_sent_record(
        cls,
        connection: Any,
        strategy: dict[str, Any],
        fingerprint: str,
        now: float,
    ) -> bool:
        if not cls._is_never_sent_record(strategy, fingerprint, now):
            return False
        try:
            metadata = _retry_metadata(strategy.get("contract"))
        except RetryDataError:
            return False
        if metadata is not None and strategy.get("attemptStarted"):
            return False
        children, unsafe = cls._retry_children_in_connection(
            connection, fingerprint, strategy["id"], strategy["contract"].get("instrumentId")
        )
        if unsafe or children:
            return False
        active_replacement = connection.execute(
            "SELECT 1 FROM strategies WHERE replacement_source_id=? AND account_fingerprint=? "
            "AND status='APPLYING' LIMIT 1",
            (strategy["id"], fingerprint),
        ).fetchone()
        return active_replacement is None

    @staticmethod
    def _valid_position_rows(rows: Any) -> bool:
        if not isinstance(rows, list):
            return False
        for row in rows:
            if not isinstance(row, dict):
                return False
            instrument_id = row.get("instId")
            side = row.get("posSide")
            if (
                not isinstance(instrument_id, str) or not instrument_id.strip()
                or side not in ("net", "long", "short")
                or _decimal(row.get("pos")) is None
            ):
                return False
        return True

    @classmethod
    def _positions_clear_for_instrument(
        cls, rows: Any, instrument_id: str, scope: StrategyScope
    ) -> bool:
        relevant = scoped_position_rows(rows, instrument_id, scope)
        return relevant is not None and not relevant

    def _terminal_delete_position_rows(self) -> tuple[list[Any] | None, bool]:
        response = self.okx.request(
            "GET", "/api/v5/account/positions", params={"instType": "SWAP"}
        )
        if (
            not isinstance(response, dict)
            or response.get("code") != "0"
            or not isinstance(response.get("data"), list)
        ):
            return None, False
        rows = response["data"]
        return rows, self._valid_position_rows(rows)

    @staticmethod
    def _terminal_delete_order_pairs(
        strategy: dict[str, Any]
    ) -> list[tuple[dict[str, Any], dict[str, Any]]] | None:
        orders = strategy.get("orders")
        results = strategy.get("results")
        if (
            not isinstance(orders, list) or not orders
            or not isinstance(results, list) or len(results) != len(orders)
        ):
            return None

        orders_by_client: dict[str, dict[str, Any]] = {}
        results_by_client: dict[str, dict[str, Any]] = {}
        for order in orders:
            if not isinstance(order, dict):
                return None
            client_id = order.get("clientOrderId")
            size = _positive(order.get("contracts"))
            side = order.get("side")
            if (
                not isinstance(client_id, str) or not client_id.strip()
                or client_id in orders_by_client
                or size is None or side not in ("long", "short")
            ):
                return None
            orders_by_client[client_id] = order
        for result in results:
            if not isinstance(result, dict):
                return None
            client_id = result.get("clientOrderId")
            if (
                not isinstance(client_id, str) or not client_id.strip()
                or client_id in results_by_client
            ):
                return None
            results_by_client[client_id] = result
        if set(orders_by_client) != set(results_by_client):
            return None

        pairs: list[tuple[dict[str, Any], dict[str, Any]]] = []
        for client_id, order in orders_by_client.items():
            result = results_by_client[client_id]
            size = _positive(order.get("contracts"))
            result_size = _positive(result.get("contracts"))
            state = result.get("status")
            if (
                result.get("side") != order.get("side")
                or result_size is None or result_size != size
                or state not in _DELETABLE_ORDER_STATES
            ):
                return None

            placement_state = result.get("placementState")
            exchange_id = result.get("exchangeOrderId")
            if state in _DELETABLE_SUBMITTED_ORDER_STATES:
                filled = _decimal(result.get("filledContracts"))
                if (
                    not isinstance(exchange_id, str) or not exchange_id.strip()
                    or filled is None or filled < 0 or filled > size
                    or placement_state not in (None, "accepted")
                ):
                    return None
            elif state == "rejected":
                code = bounded_error_code(result.get("errorCode"))
                if (
                    code is None or code == "0"
                    or (exchange_id is not None and exchange_id != "")
                    or placement_state not in (None, "rejected")
                ):
                    return None
            else:
                if (
                    placement_state != "not_submitted"
                    or (exchange_id is not None and exchange_id != "")
                ):
                    return None
            pairs.append((order, result))
        return pairs

    @classmethod
    def _eligible_terminal_delete_record(
        cls,
        connection: Any,
        strategy: dict[str, Any],
        fingerprint: str,
        now: float,
    ) -> bool:
        lease_until = strategy.get("executionLeaseUntil")
        if lease_until is not None and (
            isinstance(lease_until, bool)
            or not isinstance(lease_until, (int, float))
            or not math.isfinite(float(lease_until))
            or lease_until > now
        ):
            return False
        contract = strategy.get("contract")
        if (
            not isinstance(strategy.get("accountFingerprint"), str)
            or not hmac.compare_digest(strategy["accountFingerprint"], fingerprint)
            or strategy.get("status") not in {"APPLIED", "PARTIAL", "COMPLETED"}
            or not strategy.get("orderPlacementAttempted")
            or strategy.get("status") == "APPLYING"
            or strategy.get("executionId") is not None
            or strategy.get("submissionModeInvalid")
            or not isinstance(contract, dict)
            or not isinstance(contract.get("instrumentId"), str)
            or not contract["instrumentId"].strip()
            or cls._terminal_delete_order_pairs(strategy) is None
        ):
            return False

        if strategy.get("submissionMode") == "sequential":
            queue = strategy.get("queue")
            if (
                strategy.get("queueCorrupt")
                or not isinstance(queue, dict)
                or queue.get("phase") not in ("stopped", "submitted")
                or queue.get("inFlight") is not None
                or queue.get("totalCount") != len(strategy["orders"])
            ):
                return False
            if any(
                result.get("status") == "not_submitted"
                for result in strategy["results"]
            ) and queue.get("phase") != "stopped":
                return False
        elif (
            strategy.get("submissionMode") != "batch"
            or strategy.get("queueCorrupt")
            or strategy.get("queue") is not None
            or strategy.get("queueJsonRaw") is not None
            or any(result.get("status") == "not_submitted" for result in strategy["results"])
        ):
            return False

        try:
            metadata = _retry_metadata(contract)
        except RetryDataError:
            return False
        if metadata is not None and strategy.get("attemptStarted"):
            return False
        children, unsafe = cls._retry_children_in_connection(
            connection, fingerprint, strategy["id"], contract.get("instrumentId")
        )
        if unsafe or children:
            return False
        active_replacement = connection.execute(
            "SELECT 1 FROM strategies WHERE replacement_source_id=? AND account_fingerprint=? "
            "AND status='APPLYING' LIMIT 1",
            (strategy["id"], fingerprint),
        ).fetchone()
        if active_replacement is not None:
            return False
        reservation = connection.execute(
            "SELECT 1 FROM strategy_reservations WHERE strategy_id=? LIMIT 1",
            (strategy["id"],),
        ).fetchone()
        return reservation is None

    @staticmethod
    def _verified_terminal_order(
        instrument_id: str,
        position_mode: Any,
        order: dict[str, Any],
        result: dict[str, Any],
        details: Any,
    ) -> bool:
        if result.get("status") in {"rejected", "not_submitted"}:
            return True
        if not isinstance(details, dict):
            return False
        client_id = order.get("clientOrderId")
        exchange_id = result.get("exchangeOrderId")
        expected_size = _positive(order.get("contracts"))
        side = order.get("side")
        expected_side = "buy" if side == "long" else "sell" if side == "short" else None
        expected_position_side = (
            side if position_mode == "long_short_mode"
            else "net" if position_mode == "net_mode" else None
        )
        size = _decimal(details.get("sz"))
        filled = _decimal(details.get("accFillSz"))
        state = details.get("state")
        return (
            isinstance(client_id, str) and bool(client_id.strip())
            and isinstance(exchange_id, str) and bool(exchange_id.strip())
            and details.get("instId") == instrument_id
            and details.get("clOrdId") == client_id
            and details.get("ordId") == exchange_id
            and details.get("side") == expected_side
            and details.get("posSide") == expected_position_side
            and expected_size is not None and size == expected_size
            and filled is not None and 0 <= filled <= size
            and isinstance(state, str)
            and state.lower() in _DELETABLE_SUBMITTED_ORDER_STATES
        )

    def _terminal_delete_order_details(
        self, instrument_id: str, client_order_id: str
    ) -> dict[str, Any] | None:
        response = self.okx.request(
            "GET",
            "/api/v5/trade/order",
            params={"instId": instrument_id, "clOrdId": client_order_id},
        )
        if not isinstance(response, dict) or response.get("code") != "0":
            return None
        rows = response.get("data")
        if not isinstance(rows, list) or len(rows) != 1 or not isinstance(rows[0], dict):
            return None
        return rows[0]

    @classmethod
    def _retry_children_in_connection(
        cls, connection: Any, fingerprint: str, source_id: str, instrument_id: Any
    ) -> tuple[list[dict[str, Any]], bool]:
        """Read retry lineage locally after narrowing the scan to one account."""
        rows = connection.execute(
            "SELECT strategy_id, status, attempt_started, contract_json, preview_hash FROM strategies "
            "WHERE account_fingerprint=?",
            (fingerprint,),
        ).fetchall()
        children: list[dict[str, Any]] = []
        unsafe = False
        for row in rows:
            try:
                contract = decode_json(row["contract_json"])
            except (TypeError, ValueError):
                unsafe = True
                continue
            if not isinstance(contract, dict):
                unsafe = True
                continue
            retry_like = contract.get("kind") == "resubmission" or "resubmission" in contract
            if not retry_like:
                continue
            raw_metadata = contract.get("resubmission")
            try:
                metadata = _retry_metadata(contract)
            except RetryDataError:
                same_source = (
                    isinstance(raw_metadata, dict)
                    and raw_metadata.get("sourceStrategyId") == source_id
                )
                if same_source or contract.get("instrumentId") == instrument_id:
                    unsafe = True
                continue
            if metadata is None or metadata.get("sourceStrategyId") != source_id:
                continue
            if contract.get("instrumentId") != instrument_id:
                unsafe = True
                continue
            children.append({
                "id": row["strategy_id"],
                "status": row["status"],
                "attemptStarted": bool(row["attempt_started"]),
                "sourceClientOrderIds": list(metadata["sourceClientOrderIds"]),
                "sourceRevision": metadata["sourceRevision"],
                "sourceSelectionHash": metadata["sourceSelectionHash"],
                "retryRequestId": metadata["retryRequestId"],
                "previewHash": row["preview_hash"],
            })
        return children, unsafe

    @staticmethod
    def _delete_strategy_with_dependents(connection: Any, strategy_id: str) -> None:
        connection.execute("DELETE FROM strategy_reservations WHERE strategy_id=?", (strategy_id,))
        connection.execute("DELETE FROM strategy_sync_state WHERE strategy_id=?", (strategy_id,))
        connection.execute("DELETE FROM strategies WHERE strategy_id=?", (strategy_id,))

    @classmethod
    def _cleanup_replacement_in_connection(
        cls, connection: Any, replacement_id: str, now: float
    ) -> bool:
        replacement_row = connection.execute(
            "SELECT * FROM strategies WHERE strategy_id=?", (replacement_id,)
        ).fetchone()
        if replacement_row is None:
            return False
        replacement = cls._decode_row(replacement_row)
        source_id = replacement["replacementSourceId"]
        if (
            not isinstance(source_id, str)
            or not cls._replacement_fully_accepted(
                replacement["status"], replacement["results"], replacement["orderPlacementAttempted"]
            )
        ):
            return False
        source_row = connection.execute(
            "SELECT * FROM strategies WHERE strategy_id=? AND account_fingerprint=?",
            (source_id, replacement["accountFingerprint"]),
        ).fetchone()
        if source_row is None:
            return False
        source = cls._decode_row(source_row)
        if not cls._eligible_never_sent_record(
            connection, source, replacement["accountFingerprint"], now
        ):
            return False
        cls._delete_strategy_with_dependents(connection, source_id)
        return True

    def _require_eligible_replacement_source(
        self, replacement_source_id: str | None, fingerprint: str
    ) -> None:
        if replacement_source_id is None:
            return
        now = self.clock()
        with self.store.connection() as connection:
            row = connection.execute(
                "SELECT * FROM strategies WHERE strategy_id=? AND account_fingerprint=?",
                (replacement_source_id, fingerprint),
            ).fetchone()
            if row is None or not self._eligible_never_sent_record(
                connection, self._decode_row(row), fingerprint, now
            ):
                raise APIError(
                    409,
                    "replacement_source_unavailable",
                    "The never-sent source is no longer eligible for replacement.",
                )

    @staticmethod
    def _retry_request_error(code: str, message: str, status: int = 409) -> APIError:
        return APIError(status, code, message)

    def _retry_source_context(
        self,
        source_id: str,
        *,
        exclude_child_id: str | None = None,
        reconcile: bool = True,
        account_snapshot: tuple[dict[str, Any], str] | None = None,
    ) -> dict[str, Any]:
        account, fingerprint = self._account(account_snapshot)
        with self.store.connection() as connection:
            row = connection.execute(
                "SELECT * FROM strategies WHERE strategy_id=?", (source_id,)
            ).fetchone()
        if row is None:
            raise APIError(404, "strategy_not_found", "The strategy was not found.")
        source = self._decode_row(row)
        if not hmac.compare_digest(source["accountFingerprint"], fingerprint):
            raise APIError(409, "account_changed", "This strategy belongs to a different OKX account.")
        contract = source.get("contract")
        if not isinstance(contract, dict) or not isinstance(contract.get("instrumentId"), str):
            raise self._retry_request_error(
                "retry_source_unavailable", "The source strategy cannot be retried safely."
            )
        instrument_id = contract["instrumentId"]
        now = self.clock()
        with self.store.connection() as connection:
            current_row = connection.execute(
                "SELECT * FROM strategies WHERE strategy_id=? AND account_fingerprint=?",
                (source_id, fingerprint),
            ).fetchone()
            if current_row is None:
                raise APIError(404, "strategy_not_found", "The strategy was not found.")
            source = self._decode_row(current_row)
            children, unsafe_lineage = self._retry_children_in_connection(
                connection, fingerprint, source_id, instrument_id
            )
            ordinary_replacement = connection.execute(
                "SELECT 1 FROM strategies WHERE replacement_source_id=? AND account_fingerprint=? LIMIT 1",
                (source_id, fingerprint),
            ).fetchone()
            reservations = connection.execute(
                "SELECT strategy_id, position_mode, side_scope FROM strategy_reservations "
                "WHERE account_fingerprint=? AND instrument_id=?",
                (fingerprint, instrument_id),
            ).fetchall()

        revision = _retry_source_revision(source, self.owner.settings.session_signing_key)
        source_scope = self._persisted_scope(source, require_prepared_mode=False)
        blocked: str | None = None
        if source["status"] == "APPLYING":
            blocked = "source_applying"
        elif source["executionLeaseUntil"] is not None and (
            isinstance(source["executionLeaseUntil"], bool)
            or not isinstance(source["executionLeaseUntil"], (int, float))
            or source["executionLeaseUntil"] > now
        ):
            blocked = "source_lease_active"
        elif source["executionId"] is not None:
            blocked = "source_lease_active"
        elif source["status"] not in {"APPLIED", "PARTIAL", "UNKNOWN", "COMPLETED"} or not source["attemptStarted"]:
            blocked = "source_not_attempted"
        elif source.get("submissionModeInvalid") or source.get("queueCorrupt"):
            blocked = "source_evidence_malformed"
        elif not source_scope.valid:
            blocked = "source_evidence_malformed"
        elif unsafe_lineage:
            blocked = "source_lineage_invalid"
        elif ordinary_replacement is not None:
            blocked = "ordinary_replacement_exists"

        try:
            source_pairs = _retry_source_rows(source)
        except RetryDataError:
            source_pairs = []
            blocked = blocked or "source_evidence_malformed"

        if blocked is None and source_pairs:
            reservation_blocks_every_order = all(
                any(
                    reservation["strategy_id"] != exclude_child_id
                    and scopes_overlap(
                        scope_for_sides(source_scope.position_mode, [order["side"]]),
                        reservation_scope(reservation["position_mode"], reservation["side_scope"]),
                    )
                    for reservation in reservations
                )
                for _, order, _ in source_pairs
            )
            if reservation_blocks_every_order:
                blocked = "reservation_active"

        reviewed_source = source
        if reconcile and blocked is None and source_pairs:
            try:
                refreshed, read_error, _ = _read_order_rows(
                    source,
                    self.okx,
                    preserve_last_known=True,
                    max_reads=_MAX_ORDERS,
                    stop_after_failure=True,
                )
            except OKXError:
                refreshed, read_error = source["results"], "exchange_unavailable"
            except Exception:
                refreshed, read_error = source["results"], "exchange_unavailable"
            if read_error is not None:
                blocked = "reconciliation_unavailable"
            else:
                reviewed_source = {**source, "results": refreshed}
                try:
                    source_pairs = _retry_source_rows(reviewed_source)
                except RetryDataError:
                    source_pairs = []
                    blocked = "source_evidence_malformed"

        candidates: list[dict[str, Any]] = []
        if source_pairs:
            for index, order, result in source_pairs:
                prior, reason = _retry_classify_row(reviewed_source, index, order, result)
                row_id = order["clientOrderId"]
                eligible = prior in {"not_submitted", "rejected"} and reason is None
                if blocked is not None:
                    eligible = False
                    reason = blocked
                elif eligible:
                    for child in children:
                        if child["id"] == exclude_child_id:
                            continue
                        if row_id in child["sourceClientOrderIds"]:
                            eligible = False
                            reason = "selection_in_use"
                            break
                if eligible:
                    candidate_scope = scope_for_sides(source_scope.position_mode, [order["side"]])
                    if any(
                        reservation["strategy_id"] != exclude_child_id
                        and scopes_overlap(
                            candidate_scope,
                            reservation_scope(
                                reservation["position_mode"], reservation["side_scope"]
                            ),
                        )
                        for reservation in reservations
                    ):
                        eligible = False
                        reason = "reservation_active"
                public_row: dict[str, Any] = {
                    "sourceClientOrderId": row_id,
                    "side": order["side"],
                    "role": order["role"],
                    "limitPrice": str(order["limitPrice"]),
                    "contracts": str(order["contracts"]),
                    "leverage": order["leverage"],
                    "priorOutcome": prior,
                    "eligible": eligible,
                    "reason": "eligible" if eligible else (reason or "outcome_unknown"),
                }
                if "levelId" in order:
                    public_row["levelId"] = order["levelId"]
                candidates.append(public_row)
        if blocked is None and not any(row["eligible"] for row in candidates):
            blocked = (
                "reservation_active"
                if candidates and all(row["reason"] == "reservation_active" for row in candidates)
                else "no_eligible_rows"
            )
        return {
            "source": source,
            "reviewedSource": reviewed_source,
            "account": account,
            "fingerprint": fingerprint,
            "instrumentId": instrument_id,
            "sourceRevision": revision,
            "children": children,
            "blockedReason": blocked,
            "candidates": candidates,
            "sourcePairs": source_pairs,
        }

    def _retry_selection(
        self,
        context: dict[str, Any],
        requested_revision: str,
        selected_ids: Any,
        *,
        exclude_child_id: str | None = None,
    ) -> tuple[list[tuple[int, dict[str, Any], dict[str, Any]]], str, list[str]]:
        if not hmac.compare_digest(context["sourceRevision"], requested_revision):
            raise self._retry_request_error(
                "retry_source_stale", "The source changed; refresh retry candidates and review again."
            )
        if context["blockedReason"] not in (None, "no_eligible_rows"):
            raise self._retry_request_error(
                "retry_source_unavailable", "The source is currently blocked from resubmission."
            )
        try:
            selected = _retry_ordered_selection(context["source"], selected_ids)
        except RetryDataError:
            raise self._retry_request_error(
                "retry_selection_invalid", "Choose one through ten unique eligible source orders.", 422
            ) from None
        eligible_by_id = {row["sourceClientOrderId"]: row for row in context["candidates"]}
        selected_source_ids = _retry_ordered_ids(selected)
        for source_client_id in selected_source_ids:
            candidate = eligible_by_id.get(source_client_id)
            if candidate is None or not candidate["eligible"]:
                reason = None if candidate is None else candidate.get("reason")
                if reason == "selection_in_use":
                    raise self._retry_request_error(
                        "retry_selection_in_use", "One or more selected source orders are already in another retry."
                    )
                if reason == "reservation_active":
                    raise self._retry_request_error(
                        "retry_source_unavailable", "A selected position side is reserved by another strategy."
                    )
                raise self._retry_request_error(
                    "retry_selection_invalid", "One or more selected source orders are not safely retryable.", 422
                )
        digest = _retry_selection_hash(
            context["source"], selected, context["sourceRevision"],
            self.owner.settings.session_signing_key,
        )
        return selected, digest, selected_source_ids

    def _validate_retry_source_in_connection(
        self,
        connection: Any,
        *,
        fingerprint: str,
        source_id: str,
        instrument_id: str,
        source_revision: str,
        source_selection_hash: str,
        selected_ids: list[str],
        exclude_child_id: str | None,
        now: float,
        child_orders: list[dict[str, Any]] | None = None,
        prepared_orders: list[dict[str, Any]] | None = None,
    ) -> tuple[dict[str, Any], list[tuple[int, dict[str, Any], dict[str, Any]]]]:
        row = connection.execute(
            "SELECT * FROM strategies WHERE strategy_id=? AND account_fingerprint=?",
            (source_id, fingerprint),
        ).fetchone()
        if row is None:
            raise self._retry_request_error(
                "retry_source_unavailable", "The source strategy is no longer available."
            )
        source = self._decode_row(row)
        contract = source.get("contract")
        if not isinstance(contract, dict) or contract.get("instrumentId") != instrument_id:
            raise self._retry_request_error(
                "retry_source_stale", "The source changed; refresh retry candidates and review again."
            )
        if source["status"] == "APPLYING":
            raise self._retry_request_error(
                "retry_source_unavailable", "The source is currently being applied or reconciled."
            )
        lease_until = source.get("executionLeaseUntil")
        if (
            source.get("executionId") is not None
            or (lease_until is not None and (
                isinstance(lease_until, bool) or not isinstance(lease_until, (int, float)) or lease_until > now
            ))
        ):
            raise self._retry_request_error(
                "retry_source_unavailable", "The source is currently being applied or reconciled."
            )
        if source["status"] not in {"APPLIED", "PARTIAL", "UNKNOWN", "COMPLETED"} or not source["attemptStarted"]:
            raise self._retry_request_error(
                "retry_source_unavailable", "Only a previously attempted strategy can supply retry orders."
            )
        if source.get("submissionModeInvalid") or source.get("queueCorrupt"):
            raise self._retry_request_error(
                "retry_source_unavailable", "The source history cannot be validated safely."
            )

        current_revision = _retry_source_revision(source, self.owner.settings.session_signing_key)
        if not hmac.compare_digest(current_revision, source_revision):
            raise self._retry_request_error(
                "retry_source_stale", "The source changed; refresh retry candidates and review again."
            )
        try:
            selected = _retry_ordered_selection(source, selected_ids)
        except RetryDataError:
            raise self._retry_request_error(
                "retry_selection_invalid", "The source rows cannot be validated safely.", 422
            ) from None
        selected_order_ids = _retry_ordered_ids(selected)
        if selected_order_ids != selected_ids:
            raise self._retry_request_error(
                "retry_source_stale", "The selected source rows changed order; refresh retry review."
            )

        children, unsafe_lineage = self._retry_children_in_connection(
            connection, fingerprint, source_id, instrument_id
        )
        ordinary_replacement = connection.execute(
            "SELECT 1 FROM strategies WHERE replacement_source_id=? AND account_fingerprint=? LIMIT 1",
            (source_id, fingerprint),
        ).fetchone()
        reservations = connection.execute(
            "SELECT strategy_id, position_mode, side_scope FROM strategy_reservations "
            "WHERE account_fingerprint=? AND instrument_id=?",
            (fingerprint, instrument_id),
        ).fetchall()
        source_scope = self._persisted_scope(source, require_prepared_mode=False)
        if unsafe_lineage or ordinary_replacement is not None or not source_scope.valid:
            raise self._retry_request_error(
                "retry_source_unavailable", "The source is blocked by another strategy attempt."
            )
        if any(
            item["strategy_id"] != exclude_child_id
            and scopes_overlap(
                scope_for_sides(source_scope.position_mode, [order["side"]]),
                reservation_scope(item["position_mode"], item["side_scope"]),
            )
            for _, order, _ in selected
            for item in reservations
        ):
            raise self._retry_request_error(
                "retry_source_unavailable", "A selected position side is reserved by another strategy."
            )
        for index, order, result in selected:
            prior, reason = _retry_classify_row(source, index, order, result)
            if prior not in {"not_submitted", "rejected"} or reason is not None:
                raise self._retry_request_error(
                    "retry_selection_invalid", "One or more selected source orders are not safely retryable.", 422
                )
            for child in children:
                if child["id"] != exclude_child_id and order["clientOrderId"] in child["sourceClientOrderIds"]:
                    raise self._retry_request_error(
                        "retry_selection_in_use", "One or more selected source orders are already in another retry."
                    )

        actual_selection_hash = _retry_selection_hash(
            source, selected, current_revision, self.owner.settings.session_signing_key
        )
        if not hmac.compare_digest(actual_selection_hash, source_selection_hash):
            raise self._retry_request_error(
                "retry_source_stale", "The selected source evidence changed; refresh retry review."
            )

        if child_orders is not None:
            if len(child_orders) != len(selected):
                raise self._retry_request_error(
                    "retry_source_stale", "The retry child rows no longer match their source."
                )
            by_source = {
                item.get("sourceClientOrderId"): item
                for item in child_orders if isinstance(item, dict)
            }
            if len(by_source) != len(selected):
                raise self._retry_request_error(
                    "retry_source_stale", "The retry child rows no longer match their source."
                )
            child_client_ids: set[str] = set()
            for _, source_order, _ in selected:
                child_order = by_source.get(source_order["clientOrderId"])
                if not isinstance(child_order, dict):
                    raise self._retry_request_error(
                        "retry_source_stale", "The retry child rows no longer match their source."
                    )
                child_id = child_order.get("clientOrderId")
                if (
                    not isinstance(child_id, str) or not re.fullmatch(r"[A-Za-z0-9_-]{8,64}", child_id)
                    or child_id == source_order["clientOrderId"] or child_id in child_client_ids
                ):
                    raise self._retry_request_error(
                        "retry_source_stale", "The retry child client IDs are invalid."
                    )
                child_client_ids.add(child_id)
                for key in ("side", "role", "limitPrice", "contracts", "leverage", "levelId"):
                    if child_order.get(key) != source_order.get(key):
                        raise self._retry_request_error(
                            "retry_source_stale", "The retry child financial rows changed."
                        )
            if prepared_orders is not None:
                if len(prepared_orders) != len(child_orders) or prepared_orders != child_orders:
                    raise self._retry_request_error(
                        "retry_source_stale", "The prepared retry rows no longer match their draft."
                    )
        return source, selected

    def _retry_market_preview(
        self,
        context: dict[str, Any],
        selected: list[tuple[int, dict[str, Any], dict[str, Any]]],
        selection_digest: str,
    ) -> dict[str, Any]:
        contract = context["source"]["contract"]
        interval = contract.get("interval")
        if interval not in _INTERVALS:
            raise self._retry_request_error(
                "retry_source_unavailable", "The source strategy cannot be retried safely."
            )
        market_account, fingerprint, meta, maker_fee, tiers = self._load_market_inputs(
            {"instrumentId": context["instrumentId"]},
            account_snapshot=(context["account"], context["fingerprint"]),
        )
        if not hmac.compare_digest(context["fingerprint"], fingerprint):
            raise APIError(409, "account_changed", "The active OKX account changed; refresh retry review.")
        try:
            return _fixed_retry_preview(
                source_id=context["source"]["id"],
                source_revision_value=context["sourceRevision"],
                selection_hash_value=selection_digest,
                selected=selected,
                instrument_id=context["instrumentId"],
                interval=interval,
                current_price=meta["last"],
                quote_timestamp_ms=meta["quoteTimestamp"],
                contract_value=meta["contractValue"],
                contract_multiplier=meta["contractMultiplier"],
                tick_size=meta["tickSize"],
                lot_size=meta["lotSize"],
                minimum_size=meta["minimumSize"],
                maker_fee=meta["makerFee"],
                taker_fee=meta["takerFee"],
                tiers=tiers,
                account_fingerprint=fingerprint,
                position_mode=market_account.get("posMode"),
                signing_key=self.owner.settings.session_signing_key,
            )
        except RetryDataError as exc:
            raise self._retry_request_error(
                "retry_selection_invalid",
                "An exact source order is incompatible with current market rules or quote.",
                422,
            ) from exc

    def _retry_review_guards(
        self, context: dict[str, Any], preview: dict[str, Any]
    ) -> None:
        mode = preview.get("_internal", {}).get("positionMode")
        sides = preview.get("sides")
        scope = scope_for_sides(mode, sides)
        if not scope.valid:
            raise APIError(409, "retry_source_unavailable", "The retry orders cannot be validated safely.")
        if len(set(sides)) == 2 and mode != "long_short_mode":
            raise APIError(
                409, "account_mode_unsupported",
                "Two-sided strategies require OKX Hedge mode. Change the account mode manually and retry review.",
            )
        if mode not in ("net_mode", "long_short_mode") or context["account"].get("posMode") != mode:
            raise APIError(409, "account_mode_unsupported", "The current OKX position mode is unsupported.")

        instrument_id = context["instrumentId"]
        try:
            positions = self.okx.positions("SWAP")
            pending = self.okx.pending_orders(instrument_id)
        except OKXError as exc:
            raise self._read_failure(
                exc,
                fallback_code="account_preflight_unavailable",
                fallback_message="Current positions or pending orders are unavailable.",
            ) from None
        relevant_positions = scoped_position_rows(positions, instrument_id, scope)
        if relevant_positions is None or relevant_positions:
            raise APIError(
                409, "instrument_position_exists",
                "Close the overlapping position for this SWAP before reviewing a retry.",
            )
        conflicting_pending = scoped_pending_rows(pending, instrument_id, scope)
        if conflicting_pending is None or conflicting_pending:
            raise APIError(
                409, "pending_order_exists", "Cancel overlapping pending orders for this SWAP before reviewing a retry."
            )
        with self.store.connection() as connection:
            reservation = self._has_overlapping_reservation(
                connection, context["fingerprint"], instrument_id, scope
            )
        if reservation:
            raise APIError(
                409, "instrument_apply_in_progress",
                "Another strategy is applying or reconciling an overlapping position scope.",
            )

        try:
            balance_rows = self.okx.account_balance()
        except OKXError as exc:
            raise self._read_failure(
                exc,
                fallback_code="account_preflight_unavailable",
                fallback_message="Available USDT balance is unavailable.",
            ) from None
        available = self._available_usdt(balance_rows)
        if available is None:
            raise APIError(502, "account_preflight_unavailable", "Available USDT balance is unavailable.")
        required = Decimal(preview["totalMargin"]) + Decimal(preview["estimatedOpeningFees"] or "0")
        if available < required:
            raise APIError(
                422, "insufficient_balance", "Available USDT does not cover the retry margin and estimated fees.",
                details={"required": _text(required), "available": _text(available)},
            )

    @staticmethod
    def _public_retry_summary(contract: Any) -> dict[str, Any] | None:
        try:
            metadata = _retry_metadata(contract)
        except RetryDataError:
            return None
        if metadata is None:
            return None
        return {
            "sourceStrategyId": metadata["sourceStrategyId"],
            "sourceClientOrderIds": list(metadata["sourceClientOrderIds"]),
        }

    def _retry_candidates(self, source_id: str) -> dict[str, Any]:
        context = self._retry_source_context(source_id)
        self.automatic.assert_not_candidate(context["source"])
        diagnostics.emit_event(
            "selection", component="api", stage="retry_candidates", outcome="selected",
            selected_count=len(context["candidates"]),
            eligible_count=sum(row["eligible"] for row in context["candidates"]),
            matching_eligible_count=sum(row["eligible"] for row in context["candidates"]),
        )
        return {
            "sourceStrategyId": source_id,
            "sourceRevision": context["sourceRevision"],
            "candidates": context["candidates"],
            "blockedReason": context["blockedReason"],
            "linkedChildren": [
                {
                    "strategyId": child["id"],
                    "status": child["status"],
                    "sourceClientOrderIds": child["sourceClientOrderIds"],
                }
                for child in context["children"]
            ],
        }

    def _retry_preview(self, source_id: str, body: dict[str, Any]) -> dict[str, Any]:
        if set(body) != {"sourceRevision", "sourceClientOrderIds"}:
            raise APIError(400, "invalid_request", "The retry preview request is invalid.")
        revision = body.get("sourceRevision")
        if not isinstance(revision, str) or re.fullmatch(r"[0-9a-f]{64}", revision) is None:
            raise self._retry_request_error(
                "retry_selection_invalid", "The retry preview request is invalid.", 422
            )
        context = self._retry_source_context(source_id)
        self.automatic.assert_not_candidate(context["source"])
        selected, selection_digest, ids = self._retry_selection(
            context, revision, body.get("sourceClientOrderIds")
        )
        preview = self._retry_market_preview(context, selected, selection_digest)
        self._retry_review_guards(context, preview)
        diagnostics.emit_event(
            "selection", component="api", stage="retry_preview", outcome="success",
            selected_count=len(ids), eligible_count=len(context["candidates"]),
            matching_eligible_count=len(ids), order_count=len(ids),
        )
        return self._public_preview(preview)

    @staticmethod
    def _retry_child_contract(
        source: dict[str, Any],
        selected: list[tuple[int, dict[str, Any], dict[str, Any]]],
        preview: dict[str, Any],
        metadata: dict[str, Any],
    ) -> dict[str, Any]:
        selected_levels: list[dict[str, Any]] = []
        entry_by_side: dict[str, str] = {}
        leverage: dict[str, int] = {}
        for _, order, _ in selected:
            level: dict[str, Any] = {"side": order["side"], "price": str(order["limitPrice"])}
            if "levelId" in order:
                level["levelId"] = order["levelId"]
            selected_levels.append(level)
            leverage.setdefault(order["side"], order["leverage"])
            if order["role"] == "entry":
                if order["side"] in entry_by_side:
                    raise RetryDataError()
                entry_by_side[order["side"]] = str(order["limitPrice"])
        sides = list(leverage)
        return {
            "instrumentId": source["contract"]["instrumentId"],
            "interval": source["contract"]["interval"],
            "direction": "both" if len(sides) == 2 else sides[0],
            "selectedLevels": selected_levels,
            "entryBySide": entry_by_side,
            "totalMargin": preview["plannedMargin"],
            "leverage": leverage,
            "sidePercent": preview["sidePercent"],
            "allocation": "fixed",
            "kind": "resubmission",
            "resubmission": metadata,
        }

    @staticmethod
    def _retry_child_orders(
        preview: dict[str, Any], selected: list[tuple[int, dict[str, Any], dict[str, Any]]]
    ) -> list[dict[str, Any]]:
        ids = _retry_ordered_ids(selected)
        rows_by_source = {
            row["sourceClientOrderId"]: row for row in preview["orders"]
        }
        result: list[dict[str, Any]] = []
        if len(rows_by_source) != len(ids):
            raise RetryDataError()
        for source_client_id in ids:
            row = dict(rows_by_source[source_client_id])
            row["clientOrderId"] = "st" + secrets.token_hex(14)
            result.append(row)
        return result

    def _find_retry_request(
        self, children: list[dict[str, Any]], request_id: str
    ) -> dict[str, Any] | None:
        matches = [child for child in children if child["retryRequestId"] == request_id]
        if len(matches) > 1:
            raise self._retry_request_error(
                "retry_request_conflict", "The retry request ID is already bound to conflicting attempts."
            )
        return matches[0] if matches else None

    def _retry_replay(
        self,
        child: dict[str, Any],
        *,
        selected_ids: list[str],
        revision: str,
        preview_hash: str,
    ) -> str:
        if (
            child["sourceClientOrderIds"] != selected_ids
            or not hmac.compare_digest(child["sourceRevision"], revision)
        ):
            raise self._retry_request_error(
                "retry_request_conflict", "This retry request ID is bound to another source selection."
            )
        if not isinstance(child.get("previewHash"), str) or not hmac.compare_digest(child["previewHash"], preview_hash):
            raise self._retry_request_error(
                "retry_request_conflict", "This retry request ID is bound to another reviewed preview."
            )
        return child["id"]

    def _retry_draft_response(self, strategy_id: str) -> dict[str, Any]:
        strategy = self._load_row(strategy_id)
        response = self._basic_result(strategy)
        response["preview"] = self._public_preview(strategy["snapshot"])
        return response

    def _retry_draft(self, source_id: str, body: dict[str, Any]) -> dict[str, Any]:
        expected_keys = {"sourceRevision", "sourceClientOrderIds", "previewHash", "retryRequestId"}
        if set(body) != expected_keys:
            raise APIError(400, "invalid_request", "The retry draft request is invalid.")
        revision = body.get("sourceRevision")
        preview_hash = body.get("previewHash")
        request_id = body.get("retryRequestId")
        selected_ids = body.get("sourceClientOrderIds")
        if (
            not isinstance(revision, str) or re.fullmatch(r"[0-9a-f]{64}", revision) is None
            or not isinstance(preview_hash, str) or re.fullmatch(r"[0-9a-f]{64}", preview_hash) is None
            or not isinstance(request_id, str) or re.fullmatch(r"[A-Za-z0-9_-]{16,64}", request_id) is None
            or not isinstance(selected_ids, list) or not 1 <= len(selected_ids) <= _MAX_NEW_ORDERS
            or any(not isinstance(value, str) or re.fullmatch(r"[A-Za-z0-9_-]{8,64}", value) is None for value in selected_ids)
            or len(set(selected_ids)) != len(selected_ids)
        ):
            raise self._retry_request_error(
                "retry_selection_invalid", "The retry draft request is invalid.", 422
            )

        # Replay lookup is intentionally before market reads, preview minting, or source writes.
        context = self._retry_source_context(source_id, reconcile=False)
        self.automatic.assert_not_candidate(context["source"])
        existing = self._find_retry_request(context["children"], request_id)
        if existing is not None:
            replay_id = self._retry_replay(
                existing, selected_ids=selected_ids, revision=revision, preview_hash=preview_hash
            )
            return self._retry_draft_response(replay_id)

        context = self._retry_source_context(
            source_id,
            reconcile=True,
            account_snapshot=(context["account"], context["fingerprint"]),
        )
        selected, selection_digest, normalized_ids = self._retry_selection(
            context, revision, selected_ids
        )
        preview = self._retry_market_preview(context, selected, selection_digest)
        self._retry_review_guards(context, preview)
        if not hmac.compare_digest(preview["previewHash"], preview_hash):
            raise APIError(
                409,
                "retry_preview_stale",
                "The fixed-order preview changed; review the latest preview before saving.",
                details={"preview": self._public_preview(preview)},
            )
        metadata = {
            "sourceStrategyId": source_id,
            "sourceClientOrderIds": normalized_ids,
            "sourceRevision": revision,
            "sourceSelectionHash": selection_digest,
            "retryRequestId": request_id,
        }
        contract = self._retry_child_contract(context["source"], selected, preview, metadata)
        child_orders = self._retry_child_orders(preview, selected)
        snapshot = self._public_preview(preview)
        snapshot["orders"] = child_orders
        snapshot["_metadata"] = preview["_internal"]["metadata"]
        snapshot["_positionMode"] = preview["_internal"]["positionMode"]
        now = self.clock()
        strategy_id = new_operation_id()
        replay_id: str | None = None
        with self.store.transaction() as connection:
            children, _ = self._retry_children_in_connection(
                connection, context["fingerprint"], source_id, context["instrumentId"]
            )
            existing = self._find_retry_request(children, request_id)
            if existing is not None:
                replay_id = self._retry_replay(
                    existing,
                    selected_ids=normalized_ids,
                    revision=revision,
                    preview_hash=preview_hash,
                )
            else:
                self._validate_retry_source_in_connection(
                    connection,
                    fingerprint=context["fingerprint"],
                    source_id=source_id,
                    instrument_id=context["instrumentId"],
                    source_revision=revision,
                    source_selection_hash=selection_digest,
                    selected_ids=normalized_ids,
                    exclude_child_id=None,
                    now=now,
                )
                connection.execute(
                    "INSERT INTO strategies(strategy_id, account_fingerprint, status, contract_json, snapshot_json, "
                    "orders_json, results_json, preview_hash, replacement_source_id, submission_mode, created_at, updated_at) "
                    "VALUES (?, ?, 'DRAFT', ?, ?, ?, ?, ?, NULL, NULL, ?, ?)",
                    (
                        strategy_id,
                        context["fingerprint"],
                        encode_json(contract),
                        encode_json(snapshot),
                        encode_json(child_orders),
                        encode_json([{**row, "status": "not_submitted", "filledContracts": "0"} for row in child_orders]),
                        preview["previewHash"],
                        now,
                        now,
                    ),
                )
        if replay_id is not None:
            return self._retry_draft_response(replay_id)
        response = self._retry_draft_response(strategy_id)
        response["preview"] = self._public_preview(snapshot)
        diagnostics.emit_event(
            "selection", component="api", stage="retry_draft", outcome="success",
            selected_count=len(normalized_ids), eligible_count=len(context["candidates"]),
            matching_eligible_count=len(normalized_ids), order_count=len(normalized_ids), persisted=True,
        )
        return response

    def _expire_prepare(self, strategy: dict[str, Any]) -> None:
        if strategy["status"] != "PREPARED" or strategy["preparedExpiresAt"] is None:
            return
        if strategy["preparedExpiresAt"] > self.clock():
            return
        with self.store.transaction() as connection:
            connection.execute(
                "UPDATE strategies SET status='DRAFT', confirmation_hash=NULL, prepared_expires_at=NULL, "
                "prepared_json=NULL, updated_at=? WHERE strategy_id=? AND status='PREPARED' "
                "AND prepared_expires_at<=? AND attempt_started=0",
                (self.clock(), strategy["id"], self.clock()),
            )
        strategy["status"] = "DRAFT"
        strategy["confirmationHash"] = None
        strategy["preparedExpiresAt"] = None
        strategy["prepared"] = None
        strategy["updatedAt"] = self.clock()

    def _normalize_contract(self, body: dict[str, Any]) -> dict[str, Any]:
        if any(
            key in body
            for key in (
                "kind", "resubmission", "sourceStrategyId", "sourceClientOrderIds",
                "sourceRevision", "sourceSelectionHash", "retryRequestId",
            )
        ):
            raise self._invalid("invalid_retry_contract", "Retry lineage is server managed.")
        instrument_id = body.get("instrumentId")
        if not isinstance(instrument_id, str) or re.fullmatch(r"[A-Z0-9]+-USDT-SWAP", instrument_id) is None:
            raise self._invalid("invalid_instrument", "Choose one USDT linear SWAP instrument.")
        interval = body.get("interval")
        if interval not in _INTERVALS:
            raise self._invalid("invalid_interval", "Choose a supported UTC candle interval.")
        total_margin = _positive(body.get("totalMargin"))
        if total_margin is None:
            raise self._invalid("invalid_budget", "Total margin must be a positive decimal amount.")

        levels_value = body.get("selectedLevels")
        if not isinstance(levels_value, list) or not levels_value or len(levels_value) > _MAX_NEW_ORDERS:
            raise self._invalid("invalid_order_count", "Select between one and ten combined levels.")
        id_mode = (
            "direction" in body
            or "entryLevelIdBySide" in body
            or any(isinstance(row, dict) and "levelId" in row for row in levels_value)
        )
        levels: list[dict[str, str]] = []
        seen: set[tuple[str, str]] = set()
        seen_ids: set[str] = set()
        for row in levels_value:
            if not isinstance(row, dict) or row.get("side") not in ("long", "short"):
                raise self._invalid("invalid_level", "Each selected level must have a Long or Short side.")
            price = _positive(row.get("price"))
            if price is None:
                raise self._invalid("invalid_level", "Selected level prices must be positive decimals.")
            key = (row["side"], _text(price) or "0")
            if id_mode:
                level_id = row.get("levelId")
                if not isinstance(level_id, str) or re.fullmatch(r"[A-Za-z0-9_-]{1,128}", level_id) is None:
                    raise self._invalid("invalid_level_id", "Each selected level needs a valid bounded ID.")
                if level_id in seen_ids:
                    raise self._invalid("duplicate_level_id", "Selected level IDs must be unique.")
                seen_ids.add(level_id)
                levels.append({"side": row["side"], "price": key[1], "levelId": level_id})
            else:
                if key in seen:
                    raise self._invalid("duplicate_level", "A strategy cannot contain duplicate levels.")
                seen.add(key)
                levels.append({"side": row["side"], "price": key[1]})
        sides = sorted({row["side"] for row in levels}, key=lambda side: (side != "long", side))

        entries: dict[str, str] = {}
        entry_ids: dict[str, str] = {}
        if id_mode:
            direction = body.get("direction")
            if direction not in ("long", "short", "both"):
                raise self._invalid("invalid_direction", "Direction must be long, short, or both.")
            expected_sides = {"long"} if direction == "long" else {"short"} if direction == "short" else {"long", "short"}
            if set(sides) != expected_sides:
                raise self._invalid("direction_mismatch", "Direction must match the submitted Long and Short levels.")

            entry_ids_value = body.get("entryLevelIdBySide")
            if not isinstance(entry_ids_value, dict) or set(entry_ids_value) != set(sides):
                raise self._invalid("entry_id_required", "Choose one entry level ID for every selected side.")
            levels_by_id = {row["levelId"]: row for row in levels}
            for side in sides:
                entry_id = entry_ids_value.get(side)
                if not isinstance(entry_id, str) or entry_id not in levels_by_id or levels_by_id[entry_id]["side"] != side:
                    raise self._invalid("entry_id_required", "The entry ID must identify a selected level on its side.")
                entry_ids[side] = entry_id
                entries[side] = levels_by_id[entry_id]["price"]

            if "entryBySide" in body:
                entries_value = body.get("entryBySide")
                if not isinstance(entries_value, dict) or set(entries_value) != set(sides):
                    raise self._invalid("entry_id_price_mismatch", "Legacy entry prices must match the selected entry IDs.")
                for side in sides:
                    entry = _positive(entries_value.get(side))
                    if entry is None or (_text(entry) or "0") != entries[side]:
                        raise self._invalid("entry_id_price_mismatch", "Legacy entry prices must match the selected entry IDs.")
        else:
            entries_value = body.get("entryBySide")
            if not isinstance(entries_value, dict) or set(entries_value) != set(sides):
                raise self._invalid("entry_required", "Choose one nearest entry level for every selected side.")
            for side in sides:
                entry = _positive(entries_value.get(side))
                if entry is None or (side, _text(entry) or "0") not in seen:
                    raise self._invalid("entry_required", "The entry level must be one of the selected levels.")
                entries[side] = _text(entry) or "0"

        leverage_value = body.get("leverage")
        if not isinstance(leverage_value, dict) or set(leverage_value) != set(sides):
            raise self._invalid("invalid_leverage", "Set leverage for every selected side.")
        leverage: dict[str, int] = {}
        for side in sides:
            value = leverage_value.get(side)
            if isinstance(value, bool) or not str(value).isdigit() or not 1 <= int(value) <= 10:
                raise self._invalid("invalid_leverage", "Side leverage must be an integer from 1 through 10.")
            leverage[side] = int(value)

        percentages_value = body.get("sidePercent")
        if percentages_value is None:
            percentages_value = {side: ("50" if len(sides) == 2 else "100") for side in sides}
        if not isinstance(percentages_value, dict) or set(percentages_value) != set(sides):
            raise self._invalid("invalid_side_split", "Set the margin percentage for every selected side.")
        percentages: dict[str, str] = {}
        for side in sides:
            value = _decimal(percentages_value.get(side))
            if value is None or value <= 0 or value > 100:
                raise self._invalid("invalid_side_split", "Each selected side needs a positive margin percentage.")
            percentages[side] = _text(value) or "0"
        if sum((Decimal(value) for value in percentages.values()), Decimal(0)) != Decimal(100):
            raise self._invalid("invalid_side_split", "Side margin percentages must sum to 100.")

        allocation = body.get("allocation", "equal")
        if allocation not in ("equal", "increasing", "decreasing"):
            raise self._invalid("invalid_allocation", "Choose equal, increasing, or decreasing allocation.")
        if id_mode:
            normalized_levels = sorted(
                levels,
                key=lambda row: (
                    sides.index(row["side"]),
                    Decimal(row["price"]),
                    row["levelId"],
                ),
            )
            return {
                "instrumentId": instrument_id,
                "interval": interval,
                "direction": direction,
                "selectedLevels": normalized_levels,
                "entryLevelIdBySide": entry_ids,
                "entryBySide": entries,
                "totalMargin": _text(total_margin) or "0",
                "leverage": leverage,
                "sidePercent": percentages,
                "allocation": allocation,
            }
        return {
            "instrumentId": instrument_id,
            "interval": interval,
            "selectedLevels": sorted(levels, key=lambda row: (sides.index(row["side"]), Decimal(row["price"]))),
            "entryBySide": entries,
            "totalMargin": _text(total_margin) or "0",
            "leverage": leverage,
            "sidePercent": percentages,
            "allocation": allocation,
        }

    def _ensure_new_order_cap(self, strategy: dict[str, Any]) -> None:
        contract = strategy.get("contract")
        levels = contract.get("selectedLevels") if isinstance(contract, dict) else None
        if not isinstance(levels, list) or not levels or len(levels) > _MAX_NEW_ORDERS:
            raise self._invalid("invalid_order_count", "Select between one and ten combined levels.")

        orders = strategy.get("orders")
        if isinstance(orders, list) and len(orders) > _MAX_NEW_ORDERS:
            raise self._invalid("invalid_order_count", "Select between one and ten combined levels.")

        prepared = strategy.get("prepared")
        prepared_orders = prepared.get("orders") if isinstance(prepared, dict) else None
        if isinstance(prepared_orders, list) and len(prepared_orders) > _MAX_NEW_ORDERS:
            raise self._invalid("invalid_order_count", "Select between one and ten combined levels.")

    def _ensure_persisted_new_order_cap(self, connection: Any, strategy: dict[str, Any]) -> None:
        row = connection.execute(
            "SELECT * FROM strategies WHERE strategy_id=? AND account_fingerprint=?",
            (strategy["id"], strategy["accountFingerprint"]),
        ).fetchone()
        if row is None:
            return
        persisted = self._decode_row(row)
        if persisted["status"] == "PREPARED" and not persisted["attemptStarted"]:
            self._ensure_new_order_cap(persisted)

    def _load_market_inputs(
        self,
        contract: dict[str, Any],
        *,
        account_snapshot: tuple[dict[str, Any], str] | None = None,
    ) -> tuple[dict[str, Any], str, dict[str, Decimal], Decimal, list[dict[str, Decimal]]]:
        account, fingerprint = self._account(
            account_snapshot,
            fallback_code="preview_inputs_unavailable",
            fallback_message="Current quote, contract, maintenance-tier, or fee data is unavailable.",
        )
        try:
            instrument_rows = self.okx.instruments("SWAP")
            ticker = self.okx.ticker(contract["instrumentId"])
            family = contract["instrumentId"][: -len("-SWAP")]
            fee = self.okx.trade_fee(family)
            tier_rows = self.okx.position_tiers(family)
        except OKXError as exc:
            raise self._read_failure(
                exc,
                fallback_code="preview_inputs_unavailable",
                fallback_message="Current quote, contract, maintenance-tier, or fee data is unavailable.",
            ) from None
        instrument = next(
            (row for row in instrument_rows if row.get("instId") == contract["instrumentId"]), None
        )
        if not isinstance(instrument, dict):
            raise self._invalid("instrument_unavailable", "The selected USDT SWAP instrument is unavailable.")
        if (
            instrument.get("instType") != "SWAP"
            or instrument.get("state") != "live"
            or instrument.get("instFamily") != family
        ):
            raise APIError(
                502, "preview_inputs_unavailable",
                "The selected instrument is not a live member of the requested USDT SWAP family.",
            )
        instrument_group_id = instrument.get("groupId")
        if not isinstance(instrument_group_id, str) or not instrument_group_id.strip():
            raise APIError(502, "preview_inputs_unavailable", "The selected instrument's fee group is invalid.")
        base = contract["instrumentId"].split("-", 1)[0]
        instrument_base = instrument.get("baseCcy")
        instrument_quote = instrument.get("quoteCcy")
        base_matches = instrument_base is None or (
            isinstance(instrument_base, str)
            and (not instrument_base.strip() or instrument_base == base)
        )
        quote_matches = instrument_quote is None or (
            isinstance(instrument_quote, str)
            and (not instrument_quote.strip() or instrument_quote == "USDT")
        )
        contract_value = _positive(instrument.get("ctVal"))
        contract_multiplier = _positive(instrument.get("ctMult"))
        tick_size = _positive(instrument.get("tickSz"))
        lot_size = _positive(instrument.get("lotSz"))
        minimum_size = _positive(instrument.get("minSz"))
        if (
            instrument.get("ctType") != "linear"
            or not base_matches or not quote_matches
            or instrument.get("settleCcy") != "USDT"
            or instrument.get("ctValCcy") != base
            or contract_value is None or contract_multiplier is None
            or tick_size is None or lot_size is None or minimum_size is None
        ):
            raise APIError(
                502, "preview_inputs_unavailable",
                "The selected contract is not a validated linear USDT-settled SWAP.",
            )

        last = _positive(ticker.get("last"))
        timestamp = _decimal(ticker.get("ts"))
        if ticker.get("instId") != contract["instrumentId"] or last is None or timestamp is None or timestamp <= 0:
            raise APIError(502, "preview_inputs_unavailable", "The selected SWAP quote is malformed.")
        quote_age = int(self.clock() * 1000) - int(timestamp)
        if quote_age < 0 or quote_age > _QUOTE_MAX_AGE_MS:
            raise APIError(409, "quote_stale", "The selected SWAP quote is stale; refresh the preview.")

        fee_family = fee.get("instFamily")
        fee_groups = fee.get("feeGroup")
        if (
            fee.get("instType") != "SWAP"
            or (fee_family is not None and fee_family != family)
            or not isinstance(fee_groups, list)
            or not fee_groups
            or any(
                not isinstance(group, dict)
                or not isinstance(group.get("groupId"), str)
                or not group["groupId"].strip()
                for group in fee_groups
            )
        ):
            raise APIError(502, "preview_inputs_unavailable", "The account's applicable SWAP fee is invalid.")
        matching_fee_groups = [
            group for group in fee_groups if group["groupId"] == instrument_group_id
        ]
        if len(matching_fee_groups) != 1:
            raise APIError(502, "preview_inputs_unavailable", "The account's applicable SWAP fee is invalid.")
        maker_value = matching_fee_groups[0].get("maker")
        taker_value = matching_fee_groups[0].get("taker")
        maker_signed_fee = _decimal(maker_value) if isinstance(maker_value, str) else None
        taker_signed_fee = _decimal(taker_value) if isinstance(taker_value, str) else None
        if (
            maker_signed_fee is None or abs(maker_signed_fee) >= 1
            or taker_signed_fee is None or abs(taker_signed_fee) >= 1
        ):
            raise APIError(502, "preview_inputs_unavailable", "The account's applicable SWAP fee is invalid.")
        maker_fee = max(Decimal(0), -maker_signed_fee)
        taker_fee = max(Decimal(0), -taker_signed_fee)

        tiers: list[dict[str, Decimal]] = []
        for row in tier_rows:
            minimum = _decimal(row.get("minSz"))
            maximum = _positive(row.get("maxSz"))
            mmr = _decimal(row.get("mmr"))
            max_leverage = _positive(row.get("maxLever"))
            row_type = row.get("instType")
            row_mode = row.get("tdMode")
            if (
                row_type not in (None, "", "SWAP")
                or row_mode not in (None, "", "isolated")
                or row.get("instFamily") != family
                or minimum is None or minimum < 0
                or maximum is None or maximum < minimum
                or mmr is None or not 0 <= mmr < 1
                or max_leverage is None
            ):
                raise APIError(502, "preview_inputs_unavailable", "Current isolated position tiers are invalid.")
            tiers.append({"min": minimum, "max": maximum, "mmr": mmr, "maxLeverage": max_leverage})
        tiers.sort(key=lambda row: (row["min"], row["max"]))
        if not tiers:
            raise APIError(502, "preview_inputs_unavailable", "No validated isolated position tier is available.")
        return account, fingerprint, {
            "contractValue": contract_value,
            "contractMultiplier": contract_multiplier,
            "tickSize": tick_size,
            "lotSize": lot_size,
            "minimumSize": minimum_size,
            "last": last,
            "quoteTimestamp": timestamp,
            "makerFee": maker_fee,
            "takerFee": taker_fee,
        }, taker_fee, tiers

    def _preview_contract(
        self,
        contract: dict[str, Any],
        *,
        account_snapshot: tuple[dict[str, Any], str] | None = None,
    ) -> dict[str, Any]:
        account, fingerprint, meta, fee_rate, tiers = self._load_market_inputs(
            contract, account_snapshot=account_snapshot
        )
        current = meta["last"]
        tick = meta["tickSize"]
        id_mode = "direction" in contract
        levels_by_side: dict[str, list[dict[str, Any]]] = {"long": [], "short": []}
        for row in contract["selectedLevels"]:
            price = Decimal(row["price"])
            if (price / tick) != (price / tick).to_integral_value():
                raise self._invalid("invalid_price_tick", "Every selected limit price must match the current price tick.")
            if row["side"] == "long":
                if price >= current:
                    raise self._invalid("entry_side_invalid", "Long support entries must remain below the current SWAP price.")
            elif price <= current:
                raise self._invalid("entry_side_invalid", "Short resistance entries must remain above the current SWAP price.")
            normalized_row: dict[str, Any] = {"price": price}
            if id_mode:
                normalized_row["levelId"] = row["levelId"]
            levels_by_side[row["side"]].append(normalized_row)

        unit = meta["contractValue"] * meta["contractMultiplier"]
        total_margin = Decimal(contract["totalMargin"])
        orders: list[dict[str, Any]] = []
        total_actual_margin = Decimal(0)
        total_fees = Decimal(0)
        for side in ("long", "short"):
            side_rows = levels_by_side[side]
            if not side_rows:
                continue
            if id_mode:
                side_rows.sort(
                    key=lambda row: (
                        -row["price"] if side == "long" else row["price"],
                        row["levelId"],
                    )
                )
            else:
                side_rows.sort(key=lambda row: row["price"], reverse=(side == "long"))
            entry = Decimal(contract["entryBySide"][side])
            nearest_distance = min(abs(current - row["price"]) for row in side_rows)
            entry_id = contract["entryLevelIdBySide"][side] if id_mode else None
            if id_mode:
                entry_row = next(row for row in side_rows if row["levelId"] == entry_id)
                entry = entry_row["price"]
            if abs(current - entry) != nearest_distance:
                raise self._invalid("entry_not_nearest", "The entry must be the nearest selected level to the current SWAP price.")

            count = len(side_rows)
            if contract["allocation"] == "increasing":
                weights = list(range(1, count + 1))
            elif contract["allocation"] == "decreasing":
                weights = list(range(count, 0, -1))
            else:
                weights = [1] * count
            weight_total = Decimal(sum(weights))
            side_budget = total_margin * Decimal(contract["sidePercent"][side]) / Decimal(100)
            cumulative_contracts = Decimal(0)
            cumulative_notional = Decimal(0)
            cumulative_margin = Decimal(0)
            side_order_start = len(orders)
            for index, (selected_row, weight) in enumerate(zip(side_rows, weights)):
                price = selected_row["price"]
                allocation = side_budget * Decimal(weight) / weight_total
                side_leverage = Decimal(contract["leverage"][side])
                intended_notional = allocation * side_leverage
                contracts = (intended_notional / (price * unit) / meta["lotSize"]).to_integral_value(
                    rounding=ROUND_DOWN
                ) * meta["lotSize"]
                if contracts < meta["minimumSize"]:
                    raise self._invalid(
                        "order_below_minimum",
                        "The margin allocation produces an order below the current contract minimum.",
                    )
                actual_notional = contracts * price * unit
                actual_margin = actual_notional / side_leverage
                opening_fee = actual_notional * fee_rate
                total_actual_margin += actual_margin
                total_fees += opening_fee
                cumulative_contracts += contracts
                cumulative_notional += contracts * price
                cumulative_margin += actual_margin
                cumulative_average = cumulative_notional / cumulative_contracts
                matching_tiers = [
                    item for item in tiers if item["min"] <= cumulative_contracts <= item["max"]
                ]
                if len(matching_tiers) != 1:
                    raise APIError(
                        502, "preview_inputs_unavailable",
                        "The projected size has no unique validated isolated position tier.",
                    )
                tier = matching_tiers[0]
                if side_leverage > tier["maxLeverage"]:
                    raise self._invalid(
                        "leverage_exceeds_tier",
                        "The selected leverage exceeds the current isolated tier limit for this size.",
                    )
                rate = tier["mmr"]
                long_denominator = unit * cumulative_contracts * (Decimal(1) - rate - fee_rate)
                short_denominator = unit * cumulative_contracts * (Decimal(1) + rate + fee_rate)
                if long_denominator <= 0 or short_denominator <= 0:
                    raise APIError(502, "preview_inputs_unavailable", "The liquidation model inputs are invalid.")
                if side == "long":
                    numerator = unit * cumulative_contracts * cumulative_average - cumulative_margin
                    liquidation = (
                        {"status": "no_positive_threshold", "price": None}
                        if numerator <= 0
                        else {"status": "estimated", "price": _text(_round_up(numerator / long_denominator, tick))}
                    )
                else:
                    numerator = unit * cumulative_contracts * cumulative_average + cumulative_margin
                    liquidation = {"status": "estimated", "price": _text(_round_down(numerator / short_denominator, tick))}
                order = {
                    "side": side,
                    "role": (
                        "entry" if selected_row["levelId"] == entry_id else "dca"
                    ) if id_mode else ("entry" if price == entry else "dca"),
                    "limitPrice": _text(price),
                    "contracts": _text(contracts),
                    "leverage": int(side_leverage),
                    "allocatedMargin": _text(allocation),
                    "margin": _text(actual_margin),
                    "notional": _text(actual_notional),
                    "openingFeeEstimate": _text(opening_fee),
                    "allocationWeight": weight,
                    "cumulativeContracts": _text(cumulative_contracts),
                    "cumulativeAverageEntry": _text(cumulative_average),
                    "liquidationEstimate": liquidation,
                }
                if id_mode:
                    order["levelId"] = selected_row["levelId"]
                orders.append(order)

            if id_mode:
                same_price_groups: dict[Decimal, list[int]] = {}
                for order_index in range(side_order_start, len(orders)):
                    price = Decimal(orders[order_index]["limitPrice"])
                    same_price_groups.setdefault(price, []).append(order_index)
                for group_indices in same_price_groups.values():
                    if len(group_indices) < 2:
                        continue
                    group_estimate = orders[group_indices[-1]]["liquidationEstimate"]
                    for order_index in group_indices:
                        orders[order_index]["liquidationEstimate"] = group_estimate
                        orders[order_index]["liquidationEstimateNote"] = (
                            "Estimated after all same-price orders fill; OKX fill order is not guaranteed."
                        )

        unallocated = total_margin - total_actual_margin
        if unallocated < 0:
            raise APIError(502, "preview_inputs_unavailable", "Rounded contract margin exceeded the entered budget.")
        normalized_meta = {
            "contractValue": _text(meta["contractValue"]),
            "contractMultiplier": _text(meta["contractMultiplier"]),
            "contractValueCurrency": "base",
            "tickSize": _text(meta["tickSize"]),
            "lotSize": _text(meta["lotSize"]),
            "minimumSize": _text(meta["minimumSize"]),
            "makerFeeRate": _text(meta["makerFee"]),
            "takerFeeRate": _text(meta["takerFee"]),
            "tiers": [
                {
                    "min": _text(row["min"]), "max": _text(row["max"]),
                    "mmr": _text(row["mmr"]), "maxLeverage": _text(row["maxLeverage"]),
                }
                for row in tiers
            ],
        }
        semantic = {
            "accountFingerprint": fingerprint,
            "contract": contract,
            "metadata": normalized_meta,
            "orders": orders,
        }
        preview_hash = token_digest(encode_json(semantic), self.owner.settings.session_signing_key)
        return {
            "id": None,
            "status": "PREVIEW",
            "instrumentId": contract["instrumentId"],
            "interval": contract["interval"],
            "sides": [side for side in ("long", "short") if levels_by_side[side]],
            "currentPrice": _text(current),
            "quoteTimestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(int(meta["quoteTimestamp"] / 1000))),
            "totalMargin": _text(total_margin),
            "plannedMargin": _text(total_actual_margin),
            "unallocatedMargin": _text(unallocated),
            "estimatedOpeningFees": _text(total_fees),
            "feesOutsideMargin": True,
            "allocation": contract["allocation"],
            "sidePercent": contract["sidePercent"],
            "orders": orders,
            "previewHash": preview_hash,
            "_internal": {
                "metadata": normalized_meta,
                "accountFingerprint": fingerprint,
                "positionMode": account.get("posMode"),
            },
        }

    @staticmethod
    def _public_preview(preview: dict[str, Any]) -> dict[str, Any]:
        return {key: value for key, value in preview.items() if not key.startswith("_")}

    @staticmethod
    def _with_client_ids(preview: dict[str, Any], old_orders: list[dict[str, Any]] | None = None) -> list[dict[str, Any]]:
        id_mode = any("levelId" in row for row in preview["orders"])
        existing: dict[Any, str] = {}
        for row in old_orders or []:
            if id_mode:
                level_id = row.get("levelId")
                if isinstance(level_id, str):
                    existing[level_id] = row.get("clientOrderId", "")
            else:
                existing[(row.get("side", ""), row.get("limitPrice", ""), row.get("role", ""))] = row.get("clientOrderId", "")
        result: list[dict[str, Any]] = []
        for row in preview["orders"]:
            order = dict(row)
            key: Any = order["levelId"] if id_mode else (order["side"], order["limitPrice"], order["role"])
            order["clientOrderId"] = existing.get(key) or "st" + secrets.token_hex(14)
            result.append(order)
        return result

    @staticmethod
    def _retry_prepared_orders(
        preview: dict[str, Any], child_orders: Any
    ) -> list[dict[str, Any]]:
        if not isinstance(child_orders, list) or len(child_orders) != len(preview.get("orders", [])):
            raise APIError(409, "retry_source_stale", "The retry child rows no longer match their source.")
        old_by_source = {
            row.get("sourceClientOrderId"): row
            for row in child_orders if isinstance(row, dict)
        }
        if len(old_by_source) != len(child_orders):
            raise APIError(409, "retry_source_stale", "The retry child rows no longer match their source.")
        prepared: list[dict[str, Any]] = []
        for row in preview["orders"]:
            old = old_by_source.get(row.get("sourceClientOrderId"))
            if not isinstance(old, dict) or any(
                old.get(key) != value
                for key, value in row.items()
                if key != "sourceClientOrderId"
            ):
                raise APIError(409, "retry_source_stale", "The fixed retry payload changed; review it again.")
            client_id = old.get("clientOrderId")
            if not isinstance(client_id, str) or not re.fullmatch(r"[A-Za-z0-9_-]{8,64}", client_id):
                raise APIError(409, "retry_source_stale", "The retry child client IDs are invalid.")
            prepared.append({**row, "clientOrderId": client_id})
        return prepared

    def _validate_retry_child_in_connection(
        self,
        connection: Any,
        strategy: dict[str, Any],
        *,
        now: float,
        expected_status: str,
        prepared_orders: list[dict[str, Any]] | None = None,
    ) -> tuple[dict[str, Any], list[tuple[int, dict[str, Any], dict[str, Any]]]] | None:
        try:
            metadata = _retry_metadata(strategy.get("contract"))
        except RetryDataError:
            raise APIError(
                409, "retry_source_unavailable", "The retry lineage cannot be validated safely."
            ) from None
        if metadata is None:
            return None
        current_row = connection.execute(
            "SELECT * FROM strategies WHERE strategy_id=? AND account_fingerprint=?",
            (strategy["id"], strategy["accountFingerprint"]),
        ).fetchone()
        if current_row is None:
            raise APIError(409, "retry_source_unavailable", "The retry child is no longer available.")
        current = self._decode_row(current_row)
        if (
            current["status"] != expected_status
            or current["attemptStarted"]
            or current["replacementSourceId"] is not None
            or current["contract"] != strategy["contract"]
            or current["orders"] != strategy["orders"]
            or current["previewHash"] != strategy["previewHash"]
            or not isinstance(current["snapshot"], dict)
            or current["snapshot"].get("previewHash") != current["previewHash"]
        ):
            raise APIError(409, "retry_source_stale", "The retry child changed; reload it and review again.")
        if prepared_orders is not None:
            persisted_prepared = current.get("prepared")
            if (
                not isinstance(persisted_prepared, dict)
                or persisted_prepared.get("previewHash") != current["previewHash"]
                or persisted_prepared.get("orders") != prepared_orders
            ):
                raise APIError(409, "retry_source_stale", "The prepared retry payload changed; review it again.")

        children, unsafe = self._retry_children_in_connection(
            connection,
            strategy["accountFingerprint"],
            metadata["sourceStrategyId"],
            strategy["contract"].get("instrumentId"),
        )
        if unsafe or any(
            child["id"] != strategy["id"] and child["retryRequestId"] == metadata["retryRequestId"]
            for child in children
        ):
            raise APIError(409, "retry_request_conflict", "The retry request ID is already bound to another attempt.")
        source, selected = self._validate_retry_source_in_connection(
            connection,
            fingerprint=strategy["accountFingerprint"],
            source_id=metadata["sourceStrategyId"],
            instrument_id=strategy["contract"].get("instrumentId"),
            source_revision=metadata["sourceRevision"],
            source_selection_hash=metadata["sourceSelectionHash"],
            selected_ids=metadata["sourceClientOrderIds"],
            exclude_child_id=strategy["id"],
            now=now,
            child_orders=current["orders"],
            prepared_orders=prepared_orders,
        )
        return source, selected

    def _preview(self, body: dict[str, Any]) -> dict[str, Any]:
        contract = self._normalize_contract(body)
        preview = self._preview_contract(contract)
        return self._public_preview(preview)

    def _save(self, body: dict[str, Any]) -> dict[str, Any]:
        contract = self._normalize_contract(body)
        replacement_source_id = body.get("replacementSourceId")
        if replacement_source_id is not None and (
            not isinstance(replacement_source_id, str)
            or not _STRATEGY_ID.fullmatch(replacement_source_id)
        ):
            raise self._invalid("replacement_source_id")
        candidate_draft_id = body.get("candidateDraftId")
        if candidate_draft_id is not None and (
            not isinstance(candidate_draft_id, str)
            or not _STRATEGY_ID.fullmatch(candidate_draft_id)
        ):
            raise APIError(422, "candidate_selection_invalid", "The saved candidate selection is invalid.")
        if candidate_draft_id is not None and replacement_source_id is not None:
            raise APIError(422, "candidate_selection_invalid", "Candidate drafts cannot use replacement lineage.")
        candidate_draft: dict[str, Any] | None = None
        if candidate_draft_id is not None:
            _, initial_fingerprint = self._account()
            candidate_draft = self.automatic.load_candidate_for_materialization(
                candidate_draft_id, contract, initial_fingerprint
            )
        expected = body.get("previewHash")
        if not isinstance(expected, str):
            raise APIError(400, "preview_required", "Submit the preview hash before saving a draft.")
        preview = self._preview_contract(contract)
        if not hmac.compare_digest(preview["previewHash"], expected):
            raise APIError(
                409, "preview_stale", "The authoritative preview changed; review the latest preview before saving.",
                details={"preview": self._public_preview(preview)},
            )
        account_fingerprint = preview["_internal"]["accountFingerprint"]
        orders = self._with_client_ids(preview)
        snapshot = self._public_preview(preview)
        snapshot["orders"] = orders
        snapshot["_metadata"] = preview["_internal"]["metadata"]
        snapshot["_positionMode"] = preview["_internal"]["positionMode"]
        now = self.clock()
        strategy_id = new_operation_id() if candidate_draft is None else candidate_draft["id"]
        materialized_generation: dict[str, Any] | None = None
        if candidate_draft is not None:
            if not hmac.compare_digest(candidate_draft["accountFingerprint"], account_fingerprint):
                raise APIError(409, "account_changed", "The active OKX account changed during review.")
            self.automatic.verify_candidate_materialization(candidate_draft, contract)
            materialized_generation = candidate_draft["snapshot"]["aiGeneration"]
            snapshot["draftStage"] = "materialized"
            snapshot["aiGeneration"] = materialized_generation
        with self.store.transaction() as connection:
            if candidate_draft is not None:
                current_row = connection.execute(
                    "SELECT * FROM strategies WHERE strategy_id=? AND account_fingerprint=?",
                    (candidate_draft_id, account_fingerprint),
                ).fetchone()
                if current_row is None:
                    raise APIError(409, "candidate_not_materializable", "The saved candidate draft changed before saving.")
                current_candidate = self._decode_row(current_row)
                self.automatic.verify_candidate_materialization(current_candidate, contract)
                current_generation = current_candidate["snapshot"].get("aiGeneration")
                if encode_json(current_generation) != encode_json(materialized_generation):
                    raise APIError(409, "candidate_selection_mismatch", "The saved candidates changed before saving.")
                changed = connection.execute(
                    "UPDATE strategies SET status='DRAFT', contract_json=?, snapshot_json=?, orders_json=?, "
                    "results_json=?, preview_hash=?, confirmation_hash=NULL, prepared_expires_at=NULL, "
                    "prepared_json=NULL, attempt_started=0, batch_attempted=0, order_placement_attempted=0, "
                    "queue_json=NULL, execution_id=NULL, execution_lease_until=NULL, replacement_source_id=NULL, "
                    "failure_reason=NULL, leverage_results_json='[]', updated_at=? "
                    "WHERE strategy_id=? AND account_fingerprint=? AND status='DRAFT' AND attempt_started=0",
                    (
                        encode_json(contract),
                        encode_json(snapshot),
                        encode_json(orders),
                        encode_json([{**row, "status": "not_submitted", "filledContracts": "0"} for row in orders]),
                        preview["previewHash"],
                        now,
                        strategy_id,
                        account_fingerprint,
                    ),
                ).rowcount
                if changed != 1:
                    raise APIError(409, "candidate_not_materializable", "The saved candidate draft changed before saving.")
            elif replacement_source_id is not None:
                source_row = connection.execute(
                    "SELECT * FROM strategies WHERE strategy_id=? AND account_fingerprint=?",
                    (replacement_source_id, account_fingerprint),
                ).fetchone()
                source = None if source_row is None else self._decode_row(source_row)
                if source is not None and self.automatic.is_candidate_stage(source):
                    raise APIError(
                        409, "candidate_not_materialized",
                        "Candidate drafts cannot be used as replacement sources.",
                    )
                if source_row is None or not self._eligible_never_sent_record(
                    connection, source, account_fingerprint, now
                ):
                    raise APIError(
                        409,
                        "replacement_source_unavailable",
                        "The never-sent source is no longer eligible for replacement.",
                    )
            if candidate_draft is None:
                connection.execute(
                    "INSERT INTO strategies(strategy_id, account_fingerprint, status, contract_json, snapshot_json, "
                    "orders_json, results_json, preview_hash, replacement_source_id, submission_mode, "
                    "created_at, updated_at) "
                    "VALUES (?, ?, 'DRAFT', ?, ?, ?, ?, ?, ?, NULL, ?, ?)",
                    (
                        strategy_id, account_fingerprint, encode_json(contract), encode_json(snapshot),
                        encode_json(orders), encode_json([{**row, "status": "not_submitted", "filledContracts": "0"} for row in orders]),
                        preview["previewHash"], replacement_source_id, now, now,
                    ),
                )
        result = {
            "id": strategy_id,
            "status": "DRAFT",
            "submissionMode": None,
            "orderPlacementAttempted": False,
            "queueStatus": None,
            "queueProgress": None,
            "instrumentId": contract["instrumentId"],
            "interval": contract["interval"],
            "createdAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(now)),
            "orders": orders,
            "preview": self._public_preview(snapshot),
        }
        if candidate_draft is not None:
            result["draftStage"] = "materialized"
            result["aiGeneration"] = materialized_generation
        return result

    def _retry_preflight_preview(
        self,
        strategy: dict[str, Any],
        expected_fingerprint: str,
        account_snapshot: tuple[dict[str, Any], str],
    ) -> dict[str, Any] | None:
        contract = strategy.get("contract")
        try:
            metadata = _retry_metadata(contract)
        except RetryDataError:
            raise APIError(
                409, "retry_source_unavailable", "The retry lineage cannot be validated safely."
            ) from None
        if metadata is None:
            return None
        if strategy.get("replacementSourceId") is not None:
            raise APIError(
                409, "retry_source_unavailable", "The retry child has conflicting replacement lineage."
            )
        if not hmac.compare_digest(strategy.get("accountFingerprint", ""), expected_fingerprint):
            raise APIError(409, "account_changed", "The active OKX account changed; no strategy order was sent.")

        context = self._retry_source_context(
            metadata["sourceStrategyId"],
            exclude_child_id=strategy["id"],
            reconcile=True,
            account_snapshot=account_snapshot,
        )
        if context["instrumentId"] != contract.get("instrumentId"):
            raise APIError(
                409, "retry_source_stale", "The source changed; refresh retry candidates and review again."
            )
        try:
            selected, selection_digest, selected_ids = self._retry_selection(
                context, metadata["sourceRevision"], metadata["sourceClientOrderIds"],
                exclude_child_id=strategy["id"],
            )
        except APIError:
            raise
        if (
            selected_ids != metadata["sourceClientOrderIds"]
            or not hmac.compare_digest(selection_digest, metadata["sourceSelectionHash"])
        ):
            raise APIError(
                409, "retry_source_stale", "The selected source evidence changed; refresh retry review."
            )

        child_orders = strategy.get("orders")
        prepared = strategy.get("prepared")
        prepared_orders = prepared.get("orders") if isinstance(prepared, dict) else None
        with self.store.connection() as connection:
            _, validated_selection = self._validate_retry_source_in_connection(
                connection,
                fingerprint=expected_fingerprint,
                source_id=metadata["sourceStrategyId"],
                instrument_id=context["instrumentId"],
                source_revision=metadata["sourceRevision"],
                source_selection_hash=metadata["sourceSelectionHash"],
                selected_ids=metadata["sourceClientOrderIds"],
                exclude_child_id=strategy["id"],
                now=self.clock(),
                child_orders=child_orders,
                prepared_orders=prepared_orders,
            )

        preview = self._retry_market_preview(context, validated_selection, selection_digest)
        if (
            not hmac.compare_digest(expected_fingerprint, preview["_internal"]["accountFingerprint"])
            or context["account"].get("posMode") != preview["_internal"].get("positionMode")
        ):
            raise APIError(409, "account_changed", "The active OKX account changed; refresh retry review.")
        return preview

    def _preflight(
        self,
        contract: dict[str, Any],
        expected_fingerprint: str,
        *,
        resume: bool = False,
        strategy: dict[str, Any] | None = None,
        account_snapshot: tuple[dict[str, Any], str] | None = None,
    ) -> tuple[dict[str, Any], dict[str, Any]]:
        account, fingerprint = self._account(account_snapshot)
        if not hmac.compare_digest(expected_fingerprint, fingerprint):
            raise APIError(409, "account_changed", "The active OKX account changed; no strategy order was sent.")
        mode = account.get("posMode")
        retry_preview: dict[str, Any] | None = None
        if strategy is not None:
            retry_preview = self._retry_preflight_preview(
                strategy, fingerprint, (account, fingerprint)
            )
        elif is_resubmission_contract(contract):
            raise APIError(
                409, "prepared_strategy_invalid", "Retry preflight requires the persisted child strategy."
            )
        if retry_preview is None:
            sides = set(contract["entryBySide"])
        else:
            sides = {row["side"] for row in retry_preview["orders"]}
        if len(sides) == 2 and mode != "long_short_mode":
            raise APIError(
                409, "account_mode_unsupported",
                "Two-sided strategies require OKX Hedge mode. Change the account mode manually and prepare again.",
            )
        if mode not in ("net_mode", "long_short_mode"):
            raise APIError(409, "account_mode_unsupported", "The current OKX position mode is unsupported.")
        prepared_scope = None
        if strategy is not None and strategy.get("prepared") is not None:
            prepared_scope = self._persisted_scope(strategy, require_prepared_mode=True)
            if not prepared_scope.valid:
                raise APIError(
                    409, "prepared_strategy_invalid",
                    "The prepared strategy position scope cannot be validated safely.",
                )
            if prepared_scope.position_mode != mode:
                raise APIError(
                    409, "account_mode_unsupported",
                    "The current OKX position mode differs from the prepared strategy.",
                )
        target_scope = scope_for_sides(mode, sides)
        if not target_scope.valid:
            raise APIError(
                409, "prepared_strategy_invalid",
                "The executable position sides cannot be validated safely.",
            )
        instrument_id = contract["instrumentId"]
        if not resume:
            try:
                positions = self.okx.positions("SWAP")
                pending = self.okx.pending_orders(instrument_id)
            except OKXError as exc:
                raise self._read_failure(
                    exc,
                    fallback_code="account_preflight_unavailable",
                    fallback_message="Current positions or pending orders are unavailable.",
                ) from None
            relevant_positions = scoped_position_rows(positions, instrument_id, target_scope)
            if relevant_positions is None or relevant_positions:
                raise APIError(
                    409, "instrument_position_exists",
                    "Close the overlapping position for this SWAP before applying.",
                )
            conflicting_pending = scoped_pending_rows(pending, instrument_id, target_scope)
            if conflicting_pending is None or conflicting_pending:
                raise APIError(409, "pending_order_exists", "Cancel existing pending orders for this SWAP before applying.")
        preview = retry_preview if retry_preview is not None else self._preview_contract(
            contract, account_snapshot=(account, fingerprint)
        )
        if not hmac.compare_digest(expected_fingerprint, preview["_internal"]["accountFingerprint"]):
            raise APIError(409, "account_changed", "The active OKX account changed; no strategy order was sent.")
        if not resume:
            try:
                balance_rows = self.okx.account_balance()
            except OKXError as exc:
                raise self._read_failure(
                    exc,
                    fallback_code="account_preflight_unavailable",
                    fallback_message="Available USDT balance is unavailable.",
                ) from None
            available = self._available_usdt(balance_rows)
            if available is None:
                raise APIError(502, "account_preflight_unavailable", "Available USDT balance is unavailable.")
            required = Decimal(contract["totalMargin"]) + Decimal(preview["estimatedOpeningFees"] or "0")
            if available < required:
                raise APIError(
                    422, "insufficient_balance", "Available USDT does not cover the margin budget and estimated fees.",
                    details={"required": _text(required), "available": _text(available)},
                )
        return account, preview

    def _prepare(self, strategy_id: str) -> dict[str, Any]:
        strategy, account, fingerprint = self._current_strategy(strategy_id)
        self.automatic.assert_not_candidate(strategy)
        if strategy["attemptStarted"] or strategy["status"] not in ("DRAFT",):
            raise APIError(409, "strategy_immutable", "This strategy has already entered an application attempt.")
        self._ensure_new_order_cap(strategy)
        self._require_eligible_replacement_source(strategy["replacementSourceId"], fingerprint)
        try:
            _, preview = self._preflight(
                strategy["contract"],
                fingerprint,
                strategy=strategy,
                account_snapshot=(account, fingerprint),
            )
        except APIError as exc:
            diagnostics.emit_event(
                "preflight", component="api", stage="preflight_initial", outcome="failure",
                reason=self._preflight_diagnostic_reason(exc), api_code=exc.code,
            )
            raise
        except Exception:
            diagnostics.emit_event(
                "preflight", component="api", stage="preflight_initial", outcome="failure",
                reason="preflight_unavailable",
            )
            raise
        diagnostics.emit_event(
            "preflight", component="api", stage="preflight_initial", outcome="success",
        )
        if not hmac.compare_digest(preview["previewHash"], strategy["previewHash"]):
            raise APIError(
                409, "strategy_stale", "Contract, fee, or tier data changed; recreate and review a fresh draft.",
                details={"preview": self._public_preview(preview)},
            )
        confirmation = new_confirmation_token()
        expires_at = self.clock() + _PREPARE_TTL_SECONDS
        if is_resubmission_contract(strategy["contract"]):
            prepared_orders = self._retry_prepared_orders(preview, strategy["orders"])
        else:
            prepared_orders = self._with_client_ids(preview, strategy["orders"])
        prepared = self._public_preview(preview)
        prepared["orders"] = prepared_orders
        prepared["_positionMode"] = preview["_internal"]["positionMode"]
        with self.store.transaction() as connection:
            self._validate_retry_child_in_connection(
                connection,
                strategy,
                now=self.clock(),
                expected_status="DRAFT",
            )
            preference = connection.execute(
                "SELECT limit_order_submission_mode FROM strategy_account_preferences "
                "WHERE account_fingerprint=?",
                (fingerprint,),
            ).fetchone()
            submission_mode = "sequential" if preference is None else preference["limit_order_submission_mode"]
            if submission_mode not in ("sequential", "batch"):
                raise APIError(
                    500, "strategy_settings_unavailable",
                    "The saved strategy submission preference is invalid.",
                )
            prepared["submissionMode"] = submission_mode
            changed = connection.execute(
                "UPDATE strategies SET status='PREPARED', confirmation_hash=?, prepared_expires_at=?, "
                "prepared_json=?, submission_mode=?, queue_json=NULL, updated_at=? "
                "WHERE strategy_id=? AND status='DRAFT' AND attempt_started=0",
                (
                    token_digest(confirmation, self.owner.settings.session_signing_key),
                    expires_at, encode_json(prepared), submission_mode, self.clock(), strategy_id,
                ),
            ).rowcount
        if changed != 1:
            raise APIError(409, "strategy_state_changed", "The strategy changed; reload it and prepare again.")
        diagnostics.set_submission_mode(submission_mode)
        diagnostics.emit_event(
            "prepare_result", component="api", stage="prepare", outcome="success",
            status="PREPARED", submission_mode=submission_mode, order_count=len(prepared_orders),
        )
        result = {
            "id": strategy_id,
            "status": "PREPARED",
            "confirmationToken": confirmation,
            "expiresAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(expires_at)),
            "orders": prepared_orders,
            "plannedMargin": prepared["plannedMargin"],
            "unallocatedMargin": prepared["unallocatedMargin"],
            "estimatedOpeningFees": prepared["estimatedOpeningFees"],
            "quoteTimestamp": prepared["quoteTimestamp"],
            "submissionMode": submission_mode,
            "orderPlacementAttempted": False,
            "queueStatus": None,
            "queueProgress": None,
        }
        lineage = self._public_retry_summary(strategy.get("contract"))
        if lineage is not None:
            result["resubmission"] = lineage
        return result

    def _claim_execution(self, strategy_id: str, strategy: dict[str, Any], token: str) -> str | None:
        self._ensure_new_order_cap(strategy)
        scope = self._persisted_scope(strategy, require_prepared_mode=True)
        if not scope.valid:
            raise APIError(
                409, "prepared_strategy_invalid",
                "The prepared strategy position scope cannot be validated safely.",
            )
        presented = token_digest(token, self.owner.settings.session_signing_key)
        if not isinstance(strategy["confirmationHash"], str) or not hmac.compare_digest(strategy["confirmationHash"], presented):
            raise APIError(403, "invalid_confirmation", "The confirmation token is invalid.")
        execution_id = secrets.token_urlsafe(24)
        now = self.clock()
        try:
            with self.store.transaction() as connection:
                self._ensure_persisted_new_order_cap(connection, strategy)
                persisted_prepared = strategy.get("prepared")
                self._validate_retry_child_in_connection(
                    connection,
                    strategy,
                    now=now,
                    expected_status="PREPARED",
                    prepared_orders=(
                        persisted_prepared.get("orders")
                        if isinstance(persisted_prepared, dict)
                        else None
                    ),
                )
                replacement_source_id = strategy["replacementSourceId"]
                if replacement_source_id is not None:
                    source_row = connection.execute(
                        "SELECT * FROM strategies WHERE strategy_id=? AND account_fingerprint=?",
                        (replacement_source_id, strategy["accountFingerprint"]),
                    ).fetchone()
                    if source_row is None or not self._eligible_never_sent_record(
                        connection,
                        self._decode_row(source_row),
                        strategy["accountFingerprint"],
                        now,
                    ):
                        raise APIError(
                            409,
                            "replacement_source_unavailable",
                            "The never-sent source is no longer eligible for replacement.",
                        )
                changed = connection.execute(
                    "UPDATE strategies SET status='APPLYING', attempt_started=1, confirmation_hash=NULL, "
                    "execution_id=?, execution_lease_until=?, updated_at=? "
                    "WHERE strategy_id=? AND status='PREPARED' AND attempt_started=0 "
                    "AND confirmation_hash=? AND prepared_expires_at>?",
                    (
                        execution_id, now + _EXECUTION_LEASE_SECONDS, now,
                        strategy_id, presented, now,
                    ),
                ).rowcount
                if changed != 1:
                    return None
                self._claim_reservation_in_connection(connection, strategy, scope, now)
        except sqlite3.IntegrityError:
            raise APIError(
                409, "instrument_apply_in_progress",
                "Another strategy is applying or reconciling this account and instrument.",
            ) from None
        return execution_id

    def _claim_queue(self, strategy_id: str, strategy: dict[str, Any], token: str) -> bool:
        self._ensure_new_order_cap(strategy)
        presented = token_digest(token, self.owner.settings.session_signing_key)
        if not isinstance(strategy["confirmationHash"], str) or not hmac.compare_digest(strategy["confirmationHash"], presented):
            raise APIError(403, "invalid_confirmation", "The confirmation token is invalid.")
        prepared = strategy["prepared"]
        orders = prepared.get("orders") if isinstance(prepared, dict) else None
        preview_hash = prepared.get("previewHash") if isinstance(prepared, dict) else None
        if (
            not isinstance(orders, list) or not orders or len(orders) > _MAX_ORDERS
            or not isinstance(preview_hash, str) or not preview_hash
            or any(not isinstance(row, dict) for row in orders)
        ):
            raise APIError(409, "prepared_strategy_invalid", "The prepared strategy cannot be queued safely.")
        scope = self._persisted_scope(strategy, require_prepared_mode=True)
        if not scope.valid:
            raise APIError(
                409, "prepared_strategy_invalid",
                "The prepared strategy position scope cannot be validated safely.",
            )
        now = self.clock()
        queue = new_queue(enqueued_at=now, total_count=len(orders), preview_hash=preview_hash)
        queued_results = initial_results(orders)
        try:
            with self.store.transaction() as connection:
                self._ensure_persisted_new_order_cap(connection, strategy)
                self._validate_retry_child_in_connection(
                    connection,
                    strategy,
                    now=now,
                    expected_status="PREPARED",
                    prepared_orders=orders,
                )
                replacement_source_id = strategy["replacementSourceId"]
                if replacement_source_id is not None:
                    source_row = connection.execute(
                        "SELECT * FROM strategies WHERE strategy_id=? AND account_fingerprint=?",
                        (replacement_source_id, strategy["accountFingerprint"]),
                    ).fetchone()
                    if source_row is None or not self._eligible_never_sent_record(
                        connection, self._decode_row(source_row), strategy["accountFingerprint"], now
                    ):
                        raise APIError(
                            409,
                            "replacement_source_unavailable",
                            "The never-sent source is no longer eligible for replacement.",
                        )
                changed = connection.execute(
                    "UPDATE strategies SET status='APPLYING', attempt_started=1, confirmation_hash=NULL, "
                    "submission_mode='sequential', order_placement_attempted=0, queue_json=?, results_json=?, "
                    "execution_id=NULL, execution_lease_until=NULL, updated_at=? "
                    "WHERE strategy_id=? AND status='PREPARED' AND attempt_started=0 "
                    "AND submission_mode='sequential' AND confirmation_hash=? AND prepared_expires_at>?",
                    (
                        encode_json(queue), encode_json(queued_results), now,
                        strategy_id, presented, now,
                    ),
                ).rowcount
                if changed != 1:
                    return False
                self._claim_reservation_in_connection(connection, strategy, scope, now)
        except sqlite3.IntegrityError:
            raise APIError(
                409, "instrument_apply_in_progress",
                "Another strategy is applying or reconciling this account and instrument.",
            ) from None
        return True

    def _renew_execution(self, strategy_id: str, execution_id: str) -> bool:
        now = self.clock()
        with self.store.transaction() as connection:
            changed = connection.execute(
                "UPDATE strategies SET execution_lease_until=?, updated_at=? "
                "WHERE strategy_id=? AND status='APPLYING' AND execution_id=? "
                "AND execution_lease_until>?",
                (now + _EXECUTION_LEASE_SECONDS, now, strategy_id, execution_id, now),
            ).rowcount
        return changed == 1

    def _execute(self, strategy_id: str, body: dict[str, Any]) -> dict[str, Any]:
        token = body.get("confirmationToken")
        if not isinstance(token, str) or not token:
            raise APIError(400, "invalid_request", "A confirmation token is required.")
        strategy, account, fingerprint = self._current_strategy(strategy_id)
        self.automatic.assert_not_candidate(strategy)
        if strategy["status"] != "PREPARED":
            diagnostics.emit_event(
                "execute_noop", component="api", stage="execute", outcome="noop",
                status=strategy["status"] if strategy["status"] in {
                    "DRAFT", "APPLYING", "APPLIED", "PARTIAL", "UNKNOWN", "COMPLETED"
                } else None,
            )
            return self._basic_result(strategy)
        if strategy["attemptStarted"]:
            diagnostics.emit_event(
                "execute_noop", component="api", stage="execute", outcome="noop",
                status="PREPARED",
            )
            return self._basic_result(strategy)
        self._ensure_new_order_cap(strategy)
        if strategy["preparedExpiresAt"] is None or strategy["preparedExpiresAt"] <= self.clock():
            self._expire_prepare(strategy)
            diagnostics.emit_event(
                "execute_noop", component="api", stage="execute", outcome="expired",
                reason="queue_expired", status="DRAFT",
            )
            return {**self._basic_result(strategy), "prepareExpired": True}
        presented = token_digest(token, self.owner.settings.session_signing_key)
        if not isinstance(strategy["confirmationHash"], str) or not hmac.compare_digest(strategy["confirmationHash"], presented):
            raise APIError(403, "invalid_confirmation", "The confirmation token is invalid.")
        if strategy["submissionModeInvalid"]:
            raise APIError(409, "prepared_strategy_invalid", "The prepared submission mode is inconsistent.")
        prepared = strategy["prepared"] or {}
        submission_mode = strategy["submissionMode"] or "batch"
        diagnostics.set_submission_mode(submission_mode)
        prepared_mode = prepared.get("submissionMode")
        if prepared_mode is not None and prepared_mode != submission_mode:
            raise APIError(409, "prepared_strategy_invalid", "The prepared submission mode is inconsistent.")
        try:
            _, live_preview = self._preflight(
                strategy["contract"],
                fingerprint,
                strategy=strategy,
                account_snapshot=(account, fingerprint),
            )
        except APIError as exc:
            diagnostics.emit_event(
                "preflight", component="api", stage="preflight_initial", outcome="failure",
                reason=self._preflight_diagnostic_reason(exc), api_code=exc.code,
                submission_mode=submission_mode,
            )
            raise
        except Exception:
            diagnostics.emit_event(
                "preflight", component="api", stage="preflight_initial", outcome="failure",
                reason="preflight_unavailable", submission_mode=submission_mode,
            )
            raise
        diagnostics.emit_event(
            "preflight", component="api", stage="preflight_initial", outcome="success",
            submission_mode=submission_mode,
        )
        if not hmac.compare_digest(live_preview["previewHash"], str(prepared.get("previewHash", ""))):
            self._reset_to_draft(strategy_id)
            raise APIError(
                409, "strategy_stale", "Contract, fee, or tier data changed; review a fresh draft before applying.",
                details={"preview": self._public_preview(live_preview)},
            )
        if submission_mode == "sequential":
            if prepared_mode != "sequential":
                raise APIError(409, "prepared_strategy_invalid", "The prepared submission mode is missing.")
            if not self._claim_queue(strategy_id, strategy, token):
                diagnostics.emit_event(
                    "execute_noop", component="api", stage="execute", outcome="noop",
                    status="APPLYING",
                )
                return self._basic_result(self._load_row(strategy_id))
            diagnostics.emit_event(
                "enqueue_result", component="api", stage="enqueue", outcome="queued",
                status="APPLYING", submission_mode="sequential",
                order_count=len(prepared.get("orders", [])), persisted=True,
            )
            return self._basic_result(self._load_row(strategy_id))
        execution_id = self._claim_execution(strategy_id, strategy, token)
        if execution_id is None:
            latest = self._load_row(strategy_id)
            diagnostics.emit_event(
                "execute_noop", component="api", stage="execute", outcome="noop",
                status=latest["status"] if latest["status"] in {
                    "DRAFT", "APPLYING", "APPLIED", "PARTIAL", "UNKNOWN", "COMPLETED"
                } else None,
            )
            return self._basic_result(latest)

        orders = prepared.get("orders", [])
        leverage_results: list[dict[str, Any]] = []
        mode = prepared.get("_positionMode")
        if mode not in ("net_mode", "long_short_mode"):
            not_submitted = [{**row, "status": "not_submitted"} for row in orders]
            self._finish(strategy_id, execution_id, "UNKNOWN", not_submitted, "position_mode_unavailable", leverage_results)
            return self._result(strategy_id)
        for side in sorted({row["side"] for row in orders}, key=lambda value: (value != "long", value)):
            if not self._renew_execution(strategy_id, execution_id):
                diagnostics.emit_event(
                    "commit", component="api", stage="commit", outcome="refused",
                    reason="lease_lost", persisted=False,
                )
                return self._result(strategy_id)
            side_order = next(row for row in orders if row["side"] == side)
            pos_side = side if mode == "long_short_mode" else "net"
            request = {
                "instId": strategy["contract"]["instrumentId"],
                "lever": str(side_order["leverage"]),
                "mgnMode": "isolated",
                "posSide": pos_side,
            }
            diagnostics.emit_event(
                "write_attempt", component="api", stage="leverage", outcome="attempted",
                side=side, submission_mode=submission_mode, client_order_id=side_order.get("clientOrderId"),
            )
            try:
                response = self.okx.set_leverage(request)
            except OKXTransportError:
                diagnostics.emit_event(
                    "ack_observed", component="api", stage="leverage", outcome="unknown",
                    reason="leverage_unknown", side=side,
                    client_order_id=side_order.get("clientOrderId"),
                    persisted=False,
                )
                leverage_results.append({"side": side, "status": "unknown"})
                not_submitted = [{**row, "status": "not_submitted"} for row in orders]
                self._finish(strategy_id, execution_id, "UNKNOWN", not_submitted, "leverage_unknown", leverage_results)
                return self._result(strategy_id)
            except OKXError as exc:
                diagnostics.emit_event(
                    "ack_observed", component="api", stage="leverage",
                    outcome="rejected" if exc.error_code is not None else "unknown",
                    reason="leverage_rejected" if exc.error_code is not None else "leverage_unknown",
                    side=side, client_order_id=side_order.get("clientOrderId"),
                    item_code=exc.error_code,
                    persisted=False,
                )
                leverage_result = {"side": side, "status": "rejected"}
                if exc.error_code is not None:
                    leverage_result["errorCode"] = exc.error_code
                leverage_results.append(leverage_result)
                not_submitted = [{**row, "status": "not_submitted"} for row in orders]
                self._finish(strategy_id, execution_id, "PARTIAL", not_submitted, "leverage_rejected", leverage_results)
                return self._result(strategy_id)
            leverage_outcome, error_code = parse_leverage_ack(
                response,
                expected_pos_side=pos_side,
                expected_instrument_id=strategy["contract"]["instrumentId"],
                expected_leverage=side_order["leverage"],
            )
            diagnostics.emit_event(
                "ack_observed", component="api", stage="leverage",
                outcome=leverage_outcome, reason=diagnostics.safe_reason(
                    "leverage_rejected" if leverage_outcome == "rejected" else
                    "leverage_unknown" if leverage_outcome == "unknown" else "other"
                ),
                side=side, client_order_id=side_order.get("clientOrderId"), item_code=error_code,
                ack_shape="valid" if leverage_outcome == "applied" else "malformed",
                persisted=False,
            )
            if leverage_outcome != "applied":
                leverage_result = {"side": side, "status": leverage_outcome}
                if error_code is not None:
                    leverage_result["errorCode"] = error_code
                leverage_results.append(leverage_result)
                not_submitted = [{**row, "status": "not_submitted"} for row in orders]
                next_status = "PARTIAL" if leverage_outcome == "rejected" else "UNKNOWN"
                failure_reason = "leverage_rejected" if leverage_outcome == "rejected" else "leverage_unknown"
                self._finish(strategy_id, execution_id, next_status, not_submitted, failure_reason, leverage_results)
                return self._result(strategy_id)
            leverage_results.append({"side": side, "status": "applied"})

        if not self._renew_execution(strategy_id, execution_id):
            diagnostics.emit_event(
                "commit", component="api", stage="commit", outcome="refused",
                reason="lease_lost", persisted=False,
            )
            return self._result(strategy_id)
        try:
            try:
                _, latest_preview = self._preflight(strategy["contract"], fingerprint, strategy=strategy)
            except APIError as exc:
                diagnostics.emit_event(
                    "preflight", component="api", stage="preflight_post_leverage", outcome="failure",
                    reason=self._preflight_diagnostic_reason(exc), api_code=exc.code,
                    submission_mode=submission_mode,
                )
                raise
            except Exception:
                diagnostics.emit_event(
                    "preflight", component="api", stage="preflight_post_leverage", outcome="failure",
                    reason="preflight_unavailable", submission_mode=submission_mode,
                )
                raise
            diagnostics.emit_event(
                "preflight", component="api", stage="preflight_post_leverage", outcome="success",
                submission_mode=submission_mode,
            )
            if not hmac.compare_digest(latest_preview["previewHash"], str(prepared.get("previewHash", ""))):
                not_submitted = [{**row, "status": "not_submitted"} for row in orders]
                self._finish(strategy_id, execution_id, "PARTIAL", not_submitted, "preflight_changed_after_leverage", leverage_results)
                return self._result(strategy_id)
        except APIError:
            not_submitted = [{**row, "status": "not_submitted"} for row in orders]
            self._finish(strategy_id, execution_id, "PARTIAL", not_submitted, "preflight_failed_after_leverage", leverage_results)
            return self._result(strategy_id)

        payload = [self._okx_order(strategy["contract"], row, mode) for row in orders]
        if not self._mark_batch_attempted(strategy_id, execution_id):
            diagnostics.emit_event(
                "commit", component="api", stage="commit", outcome="refused",
                reason="marker_refused", persisted=False,
            )
            return self._result(strategy_id)
        diagnostics.emit_event(
            "write_attempt", component="api", stage="batch", outcome="attempted",
            submission_mode=submission_mode, order_count=len(orders),
        )
        try:
            response = self.okx.place_batch_orders(payload)
        except OKXTransportError:
            diagnostics.emit_event(
                "ack_observed", component="api", stage="batch", outcome="unknown",
                reason="batch_unknown", order_count=len(orders), persisted=False,
            )
            unknown = [{**row, "status": "unknown"} for row in orders]
            self._finish(strategy_id, execution_id, "UNKNOWN", unknown, "batch_unknown", leverage_results)
            return self._result(strategy_id)
        except OKXError:
            diagnostics.emit_event(
                "ack_observed", component="api", stage="batch", outcome="unknown",
                reason="batch_unknown", order_count=len(orders), persisted=False,
            )
            unknown = [{**row, "status": "unknown"} for row in orders]
            self._finish(strategy_id, execution_id, "UNKNOWN", unknown, "batch_response_unavailable", leverage_results)
            return self._result(strategy_id)
        outcomes, state, error = self._parse_batch_ack(response, orders)
        shape = self._batch_ack_shape(response, orders)
        for index, row in enumerate(outcomes):
            diagnostics.emit_event(
                "ack_observed", component="api", stage="order", outcome=row["status"],
                reason=diagnostics.safe_reason(
                    "order_rejected" if row["status"] == "rejected" else
                    "ack_unknown" if row["status"] == "unknown" else "other"
                ),
                client_order_id=row.get("clientOrderId"), order_index=index,
                item_code=row.get("errorCode"), ack_shape=shape, persisted=False,
            )
        diagnostics.emit_event(
            "batch_summary", component="api", stage="batch",
            outcome="success" if state == "APPLIED" else "failure", status=state,
            submission_mode=submission_mode, order_count=len(outcomes),
            accepted_count=sum(row["status"] == "accepted" for row in outcomes),
            pending_count=sum(row["status"] in {"unknown", "sending"} for row in outcomes),
            not_submitted_count=sum(row["status"] == "not_submitted" for row in outcomes),
            top_code=response.get("code") if isinstance(response, dict) else None,
            reason=diagnostics.safe_reason(error), ack_shape=shape,
        )
        self._finish(strategy_id, execution_id, state, outcomes, error, leverage_results)
        return self._result(strategy_id)

    @staticmethod
    def _preflight_diagnostic_reason(error: APIError) -> str:
        return {
            "exchange_rate_limited": "exchange_rate_limited",
            "account_changed": "account_changed",
            "account_identity_unavailable": "account_changed",
            "account_mode_unsupported": "account_mode_unsupported",
            "instrument_position_exists": "position_exists",
            "pending_order_exists": "pending_order_exists",
            "insufficient_balance": "insufficient_balance",
            "quote_stale": "preview_changed",
        }.get(error.code, "preflight_unavailable")

    @staticmethod
    def _batch_ack_shape(response: Any, orders: list[dict[str, Any]]) -> str:
        if not isinstance(response, dict):
            return "nonobject_data"
        top_code = bounded_error_code(response.get("code"))
        if top_code not in ("0", "1", "2"):
            return "missing_code" if "code" not in response else "invalid_code"
        data = response.get("data")
        if not isinstance(data, list):
            return "invalid_data_type"
        if len(data) != len(orders):
            return "data_cardinality"
        clients: list[str] = []
        items: list[dict[str, Any]] = []
        for item in data:
            if not isinstance(item, dict):
                return "invalid_row"
            client_id = item.get("clOrdId")
            if not isinstance(client_id, str):
                return "invalid_row"
            if client_id in clients:
                return "duplicate_client_id"
            clients.append(client_id)
            items.append(item)
        expected_clients: set[str] = set()
        for row in orders:
            if not isinstance(row, dict) or not isinstance(row.get("clientOrderId"), str):
                return "invalid_row"
            expected_clients.add(row["clientOrderId"])
        if set(clients) != expected_clients:
            return "client_identity_mismatch"
        all_accepted = True
        for item in items:
            if "sCode" not in item or item.get("sCode") in (None, ""):
                return "missing_code"
            raw_code = item.get("sCode")
            code = bounded_error_code(raw_code)
            if code is None:
                return "invalid_code"
            if int(code) == 0:
                if code != "0":
                    return "invalid_code"
                if not (isinstance(item.get("ordId"), str) and item.get("ordId", "").strip()):
                    return "missing_order_id"
            else:
                order_id = item.get("ordId")
                if "ordId" in item and (not isinstance(order_id, str) or order_id != ""):
                    return "rejection_order_id_conflict"
                all_accepted = False
        if top_code in ("1", "2") and all_accepted:
            return "top_level_conflict"
        return "valid"

    @staticmethod
    def _okx_order(contract: dict[str, Any], row: dict[str, Any], mode: Any) -> dict[str, Any]:
        pos_side = row["side"] if mode == "long_short_mode" else "net"
        return {
            "instId": contract["instrumentId"],
            "tdMode": "isolated",
            "ccy": "USDT",
            "clOrdId": row["clientOrderId"],
            "side": "buy" if row["side"] == "long" else "sell",
            "posSide": pos_side,
            "ordType": "limit",
            "px": row["limitPrice"],
            "sz": row["contracts"],
        }

    @staticmethod
    def _parse_batch_ack(response: Any, orders: list[dict[str, Any]]) -> tuple[list[dict[str, Any]], str, str | None]:
        if not isinstance(response, dict):
            return [{**row, "status": "unknown"} for row in orders], "UNKNOWN", "batch_ack_malformed"
        top_code = bounded_error_code(response.get("code"))
        data = response.get("data")
        if top_code not in ("0", "1", "2") or not isinstance(data, list) or len(data) != len(orders):
            return [{**row, "status": "unknown"} for row in orders], "UNKNOWN", "batch_ack_malformed"
        by_client: dict[str, dict[str, Any]] = {}
        for item in data:
            if not isinstance(item, dict) or not isinstance(item.get("clOrdId"), str) or item["clOrdId"] in by_client:
                return [{**row, "status": "unknown"} for row in orders], "UNKNOWN", "batch_ack_malformed"
            by_client[item["clOrdId"]] = item
        if set(by_client) != {row["clientOrderId"] for row in orders}:
            return [{**row, "status": "unknown"} for row in orders], "UNKNOWN", "batch_ack_malformed"
        outcomes: list[dict[str, Any]] = []
        rejected = False
        for order in orders:
            item = by_client[order["clientOrderId"]]
            code = bounded_error_code(item.get("sCode"))
            order_id = item.get("ordId")
            if code == "0" and isinstance(order_id, str) and order_id.strip():
                outcomes.append({**order, "status": "accepted", "exchangeOrderId": item["ordId"]})
            elif code is not None and int(code) != 0 and (
                "ordId" not in item or (isinstance(order_id, str) and order_id == "")
            ):
                rejected = True
                outcomes.append({**order, "status": "rejected", "errorCode": code})
            else:
                outcomes.append({**order, "status": "unknown"})
        if any(row["status"] == "unknown" for row in outcomes):
            return outcomes, "UNKNOWN", "batch_ack_malformed"
        if rejected:
            return outcomes, "PARTIAL", "order_rejected"
        if top_code in ("1", "2"):
            return outcomes, "UNKNOWN", "batch_top_level_conflict"
        return outcomes, "APPLIED", None

    def _mark_batch_attempted(self, strategy_id: str, execution_id: str) -> bool:
        now = self.clock()
        with self.store.transaction() as connection:
            changed = connection.execute(
                "UPDATE strategies SET batch_attempted=1, order_placement_attempted=1, "
                "execution_lease_until=?, updated_at=? "
                "WHERE strategy_id=? AND status='APPLYING' AND execution_id=? "
                "AND execution_lease_until>? AND batch_attempted=0",
                (now + _EXECUTION_LEASE_SECONDS, now, strategy_id, execution_id, now),
            )
            return changed.rowcount == 1

    def _finish(
        self,
        strategy_id: str,
        execution_id: str,
        status: str,
        orders: list[dict[str, Any]],
        error: str | None,
        leverage_results: list[dict[str, Any]],
    ) -> None:
        with self.store.transaction() as connection:
            current = connection.execute(
                "SELECT batch_attempted, order_placement_attempted FROM strategies "
                "WHERE strategy_id=? AND status='APPLYING' "
                "AND execution_id=?",
                (strategy_id, execution_id),
            ).fetchone()
            changed = connection.execute(
                "UPDATE strategies SET status=?, results_json=?, prepared_json=COALESCE(prepared_json, snapshot_json), "
                "leverage_results_json=?, failure_reason=?, execution_id=NULL, execution_lease_until=NULL, "
                "updated_at=? WHERE strategy_id=? AND status='APPLYING' AND execution_id=?",
                (
                    status, encode_json(orders), encode_json(leverage_results), error,
                    self.clock(), strategy_id, execution_id,
                ),
            ).rowcount
            if (
                changed == 1 and current is not None
                and self._can_release_reservation(
                    status, orders,
                    bool(current["batch_attempted"]) or bool(current["order_placement_attempted"]),
                )
            ):
                connection.execute(
                    "DELETE FROM strategy_reservations WHERE strategy_id=?", (strategy_id,)
                )
            if changed == 1:
                self._cleanup_replacement_in_connection(connection, strategy_id, self.clock())
        diagnostics.emit_event(
            "commit", component="api", stage="commit",
            outcome="committed" if changed == 1 else "refused",
            reason=None if changed == 1 else "fence_or_cas_loss",
            status=status, persisted=changed == 1,
            order_count=len(orders),
            accepted_count=sum(row.get("status") == "accepted" for row in orders),
            pending_count=sum(row.get("status") == "unknown" for row in orders),
            not_submitted_count=sum(row.get("status") == "not_submitted" for row in orders),
        )

    @staticmethod
    def _can_release_reservation(
        status: str, orders: list[dict[str, Any]], order_placement_attempted: bool
    ) -> bool:
        if status == "UNKNOWN":
            return not order_placement_attempted
        terminal = _ORDER_TERMINAL_STATES
        return status in ("APPLIED", "PARTIAL", "UNKNOWN", "COMPLETED") and all(
            row.get("status") in terminal for row in orders
        )

    def _reset_to_draft(self, strategy_id: str) -> None:
        with self.store.transaction() as connection:
            connection.execute(
                "UPDATE strategies SET status='DRAFT', confirmation_hash=NULL, prepared_expires_at=NULL, "
                "prepared_json=NULL, updated_at=? WHERE strategy_id=? AND status='PREPARED' AND attempt_started=0",
                (self.clock(), strategy_id),
            )

    def _load_row(self, strategy_id: str) -> dict[str, Any]:
        with self.store.connection() as connection:
            row = connection.execute("SELECT * FROM strategies WHERE strategy_id=?", (strategy_id,)).fetchone()
        if row is None:
            raise APIError(404, "strategy_not_found", "The strategy was not found.")
        return self._decode_row(row)

    def _can_replace_hint(self, strategy: dict[str, Any]) -> bool:
        fingerprint = strategy["accountFingerprint"]
        with self.store.connection() as connection:
            row = connection.execute(
                "SELECT * FROM strategies WHERE strategy_id=? AND account_fingerprint=?",
                (strategy["id"], fingerprint),
            ).fetchone()
            return row is not None and self._eligible_never_sent_record(
                connection, self._decode_row(row), fingerprint, self.clock()
            )

    def _can_delete_hint(
        self,
        strategy: dict[str, Any],
        *,
        terminal_positions: Any = None,
        terminal_positions_available: bool = False,
        order_sync_state: str | None = None,
    ) -> bool:
        fingerprint = strategy["accountFingerprint"]
        with self.store.connection() as connection:
            row = connection.execute(
                "SELECT * FROM strategies WHERE strategy_id=? AND account_fingerprint=?",
                (strategy["id"], fingerprint),
            ).fetchone()
            if row is None:
                return False
            current = self._decode_row(row)
            now = self.clock()
            if self._eligible_never_sent_record(connection, current, fingerprint, now):
                return True
            if (
                not terminal_positions_available
                or order_sync_state != "fresh"
                or not self._eligible_terminal_delete_record(
                    connection, current, fingerprint, now
                )
            ):
                return False
            scope = self._persisted_scope(current, require_prepared_mode=False)
            if not scope.valid:
                return False
            return self._positions_clear_for_instrument(
                terminal_positions, current["contract"]["instrumentId"], scope
            )

    def _replacement_cleanup_conflict(self, strategy: dict[str, Any]) -> bool:
        if not self._replacement_fully_accepted(
            strategy["status"], strategy["results"], strategy["orderPlacementAttempted"]
        ):
            return False
        source_id = strategy["replacementSourceId"]
        if not isinstance(source_id, str):
            return False
        with self.store.connection() as connection:
            row = connection.execute(
                "SELECT 1 FROM strategies WHERE strategy_id=? AND account_fingerprint=?",
                (source_id, strategy["accountFingerprint"]),
            ).fetchone()
        return row is not None

    def _try_cleanup_replacement_source(self, replacement_id: str) -> bool:
        with self.store.transaction() as connection:
            return self._cleanup_replacement_in_connection(
                connection, replacement_id, self.clock()
            )

    def _basic_result(
        self,
        strategy: dict[str, Any],
        *,
        terminal_positions: Any = None,
        terminal_positions_available: bool = False,
        order_sync_state: str | None = None,
    ) -> dict[str, Any]:
        status = strategy["status"]
        failure_reason = strategy["failureReason"]
        if self._legacy_never_sent(strategy):
            rejected_leverage = any(
                isinstance(row, dict) and row.get("status") == "rejected"
                for row in strategy["leverageResults"]
            )
            status = "PARTIAL"
            failure_reason = "leverage_rejected" if rejected_leverage else "never_sent"
        queue = strategy.get("queue")
        queue_status = None if queue is None else queue.get("phase")
        queue_counts = queue_progress(queue, strategy["results"]) if queue is not None else None
        if strategy.get("queueCorrupt") and strategy["submissionMode"] == "sequential":
            queue_status = "stopped"
        apply_outcome = (
            "queued"
            if strategy["submissionMode"] == "sequential"
            and status == "APPLYING"
            and queue_status in ("pending", "sending")
            else None
        )
        result = {
            "id": strategy["id"],
            "status": status,
            "instrumentId": strategy["contract"]["instrumentId"],
            "interval": strategy["contract"]["interval"],
            "sides": strategy["snapshot"].get("sides", []),
            "totalMargin": strategy["snapshot"].get("totalMargin"),
            "plannedMargin": strategy["snapshot"].get("plannedMargin"),
            "unallocatedMargin": strategy["snapshot"].get("unallocatedMargin"),
            "estimatedOpeningFees": strategy["snapshot"].get("estimatedOpeningFees"),
            "sidePercent": strategy["snapshot"].get("sidePercent", {}),
            "orders": strategy["results"] if strategy["results"] else strategy["orders"],
            "failureReason": failure_reason,
            "leverageResults": strategy["leverageResults"],
            "batchAttempted": strategy["batchAttempted"],
            "submissionMode": strategy["submissionMode"],
            "orderPlacementAttempted": strategy["orderPlacementAttempted"],
            "queueStatus": queue_status,
            "queueProgress": queue_counts,
            "applyOutcome": apply_outcome,
            "canDelete": self._can_delete_hint(
                strategy,
                terminal_positions=terminal_positions,
                terminal_positions_available=terminal_positions_available,
                order_sync_state=order_sync_state,
            ),
            "canReplace": self._can_replace_hint(strategy),
            "replacementCleanupConflict": self._replacement_cleanup_conflict(strategy),
            "createdAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(strategy["createdAt"])),
            "updatedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(strategy["updatedAt"])),
        }
        draft_stage = strategy["snapshot"].get("draftStage")
        ai_generation = strategy["snapshot"].get("aiGeneration")
        if draft_stage is not None:
            result["draftStage"] = draft_stage
        if isinstance(ai_generation, dict):
            result["aiGeneration"] = ai_generation
        lineage = self._public_retry_summary(strategy.get("contract"))
        if lineage is not None:
            result["resubmission"] = lineage
        return result

    def _result(self, strategy_id: str) -> dict[str, Any]:
        strategy, _, fingerprint = self._current_strategy(strategy_id)
        return self._result_for(strategy, fingerprint)

    def _result_for(self, strategy: dict[str, Any], fingerprint: str) -> dict[str, Any]:
        if self.automatic.is_candidate_stage(strategy):
            _, current_fingerprint = self._account()
            if not hmac.compare_digest(fingerprint, current_fingerprint):
                raise APIError(409, "account_changed", "The active OKX account changed.")
            return self.automatic.public_candidate_result(strategy)
        active_queue = (
            strategy["submissionMode"] == "sequential"
            and strategy["status"] == "APPLYING"
            and (strategy.get("queueCorrupt") or (
                isinstance(strategy.get("queue"), dict)
                and strategy["queue"].get("phase") in ("pending", "sending")
            ))
        )
        if strategy["replacementSourceId"] is not None and not active_queue:
            self._try_cleanup_replacement_source(strategy["id"])
        if strategy["status"] == "APPLYING" and not active_queue:
            lease_until = strategy["executionLeaseUntil"]
            if lease_until is None or lease_until <= self.clock():
                strategy = self._recover_interrupted_apply(strategy)
        elif not active_queue and strategy["status"] in ("UNKNOWN", "APPLIED", "PARTIAL"):
            if self._order_scan_due(strategy["id"]):
                strategy, scan_error = self._reconcile_orders_with_outcome(strategy)
                self._record_api_order_scan(strategy["id"], scan_error)
        try:
            account, current_fingerprint = self._account()
            if not hmac.compare_digest(fingerprint, current_fingerprint):
                raise APIError(409, "account_changed", "The active OKX account changed.")
        except APIError:
            raise
        position_status = "available"
        position_rows: list[dict[str, Any]] = []
        scope = self._persisted_scope(strategy, require_prepared_mode=False)
        try:
            raw_positions, valid_position_rows = self._terminal_delete_position_rows()
        except OKXError:
            raw_positions = None
            valid_position_rows = False
        relevant_positions = (
            None if raw_positions is None or not valid_position_rows or not scope.valid
            else scoped_position_rows(raw_positions, strategy["contract"]["instrumentId"], scope)
        )
        if relevant_positions is None:
            raw_positions = []
            position_status = "unavailable"
            actual = []
        else:
            actual = relevant_positions
        if position_status == "available" and actual:
            position_status = "present"
        if position_status == "available" and not actual:
            position_status = "none"
        for row in actual:
            position_rows.append({
                "side": row.get("posSide"),
                "contracts": row.get("pos"),
                "averageEntry": row.get("avgPx"),
                "markPrice": row.get("markPx"),
                "liquidationPrice": row.get("liqPx"),
                "unrealizedPnl": row.get("upl"),
                "marginMode": row.get("mgnMode"),
            })
        observed = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(self.clock()))
        filled_margin: Decimal | None = Decimal(0)
        expected_by_side = {"long": Decimal(0), "short": Decimal(0)}
        for row in strategy["results"]:
            filled = _decimal(row.get("filledContracts", "0")) or Decimal(0)
            if filled <= 0:
                continue
            order_price = _positive(row.get("averageFillPrice"))
            if order_price is None:
                filled_margin = None
                expected_by_side[row["side"]] += filled
                continue
            unit = Decimal(strategy["snapshot"]["_metadata"]["contractValue"]) * Decimal(
                strategy["snapshot"]["_metadata"]["contractMultiplier"]
            )
            margin = filled * order_price * unit / Decimal(str(row["leverage"]))
            if filled_margin is not None:
                filled_margin += margin
            expected_by_side[row["side"]] += filled
        pnl_values = [_decimal(row.get("upl")) for row in actual]
        pnl_values = [value for value in pnl_values if value is not None]
        pnl = sum(pnl_values, Decimal(0)) if pnl_values else None
        pnl_percent = (
            None
            if filled_margin is None or filled_margin <= 0 or pnl is None
            else pnl / filled_margin * Decimal(100)
        )
        attribution_changed: bool | None = None if position_status == "unavailable" else False
        actual_by_side = {"long": Decimal(0), "short": Decimal(0)}
        for row in actual:
            size = _decimal(row.get("pos"))
            if size is None:
                attribution_changed = True
                continue
            side = row.get("posSide")
            if side == "long":
                actual_by_side["long"] += abs(size)
            elif side == "short":
                actual_by_side["short"] += abs(size)
            elif side == "net":
                if size > 0:
                    actual_by_side["long"] += size
                elif size < 0:
                    actual_by_side["short"] += abs(size)
        if attribution_changed is not None and any(
            actual_by_side[side] != expected_by_side[side] for side in actual_by_side
        ):
            attribution_changed = True
        sync_fields = self._order_sync_fields(strategy["id"])
        result = self._basic_result(
            strategy,
            terminal_positions=raw_positions,
            terminal_positions_available=position_status != "unavailable",
            order_sync_state=sync_fields["orderSyncState"],
        )
        result.update({
            "orders": strategy["results"],
            "positionStatus": position_status,
            "positions": position_rows,
            "unrealizedPnl": _text(pnl),
            "filledMargin": _text(filled_margin),
            "usedMargin": _text(filled_margin),
            "pnlPercent": _text(pnl_percent),
            "attributionChanged": attribution_changed,
            "observedAt": observed,
            "positionMode": account.get("posMode"),
            **sync_fields,
        })
        return result

    def _order_scan_due(self, strategy_id: str) -> bool:
        now = self.clock()
        with self.store.connection() as connection:
            row = connection.execute(
                "SELECT last_attempt_at, last_success_at, last_error, next_scan_at "
                "FROM strategy_sync_state WHERE strategy_id=?",
                (strategy_id,),
            ).fetchone()
        if row is None:
            return True
        if row["next_scan_at"] is not None and row["next_scan_at"] > now:
            return False
        if row["last_error"]:
            return True
        last_success = row["last_success_at"]
        return last_success is None or now - last_success >= _ORDER_SCAN_INTERVAL_SECONDS

    def _record_api_order_scan(self, strategy_id: str, scan_error: str | None) -> None:
        now = self.clock()
        with self.store.transaction() as connection:
            if scan_error is None:
                connection.execute(
                    "INSERT INTO strategy_sync_state(strategy_id, last_attempt_at, last_success_at, "
                    "last_error, next_scan_at, consecutive_errors) VALUES (?, ?, ?, NULL, ?, 0) "
                    "ON CONFLICT(strategy_id) DO UPDATE SET last_attempt_at=excluded.last_attempt_at, "
                    "last_success_at=excluded.last_success_at, last_error=NULL, "
                    "next_scan_at=excluded.next_scan_at, consecutive_errors=0",
                    (strategy_id, now, now, now + _ORDER_SCAN_INTERVAL_SECONDS),
                )
            else:
                connection.execute(
                    "INSERT INTO strategy_sync_state(strategy_id, last_attempt_at, last_success_at, "
                    "last_error, next_scan_at, consecutive_errors) VALUES (?, ?, NULL, ?, ?, 1) "
                    "ON CONFLICT(strategy_id) DO UPDATE SET last_attempt_at=excluded.last_attempt_at, "
                    "last_error=excluded.last_error, next_scan_at=excluded.next_scan_at, "
                    "consecutive_errors=strategy_sync_state.consecutive_errors+1",
                    (strategy_id, now, scan_error, now),
                )

    def _order_sync_fields(self, strategy_id: str) -> dict[str, Any]:
        with self.store.connection() as connection:
            row = connection.execute(
                "SELECT last_success_at, last_error FROM strategy_sync_state WHERE strategy_id=?",
                (strategy_id,),
            ).fetchone()
        last_success = None if row is None else row["last_success_at"]
        last_error = None if row is None else row["last_error"]
        if last_success is None:
            state = "error" if last_error else "stale"
            formatted = None
        else:
            formatted = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(last_success))
            age = self.clock() - last_success
            state = "error" if last_error else "fresh" if 0 <= age <= _ORDER_SCAN_FRESH_SECONDS else "stale"
        return {"lastOrderScanAt": formatted, "orderSyncState": state}

    def _recover_interrupted_apply(self, strategy: dict[str, Any]) -> dict[str, Any]:
        if strategy["executionLeaseUntil"] is not None and strategy["executionLeaseUntil"] > self.clock():
            return strategy
        if strategy["batchAttempted"]:
            return self._reconcile_orders(strategy, recovering=True)
        self._finish_recovery(
            strategy, "UNKNOWN",
            [{**row, "status": "not_submitted"} for row in strategy["orders"]],
            "interrupted_before_batch",
        )
        return self._load_row(strategy["id"])

    def _finish_recovery(
        self, strategy: dict[str, Any], status: str, results: list[dict[str, Any]], error: str | None
    ) -> None:
        now = self.clock()
        with self.store.transaction() as connection:
            changed = connection.execute(
                "UPDATE strategies SET status=?, results_json=?, failure_reason=?, execution_id=NULL, "
                "execution_lease_until=NULL, updated_at=? WHERE strategy_id=? AND status='APPLYING' "
                "AND execution_id IS ? AND (execution_lease_until IS NULL OR execution_lease_until<=?)",
                (status, encode_json(results), error, now, strategy["id"], strategy["executionId"], now),
            ).rowcount
            if changed == 1 and self._can_release_reservation(
                status, results, strategy["orderPlacementAttempted"]
            ):
                connection.execute(
                    "DELETE FROM strategy_reservations WHERE strategy_id=?", (strategy["id"],)
                )

    def _reconcile_orders(self, strategy: dict[str, Any], *, recovering: bool = False) -> dict[str, Any]:
        return self._reconcile_orders_with_outcome(strategy, recovering=recovering)[0]

    def _reconcile_orders_with_outcome(
        self, strategy: dict[str, Any], *, recovering: bool = False
    ) -> tuple[dict[str, Any], str | None]:
        if not strategy["orderPlacementAttempted"]:
            return strategy, None
        if strategy["status"] == "APPLYING" and not recovering:
            return strategy, None
        results, scan_error, _ = _read_order_rows(strategy, self.okx, recovering=recovering)
        new_status, error = _reconciled_strategy_state(strategy, results, recovering=recovering)
        changed = results != strategy["results"]
        if changed or new_status != strategy["status"]:
            with self.store.transaction() as connection:
                if recovering:
                    now = self.clock()
                    saved = connection.execute(
                        "UPDATE strategies SET status=?, results_json=?, failure_reason=?, execution_id=NULL, "
                        "execution_lease_until=NULL, updated_at=? WHERE strategy_id=? AND status='APPLYING' "
                        "AND execution_id IS ? AND (execution_lease_until IS NULL OR execution_lease_until<=?)",
                        (
                            new_status, encode_json(results), error, now, strategy["id"],
                            strategy["executionId"], now,
                        ),
                    ).rowcount
                else:
                    saved = connection.execute(
                        "UPDATE strategies SET status=?, results_json=?, failure_reason=?, updated_at=? "
                        "WHERE strategy_id=? AND status=? AND results_json=?",
                        (
                            new_status, encode_json(results), error, self.clock(),
                            strategy["id"], strategy["status"], encode_json(strategy["results"]),
                        ),
                    ).rowcount
                if saved == 1 and self._can_release_reservation(
                    new_status, results, strategy["orderPlacementAttempted"]
                ):
                    connection.execute(
                        "DELETE FROM strategy_reservations WHERE strategy_id=?", (strategy["id"],)
                    )
            strategy = self._load_row(strategy["id"])
        if strategy["replacementSourceId"] is not None:
            self._try_cleanup_replacement_source(strategy["id"])
        return strategy, scan_error

    def _list(self) -> dict[str, Any]:
        _, fingerprint = self._account()
        with self.store.connection() as connection:
            rows = connection.execute(
                "SELECT * FROM strategies WHERE account_fingerprint=? ORDER BY created_at DESC, strategy_id DESC",
                (fingerprint,),
            ).fetchall()
        strategies: list[dict[str, Any]] = []
        for row in rows:
            with self.store.connection() as connection:
                current = connection.execute(
                    "SELECT * FROM strategies WHERE strategy_id=? AND account_fingerprint=?",
                    (row["strategy_id"], fingerprint),
                ).fetchone()
            if current is None:
                continue
            strategy = self._decode_row(current)
            self._expire_prepare(strategy)
            strategies.append(self._result_for(strategy, fingerprint))
        with self.store.connection() as connection:
            remaining_ids = {
                row["strategy_id"]
                for row in connection.execute(
                    "SELECT strategy_id FROM strategies WHERE account_fingerprint=?", (fingerprint,)
                ).fetchall()
            }
        return {"strategies": [row for row in strategies if row["id"] in remaining_ids]}

    def _delete(self, strategy_id: str) -> dict[str, Any]:
        strategy, _, fingerprint = self._current_strategy(strategy_id)
        now = self.clock()
        with self.store.transaction() as connection:
            current_row = connection.execute(
                "SELECT * FROM strategies WHERE strategy_id=?", (strategy_id,)
            ).fetchone()
            if current_row is None:
                raise APIError(404, "strategy_not_found", "The strategy was not found.")
            current = self._decode_row(current_row)
            if not hmac.compare_digest(current["accountFingerprint"], fingerprint):
                raise APIError(409, "account_changed", "This strategy belongs to a different OKX account.")
            if self.automatic.is_candidate_stage(current):
                reservation = connection.execute(
                    "SELECT 1 FROM strategy_reservations WHERE strategy_id=? LIMIT 1",
                    (strategy_id,),
                ).fetchone()
                replacement = connection.execute(
                    "SELECT 1 FROM strategies WHERE replacement_source_id=? LIMIT 1",
                    (strategy_id,),
                ).fetchone()
                safe_candidate = (
                    current["status"] == "DRAFT"
                    and not current["attemptStarted"]
                    and not current["orderPlacementAttempted"]
                    and not current["batchAttempted"]
                    and current.get("prepared") is None
                    and current.get("replacementSourceId") is None
                    and current.get("executionId") is None
                    and current.get("orders") == []
                    and current.get("results") == []
                    and reservation is None
                    and replacement is None
                )
                if not safe_candidate:
                    raise APIError(
                        409,
                        "strategy_immutable",
                        "Order placement and lifecycle state are not safe for deletion.",
                    )
                self._delete_strategy_with_dependents(connection, strategy_id)
                return {"id": strategy_id, "status": "DELETED"}
            if self._eligible_never_sent_record(connection, current, fingerprint, now):
                self._delete_strategy_with_dependents(connection, strategy_id)
                return {"id": strategy_id, "status": "DELETED"}
            if not self._eligible_terminal_delete_record(connection, current, fingerprint, now):
                raise APIError(
                    409,
                    "strategy_immutable",
                    "Order placement and lifecycle state are not safe for deletion.",
                )

            snapshot_row = dict(current_row)
            order_pairs = self._terminal_delete_order_pairs(current)
            if order_pairs is None:
                raise APIError(
                    409,
                    "strategy_immutable",
                    "Saved order evidence is incomplete or inconsistent.",
                )

        instrument_id = current["contract"]["instrumentId"]
        scope = self._persisted_scope(current, require_prepared_mode=False)
        if not scope.valid:
            raise APIError(
                409, "strategy_immutable",
                "The strategy position scope cannot be validated safely.",
            )
        prepared = current.get("prepared")
        position_mode = (
            prepared.get("_positionMode")
            if isinstance(prepared, dict) and prepared.get("_positionMode") is not None
            else current["snapshot"].get("_positionMode")
        )
        order_evidence_valid = True
        exchange_read_failed = False
        for order, result in order_pairs:
            if result.get("status") in {"rejected", "not_submitted"}:
                continue
            try:
                details = self._terminal_delete_order_details(
                    instrument_id, order["clientOrderId"]
                )
            except OKXError:
                details = None
                exchange_read_failed = True
            if not self._verified_terminal_order(
                instrument_id, position_mode, order, result, details
            ):
                order_evidence_valid = False

        try:
            positions, valid_position_rows = self._terminal_delete_position_rows()
        except OKXError:
            positions = None
            valid_position_rows = False
            exchange_read_failed = True
        if positions is None:
            exchange_read_failed = True

        _, current_fingerprint = self._account()
        if not hmac.compare_digest(fingerprint, current_fingerprint):
            raise APIError(409, "account_changed", "The active OKX account changed during deletion checks.")
        if exchange_read_failed:
            raise APIError(
                502,
                "exchange_unavailable",
                "Current order or position data is unavailable; the strategy was not deleted.",
            )
        if not order_evidence_valid:
            raise APIError(
                409,
                "strategy_immutable",
                "Current exchange order evidence is incomplete or no longer terminal.",
            )
        if not valid_position_rows or not self._positions_clear_for_instrument(positions, instrument_id, scope):
            raise APIError(
                409,
                "strategy_immutable",
                "A current position or uncertain position row prevents deletion.",
            )

        with self.store.transaction() as connection:
            latest_row = connection.execute(
                "SELECT * FROM strategies WHERE strategy_id=?", (strategy_id,)
            ).fetchone()
            if latest_row is None:
                raise APIError(404, "strategy_not_found", "The strategy was not found.")
            if dict(latest_row) != snapshot_row:
                raise APIError(
                    409,
                    "strategy_immutable",
                    "The strategy changed while deletion checks were running.",
                )
            latest = self._decode_row(latest_row)
            if not hmac.compare_digest(latest["accountFingerprint"], fingerprint):
                raise APIError(409, "account_changed", "This strategy belongs to a different OKX account.")
            if not self._eligible_terminal_delete_record(
                connection, latest, fingerprint, self.clock()
            ):
                raise APIError(
                    409,
                    "strategy_immutable",
                    "Order placement and lifecycle state changed during deletion checks.",
                )
            self._delete_strategy_with_dependents(connection, strategy_id)
        return {"id": strategy_id, "status": "DELETED"}
