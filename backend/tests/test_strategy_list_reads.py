from __future__ import annotations

import json
import unittest
from unittest.mock import patch
from urllib.parse import urlsplit

import backend.tests.test_strategy_api as api_fixtures


class StrategyListReadTests(unittest.TestCase):
    def setUp(self) -> None:
        self.api = api_fixtures.StrategyApiTests(
            "test_red_strategy_routes_require_bearer_before_exchange_reads"
        )
        self.api.setUp()
        self.addCleanup(self.api.tearDown)
        self.exchange = self.api.exchange
        self.strategy = self.api.service.strategy

    def save_draft(self) -> str:
        strategy_id, _ = self.api.save_draft()
        return strategy_id

    def request_list(self) -> tuple[int, dict[str, object]]:
        return self.api.request("GET", "/v1/strategies")

    def test_red_list_shares_one_terminal_position_observation_across_records(self) -> None:
        for _ in range(3):
            self.save_draft()
        self.exchange.calls.clear()
        self.exchange.position_reads = 0

        status, result = self.request_list()

        self.assertEqual(status, 200, result)
        strategies = result["strategies"]
        self.assertEqual(len(strategies), 3)
        identity_reads = sum(
            urlsplit(path).path == "/api/v5/account/config"
            for _, path, _ in self.exchange.calls
        )
        self.assertEqual(identity_reads, 3)
        self.assertEqual(self.exchange.position_reads, 1)
        self.assertEqual(len({row["observedAt"] for row in strategies}), 1)

    def test_red_list_rejects_account_change_after_shared_position_observation(self) -> None:
        self.save_draft()
        read_positions = self.strategy._terminal_delete_position_rows

        def change_account_after_position_read() -> tuple[list[object] | None, bool]:
            positions, valid = read_positions()
            self.exchange.account_uid = "987654321"
            return positions, valid

        with patch.object(
            self.strategy,
            "_terminal_delete_position_rows",
            side_effect=change_account_after_position_read,
        ):
            status, result = self.request_list()

        self.assertEqual(status, 409, result)
        self.assertEqual(result["error"], "account_changed")

    def test_green_list_finishes_all_order_scans_before_shared_position_read(self) -> None:
        strategy_ids = [self.save_draft() for _ in range(2)]
        with self.api.service.store.transaction() as connection:
            for strategy_id in strategy_ids:
                connection.execute(
                    "UPDATE strategies SET status='UNKNOWN' WHERE strategy_id=?", (strategy_id,)
                )
        events: list[str] = []
        read_positions = self.strategy._terminal_delete_position_rows

        def reconcile(strategy: dict[str, object]) -> tuple[dict[str, object], None]:
            events.append(str(strategy["id"]))
            return strategy, None

        def read_shared_positions() -> tuple[list[object] | None, bool]:
            events.append("positions")
            return read_positions()

        with (
            patch.object(self.strategy, "_order_scan_due", return_value=True),
            patch.object(self.strategy, "_reconcile_orders_with_outcome", side_effect=reconcile),
            patch.object(self.strategy, "_terminal_delete_position_rows", side_effect=read_shared_positions),
        ):
            status, result = self.request_list()

        self.assertEqual(status, 200, result)
        self.assertEqual(events[-1], "positions")
        self.assertEqual(events.count("positions"), 1)
        self.assertEqual(set(events[:-1]), set(strategy_ids))

    def test_red_malformed_shared_positions_make_every_terminal_delete_hint_unavailable(self) -> None:
        for _ in range(2):
            self.api._make_canceled_terminal_strategy()
        self.exchange.position_response_override = True
        self.exchange.position_response = {
            "code": "0",
            "data": [{"instId": "BTC-USDT-SWAP", "pos": "not-a-size", "posSide": "net"}],
        }
        self.exchange.position_reads = 0

        status, result = self.request_list()

        self.assertEqual(status, 200, result)
        self.assertEqual(self.exchange.position_reads, 1)
        self.assertEqual(len(result["strategies"]), 2)
        self.assertTrue(all(row["positionStatus"] == "unavailable" for row in result["strategies"]))
        self.assertTrue(all(row["canDelete"] is False for row in result["strategies"]))

    def test_red_stale_or_error_order_scan_blocks_shared_terminal_delete_hints(self) -> None:
        strategy_id, _ = self.api._make_canceled_terminal_strategy()
        cases = (
            (self.api.now - 1000, None, "stale"),
            (self.api.now - 10, "scan_failed", "error"),
        )
        for last_success, last_error, expected_state in cases:
            with self.subTest(expected_state=expected_state):
                with self.api.service.store.transaction() as connection:
                    connection.execute(
                        "UPDATE strategy_sync_state SET last_success_at=?, last_error=?, next_scan_at=? "
                        "WHERE strategy_id=?",
                        (last_success, last_error, self.api.now + 60, strategy_id),
                    )
                with patch.object(self.strategy, "_order_scan_due", return_value=False):
                    status, result = self.request_list()

                self.assertEqual(status, 200, result)
                listed = next(row for row in result["strategies"] if row["id"] == strategy_id)
                self.assertEqual(listed["orderSyncState"], expected_state)
                self.assertFalse(listed["canDelete"])

    def test_red_active_and_corrupt_sequential_queues_are_not_recovered_by_list(self) -> None:
        from backend.strategy_queue import new_queue

        for corrupt in (False, True):
            with self.subTest(corrupt=corrupt):
                strategy_id = self.save_draft()
                with self.api.service.store.transaction() as connection:
                    row = connection.execute(
                        "SELECT preview_hash FROM strategies WHERE strategy_id=?", (strategy_id,)
                    ).fetchone()
                    queue_raw = "{" if corrupt else api_fixtures.encode_json(
                        new_queue(enqueued_at=self.api.now, total_count=1, preview_hash=row["preview_hash"])
                    )
                    connection.execute(
                        "UPDATE strategies SET status='APPLYING', attempt_started=1, submission_mode='sequential', "
                        "queue_json=?, execution_lease_until=? WHERE strategy_id=?",
                        (queue_raw, self.api.now - 1, strategy_id),
                    )
                with (
                    patch.object(self.strategy, "_recover_interrupted_apply") as recover,
                    patch.object(self.strategy, "_reconcile_orders_with_outcome") as reconcile,
                ):
                    status, result = self.request_list()

                self.assertEqual(status, 200, result)
                listed = next(row for row in result["strategies"] if row["id"] == strategy_id)
                self.assertEqual(listed["status"], "APPLYING")
                self.assertEqual(listed["queueStatus"], "stopped" if corrupt else "pending")
                recover.assert_not_called()
                reconcile.assert_not_called()

    def test_green_list_cleans_fully_accepted_replacement_source(self) -> None:
        source_id = self.api._make_legacy_never_sent_source()
        replacement_id, _ = self.api.save_draft(replacement_source_id=source_id)
        with self.api.service.store.transaction() as connection:
            row = connection.execute(
                "SELECT results_json FROM strategies WHERE strategy_id=?", (replacement_id,)
            ).fetchone()
            results = json.loads(row["results_json"])
            accepted = [
                {**result, "status": "accepted", "exchangeOrderId": f"accepted-{index}"}
                for index, result in enumerate(results)
            ]
            connection.execute(
                "UPDATE strategies SET status='APPLIED', attempt_started=1, batch_attempted=1, "
                "order_placement_attempted=1, results_json=? WHERE strategy_id=?",
                (api_fixtures.encode_json(accepted), replacement_id),
            )

        with patch.object(self.strategy, "_order_scan_due", return_value=False):
            status, result = self.request_list()

        self.assertEqual(status, 200, result)
        self.assertIn(replacement_id, {row["id"] for row in result["strategies"]})
        self.assertNotIn(source_id, {row["id"] for row in result["strategies"]})
        with self.api.service.store.connection() as connection:
            self.assertIsNone(connection.execute(
                "SELECT 1 FROM strategies WHERE strategy_id=?", (source_id,)
            ).fetchone())

    def test_red_list_filters_a_record_deleted_during_shared_observation(self) -> None:
        for _ in range(2):
            self.save_draft()
        with self.api.service.store.connection() as connection:
            selected_ids = [
                row["strategy_id"]
                for row in connection.execute(
                    "SELECT strategy_id FROM strategies ORDER BY created_at DESC, strategy_id DESC"
                ).fetchall()
            ]
        deleted_id = selected_ids[0]
        read_positions = self.strategy._terminal_delete_position_rows

        def delete_during_observation() -> tuple[list[object] | None, bool]:
            with self.api.service.store.transaction() as connection:
                connection.execute("DELETE FROM strategies WHERE strategy_id=?", (deleted_id,))
            return read_positions()

        with patch.object(
            self.strategy,
            "_terminal_delete_position_rows",
            side_effect=delete_during_observation,
        ):
            status, result = self.request_list()

        self.assertEqual(status, 200, result)
        listed_ids = {row["id"] for row in result["strategies"]}
        self.assertNotIn(deleted_id, listed_ids)
        self.assertEqual(len(listed_ids), 1)

    def test_green_empty_and_candidate_only_lists_do_not_read_positions(self) -> None:
        status, empty = self.request_list()
        self.assertEqual(status, 200, empty)
        self.assertEqual(self.exchange.position_reads, 0)

        candidate_id = self.save_draft()
        with self.api.service.store.transaction() as connection:
            row = connection.execute(
                "SELECT snapshot_json FROM strategies WHERE strategy_id=?", (candidate_id,)
            ).fetchone()
            snapshot = json.loads(row["snapshot_json"])
            snapshot["draftStage"] = "candidates"
            snapshot["aiGeneration"] = {"requestId": "candidate-list-test"}
            connection.execute(
                "UPDATE strategies SET snapshot_json=? WHERE strategy_id=?",
                (api_fixtures.encode_json(snapshot), candidate_id),
            )
        self.exchange.position_reads = 0

        status, candidates = self.request_list()

        self.assertEqual(status, 200, candidates)
        self.assertEqual(self.exchange.position_reads, 0)
        self.assertEqual(candidates["strategies"][0]["draftStage"], "candidates")


if __name__ == "__main__":
    unittest.main()
