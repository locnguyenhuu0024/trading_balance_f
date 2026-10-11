from __future__ import annotations

import unittest
import hashlib
import json
import multiprocessing
import os
import secrets
import time
from tempfile import TemporaryDirectory
from types import SimpleNamespace

from backend.auth import IdentityAuthService
from backend.command_ledger import CommandLedger, CommandLedgerError
from backend.connections import ConnectionContext, OwnedConnections
from backend.security import CryptoInvalidCiphertext, _totp_at
from backend.service import APIError, RuntimeSettings, TradeService
from backend.store import SQLiteIdentityStore
from backend.okx import OKXTransportError


class _FabricatedSeedCipher:
    """MFA test double only; command credential tests require real AEAD."""

    key_id = "fabricated-mfa-test"

    def encrypt(self, user_id: str, secret: str) -> tuple[bytes, bytes]:
        return b"fabricated-nonce", user_id.encode() + b"\x00" + secret.encode("ascii")

    def decrypt(self, user_id: str, key_id: str, nonce: bytes, ciphertext: bytes) -> str:
        prefix = user_id.encode() + b"\x00"
        if key_id != self.key_id or not ciphertext.startswith(prefix):
            raise CryptoInvalidCiphertext("fabricated MFA seed mismatch")
        return ciphertext[len(prefix):].decode("ascii")


class _OwnedCommandTestBase(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = TemporaryDirectory()
        self.now = 1_800_000_000.0
        settings = RuntimeSettings(
            okx_api_key="", okx_api_secret="", okx_api_passphrase="", admin_password_hash="",
            totp_secret="", session_signing_key=b"S" * 32,
            allowed_web_origin="https://tradingbalancef.example",
            operation_db_path=f"{self.temp.name}/operations.sqlite3", multiuser_enabled=True,
            credential_vault_key=b"V" * 32, credential_vault_key_id="test-v1", remote_identity_key=b"R" * 32,
        )
        self.store = SQLiteIdentityStore(settings.operation_db_path)
        self.store.initialize()
        self.service = TradeService(
            settings, identity_store=self.store, seed_cipher=_FabricatedSeedCipher(), clock=lambda: self.now,
            transport=lambda *_: self.fail("owner result reads must not call the exchange"),
        )
        self.tokens: dict[str, tuple[str, str]] = {}

    def tearDown(self) -> None:
        self.temp.cleanup()

    def _ordinary_session(self, username: str) -> tuple[str, str]:
        password = "disposable owner test password"
        _, invite = self.service.identity_auth.create_invite()
        enrollment = self.service.identity_auth.activate_invite(invite, username, password, "198.51.100.10")
        enrollment_principal = self.service.identity_auth.validate_session(enrollment.token)
        challenge = self.service.identity_auth.start_enrollment(enrollment_principal)
        secret = str(challenge["totpSecret"])
        self.service.identity_auth.complete_enrollment(
            enrollment_principal, _totp_at(secret, int(self.now // 30)), True
        )
        self.now += 30
        ordinary = self.service.identity_auth.login(
            username, password, totp=_totp_at(secret, int(self.now // 30)), source="198.51.100.10"
        )
        return ordinary.token, ordinary.user_id

    def _bearer_environ(self, token: str) -> dict[str, str]:
        return {
            "HTTP_X_SESSION_TRANSPORT": "bearer",
            "HTTP_AUTHORIZATION": f"Bearer {token}",
            "REMOTE_ADDR": "198.51.100.10",
        }


class OwnedCommandClaimTests(_OwnedCommandTestBase):
    def test_owner_can_read_result_and_other_owner_guessing_both_ids_gets_uniform_404(self) -> None:
        token_a, owner_a = self._ordinary_session("Owner.Alpha")
        token_b, _ = self._ordinary_session("Owner.Bravo")
        connection_id = "connection-owned-alpha"
        operation_id = "operation-owned-alpha"
        with self.store.transaction() as connection:
            connection.execute(
                "INSERT INTO exchange_connections(user_id, connection_id, exchange, environment, region, "
                "product_capabilities_json, status, remote_identity_digest, credential_version, permission_version, "
                "created_at, updated_at) VALUES (?, ?, 'OKX', 'demo', 'global', '[\"read\"]', 'ACTIVE', ?, 1, 1, ?, ?)",
                (owner_a, connection_id, "test-only-remote-digest", self.now, self.now),
            )
            connection.execute(
                "INSERT INTO multiuser_operations(user_id, connection_id, operation_id, product, idempotency_key, "
                "request_hash, status, created_at, updated_at, result_json) VALUES (?, ?, ?, 'SWAP', ?, ?, 'SUCCEEDED', ?, ?, ?)",
                (owner_a, connection_id, operation_id, "test-idempotency-key", "request-hash", self.now, self.now,
                 '{"outcome":"accepted"}'),
            )

        status, payload, _ = self.service.dispatch(
            "GET", f"/v2/connections/{connection_id}/actions/{operation_id}", {}, self._bearer_environ(token_a)
        )
        self.assertEqual(status, 200)
        self.assertEqual(payload["operation"]["status"], "SUCCEEDED")
        self.assertEqual(payload["operation"]["result"], {"outcome": "accepted"})

        with self.assertRaises(APIError) as guessed:
            self.service.dispatch(
                "GET", f"/v2/connections/{connection_id}/actions/{operation_id}", {}, self._bearer_environ(token_b)
            )
        self.assertEqual((guessed.exception.status, guessed.exception.code), (404, "not_found"))

    def test_expired_confirmation_is_persisted_before_rejection(self) -> None:
        token, owner_id = self._ordinary_session("Owner.Expiry")
        principal = self.service.identity_auth.validate_session(token)
        connection_id = "connection-expiry"
        operation_id = "operation-expiry"
        confirmation = "fabricated-confirmation-token"
        with self.store.transaction() as connection:
            connection.execute(
                "UPDATE user_sessions SET step_up_until=? WHERE session_id=?",
                (self.now + 600, principal.session_id),
            )
            connection.execute(
                "INSERT INTO exchange_connections(user_id, connection_id, exchange, environment, region, "
                "product_capabilities_json, status, remote_identity_digest, credential_version, permission_version, "
                "created_at, updated_at) VALUES (?, ?, 'OKX', 'demo', 'global', '[\"read\",\"trade\"]', 'ACTIVE', ?, 1, 1, ?, ?)",
                (owner_id, connection_id, "test-only-remote-digest", self.now, self.now),
            )
            connection.execute(
                "INSERT INTO multiuser_operations(user_id, connection_id, operation_id, product, idempotency_key, "
                "request_hash, status, created_at, updated_at, payload_json, connection_version, permission_version, "
                "expires_at, confirmation_digest) VALUES (?, ?, ?, 'SWAP', ?, ?, 'PREPARED', ?, ?, ?, 1, 1, ?, ?)",
                (owner_id, connection_id, operation_id, "prepared:" + operation_id, "intent-hash", self.now,
                 self.now, json.dumps({"action": "cancel_order", "identity": {}}), self.now + 30,
                 hashlib.sha256(confirmation.encode("ascii")).hexdigest()),
            )
            connection.execute(
                "INSERT INTO multiuser_command_targets(user_id, connection_id, operation_id, target_index, "
                "request_json, status, updated_at) VALUES (?, ?, ?, 0, '{}', 'PREPARED', ?)",
                (owner_id, connection_id, operation_id, self.now),
            )

        self.now += 31
        with self.assertRaises(APIError) as expired:
            self.service.dispatch(
                "POST",
                f"/v2/connections/{connection_id}/actions/{operation_id}/execute",
                {"confirmationToken": confirmation, "idempotencyKey": "expired-key-0001"},
                self._bearer_environ(token),
            )
        self.assertEqual((expired.exception.status, expired.exception.code), (409, "confirmation_expired"))
        with self.store.connection() as connection:
            operation = connection.execute(
                "SELECT status, confirmation_digest FROM multiuser_operations WHERE user_id=? AND connection_id=? AND operation_id=?",
                (owner_id, connection_id, operation_id),
            ).fetchone()
            target = connection.execute(
                "SELECT status FROM multiuser_command_targets WHERE user_id=? AND connection_id=? AND operation_id=? AND target_index=0",
                (owner_id, connection_id, operation_id),
            ).fetchone()
        self.assertEqual(operation["status"], "EXPIRED")
        self.assertIsNone(operation["confirmation_digest"])
        self.assertEqual(target["status"], "CANCELED")

    def test_active_result_poll_does_not_rewrite_send_marker(self) -> None:
        token, owner_id = self._ordinary_session("Owner.Poll")
        connection_id = "connection-poll"
        operation_id = "operation-poll"
        with self.store.transaction() as connection:
            connection.execute(
                "INSERT INTO exchange_connections(user_id, connection_id, exchange, environment, region, "
                "product_capabilities_json, status, remote_identity_digest, credential_version, permission_version, "
                "created_at, updated_at) VALUES (?, ?, 'OKX', 'demo', 'global', '[\"read\"]', 'ACTIVE', ?, 1, 1, ?, ?)",
                (owner_id, connection_id, "poll-only-digest", self.now, self.now),
            )
            connection.execute(
                "INSERT INTO multiuser_operations(user_id, connection_id, operation_id, product, idempotency_key, "
                "request_hash, status, created_at, updated_at, payload_json, connection_version, permission_version, "
                "pre_send_at) VALUES (?, ?, ?, 'SWAP', ?, ?, 'SENDING', ?, ?, '{}', 1, 1, ?)",
                (owner_id, connection_id, operation_id, "poll-key-0001", "poll-hash", self.now, self.now, self.now),
            )
            connection.execute(
                "INSERT INTO multiuser_command_targets(user_id, connection_id, operation_id, target_index, "
                "request_json, status, pre_send_at, updated_at) VALUES (?, ?, ?, 0, '{}', 'ATTEMPT_STARTED', ?, ?)",
                (owner_id, connection_id, operation_id, self.now, self.now),
            )
            connection.execute(
                "INSERT INTO multiuser_connection_leases(user_id, connection_id, lease_owner, fence, lease_until, operation_id, updated_at) "
                "VALUES (?, ?, ?, 3, ?, ?, ?)",
                (owner_id, connection_id, operation_id, self.now + 45, operation_id, self.now),
            )

        status, payload, _ = self.service.dispatch(
            "GET", f"/v2/connections/{connection_id}/actions/{operation_id}", {}, self._bearer_environ(token)
        )
        self.assertEqual(status, 200)
        self.assertEqual(payload["operation"]["status"], "SENDING")
        with self.store.connection() as connection:
            operation = connection.execute(
                "SELECT status, pre_send_at FROM multiuser_operations WHERE user_id=? AND connection_id=? AND operation_id=?",
                (owner_id, connection_id, operation_id),
            ).fetchone()
            target = connection.execute(
                "SELECT status, pre_send_at FROM multiuser_command_targets WHERE user_id=? AND connection_id=? AND operation_id=? AND target_index=0",
                (owner_id, connection_id, operation_id),
            ).fetchone()
        self.assertEqual((operation["status"], operation["pre_send_at"]), ("SENDING", self.now))
        self.assertEqual((target["status"], target["pre_send_at"]), ("ATTEMPT_STARTED", self.now))


class _DurableCloseClient:
    def __init__(self) -> None:
        self.position_open = True
        self.position_size = "1"
        self.close_calls: list[dict[str, str]] = []
        self.fail_after_send = False
        self.before_send_result: object | None = None
        self.additional_positions: list[dict[str, str]] = []
        self.additional_instruments: list[str] = []

    def account_config(self) -> dict[str, str]:
        return {"uid": "123456789", "perm": "read_only,trade", "posMode": "net_mode"}

    def instruments(self, instrument_type: str) -> list[dict[str, str]]:
        return [
            {"instId": "BTC-USDT-SWAP", "instType": instrument_type},
            *({"instId": instrument_id, "instType": instrument_type}
              for instrument_id in self.additional_instruments),
        ]

    def positions(self, instrument_type: str) -> list[dict[str, str]]:
        if not self.position_open:
            return []
        return [{
            "instId": "BTC-USDT-SWAP", "instType": instrument_type, "mgnMode": "cross",
            "posSide": "net", "pos": self.position_size, "posId": "42",
        }, *self.additional_positions]

    def close_position(self, request: dict[str, str]) -> dict[str, object]:
        self.close_calls.append(dict(request))
        if self.before_send_result is not None:
            callback, self.before_send_result = self.before_send_result, None
            callback()
        if self.fail_after_send:
            self.position_open = False
            raise OKXTransportError("fabricated response loss after request send")
        self.position_open = False
        return {"code": "0", "data": [{"sCode": "0"}]}


class CommandExecutionBoundaryTests(_OwnedCommandTestBase):
    connection_id = "connection-command-execution"

    def _command_fixture(self) -> tuple[str, str, object, CommandLedger, _DurableCloseClient]:
        token, user_id = self._ordinary_session("Owner.Execute")
        with self.store.transaction() as connection:
            connection.execute(
                "UPDATE user_sessions SET step_up_until=? WHERE user_id=?",
                (self.now + 300, user_id),
            )
            connection.execute(
                "INSERT INTO exchange_connections(user_id, connection_id, exchange, environment, region, "
                "product_capabilities_json, status, remote_identity_digest, credential_version, permission_version, "
                "created_at, updated_at) VALUES (?, ?, 'OKX', 'demo', 'global', '[\"read\",\"trade\"]', "
                "'ACTIVE', ?, 1, 1, ?, ?)",
                (user_id, self.connection_id,
                 self.service.connections._identity_digest("OKX", "demo", "global", "123456789"),
                 self.now, self.now),
            )
        principal = self.service.identity_auth.validate_session(token)
        client = _DurableCloseClient()
        context = ConnectionContext(
            user_id, self.connection_id, "OKX", "demo", "global", 1, 1, ("read", "trade"),
            self.service.connections._identity_digest("OKX", "demo", "global", "123456789"), client,
        )
        self.service.connections.account_context = lambda *_args, **_kwargs: context
        ledger = CommandLedger(
            self.store, self.service.connections, clock=lambda: self.now, trade_enabled=True,
        )
        return token, user_id, principal, ledger, client

    def _prepare_close(
        self, principal: object, ledger: CommandLedger, *, instrument_id: str = "BTC-USDT-SWAP",
        position_id: str = "42",
    ) -> dict[str, object]:
        return ledger.prepare(principal, self.connection_id, {
            "action": "close_position",
            "targetIdentity": {
                "instrumentType": "SWAP", "instrumentId": instrument_id, "positionId": position_id,
                "positionSide": "net", "marginMode": "cross",
            },
        })

    def test_generation_change_after_prepare_cancels_without_send(self) -> None:
        _, user_id, principal, ledger, client = self._command_fixture()
        prepared = self._prepare_close(principal, ledger)
        with self.store.transaction() as connection:
            connection.execute(
                "UPDATE exchange_connections SET credential_version=2 WHERE user_id=? AND connection_id=?",
                (user_id, self.connection_id),
            )

        with self.assertRaises(CommandLedgerError) as changed:
            ledger.execute(principal, self.connection_id, str(prepared["operationId"]), {
                "confirmationToken": prepared["confirmationToken"], "idempotencyKey": "version-change-0001",
            })

        self.assertEqual(changed.exception.code, "connection_changed")
        self.assertEqual(client.close_calls, [])
        with self.store.connection() as connection:
            operation = connection.execute(
                "SELECT status, pre_send_at FROM multiuser_operations WHERE user_id=? AND connection_id=? "
                "AND operation_id=?",
                (user_id, self.connection_id, prepared["operationId"]),
            ).fetchone()
            target = connection.execute(
                "SELECT status, pre_send_at FROM multiuser_command_targets WHERE user_id=? AND connection_id=? "
                "AND operation_id=? AND target_index=0",
                (user_id, self.connection_id, prepared["operationId"]),
            ).fetchone()
        self.assertEqual(tuple(operation), ("CANCELED", None))
        self.assertEqual(tuple(target), ("CANCELED", None))

    def test_preflight_target_change_conflicts_before_send(self) -> None:
        _, user_id, principal, ledger, client = self._command_fixture()
        prepared = self._prepare_close(principal, ledger)
        client.position_size = "2"

        result = ledger.execute(principal, self.connection_id, str(prepared["operationId"]), {
            "confirmationToken": prepared["confirmationToken"], "idempotencyKey": "stale-target-0001",
        })

        self.assertEqual(result["status"], "CONFLICT")
        self.assertEqual(client.close_calls, [])
        with self.store.connection() as connection:
            row = connection.execute(
                "SELECT pre_send_at FROM multiuser_operations WHERE user_id=? AND connection_id=? AND operation_id=?",
                (user_id, self.connection_id, prepared["operationId"]),
            ).fetchone()
        self.assertIsNone(row["pre_send_at"])

    def test_send_timeout_persists_unknown_and_same_key_replay_does_not_resend(self) -> None:
        _, user_id, principal, ledger, client = self._command_fixture()
        prepared = self._prepare_close(principal, ledger)
        client.fail_after_send = True
        request = {
            "confirmationToken": prepared["confirmationToken"], "idempotencyKey": "unknown-send-0001",
        }

        first = ledger.execute(principal, self.connection_id, str(prepared["operationId"]), request)
        replay = ledger.execute(principal, self.connection_id, str(prepared["operationId"]), request)

        self.assertEqual(first["status"], "UNKNOWN")
        self.assertEqual(replay["status"], "UNKNOWN")
        self.assertEqual(len(client.close_calls), 1)
        self.assertEqual(first["operationId"], replay["operationId"])
        with self.store.connection() as connection:
            operation = connection.execute(
                "SELECT status, pre_send_at FROM multiuser_operations WHERE user_id=? AND connection_id=? "
                "AND operation_id=?",
                (user_id, self.connection_id, prepared["operationId"]),
            ).fetchone()
            target = connection.execute(
                "SELECT status, pre_send_at FROM multiuser_command_targets WHERE user_id=? AND connection_id=? "
                "AND operation_id=? AND target_index=0",
                (user_id, self.connection_id, prepared["operationId"]),
            ).fetchone()
        self.assertEqual(operation["status"], "UNKNOWN")
        self.assertEqual(target["status"], "UNKNOWN")
        self.assertEqual(operation["pre_send_at"], target["pre_send_at"])

    def test_reused_idempotency_key_for_different_intent_conflicts_without_second_send(self) -> None:
        _, _user_id, principal, ledger, client = self._command_fixture()
        client.additional_instruments = ["ETH-USDT-SWAP"]
        client.additional_positions = [{
            "instId": "ETH-USDT-SWAP", "instType": "SWAP", "mgnMode": "cross",
            "posSide": "net", "pos": "2", "posId": "43",
        }]
        first = self._prepare_close(principal, ledger)
        second = self._prepare_close(
            principal, ledger, instrument_id="ETH-USDT-SWAP", position_id="43",
        )
        key = "shared-idempotency-key-0001"
        ledger.execute(principal, self.connection_id, str(first["operationId"]), {
            "confirmationToken": first["confirmationToken"], "idempotencyKey": key,
        })

        with self.assertRaises(CommandLedgerError) as conflict:
            ledger.execute(principal, self.connection_id, str(second["operationId"]), {
                "confirmationToken": second["confirmationToken"], "idempotencyKey": key,
            })

        self.assertEqual(conflict.exception.code, "idempotency_conflict")
        self.assertEqual(len(client.close_calls), 1)

    def test_supported_close_polls_marker_during_send_and_same_key_returns_proven_result(self) -> None:
        _, _user_id, principal, ledger, client = self._command_fixture()
        prepared = self._prepare_close(principal, ledger)
        operation_id = str(prepared["operationId"])
        polls: list[dict[str, object]] = []
        client.before_send_result = lambda: polls.append(
            ledger.get_result(principal, self.connection_id, operation_id)
        )
        request = {
            "confirmationToken": prepared["confirmationToken"], "idempotencyKey": "close-action-0001",
        }

        result = ledger.execute(principal, self.connection_id, operation_id, request)
        replay = ledger.execute(principal, self.connection_id, operation_id, request)

        self.assertEqual(result["status"], "SUCCEEDED")
        self.assertEqual(result["targets"][0]["status"], "SUCCEEDED")
        self.assertEqual(result["result"]["targetStatus"], "SUCCEEDED")
        self.assertEqual(len(polls), 1)
        self.assertEqual(polls[0]["status"], "SENDING")
        self.assertEqual(polls[0]["targets"][0]["status"], "ATTEMPT_STARTED")
        self.assertEqual(replay["status"], "SUCCEEDED")
        self.assertEqual(client.close_calls, [{"instId": "BTC-USDT-SWAP", "mgnMode": "cross", "autoCxl": True, "posSide": "net"}])


class _PostgresCloseClient:
    def __init__(self, store: object, uid: str = "123456789", entered: object | None = None,
                 release: object | None = None) -> None:
        self.store = store
        self.uid = uid
        self.entered = entered
        self.release = release
        self.closed = False

    def account_config(self) -> dict[str, str]:
        return {"uid": self.uid, "perm": "read_only,trade", "posMode": "net_mode"}

    def instruments(self, instrument_type: str) -> list[dict[str, str]]:
        return [{"instId": "BTC-USDT-SWAP", "instType": instrument_type}]

    def positions(self, instrument_type: str) -> list[dict[str, str]]:
        if self.closed:
            return []
        return [{
            "instId": "BTC-USDT-SWAP", "instType": instrument_type, "mgnMode": "cross",
            "posSide": "net", "pos": "1", "posId": "42",
        }]

    def close_position(self, _request: dict[str, str]) -> dict[str, object]:
        self.closed = True
        if self.entered is not None:
            self.entered.set()
        if self.release is not None and not self.release.wait(timeout=45):
            raise TimeoutError("test release event was not set")
        with self.store.transaction() as connection:
            connection.execute(
                "INSERT INTO t111_external_writes(write_id) VALUES (?)", (secrets.token_hex(16),)
            )
        time.sleep(0.05)
        return {"code": "0", "data": [{"sCode": "0"}]}


def _postgres_command_execute_worker(
    schema_dsn: str,
    token: str,
    owner_id: str,
    connection_id: str,
    operation_id: str,
    confirmation: str,
    now: float,
    uid: str,
    start: object,
    output: object,
    idempotency_key: str = "postgres-race-key-0001",
    entered: object | None = None,
    release: object | None = None,
) -> None:
    try:
        from backend.postgres_store import PostgresIdentityStore

        store = PostgresIdentityStore(schema_dsn)
        store.initialize()
        key = b"R" * 32
        vault = SimpleNamespace()
        connections = OwnedConnections(store, vault, key, clock=lambda: now, trade_enabled=True)
        digest = connections._identity_digest("OKX", "demo", "global", uid)
        ledger = CommandLedger(store, connections, clock=lambda: now, trade_enabled=True)
        auth = IdentityAuthService(store, b"S" * 32, _FabricatedSeedCipher(), clock=lambda: now)
        principal = auth.validate_session(token)
        client = _PostgresCloseClient(store, uid, entered, release)
        context = ConnectionContext(
            owner_id, connection_id, "OKX", "demo", "global", 1, 1, ("read", "trade"), digest, client,
        )
        connections.account_context = lambda *_args, **_kwargs: context
        start.wait(timeout=30)
        result = ledger.execute(principal, connection_id, operation_id, {
            "confirmationToken": confirmation, "idempotencyKey": idempotency_key,
        })
        output.put(("ok", result["status"]))
    except BaseException as error:
        output.put(("error", type(error).__name__))


def _seed_postgres_close_operation(
    store: object,
    owner_id: str,
    connection_id: str,
    uid: str,
    operation_id: str,
    confirmation: str,
    idempotency_key: str,
    now: float,
) -> str:
    connections = OwnedConnections(store, SimpleNamespace(), b"R" * 32, clock=lambda: now, trade_enabled=True)
    digest = connections._identity_digest("OKX", "demo", "global", uid)
    identity = {
        "instrumentType": "SWAP", "instrumentId": "BTC-USDT-SWAP", "positionId": "42",
        "positionSide": "net", "marginMode": "cross",
    }
    snapshot = {
        "identity": identity, "positionMode": "net_mode", "signedSize": "1", "size": "1",
        "marginMode": "cross",
    }
    target = {
        "identity": identity, "snapshot": snapshot,
        "request": {"instId": "BTC-USDT-SWAP", "mgnMode": "cross", "autoCxl": True, "posSide": "net"},
        "action": "close_position",
    }
    payload = {
        "action": "close_position", "identity": identity, "target": target,
        "summary": {"action": "close_position"}, "remoteIdentityDigest": digest,
    }
    request_hash = hashlib.sha256(json.dumps(
        {"action": "close_position", "identity": identity}, sort_keys=True, separators=(",", ":")
    ).encode("utf-8")).hexdigest()
    with store.transaction() as connection:
        connection.execute(
            "INSERT INTO exchange_connections(user_id, connection_id, exchange, environment, region, "
            "product_capabilities_json, status, remote_identity_digest, credential_version, permission_version, "
            "created_at, updated_at) VALUES (?, ?, 'OKX', 'demo', 'global', '[\"read\",\"trade\"]', "
            "'ACTIVE', ?, 1, 1, ?, ?) ON CONFLICT(user_id, connection_id) DO NOTHING",
            (owner_id, connection_id, digest, now, now),
        )
        connection.execute(
            "INSERT INTO multiuser_operations(user_id, connection_id, operation_id, product, idempotency_key, "
            "request_hash, status, created_at, updated_at, payload_json, connection_version, credential_version, "
            "permission_version, expires_at, confirmation_digest) "
            "VALUES (?, ?, ?, 'SWAP', ?, ?, 'PREPARED', ?, ?, ?, 1, 1, 1, ?, ?)",
            (owner_id, connection_id, operation_id, "prepared:" + idempotency_key, request_hash, now, now,
             json.dumps(payload, sort_keys=True, separators=(",", ":")), now + 30,
             hashlib.sha256(confirmation.encode("ascii")).hexdigest()),
        )
        connection.execute(
            "INSERT INTO multiuser_command_targets(user_id, connection_id, operation_id, target_index, "
            "request_json, status, updated_at) VALUES (?, ?, ?, 0, ?, 'PREPARED', ?)",
            (owner_id, connection_id, operation_id,
             json.dumps(target, sort_keys=True, separators=(",", ":")), now),
        )
    return digest


class PostgresCommandClaimIntegrationTests(unittest.TestCase):
    def test_concurrent_claim_revoke_and_expired_fence_preserve_one_send_each(self) -> None:
        test_dsn = os.environ.get("MULTIUSER_TEST_DATABASE_URL", "")
        if not test_dsn:
            self.skipTest("BLOCKED: MULTIUSER_TEST_DATABASE_URL is not configured")
        try:
            import psycopg
        except ImportError:
            self.fail("BLOCKED: psycopg is required when MULTIUSER_TEST_DATABASE_URL is configured")

        from backend.postgres_store import PostgresIdentityStore

        schema = "t111_command_" + secrets.token_hex(8)
        with psycopg.connect(test_dsn, autocommit=True) as connection:
            connection.execute(f'CREATE SCHEMA "{schema}"')
        schema_dsn = psycopg.conninfo.make_conninfo(test_dsn, options=f"-c search_path={schema}")
        now = 1_800_000_000.0
        store = PostgresIdentityStore(schema_dsn)
        processes: list[multiprocessing.Process] = []
        queue: multiprocessing.queues.Queue | None = None
        try:
            store.initialize()
            auth = IdentityAuthService(store, b"S" * 32, _FabricatedSeedCipher(), clock=lambda: now)
            _, invite = auth.create_invite()
            password = "fabricated postgres command password"
            enrollment = auth.activate_invite(invite, "Command.Owner", password, "203.0.113.81")
            enrollment_principal = auth.validate_session(enrollment.token)
            challenge = auth.start_enrollment(enrollment_principal)
            secret = str(challenge["totpSecret"])
            auth.complete_enrollment(
                enrollment_principal, _totp_at(secret, int(now // 30)), True,
            )
            ordinary = auth.login(
                "Command.Owner", password, totp=_totp_at(secret, int((now + 30) // 30)),
                source="203.0.113.81",
            )
            owner_id = ordinary.user_id
            connection_id = "pg-command-connection"
            operation_id = "pg-command-operation"
            confirmation = "fabricated-confirmation-token"
            identity = {
                "instrumentType": "SWAP", "instrumentId": "BTC-USDT-SWAP", "positionId": "42",
                "positionSide": "net", "marginMode": "cross",
            }
            connections = OwnedConnections(store, SimpleNamespace(), b"R" * 32, clock=lambda: now, trade_enabled=True)
            digest = connections._identity_digest("OKX", "demo", "global", "123456789")
            snapshot = {
                "identity": identity, "positionMode": "net_mode", "signedSize": "1", "size": "1",
                "marginMode": "cross",
            }
            target = {
                "identity": identity, "snapshot": snapshot,
                "request": {"instId": "BTC-USDT-SWAP", "mgnMode": "cross", "autoCxl": True, "posSide": "net"},
                "action": "close_position",
            }
            payload = {
                "action": "close_position", "identity": identity, "target": target,
                "summary": {"action": "close_position"}, "remoteIdentityDigest": digest,
            }
            request_hash = hashlib.sha256(json.dumps(
                {"action": "close_position", "identity": identity}, sort_keys=True, separators=(",", ":")
            ).encode("utf-8")).hexdigest()
            with store.transaction() as connection:
                connection.execute(
                    "UPDATE user_sessions SET step_up_until=? WHERE user_id=?",
                    (now + 600, owner_id),
                )
                connection.execute(
                    "INSERT INTO exchange_connections(user_id, connection_id, exchange, environment, region, "
                    "product_capabilities_json, status, remote_identity_digest, credential_version, permission_version, "
                    "created_at, updated_at) VALUES (?, ?, 'OKX', 'demo', 'global', '[\"read\",\"trade\"]', "
                    "'ACTIVE', ?, 1, 1, ?, ?)",
                    (owner_id, connection_id, digest, now, now),
                )
                connection.execute(
                    "INSERT INTO multiuser_operations(user_id, connection_id, operation_id, product, idempotency_key, "
                    "request_hash, status, created_at, updated_at, payload_json, connection_version, credential_version, "
                    "permission_version, expires_at, confirmation_digest) "
                    "VALUES (?, ?, ?, 'SWAP', ?, ?, 'PREPARED', ?, ?, ?, 1, 1, 1, ?, ?)",
                    (owner_id, connection_id, operation_id, "prepared:" + operation_id, request_hash, now, now,
                     json.dumps(payload, sort_keys=True, separators=(",", ":")), now + 30,
                     hashlib.sha256(confirmation.encode("ascii")).hexdigest()),
                )
                connection.execute(
                    "INSERT INTO multiuser_command_targets(user_id, connection_id, operation_id, target_index, "
                    "request_json, status, updated_at) VALUES (?, ?, ?, 0, ?, 'PREPARED', ?)",
                    (owner_id, connection_id, operation_id,
                     json.dumps(target, sort_keys=True, separators=(",", ":")), now),
                )
                connection.execute("CREATE TABLE t111_external_writes(write_id TEXT PRIMARY KEY)")

            context = multiprocessing.get_context("spawn")
            start = context.Barrier(2)
            queue = context.Queue()
            for _ in range(2):
                process = context.Process(
                    target=_postgres_command_execute_worker,
                    args=(schema_dsn, ordinary.token, owner_id, connection_id, operation_id,
                          confirmation, now, "123456789", start, queue),
                )
                processes.append(process)
                process.start()
            results = [queue.get(timeout=60) for _ in processes]
            for process in processes:
                process.join(timeout=60)
                self.assertEqual(process.exitcode, 0)
            self.assertEqual([item[0] for item in results], ["ok", "ok"], results)
            with store.connection() as connection:
                operation = connection.execute(
                    "SELECT status, pre_send_at FROM multiuser_operations WHERE user_id=? AND connection_id=? AND operation_id=?",
                    (owner_id, connection_id, operation_id),
                ).fetchone()
                target = connection.execute(
                    "SELECT status, pre_send_at FROM multiuser_command_targets WHERE user_id=? AND connection_id=? "
                    "AND operation_id=? AND target_index=0",
                    (owner_id, connection_id, operation_id),
                ).fetchone()
                sends = connection.execute("SELECT COUNT(*) AS count FROM t111_external_writes").fetchone()["count"]
            self.assertEqual(operation["status"], "SUCCEEDED")
            self.assertIsNotNone(operation["pre_send_at"])
            self.assertEqual(target["status"], "SUCCEEDED")
            self.assertEqual(operation["pre_send_at"], target["pre_send_at"])
            self.assertEqual(int(sends), 1)

            principal = auth.validate_session(ordinary.token)
            owned_connections = OwnedConnections(
                store, SimpleNamespace(), b"R" * 32, clock=lambda: now, trade_enabled=True,
            )
            ledger = CommandLedger(store, owned_connections, clock=lambda: now, trade_enabled=True)
            identity = {
                "instrumentType": "SWAP", "instrumentId": "BTC-USDT-SWAP", "positionId": "42",
                "positionSide": "net", "marginMode": "cross",
            }

            # Revoke while another confirmed close is inside its exchange call.
            # Revocation preserves the stable owner and moves the connection to
            # RECONCILING; the claimed send may record its result under the same fence.
            revoke_operation = "pg-command-revoke-operation"
            revoke_confirmation = "fabricated-revoke-confirmation"
            revoke_key = "postgres-revoke-key-0001"
            _seed_postgres_close_operation(
                store, owner_id, connection_id, "123456789", revoke_operation,
                revoke_confirmation, revoke_key, now,
            )
            entered = context.Event()
            release = context.Event()
            release.clear()
            started = context.Event()
            started.set()
            revoke_output = context.Queue()
            revoke_process = context.Process(
                target=_postgres_command_execute_worker,
                args=(schema_dsn, ordinary.token, owner_id, connection_id, revoke_operation,
                      revoke_confirmation, now, "123456789", started, revoke_output,
                      revoke_key, entered, release),
            )
            processes.append(revoke_process)
            revoke_process.start()
            self.assertTrue(entered.wait(timeout=60), "send did not reach the durable marked exchange call")
            revoked = owned_connections.revoke(principal, connection_id)
            self.assertEqual(revoked["status"], "RECONCILING")
            with self.assertRaises(CommandLedgerError) as blocked:
                ledger.prepare(principal, connection_id, {"action": "close_position", "targetIdentity": identity})
            self.assertEqual((blocked.exception.status, blocked.exception.code), (409, "connection_unavailable"))
            release.set()
            revoke_result = revoke_output.get(timeout=60)
            revoke_process.join(timeout=60)
            self.assertEqual(revoke_process.exitcode, 0)
            self.assertEqual(revoke_result, ("ok", "SUCCEEDED"))
            with store.connection() as connection:
                operation = connection.execute(
                    "SELECT status, pre_send_at FROM multiuser_operations WHERE user_id=? AND connection_id=? "
                    "AND operation_id=?",
                    (owner_id, connection_id, revoke_operation),
                ).fetchone()
                owned = connection.execute(
                    "SELECT status FROM exchange_connections WHERE user_id=? AND connection_id=?",
                    (owner_id, connection_id),
                ).fetchone()
                sends = connection.execute("SELECT COUNT(*) AS count FROM t111_external_writes").fetchone()["count"]
            self.assertEqual(operation["status"], "SUCCEEDED")
            self.assertIsNotNone(operation["pre_send_at"])
            self.assertEqual(owned["status"], "RECONCILING")
            self.assertEqual(int(sends), 2)

            # Expire an in-flight fence while the fabricated transport is
            # blocked. The stale executor must leave its ATTEMPT_STARTED marker
            # unresolved, and same-key replay must not issue a second write.
            expired_connection = "pg-expired-fence-connection"
            expired_operation = "pg-expired-fence-operation"
            expired_confirmation = "fabricated-expired-fence-confirmation"
            expired_key = "postgres-expired-fence-key-0001"
            expired_uid = "987654321"
            _seed_postgres_close_operation(
                store, owner_id, expired_connection, expired_uid, expired_operation,
                expired_confirmation, expired_key, now,
            )
            entered_expired = context.Event()
            release_expired = context.Event()
            started_expired = context.Event()
            started_expired.set()
            expired_output = context.Queue()
            expired_process = context.Process(
                target=_postgres_command_execute_worker,
                args=(schema_dsn, ordinary.token, owner_id, expired_connection, expired_operation,
                      expired_confirmation, now, expired_uid, started_expired, expired_output,
                      expired_key, entered_expired, release_expired),
            )
            processes.append(expired_process)
            expired_process.start()
            self.assertTrue(entered_expired.wait(timeout=60), "send did not reach the expiring-fence test barrier")
            with store.transaction() as connection:
                connection.execute(
                    "UPDATE multiuser_connection_leases SET lease_until=? WHERE user_id=? AND connection_id=?",
                    (now - 1, owner_id, expired_connection),
                )
            release_expired.set()
            expired_result = expired_output.get(timeout=60)
            expired_process.join(timeout=60)
            self.assertEqual(expired_process.exitcode, 0)
            self.assertEqual(expired_result, ("ok", "UNKNOWN"))
            replay = ledger.execute(principal, expired_connection, expired_operation, {
                "confirmationToken": expired_confirmation, "idempotencyKey": expired_key,
            })
            self.assertEqual(ledger.get_result(principal, expired_connection, expired_operation)["status"], "UNKNOWN")
            self.assertIn(replay["status"], {"SENDING", "UNKNOWN"})
            with store.connection() as connection:
                operation = connection.execute(
                    "SELECT status, pre_send_at FROM multiuser_operations WHERE user_id=? AND connection_id=? "
                    "AND operation_id=?",
                    (owner_id, expired_connection, expired_operation),
                ).fetchone()
                target = connection.execute(
                    "SELECT status, pre_send_at FROM multiuser_command_targets WHERE user_id=? AND connection_id=? "
                    "AND operation_id=? AND target_index=0",
                    (owner_id, expired_connection, expired_operation),
                ).fetchone()
                sends = connection.execute("SELECT COUNT(*) AS count FROM t111_external_writes").fetchone()["count"]
            self.assertEqual(operation["status"], "SENDING")
            self.assertIsNotNone(operation["pre_send_at"])
            self.assertEqual(target["status"], "ATTEMPT_STARTED")
            self.assertEqual(target["pre_send_at"], operation["pre_send_at"])
            self.assertEqual(int(sends), 3)
        finally:
            for process in processes:
                if process.is_alive():
                    process.terminate()
                    process.join(timeout=5)
            if queue is not None:
                queue.close()
            with psycopg.connect(test_dsn, autocommit=True) as connection:
                connection.execute(f'DROP SCHEMA IF EXISTS "{schema}" CASCADE')


class CommandPreflightBoundaryTests(unittest.TestCase):
    @staticmethod
    def _context(position: dict[str, str]) -> ConnectionContext:
        class _Client:
            def account_config(self) -> dict:
                return {"uid": "123456789", "perm": "read_only,trade", "posMode": "long_short_mode"}

            def instruments(self, instrument_type: str) -> list[dict[str, str]]:
                return [{"instId": "BTC-USDT-SWAP", "instType": instrument_type}]

            def positions(self, instrument_type: str) -> list[dict[str, str]]:
                return [position]

        return ConnectionContext(
            "owner", "connection", "OKX", "demo", "global", 1, 1, ("read", "trade"),
            "remote-digest", _Client(),
        )

    def test_hedge_short_summary_uses_exchange_position_side(self) -> None:
        context = self._context({
            "instId": "BTC-USDT-SWAP", "mgnMode": "isolated", "posSide": "short", "pos": "2", "posId": "42",
        })
        ledger = CommandLedger(
            object(), SimpleNamespace(_identity_digest=lambda *_: "remote-digest"), clock=lambda: 1_800_000_000,
            trade_enabled=True,
        )
        prepared = ledger._preflight(context, "close_position", {
            "instrumentType": "SWAP", "instrumentId": "BTC-USDT-SWAP", "positionId": "42",
            "positionSide": "short", "marginMode": "isolated",
        })
        self.assertEqual(prepared["summary"]["direction"], "short")
        self.assertEqual(prepared["summary"]["currentSize"], "2")

    def test_malformed_relevant_position_cannot_prove_absence(self) -> None:
        context = self._context({"instId": "BTC-USDT-SWAP", "pos": "2"})
        ledger = CommandLedger(
            object(), SimpleNamespace(_identity_digest=lambda *_: "remote-digest"), clock=lambda: 1_800_000_000,
            trade_enabled=True,
        )
        with self.assertRaises(CommandLedgerError) as unavailable:
            ledger._read_position(context, {
                "instrumentType": "SWAP", "instrumentId": "BTC-USDT-SWAP", "positionSide": "short",
                "marginMode": "isolated", "positionId": "42",
            })
        self.assertEqual((unavailable.exception.status, unavailable.exception.code), (502, "position_unavailable"))

    def test_margin_hedge_close_is_rejected_before_upstream(self) -> None:
        with self.assertRaises(CommandLedgerError) as unsupported:
            CommandLedger._identity("close_position", {
                "instrumentType": "MARGIN", "instrumentId": "BTC-USDT", "positionSide": "short",
                "marginMode": "isolated", "marginCurrency": "USDT",
            })
        self.assertEqual(unsupported.exception.code, "action_invalid")


if __name__ == "__main__":
    unittest.main()
