"""Versioned, additive identity and owner-scoped relational schema."""

from __future__ import annotations

from typing import Any


SCHEMA_VERSION = 2


_BASE_STATEMENTS = (
    """CREATE TABLE IF NOT EXISTS multiuser_schema_version (
        singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
        version INTEGER NOT NULL
    )""",
    """CREATE TABLE IF NOT EXISTS users (
        user_id TEXT PRIMARY KEY,
        username TEXT NOT NULL,
        username_normalized TEXT NOT NULL UNIQUE,
        password_hash TEXT NOT NULL,
        status TEXT NOT NULL CHECK (status IN ('PENDING_ENROLLMENT', 'ACTIVE', 'MFA_RECOVERY', 'DISABLED')),
        auth_version INTEGER NOT NULL DEFAULT 1 CHECK (auth_version >= 1),
        created_at DOUBLE PRECISION NOT NULL
    )""",
    """CREATE TABLE IF NOT EXISTS user_mfa (
        user_id TEXT PRIMARY KEY,
        key_id TEXT NOT NULL,
        nonce {BINARY} NOT NULL,
        ciphertext {BINARY} NOT NULL,
        last_totp_counter BIGINT NOT NULL DEFAULT -1,
        updated_at DOUBLE PRECISION NOT NULL,
        FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE
    )""",
    """CREATE TABLE IF NOT EXISTS user_sessions (
        session_id TEXT PRIMARY KEY,
        token_hash TEXT NOT NULL UNIQUE,
        user_id TEXT NOT NULL,
        auth_version INTEGER NOT NULL,
        auth_mode TEXT NOT NULL CHECK (auth_mode IN ('ordinary', 'enrollment', 'mfa_recovery')),
        csrf_hash TEXT,
        created_at DOUBLE PRECISION NOT NULL,
        expires_at DOUBLE PRECISION NOT NULL,
        last_seen_at DOUBLE PRECISION NOT NULL,
        revoked_at DOUBLE PRECISION,
        step_up_until DOUBLE PRECISION,
        FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
        UNIQUE (user_id, session_id)
    )""",
    """CREATE TABLE IF NOT EXISTS user_invites (
        invite_id TEXT PRIMARY KEY,
        token_hash TEXT NOT NULL UNIQUE,
        created_at DOUBLE PRECISION NOT NULL,
        expires_at DOUBLE PRECISION NOT NULL,
        revoked_at DOUBLE PRECISION,
        consumed_at DOUBLE PRECISION,
        activated_user_id TEXT,
        FOREIGN KEY (activated_user_id) REFERENCES users(user_id)
    )""",
    """CREATE TABLE IF NOT EXISTS user_mfa_enrollments (
        enrollment_id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        session_id TEXT NOT NULL,
        key_id TEXT NOT NULL,
        nonce {BINARY} NOT NULL,
        ciphertext {BINARY} NOT NULL,
        created_at DOUBLE PRECISION NOT NULL,
        expires_at DOUBLE PRECISION NOT NULL,
        completed_at DOUBLE PRECISION,
        FOREIGN KEY (user_id, session_id) REFERENCES user_sessions(user_id, session_id) ON DELETE CASCADE
    )""",
    """CREATE TABLE IF NOT EXISTS user_recovery_codes (
        user_id TEXT NOT NULL,
        code_id TEXT NOT NULL,
        code_salt {BINARY} NOT NULL,
        code_hash {BINARY} NOT NULL,
        created_at DOUBLE PRECISION NOT NULL,
        consumed_at DOUBLE PRECISION,
        PRIMARY KEY (user_id, code_id),
        FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE
    )""",
    """CREATE TABLE IF NOT EXISTS pending_recovery_codes (
        enrollment_id TEXT NOT NULL,
        code_id TEXT NOT NULL,
        code_salt {BINARY} NOT NULL,
        code_hash {BINARY} NOT NULL,
        created_at DOUBLE PRECISION NOT NULL,
        PRIMARY KEY (enrollment_id, code_id),
        FOREIGN KEY (enrollment_id) REFERENCES user_mfa_enrollments(enrollment_id) ON DELETE CASCADE
    )""",
    """CREATE TABLE IF NOT EXISTS multiuser_login_attempts (
        bucket_key TEXT PRIMARY KEY,
        window_started DOUBLE PRECISION NOT NULL,
        failures INTEGER NOT NULL CHECK (failures >= 0),
        reserved INTEGER NOT NULL DEFAULT 0 CHECK (reserved >= 0)
    )""",
    """CREATE TABLE IF NOT EXISTS multiuser_action_limits (
        bucket_key TEXT PRIMARY KEY,
        window_started BIGINT NOT NULL,
        count INTEGER NOT NULL CHECK (count >= 0)
    )""",
    """CREATE TABLE IF NOT EXISTS exchange_connections (
        user_id TEXT NOT NULL,
        connection_id TEXT NOT NULL,
        exchange TEXT NOT NULL,
        environment TEXT NOT NULL,
        region TEXT NOT NULL,
        product_capabilities_json TEXT NOT NULL DEFAULT '[]',
        nickname TEXT,
        status TEXT NOT NULL,
        remote_identity_digest TEXT NOT NULL,
        credential_version INTEGER NOT NULL DEFAULT 1,
        permission_version INTEGER NOT NULL DEFAULT 1,
        created_at DOUBLE PRECISION NOT NULL,
        updated_at DOUBLE PRECISION NOT NULL,
        PRIMARY KEY (user_id, connection_id),
        UNIQUE (connection_id),
        UNIQUE (exchange, environment, region, remote_identity_digest),
        FOREIGN KEY (user_id) REFERENCES users(user_id)
    )""",
    """CREATE TABLE IF NOT EXISTS multiuser_operations (
        user_id TEXT NOT NULL,
        connection_id TEXT NOT NULL,
        operation_id TEXT NOT NULL,
        product TEXT NOT NULL,
        idempotency_key TEXT NOT NULL,
        request_hash TEXT NOT NULL,
        status TEXT NOT NULL,
        created_at DOUBLE PRECISION NOT NULL,
        updated_at DOUBLE PRECISION NOT NULL,
        PRIMARY KEY (user_id, connection_id, operation_id),
        UNIQUE (user_id, connection_id, idempotency_key),
        FOREIGN KEY (user_id, connection_id)
            REFERENCES exchange_connections(user_id, connection_id)
    )""",
    """CREATE TABLE IF NOT EXISTS multiuser_strategies (
        user_id TEXT NOT NULL,
        connection_id TEXT NOT NULL,
        strategy_id TEXT NOT NULL,
        status TEXT NOT NULL,
        account_fingerprint TEXT NOT NULL DEFAULT '',
        contract_json TEXT NOT NULL DEFAULT '{{}}',
        snapshot_json TEXT NOT NULL DEFAULT '{{}}',
        orders_json TEXT NOT NULL DEFAULT '[]',
        results_json TEXT NOT NULL DEFAULT '[]',
        preview_hash TEXT NOT NULL DEFAULT '',
        confirmation_hash TEXT,
        prepared_expires_at DOUBLE PRECISION,
        prepared_json TEXT,
        attempt_started INTEGER NOT NULL DEFAULT 0,
        batch_attempted INTEGER NOT NULL DEFAULT 0,
        submission_mode TEXT DEFAULT 'batch',
        order_placement_attempted INTEGER NOT NULL DEFAULT 0,
        queue_json TEXT,
        execution_id TEXT,
        execution_lease_until DOUBLE PRECISION,
        replacement_source_id TEXT,
        failure_reason TEXT,
        leverage_results_json TEXT NOT NULL DEFAULT '[]',
        worker_scope TEXT NOT NULL DEFAULT 'api',
        credential_version INTEGER NOT NULL DEFAULT 1,
        permission_version INTEGER NOT NULL DEFAULT 1,
        created_at DOUBLE PRECISION NOT NULL,
        updated_at DOUBLE PRECISION NOT NULL,
        PRIMARY KEY (user_id, connection_id, strategy_id),
        FOREIGN KEY (user_id, connection_id)
            REFERENCES exchange_connections(user_id, connection_id)
    )""",
    """CREATE TABLE IF NOT EXISTS multiuser_strategy_reservations (
        user_id TEXT NOT NULL,
        connection_id TEXT NOT NULL,
        instrument_id TEXT NOT NULL,
        strategy_id TEXT NOT NULL,
        position_mode TEXT NOT NULL,
        side_scope TEXT NOT NULL,
        created_at DOUBLE PRECISION NOT NULL,
        PRIMARY KEY (user_id, connection_id, instrument_id, strategy_id),
        FOREIGN KEY (user_id, connection_id)
            REFERENCES exchange_connections(user_id, connection_id),
        FOREIGN KEY (user_id, connection_id, strategy_id)
            REFERENCES multiuser_strategies(user_id, connection_id, strategy_id)
    )""",
    """CREATE TABLE IF NOT EXISTS multiuser_credentials (
        user_id TEXT NOT NULL,
        connection_id TEXT NOT NULL,
        credential_version INTEGER NOT NULL,
        key_id TEXT NOT NULL,
        nonce {BINARY} NOT NULL,
        ciphertext {BINARY} NOT NULL,
        updated_at DOUBLE PRECISION NOT NULL,
        PRIMARY KEY (user_id, connection_id),
        FOREIGN KEY (user_id, connection_id)
            REFERENCES exchange_connections(user_id, connection_id)
    )""",
    """CREATE TABLE IF NOT EXISTS multiuser_connection_leases (
        user_id TEXT NOT NULL,
        connection_id TEXT NOT NULL,
        lease_owner TEXT,
        fence BIGINT NOT NULL DEFAULT 0,
        lease_until DOUBLE PRECISION,
        operation_id TEXT,
        updated_at DOUBLE PRECISION NOT NULL,
        PRIMARY KEY (user_id, connection_id),
        FOREIGN KEY (user_id, connection_id)
            REFERENCES exchange_connections(user_id, connection_id)
    )""",
    """CREATE TABLE IF NOT EXISTS multiuser_command_targets (
        user_id TEXT NOT NULL,
        connection_id TEXT NOT NULL,
        operation_id TEXT NOT NULL,
        target_index INTEGER NOT NULL,
        request_json TEXT NOT NULL,
        status TEXT NOT NULL,
        pre_send_at DOUBLE PRECISION,
        result_json TEXT,
        updated_at DOUBLE PRECISION NOT NULL,
        PRIMARY KEY (user_id, connection_id, operation_id, target_index),
        FOREIGN KEY (user_id, connection_id, operation_id)
            REFERENCES multiuser_operations(user_id, connection_id, operation_id)
    )""",
    """CREATE TABLE IF NOT EXISTS multiuser_operation_events (
        user_id TEXT NOT NULL,
        connection_id TEXT NOT NULL,
        operation_id TEXT NOT NULL,
        event_id TEXT NOT NULL,
        event_type TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        created_at DOUBLE PRECISION NOT NULL,
        PRIMARY KEY (user_id, connection_id, operation_id, event_id),
        FOREIGN KEY (user_id, connection_id, operation_id)
            REFERENCES multiuser_operations(user_id, connection_id, operation_id)
    )""",
    """CREATE TABLE IF NOT EXISTS multiuser_connection_events (
        user_id TEXT NOT NULL,
        connection_id TEXT NOT NULL,
        event_id TEXT NOT NULL,
        event_type TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        created_at DOUBLE PRECISION NOT NULL,
        PRIMARY KEY (user_id, connection_id, event_id),
        FOREIGN KEY (user_id, connection_id)
            REFERENCES exchange_connections(user_id, connection_id)
    )""",
    """CREATE TABLE IF NOT EXISTS multiuser_strategy_settings (
        user_id TEXT NOT NULL,
        connection_id TEXT NOT NULL,
        settings_json TEXT NOT NULL,
        preferences_json TEXT NOT NULL,
        account_fingerprint TEXT NOT NULL DEFAULT '',
        limit_order_submission_mode TEXT NOT NULL DEFAULT 'sequential',
        jev_min_structural_quality INTEGER NOT NULL DEFAULT 4,
        jev_min_entry_suitability_probability DOUBLE PRECISION NOT NULL DEFAULT 0.6,
        jev_max_failure_risk_probability DOUBLE PRECISION NOT NULL DEFAULT 0.4,
        updated_at DOUBLE PRECISION NOT NULL,
        PRIMARY KEY (user_id, connection_id),
        FOREIGN KEY (user_id, connection_id)
            REFERENCES exchange_connections(user_id, connection_id)
    )""",
    """CREATE TABLE IF NOT EXISTS multiuser_strategy_claims (
        user_id TEXT NOT NULL,
        connection_id TEXT NOT NULL,
        strategy_id TEXT NOT NULL,
        lease_owner TEXT,
        fence BIGINT NOT NULL DEFAULT 0,
        lease_until DOUBLE PRECISION,
        updated_at DOUBLE PRECISION NOT NULL,
        PRIMARY KEY (user_id, connection_id, strategy_id),
        FOREIGN KEY (user_id, connection_id, strategy_id)
            REFERENCES multiuser_strategies(user_id, connection_id, strategy_id)
    )""",
    """CREATE TABLE IF NOT EXISTS multiuser_strategy_events (
        user_id TEXT NOT NULL,
        connection_id TEXT NOT NULL,
        strategy_id TEXT NOT NULL,
        event_id TEXT NOT NULL,
        event_type TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        created_at DOUBLE PRECISION NOT NULL,
        PRIMARY KEY (user_id, connection_id, strategy_id, event_id),
        FOREIGN KEY (user_id, connection_id, strategy_id)
            REFERENCES multiuser_strategies(user_id, connection_id, strategy_id)
    )""",
    """CREATE TABLE IF NOT EXISTS multiuser_strategy_sync_state (
        user_id TEXT NOT NULL,
        connection_id TEXT NOT NULL,
        strategy_id TEXT NOT NULL,
        last_attempt_at DOUBLE PRECISION,
        last_success_at DOUBLE PRECISION,
        last_error TEXT,
        next_scan_at DOUBLE PRECISION,
        consecutive_errors INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (user_id, connection_id, strategy_id),
        FOREIGN KEY (user_id, connection_id, strategy_id)
            REFERENCES multiuser_strategies(user_id, connection_id, strategy_id)
    )""",
    """CREATE TABLE IF NOT EXISTS multiuser_identity_key_state (
        singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
        key_fingerprint TEXT,
        rotation_status TEXT NOT NULL,
        target_key_fingerprint TEXT,
        updated_at DOUBLE PRECISION NOT NULL
    )""",
)


_INDEX_STATEMENTS = (
    "CREATE INDEX IF NOT EXISTS user_sessions_owner_expiry ON user_sessions(user_id, expires_at, revoked_at)",
    "CREATE INDEX IF NOT EXISTS user_sessions_expiry ON user_sessions(expires_at)",
    "CREATE INDEX IF NOT EXISTS multiuser_action_limits_window ON multiuser_action_limits(window_started)",
    "CREATE INDEX IF NOT EXISTS mfa_enrollments_owner_expiry ON user_mfa_enrollments(user_id, expires_at)",
    "CREATE INDEX IF NOT EXISTS recovery_codes_owner_consumed ON user_recovery_codes(user_id, consumed_at)",
    "CREATE INDEX IF NOT EXISTS connections_owner_status_updated ON exchange_connections(user_id, status, updated_at, connection_id)",
    "CREATE INDEX IF NOT EXISTS multiuser_operations_owner_status_created ON multiuser_operations(user_id, connection_id, status, created_at, operation_id)",
    "CREATE INDEX IF NOT EXISTS multiuser_strategies_owner_status_updated ON multiuser_strategies(user_id, connection_id, status, updated_at, strategy_id)",
    "CREATE INDEX IF NOT EXISTS multiuser_strategies_owner_fingerprint ON multiuser_strategies(user_id, connection_id, account_fingerprint, created_at, strategy_id)",
    "CREATE INDEX IF NOT EXISTS multiuser_reservations_owner_scope ON multiuser_strategy_reservations(user_id, connection_id, instrument_id, position_mode, side_scope)",
    "CREATE INDEX IF NOT EXISTS multiuser_targets_owner_status ON multiuser_command_targets(user_id, connection_id, status, operation_id)",
    "CREATE INDEX IF NOT EXISTS multiuser_operation_events_owner_created ON multiuser_operation_events(user_id, connection_id, operation_id, created_at)",
    "CREATE INDEX IF NOT EXISTS multiuser_connection_events_owner_created ON multiuser_connection_events(user_id, connection_id, created_at)",
    "CREATE INDEX IF NOT EXISTS multiuser_strategy_events_owner_created ON multiuser_strategy_events(user_id, connection_id, strategy_id, created_at)",
)


_ADDITIVE_COLUMNS = {
    "exchange_connections": (
        ("remote_identity_nonce", "{BINARY}"),
        ("remote_identity_ciphertext", "{BINARY}"),
        ("identity_vault_key_id", "TEXT"),
        ("verified_at", "DOUBLE PRECISION"),
    ),
    "multiuser_operations": (
        ("payload_json", "TEXT"),
        ("connection_version", "INTEGER"),
        ("credential_version", "INTEGER NOT NULL DEFAULT 1"),
        ("permission_version", "INTEGER NOT NULL DEFAULT 1"),
        ("expires_at", "DOUBLE PRECISION"),
        ("confirmation_digest", "TEXT"),
        ("confirmation_used_at", "DOUBLE PRECISION"),
        ("lease_owner", "TEXT"),
        ("lease_fence", "BIGINT"),
        ("lease_until", "DOUBLE PRECISION"),
        ("pre_send_at", "DOUBLE PRECISION"),
        ("result_json", "TEXT"),
        ("failure_code", "TEXT"),
    ),
    "multiuser_strategies": (
        ("strategy_json", "TEXT"),
        ("settings_json", "TEXT"),
        ("preferences_json", "TEXT"),
        ("connection_version", "INTEGER"),
        ("lease_owner", "TEXT"),
        ("lease_fence", "BIGINT"),
        ("lease_until", "DOUBLE PRECISION"),
        ("pre_send_at", "DOUBLE PRECISION"),
        ("account_fingerprint", "TEXT NOT NULL DEFAULT ''"),
        ("contract_json", "TEXT NOT NULL DEFAULT '{{}}'"),
        ("snapshot_json", "TEXT NOT NULL DEFAULT '{{}}'"),
        ("orders_json", "TEXT NOT NULL DEFAULT '[]'"),
        ("results_json", "TEXT NOT NULL DEFAULT '[]'"),
        ("preview_hash", "TEXT NOT NULL DEFAULT ''"),
        ("confirmation_hash", "TEXT"),
        ("prepared_expires_at", "DOUBLE PRECISION"),
        ("prepared_json", "TEXT"),
        ("attempt_started", "INTEGER NOT NULL DEFAULT 0"),
        ("batch_attempted", "INTEGER NOT NULL DEFAULT 0"),
        ("submission_mode", "TEXT DEFAULT 'batch'"),
        ("order_placement_attempted", "INTEGER NOT NULL DEFAULT 0"),
        ("queue_json", "TEXT"),
        ("execution_id", "TEXT"),
        ("execution_lease_until", "DOUBLE PRECISION"),
        ("replacement_source_id", "TEXT"),
        ("failure_reason", "TEXT"),
        ("leverage_results_json", "TEXT NOT NULL DEFAULT '[]'"),
        ("worker_scope", "TEXT NOT NULL DEFAULT 'api'"),
        ("credential_version", "INTEGER NOT NULL DEFAULT 1"),
        ("permission_version", "INTEGER NOT NULL DEFAULT 1"),
    ),
    "multiuser_strategy_reservations": (
        ("account_fingerprint", "TEXT NOT NULL DEFAULT ''"),
    ),
    "multiuser_strategy_settings": (
        ("account_fingerprint", "TEXT NOT NULL DEFAULT ''"),
        ("limit_order_submission_mode", "TEXT NOT NULL DEFAULT 'sequential'"),
        ("jev_min_structural_quality", "INTEGER NOT NULL DEFAULT 4"),
        ("jev_min_entry_suitability_probability", "DOUBLE PRECISION NOT NULL DEFAULT 0.6"),
        ("jev_max_failure_risk_probability", "DOUBLE PRECISION NOT NULL DEFAULT 0.4"),
    ),
}


def statements_for(dialect: str) -> tuple[str, ...]:
    if dialect not in {"sqlite", "postgresql"}:
        raise ValueError("unsupported identity-store dialect")
    binary_type = "BLOB" if dialect == "sqlite" else "BYTEA"
    statements = (*_BASE_STATEMENTS, *_INDEX_STATEMENTS)
    return tuple(statement.format(BINARY=binary_type) for statement in statements)


def ensure_schema(connection: Any, dialect: str) -> None:
    if dialect == "postgresql":
        # The store wraps initialization in a transaction, so this serializes
        # schema inspection and every additive DDL step across app processes.
        connection.execute("SELECT pg_advisory_xact_lock(174923118, 11102)")
        exists = connection.execute(
            "SELECT to_regclass('multiuser_schema_version') AS table_name"
        ).fetchone()
        has_version = exists is not None and exists["table_name"] is not None
    else:
        exists = connection.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='multiuser_schema_version'"
        ).fetchone()
        has_version = exists is not None
    if has_version:
        existing_version = connection.execute(
            "SELECT version FROM multiuser_schema_version WHERE singleton=1"
        ).fetchone()
        if existing_version is not None and int(existing_version["version"]) > SCHEMA_VERSION:
            raise RuntimeError("multi-user schema is newer than this application")
    statements = statements_for(dialect)
    base_statement_count = len(_BASE_STATEMENTS)
    for statement in statements[:base_statement_count]:
        connection.execute(statement)
    for table, columns in _ADDITIVE_COLUMNS.items():
        for column, data_type in columns:
            if dialect == "sqlite":
                present = {
                    str(row["name"])
                    for row in connection.execute(f"PRAGMA table_info({table})").fetchall()
                }
            else:
                present = {
                    str(row["column_name"])
                    for row in connection.execute(
                        "SELECT column_name FROM information_schema.columns "
                        "WHERE table_schema=current_schema() AND table_name=?",
                        (table,),
                    ).fetchall()
                }
            if column not in present:
                connection.execute(
                    f"ALTER TABLE {table} ADD COLUMN {column} {data_type.format(BINARY='BLOB' if dialect == 'sqlite' else 'BYTEA')}"
                )
    for statement in statements[base_statement_count:]:
        connection.execute(statement)
    connection.execute(
        "INSERT INTO multiuser_schema_version(singleton, version) VALUES (1, ?) "
        "ON CONFLICT(singleton) DO UPDATE SET version=excluded.version",
        (SCHEMA_VERSION,),
    )
