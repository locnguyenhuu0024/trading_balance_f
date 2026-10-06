"""Durable SQLite state for sessions, rate limits, and action operations."""

from __future__ import annotations

import json
import os
import sqlite3
import threading
from contextlib import contextmanager
from typing import Any, Callable, Iterator

from .strategy_scope import UNKNOWN_SCOPE, extract_persisted_scope


_SCHEMA = """
CREATE TABLE IF NOT EXISTS auth_state (
    singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
    last_totp_counter INTEGER NOT NULL DEFAULT -1
);
INSERT OR IGNORE INTO auth_state(singleton, last_totp_counter) VALUES (1, -1);
CREATE TABLE IF NOT EXISTS login_attempts (
    source_key TEXT PRIMARY KEY,
    window_started REAL NOT NULL,
    failures INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS rate_limits (
    bucket_key TEXT PRIMARY KEY,
    window_started INTEGER NOT NULL,
    count INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS sessions (
    token_hash TEXT PRIMARY KEY,
    expires_at REAL NOT NULL,
    created_at REAL NOT NULL
);
CREATE TABLE IF NOT EXISTS operations (
    operation_id TEXT PRIMARY KEY,
    action TEXT NOT NULL,
    confirmation_hash TEXT NOT NULL,
    expires_at REAL NOT NULL,
    status TEXT NOT NULL,
    payload_json TEXT NOT NULL,
    results_json TEXT NOT NULL,
    created_at REAL NOT NULL,
    updated_at REAL NOT NULL
);
CREATE INDEX IF NOT EXISTS operations_status_expiry ON operations(status, expires_at);
CREATE TABLE IF NOT EXISTS strategies (
    strategy_id TEXT PRIMARY KEY,
    account_fingerprint TEXT NOT NULL,
    status TEXT NOT NULL,
    contract_json TEXT NOT NULL,
    snapshot_json TEXT NOT NULL,
    orders_json TEXT NOT NULL,
    results_json TEXT NOT NULL,
    preview_hash TEXT NOT NULL,
    confirmation_hash TEXT,
    prepared_expires_at REAL,
    prepared_json TEXT,
    attempt_started INTEGER NOT NULL DEFAULT 0,
    batch_attempted INTEGER NOT NULL DEFAULT 0,
    submission_mode TEXT DEFAULT 'batch',
    order_placement_attempted INTEGER NOT NULL DEFAULT 0,
    queue_json TEXT,
    execution_id TEXT,
    execution_lease_until REAL,
    replacement_source_id TEXT,
    failure_reason TEXT,
    leverage_results_json TEXT NOT NULL DEFAULT '[]',
    created_at REAL NOT NULL,
    updated_at REAL NOT NULL
);
CREATE INDEX IF NOT EXISTS strategies_account_updated ON strategies(account_fingerprint, updated_at);
CREATE TABLE IF NOT EXISTS strategy_account_preferences (
    account_fingerprint TEXT PRIMARY KEY,
    limit_order_submission_mode TEXT NOT NULL,
    updated_at REAL NOT NULL
);
CREATE TABLE IF NOT EXISTS strategy_reservations (
    account_fingerprint TEXT NOT NULL,
    instrument_id TEXT NOT NULL,
    strategy_id TEXT NOT NULL UNIQUE,
    position_mode TEXT NOT NULL DEFAULT 'unknown',
    side_scope TEXT NOT NULL DEFAULT 'all',
    created_at REAL NOT NULL,
    PRIMARY KEY (account_fingerprint, instrument_id, strategy_id)
);
CREATE TABLE IF NOT EXISTS strategy_monitor_lease (
    singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
    owner_id TEXT,
    fence INTEGER NOT NULL DEFAULT 0,
    lease_until REAL NOT NULL DEFAULT 0
);
INSERT OR IGNORE INTO strategy_monitor_lease(singleton, owner_id, fence, lease_until)
VALUES (1, NULL, 0, 0);
CREATE TABLE IF NOT EXISTS strategy_sync_state (
    strategy_id TEXT PRIMARY KEY,
    last_attempt_at REAL,
    last_success_at REAL,
    last_error TEXT,
    next_scan_at REAL,
    consecutive_errors INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS strategy_sync_next_scan ON strategy_sync_state(next_scan_at);
"""


def encode_json(value: Any) -> str:
    return json.dumps(value, separators=(",", ":"), sort_keys=True, ensure_ascii=False)


def decode_json(value: str) -> Any:
    return json.loads(value)


def _migrate_strategy_reservations(connection: sqlite3.Connection) -> None:
    def schema_is_scoped() -> bool:
        info = connection.execute("PRAGMA table_info(strategy_reservations)").fetchall()
        columns = {row[1] for row in info}
        primary_key = {row[1] for row in info if row[5]}
        return (
            {"position_mode", "side_scope"}.issubset(columns)
            and primary_key == {"account_fingerprint", "instrument_id", "strategy_id"}
        )

    def ensure_lookup_index() -> None:
        connection.execute(
            "CREATE INDEX IF NOT EXISTS strategy_reservations_scope_lookup "
            "ON strategy_reservations(account_fingerprint, instrument_id)"
        )

    if schema_is_scoped():
        ensure_lookup_index()
        return

    connection.execute("BEGIN IMMEDIATE")
    try:
        if schema_is_scoped():
            ensure_lookup_index()
            connection.execute("COMMIT")
            return

        temporary = connection.execute(
            "SELECT 1 FROM sqlite_master WHERE type='table' "
            "AND name='strategy_reservations_scoped_migration'"
        ).fetchone()
        if temporary is not None:
            raise sqlite3.DatabaseError("strategy reservation migration table already exists")

        connection.execute(
            "CREATE TABLE strategy_reservations_scoped_migration ("
            "account_fingerprint TEXT NOT NULL, instrument_id TEXT NOT NULL, "
            "strategy_id TEXT NOT NULL UNIQUE, position_mode TEXT NOT NULL DEFAULT 'unknown', "
            "side_scope TEXT NOT NULL DEFAULT 'all', created_at REAL NOT NULL, "
            "PRIMARY KEY (account_fingerprint, instrument_id, strategy_id))"
        )
        legacy_rows = connection.execute(
            "SELECT account_fingerprint, instrument_id, strategy_id, created_at "
            "FROM strategy_reservations"
        ).fetchall()
        for reservation in legacy_rows:
            account_fingerprint, instrument_id, strategy_id, created_at = reservation
            scope = UNKNOWN_SCOPE
            strategy = connection.execute(
                "SELECT account_fingerprint, contract_json, snapshot_json, orders_json, prepared_json "
                "FROM strategies WHERE strategy_id=?",
                (strategy_id,),
            ).fetchone()
            if strategy is not None:
                try:
                    contract = json.loads(strategy[1])
                    snapshot = json.loads(strategy[2])
                    orders = json.loads(strategy[3])
                    prepared = None if strategy[4] is None else json.loads(strategy[4])
                except (TypeError, ValueError, json.JSONDecodeError):
                    pass
                else:
                    if (
                        strategy[0] == account_fingerprint
                        and isinstance(contract, dict)
                        and contract.get("instrumentId") == instrument_id
                    ):
                        scope = extract_persisted_scope(
                            prepared, snapshot, orders, require_prepared_mode=True
                        )
            if not scope.valid:
                scope = UNKNOWN_SCOPE
            connection.execute(
                "INSERT INTO strategy_reservations_scoped_migration "
                "(account_fingerprint, instrument_id, strategy_id, position_mode, side_scope, created_at) "
                "VALUES (?, ?, ?, ?, ?, ?)",
                (
                    account_fingerprint, instrument_id, strategy_id,
                    scope.position_mode, scope.side_scope, created_at,
                ),
            )
        connection.execute("DROP TABLE strategy_reservations")
        connection.execute(
            "ALTER TABLE strategy_reservations_scoped_migration RENAME TO strategy_reservations"
        )
        ensure_lookup_index()
        connection.execute("COMMIT")
    except Exception:
        connection.execute("ROLLBACK")
        raise


class SQLiteStore:
    def __init__(self, path: str):
        self.path = path
        self._init_lock = threading.Lock()
        self._initialized = False

    def initialize(self) -> None:
        if self._initialized:
            return
        with self._init_lock:
            if self._initialized:
                return
            parent = os.path.dirname(self.path)
            os.makedirs(parent, exist_ok=True)
            connection = sqlite3.connect(self.path, timeout=5, isolation_level=None)
            try:
                connection.execute("PRAGMA busy_timeout=5000")
                connection.execute("PRAGMA journal_mode=DELETE")
                connection.execute("PRAGMA synchronous=FULL")
                connection.executescript(_SCHEMA)
                strategy_columns = {
                    row[1] for row in connection.execute("PRAGMA table_info(strategies)").fetchall()
                }
                if "execution_id" not in strategy_columns:
                    connection.execute("ALTER TABLE strategies ADD COLUMN execution_id TEXT")
                if "execution_lease_until" not in strategy_columns:
                    connection.execute("ALTER TABLE strategies ADD COLUMN execution_lease_until REAL")
                if "replacement_source_id" not in strategy_columns:
                    connection.execute("ALTER TABLE strategies ADD COLUMN replacement_source_id TEXT")
                if "submission_mode" not in strategy_columns:
                    connection.execute("ALTER TABLE strategies ADD COLUMN submission_mode TEXT DEFAULT 'batch'")
                if "order_placement_attempted" not in strategy_columns:
                    connection.execute(
                        "ALTER TABLE strategies ADD COLUMN order_placement_attempted INTEGER NOT NULL DEFAULT 0"
                    )
                if "queue_json" not in strategy_columns:
                    connection.execute("ALTER TABLE strategies ADD COLUMN queue_json TEXT")
                if "batch_attempted" in strategy_columns:
                    connection.execute(
                        "UPDATE strategies SET order_placement_attempted=1 "
                        "WHERE batch_attempted=1 AND order_placement_attempted=0"
                    )
                connection.execute(
                    "CREATE INDEX IF NOT EXISTS strategies_replacement_source "
                    "ON strategies(replacement_source_id, status)"
                )
                _migrate_strategy_reservations(connection)
            finally:
                connection.close()
            self._initialized = True

    @contextmanager
    def connection(self) -> Iterator[sqlite3.Connection]:
        self.initialize()
        connection = sqlite3.connect(self.path, timeout=5, isolation_level=None)
        connection.row_factory = sqlite3.Row
        connection.execute("PRAGMA busy_timeout=5000")
        connection.execute("PRAGMA synchronous=FULL")
        try:
            yield connection
        finally:
            connection.close()

    @contextmanager
    def transaction(self) -> Iterator[sqlite3.Connection]:
        with self.connection() as connection:
            connection.execute("BEGIN IMMEDIATE")
            try:
                yield connection
                connection.execute("COMMIT")
            except Exception:
                connection.execute("ROLLBACK")
                raise

    def acquire_strategy_monitor_lease(self, owner_id: str, now: float, lease_seconds: float) -> int | None:
        """Claim or renew the singleton order-monitor lease and return its fence."""
        with self.transaction() as connection:
            row = connection.execute(
                "SELECT owner_id, fence, lease_until FROM strategy_monitor_lease WHERE singleton=1"
            ).fetchone()
            if row is None:
                return None
            if row["owner_id"] == owner_id and row["lease_until"] > now:
                changed = connection.execute(
                    "UPDATE strategy_monitor_lease SET lease_until=? WHERE singleton=1 "
                    "AND owner_id=? AND fence=? AND lease_until>?",
                    (now + lease_seconds, owner_id, row["fence"], now),
                ).rowcount
                return int(row["fence"]) if changed == 1 else None
            if row["lease_until"] > now:
                return None
            fence = int(row["fence"]) + 1
            changed = connection.execute(
                "UPDATE strategy_monitor_lease SET owner_id=?, fence=?, lease_until=? "
                "WHERE singleton=1 AND fence=? AND lease_until<=?",
                (owner_id, fence, now + lease_seconds, row["fence"], now),
            ).rowcount
            return fence if changed == 1 else None

    def renew_strategy_monitor_lease(
        self,
        owner_id: str,
        fence: int,
        now: float,
        lease_seconds: float,
        *,
        clock: Callable[[], float] | None = None,
    ) -> bool:
        with self.transaction() as connection:
            effective_now = now if clock is None else clock()
            changed = connection.execute(
                "UPDATE strategy_monitor_lease SET lease_until=? WHERE singleton=1 "
                "AND owner_id=? AND fence=? AND lease_until>?",
                (effective_now + lease_seconds, owner_id, fence, effective_now),
            ).rowcount
        return changed == 1
