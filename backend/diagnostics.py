"""Best-effort, privacy-bounded strategy submission diagnostics."""

from __future__ import annotations

import contextvars
import datetime as dt
import hashlib
import json
import math
import os
import queue
import re
import sys
import threading
import time
from contextlib import contextmanager
from typing import Any, Iterator, TextIO


SCHEMA_VERSION = 1
MAX_RECORD_BYTES = 4096
MAX_QUEUE_LENGTH = 256
MAX_DRAIN_SECONDS = 0.250

_ENUMS: dict[str, frozenset[str]] = {
    "event": frozenset({
        "request_start", "request_end", "request_failure", "prepare_result",
        "enqueue_result", "execute_noop", "worker_startup", "worker_shutdown",
        "worker_fatal", "heartbeat", "selection", "preflight", "write_attempt",
        "ack_observed", "commit", "queue_stop", "batch_summary", "okx_request",
        "diagnostic_drop",
    }),
    "component": frozenset({"api", "worker", "diagnostics"}),
    "stage": frozenset({
        "request", "prepare", "execute", "enqueue", "preflight", "preflight_initial",
        "preflight_resume", "preflight_post_leverage", "leverage",
        "order", "batch", "commit", "queue", "startup", "shutdown", "fatal",
        "heartbeat", "selection", "sink", "account_config", "positions",
        "pending_orders", "account_balance", "trade_fee", "position_tiers",
        "instruments", "ticker", "order_details", "retry_candidates",
        "retry_preview", "retry_draft",
    }),
    "outcome": frozenset({
        "started", "success", "failure", "queued", "noop", "leased", "lease_busy",
        "account_read_failed", "invalid_account", "no_due", "selected", "attempted",
        "accepted", "rejected", "unknown", "applied", "stopped", "refused",
        "persisted", "unpersisted", "expired", "changed", "malformed",
        "transport_failure", "http_rejected", "oversized", "nonobject_response",
        "malformed_json", "malformed_data", "exchange_rejected", "committed",
        "dropped", "other",
    }),
    "reason": frozenset({
        "other", "origin_denied", "authentication_failed", "invalid_request",
        "body_invalid", "service_unavailable", "internal_error", "strategy_stale",
        "account_changed", "account_mode_unsupported", "position_exists",
        "pending_order_exists", "insufficient_balance", "confirmation_invalid",
        "strategy_immutable", "strategy_state_changed", "prepared_invalid",
        "queue_expired", "queue_stopped", "preflight_failed", "lease_busy",
        "lease_lost", "account_read_failed", "account_identity_invalid", "no_due",
        "marker_refused", "http_rejected", "response_oversized", "malformed_json",
        "nonobject_response", "malformed_data", "transport_failure",
        "exchange_rejected", "missing_code", "invalid_code", "top_level_conflict",
        "data_cardinality", "invalid_row", "duplicate_client_id",
        "client_identity_mismatch", "missing_order_id", "leverage_identity_mismatch",
        "sink_failed", "sink_full", "ack_unknown", "order_rejected", "order_unknown",
        "leverage_rejected", "leverage_unknown", "batch_unknown", "batch_top_level_conflict",
        "fence_or_cas_loss",
        "preflight_unavailable", "preview_changed", "position_mode_changed",
        "resume_validation_failed", "deadline_before_write", "interrupted_order_attempt",
        "interrupted_leverage_attempt", "account_mode_unsupported",
        "order_ack_malformed", "batch_ack_malformed", "batch_response_unavailable",
        "preflight_changed_after_leverage", "preflight_failed_after_leverage",
        "retry_source_unavailable", "retry_selection_invalid", "retry_source_stale",
        "retry_selection_in_use", "retry_request_conflict", "retry_preview_stale",
        "exchange_rate_limited",
    }),
    "endpoint": frozenset({
        "account_config", "positions", "pending_orders", "account_balance",
        "trade_fee", "instruments", "ticker", "position_tiers", "set_leverage",
        "place_order", "batch_orders",
    }),
    "method": frozenset({"GET", "POST", "other"}),
    "submission_mode": frozenset({"sequential", "batch", "legacy"}),
    "side": frozenset({"long", "short", "net"}),
    "status": frozenset({
        "DRAFT", "PREPARED", "APPLYING", "APPLIED", "PARTIAL", "UNKNOWN",
        "COMPLETED", "accepted", "rejected", "unknown", "not_submitted",
        "applied", "sending", "pending", "stopped",
    }),
    "ack_shape": frozenset({
        "valid", "missing_code", "invalid_code", "top_level_conflict",
        "data_cardinality", "invalid_row", "duplicate_client_id",
        "client_identity_mismatch", "missing_order_id", "leverage_identity_mismatch",
        "nonobject_data", "invalid_data_type", "malformed",
    }),
}

_API_CODES = frozenset({
    "origin_denied", "service_not_configured", "json_required", "invalid_content_length",
    "body_too_large", "invalid_json", "internal_error", "unauthorized", "forbidden",
    "strategy_not_found", "strategy_immutable", "replacement_source_unavailable",
    "account_changed", "account_mode_unsupported", "account_preflight_unavailable",
    "instrument_position_exists", "pending_order_exists", "insufficient_balance",
    "strategy_stale", "strategy_settings_unavailable", "strategy_state_changed",
    "invalid_confirmation", "prepared_strategy_invalid", "instrument_apply_in_progress",
    "not_found", "method_not_allowed", "invalid_request", "account_identity_unavailable",
    "authentication_required",
    "preview_inputs_unavailable", "quote_stale", "quote_invalid", "strategy_expired",
        "strategy_result_unavailable", "strategy_state_unavailable", "strategy_rate_limited",
    "retry_source_unavailable", "retry_selection_invalid", "retry_source_stale",
    "retry_selection_in_use", "retry_request_conflict", "retry_preview_stale",
    "exchange_rate_limited",
})
_NUMERIC_CODE = re.compile(r"[0-9]{1,12}\Z")
_ENDPOINTS = {
    "/api/v5/account/config": ("account_config", "account_config"),
    "/api/v5/account/positions": ("positions", "positions"),
    "/api/v5/trade/orders-pending": ("pending_orders", "pending_orders"),
    "/api/v5/account/balance": ("account_balance", "account_balance"),
    "/api/v5/account/trade-fee": ("trade_fee", "trade_fee"),
    "/api/v5/public/instruments": ("instruments", "instruments"),
    "/api/v5/market/ticker": ("ticker", "ticker"),
    "/api/v5/public/position-tiers": ("position_tiers", "position_tiers"),
    "/api/v5/account/set-leverage": ("set_leverage", "leverage"),
    "/api/v5/trade/order": ("place_order", "order"),
    "/api/v5/trade/batch-orders": ("batch_orders", "batch"),
}
_STRATEGY_ROUTE = re.compile(
    r"/v1/strategies/([A-Za-z0-9_-]{8,64})/"
    r"(prepare-apply|execute-apply|retry-candidates|retry-preview|retry-drafts)\Z"
)


def _ref(prefix: str, value: Any) -> str | None:
    if not isinstance(value, (str, int)) or isinstance(value, bool):
        return None
    if isinstance(value, str) and len(value) > 256:
        return None
    token = f"strategy-diagnostics:v1:{prefix}:{value}".encode("utf-8", "replace")
    return prefix[0] + "_" + hashlib.sha256(token).hexdigest()[:16]


def strategy_ref(value: Any) -> str | None:
    return _ref("strategy", value)


def order_ref(value: Any) -> str | None:
    return _ref("order", value)


_CONTEXT: contextvars.ContextVar[dict[str, str] | None] = contextvars.ContextVar(
    "strategy_diagnostics_context", default=None
)


def current_context() -> dict[str, str] | None:
    value = _CONTEXT.get()
    return None if value is None else dict(value)


@contextmanager
def strategy_context(
    strategy_id: Any,
    *,
    component: str | None = None,
    submission_mode: str | None = None,
) -> Iterator[None]:
    prior = current_context() or {}
    hashed = strategy_ref(strategy_id)
    value = dict(prior)
    if hashed is not None:
        value["strategy_ref"] = hashed
    if isinstance(component, str) and component in _ENUMS["component"]:
        value["component"] = component
    if isinstance(submission_mode, str) and submission_mode in _ENUMS["submission_mode"]:
        value["submission_mode"] = submission_mode
    token = _CONTEXT.set(value)
    try:
        yield
    finally:
        _CONTEXT.reset(token)


def set_submission_mode(value: Any) -> None:
    current = current_context()
    if current is None:
        return
    if not isinstance(value, str) or value not in _ENUMS["submission_mode"]:
        current.pop("submission_mode", None)
    else:
        current["submission_mode"] = value
    _CONTEXT.set(current)


def classified_strategy_route(method: Any, path: Any) -> tuple[str, str] | None:
    if not isinstance(path, str):
        return None
    match = _STRATEGY_ROUTE.fullmatch(path)
    if match is None:
        return None
    action = match.group(2)
    normalized_method = method.upper() if isinstance(method, str) else ""
    stages = {
        ("POST", "prepare-apply"): "prepare",
        ("POST", "execute-apply"): "execute",
        ("GET", "retry-candidates"): "retry_candidates",
        ("POST", "retry-preview"): "retry_preview",
        ("POST", "retry-drafts"): "retry_draft",
    }
    stage = stages.get((normalized_method, action))
    if stage is not None:
        return match.group(1), stage
    return None


def endpoint_for_path(path: Any) -> tuple[str, str] | None:
    if not isinstance(path, str):
        return None
    return _ENDPOINTS.get(path)


def _bounded_code(value: Any) -> str | None:
    if isinstance(value, bool) or not isinstance(value, (str, int)):
        return None
    token = str(value)
    if len(token) > 12:
        return None
    return token if _NUMERIC_CODE.fullmatch(token) else None


def _bounded_integer(value: Any, maximum: int, *, minimum: int = 0) -> int | None:
    if isinstance(value, bool) or not isinstance(value, int) or value < minimum:
        return None
    return min(value, maximum)


def _bounded_elapsed(value: Any) -> int | None:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    if not math.isfinite(float(value)) or value < 0:
        return None
    return min(int(value), 600_000)


def _new_record(event: str, fields: dict[str, Any]) -> dict[str, Any] | None:
    if event not in _ENUMS["event"]:
        return None
    record: dict[str, Any] = {
        "timestamp": dt.datetime.now(dt.timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z"),
        "event": event,
    }
    context = current_context() or {}
    merged = {**context, **fields}
    field_enums = {
        "component", "stage", "outcome", "reason", "endpoint", "method",
        "submission_mode", "side", "status", "ack_shape",
    }
    for name in field_enums:
        value = merged.get(name)
        if value is not None:
            if not isinstance(value, str) or len(value) > 64 or value not in _ENUMS[name]:
                return None
            record[name] = value
    if "component" not in record:
        record["component"] = "diagnostics"
    for name in ("strategy_ref", "order_ref"):
        value = merged.get(name)
        if value is not None:
            if not isinstance(value, str) or re.fullmatch(r"[so]_[0-9a-f]{16}", value) is None:
                return None
            record[name] = value
    count_bounds = {
        "order_index": (19, 0), "order_count": (20, 0), "attempted_count": (20, 0),
        "accepted_count": (20, 0), "pending_count": (20, 0),
        "not_submitted_count": (20, 0), "eligible_count": (1_000_000, 0),
        "matching_eligible_count": (1_000_000, 0), "selected_count": (1_000_000, 0),
        "pass_count": (1_000_000, 0), "dropped_count": (1_000_000, 0),
        "data_count": (21, 0),
    }
    for name, (maximum, minimum) in count_bounds.items():
        if name in merged and merged[name] is not None:
            value = _bounded_integer(merged[name], maximum, minimum=minimum)
            if value is None:
                return None
            record[name] = value
    if "http_status" in merged and merged["http_status"] is not None:
        value = merged["http_status"]
        if isinstance(value, bool) or not isinstance(value, int) or not 100 <= value <= 599:
            return None
        record["http_status"] = value
    if "elapsed_ms" in merged and merged["elapsed_ms"] is not None:
        value = _bounded_elapsed(merged["elapsed_ms"])
        if value is None:
            return None
        record["elapsed_ms"] = value
    for name in ("top_code", "item_code"):
        if name in merged and merged[name] is not None:
            value = _bounded_code(merged[name])
            if value is not None:
                record[name] = value
    if "api_code" in merged and merged["api_code"] is not None:
        value = merged["api_code"]
        if not isinstance(value, str):
            return None
        record["api_code"] = value if len(value) <= 64 and value in _API_CODES else "other"
    if "persisted" in merged and merged["persisted"] is not None:
        if not isinstance(merged["persisted"], bool):
            return None
        record["persisted"] = merged["persisted"]
    return record


def _encode(record: dict[str, Any]) -> str | None:
    try:
        value = json.dumps(record, ensure_ascii=True, separators=(",", ":"), allow_nan=False)
    except (TypeError, ValueError):
        return None
    if len(value.encode("utf-8")) > MAX_RECORD_BYTES:
        return None
    return value


def _drop_record(count: int) -> dict[str, Any]:
    return {
        "timestamp": dt.datetime.now(dt.timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z"),
        "event": "diagnostic_drop", "component": "diagnostics", "stage": "sink",
        "outcome": "dropped", "reason": "sink_full", "dropped_count": min(count, 1_000_000),
    }


class _Sink:
    """One process-local bounded queue and stderr writer."""

    def __init__(self, *, maxsize: int = MAX_QUEUE_LENGTH, stream: TextIO | None = None):
        self._maxsize = maxsize
        self._stream = stream
        self._pid = os.getpid()
        self._queue: queue.Queue[str | None] = queue.Queue(maxsize=maxsize)
        self._lock = threading.Lock()
        self._thread: threading.Thread | None = None
        self._dropped = 0
        self._drop_lock = threading.Lock()

    def reset_after_fork(self) -> None:
        self._pid = os.getpid()
        self._queue = queue.Queue(maxsize=self._maxsize)
        self._lock = threading.Lock()
        self._thread = None
        self._dropped = 0
        self._drop_lock = threading.Lock()

    def _ensure_process(self) -> None:
        if os.getpid() != self._pid:
            self.reset_after_fork()

    def _ensure_started(self) -> None:
        self._ensure_process()
        thread = self._thread
        if thread is not None and thread.is_alive():
            return
        with self._lock:
            thread = self._thread
            if thread is None or not thread.is_alive():
                thread = threading.Thread(target=self._run, name="strategy-diagnostics", daemon=True)
                self._thread = thread
                thread.start()

    def _increment_dropped(self, amount: int = 1) -> None:
        with self._drop_lock:
            self._dropped = min(1_000_000, self._dropped + amount)

    def _take_dropped(self) -> int:
        with self._drop_lock:
            value = self._dropped
            self._dropped = 0
            return value

    def emit_record(self, record: dict[str, Any]) -> bool:
        self._ensure_process()
        value = _encode(record)
        if value is None:
            self._increment_dropped()
            return False
        try:
            self._ensure_started()
            self._queue.put_nowait(value)
            return True
        except (queue.Full, RuntimeError, OSError):
            self._increment_dropped()
            return False
        except Exception:
            self._increment_dropped()
            return False

    def _write(self, value: str) -> None:
        stream = self._stream or sys.stderr
        stream.write(value + "\n")
        stream.flush()

    def _run(self) -> None:
        while True:
            value = self._queue.get()
            try:
                if value is None:
                    return
                dropped = self._take_dropped()
                if dropped:
                    try:
                        encoded = _encode(_drop_record(dropped))
                        if encoded is not None:
                            self._write(encoded)
                    except Exception:
                        self._increment_dropped(dropped)
                try:
                    self._write(value)
                except Exception:
                    self._increment_dropped()
            finally:
                self._queue.task_done()

    def drain(self, timeout: float = MAX_DRAIN_SECONDS) -> bool:
        self._ensure_process()
        bounded = min(max(float(timeout), 0.0), MAX_DRAIN_SECONDS)
        deadline = time.monotonic() + bounded
        condition = self._queue.all_tasks_done
        with condition:
            while self._queue.unfinished_tasks:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    return False
                condition.wait(remaining)
            return True

    def shutdown(self, timeout: float = MAX_DRAIN_SECONDS) -> bool:
        bounded = min(max(float(timeout), 0.0), MAX_DRAIN_SECONDS)
        started = time.monotonic()
        drained = self.drain(bounded)
        if not drained:
            return False
        try:
            self._queue.put_nowait(None)
        except queue.Full:
            return False
        thread = self._thread
        if thread is not None:
            thread.join(max(0.0, bounded - (time.monotonic() - started)))
        return thread is None or not thread.is_alive()


_DEFAULT_SINK = _Sink()
if hasattr(os, "register_at_fork"):
    os.register_at_fork(after_in_child=_DEFAULT_SINK.reset_after_fork)


def emit_event(
    event: str,
    *,
    component: str | None = None,
    stage: str | None = None,
    outcome: str | None = None,
    reason: str | None = None,
    endpoint: str | None = None,
    method: str | None = None,
    submission_mode: str | None = None,
    side: str | None = None,
    status: str | None = None,
    ack_shape: str | None = None,
    strategy_id: Any = None,
    client_order_id: Any = None,
    order_index: Any = None,
    order_count: Any = None,
    attempted_count: Any = None,
    accepted_count: Any = None,
    pending_count: Any = None,
    not_submitted_count: Any = None,
    eligible_count: Any = None,
    matching_eligible_count: Any = None,
    selected_count: Any = None,
    pass_count: Any = None,
    dropped_count: Any = None,
    http_status: Any = None,
    top_code: Any = None,
    item_code: Any = None,
    api_code: Any = None,
    elapsed_ms: Any = None,
    data_count: Any = None,
    persisted: Any = None,
    **unexpected: Any,
) -> bool:
    """Validate, serialize and enqueue one allow-listed event without raising."""
    try:
        if unexpected:
            _DEFAULT_SINK._increment_dropped()
            return False
        hashed_strategy = strategy_ref(strategy_id) if strategy_id is not None else None
        hashed_order = order_ref(client_order_id) if client_order_id is not None else None
        if (strategy_id is not None and hashed_strategy is None) or (
            client_order_id is not None and hashed_order is None
        ):
            _DEFAULT_SINK._increment_dropped()
            return False
        fields: dict[str, Any] = {
            "component": component, "stage": stage, "outcome": outcome, "reason": reason,
            "endpoint": endpoint, "method": method, "submission_mode": submission_mode,
            "side": side, "status": status, "ack_shape": ack_shape,
            "strategy_ref": hashed_strategy,
            "order_ref": hashed_order,
            "order_index": order_index, "order_count": order_count,
            "attempted_count": attempted_count, "accepted_count": accepted_count,
            "pending_count": pending_count, "not_submitted_count": not_submitted_count,
            "eligible_count": eligible_count, "matching_eligible_count": matching_eligible_count,
            "selected_count": selected_count, "pass_count": pass_count,
            "dropped_count": dropped_count, "http_status": http_status,
            "top_code": top_code, "item_code": item_code, "api_code": api_code,
            "elapsed_ms": elapsed_ms, "data_count": data_count, "persisted": persisted,
        }
        clean = {name: value for name, value in fields.items() if value is not None}
        record = _new_record(event, clean)
        if record is None:
            _DEFAULT_SINK._increment_dropped()
            return False
        return _DEFAULT_SINK.emit_record(record)
    except Exception:
        try:
            _DEFAULT_SINK._increment_dropped()
        except Exception:
            pass
        return False


def safe_api_code(value: Any) -> str:
    return value if isinstance(value, str) and len(value) <= 64 and value in _API_CODES else "other"


def safe_reason(value: Any, fallback: str = "other") -> str:
    if isinstance(value, str) and len(value) <= 64 and value in _ENUMS["reason"]:
        return value
    return fallback if fallback in _ENUMS["reason"] else "other"


def okx_category_reason(value: Any) -> tuple[str, str]:
    mapping = {
        "http_rejected": ("http_rejected", "http_rejected"),
        "response_oversized": ("oversized", "response_oversized"),
        "malformed_json": ("malformed_json", "malformed_json"),
        "nonobject_response": ("nonobject_response", "nonobject_response"),
        "malformed_data": ("malformed_data", "malformed_data"),
        "exchange_rejected": ("exchange_rejected", "exchange_rejected"),
        "transport_failure": ("transport_failure", "transport_failure"),
    }
    return mapping.get(value, mapping["transport_failure"])


def should_emit_heartbeat(now: float, *, interval: float = 60.0) -> bool:
    _heartbeat_state.ensure_process()
    return _heartbeat_state.mark(now, interval)


class _HeartbeatState:
    def __init__(self) -> None:
        self.pid = os.getpid()
        self.lock = threading.Lock()
        self.last: float | None = None

    def ensure_process(self) -> None:
        if os.getpid() != self.pid:
            self.pid = os.getpid()
            self.lock = threading.Lock()
            self.last = None

    def mark(self, now: float, interval: float) -> bool:
        with self.lock:
            if self.last is None or now - self.last >= interval:
                self.last = now
                return True
            return False


_heartbeat_state = _HeartbeatState()
if hasattr(os, "register_at_fork"):
    os.register_at_fork(after_in_child=_heartbeat_state.ensure_process)


def flush(timeout: float = MAX_DRAIN_SECONDS) -> bool:
    try:
        return _DEFAULT_SINK.drain(timeout)
    except Exception:
        return False


def shutdown(timeout: float = MAX_DRAIN_SECONDS) -> bool:
    try:
        return _DEFAULT_SINK.shutdown(timeout)
    except Exception:
        return False
