"""Versioned, additive identity and owner-scoped relational schema."""

from __future__ import annotations

from typing import Any


SCHEMA_VERSION = 1


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
    "CREATE INDEX IF NOT EXISTS user_sessions_owner_expiry ON user_sessions(user_id, expires_at, revoked_at)",
    "CREATE INDEX IF NOT EXISTS user_sessions_expiry ON user_sessions(expires_at)",
    "CREATE INDEX IF NOT EXISTS mfa_enrollments_owner_expiry ON user_mfa_enrollments(user_id, expires_at)",
    "CREATE INDEX IF NOT EXISTS recovery_codes_owner_consumed ON user_recovery_codes(user_id, consumed_at)",
    "CREATE INDEX IF NOT EXISTS connections_owner_status_updated ON exchange_connections(user_id, status, updated_at, connection_id)",
    "CREATE INDEX IF NOT EXISTS multiuser_operations_owner_status_created ON multiuser_operations(user_id, connection_id, status, created_at, operation_id)",
    "CREATE INDEX IF NOT EXISTS multiuser_strategies_owner_status_updated ON multiuser_strategies(user_id, connection_id, status, updated_at, strategy_id)",
    "CREATE INDEX IF NOT EXISTS multiuser_reservations_owner_scope ON multiuser_strategy_reservations(user_id, connection_id, instrument_id, position_mode, side_scope)",
)


def statements_for(dialect: str) -> tuple[str, ...]:
    if dialect not in {"sqlite", "postgresql"}:
        raise ValueError("unsupported identity-store dialect")
    binary_type = "BLOB" if dialect == "sqlite" else "BYTEA"
    return tuple(statement.format(BINARY=binary_type) for statement in _BASE_STATEMENTS)


def ensure_schema(connection: Any, dialect: str) -> None:
    for statement in statements_for(dialect):
        connection.execute(statement)
    connection.execute(
        "INSERT INTO multiuser_schema_version(singleton, version) VALUES (1, ?) "
        "ON CONFLICT(singleton) DO NOTHING",
        (SCHEMA_VERSION,),
    )
