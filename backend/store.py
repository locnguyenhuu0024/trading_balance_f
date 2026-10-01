"""Durable SQLite state for sessions, rate limits, and action operations."""

from __future__ import annotations

import json
import os
import sqlite3
import threading
from contextlib import contextmanager
from typing import Any, Iterator


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
    execution_id TEXT,
    execution_lease_until REAL,
    failure_reason TEXT,
    leverage_results_json TEXT NOT NULL DEFAULT '[]',
    created_at REAL NOT NULL,
    updated_at REAL NOT NULL
);
CREATE INDEX IF NOT EXISTS strategies_account_updated ON strategies(account_fingerprint, updated_at);
CREATE TABLE IF NOT EXISTS strategy_reservations (
    account_fingerprint TEXT NOT NULL,
    instrument_id TEXT NOT NULL,
    strategy_id TEXT NOT NULL UNIQUE,
    created_at REAL NOT NULL,
    PRIMARY KEY (account_fingerprint, instrument_id)
);
"""


def encode_json(value: Any) -> str:
    return json.dumps(value, separators=(",", ":"), sort_keys=True, ensure_ascii=False)


def decode_json(value: str) -> Any:
    return json.loads(value)


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
