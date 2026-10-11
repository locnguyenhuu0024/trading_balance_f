from __future__ import annotations

import unittest
import hashlib
import json
import multiprocessing
import os
import secrets
import threading
import time
from tempfile import TemporaryDirectory
from types import SimpleNamespace
from decimal import Decimal
from urllib.parse import parse_qs, urlsplit

from backend.account_context import BinanceClientBundle, create_exchange_client
from backend.auth import IdentityAuthService
from backend.command_ledger import CommandLedger, CommandLedgerError
from backend.connections import ConnectionContext, ConnectionServiceError, OwnedConnections
from backend.security import CryptoInvalidCiphertext, _totp_at
from backend.service import APIError, RuntimeSettings, TradeService
from backend.store import SQLiteIdentityStore
from backend.okx import OKXTransportError
from backend.exchanges.binance_transport import BinanceTransportError
from backend.exchanges.contracts import BinanceQuantityFilter, BinanceUSDMOrderFilters, decimal_add, decimal_subtract


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


class _BinanceFixtureTransport:
    has_injected_transport = True


class _BinanceFixtureSpot:
    def __init__(self, uid: str) -> None:
        self.uid = uid
        self.original_uid = uid
        self.enable_futures = True

    def account(self) -> dict[str, object]:
        return {"uid": self.uid}

    def restrictions(self) -> dict[str, bool]:
        return {"enableReading": True, "enableWithdrawals": False, "enableFutures": self.enable_futures}


class _BinanceFixtureUSDM:
    def __init__(self, positions: list[dict[str, str]]) -> None:
        self.positions = [dict(row) for row in positions]
        self.can_trade = True
        self.portfolio_margin = False
        self.dual_side_position = False
        self.filter_step_size = "0.000000001"
        self.writes: list[dict[str, str]] = []
        self.orders: dict[str, dict[str, object]] = {}
        self.lookups: list[tuple[str, str | None, str | None]] = []
        self.malformed_ack = False
        self.lose_response = False
        self.cancel_lost_response = False
        self.cancel_requests: list[dict[str, str]] = []
        self.lookup_overrides: list[dict[str, object]] = []
        self.next_state = "FILLED"
        self.partial_execution = "0.4"
        self.cancel_state_after: str | None = None
        self.unexpected_position_after_write: dict[str, str] | None = None
        self.block_started: threading.Event | None = None
        self.block_release: threading.Event | None = None

    def account(self) -> dict[str, object]:
        return {
            "assets": [], "positions": [], "canTrade": self.can_trade,
            "portfolioMargin": self.portfolio_margin, "multiAssetsMargin": False,
        }

    def position_mode(self) -> bool:
        return self.dual_side_position

    def position_rows(self, instrument: str | None = None) -> list[dict[str, str]]:
        rows = self.positions if instrument is None else [
            row for row in self.positions if row.get("symbol") == instrument
        ]
        return [dict(row) for row in rows]

    def order_filters(self, symbol: str) -> BinanceUSDMOrderFilters:
        return BinanceUSDMOrderFilters(
            symbol=symbol,
            lot_size=BinanceQuantityFilter(Decimal(self.filter_step_size), Decimal("1e100"), Decimal(self.filter_step_size)),
            market_lot_size=BinanceQuantityFilter(Decimal(self.filter_step_size), Decimal("1e100"), Decimal(self.filter_step_size)),
            metadata_version="fixture-metadata-v1",
        )

    def place_market_reduce(self, request: dict[str, str]) -> dict[str, object]:
        self.writes.append(dict(request))
        if self.block_started is not None:
            self.block_started.set()
            if self.block_release is None or not self.block_release.wait(5):
                raise AssertionError("fixture write barrier was not released")
            self.block_started = None
            self.block_release = None
        position = next(row for row in self.positions if row["symbol"] == request["symbol"])
        current = Decimal(position["positionAmt"])
        quantity = Decimal(request["quantity"])
        executed = quantity if self.next_state == "FILLED" else Decimal(self.partial_execution)
        if request["side"] == "SELL":
            remaining = decimal_subtract(current, executed)
        else:
            remaining = decimal_add(current, executed)
        position["positionAmt"] = format(remaining, "f")
        if self.unexpected_position_after_write is not None:
            self.positions.append(dict(self.unexpected_position_after_write))
            self.unexpected_position_after_write = None
        order_id = str(7000 + len(self.writes))
        order = {
            "symbol": request["symbol"], "orderId": order_id,
            "clientOrderId": request["newClientOrderId"], "side": request["side"],
            "type": "MARKET", "positionSide": "BOTH", "reduceOnly": "true",
            "origQty": request["quantity"], "executedQty": format(executed, "f"),
            "status": self.next_state,
        }
        self.orders[request["newClientOrderId"]] = order
        if self.lose_response:
            self.lose_response = False
            raise BinanceTransportError(
                502, "outcome_unknown", "The exchange operation could not be confirmed.",
                http_status=200, native_code=-1000, definite_failure=False,
            )
        response = dict(order)
        if self.malformed_ack:
            self.malformed_ack = False
            response["status"] = ["FILLED"]
        return response

    def order_by_id(
        self, symbol: str, *, order_id: str | None = None, client_order_id: str | None = None,
    ) -> dict[str, object] | None:
        self.lookups.append((symbol, order_id, client_order_id))
        if self.lookup_overrides:
            return dict(self.lookup_overrides.pop(0))
        if client_order_id is not None:
            order = self.orders.get(client_order_id)
        else:
            order = next((row for row in self.orders.values() if row["orderId"] == order_id), None)
        return None if order is None else dict(order)

    def cancel_regular_order(self, request: dict[str, str]) -> dict[str, object]:
        self.cancel_requests.append(dict(request))
        order = next(row for row in self.orders.values() if row["orderId"] == request["orderId"])
        order["status"] = self.cancel_state_after or "CANCELED"
        if order["status"] == "FILLED":
            order["executedQty"] = order["origQty"]
        if self.cancel_lost_response:
            self.cancel_lost_response = False
            raise BinanceTransportError(
                502, "outcome_unknown", "The exchange operation could not be confirmed.",
                http_status=None, definite_failure=False,
            )
        return dict(order)

    def fill_order(self, client_order_id: str) -> None:
        order = self.orders[client_order_id]
        order["executedQty"] = order["origQty"]
        order["status"] = "FILLED"
        position = next(row for row in self.positions if row["symbol"] == order["symbol"])
        position["positionAmt"] = "0"


class BinanceCommandExecutionTests(_OwnedCommandTestBase):
    connection_id = "connection-binance-command"

    def setUp(self) -> None:
        super().setUp()
        self._fixture_serial = 0

    def _binance_fixture(
        self, positions: list[dict[str, str]] | None = None,
    ) -> tuple[str, CommandLedger, object, _BinanceFixtureSpot, _BinanceFixtureUSDM, ConnectionContext]:
        self._fixture_serial += 1
        self.connection_id = f"connection-binance-command-{self._fixture_serial}"
        token, user_id = self._ordinary_session(f"Owner.Binance{self._fixture_serial}")
        with self.store.transaction() as connection:
            connection.execute(
                "UPDATE user_sessions SET step_up_until=? WHERE user_id=?",
                (self.now + 300, user_id),
            )
            uid = f"12345678{self._fixture_serial}"
            remote_digest = self.service.connections._identity_digest("BINANCE", "demo", "global", uid)
            connection.execute(
                "INSERT INTO exchange_connections(user_id, connection_id, exchange, environment, region, "
                "product_capabilities_json, status, remote_identity_digest, credential_version, permission_version, "
                "created_at, updated_at) VALUES (?, ?, 'BINANCE', 'demo', 'global', '[\"read:USD_M\"]', "
                "'ACTIVE', ?, 1, 1, ?, ?)",
                (user_id, self.connection_id, remote_digest, self.now, self.now),
            )
        principal = self.service.identity_auth.validate_session(token)
        spot = _BinanceFixtureSpot(uid)
        usdm = _BinanceFixtureUSDM(positions or [{
            "symbol": "BTCUSDT", "positionAmt": "1", "positionSide": "BOTH", "marginType": "cross",
        }])
        bundle = BinanceClientBundle(_BinanceFixtureTransport(), spot, usdm, "demo", "global")
        context = ConnectionContext(
            user_id, self.connection_id, "BINANCE", "demo", "global", 1, 1,
            ("read:USD_M",), remote_digest, bundle,
        )
        self.service.connections.account_context = lambda *_args, **_kwargs: context
        self.service.connections.account_context_for_job = lambda *_args, **_kwargs: context
        ledger = CommandLedger(
            self.store, self.service.connections, clock=lambda: self.now,
            trade_enabled=True, allow_binance_fixtures=True,
        )
        return user_id, ledger, principal, spot, usdm, context

    def _prepare_binance(
        self, ledger: CommandLedger, principal: object, action: str = "close_position",
        identity: dict[str, str] | None = None,
    ) -> dict[str, object]:
        if identity is None:
            identity = {"product": "USD_M", "instrumentId": "BTCUSDT", "positionSide": "BOTH"}
        return ledger.prepare(principal, self.connection_id, {"action": action, "targetIdentity": identity})

    @staticmethod
    def _execute_body(prepared: dict[str, object], key: str) -> dict[str, str]:
        return {"confirmationToken": str(prepared["confirmationToken"]), "idempotencyKey": key}

    def test_actual_binance_adapters_execute_through_sqlite_with_fabricated_native_callbacks(self) -> None:
        user_id, ledger, principal, fixture_spot, _usdm, context = self._binance_fixture()
        positions = [{
            "symbol": "BTCUSDT", "positionAmt": "1", "positionSide": "BOTH", "marginType": "cross",
        }]
        orders: dict[str, dict[str, object]] = {}
        callbacks: list[tuple[str, str, dict[str, str]]] = []

        def native_callback(
            method: str, request_path: str, headers: dict[str, str], body: bytes | None,
        ) -> dict[str, object] | list[dict[str, object]]:
            parsed = urlsplit(request_path)
            query = {key: values[-1] for key, values in parse_qs(parsed.query).items()}
            callbacks.append((method, parsed.path, dict(headers)))
            self.assertIsNone(body)
            if parsed.path in {"/api/v3/time", "/fapi/v1/time"}:
                return {"serverTime": int(self.now * 1000)}
            if parsed.path in {"/api/v3/account", "/sapi/v1/account/apiRestrictions", "/fapi/v2/account", "/fapi/v1/positionSide/dual", "/fapi/v2/positionRisk", "/fapi/v1/order"}:
                self.assertEqual(headers.get("X-MBX-APIKEY"), "fabricated-key")
            if parsed.path == "/api/v3/account":
                return {"uid": fixture_spot.uid, "balances": []}
            if parsed.path == "/sapi/v1/account/apiRestrictions":
                return {"enableReading": True, "enableWithdrawals": False, "enableFutures": True}
            if parsed.path == "/fapi/v2/account":
                return {
                    "assets": [], "positions": [], "canTrade": True,
                    "portfolioMargin": False, "multiAssetsMargin": False,
                }
            if parsed.path == "/fapi/v1/positionSide/dual":
                return {"dualSidePosition": False}
            if parsed.path == "/fapi/v2/positionRisk":
                symbol = query.get("symbol")
                return [dict(row) for row in positions if symbol is None or row["symbol"] == symbol]
            if parsed.path == "/fapi/v1/exchangeInfo":
                return {"symbols": [{
                    "symbol": "BTCUSDT", "status": "TRADING", "filters": [
                        {"filterType": "LOT_SIZE", "minQty": "0.001", "maxQty": "100", "stepSize": "0.001"},
                        {"filterType": "MARKET_LOT_SIZE", "minQty": "0.001", "maxQty": "100", "stepSize": "0.001"},
                    ],
                }]}
            if parsed.path == "/fapi/v1/order" and method == "POST":
                quantity = query["quantity"]
                position = positions[0]
                position["positionAmt"] = format(decimal_subtract(Decimal(position["positionAmt"]), Decimal(quantity)), "f")
                order = {
                    "symbol": query["symbol"], "orderId": 7201,
                    "clientOrderId": query["newClientOrderId"], "side": query["side"],
                    "type": query["type"], "positionSide": query["positionSide"],
                    "reduceOnly": query["reduceOnly"], "origQty": quantity,
                    "executedQty": quantity, "status": "FILLED",
                }
                orders[order["clientOrderId"]] = order
                return dict(order)
            if parsed.path == "/fapi/v1/order" and method == "GET":
                order = orders.get(query.get("origClientOrderId", ""))
                return {"code": -2013, "msg": "Order does not exist"} if order is None else dict(order)
            raise AssertionError(f"unexpected fabricated Binance request: {method} {parsed.path}")

        bundle = create_exchange_client(
            {"apiKey": "fabricated-key", "apiSecret": "fabricated-secret"},
            exchange="BINANCE", environment="demo", region="global",
            transport=native_callback, clock=lambda: self.now,
        )
        native_context = ConnectionContext(
            context.user_id, context.connection_id, context.exchange, context.environment,
            context.region, context.credential_version, context.permission_version,
            context.capabilities, context.remote_identity_digest, bundle,
        )
        self.service.connections.account_context = lambda *_args, **_kwargs: native_context
        self.service.connections.account_context_for_job = lambda *_args, **_kwargs: native_context

        self.assertIsInstance(self.store, SQLiteIdentityStore)
        self.assertTrue(bundle.transport.has_injected_transport)
        prepared = self._prepare_binance(ledger, principal)
        completed = ledger.execute(
            principal, self.connection_id, str(prepared["operationId"]),
            self._execute_body(prepared, "binance-adapter-sqlite-e2e"),
        )

        self.assertEqual(completed["status"], "SUCCEEDED")
        self.assertEqual(completed["targets"][0]["result"]["remainingPosition"], "0")
        self.assertEqual(positions[0]["positionAmt"], "0")
        self.assertEqual(len(orders), 1)
        self.assertIn(("POST", "/fapi/v1/order"), [(method, path) for method, path, _headers in callbacks])
        self.assertTrue(all(method in {"GET", "POST"} for method, _path, _headers in callbacks))
        with self.store.connection() as connection:
            event_count = connection.execute(
                "SELECT COUNT(*) AS n FROM multiuser_operation_events WHERE user_id=? AND connection_id=? AND operation_id=?",
                (user_id, self.connection_id, prepared["operationId"]),
            ).fetchone()["n"]
        self.assertGreater(event_count, 0)

    def test_malformed_ack_stays_unknown_until_explicit_reconciliation(self) -> None:
        _user_id, ledger, principal, _spot, usdm, _context = self._binance_fixture()
        usdm.malformed_ack = True
        prepared = self._prepare_binance(ledger, principal)

        first = ledger.execute(
            principal, self.connection_id, str(prepared["operationId"]),
            self._execute_body(prepared, "binance-ack-unknown-01"),
        )
        self.assertEqual(first["status"], "UNKNOWN")
        self.assertEqual(usdm.lookups, [])
        self.assertEqual(first["targets"][0]["status"], "UNKNOWN")

        reconciled = ledger.reconcile(principal, self.connection_id, str(prepared["operationId"]))
        self.assertEqual(reconciled["status"], "SUCCEEDED")
        self.assertEqual(len(usdm.writes), 1)
        self.assertEqual(len(usdm.lookups), 1)

    def test_uncertain_send_uses_read_only_same_uid_reconciliation_without_resend(self) -> None:
        _user_id, ledger, principal, spot, usdm, _context = self._binance_fixture()
        usdm.lose_response = True
        prepared = self._prepare_binance(ledger, principal)
        first = ledger.execute(
            principal, self.connection_id, str(prepared["operationId"]),
            self._execute_body(prepared, "binance-timeout-unknown-01"),
        )
        self.assertEqual(first["status"], "UNKNOWN")
        self.assertEqual(usdm.lookups, [])
        self.assertEqual(len(usdm.writes), 1)

        spot.uid = "987654321"
        changed = ledger.reconcile(principal, self.connection_id, str(prepared["operationId"]))
        self.assertEqual(changed["status"], "UNKNOWN")
        self.assertEqual(len(usdm.writes), 1)
        self.assertEqual(usdm.lookups, [])

        spot.uid = spot.original_uid
        usdm.can_trade = False
        resolved = ledger.reconcile(principal, self.connection_id, str(prepared["operationId"]))
        self.assertEqual(resolved["status"], "SUCCEEDED")
        self.assertEqual(len(usdm.writes), 1)
        self.assertEqual(len(usdm.lookups), 1)

    def test_read_only_account_cannot_prepare_a_new_write(self) -> None:
        _user_id, ledger, principal, _spot, usdm, _context = self._binance_fixture()
        usdm.can_trade = False
        with self.assertRaises(CommandLedgerError) as denied:
            self._prepare_binance(ledger, principal)
        self.assertEqual(denied.exception.code, "capability_unsupported")
        self.assertEqual(usdm.writes, [])

    def test_unsupported_hedge_portfolio_spot_and_algo_targets_reject_before_prepare(self) -> None:
        for case in ("hedge", "portfolio_margin", "spot", "algo"):
            with self.subTest(case=case):
                user_id, ledger, principal, _spot, usdm, _context = self._binance_fixture()
                if case == "hedge":
                    usdm.dual_side_position = True
                elif case == "portfolio_margin":
                    usdm.portfolio_margin = True
                elif case == "algo":
                    order = {
                        "symbol": "BTCUSDT", "orderId": "8802", "clientOrderId": "fixture-algo-8802",
                        "type": "STOP", "side": "SELL", "origQty": "2", "executedQty": "0",
                        "price": "100", "status": "NEW",
                    }
                    usdm.orders[order["clientOrderId"]] = order

                with self.assertRaises(CommandLedgerError):
                    if case == "spot":
                        self._prepare_binance(ledger, principal, identity={
                            "product": "SPOT", "instrumentId": "BTCUSDT", "positionSide": "BOTH",
                        })
                    elif case == "algo":
                        self._prepare_binance(ledger, principal, "cancel_order", {
                            "product": "USD_M", "instrumentId": "BTCUSDT", "orderId": "8802",
                        })
                    else:
                        self._prepare_binance(ledger, principal)
                self.assertEqual(usdm.writes, [])
                self.assertEqual(usdm.cancel_requests, [])
                with self.store.connection() as connection:
                    operation_count = connection.execute(
                        "SELECT COUNT(*) AS n FROM multiuser_operations WHERE user_id=? AND connection_id=?",
                        (user_id, self.connection_id),
                    ).fetchone()["n"]
                    target_count = connection.execute(
                        "SELECT COUNT(*) AS n FROM multiuser_command_targets WHERE user_id=? AND connection_id=?",
                        (user_id, self.connection_id),
                    ).fetchone()["n"]
                self.assertEqual((operation_count, target_count), (0, 0))

    def test_wrong_owner_public_gate_and_default_fixture_policy_reject_even_when_enabled(self) -> None:
        user_id, ledger, principal, _spot, usdm, _context = self._binance_fixture()
        wrong_token, wrong_user_id = self._ordinary_session("Other.BinanceOwner")
        with self.store.transaction() as connection:
            connection.execute(
                "UPDATE user_sessions SET step_up_until=? WHERE user_id=?",
                (self.now + 300, wrong_user_id),
            )
        wrong_principal = self.service.identity_auth.validate_session(wrong_token)
        with self.assertRaises(CommandLedgerError) as wrong_owner:
            self._prepare_binance(ledger, wrong_principal)
        self.assertEqual(wrong_owner.exception.code, "not_found")

        with self.assertRaises(ConnectionServiceError) as public_gate:
            self.service.connections.assert_action_supported(principal, self.connection_id)
        self.assertEqual(public_gate.exception.code, "capability_unsupported")

        default_policy_ledger = CommandLedger(
            self.store, self.service.connections, clock=lambda: self.now, trade_enabled=True,
        )
        with self.assertRaises(CommandLedgerError) as default_policy:
            self._prepare_binance(default_policy_ledger, principal)
        self.assertEqual(default_policy.exception.code, "capability_unsupported")
        self.assertEqual(usdm.writes, [])
        self.assertEqual(usdm.cancel_requests, [])
        with self.store.connection() as connection:
            owner_count = connection.execute(
                "SELECT COUNT(*) AS n FROM multiuser_operations WHERE user_id=? AND connection_id=?",
                (user_id, self.connection_id),
            ).fetchone()["n"]
            wrong_user_count = connection.execute(
                "SELECT COUNT(*) AS n FROM multiuser_operations WHERE user_id=? AND connection_id=?",
                (wrong_user_id, self.connection_id),
            ).fetchone()["n"]
        self.assertEqual((owner_count, wrong_user_count), (0, 0))

    def test_prepare_execute_snapshot_changes_leave_no_write_marker(self) -> None:
        mutations = ("size", "sign", "filters", "exchange_permission", "connection_permission")
        for case in mutations:
            with self.subTest(case=case):
                user_id, ledger, principal, spot, usdm, _context = self._binance_fixture()
                prepared = self._prepare_binance(ledger, principal)
                operation_id = str(prepared["operationId"])
                if case == "size":
                    usdm.positions[0]["positionAmt"] = "2"
                elif case == "sign":
                    usdm.positions[0]["positionAmt"] = "-1"
                elif case == "filters":
                    usdm.filter_step_size = "0.0001"
                elif case == "exchange_permission":
                    spot.enable_futures = False
                else:
                    with self.store.transaction() as connection:
                        connection.execute(
                            "UPDATE exchange_connections SET permission_version=permission_version+1 "
                            "WHERE user_id=? AND connection_id=?",
                            (user_id, self.connection_id),
                        )
                try:
                    ledger.execute(
                        principal, self.connection_id, operation_id,
                        self._execute_body(prepared, f"binance-snapshot-change-{case}"),
                    )
                except CommandLedgerError:
                    pass
                self.assertEqual(usdm.writes, [])
                self.assertEqual(usdm.cancel_requests, [])
                with self.store.connection() as connection:
                    operation = connection.execute(
                        "SELECT pre_send_at FROM multiuser_operations WHERE user_id=? AND connection_id=? AND operation_id=?",
                        (user_id, self.connection_id, operation_id),
                    ).fetchone()
                    target = connection.execute(
                        "SELECT status, pre_send_at FROM multiuser_command_targets "
                        "WHERE user_id=? AND connection_id=? AND operation_id=? AND target_index=0",
                        (user_id, self.connection_id, operation_id),
                    ).fetchone()
                self.assertIsNone(operation["pre_send_at"])
                self.assertIsNone(target["pre_send_at"])
                self.assertNotEqual(target["status"], "ATTEMPT_STARTED")

    def test_partial_close_exact_fill_and_residual_position(self) -> None:
        for quantity, expected_remaining in (("1", "0"), ("0.4", "0.6")):
            with self.subTest(quantity=quantity):
                _user_id, ledger, principal, _spot, usdm, _context = self._binance_fixture()
                prepared = self._prepare_binance(ledger, principal, "partial_close", {
                    "product": "USD_M", "instrumentId": "BTCUSDT", "positionSide": "BOTH",
                    "quantity": quantity,
                })
                completed = ledger.execute(
                    principal, self.connection_id, str(prepared["operationId"]),
                    self._execute_body(prepared, f"binance-partial-close-{quantity}"),
                )
                self.assertEqual(completed["status"], "SUCCEEDED")
                self.assertEqual(usdm.writes[0]["quantity"], quantity)
                self.assertEqual(usdm.writes[0]["side"], "SELL")
                self.assertEqual(usdm.positions[0]["positionAmt"], expected_remaining)
                self.assertEqual(completed["targets"][0]["result"]["remainingPosition"], expected_remaining)
                self.assertEqual(len(usdm.writes), 1)

    def test_regular_cancel_zero_partial_and_filled_races(self) -> None:
        scenarios = (
            ("zero_fill", "NEW", "0", None, "SUCCEEDED"),
            ("partial_fill", "PARTIALLY_FILLED", "0.4", None, "PARTIAL"),
            ("filled_race", "NEW", "0", "FILLED", "FAILED"),
        )
        for case, initial_state, executed, cancel_state, expected in scenarios:
            with self.subTest(case=case):
                _user_id, ledger, principal, _spot, usdm, _context = self._binance_fixture()
                order = {
                    "symbol": "BTCUSDT", "orderId": "8803", "clientOrderId": f"fixture-{case}-8803",
                    "type": "LIMIT", "side": "SELL", "origQty": "2", "executedQty": executed,
                    "price": "100", "status": initial_state,
                }
                usdm.orders[order["clientOrderId"]] = order
                usdm.cancel_state_after = cancel_state
                prepared = self._prepare_binance(ledger, principal, "cancel_order", {
                    "product": "USD_M", "instrumentId": "BTCUSDT", "orderId": "8803",
                })
                completed = ledger.execute(
                    principal, self.connection_id, str(prepared["operationId"]),
                    self._execute_body(prepared, f"binance-cancel-race-{case}"),
                )
                self.assertEqual(completed["status"], expected)
                self.assertEqual(len(usdm.cancel_requests), 1)
                self.assertEqual(len(usdm.writes), 0)
                self.assertEqual(completed["targets"][0]["result"]["orderState"], cancel_state or "CANCELED")

    def test_close_all_twenty_boundary_and_twenty_one_rejection(self) -> None:
        symbols_20 = [f"T{index:03d}USDT" for index in range(20)]
        user_id, ledger, principal, _spot, usdm, _context = self._binance_fixture([
            {"symbol": symbol, "positionAmt": "1", "positionSide": "BOTH", "marginType": "cross"}
            for symbol in symbols_20
        ])
        prepared = self._prepare_binance(ledger, principal, "close_all", {"product": "USD_M"})
        self.assertEqual(len(prepared["targets"]), 20)
        completed = ledger.execute(
            principal, self.connection_id, str(prepared["operationId"]),
            self._execute_body(prepared, "binance-close-all-twenty"),
        )
        self.assertEqual(completed["status"], "SUCCEEDED")
        self.assertEqual(len(usdm.writes), 20)
        self.assertTrue(all(row["positionAmt"] == "0" for row in usdm.positions))

        user_id, ledger, principal, _spot, usdm, _context = self._binance_fixture([
            {"symbol": f"T{index:03d}USDT", "positionAmt": "1", "positionSide": "BOTH", "marginType": "cross"}
            for index in range(21)
        ])
        with self.assertRaises(CommandLedgerError) as rejected:
            self._prepare_binance(ledger, principal, "close_all", {"product": "USD_M"})
        self.assertEqual(rejected.exception.code, "capability_unsupported")
        self.assertEqual(usdm.writes, [])
        with self.store.connection() as connection:
            operation_count = connection.execute(
                "SELECT COUNT(*) AS n FROM multiuser_operations WHERE user_id=? AND connection_id=?",
                (user_id, self.connection_id),
            ).fetchone()["n"]
        self.assertEqual(operation_count, 0)

    def test_close_all_final_scope_rejects_unexpected_exposure(self) -> None:
        _user_id, ledger, principal, _spot, usdm, _context = self._binance_fixture()
        usdm.unexpected_position_after_write = {
            "symbol": "ETHUSDT", "positionAmt": "0.5", "positionSide": "BOTH", "marginType": "cross",
        }
        prepared = self._prepare_binance(ledger, principal, "close_all", {"product": "USD_M"})
        completed = ledger.execute(
            principal, self.connection_id, str(prepared["operationId"]),
            self._execute_body(prepared, "binance-close-all-unexpected-exposure"),
        )
        self.assertEqual(completed["status"], "PARTIAL")
        self.assertEqual(completed["targets"][0]["result"]["reason"], "unexpected_exposure")
        self.assertEqual(completed["targets"][0]["result"]["remainingSymbol"], "ETHUSDT")
        self.assertEqual(len(usdm.writes), 1)

    def test_logout_between_close_all_targets_stops_without_marking_tail(self) -> None:
        user_id, ledger, principal, _spot, usdm, _context = self._binance_fixture([
            {"symbol": "BTCUSDT", "positionAmt": "1", "positionSide": "BOTH", "marginType": "cross"},
            {"symbol": "ETHUSDT", "positionAmt": "2", "positionSide": "BOTH", "marginType": "cross"},
        ])
        prepared = self._prepare_binance(ledger, principal, "close_all", {"product": "USD_M"})
        original_record = ledger._record_binance_target

        def logout_after_first(*args: object, **kwargs: object) -> bool:
            result = original_record(*args, **kwargs)
            if int(args[3]) == 0:
                self.service.identity_auth.logout(principal)
            return result

        ledger._record_binance_target = logout_after_first  # type: ignore[method-assign]
        with self.assertRaises(CommandLedgerError):
            ledger.execute(
                principal, self.connection_id, str(prepared["operationId"]),
                self._execute_body(prepared, "binance-close-all-logout"),
            )
        self.assertEqual(len(usdm.writes), 1)
        with self.store.connection() as connection:
            operation = connection.execute(
                "SELECT status FROM multiuser_operations WHERE user_id=? AND connection_id=? AND operation_id=?",
                (user_id, self.connection_id, prepared["operationId"]),
            ).fetchone()
            tail = connection.execute(
                "SELECT status, pre_send_at FROM multiuser_command_targets "
                "WHERE user_id=? AND connection_id=? AND operation_id=? AND target_index=1",
                (user_id, self.connection_id, prepared["operationId"]),
            ).fetchone()
            send_markers = connection.execute(
                "SELECT COUNT(*) AS n FROM multiuser_operation_events WHERE user_id=? AND connection_id=? "
                "AND operation_id=? AND event_type='action_send_marked'",
                (user_id, self.connection_id, prepared["operationId"]),
            ).fetchone()["n"]
        self.assertEqual(operation["status"], "SENDING")
        self.assertEqual((tail["status"], tail["pre_send_at"]), ("PREPARED", None))
        self.assertEqual(send_markers, 1)

    def test_live_partial_fill_stays_unknown_then_reconciles_without_resubmission(self) -> None:
        _user_id, ledger, principal, _spot, usdm, _context = self._binance_fixture()
        usdm.next_state = "PARTIALLY_FILLED"
        prepared = self._prepare_binance(ledger, principal)
        first = ledger.execute(
            principal, self.connection_id, str(prepared["operationId"]),
            self._execute_body(prepared, "binance-partial-live-01"),
        )
        self.assertEqual(first["status"], "UNKNOWN")
        self.assertEqual(first["targets"][0]["result"]["orderState"], "PARTIALLY_FILLED")
        self.assertEqual(len(usdm.writes), 1)
        self.assertEqual(len(usdm.lookups), 1)

        client_order_id = usdm.writes[0]["newClientOrderId"]
        usdm.fill_order(client_order_id)
        resolved = ledger.reconcile(principal, self.connection_id, str(prepared["operationId"]))
        self.assertEqual(resolved["status"], "SUCCEEDED")
        self.assertEqual(len(usdm.writes), 1)
        self.assertEqual(len(usdm.lookups), 2)

    def test_malformed_cancel_observations_are_sanitized_and_never_resubmitted(self) -> None:
        _user_id, ledger, principal, _spot, usdm, _context = self._binance_fixture()
        order = {
            "symbol": "BTCUSDT", "orderId": "8801", "clientOrderId": "fixture-order-8801",
            "type": "LIMIT", "side": "SELL", "origQty": "2", "executedQty": "0",
            "price": "100", "status": "NEW",
        }
        usdm.orders[order["clientOrderId"]] = order
        usdm.cancel_lost_response = True
        prepared = self._prepare_binance(ledger, principal, "cancel_order", {
            "product": "USD_M", "instrumentId": "BTCUSDT", "orderId": "8801",
        })
        first = ledger.execute(
            principal, self.connection_id, str(prepared["operationId"]),
            self._execute_body(prepared, "binance-cancel-unknown-01"),
        )
        self.assertEqual(first["status"], "UNKNOWN")
        self.assertEqual(len(usdm.lookups), 2)  # prepare + fresh execute preflight; no post-marker observation
        malformed = [
            {**order, "status": ["RAW_NATIVE_STATUS"]},
            {**order, "price": float("nan")},
            {**order, "orderId": ["8801"]},
        ]
        for observation in malformed:
            usdm.lookup_overrides.append(observation)
            unresolved = ledger.reconcile(principal, self.connection_id, str(prepared["operationId"]))
            self.assertEqual(unresolved["status"], "UNKNOWN")
            self.assertEqual(unresolved["targets"][0]["result"]["reason"], "order_state_unavailable")
            self.assertNotIn("RAW_NATIVE_STATUS", json.dumps(unresolved))
        self.assertEqual(len(usdm.cancel_requests), 1)
        self.assertEqual(len(usdm.lookups), 5)

    def test_expiry_during_final_principal_check_creates_no_send_marker(self) -> None:
        user_id, ledger, principal, _spot, usdm, _context = self._binance_fixture()
        prepared = self._prepare_binance(ledger, principal)
        original_require = ledger._require_principal
        step_up_calls = 0

        def crossing_expiry(connection: object, checked_principal: object, *, step_up: bool) -> None:
            nonlocal step_up_calls
            original_require(connection, checked_principal, step_up=step_up)
            if step_up:
                step_up_calls += 1
                if step_up_calls == 2:
                    self.now += CommandLedger.CONFIRMATION_SECONDS + 1

        ledger._require_principal = crossing_expiry  # type: ignore[method-assign]
        with self.assertRaises(CommandLedgerError):
            ledger.execute(
                principal, self.connection_id, str(prepared["operationId"]),
                self._execute_body(prepared, "binance-expiry-final-check"),
            )
        self.assertEqual(usdm.writes, [])
        with self.store.connection() as connection:
            operation = connection.execute(
                "SELECT status, pre_send_at, confirmation_digest FROM multiuser_operations "
                "WHERE user_id=? AND connection_id=? AND operation_id=?",
                (user_id, self.connection_id, prepared["operationId"]),
            ).fetchone()
            target = connection.execute(
                "SELECT status, pre_send_at FROM multiuser_command_targets "
                "WHERE user_id=? AND connection_id=? AND operation_id=? AND target_index=0",
                (user_id, self.connection_id, prepared["operationId"]),
            ).fetchone()
        self.assertEqual(operation["status"], "PREPARED")
        self.assertIsNone(operation["pre_send_at"])
        self.assertIsNotNone(operation["confirmation_digest"])
        self.assertEqual((target["status"], target["pre_send_at"]), ("PREPARED", None))

    def test_close_all_keeps_one_fence_between_targets_and_rejects_competing_claim(self) -> None:
        user_id, ledger, principal, _spot, usdm, _context = self._binance_fixture([
            {"symbol": "BTCUSDT", "positionAmt": "1", "positionSide": "BOTH", "marginType": "cross"},
            {"symbol": "ETHUSDT", "positionAmt": "2", "positionSide": "BOTH", "marginType": "cross"},
        ])
        close_all = self._prepare_binance(ledger, principal, "close_all", {"product": "USD_M"})
        competing = self._prepare_binance(ledger, principal, "partial_close", {
            "product": "USD_M", "instrumentId": "ETHUSDT", "positionSide": "BOTH", "quantity": "1",
        })
        original_record = ledger._record_binance_target
        observed_fence: int | None = None
        loser_error: CommandLedgerError | None = None

        def inspect_between_targets(*args: object, **kwargs: object) -> bool:
            nonlocal observed_fence, loser_error
            result = original_record(*args, **kwargs)
            target_index = int(args[3])
            if target_index == 0:
                with self.store.connection() as connection:
                    lease = connection.execute(
                        "SELECT lease_owner, fence, lease_until FROM multiuser_connection_leases "
                        "WHERE user_id=? AND connection_id=?",
                        (user_id, self.connection_id),
                    ).fetchone()
                observed_fence = int(lease["fence"])
                self.assertEqual(lease["lease_owner"], close_all["operationId"])
                self.assertGreater(float(lease["lease_until"]), self.now)
                try:
                    ledger.execute(
                        principal, self.connection_id, str(competing["operationId"]),
                        self._execute_body(competing, "binance-competing-claim-01"),
                    )
                except CommandLedgerError as error:
                    loser_error = error
                with self.store.connection() as connection:
                    after = connection.execute(
                        "SELECT lease_owner, fence, lease_until FROM multiuser_connection_leases "
                        "WHERE user_id=? AND connection_id=?",
                        (user_id, self.connection_id),
                    ).fetchone()
                    losing_operation = connection.execute(
                        "SELECT status, pre_send_at FROM multiuser_operations WHERE user_id=? AND connection_id=? AND operation_id=?",
                        (user_id, self.connection_id, competing["operationId"]),
                    ).fetchone()
                    losing_target = connection.execute(
                        "SELECT status, pre_send_at FROM multiuser_command_targets WHERE user_id=? AND connection_id=? AND operation_id=? AND target_index=0",
                        (user_id, self.connection_id, competing["operationId"]),
                    ).fetchone()
                self.assertEqual((after["lease_owner"], int(after["fence"])), (close_all["operationId"], observed_fence))
                self.assertEqual((losing_operation["status"], losing_operation["pre_send_at"]), ("PREPARED", None))
                self.assertEqual((losing_target["status"], losing_target["pre_send_at"]), ("PREPARED", None))
            return result

        ledger._record_binance_target = inspect_between_targets  # type: ignore[method-assign]
        completed = ledger.execute(
            principal, self.connection_id, str(close_all["operationId"]),
            self._execute_body(close_all, "binance-closeall-fenced-01"),
        )
        self.assertEqual(completed["status"], "SUCCEEDED")
        self.assertEqual(loser_error.code if loser_error else None, "action_changed")
        self.assertEqual(len(usdm.writes), 2)
        with self.store.connection() as connection:
            events = connection.execute(
                "SELECT payload_json FROM multiuser_operation_events WHERE user_id=? AND connection_id=? "
                "AND operation_id=? AND event_type='action_send_marked' ORDER BY created_at, event_id",
                (user_id, self.connection_id, close_all["operationId"]),
            ).fetchall()
        self.assertEqual([json.loads(row["payload_json"])["fence"] for row in events], [observed_fence, observed_fence])

    def test_stolen_between_target_fence_blocks_unsent_tail(self) -> None:
        user_id, ledger, principal, _spot, usdm, _context = self._binance_fixture([
            {"symbol": "BTCUSDT", "positionAmt": "1", "positionSide": "BOTH", "marginType": "cross"},
            {"symbol": "ETHUSDT", "positionAmt": "2", "positionSide": "BOTH", "marginType": "cross"},
        ])
        prepared = self._prepare_binance(ledger, principal, "close_all", {"product": "USD_M"})
        original_record = ledger._record_binance_target

        def steal_after_first(*args: object, **kwargs: object) -> bool:
            result = original_record(*args, **kwargs)
            if int(args[3]) == 0:
                with self.store.transaction() as connection:
                    lease = connection.execute(
                        "SELECT fence FROM multiuser_connection_leases WHERE user_id=? AND connection_id=?",
                        (user_id, self.connection_id),
                    ).fetchone()
                    connection.execute(
                        "UPDATE multiuser_connection_leases SET lease_owner='fixture-foreign-owner', "
                        "operation_id='fixture-foreign-operation', fence=?, lease_until=?, updated_at=? "
                        "WHERE user_id=? AND connection_id=?",
                        (int(lease["fence"]) + 1, self.now + CommandLedger.LEASE_SECONDS, self.now,
                         user_id, self.connection_id),
                    )
            return result

        ledger._record_binance_target = steal_after_first  # type: ignore[method-assign]
        with self.assertRaises(CommandLedgerError):
            ledger.execute(
                principal, self.connection_id, str(prepared["operationId"]),
                self._execute_body(prepared, "binance-stolen-fence-01"),
            )
        self.assertEqual(len(usdm.writes), 1)
        with self.store.connection() as connection:
            operation = connection.execute(
                "SELECT status FROM multiuser_operations WHERE user_id=? AND connection_id=? AND operation_id=?",
                (user_id, self.connection_id, prepared["operationId"]),
            ).fetchone()
            tail = connection.execute(
                "SELECT status, pre_send_at FROM multiuser_command_targets WHERE user_id=? AND connection_id=? AND operation_id=? AND target_index=1",
                (user_id, self.connection_id, prepared["operationId"]),
            ).fetchone()
            lease = connection.execute(
                "SELECT lease_owner, operation_id FROM multiuser_connection_leases WHERE user_id=? AND connection_id=?",
                (user_id, self.connection_id),
            ).fetchone()
        self.assertEqual(operation["status"], "SENDING")
        self.assertEqual((tail["status"], tail["pre_send_at"]), ("PREPARED", None))
        self.assertEqual((lease["lease_owner"], lease["operation_id"]), ("fixture-foreign-owner", "fixture-foreign-operation"))

    def test_recovered_fill_with_canceled_close_all_tail_is_partial_and_never_resumed(self) -> None:
        _user_id, ledger, principal, _spot, usdm, _context = self._binance_fixture([
            {"symbol": "BTCUSDT", "positionAmt": "1", "positionSide": "BOTH", "marginType": "cross"},
            {"symbol": "ETHUSDT", "positionAmt": "2", "positionSide": "BOTH", "marginType": "cross"},
        ])
        usdm.lose_response = True
        prepared = self._prepare_binance(ledger, principal, "close_all", {"product": "USD_M"})
        first = ledger.execute(
            principal, self.connection_id, str(prepared["operationId"]),
            self._execute_body(prepared, "binance-recovered-fill-tail-01"),
        )
        self.assertEqual(first["status"], "UNKNOWN")
        self.assertEqual([target["status"] for target in first["targets"]], ["UNKNOWN", "CANCELED"])
        self.assertEqual(len(usdm.writes), 1)
        lookups = len(usdm.lookups)

        recovered = ledger.reconcile(principal, self.connection_id, str(prepared["operationId"]))

        self.assertEqual(recovered["status"], "PARTIAL")
        self.assertEqual([target["status"] for target in recovered["targets"]], ["SUCCEEDED", "CANCELED"])
        self.assertEqual(len(usdm.writes), 1)
        self.assertEqual(len(usdm.lookups), lookups + 1)

    def test_crash_after_successful_prefix_recovers_partial_without_resuming_tail(self) -> None:
        _user_id, ledger, principal, _spot, usdm, _context = self._binance_fixture([
            {"symbol": "BTCUSDT", "positionAmt": "1", "positionSide": "BOTH", "marginType": "cross"},
            {"symbol": "ETHUSDT", "positionAmt": "2", "positionSide": "BOTH", "marginType": "cross"},
        ])
        prepared = self._prepare_binance(ledger, principal, "close_all", {"product": "USD_M"})
        original_record = ledger._record_binance_target

        def crash_after_first(*args: object, **kwargs: object) -> bool:
            result = original_record(*args, **kwargs)
            if int(args[3]) == 0:
                raise KeyboardInterrupt("simulated process interruption")
            return result

        ledger._record_binance_target = crash_after_first  # type: ignore[method-assign]
        with self.assertRaises(KeyboardInterrupt):
            ledger.execute(
                principal, self.connection_id, str(prepared["operationId"]),
                self._execute_body(prepared, "binance-crash-prefix-01"),
            )
        ledger._record_binance_target = original_record  # type: ignore[method-assign]
        before_lookups = len(usdm.lookups)
        self.now += CommandLedger.LEASE_SECONDS + 1

        recovered = ledger.reconcile(principal, self.connection_id, str(prepared["operationId"]))

        self.assertEqual(recovered["status"], "PARTIAL")
        self.assertEqual([target["status"] for target in recovered["targets"]], ["SUCCEEDED", "CANCELED"])
        self.assertEqual(len(usdm.writes), 1)
        self.assertEqual(len(usdm.lookups), before_lookups)
        with self.store.connection() as connection:
            tail = connection.execute(
                "SELECT status, pre_send_at FROM multiuser_command_targets WHERE operation_id=? AND target_index=1",
                (prepared["operationId"],),
            ).fetchone()
        self.assertEqual((tail["status"], tail["pre_send_at"]), ("CANCELED", None))

    def test_expired_reconciling_recovery_claim_is_taken_over_without_resending(self) -> None:
        user_id, ledger, principal, _spot, usdm, _context = self._binance_fixture([
            {"symbol": "BTCUSDT", "positionAmt": "1", "positionSide": "BOTH", "marginType": "cross"},
            {"symbol": "ETHUSDT", "positionAmt": "2", "positionSide": "BOTH", "marginType": "cross"},
        ])
        prepared = self._prepare_binance(ledger, principal, "close_all", {"product": "USD_M"})
        original_record = ledger._record_binance_target

        def crash_after_first(*args: object, **kwargs: object) -> bool:
            result = original_record(*args, **kwargs)
            if int(args[3]) == 0:
                raise KeyboardInterrupt("simulated process interruption")
            return result

        ledger._record_binance_target = crash_after_first  # type: ignore[method-assign]
        with self.assertRaises(KeyboardInterrupt):
            ledger.execute(
                principal, self.connection_id, str(prepared["operationId"]),
                self._execute_body(prepared, "binance-recovery-takeover-01"),
            )
        ledger._record_binance_target = original_record  # type: ignore[method-assign]
        self.now += CommandLedger.LEASE_SECONDS + 1

        original_finish = ledger._finish_binance_crash_recovery

        def crash_after_claim(*args: object, **kwargs: object) -> None:
            raise KeyboardInterrupt("simulated interruption after recovery claim")

        ledger._finish_binance_crash_recovery = crash_after_claim  # type: ignore[method-assign]
        with self.assertRaises(KeyboardInterrupt):
            ledger.reconcile(principal, self.connection_id, str(prepared["operationId"]))
        ledger._finish_binance_crash_recovery = original_finish  # type: ignore[method-assign]

        with self.store.connection() as connection:
            claimed = connection.execute(
                "SELECT status, lease_owner, lease_fence, lease_until FROM multiuser_operations "
                "WHERE user_id=? AND connection_id=? AND operation_id=?",
                (user_id, self.connection_id, prepared["operationId"]),
            ).fetchone()
            claim_lease = connection.execute(
                "SELECT lease_owner, fence, lease_until, operation_id FROM multiuser_connection_leases "
                "WHERE user_id=? AND connection_id=?",
                (user_id, self.connection_id),
            ).fetchone()
            tail = connection.execute(
                "SELECT status, pre_send_at FROM multiuser_command_targets "
                "WHERE user_id=? AND connection_id=? AND operation_id=? AND target_index=1",
                (user_id, self.connection_id, prepared["operationId"]),
            ).fetchone()
        self.assertEqual(claimed["status"], "RECONCILING")
        self.assertTrue(str(claimed["lease_owner"]).startswith("reconcile-"))
        self.assertEqual(claimed["lease_owner"], claim_lease["lease_owner"])
        self.assertEqual(int(claimed["lease_fence"]), int(claim_lease["fence"]))
        self.assertEqual(claim_lease["operation_id"], prepared["operationId"])
        self.assertEqual((tail["status"], tail["pre_send_at"]), ("PREPARED", None))
        prior_owner = claimed["lease_owner"]
        prior_fence = int(claim_lease["fence"])

        before_lookups = len(usdm.lookups)
        self.now += CommandLedger.LEASE_SECONDS + 1
        recovered = ledger.reconcile(principal, self.connection_id, str(prepared["operationId"]))

        self.assertEqual(recovered["status"], "PARTIAL")
        self.assertEqual([target["status"] for target in recovered["targets"]], ["SUCCEEDED", "CANCELED"])
        self.assertEqual(len(usdm.writes), 1)
        self.assertEqual(len(usdm.lookups), before_lookups)
        with self.store.connection() as connection:
            final_lease = connection.execute(
                "SELECT lease_owner, fence, operation_id FROM multiuser_connection_leases "
                "WHERE user_id=? AND connection_id=?",
                (user_id, self.connection_id),
            ).fetchone()
            final_operation = connection.execute(
                "SELECT status, lease_fence FROM multiuser_operations "
                "WHERE user_id=? AND connection_id=? AND operation_id=?",
                (user_id, self.connection_id, prepared["operationId"]),
            ).fetchone()
            final_tail = connection.execute(
                "SELECT status, pre_send_at FROM multiuser_command_targets "
                "WHERE user_id=? AND connection_id=? AND operation_id=? AND target_index=1",
                (user_id, self.connection_id, prepared["operationId"]),
            ).fetchone()
        self.assertIsNone(final_lease["lease_owner"])
        self.assertIsNone(final_lease["operation_id"])
        self.assertEqual(int(final_lease["fence"]), prior_fence + 1)
        self.assertEqual(final_operation["status"], "PARTIAL")
        self.assertEqual(int(final_operation["lease_fence"]), prior_fence + 1)
        self.assertNotEqual(prior_owner, final_lease["lease_owner"])
        self.assertEqual((final_tail["status"], final_tail["pre_send_at"]), ("CANCELED", None))

    def test_winner_marker_blocks_loser_and_preserves_winner_fence(self) -> None:
        user_id, ledger, principal, _spot, usdm, _context = self._binance_fixture()
        winner = self._prepare_binance(ledger, principal)
        loser = self._prepare_binance(ledger, principal)
        started = threading.Event()
        release = threading.Event()
        usdm.block_started = started
        usdm.block_release = release
        winner_results: list[dict[str, object]] = []
        worker_errors: list[str] = []

        def run_winner() -> None:
            try:
                winner_results.append(ledger.execute(
                    principal, self.connection_id, str(winner["operationId"]),
                    self._execute_body(winner, "binance-winner-claim-01"),
                ))
            except BaseException:
                import traceback
                worker_errors.append(traceback.format_exc())

        worker = threading.Thread(target=run_winner, daemon=True)
        worker.start()
        try:
            self.assertTrue(started.wait(3), f"winner did not reach the native send barrier: {worker_errors!r}")
            with self.assertRaises(CommandLedgerError) as rejected:
                ledger.execute(
                    principal, self.connection_id, str(loser["operationId"]),
                    self._execute_body(loser, "binance-loser-claim-01"),
                )
            self.assertEqual(rejected.exception.code, "action_changed")
            with self.store.connection() as connection:
                lease = connection.execute(
                    "SELECT lease_owner, fence FROM multiuser_connection_leases WHERE user_id=? AND connection_id=?",
                    (user_id, self.connection_id),
                ).fetchone()
                winner_state = connection.execute(
                    "SELECT status, pre_send_at FROM multiuser_operations WHERE user_id=? AND connection_id=? AND operation_id=?",
                    (user_id, self.connection_id, winner["operationId"]),
                ).fetchone()
                winner_target = connection.execute(
                    "SELECT status, pre_send_at FROM multiuser_command_targets WHERE user_id=? AND connection_id=? AND operation_id=? AND target_index=0",
                    (user_id, self.connection_id, winner["operationId"]),
                ).fetchone()
                loser_state = connection.execute(
                    "SELECT status, pre_send_at, confirmation_digest FROM multiuser_operations WHERE user_id=? AND connection_id=? AND operation_id=?",
                    (user_id, self.connection_id, loser["operationId"]),
                ).fetchone()
                loser_target = connection.execute(
                    "SELECT status, pre_send_at FROM multiuser_command_targets WHERE user_id=? AND connection_id=? AND operation_id=? AND target_index=0",
                    (user_id, self.connection_id, loser["operationId"]),
                ).fetchone()
            self.assertEqual(lease["lease_owner"], winner["operationId"])
            self.assertEqual((winner_state["status"], winner_target["status"]), ("SENDING", "ATTEMPT_STARTED"))
            self.assertIsNotNone(winner_target["pre_send_at"])
            self.assertEqual((loser_state["status"], loser_state["pre_send_at"]), ("PREPARED", None))
            self.assertIsNotNone(loser_state["confirmation_digest"])
            self.assertEqual((loser_target["status"], loser_target["pre_send_at"]), ("PREPARED", None))
            self.assertEqual(len(usdm.writes), 1)
        finally:
            release.set()
            worker.join(5)
        self.assertFalse(worker.is_alive())
        self.assertEqual(worker_errors, [])
        self.assertEqual(winner_results[0]["status"], "SUCCEEDED")
        self.assertEqual(len(usdm.writes), 1)

    def test_high_precision_signed_position_closes_exactly(self) -> None:
        amount = "-12345678901234567890123456789.123456789"
        _user_id, ledger, principal, _spot, usdm, _context = self._binance_fixture([{
            "symbol": "BTCUSDT", "positionAmt": amount,
            "positionSide": "BOTH", "marginType": "cross",
        }])
        prepared = self._prepare_binance(ledger, principal)
        result = ledger.execute(
            principal, self.connection_id, str(prepared["operationId"]),
            self._execute_body(prepared, "binance-high-precision-01"),
        )
        self.assertEqual(result["status"], "SUCCEEDED", result)
        self.assertEqual(usdm.writes[0]["side"], "BUY")
        self.assertEqual(usdm.writes[0]["quantity"], amount[1:])

    def test_float_or_unbounded_position_value_is_rejected_before_marker(self) -> None:
        for value in (1.0, "1e999"):
            with self.subTest(value=value):
                _user_id, ledger, principal, _spot, usdm, _context = self._binance_fixture([{
                    "symbol": "BTCUSDT", "positionAmt": value,
                    "positionSide": "BOTH", "marginType": "cross",
                }])
                with self.assertRaises(CommandLedgerError):
                    self._prepare_binance(ledger, principal)
                self.assertEqual(usdm.writes, [])
                with self.store.connection() as connection:
                    count = connection.execute(
                        "SELECT COUNT(*) FROM multiuser_operations WHERE user_id=? AND connection_id=?",
                        (principal.user_id, self.connection_id),
                    ).fetchone()[0]
                self.assertEqual(count, 0)


if __name__ == "__main__":
    unittest.main()
