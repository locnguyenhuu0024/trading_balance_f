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

from .okx import OKXClient, OKXError, Transport
from .security import token_digest
from .store import SQLiteStore, encode_json
from .strategy import (
    _ORDER_TERMINAL_STATES,
    _decimal,
    _read_order_rows,
    _reconciled_strategy_state,
    StrategyService,
)


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
        self.okx = okx or OKXClient(
            settings.okx_api_key,
            settings.okx_api_secret,
            settings.okx_api_passphrase,
            transport=transport,
            clock=clock,
        )
        # StrategyService supplies the shared row decoder and reconciliation contract.
        self.strategy = StrategyService(self)
        self._last_call_monotonic: float | None = None

    def _account_fingerprint(self, uid: Any) -> str | None:
        if isinstance(uid, bool) or not isinstance(uid, (str, int)):
            return None
        normalized = str(uid).strip()
        if not normalized:
            return None
        return token_digest("okx-account-uid:v1:" + normalized, self.settings.session_signing_key)

    def run_once(self) -> bool:
        """Run one bounded pass. False means another live worker owns the lease."""
        now = self.clock()
        fence = self.store.acquire_strategy_monitor_lease(self.owner_id, now, self.lease_seconds)
        if fence is None:
            return False
        try:
            account = self.okx.account_config()
        except OKXError:
            return True
        fingerprint = self._account_fingerprint(account.get("uid"))
        if fingerprint is None:
            return True
        for _ in range(_MAX_STRATEGIES_PER_PASS):
            try:
                self._ensure_lease(fence)
            except _MonitorLeaseLost:
                break
            strategy = self._next_due_strategy(fingerprint, self.clock())
            if strategy is None:
                break
            try:
                self._process_strategy(strategy, fence)
            except _MonitorLeaseLost:
                break
        return True

    def _next_due_strategy(self, fingerprint: str, now: float) -> dict[str, Any] | None:
        with self.store.connection() as connection:
            row = connection.execute(
                "SELECT s.* FROM strategies AS s "
                "LEFT JOIN strategy_sync_state AS sync ON sync.strategy_id=s.strategy_id "
                "WHERE s.account_fingerprint=? AND s.attempt_started=1 AND s.status IN "
                "('APPLYING', 'UNKNOWN', 'APPLIED', 'PARTIAL') "
                "AND (s.status!='APPLYING' OR s.execution_lease_until IS NULL OR s.execution_lease_until<=?) "
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
            self.owner_id, fence, self.clock(), self.lease_seconds
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
        if scan_error is None and self._all_orders_terminal(results):
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
                "SELECT status, results_json, updated_at, batch_attempted FROM strategies "
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
                if StrategyService._can_release_reservation(status, results, bool(current["batch_attempted"])):
                    connection.execute(
                        "DELETE FROM strategy_reservations WHERE strategy_id=?", (strategy_id,)
                    )
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
                "SELECT status, results_json, updated_at, batch_attempted FROM strategies "
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
                    status, results, bool(current["batch_attempted"])
                ):
                    connection.execute(
                        "DELETE FROM strategy_reservations WHERE strategy_id=?", (strategy_id,)
                    )
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
        while not stopping.is_set():
            started = time.monotonic()
            self.run_once()
            remaining = interval - (time.monotonic() - started)
            if remaining > 0:
                stopping.wait(remaining)


def main() -> None:
    settings = WorkerSettings.from_environ()
    worker = StrategyOrderWorker(settings)
    stop = threading.Event()
    signal.signal(signal.SIGTERM, lambda *_: stop.set())
    signal.signal(signal.SIGINT, lambda *_: stop.set())
    worker.run_forever(stop)


if __name__ == "__main__":
    main()
