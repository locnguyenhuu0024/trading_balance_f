from __future__ import annotations

import json
import base64
import datetime as dt
import hashlib
import hmac
import sqlite3
import threading
import time
from contextlib import closing
import urllib.error
import urllib.request
from decimal import Decimal
from tempfile import TemporaryDirectory
from urllib.parse import parse_qs, urlsplit
from wsgiref.simple_server import WSGIRequestHandler, make_server
from wsgiref.simple_server import WSGIServer as BaseWSGIServer
from socketserver import TCPServer, ThreadingMixIn
import unittest

from backend.app import create_application
from backend.okx import OKXClient
from backend.security import _totp_at, hash_password, token_digest
from backend.service import RuntimeSettings


ORIGIN = "https://tradingbalancef.vercel.app"
PASSWORD = "disposable-test-password-2026"
TOTP_SECRET = "JBSWY3DPEHPK3PXP"
SIGNING_KEY = b"T" * 32
BASE_TIME = 1_800_000_000.0


class QuietHandler(WSGIRequestHandler):
    def log_message(self, format: str, *args: object) -> None:
        return


class ThreadingWSGIServer(ThreadingMixIn, BaseWSGIServer):
    daemon_threads = True

    def server_bind(self) -> None:
        # Avoid reverse-DNS lookup during test setup; the server binds only to
        # loopback and does not need a resolvable host name.
        TCPServer.server_bind(self)
        self.server_name = "127.0.0.1"
        self.server_port = self.server_address[1]
        self.setup_environ()


class FakeOKX:
    """Stateful fake transport; it never opens a network connection."""

    def __init__(self):
        self.positions = {
            "MARGIN": [],
            "SWAP": [
                {
                    "instId": "BTC-USDT-SWAP",
                    "posId": "sw-1",
                    "pos": "2",
                    "posSide": "net",
                    "mgnMode": "isolated",
                    "ccy": "USDT",
                    "availPos": "2",
                    "margin": "100",
                }
            ],
            "FUTURES": [],
        }
        self.instruments = {
            "MARGIN": [
                {"instId": "BTC-USDT", "baseCcy": "BTC", "quoteCcy": "USDT", "lotSz": "0.01", "minSz": "0.01"}
            ],
            "SWAP": [
                {"instId": "BTC-USDT-SWAP", "baseCcy": "BTC", "lotSz": "1", "minSz": "1"},
                {"instId": "ETH-USDT-SWAP", "baseCcy": "ETH", "lotSz": "1", "minSz": "1"},
            ],
            "FUTURES": [
                {"instId": "BTC-USDT-260925", "baseCcy": "BTC", "lotSz": "1", "minSz": "1"}
            ],
        }
        self.calls: list[tuple[str, str, dict | None]] = []
        self.orders: dict[str, dict] = {}
        self.item_codes: list[str] = []
        self.top_level_codes: list[str] = []
        self.ack_overrides: list[dict] = []
        self.order_result_overrides: list[tuple[str, str]] = []
        self.suppress_order_position_update = False
        self.timeout_write_number: int | None = None
        self.write_count = 0
        self.account_uid: str | None = "123456789"
        self.switch_account_after_first_write = False
        self.post_write_snapshot_count = 0
        self.fail_positions_on_post_write_snapshot: int | None = None
        self.position_to_appear_after_close: dict | None = None
        self.account_config_read_count = 0
        self.switch_account_on_config_read: int | None = None

    def transport(self, method: str, path: str, headers: dict[str, str], body: bytes | None) -> dict:
        parsed = urlsplit(path)
        params = {key: values[-1] for key, values in parse_qs(parsed.query).items()}
        payload = None if body is None else json.loads(body.decode("utf-8"))
        self.calls.append((method, path, payload))

        if method == "GET" and parsed.path == "/api/v5/account/config":
            self.account_config_read_count += 1
            if self.write_count > 0:
                self.post_write_snapshot_count += 1
            uid = self.account_uid
            if self.switch_account_on_config_read == self.account_config_read_count:
                self.account_uid = "987654321"
                uid = self.account_uid
            if self.switch_account_after_first_write and self.write_count > 0:
                uid = "987654321"
            account = {"posMode": "net_mode", "acctLv": "2"}
            if uid is not None:
                account["uid"] = uid
            return {"code": "0", "data": [account]}
        if method == "GET" and parsed.path == "/api/v5/account/balance":
            return {"code": "0", "data": [{"totalEq": "0", "details": []}]}
        if method == "GET" and parsed.path == "/api/v5/account/positions":
            instrument_type = params["instType"]
            if (
                self.fail_positions_on_post_write_snapshot is not None
                and self.post_write_snapshot_count == self.fail_positions_on_post_write_snapshot
                and instrument_type == "MARGIN"
            ):
                self.fail_positions_on_post_write_snapshot = None
                raise TimeoutError("simulated transient positions failure")
            return {"code": "0", "data": [dict(item) for item in self.positions[instrument_type]]}
        if method == "GET" and parsed.path == "/api/v5/public/instruments":
            return {"code": "0", "data": [dict(item) for item in self.instruments[params["instType"]]]}
        if method == "GET" and parsed.path == "/api/v5/trade/order":
            return {"code": "0", "data": [dict(self.orders[params["clOrdId"]])] if params.get("clOrdId") in self.orders else []}

        if method == "POST" and parsed.path in (
            "/api/v5/account/position/margin-balance",
            "/api/v5/trade/order",
            "/api/v5/trade/close-position",
        ):
            self.write_count += 1
            if self.timeout_write_number == self.write_count:
                raise TimeoutError("simulated timeout")
            if self.top_level_codes:
                top_code = self.top_level_codes.pop(0)
                return {"code": top_code, "data": []}
            if self.ack_overrides:
                return self.ack_overrides.pop(0)
            code = self.item_codes.pop(0) if self.item_codes else "0"
            if code != "0":
                return {"code": "0", "data": [{"sCode": code, "sMsg": "simulated rejection"}]}
            if parsed.path == "/api/v5/trade/order":
                client_id = payload["clOrdId"]
                state, filled_size = self.order_result_overrides.pop(0) if self.order_result_overrides else (
                    "filled", payload["sz"]
                )
                self.orders[client_id] = {
                    "instId": payload["instId"],
                    "clOrdId": client_id,
                    "ordId": f"order-{self.write_count}",
                    "state": state,
                    "accFillSz": filled_size,
                }
                if not self.suppress_order_position_update:
                    self._apply_order(payload, filled_size)
                return {"code": "0", "data": [{"sCode": "0", "ordId": f"order-{self.write_count}", "clOrdId": client_id}]}
            if parsed.path == "/api/v5/trade/close-position":
                self._remove_position(payload["instId"])
                return {"code": "0", "data": [{"sCode": "0"}]}
            self._apply_margin(payload)
            return {"code": "0", "data": [{"sCode": "0"}]}

        raise AssertionError("unexpected fake exchange request")

    def _apply_order(self, payload: dict, executed_size: str | None = None) -> None:
        instrument_type = "MARGIN" if payload["instId"].count("-") == 1 else (
            "FUTURES" if payload["instId"].endswith(("260925",)) else "SWAP"
        )
        for position in self.positions[instrument_type]:
            if position["instId"] != payload["instId"]:
                continue
            old = Decimal(position["pos"])
            size = Decimal(executed_size if executed_size is not None else payload["sz"])
            position["pos"] = str(old + size if payload["side"] == "buy" else old - size)
            position["availPos"] = str(abs(Decimal(position["pos"])))
            return

    def _remove_position(self, instrument_id: str) -> None:
        for instrument_type in self.positions:
            self.positions[instrument_type] = [
                position for position in self.positions[instrument_type]
                if position["instId"] != instrument_id
            ]
        if self.position_to_appear_after_close is not None:
            position = self.position_to_appear_after_close
            self.position_to_appear_after_close = None
            instrument_id = position["instId"]
            instrument_type = "MARGIN" if instrument_id.count("-") == 1 else (
                "FUTURES" if instrument_id.endswith("260925") else "SWAP"
            )
            self.positions[instrument_type].append(position)

    def _apply_margin(self, payload: dict) -> None:
        for position in self.positions["MARGIN"]:
            if position["instId"] == payload["instId"]:
                position["margin"] = str(Decimal(position.get("margin", "0")) + Decimal(payload["amt"]))


class TradeApiTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = TemporaryDirectory()
        self.now = BASE_TIME
        self.exchange = FakeOKX()
        self.settings = RuntimeSettings(
            okx_api_key="test-key",
            okx_api_secret="test-secret",
            okx_api_passphrase="test-passphrase",
            admin_password_hash=hash_password(PASSWORD, salt=b"0123456789abcdef"),
            totp_secret=TOTP_SECRET,
            session_signing_key=SIGNING_KEY,
            allowed_web_origin=ORIGIN,
            operation_db_path=f"{self.temp.name}/operations.sqlite3",
        )
        self._start_server()

    def tearDown(self) -> None:
        self._stop_server()
        self.temp.cleanup()

    def _start_server(self) -> None:
        app = create_application(settings=self.settings, transport=self.exchange.transport, clock=lambda: self.now)
        self.server = make_server("127.0.0.1", 0, app, server_class=ThreadingWSGIServer, handler_class=QuietHandler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.base_url = f"http://127.0.0.1:{self.server.server_port}"

    def _stop_server(self) -> None:
        if getattr(self, "server", None) is not None:
            self.server.shutdown()
            self.server.server_close()
            self.thread.join(timeout=2)
            self.server = None

    def restart_server(self) -> None:
        self._stop_server()
        self._start_server()

    def simulate_interrupted_operation(
        self, operation_id: str, *, completed_targets: int = 0
    ) -> dict:
        with closing(sqlite3.connect(self.settings.operation_db_path)) as connection, connection:
            row = connection.execute(
                "SELECT payload_json FROM operations WHERE operation_id=?", (operation_id,)
            ).fetchone()
            self.assertIsNotNone(row)
            payload = json.loads(row[0])
            results = []
            for index, target in enumerate(payload["targets"]):
                if index < completed_targets:
                    self.exchange.transport(
                        "POST",
                        "/api/v5/trade/close-position",
                        {},
                        json.dumps(target["request"]).encode("utf-8"),
                    )
                    status = "SUCCEEDED"
                    outcome = {"reason": "position_closed_verified"}
                else:
                    status = "PENDING"
                    outcome = None
                results.append({"identity": target["identity"], "status": status, "outcome": outcome})
            connection.execute(
                "UPDATE operations SET status='IN_PROGRESS', results_json=?, updated_at=? WHERE operation_id=?",
                (json.dumps(results, separators=(",", ":")), self.now, operation_id),
            )
        return payload

    def request(
        self,
        method: str,
        path: str,
        body: dict | None = None,
        *,
        token: str | None = None,
        cookie: str | None = None,
        origin: str = ORIGIN,
        raw_body: bytes | None = None,
    ) -> tuple[int, dict]:
        data = raw_body
        headers = {"Origin": origin}
        if body is not None:
            data = json.dumps(body).encode("utf-8")
        if data is not None:
            headers["Content-Type"] = "application/json"
        if token:
            headers["Authorization"] = f"Bearer {token}"
        if cookie:
            headers["Cookie"] = f"__Host-trade_session={cookie}"
        request = urllib.request.Request(self.base_url + path, data=data, headers=headers, method=method)
        try:
            with urllib.request.urlopen(request, timeout=3) as response:
                self.last_response_headers = response.headers
                raw = response.read()
                return response.status, json.loads(raw.decode("utf-8")) if raw else {}
        except urllib.error.HTTPError as error:
            self.last_response_headers = error.headers
            raw = error.read()
            return error.code, json.loads(raw.decode("utf-8")) if raw else {}

    def login(self) -> str:
        code = _totp_at(TOTP_SECRET, int(self.now // 30))
        status, result = self.request("POST", "/v1/login", {"password": PASSWORD, "totp": code})
        self.assertEqual(status, 200, result)
        self.assertEqual(result["accountIdentifier"], "••••6789")
        return result["token"]

    @staticmethod
    def swap_identity() -> dict:
        return {
            "instrumentType": "SWAP",
            "instrumentId": "BTC-USDT-SWAP",
            "positionId": "sw-1",
            "positionSide": "net",
            "marginMode": "isolated",
        }

    def prepare(self, token: str, action: str, **fields: object) -> dict:
        body = {"action": action, **fields}
        status, result = self.request("POST", "/v1/actions/prepare", body, token=token)
        self.assertEqual(status, 200, result)
        return result

    def test_red_missing_session_and_wrong_origin_never_write(self) -> None:
        status, _ = self.request("POST", "/v1/actions/execute", {"operationId": "deadbeef", "confirmationToken": "x"})
        self.assertEqual(status, 401)
        status, _ = self.request("POST", "/v1/actions/prepare", {"action": "close_all"}, origin="https://attacker.example")
        self.assertEqual(status, 403)
        self.assertEqual(self.exchange.write_count, 0)

    def test_red_invalid_totp_and_replay_are_rejected_durably(self) -> None:
        valid_code = _totp_at(TOTP_SECRET, int(self.now // 30))
        status, _ = self.request("POST", "/v1/login", {"password": PASSWORD, "totp": "000000"})
        self.assertEqual(status, 401)
        status, first = self.request("POST", "/v1/login", {"password": PASSWORD, "totp": valid_code})
        self.assertEqual(status, 200)
        self.assertTrue(first["token"])
        status, _ = self.request("POST", "/v1/login", {"password": PASSWORD, "totp": valid_code})
        self.assertEqual(status, 401)
        self.restart_server()
        status, _ = self.request("POST", "/v1/login", {"password": PASSWORD, "totp": valid_code})
        self.assertEqual(status, 401)
        self.assertEqual(self.exchange.write_count, 0)

    def test_red_login_failure_limit_persists_across_restart(self) -> None:
        for _ in range(5):
            status, _ = self.request("POST", "/v1/login", {"password": "wrong-disposable-password", "totp": "000000"})
            self.assertEqual(status, 401)
        self.restart_server()
        status, result = self.request("POST", "/v1/login", {"password": "wrong-disposable-password", "totp": "000000"})
        self.assertEqual(status, 429)
        self.assertEqual(result["error"], "rate_limited")
        self.assertEqual(self.exchange.write_count, 0)

    def test_red_expired_session_is_rejected_without_exchange_write(self) -> None:
        token = self.login()
        self.now += 28_800
        status, _ = self.request("GET", "/v1/positions", token=token)
        self.assertEqual(status, 401)
        self.assertEqual(self.exchange.write_count, 0)

    def test_red_expired_session_cannot_read_cached_private_gateway_data(self) -> None:
        token = self.login()
        status, _ = self.request("GET", "/v1/data/account/balance", token=token)
        self.assertEqual(status, 200)
        calls_after_initial_read = len(self.exchange.calls)

        self.now += 28_800
        status, _ = self.request("GET", "/v1/data/account/balance", token=token)

        self.assertEqual(status, 401)
        self.assertEqual(len(self.exchange.calls), calls_after_initial_read)

    def test_red_login_cookie_restores_the_fixed_eight_hour_bearer_session(self) -> None:
        code = _totp_at(TOTP_SECRET, int(self.now // 30))
        status, login = self.request("POST", "/v1/login", {"password": PASSWORD, "totp": code})

        self.assertEqual(status, 200)
        set_cookie = self.last_response_headers.get("Set-Cookie")
        self.assertIsNotNone(set_cookie)
        cookie_parts = [part.strip() for part in set_cookie.split(";")]
        self.assertEqual(cookie_parts[0], f"__Host-trade_session={login['token']}")
        self.assertIn("Secure", cookie_parts)
        self.assertIn("HttpOnly", cookie_parts)
        self.assertIn("SameSite=Strict", cookie_parts)
        self.assertIn("Path=/", cookie_parts)
        self.assertIn("Max-Age=28800", cookie_parts)
        self.assertFalse(any(part.lower().startswith("domain=") for part in cookie_parts))

        with closing(sqlite3.connect(self.settings.operation_db_path)) as connection, connection:
            expires_at = connection.execute(
                "SELECT expires_at FROM sessions WHERE token_hash=?",
                (token_digest(login["token"], SIGNING_KEY),),
            ).fetchone()[0]
        self.assertEqual(expires_at, BASE_TIME + 28_800)

        self.now += 60
        status, restored = self.request("GET", "/v1/session", cookie=login["token"])

        self.assertEqual(status, 200)
        self.assertEqual(restored["token"], login["token"])
        self.assertEqual(restored["expiresAt"], login["expiresAt"])
        self.assertEqual(restored["accountIdentifier"], login["accountIdentifier"])
        status, _ = self.request("GET", "/v1/positions", token=login["token"])
        self.assertEqual(status, 200)
        with closing(sqlite3.connect(self.settings.operation_db_path)) as connection, connection:
            unchanged_expiry = connection.execute(
                "SELECT expires_at FROM sessions WHERE token_hash=?",
                (token_digest(login["token"], SIGNING_KEY),),
            ).fetchone()[0]
        self.assertEqual(unchanged_expiry, BASE_TIME + 28_800)

    def test_red_session_and_bearer_are_rejected_at_exact_expiry_without_write(self) -> None:
        token = self.login()
        self.now += 28_799

        status, _ = self.request("GET", "/v1/positions", token=token)
        self.assertEqual(status, 200)
        self.now += 1

        status, _ = self.request("GET", "/v1/session", cookie=token)
        self.assertEqual(status, 401)
        status, _ = self.request(
            "POST", "/v1/actions/execute",
            {"operationId": "deadbeef", "confirmationToken": "disposable"}, token=token,
        )
        self.assertEqual(status, 401)
        self.assertEqual(self.exchange.write_count, 0)

    def test_red_cookie_does_not_authorize_trade_writes(self) -> None:
        token = self.login()

        for method, path, body in (
            ("GET", "/v1/positions", None),
            ("POST", "/v1/actions/prepare", {"action": "close_all"}),
            ("POST", "/v1/actions/execute", {"operationId": "deadbeef", "confirmationToken": "x"}),
        ):
            with self.subTest(method=method, path=path):
                status, _ = self.request(method, path, body, cookie=token)
                self.assertEqual(status, 401)
        self.assertEqual(self.exchange.write_count, 0)

    def test_red_logout_revokes_session_and_clears_cookie(self) -> None:
        token = self.login()

        status, result = self.request("POST", "/v1/logout", {}, token=token)

        self.assertEqual(status, 200)
        self.assertEqual(result, {"status": "logged_out"})
        clear_cookie = self.last_response_headers.get("Set-Cookie")
        self.assertIsNotNone(clear_cookie)
        cookie_parts = [part.strip() for part in clear_cookie.split(";")]
        self.assertEqual(cookie_parts[0], "__Host-trade_session=")
        self.assertIn("Secure", cookie_parts)
        self.assertIn("HttpOnly", cookie_parts)
        self.assertIn("SameSite=Strict", cookie_parts)
        self.assertIn("Path=/", cookie_parts)
        self.assertIn("Max-Age=0", cookie_parts)
        status, _ = self.request("GET", "/v1/session", cookie=token)
        self.assertEqual(status, 401)
        self.assertEqual(self.exchange.write_count, 0)

    def test_red_allowed_origin_cors_includes_credentials_on_response_and_preflight(self) -> None:
        status, _ = self.request("GET", "/v1/health")

        self.assertEqual(status, 200)
        self.assertEqual(self.last_response_headers.get("Access-Control-Allow-Origin"), ORIGIN)
        self.assertEqual(self.last_response_headers.get("Access-Control-Allow-Credentials"), "true")
        status, _ = self.request("OPTIONS", "/v1/positions")
        self.assertEqual(status, 204)
        self.assertEqual(self.last_response_headers.get("Access-Control-Allow-Origin"), ORIGIN)
        self.assertEqual(self.last_response_headers.get("Access-Control-Allow-Credentials"), "true")
        status, _ = self.request("GET", "/v1/health", origin="https://attacker.example")
        self.assertEqual(status, 403)
        self.assertIsNone(self.last_response_headers.get("Access-Control-Allow-Origin"))
        status, _ = self.request("OPTIONS", "/v1/session", origin="https://attacker.example")
        self.assertEqual(status, 403)
        self.assertIsNone(self.last_response_headers.get("Access-Control-Allow-Credentials"))

    def test_green_authenticated_positions_include_normalized_okx_display_metrics(self) -> None:
        token = self.login()
        self.exchange.positions["SWAP"][0].update({
            "avgPx": "61000.1000",
            "markPx": "61111.20",
            "liqPx": "40000",
            "upl": "-12.500",
            "uplRatio": "-0.0500",
            "notionalUsd": "122222.400",
            "lever": "10.0",
        })

        status, response = self.request("GET", "/v1/positions", token=token)

        self.assertEqual(status, 200)
        position = response["positions"][0]
        self.assertEqual(position["avgPx"], "61000.1")
        self.assertEqual(position["markPx"], "61111.2")
        self.assertEqual(position["liqPx"], "40000")
        self.assertEqual(position["upl"], "-12.5")
        self.assertEqual(position["uplRatio"], "-0.05")
        self.assertEqual(position["notionalUsd"], "122222.4")
        self.assertEqual(position["lever"], "10")
        self.assertEqual(position["size"], "2")
        self.assertEqual(position["identity"], self.swap_identity())
        self.assertTrue(position["eligibleActions"]["closePosition"]["eligible"])

    def test_green_missing_okx_display_metrics_remain_absent(self) -> None:
        token = self.login()

        status, response = self.request("GET", "/v1/positions", token=token)

        self.assertEqual(status, 200)
        position = response["positions"][0]
        for field in ("avgPx", "markPx", "liqPx", "upl", "uplRatio", "notionalUsd", "lever"):
            self.assertIsNone(position[field], field)

    def test_red_stale_position_conflicts_before_any_write(self) -> None:
        token = self.login()
        prepared = self.prepare(token, "dca", targetIdentity=self.swap_identity(), size="1")
        self.exchange.positions["SWAP"][0]["pos"] = "3"
        status, result = self.request(
            "POST", "/v1/actions/execute",
            {"operationId": prepared["operationId"], "confirmationToken": prepared["confirmationToken"]},
            token=token,
        )
        self.assertEqual(status, 200)
        self.assertEqual(result["status"], "CONFLICT")
        self.assertEqual(self.exchange.write_count, 0)

    def test_red_changed_account_conflicts_even_when_position_matches(self) -> None:
        token = self.login()
        prepared = self.prepare(token, "dca", targetIdentity=self.swap_identity(), size="1")
        self.exchange.account_uid = "987654321"

        status, result = self.request(
            "POST", "/v1/actions/execute",
            {"operationId": prepared["operationId"], "confirmationToken": prepared["confirmationToken"]},
            token=token,
        )

        self.assertEqual(status, 200)
        self.assertEqual(result["status"], "CONFLICT")
        self.assertEqual(self.exchange.write_count, 0)
        self.assertNotIn("123456789", json.dumps(result))

    def test_red_missing_account_uid_does_not_create_an_actionable_operation(self) -> None:
        token = self.login()
        self.exchange.account_uid = None

        status, result = self.request(
            "POST", "/v1/actions/prepare",
            {"action": "close_position", "targetIdentity": self.swap_identity()},
            token=token,
        )

        self.assertEqual(status, 502)
        self.assertEqual(result["error"], "account_identity_unavailable")
        self.assertEqual(self.exchange.write_count, 0)
        with closing(sqlite3.connect(self.settings.operation_db_path)) as connection, connection:
            count = connection.execute("SELECT COUNT(*) FROM operations").fetchone()[0]
        self.assertEqual(count, 0)

    def test_red_legacy_operation_without_account_fingerprint_stays_unresolved(self) -> None:
        token = self.login()
        prepared = self.prepare(token, "close_position", targetIdentity=self.swap_identity())
        with closing(sqlite3.connect(self.settings.operation_db_path)) as connection, connection:
            row = connection.execute(
                "SELECT payload_json FROM operations WHERE operation_id=?",
                (prepared["operationId"],),
            ).fetchone()
            payload = json.loads(row[0])
            payload.pop("accountFingerprint", None)
            connection.execute(
                "UPDATE operations SET status='IN_PROGRESS', payload_json=?, results_json=? WHERE operation_id=?",
                (
                    json.dumps(payload, separators=(",", ":")),
                    json.dumps([{
                        "identity": self.swap_identity(),
                        "status": "UNKNOWN",
                        "outcome": {"reason": "exchange_outcome_unknown"},
                    }], separators=(",", ":")),
                    prepared["operationId"],
                ),
            )
        self.exchange.account_uid = "987654321"
        self.exchange.positions["SWAP"] = []

        status, result = self.request(
            "GET", f"/v1/actions/result/{prepared['operationId']}", token=token
        )

        self.assertEqual(status, 200)
        self.assertNotEqual(result["targets"][0]["status"], "SUCCEEDED")
        self.assertEqual(self.exchange.write_count, 0)

    def test_red_execute_rejects_legacy_operation_without_account_fingerprint(self) -> None:
        token = self.login()
        prepared = self.prepare(token, "close_position", targetIdentity=self.swap_identity())
        with closing(sqlite3.connect(self.settings.operation_db_path)) as connection, connection:
            row = connection.execute(
                "SELECT payload_json FROM operations WHERE operation_id=?",
                (prepared["operationId"],),
            ).fetchone()
            payload = json.loads(row[0])
            payload.pop("accountFingerprint", None)
            connection.execute(
                "UPDATE operations SET payload_json=? WHERE operation_id=?",
                (json.dumps(payload, separators=(",", ":")), prepared["operationId"]),
            )

        status, result = self.request(
            "POST", "/v1/actions/execute",
            {"operationId": prepared["operationId"], "confirmationToken": prepared["confirmationToken"]},
            token=token,
        )

        self.assertEqual(status, 200)
        self.assertEqual(result["status"], "CONFLICT")
        self.assertEqual(self.exchange.write_count, 0)

    def test_red_result_reconciliation_rejects_changed_account(self) -> None:
        token = self.login()
        prepared = self.prepare(token, "close_position", targetIdentity=self.swap_identity())
        with closing(sqlite3.connect(self.settings.operation_db_path)) as connection, connection:
            connection.execute(
                "UPDATE operations SET status='IN_PROGRESS', results_json=? WHERE operation_id=?",
                (
                    json.dumps([{
                        "identity": self.swap_identity(),
                        "status": "UNKNOWN",
                        "outcome": {"reason": "exchange_outcome_unknown"},
                    }], separators=(",", ":")),
                    prepared["operationId"],
                ),
            )
        self.exchange.account_uid = "987654321"
        self.exchange.positions["SWAP"] = []

        status, result = self.request(
            "GET", f"/v1/actions/result/{prepared['operationId']}", token=token
        )

        self.assertEqual(status, 200)
        self.assertNotEqual(result["targets"][0]["status"], "SUCCEEDED")
        self.assertEqual(self.exchange.write_count, 0)

    def test_red_close_all_stops_remaining_writes_after_account_changes(self) -> None:
        token = self.login()
        self.exchange.positions["SWAP"].append({
            "instId": "ETH-USDT-SWAP",
            "posId": "sw-2",
            "pos": "3",
            "posSide": "net",
            "mgnMode": "isolated",
            "ccy": "USDT",
            "availPos": "3",
            "margin": "150",
        })
        prepared = self.prepare(token, "close_all")
        self.exchange.switch_account_after_first_write = True

        status, result = self.request(
            "POST", "/v1/actions/execute",
            {"operationId": prepared["operationId"], "confirmationToken": prepared["confirmationToken"]},
            token=token,
        )

        self.assertEqual(status, 200)
        self.assertEqual(self.exchange.write_count, 1)
        self.assertEqual(result["targets"][1]["status"], "CONFLICT")
        self.assertEqual(
            result["targets"][1]["outcome"]["reason"],
            "account_identity_changed_during_execution",
        )
        self.assertNotIn("123456789", json.dumps(result))

    def test_red_margin_market_actions_are_disabled_and_close_all_ineligible_target_is_blocked(self) -> None:
        token = self.login()
        self.exchange.positions["MARGIN"] = [{
            "instId": "BTC-USDT", "posId": "m-1", "pos": "0.5", "posSide": "net",
            "mgnMode": "isolated", "ccy": "USDT", "posCcy": "BTC", "availPos": "1",
            "liab": "0.5", "liabCcy": "BTC",
        }]
        identity = {
            "instrumentType": "MARGIN", "instrumentId": "BTC-USDT", "positionId": "m-1",
            "positionSide": "net", "marginMode": "isolated", "marginCurrency": "USDT",
        }
        for action, fields, reason in (
            ("dca", {"size": "0.01"}, "margin_dca_capacity_unverified"),
            ("partial_close", {"percentage": "50"}, "margin_partial_close_capacity_unverified"),
        ):
            status, result = self.request(
                "POST", "/v1/actions/prepare",
                {"action": action, "targetIdentity": identity, **fields}, token=token,
            )
            self.assertEqual(status, 422)
            self.assertEqual(result["error"], "ineligible_target")
            self.assertEqual(result["reason"], reason)
        self.exchange.positions["SWAP"][0]["mgnMode"] = "unknown"
        status, result = self.request("POST", "/v1/actions/prepare", {"action": "close_all"}, token=token)
        self.assertEqual(status, 409)
        self.assertEqual(result["error"], "close_all_ineligible_targets")
        self.assertEqual(self.exchange.write_count, 0)

    def test_red_margin_direction_requires_verified_pos_currency_and_instrument_metadata(self) -> None:
        token = self.login()
        raw_position = {
            "instId": "BTC-USDT", "posId": "m-direction", "pos": "0.5", "posSide": "net",
            "mgnMode": "isolated", "ccy": "BTC", "availPos": "0.5",
        }
        cases = (
            ("missing posCcy", None, "BTC", "USDT", "0.5"),
            ("unrecognized posCcy", "DOGE", "BTC", "USDT", "0.5"),
            ("missing base metadata", "BTC", "", "USDT", "0.5"),
            ("missing quote metadata", "USDT", "BTC", "", "0.5"),
            ("nonpositive MARGIN pos", "BTC", "BTC", "USDT", "-0.5"),
        )
        for label, pos_currency, base_currency, quote_currency, pos_size in cases:
            with self.subTest(label=label):
                position = dict(raw_position, pos=pos_size)
                if pos_currency is not None:
                    position["posCcy"] = pos_currency
                else:
                    position.pop("posCcy", None)
                self.exchange.positions["MARGIN"] = [position]
                metadata = self.exchange.instruments["MARGIN"][0]
                metadata["baseCcy"] = base_currency
                metadata["quoteCcy"] = quote_currency

                status, result = self.request("GET", "/v1/positions", token=token)
                self.assertEqual(status, 200)
                view = result["positions"][0]
                self.assertIsNone(view["direction"])
                self.assertFalse(view["eligibleActions"]["addMargin"]["eligible"])
                self.assertFalse(view["eligibleActions"]["closePosition"]["eligible"])
                identity = {
                    "instrumentType": "MARGIN", "instrumentId": "BTC-USDT",
                    "positionId": "m-direction", "positionSide": "net",
                    "marginMode": "isolated", "marginCurrency": "BTC",
                }
                status, rejected = self.request(
                    "POST", "/v1/actions/prepare",
                    {"action": "close_position", "targetIdentity": identity}, token=token,
                )
                self.assertEqual(status, 422)
                self.assertEqual(rejected["reason"], "ambiguous_position_direction")
                self.assertEqual(self.exchange.write_count, 0)

    def test_green_login_and_derivative_dca_make_one_verified_fake_order(self) -> None:
        token = self.login()
        prepared = self.prepare(token, "dca", targetIdentity=self.swap_identity(), size="1")
        self.assertEqual(prepared["summary"]["targets"][0]["normalizedSize"], "1")
        self.assertNotIn("accountFingerprint", json.dumps(prepared))
        with closing(sqlite3.connect(self.settings.operation_db_path)) as connection, connection:
            row = connection.execute(
                "SELECT payload_json FROM operations WHERE operation_id=?",
                (prepared["operationId"],),
            ).fetchone()
        self.assertIsNotNone(row)
        journal_payload = json.loads(row[0])
        self.assertEqual(
            journal_payload["accountFingerprint"],
            token_digest("okx-account-uid:v1:123456789", SIGNING_KEY),
        )
        self.assertNotIn("123456789", row[0])
        status, result = self.request(
            "POST", "/v1/actions/execute",
            {"operationId": prepared["operationId"], "confirmationToken": prepared["confirmationToken"]},
            token=token,
        )
        self.assertEqual(status, 200)
        self.assertEqual(result["status"], "SUCCEEDED", result)
        self.assertEqual(self.exchange.write_count, 1)
        writes = [call for call in self.exchange.calls if call[0] == "POST"]
        self.assertEqual(writes[0][2]["side"], "buy")
        self.assertEqual(writes[0][2]["ordType"], "market")
        self.assertEqual(writes[0][2]["sz"], "1")

    def test_red_duplicate_execute_returns_journal_without_second_write(self) -> None:
        token = self.login()
        prepared = self.prepare(token, "close_position", targetIdentity=self.swap_identity())
        command = {"operationId": prepared["operationId"], "confirmationToken": prepared["confirmationToken"]}
        status, first = self.request("POST", "/v1/actions/execute", command, token=token)
        self.assertEqual(status, 200)
        self.assertEqual(first["status"], "SUCCEEDED")
        status, second = self.request("POST", "/v1/actions/execute", command, token=token)
        self.assertEqual(status, 200)
        self.assertEqual(second["status"], "SUCCEEDED")
        self.assertEqual(self.exchange.write_count, 1)

    def test_red_unknown_timeout_survives_restart_and_is_never_retried(self) -> None:
        token = self.login()
        prepared = self.prepare(token, "dca", targetIdentity=self.swap_identity(), size="1")
        self.exchange.timeout_write_number = 1
        command = {"operationId": prepared["operationId"], "confirmationToken": prepared["confirmationToken"]}
        status, executed = self.request("POST", "/v1/actions/execute", command, token=token)
        self.assertEqual(status, 200)
        self.assertEqual(executed["status"], "UNKNOWN")
        self.restart_server()
        status, persisted = self.request("GET", f"/v1/actions/result/{prepared['operationId']}", token=token)
        self.assertEqual(status, 200)
        self.assertEqual(persisted["status"], "UNKNOWN")
        status, duplicate = self.request("POST", "/v1/actions/execute", command, token=token)
        self.assertEqual(status, 200)
        self.assertEqual(duplicate["status"], "UNKNOWN")
        self.assertEqual(self.exchange.write_count, 1)

    def test_red_restart_conflicts_unattempted_single_action_without_write(self) -> None:
        token = self.login()
        prepared = self.prepare(token, "close_position", targetIdentity=self.swap_identity())
        self.simulate_interrupted_operation(prepared["operationId"])
        self.restart_server()
        call_count_before_result = len(self.exchange.calls)

        status, result = self.request(
            "GET", f"/v1/actions/result/{prepared['operationId']}", token=token
        )
        self.assertEqual(status, 200)
        self.assertEqual(result["status"], "CONFLICT")
        self.assertEqual(result["targets"][0]["status"], "CONFLICT")
        self.assertEqual(result["targets"][0]["outcome"]["reason"], "process_stopped_before_attempt")
        self.assertEqual(len(self.exchange.calls), call_count_before_result)
        self.assertEqual(self.exchange.write_count, 0)

        status, fresh = self.request(
            "POST", "/v1/actions/prepare",
            {"action": "close_position", "targetIdentity": self.swap_identity()}, token=token,
        )
        self.assertEqual(status, 200, fresh)
        self.assertEqual(self.exchange.write_count, 0)

    def test_red_restart_conflicts_later_close_all_target_without_another_write(self) -> None:
        token = self.login()
        self.exchange.positions["SWAP"].append({
            "instId": "ETH-USDT-SWAP", "posId": "sw-eth", "pos": "1", "posSide": "net",
            "mgnMode": "isolated", "ccy": "USDT", "availPos": "1", "margin": "25",
        })
        prepared = self.prepare(token, "close_all")
        self.assertEqual(prepared["summary"]["targetCount"], 2)
        payload = self.simulate_interrupted_operation(
            prepared["operationId"], completed_targets=1
        )
        self.assertEqual(self.exchange.write_count, 1)
        self.restart_server()

        status, result = self.request(
            "GET", f"/v1/actions/result/{prepared['operationId']}", token=token
        )
        self.assertEqual(status, 200)
        self.assertEqual(result["status"], "PARTIAL")
        self.assertEqual([target["status"] for target in result["targets"]], ["SUCCEEDED", "CONFLICT"])
        self.assertEqual(
            result["targets"][1]["outcome"]["reason"], "process_stopped_before_attempt"
        )
        self.assertEqual(self.exchange.write_count, 1)

        status, fresh = self.request(
            "POST", "/v1/actions/prepare",
            {"action": "close_position", "targetIdentity": payload["targets"][1]["identity"]},
            token=token,
        )
        self.assertEqual(status, 200, fresh)
        self.assertEqual(self.exchange.write_count, 1)

    def test_red_empty_success_ack_is_unknown_and_blocks_replacement_action(self) -> None:
        token = self.login()
        self.exchange.ack_overrides = [{"code": "0", "data": []}]
        prepared = self.prepare(token, "close_position", targetIdentity=self.swap_identity())
        command = {"operationId": prepared["operationId"], "confirmationToken": prepared["confirmationToken"]}
        status, result = self.request("POST", "/v1/actions/execute", command, token=token)
        self.assertEqual(status, 200)
        self.assertEqual(result["status"], "UNKNOWN")

        status, conflict = self.request(
            "POST", "/v1/actions/prepare",
            {"action": "close_position", "targetIdentity": self.swap_identity()}, token=token,
        )
        self.assertEqual(status, 409)
        self.assertEqual(conflict["error"], "operation_pending")
        self.assertEqual(self.exchange.write_count, 1)

    def test_red_malformed_success_item_ack_is_unknown(self) -> None:
        token = self.login()
        self.exchange.ack_overrides = [{"code": "0", "data": [{"ordId": "unindexed"}]}]
        prepared = self.prepare(token, "close_position", targetIdentity=self.swap_identity())
        status, result = self.request(
            "POST", "/v1/actions/execute",
            {"operationId": prepared["operationId"], "confirmationToken": prepared["confirmationToken"]},
            token=token,
        )
        self.assertEqual(status, 200)
        self.assertEqual(result["status"], "UNKNOWN")
        self.assertEqual(result["targets"][0]["status"], "UNKNOWN")
        self.assertEqual(self.exchange.write_count, 1)

    def test_red_canceled_order_with_nonzero_fill_is_partial_not_failed(self) -> None:
        token = self.login()
        self.exchange.order_result_overrides = [("canceled", "0.5")]
        prepared = self.prepare(token, "dca", targetIdentity=self.swap_identity(), size="1")
        command = {"operationId": prepared["operationId"], "confirmationToken": prepared["confirmationToken"]}
        status, result = self.request("POST", "/v1/actions/execute", command, token=token)
        self.assertEqual(status, 200)
        self.assertEqual(result["status"], "PARTIAL")
        self.assertEqual(result["targets"][0]["status"], "PARTIAL")
        self.assertEqual(result["targets"][0]["outcome"]["orderState"], "canceled")
        self.assertEqual(self.exchange.write_count, 1)

        status, polled = self.request(
            "GET", f"/v1/actions/result/{prepared['operationId']}", token=token
        )
        self.assertEqual(status, 200)
        self.assertEqual(polled["status"], "PARTIAL")
        self.assertEqual(self.exchange.write_count, 1)

    def test_green_result_route_reconciles_lost_order_ack_after_restart(self) -> None:
        token = self.login()
        prepared = self.prepare(token, "dca", targetIdentity=self.swap_identity(), size="1")
        self.exchange.timeout_write_number = 1
        command = {"operationId": prepared["operationId"], "confirmationToken": prepared["confirmationToken"]}
        status, executed = self.request("POST", "/v1/actions/execute", command, token=token)
        self.assertEqual(status, 200)
        self.assertEqual(executed["status"], "UNKNOWN")

        order = [call[2] for call in self.exchange.calls if call[0] == "POST"][0]
        self.exchange.orders[order["clOrdId"]] = {
            "instId": order["instId"], "clOrdId": order["clOrdId"],
            "ordId": "accepted-before-timeout", "state": "filled", "accFillSz": order["sz"],
        }
        self.exchange.positions["SWAP"][0]["pos"] = "3"
        self.exchange.positions["SWAP"][0]["availPos"] = "3"
        self.restart_server()
        status, reconciled = self.request(
            "GET", f"/v1/actions/result/{prepared['operationId']}", token=token
        )
        self.assertEqual(status, 200)
        self.assertEqual(reconciled["status"], "SUCCEEDED")
        self.assertEqual(self.exchange.write_count, 1)

    def test_green_result_route_advances_partial_order_to_filled_without_resending(self) -> None:
        token = self.login()
        self.exchange.order_result_overrides = [("partially_filled", "0.5")]
        prepared = self.prepare(token, "dca", targetIdentity=self.swap_identity(), size="1")
        command = {"operationId": prepared["operationId"], "confirmationToken": prepared["confirmationToken"]}
        status, partial = self.request("POST", "/v1/actions/execute", command, token=token)
        self.assertEqual(status, 200)
        self.assertEqual(partial["status"], "PARTIAL")
        self.assertEqual(self.exchange.write_count, 1)
        status, blocked = self.request(
            "POST", "/v1/actions/prepare",
            {"action": "dca", "targetIdentity": self.swap_identity(), "size": "1"}, token=token,
        )
        self.assertEqual(status, 409)
        self.assertEqual(blocked["error"], "operation_pending")

        order = [call[2] for call in self.exchange.calls if call[0] == "POST"][0]
        self.exchange.orders[order["clOrdId"]]["state"] = "filled"
        self.exchange.orders[order["clOrdId"]]["accFillSz"] = "1"
        self.exchange.positions["SWAP"][0]["pos"] = "3"
        self.exchange.positions["SWAP"][0]["availPos"] = "3"

        status, result = self.request(
            "GET", f"/v1/actions/result/{prepared['operationId']}", token=token
        )
        self.assertEqual(status, 200)
        self.assertEqual(result["status"], "SUCCEEDED")
        self.assertEqual(self.exchange.write_count, 1)

    def test_green_result_route_advances_partial_order_to_canceled_without_resending(self) -> None:
        token = self.login()
        self.exchange.order_result_overrides = [("partially_filled", "0.5")]
        prepared = self.prepare(token, "dca", targetIdentity=self.swap_identity(), size="1")
        status, partial = self.request(
            "POST", "/v1/actions/execute",
            {"operationId": prepared["operationId"], "confirmationToken": prepared["confirmationToken"]},
            token=token,
        )
        self.assertEqual(status, 200)
        self.assertEqual(partial["status"], "PARTIAL")

        order = [call[2] for call in self.exchange.calls if call[0] == "POST"][0]
        self.exchange.orders[order["clOrdId"]]["state"] = "canceled"
        self.exchange.orders[order["clOrdId"]]["accFillSz"] = "0.5"
        status, result = self.request(
            "GET", f"/v1/actions/result/{prepared['operationId']}", token=token
        )
        self.assertEqual(status, 200)
        self.assertEqual(result["status"], "PARTIAL")
        self.assertEqual(result["targets"][0]["outcome"]["reason"], "partial_fill_canceled")
        self.assertEqual(self.exchange.write_count, 1)

    def test_green_verified_terminal_partial_cancel_releases_prepare_conflict(self) -> None:
        token = self.login()
        self.exchange.order_result_overrides = [("canceled", "0.5")]
        self.exchange.suppress_order_position_update = True
        prepared = self.prepare(token, "dca", targetIdentity=self.swap_identity(), size="1")
        status, partial = self.request(
            "POST", "/v1/actions/execute",
            {"operationId": prepared["operationId"], "confirmationToken": prepared["confirmationToken"]},
            token=token,
        )
        self.assertEqual(status, 200)
        self.assertEqual(partial["status"], "PARTIAL")
        self.assertEqual(self.exchange.write_count, 1)

        status, blocked = self.request(
            "POST", "/v1/actions/prepare",
            {"action": "dca", "targetIdentity": self.swap_identity(), "size": "1"}, token=token,
        )
        self.assertEqual(status, 409)
        self.assertEqual(blocked["error"], "operation_pending")
        self.assertEqual(self.exchange.write_count, 1)

        self.exchange.positions["SWAP"][0]["pos"] = "2.5"
        self.exchange.positions["SWAP"][0]["availPos"] = "2.5"
        status, reconciled = self.request(
            "GET", f"/v1/actions/result/{prepared['operationId']}", token=token
        )
        self.assertEqual(status, 200)
        self.assertEqual(reconciled["status"], "PARTIAL")
        outcome = reconciled["targets"][0]["outcome"]
        self.assertEqual(outcome["orderState"], "canceled")
        self.assertIs(outcome["positionVerified"], True)
        self.assertIs(outcome["terminalPartialResolved"], True)

        status, next_prepared = self.request(
            "POST", "/v1/actions/prepare",
            {"action": "dca", "targetIdentity": self.swap_identity(), "size": "1"}, token=token,
        )
        self.assertEqual(status, 200, next_prepared)
        self.assertEqual(self.exchange.write_count, 1)

    def test_green_close_request_cancels_open_orders(self) -> None:
        token = self.login()
        prepared = self.prepare(token, "close_position", targetIdentity=self.swap_identity())
        status, result = self.request(
            "POST", "/v1/actions/execute",
            {"operationId": prepared["operationId"], "confirmationToken": prepared["confirmationToken"]},
            token=token,
        )
        self.assertEqual(status, 200)
        self.assertEqual(result["status"], "SUCCEEDED")
        close_request = [call[2] for call in self.exchange.calls if call[0] == "POST"][0]
        self.assertIs(close_request["autoCxl"], True)

    def test_red_action_rate_limit_and_body_cap(self) -> None:
        token = self.login()
        for _ in range(30):
            status, _ = self.request("POST", "/v1/actions/prepare", {}, token=token)
            self.assertEqual(status, 400)
        status, result = self.request("POST", "/v1/actions/prepare", {}, token=token)
        self.assertEqual(status, 429)
        self.assertEqual(result["error"], "rate_limited")
        status, result = self.request("POST", "/v1/login", raw_body=b"{" + b" " * 65536)
        self.assertEqual(status, 413)
        self.assertEqual(result["error"], "body_too_large")

    def test_green_margin_add_uses_margin_currency_and_verifies_increase(self) -> None:
        token = self.login()
        self.exchange.positions["MARGIN"] = [{
            "instId": "BTC-USDT", "posId": "m-2", "pos": "1", "posSide": "net",
            "mgnMode": "isolated", "ccy": "USDT", "posCcy": "BTC", "availPos": "1",
            "liab": "0", "liabCcy": "BTC", "margin": "20",
        }]
        identity = {
            "instrumentType": "MARGIN", "instrumentId": "BTC-USDT", "positionId": "m-2",
            "positionSide": "net", "marginMode": "isolated", "marginCurrency": "USDT",
        }
        prepared = self.prepare(token, "add_margin", targetIdentity=identity, amount="5")
        status, result = self.request(
            "POST", "/v1/actions/execute",
            {"operationId": prepared["operationId"], "confirmationToken": prepared["confirmationToken"]},
            token=token,
        )
        self.assertEqual(status, 200)
        self.assertEqual(result["status"], "SUCCEEDED", result)
        writes = [call for call in self.exchange.calls if call[0] == "POST"]
        self.assertEqual(writes[0][1], "/api/v5/account/position/margin-balance")
        self.assertEqual(writes[0][2]["ccy"], "USDT")

    def test_green_partial_close_is_reduce_only_and_rounded_down(self) -> None:
        token = self.login()
        prepared = self.prepare(token, "partial_close", targetIdentity=self.swap_identity(), percentage="50")
        self.assertEqual(prepared["summary"]["targets"][0]["normalizedSize"], "1")
        status, result = self.request(
            "POST", "/v1/actions/execute",
            {"operationId": prepared["operationId"], "confirmationToken": prepared["confirmationToken"]},
            token=token,
        )
        self.assertEqual(status, 200)
        self.assertEqual(result["status"], "SUCCEEDED")
        order = [call[2] for call in self.exchange.calls if call[0] == "POST"][0]
        self.assertIs(order["reduceOnly"], True)
        self.assertEqual(order["side"], "sell")

    def test_red_margin_dca_and_partial_close_are_disabled(self) -> None:
        token = self.login()
        position = {
            "instId": "BTC-USDT", "posId": "m-close", "pos": "0.5", "posSide": "net",
            "mgnMode": "isolated", "ccy": "USDT", "posCcy": "BTC", "availPos": "0.5",
            "liab": "0.1", "liabCcy": "BTC",
        }
        self.exchange.positions["MARGIN"] = [position]
        identity = {
            "instrumentType": "MARGIN", "instrumentId": "BTC-USDT", "positionId": "m-close",
            "positionSide": "net", "marginMode": "isolated", "marginCurrency": "USDT",
        }
        status, rejected = self.request(
            "POST", "/v1/actions/prepare",
            {"action": "partial_close", "targetIdentity": identity, "percentage": "50"}, token=token,
        )
        self.assertEqual(status, 422)
        self.assertEqual(rejected["error"], "ineligible_target")
        self.assertEqual(rejected["reason"], "margin_partial_close_capacity_unverified")

        status, rejected = self.request(
            "POST", "/v1/actions/prepare",
            {"action": "dca", "targetIdentity": identity, "size": "0.25"}, token=token,
        )
        self.assertEqual(status, 422)
        self.assertEqual(rejected["error"], "ineligible_target")
        self.assertEqual(rejected["reason"], "margin_dca_capacity_unverified")
        self.assertEqual(self.exchange.write_count, 0)

    def test_green_positive_pos_margin_short_uses_pos_currency_for_direction_and_margin_currency_for_close(self) -> None:
        token = self.login()
        self.exchange.positions["MARGIN"] = [{
            "instId": "BTC-USDT", "posId": "m-short", "pos": "0.5", "posSide": "net",
            "mgnMode": "isolated", "ccy": "BTC", "posCcy": "USDT", "availPos": "0.5",
            "margin": "20",
        }]
        status, positions = self.request("GET", "/v1/positions", token=token)
        self.assertEqual(status, 200)
        margin_position = positions["positions"][0]
        self.assertEqual(margin_position["direction"], "short")
        self.assertEqual(margin_position["size"], "0.5")
        self.assertEqual(margin_position["positionCurrency"], "USDT")
        self.assertEqual(margin_position["marginCurrency"], "BTC")
        self.assertTrue(margin_position["eligibleActions"]["addMargin"]["eligible"])
        self.assertTrue(margin_position["eligibleActions"]["closePosition"]["eligible"])
        self.assertEqual(
            margin_position["eligibleActions"]["dca"]["reason"],
            "margin_dca_capacity_unverified",
        )
        self.assertEqual(
            margin_position["eligibleActions"]["partialClose"]["reason"],
            "margin_partial_close_capacity_unverified",
        )
        identity = {
            "instrumentType": "MARGIN", "instrumentId": "BTC-USDT", "positionId": "m-short",
            "positionSide": "net", "marginMode": "isolated", "marginCurrency": "BTC",
        }
        prepared = self.prepare(token, "close_position", targetIdentity=identity)
        status, result = self.request(
            "POST", "/v1/actions/execute",
            {"operationId": prepared["operationId"], "confirmationToken": prepared["confirmationToken"]},
            token=token,
        )
        self.assertEqual(status, 200)
        self.assertEqual(result["status"], "SUCCEEDED")
        request = [call[2] for call in self.exchange.calls if call[0] == "POST"][0]
        self.assertEqual(request["ccy"], "BTC")
        self.assertEqual(request["ccy"], margin_position["marginCurrency"])
        self.assertNotEqual(request["ccy"], margin_position["positionCurrency"])
        self.assertIs(request["autoCxl"], True)
        self.assertEqual(self.exchange.write_count, 1)

    def test_red_close_all_uses_full_account_set_and_rechecks_before_writing(self) -> None:
        token = self.login()
        self.exchange.positions["FUTURES"] = [{
            "instId": "BTC-USDT-260925", "posId": "f-1", "pos": "1", "posSide": "net",
            "mgnMode": "isolated", "ccy": "USDT", "availPos": "1", "margin": "30",
        }]
        prepared = self.prepare(token, "close_all", displayFilter="BTC-USDT-SWAP")
        self.assertEqual(prepared["summary"]["targetCount"], 2)
        self.exchange.positions["FUTURES"].append({
            "instId": "ETH-USDT-SWAP", "posId": "new-1", "pos": "1", "posSide": "net",
            "mgnMode": "isolated", "ccy": "USDT", "availPos": "1", "margin": "10",
        })
        status, result = self.request(
            "POST", "/v1/actions/execute",
            {"operationId": prepared["operationId"], "confirmationToken": prepared["confirmationToken"]},
            token=token,
        )
        self.assertEqual(status, 200)
        self.assertEqual(result["status"], "CONFLICT")
        self.assertEqual(self.exchange.write_count, 0)

    def test_red_partial_close_all_reports_each_target_without_claiming_success(self) -> None:
        token = self.login()
        self.exchange.positions["FUTURES"] = [{
            "instId": "BTC-USDT-260925", "posId": "f-1", "pos": "1", "posSide": "net",
            "mgnMode": "isolated", "ccy": "USDT", "availPos": "1", "margin": "30",
        }]
        self.exchange.item_codes = ["0", "51000"]
        prepared = self.prepare(token, "close_all")
        status, result = self.request(
            "POST", "/v1/actions/execute",
            {"operationId": prepared["operationId"], "confirmationToken": prepared["confirmationToken"]},
            token=token,
        )
        self.assertEqual(status, 200)
        self.assertEqual(result["status"], "PARTIAL")
        self.assertEqual([target["status"] for target in result["targets"]], ["SUCCEEDED", "FAILED"])
        self.assertEqual(self.exchange.write_count, 2)

    def test_red_close_all_reconciles_transient_final_account_read_without_retrying_writes(self) -> None:
        token = self.login()
        prepared = self.prepare(token, "close_all")
        self.exchange.fail_positions_on_post_write_snapshot = 2

        status, executed = self.request(
            "POST", "/v1/actions/execute",
            {"operationId": prepared["operationId"], "confirmationToken": prepared["confirmationToken"]},
            token=token,
        )

        self.assertEqual(status, 200)
        self.assertEqual(executed["status"], "PARTIAL")
        self.assertEqual(executed["targets"][-1]["identity"], None)
        self.assertEqual(executed["targets"][-1]["status"], "UNKNOWN")
        write_count = self.exchange.write_count

        status, reconciled = self.request(
            "GET", f"/v1/actions/result/{prepared['operationId']}", token=token
        )

        self.assertEqual(status, 200)
        self.assertEqual(reconciled["status"], "SUCCEEDED")
        self.assertEqual([target["status"] for target in reconciled["targets"]], ["SUCCEEDED", "SUCCEEDED"])
        self.assertEqual(self.exchange.write_count, write_count)

    def test_red_close_all_aggregate_reconciliation_stays_unknown_on_account_change(self) -> None:
        token = self.login()
        prepared = self.prepare(token, "close_all")
        self.exchange.fail_positions_on_post_write_snapshot = 2
        status, executed = self.request(
            "POST", "/v1/actions/execute",
            {"operationId": prepared["operationId"], "confirmationToken": prepared["confirmationToken"]},
            token=token,
        )
        self.assertEqual(status, 200)
        self.assertEqual(executed["targets"][-1]["status"], "UNKNOWN")
        write_count = self.exchange.write_count
        self.exchange.account_uid = "987654321"

        status, reconciled = self.request(
            "GET", f"/v1/actions/result/{prepared['operationId']}", token=token
        )

        self.assertEqual(status, 200)
        self.assertEqual(reconciled["status"], "PARTIAL")
        self.assertEqual(reconciled["targets"][-1]["status"], "UNKNOWN")
        self.assertEqual(self.exchange.write_count, write_count)

    def test_red_close_all_final_snapshot_account_change_adds_unresolved_aggregate(self) -> None:
        token = self.login()
        prepared = self.prepare(token, "close_all")
        # Reads 1–4 cover prepare, execute preflight, per-target recheck, and
        # the successful post-close verification. Switch only for final check.
        self.exchange.switch_account_on_config_read = self.exchange.account_config_read_count + 4

        status, executed = self.request(
            "POST", "/v1/actions/execute",
            {"operationId": prepared["operationId"], "confirmationToken": prepared["confirmationToken"]},
            token=token,
        )

        self.assertEqual(status, 200)
        self.assertEqual(executed["targets"][0]["status"], "SUCCEEDED")
        self.assertEqual(executed["targets"][-1]["identity"], None)
        self.assertEqual(executed["targets"][-1]["status"], "UNKNOWN")
        self.assertNotEqual(executed["status"], "SUCCEEDED")
        write_count = self.exchange.write_count

        status, unresolved = self.request(
            "GET", f"/v1/actions/result/{prepared['operationId']}", token=token
        )

        self.assertEqual(status, 200)
        self.assertEqual(unresolved["targets"][-1]["status"], "UNKNOWN")
        self.assertNotEqual(unresolved["status"], "SUCCEEDED")
        self.assertEqual(self.exchange.write_count, write_count)

    def test_red_close_all_interrupted_after_targets_requires_same_account_final_check(self) -> None:
        token = self.login()
        prepared = self.prepare(token, "close_all")
        with closing(sqlite3.connect(self.settings.operation_db_path)) as connection, connection:
            row = connection.execute(
                "SELECT payload_json FROM operations WHERE operation_id=?",
                (prepared["operationId"],),
            ).fetchone()
            payload = json.loads(row[0])
            results = [
                {
                    "identity": target["identity"],
                    "status": "SUCCEEDED",
                    "outcome": {"reason": "position_closed_verified"},
                }
                for target in payload["targets"]
            ]
            connection.execute(
                "UPDATE operations SET status='IN_PROGRESS', results_json=? WHERE operation_id=?",
                (json.dumps(results, separators=(",", ":")), prepared["operationId"]),
            )
        self.exchange.account_uid = "987654321"

        status, unresolved = self.request(
            "GET", f"/v1/actions/result/{prepared['operationId']}", token=token
        )

        self.assertEqual(status, 200)
        self.assertEqual(unresolved["targets"][-1]["identity"], None)
        self.assertEqual(unresolved["targets"][-1]["status"], "UNKNOWN")
        self.assertNotEqual(unresolved["status"], "SUCCEEDED")
        self.assertEqual(self.exchange.write_count, 0)

    def test_red_close_all_reconciles_unconfirmed_position_only_after_it_disappears(self) -> None:
        token = self.login()
        self.exchange.position_to_appear_after_close = {
            "instId": "ETH-USDT-SWAP", "posId": "sw-new", "pos": "1", "posSide": "net",
            "mgnMode": "isolated", "ccy": "USDT", "availPos": "1", "margin": "10",
        }
        prepared = self.prepare(token, "close_all")

        status, executed = self.request(
            "POST", "/v1/actions/execute",
            {"operationId": prepared["operationId"], "confirmationToken": prepared["confirmationToken"]},
            token=token,
        )

        self.assertEqual(status, 200)
        self.assertEqual(executed["status"], "PARTIAL")
        extra = next(target for target in executed["targets"] if target["identity"]["positionId"] == "sw-new")
        self.assertEqual(extra["status"], "UNKNOWN")
        extra_identity = extra["identity"]
        write_count = self.exchange.write_count

        status, blocked = self.request(
            "POST", "/v1/actions/prepare",
            {"action": "close_position", "targetIdentity": extra_identity}, token=token,
        )
        self.assertEqual(status, 409)
        self.assertEqual(blocked["error"], "operation_pending")

        status, still_open = self.request(
            "GET", f"/v1/actions/result/{prepared['operationId']}", token=token
        )
        self.assertEqual(status, 200)
        self.assertEqual(still_open["status"], "PARTIAL")
        self.assertEqual(
            next(target for target in still_open["targets"] if target["identity"] == extra_identity)["status"],
            "UNKNOWN",
        )

        self.exchange._remove_position("ETH-USDT-SWAP")
        self.exchange.positions["SWAP"].append({
            "instId": "BTC-USDT-SWAP", "posId": "sw-late", "pos": "1", "posSide": "net",
            "mgnMode": "isolated", "ccy": "USDT", "availPos": "1", "margin": "10",
        })
        status, with_new_position = self.request(
            "GET", f"/v1/actions/result/{prepared['operationId']}", token=token
        )
        self.assertEqual(status, 200)
        self.assertEqual(with_new_position["status"], "PARTIAL")
        self.assertEqual(
            next(target for target in with_new_position["targets"] if target["identity"] == extra_identity)["status"],
            "SUCCEEDED",
        )
        late_position = next(
            target for target in with_new_position["targets"] if target["identity"]["positionId"] == "sw-late"
        )
        self.assertEqual(late_position["status"], "UNKNOWN")
        self.assertEqual(self.exchange.write_count, write_count)

        self.exchange._remove_position("BTC-USDT-SWAP")
        status, reconciled = self.request(
            "GET", f"/v1/actions/result/{prepared['operationId']}", token=token
        )
        self.assertEqual(status, 200)
        self.assertEqual(reconciled["status"], "SUCCEEDED")
        self.assertEqual(
            next(target for target in reconciled["targets"] if target["identity"]["positionId"] == "sw-late")["status"],
            "SUCCEEDED",
        )
        self.assertEqual(self.exchange.write_count, write_count)

    def test_red_item_level_exchange_error_is_not_reported_as_success(self) -> None:
        token = self.login()
        self.exchange.item_codes = ["51000"]
        prepared = self.prepare(token, "close_position", targetIdentity=self.swap_identity())
        status, result = self.request(
            "POST", "/v1/actions/execute",
            {"operationId": prepared["operationId"], "confirmationToken": prepared["confirmationToken"]},
            token=token,
        )
        self.assertEqual(status, 200)
        self.assertEqual(result["status"], "FAILED")
        self.assertEqual(result["targets"][0]["outcome"]["exchangeCode"], "51000")
        self.assertEqual(self.exchange.write_count, 1)

    def test_red_top_level_exchange_error_is_not_reported_as_success(self) -> None:
        token = self.login()
        self.exchange.top_level_codes = ["51008"]
        prepared = self.prepare(token, "close_position", targetIdentity=self.swap_identity())
        status, result = self.request(
            "POST", "/v1/actions/execute",
            {"operationId": prepared["operationId"], "confirmationToken": prepared["confirmationToken"]},
            token=token,
        )
        self.assertEqual(status, 200)
        self.assertEqual(result["status"], "FAILED")
        self.assertEqual(self.exchange.write_count, 1)

    def test_health_is_static_and_does_not_call_okx(self) -> None:
        status, result = self.request("GET", "/v1/health")
        self.assertEqual(status, 200)
        self.assertEqual(result, {"status": "ok"})
        self.assertEqual(self.exchange.calls, [])

    def test_okx_private_signature_matches_prehash_and_public_call_has_no_credentials(self) -> None:
        captured: list[tuple[str, str, dict[str, str], bytes | None]] = []

        def transport(method: str, path: str, headers: dict[str, str], body: bytes | None) -> dict:
            captured.append((method, path, headers, body))
            return {"code": "0", "data": []}

        client = OKXClient("fixture-key", "fixture-secret", "fixture-passphrase", transport=transport, clock=lambda: BASE_TIME)
        client.request("POST", "/api/v5/trade/order", body={"instId": "BTC-USDT-SWAP", "sz": "1"})
        method, path, headers, body = captured[-1]
        timestamp = dt.datetime.fromtimestamp(BASE_TIME, tz=dt.timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")
        prehash = f"{timestamp}{method}{path}{body.decode('utf-8')}".encode("utf-8")
        signature = base64.b64encode(hmac.new(b"fixture-secret", prehash, hashlib.sha256).digest()).decode("ascii")
        self.assertEqual(headers["OK-ACCESS-KEY"], "fixture-key")
        self.assertEqual(headers["OK-ACCESS-SIGN"], signature)
        self.assertEqual(headers["OK-ACCESS-PASSPHRASE"], "fixture-passphrase")
        client.request("GET", "/api/v5/public/instruments", params={"instType": "SWAP"})
        self.assertNotIn("OK-ACCESS-KEY", captured[-1][2])


if __name__ == "__main__":
    unittest.main()
