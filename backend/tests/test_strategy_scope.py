from __future__ import annotations

import sqlite3
import tempfile
import unittest
from pathlib import Path
from typing import Any
from unittest.mock import patch

from backend.store import SQLiteStore, encode_json
from backend.strategy_scope import (
    UNKNOWN_SCOPE,
    extract_persisted_scope,
    reservation_scope,
    scope_for_sides,
    scoped_pending_rows,
    scoped_position_rows,
    scopes_overlap,
)


INSTRUMENT = "BTC-USDT-SWAP"
ACCOUNT = "scope-test-account"


class StrategyScopeContractTests(unittest.TestCase):
    def test_only_opposite_single_sided_hedge_scopes_are_independent(self) -> None:
        long_scope = scope_for_sides("long_short_mode", ["long"])
        short_scope = scope_for_sides("long_short_mode", ["short"])
        both_scope = scope_for_sides("long_short_mode", ["long", "short"])
        net_scope = scope_for_sides("net_mode", ["long"])

        self.assertFalse(scopes_overlap(long_scope, short_scope))
        self.assertTrue(scopes_overlap(long_scope, long_scope))
        self.assertTrue(scopes_overlap(long_scope, both_scope))
        self.assertTrue(scopes_overlap(short_scope, both_scope))
        self.assertTrue(scopes_overlap(long_scope, net_scope))
        self.assertTrue(scopes_overlap(long_scope, UNKNOWN_SCOPE))
        self.assertTrue(scopes_overlap(reservation_scope("long_short_mode", "all"), short_scope))

    def test_prepared_scope_uses_consistent_orders_when_snapshot_omits_mode(self) -> None:
        order = {"clientOrderId": "scope-order-1", "side": "long", "contracts": "2"}
        prepared = {"_positionMode": "long_short_mode", "orders": [order]}
        snapshot = {"orders": [order]}
        stored = [{**order, "status": "accepted"}]

        scope = extract_persisted_scope(prepared, snapshot, stored)

        self.assertEqual(scope, scope_for_sides("long_short_mode", ["long"]))
        draft_snapshot = {"_positionMode": "net_mode", "orders": [order]}
        self.assertEqual(
            extract_persisted_scope(prepared, draft_snapshot, stored),
            scope_for_sides("long_short_mode", ["long"]),
        )
        mismatched = {"orders": [{**order, "side": "short"}]}
        self.assertFalse(extract_persisted_scope(prepared, mismatched, stored).valid)

    def test_malformed_unhashable_scope_and_exchange_evidence_fail_closed(self) -> None:
        cases = (
            ("long_short_mode", [{"side": "long"}]),
            ({"mode": "long_short_mode"}, ["long"]),
            ("unknown", ["long"]),
            ("net_mode", ["long", "short"]),
        )
        for mode, sides in cases:
            with self.subTest(mode=mode, sides=sides):
                self.assertFalse(scope_for_sides(mode, sides).valid)
        self.assertFalse(reservation_scope({}, {}).valid)
        self.assertFalse(reservation_scope("long_short_mode", []).valid)

        malformed_prepared = {"_positionMode": {}, "orders": []}
        self.assertFalse(extract_persisted_scope(malformed_prepared, {}, []).valid)
        self.assertFalse(extract_persisted_scope(
            {"_positionMode": "long_short_mode", "orders": []},
            {"_positionMode": {}, "orders": []},
            [],
        ).valid)

        long_scope = scope_for_sides("long_short_mode", ["long"])
        self.assertIsNone(scoped_position_rows(
            [{"instId": INSTRUMENT, "pos": "1", "posSide": {}}], INSTRUMENT, long_scope
        ))
        self.assertIsNone(scoped_pending_rows(
            [{"instId": INSTRUMENT, "posSide": ["short"], "side": "sell", "sz": "1"}],
            INSTRUMENT,
            long_scope,
        ))
        self.assertIsNone(scoped_pending_rows(
            [{"instId": INSTRUMENT, "posSide": "short", "side": {}, "sz": "1"}],
            INSTRUMENT,
            long_scope,
        ))


class StrategyReservationMigrationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory(prefix="strategy-scope-migration-")
        self.db_path = Path(self.temp_dir.name) / "store.sqlite3"
        self.store = SQLiteStore(str(self.db_path))
        self.store.initialize()

    def tearDown(self) -> None:
        self.temp_dir.cleanup()

    def _create_legacy_reservations(self, rows: list[tuple[str, str, str, float]]) -> None:
        with self.store.connection() as connection:
            connection.execute("DROP INDEX IF EXISTS strategy_reservations_scope_lookup")
            connection.execute("DROP TABLE strategy_reservations")
            connection.execute(
                "CREATE TABLE strategy_reservations ("
                "account_fingerprint TEXT NOT NULL, instrument_id TEXT NOT NULL, "
                "strategy_id TEXT NOT NULL UNIQUE, created_at REAL NOT NULL, "
                "PRIMARY KEY (account_fingerprint, instrument_id))"
            )
            connection.executemany(
                "INSERT INTO strategy_reservations "
                "(account_fingerprint, instrument_id, strategy_id, created_at) VALUES (?, ?, ?, ?)",
                rows,
            )

    def _insert_strategy(
        self,
        strategy_id: str,
        instrument: str,
        *,
        prepared: Any,
        snapshot: Any,
        orders: Any,
    ) -> None:
        with self.store.connection() as connection:
            connection.execute(
                "INSERT INTO strategies(strategy_id, account_fingerprint, status, contract_json, "
                "snapshot_json, orders_json, results_json, preview_hash, prepared_json, created_at, updated_at) "
                "VALUES (?, ?, 'APPLIED', ?, ?, ?, '[]', '', ?, 10, 11)",
                (
                    strategy_id,
                    ACCOUNT,
                    encode_json({"instrumentId": instrument}),
                    encode_json(snapshot),
                    encode_json(orders),
                    None if prepared is None else encode_json(prepared),
                ),
            )

    def test_legacy_migration_narrows_only_proven_scope_and_preserves_rows(self) -> None:
        order = {"clientOrderId": "legacy-long-1", "side": "long", "contracts": "2"}
        stored_order = {**order, "status": "accepted"}
        self._insert_strategy(
            "legacy-hedge-long",
            INSTRUMENT,
            prepared={"_positionMode": "long_short_mode", "orders": [order]},
            snapshot={"orders": [order]},
            orders=[stored_order],
        )
        self._insert_strategy(
            "legacy-malformed",
            "ETH-USDT-SWAP",
            prepared={"_positionMode": "long_short_mode", "orders": [order]},
            snapshot={"orders": [order]},
            orders=[{**stored_order, "clientOrderId": "different-order"}],
        )
        old_rows = [
            (ACCOUNT, INSTRUMENT, "legacy-hedge-long", 21.0),
            (ACCOUNT, "ETH-USDT-SWAP", "legacy-malformed", 22.0),
            (ACCOUNT, "DOGE-USDT-SWAP", "orphan-reservation", 23.0),
        ]
        self._create_legacy_reservations(old_rows)
        self.store._initialized = False

        self.store.initialize()

        with self.store.connection() as connection:
            migrated = connection.execute(
                "SELECT account_fingerprint, instrument_id, strategy_id, position_mode, side_scope, created_at "
                "FROM strategy_reservations ORDER BY strategy_id"
            ).fetchall()
            self.assertEqual(
                [tuple(row) for row in migrated],
                [
                    (ACCOUNT, INSTRUMENT, "legacy-hedge-long", "long_short_mode", "long", 21.0),
                    (ACCOUNT, "ETH-USDT-SWAP", "legacy-malformed", "unknown", "all", 22.0),
                    (ACCOUNT, "DOGE-USDT-SWAP", "orphan-reservation", "unknown", "all", 23.0),
                ],
            )

        SQLiteStore(str(self.db_path)).initialize()
        with self.store.connection() as connection:
            count = connection.execute("SELECT COUNT(*) FROM strategy_reservations").fetchone()[0]
        self.assertEqual(count, len(old_rows))

    def test_failed_migration_rolls_back_legacy_table_and_rows(self) -> None:
        self._create_legacy_reservations([(ACCOUNT, INSTRUMENT, "legacy-row", 31.0)])
        self.store._initialized = False
        real_connect = sqlite3.connect
        copied_rows: list[str] = []

        def connect_with_migration_failure(*args: Any, **kwargs: Any) -> sqlite3.Connection:
            connection = real_connect(*args, **kwargs)

            def authorize(action: int, arg1: str | None, arg2: str | None, _db: str | None, _source: str | None) -> int:
                if action == sqlite3.SQLITE_INSERT and arg1 == "strategy_reservations_scoped_migration":
                    copied_rows.append(arg1)
                if action == sqlite3.SQLITE_DROP_TABLE and arg1 == "strategy_reservations":
                    return sqlite3.SQLITE_DENY
                return sqlite3.SQLITE_OK

            connection.set_authorizer(authorize)
            return connection

        with patch("backend.store.sqlite3.connect", side_effect=connect_with_migration_failure):
            with self.assertRaises(sqlite3.DatabaseError):
                self.store.initialize()

        with sqlite3.connect(self.db_path) as connection:
            columns = {row[1] for row in connection.execute("PRAGMA table_info(strategy_reservations)")}
            row = connection.execute(
                "SELECT account_fingerprint, instrument_id, strategy_id, created_at "
                "FROM strategy_reservations"
            ).fetchone()
            migration_table = connection.execute(
                "SELECT 1 FROM sqlite_master WHERE type='table' "
                "AND name='strategy_reservations_scoped_migration'"
            ).fetchone()
        self.assertEqual(copied_rows, ["strategy_reservations_scoped_migration"])
        self.assertEqual(columns, {"account_fingerprint", "instrument_id", "strategy_id", "created_at"})
        self.assertEqual(row, (ACCOUNT, INSTRUMENT, "legacy-row", 31.0))
        self.assertIsNone(migration_table)


if __name__ == "__main__":
    unittest.main()
