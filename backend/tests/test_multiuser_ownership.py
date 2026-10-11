from __future__ import annotations

import unittest
import sqlite3
import multiprocessing
import os
import secrets
from dataclasses import replace
from tempfile import TemporaryDirectory
from unittest.mock import patch

from backend.app import create_application
from backend.auth import IdentityAuthError
from backend.connections import ConnectionContext, ConnectionServiceError, OwnedConnections
from backend.security import CryptoInvalidCiphertext, _totp_at
from backend.service import APIError, RuntimeSettings, TradeService, _OwnedStrategyOwner
from backend.store import SQLiteIdentityStore
from backend.strategy import StrategyService
from backend.strategy_scope import owned_strategy_fingerprint, scope_for_sides


def _postgres_schema_upgrade_worker(
    dsn: str,
    barrier: object,
    output: object,
) -> None:
    try:
        from backend.postgres_store import PostgresIdentityStore

        barrier.wait(timeout=30)
        PostgresIdentityStore(dsn).initialize()
        output.put(("ok",))
    except BaseException as error:
        output.put(("error", type(error).__name__))


class _FabricatedSeedCipher:
    """Test-only double for MFA setup; credential-vault tests use real AEAD."""

    key_id = "fabricated-mfa-test"

    def encrypt(self, user_id: str, secret: str) -> tuple[bytes, bytes]:
        return b"fabricated-nonce", user_id.encode() + b"\x00" + secret.encode("ascii")

    def decrypt(self, user_id: str, key_id: str, nonce: bytes, ciphertext: bytes) -> str:
        prefix = user_id.encode() + b"\x00"
        if key_id != self.key_id or not ciphertext.startswith(prefix):
            raise CryptoInvalidCiphertext("fabricated MFA seed mismatch")
        return ciphertext[len(prefix):].decode("ascii")


class _AccountConfigTransport:
    def __init__(self) -> None:
        self.calls: list[tuple[str, str, dict[str, str]]] = []
        self.uid = "123456789"
        self.permission = "read_only,trade"

    def __call__(self, method: str, path: str, headers: dict[str, str], body: bytes | None) -> dict:
        self.calls.append((method, path, dict(headers)))
        if method == "GET" and path == "/api/v5/account/config":
            return {"code": "0", "data": [{
                "uid": self.uid, "perm": self.permission, "posMode": "net_mode",
            }]}
        raise AssertionError(f"unexpected fake OKX request: {method} {path}")


class _FabricatedCredentialVault:
    """Connection-flow test double; real AEAD behavior is covered separately."""

    key_id = "fabricated-vault-test"

    def __init__(self) -> None:
        self.fail_next_identity_decrypt = False

    def encrypt_credentials(self, _credentials: dict, **_context: object) -> tuple[bytes, bytes]:
        return b"fabricated-nonce", b"fabricated-credential-ciphertext"

    def decrypt_credentials(self, *_args: object, **_context: object) -> dict[str, str]:
        return {
            "apiKey": "fabricated-api-key",
            "apiSecret": "fabricated-api-secret",
            "passphrase": "fabricated-passphrase",
        }

    def encrypt_remote_identity(self, uid: str, **_context: object) -> tuple[bytes, bytes]:
        return b"fabricated-identity-nonce", uid.encode("ascii")

    def decrypt_remote_identity(self, *_args: object, **_context: object) -> str:
        if self.fail_next_identity_decrypt:
            self.fail_next_identity_decrypt = False
            raise CryptoInvalidCiphertext("fabricated identity decryption failure")
        return "123456789"


class MultiuserOwnershipBaselineTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = TemporaryDirectory()
        self.now = 1_800_000_000.0
        self.settings = RuntimeSettings(
            okx_api_key="",
            okx_api_secret="",
            okx_api_passphrase="",
            admin_password_hash="",
            totp_secret="",
            session_signing_key=b"S" * 32,
            allowed_web_origin="https://tradingbalancef.example",
            operation_db_path=f"{self.temp.name}/operations.sqlite3",
            multiuser_enabled=True,
            multiuser_trade_enabled=False,
            credential_vault_key=b"V" * 32,
            credential_vault_key_id="test-v1",
            remote_identity_key=b"R" * 32,
        )
        self.store = SQLiteIdentityStore(self.settings.operation_db_path)
        self.store.initialize()
        self.transport = _AccountConfigTransport()
        self.service = TradeService(
            self.settings,
            identity_store=self.store,
            seed_cipher=_FabricatedSeedCipher(),
            transport=self.transport,
            clock=lambda: self.now,
        )
        self.app = create_application(service=self.service)
        self._totp_secrets: dict[str, str] = {}

    def tearDown(self) -> None:
        self.temp.cleanup()

    def _ordinary_session(self, username: str = "Owner.One") -> tuple[str, str]:
        password = "disposable owner test password"
        _, invite = self.service.identity_auth.create_invite()
        enrollment = self.service.identity_auth.activate_invite(
            invite, username, password, "198.51.100.10"
        )
        enrollment_principal = self.service.identity_auth.validate_session(enrollment.token)
        challenge = self.service.identity_auth.start_enrollment(enrollment_principal)
        secret = str(challenge["totpSecret"])
        self._totp_secrets[enrollment.user_id] = secret
        self.service.identity_auth.complete_enrollment(
            enrollment_principal,
            _totp_at(secret, int(self.now // 30)),
            True,
        )
        self.now += 30
        ordinary = self.service.identity_auth.login(
            username,
            password,
            totp=_totp_at(secret, int(self.now // 30)),
            source="198.51.100.10",
        )
        return ordinary.token, ordinary.user_id

    def _step_up(self, token: str, user_id: str) -> None:
        self.now += 30
        principal = self.service.identity_auth.validate_session(token)
        secret = self._totp_secrets[user_id]
        self.service.identity_auth.step_up(
            principal,
            "disposable owner test password",
            _totp_at(secret, int(self.now // 30)),
        )

    def _bearer_environ(self, token: str) -> dict[str, str]:
        return {
            "HTTP_X_SESSION_TRANSPORT": "bearer",
            "HTTP_AUTHORIZATION": f"Bearer {token}",
            "REMOTE_ADDR": "198.51.100.10",
        }

    def _connection_body(self) -> dict[str, str]:
        return {
            "exchange": "OKX",
            "environment": "demo",
            "region": "global",
            "nickname": "Fabricated account",
            "apiKey": "fabricated-api-key",
            "apiSecret": "fabricated-api-secret",
            "passphrase": "fabricated-passphrase",
        }

    def test_authenticated_owner_can_list_owned_connections(self) -> None:
        token, _ = self._ordinary_session()
        status, payload, _ = self.service.dispatch(
            "GET",
            "/v2/connections",
            {},
            {
                "HTTP_X_SESSION_TRANSPORT": "bearer",
                "HTTP_AUTHORIZATION": f"Bearer {token}",
                "REMOTE_ADDR": "198.51.100.10",
            },
        )

        self.assertEqual(status, 200)
        self.assertEqual(payload["connections"], [])
        self.assertEqual(self.transport.calls, [])

    def test_connection_create_requires_recent_step_up_before_upstream(self) -> None:
        token, _ = self._ordinary_session()

        with self.assertRaises(APIError) as denied:
            self.service.dispatch(
                "POST", "/v2/connections", self._connection_body(), self._bearer_environ(token)
            )

        self.assertEqual((denied.exception.status, denied.exception.code), (403, "step_up_required"))
        self.assertEqual(self.transport.calls, [])
        with self.store.connection() as connection:
            count = connection.execute("SELECT COUNT(*) FROM exchange_connections").fetchone()[0]
        self.assertEqual(count, 0)

    def test_connection_cookie_mutation_requires_csrf_and_native_bearer_rejects_origin(self) -> None:
        token, user_id = self._ordinary_session()
        principal = self.service.identity_auth.validate_session(token)
        csrf = self.service.identity_auth.csrf_token(principal)
        cookie_environ = {
            "HTTP_COOKIE": f"__Host-trade_v2_session={token}; __Host-trade_v2_csrf={csrf}",
            "HTTP_ORIGIN": self.settings.allowed_web_origin,
            "REMOTE_ADDR": "198.51.100.10",
        }

        with self.assertRaises(APIError) as csrf_denied:
            self.service.dispatch("POST", "/v2/connections", self._connection_body(), cookie_environ)
        self.assertEqual((csrf_denied.exception.status, csrf_denied.exception.code), (403, "csrf_denied"))
        self.assertEqual(self.transport.calls, [])

        native_with_origin = self._bearer_environ(token)
        native_with_origin["HTTP_ORIGIN"] = self.settings.allowed_web_origin
        with self.assertRaises(APIError) as transport_denied:
            self.service.dispatch("GET", "/v2/connections", {}, native_with_origin)
        self.assertEqual((transport_denied.exception.status, transport_denied.exception.code), (400, "transport_invalid"))
        self.assertEqual(self.transport.calls, [])
        self.assertTrue(user_id)

    def test_connection_id_guess_is_owner_first_uniform_404_without_upstream(self) -> None:
        token_a, owner_a = self._ordinary_session("Owner.ConnectionA")
        token_b, _ = self._ordinary_session("Owner.ConnectionB")
        connection_id = "owned-connection-a"
        with self.store.transaction() as connection:
            connection.execute(
                "INSERT INTO exchange_connections(user_id, connection_id, exchange, environment, region, "
                "product_capabilities_json, status, remote_identity_digest, credential_version, permission_version, "
                "created_at, updated_at) VALUES (?, ?, 'OKX', 'demo', 'global', '[\"read\"]', 'ACTIVE', ?, 1, 1, ?, ?)",
                (owner_a, connection_id, "fabricated-remote-digest", self.now, self.now),
            )

        with self.assertRaises(APIError) as guessed:
            self.service.dispatch(
                "GET", f"/v2/connections/{connection_id}", {}, self._bearer_environ(token_b)
            )
        self.assertEqual((guessed.exception.status, guessed.exception.code), (404, "not_found"))
        self.assertEqual(self.transport.calls, [])
        self.assertTrue(token_a)

    def test_get_account_is_read_only_and_post_verify_still_requires_step_up(self) -> None:
        token, user_id = self._ordinary_session()
        connection_id = "read-only-account"
        with self.store.transaction() as connection:
            connection.execute(
                "INSERT INTO exchange_connections(user_id, connection_id, exchange, environment, region, "
                "product_capabilities_json, status, remote_identity_digest, credential_version, permission_version, "
                "created_at, updated_at) VALUES (?, ?, 'OKX', 'demo', 'global', '[\"read\"]', 'ACTIVE', ?, 1, 1, ?, ?)",
                (user_id, connection_id, "read-only-digest", self.now, self.now),
            )

        status, payload, _ = self.service.dispatch(
            "GET", f"/v2/connections/{connection_id}/account", {}, self._bearer_environ(token)
        )
        self.assertEqual(status, 200)
        self.assertEqual(payload["account"]["capabilities"], ["read"])
        with self.assertRaises(APIError) as verify_denied:
            self.service.dispatch(
                "POST", f"/v2/connections/{connection_id}/verify", {}, self._bearer_environ(token)
            )
        self.assertEqual((verify_denied.exception.status, verify_denied.exception.code), (403, "step_up_required"))
        self.assertEqual(self.transport.calls, [])
        with self.store.connection() as connection:
            row = connection.execute(
                "SELECT product_capabilities_json, permission_version, status FROM exchange_connections "
                "WHERE user_id=? AND connection_id=?",
                (user_id, connection_id),
            ).fetchone()
        self.assertEqual(tuple(row), ('["read"]', 1, "ACTIVE"))

    def test_mixed_withdraw_permission_is_rejected_without_persisting_connection(self) -> None:
        token, user_id = self._ordinary_session()
        self._step_up(token, user_id)
        self.service.connections.vault = _FabricatedCredentialVault()
        principal = self.service.identity_auth.validate_session(token)
        self.transport.permission = "read_only,withdraw,trade"

        with self.assertRaises(ConnectionServiceError) as rejected:
            self.service.connections.create(principal, self._connection_body())

        self.assertEqual((rejected.exception.status, rejected.exception.code), (400, "verification_failed"))
        self.assertEqual(len(self.transport.calls), 1)
        with self.store.connection() as connection:
            self.assertEqual(connection.execute("SELECT COUNT(*) FROM exchange_connections").fetchone()[0], 0)

    def test_remote_identity_rotation_resumes_only_matching_interrupted_key_pair(self) -> None:
        token, user_id = self._ordinary_session()
        self._step_up(token, user_id)
        vault = _FabricatedCredentialVault()
        self.service.connections.vault = vault
        principal = self.service.identity_auth.validate_session(token)
        created = self.service.connections.create(principal, self._connection_body())
        connection_id = created["connectionId"]
        next_vault = _FabricatedCredentialVault()
        next_connections = OwnedConnections(
            self.store, next_vault, b"N" * 32, clock=lambda: self.now, trade_enabled=False,
        )
        next_vault.fail_next_identity_decrypt = True

        with self.assertRaises(CryptoInvalidCiphertext):
            next_connections.rotate_remote_identity_key(b"R" * 32)
        with self.store.connection() as connection:
            rotating = connection.execute(
                "SELECT rotation_status, target_key_fingerprint FROM multiuser_identity_key_state WHERE singleton=1"
            ).fetchone()
            old_digest = connection.execute(
                "SELECT remote_identity_digest FROM exchange_connections WHERE user_id=? AND connection_id=?",
                (user_id, connection_id),
            ).fetchone()["remote_identity_digest"]
        self.assertEqual(rotating["rotation_status"], "ROTATING")
        self.assertEqual(rotating["target_key_fingerprint"], next_connections.key_fingerprint)

        with self.assertRaises(ConnectionServiceError) as wrong_pair:
            next_connections.rotate_remote_identity_key(b"X" * 32)
        self.assertEqual(wrong_pair.exception.code, "identity_key_rotation_invalid")
        self.assertEqual(next_connections.rotate_remote_identity_key(b"R" * 32), 1)
        with self.store.connection() as connection:
            active = connection.execute(
                "SELECT rotation_status FROM multiuser_identity_key_state WHERE singleton=1"
            ).fetchone()["rotation_status"]
            new_digest = connection.execute(
                "SELECT remote_identity_digest FROM exchange_connections WHERE user_id=? AND connection_id=?",
                (user_id, connection_id),
            ).fetchone()["remote_identity_digest"]
        self.assertEqual(active, "ACTIVE")
        self.assertNotEqual(old_digest, new_digest)

    def test_revoke_same_account_relink_keeps_id_and_unknown_barrier(self) -> None:
        token, user_id = self._ordinary_session()
        self._step_up(token, user_id)
        self.service.connections.vault = _FabricatedCredentialVault()
        principal = self.service.identity_auth.validate_session(token)
        created = self.service.connections.create(principal, self._connection_body())
        connection_id = created["connectionId"]
        self.assertEqual(created["status"], "ACTIVE")
        self.assertEqual(created["capabilities"], ["read"])
        self.assertNotIn("apiKey", created)
        self.assertNotIn("apiSecret", created)

        with self.store.transaction() as connection:
            connection.execute(
                "INSERT INTO multiuser_operations(user_id, connection_id, operation_id, product, idempotency_key, "
                "request_hash, status, created_at, updated_at, pre_send_at, payload_json) "
                "VALUES (?, ?, ?, 'SWAP', ?, ?, 'UNKNOWN', ?, ?, ?, '{}')",
                (user_id, connection_id, "unknown-operation", "fabricated-idempotency-key", "fabricated-hash",
                 self.now, self.now, self.now),
            )

        revoked = self.service.connections.revoke(principal, connection_id)
        self.assertEqual(revoked["status"], "RECONCILING")
        relinked = self.service.connections.create(principal, self._connection_body())
        self.assertEqual(relinked["connectionId"], connection_id)
        self.assertEqual(relinked["status"], "RECONCILING")
        self.assertGreater(relinked["credentialVersion"], revoked["credentialVersion"])

        with self.store.connection() as connection:
            operation = connection.execute(
                "SELECT status, pre_send_at FROM multiuser_operations WHERE user_id=? AND connection_id=? "
                "AND operation_id='unknown-operation'",
                (user_id, connection_id),
            ).fetchone()
            count = connection.execute(
                "SELECT COUNT(*) FROM exchange_connections WHERE remote_identity_digest=?",
                (self.service.connections._identity_digest("OKX", "demo", "global", self.transport.uid),),
            ).fetchone()[0]
        self.assertEqual((operation["status"], operation["pre_send_at"]), ("UNKNOWN", self.now))
        self.assertEqual(count, 1)

    def test_strategy_prepare_route_requires_step_up_on_real_nested_action_path(self) -> None:
        token, user_id = self._ordinary_session()
        connection_id = "owned-route-connection"
        remote_digest = "owned-route-remote-digest"
        with self.store.transaction() as connection:
            connection.execute(
                "INSERT INTO exchange_connections(user_id, connection_id, exchange, environment, region, "
                "product_capabilities_json, status, remote_identity_digest, credential_version, permission_version, "
                "created_at, updated_at) VALUES (?, ?, 'OKX', 'demo', 'global', '[\"read\",\"trade\"]', "
                "'ACTIVE', ?, 1, 1, ?, ?)",
                (user_id, connection_id, remote_digest, self.now, self.now),
            )
        context = ConnectionContext(
            user_id, connection_id, "OKX", "demo", "global", 1, 1, ("read", "trade"),
            remote_digest, object(),
        )
        self.service.connections.account_context = lambda principal, requested_id, **kwargs: context

        def dispatch_with_guard(strategy, method, path, body, *, request_guard=None):
            if request_guard is not None:
                request_guard()
            return {"path": path}

        from backend.strategy import StrategyService

        with patch.object(StrategyService, "dispatch", dispatch_with_guard):
            with self.assertRaises(APIError) as raised:
                self.service.dispatch(
                    "POST",
                    f"/v2/connections/{connection_id}/strategies/strategy-one/prepare-apply",
                    {},
                    {
                        "HTTP_X_SESSION_TRANSPORT": "bearer",
                        "HTTP_AUTHORIZATION": f"Bearer {token}",
                        "REMOTE_ADDR": "198.51.100.10",
                    },
                )

        self.assertEqual(raised.exception.code, "step_up_required")
        self.assertEqual(self.transport.calls, [])

    def test_revoked_connection_historical_result_is_read_without_credentials(self) -> None:
        token, user_id = self._ordinary_session()
        connection_id = "revoked-result-connection"
        remote_digest = "revoked-result-remote-digest"
        fingerprint = owned_strategy_fingerprint(user_id, connection_id)
        with self.store.transaction() as connection:
            connection.execute(
                "INSERT INTO exchange_connections(user_id, connection_id, exchange, environment, region, "
                "product_capabilities_json, status, remote_identity_digest, credential_version, permission_version, "
                "created_at, updated_at) VALUES (?, ?, 'OKX', 'demo', 'global', '[]', 'REVOKED', ?, 2, 2, ?, ?)",
                (user_id, connection_id, remote_digest, self.now, self.now),
            )
            connection.execute(
                "INSERT INTO multiuser_strategies(user_id, connection_id, strategy_id, status, account_fingerprint, "
                "contract_json, snapshot_json, orders_json, results_json, created_at, updated_at) "
                "VALUES (?, ?, 'historical-job-1', 'UNKNOWN', ?, ?, ?, '[]', '[]', ?, ?)",
                (user_id, connection_id, fingerprint,
                 '{"instrumentId":"BTC-USDT-SWAP","interval":"1Dutc"}',
                 '{"sides":[],"totalMargin":"0"}', self.now - 60, self.now - 30),
            )

        status, payload, _ = self.service.dispatch(
            "GET",
            f"/v2/connections/{connection_id}/strategies/historical-job-1/result",
            {},
            {
                "HTTP_X_SESSION_TRANSPORT": "bearer",
                "HTTP_AUTHORIZATION": f"Bearer {token}",
                "REMOTE_ADDR": "198.51.100.10",
            },
        )

        self.assertEqual(status, 200)
        self.assertEqual(payload["status"], "UNKNOWN")
        self.assertEqual(payload["id"], "historical-job-1")
        self.assertEqual(self.transport.calls, [])

    def test_owned_history_preferences_and_reservation_survive_signing_key_rotation(self) -> None:
        _, user_id = self._ordinary_session()
        connection_id = "stable-owner-connection"
        remote_digest = "stable-owner-remote-digest"
        fingerprint = owned_strategy_fingerprint(user_id, connection_id)
        with self.store.transaction() as connection:
            connection.execute(
                "INSERT INTO exchange_connections(user_id, connection_id, exchange, environment, region, "
                "product_capabilities_json, status, remote_identity_digest, credential_version, permission_version, "
                "created_at, updated_at) VALUES (?, ?, 'OKX', 'demo', 'global', '[]', 'REVOKED', ?, 2, 2, ?, ?)",
                (user_id, connection_id, remote_digest, self.now, self.now),
            )
            connection.execute(
                "INSERT INTO multiuser_strategies(user_id, connection_id, strategy_id, status, account_fingerprint, "
                "contract_json, snapshot_json, orders_json, results_json, created_at, updated_at) "
                "VALUES (?, ?, 'stable-history-1', 'UNKNOWN', ?, ?, ?, '[]', '[]', ?, ?)",
                (user_id, connection_id, fingerprint,
                 '{"instrumentId":"BTC-USDT-SWAP","interval":"1Dutc"}',
                 '{"sides":[],"totalMargin":"0"}', self.now - 60, self.now - 30),
            )
            connection.execute(
                "INSERT INTO multiuser_strategy_settings(user_id, connection_id, settings_json, preferences_json, "
                "account_fingerprint, limit_order_submission_mode, jev_min_structural_quality, "
                "jev_min_entry_suitability_probability, jev_max_failure_risk_probability, updated_at) "
                "VALUES (?, ?, ?, ?, ?, 'batch', 3, 0.7, 0.2, ?)",
                (user_id, connection_id, '{"limitOrderSubmissionMode":"batch"}', '{}', fingerprint, self.now),
            )
            connection.execute(
                "INSERT INTO multiuser_strategy_reservations(user_id, connection_id, account_fingerprint, "
                "instrument_id, strategy_id, position_mode, side_scope, created_at) "
                "VALUES (?, ?, ?, 'BTC-USDT-SWAP', 'stable-history-1', 'net_mode', 'all', ?)",
                (user_id, connection_id, fingerprint, self.now),
            )

        rotated_settings = replace(self.settings, session_signing_key=b"T" * 32)
        rotated_service = TradeService(
            rotated_settings,
            identity_store=self.store,
            seed_cipher=self.service.identity_auth.seed_cipher,
            transport=self.transport,
            clock=lambda: self.now,
        )
        self.now += 30
        rotated_token = rotated_service.identity_auth.login(
            "Owner.One",
            "disposable owner test password",
            totp=_totp_at(self._totp_secrets[user_id], int(self.now // 30)),
            source="198.51.100.10",
        ).token
        environ = {
            "HTTP_X_SESSION_TRANSPORT": "bearer",
            "HTTP_AUTHORIZATION": f"Bearer {rotated_token}",
            "REMOTE_ADDR": "198.51.100.10",
        }

        result_status, result_payload, _ = rotated_service.dispatch(
            "GET",
            f"/v2/connections/{connection_id}/strategies/stable-history-1/result",
            {},
            environ,
        )
        settings_status, settings_payload, _ = rotated_service.dispatch(
            "GET", f"/v2/connections/{connection_id}/strategies/settings", {}, environ
        )
        principal = rotated_service.identity_auth.validate_session(rotated_token)
        metadata = rotated_service.connections.strategy_metadata_context(principal, connection_id)
        owner = _OwnedStrategyOwner(rotated_service, principal, metadata)
        strategy = StrategyService(owner, strategy_scope=owner.strategy_scope)
        with self.store.connection() as connection:
            reservation_visible = strategy._has_overlapping_reservation(
                connection,
                owner.strategy_scope.account_fingerprint,
                "BTC-USDT-SWAP",
                scope_for_sides("net_mode", ["long"]),
            )

        self.assertEqual((result_status, result_payload["id"], result_payload["status"]),
                         (200, "stable-history-1", "UNKNOWN"))
        self.assertEqual(settings_status, 200)
        self.assertEqual(settings_payload["limitOrderSubmissionMode"], "batch")
        self.assertTrue(reservation_visible)
        self.assertEqual(self.transport.calls, [])

    def test_t110_schema_upgrade_preserves_owner_and_connection_rows(self) -> None:
        old_path = f"{self.temp.name}/old-v1.sqlite3"
        connection = sqlite3.connect(old_path)
        try:
            connection.executescript(
                "CREATE TABLE multiuser_schema_version(singleton INTEGER PRIMARY KEY, version INTEGER NOT NULL);"
                "INSERT INTO multiuser_schema_version VALUES (1, 1);"
                "CREATE TABLE users(user_id TEXT PRIMARY KEY, username TEXT NOT NULL, username_normalized TEXT NOT NULL UNIQUE, "
                "password_hash TEXT NOT NULL, status TEXT NOT NULL, auth_version INTEGER NOT NULL DEFAULT 1, created_at REAL NOT NULL);"
                "INSERT INTO users VALUES ('owner-v1', 'Owner V1', 'owner v1', 'password-hash', 'ACTIVE', 3, 123.0);"
                "CREATE TABLE exchange_connections(user_id TEXT NOT NULL, connection_id TEXT NOT NULL, exchange TEXT NOT NULL, "
                "environment TEXT NOT NULL, region TEXT NOT NULL, product_capabilities_json TEXT NOT NULL, nickname TEXT, "
                "status TEXT NOT NULL, remote_identity_digest TEXT NOT NULL, credential_version INTEGER NOT NULL, "
                "permission_version INTEGER NOT NULL, created_at REAL NOT NULL, updated_at REAL NOT NULL, "
                "PRIMARY KEY(user_id, connection_id), UNIQUE(connection_id), UNIQUE(exchange, environment, region, remote_identity_digest));"
                "INSERT INTO exchange_connections VALUES ('owner-v1', 'connection-v1', 'OKX', 'demo', 'global', '[\"read\"]', "
                "'kept nickname', 'REVOKED', 'stable-digest', 4, 7, 100.0, 200.0);"
                "CREATE TABLE multiuser_strategies (user_id TEXT NOT NULL, connection_id TEXT NOT NULL, "
                "strategy_id TEXT NOT NULL, status TEXT NOT NULL, created_at REAL NOT NULL, updated_at REAL NOT NULL, "
                "PRIMARY KEY(user_id, connection_id, strategy_id), "
                "FOREIGN KEY(user_id, connection_id) REFERENCES exchange_connections(user_id, connection_id));"
                "INSERT INTO multiuser_strategies VALUES ('owner-v1', 'connection-v1', 'strategy-v1', 'UNKNOWN', 150.0, 175.0);"
                "CREATE TABLE multiuser_strategy_reservations (user_id TEXT NOT NULL, connection_id TEXT NOT NULL, "
                "instrument_id TEXT NOT NULL, strategy_id TEXT NOT NULL, position_mode TEXT NOT NULL, "
                "side_scope TEXT NOT NULL, created_at REAL NOT NULL, "
                "PRIMARY KEY(user_id, connection_id, instrument_id, strategy_id), "
                "FOREIGN KEY(user_id, connection_id) REFERENCES exchange_connections(user_id, connection_id), "
                "FOREIGN KEY(user_id, connection_id, strategy_id) "
                "REFERENCES multiuser_strategies(user_id, connection_id, strategy_id));"
                "INSERT INTO multiuser_strategy_reservations VALUES ('owner-v1', 'connection-v1', 'BTC-USDT-SWAP', "
                "'strategy-v1', 'net_mode', 'both', 175.0);"
            )
            connection.commit()
        finally:
            connection.close()

        upgraded = SQLiteIdentityStore(old_path)
        upgraded.initialize()
        with upgraded.connection() as migrated:
            version = migrated.execute(
                "SELECT version FROM multiuser_schema_version WHERE singleton=1"
            ).fetchone()
            owner = migrated.execute(
                "SELECT username, auth_version, created_at FROM users WHERE user_id='owner-v1'"
            ).fetchone()
            connection_row = migrated.execute(
                "SELECT connection_id, nickname, status, remote_identity_digest, credential_version, permission_version "
                "FROM exchange_connections WHERE user_id='owner-v1'"
            ).fetchone()
            columns = {row["name"] for row in migrated.execute("PRAGMA table_info(exchange_connections)").fetchall()}
            operation_columns = {row["name"] for row in migrated.execute("PRAGMA table_info(multiuser_operations)").fetchall()}
            strategy_columns = {row["name"] for row in migrated.execute("PRAGMA table_info(multiuser_strategies)").fetchall()}
            strategy = migrated.execute(
                "SELECT user_id, connection_id, strategy_id, status, credential_version, permission_version, created_at "
                "FROM multiuser_strategies WHERE strategy_id='strategy-v1'"
            ).fetchone()
            reservation = migrated.execute(
                "SELECT user_id, connection_id, instrument_id, strategy_id, position_mode, side_scope, account_fingerprint "
                "FROM multiuser_strategy_reservations WHERE strategy_id='strategy-v1'"
            ).fetchone()
            fingerprint_index = migrated.execute(
                "SELECT 1 FROM sqlite_master WHERE type='index' AND name='multiuser_strategies_owner_fingerprint'"
            ).fetchone()

        self.assertEqual(version["version"], 2)
        self.assertEqual((owner["username"], owner["auth_version"], owner["created_at"]), ("Owner V1", 3, 123.0))
        self.assertEqual(
            (connection_row["connection_id"], connection_row["nickname"], connection_row["status"],
             connection_row["remote_identity_digest"], connection_row["credential_version"], connection_row["permission_version"]),
            ("connection-v1", "kept nickname", "REVOKED", "stable-digest", 4, 7),
        )
        self.assertTrue({"remote_identity_nonce", "remote_identity_ciphertext", "verified_at"} <= columns)
        self.assertTrue({"confirmation_digest", "confirmation_used_at", "pre_send_at"} <= operation_columns)
        self.assertTrue({"account_fingerprint", "contract_json", "credential_version", "permission_version"} <= strategy_columns)
        self.assertEqual(
            tuple(strategy),
            ("owner-v1", "connection-v1", "strategy-v1", "UNKNOWN", 1, 1, 150.0),
        )
        self.assertEqual(
            tuple(reservation),
            ("owner-v1", "connection-v1", "BTC-USDT-SWAP", "strategy-v1", "net_mode", "both", ""),
        )
        self.assertIsNotNone(fingerprint_index)


class PostgresOwnedConnectionIntegrationTests(unittest.TestCase):
    def test_concurrent_v1_upgrade_serializes_and_preserves_owned_rows(self) -> None:
        test_dsn = os.environ.get("MULTIUSER_TEST_DATABASE_URL", "")
        if not test_dsn:
            self.skipTest("BLOCKED: MULTIUSER_TEST_DATABASE_URL is not configured")
        try:
            import psycopg
        except ImportError:
            self.fail("BLOCKED: psycopg is required when MULTIUSER_TEST_DATABASE_URL is configured")

        from backend.postgres_store import PostgresIdentityStore

        schema = "t111_upgrade_" + secrets.token_hex(8)
        with psycopg.connect(test_dsn, autocommit=True) as connection:
            connection.execute(f'CREATE SCHEMA "{schema}"')
        schema_dsn = psycopg.conninfo.make_conninfo(test_dsn, options=f"-c search_path={schema}")
        with psycopg.connect(schema_dsn, autocommit=True) as connection:
            connection.execute(
                "CREATE TABLE multiuser_schema_version(singleton INTEGER PRIMARY KEY, version INTEGER NOT NULL)"
            )
            connection.execute("INSERT INTO multiuser_schema_version VALUES (1, 1)")
            connection.execute(
                "CREATE TABLE users(user_id TEXT PRIMARY KEY, username TEXT NOT NULL, "
                "username_normalized TEXT NOT NULL UNIQUE, password_hash TEXT NOT NULL, status TEXT NOT NULL, "
                "auth_version INTEGER NOT NULL DEFAULT 1, created_at DOUBLE PRECISION NOT NULL)"
            )
            connection.execute(
                "INSERT INTO users VALUES ('upgrade-owner', 'Upgrade Owner', 'upgrade owner', "
                "'fabricated-hash', 'ACTIVE', 3, 123.0)"
            )
            connection.execute(
                "CREATE TABLE exchange_connections(user_id TEXT NOT NULL, connection_id TEXT NOT NULL UNIQUE, "
                "exchange TEXT NOT NULL, environment TEXT NOT NULL, region TEXT NOT NULL, "
                "product_capabilities_json TEXT NOT NULL, nickname TEXT, status TEXT NOT NULL, "
                "remote_identity_digest TEXT NOT NULL, credential_version INTEGER NOT NULL, "
                "permission_version INTEGER NOT NULL, created_at DOUBLE PRECISION NOT NULL, "
                "updated_at DOUBLE PRECISION NOT NULL, PRIMARY KEY(user_id, connection_id), "
                "UNIQUE(exchange, environment, region, remote_identity_digest), "
                "FOREIGN KEY(user_id) REFERENCES users(user_id))"
            )
            connection.execute(
                "INSERT INTO exchange_connections VALUES ('upgrade-owner', 'upgrade-connection', 'OKX', "
                "'demo', 'global', '[\"read\"]', 'kept nickname', 'REVOKED', 'stable-digest', 4, 7, 100.0, 200.0)"
            )
            connection.execute(
                "CREATE TABLE multiuser_operations(user_id TEXT NOT NULL, connection_id TEXT NOT NULL, "
                "operation_id TEXT NOT NULL, product TEXT NOT NULL, idempotency_key TEXT NOT NULL, "
                "request_hash TEXT NOT NULL, status TEXT NOT NULL, created_at DOUBLE PRECISION NOT NULL, "
                "updated_at DOUBLE PRECISION NOT NULL, PRIMARY KEY(user_id, connection_id, operation_id), "
                "UNIQUE(user_id, connection_id, idempotency_key), FOREIGN KEY(user_id, connection_id) "
                "REFERENCES exchange_connections(user_id, connection_id))"
            )
            connection.execute(
                "INSERT INTO multiuser_operations VALUES ('upgrade-owner', 'upgrade-connection', "
                "'operation-v1', 'SWAP', 'legacy-idempotency-key', 'legacy-request-hash', 'UNKNOWN', 160.0, 170.0)"
            )
            connection.execute(
                "CREATE TABLE multiuser_strategies(user_id TEXT NOT NULL, connection_id TEXT NOT NULL, "
                "strategy_id TEXT NOT NULL, status TEXT NOT NULL, created_at DOUBLE PRECISION NOT NULL, "
                "updated_at DOUBLE PRECISION NOT NULL, PRIMARY KEY(user_id, connection_id, strategy_id), "
                "FOREIGN KEY(user_id, connection_id) REFERENCES exchange_connections(user_id, connection_id))"
            )
            connection.execute(
                "INSERT INTO multiuser_strategies VALUES ('upgrade-owner', 'upgrade-connection', "
                "'strategy-v1', 'UNKNOWN', 150.0, 175.0)"
            )
            connection.execute(
                "CREATE TABLE multiuser_strategy_reservations(user_id TEXT NOT NULL, connection_id TEXT NOT NULL, "
                "instrument_id TEXT NOT NULL, strategy_id TEXT NOT NULL, position_mode TEXT NOT NULL, "
                "side_scope TEXT NOT NULL, created_at DOUBLE PRECISION NOT NULL, "
                "PRIMARY KEY(user_id, connection_id, instrument_id, strategy_id), "
                "FOREIGN KEY(user_id, connection_id) REFERENCES exchange_connections(user_id, connection_id), "
                "FOREIGN KEY(user_id, connection_id, strategy_id) "
                "REFERENCES multiuser_strategies(user_id, connection_id, strategy_id))"
            )
            connection.execute(
                "INSERT INTO multiuser_strategy_reservations VALUES ('upgrade-owner', 'upgrade-connection', "
                "'BTC-USDT-SWAP', 'strategy-v1', 'net_mode', 'both', 175.0)"
            )

        context = multiprocessing.get_context("spawn")
        barrier = context.Barrier(2)
        output = context.Queue()
        processes = [
            context.Process(target=_postgres_schema_upgrade_worker, args=(schema_dsn, barrier, output))
            for _ in range(2)
        ]
        try:
            for process in processes:
                process.start()
            results = [output.get(timeout=90) for _ in processes]
            for process in processes:
                process.join(timeout=90)
                self.assertEqual(process.exitcode, 0)
            self.assertEqual(results, [("ok",), ("ok",)])

            PostgresIdentityStore(schema_dsn).initialize()
            with psycopg.connect(schema_dsn) as connection:
                version = connection.execute(
                    "SELECT version FROM multiuser_schema_version WHERE singleton=1"
                ).fetchone()[0]
                owner = connection.execute(
                    "SELECT username, auth_version, created_at FROM users WHERE user_id='upgrade-owner'"
                ).fetchone()
                owned_connection = connection.execute(
                    "SELECT connection_id, nickname, status, credential_version, permission_version "
                    "FROM exchange_connections WHERE user_id='upgrade-owner'"
                ).fetchone()
                operation = connection.execute(
                    "SELECT operation_id, idempotency_key, request_hash, status, created_at, updated_at, "
                    "credential_version, permission_version, pre_send_at FROM multiuser_operations "
                    "WHERE user_id='upgrade-owner' AND connection_id='upgrade-connection'"
                ).fetchone()
                strategy = connection.execute(
                    "SELECT status, credential_version, permission_version FROM multiuser_strategies "
                    "WHERE user_id='upgrade-owner' AND connection_id='upgrade-connection' "
                    "AND strategy_id='strategy-v1'"
                ).fetchone()
                reservation = connection.execute(
                    "SELECT account_fingerprint FROM multiuser_strategy_reservations "
                    "WHERE user_id='upgrade-owner' AND connection_id='upgrade-connection' "
                    "AND strategy_id='strategy-v1'"
                ).fetchone()
                columns = {
                    row[0] for row in connection.execute(
                        "SELECT column_name FROM information_schema.columns "
                        "WHERE table_schema=current_schema() AND table_name='multiuser_strategies'"
                    ).fetchall()
                }
            self.assertEqual(version, 2)
            self.assertEqual(tuple(owner), ("Upgrade Owner", 3, 123.0))
            self.assertEqual(tuple(owned_connection), ("upgrade-connection", "kept nickname", "REVOKED", 4, 7))
            self.assertEqual(
                tuple(operation),
                ("operation-v1", "legacy-idempotency-key", "legacy-request-hash", "UNKNOWN", 160.0, 170.0, 1, 1, None),
            )
            self.assertEqual(tuple(strategy), ("UNKNOWN", 1, 1))
            self.assertEqual(reservation[0], "")
            self.assertTrue({"account_fingerprint", "credential_version", "permission_version", "pre_send_at"} <= columns)
        finally:
            for process in processes:
                if process.is_alive():
                    process.terminate()
                    process.join(timeout=5)
            output.close()
            with psycopg.connect(test_dsn, autocommit=True) as connection:
                connection.execute(f'DROP SCHEMA IF EXISTS "{schema}" CASCADE')


if __name__ == "__main__":
    unittest.main()
