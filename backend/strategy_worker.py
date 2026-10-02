"""Separately supervised read-only monitor for already-submitted strategy orders."""

from __future__ import annotations

import os
import re
import secrets
import signal
import threading
import time
from dataclasses import dataclass
from typing import Any, Callable

from .okx import OKXClient, OKXError, OKXTransportError, Transport, bounded_error_code
from .security import token_digest
from .store import SQLiteStore, encode_json
from .strategy import (
    _ORDER_TERMINAL_STATES,
    _decimal,
    _read_order_rows,
    _reconciled_strategy_state,
    StrategyService,
)
from .strategy_queue import (
    MAX_PLACEMENTS_PER_PASS,
    MIN_PLACEMENT_SPACING_SECONDS,
    StrategyQueueLedger,
    new_queue,
    normalize_queue,
    parse_leverage_ack,
    parse_order_ack,
    stop_queue,
    _ack_decimal,
)
from .service import APIError
from . import diagnostics


_REQUIRED_ENV = (
    "OKX_API_KEY",
    "OKX_API_SECRET",
    "OKX_API_PASSPHRASE",
    "SESSION_SIGNING_KEY",
    "OPERATION_DB_PATH",
)
_MAX_ORDERS_PER_STRATEGY = 20
_MAX_STRATEGIES_PER_PASS = 20
_MAX_BACKOFF_SECONDS = 300


class _MonitorLeaseLost(Exception):
    pass


class _QueueDeadline(Exception):
    pass


class _LeaseAwareExchange:
    """Renew the worker fence immediately before each queue preflight call."""

    def __init__(self, exchange: Any, before_call: Callable[[str], None]):
        self._exchange = exchange
        self._before_call = before_call

    def __getattr__(self, name: str) -> Any:
        target = getattr(self._exchange, name)
        if not callable(target):
            return target

        def fenced_call(*args: Any, **kwargs: Any) -> Any:
            self._before_call(name)
            return target(*args, **kwargs)

        return fenced_call


@dataclass(frozen=True)
class WorkerSettings:
    okx_api_key: str
    okx_api_secret: str
    okx_api_passphrase: str
    session_signing_key: bytes
    operation_db_path: str

    def __post_init__(self) -> None:
        if any(not isinstance(value, str) or not value for value in (
            self.okx_api_key, self.okx_api_secret, self.okx_api_passphrase, self.operation_db_path,
        )):
            raise ValueError("worker is not configured")
        if len(self.session_signing_key) != 32:
            raise ValueError("worker is not configured")
        if not os.path.isabs(self.operation_db_path):
            raise ValueError("worker is not configured")

    @classmethod
    def from_environ(cls, environ: dict[str, str] | None = None) -> "WorkerSettings":
        source = os.environ if environ is None else environ
        values = {name: source.get(name, "") for name in _REQUIRED_ENV}
        if any(not value for value in values.values()):
            raise ValueError("worker is not configured")
        if re.fullmatch(r"[0-9a-fA-F]{64}", values["SESSION_SIGNING_KEY"]) is None:
            raise ValueError("worker is not configured")
        try:
            signing_key = bytes.fromhex(values["SESSION_SIGNING_KEY"])
        except ValueError:
            raise ValueError("worker is not configured") from None
        return cls(
            okx_api_key=values["OKX_API_KEY"],
            okx_api_secret=values["OKX_API_SECRET"],
            okx_api_passphrase=values["OKX_API_PASSPHRASE"],
            session_signing_key=signing_key,
            operation_db_path=values["OPERATION_DB_PATH"],
        )


class StrategyOrderWorker:
    """Owns one expiring SQLite lease and reconciles no more than 20 order reads per pass."""

    def __init__(
        self,
        settings: WorkerSettings,
        *,
        store: SQLiteStore | None = None,
        okx: Any | None = None,
        transport: Transport | None = None,
        clock: Callable[[], float] = time.time,
        owner_id: str | None = None,
        lease_seconds: float = 30,
        order_interval_seconds: float = 5,
        call_spacing_seconds: float = 0.1,
        sleep: Callable[[float], None] = time.sleep,
        monotonic: Callable[[], float] = time.monotonic,
    ):
        if lease_seconds <= 0 or order_interval_seconds <= 0 or call_spacing_seconds < 0:
            raise ValueError("worker timing is invalid")
        self.settings = settings
        self.store = store or SQLiteStore(settings.operation_db_path)
        self.store.initialize()
        self.clock = clock
        self.owner_id = owner_id or secrets.token_urlsafe(24)
        self.lease_seconds = lease_seconds
        self.order_interval_seconds = order_interval_seconds
        self.call_spacing_seconds = call_spacing_seconds
        self.sleep = sleep
        self.monotonic = monotonic
        self.okx = okx or OKXClient(
            settings.okx_api_key,
            settings.okx_api_secret,
            settings.okx_api_passphrase,
            transport=transport,
            clock=clock,
        )
        # StrategyService supplies the shared row decoder and reconciliation contract.
        self.strategy = StrategyService(self)
        self._queue_placements_this_pass = 0
        self._last_call_monotonic: float | None = None
        self._last_placement_monotonic: float | None = None

    def _account_fingerprint(self, uid: Any) -> str | None:
        if isinstance(uid, bool) or not isinstance(uid, (str, int)):
            return None
        normalized = str(uid).strip()
        if not normalized:
            return None
        return token_digest("okx-account-uid:v1:" + normalized, self.settings.session_signing_key)

    @staticmethod
    def _valid_account_fingerprint(value: Any) -> bool:
        return isinstance(value, str) and re.fullmatch(r"[0-9a-f]{64}", value) is not None

    def run_once(self) -> bool:
        now = self.clock()
        if diagnostics.should_emit_heartbeat(now):
            diagnostics.emit_event(
                "heartbeat", component="worker", stage="heartbeat", outcome="success",
                pass_count=1,
            )
        try:
            return self._run_once()
        except Exception:
            diagnostics.emit_event(
                "worker_fatal", component="worker", stage="fatal", outcome="failure",
                reason="other",
            )
            raise

    def _run_once(self) -> bool:
        """Run one bounded pass. False means another live worker owns the lease."""
        now = self.clock()
        self._queue_placements_this_pass = 0
        fence = self.store.acquire_strategy_monitor_lease(self.owner_id, now, self.lease_seconds)
        if fence is None:
            diagnostics.emit_event(
                "selection", component="worker", stage="selection", outcome="lease_busy",
                reason="lease_busy", pass_count=1,
            )
            return False
        try:
            self._ensure_lease(fence)
            account = self.okx.account_config()
        except OKXError:
            diagnostics.emit_event(
                "selection", component="worker", stage="selection", outcome="account_read_failed",
                reason="account_read_failed", pass_count=1,
            )
            return True
        fingerprint = self._account_fingerprint(account.get("uid"))
        if fingerprint is None:
            diagnostics.emit_event(
                "selection", component="worker", stage="selection", outcome="invalid_account",
                reason="account_identity_invalid", pass_count=1,
            )
            return True
        eligible_count, matching_count = self._eligible_counts(fingerprint, now)
        selected_count = 0
        pass_count = 0
        for _ in range(_MAX_STRATEGIES_PER_PASS):
            pass_count += 1
            try:
                self._ensure_lease(fence)
            except _MonitorLeaseLost:
                diagnostics.emit_event(
                    "selection", component="worker", stage="selection", outcome="failure",
                    reason="lease_lost", eligible_count=eligible_count,
                    matching_eligible_count=matching_count, selected_count=selected_count,
                    pass_count=pass_count,
                )
                break
            strategy = self._next_due_strategy(fingerprint, self.clock())
            if strategy is None:
                diagnostics.emit_event(
                    "selection", component="worker", stage="selection", outcome="no_due",
                    reason="no_due", eligible_count=eligible_count,
                    matching_eligible_count=matching_count, selected_count=selected_count,
                    pass_count=pass_count,
                )
                break
            selected_count += 1
            diagnostics.emit_event(
                "selection", component="worker", stage="selection", outcome="selected",
                strategy_id=strategy.get("id"), status=strategy.get("status"),
                submission_mode=strategy.get("submissionMode") if strategy.get("submissionMode") in {
                    "sequential", "batch", "legacy"
                } else None,
                eligible_count=eligible_count, matching_eligible_count=matching_count,
                selected_count=selected_count, pass_count=pass_count,
            )
            try:
                self._process_strategy(strategy, fence)
            except _MonitorLeaseLost:
                diagnostics.emit_event(
                    "selection", component="worker", stage="selection", outcome="failure",
                    reason="lease_lost", strategy_id=strategy.get("id"),
                    eligible_count=eligible_count, matching_eligible_count=matching_count,
                    selected_count=selected_count, pass_count=pass_count,
                )
                break
        return True

    def _eligible_counts(self, fingerprint: str, now: float) -> tuple[int | None, int | None]:
        """Count due reconciliation candidates across accounts and for this account."""
        try:
            with self.store.connection() as connection:
                rows = connection.execute(
                    "SELECT s.account_fingerprint, COUNT(*) AS candidate_count FROM strategies AS s "
                    "LEFT JOIN strategy_sync_state AS sync ON sync.strategy_id=s.strategy_id "
                    "WHERE s.attempt_started=1 AND s.status IN ('APPLYING', 'UNKNOWN', 'APPLIED', 'PARTIAL') "
                    "AND ((s.status='APPLYING' AND s.submission_mode='sequential' AND s.queue_json IS NOT NULL) "
                    "OR (s.status='APPLYING' AND (s.submission_mode!='sequential' OR s.queue_json IS NULL) "
                    "AND (s.execution_lease_until IS NULL OR s.execution_lease_until<=?)) "
                    "OR (s.status!='APPLYING' AND (s.batch_attempted=1 OR s.order_placement_attempted=1))) "
                    "AND COALESCE(sync.next_scan_at, 0)<=? GROUP BY s.account_fingerprint",
                    (now, now),
                ).fetchall()
        except Exception:
            return None, None
        try:
            eligible = sum(row["candidate_count"] for row in rows)
            matching = sum(
                row["candidate_count"] for row in rows if row["account_fingerprint"] == fingerprint
            )
            return min(int(eligible), 1_000_000), min(int(matching), 1_000_000)
        except Exception:
            return None, None

    def _next_due_strategy(self, fingerprint: str, now: float) -> dict[str, Any] | None:
        with self.store.connection() as connection:
            row = connection.execute(
                "SELECT s.* FROM strategies AS s "
                "LEFT JOIN strategy_sync_state AS sync ON sync.strategy_id=s.strategy_id "
                "WHERE s.account_fingerprint=? AND s.attempt_started=1 AND s.status IN "
                "('APPLYING', 'UNKNOWN', 'APPLIED', 'PARTIAL') "
                "AND ((s.status='APPLYING' AND s.submission_mode='sequential' AND s.queue_json IS NOT NULL) "
                "OR (s.status='APPLYING' AND (s.submission_mode!='sequential' OR s.queue_json IS NULL) "
                "AND (s.execution_lease_until IS NULL OR s.execution_lease_until<=?)) "
                "OR (s.status!='APPLYING' AND (s.batch_attempted=1 OR s.order_placement_attempted=1))) "
                "AND COALESCE(sync.next_scan_at, 0)<=? "
                "ORDER BY COALESCE(sync.next_scan_at, 0), COALESCE(sync.last_attempt_at, 0), "
                "s.created_at, s.strategy_id LIMIT 1",
                (fingerprint, now, now),
            ).fetchone()
        return None if row is None else self.strategy._decode_row(row)

    def _lease_is_current(self, connection: Any, fence: int, now: float) -> bool:
        row = connection.execute(
            "SELECT 1 FROM strategy_monitor_lease WHERE singleton=1 AND owner_id=? "
            "AND fence=? AND lease_until>?",
            (self.owner_id, fence, now),
        ).fetchone()
        return row is not None

    def _ensure_lease(self, fence: int) -> None:
        if not self.store.renew_strategy_monitor_lease(
            self.owner_id, fence, self.clock(), self.lease_seconds, clock=self.clock
        ):
            raise _MonitorLeaseLost

    def _before_order_call(self, fence: int) -> None:
        self._pace()
        self._ensure_lease(fence)

    def _write_attempt(self, strategy_id: str, fence: int) -> tuple[int, float] | None:
        now = self.clock()
        with self.store.transaction() as connection:
            if not self._lease_is_current(connection, fence, now):
                return None
            row = connection.execute(
                "SELECT consecutive_errors FROM strategy_sync_state WHERE strategy_id=?",
                (strategy_id,),
            ).fetchone()
            errors = 0 if row is None else int(row["consecutive_errors"])
            connection.execute(
                "INSERT INTO strategy_sync_state(strategy_id, last_attempt_at, last_success_at, last_error, "
                "next_scan_at, consecutive_errors) VALUES (?, ?, NULL, NULL, ?, 0) "
                "ON CONFLICT(strategy_id) DO UPDATE SET last_attempt_at=excluded.last_attempt_at, "
                "next_scan_at=excluded.next_scan_at",
                (strategy_id, now, now + self.order_interval_seconds),
            )
        return errors, now

    def _pace(self) -> None:
        if self.call_spacing_seconds <= 0:
            return
        current = time.monotonic()
        if self._last_call_monotonic is not None:
            remaining = self.call_spacing_seconds - (current - self._last_call_monotonic)
            if remaining > 0:
                self.sleep(remaining)
                current = time.monotonic()
        self._last_call_monotonic = current

    @staticmethod
    def _all_orders_terminal(results: list[dict[str, Any]]) -> bool:
        return bool(results) and all(row.get("status") in _ORDER_TERMINAL_STATES for row in results)

    def _position_proves_zero(self, instrument_id: str, fence: int) -> tuple[bool, str | None]:
        self._pace()
        self._ensure_lease(fence)
        try:
            rows = self.okx.positions("SWAP")
        except OKXError:
            return False, "positions_unavailable"
        if not isinstance(rows, list):
            return False, "positions_invalid"
        for row in rows:
            if not isinstance(row, dict):
                return False, "positions_invalid"
            row_instrument = row.get("instId")
            if not isinstance(row_instrument, str) or not row_instrument:
                return False, "positions_invalid"
            if row_instrument != instrument_id:
                continue
            size = _decimal(row.get("pos"))
            if size is None:
                return False, "positions_invalid"
            if size != 0:
                return False, None
        return True, None

    def _process_strategy(self, strategy: dict[str, Any], fence: int) -> None:
        if strategy["submissionMode"] == "sequential" and strategy["status"] == "APPLYING":
            with diagnostics.strategy_context(
                strategy.get("id"), component="worker", submission_mode="sequential"
            ):
                self._process_queue(strategy, fence)
            return
        strategy_id = strategy["id"]
        attempt = self._write_attempt(strategy_id, fence)
        if attempt is None:
            return
        prior_errors, scan_started_at = attempt
        recovering = strategy["status"] == "APPLYING"
        if recovering and not strategy["batchAttempted"]:
            results = [{**row, "status": "not_submitted"} for row in strategy["orders"]]
            order_error = None
            next_status = "UNKNOWN"
            failure_reason = "interrupted_before_batch"
        else:
            results, order_error, _ = _read_order_rows(
                strategy,
                self.okx,
                recovering=recovering,
                preserve_last_known=True,
                max_reads=_MAX_ORDERS_PER_STRATEGY,
                stop_after_failure=True,
                before_order_call=lambda: self._before_order_call(fence),
            )
            next_status, failure_reason = _reconciled_strategy_state(
                strategy, results, recovering=recovering
            )

        if order_error is not None:
            if recovering:
                next_status = "UNKNOWN"
                failure_reason = "batch_reconciliation_incomplete"
            else:
                next_status = strategy["status"]
                failure_reason = strategy["failureReason"]

        scan_error = order_error
        complete = False
        if scan_error is None and strategy["orderPlacementAttempted"] and self._all_orders_terminal(results):
            complete, position_error = self._position_proves_zero(
                strategy["contract"]["instrumentId"], fence
            )
            if position_error is not None:
                scan_error = position_error
            elif complete:
                next_status = "COMPLETED"
                failure_reason = None

        if scan_error is not None:
            self._persist_failure(
                strategy,
                results,
                next_status,
                failure_reason,
                fence,
                prior_errors,
                scan_error,
                recovering=recovering,
            )
            return
        self._persist_success(
            strategy,
            results,
            next_status,
            failure_reason,
            fence,
            recovering=recovering,
            scan_started_at=scan_started_at,
        )

    def _queue_service(self, fence: int, deadline: float) -> StrategyService:
        service = StrategyService(self)
        service.okx = _LeaseAwareExchange(
            self.okx,
            lambda name: self._before_queue_exchange(name, fence, deadline),
        )
        return service

    def _before_queue_exchange(self, method_name: str, fence: int, deadline: float) -> None:
        self._ensure_lease(fence)
        if method_name in {"set_leverage", "place_order", "place_batch_orders", "close_position", "add_margin"}:
            if self.clock() >= deadline:
                raise _QueueDeadline
            if method_name == "place_order":
                current = self.monotonic()
                if self._last_placement_monotonic is not None:
                    remaining = MIN_PLACEMENT_SPACING_SECONDS - (
                        current - self._last_placement_monotonic
                    )
                    if remaining > 0:
                        self.sleep(remaining + 1e-9)
                        self._ensure_lease(fence)
                        if self.clock() >= deadline:
                            raise _QueueDeadline
                # Record after the last ownership check, immediately before the
                # wrapped exchange method starts. Lease renewal time counts toward
                # the spacing interval.
                self._last_placement_monotonic = self.monotonic()
                self._queue_placements_this_pass += 1

    def _pace_queue_placement(self, fence: int, deadline: float, *, resumed_prefix: bool) -> None:
        if resumed_prefix and self._last_placement_monotonic is None:
            # The prior call belongs to an earlier worker process. Waiting from
            # takeover is conservative and guarantees a full interval before the
            # first resumed placement without persisting a process-local clock.
            self._last_placement_monotonic = self.monotonic()
        current = self.monotonic()
        if self._last_placement_monotonic is not None:
            remaining = MIN_PLACEMENT_SPACING_SECONDS - (current - self._last_placement_monotonic)
            if remaining > 0:
                self.sleep(remaining + 1e-9)
        self._ensure_lease(fence)
        if self.clock() >= deadline:
            raise _QueueDeadline

    def _queue_ledger(self, fence: int) -> StrategyQueueLedger:
        return StrategyQueueLedger(
            self.store,
            owner_id=self.owner_id,
            fence=fence,
            lease_seconds=self.lease_seconds,
            clock=self.clock,
        )

    def _persist_queue_transition(
        self,
        strategy: dict[str, Any],
        fence: int,
        *,
        queue: dict[str, Any],
        results: list[dict[str, Any]],
        status: str,
        failure_reason: str | None,
        leverage_results: list[dict[str, Any]] | None = None,
        mark_placement_attempted: bool = False,
    ) -> dict[str, Any] | None:
        marker = strategy.get("queue", {}).get("inFlight") if isinstance(strategy.get("queue"), dict) else None
        commit_order_id = None
        commit_order_index = None
        commit_side = None
        if isinstance(marker, dict):
            if marker.get("kind") == "placement":
                commit_order_index = marker.get("index")
                prepared = strategy.get("prepared")
                orders = prepared.get("orders") if isinstance(prepared, dict) else None
                if (
                    isinstance(orders, list) and type(commit_order_index) is int
                    and 0 <= commit_order_index < len(orders)
                    and isinstance(orders[commit_order_index], dict)
                ):
                    commit_order_id = orders[commit_order_index].get("clientOrderId")
                    commit_side = orders[commit_order_index].get("side")
            elif marker.get("kind") == "leverage":
                commit_side = marker.get("side")
                prepared = strategy.get("prepared")
                orders = prepared.get("orders") if isinstance(prepared, dict) else None
                if isinstance(orders, list):
                    row = next((item for item in orders if isinstance(item, dict) and item.get("side") == commit_side), None)
                    if isinstance(row, dict):
                        commit_order_id = row.get("clientOrderId")
        persisted = self._queue_ledger(fence).persist_transition(
            strategy,
            queue=queue,
            results=results,
            status=status,
            failure_reason=failure_reason,
            leverage_results=strategy["leverageResults"] if leverage_results is None else leverage_results,
            mark_placement_attempted=mark_placement_attempted,
        )
        diagnostics.emit_event(
            "commit", component="worker", stage="commit",
            outcome="committed" if persisted else "refused",
            reason=None if persisted else "fence_or_cas_loss",
            status=status, persisted=persisted,
            client_order_id=commit_order_id, order_index=commit_order_index, side=commit_side,
            order_count=len(results),
            accepted_count=sum(row.get("status") == "accepted" for row in results),
            pending_count=sum(row.get("status") == "unknown" for row in results),
            not_submitted_count=sum(row.get("status") == "not_submitted" for row in results),
        )
        if queue.get("phase") == "stopped":
            diagnostics.emit_event(
                    "queue_stop", component="worker", stage="queue", outcome="stopped",
                    reason=diagnostics.safe_reason(queue.get("stopReason")), status=status,
                    submission_mode="sequential", order_count=len(results),
                    accepted_count=sum(row.get("status") == "accepted" for row in results),
                    pending_count=sum(row.get("status") == "unknown" for row in results),
                    not_submitted_count=sum(row.get("status") == "not_submitted" for row in results),
                    persisted=persisted,
                )
        if not persisted:
            return None
        latest = self.strategy._load_row(strategy["id"])
        if latest["status"] != "APPLYING" and latest["replacementSourceId"] is not None:
            self.strategy._try_cleanup_replacement_source(latest["id"])
            latest = self.strategy._load_row(strategy["id"])
        return latest

    @staticmethod
    def _queue_validation_reason(error: APIError, *, resume: bool) -> str:
        return {
            "account_changed": "account_changed",
            "account_identity_unavailable": "account_changed",
            "account_mode_unsupported": "account_mode_unsupported",
            "instrument_position_exists": "position_exists",
            "pending_order_exists": "pending_order_exists",
            "insufficient_balance": "insufficient_balance",
            "quote_stale": "preview_changed",
            "preview_inputs_unavailable": "preflight_unavailable",
            "account_preflight_unavailable": "preflight_unavailable",
        }.get(error.code, "resume_validation_failed" if resume else "preflight_unavailable")

    def _stop_queue_without_marker(
        self,
        strategy: dict[str, Any],
        fence: int,
        reason: str,
        *,
        unknown_index: int | None = None,
    ) -> None:
        queue = strategy.get("queue")
        if not isinstance(queue, dict):
            return
        results = [dict(row) for row in strategy["results"]]
        suspected = [
            index for index, row in enumerate(results)
            if row.get("placementState") == "sending"
        ]
        effective_unknown = unknown_index
        if effective_unknown is None and suspected:
            effective_unknown = suspected[0]
        stopped, results = stop_queue(queue, results, reason, unknown_index=effective_unknown)
        for index in suspected:
            if index != effective_unknown:
                results[index] = {**results[index], "status": "unknown", "placementState": "unknown"}
        unknown = effective_unknown is not None or any(row.get("status") == "unknown" for row in results)
        self._persist_queue_transition(
            strategy,
            fence,
            queue=stopped,
            results=results,
            status="UNKNOWN" if unknown else "PARTIAL",
            failure_reason=reason,
        )

    def _stop_interrupted_queue(self, strategy: dict[str, Any], fence: int) -> None:
        queue = strategy["queue"]
        marker = queue["inFlight"]
        results = [dict(row) for row in strategy["results"]]
        leverage_results = list(strategy["leverageResults"])
        queue_without_marker = {**queue, "inFlight": None}
        unknown_index: int | None = None
        if marker["kind"] == "placement":
            unknown_index = marker["index"]
            reason = "interrupted_order_attempt"
        else:
            side = marker["side"]
            if not any(row.get("side") == side for row in leverage_results):
                leverage_results.append({"side": side, "status": "unknown"})
            reason = "interrupted_leverage_attempt"
        stopped, results = stop_queue(
            queue_without_marker, results, reason, unknown_index=unknown_index
        )
        self._persist_queue_transition(
            strategy,
            fence,
            queue=stopped,
            results=results,
            status="UNKNOWN",
            failure_reason=reason,
            leverage_results=leverage_results,
        )

    def _stop_after_marker_deadline(
        self,
        strategy: dict[str, Any],
        fence: int,
        *,
        unknown_index: int | None,
        leverage_side: str | None = None,
    ) -> None:
        queue = strategy["queue"]
        results = [dict(row) for row in strategy["results"]]
        leverage_results = list(strategy["leverageResults"])
        if leverage_side is not None and not any(row.get("side") == leverage_side for row in leverage_results):
            leverage_results.append({"side": leverage_side, "status": "unknown"})
        stopped, results = stop_queue(
            queue, results, "deadline_before_write", unknown_index=unknown_index
        )
        self._persist_queue_transition(
            strategy,
            fence,
            queue=stopped,
            results=results,
            status="UNKNOWN",
            failure_reason="deadline_before_write",
            leverage_results=leverage_results,
        )

    def _mark_queue_write(
        self,
        strategy: dict[str, Any],
        fence: int,
        marker: dict[str, Any],
    ) -> dict[str, Any] | None:
        queue = strategy["queue"]
        next_queue = {**queue, "phase": "sending", "inFlight": marker}
        results = [dict(row) for row in strategy["results"]]
        mark_placement = marker["kind"] == "placement"
        if mark_placement:
            index = marker["index"]
            results[index] = {**results[index], "status": "sending", "placementState": "sending"}
        return self._persist_queue_transition(
            strategy,
            fence,
            queue=next_queue,
            results=results,
            status="APPLYING",
            failure_reason=None,
            mark_placement_attempted=mark_placement,
        )

    @staticmethod
    def _leverage_outcome(
        response: Any,
        expected_pos_side: str,
        expected_instrument_id: str,
        expected_leverage: Any,
    ) -> tuple[str, str | None]:
        return parse_leverage_ack(
            response,
            expected_pos_side=expected_pos_side,
            expected_instrument_id=expected_instrument_id,
            expected_leverage=expected_leverage,
        )

    def _commit_leverage_outcome(
        self,
        strategy: dict[str, Any],
        fence: int,
        side: str,
        outcome: str,
        error_code: str | None,
    ) -> dict[str, Any] | None:
        queue = strategy["queue"]
        leverage_results = list(strategy["leverageResults"])
        value: dict[str, Any] = {"side": side, "status": outcome}
        if error_code is not None:
            value["errorCode"] = error_code
        leverage_results = [row for row in leverage_results if row.get("side") != side]
        leverage_results.append(value)
        if outcome == "applied":
            next_queue = {**queue, "phase": "sending", "inFlight": None}
            results = strategy["results"]
            status, reason = "APPLYING", None
        else:
            clear_marker = {**queue, "inFlight": None}
            stopped, results = stop_queue(clear_marker, strategy["results"], f"leverage_{outcome}")
            next_queue = stopped
            status = "PARTIAL" if outcome == "rejected" else "UNKNOWN"
            reason = f"leverage_{outcome}"
        return self._persist_queue_transition(
            strategy,
            fence,
            queue=next_queue,
            results=results,
            status=status,
            failure_reason=reason,
            leverage_results=leverage_results,
        )

    def _commit_order_outcome(
        self,
        strategy: dict[str, Any],
        fence: int,
        index: int,
        outcome: str,
        exchange_order_id: str | None,
        error_code: str | None,
        reason: str,
    ) -> dict[str, Any] | None:
        queue = strategy["queue"]
        results = [dict(row) for row in strategy["results"]]
        row = results[index]
        updated = {**row, "status": outcome, "placementState": outcome}
        if exchange_order_id is not None:
            updated["exchangeOrderId"] = exchange_order_id
        if error_code is not None:
            updated["errorCode"] = error_code
        results[index] = updated
        if outcome == "accepted":
            cursor = index + 1
            phase = "submitted" if cursor >= queue["totalCount"] else "sending"
            next_queue = {**queue, "phase": phase, "cursor": cursor, "inFlight": None, "stopReason": None}
            status = "APPLIED" if phase == "submitted" else "APPLYING"
            failure_reason = None
        else:
            clear_marker = {**queue, "inFlight": None}
            next_queue, results = stop_queue(clear_marker, results, reason)
            status = "PARTIAL" if outcome == "rejected" else "UNKNOWN"
            failure_reason = reason
        return self._persist_queue_transition(
            strategy,
            fence,
            queue=next_queue,
            results=results,
            status=status,
            failure_reason=failure_reason,
        )

    def _process_queue(self, strategy: dict[str, Any], fence: int) -> None:
        if strategy.get("submissionModeInvalid"):
            self._stop_queue_without_marker(strategy, fence, "resume_validation_failed")
            return
        if strategy.get("queueCorrupt"):
            self._stop_corrupt_queue(strategy, fence)
            return
        queue = normalize_queue(strategy.get("queue"))
        if queue is None:
            self._stop_corrupt_queue(strategy, fence)
            return
        if queue["inFlight"] is not None:
            self._stop_interrupted_queue(strategy, fence)
            return
        if queue["phase"] not in ("pending", "sending"):
            return
        if self.clock() >= queue["deadlineAt"]:
            self._stop_queue_without_marker(strategy, fence, "queue_expired")
            return
        if self._queue_placements_this_pass >= MAX_PLACEMENTS_PER_PASS:
            return

        prepared = strategy.get("prepared")
        orders = prepared.get("orders") if isinstance(prepared, dict) else None
        if (
            not isinstance(orders, list) or len(orders) != queue["totalCount"]
            or not orders or len(orders) > 20
            or prepared.get("submissionMode") != "sequential"
            or strategy["submissionMode"] != "sequential"
        ):
            self._stop_queue_without_marker(strategy, fence, "resume_validation_failed")
            return
        cursor = queue["cursor"]
        resume = cursor > 0
        if resume and any(
            row.get("placementState") != "accepted" for row in strategy["results"][:cursor]
        ):
            self._stop_queue_without_marker(strategy, fence, "resume_validation_failed")
            return
        if resume and any(
            row.get("placementState") != "pending" for row in strategy["results"][cursor:]
        ):
            self._stop_queue_without_marker(strategy, fence, "resume_validation_failed")
            return

        service = self._queue_service(fence, queue["deadlineAt"])
        try:
            account, preview = service._preflight(
                strategy["contract"], strategy["accountFingerprint"], resume=resume
            )
        except APIError as exc:
            reason = self._queue_validation_reason(exc, resume=resume)
            diagnostics.emit_event(
                "preflight", component="worker",
                stage="preflight_resume" if resume else "preflight_initial", outcome="failure",
                reason=diagnostics.safe_reason(reason), status=strategy.get("status"),
                submission_mode="sequential",
            )
            self._stop_queue_without_marker(strategy, fence, reason)
            return
        except Exception:
            diagnostics.emit_event(
                "preflight", component="worker",
                stage="preflight_resume" if resume else "preflight_initial", outcome="failure",
                reason="preflight_unavailable", status=strategy.get("status"),
                submission_mode="sequential",
            )
            raise
        diagnostics.emit_event(
            "preflight", component="worker",
            stage="preflight_resume" if resume else "preflight_initial", outcome="success",
            status=strategy.get("status"), submission_mode="sequential",
        )
        expected_mode = prepared.get("_positionMode")
        if (
            expected_mode not in ("net_mode", "long_short_mode")
            or account.get("posMode") != expected_mode
            or preview.get("_internal", {}).get("positionMode") != expected_mode
        ):
            self._stop_queue_without_marker(strategy, fence, "position_mode_changed")
            return
        if (
            not isinstance(preview.get("previewHash"), str)
            or preview["previewHash"] != queue["previewHash"]
            or preview["previewHash"] != prepared.get("previewHash")
        ):
            self._stop_queue_without_marker(
                strategy, fence, "resume_validation_failed" if resume else "preview_changed"
            )
            return

        if not resume:
            sides = sorted({row["side"] for row in orders}, key=lambda value: (value != "long", value))
            for side in sides:
                existing = next((row for row in strategy["leverageResults"] if row.get("side") == side), None)
                if existing is not None:
                    if existing.get("status") == "applied":
                        continue
                    self._stop_queue_without_marker(strategy, fence, "leverage_unknown")
                    return
                if self.clock() >= queue["deadlineAt"]:
                    self._stop_queue_without_marker(strategy, fence, "queue_expired")
                    return
                self._ensure_lease(fence)
                if self.clock() >= queue["deadlineAt"]:
                    self._stop_queue_without_marker(strategy, fence, "queue_expired")
                    return
                strategy = self._mark_queue_write(
                    strategy, fence, {"kind": "leverage", "side": side}
                )
                if strategy is None:
                    return
                order = next(row for row in orders if row["side"] == side)
                pos_side = side if expected_mode == "long_short_mode" else "net"
                diagnostics.emit_event(
                    "write_attempt", component="worker", stage="leverage", outcome="attempted",
                    side=side, submission_mode="sequential",
                    client_order_id=order.get("clientOrderId"),
                )
                response = None
                try:
                    response = service.okx.set_leverage({
                        "instId": strategy["contract"]["instrumentId"],
                        "lever": str(order["leverage"]),
                        "mgnMode": "isolated",
                        "posSide": pos_side,
                    })
                except _QueueDeadline:
                    self._stop_after_marker_deadline(
                        strategy, fence, unknown_index=None, leverage_side=side
                    )
                    return
                except _MonitorLeaseLost:
                    raise
                except OKXTransportError:
                    outcome, error_code = "unknown", None
                except OKXError as exc:
                    outcome, error_code = (
                        ("unknown", None) if exc.error_code is None else ("rejected", exc.error_code)
                    )
                else:
                    outcome, error_code = self._leverage_outcome(
                        response,
                        pos_side,
                        strategy["contract"]["instrumentId"],
                        order["leverage"],
                    )
                diagnostics.emit_event(
                    "ack_observed", component="worker", stage="leverage", outcome=outcome,
                    reason=diagnostics.safe_reason(
                        "leverage_rejected" if outcome == "rejected" else
                        "leverage_unknown" if outcome == "unknown" else "other"
                    ),
                    side=side, client_order_id=order.get("clientOrderId"),
                    item_code=error_code, persisted=False,
                    ack_shape=self._leverage_ack_shape(
                        response,
                        expected_pos_side=pos_side,
                        expected_instrument_id=strategy["contract"]["instrumentId"],
                        expected_leverage=order["leverage"],
                    ),
                )
                strategy = self._commit_leverage_outcome(
                    strategy, fence, side, outcome, error_code
                )
                if strategy is None or outcome != "applied":
                    return

            try:
                account, preview = service._preflight(
                    strategy["contract"], strategy["accountFingerprint"], resume=False
                )
            except APIError as exc:
                reason = self._queue_validation_reason(exc, resume=False)
                diagnostics.emit_event(
                    "preflight", component="worker", stage="preflight_post_leverage", outcome="failure",
                    reason=diagnostics.safe_reason(reason), status=strategy.get("status"),
                    submission_mode="sequential",
                )
                self._stop_queue_without_marker(
                    strategy, fence, reason
                )
                return
            except Exception:
                diagnostics.emit_event(
                    "preflight", component="worker", stage="preflight_post_leverage", outcome="failure",
                    reason="preflight_unavailable", status=strategy.get("status"),
                    submission_mode="sequential",
                )
                raise
            diagnostics.emit_event(
                "preflight", component="worker", stage="preflight_post_leverage", outcome="success",
                status=strategy.get("status"), submission_mode="sequential",
            )
            if (
                account.get("posMode") != expected_mode
                or preview.get("_internal", {}).get("positionMode") != expected_mode
            ):
                self._stop_queue_without_marker(strategy, fence, "position_mode_changed")
                return
            if preview.get("previewHash") != queue["previewHash"]:
                self._stop_queue_without_marker(strategy, fence, "preview_changed")
                return

        while queue["cursor"] < queue["totalCount"]:
            if self._queue_placements_this_pass >= MAX_PLACEMENTS_PER_PASS:
                return
            index = queue["cursor"]
            if self.clock() >= queue["deadlineAt"]:
                self._stop_queue_without_marker(strategy, fence, "queue_expired")
                return
            try:
                self._pace_queue_placement(
                    fence,
                    queue["deadlineAt"],
                    resumed_prefix=resume and self._queue_placements_this_pass == 0,
                )
            except _QueueDeadline:
                self._stop_queue_without_marker(strategy, fence, "queue_expired")
                return
            self._ensure_lease(fence)
            if self.clock() >= queue["deadlineAt"]:
                self._stop_queue_without_marker(strategy, fence, "queue_expired")
                return
            strategy = self._mark_queue_write(
                strategy, fence, {"kind": "placement", "index": index}
            )
            if strategy is None:
                return
            diagnostics.emit_event(
                "write_attempt", component="worker", stage="order", outcome="attempted",
                submission_mode="sequential", client_order_id=orders[index].get("clientOrderId"),
                order_index=index, order_count=queue["totalCount"],
            )
            response = None
            try:
                response = service.okx.place_order(
                    self.strategy._okx_order(strategy["contract"], orders[index], expected_mode)
                )
            except _QueueDeadline:
                self._stop_after_marker_deadline(
                    strategy, fence, unknown_index=index
                )
                return
            except _MonitorLeaseLost:
                raise
            except OKXTransportError:
                outcome, exchange_order_id, error_code, reason = (
                    "unknown", None, None, "order_unknown"
                )
            except OKXError as exc:
                if exc.error_code is None:
                    outcome, exchange_order_id, error_code, reason = (
                        "unknown", None, None, "order_ack_malformed"
                    )
                else:
                    outcome, exchange_order_id, error_code, reason = (
                        "rejected", None, exc.error_code, "order_rejected"
                    )
            else:
                outcome, exchange_order_id, error_code, reason = parse_order_ack(
                    response, orders[index].get("clientOrderId", "")
                )
            diagnostics.emit_event(
                "ack_observed", component="worker", stage="order", outcome=outcome,
                reason=diagnostics.safe_reason(
                    "order_rejected" if outcome == "rejected" else
                    "ack_unknown" if outcome == "unknown" else "other"
                ),
                client_order_id=orders[index].get("clientOrderId"), order_index=index,
                item_code=error_code, persisted=False,
                ack_shape=self._order_ack_shape(
                    response, orders[index].get("clientOrderId"), outcome, reason
                ),
            )
            strategy = self._commit_order_outcome(
                strategy,
                fence,
                index,
                outcome,
                exchange_order_id,
                error_code,
                reason or "order_ack_malformed",
            )
            if strategy is None or outcome != "accepted":
                return
            queue = strategy["queue"]
            if queue["phase"] == "submitted":
                return

    @staticmethod
    def _leverage_ack_shape(
        response: Any,
        *,
        expected_pos_side: str,
        expected_instrument_id: str,
        expected_leverage: Any,
    ) -> str:
        if not isinstance(response, dict):
            return "nonobject_data"
        if "code" not in response:
            return "missing_code"
        code = response.get("code")
        safe_code = bounded_error_code(code)
        if safe_code is None:
            return "invalid_code"
        if safe_code != "0":
            return "valid"
        data = response.get("data")
        if not isinstance(data, list) or len(data) != 1:
            return "data_cardinality"
        item = data[0]
        if not isinstance(item, dict):
            return "invalid_row"
        if "sCode" in item:
            sub_code = item.get("sCode")
            if bounded_error_code(sub_code) is None:
                return "invalid_code"
        actual = item.get("lever")
        if (
            item.get("instId") != expected_instrument_id
            or item.get("mgnMode") != "isolated"
            or item.get("posSide") != expected_pos_side
            or _ack_decimal(actual) is None
            or _ack_decimal(expected_leverage) is None
            or _ack_decimal(actual) != _ack_decimal(expected_leverage)
        ):
            return "leverage_identity_mismatch"
        return "valid"

    @staticmethod
    def _order_ack_shape(response: Any, client_order_id: Any, outcome: str, reason: Any) -> str:
        if not isinstance(response, dict):
            return "nonobject_data"
        if "code" not in response:
            return "missing_code"
        top_code = bounded_error_code(response.get("code"))
        if top_code is None:
            return "invalid_code"
        if top_code != "0":
            return "valid"
        data = response.get("data")
        if not isinstance(data, list) or len(data) != 1:
            return "data_cardinality"
        item = data[0]
        if not isinstance(item, dict):
            return "invalid_row"
        if item.get("clOrdId") != client_order_id:
            return "client_identity_mismatch"
        if "sCode" not in item or item.get("sCode") in (None, ""):
            return "missing_code"
        item_code = bounded_error_code(item.get("sCode"))
        if item_code is None:
            return "invalid_code"
        if item_code != "0":
            return "valid"
        order_id = item.get("ordId")
        if not isinstance(order_id, str) or not order_id.strip():
            return "missing_order_id"
        return "valid"

    def _stop_corrupt_queue(self, strategy: dict[str, Any], fence: int) -> None:
        prepared = strategy.get("prepared")
        orders = prepared.get("orders") if isinstance(prepared, dict) else []
        orders = orders if isinstance(orders, list) else []
        preview_hash = prepared.get("previewHash") if isinstance(prepared, dict) else "corrupt"
        queue = new_queue(
            enqueued_at=self.clock(),
            total_count=min(len(orders), 20),
            preview_hash=preview_hash if isinstance(preview_hash, str) and preview_hash else "corrupt",
        )
        queue["phase"] = "stopped"
        queue["stopReason"] = "interrupted_order_attempt"
        results = [dict(row) for row in strategy["results"]]
        has_unknown = False
        for index, row in enumerate(results):
            if row.get("placementState") == "sending":
                results[index] = {**row, "status": "unknown", "placementState": "unknown"}
                has_unknown = True
            elif row.get("placementState", "pending") == "pending":
                results[index] = {**row, "status": "not_submitted", "placementState": "not_submitted"}
        status = "UNKNOWN" if has_unknown or strategy["orderPlacementAttempted"] else "PARTIAL"
        reason = "interrupted_order_attempt" if status == "UNKNOWN" else "resume_validation_failed"
        queue["stopReason"] = reason
        self._persist_queue_transition(
            strategy,
            fence,
            queue=queue,
            results=results,
            status=status,
            failure_reason=reason,
            mark_placement_attempted=has_unknown,
        )

    def _persist_success(
        self,
        strategy: dict[str, Any],
        results: list[dict[str, Any]],
        status: str,
        failure_reason: str | None,
        fence: int,
        *,
        recovering: bool,
        scan_started_at: float,
    ) -> bool:
        now = self.clock()
        strategy_id = strategy["id"]
        with self.store.transaction() as connection:
            if not self._lease_is_current(connection, fence, now):
                return False
            current = connection.execute(
                "SELECT status, results_json, updated_at, batch_attempted, order_placement_attempted FROM strategies "
                "WHERE strategy_id=? AND account_fingerprint=?",
                (strategy_id, strategy["accountFingerprint"]),
            ).fetchone()
            if (
                current is None
                or current["status"] != strategy["status"]
                or current["results_json"] != encode_json(strategy["results"])
                or current["updated_at"] != strategy["updatedAt"]
            ):
                return False
            changed = results != strategy["results"] or status != strategy["status"] or failure_reason != strategy["failureReason"]
            if changed:
                execution_clause = ", execution_id=NULL, execution_lease_until=NULL" if recovering else ""
                updated = connection.execute(
                    "UPDATE strategies SET status=?, results_json=?, failure_reason=?, updated_at=?" +
                    execution_clause +
                    " WHERE strategy_id=? AND account_fingerprint=? AND status=? AND results_json=? AND updated_at=?",
                    (
                        status,
                        encode_json(results),
                        failure_reason,
                        now,
                        strategy_id,
                        strategy["accountFingerprint"],
                        strategy["status"],
                        encode_json(strategy["results"]),
                        strategy["updatedAt"],
                    ),
                ).rowcount
                if updated != 1:
                    return False
                if StrategyService._can_release_reservation(
                    status, results,
                    bool(current["batch_attempted"]) or bool(current["order_placement_attempted"]),
                ):
                    connection.execute(
                        "DELETE FROM strategy_reservations WHERE strategy_id=?", (strategy_id,)
                    )
            StrategyService._cleanup_replacement_in_connection(connection, strategy_id, now)
            connection.execute(
                "INSERT INTO strategy_sync_state(strategy_id, last_attempt_at, last_success_at, last_error, "
                "next_scan_at, consecutive_errors) VALUES (?, ?, ?, NULL, ?, 0) "
                "ON CONFLICT(strategy_id) DO UPDATE SET last_attempt_at=excluded.last_attempt_at, "
                "last_success_at=excluded.last_success_at, last_error=NULL, "
                "next_scan_at=excluded.next_scan_at, consecutive_errors=0",
                (strategy_id, now, now, max(scan_started_at + self.order_interval_seconds, now)),
            )
        return True

    def _persist_failure(
        self,
        strategy: dict[str, Any],
        results: list[dict[str, Any]],
        status: str,
        failure_reason: str | None,
        fence: int,
        prior_errors: int,
        scan_error: str,
        *,
        recovering: bool,
    ) -> bool:
        now = self.clock()
        strategy_id = strategy["id"]
        delay = min(self.order_interval_seconds * (2 ** min(prior_errors, 6)), _MAX_BACKOFF_SECONDS)
        with self.store.transaction() as connection:
            if not self._lease_is_current(connection, fence, now):
                return False
            current = connection.execute(
                "SELECT status, results_json, updated_at, batch_attempted, order_placement_attempted FROM strategies "
                "WHERE strategy_id=? AND account_fingerprint=?",
                (strategy_id, strategy["accountFingerprint"]),
            ).fetchone()
            unchanged = (
                current is not None
                and current["status"] == strategy["status"]
                and current["results_json"] == encode_json(strategy["results"])
                and current["updated_at"] == strategy["updatedAt"]
            )
            if unchanged and (
                results != strategy["results"]
                or status != strategy["status"]
                or failure_reason != strategy["failureReason"]
            ):
                execution_clause = ", execution_id=NULL, execution_lease_until=NULL" if recovering else ""
                updated = connection.execute(
                    "UPDATE strategies SET status=?, results_json=?, failure_reason=?, updated_at=?" +
                    execution_clause +
                    " WHERE strategy_id=? AND account_fingerprint=? AND status=? AND results_json=? AND updated_at=?",
                    (
                        status,
                        encode_json(results),
                        failure_reason,
                        now,
                        strategy_id,
                        strategy["accountFingerprint"],
                        strategy["status"],
                        encode_json(strategy["results"]),
                        strategy["updatedAt"],
                    ),
                ).rowcount
                if updated == 1 and StrategyService._can_release_reservation(
                    status, results,
                    bool(current["batch_attempted"]) or bool(current["order_placement_attempted"]),
                ):
                    connection.execute(
                        "DELETE FROM strategy_reservations WHERE strategy_id=?", (strategy_id,)
                    )
            if unchanged:
                StrategyService._cleanup_replacement_in_connection(connection, strategy_id, now)
            connection.execute(
                "INSERT INTO strategy_sync_state(strategy_id, last_attempt_at, last_success_at, last_error, "
                "next_scan_at, consecutive_errors) VALUES (?, ?, NULL, ?, ?, 1) "
                "ON CONFLICT(strategy_id) DO UPDATE SET last_attempt_at=excluded.last_attempt_at, "
                "last_error=excluded.last_error, next_scan_at=excluded.next_scan_at, "
                "consecutive_errors=strategy_sync_state.consecutive_errors+1",
                (strategy_id, now, scan_error, now + delay),
            )
        return unchanged

    def run_forever(self, stop_event: threading.Event | None = None) -> None:
        stopping = stop_event or threading.Event()
        interval = self.order_interval_seconds
        diagnostics.emit_event(
            "worker_startup", component="worker", stage="startup", outcome="success"
        )
        try:
            while not stopping.is_set():
                started = time.monotonic()
                self.run_once()
                remaining = interval - (time.monotonic() - started)
                if remaining > 0:
                    stopping.wait(remaining)
        finally:
            diagnostics.emit_event(
                "worker_shutdown", component="worker", stage="shutdown", outcome="success"
            )
            diagnostics.shutdown()


def main() -> None:
    settings = WorkerSettings.from_environ()
    worker = StrategyOrderWorker(settings)
    stop = threading.Event()
    signal.signal(signal.SIGTERM, lambda *_: stop.set())
    signal.signal(signal.SIGINT, lambda *_: stop.set())
    worker.run_forever(stop)


if __name__ == "__main__":
    main()
