from __future__ import annotations

import io
import json
import threading
import unittest
from copy import deepcopy
from concurrent.futures import ThreadPoolExecutor
from decimal import Decimal, ROUND_CEILING
from tempfile import TemporaryDirectory
from typing import Any
from urllib.parse import parse_qs, urlsplit

from backend.app import create_application
from backend.security import token_digest
from backend.service import RuntimeSettings, TradeService


NOW = 1_798_848_000.0
SIGNING_KEY = bytes(range(32))
TOKEN = "strategy-test-session-token"
ORIGIN = "https://strategy.example.test"
INSTRUMENT = "BTC-USDT-SWAP"


class FakeStrategyExchange:
    """Injectable exchange transport. All requests remain local to this test."""

    def __init__(self) -> None:
        self.pos_mode = "net_mode"
        self.account_uid = "123456789"
        self.positions: list[dict[str, Any]] = []
        self.fail_position_reads = False
        self.pending: list[dict[str, Any]] = []
        self.fee_data: list[dict[str, Any]] = [
            {"instType": "SWAP", "instFamily": "BTC-USDT", "maker": "0.0002", "taker": "0.0005"}
        ]
        self.tier_data: list[dict[str, Any]] = [
            {"instType": "SWAP", "tdMode": "isolated", "instFamily": "BTC-USDT", "tier": "1",
             "minSz": "0", "maxSz": "100000", "mmr": "0.01", "imr": "0.1", "maxLever": "125"}
        ]
        self.instrument_data: list[dict[str, Any]] = [
            {"instId": INSTRUMENT, "instType": "SWAP", "instFamily": "BTC-USDT", "state": "live",
             "baseCcy": "BTC", "quoteCcy": "USDT",
             "settleCcy": "USDT", "ctVal": "0.001", "ctMult": "1", "ctValCcy": "BTC",
             "tickSz": "0.1", "lotSz": "1", "minSz": "1"}
        ]
        self.last = "60000"
        self.ticker_instrument_id = INSTRUMENT
        self.calls: list[tuple[str, str, Any]] = []
        self.orders: dict[str, dict[str, Any]] = {}
        self.batch_timeout = False
        self.batch_ack: Any = None
        self.batch_top_code = "0"
        self.position_read_barrier: threading.Barrier | None = None
        self.position_barrier_reads = 0
        self.pause_batch_response = False
        self.batch_started = threading.Event()
        self.batch_release = threading.Event()
        self.order_detail_reads = 0

    @property
    def trade_writes(self) -> list[tuple[str, str, Any]]:
        return [call for call in self.calls if call[0] == "POST"]

    @property
    def batch_writes(self) -> list[tuple[str, str, Any]]:
        return [call for call in self.trade_writes if urlsplit(call[1]).path == "/api/v5/trade/batch-orders"]

    def transport(self, method: str, path: str, headers: dict[str, str], body: bytes | None) -> dict[str, Any]:
        parsed = urlsplit(path)
        params = {key: values[-1] for key, values in parse_qs(parsed.query).items()}
        payload = None if body is None else json.loads(body.decode("utf-8"))
        self.calls.append((method, path, payload))

        if method == "GET" and parsed.path == "/api/v5/account/config":
            return {"code": "0", "data": [{"uid": self.account_uid, "posMode": self.pos_mode}]}
        if method == "GET" and parsed.path == "/api/v5/account/balance":
            return {"code": "0", "data": [{"details": [{"ccy": "USDT", "availBal": "100000"}]}]}
        if method == "GET" and parsed.path == "/api/v5/account/positions":
            if self.fail_position_reads:
                raise TimeoutError("simulated account position read failure")
            if self.position_read_barrier is not None and self.position_barrier_reads < 2:
                self.position_barrier_reads += 1
                self.position_read_barrier.wait(timeout=3)
            return {"code": "0", "data": [dict(row) for row in self.positions]}
        if method == "GET" and parsed.path == "/api/v5/trade/orders-pending":
            return {"code": "0", "data": [dict(row) for row in self.pending]}
        if method == "GET" and parsed.path == "/api/v5/account/trade-fee":
            return {"code": "0", "data": [dict(row) for row in self.fee_data]}
        if method == "GET" and parsed.path == "/api/v5/public/instruments":
            return {"code": "0", "data": [dict(row) for row in self.instrument_data]}
        if method == "GET" and parsed.path == "/api/v5/public/position-tiers":
            return {"code": "0", "data": [dict(row) for row in self.tier_data]}
        if method == "GET" and parsed.path == "/api/v5/market/ticker":
            return {"code": "0", "data": [{"instId": self.ticker_instrument_id, "last": self.last, "ts": str(int(NOW * 1000))}]}
        if method == "GET" and parsed.path == "/api/v5/trade/order":
            self.order_detail_reads += 1
            client_id = params.get("clOrdId", "")
            row = self.orders.get(client_id)
            return {"code": "0", "data": [] if row is None else [dict(row)]}
        if method == "POST" and parsed.path == "/api/v5/account/set-leverage":
            return {"code": "0", "data": [{"sCode": "0", "posSide": payload["posSide"]}]}
        if method == "POST" and parsed.path == "/api/v5/trade/batch-orders":
            if self.batch_timeout:
                raise TimeoutError("simulated lost batch response")
            if self.batch_ack is not None:
                return {"code": self.batch_top_code, "data": self.batch_ack}
            rows = []
            for index, order in enumerate(payload):
                client_id = order["clOrdId"]
                exchange_id = f"exchange-{index + 1}"
                self.orders[client_id] = {
                    **order, "ordId": exchange_id, "state": "live", "accFillSz": "0"
                }
                rows.append({"sCode": "0", "ordId": exchange_id, "clOrdId": client_id})
            if self.pause_batch_response:
                self.batch_started.set()
                if not self.batch_release.wait(timeout=5):
                    raise TimeoutError("test batch response release timed out")
            return {"code": self.batch_top_code, "data": rows}
        raise AssertionError(f"Unexpected fake exchange request: {method} {parsed.path}")


class StrategyApiTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = TemporaryDirectory()
        self.now = NOW
        self.exchange = FakeStrategyExchange()
        self.settings = RuntimeSettings(
            okx_api_key="test-key", okx_api_secret="test-secret", okx_api_passphrase="test-passphrase",
            admin_password_hash="unused-in-this-session-fixture", totp_secret="unused-in-this-session-fixture",
            session_signing_key=SIGNING_KEY, allowed_web_origin=ORIGIN,
            operation_db_path=f"{self.temp.name}/operations.sqlite3",
        )
        self.service = TradeService(self.settings, transport=self.exchange.transport, clock=lambda: self.now)
        self.app = create_application(service=self.service)
        with self.service.store.transaction() as connection:
            connection.execute(
                "INSERT INTO sessions(token_hash, expires_at, created_at) VALUES (?, ?, ?)",
                (token_digest(TOKEN, SIGNING_KEY), self.now + 3600, self.now),
            )

    def tearDown(self) -> None:
        self.temp.cleanup()

    def request(
        self, method: str, path: str, body: dict[str, Any] | None = None, *, authenticated: bool = True
    ) -> tuple[int, dict[str, Any]]:
        raw = b"" if body is None else json.dumps(body).encode("utf-8")
        environ: dict[str, Any] = {
            "REQUEST_METHOD": method, "PATH_INFO": path, "REMOTE_ADDR": "127.0.0.1",
            "HTTP_ORIGIN": ORIGIN, "CONTENT_TYPE": "application/json", "CONTENT_LENGTH": str(len(raw)),
            "wsgi.input": io.BytesIO(raw),
        }
        if authenticated:
            environ["HTTP_AUTHORIZATION"] = f"Bearer {TOKEN}"
        response: dict[str, Any] = {}

        def start_response(status: str, headers: list[tuple[str, str]]) -> None:
            response["status"] = int(status.split(" ", 1)[0])

        chunks = self.app(environ, start_response)
        payload = b"".join(chunks)
        return response["status"], {} if not payload else json.loads(payload.decode("utf-8"))

    @staticmethod
    def one_sided_contract() -> dict[str, Any]:
        return {
            "instrumentId": INSTRUMENT,
            "interval": "12Hutc",
            "selectedLevels": [{"side": "long", "price": "59000"}],
            "entryBySide": {"long": "59000"},
            "totalMargin": "60",
            "leverage": {"long": 5},
            "sidePercent": {"long": "100"},
            "allocation": "equal",
        }

    @staticmethod
    def two_sided_contract() -> dict[str, Any]:
        return {
            "instrumentId": INSTRUMENT,
            "interval": "12Hutc",
            "selectedLevels": [
                {"side": "long", "price": "59000"}, {"side": "short", "price": "61000"}
            ],
            "entryBySide": {"long": "59000", "short": "61000"},
            "totalMargin": "100",
            "leverage": {"long": 5, "short": 5},
            "sidePercent": {"long": "50", "short": "50"},
            "allocation": "equal",
        }

    def save_draft(self, contract: dict[str, Any] | None = None) -> tuple[str, dict[str, Any]]:
        source = self.one_sided_contract() if contract is None else contract
        status, preview = self.request("POST", "/v1/strategies/preview", source)
        self.assertEqual(status, 200, preview)
        status, saved = self.request(
            "POST", "/v1/strategies", {**source, "previewHash": preview["previewHash"]}
        )
        self.assertEqual(status, 200, saved)
        return saved["id"], preview

    def test_red_strategy_routes_require_bearer_before_exchange_reads(self) -> None:
        status, result = self.request("GET", "/v1/strategies", authenticated=False)
        self.assertEqual(status, 401, result)
        self.assertEqual(result["error"], "authentication_required")
        self.assertEqual(self.exchange.calls, [])

    def test_red_apply_preflight_blocks_net_mode_position_and_pending_order_before_writes(self) -> None:
        strategy_id, _ = self.save_draft(self.two_sided_contract())
        status, result = self.request("POST", f"/v1/strategies/{strategy_id}/prepare-apply", {})
        self.assertEqual(status, 409, result)
        self.assertEqual(result["error"], "account_mode_unsupported")
        self.assertEqual(self.exchange.trade_writes, [])

        self.exchange.pos_mode = "long_short_mode"
        self.exchange.positions = [{"instId": INSTRUMENT, "pos": "1", "posSide": "long", "mgnMode": "isolated"}]
        status, result = self.request("POST", f"/v1/strategies/{strategy_id}/prepare-apply", {})
        self.assertEqual(status, 409, result)
        self.assertEqual(result["error"], "instrument_position_exists")
        self.assertEqual(self.exchange.trade_writes, [])

        self.exchange.positions = []
        self.exchange.pending = [{"instId": INSTRUMENT, "ordId": "existing-order"}]
        status, result = self.request("POST", f"/v1/strategies/{strategy_id}/prepare-apply", {})
        self.assertEqual(status, 409, result)
        self.assertEqual(result["error"], "pending_order_exists")
        self.assertEqual(self.exchange.trade_writes, [])

    def test_red_unvalidated_fee_tier_or_contract_metadata_blocks_preview(self) -> None:
        self.exchange.tier_data = []
        status, result = self.request("POST", "/v1/strategies/preview", self.one_sided_contract())
        self.assertEqual(status, 502, result)
        self.assertEqual(result["error"], "preview_inputs_unavailable")

        self.exchange.tier_data = [
            {"instType": "SWAP", "tdMode": "isolated", "instFamily": "BTC-USDT", "tier": "1",
             "minSz": "0", "maxSz": "100000", "mmr": "0.01", "imr": "0.1", "maxLever": "125"}
        ]
        self.exchange.fee_data = []
        status, result = self.request("POST", "/v1/strategies/preview", self.one_sided_contract())
        self.assertEqual(status, 502, result)
        self.assertEqual(result["error"], "preview_inputs_unavailable")

        self.exchange.fee_data = [
            {"instType": "SWAP", "instFamily": "BTC-USDT", "maker": "0.0002", "taker": "0.0005"}
        ]
        undersized = self.one_sided_contract()
        undersized["totalMargin"] = "1"
        undersized["leverage"] = {"long": 1}
        status, result = self.request("POST", "/v1/strategies/preview", undersized)
        self.assertEqual(status, 422, result)
        self.assertEqual(result["reason"], "order_below_minimum")
        self.assertEqual(self.exchange.trade_writes, [])

    def test_red_invalid_tick_and_marketable_level_are_rejected_before_save(self) -> None:
        invalid_tick = self.one_sided_contract()
        invalid_tick["selectedLevels"] = [{"side": "long", "price": "59000.05"}]
        invalid_tick["entryBySide"] = {"long": "59000.05"}
        status, result = self.request("POST", "/v1/strategies/preview", invalid_tick)
        self.assertEqual(status, 422, result)
        self.assertEqual(result["error"], "invalid_strategy")

        self.exchange.last = "58000"
        status, result = self.request("POST", "/v1/strategies/preview", self.one_sided_contract())
        self.assertEqual(status, 422, result)
        self.assertEqual(result["reason"], "entry_side_invalid")
        self.assertEqual(self.exchange.trade_writes, [])

    def test_red_account_change_and_expired_prepare_do_not_write(self) -> None:
        strategy_id, _ = self.save_draft()
        self.exchange.account_uid = "987654321"
        status, result = self.request("POST", f"/v1/strategies/{strategy_id}/prepare-apply", {})
        self.assertEqual(status, 409, result)
        self.assertEqual(result["error"], "account_changed")
        self.assertEqual(self.exchange.trade_writes, [])

        self.exchange.account_uid = "123456789"
        status, prepared = self.request("POST", f"/v1/strategies/{strategy_id}/prepare-apply", {})
        self.assertEqual(status, 200, prepared)
        self.now += 121
        status, expired = self.request(
            "POST", f"/v1/strategies/{strategy_id}/execute-apply",
            {"confirmationToken": prepared["confirmationToken"]},
        )
        self.assertEqual(status, 200, expired)
        self.assertEqual(expired["status"], "DRAFT")
        self.assertEqual(self.exchange.trade_writes, [])

    def test_red_partial_batch_ack_is_immutable_and_not_resubmitted(self) -> None:
        strategy_id, _ = self.save_draft()
        status, prepared = self.request("POST", f"/v1/strategies/{strategy_id}/prepare-apply", {})
        self.assertEqual(status, 200, prepared)
        client_id = prepared["orders"][0]["clientOrderId"]
        self.exchange.batch_ack = [{"sCode": "51000", "sMsg": "rejected", "clOrdId": client_id}]
        command = {"confirmationToken": prepared["confirmationToken"]}
        status, result = self.request("POST", f"/v1/strategies/{strategy_id}/execute-apply", command)
        self.assertEqual(status, 200, result)
        self.assertEqual(result["status"], "PARTIAL")
        status, duplicate = self.request("POST", f"/v1/strategies/{strategy_id}/execute-apply", command)
        self.assertEqual(status, 200, duplicate)
        self.assertEqual(duplicate["status"], "PARTIAL")
        status, deleted = self.request("POST", f"/v1/strategies/{strategy_id}/delete", {})
        self.assertEqual(status, 409, deleted)
        self.assertEqual(len(self.exchange.batch_writes), 1)

    def test_red_unknown_batch_and_duplicate_execute_are_durable_and_never_retried(self) -> None:
        strategy_id, _ = self.save_draft()
        status, prepared = self.request("POST", f"/v1/strategies/{strategy_id}/prepare-apply", {})
        self.assertEqual(status, 200, prepared)
        self.exchange.batch_timeout = True
        command = {"confirmationToken": prepared["confirmationToken"]}
        status, first = self.request("POST", f"/v1/strategies/{strategy_id}/execute-apply", command)
        self.assertEqual(status, 200, first)
        self.assertEqual(first["status"], "UNKNOWN")

        status, duplicate = self.request("POST", f"/v1/strategies/{strategy_id}/execute-apply", command)
        self.assertEqual(status, 200, duplicate)
        status, reconciled = self.request("GET", f"/v1/strategies/{strategy_id}/result")
        self.assertEqual(status, 200, reconciled)
        self.assertEqual(reconciled["status"], "UNKNOWN")
        self.assertEqual(len(self.exchange.batch_writes), 1)
        status, deleted = self.request("POST", f"/v1/strategies/{strategy_id}/delete", {})
        self.assertEqual(status, 409, deleted)
        self.assertEqual(len(self.exchange.batch_writes), 1)

    def test_red_top_level_partial_batch_code_uses_per_order_outcomes(self) -> None:
        self.exchange.pos_mode = "long_short_mode"
        strategy_id, _ = self.save_draft(self.two_sided_contract())
        status, prepared = self.request("POST", f"/v1/strategies/{strategy_id}/prepare-apply", {})
        self.assertEqual(status, 200, prepared)
        self.exchange.batch_top_code = "2"
        self.exchange.batch_ack = [
            {"sCode": "0", "ordId": "accepted-order", "clOrdId": prepared["orders"][0]["clientOrderId"]},
            {"sCode": "51000", "sMsg": "rejected", "clOrdId": prepared["orders"][1]["clientOrderId"]},
        ]
        status, result = self.request(
            "POST", f"/v1/strategies/{strategy_id}/execute-apply",
            {"confirmationToken": prepared["confirmationToken"]},
        )
        self.assertEqual(status, 200, result)
        self.assertEqual(result["status"], "PARTIAL")
        self.assertEqual([row["status"] for row in result["orders"]], ["accepted", "rejected"])

    def test_red_top_level_error_without_per_order_evidence_is_unknown(self) -> None:
        strategy_id, _ = self.save_draft()
        status, prepared = self.request("POST", f"/v1/strategies/{strategy_id}/prepare-apply", {})
        self.assertEqual(status, 200, prepared)
        self.exchange.batch_top_code = "1"
        self.exchange.batch_ack = []
        status, result = self.request(
            "POST", f"/v1/strategies/{strategy_id}/execute-apply",
            {"confirmationToken": prepared["confirmationToken"]},
        )
        self.assertEqual(status, 200, result)
        self.assertEqual(result["status"], "UNKNOWN")
        self.assertEqual(result["orders"][0]["status"], "unknown")

    def test_red_top_level_code_1_contradicting_all_success_items_stays_unknown(self) -> None:
        strategy_id, _ = self.save_draft()
        status, prepared = self.request("POST", f"/v1/strategies/{strategy_id}/prepare-apply", {})
        self.assertEqual(status, 200, prepared)
        self.exchange.batch_top_code = "1"
        self.exchange.batch_ack = [{
            "sCode": "0", "ordId": "accepted-order", "clOrdId": prepared["orders"][0]["clientOrderId"],
        }]
        status, result = self.request(
            "POST", f"/v1/strategies/{strategy_id}/execute-apply",
            {"confirmationToken": prepared["confirmationToken"]},
        )
        self.assertEqual(status, 200, result)
        self.assertEqual(result["status"], "UNKNOWN")
        self.assertEqual(result["orders"][0]["status"], "accepted")

    def test_red_top_level_code_2_contradicting_all_success_items_stays_unknown(self) -> None:
        strategy_id, _ = self.save_draft()
        status, prepared = self.request("POST", f"/v1/strategies/{strategy_id}/prepare-apply", {})
        self.assertEqual(status, 200, prepared)
        self.exchange.batch_top_code = "2"
        self.exchange.batch_ack = [{
            "sCode": "0", "ordId": "accepted-order", "clOrdId": prepared["orders"][0]["clientOrderId"],
        }]
        status, result = self.request(
            "POST", f"/v1/strategies/{strategy_id}/execute-apply",
            {"confirmationToken": prepared["confirmationToken"]},
        )
        self.assertEqual(status, 200, result)
        self.assertEqual(result["status"], "UNKNOWN")
        self.assertEqual(result["orders"][0]["status"], "accepted")

    def test_red_active_result_and_list_do_not_reconcile_applying_batch(self) -> None:
        strategy_id, _ = self.save_draft()
        status, prepared = self.request("POST", f"/v1/strategies/{strategy_id}/prepare-apply", {})
        self.assertEqual(status, 200, prepared)
        self.exchange.pause_batch_response = True
        command = {"confirmationToken": prepared["confirmationToken"]}
        with ThreadPoolExecutor(max_workers=1) as pool:
            future = pool.submit(self.request, "POST", f"/v1/strategies/{strategy_id}/execute-apply", command)
            self.assertTrue(self.exchange.batch_started.wait(timeout=5), "batch request did not reach fake exchange")
            before = self.exchange.order_detail_reads
            with self.service.store.connection() as connection:
                marker_before = connection.execute(
                    "SELECT status, batch_attempted FROM strategies WHERE strategy_id=?", (strategy_id,)
                ).fetchone()
            self.assertEqual(tuple(marker_before), ("APPLYING", 1))
            status, detail = self.request("GET", f"/v1/strategies/{strategy_id}/result")
            self.assertEqual(status, 200, detail)
            status, listing = self.request("GET", "/v1/strategies")
            self.assertEqual(status, 200, listing)
            self.assertEqual(self.exchange.order_detail_reads, before)
            self.assertEqual(detail["status"], "APPLYING")
            with self.service.store.connection() as connection:
                marker_after = connection.execute(
                    "SELECT status, batch_attempted FROM strategies WHERE strategy_id=?", (strategy_id,)
                ).fetchone()
            self.assertEqual(tuple(marker_after), ("APPLYING", 1))
            self.exchange.batch_release.set()
            status, final = future.result(timeout=8)
        self.assertEqual(status, 200, final)
        self.assertEqual(final["status"], "APPLIED")

    def test_red_interrupted_batch_attempt_recovers_from_applying(self) -> None:
        strategy_id, _ = self.save_draft()
        status, prepared = self.request("POST", f"/v1/strategies/{strategy_id}/prepare-apply", {})
        self.assertEqual(status, 200, prepared)
        with self.service.store.transaction() as connection:
            connection.execute(
                "UPDATE strategies SET status='APPLYING', attempt_started=1, batch_attempted=1, "
                "updated_at=? WHERE strategy_id=?",
                (self.now - 3600, strategy_id),
            )
        status, result = self.request("GET", f"/v1/strategies/{strategy_id}/result")
        self.assertEqual(status, 200, result)
        self.assertNotEqual(result["status"], "APPLYING")
        self.assertEqual(result["status"], "UNKNOWN")

    def test_green_interrupted_batch_with_known_exchange_order_recovers_applied(self) -> None:
        strategy_id, _ = self.save_draft()
        status, prepared = self.request("POST", f"/v1/strategies/{strategy_id}/prepare-apply", {})
        self.assertEqual(status, 200, prepared)
        order = prepared["orders"][0]
        client_id = order["clientOrderId"]
        self.exchange.orders[client_id] = {
            "clOrdId": client_id, "ordId": "exchange-after-crash", "instId": INSTRUMENT,
            "sz": order["contracts"], "accFillSz": "0", "state": "live",
        }
        with self.service.store.transaction() as connection:
            connection.execute(
                "UPDATE strategies SET status='APPLYING', attempt_started=1, batch_attempted=1, "
                "execution_id='abandoned-executor', execution_lease_until=?, updated_at=? "
                "WHERE strategy_id=?",
                (self.now - 1, self.now - 3600, strategy_id),
            )
            connection.execute(
                "INSERT INTO strategy_reservations(account_fingerprint, instrument_id, strategy_id, created_at) "
                "SELECT account_fingerprint, ?, strategy_id, ? FROM strategies WHERE strategy_id=?",
                (INSTRUMENT, self.now - 3600, strategy_id),
            )
        self.service = TradeService(self.settings, transport=self.exchange.transport, clock=lambda: self.now)
        self.app = create_application(service=self.service)
        other_id, _ = self.save_draft()
        status, other_prepared = self.request("POST", f"/v1/strategies/{other_id}/prepare-apply", {})
        self.assertEqual(status, 200, other_prepared)
        status, conflict = self.request(
            "POST", f"/v1/strategies/{other_id}/execute-apply",
            {"confirmationToken": other_prepared["confirmationToken"]},
        )
        self.assertEqual(status, 409, conflict)
        self.assertEqual(conflict["error"], "instrument_apply_in_progress")
        self.assertEqual(self.exchange.trade_writes, [])
        status, result = self.request("GET", f"/v1/strategies/{strategy_id}/result")
        self.assertEqual(status, 200, result)
        self.assertEqual(result["status"], "APPLIED")
        self.assertEqual(result["orders"][0]["status"], "live")
        with self.service.store.connection() as connection:
            reservation = connection.execute(
                "SELECT strategy_id FROM strategy_reservations WHERE strategy_id=?", (strategy_id,)
            ).fetchone()
        self.assertIsNotNone(reservation)

    def test_red_order_detail_identity_and_planned_size_mismatch_remain_unknown(self) -> None:
        strategy_id, _ = self.save_draft()
        status, prepared = self.request("POST", f"/v1/strategies/{strategy_id}/prepare-apply", {})
        self.assertEqual(status, 200, prepared)
        status, applied = self.request(
            "POST", f"/v1/strategies/{strategy_id}/execute-apply",
            {"confirmationToken": prepared["confirmationToken"]},
        )
        self.assertEqual(status, 200, applied)
        client_id = prepared["orders"][0]["clientOrderId"]
        expected_size = prepared["orders"][0]["contracts"]
        original = dict(self.exchange.orders[client_id])
        mismatches = [
            ("instrument", {"instId": "ETH-USDT-SWAP"}),
            ("client order", {"clOrdId": "stwrongclientorderid"}),
            ("planned size", {"sz": "4"}),
        ]
        for label, changes in mismatches:
            with self.subTest(label=label):
                self.exchange.orders[client_id] = {
                    **original, **changes, "state": "filled", "accFillSz": "4", "avgPx": "59000",
                }
                status, result = self.request("GET", f"/v1/strategies/{strategy_id}/result")
                self.assertEqual(status, 200, result)
                self.assertEqual(result["status"], "UNKNOWN")
                self.assertEqual(result["orders"][0]["status"], "unknown")
                self.assertEqual(result["orders"][0].get("filledContracts"), "0")
                self.assertEqual(result["orders"][0].get("averageFillPrice"), None)
                with self.service.store.connection() as connection:
                    reservation = connection.execute(
                        "SELECT strategy_id FROM strategy_reservations WHERE strategy_id=?", (strategy_id,)
                    ).fetchone()
                self.assertIsNotNone(reservation)
                self.exchange.orders[client_id] = {
                    **original, "sz": expected_size, "state": "live", "accFillSz": "0",
                }
                status, resolved = self.request("GET", f"/v1/strategies/{strategy_id}/result")
                self.assertEqual(status, 200, resolved)
                self.assertEqual(resolved["status"], "APPLIED")

    def test_red_batch_marker_update_refusal_prevents_network_write(self) -> None:
        strategy_id, _ = self.save_draft()
        status, prepared = self.request("POST", f"/v1/strategies/{strategy_id}/prepare-apply", {})
        self.assertEqual(status, 200, prepared)
        self.service.strategy._mark_batch_attempted = lambda _strategy_id, _execution_id: False
        status, result = self.request(
            "POST", f"/v1/strategies/{strategy_id}/execute-apply",
            {"confirmationToken": prepared["confirmationToken"]},
        )
        self.assertEqual(status, 200, result)
        self.assertEqual(result["status"], "APPLYING")
        self.assertEqual(self.exchange.batch_writes, [])
        with self.service.store.connection() as connection:
            row = connection.execute(
                "SELECT batch_attempted FROM strategies WHERE strategy_id=?", (strategy_id,)
            ).fetchone()
        self.assertEqual(row["batch_attempted"], 0)

    def test_red_account_instrument_reservation_serializes_parallel_strategies(self) -> None:
        strategy_ids: list[str] = []
        prepared: list[dict[str, Any]] = []
        for _ in range(2):
            strategy_id, _ = self.save_draft()
            status, value = self.request("POST", f"/v1/strategies/{strategy_id}/prepare-apply", {})
            self.assertEqual(status, 200, value)
            strategy_ids.append(strategy_id)
            prepared.append(value)
        self.exchange.position_read_barrier = threading.Barrier(2)
        self.exchange.position_barrier_reads = 0
        def execute(index: int) -> tuple[int, dict[str, Any]]:
            return self.request(
                "POST", f"/v1/strategies/{strategy_ids[index]}/execute-apply",
                {"confirmationToken": prepared[index]["confirmationToken"]},
            )
        with ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(execute, range(2)))
        self.assertEqual(len(self.exchange.batch_writes), 1)
        self.assertEqual(sorted(status for status, _ in results), [200, 409])

    def test_red_missing_or_invalid_actual_fill_price_stays_unavailable(self) -> None:
        strategy_id, _ = self.save_draft()
        status, prepared = self.request("POST", f"/v1/strategies/{strategy_id}/prepare-apply", {})
        self.assertEqual(status, 200, prepared)
        status, applied = self.request(
            "POST", f"/v1/strategies/{strategy_id}/execute-apply",
            {"confirmationToken": prepared["confirmationToken"]},
        )
        self.assertEqual(status, 200, applied)
        client_id = prepared["orders"][0]["clientOrderId"]
        self.exchange.orders[client_id].update(state="filled", accFillSz="5", avgPx="not-a-price")
        self.exchange.positions = [{
            "instId": INSTRUMENT, "pos": "5", "posSide": "net", "mgnMode": "isolated", "upl": "10",
        }]
        status, result = self.request("GET", f"/v1/strategies/{strategy_id}/result")
        self.assertEqual(status, 200, result)
        self.assertIsNone(result["filledMargin"])
        self.assertIsNone(result["usedMargin"])
        self.assertIsNone(result["pnlPercent"])

    def test_red_exchange_market_metadata_identity_and_max_leverage_are_validated(self) -> None:
        baseline_instruments = deepcopy(self.exchange.instrument_data)
        baseline_fees = deepcopy(self.exchange.fee_data)
        baseline_tiers = deepcopy(self.exchange.tier_data)
        baseline_ticker = self.exchange.ticker_instrument_id
        cases = [
            ("instrument state", lambda: self.exchange.instrument_data[0].update(state="suspend")),
            ("instrument type", lambda: self.exchange.instrument_data[0].update(instType="SPOT")),
            ("ticker identity", lambda: setattr(self.exchange, "ticker_instrument_id", "ETH-USDT-SWAP")),
            ("fee type", lambda: self.exchange.fee_data[0].update(instType="SPOT")),
            ("fee family", lambda: self.exchange.fee_data[0].update(instFamily="ETH-USDT")),
            ("tier mode", lambda: self.exchange.tier_data[0].update(tdMode="cross")),
            ("tier family", lambda: self.exchange.tier_data[0].update(instFamily="ETH-USDT")),
            ("missing max leverage", lambda: self.exchange.tier_data[0].pop("maxLever")),
        ]
        for label, corrupt in cases:
            with self.subTest(label=label):
                self.exchange.instrument_data = deepcopy(baseline_instruments)
                self.exchange.fee_data = deepcopy(baseline_fees)
                self.exchange.tier_data = deepcopy(baseline_tiers)
                self.exchange.ticker_instrument_id = baseline_ticker
                corrupt()
                status, result = self.request("POST", "/v1/strategies/preview", self.one_sided_contract())
                self.assertEqual(status, 502, result)
        self.exchange.instrument_data = deepcopy(baseline_instruments)
        self.exchange.fee_data = deepcopy(baseline_fees)
        self.exchange.tier_data = deepcopy(baseline_tiers)
        self.exchange.ticker_instrument_id = baseline_ticker
        self.exchange.tier_data[0]["maxLever"] = "4"
        status, result = self.request("POST", "/v1/strategies/preview", self.one_sided_contract())
        self.assertEqual(status, 422, result)
        self.assertEqual(result["reason"], "leverage_exceeds_tier")

    def test_red_missing_fee_identity_and_tier_instrument_type_fail_closed(self) -> None:
        for path, field in (
            ("fee_data", "instType"), ("fee_data", "instFamily"), ("tier_data", "instType"),
        ):
            with self.subTest(path=path, field=field):
                exchange_rows = getattr(self.exchange, path)
                original = deepcopy(exchange_rows)
                exchange_rows[0].pop(field)
                status, result = self.request("POST", "/v1/strategies/preview", self.one_sided_contract())
                self.assertEqual(status, 502, result)
                setattr(self.exchange, path, original)

    def test_green_decimal_preview_batch_and_restart_status(self) -> None:
        strategy_id, preview = self.save_draft()
        status, draft = self.request("GET", f"/v1/strategies/{strategy_id}/result")
        self.assertEqual(status, 200, draft)
        order = preview["orders"][0]
        saved_order = draft["orders"][0]
        self.assertEqual(order["contracts"], "5")
        self.assertEqual(order["margin"], "59")
        self.assertEqual(preview["unallocatedMargin"], "1")
        independently_calculated = (
            (Decimal("236") / Decimal("0.0049475") / Decimal("0.1"))
            .to_integral_value(rounding=ROUND_CEILING) * Decimal("0.1")
        )
        self.assertEqual(order["liquidationEstimate"], {
            "status": "estimated", "price": format(independently_calculated, "f")
        })

        status, prepared = self.request("POST", f"/v1/strategies/{strategy_id}/prepare-apply", {})
        self.assertEqual(status, 200, prepared)
        self.assertEqual(prepared["orders"][0]["clientOrderId"], saved_order["clientOrderId"])
        status, applied = self.request(
            "POST", f"/v1/strategies/{strategy_id}/execute-apply",
            {"confirmationToken": prepared["confirmationToken"]},
        )
        self.assertEqual(status, 200, applied)
        self.assertEqual(applied["status"], "APPLIED")
        self.assertEqual(len(self.exchange.batch_writes), 1)
        batch = self.exchange.batch_writes[0][2]
        self.assertEqual(len(batch), 1)
        self.assertEqual(batch[0]["ordType"], "limit")
        self.assertEqual(batch[0]["tdMode"], "isolated")
        self.assertEqual(batch[0]["side"], "buy")

        self.service = TradeService(self.settings, transport=self.exchange.transport, clock=lambda: self.now)
        self.app = create_application(service=self.service)
        status, result = self.request("GET", f"/v1/strategies/{strategy_id}/result")
        self.assertEqual(status, 200, result)
        self.assertEqual(result["status"], "APPLIED")
        self.assertEqual(result["orders"][0]["status"], "live")
        self.assertEqual(result["filledMargin"], "0")
        self.assertIsNone(result["pnlPercent"])

        client_id = saved_order["clientOrderId"]
        self.exchange.orders[client_id].update(state="filled", accFillSz="5", avgPx="59000")
        self.exchange.positions = [{
            "instId": INSTRUMENT, "pos": "5", "posSide": "net", "mgnMode": "isolated",
            "upl": "10", "avgPx": "59000", "markPx": "60000", "liqPx": "47700.9",
        }]
        status, filled = self.request("GET", f"/v1/strategies/{strategy_id}/result")
        self.assertEqual(status, 200, filled)
        self.assertEqual(filled["orders"][0]["status"], "filled")
        self.assertEqual(filled["usedMargin"], "59")
        self.assertEqual(Decimal(filled["pnlPercent"]), Decimal("10") / Decimal("59") * Decimal(100))
        self.assertEqual(filled["positions"][0]["liquidationPrice"], "47700.9")
        self.assertFalse(filled["attributionChanged"])
        self.exchange.fail_position_reads = True
        status, unavailable = self.request("GET", f"/v1/strategies/{strategy_id}/result")
        self.assertEqual(status, 200, unavailable)
        self.assertEqual(unavailable["positionStatus"], "unavailable")
        self.assertIsNone(unavailable["unrealizedPnl"])
        self.assertIsNone(unavailable["attributionChanged"])
        self.assertEqual(len(self.exchange.batch_writes), 1)


if __name__ == "__main__":
    unittest.main()
