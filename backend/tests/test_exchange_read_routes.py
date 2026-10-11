from __future__ import annotations

import threading
import unittest
from concurrent.futures import ThreadPoolExecutor
from tempfile import TemporaryDirectory
from urllib.parse import parse_qs, urlsplit

from backend.security import _totp_at
from backend.service import APIError, RuntimeSettings, TradeService, _OwnedStrategyOwner
from backend.store import encode_json
from backend.store import SQLiteIdentityStore
from backend.strategy import StrategyService, _ReadOnlyOrderDetailsClient
from backend.strategy_scope import owned_strategy_fingerprint
from backend.exchanges.binance_transport import BinanceTransportError
from backend.okx import OKXError
from backend.tests.test_multiuser_ownership import _FabricatedCredentialVault, _FabricatedSeedCipher


class _ReadOKXTransport:
    def __init__(self):
        self.calls: list[tuple[str, str]] = []
        self.order_response: dict | None = {
            "instId": "BTC-USDT-SWAP", "clOrdId": "client-1", "sz": "1",
            "accFillSz": "0.5", "state": "partially_filled", "ordId": "exchange-1", "avgPx": "101",
        }
        self.order_called = threading.Event()
        self.account_config_hook = None
        self.pending_orders: list[dict] = []
        self.order_hook = None
        self.balance_hook = None
        self.account_config_error = None

    def __call__(self, method: str, path: str, _headers: dict[str, str], _body: bytes | None):
        self.calls.append((method, path))
        endpoint = urlsplit(path).path
        query = parse_qs(urlsplit(path).query)
        if endpoint == "/api/v5/account/config":
            if self.account_config_hook is not None:
                self.account_config_hook()
            if self.account_config_error is not None:
                raise self.account_config_error
            return {"code": "0", "data": [{"uid": "123456789", "perm": "read_only", "posMode": "net_mode"}]}
        if endpoint == "/api/v5/account/balance":
            if self.balance_hook is not None:
                self.balance_hook()
            return {"code": "0", "data": [{"details": [
                {"ccy": "BTC", "availBal": "0.03", "frozenBal": "0", "cashBal": "0.03"},
                {"ccy": "USDT", "availBal": "100", "frozenBal": "5", "cashBal": "105"},
            ]}]}
        if endpoint == "/api/v5/account/positions":
            return {"code": "0", "data": []}
        if endpoint == "/api/v5/public/instruments":
            inst_type = query.get("instType", ["SPOT"])[0]
            instrument = query.get("instId", ["BTC-USDT" if inst_type == "SPOT" else "BTC-USDT-SWAP"])[0]
            row = {
                "instId": instrument, "tickSz": "0.01", "lotSz": "0.001", "minSz": "0.001", "state": "live",
            }
            if inst_type in {"SWAP", "FUTURES"}:
                row.update({"ctVal": "0.01", "ctValCcy": "BTC", "ctType": "linear", "settleCcy": "USDT"})
            return {"code": "0", "data": [row]}
        if endpoint == "/api/v5/market/ticker":
            instrument = query.get("instId", [""])[0]
            price = "100" if instrument == "BTC-USDT" else "300"
            return {"code": "0", "data": [{"instId": instrument, "last": price, "ts": "1700000000000"}]}
        if endpoint == "/api/v5/trade/order":
            self.order_called.set()
            if self.order_hook is not None:
                self.order_hook()
            return {"code": "0", "data": [] if self.order_response is None else [self.order_response]}
        if endpoint == "/api/v5/trade/orders-pending":
            return {"code": "0", "data": self.pending_orders}
        raise AssertionError(f"unexpected fabricated OKX request: {method} {path}")


class _BinanceLifecycleTransport:
    def __init__(self, clock):
        self.clock = clock
        self.calls: list[tuple[str, str]] = []
        self.uid = 123456789
        self.restrictions = {
            "enableReading": True, "enableWithdrawals": False, "enableFutures": True,
        }
        self.failure: BinanceTransportError | None = None

    def __call__(self, method: str, path: str, _headers: dict[str, str], _body: bytes | None):
        self.calls.append((method, path))
        endpoint = urlsplit(path).path
        if endpoint in {"/api/v3/time", "/fapi/v1/time"}:
            return {"serverTime": int(self.clock() * 1000)}
        if endpoint == "/api/v3/account":
            return {"uid": self.uid, "balances": []}
        if endpoint == "/sapi/v1/account/apiRestrictions":
            if self.failure is not None:
                raise self.failure
            return dict(self.restrictions)
        if endpoint == "/fapi/v2/account":
            return {"canTrade": False, "multiAssetsMargin": True, "assets": [], "positions": []}
        raise AssertionError(f"unexpected fabricated Binance request: {method} {path}")


class _FabricatedBinanceVault(_FabricatedCredentialVault):
    def decrypt_credentials(self, *args: object, **context: object) -> dict[str, str]:
        if context.get("exchange") == "BINANCE":
            return {"apiKey": "fabricated-binance-key", "apiSecret": "fabricated-binance-secret"}
        return super().decrypt_credentials(*args, **context)


class ExchangeReadRouteTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = TemporaryDirectory()
        self.now = 1_800_000_000.0
        self.settings = RuntimeSettings(
            okx_api_key="", okx_api_secret="", okx_api_passphrase="", admin_password_hash="",
            totp_secret="", session_signing_key=b"S" * 32,
            allowed_web_origin="https://tradingbalancef.example",
            operation_db_path=f"{self.temp.name}/identity.sqlite3", multiuser_enabled=True,
            multiuser_trade_enabled=False, credential_vault_key=b"V" * 32,
            credential_vault_key_id="fixture-v1", remote_identity_key=b"R" * 32,
        )
        self.store = SQLiteIdentityStore(self.settings.operation_db_path)
        self.store.initialize()
        self.transport = _ReadOKXTransport()
        self.service = TradeService(
            self.settings, identity_store=self.store, seed_cipher=_FabricatedSeedCipher(),
            transport=self.transport, clock=lambda: self.now,
        )
        self.service.connections.vault = _FabricatedCredentialVault()
        self._totp_secrets: dict[str, str] = {}
        self.token, self.user_id = self._ordinary_session()
        self._step_up(self.token, self.user_id)
        status, payload, _ = self.service.dispatch(
            "POST", "/v2/connections", self._connection_body(), self._bearer_environ(self.token)
        )
        self.assertEqual(status, 201)
        self.connection_id = payload["connection"]["connectionId"]
        self.binance_transport = _BinanceLifecycleTransport(lambda: self.now)
        self.service.connections._transport = self._exchange_transport
        self.service.connections.vault = _FabricatedBinanceVault()

    def tearDown(self) -> None:
        self.temp.cleanup()

    def _ordinary_session(self, username: str = "Read.Route.Owner") -> tuple[str, str]:
        password = "fabricated read-route session password"
        _, invite = self.service.identity_auth.create_invite()
        enrollment = self.service.identity_auth.activate_invite(invite, username, password, "198.51.100.10")
        enrollment_principal = self.service.identity_auth.validate_session(enrollment.token)
        challenge = self.service.identity_auth.start_enrollment(enrollment_principal)
        secret = str(challenge["totpSecret"])
        self._totp_secrets[enrollment.user_id] = secret
        self.service.identity_auth.complete_enrollment(
            enrollment_principal, _totp_at(secret, int(self.now // 30)), True
        )
        self.now += 30
        ordinary = self.service.identity_auth.login(
            username, password, totp=_totp_at(secret, int(self.now // 30)), source="198.51.100.10"
        )
        return ordinary.token, ordinary.user_id

    def _step_up(self, token: str, user_id: str) -> None:
        self.now += 30
        principal = self.service.identity_auth.validate_session(token)
        secret = self._totp_secrets[user_id]
        self.service.identity_auth.step_up(
            principal, "fabricated read-route session password", _totp_at(secret, int(self.now // 30))
        )

    @staticmethod
    def _connection_body() -> dict[str, str]:
        return {
            "exchange": "OKX", "environment": "demo", "region": "global",
            "nickname": "Fabricated account", "apiKey": "fabricated-key",
            "apiSecret": "fabricated-secret", "passphrase": "fabricated-passphrase",
        }

    @staticmethod
    def _bearer_environ(token: str) -> dict[str, str]:
        return {
            "HTTP_X_SESSION_TRANSPORT": "bearer", "HTTP_AUTHORIZATION": f"Bearer {token}",
            "REMOTE_ADDR": "198.51.100.10",
        }

    def _read(self, path: str, token: str | None = None):
        target, separator, query = path.partition("?")
        environ = self._bearer_environ(token or self.token)
        if separator:
            environ["QUERY_STRING"] = query
        return self.service.dispatch(
            "GET", target, {}, environ
        )

    def _binance_body(self, *, environment: str = "live", api_key: str = "fabricated-binance-key") -> dict[str, str]:
        return {
            "exchange": "BINANCE", "environment": environment, "region": "global",
            "nickname": "Fabricated Binance account", "apiKey": api_key,
            "apiSecret": "fabricated-binance-secret",
        }

    def _exchange_transport(self, method: str, path: str, headers: dict[str, str], body: bytes | None):
        if urlsplit(path).path.startswith(("/api/v3/", "/sapi/v1/", "/fapi/v1/", "/fapi/v2/")):
            return self.binance_transport(method, path, headers, body)
        return self.transport(method, path, headers, body)

    def test_binance_connection_create_reverify_rotate_revoke_and_same_uid_relink(self) -> None:
        environ = self._bearer_environ(self.token)
        status, created, _ = self.service.dispatch("POST", "/v2/connections", self._binance_body(), environ)
        self.assertEqual(status, 201)
        connection = created["connection"]
        connection_id = connection["connectionId"]
        self.assertEqual(connection["exchange"], "BINANCE")
        self.assertEqual(connection["capabilities"], ["read", "read:SPOT", "read:USD_M"])
        self.assertNotIn("withdraw", connection["capabilities"])
        self.assertTrue(all(method == "GET" for method, _path in self.binance_transport.calls))

        status, verified, _ = self.service.dispatch(
            "POST", f"/v2/connections/{connection_id}/verify", {}, environ
        )
        self.assertEqual(status, 200)
        self.assertEqual(verified["connection"]["credentialVersion"], connection["credentialVersion"])

        current_version = connection["credentialVersion"]
        status, rotated, _ = self.service.dispatch(
            "POST", f"/v2/connections/{connection_id}/credentials",
            self._binance_body(api_key="fabricated-binance-key-rotated"), environ,
        )
        self.assertEqual(status, 200)
        self.assertEqual(rotated["connection"]["credentialVersion"], current_version + 1)

        status, revoked, _ = self.service.dispatch(
            "POST", f"/v2/connections/{connection_id}/revoke", {}, environ
        )
        self.assertEqual(status, 200)
        self.assertEqual(revoked["connection"]["status"], "REVOKED")
        status, relinked, _ = self.service.dispatch(
            "POST", "/v2/connections", self._binance_body(api_key="fabricated-binance-key-relinked"), environ
        )
        self.assertEqual(status, 201)
        self.assertEqual(relinked["connection"]["connectionId"], connection_id)
        self.assertEqual(relinked["connection"]["credentialVersion"], current_version + 3)
        self.assertEqual(relinked["connection"]["status"], "ACTIVE")

    def test_binance_create_and_owned_rotation_reject_extra_passphrase_before_upstream(self) -> None:
        environ = self._bearer_environ(self.token)
        for passphrase in ("", "fabricated-extra-passphrase"):
            body_with_extra = self._binance_body()
            body_with_extra["passphrase"] = passphrase
            with self.subTest(passphrase=passphrase), self.assertRaises(APIError) as invalid_schema:
                self.service.dispatch("POST", "/v2/connections", body_with_extra, environ)
            self.assertEqual((invalid_schema.exception.status, invalid_schema.exception.code), (400, "connection_invalid"))
        self.assertEqual(self.binance_transport.calls, [])

        status, created, _ = self.service.dispatch("POST", "/v2/connections", self._binance_body(), environ)
        self.assertEqual(status, 201)
        connection_id = created["connection"]["connectionId"]
        current_version = created["connection"]["credentialVersion"]
        before_rotation = list(self.binance_transport.calls)
        for passphrase in ("", "fabricated-extra-passphrase"):
            body_with_extra = self._binance_body()
            body_with_extra["passphrase"] = passphrase
            with self.subTest(rotation_passphrase=passphrase), self.assertRaises(APIError) as invalid_rotation:
                self.service.dispatch(
                    "POST", f"/v2/connections/{connection_id}/credentials", body_with_extra, environ
                )
            self.assertEqual((invalid_rotation.exception.status, invalid_rotation.exception.code), (400, "connection_invalid"))
        with self.assertRaises(APIError) as foreign:
            self.service.dispatch(
                "POST", "/v2/connections/unknown-owner-123/credentials",
                {**self._binance_body(), "passphrase": "fabricated-extra-passphrase"}, environ,
            )
        self.assertEqual((foreign.exception.status, foreign.exception.code), (404, "not_found"))
        self.assertEqual(self.binance_transport.calls, before_rotation)
        with self.store.connection() as db:
            version = db.execute(
                "SELECT credential_version FROM exchange_connections WHERE user_id=? AND connection_id=?",
                (self.user_id, connection_id),
            ).fetchone()["credential_version"]
        self.assertEqual(version, current_version)

    def test_binance_rotation_rejects_mismatched_remote_uid_without_persistence(self) -> None:
        environ = self._bearer_environ(self.token)
        status, created, _ = self.service.dispatch("POST", "/v2/connections", self._binance_body(), environ)
        self.assertEqual(status, 201)
        connection_id = created["connection"]["connectionId"]
        version = created["connection"]["credentialVersion"]
        with self.store.connection() as db:
            digest = db.execute(
                "SELECT remote_identity_digest FROM exchange_connections WHERE user_id=? AND connection_id=?",
                (self.user_id, connection_id),
            ).fetchone()["remote_identity_digest"]
        self.binance_transport.uid = 987654321
        with self.assertRaises(APIError) as mismatched:
            self.service.dispatch(
                "POST", f"/v2/connections/{connection_id}/credentials", self._binance_body(), environ
            )
        self.assertEqual((mismatched.exception.status, mismatched.exception.code), (409, "account_changed"))
        with self.store.connection() as db:
            row = db.execute(
                "SELECT credential_version, remote_identity_digest FROM exchange_connections "
                "WHERE user_id=? AND connection_id=?",
                (self.user_id, connection_id),
            ).fetchone()
        self.assertEqual(row["credential_version"], version)
        self.assertEqual(row["remote_identity_digest"], digest)

    def test_binance_demo_gate_missing_read_authority_withdrawals_and_retry_after(self) -> None:
        environ = self._bearer_environ(self.token)
        with self.assertRaises(APIError) as demo:
            self.service.dispatch("POST", "/v2/connections", self._binance_body(environment="demo"), environ)
        self.assertEqual((demo.exception.status, demo.exception.code), (503, "verification_unavailable"))
        self.assertEqual(self.binance_transport.calls, [])

        self.binance_transport.restrictions["enableReading"] = False
        with self.assertRaises(APIError) as no_read:
            self.service.dispatch("POST", "/v2/connections", self._binance_body(), environ)
        self.assertEqual((no_read.exception.status, no_read.exception.code), (400, "verification_failed"))
        self.binance_transport.restrictions["enableReading"] = True

        self.binance_transport.restrictions["enableWithdrawals"] = True
        with self.assertRaises(APIError) as withdrawals:
            self.service.dispatch("POST", "/v2/connections", self._binance_body(), environ)
        self.assertEqual((withdrawals.exception.status, withdrawals.exception.code), (400, "verification_failed"))
        self.binance_transport.restrictions["enableWithdrawals"] = False

        self.binance_transport.failure = BinanceTransportError(
            429, "rate_limited", "fabricated rate limit", retry_after="17"
        )
        with self.assertRaises(APIError) as limited:
            self.service.dispatch("POST", "/v2/connections", self._binance_body(), environ)
        self.assertEqual((limited.exception.status, limited.exception.code), (429, "rate_limited"))
        self.assertIn(("Retry-After", "17"), limited.exception.headers)
        with self.store.connection() as db:
            count = db.execute(
                "SELECT COUNT(*) FROM exchange_connections WHERE user_id=? AND exchange='BINANCE'",
                (self.user_id,),
            ).fetchone()[0]
        self.assertEqual(count, 0)

    def test_cross_resource_cursor_is_owner_first_404_without_exchange_call(self) -> None:
        status, first, _ = self._read(
            f"/v2/connections/{self.connection_id}/balances?product=SPOT&limit=1"
        )
        self.assertEqual(status, 200)
        cursor = first["page"]["nextCursor"]
        self.assertIsInstance(cursor, str)
        calls_before = list(self.transport.calls)
        with self.assertRaises(APIError) as denied:
            self._read(
                f"/v2/connections/{self.connection_id}/positions?product=SWAP&limit=1&cursor={cursor}"
            )
        self.assertEqual((denied.exception.status, denied.exception.code), (404, "not_found"))
        self.assertEqual(self.transport.calls, calls_before)

    def test_binance_mutations_are_owner_first_and_stop_before_ledger_or_strategy_preflight(self) -> None:
        with self.store.transaction() as connection:
            connection.execute(
                "UPDATE exchange_connections SET exchange='BINANCE' WHERE user_id=? AND connection_id=?",
                (self.user_id, self.connection_id),
            )

        ledger_calls: list[str] = []

        class LedgerSpy:
            def prepare(_self, *_args, **_kwargs):
                ledger_calls.append("prepare")
                return {}

            def execute(_self, *_args, **_kwargs):
                ledger_calls.append("execute")
                return {}

            def reconcile(_self, *_args, **_kwargs):
                ledger_calls.append("reconcile")
                return {}

        self.service.commands = LedgerSpy()
        rate_calls: list[str] = []
        self.service._check_v2_action_rate = lambda action, _source: rate_calls.append(action)
        environ = self._bearer_environ(self.token)
        calls_before = list(self.transport.calls)

        with self.assertRaises(APIError) as action:
            self.service.dispatch(
                "POST", f"/v2/connections/{self.connection_id}/actions/prepare", {}, environ
            )
        self.assertEqual((action.exception.status, action.exception.code), (422, "capability_unsupported"))

        with self.assertRaises(APIError) as strategy:
            self.service.dispatch(
                "POST",
                f"/v2/connections/{self.connection_id}/strategies/strategy-1234/prepare-apply",
                {},
                environ,
            )
        self.assertEqual((strategy.exception.status, strategy.exception.code), (422, "capability_unsupported"))

        with self.assertRaises(APIError) as unknown_owner:
            self.service.dispatch(
                "POST", "/v2/connections/unknown-id-1234/actions/prepare", {}, environ
            )
        self.assertEqual((unknown_owner.exception.status, unknown_owner.exception.code), (404, "not_found"))
        self.assertEqual(ledger_calls, [])
        self.assertEqual(rate_calls, [])
        self.assertEqual(self.transport.calls, calls_before)

    def test_owned_normalized_cache_separates_resource_under_same_scope(self) -> None:
        base = "exchange=OKX&product=SPOT&environment=demo&region=global&instrument=BTC-USDT"
        _, ticker, _ = self._read(f"/v2/market/ticker?{base}")
        _, metadata, _ = self._read(f"/v2/market/instruments?{base}")
        self.assertEqual(ticker["data"][0]["price"], "100")
        self.assertEqual(metadata["data"][0]["tickSize"], "0.01")
        self.assertIn("baseAsset", metadata["data"][0])

    def test_unrecognized_spot_market_target_returns_incomplete_native_order_page(self) -> None:
        self.transport.pending_orders = [{
            "instId": "BTC-USDT", "ordId": "market-1", "clOrdId": "client-market-1",
            "sz": "100", "accFillSz": "0.03", "side": "buy", "ordType": "market",
            "tgtCcy": "unknown", "state": "live",
        }]
        status, payload, _headers = self._read(
            f"/v2/connections/{self.connection_id}/orders?product=SPOT"
        )
        self.assertEqual(status, 200)
        self.assertEqual(payload["data"][0]["nativeQuantity"], "100")
        self.assertIsNone(payload["data"][0]["quantityUnit"])
        self.assertIsNone(payload["data"][0]["nativeAsset"])
        self.assertEqual(payload["data"][0]["filledQuantityUnit"], "base")
        self.assertFalse(payload["dataMeta"]["complete"])

    def test_final_uid_check_rejects_connection_rotation_during_identity_call(self) -> None:
        before = list(self.transport.calls)
        first = True

        def rotate_during_identity_call():
            nonlocal first
            if first:
                first = False
                with self.store.transaction() as connection:
                    connection.execute(
                        "UPDATE exchange_connections SET credential_version=credential_version+1 "
                        "WHERE user_id=? AND connection_id=?",
                        (self.user_id, self.connection_id),
                    )

        self.transport.account_config_hook = rotate_during_identity_call
        with self.assertRaises(APIError) as denied:
            self._read(f"/v2/connections/{self.connection_id}/balances?product=SPOT")
        self.assertEqual((denied.exception.status, denied.exception.code), (409, "connection_changed"))
        calls_after = self.transport.calls[len(before):]
        self.assertTrue(any(path == "/api/v5/account/config" for _method, path in calls_after))
        self.assertFalse(any(path == "/api/v5/account/balance" for _method, path in calls_after))

    def test_final_uid_check_after_balance_rejects_rotation_without_cache_or_snapshot_publish(self) -> None:
        balance_complete = False
        rotation_occurred = False

        def rotate_on_final_identity_check():
            nonlocal rotation_occurred
            if balance_complete and not rotation_occurred:
                with self.store.transaction() as connection:
                    connection.execute(
                        "UPDATE exchange_connections SET credential_version=credential_version+1 "
                        "WHERE user_id=? AND connection_id=?",
                        (self.user_id, self.connection_id),
                    )
                rotation_occurred = True

        def mark_balance_complete():
            nonlocal balance_complete
            balance_complete = True

        self.transport.account_config_hook = rotate_on_final_identity_check
        self.transport.balance_hook = mark_balance_complete
        with self.assertRaises(APIError) as denied:
            self._read(f"/v2/connections/{self.connection_id}/balances?product=SPOT")
        self.assertEqual((denied.exception.status, denied.exception.code), (409, "connection_changed"))
        called_paths = [urlsplit(path).path for _method, path in self.transport.calls]
        self.assertTrue(rotation_occurred)
        self.assertIn("/api/v5/account/balance", called_paths)
        self.assertFalse(self.service.data_gateway._cache)
        self.assertFalse(self.service.data_gateway._snapshots)

    def test_private_identity_429_cooldown_skips_same_resource_network_retry(self) -> None:
        calls_before = list(self.transport.calls)
        self.transport.account_config_error = OKXError(
            "safe fabricated rejection", http_status=429, retry_after="13"
        )
        query = f"/v2/connections/{self.connection_id}/balances?product=SPOT"
        with self.assertRaises(APIError) as first:
            self._read(query)
        self.assertEqual((first.exception.status, first.exception.code), (429, "rate_limited"))
        self.assertIn(("Retry-After", "13"), first.exception.headers)
        calls_after_first = list(self.transport.calls)
        first_attempt_calls = calls_after_first[len(calls_before):]
        identity_calls = sum(path == "/api/v5/account/config" for _method, path in first_attempt_calls)
        self.assertEqual(identity_calls, 1)

        with self.assertRaises(APIError) as retry:
            self._read(query)
        self.assertEqual((retry.exception.status, retry.exception.code), (429, "rate_limited"))
        self.assertEqual(self.transport.calls, calls_after_first)

        with self.assertRaises(APIError) as other_resource:
            self._read(f"/v2/connections/{self.connection_id}/positions?product=SWAP")
        self.assertEqual((other_resource.exception.status, other_resource.exception.code), (429, "rate_limited"))
        self.assertEqual(
            sum(path == "/api/v5/account/config" for _method, path in self.transport.calls[len(calls_before):]),
            identity_calls + 1,
        )

    def test_owned_strategy_projection_uses_bound_sql_and_frozen_pages_without_upstream(self) -> None:
        principal = self.service.identity_auth.validate_session(self.token)
        metadata = self.service.connections.strategy_metadata_context(principal, self.connection_id)
        fingerprint = owned_strategy_fingerprint(self.user_id, self.connection_id)
        now = self.now
        with self.store.transaction() as connection:
            for index in range(501):
                connection.execute(
                    "INSERT INTO multiuser_strategies(user_id, connection_id, strategy_id, status, "
                    "account_fingerprint, contract_json, snapshot_json, orders_json, results_json, preview_hash, "
                    "leverage_results_json, credential_version, permission_version, created_at, updated_at) "
                    "VALUES (?, ?, ?, 'DRAFT', ?, ?, ?, '[]', '[]', '', '[]', ?, ?, ?, ?)",
                    (
                        self.user_id, self.connection_id, f"route-strategy-{index:04d}", fingerprint,
                        encode_json({"instrumentId": "BTC-USDT-SWAP", "interval": "1Dutc"}),
                        encode_json({"sides": []}), metadata.credential_version, metadata.permission_version,
                        now - index, now - index,
                    ),
                )
        credential_reads: list[str] = []

        def deny_vault(*_args, **_kwargs):
            credential_reads.append("unexpected")
            self.fail("owned strategy projections must not decrypt exchange credentials")

        self.service.connections.vault.decrypt_credentials = deny_vault
        before = list(self.transport.calls)
        _, first, _ = self._read(f"/v2/connections/{self.connection_id}/strategies?limit=50")
        self.assertEqual(first["page"]["total"], 501)
        self.assertEqual(len(first["strategies"]), 50)
        cursor = first["page"]["nextCursor"]
        with self.store.transaction() as connection:
            connection.execute(
                "DELETE FROM multiuser_strategies WHERE user_id=? AND connection_id=? AND strategy_id=?",
                (self.user_id, self.connection_id, "route-strategy-0050"),
            )
        _, second, _ = self._read(
            f"/v2/connections/{self.connection_id}/strategies?limit=50&cursor={cursor}"
        )
        self.assertEqual(second["strategies"][0]["id"], "route-strategy-0050")
        self.assertEqual(self.transport.calls, before)
        self.assertEqual(credential_reads, [])

    def _insert_refresh_strategy(self, strategy_id: str = "refresh-strategy-01") -> tuple[StrategyService, str]:
        principal = self.service.identity_auth.validate_session(self.token)
        context = self.service.connections.account_context(principal, self.connection_id)
        owner = _OwnedStrategyOwner(self.service, principal, context)
        strategy = StrategyService(owner, strategy_scope=owner.strategy_scope)
        now = self.now
        with self.store.transaction() as connection:
            connection.execute(
                "INSERT INTO multiuser_strategies(user_id, connection_id, strategy_id, status, "
                "account_fingerprint, contract_json, snapshot_json, orders_json, results_json, preview_hash, "
                "attempt_started, batch_attempted, order_placement_attempted, submission_mode, leverage_results_json, "
                "credential_version, permission_version, created_at, updated_at) "
                "VALUES (?, ?, ?, 'APPLIED', ?, ?, ?, ?, ?, 'fixture-hash', 1, 1, 1, 'batch', '[]', ?, ?, ?, ?)",
                (
                    self.user_id, self.connection_id, strategy_id, owner.strategy_scope.account_fingerprint,
                    encode_json({"instrumentId": "BTC-USDT-SWAP", "interval": "1Dutc"}),
                    encode_json({"sides": ["long"]}),
                    encode_json([{"clientOrderId": "client-1", "contracts": "1", "side": "buy"}]),
                    encode_json([{
                        "clientOrderId": "client-1", "contracts": "1", "status": "live",
                        "placementState": "accepted", "filledContracts": "0", "exchangeOrderId": "exchange-1",
                    }]),
                    context.credential_version, context.permission_version, now, now,
                ),
            )
        return strategy, strategy_id

    def _capture_refresh_work(self, strategy_id: str):
        captured: dict[str, object] = {}

        def capture(_key, work):
            captured["work"] = work
            return False

        self.service._enqueue_read_only_strategy_refresh = capture
        status, payload, _headers = self.service.dispatch(
            "POST",
            f"/v2/connections/{self.connection_id}/strategies/{strategy_id}/refresh",
            {},
            self._bearer_environ(self.token),
        )
        self.assertEqual(status, 202)
        self.assertEqual(payload["refresh"]["accepted"], True)
        self.assertTrue(callable(captured.get("work")))
        return captured["work"]

    def test_read_only_refresh_refuses_live_connection_leases_and_claims(self) -> None:
        strategy, strategy_id = self._insert_refresh_strategy()
        with self.store.transaction() as connection:
            connection.execute(
                "UPDATE multiuser_connection_leases SET lease_until=? WHERE user_id=? AND connection_id=?",
                (self.now + 60, self.user_id, self.connection_id),
            )
        with self.assertRaises(APIError) as lease:
            strategy.inspect_read_only_refresh(strategy_id)
        self.assertEqual(lease.exception.code, "strategy_refresh_unavailable")
        with self.store.transaction() as connection:
            connection.execute(
                "UPDATE multiuser_connection_leases SET lease_until=NULL WHERE user_id=? AND connection_id=?",
                (self.user_id, self.connection_id),
            )
            connection.execute(
                "INSERT INTO multiuser_strategy_claims(user_id, connection_id, strategy_id, lease_owner, fence, lease_until, updated_at) "
                "VALUES (?, ?, ?, 'fixture-worker', 1, ?, ?)",
                (self.user_id, self.connection_id, strategy_id, self.now + 60, self.now),
            )
        with self.assertRaises(APIError) as claim:
            strategy.inspect_read_only_refresh(strategy_id)
        self.assertEqual(claim.exception.code, "strategy_refresh_unavailable")

    def test_refresh_route_rechecks_revoked_session_before_order_read(self) -> None:
        strategy_id = "refresh-session-01"
        _strategy, strategy_id = self._insert_refresh_strategy(strategy_id)
        work = self._capture_refresh_work(strategy_id)
        original_identity = self.service.connections.assert_context_identity

        def revoke_session_after_uid(principal, context, *, product=None):
            result = original_identity(principal, context, product=product)
            with self.store.transaction() as connection:
                connection.execute("DELETE FROM user_sessions")
            return result

        self.service.connections.assert_context_identity = revoke_session_after_uid
        work()
        self.assertFalse(self.transport.order_called.is_set())
        with self.store.connection() as connection:
            row = connection.execute(
                "SELECT results_json FROM multiuser_strategies WHERE user_id=? AND connection_id=? AND strategy_id=?",
                (self.user_id, self.connection_id, strategy_id),
            ).fetchone()
            sync = connection.execute(
                "SELECT 1 FROM multiuser_strategy_sync_state WHERE user_id=? AND connection_id=? AND strategy_id=?",
                (self.user_id, self.connection_id, strategy_id),
            ).fetchone()
        self.assertIn('"filledContracts":"0"', row["results_json"])
        self.assertIsNone(sync)

    def test_refresh_route_rechecks_connection_rotation_before_order_read(self) -> None:
        strategy_id = "refresh-rotation-01"
        _strategy, strategy_id = self._insert_refresh_strategy(strategy_id)
        work = self._capture_refresh_work(strategy_id)
        original_identity = self.service.connections.assert_context_identity

        def rotate_after_uid(principal, context, *, product=None):
            result = original_identity(principal, context, product=product)
            with self.store.transaction() as connection:
                connection.execute(
                    "UPDATE exchange_connections SET credential_version=credential_version+1 "
                    "WHERE user_id=? AND connection_id=?",
                    (self.user_id, self.connection_id),
                )
            return result

        self.service.connections.assert_context_identity = rotate_after_uid
        work()
        self.assertFalse(self.transport.order_called.is_set())
        with self.store.connection() as connection:
            row = connection.execute(
                "SELECT results_json FROM multiuser_strategies WHERE user_id=? AND connection_id=? AND strategy_id=?",
                (self.user_id, self.connection_id, strategy_id),
            ).fetchone()
            sync = connection.execute(
                "SELECT 1 FROM multiuser_strategy_sync_state WHERE user_id=? AND connection_id=? AND strategy_id=?",
                (self.user_id, self.connection_id, strategy_id),
            ).fetchone()
        self.assertIn('"filledContracts":"0"', row["results_json"])
        self.assertIsNone(sync)

    def test_refresh_route_rechecks_session_and_uid_after_order_read_before_publish(self) -> None:
        strategy_id = "refresh-final-authority-01"
        self._insert_refresh_strategy(strategy_id)
        work = self._capture_refresh_work(strategy_id)

        def revoke_after_order_read():
            with self.store.transaction() as connection:
                connection.execute("DELETE FROM user_sessions")

        self.transport.order_hook = revoke_after_order_read
        work()
        self.assertTrue(self.transport.order_called.is_set())
        with self.store.connection() as connection:
            row = connection.execute(
                "SELECT results_json FROM multiuser_strategies WHERE user_id=? AND connection_id=? AND strategy_id=?",
                (self.user_id, self.connection_id, strategy_id),
            ).fetchone()
            sync = connection.execute(
                "SELECT 1 FROM multiuser_strategy_sync_state WHERE user_id=? AND connection_id=? AND strategy_id=?",
                (self.user_id, self.connection_id, strategy_id),
            ).fetchone()
        self.assertIn('"filledContracts":"0"', row["results_json"])
        self.assertIsNone(sync)

    def test_refresh_final_cas_refuses_live_claim_and_revision_changed_during_order_read(self) -> None:
        strategy_id = "refresh-final-claim-01"
        self._insert_refresh_strategy(strategy_id)
        work = self._capture_refresh_work(strategy_id)

        def claim_after_order_read():
            with self.store.transaction() as connection:
                connection.execute(
                    "INSERT INTO multiuser_strategy_claims(user_id, connection_id, strategy_id, lease_owner, fence, lease_until, updated_at) "
                    "VALUES (?, ?, ?, 'fixture-worker', 1, ?, ?)",
                    (self.user_id, self.connection_id, strategy_id, self.now + 60, self.now),
                )

        self.transport.order_hook = claim_after_order_read
        work()
        self.assertTrue(self.transport.order_called.is_set())
        with self.store.connection() as connection:
            row = connection.execute(
                "SELECT results_json FROM multiuser_strategies WHERE user_id=? AND connection_id=? AND strategy_id=?",
                (self.user_id, self.connection_id, strategy_id),
            ).fetchone()
            sync = connection.execute(
                "SELECT 1 FROM multiuser_strategy_sync_state WHERE user_id=? AND connection_id=? AND strategy_id=?",
                (self.user_id, self.connection_id, strategy_id),
            ).fetchone()
        self.assertIn('"filledContracts":"0"', row["results_json"])
        self.assertIsNone(sync)

        with self.store.transaction() as connection:
            connection.execute(
                "DELETE FROM multiuser_strategy_claims WHERE user_id=? AND connection_id=? AND strategy_id=?",
                (self.user_id, self.connection_id, strategy_id),
            )
        strategy_id = "refresh-final-revision-01"
        self._insert_refresh_strategy(strategy_id)
        self.transport.order_hook = lambda: self._replace_refresh_results(strategy_id)
        work = self._capture_refresh_work(strategy_id)
        work()
        with self.store.connection() as connection:
            row = connection.execute(
                "SELECT results_json FROM multiuser_strategies WHERE user_id=? AND connection_id=? AND strategy_id=?",
                (self.user_id, self.connection_id, strategy_id),
            ).fetchone()
            sync = connection.execute(
                "SELECT 1 FROM multiuser_strategy_sync_state WHERE user_id=? AND connection_id=? AND strategy_id=?",
                (self.user_id, self.connection_id, strategy_id),
            ).fetchone()
        self.assertIn("revision-writer", row["results_json"])
        self.assertIsNone(sync)

    def _replace_refresh_results(self, strategy_id: str) -> None:
        with self.store.transaction() as connection:
            connection.execute(
                "UPDATE multiuser_strategies SET results_json=?, updated_at=? "
                "WHERE user_id=? AND connection_id=? AND strategy_id=?",
                (
                    encode_json([{"clientOrderId": "revision-writer", "status": "live"}]),
                    self.now + 1, self.user_id, self.connection_id, strategy_id,
                ),
            )

    def test_refresh_route_refuses_claim_acquired_after_uid_check_before_order_read(self) -> None:
        strategy_id = "refresh-claim-01"
        _strategy, strategy_id = self._insert_refresh_strategy(strategy_id)
        work = self._capture_refresh_work(strategy_id)
        original_identity = self.service.connections.assert_context_identity

        def claim_after_uid(principal, context, *, product=None):
            result = original_identity(principal, context, product=product)
            with self.store.transaction() as connection:
                connection.execute(
                    "INSERT INTO multiuser_strategy_claims(user_id, connection_id, strategy_id, lease_owner, fence, lease_until, updated_at) "
                    "VALUES (?, ?, ?, 'fixture-worker', 1, ?, ?)",
                    (self.user_id, self.connection_id, strategy_id, self.now + 60, self.now),
                )
            return result

        self.service.connections.assert_context_identity = claim_after_uid
        work()
        self.assertFalse(self.transport.order_called.is_set())
        with self.store.connection() as connection:
            row = connection.execute(
                "SELECT results_json FROM multiuser_strategies WHERE user_id=? AND connection_id=? AND strategy_id=?",
                (self.user_id, self.connection_id, strategy_id),
            ).fetchone()
            sync = connection.execute(
                "SELECT 1 FROM multiuser_strategy_sync_state WHERE user_id=? AND connection_id=? AND strategy_id=?",
                (self.user_id, self.connection_id, strategy_id),
            ).fetchone()
        self.assertIn('"filledContracts":"0"', row["results_json"])
        self.assertIsNone(sync)

    def test_refresh_account_changed_identity_never_publishes_observations_or_sync_state(self) -> None:
        strategy, strategy_id = self._insert_refresh_strategy("refresh-account-changed-initial")

        def initial_mismatch():
            raise APIError(409, "account_changed", "fabricated UID mismatch")

        strategy.run_read_only_refresh(
            strategy_id, strategy.inspect_read_only_refresh(strategy_id)[1],
            before_order_call=lambda: None, verify_identity=initial_mismatch,
        )
        with self.store.connection() as connection:
            initial = connection.execute(
                "SELECT results_json FROM multiuser_strategies WHERE user_id=? AND connection_id=? AND strategy_id=?",
                (self.user_id, self.connection_id, strategy_id),
            ).fetchone()
            initial_sync = connection.execute(
                "SELECT 1 FROM multiuser_strategy_sync_state WHERE user_id=? AND connection_id=? AND strategy_id=?",
                (self.user_id, self.connection_id, strategy_id),
            ).fetchone()
        self.assertIn('"filledContracts":"0"', initial["results_json"])
        self.assertIsNone(initial_sync)

        strategy, strategy_id = self._insert_refresh_strategy("refresh-account-changed-final")
        identity_calls = 0

        def final_mismatch():
            nonlocal identity_calls
            identity_calls += 1
            if identity_calls == 2:
                raise APIError(409, "account_changed", "fabricated UID mismatch")

        strategy.run_read_only_refresh(
            strategy_id, strategy.inspect_read_only_refresh(strategy_id)[1],
            before_order_call=lambda: None, verify_identity=final_mismatch,
        )
        with self.store.connection() as connection:
            final = connection.execute(
                "SELECT results_json FROM multiuser_strategies WHERE user_id=? AND connection_id=? AND strategy_id=?",
                (self.user_id, self.connection_id, strategy_id),
            ).fetchone()
            final_sync = connection.execute(
                "SELECT 1 FROM multiuser_strategy_sync_state WHERE user_id=? AND connection_id=? AND strategy_id=?",
                (self.user_id, self.connection_id, strategy_id),
            ).fetchone()
        self.assertIn('"filledContracts":"0"', final["results_json"])
        self.assertIsNone(final_sync)

    def test_refresh_revision_loss_and_failed_read_preserve_last_known_projection(self) -> None:
        strategy, strategy_id = self._insert_refresh_strategy()
        _row, revision = strategy.inspect_read_only_refresh(strategy_id)
        with self.store.transaction() as connection:
            connection.execute(
                "UPDATE multiuser_strategies SET results_json=?, updated_at=? WHERE user_id=? AND connection_id=? AND strategy_id=?",
                (encode_json([{"clientOrderId": "changed", "status": "live"}]), self.now + 1, self.user_id, self.connection_id, strategy_id),
            )
        called = []
        strategy.run_read_only_refresh(
            strategy_id, revision, before_order_call=lambda: called.append("order"),
            verify_identity=lambda: called.append("identity"),
        )
        self.assertEqual(called, [])

        strategy, strategy_id = self._insert_refresh_strategy("refresh-strategy-02")
        self.transport.order_response = None
        strategy.run_read_only_refresh(
            strategy_id, strategy.inspect_read_only_refresh(strategy_id)[1],
            before_order_call=lambda: None, verify_identity=lambda: None,
        )
        with self.store.connection() as connection:
            row = connection.execute(
                "SELECT status, results_json FROM multiuser_strategies WHERE user_id=? AND connection_id=? AND strategy_id=?",
                (self.user_id, self.connection_id, strategy_id),
            ).fetchone()
            sync = connection.execute(
                "SELECT last_error FROM multiuser_strategy_sync_state WHERE user_id=? AND connection_id=? AND strategy_id=?",
                (self.user_id, self.connection_id, strategy_id),
            ).fetchone()
        self.assertEqual(row["status"], "APPLIED")
        self.assertIn('"filledContracts":"0"', row["results_json"])
        self.assertEqual(sync["last_error"], "order_unavailable")

    def test_successful_refresh_updates_persisted_observation_and_exposes_read_only_client(self) -> None:
        strategy, strategy_id = self._insert_refresh_strategy()
        wrapper = _ReadOnlyOrderDetailsClient(self.service.connections.account_context(
            self.service.identity_auth.validate_session(self.token), self.connection_id
        ).client)
        for forbidden in ("place_order", "set_leverage", "cancel_order", "close_position", "delete_order"):
            with self.subTest(forbidden=forbidden), self.assertRaises(AttributeError):
                getattr(wrapper, forbidden)
        strategy.run_read_only_refresh(
            strategy_id, strategy.inspect_read_only_refresh(strategy_id)[1],
            before_order_call=lambda: None, verify_identity=lambda: None,
        )
        with self.store.connection() as connection:
            row = connection.execute(
                "SELECT status, results_json FROM multiuser_strategies WHERE user_id=? AND connection_id=? AND strategy_id=?",
                (self.user_id, self.connection_id, strategy_id),
            ).fetchone()
            sync = connection.execute(
                "SELECT last_success_at, last_error FROM multiuser_strategy_sync_state WHERE user_id=? AND connection_id=? AND strategy_id=?",
                (self.user_id, self.connection_id, strategy_id),
            ).fetchone()
        self.assertEqual(row["status"], "APPLIED")
        self.assertIn('"filledContracts":"0.5"', row["results_json"])
        self.assertIsNotNone(sync["last_success_at"])
        self.assertIsNone(sync["last_error"])
        self.assertTrue(self.transport.order_called.is_set())

    def test_refresh_admission_is_bounded_coalesced_and_two_workers_only(self) -> None:
        service = TradeService.__new__(TradeService)
        service._strategy_refresh_executor = ThreadPoolExecutor(max_workers=2)
        service._strategy_refresh_admission = threading.BoundedSemaphore(16)
        service._strategy_refresh_lock = threading.Lock()
        service._strategy_refresh_jobs = {}
        service.STRATEGY_REFRESH_QUEUE_TTL_SECONDS = 30
        entered = threading.Semaphore(0)
        release = threading.Event()
        completed = threading.Semaphore(0)
        active = 0
        active_lock = threading.Lock()
        maximum_active = 0

        def work():
            nonlocal active, maximum_active
            with active_lock:
                active += 1
                maximum_active = max(maximum_active, active)
            entered.release()
            release.wait(2)
            with active_lock:
                active -= 1
            completed.release()

        keys = [("owner", f"connection-{index}") for index in range(16)]
        for key in keys:
            self.assertFalse(service._enqueue_read_only_strategy_refresh(key, work))
        self.assertTrue(entered.acquire(timeout=2))
        self.assertTrue(entered.acquire(timeout=2))
        self.assertTrue(service._enqueue_read_only_strategy_refresh(keys[0], work))
        with self.assertRaises(APIError) as full:
            service._enqueue_read_only_strategy_refresh(("owner", "connection-overflow"), work)
        self.assertEqual((full.exception.status, full.exception.code), (503, "busy"))
        release.set()
        for _ in keys:
            self.assertTrue(completed.acquire(timeout=3))
        self.assertLessEqual(maximum_active, 2)
        service._strategy_refresh_executor.shutdown(wait=True)


if __name__ == "__main__":
    unittest.main()
