from __future__ import annotations

import threading
import unittest
import os
from pathlib import Path
from typing import Any

from backend.okx import OKXTransportError
from backend.security import token_digest
from backend.store import SQLiteStore, decode_json, encode_json
from backend.strategy_worker import StrategyOrderWorker, WorkerSettings


NOW = 1_798_848_000.0
SIGNING_KEY = bytes(range(32))
INSTRUMENT = "BTC-USDT-SWAP"
CLIENT_ORDER_ID = "worker-order-0001"
ACCOUNT_FINGERPRINT = token_digest("okx-account-uid:v1:123456789", SIGNING_KEY)


class FakeReadOnlyOKX:
    def __init__(self) -> None:
        self.uid = "123456789"
        self.orders: dict[str, dict[str, Any]] = {}
        self.position_rows: list[dict[str, Any]] = []
        self.fail_positions = False
        self.order_detail_reads = 0
        self.write_calls: list[str] = []
        self.order_detail_hook: Any = None

    def account_config(self) -> dict[str, Any]:
        return {"uid": self.uid}

    def order_details(self, instrument_id: str, client_order_id: str) -> dict[str, Any] | None:
        self.order_detail_reads += 1
        if self.order_detail_hook is not None:
            return self.order_detail_hook(instrument_id, client_order_id)
        row = self.orders.get(client_order_id)
        return None if row is None else dict(row)

    def positions(self, instrument_type: str) -> list[dict[str, Any]]:
        if self.fail_positions:
            raise OKXTransportError("simulated positions failure")
        return [dict(row) for row in self.position_rows]

    def place_order(self, payload: dict[str, Any]) -> None:
        self.write_calls.append("place_order")

    def place_batch_orders(self, payload: list[dict[str, Any]]) -> None:
        self.write_calls.append("place_batch_orders")

    def set_leverage(self, payload: dict[str, Any]) -> None:
        self.write_calls.append("set_leverage")

    def close_position(self, payload: dict[str, Any]) -> None:
        self.write_calls.append("close_position")


class StrategyWorkerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.db_path = Path(__file__).resolve().parents[2] / (
            f".strategy-worker-test-{os.getpid()}-{id(self)}.sqlite3"
        )
        self.now = NOW
        self.store = SQLiteStore(str(self.db_path))
        self.store.initialize()
        self.exchange = FakeReadOnlyOKX()
        self.exchange.orders[CLIENT_ORDER_ID] = {
            "instId": INSTRUMENT,
            "clOrdId": CLIENT_ORDER_ID,
            "ordId": "exchange-order-1",
            "sz": "2",
            "accFillSz": "0",
            "state": "live",
            "avgPx": "",
        }
        self._insert_strategy()
        self.settings = WorkerSettings(
            okx_api_key="test-key",
            okx_api_secret="test-secret",
            okx_api_passphrase="test-passphrase",
            session_signing_key=SIGNING_KEY,
            operation_db_path=str(self.db_path),
        )

    def tearDown(self) -> None:
        self.db_path.unlink(missing_ok=True)

    def _insert_strategy(
        self,
        *,
        strategy_id: str = "strategy-worker-01",
        status: str = "APPLIED",
        order_status: str = "accepted",
        batch_attempted: int = 1,
    ) -> str:
        order = {
            "clientOrderId": CLIENT_ORDER_ID,
            "exchangeOrderId": "exchange-order-1",
            "side": "long",
            "role": "entry",
            "limitPrice": "59000",
            "contracts": "2",
            "status": order_status,
            "filledContracts": "0",
            "averageFillPrice": None,
        }
        with self.store.transaction() as connection:
            connection.execute(
                "INSERT INTO strategies(strategy_id, account_fingerprint, status, contract_json, "
                "snapshot_json, orders_json, results_json, preview_hash, confirmation_hash, "
                "prepared_expires_at, prepared_json, attempt_started, batch_attempted, execution_id, "
                "execution_lease_until, failure_reason, leverage_results_json, created_at, updated_at) "
                "VALUES (?, ?, ?, ?, ?, ?, ?, '', NULL, NULL, NULL, 1, ?, NULL, NULL, NULL, '[]', ?, ?)",
                (
                    strategy_id,
                    ACCOUNT_FINGERPRINT,
                    status,
                    encode_json({"instrumentId": INSTRUMENT}),
                    encode_json({}),
                    encode_json([order]),
                    encode_json([order]),
                    batch_attempted,
                    self.now,
                    self.now,
                ),
            )
        return strategy_id

    def _worker(self, *, owner_id: str, lease_seconds: float = 30) -> StrategyOrderWorker:
        return StrategyOrderWorker(
            self.settings,
            store=self.store,
            okx=self.exchange,
            clock=lambda: self.now,
            owner_id=owner_id,
            lease_seconds=lease_seconds,
            order_interval_seconds=5,
            call_spacing_seconds=0,
            sleep=lambda _seconds: None,
        )

    def _strategy(self, strategy_id: str = "strategy-worker-01") -> tuple[dict[str, Any], dict[str, Any]]:
        with self.store.connection() as connection:
            strategy = connection.execute(
                "SELECT status, results_json FROM strategies WHERE strategy_id=?", (strategy_id,)
            ).fetchone()
            sync = connection.execute(
                "SELECT * FROM strategy_sync_state WHERE strategy_id=?", (strategy_id,)
            ).fetchone()
        return dict(strategy), {} if sync is None else dict(sync)

    def test_red_worker_persists_partial_then_full_fill_without_browser_get(self) -> None:
        self.exchange.orders[CLIENT_ORDER_ID].update(
            state="partially_filled", accFillSz="1.250", avgPx="59001.25"
        )
        worker = self._worker(owner_id="worker-one")

        self.assertTrue(worker.run_once())
        strategy, sync = self._strategy()
        partial = decode_json(strategy["results_json"])[0]
        self.assertEqual(partial["status"], "partially_filled")
        self.assertEqual(partial["filledContracts"], "1.25")
        self.assertEqual(partial["averageFillPrice"], "59001.25")
        self.assertIsNotNone(sync.get("last_success_at"))
        self.assertEqual(self.exchange.write_calls, [])

        self.now += 5
        self.exchange.orders[CLIENT_ORDER_ID].update(state="filled", accFillSz="2", avgPx="59002")
        self.assertTrue(worker.run_once())
        strategy, _ = self._strategy()
        filled = decode_json(strategy["results_json"])[0]
        self.assertEqual(filled["status"], "filled")
        self.assertEqual(filled["filledContracts"], "2")
        self.assertEqual(filled["averageFillPrice"], "59002")
        self.assertEqual(self.exchange.write_calls, [])

    def test_red_one_pass_scans_multiple_due_strategies_with_shared_rate_spacing(self) -> None:
        second_id = self._insert_strategy(strategy_id="strategy-worker-02")
        sleeps: list[float] = []
        worker = StrategyOrderWorker(
            self.settings,
            store=self.store,
            okx=self.exchange,
            clock=lambda: self.now,
            owner_id="worker-one",
            lease_seconds=30,
            order_interval_seconds=5,
            call_spacing_seconds=0.1,
            sleep=sleeps.append,
        )

        self.assertTrue(worker.run_once())

        _, first_sync = self._strategy()
        _, second_sync = self._strategy(second_id)
        self.assertEqual(first_sync.get("last_success_at"), self.now)
        self.assertEqual(second_sync.get("last_success_at"), self.now)
        self.assertEqual(self.exchange.order_detail_reads, 2)
        self.assertTrue(any(delay > 0 for delay in sleeps))

    def test_red_recovery_read_failures_retain_last_known_order_state(self) -> None:
        with self.store.transaction() as connection:
            connection.execute(
                "UPDATE strategies SET status='APPLYING', execution_lease_until=NULL "
                "WHERE strategy_id='strategy-worker-01'"
            )

        def unavailable(_instrument_id: str, _client_order_id: str) -> None:
            raise OKXTransportError("simulated order details failure")

        self.exchange.order_detail_hook = unavailable
        worker = self._worker(owner_id="worker-one")
        self.assertTrue(worker.run_once())
        strategy, _ = self._strategy()
        self.assertEqual(strategy["status"], "UNKNOWN")
        self.assertEqual(decode_json(strategy["results_json"])[0]["status"], "accepted")

        second_id = self._insert_strategy(strategy_id="strategy-worker-02", status="APPLYING")
        self.exchange.order_detail_hook = lambda _instrument_id, _client_order_id: {
            "instId": "ETH-USDT-SWAP",
            "clOrdId": CLIENT_ORDER_ID,
            "ordId": "exchange-order-1",
            "sz": "2",
            "accFillSz": "1",
            "state": "partially_filled",
            "avgPx": "59001",
        }
        self.now += 5
        self.assertTrue(worker.run_once())
        strategy, _ = self._strategy(second_id)
        self.assertEqual(strategy["status"], "UNKNOWN")
        self.assertEqual(decode_json(strategy["results_json"])[0]["status"], "accepted")

    def test_red_duplicate_worker_cannot_scan_while_lease_is_active(self) -> None:
        first = self._worker(owner_id="worker-one")
        second = self._worker(owner_id="worker-two")

        self.assertTrue(first.run_once())
        calls_after_first = self.exchange.order_detail_reads
        self.assertFalse(second.run_once())
        self.assertEqual(self.exchange.order_detail_reads, calls_after_first)
        self.assertEqual(self.exchange.write_calls, [])

    def test_red_expired_lease_fences_old_worker_after_restart(self) -> None:
        entered_read = threading.Event()
        release_read = threading.Event()

        def late_old_response(_instrument_id: str, _client_order_id: str) -> dict[str, Any]:
            entered_read.set()
            self.assertTrue(release_read.wait(timeout=3))
            return {
                "instId": INSTRUMENT,
                "clOrdId": CLIENT_ORDER_ID,
                "ordId": "exchange-order-1",
                "sz": "2",
                "accFillSz": "0",
                "state": "live",
                "avgPx": "",
            }

        old_worker = self._worker(owner_id="old-worker", lease_seconds=10)
        new_worker = self._worker(owner_id="new-worker", lease_seconds=10)
        self.exchange.order_detail_hook = late_old_response
        old_result: list[bool] = []
        thread = threading.Thread(target=lambda: old_result.append(old_worker.run_once()))
        thread.start()
        self.assertTrue(entered_read.wait(timeout=3))

        self.now += 11
        self.exchange.order_detail_hook = None
        self.exchange.orders[CLIENT_ORDER_ID].update(
            state="partially_filled", accFillSz="1", avgPx="59001"
        )
        self.exchange.position_rows = [{"instId": INSTRUMENT, "pos": "1", "posSide": "long"}]
        self.assertTrue(new_worker.run_once())
        release_read.set()
        thread.join(timeout=3)
        self.assertFalse(thread.is_alive())

        strategy, _ = self._strategy()
        persisted = decode_json(strategy["results_json"])[0]
        self.assertEqual(persisted["status"], "partially_filled")
        self.assertEqual(persisted["filledContracts"], "1")
        self.assertEqual(self.exchange.write_calls, [])

    def test_red_completion_requires_terminal_orders_and_fresh_zero_positions(self) -> None:
        worker = self._worker(owner_id="worker-one")
        self.exchange.orders[CLIENT_ORDER_ID].update(
            state="filled", accFillSz="2", avgPx="59002"
        )
        self.assertTrue(worker.run_once())
        strategy, _ = self._strategy()
        self.assertEqual(strategy["status"], "COMPLETED")

        self._insert_strategy(
            strategy_id="strategy-worker-02", order_status="accepted"
        )
        self.exchange.orders[CLIENT_ORDER_ID].update(state="filled", accFillSz="2", avgPx="59002")
        self.exchange.fail_positions = True
        self.now += 5
        self.assertTrue(worker.run_once())
        strategy, sync = self._strategy("strategy-worker-02")
        self.assertNotEqual(strategy["status"], "COMPLETED")
        self.assertEqual(sync.get("last_error"), "positions_unavailable")

        self.exchange.fail_positions = False
        self.exchange.position_rows = [{"instId": INSTRUMENT, "pos": "2", "posSide": "long"}]
        self.now += 5
        self.assertTrue(worker.run_once())
        strategy, sync = self._strategy("strategy-worker-02")
        self.assertNotEqual(strategy["status"], "COMPLETED")
        self.assertIsNone(sync.get("last_error"))

        self.exchange.position_rows = []
        self.now += 5
        self.assertTrue(worker.run_once())
        strategy, _ = self._strategy("strategy-worker-02")
        self.assertEqual(strategy["status"], "COMPLETED")

        self._insert_strategy(
            strategy_id="strategy-worker-03", status="UNKNOWN", order_status="unknown"
        )
        self.exchange.orders[CLIENT_ORDER_ID].update(state="unrecognized", accFillSz="2", avgPx="59002")
        self.now += 5
        self.assertTrue(worker.run_once())
        strategy, _ = self._strategy("strategy-worker-03")
        self.assertNotEqual(strategy["status"], "COMPLETED")

    def test_red_account_mismatch_and_invalid_details_preserve_last_known_order(self) -> None:
        worker = self._worker(owner_id="worker-one")
        self.exchange.orders[CLIENT_ORDER_ID].update(
            state="live", accFillSz="0", avgPx=""
        )
        self.exchange.order_detail_hook = lambda *_: {
            "instId": "ETH-USDT-SWAP",
            "clOrdId": CLIENT_ORDER_ID,
            "ordId": "wrong-order",
            "sz": "2",
            "accFillSz": "2",
            "state": "filled",
            "avgPx": "59000",
        }
        self.assertTrue(worker.run_once())
        strategy, sync = self._strategy()
        current = decode_json(strategy["results_json"])[0]
        self.assertEqual(current["status"], "accepted")
        self.assertEqual(current["filledContracts"], "0")
        self.assertEqual(sync.get("last_error"), "invalid_order_details")
        self.assertEqual(self.exchange.write_calls, [])

        self.now += 30
        self.exchange.uid = "987654321"
        self.exchange.order_detail_hook = None
        calls = self.exchange.order_detail_reads
        self.assertTrue(worker.run_once())
        strategy, sync = self._strategy()
        self.assertEqual(decode_json(strategy["results_json"])[0]["status"], "accepted")
        self.assertEqual(sync.get("last_error"), "invalid_order_details")
        self.assertEqual(self.exchange.order_detail_reads, calls)
        self.assertEqual(self.exchange.write_calls, [])

    def test_worker_settings_consume_only_the_five_approved_values(self) -> None:
        values = {
            "OKX_API_KEY": "key",
            "OKX_API_SECRET": "secret",
            "OKX_API_PASSPHRASE": "passphrase",
            "SESSION_SIGNING_KEY": SIGNING_KEY.hex(),
            "OPERATION_DB_PATH": str(self.db_path.with_name("separate.sqlite3")),
            "ADMIN_PASSWORD_HASH": "must-not-be-required",
            "TOTP_SECRET": "must-not-be-required",
            "ALLOWED_WEB_ORIGIN": "must-not-be-required",
        }
        settings = WorkerSettings.from_environ(values)
        self.assertEqual(settings.operation_db_path, values["OPERATION_DB_PATH"])
        self.assertEqual(settings.session_signing_key, SIGNING_KEY)

    def test_green_monitor_schema_upgrade_keeps_existing_strategy_rows(self) -> None:
        with self.store.transaction() as connection:
            connection.execute("DROP TABLE strategy_sync_state")
            connection.execute("DROP TABLE strategy_monitor_lease")

        migrated_store = SQLiteStore(str(self.db_path))
        migrated_store.initialize()
        with migrated_store.connection() as connection:
            strategy = connection.execute(
                "SELECT strategy_id, status FROM strategies WHERE strategy_id=?",
                ("strategy-worker-01",),
            ).fetchone()
            lease = connection.execute(
                "SELECT owner_id, fence, lease_until FROM strategy_monitor_lease WHERE singleton=1"
            ).fetchone()
            sync_table = connection.execute(
                "SELECT name FROM sqlite_master WHERE type='table' AND name='strategy_sync_state'"
            ).fetchone()
        self.assertEqual(tuple(strategy), ("strategy-worker-01", "APPLIED"))
        self.assertEqual(tuple(lease), (None, 0, 0.0))
        self.assertIsNotNone(sync_table)


if __name__ == "__main__":
    unittest.main()
