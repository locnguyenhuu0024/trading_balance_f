from __future__ import annotations

import sqlite3
import json
import multiprocessing
import os
import secrets
import tempfile
import unittest
from contextlib import closing
from pathlib import Path
from types import SimpleNamespace
from typing import Any
from unittest.mock import patch

from backend.service import APIError
from backend.store import SQLiteStore, encode_json
from backend.security import token_digest
from backend.store import SQLiteIdentityStore
from backend.strategy import StrategyService
from backend.strategy_worker import OwnedStrategyOrderWorker
from backend.strategy_queue import OwnedStrategyQueueLedger, initial_results, new_queue
from backend.strategy_scope import (
    OwnedStrategyScope,
    UNKNOWN_SCOPE,
    extract_persisted_scope,
    owned_strategy_fingerprint,
    reservation_scope,
    scope_for_sides,
    scoped_pending_rows,
    scoped_position_rows,
    scopes_overlap,
)


INSTRUMENT = "BTC-USDT-SWAP"
ACCOUNT = "scope-test-account"


def _postgres_owned_api_claim_worker(dsn: str, barrier: object, output: object, now: float) -> None:
    try:
        from backend.postgres_store import PostgresIdentityStore

        store = PostgresIdentityStore(dsn)
        store.initialize()
        scope = OwnedStrategyScope(
            user_id="owner-one", connection_id="connection-one",
            account_fingerprint="owner-scoped-fingerprint", remote_identity_digest="remote-digest",
            credential_version=2, permission_version=3, environment="demo",
        )
        owner = _OwnedStrategyOwnerStub(store, scope.account_fingerprint)
        service = StrategyService(owner, strategy_scope=scope)
        strategy = service._load_row("api-prepared-strategy")
        barrier.wait(timeout=30)
        try:
            result = service._claim_execution("api-prepared-strategy", strategy, "api-confirmation")
            output.put(("api", "claimed" if result is not None else "declined", None))
        except APIError as error:
            output.put(("api", "blocked", error.code))
    except BaseException as error:
        output.put(("api-error", type(error).__name__))


def _postgres_owned_worker_claim_worker(dsn: str, barrier: object, output: object, now: float) -> None:
    try:
        from backend.postgres_store import PostgresIdentityStore

        store = PostgresIdentityStore(dsn)
        worker = OwnedStrategyOrderWorker(
            SimpleNamespace(multiuser_enabled=True, multiuser_trade_enabled=True),
            store=store, connections=SimpleNamespace(store=store), clock=lambda: now,
            owner_id="pg-owned-worker", lease_seconds=30,
        )
        candidates = worker._candidate_ids(now)
        barrier.wait(timeout=30)
        if not candidates:
            output.put(("worker", "no_candidate", None))
            return
        job = worker._claim_job(*candidates[0])
        output.put(("worker", "claimed" if job is not None else "declined", None if job is None else job["fence"]))
    except BaseException as error:
        output.put(("worker-error", type(error).__name__))


def _seed_owned_claim_race_fixture(connection: Any, scope: OwnedStrategyScope, now: float) -> None:
    worker_orders = [{
        "clientOrderId": "worker-order-1", "side": "long", "contracts": "1", "leverage": 3,
    }]
    worker_prepared = {
        "submissionMode": "sequential", "_positionMode": "net_mode",
        "orders": worker_orders, "previewHash": "worker-preview",
    }
    worker_queue = new_queue(enqueued_at=now - 10, total_count=1, preview_hash="worker-preview")
    api_orders = [{
        "clientOrderId": "api-order-1", "side": "short", "contracts": "1", "leverage": 3,
    }]
    api_prepared = {
        "submissionMode": "sequential", "_positionMode": "net_mode",
        "orders": api_orders, "previewHash": "api-preview",
    }
    api_contract = {
        "instrumentId": INSTRUMENT,
        "interval": "12Hutc",
        "selectedLevels": [{"side": "short", "price": "61000"}],
        "entryBySide": {"short": "61000"},
        "totalMargin": "60",
        "leverage": {"short": 3},
        "sidePercent": {"short": "100"},
        "allocation": "equal",
    }

    connection.execute(
        "INSERT INTO multiuser_connection_leases(user_id, connection_id, lease_owner, fence, "
        "lease_until, operation_id, updated_at) VALUES (?, ?, NULL, 4, ?, NULL, ?)",
        (scope.user_id, scope.connection_id, now - 1, now - 10),
    )
    connection.execute(
        "INSERT INTO multiuser_strategies(user_id, connection_id, strategy_id, status, "
        "account_fingerprint, contract_json, snapshot_json, orders_json, results_json, "
        "prepared_json, queue_json, preview_hash, attempt_started, submission_mode, "
        "execution_id, execution_lease_until, lease_owner, lease_fence, lease_until, "
        "credential_version, permission_version, created_at, updated_at) "
        "VALUES (?, ?, 'worker-queued-job', 'APPLYING', ?, ?, ?, ?, ?, ?, ?, ?, 1, 'sequential', "
        "'expired-worker', ?, 'expired-worker', 4, ?, 2, 3, ?, ?)",
        (scope.user_id, scope.connection_id, scope.account_fingerprint,
         encode_json({"instrumentId": INSTRUMENT}), encode_json({"_positionMode": "net_mode"}),
         encode_json(worker_orders), encode_json(initial_results(worker_orders)),
         encode_json(worker_prepared), encode_json(worker_queue), "worker-preview",
         now - 1, now - 1, now - 100, now - 10),
    )
    connection.execute(
        "INSERT INTO multiuser_strategy_claims(user_id, connection_id, strategy_id, lease_owner, "
        "fence, lease_until, updated_at) VALUES (?, ?, 'worker-queued-job', NULL, 4, ?, ?)",
        (scope.user_id, scope.connection_id, now - 1, now - 10),
    )
    connection.execute(
        "INSERT INTO multiuser_strategies(user_id, connection_id, strategy_id, status, "
        "account_fingerprint, contract_json, snapshot_json, orders_json, results_json, preview_hash, "
        "confirmation_hash, prepared_expires_at, prepared_json, attempt_started, submission_mode, "
        "credential_version, permission_version, created_at, updated_at) "
        "VALUES (?, ?, 'api-prepared-strategy', 'PREPARED', ?, ?, ?, ?, '[]', ?, ?, ?, ?, 0, "
        "'sequential', 2, 3, ?, ?)",
        (scope.user_id, scope.connection_id, scope.account_fingerprint,
         encode_json(api_contract),
         encode_json({"_positionMode": "net_mode", "orders": api_orders}),
         encode_json(api_orders), "api-preview", token_digest("api-confirmation", b"S" * 32),
         now + 60, encode_json(api_prepared), now - 5, now - 5),
    )


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

        with closing(sqlite3.connect(self.db_path)) as connection, connection:
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


class _OwnedStrategyOwnerStub:
    def __init__(self, store: SQLiteIdentityStore, fingerprint: str) -> None:
        self.store = store
        self.clock = lambda: 1_800_000_000.0
        self.settings = SimpleNamespace(session_signing_key=b"S" * 32)
        self.account_calls = 0
        self.okx = SimpleNamespace(account_config=self._account_config)
        self._fingerprint = fingerprint

    def _account_config(self) -> dict[str, Any]:
        self.account_calls += 1
        raise AssertionError("owner lookup must precede private exchange calls")

    def _account_fingerprint(self, uid: Any) -> str:
        self.account_calls += 1
        raise AssertionError("unexpected account fingerprint lookup")

    def _valid_account_fingerprint(self, value: Any) -> bool:
        return value == self._fingerprint

    def assert_strategy_authority(self, connection: Any) -> None:
        row = connection.execute(
            "SELECT status, credential_version, permission_version, remote_identity_digest "
            "FROM exchange_connections WHERE user_id=? AND connection_id=?",
            ("owner-one", "connection-one"),
        ).fetchone()
        if (
            row is None or row["status"] != "ACTIVE"
            or int(row["credential_version"]) != 2 or int(row["permission_version"]) != 3
            or row["remote_identity_digest"] != "remote-digest"
        ):
            raise APIError(409, "connection_version_changed", "The owned connection changed.")


class OwnedStrategyLookupTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory(prefix="owned-strategy-lookup-")
        self.store = SQLiteIdentityStore(str(Path(self.temp.name) / "identity.sqlite3"))
        self.store.initialize()
        self.scope = OwnedStrategyScope(
            user_id="owner-one", connection_id="connection-one",
            account_fingerprint="owner-scoped-fingerprint", remote_identity_digest="remote-digest",
            credential_version=2, permission_version=3, environment="demo",
        )
        self.owner = _OwnedStrategyOwnerStub(self.store, self.scope.account_fingerprint)
        self.service = StrategyService(self.owner, strategy_scope=self.scope)

    def tearDown(self) -> None:
        self.temp.cleanup()

    def _seed_owned_connection(self) -> None:
        with self.store.transaction() as connection:
            connection.execute(
                "INSERT INTO users(user_id, username, username_normalized, password_hash, status, created_at) "
                "VALUES (?, ?, ?, ?, 'ACTIVE', ?)",
                (self.scope.user_id, "Owner", "owner", "password-hash", 100.0),
            )
            connection.execute(
                "INSERT INTO exchange_connections(user_id, connection_id, exchange, environment, region, "
                "product_capabilities_json, status, remote_identity_digest, credential_version, permission_version, "
                "created_at, updated_at) VALUES (?, ?, 'OKX', 'demo', 'global', '[\"read\",\"trade\"]', "
                "'ACTIVE', ?, 2, 3, 100.0, 100.0)",
                (self.scope.user_id, self.scope.connection_id, self.scope.remote_identity_digest),
            )

    def test_owned_api_claim_race_fixture_reaches_busy_guard(self) -> None:
        self._seed_owned_connection()
        now = self.service.clock()
        with self.store.transaction() as connection:
            _seed_owned_claim_race_fixture(connection, self.scope, now)

        strategy = self.service._load_row("api-prepared-strategy")
        with self.assertRaises(APIError) as raised:
            self.service._claim_execution("api-prepared-strategy", strategy, "api-confirmation")

        self.assertEqual(raised.exception.code, "connection_busy")
        with self.store.connection() as connection:
            lease = connection.execute(
                "SELECT lease_owner, fence, lease_until, operation_id FROM multiuser_connection_leases "
                "WHERE user_id=? AND connection_id=?",
                (self.scope.user_id, self.scope.connection_id),
            ).fetchone()
            api_strategy = connection.execute(
                "SELECT status, confirmation_hash, attempt_started FROM multiuser_strategies "
                "WHERE user_id=? AND connection_id=? AND strategy_id='api-prepared-strategy'",
                (self.scope.user_id, self.scope.connection_id),
            ).fetchone()
        self.assertEqual(tuple(lease), (None, 4, now - 1, None))
        self.assertEqual(api_strategy["status"], "PREPARED")
        self.assertEqual(api_strategy["confirmation_hash"], token_digest("api-confirmation", b"S" * 32))
        self.assertEqual(api_strategy["attempt_started"], 0)

    def test_owned_api_claim_rejects_malformed_race_fixture_before_busy_guard(self) -> None:
        self._seed_owned_connection()
        now = self.service.clock()
        with self.store.transaction() as connection:
            _seed_owned_claim_race_fixture(connection, self.scope, now)
            connection.execute(
                "UPDATE multiuser_strategies SET contract_json=? WHERE user_id=? AND connection_id=? "
                "AND strategy_id='api-prepared-strategy'",
                (encode_json({
                    "instrumentId": INSTRUMENT, "interval": "12Hutc", "selectedLevels": [],
                }), self.scope.user_id, self.scope.connection_id),
            )

        strategy = self.service._load_row("api-prepared-strategy")
        with self.assertRaises(APIError) as raised:
            self.service._claim_execution("api-prepared-strategy", strategy, "api-confirmation")

        self.assertEqual(raised.exception.code, "invalid_strategy")
        self.assertEqual(raised.exception.details["reason"], "invalid_order_count")
        with self.store.connection() as connection:
            lease = connection.execute(
                "SELECT lease_owner, fence, lease_until, operation_id FROM multiuser_connection_leases "
                "WHERE user_id=? AND connection_id=?",
                (self.scope.user_id, self.scope.connection_id),
            ).fetchone()
            api_strategy = connection.execute(
                "SELECT status, confirmation_hash, attempt_started FROM multiuser_strategies "
                "WHERE user_id=? AND connection_id=? AND strategy_id='api-prepared-strategy'",
                (self.scope.user_id, self.scope.connection_id),
            ).fetchone()
        self.assertEqual(tuple(lease), (None, 4, now - 1, None))
        self.assertEqual(api_strategy["status"], "PREPARED")
        self.assertEqual(api_strategy["confirmation_hash"], token_digest("api-confirmation", b"S" * 32))
        self.assertEqual(api_strategy["attempt_started"], 0)

    def test_missing_owned_id_returns_404_before_upstream_call(self) -> None:
        with self.assertRaises(APIError) as raised:
            self.service._current_strategy("guessed-strategy-id")
        self.assertEqual(raised.exception.status, 404)
        self.assertEqual(self.owner.account_calls, 0)

    def test_historical_result_survives_connection_generation_change(self) -> None:
        with self.store.transaction() as connection:
            connection.execute(
                "INSERT INTO users(user_id, username, username_normalized, password_hash, status, created_at) "
                "VALUES (?, ?, ?, ?, 'ACTIVE', ?)",
                (self.scope.user_id, "Owner", "owner", "password-hash", 100.0),
            )
            connection.execute(
                "INSERT INTO exchange_connections(user_id, connection_id, exchange, environment, region, "
                "status, remote_identity_digest, created_at, updated_at) VALUES (?, ?, 'OKX', 'demo', 'global', "
                "'ACTIVE', ?, 100.0, 100.0)",
                (self.scope.user_id, self.scope.connection_id, self.scope.remote_identity_digest),
            )
            connection.execute(
                "INSERT INTO multiuser_strategies(user_id, connection_id, strategy_id, status, account_fingerprint, "
                "credential_version, permission_version, contract_json, snapshot_json, created_at, updated_at) "
                "VALUES (?, ?, 'historical-job-1', 'UNKNOWN', ?, 1, 1, ?, ?, 120.0, 130.0)",
                (
                    self.scope.user_id, self.scope.connection_id, self.scope.account_fingerprint,
                    encode_json({"instrumentId": INSTRUMENT, "interval": "1Dutc"}),
                    encode_json({"sides": [], "totalMargin": "0"}),
                ),
            )

        result = self.service._result_owned("historical-job-1")

        self.assertEqual(result["id"], "historical-job-1")
        self.assertEqual(result["status"], "UNKNOWN")
        self.assertEqual(self.owner.account_calls, 0)

    def test_owned_order_scan_upsert_preserves_success_time_on_later_failure(self) -> None:
        with self.store.transaction() as connection:
            connection.execute(
                "INSERT INTO users(user_id, username, username_normalized, password_hash, status, created_at) "
                "VALUES (?, ?, ?, ?, 'ACTIVE', ?)",
                (self.scope.user_id, "Owner", "owner", "password-hash", 100.0),
            )
            connection.execute(
                "INSERT INTO exchange_connections(user_id, connection_id, exchange, environment, region, "
                "status, remote_identity_digest, created_at, updated_at) VALUES (?, ?, 'OKX', 'demo', 'global', "
                "'ACTIVE', ?, 100.0, 100.0)",
                (self.scope.user_id, self.scope.connection_id, self.scope.remote_identity_digest),
            )
            connection.execute(
                "INSERT INTO multiuser_strategies(user_id, connection_id, strategy_id, status, account_fingerprint, "
                "created_at, updated_at) VALUES (?, ?, 'scan-strategy-1', 'UNKNOWN', ?, 120.0, 130.0)",
                (self.scope.user_id, self.scope.connection_id, self.scope.account_fingerprint),
            )

        self.service._record_api_order_scan("scan-strategy-1", None)
        self.service.clock = lambda: 1_800_000_005.0
        self.service._record_api_order_scan("scan-strategy-1", "read_failed")

        with self.store.connection() as connection:
            row = connection.execute(
                "SELECT user_id, connection_id, strategy_id, last_attempt_at, last_success_at, last_error, "
                "next_scan_at, consecutive_errors FROM multiuser_strategy_sync_state WHERE strategy_id=?",
                ("scan-strategy-1",),
            ).fetchone()
        self.assertEqual(
            tuple(row),
            (self.scope.user_id, self.scope.connection_id, "scan-strategy-1",
             1_800_000_005.0, 1_800_000_000.0, "read_failed", 1_800_000_005.0, 1),
        )

    def test_legacy_order_scan_upsert_success_and_failure(self) -> None:
        legacy_path = Path(self.temp.name) / "legacy.sqlite3"
        legacy = SQLiteStore(str(legacy_path))
        legacy.initialize()
        owner = SimpleNamespace(
            store=legacy,
            clock=lambda: 1_800_000_000.0,
            settings=SimpleNamespace(session_signing_key=b"S" * 32),
            okx=SimpleNamespace(),
        )
        service = StrategyService(owner)

        service._record_api_order_scan("legacy-scan-1", None)
        owner.clock = lambda: 1_800_000_005.0
        service.clock = owner.clock
        service._record_api_order_scan("legacy-scan-1", "read_failed")

        with legacy.connection() as connection:
            row = connection.execute(
                "SELECT strategy_id, last_attempt_at, last_success_at, last_error, next_scan_at, consecutive_errors "
                "FROM strategy_sync_state WHERE strategy_id=?",
                ("legacy-scan-1",),
            ).fetchone()
        self.assertEqual(
            tuple(row),
            ("legacy-scan-1", 1_800_000_005.0, 1_800_000_000.0, "read_failed", 1_800_000_005.0, 1),
        )

    def _seed_applying_strategy(self, *, lease_until: float = 1_800_000_030.0) -> None:
        orders = [
            {"clientOrderId": "target-long-0001", "side": "long", "contracts": "2", "limitPrice": "100"},
            {"clientOrderId": "target-short-01", "side": "short", "contracts": "3", "limitPrice": "101"},
        ]
        with self.store.transaction() as connection:
            connection.execute(
                "INSERT INTO users(user_id, username, username_normalized, password_hash, status, created_at) "
                "VALUES (?, ?, ?, ?, 'ACTIVE', ?) ON CONFLICT(user_id) DO NOTHING",
                (self.scope.user_id, "Owner", "owner", "password-hash", 100.0),
            )
            connection.execute(
                "INSERT INTO exchange_connections(user_id, connection_id, exchange, environment, region, "
                "product_capabilities_json, status, remote_identity_digest, credential_version, permission_version, "
                "created_at, updated_at) VALUES (?, ?, 'OKX', 'demo', 'global', '[\"read\",\"trade\"]', "
                "'ACTIVE', ?, 2, 3, 100.0, 100.0) ON CONFLICT(user_id, connection_id) DO NOTHING",
                (self.scope.user_id, self.scope.connection_id, self.scope.remote_identity_digest),
            )
            connection.execute(
                "INSERT INTO multiuser_connection_leases(user_id, connection_id, lease_owner, fence, lease_until, "
                "operation_id, updated_at) VALUES (?, ?, 'execution-1', 4, ?, 'batch-strategy-1', ?)",
                (self.scope.user_id, self.scope.connection_id, lease_until, 1_800_000_000.0),
            )
            connection.execute(
                "INSERT INTO multiuser_strategies(user_id, connection_id, strategy_id, status, account_fingerprint, "
                "contract_json, orders_json, execution_id, execution_lease_until, lease_fence, lease_owner, lease_until, "
                "attempt_started, created_at, updated_at) VALUES (?, ?, 'batch-strategy-1', 'APPLYING', ?, ?, ?, "
                "'execution-1', ?, 4, 'execution-1', ?, 1, ?, ?)",
                (self.scope.user_id, self.scope.connection_id, self.scope.account_fingerprint,
                 encode_json({"instrumentId": INSTRUMENT}), encode_json(orders), lease_until, lease_until,
                 1_800_000_000.0, 1_800_000_000.0),
            )
            connection.execute(
                "INSERT INTO multiuser_strategy_claims(user_id, connection_id, strategy_id, lease_owner, fence, "
                "lease_until, updated_at) VALUES (?, ?, 'batch-strategy-1', 'execution-1', 4, ?, ?)",
                (self.scope.user_id, self.scope.connection_id, lease_until, 1_800_000_000.0),
            )

    def test_expired_connection_fence_denies_batch_marker_before_any_target_event(self) -> None:
        self._seed_applying_strategy(lease_until=1_799_999_999.0)
        orders = [
            {"clientOrderId": "target-long-0001", "side": "long", "contracts": "2"},
            {"clientOrderId": "target-short-01", "side": "short", "contracts": "3"},
        ]

        self.assertFalse(self.service._mark_batch_attempted("batch-strategy-1", "execution-1", orders))

        with self.store.connection() as connection:
            row = connection.execute(
                "SELECT status, batch_attempted, order_placement_attempted, pre_send_at "
                "FROM multiuser_strategies WHERE user_id=? AND connection_id=? AND strategy_id=?",
                (self.scope.user_id, self.scope.connection_id, "batch-strategy-1"),
            ).fetchone()
            events = connection.execute(
                "SELECT COUNT(*) FROM multiuser_strategy_events WHERE user_id=? AND connection_id=? "
                "AND strategy_id=? AND event_type='strategy_target_pre_send'",
                (self.scope.user_id, self.scope.connection_id, "batch-strategy-1"),
            ).fetchone()[0]
        self.assertEqual(tuple(row), ("APPLYING", 0, 0, None))
        self.assertEqual(events, 0)

    def test_live_owned_fence_persists_each_target_before_batch_and_finish_releases_lease(self) -> None:
        self._seed_applying_strategy()
        orders = [
            {"clientOrderId": "target-long-0001", "side": "long", "contracts": "2"},
            {"clientOrderId": "target-short-01", "side": "short", "contracts": "3"},
        ]

        self.assertTrue(self.service._mark_batch_attempted("batch-strategy-1", "execution-1", orders))
        self.service._finish(
            "batch-strategy-1", "execution-1", "UNKNOWN",
            [{**order, "status": "unknown"} for order in orders], "batch_unknown", [],
        )

        with self.store.connection() as connection:
            strategy = connection.execute(
                "SELECT status, batch_attempted, order_placement_attempted, pre_send_at, execution_id "
                "FROM multiuser_strategies WHERE user_id=? AND connection_id=? AND strategy_id=?",
                (self.scope.user_id, self.scope.connection_id, "batch-strategy-1"),
            ).fetchone()
            events = connection.execute(
                "SELECT payload_json FROM multiuser_strategy_events WHERE user_id=? AND connection_id=? "
                "AND strategy_id=? AND event_type='strategy_target_pre_send' ORDER BY created_at, event_id",
                (self.scope.user_id, self.scope.connection_id, "batch-strategy-1"),
            ).fetchall()
            lease = connection.execute(
                "SELECT lease_owner, lease_until, fence FROM multiuser_connection_leases "
                "WHERE user_id=? AND connection_id=?",
                (self.scope.user_id, self.scope.connection_id),
            ).fetchone()
        self.assertEqual(tuple(strategy[:3]), ("UNKNOWN", 1, 1))
        self.assertIsNotNone(strategy["pre_send_at"])
        self.assertIsNone(strategy["execution_id"])
        self.assertEqual(len(events), 2)
        self.assertEqual(sorted(json.loads(row["payload_json"])["index"] for row in events), [0, 1])
        self.assertEqual((lease["lease_owner"], lease["lease_until"], lease["fence"]), (None, None, 4))

    def test_owned_finish_persists_post_send_evidence_after_revoke_and_lease_expiry(self) -> None:
        self._seed_applying_strategy()
        orders = [
            {"clientOrderId": "target-long-0001", "side": "long", "contracts": "2"},
            {"clientOrderId": "target-short-01", "side": "short", "contracts": "3"},
        ]
        self.assertTrue(self.service._mark_batch_attempted("batch-strategy-1", "execution-1", orders))
        with self.store.transaction() as connection:
            connection.execute(
                "UPDATE exchange_connections SET status='REVOKED', credential_version=3, "
                "permission_version=4 WHERE user_id=? AND connection_id=?",
                (self.scope.user_id, self.scope.connection_id),
            )
            connection.execute(
                "UPDATE multiuser_connection_leases SET lease_until=? WHERE user_id=? AND connection_id=?",
                (1_799_999_999.0, self.scope.user_id, self.scope.connection_id),
            )

        accepted = [{**order, "status": "accepted", "exchangeOrderId": f"exchange-{index}"}
                    for index, order in enumerate(orders)]
        self.service._finish(
            "batch-strategy-1", "execution-1", "APPLIED", accepted, None, [],
        )

        with self.store.connection() as connection:
            row = connection.execute(
                "SELECT status, results_json, execution_id FROM multiuser_strategies "
                "WHERE user_id=? AND connection_id=? AND strategy_id=?",
                (self.scope.user_id, self.scope.connection_id, "batch-strategy-1"),
            ).fetchone()
            lease = connection.execute(
                "SELECT lease_owner, fence FROM multiuser_connection_leases "
                "WHERE user_id=? AND connection_id=?",
                (self.scope.user_id, self.scope.connection_id),
            ).fetchone()
        self.assertEqual(row["status"], "APPLIED")
        self.assertEqual(json.loads(row["results_json"]), accepted)
        self.assertIsNone(row["execution_id"])
        self.assertEqual((lease["lease_owner"], lease["fence"]), (None, 4))

    def test_owned_finish_refuses_to_overwrite_a_newer_fence(self) -> None:
        self._seed_applying_strategy()
        orders = [
            {"clientOrderId": "target-long-0001", "side": "long", "contracts": "2"},
        ]
        self.assertTrue(self.service._mark_batch_attempted("batch-strategy-1", "execution-1", orders))
        with self.store.transaction() as connection:
            connection.execute(
                "UPDATE multiuser_connection_leases SET lease_owner='worker-2', fence=5, lease_until=? "
                "WHERE user_id=? AND connection_id=?",
                (1_800_000_030.0, self.scope.user_id, self.scope.connection_id),
            )

        self.service._finish(
            "batch-strategy-1", "execution-1", "APPLIED",
            [{**orders[0], "status": "accepted", "exchangeOrderId": "exchange-1"}], None, [],
        )

        with self.store.connection() as connection:
            row = connection.execute(
                "SELECT status, results_json, execution_id FROM multiuser_strategies "
                "WHERE user_id=? AND connection_id=? AND strategy_id=?",
                (self.scope.user_id, self.scope.connection_id, "batch-strategy-1"),
            ).fetchone()
        self.assertEqual(row["status"], "APPLYING")
        self.assertEqual(json.loads(row["results_json"]), [])
        self.assertEqual(row["execution_id"], "execution-1")

    def test_revoke_after_leverage_ack_persists_ack_and_unsent_order_tail(self) -> None:
        self._seed_applying_strategy()
        orders = [
            {"clientOrderId": "target-long-0001", "side": "long", "contracts": "2"},
            {"clientOrderId": "target-short-01", "side": "short", "contracts": "3"},
        ]

        self.assertTrue(self.service._renew_execution(
            "batch-strategy-1", "execution-1",
            target={"kind": "leverage", "side": "long", "instrumentId": INSTRUMENT},
        ))
        leverage_results = [{"side": "long", "status": "applied"}]
        with self.store.transaction() as connection:
            connection.execute(
                "UPDATE exchange_connections SET status='REVOKED', credential_version=3, "
                "permission_version=4 WHERE user_id=? AND connection_id=?",
                (self.scope.user_id, self.scope.connection_id),
            )

        self.assertFalse(self.service._mark_batch_attempted(
            "batch-strategy-1", "execution-1", orders,
        ))
        unsent = [{**order, "status": "not_submitted"} for order in orders]
        self.service._finish(
            "batch-strategy-1", "execution-1", "PARTIAL", unsent,
            "connection_version_changed", leverage_results,
        )

        with self.store.connection() as connection:
            row = connection.execute(
                "SELECT status, results_json, leverage_results_json, batch_attempted, "
                "order_placement_attempted, execution_id FROM multiuser_strategies "
                "WHERE user_id=? AND connection_id=? AND strategy_id=?",
                (self.scope.user_id, self.scope.connection_id, "batch-strategy-1"),
            ).fetchone()
            events = connection.execute(
                "SELECT payload_json FROM multiuser_strategy_events WHERE user_id=? AND connection_id=? "
                "AND strategy_id=? AND event_type='strategy_target_pre_send'",
                (self.scope.user_id, self.scope.connection_id, "batch-strategy-1"),
            ).fetchall()
        self.assertEqual(row["status"], "PARTIAL")
        self.assertEqual(json.loads(row["results_json"]), unsent)
        self.assertEqual(json.loads(row["leverage_results_json"]), leverage_results)
        self.assertEqual((row["batch_attempted"], row["order_placement_attempted"]), (0, 0))
        self.assertIsNone(row["execution_id"])
        self.assertEqual(len(events), 1)
        self.assertEqual(json.loads(events[0]["payload_json"])["kind"], "leverage")

    def test_unknown_leverage_attempt_keeps_reservation_and_blocks_new_writer(self) -> None:
        self._seed_applying_strategy()
        orders = [
            {"clientOrderId": "target-long-0001", "side": "long", "contracts": "2"},
            {"clientOrderId": "target-short-01", "side": "short", "contracts": "3"},
        ]
        with self.store.transaction() as connection:
            connection.execute(
                "UPDATE multiuser_strategies SET pre_send_at=? WHERE user_id=? AND connection_id=? "
                "AND strategy_id=?",
                (1_800_000_000.0, self.scope.user_id, self.scope.connection_id, "batch-strategy-1"),
            )
            connection.execute(
                "INSERT INTO multiuser_strategy_reservations(user_id, connection_id, instrument_id, "
                "strategy_id, position_mode, side_scope, created_at) VALUES (?, ?, ?, ?, 'net_mode', 'all', ?)",
                (self.scope.user_id, self.scope.connection_id, INSTRUMENT, "batch-strategy-1", 1_800_000_000.0),
            )

        self.service._finish(
            "batch-strategy-1", "execution-1", "UNKNOWN",
            [{**order, "status": "not_submitted"} for order in orders],
            "leverage_unknown", [{"side": "long", "status": "unknown"}],
        )

        current = self.service._load_row("batch-strategy-1")
        self.assertFalse(self.service._can_delete_hint(current))
        self.assertFalse(self.service._can_replace_hint(current))
        with self.store.transaction() as connection:
            self.assertTrue(self.service._owned_connection_busy(
                connection, strategy_id="new-strategy-1", now=self.service.clock()
            ))
            self.assertIsNone(self.service._claim_owned_connection_lease(
                connection,
                strategy_id="new-strategy-1",
                lease_owner="execution-2",
                now=self.service.clock(),
            ))
            reservation_count = connection.execute(
                "SELECT COUNT(*) FROM multiuser_strategy_reservations WHERE user_id=? AND connection_id=?",
                (self.scope.user_id, self.scope.connection_id),
            ).fetchone()[0]
            events = connection.execute(
                "SELECT COUNT(*) FROM multiuser_strategy_events WHERE user_id=? AND connection_id=? "
                "AND strategy_id=? AND event_type='strategy_execution_finished'",
                (self.scope.user_id, self.scope.connection_id, "batch-strategy-1"),
            ).fetchone()[0]
        self.assertEqual(reservation_count, 1)
        self.assertEqual(events, 1)

    def _seed_owned_queue(self, *, lease_until: float = 1_800_000_030.0) -> dict[str, Any]:
        self._seed_applying_strategy(lease_until=lease_until)
        orders = [
            {"clientOrderId": "queue-target-01", "side": "long", "contracts": "2", "leverage": 3},
        ]
        queue = new_queue(enqueued_at=1_800_000_000.0, total_count=1, preview_hash="queue-preview-hash")
        results = initial_results(orders)
        prepared = {
            "submissionMode": "sequential", "_positionMode": "net_mode", "orders": orders,
        }
        snapshot = {"_positionMode": "net_mode", "orders": orders}
        with self.store.transaction() as connection:
            connection.execute(
                "UPDATE multiuser_connection_leases SET lease_owner='worker-1', operation_id=?, lease_until=? "
                "WHERE user_id=? AND connection_id=?",
                ("batch-strategy-1", lease_until, self.scope.user_id, self.scope.connection_id),
            )
            connection.execute(
                "UPDATE multiuser_strategy_claims SET lease_owner='worker-1', lease_until=? "
                "WHERE user_id=? AND connection_id=? AND strategy_id=?",
                (lease_until, self.scope.user_id, self.scope.connection_id, "batch-strategy-1"),
            )
            connection.execute(
                "UPDATE multiuser_strategies SET lease_owner='worker-1', execution_id=NULL, "
                "queue_json=?, prepared_json=?, snapshot_json=?, orders_json=?, results_json=?, "
                "submission_mode='sequential', order_placement_attempted=0, updated_at=? "
                "WHERE user_id=? AND connection_id=? AND strategy_id=?",
                (encode_json(queue), encode_json(prepared), encode_json(snapshot), encode_json(orders),
                 encode_json(results), 1_800_000_000.0, self.scope.user_id, self.scope.connection_id,
                 "batch-strategy-1"),
            )
            row = connection.execute(
                "SELECT * FROM multiuser_strategies WHERE user_id=? AND connection_id=? AND strategy_id=?",
                (self.scope.user_id, self.scope.connection_id, "batch-strategy-1"),
            ).fetchone()
        return self.service._decode_row(row)

    def _seed_unmarked_owned_batch(self, *, unresolved_leverage: bool) -> None:
        self._seed_applying_strategy(lease_until=1_799_999_999.0)
        orders = [
            {"clientOrderId": "batch-target-01", "side": "long", "contracts": "2", "leverage": 3},
        ]
        prepared = {"submissionMode": "batch", "_positionMode": "net_mode", "orders": orders}
        with self.store.transaction() as connection:
            connection.execute(
                "UPDATE multiuser_strategies SET submission_mode='batch', queue_json=NULL, prepared_json=?, "
                "snapshot_json=?, orders_json=?, results_json='[]', batch_attempted=0, "
                "order_placement_attempted=0, execution_lease_until=?, pre_send_at=? "
                "WHERE user_id=? AND connection_id=? AND strategy_id=?",
                (encode_json(prepared), encode_json(prepared), encode_json(orders), 1_799_999_999.0,
                 1_800_000_000.0 if unresolved_leverage else None,
                 self.scope.user_id, self.scope.connection_id, "batch-strategy-1"),
            )
            if unresolved_leverage:
                connection.execute(
                    "INSERT INTO multiuser_strategy_reservations(user_id, connection_id, instrument_id, "
                    "strategy_id, position_mode, side_scope, created_at) VALUES (?, ?, ?, ?, 'net_mode', 'all', ?)",
                    (self.scope.user_id, self.scope.connection_id, INSTRUMENT, "batch-strategy-1", 1_800_000_000.0),
                )
                connection.execute(
                    "INSERT INTO multiuser_strategy_events(user_id, connection_id, strategy_id, event_id, "
                    "event_type, payload_json, created_at) VALUES (?, ?, ?, ?, 'strategy_target_pre_send', ?, ?)",
                    (self.scope.user_id, self.scope.connection_id, "batch-strategy-1", "leverage-marker",
                     encode_json({"kind": "leverage", "side": "long", "instrumentId": INSTRUMENT}),
                     1_800_000_000.0),
                )

    def _owned_worker(self) -> OwnedStrategyOrderWorker:
        return OwnedStrategyOrderWorker(
            SimpleNamespace(multiuser_enabled=True, multiuser_trade_enabled=True),
            store=self.store, connections=SimpleNamespace(store=self.store),
            clock=lambda: 1_800_000_000.0, owner_id="owned-worker", lease_seconds=30,
        )

    def test_owned_worker_queue_persists_markers_and_ack_with_advancing_transport(self) -> None:
        self._seed_owned_queue(lease_until=1_799_999_999.0)
        stable_fingerprint = owned_strategy_fingerprint(self.scope.user_id, self.scope.connection_id)
        with self.store.transaction() as connection:
            row = connection.execute(
                "SELECT prepared_json FROM multiuser_strategies WHERE user_id=? AND connection_id=? "
                "AND strategy_id=?",
                (self.scope.user_id, self.scope.connection_id, "batch-strategy-1"),
            ).fetchone()
            prepared = json.loads(row["prepared_json"])
            prepared["previewHash"] = "queue-preview-hash"
            prepared["orders"][0]["limitPrice"] = "100"
            connection.execute(
                "UPDATE multiuser_strategies SET account_fingerprint=?, credential_version=2, "
                "permission_version=3, prepared_json=? WHERE user_id=? AND connection_id=? AND strategy_id=?",
                (stable_fingerprint, encode_json(prepared), self.scope.user_id,
                 self.scope.connection_id, "batch-strategy-1"),
            )

        now = [1_800_000_000.0]
        monotonic = [0.0]

        class AdvancingClient:
            def __init__(self) -> None:
                self.calls: list[tuple[str, Any]] = []
                self.mutations: list[str] = []

            def _advance(self, name: str, payload: Any = None) -> None:
                now[0] += 1.0
                self.calls.append((name, payload))

            def account_config(self) -> dict[str, Any]:
                self._advance("account_config")
                return {"uid": "canonical-uid"}

            def positions(self, instrument_type: str) -> list[dict[str, Any]]:
                self._advance("positions", instrument_type)
                return []

            def pending_orders(self, instrument_id: str) -> list[dict[str, Any]]:
                self._advance("pending_orders", instrument_id)
                return []

            def set_leverage(self, payload: dict[str, Any]) -> dict[str, Any]:
                self._advance("set_leverage", dict(payload))
                self.mutations.append("set_leverage")
                return {"code": "0", "data": [{
                    "instId": payload["instId"], "lever": payload["lever"],
                    "mgnMode": payload["mgnMode"], "posSide": payload["posSide"], "sCode": "0",
                }]}

            def place_order(self, payload: dict[str, Any]) -> dict[str, Any]:
                self._advance("place_order", dict(payload))
                self.mutations.append("place_order")
                return {"code": "0", "data": [{
                    "clOrdId": payload["clOrdId"], "ordId": "exchange-order-queue-1", "sCode": "0",
                }]}

        client = AdvancingClient()
        context_requests: list[bool] = []
        context = SimpleNamespace(
            client=client, exchange="OKX", environment="demo", region="global",
            remote_identity_digest=self.scope.remote_identity_digest,
            credential_version=2, permission_version=3, capabilities=("read", "trade"),
        )

        def account_context(*_args: Any, recovery: bool = False) -> Any:
            context_requests.append(recovery)
            return context

        connections = SimpleNamespace(
            store=self.store,
            _identity_digest=lambda _exchange, _environment, _region, uid: (
                self.scope.remote_identity_digest if uid == "canonical-uid" else "wrong-identity"
            ),
            account_context_for_strategy_job=account_context,
        )
        worker = OwnedStrategyOrderWorker(
            SimpleNamespace(multiuser_enabled=True, multiuser_trade_enabled=True),
            store=self.store, connections=connections, clock=lambda: now[0], owner_id="owned-worker",
            lease_seconds=30, call_spacing_seconds=0,
            sleep=lambda seconds: (monotonic.__setitem__(0, monotonic[0] + seconds),
                                   now.__setitem__(0, now[0] + seconds)),
            monotonic=lambda: monotonic[0],
        )

        def deterministic_preflight(
            service: StrategyService, contract: dict[str, Any], account_fingerprint: str,
            *, resume: bool = False, strategy: dict[str, Any] | None = None,
        ) -> tuple[dict[str, Any], dict[str, Any]]:
            account = service.okx.account_config()
            self.assertEqual(service.owner._account_fingerprint(account["uid"]), account_fingerprint)
            service.okx.positions("SWAP")
            service.okx.pending_orders(contract["instrumentId"])
            return (
                {"uid": account["uid"], "posMode": "net_mode"},
                {"previewHash": "queue-preview-hash", "_internal": {"positionMode": "net_mode"}},
            )

        with patch.object(StrategyService, "_preflight", new=deterministic_preflight):
            worker._run_once()

        self.assertEqual(context_requests, [False])
        self.assertEqual(client.mutations, ["set_leverage", "place_order"])
        self.assertGreater(now[0], 1_800_000_000.0)
        self.assertGreaterEqual(sum(name == "account_config" for name, _ in client.calls), 2)
        with self.store.connection() as connection:
            strategy = connection.execute(
                "SELECT status, results_json, queue_json, pre_send_at, order_placement_attempted, "
                "lease_owner, updated_at FROM multiuser_strategies WHERE user_id=? AND connection_id=? "
                "AND strategy_id=?",
                (self.scope.user_id, self.scope.connection_id, "batch-strategy-1"),
            ).fetchone()
            markers = connection.execute(
                "SELECT payload_json FROM multiuser_strategy_events WHERE user_id=? AND connection_id=? "
                "AND strategy_id=? AND event_type='strategy_target_pre_send' ORDER BY created_at, event_id",
                (self.scope.user_id, self.scope.connection_id, "batch-strategy-1"),
            ).fetchall()
            lease = connection.execute(
                "SELECT lease_owner, fence FROM multiuser_connection_leases WHERE user_id=? AND connection_id=?",
                (self.scope.user_id, self.scope.connection_id),
            ).fetchone()
        self.assertEqual(strategy["status"], "APPLIED")
        self.assertEqual(json.loads(strategy["results_json"])[0]["status"], "accepted")
        self.assertEqual(json.loads(strategy["queue_json"])["phase"], "submitted")
        self.assertIsNotNone(strategy["pre_send_at"])
        self.assertEqual(strategy["order_placement_attempted"], 1)
        self.assertIsNone(strategy["lease_owner"])
        self.assertEqual(len(markers), 2)
        self.assertEqual({json.loads(row["payload_json"])["kind"] for row in markers}, {"leverage", "placement"})
        self.assertEqual(tuple(lease), (None, 5))

    def test_owned_worker_persists_readonly_same_owner_recovery_without_resending(self) -> None:
        self._seed_applying_strategy(lease_until=1_799_999_999.0)
        stable_fingerprint = owned_strategy_fingerprint(self.scope.user_id, self.scope.connection_id)
        order = {
            "clientOrderId": "recovery-order-1", "exchangeOrderId": None,
            "side": "long", "contracts": "2", "status": "unknown", "placementState": "unknown",
        }
        prepared = {"submissionMode": "batch", "_positionMode": "net_mode", "orders": [order]}
        snapshot = {"_positionMode": "net_mode", "orders": [order]}
        with self.store.transaction() as connection:
            connection.execute(
                "UPDATE exchange_connections SET status='RECONCILING', product_capabilities_json='[\"read\"]', "
                "credential_version=3, permission_version=4 WHERE user_id=? AND connection_id=?",
                (self.scope.user_id, self.scope.connection_id),
            )
            connection.execute(
                "UPDATE multiuser_strategies SET account_fingerprint=?, status='UNKNOWN', submission_mode='batch', "
                "queue_json=NULL, prepared_json=?, snapshot_json=?, orders_json=?, results_json=?, batch_attempted=1, "
                "order_placement_attempted=1, pre_send_at=?, credential_version=2, permission_version=3, "
                "execution_lease_until=?, lease_until=? WHERE user_id=? AND connection_id=? AND strategy_id=?",
                (stable_fingerprint, encode_json(prepared), encode_json(snapshot), encode_json([order]),
                 encode_json([order]), 1_799_999_990.0, 1_799_999_999.0, 1_799_999_999.0,
                 self.scope.user_id, self.scope.connection_id, "batch-strategy-1"),
            )

        class ReadOnlyRecoveryClient:
            def __init__(self) -> None:
                self.account_reads = 0
                self.order_reads = 0
                self.write_attempts = 0

            def account_config(self) -> dict[str, Any]:
                self.account_reads += 1
                return {"uid": "canonical-uid"}

            def order_details(self, instrument_id: str, client_order_id: str) -> dict[str, Any]:
                self.order_reads += 1
                return {
                    "instId": instrument_id, "clOrdId": client_order_id, "ordId": "exchange-order-recovered",
                    "sz": "2", "accFillSz": "0", "state": "live", "avgPx": "",
                }

            def set_leverage(self, _payload: Any) -> None:
                self.write_attempts += 1
                raise AssertionError("read-only recovery attempted a mutation")

            def place_order(self, _payload: Any) -> None:
                self.write_attempts += 1
                raise AssertionError("read-only recovery attempted a mutation")

        client = ReadOnlyRecoveryClient()
        context = SimpleNamespace(
            client=client, exchange="OKX", environment="demo", region="global",
            remote_identity_digest=self.scope.remote_identity_digest,
            credential_version=3, permission_version=4, capabilities=("read",),
        )
        context_requests: list[tuple[bool, int, int]] = []

        def readonly_recovery_context(
            user_id: str, connection_id: str, _strategy_id: str, _worker_id: str, _fence: int,
            *, recovery: bool = False,
        ) -> Any:
            with self.store.connection() as connection:
                owned = connection.execute(
                    "SELECT status, product_capabilities_json, credential_version, permission_version "
                    "FROM exchange_connections WHERE user_id=? AND connection_id=?",
                    (user_id, connection_id),
                ).fetchone()
            self.assertTrue(recovery)
            self.assertEqual(owned["status"], "RECONCILING")
            self.assertEqual(json.loads(owned["product_capabilities_json"]), ["read"])
            context_requests.append((recovery, owned["credential_version"], owned["permission_version"]))
            return context

        connections = SimpleNamespace(
            store=self.store,
            _identity_digest=lambda _exchange, _environment, _region, uid: (
                self.scope.remote_identity_digest if uid == "canonical-uid" else "wrong-identity"
            ),
            account_context_for_strategy_job=readonly_recovery_context,
        )
        worker = OwnedStrategyOrderWorker(
            SimpleNamespace(multiuser_enabled=True, multiuser_trade_enabled=True),
            store=self.store, connections=connections, clock=lambda: 1_800_000_000.0,
            owner_id="readonly-worker", lease_seconds=30,
        )

        worker._run_once()

        self.assertEqual(context_requests, [(True, 3, 4)])
        self.assertEqual(client.account_reads, 1)
        self.assertEqual(client.order_reads, 1)
        self.assertEqual(client.write_attempts, 0)
        with self.store.connection() as connection:
            strategy = connection.execute(
                "SELECT status, results_json, credential_version, permission_version FROM multiuser_strategies "
                "WHERE user_id=? AND connection_id=? AND strategy_id=?",
                (self.scope.user_id, self.scope.connection_id, "batch-strategy-1"),
            ).fetchone()
            owned = connection.execute(
                "SELECT status, credential_version, permission_version, product_capabilities_json "
                "FROM exchange_connections WHERE user_id=? AND connection_id=?",
                (self.scope.user_id, self.scope.connection_id),
            ).fetchone()
        persisted = json.loads(strategy["results_json"])[0]
        self.assertEqual(strategy["status"], "APPLIED")
        self.assertEqual((strategy["credential_version"], strategy["permission_version"]), (2, 3))
        self.assertEqual((owned["status"], owned["credential_version"], owned["permission_version"]),
                         ("RECONCILING", 3, 4))
        self.assertEqual(json.loads(owned["product_capabilities_json"]), ["read"])
        self.assertEqual((persisted["status"], persisted["placementState"]), ("live", "accepted"))
        self.assertEqual(persisted["exchangeOrderId"], "exchange-order-recovered")

    def test_owned_worker_reclaims_historical_readonly_jobs_after_connection_fence_advances(self) -> None:
        self._seed_applying_strategy(lease_until=1_799_999_999.0)
        stable_fingerprint = owned_strategy_fingerprint(self.scope.user_id, self.scope.connection_id)
        orders_by_id = {
            "batch-strategy-1": {
                "clientOrderId": "recovery-order-1", "side": "long", "contracts": "2",
            },
            "batch-strategy-2": {
                "clientOrderId": "recovery-order-2", "side": "long", "contracts": "2",
            },
        }
        with self.store.transaction() as connection:
            for strategy_id, order in orders_by_id.items():
                prepared = {"submissionMode": "batch", "_positionMode": "net_mode", "orders": [order]}
                snapshot = {"_positionMode": "net_mode", "orders": [order]}
                results = [{**order, "status": "unknown", "placementState": "unknown"}]
                if strategy_id == "batch-strategy-1":
                    connection.execute(
                        "UPDATE multiuser_strategies SET account_fingerprint=?, status='UNKNOWN', "
                        "snapshot_json=?, orders_json=?, results_json=?, prepared_json=?, batch_attempted=1, "
                        "submission_mode='batch', order_placement_attempted=1, pre_send_at=?, "
                        "credential_version=2, permission_version=3, execution_id=NULL, "
                        "execution_lease_until=NULL, lease_owner=NULL, lease_fence=4, lease_until=NULL "
                        "WHERE user_id=? AND connection_id=? AND strategy_id=?",
                        (stable_fingerprint, encode_json(snapshot), encode_json([order]), encode_json(results),
                         encode_json(prepared), 1_799_999_990.0, self.scope.user_id,
                         self.scope.connection_id, strategy_id),
                    )
                    connection.execute(
                        "UPDATE multiuser_strategy_claims SET lease_owner=NULL, fence=4, lease_until=NULL "
                        "WHERE user_id=? AND connection_id=? AND strategy_id=?",
                        (self.scope.user_id, self.scope.connection_id, strategy_id),
                    )
                else:
                    connection.execute(
                        "INSERT INTO multiuser_strategies(user_id, connection_id, strategy_id, status, "
                        "account_fingerprint, contract_json, snapshot_json, orders_json, results_json, "
                        "prepared_json, attempt_started, batch_attempted, submission_mode, "
                        "order_placement_attempted, pre_send_at, credential_version, permission_version, "
                        "lease_fence, created_at, updated_at) VALUES (?, ?, ?, 'UNKNOWN', ?, ?, ?, ?, ?, ?, "
                        "1, 1, 'batch', 1, ?, 2, 3, 4, ?, ?)",
                        (self.scope.user_id, self.scope.connection_id, strategy_id, stable_fingerprint,
                         encode_json({"instrumentId": INSTRUMENT}), encode_json(snapshot),
                         encode_json([order]), encode_json(results), encode_json(prepared),
                         1_799_999_990.0, 1_800_000_000.0, 1_800_000_000.0),
                    )
                    connection.execute(
                        "INSERT INTO multiuser_strategy_claims(user_id, connection_id, strategy_id, "
                        "lease_owner, fence, lease_until, updated_at) VALUES (?, ?, ?, NULL, 4, NULL, ?)",
                        (self.scope.user_id, self.scope.connection_id, strategy_id, 1_800_000_000.0),
                    )
            connection.execute(
                "UPDATE multiuser_connection_leases SET lease_owner=NULL, fence=4, lease_until=NULL, "
                "operation_id=NULL WHERE user_id=? AND connection_id=?",
                (self.scope.user_id, self.scope.connection_id),
            )

        class ReadOnlyRecoveryClient:
            def __init__(self) -> None:
                self.account_reads = 0
                self.order_reads: list[str] = []
                self.write_attempts = 0

            def account_config(self) -> dict[str, Any]:
                self.account_reads += 1
                return {"uid": "canonical-uid"}

            def order_details(self, instrument_id: str, client_order_id: str) -> dict[str, Any]:
                self.order_reads.append(client_order_id)
                return {
                    "instId": instrument_id, "clOrdId": client_order_id,
                    "ordId": f"exchange-{client_order_id}", "sz": "2", "accFillSz": "0",
                    "state": "live", "avgPx": "",
                }

            def set_leverage(self, _payload: Any) -> None:
                self.write_attempts += 1
                raise AssertionError("read-only recovery attempted a leverage mutation")

            def place_order(self, _payload: Any) -> None:
                self.write_attempts += 1
                raise AssertionError("read-only recovery attempted an order mutation")

        client = ReadOnlyRecoveryClient()
        context = SimpleNamespace(
            client=client, exchange="OKX", environment="demo", region="global",
            remote_identity_digest=self.scope.remote_identity_digest,
            credential_version=2, permission_version=3, capabilities=("read",),
        )
        connections = SimpleNamespace(
            store=self.store,
            _identity_digest=lambda _exchange, _environment, _region, uid: (
                self.scope.remote_identity_digest if uid == "canonical-uid" else "wrong-identity"
            ),
            account_context_for_strategy_job=lambda *_args, **_kwargs: context,
        )
        worker = OwnedStrategyOrderWorker(
            SimpleNamespace(multiuser_enabled=True, multiuser_trade_enabled=True),
            store=self.store, connections=connections, clock=lambda: 1_800_000_000.0,
            owner_id="sequential-recovery-worker", lease_seconds=30,
        )
        jobs: list[dict[str, Any]] = []
        run_claimed_job = worker._run_claimed_job

        def capture_job(job: dict[str, Any]) -> None:
            jobs.append(job)
            run_claimed_job(job)

        worker._run_claimed_job = capture_job  # type: ignore[method-assign]

        worker._run_once()

        self.assertEqual([job["strategy_id"] for job in jobs], ["batch-strategy-1", "batch-strategy-2"])
        self.assertEqual([job["fence"] for job in jobs], [5, 6])
        self.assertEqual(client.account_reads, 2)
        self.assertEqual(set(client.order_reads), {"recovery-order-1", "recovery-order-2"})
        self.assertEqual(client.write_attempts, 0)
        with self.store.connection() as connection:
            strategies = connection.execute(
                "SELECT strategy_id, status FROM multiuser_strategies WHERE user_id=? "
                "AND connection_id=? ORDER BY strategy_id",
                (self.scope.user_id, self.scope.connection_id),
            ).fetchall()
            claims = connection.execute(
                "SELECT strategy_id, fence FROM multiuser_strategy_claims WHERE user_id=? "
                "AND connection_id=? ORDER BY strategy_id",
                (self.scope.user_id, self.scope.connection_id),
            ).fetchall()
            lease = connection.execute(
                "SELECT lease_owner, fence, lease_until FROM multiuser_connection_leases "
                "WHERE user_id=? AND connection_id=?",
                (self.scope.user_id, self.scope.connection_id),
            ).fetchone()
        self.assertEqual([(row["strategy_id"], row["status"]) for row in strategies], [
            ("batch-strategy-1", "APPLIED"), ("batch-strategy-2", "APPLIED"),
        ])
        self.assertEqual([(row["strategy_id"], row["fence"]) for row in claims], [
            ("batch-strategy-1", 5), ("batch-strategy-2", 6),
        ])
        self.assertEqual((lease["lease_owner"], lease["fence"], lease["lease_until"]), (None, 6, None))

        worker.scope = OwnedStrategyScope(
            user_id=jobs[0]["user_id"], connection_id=jobs[0]["connection_id"],
            account_fingerprint=stable_fingerprint, remote_identity_digest=self.scope.remote_identity_digest,
            credential_version=2, permission_version=3, environment="demo",
        )
        worker._job_strategy_id = jobs[0]["strategy_id"]
        worker._job_fence = jobs[0]["fence"]
        self.assertIsNone(worker._write_attempt(jobs[0]["strategy_id"], jobs[0]["fence"]))
        self.assertEqual(client.write_attempts, 0)

    def test_owned_worker_historical_claim_takeover_requires_expired_valid_fences(self) -> None:
        self._seed_applying_strategy(lease_until=1_800_000_030.0)
        worker = self._owned_worker()
        strategy_id = "batch-strategy-1"

        # A current connection lease or a still-active historical claim always blocks takeover.
        self.assertIsNone(worker._claim_job(self.scope.user_id, self.scope.connection_id, strategy_id))
        with self.store.transaction() as connection:
            connection.execute(
                "UPDATE multiuser_connection_leases SET lease_until=? WHERE user_id=? AND connection_id=?",
                (1_799_999_999.0, self.scope.user_id, self.scope.connection_id),
            )
        self.assertIsNone(worker._claim_job(self.scope.user_id, self.scope.connection_id, strategy_id))

        # A claim ahead of the durable connection fence is corrupt and cannot be adopted.
        with self.store.transaction() as connection:
            connection.execute(
                "UPDATE multiuser_strategy_claims SET lease_owner=NULL, fence=5, lease_until=NULL "
                "WHERE user_id=? AND connection_id=? AND strategy_id=?",
                (self.scope.user_id, self.scope.connection_id, strategy_id),
            )
        self.assertIsNone(worker._claim_job(self.scope.user_id, self.scope.connection_id, strategy_id))

    def test_owned_worker_does_not_reconcile_after_fresh_account_identity_changes(self) -> None:
        self._seed_applying_strategy(lease_until=1_799_999_999.0)
        order = {"clientOrderId": "batch-target-01", "side": "long", "contracts": "2"}
        read_calls = {"account": 0, "orders": 0}

        def account_config() -> dict[str, Any]:
            read_calls["account"] += 1
            return {"uid": "relinked-uid"}

        def order_details(_instrument_id: str, _client_order_id: str) -> None:
            read_calls["orders"] += 1
            return None

        client = SimpleNamespace(account_config=account_config, order_details=order_details)
        context = SimpleNamespace(
            client=client, exchange="OKX", environment="demo", region="global",
            remote_identity_digest=self.scope.remote_identity_digest,
            credential_version=self.scope.credential_version,
            permission_version=self.scope.permission_version,
        )
        connections = SimpleNamespace(
            store=self.store,
            _identity_digest=lambda _exchange, _environment, _region, uid: (
                "remote-digest" if uid == "original-uid" else "relinked-digest"
            ),
            account_context_for_strategy_job=lambda *_args, **_kwargs: context,
        )
        with self.store.transaction() as connection:
            connection.execute(
                "UPDATE multiuser_strategies SET status='UNKNOWN', submission_mode='batch', queue_json=NULL, "
                "orders_json=?, results_json=?, batch_attempted=1, order_placement_attempted=1, pre_send_at=?, "
                "execution_lease_until=?, lease_until=? WHERE user_id=? AND connection_id=? AND strategy_id=?",
                (encode_json([order]), encode_json([{**order, "status": "accepted"}]),
                 1_800_000_000.0, 1_799_999_999.0, 1_799_999_999.0,
                 self.scope.user_id, self.scope.connection_id, "batch-strategy-1"),
            )
            connection.execute(
                "UPDATE multiuser_strategies SET lease_owner='execution-1' WHERE user_id=? AND connection_id=? "
                "AND strategy_id=?",
                (self.scope.user_id, self.scope.connection_id, "batch-strategy-1"),
            )
        worker = OwnedStrategyOrderWorker(
            SimpleNamespace(multiuser_enabled=True, multiuser_trade_enabled=True),
            store=self.store, connections=connections, clock=lambda: 1_800_000_000.0,
            owner_id="owned-worker", lease_seconds=30,
        )

        job = worker._claim_job(self.scope.user_id, self.scope.connection_id, "batch-strategy-1")
        self.assertIsNotNone(job)
        self.assertEqual(job["mode"], "recovery")
        worker._run_claimed_job(job)

        self.assertEqual(read_calls, {"account": 1, "orders": 0})
        current = self.service._load_row("batch-strategy-1")
        self.assertEqual(current["status"], "UNKNOWN")

    def test_owned_worker_allows_readonly_recovery_for_verified_same_identity(self) -> None:
        self._seed_owned_queue()
        with self.store.transaction() as connection:
            connection.execute(
                "UPDATE multiuser_strategies SET status='UNKNOWN', pre_send_at=? WHERE user_id=? "
                "AND connection_id=? AND strategy_id=?",
                (1_800_000_000.0, self.scope.user_id, self.scope.connection_id, "batch-strategy-1"),
            )
        client = SimpleNamespace(account_config=lambda: {"uid": "original-uid"})
        context = SimpleNamespace(
            exchange="OKX", environment="demo", region="global",
            remote_identity_digest=self.scope.remote_identity_digest,
        )
        worker = self._owned_worker()
        worker.owner_id = "worker-1"
        worker.scope = self.scope
        worker._job_strategy_id = "batch-strategy-1"
        worker._job_fence = 4
        worker._job_mode = "recovery"
        worker._job_context = context
        worker.okx = client
        worker.connections = SimpleNamespace(
            store=self.store,
            _identity_digest=lambda *_args: self.scope.remote_identity_digest,
        )

        self.assertTrue(worker._verify_recovery_identity(4))

    def test_owned_worker_recovers_batch_crash_before_first_mutation_marker(self) -> None:
        self._seed_unmarked_owned_batch(unresolved_leverage=False)
        worker = self._owned_worker()

        worker._run_once()

        current = self.service._load_row("batch-strategy-1")
        self.assertEqual(current["status"], "PARTIAL")
        self.assertEqual([row["status"] for row in current["results"]], ["not_submitted"])

    def test_owned_worker_recovers_expired_batch_after_durable_order_marker(self) -> None:
        self._seed_unmarked_owned_batch(unresolved_leverage=False)
        with self.store.transaction() as connection:
            connection.execute(
                "UPDATE multiuser_strategies SET batch_attempted=1, order_placement_attempted=1, "
                "pre_send_at=? WHERE user_id=? AND connection_id=? AND strategy_id=?",
                (1_800_000_000.0, self.scope.user_id, self.scope.connection_id, "batch-strategy-1"),
            )
        worker = self._owned_worker()
        client = SimpleNamespace(account_config=lambda: {"uid": "original-uid"})
        context = SimpleNamespace(client=client)
        worker.connections = SimpleNamespace(
            store=self.store,
            account_context_for_strategy_job=lambda *_args, **_kwargs: context,
        )
        job = worker._claim_job(self.scope.user_id, self.scope.connection_id, "batch-strategy-1")
        self.assertIsNotNone(job)
        self.assertEqual(job["mode"], "recovery")

        processed: list[str] = []
        with patch.object(worker, "_verify_recovery_identity", return_value=True), patch.object(
            worker, "_process_strategy", side_effect=lambda strategy, _fence: processed.append(strategy["id"]),
        ):
            worker._run_claimed_job(job)

        self.assertEqual(processed, ["batch-strategy-1"])
        current = self.service._load_row("batch-strategy-1")
        self.assertEqual(current["status"], "APPLYING")
        self.assertEqual(current["results"], [])

    def test_owned_worker_preserves_unresolved_batch_leverage_barrier_after_crash(self) -> None:
        self._seed_unmarked_owned_batch(unresolved_leverage=True)
        worker = self._owned_worker()

        worker._run_once()

        current = self.service._load_row("batch-strategy-1")
        self.assertEqual(current["status"], "UNKNOWN")
        self.assertEqual(current["leverageResults"], [{"side": "long", "status": "unknown"}])
        self.assertFalse(self.service._can_delete_hint(current))
        with self.store.connection() as connection:
            count = connection.execute(
                "SELECT COUNT(*) FROM multiuser_strategy_reservations WHERE user_id=? AND connection_id=?",
                (self.scope.user_id, self.scope.connection_id),
            ).fetchone()[0]
        self.assertEqual(count, 1)

    def test_owned_worker_preserves_unmarked_queue_leverage_barrier_after_crash(self) -> None:
        self._seed_owned_queue(lease_until=1_799_999_999.0)
        with self.store.transaction() as connection:
            connection.execute(
                "UPDATE multiuser_strategies SET pre_send_at=? WHERE user_id=? AND connection_id=? "
                "AND strategy_id=?",
                (1_800_000_000.0, self.scope.user_id, self.scope.connection_id, "batch-strategy-1"),
            )
            connection.execute(
                "INSERT INTO multiuser_strategy_reservations(user_id, connection_id, instrument_id, "
                "strategy_id, position_mode, side_scope, created_at) VALUES (?, ?, ?, ?, 'net_mode', 'all', ?)",
                (self.scope.user_id, self.scope.connection_id, INSTRUMENT, "batch-strategy-1", 1_800_000_000.0),
            )
            connection.execute(
                "INSERT INTO multiuser_strategy_events(user_id, connection_id, strategy_id, event_id, "
                "event_type, payload_json, created_at) VALUES (?, ?, ?, ?, 'strategy_target_pre_send', ?, ?)",
                (self.scope.user_id, self.scope.connection_id, "batch-strategy-1", "leverage-marker",
                 encode_json({"kind": "leverage", "side": "long", "instrumentId": INSTRUMENT}),
                 1_800_000_000.0),
            )
        worker = self._owned_worker()

        worker._run_once()

        current = self.service._load_row("batch-strategy-1")
        self.assertEqual(current["status"], "UNKNOWN")
        self.assertEqual(current["leverageResults"], [{"side": "long", "status": "unknown"}])
        with self.store.connection() as connection:
            count = connection.execute(
                "SELECT COUNT(*) FROM multiuser_strategy_reservations WHERE user_id=? AND connection_id=?",
                (self.scope.user_id, self.scope.connection_id),
            ).fetchone()[0]
        self.assertEqual(count, 1)

    def test_owned_worker_selection_and_takeover_share_connection_fence(self) -> None:
        self._seed_owned_queue()
        with self.store.transaction() as connection:
            connection.execute(
                "UPDATE multiuser_strategies SET credential_version=?, permission_version=? "
                "WHERE user_id=? AND connection_id=? AND strategy_id=?",
                (self.scope.credential_version, self.scope.permission_version,
                 self.scope.user_id, self.scope.connection_id, "batch-strategy-1"),
            )
        worker = self._owned_worker()

        self.assertEqual(worker._candidate_ids(1_800_000_000.0), [])
        with self.store.transaction() as connection:
            connection.execute(
                "UPDATE multiuser_connection_leases SET lease_until=? WHERE user_id=? AND connection_id=?",
                (1_799_999_999.0, self.scope.user_id, self.scope.connection_id),
            )
            connection.execute(
                "UPDATE multiuser_strategy_claims SET lease_until=? WHERE user_id=? AND connection_id=? "
                "AND strategy_id=?",
                (1_799_999_999.0, self.scope.user_id, self.scope.connection_id, "batch-strategy-1"),
            )
            connection.execute(
                "UPDATE multiuser_strategies SET execution_lease_until=? WHERE user_id=? AND connection_id=? "
                "AND strategy_id=?",
                (1_799_999_999.0, self.scope.user_id, self.scope.connection_id, "batch-strategy-1"),
            )

        job = worker._claim_job(self.scope.user_id, self.scope.connection_id, "batch-strategy-1")

        self.assertIsNotNone(job)
        self.assertEqual(job["mode"], "submit")
        self.assertEqual(job["fence"], 5)
        with self.store.connection() as connection:
            lease = connection.execute(
                "SELECT lease_owner, fence, operation_id FROM multiuser_connection_leases "
                "WHERE user_id=? AND connection_id=?",
                (self.scope.user_id, self.scope.connection_id),
            ).fetchone()
            claim = connection.execute(
                "SELECT lease_owner, fence FROM multiuser_strategy_claims WHERE user_id=? "
                "AND connection_id=? AND strategy_id=?",
                (self.scope.user_id, self.scope.connection_id, "batch-strategy-1"),
            ).fetchone()
            strategy = connection.execute(
                "SELECT lease_owner, lease_fence, worker_scope FROM multiuser_strategies WHERE user_id=? "
                "AND connection_id=? AND strategy_id=?",
                (self.scope.user_id, self.scope.connection_id, "batch-strategy-1"),
            ).fetchone()
        self.assertEqual(tuple(lease), ("owned-worker", 5, "batch-strategy-1"))
        self.assertEqual(tuple(claim), ("owned-worker", 5))
        self.assertEqual(tuple(strategy), ("owned-worker", 5, "owned_worker"))

    def test_owned_queue_marker_refuses_expired_worker_fence(self) -> None:
        strategy = self._seed_owned_queue(lease_until=1_799_999_999.0)
        queue = {**strategy["queue"], "phase": "sending", "inFlight": {"kind": "placement", "index": 0}}
        results = [{**strategy["results"][0], "status": "sending", "placementState": "sending"}]
        ledger = OwnedStrategyQueueLedger(
            self.store, scope=self.scope, owner_id="worker-1", fence=4,
            lease_seconds=30, clock=self.service.clock,
        )

        self.assertFalse(ledger.persist_transition(
            strategy, queue=queue, results=results, status="APPLYING", failure_reason=None,
            leverage_results=[], mark_placement_attempted=True,
        ))

        with self.store.connection() as connection:
            row = connection.execute(
                "SELECT order_placement_attempted, pre_send_at FROM multiuser_strategies "
                "WHERE user_id=? AND connection_id=? AND strategy_id=?",
                (self.scope.user_id, self.scope.connection_id, "batch-strategy-1"),
            ).fetchone()
            events = connection.execute(
                "SELECT COUNT(*) FROM multiuser_strategy_events WHERE user_id=? AND connection_id=? "
                "AND strategy_id=? AND event_type='strategy_target_pre_send'",
                (self.scope.user_id, self.scope.connection_id, "batch-strategy-1"),
            ).fetchone()[0]
        self.assertEqual(tuple(row), (0, None))
        self.assertEqual(events, 0)

    def test_owned_queue_persists_target_marker_before_mutation(self) -> None:
        strategy = self._seed_owned_queue()
        queue = {**strategy["queue"], "phase": "sending", "inFlight": {"kind": "placement", "index": 0}}
        results = [{**strategy["results"][0], "status": "sending", "placementState": "sending"}]
        ledger = OwnedStrategyQueueLedger(
            self.store, scope=self.scope, owner_id="worker-1", fence=4,
            lease_seconds=30, clock=self.service.clock,
        )

        self.assertTrue(ledger.persist_transition(
            strategy, queue=queue, results=results, status="APPLYING", failure_reason=None,
            leverage_results=[], mark_placement_attempted=True,
        ))

        with self.store.connection() as connection:
            row = connection.execute(
                "SELECT order_placement_attempted, pre_send_at, queue_json FROM multiuser_strategies "
                "WHERE user_id=? AND connection_id=? AND strategy_id=?",
                (self.scope.user_id, self.scope.connection_id, "batch-strategy-1"),
            ).fetchone()
            event = connection.execute(
                "SELECT payload_json FROM multiuser_strategy_events WHERE user_id=? AND connection_id=? "
                "AND strategy_id=? AND event_type='strategy_target_pre_send'",
                (self.scope.user_id, self.scope.connection_id, "batch-strategy-1"),
            ).fetchone()
        self.assertEqual(row["order_placement_attempted"], 1)
        self.assertEqual(row["pre_send_at"], 1_800_000_000.0)
        self.assertEqual(json.loads(row["queue_json"])["inFlight"], {"kind": "placement", "index": 0})
        self.assertEqual(json.loads(event["payload_json"]), {
            "kind": "placement", "index": 0, "side": "long", "clientOrderId": "queue-target-01",
            "instrumentId": INSTRUMENT, "contracts": "2",
        })

    def test_owned_worker_lease_renewal_preserves_queue_ack_cas_timestamp(self) -> None:
        strategy = self._seed_owned_queue()
        with self.store.transaction() as connection:
            connection.execute(
                "UPDATE multiuser_strategies SET credential_version=?, permission_version=? "
                "WHERE user_id=? AND connection_id=? AND strategy_id=?",
                (self.scope.credential_version, self.scope.permission_version,
                 self.scope.user_id, self.scope.connection_id, "batch-strategy-1"),
            )
        now = [1_800_000_001.0]
        settings = SimpleNamespace(multiuser_enabled=True, multiuser_trade_enabled=True)
        worker = OwnedStrategyOrderWorker(
            settings, store=self.store, connections=SimpleNamespace(store=self.store),
            clock=lambda: now[0], owner_id="worker-1", lease_seconds=30,
        )
        worker.scope = self.scope
        worker._job_strategy_id = "batch-strategy-1"
        worker._job_fence = 4
        worker._job_mode = "submit"
        worker.strategy = StrategyService(worker, strategy_scope=self.scope)

        queue = {**strategy["queue"], "phase": "sending", "inFlight": {"kind": "placement", "index": 0}}
        results = [{**strategy["results"][0], "status": "sending", "placementState": "sending"}]
        ledger = worker._queue_ledger(4)
        self.assertTrue(ledger.persist_transition(
            strategy, queue=queue, results=results, status="APPLYING", failure_reason=None,
            leverage_results=[], mark_placement_attempted=True,
        ))
        marked = worker.strategy._load_row("batch-strategy-1")

        now[0] += 1
        worker._ensure_lease(4)
        accepted = [{**results[0], "status": "accepted", "placementState": "accepted",
                     "exchangeOrderId": "exchange-1"}]
        completed_queue = {**marked["queue"], "phase": "submitted", "cursor": 1,
                           "inFlight": None, "stopReason": None}

        self.assertTrue(ledger.persist_transition(
            marked, queue=completed_queue, results=accepted, status="APPLIED", failure_reason=None,
            leverage_results=[],
        ))

    def test_owned_queue_persists_leverage_unknown_after_revoke_and_lease_expiry(self) -> None:
        strategy = self._seed_owned_queue()
        ledger = OwnedStrategyQueueLedger(
            self.store, scope=self.scope, owner_id="worker-1", fence=4,
            lease_seconds=30, clock=self.service.clock,
        )
        marked = {**strategy["queue"], "phase": "sending", "inFlight": {"kind": "leverage", "side": "long"}}
        self.assertTrue(ledger.persist_transition(
            strategy, queue=marked, results=strategy["results"], status="APPLYING",
            failure_reason=None, leverage_results=[],
        ))
        after_marker = self.service._load_row("batch-strategy-1")
        with self.store.transaction() as connection:
            connection.execute(
                "UPDATE exchange_connections SET status='REVOKED', credential_version=3, "
                "permission_version=4 WHERE user_id=? AND connection_id=?",
                (self.scope.user_id, self.scope.connection_id),
            )
            connection.execute(
                "UPDATE multiuser_connection_leases SET lease_until=? WHERE user_id=? AND connection_id=?",
                (1_799_999_999.0, self.scope.user_id, self.scope.connection_id),
            )
            connection.execute(
                "INSERT INTO multiuser_strategy_reservations(user_id, connection_id, instrument_id, "
                "strategy_id, position_mode, side_scope, created_at) VALUES (?, ?, ?, ?, 'net_mode', 'all', ?)",
                (self.scope.user_id, self.scope.connection_id, INSTRUMENT, "batch-strategy-1", 1_800_000_000.0),
            )
        stopped = {**after_marker["queue"], "phase": "stopped", "inFlight": None,
                   "stopReason": "leverage_unknown"}

        self.assertTrue(ledger.persist_transition(
            after_marker, queue=stopped, results=after_marker["results"], status="UNKNOWN",
            failure_reason="leverage_unknown", leverage_results=[{"side": "long", "status": "unknown"}],
        ))

        with self.store.connection() as connection:
            row = connection.execute(
                "SELECT status, queue_json, leverage_results_json, pre_send_at FROM multiuser_strategies "
                "WHERE user_id=? AND connection_id=? AND strategy_id=?",
                (self.scope.user_id, self.scope.connection_id, "batch-strategy-1"),
            ).fetchone()
            reservation_count = connection.execute(
                "SELECT COUNT(*) FROM multiuser_strategy_reservations WHERE user_id=? AND connection_id=?",
                (self.scope.user_id, self.scope.connection_id),
            ).fetchone()[0]
        self.assertEqual(row["status"], "UNKNOWN")
        self.assertIsNotNone(row["pre_send_at"])
        self.assertEqual(json.loads(row["queue_json"])["inFlight"], None)
        self.assertEqual(json.loads(row["leverage_results_json"]), [{"side": "long", "status": "unknown"}])
        self.assertEqual(reservation_count, 1)


class PostgresOwnedStrategyIntegrationTests(unittest.TestCase):
    def test_pg_owner_api_claim_and_worker_claim_share_connection_fence(self) -> None:
        test_dsn = os.environ.get("MULTIUSER_TEST_DATABASE_URL", "")
        if not test_dsn:
            self.skipTest("BLOCKED: MULTIUSER_TEST_DATABASE_URL is not configured")
        try:
            import psycopg
        except ImportError:
            self.fail("BLOCKED: psycopg is required when MULTIUSER_TEST_DATABASE_URL is configured")

        from backend.postgres_store import PostgresIdentityStore

        schema = "t111_strategy_" + secrets.token_hex(8)
        with psycopg.connect(test_dsn, autocommit=True) as connection:
            connection.execute(f'CREATE SCHEMA "{schema}"')
        dsn = psycopg.conninfo.make_conninfo(test_dsn, options=f"-c search_path={schema}")
        now = 1_800_000_000.0
        store = PostgresIdentityStore(dsn)
        processes: list[multiprocessing.Process] = []
        output: multiprocessing.queues.Queue | None = None
        try:
            store.initialize()
            scope = OwnedStrategyScope(
                user_id="owner-one", connection_id="connection-one",
                account_fingerprint="owner-scoped-fingerprint", remote_identity_digest="remote-digest",
                credential_version=2, permission_version=3, environment="demo",
            )
            with store.transaction() as connection:
                connection.execute(
                    "INSERT INTO users(user_id, username, username_normalized, password_hash, status, created_at) "
                    "VALUES ('owner-one', 'Owner One', 'owner one', 'fabricated-hash', 'ACTIVE', ?) ",
                    (now - 100,),
                )
                connection.execute(
                    "INSERT INTO exchange_connections(user_id, connection_id, exchange, environment, region, "
                    "product_capabilities_json, status, remote_identity_digest, credential_version, permission_version, "
                    "created_at, updated_at) VALUES (?, ?, 'OKX', 'demo', 'global', '[\"read\",\"trade\"]', "
                    "'ACTIVE', ?, 2, 3, ?, ?)",
                    (scope.user_id, scope.connection_id, scope.remote_identity_digest, now - 100, now - 100),
                )
                _seed_owned_claim_race_fixture(connection, scope, now)

            context = multiprocessing.get_context("spawn")
            barrier = context.Barrier(2)
            output = context.Queue()
            processes = [
                context.Process(target=_postgres_owned_api_claim_worker, args=(dsn, barrier, output, now)),
                context.Process(target=_postgres_owned_worker_claim_worker, args=(dsn, barrier, output, now)),
            ]
            for process in processes:
                process.start()
            results = [output.get(timeout=90) for _ in processes]
            for process in processes:
                process.join(timeout=90)
                self.assertEqual(process.exitcode, 0)
            self.assertCountEqual(
                results,
                [("api", "blocked", "connection_busy"), ("worker", "claimed", 5)],
            )
            with store.connection() as connection:
                lease = connection.execute(
                    "SELECT lease_owner, fence, operation_id FROM multiuser_connection_leases "
                    "WHERE user_id=? AND connection_id=?",
                    (scope.user_id, scope.connection_id),
                ).fetchone()
                worker_strategy = connection.execute(
                    "SELECT status, lease_owner, lease_fence FROM multiuser_strategies WHERE user_id=? "
                    "AND connection_id=? AND strategy_id='worker-queued-job'",
                    (scope.user_id, scope.connection_id),
                ).fetchone()
                api_strategy = connection.execute(
                    "SELECT status, confirmation_hash, attempt_started FROM multiuser_strategies "
                    "WHERE user_id=? AND connection_id=? AND strategy_id='api-prepared-strategy'",
                    (scope.user_id, scope.connection_id),
                ).fetchone()
            self.assertEqual(tuple(lease), ("pg-owned-worker", 5, "worker-queued-job"))
            self.assertEqual(tuple(worker_strategy), ("APPLYING", "pg-owned-worker", 5))
            self.assertEqual(api_strategy["status"], "PREPARED")
            self.assertEqual(api_strategy["confirmation_hash"], token_digest("api-confirmation", b"S" * 32))
            self.assertEqual(api_strategy["attempt_started"], 0)
        finally:
            for process in processes:
                if process.is_alive():
                    process.terminate()
                    process.join(timeout=5)
            if output is not None:
                output.close()
            with psycopg.connect(test_dsn, autocommit=True) as connection:
                connection.execute(f'DROP SCHEMA IF EXISTS "{schema}" CASCADE')


if __name__ == "__main__":
    unittest.main()
