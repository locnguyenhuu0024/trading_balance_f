"""Owner-first exchange connection lifecycle and remote identity ledger."""

from __future__ import annotations

import hashlib
import hmac
import json
import uuid
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any, Callable

from .account_context import (
    AccountContextError,
    SUPPORTED_ENVIRONMENTS,
    SUPPORTED_EXCHANGES,
    SUPPORTED_REGIONS,
    VerifiedExchangeIdentity,
    create_exchange_client,
    verify_exchange_identity,
)
from .credential_vault import CredentialVault
from .principal import Principal
from .security import CryptoInvalidCiphertext, CryptoUnavailable
from .store_contract import IdentityStoreConflict, IdentityStoreUnavailable


class ConnectionServiceError(Exception):
    def __init__(self, status: int, code: str, message: str, *, headers: list[tuple[str, str]] | None = None):
        super().__init__(message)
        self.status = status
        self.code = code
        self.message = message
        self.headers = headers or []


@dataclass(frozen=True, slots=True)
class ConnectionContext:
    user_id: str
    connection_id: str
    exchange: str
    environment: str
    region: str
    credential_version: int
    permission_version: int
    capabilities: tuple[str, ...]
    remote_identity_digest: str
    client: Any


class OwnedConnections:
    """All queries and lifecycle writes are scoped to a validated owner."""

    def __init__(
        self,
        store: Any,
        vault: CredentialVault,
        remote_identity_key: bytes,
        *,
        transport: Any = None,
        clock: Callable[[], float],
        trade_enabled: bool = False,
    ):
        if not isinstance(remote_identity_key, bytes) or len(remote_identity_key) != 32:
            raise ValueError("remote identity key must be 32 bytes")
        self.store = store
        self.vault = vault
        self._remote_identity_key = bytes(remote_identity_key)
        self._transport = transport
        self._clock = clock
        self._trade_enabled = trade_enabled

    @property
    def key_fingerprint(self) -> str:
        return hmac.new(
            self._remote_identity_key, b"trading-balance-f/remote-identity-key-id/v1", hashlib.sha256
        ).hexdigest()

    def _identity_digest(self, exchange: str, environment: str, region: str, uid: str, key: bytes | None = None) -> str:
        secret = self._remote_identity_key if key is None else key
        message = b"\x00".join(
            (b"v1", exchange.encode("ascii"), environment.encode("ascii"), region.encode("ascii"), uid.encode("ascii"))
        )
        return hmac.new(secret, message, hashlib.sha256).hexdigest()

    def _lock_suffix(self) -> str:
        return " FOR UPDATE" if self.store.dialect == "postgresql" else ""

    def _require_principal(self, connection: Any, principal: Principal, now: float | None = None, *, step_up: bool) -> Any:
        if principal.mode != "ordinary":
            raise ConnectionServiceError(403, "step_up_required", "An ordinary authenticated session is required.")
        suffix = self._lock_suffix()
        user = connection.execute(
            "SELECT status, auth_version FROM users WHERE user_id=?" + suffix, (principal.user_id,)
        ).fetchone()
        session = connection.execute(
            "SELECT user_id, auth_version, auth_mode, created_at, expires_at, last_seen_at, revoked_at, step_up_until "
            "FROM user_sessions WHERE session_id=?" + suffix,
            (principal.session_id,),
        ).fetchone()
        # Read the clock after obtaining the persisted identity locks. A caller
        # cannot carry a pre-upstream or pre-lock timestamp into a mutation.
        now = self._clock()
        if (
            user is None or session is None or user["status"] != "ACTIVE"
            or int(user["auth_version"]) != principal.auth_version
            or session["user_id"] != principal.user_id
            or int(session["auth_version"]) != principal.auth_version
            or session["auth_mode"] != "ordinary"
            or session["revoked_at"] is not None
            or float(session["expires_at"]) <= now
            or now - float(session["last_seen_at"]) >= 30 * 60
        ):
            raise ConnectionServiceError(401, "authentication_required", "A valid session is required.")
        if step_up and (
            session["step_up_until"] is None
            or float(session["step_up_until"]) <= now
            or float(session["step_up_until"]) > float(session["expires_at"])
        ):
            raise ConnectionServiceError(403, "step_up_required", "Recent step-up authentication is required.")
        return session

    def list_owned(self, principal: Principal) -> list[dict[str, Any]]:
        now = self._clock()
        with self.store.transaction() as connection:
            self._require_principal(connection, principal, now, step_up=False)
            rows = connection.execute(
                "SELECT connection_id, exchange, environment, region, product_capabilities_json, nickname, status, "
                "credential_version, permission_version, created_at, updated_at, verified_at "
                "FROM exchange_connections WHERE user_id=? ORDER BY created_at, connection_id",
                (principal.user_id,),
            ).fetchall()
        return [self._public_connection(row) for row in rows]

    @staticmethod
    def _public_connection(row: Any) -> dict[str, Any]:
        try:
            capabilities = json.loads(row["product_capabilities_json"])
        except (TypeError, ValueError):
            capabilities = []
        def timestamp(value: Any) -> str:
            return datetime.fromtimestamp(float(value), tz=timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")

        return {
            "connectionId": str(row["connection_id"]),
            "exchange": str(row["exchange"]),
            "environment": str(row["environment"]),
            "region": str(row["region"]),
            "capabilities": capabilities if isinstance(capabilities, list) else [],
            "nickname": row["nickname"],
            "status": str(row["status"]),
            "credentialVersion": int(row["credential_version"]),
            "permissionVersion": int(row["permission_version"]),
            "createdAt": timestamp(row["created_at"]),
            "updatedAt": timestamp(row["updated_at"]),
            "verifiedAt": None if row["verified_at"] is None else timestamp(row["verified_at"]),
        }

    def _lock_identity_key_state(self, connection: Any, now: float, *, allow_initialize: bool) -> Any:
        suffix = self._lock_suffix()
        state = connection.execute(
            "SELECT key_fingerprint, rotation_status, target_key_fingerprint "
            "FROM multiuser_identity_key_state WHERE singleton=1" + suffix
        ).fetchone()
        if state is None and allow_initialize:
            count = connection.execute("SELECT COUNT(*) AS count FROM exchange_connections").fetchone()
            if int(count["count"]) != 0:
                connection.execute(
                    "INSERT INTO multiuser_identity_key_state(singleton, key_fingerprint, rotation_status, "
                    "target_key_fingerprint, updated_at) VALUES (1, NULL, 'ROTATION_REQUIRED', NULL, ?)",
                    (now,),
                )
            else:
                connection.execute(
                    "INSERT INTO multiuser_identity_key_state(singleton, key_fingerprint, rotation_status, "
                    "target_key_fingerprint, updated_at) VALUES (1, ?, 'ACTIVE', NULL, ?)",
                    (self.key_fingerprint, now),
                )
            state = connection.execute(
                "SELECT key_fingerprint, rotation_status, target_key_fingerprint "
                "FROM multiuser_identity_key_state WHERE singleton=1" + suffix
            ).fetchone()
        if (
            state is None or state["rotation_status"] != "ACTIVE"
            or state["key_fingerprint"] != self.key_fingerprint
        ):
            raise ConnectionServiceError(
                503, "identity_key_rotation_required", "Remote identity indexing is paused pending key rotation."
            )
        return state

    def _connection_row(self, connection: Any, user_id: str, connection_id: str, *, lock: bool) -> Any:
        suffix = self._lock_suffix() if lock else ""
        return connection.execute(
            "SELECT * FROM exchange_connections WHERE user_id=? AND connection_id=?" + suffix,
            (user_id, connection_id),
        ).fetchone()

    def _active_connection_lease(self, connection: Any, user_id: str, connection_id: str, now: float) -> bool:
        lease = connection.execute(
            "SELECT lease_until FROM multiuser_connection_leases WHERE user_id=? AND connection_id=?" + self._lock_suffix(),
            (user_id, connection_id),
        ).fetchone()
        return bool(lease is not None and lease["lease_until"] is not None and float(lease["lease_until"]) > now)

    @staticmethod
    def _has_unresolved_activity(connection: Any, user_id: str, connection_id: str, now: float) -> bool:
        if connection.execute(
            "SELECT 1 FROM multiuser_command_targets WHERE user_id=? AND connection_id=? "
            "AND status IN ('ATTEMPT_STARTED', 'UNKNOWN') LIMIT 1",
            (user_id, connection_id),
        ).fetchone() is not None:
            return True
        if connection.execute(
            "SELECT 1 FROM multiuser_operations WHERE user_id=? AND connection_id=? "
            "AND status IN ('UNKNOWN', 'SENDING') AND pre_send_at IS NOT NULL LIMIT 1",
            (user_id, connection_id),
        ).fetchone() is not None:
            return True
        if connection.execute(
            "SELECT 1 FROM multiuser_strategy_claims WHERE user_id=? AND connection_id=? "
            "AND lease_until>? LIMIT 1",
            (user_id, connection_id, now),
        ).fetchone() is not None:
            return True
        if connection.execute(
            "SELECT 1 FROM multiuser_strategies WHERE user_id=? AND connection_id=? "
            "AND status IN ('APPLYING', 'UNKNOWN', 'RECONCILING', 'QUEUED', 'PREPARED') LIMIT 1",
            (user_id, connection_id),
        ).fetchone() is not None:
            return True
        return connection.execute(
            "SELECT 1 FROM multiuser_strategy_reservations WHERE user_id=? AND connection_id=? LIMIT 1",
            (user_id, connection_id),
        ).fetchone() is not None

    def _credentials(self, connection: Any, row: Any) -> dict[str, str]:
        record = connection.execute(
            "SELECT credential_version, key_id, nonce, ciphertext FROM multiuser_credentials "
            "WHERE user_id=? AND connection_id=?",
            (row["user_id"], row["connection_id"]),
        ).fetchone()
        if record is None or int(record["credential_version"]) != int(row["credential_version"]):
            raise ConnectionServiceError(409, "credentials_unavailable", "The exchange credentials need to be reconnected.")
        try:
            return self.vault.decrypt_credentials(
                str(record["key_id"]), bytes(record["nonce"]), bytes(record["ciphertext"]),
                user_id=str(row["user_id"]), connection_id=str(row["connection_id"]),
                exchange=str(row["exchange"]), credential_version=int(row["credential_version"]),
                environment=str(row["environment"]), region=str(row["region"]),
            )
        except CryptoUnavailable:
            raise
        except CryptoInvalidCiphertext:
            raise ConnectionServiceError(503, "credentials_unavailable", "The exchange credentials are unavailable.") from None

    def _new_client(self, credentials: dict[str, str], *, exchange: str, environment: str, region: str) -> Any:
        try:
            return create_exchange_client(
                credentials, exchange=exchange, environment=environment, region=region,
                transport=self._transport, clock=self._clock,
            )
        except AccountContextError as error:
            raise ConnectionServiceError(400, "connection_invalid", str(error)) from None

    def _verify(self, client: Any) -> VerifiedExchangeIdentity:
        try:
            return verify_exchange_identity(client)
        except AccountContextError as error:
            raise ConnectionServiceError(
                error.status, error.code, str(error), headers=error.headers
            ) from None

    @staticmethod
    def _requested_context(body: dict[str, Any]) -> tuple[str, str, str, str | None]:
        exchange = body.get("exchange", "OKX")
        environment = body.get("environment")
        region = body.get("region")
        nickname = body.get("nickname")
        if exchange not in SUPPORTED_EXCHANGES:
            raise ConnectionServiceError(400, "connection_invalid", "Only the supported exchange is available.")
        if environment not in SUPPORTED_ENVIRONMENTS:
            raise ConnectionServiceError(400, "connection_invalid", "The exchange environment is invalid.")
        if region not in SUPPORTED_REGIONS:
            raise ConnectionServiceError(400, "connection_invalid", "The exchange region is not supported.")
        if nickname is not None and (not isinstance(nickname, str) or len(nickname.strip()) > 64):
            raise ConnectionServiceError(400, "connection_invalid", "The connection nickname is invalid.")
        return exchange, environment, region, nickname.strip() if isinstance(nickname, str) and nickname.strip() else None

    def _event(self, connection: Any, user_id: str, connection_id: str, event_type: str, now: float) -> None:
        connection.execute(
            "INSERT INTO multiuser_connection_events(user_id, connection_id, event_id, event_type, payload_json, created_at) "
            "VALUES (?, ?, ?, ?, '{}', ?)",
            (user_id, connection_id, uuid.uuid4().hex, event_type, now),
        )

    def create(self, principal: Principal, body: dict[str, Any]) -> dict[str, Any]:
        exchange, environment, region, nickname = self._requested_context(body)
        fields = ("apiKey", "apiSecret", "passphrase") if exchange == "OKX" else ("apiKey", "apiSecret")
        credentials = {key: body.get(key) for key in fields}
        connection_id = uuid.uuid4().hex
        now = self._clock()
        with self.store.transaction() as connection:
            self._require_principal(connection, principal, now, step_up=True)
        if exchange == "BINANCE" and "passphrase" in body:
            raise ConnectionServiceError(400, "connection_invalid", "The exchange credential schema is invalid.")
        credential_nonce, credential_ciphertext = self.vault.encrypt_credentials(
            credentials, user_id=principal.user_id, connection_id=connection_id,
            exchange=exchange, credential_version=1, environment=environment, region=region,
        )
        client = self._new_client(credentials, exchange=exchange, environment=environment, region=region)
        identity = self._verify(client)
        digest = self._identity_digest(exchange, environment, region, identity.uid)
        identity_nonce, identity_ciphertext = self.vault.encrypt_remote_identity(
            identity.uid, user_id=principal.user_id, connection_id=connection_id, exchange=exchange,
            environment=environment, region=region,
        )
        capabilities = list(identity.capabilities)
        if not self._trade_enabled:
            capabilities = [value for value in capabilities if value != "trade"]
        status = "ACTIVE"
        try:
            with self.store.transaction() as connection:
                self._require_principal(connection, principal, now, step_up=True)
                self._lock_identity_key_state(connection, now, allow_initialize=True)
                existing = connection.execute(
                    "SELECT user_id, connection_id, credential_version, permission_version, status, "
                    "product_capabilities_json FROM exchange_connections WHERE exchange=? AND environment=? "
                    "AND region=? AND remote_identity_digest=?" + self._lock_suffix(),
                    (exchange, environment, region, digest),
                ).fetchone()
                if existing is not None and existing["user_id"] != principal.user_id:
                    raise ConnectionServiceError(409, "connection_conflict", "This exchange account is already connected.")
                if existing is not None:
                    connection_id = str(existing["connection_id"])
                    active_lease = self._active_connection_lease(
                        connection, principal.user_id, connection_id, now
                    )
                    unresolved = self._has_unresolved_activity(
                        connection, principal.user_id, connection_id, now
                    )
                    status = "RECONCILING" if active_lease or unresolved else "ACTIVE"
                    self._require_principal(connection, principal, self._clock(), step_up=True)
                    now = self._clock()
                    credential_version = int(existing["credential_version"]) + 1
                    prior_caps = json.loads(existing["product_capabilities_json"] or "[]")
                    permission_version = int(existing["permission_version"]) + int(prior_caps != capabilities)
                    identity_nonce, identity_ciphertext = self.vault.encrypt_remote_identity(
                        identity.uid, user_id=principal.user_id, connection_id=connection_id, exchange=exchange,
                        environment=environment, region=region,
                    )
                    credential_nonce, credential_ciphertext = self.vault.encrypt_credentials(
                        credentials, user_id=principal.user_id, connection_id=connection_id,
                        exchange=exchange, credential_version=credential_version,
                        environment=environment, region=region,
                    )
                    connection.execute(
                        "UPDATE exchange_connections SET product_capabilities_json=?, nickname=?, status=?, "
                        "remote_identity_nonce=?, remote_identity_ciphertext=?, identity_vault_key_id=?, "
                        "credential_version=?, permission_version=?, verified_at=?, updated_at=? "
                        "WHERE user_id=? AND connection_id=?",
                        (json.dumps(capabilities, separators=(",", ":")), nickname, status,
                         identity_nonce, identity_ciphertext, self.vault.key_id, credential_version,
                         permission_version, now, now, principal.user_id, connection_id),
                    )
                    event_type = "connection_reactivated"
                else:
                    self._require_principal(connection, principal, self._clock(), step_up=True)
                    now = self._clock()
                    credential_version = 1
                    permission_version = 1
                    connection.execute(
                        "INSERT INTO exchange_connections(user_id, connection_id, exchange, environment, region, "
                        "product_capabilities_json, nickname, status, remote_identity_digest, credential_version, "
                        "permission_version, created_at, updated_at, remote_identity_nonce, remote_identity_ciphertext, "
                        "identity_vault_key_id, verified_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                        (principal.user_id, connection_id, exchange, environment, region,
                         json.dumps(capabilities, separators=(",", ":")), nickname, status, digest,
                         credential_version, permission_version, now, now, identity_nonce,
                         identity_ciphertext, self.vault.key_id, now),
                    )
                    event_type = "connection_created"
                connection.execute(
                    "INSERT INTO multiuser_credentials(user_id, connection_id, credential_version, key_id, nonce, ciphertext, updated_at) "
                    "VALUES (?, ?, ?, ?, ?, ?, ?) ON CONFLICT(user_id, connection_id) DO UPDATE SET "
                    "credential_version=excluded.credential_version, key_id=excluded.key_id, nonce=excluded.nonce, "
                    "ciphertext=excluded.ciphertext, updated_at=excluded.updated_at",
                    (principal.user_id, connection_id, credential_version, self.vault.key_id,
                     credential_nonce, credential_ciphertext, now),
                )
                connection.execute(
                    "INSERT INTO multiuser_connection_leases(user_id, connection_id, updated_at) VALUES (?, ?, ?) "
                    "ON CONFLICT(user_id, connection_id) DO NOTHING",
                    (principal.user_id, connection_id, now),
                )
                self._event(connection, principal.user_id, connection_id, event_type, now)
                row = self._connection_row(connection, principal.user_id, connection_id, lock=False)
        except IdentityStoreConflict:
            raise ConnectionServiceError(409, "connection_conflict", "This exchange account is already connected.") from None
        return self._public_connection(row)

    def _load_owned_client(
        self, principal: Principal, connection_id: str, *, step_up: bool = False
    ) -> tuple[Any, dict[str, str], int, int, Any]:
        now = self._clock()
        with self.store.transaction() as connection:
            self._require_principal(connection, principal, now, step_up=step_up)
            row = self._connection_row(connection, principal.user_id, connection_id, lock=False)
            if row is None:
                raise ConnectionServiceError(404, "not_found", "The requested resource was not found.")
            if row["status"] in {"REVOKED", "REVOKING"}:
                raise ConnectionServiceError(409, "connection_unavailable", "The exchange connection is unavailable.")
            credentials = self._credentials(connection, row)
            client = self._new_client(
                credentials, exchange=str(row["exchange"]), environment=str(row["environment"]), region=str(row["region"])
            )
            return row, credentials, int(row["credential_version"]), int(row["permission_version"]), client

    def verify_connection(self, principal: Principal, connection_id: str) -> dict[str, Any]:
        row, _, credential_version, permission_version, client = self._load_owned_client(
            principal, connection_id, step_up=True
        )
        identity = self._verify(client)
        digest = self._identity_digest(str(row["exchange"]), str(row["environment"]), str(row["region"]), identity.uid)
        if not hmac.compare_digest(digest, str(row["remote_identity_digest"])):
            raise ConnectionServiceError(409, "account_changed", "The credentials resolve to a different exchange account.")
        capabilities = list(identity.capabilities)
        if not self._trade_enabled:
            capabilities = [value for value in capabilities if value != "trade"]
        now = self._clock()
        try:
            with self.store.transaction() as connection:
                self._require_principal(connection, principal, now, step_up=True)
                current = self._connection_row(connection, principal.user_id, connection_id, lock=True)
                if (
                    current is None
                    or int(current["credential_version"]) != credential_version
                    or int(current["permission_version"]) != permission_version
                    or current["status"] in {"REVOKED", "REVOKING"}
                ):
                    raise ConnectionServiceError(409, "connection_changed", "The connection changed during verification.")
                if self._active_connection_lease(connection, principal.user_id, connection_id, self._clock()):
                    raise ConnectionServiceError(409, "connection_busy", "An exchange operation is still active.")
                unresolved = self._has_unresolved_activity(
                    connection, principal.user_id, connection_id, self._clock()
                )
                self._require_principal(connection, principal, self._clock(), step_up=True)
                now = self._clock()
                prior = json.loads(current["product_capabilities_json"] or "[]")
                next_permission_version = permission_version + int(prior != capabilities)
                next_status = "RECONCILING" if unresolved else "ACTIVE"
                connection.execute(
                    "UPDATE exchange_connections SET product_capabilities_json=?, status=?, permission_version=?, "
                    "verified_at=?, updated_at=? WHERE user_id=? AND connection_id=?",
                    (json.dumps(capabilities, separators=(",", ":")), next_status, next_permission_version,
                     now, now, principal.user_id, connection_id),
                )
                self._event(connection, principal.user_id, connection_id, "connection_verified", now)
                result = self._public_connection(self._connection_row(connection, principal.user_id, connection_id, lock=False))
        except IdentityStoreConflict:
            raise ConnectionServiceError(409, "connection_changed", "The connection changed during verification.") from None
        return result

    def rotate_credentials(self, principal: Principal, connection_id: str, body: dict[str, Any]) -> dict[str, Any]:
        now = self._clock()
        with self.store.transaction() as connection:
            self._require_principal(connection, principal, now, step_up=True)
            row = self._connection_row(connection, principal.user_id, connection_id, lock=False)
            if row is None:
                raise ConnectionServiceError(404, "not_found", "The requested resource was not found.")
            if row["status"] in {"REVOKED", "REVOKING"}:
                raise ConnectionServiceError(409, "connection_unavailable", "The exchange connection is unavailable.")
            prior_version = int(row["credential_version"])
            prior_permission = int(row["permission_version"])
            exchange, environment, region = str(row["exchange"]), str(row["environment"]), str(row["region"])
            fields = ("apiKey", "apiSecret", "passphrase") if exchange == "OKX" else ("apiKey", "apiSecret")
            credentials = {key: body.get(key) for key in fields}
        if exchange == "BINANCE" and "passphrase" in body:
            raise ConnectionServiceError(400, "connection_invalid", "The exchange credential schema is invalid.")
        client = self._new_client(credentials, exchange=exchange, environment=environment, region=region)
        identity = self._verify(client)
        digest = self._identity_digest(exchange, environment, region, identity.uid)
        if not hmac.compare_digest(digest, str(row["remote_identity_digest"])):
            raise ConnectionServiceError(409, "account_changed", "Credential rotation must resolve to the same exchange account.")
        next_version = prior_version + 1
        nonce, ciphertext = self.vault.encrypt_credentials(
            credentials, user_id=principal.user_id, connection_id=connection_id, exchange=exchange,
            credential_version=next_version, environment=environment, region=region,
        )
        capabilities = list(identity.capabilities)
        if not self._trade_enabled:
            capabilities = [value for value in capabilities if value != "trade"]
        with self.store.transaction() as connection:
            self._require_principal(connection, principal, now, step_up=True)
            current = self._connection_row(connection, principal.user_id, connection_id, lock=True)
            if (
                current is None or int(current["credential_version"]) != prior_version
                or int(current["permission_version"]) != prior_permission
            ):
                raise ConnectionServiceError(409, "connection_changed", "The connection changed during credential rotation.")
            lease = connection.execute(
                "SELECT lease_until FROM multiuser_connection_leases WHERE user_id=? AND connection_id=?" + self._lock_suffix(),
                (principal.user_id, connection_id),
            ).fetchone()
            if lease is not None and lease["lease_until"] is not None and float(lease["lease_until"]) > now:
                raise ConnectionServiceError(409, "connection_busy", "An exchange operation is still active.")
            unresolved = self._has_unresolved_activity(connection, principal.user_id, connection_id, now)
            self._require_principal(connection, principal, self._clock(), step_up=True)
            now = self._clock()
            status = "RECONCILING" if unresolved else "ACTIVE"
            prior_caps = json.loads(current["product_capabilities_json"] or "[]")
            next_permission_version = prior_permission + int(prior_caps != capabilities)
            connection.execute(
                "UPDATE exchange_connections SET credential_version=?, permission_version=?, "
                "product_capabilities_json=?, status=?, verified_at=?, updated_at=? "
                "WHERE user_id=? AND connection_id=? AND credential_version=? AND permission_version=?",
                (next_version, next_permission_version, json.dumps(capabilities, separators=(",", ":")),
                 status, now, now, principal.user_id, connection_id, prior_version, prior_permission),
            )
            connection.execute(
                "UPDATE multiuser_credentials SET credential_version=?, key_id=?, nonce=?, ciphertext=?, updated_at=? "
                "WHERE user_id=? AND connection_id=? AND credential_version=?",
                (next_version, self.vault.key_id, nonce, ciphertext, now, principal.user_id, connection_id, prior_version),
            )
            self._event(connection, principal.user_id, connection_id, "credentials_rotated", now)
            return self._public_connection(self._connection_row(connection, principal.user_id, connection_id, lock=False))

    def revoke(self, principal: Principal, connection_id: str) -> dict[str, Any]:
        now = self._clock()
        with self.store.transaction() as connection:
            self._require_principal(connection, principal, now, step_up=True)
            row = self._connection_row(connection, principal.user_id, connection_id, lock=True)
            if row is None:
                raise ConnectionServiceError(404, "not_found", "The requested resource was not found.")
            lease = connection.execute(
                "SELECT lease_until FROM multiuser_connection_leases WHERE user_id=? AND connection_id=?" + self._lock_suffix(),
                (principal.user_id, connection_id),
            ).fetchone()
            unresolved = connection.execute(
                "SELECT 1 FROM multiuser_command_targets WHERE user_id=? AND connection_id=? "
                "AND status IN ('ATTEMPT_STARTED', 'UNKNOWN') LIMIT 1",
                (principal.user_id, connection_id),
            ).fetchone()
            active_lease = lease is not None and lease["lease_until"] is not None and float(lease["lease_until"]) > now
            unresolved_activity = self._has_unresolved_activity(connection, principal.user_id, connection_id, now)
            self._require_principal(connection, principal, self._clock(), step_up=True)
            now = self._clock()
            status = "RECONCILING" if active_lease or unresolved is not None or unresolved_activity else "REVOKED"
            connection.execute(
                "UPDATE multiuser_command_targets SET status='CANCELED', updated_at=? WHERE user_id=? "
                "AND connection_id=? AND status='PREPARED' AND pre_send_at IS NULL",
                (now, principal.user_id, connection_id),
            )
            connection.execute(
                "UPDATE multiuser_operations SET status='CANCELED', updated_at=? WHERE user_id=? AND connection_id=? "
                "AND pre_send_at IS NULL AND status IN ('PREPARED', 'READY')",
                (now, principal.user_id, connection_id),
            )
            connection.execute(
                "DELETE FROM multiuser_credentials WHERE user_id=? AND connection_id=?",
                (principal.user_id, connection_id),
            )
            connection.execute(
                "UPDATE exchange_connections SET status=?, product_capabilities_json='[]', "
                "credential_version=credential_version+1, permission_version=permission_version+1, updated_at=? "
                "WHERE user_id=? AND connection_id=?",
                (status, now, principal.user_id, connection_id),
            )
            self._event(connection, principal.user_id, connection_id, "connection_revoked", now)
            return self._public_connection(self._connection_row(connection, principal.user_id, connection_id, lock=False))

    def account_context(
        self, principal: Principal, connection_id: str, *, step_up: bool = False
    ) -> ConnectionContext:
        row, credentials, credential_version, permission_version, _ = self._load_owned_client(
            principal, connection_id, step_up=step_up
        )
        client = self._new_client(
            credentials, exchange=str(row["exchange"]), environment=str(row["environment"]), region=str(row["region"])
        )
        capabilities = json.loads(row["product_capabilities_json"] or "[]")
        return ConnectionContext(
            principal.user_id, connection_id, str(row["exchange"]), str(row["environment"]),
            str(row["region"]), credential_version, permission_version,
            tuple(value for value in capabilities if isinstance(value, str)),
            str(row["remote_identity_digest"]), client,
        )

    def strategy_metadata_context(self, principal: Principal, connection_id: str) -> ConnectionContext:
        """Return owner-checked connection metadata without loading vault credentials."""
        with self.store.transaction() as connection:
            self._require_principal(connection, principal, step_up=False)
            row = self._connection_row(connection, principal.user_id, connection_id, lock=True)
            if row is None:
                raise ConnectionServiceError(404, "not_found", "The requested resource was not found.")
            self._require_principal(connection, principal, step_up=False)
            try:
                capabilities = json.loads(row["product_capabilities_json"] or "[]")
            except (TypeError, ValueError):
                capabilities = []
            if not isinstance(capabilities, list):
                capabilities = []
            return ConnectionContext(
                principal.user_id, connection_id, str(row["exchange"]), str(row["environment"]),
                str(row["region"]), int(row["credential_version"]), int(row["permission_version"]),
                tuple(value for value in capabilities if isinstance(value, str)),
                str(row["remote_identity_digest"]), None,
            )

    def assert_product_read_supported(
        self, principal: Principal, connection_id: str, product: str, *, resource: str | None = None
    ) -> Any:
        """Check owner and stored product capability before vault or venue access."""
        with self.store.transaction() as connection:
            self._require_principal(connection, principal, step_up=False)
            row = self._connection_row(connection, principal.user_id, connection_id, lock=True)
            if row is None:
                raise ConnectionServiceError(404, "not_found", "The requested resource was not found.")
            self._require_principal(connection, principal, step_up=False)
            if row["status"] not in {"ACTIVE", "RECONCILING"}:
                raise ConnectionServiceError(409, "connection_unavailable", "The exchange connection is unavailable.")
            if row["exchange"] == "BINANCE" and row["environment"] == "demo":
                raise ConnectionServiceError(
                    503, "verification_unavailable", "Binance demo identity verification is unavailable."
                )
            try:
                capabilities = json.loads(row["product_capabilities_json"] or "[]")
            except (TypeError, ValueError):
                capabilities = []
            if not isinstance(capabilities, list):
                capabilities = []
            required = "read:" + product
            supported = required in capabilities or (row["exchange"] == "OKX" and "read" in capabilities)
            if not supported:
                raise ConnectionServiceError(422, "capability_unsupported", "This connection cannot read that product.")
            if product == "SPOT" and resource == "positions":
                raise ConnectionServiceError(422, "capability_unsupported", "Spot positions are not supported.")
            return row

    def assert_context_identity(
        self, principal: Principal, context: ConnectionContext, *, product: str | None = None
    ) -> VerifiedExchangeIdentity:
        """Recheck session, versions, status and authoritative UID around reads."""
        self.assert_context_authority(principal, context)
        identity = self._verify(context.client)
        digest = self._identity_digest(context.exchange, context.environment, context.region, identity.uid)
        if not hmac.compare_digest(digest, context.remote_identity_digest):
            raise ConnectionServiceError(409, "account_changed", "The exchange account changed during the read.")
        if (
            context.exchange == "BINANCE" and product is not None
            and "read:" + product not in identity.capabilities
        ):
            raise ConnectionServiceError(409, "connection_changed", "The exchange read permission changed.")
        # The final database-only check fences logout, rotation, and revocation
        # that happen while the authoritative exchange identity is in flight.
        self.assert_context_authority(principal, context)
        return identity

    def assert_context_authority(self, principal: Principal, context: ConnectionContext) -> None:
        """Check persisted session and connection authority without exchange I/O."""
        with self.store.transaction() as connection:
            self._require_principal(connection, principal, step_up=False)
            row = self._connection_row(connection, principal.user_id, context.connection_id, lock=True)
            if (
                row is None or row["status"] not in {"ACTIVE", "RECONCILING"}
                or int(row["credential_version"]) != context.credential_version
                or int(row["permission_version"]) != context.permission_version
                or not hmac.compare_digest(str(row["remote_identity_digest"]), context.remote_identity_digest)
            ):
                raise ConnectionServiceError(409, "connection_changed", "The connection changed during the read.")
            self._require_principal(connection, principal, step_up=False)

    def assert_action_supported(self, principal: Principal, connection_id: str) -> None:
        """Authorize ownership before rejecting unsupported venue mutations."""
        with self.store.transaction() as connection:
            self._require_principal(connection, principal, step_up=False)
            row = self._connection_row(connection, principal.user_id, connection_id, lock=True)
            if row is None:
                raise ConnectionServiceError(404, "not_found", "The requested resource was not found.")
            self._require_principal(connection, principal, step_up=False)
            if row["exchange"] == "BINANCE":
                raise ConnectionServiceError(422, "capability_unsupported", "Binance actions are not supported.")

    def account_context_for_job(
        self, user_id: str, connection_id: str, operation_id: str, lease_owner: str, fence: int
    ) -> ConnectionContext:
        """Load recovery credentials for an already-sent, currently fenced job.

        Historical credential and permission versions stay on the operation. A
        recovery lookup may use the current owned credentials after a same-owner
        relink, but its caller must prove the canonical remote identity before
        it trusts any exchange observation.
        """
        suffix = self._lock_suffix()
        with self.store.transaction() as connection:
            row = self._connection_row(connection, user_id, connection_id, lock=True)
            lease = connection.execute(
                "SELECT lease_owner, fence, lease_until, operation_id FROM multiuser_connection_leases "
                "WHERE user_id=? AND connection_id=?" + suffix,
                (user_id, connection_id),
            ).fetchone()
            operation = connection.execute(
                "SELECT status, connection_version, permission_version, pre_send_at FROM multiuser_operations "
                "WHERE user_id=? AND connection_id=? AND operation_id=?" + suffix,
                (user_id, connection_id, operation_id),
            ).fetchone()
            now = self._clock()
            if (
                row is None or lease is None or operation is None
                or lease["lease_owner"] != lease_owner or int(lease["fence"]) != fence
                or lease["operation_id"] != operation_id or lease["lease_until"] is None
                or float(lease["lease_until"]) <= now
                or operation["status"] != "RECONCILING"
                or operation["pre_send_at"] is None
                or row["status"] not in {"ACTIVE", "RECONCILING"}
            ):
                raise ConnectionServiceError(409, "job_fenced", "The accepted exchange job is no longer current.")
            credentials = self._credentials(connection, row)
            client = self._new_client(
                credentials, exchange=str(row["exchange"]), environment=str(row["environment"]),
                region=str(row["region"]),
            )
            capabilities = json.loads(row["product_capabilities_json"] or "[]")
            return ConnectionContext(
                user_id, connection_id, str(row["exchange"]), str(row["environment"]),
                str(row["region"]), int(row["credential_version"]), int(row["permission_version"]),
                tuple(value for value in capabilities if isinstance(value, str)),
                str(row["remote_identity_digest"]), client,
            )

    def account_context_for_strategy_job(
        self,
        user_id: str,
        connection_id: str,
        strategy_id: str,
        lease_owner: str,
        fence: int,
        *,
        recovery: bool = False,
    ) -> ConnectionContext:
        """Load credentials for one explicitly owned strategy job.

        New queued mutations require the exact versions captured when the
        strategy was prepared and current trade authority. Recovery reads may
        use current same-owner credentials after relink, but only for a job
        with a durable pre-send marker and never for resubmission.
        """
        suffix = self._lock_suffix()
        with self.store.transaction() as connection:
            row = self._connection_row(connection, user_id, connection_id, lock=True)
            lease = connection.execute(
                "SELECT lease_owner, fence, lease_until, operation_id FROM multiuser_connection_leases "
                "WHERE user_id=? AND connection_id=?" + suffix,
                (user_id, connection_id),
            ).fetchone()
            strategy = connection.execute(
                "SELECT status, credential_version, permission_version, attempt_started, pre_send_at "
                "FROM multiuser_strategies WHERE user_id=? AND connection_id=? AND strategy_id=?" + suffix,
                (user_id, connection_id, strategy_id),
            ).fetchone()
            claim = connection.execute(
                "SELECT lease_owner, fence, lease_until FROM multiuser_strategy_claims "
                "WHERE user_id=? AND connection_id=? AND strategy_id=?" + suffix,
                (user_id, connection_id, strategy_id),
            ).fetchone()
            now = self._clock()
            if (
                row is None or lease is None or strategy is None or claim is None
                or lease["lease_owner"] != lease_owner or int(lease["fence"]) != fence
                or lease["operation_id"] != strategy_id or lease["lease_until"] is None
                or float(lease["lease_until"]) <= now
                or claim["lease_owner"] != lease_owner or int(claim["fence"]) != fence
                or claim["lease_until"] is None or float(claim["lease_until"]) <= now
            ):
                raise ConnectionServiceError(409, "job_fenced", "The strategy job is no longer current.")
            capabilities = json.loads(row["product_capabilities_json"] or "[]")
            if recovery:
                if (
                    strategy["status"] not in {"UNKNOWN", "APPLYING", "RECONCILING", "APPLIED", "PARTIAL"}
                    or not bool(strategy["attempt_started"]) or strategy["pre_send_at"] is None
                    or row["status"] not in {"ACTIVE", "RECONCILING"}
                    or not isinstance(capabilities, list) or "read" not in capabilities
                ):
                    raise ConnectionServiceError(409, "job_recovery_unavailable", "The strategy cannot be reconciled with this connection.")
            elif (
                strategy["status"] != "APPLYING" or row["status"] != "ACTIVE"
                or int(strategy["credential_version"]) != int(row["credential_version"])
                or int(strategy["permission_version"]) != int(row["permission_version"])
                or not isinstance(capabilities, list) or "trade" not in capabilities
            ):
                raise ConnectionServiceError(409, "job_generation_changed", "The strategy connection changed before its next write.")
            credentials = self._credentials(connection, row)
            client = self._new_client(
                credentials, exchange=str(row["exchange"]), environment=str(row["environment"]),
                region=str(row["region"]),
            )
            return ConnectionContext(
                user_id, connection_id, str(row["exchange"]), str(row["environment"]),
                str(row["region"]), int(row["credential_version"]), int(row["permission_version"]),
                tuple(value for value in capabilities if isinstance(value, str)),
                str(row["remote_identity_digest"]), client,
            )

    def rotate_remote_identity_key(self, previous_key: bytes) -> int:
        """Atomically reindex every owner and tombstone before enabling the new key."""
        if not isinstance(previous_key, bytes) or len(previous_key) != 32:
            raise ValueError("previous remote identity key must be 32 bytes")
        old_fingerprint = hmac.new(
            previous_key, b"trading-balance-f/remote-identity-key-id/v1", hashlib.sha256
        ).hexdigest()
        now = self._clock()
        with self.store.transaction() as connection:
            state = connection.execute(
                "SELECT key_fingerprint, rotation_status, target_key_fingerprint "
                "FROM multiuser_identity_key_state WHERE singleton=1" + self._lock_suffix()
            ).fetchone()
            if state is None or not (
                (state["rotation_status"] == "ACTIVE" and state["key_fingerprint"] == old_fingerprint)
                or (
                    state["rotation_status"] == "ROTATING"
                    and state["key_fingerprint"] == old_fingerprint
                    and state["target_key_fingerprint"] == self.key_fingerprint
                )
            ):
                raise ConnectionServiceError(409, "identity_key_rotation_invalid", "The supplied previous key does not match the active identity index.")
            if state["rotation_status"] == "ACTIVE":
                connection.execute(
                    "UPDATE multiuser_identity_key_state SET rotation_status='ROTATING', target_key_fingerprint=?, updated_at=? WHERE singleton=1",
                    (self.key_fingerprint, now),
                )
        count = 0
        try:
            with self.store.transaction() as connection:
                state = connection.execute(
                    "SELECT key_fingerprint, rotation_status, target_key_fingerprint "
                    "FROM multiuser_identity_key_state WHERE singleton=1" + self._lock_suffix()
                ).fetchone()
                if (
                    state is None or state["rotation_status"] != "ROTATING"
                    or state["key_fingerprint"] != old_fingerprint
                    or state["target_key_fingerprint"] != self.key_fingerprint
                ):
                    raise ConnectionServiceError(409, "identity_key_rotation_invalid", "The identity index changed during key rotation.")
                rows = connection.execute(
                    "SELECT user_id, connection_id, exchange, environment, region, remote_identity_nonce, "
                    "remote_identity_ciphertext, identity_vault_key_id FROM exchange_connections "
                    "ORDER BY exchange, environment, region, remote_identity_digest" + self._lock_suffix()
                ).fetchall()
                for row in rows:
                    if (
                        row["remote_identity_nonce"] is None or row["remote_identity_ciphertext"] is None
                        or row["identity_vault_key_id"] is None
                    ):
                        raise ConnectionServiceError(
                            409, "identity_reindex_required", "A legacy connection lacks encrypted identity material; automatic key rotation is blocked."
                        )
                    uid = self.vault.decrypt_remote_identity(
                        str(row["identity_vault_key_id"]), bytes(row["remote_identity_nonce"]),
                        bytes(row["remote_identity_ciphertext"]), user_id=str(row["user_id"]),
                        connection_id=str(row["connection_id"]), exchange=str(row["exchange"]),
                        environment=str(row["environment"]), region=str(row["region"]),
                    )
                    digest = self._identity_digest(
                        str(row["exchange"]), str(row["environment"]), str(row["region"]), uid
                    )
                    connection.execute(
                        "UPDATE exchange_connections SET remote_identity_digest=?, updated_at=? "
                        "WHERE user_id=? AND connection_id=?",
                        (digest, now, row["user_id"], row["connection_id"]),
                    )
                    # Durable operations retain the original credential and
                    # permission generations, but their opaque owner/account
                    # binding follows the canonical identity-key reindex so
                    # read-only recovery remains possible after rotation.
                    operations = connection.execute(
                        "SELECT operation_id, payload_json FROM multiuser_operations "
                        "WHERE user_id=? AND connection_id=? AND pre_send_at IS NOT NULL",
                        (row["user_id"], row["connection_id"]),
                    ).fetchall()
                    for operation in operations:
                        try:
                            payload = json.loads(operation["payload_json"] or "{}")
                        except (TypeError, ValueError):
                            raise ConnectionServiceError(
                                409, "identity_reindex_required", "A durable operation lacks valid identity binding."
                            ) from None
                        if not isinstance(payload, dict) or not isinstance(payload.get("remoteIdentityDigest"), str):
                            raise ConnectionServiceError(
                                409, "identity_reindex_required", "A durable operation lacks valid identity binding."
                            )
                        payload["remoteIdentityDigest"] = digest
                        connection.execute(
                            "UPDATE multiuser_operations SET payload_json=?, updated_at=? "
                            "WHERE user_id=? AND connection_id=? AND operation_id=?",
                            (json.dumps(payload, sort_keys=True, separators=(",", ":")), now,
                             row["user_id"], row["connection_id"], operation["operation_id"]),
                        )
                    count += 1
                connection.execute(
                    "UPDATE multiuser_identity_key_state SET key_fingerprint=?, rotation_status='ACTIVE', "
                    "target_key_fingerprint=NULL, updated_at=? WHERE singleton=1",
                    (self.key_fingerprint, now),
                )
        except IdentityStoreConflict:
            raise ConnectionServiceError(409, "identity_reindex_conflict", "The new key produced an identity collision; the identity index remains paused.") from None
        return count
