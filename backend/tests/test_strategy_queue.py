from __future__ import annotations

import sqlite3
import unittest
from contextlib import contextmanager
from copy import deepcopy
from pathlib import Path
from typing import Any

from backend.security import token_digest
from backend.store import SQLiteStore, decode_json, encode_json
from backend.strategy_queue import StrategyQueueLedger, initial_results, new_queue, parse_order_ack
from backend.strategy_worker import StrategyOrderWorker, WorkerSettings
from backend.tests import test_strategy_api as api_fixtures


INSTRUMENT = api_fixtures.INSTRUMENT
SIGNING_KEY = api_fixtures.SIGNING_KEY


class StrategyQueueTests(unittest.TestCase):
    def setUp(self) -> None:
        self.api = api_fixtures.StrategyApiTests(
            "test_red_strategy_routes_require_bearer_before_exchange_reads"
        )
        self.api.setUp()
        self.addCleanup(self.api.tearDown)
        self.monotonic_now = 0.0
        self.sleeps: list[float] = []
        self.api.exchange.monotonic = lambda: self.monotonic_now

    def _sleep(self, seconds: float) -> None:
        self.sleeps.append(seconds)
        self.monotonic_now += seconds
        self.api.now += seconds

    def _worker(self, owner_id: str = "queue-worker") -> StrategyOrderWorker:
        settings = WorkerSettings(
            okx_api_key="test-key",
            okx_api_secret="test-secret",
            okx_api_passphrase="test-passphrase",
            session_signing_key=SIGNING_KEY,
            operation_db_path=self.api.settings.operation_db_path,
        )
        return StrategyOrderWorker(
            settings,
            store=self.api.service.store,
            transport=self.api.exchange.transport,
            clock=lambda: self.api.now,
            owner_id=owner_id,
            lease_seconds=30,
            order_interval_seconds=5,
            call_spacing_seconds=0,
            sleep=self._sleep,
            monotonic=lambda: self.monotonic_now,
        )

    def _contract(self, count: int = 3, instrument_id: str = INSTRUMENT) -> dict[str, Any]:
        rows = [
            {
                "side": "long",
                "price": str(59000 - index * 100),
                "levelId": "queue-entry" if index == 0 else f"queue-level-{index + 1}",
            }
            for index in range(count)
        ]
        contract = api_fixtures.StrategyApiTests.id_mode_contract(
            rows,
            entry_ids={"long": "queue-entry"},
        )
        contract["instrumentId"] = instrument_id
        if count > 3:
            contract["totalMargin"] = "600"
        return contract

    def _start_queue(
        self, count: int = 3, instrument_id: str = INSTRUMENT
    ) -> tuple[str, dict[str, Any]]:
        status, saved_setting = self.api.request(
            "POST", "/v1/strategies/settings", {"limitOrderSubmissionMode": "sequential"}
        )
        self.assertEqual(status, 200, saved_setting)
        strategy_id, _ = self.api.save_draft(self._contract(count, instrument_id))
        status, prepared = self.api.request(
            "POST", f"/v1/strategies/{strategy_id}/prepare-apply", {}
        )
        self.assertEqual(status, 200, prepared)
        status, applying = self.api.request(
            "POST", f"/v1/strategies/{strategy_id}/execute-apply",
            {"confirmationToken": prepared["confirmationToken"]},
        )
        self.assertEqual(status, 200, applying)
        self.assertEqual(applying["status"], "APPLYING")
        self.assertEqual(applying["submissionMode"], "sequential")
        self.assertEqual(applying["queueStatus"], "pending")
        status, duplicate = self.api.request(
            "POST", f"/v1/strategies/{strategy_id}/execute-apply",
            {"confirmationToken": prepared["confirmationToken"]},
        )
        self.assertEqual(status, 200, duplicate)
        self.assertEqual(duplicate["status"], "APPLYING")
        self.assertEqual(self.api.exchange.single_order_attempts, 0)
        return strategy_id, prepared

    def _seed_confirmed_legacy_queue_twenty(self, strategy_id: str) -> None:
        strategy_service = self.api.service.strategy
        contract = self._contract(20)
        contract["entryBySide"] = {"long": "59000"}
        preview = strategy_service._preview_contract(contract)
        orders = strategy_service._with_client_ids(preview)
        snapshot = strategy_service._public_preview(preview)
        snapshot["orders"] = orders
        snapshot["_metadata"] = preview["_internal"]["metadata"]
        snapshot["_positionMode"] = preview["_internal"]["positionMode"]
        prepared = strategy_service._public_preview(preview)
        prepared["orders"] = orders
        prepared["_positionMode"] = preview["_internal"]["positionMode"]
        prepared["submissionMode"] = "sequential"
        queue = new_queue(enqueued_at=self.api.now, total_count=20, preview_hash=preview["previewHash"])
        results = initial_results(orders)
        with self.api.service.store.transaction() as connection:
            connection.execute(
                "UPDATE strategies SET status='APPLYING', contract_json=?, snapshot_json=?, orders_json=?, "
                "results_json=?, preview_hash=?, confirmation_hash=NULL, prepared_json=?, submission_mode='sequential', "
                "attempt_started=1, batch_attempted=0, order_placement_attempted=0, queue_json=?, "
                "execution_id=NULL, execution_lease_until=NULL, updated_at=? WHERE strategy_id=?",
                (
                    encode_json(contract), encode_json(snapshot), encode_json(orders), encode_json(results),
                    preview["previewHash"], encode_json(prepared), encode_json(queue), self.api.now, strategy_id,
                ),
            )

    def _assert_malformed_order_ack_stops_tail(self, ack: dict[str, Any]) -> None:
        strategy_id, prepared = self._start_queue()
        first_client_id = prepared["orders"][0]["clientOrderId"]
        self.api.exchange.single_order_acks[0] = ack

        self.assertTrue(self._worker().run_once())
        strategy = self._read_strategy(strategy_id)
        self.assertEqual(strategy["status"], "UNKNOWN")
        self.assertEqual(strategy["queue"]["phase"], "stopped")
        self.assertEqual(
            [row["placementState"] for row in strategy["results"]],
            ["unknown", "not_submitted", "not_submitted"],
        )
        self.assertTrue(strategy["orderPlacementAttempted"])
        self.assertEqual(self.api.exchange.single_order_attempts, 1)
        self.assertEqual(
            [call[2]["clOrdId"] for call in self.api.exchange.trade_writes
             if call[1].split("?", 1)[0] == "/api/v5/trade/order"],
            [first_client_id],
        )

        status, reconciled = self.api.request("GET", f"/v1/strategies/{strategy_id}/result")
        self.assertEqual(status, 200, reconciled)
        self.assertEqual(reconciled["status"], "UNKNOWN")
        self.assertEqual(self.api.exchange.order_detail_client_ids, [first_client_id])

        with self.api.service.store.connection() as connection:
            prior_lease = connection.execute(
                "SELECT owner_id, fence FROM strategy_monitor_lease WHERE singleton=1"
            ).fetchone()
        self.assertEqual(prior_lease["owner_id"], "queue-worker")
        prior_fence = prior_lease["fence"]
        self.api.now += 35
        self.assertTrue(self._worker("queue-worker-restart").run_once())
        with self.api.service.store.connection() as connection:
            takeover = connection.execute(
                "SELECT owner_id, fence FROM strategy_monitor_lease WHERE singleton=1"
            ).fetchone()
        self.assertEqual(takeover["owner_id"], "queue-worker-restart")
        self.assertGreater(takeover["fence"], prior_fence)
        self.assertEqual(self.api.exchange.single_order_attempts, 1)
        self.assertEqual(
            self.api.exchange.order_detail_client_ids,
            [first_client_id, first_client_id],
        )
        strategy = self._read_strategy(strategy_id)
        self.assertEqual(strategy["queue"]["phase"], "stopped")
        self.assertEqual(
            [row["placementState"] for row in strategy["results"]],
            ["unknown", "not_submitted", "not_submitted"],
        )

    def _read_strategy(self, strategy_id: str) -> dict[str, Any]:
        with self.api.service.store.connection() as connection:
            row = connection.execute(
                "SELECT * FROM strategies WHERE strategy_id=?", (strategy_id,)
            ).fetchone()
        self.assertIsNotNone(row)
        return self.api.service.strategy._decode_row(row)

    def _seed_accepted_prefix(self, strategy_id: str, *, raw_mode: str = "sequential") -> None:
        with self.api.service.store.transaction() as connection:
            row = connection.execute(
                "SELECT queue_json, results_json FROM strategies WHERE strategy_id=?",
                (strategy_id,),
            ).fetchone()
            queue = decode_json(row["queue_json"])
            results = decode_json(row["results_json"])
            queue.update({"phase": "sending", "cursor": 1, "inFlight": None})
            results[0] = {
                **results[0],
                "status": "accepted",
                "placementState": "accepted",
                "exchangeOrderId": "accepted-before-restart",
            }
            connection.execute(
                "UPDATE strategies SET queue_json=?, results_json=?, submission_mode=?, "
                "order_placement_attempted=1, execution_lease_until=NULL, updated_at=? "
                "WHERE strategy_id=?",
                (encode_json(queue), encode_json(results), raw_mode, self.api.now, strategy_id),
            )

    def _reservation_exists(self, strategy_id: str) -> bool:
        with self.api.service.store.connection() as connection:
            return connection.execute(
                "SELECT 1 FROM strategy_reservations WHERE strategy_id=?", (strategy_id,)
            ).fetchone() is not None

    def test_red_timeout_stops_tail_without_resend(self) -> None:
        strategy_id, prepared = self._start_queue()
        self.api.exchange.single_order_timeouts.add(1)

        worker = self._worker()
        self.assertTrue(worker.run_once())

        single_writes = [
            call for call in self.api.exchange.trade_writes
            if call[1].split("?", 1)[0] == "/api/v5/trade/order"
        ]
        self.assertEqual(len(single_writes), 2)
        self.assertEqual(self.api.exchange.batch_writes, [])
        self.assertEqual(
            [payload["clOrdId"] for _, _, payload in single_writes],
            [row["clientOrderId"] for row in prepared["orders"][:2]],
        )

        result = self._read_strategy(strategy_id)
        self.assertEqual(result["status"], "UNKNOWN")
        self.assertEqual(result["queue"]["phase"], "stopped")
        self.assertEqual(
            [row["placementState"] for row in result["results"]],
            ["accepted", "unknown", "not_submitted"],
        )
        self.assertTrue(result["orderPlacementAttempted"])
        self.assertTrue(self._reservation_exists(strategy_id))

        status, reconciled = self.api.request("GET", f"/v1/strategies/{strategy_id}/result")
        self.assertEqual(status, 200, reconciled)
        self.assertEqual(reconciled["status"], "UNKNOWN")
        self.assertTrue(self._reservation_exists(strategy_id))
        self.assertEqual(
            self.api.exchange.order_detail_client_ids,
            [row["clientOrderId"] for row in prepared["orders"][:2]],
        )
        self.assertEqual(self.api.exchange.single_order_attempts, 2)
        status, deletion = self.api.request("POST", f"/v1/strategies/{strategy_id}/delete", {})
        self.assertEqual(status, 409, deletion)
        self.assertEqual(deletion["error"], "strategy_immutable")
        contract = self._contract()
        status, preview = self.api.request("POST", "/v1/strategies/preview", contract)
        self.assertEqual(status, 200, preview)
        status, replacement = self.api.request(
            "POST", "/v1/strategies",
            {**contract, "previewHash": preview["previewHash"], "replacementSourceId": strategy_id},
        )
        self.assertEqual(status, 409, replacement)
        self.assertEqual(replacement["error"], "replacement_source_unavailable")

        reads_before_restart = self.api.exchange.order_detail_reads
        self.api.now += 35
        self.assertTrue(self._worker("queue-worker-restart").run_once())
        self.assertEqual(self.api.exchange.single_order_attempts, 2)
        self.assertEqual(self.api.exchange.order_detail_reads, reads_before_restart + 2)
        self.assertTrue(self._reservation_exists(strategy_id))

    def test_green_exact_fifo_single_order_submission(self) -> None:
        strategy_id, prepared = self._start_queue()

        worker = self._worker()
        self.assertTrue(worker.run_once())

        writes = [
            payload for method, path, payload in self.api.exchange.trade_writes
            if method == "POST" and path.split("?", 1)[0] == "/api/v5/trade/order"
        ]
        self.assertEqual(
            [row["clOrdId"] for row in writes],
            [row["clientOrderId"] for row in prepared["orders"]],
        )
        strategy = self._read_strategy(strategy_id)
        expected_payloads = [
            self.api.service.strategy._okx_order(strategy["contract"], row, "net_mode")
            for row in prepared["orders"]
        ]
        self.assertEqual(writes, expected_payloads)
        self.assertEqual(self.api.exchange.batch_writes, [])
        self.assertEqual(len(self.api.exchange.single_order_start_times), 3)
        self.assertTrue(all(
            later - earlier >= 0.250
            for earlier, later in zip(
                self.api.exchange.single_order_start_times,
                self.api.exchange.single_order_start_times[1:],
            )
        ))
        result = self._read_strategy(strategy_id)
        self.assertEqual(result["status"], "APPLIED")
        self.assertEqual(result["queue"]["phase"], "submitted")
        self.assertEqual([row["placementState"] for row in result["results"]], ["accepted"] * 3)

    def test_green_ten_order_queue_finishes_the_full_tail(self) -> None:
        strategy_id, prepared = self._start_queue(count=10)
        self.assertEqual(len(prepared["orders"]), 10)

        self.assertTrue(self._worker().run_once())

        strategy = self._read_strategy(strategy_id)
        self.assertEqual(strategy["status"], "APPLIED")
        self.assertEqual(strategy["queue"]["totalCount"], 10)
        self.assertEqual([row["placementState"] for row in strategy["results"]], ["accepted"] * 10)
        self.assertEqual(self.api.exchange.single_order_attempts, 10)

    def test_delayed_prewrite_lease_renewal_does_not_shorten_actual_call_spacing(self) -> None:
        self._start_queue()
        store = self.api.service.store
        original_renew = store.renew_strategy_monitor_lease
        delayed = False

        def delayed_renew(owner_id: str, fence: int, now: float, lease_seconds: float, *, clock: Any = None) -> bool:
            nonlocal delayed
            with store.connection() as connection:
                row = connection.execute(
                    "SELECT queue_json FROM strategies WHERE status='APPLYING' "
                    "AND submission_mode='sequential' AND queue_json IS NOT NULL LIMIT 1"
                ).fetchone()
            queue = None if row is None else decode_json(row["queue_json"])
            marker = queue.get("inFlight") if isinstance(queue, dict) else None
            if not delayed and isinstance(marker, dict) and marker.get("kind") == "placement":
                delayed = True
                self.monotonic_now += 0.2
                self.api.now += 0.2
            return original_renew(owner_id, fence, now, lease_seconds, clock=clock)

        store.renew_strategy_monitor_lease = delayed_renew
        try:
            self.assertTrue(self._worker().run_once())
        finally:
            store.renew_strategy_monitor_lease = original_renew
        starts = self.api.exchange.single_order_start_times
        self.assertEqual(len(starts), 3)
        self.assertAlmostEqual(starts[0], 0.2)
        self.assertGreaterEqual(starts[1] - starts[0], 0.250)
        self.assertGreaterEqual(starts[2] - starts[1], 0.250)

    def test_invalid_saved_preference_fails_closed_without_order_writes(self) -> None:
        strategy_id, _ = self.api.save_draft(self._contract(1))
        fingerprint = token_digest("okx-account-uid:v1:" + self.api.exchange.account_uid, SIGNING_KEY)
        with self.api.service.store.transaction() as connection:
            connection.execute(
                "UPDATE strategy_account_preferences SET limit_order_submission_mode='corrupt' "
                "WHERE account_fingerprint=?", (fingerprint,)
            )

        status, result = self.api.request(
            "POST", f"/v1/strategies/{strategy_id}/prepare-apply", {}
        )

        self.assertEqual(status, 500, result)
        self.assertEqual(result["error"], "strategy_settings_unavailable")
        self.assertEqual(self.api.exchange.trade_writes, [])

    def test_invalid_settings_post_returns_400_and_keeps_saved_preference(self) -> None:
        status, before = self.api.request("GET", "/v1/strategies/settings")
        self.assertEqual(status, 200, before)
        self.assertEqual(before["limitOrderSubmissionMode"], "batch")

        status, invalid = self.api.request(
            "POST", "/v1/strategies/settings", {"limitOrderSubmissionMode": "parallel"}
        )

        self.assertEqual(status, 400, invalid)
        self.assertEqual(invalid["error"], "invalid_submission_mode")
        status, after = self.api.request("GET", "/v1/strategies/settings")
        self.assertEqual(status, 200, after)
        self.assertEqual(after["limitOrderSubmissionMode"], "batch")
        self.assertEqual(self.api.exchange.trade_writes, [])

    def test_legacy_prepared_record_without_mode_still_uses_batch_path(self) -> None:
        status, setting = self.api.request(
            "POST", "/v1/strategies/settings", {"limitOrderSubmissionMode": "batch"}
        )
        self.assertEqual(status, 200, setting)
        strategy_id, _ = self.api.save_draft(self._contract(1))
        status, prepared = self.api.request(
            "POST", f"/v1/strategies/{strategy_id}/prepare-apply", {}
        )
        self.assertEqual(status, 200, prepared)
        with self.api.service.store.transaction() as connection:
            row = connection.execute(
                "SELECT prepared_json FROM strategies WHERE strategy_id=?", (strategy_id,)
            ).fetchone()
            legacy_prepared = decode_json(row["prepared_json"])
            legacy_prepared.pop("submissionMode", None)
            connection.execute(
                "UPDATE strategies SET prepared_json=? WHERE strategy_id=?",
                (encode_json(legacy_prepared), strategy_id),
            )

        status, applied = self.api.request(
            "POST", f"/v1/strategies/{strategy_id}/execute-apply",
            {"confirmationToken": prepared["confirmationToken"]},
        )

        self.assertEqual(status, 200, applied)
        self.assertEqual(applied["status"], "APPLIED")
        self.assertEqual(applied["submissionMode"], "batch")
        self.assertEqual(len(self.api.exchange.batch_writes), 1)
        self.assertEqual(self.api.exchange.single_order_attempts, 0)

    def test_each_external_preflight_read_has_a_fresh_lease_renewal(self) -> None:
        self._start_queue(count=1)
        store = self.api.service.store
        original_renew = store.renew_strategy_monitor_lease
        renewals = 0

        def counted_renew(
            owner_id: str, fence: int, now: float, lease_seconds: float, *, clock: Any = None
        ) -> bool:
            nonlocal renewals
            renewed = original_renew(owner_id, fence, now, lease_seconds, clock=clock)
            if renewed:
                renewals += 1
            return renewed

        store.renew_strategy_monitor_lease = counted_renew
        self.api.exchange.calls.clear()
        self.api.exchange.lease_renewal_counts.clear()
        self.api.exchange.lease_renewal_counter = lambda: renewals
        try:
            self.assertTrue(self._worker().run_once())
        finally:
            store.renew_strategy_monitor_lease = original_renew
            self.api.exchange.lease_renewal_counter = None

        self.assertEqual(len(self.api.exchange.calls), len(self.api.exchange.lease_renewal_counts))
        counts = self.api.exchange.lease_renewal_counts
        self.assertTrue(all(later > earlier for earlier, later in zip(counts, counts[1:])))
        paths = {path.split("?", 1)[0] for _, path, _ in self.api.exchange.calls}
        self.assertTrue({
            "/api/v5/account/config",
            "/api/v5/public/instruments",
            "/api/v5/market/ticker",
            "/api/v5/account/trade-fee",
            "/api/v5/public/position-tiers",
            "/api/v5/account/positions",
            "/api/v5/trade/orders-pending",
            "/api/v5/account/balance",
        }.issubset(paths))

    def test_lost_fence_after_http_ack_keeps_marker_and_never_sends_tail(self) -> None:
        strategy_id, _ = self._start_queue()

        def steal_fence(_payload: dict[str, Any], _exchange_id: str) -> None:
            with self.api.service.store.transaction() as connection:
                lease = connection.execute(
                    "SELECT fence FROM strategy_monitor_lease WHERE singleton=1"
                ).fetchone()
                connection.execute(
                    "UPDATE strategy_monitor_lease SET owner_id='other-worker', fence=?, lease_until=? "
                    "WHERE singleton=1",
                    (lease["fence"] + 1, self.api.now + 30),
                )

        self.api.exchange.after_single_order_write = steal_fence
        self.assertTrue(self._worker().run_once())

        strategy = self._read_strategy(strategy_id)
        self.assertEqual(self.api.exchange.single_order_attempts, 1)
        self.assertEqual(strategy["status"], "APPLYING")
        self.assertEqual(strategy["queue"]["inFlight"], {"kind": "placement", "index": 0})
        self.assertEqual(strategy["results"][0]["placementState"], "sending")
        self.assertTrue(strategy["orderPlacementAttempted"])

    def test_resume_hash_change_stops_before_next_placement(self) -> None:
        strategy_id, _ = self._start_queue()
        self._seed_accepted_prefix(strategy_id)
        for fee in self.api.exchange.fee_data[0]["feeGroup"]:
            if fee["groupId"] == "2":
                fee["taker"] = "-0.0006"

        self.assertTrue(self._worker("queue-worker-restart").run_once())

        strategy = self._read_strategy(strategy_id)
        self.assertEqual(strategy["queue"]["phase"], "stopped")
        self.assertEqual(strategy["queue"]["stopReason"], "resume_validation_failed")
        self.assertEqual(self.api.exchange.single_order_attempts, 0)

    def test_ambiguous_leverage_ack_stops_before_any_order_placement(self) -> None:
        strategy_id, _ = self._start_queue()
        self.api.exchange.leverage_response = {
            "code": "0",
            "data": [{
                "instId": INSTRUMENT,
                "mgnMode": "isolated",
                "lever": "6",
                "posSide": "net",
            }],
        }

        self.assertTrue(self._worker().run_once())

        strategy = self._read_strategy(strategy_id)
        self.assertEqual(strategy["status"], "UNKNOWN")
        self.assertEqual(strategy["leverageResults"][0]["status"], "unknown")
        self.assertEqual(strategy["queue"]["phase"], "stopped")
        self.assertEqual(self.api.exchange.single_order_attempts, 0)

    def test_worker_pass_shares_twenty_placement_budget_and_preserves_spacing(self) -> None:
        first_id, _ = self._start_queue(count=10)
        self._seed_confirmed_legacy_queue_twenty(first_id)
        self.api.exchange.instrument_data.append({
            **self.api.exchange.instrument_data[0],
            "instId": "ETH-USDT-SWAP",
            "instFamily": "ETH-USDT",
            "groupId": "3",
            "baseCcy": "ETH",
            "ctValCcy": "ETH",
        })
        self.api.exchange.fee_data.append({
            "instType": "SWAP", "instFamily": "ETH-USDT",
            "feeGroup": [{"groupId": "3", "maker": "-0.0001", "taker": "-0.0005"}],
        })
        self.api.exchange.tier_data.append({
            **self.api.exchange.tier_data[0], "instFamily": "ETH-USDT",
        })
        self.api.exchange.use_requested_ticker = True
        second_id, _ = self._start_queue(count=1, instrument_id="ETH-USDT-SWAP")
        with self.api.service.store.transaction() as connection:
            connection.execute(
                "UPDATE strategies SET created_at=? WHERE strategy_id=?",
                (self.api.now + 1, second_id),
            )
        worker = self._worker()

        self.assertTrue(worker.run_once())

        self.assertEqual(self.api.exchange.single_order_attempts, 20)
        second = self._read_strategy(second_id)
        self.assertEqual(second["status"], "APPLYING")
        self.assertEqual(second["queue"]["cursor"], 0)

        self.assertTrue(worker.run_once())

        self.assertEqual(self.api.exchange.single_order_attempts, 21)
        starts = self.api.exchange.single_order_start_times
        self.assertGreaterEqual(starts[20] - starts[19], 0.250)
        self.assertEqual(self._read_strategy(second_id)["status"], "APPLIED")

    def test_default_preference_is_sequential_and_prepare_freezes_mode(self) -> None:
        fingerprint = token_digest("okx-account-uid:v1:" + self.api.exchange.account_uid, SIGNING_KEY)
        with self.api.service.store.transaction() as connection:
            connection.execute(
                "DELETE FROM strategy_account_preferences WHERE account_fingerprint=?", (fingerprint,)
            )
        status, settings = self.api.request("GET", "/v1/strategies/settings")
        self.assertEqual(status, 200, settings)
        self.assertEqual(settings["limitOrderSubmissionMode"], "sequential")

        strategy_id, _ = self.api.save_draft(self._contract(1))
        status, prepared = self.api.request(
            "POST", f"/v1/strategies/{strategy_id}/prepare-apply", {}
        )
        self.assertEqual(status, 200, prepared)
        self.assertEqual(prepared["submissionMode"], "sequential")
        status, saved = self.api.request(
            "POST", "/v1/strategies/settings", {"limitOrderSubmissionMode": "batch"}
        )
        self.assertEqual(status, 200, saved)
        status, applying = self.api.request(
            "POST", f"/v1/strategies/{strategy_id}/execute-apply",
            {"confirmationToken": prepared["confirmationToken"]},
        )
        self.assertEqual(status, 200, applying)
        self.assertEqual(applying["submissionMode"], "sequential")
        self.assertEqual(applying["queueStatus"], "pending")

        self.api.exchange.account_uid = "987654321"
        status, other_account = self.api.request("GET", "/v1/strategies/settings")
        self.assertEqual(status, 200, other_account)
        self.assertEqual(other_account["limitOrderSubmissionMode"], "sequential")

    def test_order_ack_missing_or_malformed_top_code_is_unknown(self) -> None:
        response_row = {"sCode": "0", "ordId": "exchange-1", "clOrdId": "client-1"}
        self.assertEqual(
            parse_order_ack({"data": [response_row]}, "client-1"),
            ("unknown", None, None, "order_ack_malformed"),
        )
        self.assertEqual(
            parse_order_ack({"code": "bad", "data": [response_row]}, "client-1"),
            ("unknown", None, None, "order_ack_malformed"),
        )
        self.assertEqual(
            parse_order_ack(
                {"code": "0", "data": [{**response_row, "clOrdId": "another-client"}]},
                "client-1",
            ),
            ("unknown", None, None, "order_ack_malformed"),
        )
        self.assertEqual(
            parse_order_ack(
                {"code": "0", "data": [{"sCode": "0", "clOrdId": "client-1"}]},
                "client-1",
            ),
            ("unknown", None, None, "order_ack_malformed"),
        )
        self.assertEqual(
            parse_order_ack({"code": "51000", "data": []}, "client-1"),
            ("rejected", None, "51000", "order_rejected"),
        )

    def test_mismatched_client_id_ack_stops_tail_across_restart(self) -> None:
        self._assert_malformed_order_ack_stops_tail({
            "code": "0",
            "data": [{"sCode": "0", "ordId": "exchange-mismatch", "clOrdId": "wrong-client"}],
        })

    def test_missing_order_id_ack_stops_tail_across_restart(self) -> None:
        self._assert_malformed_order_ack_stops_tail({
            "code": "0",
            "data": [{"sCode": "0", "clOrdId": "placeholder-client"}],
        })

    def test_leverage_ack_requires_matching_actual_success_fields(self) -> None:
        expected = {
            "instId": INSTRUMENT,
            "mgnMode": "isolated",
            "lever": "5",
            "posSide": "net",
        }
        self.assertEqual(
            StrategyOrderWorker._leverage_outcome(
                {"code": "0", "data": [expected]}, "net", INSTRUMENT, 5
            ),
            ("applied", None),
        )
        for field, value in (("instId", "ETH-USDT-SWAP"), ("mgnMode", "cross"),
                             ("posSide", "long"), ("lever", "5.1")):
            mismatched = {**expected, field: value}
            self.assertEqual(
                StrategyOrderWorker._leverage_outcome(
                    {"code": "0", "data": [mismatched]}, "net", INSTRUMENT, 5
                ),
                ("unknown", None),
            )
        self.assertEqual(
            StrategyOrderWorker._leverage_outcome(
                {"code": "0", "data": [{**expected, "sCode": "51000"}]},
                "net", INSTRUMENT, 5,
            ),
            ("rejected", "51000"),
        )
        self.assertEqual(
            StrategyOrderWorker._leverage_outcome(
                {"data": [expected]}, "net", INSTRUMENT, 5
            ),
            ("unknown", None),
        )

    def test_resume_after_accepted_prefix_skips_initial_position_and_pending_guards(self) -> None:
        strategy_id, prepared = self._start_queue()
        self._seed_accepted_prefix(strategy_id)
        self.api.exchange.positions = [{"instId": INSTRUMENT, "pos": "1", "posSide": "net"}]
        self.api.exchange.pending = [{"instId": INSTRUMENT, "clOrdId": "own-pending"}]
        self.api.exchange.position_reads = 0
        self.api.exchange.pending_reads = 0

        self.assertTrue(self._worker("queue-worker-restart").run_once())

        posted_ids = [
            payload["clOrdId"] for method, path, payload in self.api.exchange.trade_writes
            if method == "POST" and path.split("?", 1)[0] == "/api/v5/trade/order"
        ]
        self.assertEqual(posted_ids, [row["clientOrderId"] for row in prepared["orders"][1:]])
        self.assertEqual(self.api.exchange.position_reads, 0)
        self.assertEqual(self.api.exchange.pending_reads, 0)
        self.assertGreaterEqual(self.api.exchange.single_order_start_times[0], 0.250)
        self.assertEqual(self._read_strategy(strategy_id)["status"], "APPLIED")

    def test_raw_submission_mode_mismatch_after_prefix_stops_without_writes(self) -> None:
        strategy_id, _ = self._start_queue()
        self._seed_accepted_prefix(strategy_id, raw_mode="batch")

        self.assertTrue(self._worker("queue-worker-restart").run_once())

        strategy = self._read_strategy(strategy_id)
        self.assertTrue(strategy["submissionModeInvalid"])
        self.assertEqual(strategy["queue"]["phase"], "stopped")
        self.assertEqual(self.api.exchange.single_order_attempts, 0)
        self.assertEqual(self.api.exchange.batch_writes, [])

    def test_stopped_queue_completes_after_terminal_prefix_and_fresh_zero_positions(self) -> None:
        strategy_id, prepared = self._start_queue()
        self.api.exchange.single_order_acks[1] = {
            "code": "0",
            "data": [{"sCode": "51008", "clOrdId": prepared["orders"][1]["clientOrderId"]}],
        }
        worker = self._worker()
        self.assertTrue(worker.run_once())
        stopped = self._read_strategy(strategy_id)
        self.assertEqual(stopped["status"], "PARTIAL")
        self.assertEqual(stopped["queue"]["phase"], "stopped")
        first_client_id = prepared["orders"][0]["clientOrderId"]
        self.api.exchange.orders[first_client_id]["state"] = "canceled"

        self.api.now += 5
        self.assertTrue(worker.run_once())

        completed = self._read_strategy(strategy_id)
        self.assertEqual(completed["status"], "COMPLETED")
        self.assertEqual(completed["queue"]["phase"], "stopped")
        self.assertEqual(
            [row["status"] for row in completed["results"]],
            ["canceled", "rejected", "not_submitted"],
        )

    def test_deadline_crossed_during_resume_pacing_stops_before_http_write(self) -> None:
        strategy_id, _ = self._start_queue()
        self._seed_accepted_prefix(strategy_id)
        with self.api.service.store.transaction() as connection:
            row = connection.execute(
                "SELECT queue_json FROM strategies WHERE strategy_id=?", (strategy_id,)
            ).fetchone()
            queue = decode_json(row["queue_json"])
            queue["deadlineAt"] = self.api.now + 0.1
            connection.execute(
                "UPDATE strategies SET queue_json=? WHERE strategy_id=?",
                (encode_json(queue), strategy_id),
            )

        self.assertTrue(self._worker("queue-worker-restart").run_once())

        strategy = self._read_strategy(strategy_id)
        self.assertEqual(strategy["queue"]["phase"], "stopped")
        self.assertEqual(strategy["queue"]["stopReason"], "queue_expired")
        self.assertEqual(self.api.exchange.single_order_attempts, 0)

    def test_interrupted_inflight_marker_becomes_unknown_without_retry(self) -> None:
        strategy_id, _ = self._start_queue()
        with self.api.service.store.transaction() as connection:
            row = connection.execute(
                "SELECT queue_json, results_json FROM strategies WHERE strategy_id=?",
                (strategy_id,),
            ).fetchone()
            queue = decode_json(row["queue_json"])
            results = decode_json(row["results_json"])
            queue.update({"phase": "sending", "inFlight": {"kind": "placement", "index": 0}})
            results[0] = {**results[0], "status": "sending", "placementState": "sending"}
            connection.execute(
                "UPDATE strategies SET queue_json=?, results_json=?, order_placement_attempted=1, "
                "execution_lease_until=NULL WHERE strategy_id=?",
                (encode_json(queue), encode_json(results), strategy_id),
            )

        self.assertTrue(self._worker("queue-worker-restart").run_once())

        strategy = self._read_strategy(strategy_id)
        self.assertEqual(strategy["status"], "UNKNOWN")
        self.assertEqual(strategy["results"][0]["placementState"], "unknown")
        self.assertEqual(strategy["queue"]["phase"], "stopped")
        self.assertEqual(self.api.exchange.single_order_attempts, 0)

    def test_restart_cursor_zero_skips_committed_successful_leverage(self) -> None:
        strategy_id, _ = self._start_queue(count=1)
        with self.api.service.store.transaction() as connection:
            connection.execute(
                "UPDATE strategies SET leverage_results_json=? WHERE strategy_id=?",
                (encode_json([{"side": "long", "status": "applied"}]), strategy_id),
            )

        self.assertTrue(self._worker("queue-worker-restart").run_once())

        self.assertEqual(
            [path for method, path, _ in self.api.exchange.trade_writes
             if method == "POST" and path.split("?", 1)[0] == "/api/v5/account/set-leverage"],
            [],
        )
        self.assertEqual(self.api.exchange.single_order_attempts, 1)
        self.assertEqual(self._read_strategy(strategy_id)["status"], "APPLIED")

    def test_never_sent_stopped_queue_remains_delete_and_replacement_eligible(self) -> None:
        first_source, _ = self._start_queue(count=1)
        self.api.exchange.positions = [{"instId": INSTRUMENT, "pos": "1", "posSide": "net"}]
        worker = self._worker()
        self.assertTrue(worker.run_once())
        status, stopped = self.api.request("GET", f"/v1/strategies/{first_source}/result")
        self.assertEqual(status, 200, stopped)
        self.assertEqual(stopped["queueStatus"], "stopped")
        self.assertFalse(stopped["orderPlacementAttempted"])
        self.assertTrue(stopped["canDelete"])
        status, deleted = self.api.request("POST", f"/v1/strategies/{first_source}/delete", {})
        self.assertEqual(status, 200, deleted)
        self.assertEqual(deleted["status"], "DELETED")

        self.api.exchange.positions = []
        second_source, _ = self._start_queue(count=1)
        self.api.exchange.positions = [{"instId": INSTRUMENT, "pos": "1", "posSide": "net"}]
        self.assertTrue(worker.run_once())
        status, stopped = self.api.request("GET", f"/v1/strategies/{second_source}/result")
        self.assertEqual(status, 200, stopped)
        self.assertTrue(stopped["canDelete"])

        replacement_id, _ = self.api.save_draft(
            self._contract(1), replacement_source_id=second_source
        )
        replacement = self._read_strategy(replacement_id)
        self.assertEqual(replacement["replacementSourceId"], second_source)

    def test_lease_and_queue_commits_sample_clock_after_transaction_lock(self) -> None:
        strategy_id, _ = self._start_queue()
        store = self.api.service.store
        owner = "stale-clock-worker"
        fence = store.acquire_strategy_monitor_lease(owner, self.api.now, 1)
        self.assertIsNotNone(fence)
        original_transaction = store.transaction

        @contextmanager
        def advance_after_lock():
            with original_transaction() as connection:
                self.api.now += 2
                yield connection

        store.transaction = advance_after_lock
        try:
            self.assertFalse(
                store.renew_strategy_monitor_lease(
                    owner, fence, self.api.now - 2, 30, clock=lambda: self.api.now
                )
            )
        finally:
            store.transaction = original_transaction

        fence = store.acquire_strategy_monitor_lease(owner, self.api.now, 1)
        self.assertIsNotNone(fence)
        strategy = self._read_strategy(strategy_id)
        queue = {**strategy["queue"], "phase": "sending", "inFlight": {"kind": "placement", "index": 0}}
        results = [dict(row) for row in strategy["results"]]
        results[0] = {**results[0], "status": "sending", "placementState": "sending"}
        ledger = StrategyQueueLedger(
            store, owner_id=owner, fence=fence, lease_seconds=1, clock=lambda: self.api.now
        )
        store.transaction = advance_after_lock
        try:
            self.assertFalse(ledger.persist_transition(
                strategy,
                queue=queue,
                results=results,
                status="APPLYING",
                failure_reason=None,
                leverage_results=strategy["leverageResults"],
                mark_placement_attempted=True,
            ))
        finally:
            store.transaction = original_transaction
        self.assertIsNone(self._read_strategy(strategy_id)["queue"]["inFlight"])

        # Commit a real marker, then prove that a delayed ACK transaction cannot
        # renew the expired fence or replace the durable in-flight marker.
        fence = store.acquire_strategy_monitor_lease(owner, self.api.now, 1)
        self.assertIsNotNone(fence)
        strategy = self._read_strategy(strategy_id)
        ledger = StrategyQueueLedger(
            store, owner_id=owner, fence=fence, lease_seconds=1, clock=lambda: self.api.now
        )
        self.assertTrue(ledger.persist_transition(
            strategy,
            queue=queue,
            results=results,
            status="APPLYING",
            failure_reason=None,
            leverage_results=strategy["leverageResults"],
            mark_placement_attempted=True,
        ))
        marked = self._read_strategy(strategy_id)
        accepted_queue = {
            **marked["queue"], "phase": "sending", "cursor": 1, "inFlight": None
        }
        accepted_results = [dict(row) for row in marked["results"]]
        accepted_results[0] = {
            **accepted_results[0], "status": "accepted", "placementState": "accepted",
            "exchangeOrderId": "late-ack",
        }
        store.transaction = advance_after_lock
        try:
            self.assertFalse(ledger.persist_transition(
                marked,
                queue=accepted_queue,
                results=accepted_results,
                status="APPLYING",
                failure_reason=None,
                leverage_results=marked["leverageResults"],
            ))
        finally:
            store.transaction = original_transaction
        durable = self._read_strategy(strategy_id)
        self.assertEqual(durable["queue"]["inFlight"], {"kind": "placement", "index": 0})
        self.assertEqual(durable["results"][0]["placementState"], "sending")

    def test_additive_schema_upgrade_backfills_legacy_batch_attempts(self) -> None:
        legacy_path = Path(self.api.settings.operation_db_path).with_name("queue-legacy.sqlite3")
        legacy_path.unlink(missing_ok=True)
        connection = sqlite3.connect(legacy_path)
        try:
            connection.execute(
                "CREATE TABLE strategies (strategy_id TEXT PRIMARY KEY, account_fingerprint TEXT NOT NULL, "
                "status TEXT NOT NULL, contract_json TEXT NOT NULL, snapshot_json TEXT NOT NULL, "
                "orders_json TEXT NOT NULL, results_json TEXT NOT NULL, preview_hash TEXT NOT NULL, "
                "confirmation_hash TEXT, prepared_expires_at REAL, prepared_json TEXT, "
                "attempt_started INTEGER NOT NULL DEFAULT 0, batch_attempted INTEGER NOT NULL DEFAULT 0, "
                "execution_id TEXT, execution_lease_until REAL, replacement_source_id TEXT, "
                "failure_reason TEXT, leverage_results_json TEXT NOT NULL DEFAULT '[]', "
                "created_at REAL NOT NULL, updated_at REAL NOT NULL)"
            )
            connection.execute(
                "INSERT INTO strategies(strategy_id, account_fingerprint, status, contract_json, snapshot_json, "
                "orders_json, results_json, preview_hash, attempt_started, batch_attempted, created_at, updated_at) "
                "VALUES ('legacy-batch', 'fingerprint', 'APPLYING', '{}', '{}', '[]', '[]', '', 1, 1, 1, 1)"
            )
            connection.commit()
        finally:
            connection.close()
        self.addCleanup(lambda: legacy_path.unlink(missing_ok=True))

        migrated = SQLiteStore(str(legacy_path))
        migrated.initialize()
        with migrated.connection() as connection:
            columns = {row[1] for row in connection.execute("PRAGMA table_info(strategies)")}
            row = connection.execute(
                "SELECT submission_mode, order_placement_attempted, queue_json FROM strategies "
                "WHERE strategy_id='legacy-batch'"
            ).fetchone()
            preference_table = connection.execute(
                "SELECT name FROM sqlite_master WHERE type='table' AND name='strategy_account_preferences'"
            ).fetchone()
        self.assertTrue({"submission_mode", "order_placement_attempted", "queue_json"}.issubset(columns))
        self.assertEqual(tuple(row), ("batch", 1, None))
        self.assertIsNotNone(preference_table)


if __name__ == "__main__":
    unittest.main()
