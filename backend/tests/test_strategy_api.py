from __future__ import annotations

import io
import json
import os
import threading
import unittest
from copy import deepcopy
from concurrent.futures import ThreadPoolExecutor
from decimal import Decimal, ROUND_CEILING, ROUND_FLOOR
from pathlib import Path
from typing import Any
from unittest.mock import patch
from urllib.parse import parse_qs, urlsplit

from backend.app import create_application
from backend.okx import OKXError
from backend.security import token_digest
from backend.service import APIError, RuntimeSettings, TradeService
from backend.store import encode_json
from backend.strategy_worker import StrategyOrderWorker, WorkerSettings


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
        self.position_response_override = False
        self.position_response: Any = None
        self.fail_position_reads = False
        self.pending: list[dict[str, Any]] = []
        self.available_balance = "100000"
        self.account_balance_response_override = False
        self.account_balance_response: Any = None
        self.pending_reads = 0
        self.position_reads = 0
        self.fee_data: list[dict[str, Any]] = [
            {
                "instType": "SWAP", "instFamily": "BTC-USDT",
                "feeGroup": [
                    {"groupId": "1", "maker": "-0.0001", "taker": "-0.001"},
                    {"groupId": "2", "maker": "-0.0002", "taker": "-0.0005"},
                ],
            }
        ]
        self.tier_data: list[dict[str, Any]] = [
            {"instType": "SWAP", "tdMode": "isolated", "instFamily": "BTC-USDT", "tier": "1",
             "minSz": "0", "maxSz": "100000", "mmr": "0.01", "imr": "0.1", "maxLever": "125"}
        ]
        self.instrument_data: list[dict[str, Any]] = [
            {"instId": INSTRUMENT, "instType": "SWAP", "instFamily": "BTC-USDT", "state": "live",
             "groupId": "2", "ctType": "linear",
             "baseCcy": "BTC", "quoteCcy": "USDT",
             "settleCcy": "USDT", "ctVal": "0.001", "ctMult": "1", "ctValCcy": "BTC",
             "tickSz": "0.1", "lotSz": "1", "minSz": "1"}
        ]
        self.last = "60000"
        self.ticker_instrument_id = INSTRUMENT
        self.use_requested_ticker = False
        self.ticker_timestamp_ms = str(int(NOW * 1000))
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
        self.single_order_attempts = 0
        self.single_order_timeouts: set[int] = set()
        self.single_order_acks: dict[int, Any] = {}
        self.single_order_start_times: list[float] = []
        self.lease_renewal_counter: Any = None
        self.lease_renewal_counts: list[int] = []
        self.after_single_order_write: Any = None
        self.monotonic: Any = None
        self.order_detail_reads = 0
        self.order_detail_client_ids: list[str] = []
        self.after_order_detail_read: Any = None
        self.order_detail_response_override = False
        self.order_detail_response: Any = None
        self.leverage_response: dict[str, Any] | None = None
        self.after_leverage_write: Any = None
        self.quote_account_barrier: threading.Barrier | None = None
        self.pause_ticker = False
        self.ticker_started = threading.Event()
        self.ticker_release = threading.Event()

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
        if self.lease_renewal_counter is not None:
            self.lease_renewal_counts.append(self.lease_renewal_counter())
        self.calls.append((method, path, payload))

        if method == "GET" and parsed.path == "/api/v5/account/config":
            if self.quote_account_barrier is not None:
                self.quote_account_barrier.wait(timeout=3)
            return {"code": "0", "data": [{"uid": self.account_uid, "posMode": self.pos_mode}]}
        if method == "GET" and parsed.path == "/api/v5/account/balance":
            if self.account_balance_response_override:
                return deepcopy(self.account_balance_response)
            return {"code": "0", "data": [{"details": [{"ccy": "USDT", "availBal": self.available_balance}]}]}
        if method == "GET" and parsed.path == "/api/v5/account/positions":
            self.position_reads += 1
            if self.fail_position_reads:
                raise TimeoutError("simulated account position read failure")
            if self.position_read_barrier is not None and self.position_barrier_reads < 2:
                self.position_barrier_reads += 1
                self.position_read_barrier.wait(timeout=3)
            if self.position_response_override:
                return deepcopy(self.position_response)
            return {"code": "0", "data": [dict(row) for row in self.positions]}
        if method == "GET" and parsed.path == "/api/v5/trade/orders-pending":
            self.pending_reads += 1
            return {"code": "0", "data": [dict(row) for row in self.pending]}
        if method == "GET" and parsed.path == "/api/v5/account/trade-fee":
            family = params.get("instFamily")
            matched = [row for row in self.fee_data if row.get("instFamily") == family]
            rows = matched if matched else self.fee_data
            return {"code": "0", "data": [dict(row) for row in rows]}
        if method == "GET" and parsed.path == "/api/v5/public/instruments":
            return {"code": "0", "data": [dict(row) for row in self.instrument_data]}
        if method == "GET" and parsed.path == "/api/v5/public/position-tiers":
            family = params.get("instFamily")
            matched = [row for row in self.tier_data if row.get("instFamily") == family]
            rows = matched if matched else self.tier_data
            return {"code": "0", "data": [dict(row) for row in rows]}
        if method == "GET" and parsed.path == "/api/v5/market/ticker":
            if self.pause_ticker:
                self.ticker_started.set()
                if not self.ticker_release.wait(timeout=3):
                    raise TimeoutError("test ticker response release timed out")
            ticker_instrument = (
                params.get("instId", INSTRUMENT)
                if self.use_requested_ticker else self.ticker_instrument_id
            )
            return {"code": "0", "data": [{"instId": ticker_instrument, "last": self.last, "ts": self.ticker_timestamp_ms}]}
        if method == "GET" and parsed.path == "/api/v5/trade/order":
            self.order_detail_reads += 1
            client_id = params.get("clOrdId", "")
            self.order_detail_client_ids.append(client_id)
            row = self.orders.get(client_id)
            details = None if row is None else dict(row)
            if self.after_order_detail_read is not None:
                self.after_order_detail_read(client_id, details)
            if self.order_detail_response_override:
                return deepcopy(self.order_detail_response)
            return {"code": "0", "data": [] if details is None else [details]}
        if method == "POST" and parsed.path == "/api/v5/account/set-leverage":
            if self.leverage_response is not None:
                response = dict(self.leverage_response)
            else:
                response = {
                    "code": "0",
                    "data": [{
                        "instId": payload["instId"], "mgnMode": payload["mgnMode"],
                        "lever": payload["lever"], "posSide": payload["posSide"],
                    }],
                }
            if self.after_leverage_write is not None:
                self.after_leverage_write(payload, response)
            return response
        if method == "POST" and parsed.path == "/api/v5/trade/order":
            attempt = self.single_order_attempts
            self.single_order_attempts += 1
            if self.monotonic is not None:
                self.single_order_start_times.append(self.monotonic())
            if attempt in self.single_order_timeouts:
                raise TimeoutError("simulated lost single-order response")
            if attempt in self.single_order_acks:
                return self.single_order_acks[attempt]
            client_id = payload["clOrdId"]
            exchange_id = f"single-exchange-{attempt + 1}"
            self.orders[client_id] = {
                **payload, "ordId": exchange_id, "state": "live", "accFillSz": "0"
            }
            if self.after_single_order_write is not None:
                self.after_single_order_write(payload, exchange_id)
            return {
                "code": "0",
                "data": [{"sCode": "0", "ordId": exchange_id, "clOrdId": client_id}],
            }
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
        self.db_path = Path(__file__).resolve().parents[2] / (
            f".strategy-api-test-{os.getpid()}-{id(self)}.sqlite3"
        )
        self.now = NOW
        self.exchange = FakeStrategyExchange()
        self.settings = RuntimeSettings(
            okx_api_key="test-key", okx_api_secret="test-secret", okx_api_passphrase="test-passphrase",
            admin_password_hash="unused-in-this-session-fixture", totp_secret="unused-in-this-session-fixture",
            session_signing_key=SIGNING_KEY, allowed_web_origin=ORIGIN,
            operation_db_path=str(self.db_path),
        )
        self.service = TradeService(self.settings, transport=self.exchange.transport, clock=lambda: self.now)
        self.app = create_application(service=self.service)
        with self.service.store.transaction() as connection:
            connection.execute(
                "INSERT INTO sessions(token_hash, expires_at, created_at) VALUES (?, ?, ?)",
                (token_digest(TOKEN, SIGNING_KEY), self.now + 3600, self.now),
            )
            connection.execute(
                "INSERT INTO strategy_account_preferences(account_fingerprint, limit_order_submission_mode, updated_at) "
                "VALUES (?, 'batch', ?)",
                (token_digest("okx-account-uid:v1:" + self.exchange.account_uid, SIGNING_KEY), self.now),
            )

    def tearDown(self) -> None:
        self.db_path.unlink(missing_ok=True)

    def request(
        self,
        method: str,
        path: str,
        body: dict[str, Any] | None = None,
        *,
        authenticated: bool = True,
        captured_headers: list[tuple[str, str]] | None = None,
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
            if captured_headers is not None:
                captured_headers.extend(headers)

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

    @staticmethod
    def id_mode_contract(
        selected_levels: list[dict[str, Any]] | None = None,
        *,
        direction: str = "long",
        entry_ids: dict[str, str] | None = None,
        include_legacy_entries: bool = False,
    ) -> dict[str, Any]:
        rows = deepcopy(selected_levels or [{"side": "long", "price": "59000", "levelId": "long-1"}])
        selected_entries = dict(entry_ids or {"long": rows[0]["levelId"]})
        sides = sorted({row["side"] for row in rows}, key=lambda side: (side != "long", side))
        contract: dict[str, Any] = {
            "instrumentId": INSTRUMENT,
            "interval": "12Hutc",
            "selectedLevels": rows,
            "direction": direction,
            "entryLevelIdBySide": selected_entries,
            "totalMargin": "60" if len(sides) == 1 else "100",
            "leverage": {side: 5 for side in sides},
            "sidePercent": {side: "100" if len(sides) == 1 else "50" for side in sides},
            "allocation": "equal",
        }
        if include_legacy_entries:
            contract["entryBySide"] = {
                side: next(row["price"] for row in rows if row["levelId"] == level_id)
                for side, level_id in selected_entries.items()
            }
        return contract

    @staticmethod
    def multi_order_contract(
        long_count: int, short_count: int = 0, instrument_id: str = INSTRUMENT
    ) -> dict[str, Any]:
        rows: list[dict[str, Any]] = []
        entries: dict[str, str] = {}
        for side, count in (("long", long_count), ("short", short_count)):
            for index in range(count):
                level_id = f"{side}-{index + 1}"
                price = str(59000 - index * 100) if side == "long" else str(61000 + index * 100)
                rows.append({"side": side, "price": price, "levelId": level_id})
                if index == 0:
                    entries[side] = level_id
        direction = "both" if long_count and short_count else "long" if long_count else "short"
        contract = StrategyApiTests.id_mode_contract(rows, direction=direction, entry_ids=entries)
        contract["instrumentId"] = instrument_id
        contract["totalMargin"] = "1000" if long_count and short_count else "600"
        return contract

    def _add_fake_instrument(self, instrument_id: str) -> None:
        family = instrument_id[: -len("-SWAP")]
        currency = family.split("-", 1)[0]
        self.exchange.instrument_data.append({
            **self.exchange.instrument_data[0],
            "instId": instrument_id,
            "instFamily": family,
            "baseCcy": currency,
            "ctValCcy": currency,
        })
        self.exchange.fee_data.append({**self.exchange.fee_data[0], "instFamily": family})
        self.exchange.tier_data.append({**self.exchange.tier_data[0], "instFamily": family})
        self.exchange.use_requested_ticker = True

    def _worker(self) -> StrategyOrderWorker:
        monotonic_now = [0.0]

        def sleep(seconds: float) -> None:
            self.now += seconds
            monotonic_now[0] += seconds

        settings = WorkerSettings(
            okx_api_key="test-key",
            okx_api_secret="test-secret",
            okx_api_passphrase="test-passphrase",
            session_signing_key=SIGNING_KEY,
            operation_db_path=self.settings.operation_db_path,
        )
        return StrategyOrderWorker(
            settings,
            store=self.service.store,
            transport=self.exchange.transport,
            clock=lambda: self.now,
            owner_id="strategy-api-test-worker",
            lease_seconds=30,
            order_interval_seconds=5,
            call_spacing_seconds=0,
            sleep=sleep,
            monotonic=lambda: monotonic_now[0],
        )

    def _append_persisted_order(self, strategy_id: str, *, append_contract: bool = True) -> None:
        with self.service.store.transaction() as connection:
            row = connection.execute(
                "SELECT contract_json, orders_json, prepared_json FROM strategies WHERE strategy_id=?",
                (strategy_id,),
            ).fetchone()
            contract = json.loads(row["contract_json"])
            orders = json.loads(row["orders_json"])
            contract["selectedLevels"].append(deepcopy(contract["selectedLevels"][-1]))
            orders.append(deepcopy(orders[-1]))
            prepared = None if row["prepared_json"] is None else json.loads(row["prepared_json"])
            if isinstance(prepared, dict) and isinstance(prepared.get("orders"), list):
                prepared["orders"].append(deepcopy(prepared["orders"][-1]))
            connection.execute(
                "UPDATE strategies SET contract_json=?, orders_json=?, prepared_json=? WHERE strategy_id=?",
                (
                    encode_json(contract) if append_contract else row["contract_json"],
                    encode_json(orders),
                    None if prepared is None else encode_json(prepared),
                    strategy_id,
                ),
            )

    def save_draft(
        self,
        contract: dict[str, Any] | None = None,
        *,
        replacement_source_id: str | None = None,
    ) -> tuple[str, dict[str, Any]]:
        source = self.one_sided_contract() if contract is None else contract
        status, preview = self.request("POST", "/v1/strategies/preview", source)
        self.assertEqual(status, 200, preview)
        draft_body = {**source, "previewHash": preview["previewHash"]}
        if replacement_source_id is not None:
            draft_body["replacementSourceId"] = replacement_source_id
        status, saved = self.request(
            "POST", "/v1/strategies", draft_body
        )
        self.assertEqual(status, 200, saved)
        return saved["id"], preview

    def apply_strategy(self) -> str:
        strategy_id, _ = self.save_draft()
        self.exchange.pos_mode = "long_short_mode"
        status, prepared = self.request("POST", f"/v1/strategies/{strategy_id}/prepare-apply", {})
        self.assertEqual(status, 200, prepared)
        status, applied = self.request(
            "POST", f"/v1/strategies/{strategy_id}/execute-apply",
            {"confirmationToken": prepared["confirmationToken"]},
        )
        self.assertEqual(status, 200, applied)
        self.assertEqual(applied["status"], "APPLIED")
        return strategy_id

    def _make_rejected_source(
        self,
        *,
        contract: dict[str, Any] | None = None,
        rejected_order_index: int = 0,
        rejected_order_indexes: set[int] | None = None,
        accepted_as_canceled: bool = False,
    ) -> tuple[str, dict[str, Any], dict[str, Any]]:
        source_id, _ = self.save_draft(contract)
        status, prepared = self.request(
            "POST", f"/v1/strategies/{source_id}/prepare-apply", {}
        )
        self.assertEqual(status, 200, prepared)
        ack: list[dict[str, Any]] = []
        rejected_indexes = {rejected_order_index} if rejected_order_indexes is None else rejected_order_indexes
        for index, row in enumerate(prepared["orders"]):
            if index in rejected_indexes:
                ack.append({"clOrdId": row["clientOrderId"], "sCode": "51008", "sMsg": "private rejection"})
            else:
                ack.append({"clOrdId": row["clientOrderId"], "sCode": "0", "ordId": f"accepted-{index}"})
                if accepted_as_canceled:
                    payload = self.service.strategy._okx_order(
                        {"instrumentId": INSTRUMENT}, row, "net_mode"
                    )
                    self.exchange.orders[row["clientOrderId"]] = {
                        **payload, "ordId": f"accepted-{index}", "state": "canceled",
                        "accFillSz": "0", "avgPx": "0",
                    }
        self.exchange.batch_ack = ack
        status, result = self.request(
            "POST", f"/v1/strategies/{source_id}/execute-apply",
            {"confirmationToken": prepared["confirmationToken"]},
        )
        self.assertEqual(status, 200, result)
        self.assertIn(result["status"], {"PARTIAL", "UNKNOWN"})
        self.exchange.batch_ack = None
        return source_id, result, prepared

    def _make_legacy_never_sent_source(self) -> str:
        source_id, _ = self.save_draft()
        with self.service.store.transaction() as connection:
            connection.execute(
                "UPDATE strategies SET status='COMPLETED', attempt_started=1, batch_attempted=0, "
                "order_placement_attempted=0 WHERE strategy_id=?",
                (source_id,),
            )
        return source_id

    def _make_canceled_terminal_strategy(self) -> tuple[str, dict[str, Any]]:
        strategy_id = self.apply_strategy()
        for row in self.exchange.orders.values():
            row["state"] = "canceled"
            row["accFillSz"] = "0"
            row["avgPx"] = "0"
        with self.service.store.transaction() as connection:
            connection.execute(
                "UPDATE strategy_sync_state SET last_success_at=?, last_error=NULL, next_scan_at=? "
                "WHERE strategy_id=?",
                (self.now - 60, self.now - 60, strategy_id),
            )
        status, result = self.request("GET", f"/v1/strategies/{strategy_id}/result")
        self.assertEqual(status, 200, result)
        self.assertTrue(result["orders"])
        self.assertTrue(all(row["status"] == "canceled" for row in result["orders"]), result)
        return strategy_id, result

    def test_red_strategy_routes_require_bearer_before_exchange_reads(self) -> None:
        status, result = self.request("GET", "/v1/strategies", authenticated=False)
        self.assertEqual(status, 401, result)
        self.assertEqual(result["error"], "authentication_required")
        self.assertEqual(self.exchange.calls, [])

    def test_red_owned_applied_strategy_quote_requires_authentication_and_is_backend_fed(self) -> None:
        strategy_id = self.apply_strategy()
        path = f"/v1/strategies/{strategy_id}/quote"
        self.exchange.calls.clear()
        self.exchange.last = "60000.0000000123"

        status, result = self.request("GET", path, authenticated=False)
        self.assertEqual(status, 401, result)
        self.assertEqual(result["error"], "authentication_required")
        self.assertEqual(self.exchange.calls, [])

        status, quote = self.request("GET", path)
        self.assertEqual(status, 200, quote)
        self.assertEqual(quote["instrumentId"], INSTRUMENT)
        self.assertEqual(quote["lastPrice"], "60000.0000000123")
        self.assertTrue(quote["observedAt"].endswith("Z"))
        self.assertEqual(set(quote), {"instrumentId", "lastPrice", "observedAt"})

    def test_quote_revalidates_account_before_serving_one_second_instrument_cache(self) -> None:
        strategy_id = self.apply_strategy()
        path = f"/v1/strategies/{strategy_id}/quote"
        self.exchange.calls.clear()

        status, first = self.request("GET", path)
        self.assertEqual(status, 200, first)
        self.assertEqual(first["lastPrice"], "60000")
        status, second = self.request("GET", path)
        self.assertEqual(status, 200, second)
        self.assertEqual(second, first)
        account_reads = [call for call in self.exchange.calls if call[1].split("?", 1)[0] == "/api/v5/account/config"]
        ticker_reads = [call for call in self.exchange.calls if call[1].split("?", 1)[0] == "/api/v5/market/ticker"]
        self.assertEqual(len(account_reads), 2)
        self.assertEqual(len(ticker_reads), 1)

        self.now += 1.1
        self.exchange.last = "61000"
        status, refreshed = self.request("GET", path)
        self.assertEqual(status, 200, refreshed)
        self.assertEqual(refreshed["lastPrice"], "61000")
        account_reads = [call for call in self.exchange.calls if call[1].split("?", 1)[0] == "/api/v5/account/config"]
        ticker_reads = [call for call in self.exchange.calls if call[1].split("?", 1)[0] == "/api/v5/market/ticker"]
        self.assertEqual(len(account_reads), 3)
        self.assertEqual(len(ticker_reads), 2)

        self.exchange.account_uid = "different-account"
        status, changed = self.request("GET", path)
        self.assertEqual(status, 409, changed)
        self.assertEqual(changed["error"], "account_changed")
        account_reads = [call for call in self.exchange.calls if call[1].split("?", 1)[0] == "/api/v5/account/config"]
        ticker_reads = [call for call in self.exchange.calls if call[1].split("?", 1)[0] == "/api/v5/market/ticker"]
        self.assertEqual(len(account_reads), 4)
        self.assertEqual(len(ticker_reads), 2)

    def test_concurrent_quote_reads_coalesce_to_one_public_ticker_request(self) -> None:
        strategy_id = self.apply_strategy()
        path = f"/v1/strategies/{strategy_id}/quote"
        self.exchange.calls.clear()
        self.exchange.quote_account_barrier = threading.Barrier(2)
        self.exchange.pause_ticker = True

        with ThreadPoolExecutor(max_workers=2) as executor:
            first = executor.submit(self.request, "GET", path)
            second = executor.submit(self.request, "GET", path)
            self.assertTrue(self.exchange.ticker_started.wait(timeout=3))
            self.exchange.ticker_release.set()
            results = [first.result(timeout=3), second.result(timeout=3)]

        self.exchange.quote_account_barrier = None
        self.assertEqual([status for status, _ in results], [200, 200])
        self.assertEqual(results[0][1], results[1][1])
        ticker_reads = [call for call in self.exchange.calls if call[1].split("?", 1)[0] == "/api/v5/market/ticker"]
        self.assertEqual(len(ticker_reads), 1)

    def test_quote_rejects_wrong_instrument_invalid_decimal_and_stale_or_future_timestamps(self) -> None:
        strategy_id = self.apply_strategy()
        path = f"/v1/strategies/{strategy_id}/quote"
        invalid_quotes = [
            (INSTRUMENT.replace("BTC", "ETH"), "60000", str(int(NOW * 1000)), 502),
            (INSTRUMENT, "0", str(int(NOW * 1000)), 502),
            (INSTRUMENT, "NaN", str(int(NOW * 1000)), 502),
            (INSTRUMENT, "60000", str(int((NOW - 16) * 1000)), 409),
            (INSTRUMENT, "60000", str(int((NOW + 1) * 1000)), 409),
            (INSTRUMENT, "60000", str(int(NOW * 1000) + 1) + ".5", 502),
            (INSTRUMENT, "60000.0000000001", str(int((NOW - 15) * 1000)), 200),
        ]
        for instrument, last, timestamp_ms, expected_status in invalid_quotes:
            with self.subTest(instrument=instrument, last=last, timestamp=timestamp_ms):
                self.exchange.ticker_instrument_id = instrument
                self.exchange.last = last
                self.exchange.ticker_timestamp_ms = timestamp_ms
                status, result = self.request("GET", path)
                self.assertEqual(status, expected_status, result)
                if expected_status == 200:
                    self.assertEqual(result["lastPrice"], "60000.0000000001")
                self.assertNotIn("test-key", json.dumps(result))
                self.assertNotIn("test-secret", json.dumps(result))

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
        valid_fee_data = deepcopy(self.exchange.fee_data)
        self.exchange.fee_data = []
        status, result = self.request("POST", "/v1/strategies/preview", self.one_sided_contract())
        self.assertEqual(status, 502, result)
        self.assertEqual(result["error"], "preview_inputs_unavailable")

        self.exchange.fee_data = valid_fee_data
        undersized = self.one_sided_contract()
        undersized["totalMargin"] = "1"
        undersized["leverage"] = {"long": 1}
        status, result = self.request("POST", "/v1/strategies/preview", undersized)
        self.assertEqual(status, 422, result)
        self.assertEqual(result["reason"], "order_below_minimum")
        self.assertEqual(self.exchange.trade_writes, [])

    def test_red_blank_or_missing_swap_base_and_quote_metadata_allow_preview(self) -> None:
        baseline = deepcopy(self.exchange.instrument_data)
        cases = [
            ("blank base and quote", {"baseCcy": "", "quoteCcy": ""}),
            ("missing base and quote", {"baseCcy": None, "quoteCcy": None}),
            ("blank base", {"baseCcy": ""}),
            ("missing base", {"baseCcy": None}),
            ("blank quote", {"quoteCcy": ""}),
            ("missing quote", {"quoteCcy": None}),
        ]
        for label, metadata in cases:
            with self.subTest(label=label):
                self.exchange.instrument_data = deepcopy(baseline)
                for key, value in metadata.items():
                    if value is None:
                        self.exchange.instrument_data[0].pop(key, None)
                    else:
                        self.exchange.instrument_data[0][key] = value
                status, result = self.request("POST", "/v1/strategies/preview", self.one_sided_contract())
                self.assertEqual(status, 200, result)
                self.assertTrue(result.get("previewHash"))
                self.assertEqual(self.exchange.trade_writes, [])

    def test_red_conflicting_or_non_linear_swap_metadata_blocks_preview(self) -> None:
        baseline = deepcopy(self.exchange.instrument_data)
        cases = [
            ("conflicting base", {"baseCcy": "ETH", "ctValCcy": "ETH"}),
            ("conflicting quote", {"quoteCcy": "USDC"}),
            ("inverse contract", {"ctType": "inverse"}),
            ("missing contract type", {"ctType": None}),
            ("conflicting contract value currency", {"ctValCcy": "USDT"}),
            ("missing contract value", {"ctVal": None}),
        ]
        for label, metadata in cases:
            with self.subTest(label=label):
                self.exchange.instrument_data = deepcopy(baseline)
                for key, value in metadata.items():
                    if value is None:
                        self.exchange.instrument_data[0].pop(key, None)
                    else:
                        self.exchange.instrument_data[0][key] = value
                status, result = self.request("POST", "/v1/strategies/preview", self.one_sided_contract())
                self.assertEqual(status, 502, result)
                self.assertEqual(result["error"], "preview_inputs_unavailable")
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

    def test_red_id_mode_preserves_equal_price_levels_and_groups_liquidation(self) -> None:
        self.exchange.tier_data = [
            {"instType": "SWAP", "tdMode": "isolated", "instFamily": "BTC-USDT", "tier": "1",
             "minSz": "0", "maxSz": "2", "mmr": "0.01", "imr": "0.1", "maxLever": "125"},
            {"instType": "SWAP", "tdMode": "isolated", "instFamily": "BTC-USDT", "tier": "2",
             "minSz": "2.1", "maxSz": "100000", "mmr": "0.02", "imr": "0.1", "maxLever": "125"},
        ]
        rows = [
            {"side": "long", "price": "59000", "levelId": "long-z"},
            {"side": "long", "price": "59000", "levelId": "long-a"},
        ]
        contract = self.id_mode_contract(
            rows, entry_ids={"long": "long-z"}, include_legacy_entries=True,
        )

        status, preview = self.request("POST", "/v1/strategies/preview", contract)
        self.assertEqual(status, 200, preview)
        self.assertEqual([row["levelId"] for row in preview["orders"]], ["long-a", "long-z"])
        self.assertEqual({row["role"] for row in preview["orders"] if row["levelId"] == "long-z"}, {"entry"})
        self.assertEqual({row["role"] for row in preview["orders"] if row["levelId"] == "long-a"}, {"dca"})

        unit = Decimal("0.001")
        contracts = Decimal("4")
        average = Decimal("59000")
        margin = Decimal("47.2")
        mmr = Decimal("0.02")
        fee = Decimal("0.0005")
        long_price = ((unit * contracts * average - margin) / (unit * contracts * (1 - mmr - fee))).quantize(
            Decimal("0.1"), rounding=ROUND_CEILING,
        )
        estimates = [row["liquidationEstimate"]["price"] for row in preview["orders"]]
        self.assertEqual(estimates, [format(long_price, "f"), format(long_price, "f")])
        for row in preview["orders"]:
            note = row["liquidationEstimateNote"].lower()
            self.assertIn("same-price orders", note)
            self.assertIn("fill order is not guaranteed", note)

        reordered = {**contract, "selectedLevels": list(reversed(rows))}
        status, reordered_preview = self.request("POST", "/v1/strategies/preview", reordered)
        self.assertEqual(status, 200, reordered_preview)
        self.assertEqual(reordered_preview["previewHash"], preview["previewHash"])

        sequence_contract = self.id_mode_contract(
            [
                {"side": "long", "price": "58000", "levelId": "long-low"},
                {"side": "long", "price": "59000", "levelId": "long-high"},
            ],
            entry_ids={"long": "long-high"},
        )
        status, sequence_preview = self.request("POST", "/v1/strategies/preview", sequence_contract)
        self.assertEqual(status, 200, sequence_preview)
        self.assertEqual([row["levelId"] for row in sequence_preview["orders"]], ["long-high", "long-low"])

    def test_red_id_mode_validates_ids_direction_entries_tick_and_order_limit(self) -> None:
        rows = [
            {"side": "long", "price": "59000", "levelId": "near"},
            {"side": "long", "price": "58000", "levelId": "far"},
        ]
        base = self.id_mode_contract(
            rows, entry_ids={"long": "near"}, include_legacy_entries=True,
        )
        invalid_contracts: list[tuple[str, dict[str, Any]]] = []

        missing_direction = deepcopy(base)
        missing_direction.pop("direction")
        invalid_contracts.append(("missing direction", missing_direction))

        wrong_direction = deepcopy(base)
        wrong_direction["direction"] = "both"
        invalid_contracts.append(("direction does not match sides", wrong_direction))

        mixed_ids = deepcopy(base)
        mixed_ids["selectedLevels"][1].pop("levelId")
        invalid_contracts.append(("ID mode is all or none", mixed_ids))

        duplicate_ids = deepcopy(base)
        duplicate_ids["selectedLevels"][1]["levelId"] = "near"
        invalid_contracts.append(("duplicate IDs", duplicate_ids))

        invalid_id = deepcopy(base)
        invalid_id["selectedLevels"][0]["levelId"] = "near:bad"
        invalid_contracts.append(("unsafe ID characters", invalid_id))

        long_id = deepcopy(base)
        long_id["selectedLevels"][0]["levelId"] = "a" * 129
        invalid_contracts.append(("ID exceeds bound", long_id))

        missing_entry = deepcopy(base)
        missing_entry["entryLevelIdBySide"] = {}
        invalid_contracts.append(("missing entry ID", missing_entry))

        foreign_entry = self.id_mode_contract(
            [
                {"side": "long", "price": "59000", "levelId": "near"},
                {"side": "short", "price": "61000", "levelId": "short-near"},
            ],
            direction="both", entry_ids={"long": "short-near", "short": "short-near"},
        )
        invalid_contracts.append(("entry ID belongs to another side", foreign_entry))

        inconsistent_legacy_entry = deepcopy(base)
        inconsistent_legacy_entry["entryBySide"]["long"] = "58000"
        invalid_contracts.append(("legacy entry price disagrees with selected ID", inconsistent_legacy_entry))

        off_tick = deepcopy(base)
        off_tick["selectedLevels"][0]["price"] = "59000.05"
        off_tick["entryBySide"]["long"] = "59000.05"
        invalid_contracts.append(("off tick price", off_tick))

        not_nearest = deepcopy(base)
        not_nearest["entryLevelIdBySide"]["long"] = "far"
        not_nearest["entryBySide"]["long"] = "58000"
        invalid_contracts.append(("entry ID is not nearest", not_nearest))

        for label, contract in invalid_contracts:
            with self.subTest(label=label):
                status, result = self.request("POST", "/v1/strategies/preview", contract)
                self.assertEqual(status, 422, result)
                self.assertEqual(self.exchange.trade_writes, [])

    def test_red_new_contract_admission_rejects_eleven_single_and_mixed_rows(self) -> None:
        oversized = (
            ("single side", self.multi_order_contract(11)),
            ("mixed six plus five", self.multi_order_contract(6, 5)),
        )
        for label, contract in oversized:
            for operation, path in (("preview", "/v1/strategies/preview"), ("save", "/v1/strategies")):
                with self.subTest(contract=label, operation=operation):
                    body = contract if operation == "preview" else {**contract, "previewHash": "unused"}
                    status, result = self.request("POST", path, body)
                    self.assertEqual(status, 422, result)
                    self.assertEqual(result["reason"], "invalid_order_count")
                    self.assertIn("ten", result["message"])
        self.assertEqual(self.exchange.calls, [])
        with self.service.store.connection() as connection:
            count = connection.execute("SELECT COUNT(*) FROM strategies").fetchone()[0]
        self.assertEqual(count, 0)

    def test_red_unstarted_persisted_oversize_records_reject_before_preflight_or_claim(self) -> None:
        draft_id, _ = self.save_draft(self.multi_order_contract(10))
        self._append_persisted_order(draft_id)
        position_reads = self.exchange.position_reads
        pending_reads = self.exchange.pending_reads

        status, draft_error = self.request("POST", f"/v1/strategies/{draft_id}/prepare-apply", {})
        self.assertEqual(status, 422, draft_error)
        self.assertEqual(draft_error["reason"], "invalid_order_count")
        with self.service.store.connection() as connection:
            draft_status = connection.execute(
                "SELECT status FROM strategies WHERE strategy_id=?", (draft_id,)
            ).fetchone()["status"]
        self.assertEqual(draft_status, "DRAFT")
        self.assertEqual(self.exchange.position_reads, position_reads)
        self.assertEqual(self.exchange.pending_reads, pending_reads)
        self.assertEqual(self.exchange.trade_writes, [])

        prepared_id, _ = self.save_draft(self.multi_order_contract(10))
        status, prepared = self.request("POST", f"/v1/strategies/{prepared_id}/prepare-apply", {})
        self.assertEqual(status, 200, prepared)
        with self.service.store.connection() as connection:
            before = connection.execute(
                "SELECT confirmation_hash, prepared_json FROM strategies WHERE strategy_id=?",
                (prepared_id,),
            ).fetchone()
        prepared_json = json.loads(before["prepared_json"])
        prepared_json["orders"].append(deepcopy(prepared_json["orders"][-1]))
        with self.service.store.transaction() as connection:
            connection.execute(
                "UPDATE strategies SET prepared_json=? WHERE strategy_id=?",
                (encode_json(prepared_json), prepared_id),
            )
        position_reads = self.exchange.position_reads
        pending_reads = self.exchange.pending_reads
        status, prepared_error = self.request(
            "POST", f"/v1/strategies/{prepared_id}/execute-apply",
            {"confirmationToken": prepared["confirmationToken"]},
        )
        self.assertEqual(status, 422, prepared_error)
        self.assertEqual(prepared_error["reason"], "invalid_order_count")
        self.assertEqual(self.exchange.position_reads, position_reads)
        self.assertEqual(self.exchange.pending_reads, pending_reads)
        self.assertEqual(self.exchange.trade_writes, [])
        with self.service.store.connection() as connection:
            after = connection.execute(
                "SELECT status, attempt_started, confirmation_hash FROM strategies WHERE strategy_id=?",
                (prepared_id,),
            ).fetchone()
            reservations = connection.execute(
                "SELECT COUNT(*) FROM strategy_reservations WHERE strategy_id=?", (prepared_id,)
            ).fetchone()[0]
        self.assertEqual(after["status"], "PREPARED")
        self.assertEqual(after["attempt_started"], 0)
        self.assertEqual(after["confirmation_hash"], before["confirmation_hash"])
        self.assertEqual(reservations, 0)

    def test_red_batch_and_sequential_claims_recheck_persisted_order_count(self) -> None:
        for mode in ("batch", "sequential"):
            with self.subTest(mode=mode):
                status, settings = self.request(
                    "POST", "/v1/strategies/settings", {"limitOrderSubmissionMode": mode}
                )
                self.assertEqual(status, 200, settings)
                strategy_id, _ = self.save_draft(self.multi_order_contract(10))
                status, prepared = self.request("POST", f"/v1/strategies/{strategy_id}/prepare-apply", {})
                self.assertEqual(status, 200, prepared)
                strategy, _, _ = self.service.strategy._current_strategy(strategy_id)
                with self.service.store.transaction() as connection:
                    row = connection.execute(
                        "SELECT prepared_json FROM strategies WHERE strategy_id=?", (strategy_id,)
                    ).fetchone()
                    persisted_prepared = json.loads(row["prepared_json"])
                    persisted_prepared["orders"].append(deepcopy(persisted_prepared["orders"][-1]))
                    connection.execute(
                        "UPDATE strategies SET prepared_json=? WHERE strategy_id=?",
                        (encode_json(persisted_prepared), strategy_id),
                    )

                with self.assertRaises(APIError) as raised:
                    if mode == "sequential":
                        self.service.strategy._claim_queue(strategy_id, strategy, prepared["confirmationToken"])
                    else:
                        self.service.strategy._claim_execution(strategy_id, strategy, prepared["confirmationToken"])
                self.assertEqual(raised.exception.details["reason"], "invalid_order_count")
                with self.service.store.connection() as connection:
                    current = connection.execute(
                        "SELECT status, attempt_started, confirmation_hash FROM strategies WHERE strategy_id=?",
                        (strategy_id,),
                    ).fetchone()
                    reservations = connection.execute(
                        "SELECT COUNT(*) FROM strategy_reservations WHERE strategy_id=?", (strategy_id,)
                    ).fetchone()[0]
                self.assertEqual(current["status"], "PREPARED")
                self.assertEqual(current["attempt_started"], 0)
                self.assertIsNotNone(current["confirmation_hash"])
                self.assertEqual(reservations, 0)
                self.assertEqual(self.exchange.trade_writes, [])

    def test_red_attempted_oversize_strategy_execute_remains_noop_and_keeps_markers(self) -> None:
        strategy_id, _ = self.save_draft(self.multi_order_contract(10))
        status, prepared = self.request("POST", f"/v1/strategies/{strategy_id}/prepare-apply", {})
        self.assertEqual(status, 200, prepared)
        status, applied = self.request(
            "POST", f"/v1/strategies/{strategy_id}/execute-apply",
            {"confirmationToken": prepared["confirmationToken"]},
        )
        self.assertEqual(status, 200, applied)
        self.assertEqual(applied["status"], "APPLIED")
        self._append_persisted_order(strategy_id)
        with self.service.store.connection() as connection:
            before = connection.execute(
                "SELECT status, attempt_started, order_placement_attempted, batch_attempted "
                ", contract_json FROM strategies WHERE strategy_id=?", (strategy_id,),
            ).fetchone()
        self.assertEqual(len(json.loads(before["contract_json"])["selectedLevels"]), 11)
        self.assertTrue(before["attempt_started"])
        writes_before = list(self.exchange.trade_writes)

        status, result = self.request(
            "POST", f"/v1/strategies/{strategy_id}/execute-apply",
            {"confirmationToken": "already-consumed"},
        )

        self.assertEqual(status, 200, result)
        self.assertEqual(result["status"], before["status"])
        self.assertEqual(self.exchange.trade_writes, writes_before)
        with self.service.store.connection() as connection:
            after = connection.execute(
                "SELECT status, attempt_started, order_placement_attempted, batch_attempted "
                "FROM strategies WHERE strategy_id=?", (strategy_id,),
            ).fetchone()
        self.assertEqual(dict(after), {
            "status": before["status"],
            "attempt_started": before["attempt_started"],
            "order_placement_attempted": before["order_placement_attempted"],
            "batch_attempted": before["batch_attempted"],
        })

    def test_green_ten_order_contracts_apply_in_both_submission_modes(self) -> None:
        cases = (
            ("batch", "single side", "BTC-USDT-SWAP", self.multi_order_contract(10)),
            ("batch", "mixed five plus five", "ETH-USDT-SWAP", self.multi_order_contract(5, 5, "ETH-USDT-SWAP")),
            ("sequential", "single side", "SOL-USDT-SWAP", self.multi_order_contract(10, instrument_id="SOL-USDT-SWAP")),
            ("sequential", "mixed five plus five", "ADA-USDT-SWAP", self.multi_order_contract(5, 5, "ADA-USDT-SWAP")),
        )
        for mode, label, instrument_id, contract in cases:
            if instrument_id != INSTRUMENT:
                self._add_fake_instrument(instrument_id)
            status, settings = self.request(
                "POST", "/v1/strategies/settings", {"limitOrderSubmissionMode": mode}
            )
            self.assertEqual(status, 200, settings)
            with self.subTest(mode=mode, contract=label):
                self.exchange.pos_mode = "long_short_mode" if "mixed" in label else "net_mode"
                batch_count = len(self.exchange.batch_writes)
                order_count = self.exchange.single_order_attempts
                strategy_id, _ = self.save_draft(contract)
                status, prepared = self.request(
                    "POST", f"/v1/strategies/{strategy_id}/prepare-apply", {}
                )
                self.assertEqual(status, 200, prepared)
                self.assertEqual(len(prepared["orders"]), 10)
                status, applied = self.request(
                    "POST", f"/v1/strategies/{strategy_id}/execute-apply",
                    {"confirmationToken": prepared["confirmationToken"]},
                )
                self.assertEqual(status, 200, applied)
                if mode == "batch":
                    self.assertEqual(applied["status"], "APPLIED")
                    self.assertEqual(len(self.exchange.batch_writes), batch_count + 1)
                    self.assertEqual(len(self.exchange.batch_writes[-1][2]), 10)
                else:
                    self.assertEqual(applied["status"], "APPLYING")
                    self.assertEqual(applied["queueProgress"]["totalCount"], 10)
                    self.assertEqual(self.exchange.single_order_attempts, order_count)
                    self.assertTrue(self._worker().run_once())
                    status, result = self.request("GET", f"/v1/strategies/{strategy_id}/result")
                    self.assertEqual(status, 200, result)
                    self.assertEqual(result["status"], "APPLIED")
                    self.assertEqual(self.exchange.single_order_attempts, order_count + 10)

    def test_red_id_mode_persists_both_sides_through_prepare_batch_and_reconciliation(self) -> None:
        self.exchange.tier_data = [
            {"instType": "SWAP", "tdMode": "isolated", "instFamily": "BTC-USDT", "tier": "1",
             "minSz": "0", "maxSz": "2", "mmr": "0.01", "imr": "0.1", "maxLever": "125"},
            {"instType": "SWAP", "tdMode": "isolated", "instFamily": "BTC-USDT", "tier": "2",
             "minSz": "2.1", "maxSz": "100000", "mmr": "0.02", "imr": "0.1", "maxLever": "125"},
        ]
        rows = [
            {"side": "short", "price": "61000", "levelId": "short-z"},
            {"side": "long", "price": "59000", "levelId": "long-z"},
            {"side": "short", "price": "61000", "levelId": "short-a"},
            {"side": "long", "price": "59000", "levelId": "long-a"},
        ]
        contract = self.id_mode_contract(
            rows, direction="both", entry_ids={"long": "long-z", "short": "short-a"},
        )
        status, preview = self.request("POST", "/v1/strategies/preview", contract)
        self.assertEqual(status, 200, preview)
        self.assertEqual([row["levelId"] for row in preview["orders"]], [
            "long-a", "long-z", "short-a", "short-z",
        ])
        self.assertEqual([row["side"] for row in preview["orders"]], ["long", "long", "short", "short"])
        roles = {row["levelId"]: row["role"] for row in preview["orders"]}
        self.assertEqual(roles, {
            "long-a": "dca", "long-z": "entry", "short-a": "entry", "short-z": "dca",
        })
        unit = Decimal("0.001")
        contracts = Decimal("4")
        mmr = Decimal("0.02")
        fee = Decimal("0.0005")
        long_margin = Decimal("23.6") * 2
        long_expected = ((unit * contracts * Decimal("59000") - long_margin) /
                         (unit * contracts * (1 - mmr - fee))).quantize(Decimal("0.1"), rounding=ROUND_CEILING)
        short_margin = Decimal("24.4") * 2
        short_expected = ((unit * contracts * Decimal("61000") + short_margin) /
                          (unit * contracts * (1 + mmr + fee))).quantize(Decimal("0.1"), rounding=ROUND_FLOOR)
        for side, expected in (("long", long_expected), ("short", short_expected)):
            side_orders = [row for row in preview["orders"] if row["side"] == side]
            self.assertEqual(
                [row["liquidationEstimate"]["price"] for row in side_orders],
                [format(expected, "f"), format(expected, "f")],
            )
            self.assertTrue(all("fill order is not guaranteed" in row["liquidationEstimateNote"] for row in side_orders))

        reordered = {**contract, "selectedLevels": list(reversed(rows))}
        status, reordered_preview = self.request("POST", "/v1/strategies/preview", reordered)
        self.assertEqual(status, 200, reordered_preview)
        self.assertEqual(reordered_preview["previewHash"], preview["previewHash"])

        strategy_id, saved_preview = self.save_draft(contract)
        status, draft = self.request("GET", f"/v1/strategies/{strategy_id}/result")
        self.assertEqual(status, 200, draft)
        draft_by_id = {row["levelId"]: row["clientOrderId"] for row in draft["orders"]}
        self.assertEqual(set(draft_by_id), {"long-a", "long-z", "short-a", "short-z"})

        status, net_mode = self.request("POST", f"/v1/strategies/{strategy_id}/prepare-apply", {})
        self.assertEqual(status, 409, net_mode)
        self.assertEqual(net_mode["error"], "account_mode_unsupported")
        self.assertEqual(self.exchange.trade_writes, [])
        self.exchange.pos_mode = "long_short_mode"
        status, prepared = self.request("POST", f"/v1/strategies/{strategy_id}/prepare-apply", {})
        self.assertEqual(status, 200, prepared)
        prepared_by_id = {row["levelId"]: row["clientOrderId"] for row in prepared["orders"]}
        self.assertEqual(prepared_by_id, draft_by_id)
        self.assertEqual(saved_preview["previewHash"], preview["previewHash"])

        status, applied = self.request(
            "POST", f"/v1/strategies/{strategy_id}/execute-apply",
            {"confirmationToken": prepared["confirmationToken"]},
        )
        self.assertEqual(status, 200, applied)
        self.assertEqual(applied["status"], "APPLIED")
        self.assertEqual({row["levelId"]: row["clientOrderId"] for row in applied["orders"]}, draft_by_id)
        batch = self.exchange.batch_writes[0][2]
        self.assertEqual(len(batch), 4)
        self.assertEqual([row["posSide"] for row in batch], ["long", "long", "short", "short"])
        self.assertEqual({row["clOrdId"] for row in batch}, set(draft_by_id.values()))
        self.assertEqual(len({row["clOrdId"] for row in batch}), 4)
        prepared_by_client = {row["clientOrderId"]: row for row in prepared["orders"]}
        self.assertEqual(
            [
                (row["ordType"], row["side"], row["px"], row["sz"])
                for row in batch
            ],
            [
                (
                    "limit",
                    "buy" if prepared_by_client[row["clOrdId"]]["side"] == "long" else "sell",
                    prepared_by_client[row["clOrdId"]]["limitPrice"],
                    prepared_by_client[row["clOrdId"]]["contracts"],
                )
                for row in batch
            ],
        )

        status, reconciled = self.request("GET", f"/v1/strategies/{strategy_id}/result")
        self.assertEqual(status, 200, reconciled)
        self.assertEqual(reconciled["status"], "APPLIED")
        self.assertEqual({row["levelId"]: row["clientOrderId"] for row in reconciled["orders"]}, draft_by_id)
        self.assertEqual([row["status"] for row in reconciled["orders"]], ["live"] * 4)

    def test_green_legacy_preview_hash_and_idless_orders_remain_unchanged(self) -> None:
        status, preview = self.request("POST", "/v1/strategies/preview", self.one_sided_contract())
        self.assertEqual(status, 200, preview)
        self.assertEqual(preview["previewHash"], "1daa30a7fbef88e95ac266a003bdcd5c9321bfc244ee8f71273253ee9f1072c8")
        self.assertTrue(all("levelId" not in row for row in preview["orders"]))

        strategy_id, _ = self.save_draft()
        status, result = self.request("GET", f"/v1/strategies/{strategy_id}/result")
        self.assertEqual(status, 200, result)
        self.assertTrue(all("levelId" not in row for row in result["orders"]))

    def test_green_order_scan_metadata_is_fresh_and_recent_get_skips_duplicate_scan(self) -> None:
        strategy_id, _ = self.save_draft()
        status, prepared = self.request("POST", f"/v1/strategies/{strategy_id}/prepare-apply", {})
        self.assertEqual(status, 200, prepared)
        status, applied = self.request(
            "POST", f"/v1/strategies/{strategy_id}/execute-apply",
            {"confirmationToken": prepared["confirmationToken"]},
        )
        self.assertEqual(status, 200, applied)
        self.assertEqual(applied["orderSyncState"], "fresh")
        self.assertEqual(applied["lastOrderScanAt"], "2027-01-02T00:00:00Z")
        reads_after_apply = self.exchange.order_detail_reads

        status, result = self.request("GET", f"/v1/strategies/{strategy_id}/result")
        self.assertEqual(status, 200, result)
        self.assertEqual(result["orderSyncState"], "fresh")
        self.assertEqual(result["lastOrderScanAt"], applied["lastOrderScanAt"])
        self.assertEqual(self.exchange.order_detail_reads, reads_after_apply)

        status, listing = self.request("GET", "/v1/strategies")
        self.assertEqual(status, 200, listing)
        listed = next(row for row in listing["strategies"] if row["id"] == strategy_id)
        self.assertEqual(listed["orderSyncState"], "fresh")
        self.assertEqual(listed["lastOrderScanAt"], applied["lastOrderScanAt"])

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

    def test_green_rejected_batch_ack_is_deletable_but_never_resubmitted(self) -> None:
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
        self.assertFalse(duplicate["canDelete"])
        self.assertFalse(duplicate["canReplace"])
        status, terminal = self.request("GET", f"/v1/strategies/{strategy_id}/result")
        self.assertEqual(status, 200, terminal)
        self.assertTrue(terminal["canDelete"])
        status, deleted = self.request("POST", f"/v1/strategies/{strategy_id}/delete", {})
        self.assertEqual(status, 200, deleted)
        self.assertEqual(deleted["status"], "DELETED")
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
                self.now += 5
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
        self.now += 5
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

    def test_red_missing_fee_identity_fails_closed(self) -> None:
        original = deepcopy(self.exchange.fee_data)
        self.exchange.fee_data[0].pop("instType")
        status, result = self.request("POST", "/v1/strategies/preview", self.one_sided_contract())
        self.assertEqual(status, 502, result)
        self.exchange.fee_data = original

    def test_green_documented_fee_group_selects_instrument_group_without_family_echo(self) -> None:
        self.exchange.fee_data = [{
            "instType": "SWAP",
            "feeGroup": [
                {"groupId": "1", "maker": "-0.0001", "taker": "-0.001"},
                {"groupId": "2", "maker": "-0.0002", "taker": "-0.0005"},
            ],
        }]
        status, preview = self.request("POST", "/v1/strategies/preview", self.one_sided_contract())
        self.assertEqual(status, 200, preview)
        expected_notional = Decimal("5") * Decimal("59000") * Decimal("0.001")
        expected_taker_cost = expected_notional * Decimal("0.0005")
        self.assertEqual(Decimal(preview["estimatedOpeningFees"]), expected_taker_cost)
        self.assertEqual(Decimal(preview["orders"][0]["openingFeeEstimate"]), expected_taker_cost)
        self.assertEqual(preview["feesOutsideMargin"], True)
        self.assertEqual(self.exchange.trade_writes, [])

    def test_green_fee_group_rejects_ambiguous_or_malformed_data_without_writes(self) -> None:
        baseline_fees = deepcopy(self.exchange.fee_data)
        baseline_instruments = deepcopy(self.exchange.instrument_data)
        cases = [
            ("missing instrument group", lambda: self.exchange.instrument_data[0].pop("groupId")),
            ("blank instrument group", lambda: self.exchange.instrument_data[0].update(groupId=" ")),
            ("wrong fee group", lambda: self.exchange.fee_data[0].update(feeGroup=[{
                "groupId": "3", "maker": "-0.0002", "taker": "-0.0005",
            }])),
            ("duplicate matching group", lambda: self.exchange.fee_data[0]["feeGroup"].append(
                deepcopy(self.exchange.fee_data[0]["feeGroup"][1])
            )),
            ("malformed unrelated group", lambda: self.exchange.fee_data[0]["feeGroup"].__setitem__(0, {
                "groupId": "", "maker": "-0.0001", "taker": "-0.001",
            })),
            ("conflicting family", lambda: self.exchange.fee_data[0].update(instFamily="ETH-USDT")),
            ("missing signed taker", lambda: self.exchange.fee_data[0]["feeGroup"][1].pop("taker")),
            ("nonfinite signed maker", lambda: self.exchange.fee_data[0]["feeGroup"][1].update(maker="NaN")),
            ("out of range signed taker", lambda: self.exchange.fee_data[0]["feeGroup"][1].update(taker="-1")),
            ("numeric signed taker", lambda: self.exchange.fee_data[0]["feeGroup"][1].update(taker=0.0005)),
            ("legacy top-level rates", lambda: self.exchange.fee_data.__setitem__(0, {
                "instType": "SWAP", "instFamily": "BTC-USDT",
                "maker": "-0.0002", "taker": "-0.0005",
            })),
            ("multiple fee rows", lambda: self.exchange.fee_data.append(deepcopy(self.exchange.fee_data[0]))),
        ]
        for label, corrupt in cases:
            with self.subTest(label=label):
                self.exchange.fee_data = deepcopy(baseline_fees)
                self.exchange.instrument_data = deepcopy(baseline_instruments)
                corrupt()
                status, result = self.request("POST", "/v1/strategies/preview", self.one_sided_contract())
                self.assertEqual(status, 502, result)
                self.assertEqual(result["error"], "preview_inputs_unavailable")
                self.assertEqual(self.exchange.trade_writes, [])

    def test_green_positive_fee_rebate_has_zero_estimated_cost(self) -> None:
        self.exchange.fee_data = [{
            "instType": "SWAP",
            "feeGroup": [
                {"groupId": "2", "maker": "0.0002", "taker": "0.0005"},
            ],
        }]
        status, preview = self.request("POST", "/v1/strategies/preview", self.one_sided_contract())
        self.assertEqual(status, 200, preview)
        self.assertEqual(preview["estimatedOpeningFees"], "0")
        self.assertEqual(preview["orders"][0]["openingFeeEstimate"], "0")
        self.assertEqual(preview["plannedMargin"], "59")
        self.assertEqual(preview["feesOutsideMargin"], True)
        self.assertEqual(self.exchange.trade_writes, [])

    def test_green_omitted_tier_request_metadata_is_accepted_but_conflicts_fail_closed(self) -> None:
        baseline = deepcopy(self.exchange.tier_data)
        optional_metadata_cases = [
            ("both omitted", {"instType": ..., "tdMode": ...}),
            ("null", {"instType": None, "tdMode": None}),
            ("blank", {"instType": "", "tdMode": ""}),
        ]
        for label, values in optional_metadata_cases:
            with self.subTest(label=label):
                self.exchange.tier_data = deepcopy(baseline)
                row = self.exchange.tier_data[0]
                for field, value in values.items():
                    if value is ...:
                        row.pop(field)
                    else:
                        row[field] = value
                status, result = self.request("POST", "/v1/strategies/preview", self.one_sided_contract())
                self.assertEqual(status, 200, result)
                self.assertEqual(self.exchange.trade_writes, [])

        for field, value in (("instType", "SPOT"), ("tdMode", "cross"), ("instType", 1), ("tdMode", [])):
            with self.subTest(field=field, value=value):
                self.exchange.tier_data = deepcopy(baseline)
                self.exchange.tier_data[0][field] = value
                status, result = self.request("POST", "/v1/strategies/preview", self.one_sided_contract())
                self.assertEqual(status, 502, result)
                self.assertEqual(result["error"], "preview_inputs_unavailable")
                self.assertEqual(self.exchange.trade_writes, [])

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
        self.now += 5
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

    def test_red_legacy_never_sent_result_is_projected_as_failure_and_deletable(self) -> None:
        strategy_id, _ = self.save_draft()
        leverage_results = [{"side": "long", "status": "rejected", "errorCode": "51000"}]
        with self.service.store.transaction() as connection:
            connection.execute(
                "UPDATE strategies SET status='COMPLETED', attempt_started=1, failure_reason=NULL, "
                "leverage_results_json=? WHERE strategy_id=?",
                (encode_json(leverage_results), strategy_id),
            )

        status, result = self.request("GET", f"/v1/strategies/{strategy_id}/result")
        self.assertEqual(status, 200, result)
        self.assertEqual(result["status"], "PARTIAL")
        self.assertEqual(result["failureReason"], "leverage_rejected")
        self.assertFalse(result["batchAttempted"])
        self.assertTrue(result["canDelete"])
        self.assertTrue(result["canReplace"])
        self.assertFalse(result["replacementCleanupConflict"])
        with self.service.store.connection() as connection:
            persisted = connection.execute(
                "SELECT status, failure_reason FROM strategies WHERE strategy_id=?", (strategy_id,)
            ).fetchone()
        self.assertEqual(tuple(persisted), ("COMPLETED", None))

    def test_green_guarded_delete_rechecks_eligibility_and_removes_dependent_rows(self) -> None:
        strategy_id, _ = self.save_draft()
        with self.service.store.transaction() as connection:
            row = connection.execute(
                "SELECT account_fingerprint FROM strategies WHERE strategy_id=?", (strategy_id,)
            ).fetchone()
            connection.execute(
                "UPDATE strategies SET status='PARTIAL', attempt_started=1, failure_reason='leverage_rejected' "
                "WHERE strategy_id=?",
                (strategy_id,),
            )
            connection.execute(
                "INSERT INTO strategy_reservations(account_fingerprint, instrument_id, strategy_id, created_at) "
                "VALUES (?, ?, ?, ?)",
                (row["account_fingerprint"], INSTRUMENT, strategy_id, self.now),
            )
            connection.execute(
                "INSERT INTO strategy_sync_state(strategy_id, next_scan_at) VALUES (?, ?)",
                (strategy_id, self.now + 30),
            )

        status, deleted = self.request("POST", f"/v1/strategies/{strategy_id}/delete", {})
        self.assertEqual(status, 200, deleted)
        with self.service.store.connection() as connection:
            self.assertIsNone(connection.execute(
                "SELECT 1 FROM strategies WHERE strategy_id=?", (strategy_id,)
            ).fetchone())
            self.assertIsNone(connection.execute(
                "SELECT 1 FROM strategy_reservations WHERE strategy_id=?", (strategy_id,)
            ).fetchone())
            self.assertIsNone(connection.execute(
                "SELECT 1 FROM strategy_sync_state WHERE strategy_id=?", (strategy_id,)
            ).fetchone())

        applying_id, _ = self.save_draft()
        with self.service.store.transaction() as connection:
            connection.execute(
                "UPDATE strategies SET status='APPLYING', attempt_started=1, execution_id='active-run', "
                "execution_lease_until=? WHERE strategy_id=?",
                (self.now + 30, applying_id),
            )
        status, listing = self.request("GET", "/v1/strategies")
        self.assertEqual(status, 200, listing)
        applying = next(row for row in listing["strategies"] if row["id"] == applying_id)
        self.assertFalse(applying["canDelete"])
        status, conflict = self.request("POST", f"/v1/strategies/{applying_id}/delete", {})
        self.assertEqual(status, 409, conflict)

    def test_red_terminal_delete_rechecks_cached_orders_and_rejects_live_or_unknown_state(self) -> None:
        strategy_id, result = self._make_canceled_terminal_strategy()
        client_id = result["orders"][0]["clientOrderId"]
        reads_before = self.exchange.order_detail_reads
        self.exchange.calls.clear()

        original = deepcopy(self.exchange.orders[client_id])
        bad_details = (
            {"state": "live"},
            {"state": "unknown"},
            {"instId": "ETH-USDT-SWAP"},
            {"clOrdId": "different-client-id"},
            {"ordId": "different-exchange-id"},
            {"sz": "6"},
            {"side": "sell"},
            {"accFillSz": "6"},
        )
        for changes in bad_details:
            self.exchange.orders[client_id] = {**original, **changes}
            status, rejected = self.request("POST", f"/v1/strategies/{strategy_id}/delete", {})
            self.assertEqual(status, 409, rejected)
            self.assertEqual(rejected["error"], "strategy_immutable")

        self.assertEqual(self.exchange.order_detail_reads - reads_before, len(bad_details))
        self.assertEqual(self.exchange.trade_writes, [])
        with self.service.store.connection() as connection:
            self.assertIsNotNone(connection.execute(
                "SELECT 1 FROM strategies WHERE strategy_id=?", (strategy_id,)
            ).fetchone())

    def test_red_terminal_delete_rejects_malformed_or_incomplete_local_order_identity(self) -> None:
        strategy_id, result = self._make_canceled_terminal_strategy()
        saved = result["orders"][0]
        saved.pop("exchangeOrderId")
        with self.service.store.transaction() as connection:
            connection.execute(
                "UPDATE strategies SET results_json=?, updated_at=updated_at+1 WHERE strategy_id=?",
                (encode_json(result["orders"]), strategy_id),
            )
        reads_before = self.exchange.order_detail_reads
        self.exchange.calls.clear()

        status, rejected = self.request("POST", f"/v1/strategies/{strategy_id}/delete", {})

        self.assertEqual(status, 409, rejected)
        self.assertEqual(rejected["error"], "strategy_immutable")
        self.assertEqual(self.exchange.order_detail_reads, reads_before)
        self.assertEqual(self.exchange.trade_writes, [])
        with self.service.store.connection() as connection:
            self.assertIsNotNone(connection.execute(
                "SELECT 1 FROM strategies WHERE strategy_id=?", (strategy_id,)
            ).fetchone())

    def test_red_terminal_delete_rejects_position_presence_and_uncertain_size(self) -> None:
        strategy_id, _ = self._make_canceled_terminal_strategy()
        self.exchange.calls.clear()

        for position in (
            {"instId": INSTRUMENT, "pos": "1", "posSide": "net"},
            {"instId": INSTRUMENT, "pos": "invalid", "posSide": "long"},
        ):
            self.exchange.positions = [position]
            status, rejected = self.request("POST", f"/v1/strategies/{strategy_id}/delete", {})
            self.assertEqual(status, 409, rejected)
            self.assertEqual(rejected["error"], "strategy_immutable")

        self.assertEqual(self.exchange.trade_writes, [])
        with self.service.store.connection() as connection:
            self.assertIsNotNone(connection.execute(
                "SELECT 1 FROM strategies WHERE strategy_id=?", (strategy_id,)
            ).fetchone())

    def test_red_terminal_delete_fails_closed_on_position_read_error(self) -> None:
        strategy_id, _ = self._make_canceled_terminal_strategy()
        self.exchange.fail_position_reads = True
        self.exchange.calls.clear()

        status, rejected = self.request("POST", f"/v1/strategies/{strategy_id}/delete", {})

        self.assertEqual(status, 502, rejected)
        self.assertEqual(rejected["error"], "exchange_unavailable")
        self.assertEqual(self.exchange.trade_writes, [])
        with self.service.store.connection() as connection:
            self.assertIsNotNone(connection.execute(
                "SELECT 1 FROM strategies WHERE strategy_id=?", (strategy_id,)
            ).fetchone())

    def test_red_terminal_delete_rejects_account_change_during_fresh_reads(self) -> None:
        strategy_id, _ = self._make_canceled_terminal_strategy()
        self.exchange.after_order_detail_read = lambda _client_id, _details: setattr(
            self.exchange, "account_uid", "987654321"
        )
        self.exchange.calls.clear()

        status, rejected = self.request("POST", f"/v1/strategies/{strategy_id}/delete", {})

        self.assertEqual(status, 409, rejected)
        self.assertEqual(rejected["error"], "account_changed")
        self.assertEqual(self.exchange.trade_writes, [])
        with self.service.store.connection() as connection:
            self.assertIsNotNone(connection.execute(
                "SELECT 1 FROM strategies WHERE strategy_id=?", (strategy_id,)
            ).fetchone())

    def test_red_terminal_delete_rejects_concurrent_strategy_revision_change(self) -> None:
        strategy_id, _ = self._make_canceled_terminal_strategy()

        def change_revision(_client_id: str, _details: dict[str, Any] | None) -> None:
            self.exchange.after_order_detail_read = None
            with self.service.store.transaction() as connection:
                connection.execute(
                    "UPDATE strategies SET updated_at=updated_at+1 WHERE strategy_id=?",
                    (strategy_id,),
                )

        self.exchange.after_order_detail_read = change_revision
        self.exchange.calls.clear()

        status, rejected = self.request("POST", f"/v1/strategies/{strategy_id}/delete", {})

        self.assertEqual(status, 409, rejected)
        self.assertEqual(rejected["error"], "strategy_immutable")
        self.assertEqual(self.exchange.trade_writes, [])
        with self.service.store.connection() as connection:
            self.assertIsNotNone(connection.execute(
                "SELECT 1 FROM strategies WHERE strategy_id=?", (strategy_id,)
            ).fetchone())

    def test_red_terminal_delete_rejects_corrupt_queue_or_active_lease_before_reads(self) -> None:
        strategy_id, _ = self._make_canceled_terminal_strategy()
        with self.service.store.transaction() as connection:
            connection.execute(
                "UPDATE strategies SET submission_mode='sequential', queue_json='not-json', "
                "updated_at=updated_at+1 WHERE strategy_id=?",
                (strategy_id,),
            )
        reads_before = self.exchange.order_detail_reads
        self.exchange.calls.clear()

        status, rejected = self.request("POST", f"/v1/strategies/{strategy_id}/delete", {})

        self.assertEqual(status, 409, rejected)
        self.assertEqual(self.exchange.order_detail_reads, reads_before)
        self.assertEqual(self.exchange.trade_writes, [])
        with self.service.store.transaction() as connection:
            connection.execute(
                "UPDATE strategies SET submission_mode='batch', queue_json=NULL, execution_id='active-run', "
                "execution_lease_until=?, updated_at=updated_at+1 WHERE strategy_id=?",
                (self.now + 30, strategy_id),
            )
        status, rejected = self.request("POST", f"/v1/strategies/{strategy_id}/delete", {})
        self.assertEqual(status, 409, rejected)
        self.assertEqual(self.exchange.order_detail_reads, reads_before)
        self.assertEqual(self.exchange.trade_writes, [])

    def test_red_t73_terminal_delete_rejects_malformed_raw_positions_for_hint_and_delete(self) -> None:
        valid_position = {"instId": INSTRUMENT, "pos": "0", "posSide": "net"}
        invalid_responses = (
            ("missing_data", {"code": "0"}),
            ("null_data", {"code": "0", "data": None}),
            ("scalar_data", {"code": "0", "data": "invalid"}),
            ("nonobject_response", []),
            ("nonobject_row", {"code": "0", "data": [None]}),
            ("mixed_rows", {"code": "0", "data": [valid_position, None]}),
        )
        for name, response in invalid_responses:
            with self.subTest(response=name):
                self.exchange.position_response_override = False
                strategy_id, _ = self._make_canceled_terminal_strategy()
                self.exchange.position_response_override = True
                self.exchange.position_response = response

                status, result = self.request("GET", f"/v1/strategies/{strategy_id}/result")

                self.assertEqual(status, 200, result)
                self.assertFalse(result["canDelete"], result)
                self.assertEqual(result["positionStatus"], "unavailable", result)
                self.exchange.calls.clear()

                status, rejected = self.request("POST", f"/v1/strategies/{strategy_id}/delete", {})

                expected_status = 409 if name in {"nonobject_row", "mixed_rows"} else 502
                expected_error = "strategy_immutable" if expected_status == 409 else "exchange_unavailable"
                self.assertEqual(status, expected_status, rejected)
                self.assertEqual(rejected["error"], expected_error)
                self.assertEqual(self.exchange.trade_writes, [])
                with self.service.store.connection() as connection:
                    self.assertIsNotNone(connection.execute(
                        "SELECT 1 FROM strategies WHERE strategy_id=?", (strategy_id,)
                    ).fetchone())
        self.exchange.position_response_override = False

    def test_red_t73_terminal_delete_rejects_ambiguous_raw_order_responses(self) -> None:
        responses = (
            ("missing_data", lambda details: {"code": "0"}),
            ("null_data", lambda details: {"code": "0", "data": None}),
            ("nonlist_data", lambda details: {"code": "0", "data": {}}),
            ("nonobject_response", lambda details: []),
            ("nonobject_row", lambda details: {"code": "0", "data": [None]}),
            (
                "multiple_rows",
                lambda details: {"code": "0", "data": [details, {**details, "state": "live"}]},
            ),
        )
        for name, response_factory in responses:
            with self.subTest(response=name):
                self.exchange.order_detail_response_override = False
                strategy_id, result = self._make_canceled_terminal_strategy()
                client_id = result["orders"][0]["clientOrderId"]
                details = deepcopy(self.exchange.orders[client_id])
                self.exchange.order_detail_response_override = True
                self.exchange.order_detail_response = response_factory(details)
                self.exchange.calls.clear()

                status, rejected = self.request("POST", f"/v1/strategies/{strategy_id}/delete", {})

                expected_status = 502 if name in {"nonlist_data", "nonobject_response"} else 409
                expected_error = "exchange_unavailable" if expected_status == 502 else "strategy_immutable"
                self.assertEqual(status, expected_status, rejected)
                self.assertEqual(rejected["error"], expected_error)
                self.assertEqual(self.exchange.trade_writes, [])
                with self.service.store.connection() as connection:
                    self.assertIsNotNone(connection.execute(
                        "SELECT 1 FROM strategies WHERE strategy_id=?", (strategy_id,)
                    ).fetchone())
        self.exchange.order_detail_response_override = False

    def test_red_t73_submitted_batch_delete_rejects_not_submitted_rows(self) -> None:
        strategy_id, result = self._make_canceled_terminal_strategy()
        orders = deepcopy(result["orders"])
        orders[0]["status"] = "not_submitted"
        orders[0]["placementState"] = "not_submitted"
        orders[0]["exchangeOrderId"] = None
        orders[0]["filledContracts"] = "0"
        with self.service.store.transaction() as connection:
            connection.execute(
                "UPDATE strategies SET results_json=?, updated_at=updated_at+1 WHERE strategy_id=?",
                (encode_json(orders), strategy_id),
            )

        status, projected = self.request("GET", f"/v1/strategies/{strategy_id}/result")
        self.assertEqual(status, 200, projected)
        self.assertFalse(projected["canDelete"], projected)
        self.exchange.calls.clear()
        reads_before = self.exchange.order_detail_reads

        status, rejected = self.request("POST", f"/v1/strategies/{strategy_id}/delete", {})

        self.assertEqual(status, 409, rejected)
        self.assertEqual(rejected["error"], "strategy_immutable")
        self.assertEqual(self.exchange.order_detail_reads, reads_before)
        self.assertEqual(self.exchange.trade_writes, [])
        with self.service.store.connection() as connection:
            self.assertIsNotNone(connection.execute(
                "SELECT 1 FROM strategies WHERE strategy_id=?", (strategy_id,)
            ).fetchone())

    def test_green_t73_stopped_sequential_not_submitted_rows_remain_deletable(self) -> None:
        status, setting = self.request(
            "POST", "/v1/strategies/settings", {"limitOrderSubmissionMode": "sequential"}
        )
        self.assertEqual(status, 200, setting)
        strategy_id, _ = self.save_draft(self.multi_order_contract(2))
        status, prepared = self.request(
            "POST", f"/v1/strategies/{strategy_id}/prepare-apply", {}
        )
        self.assertEqual(status, 200, prepared)
        status, queued = self.request(
            "POST", f"/v1/strategies/{strategy_id}/execute-apply",
            {"confirmationToken": prepared["confirmationToken"]},
        )
        self.assertEqual(status, 200, queued)
        self.assertEqual(queued["queueStatus"], "pending")
        self.exchange.leverage_response = {"code": "51008", "data": [{}]}
        self.assertTrue(self._worker().run_once())
        self.exchange.leverage_response = None

        status, stopped = self.request("GET", f"/v1/strategies/{strategy_id}/result")
        self.assertEqual(status, 200, stopped)
        self.assertEqual(stopped["queueStatus"], "stopped")
        self.assertEqual([row["status"] for row in stopped["orders"]], ["not_submitted", "not_submitted"])
        self.assertTrue(stopped["canDelete"], stopped)
        reads_before = self.exchange.order_detail_reads
        self.exchange.calls.clear()

        status, deleted = self.request("POST", f"/v1/strategies/{strategy_id}/delete", {})

        self.assertEqual(status, 200, deleted)
        self.assertEqual(deleted["status"], "DELETED")
        self.assertEqual(self.exchange.order_detail_reads, reads_before)
        self.assertEqual(self.exchange.trade_writes, [])

    def test_green_canceled_terminal_orders_can_be_deleted_without_replacement_eligibility(self) -> None:
        strategy_id, result = self._make_canceled_terminal_strategy()
        self.assertTrue(result["canDelete"])
        self.assertFalse(result["canReplace"])
        reads_before = self.exchange.order_detail_reads
        self.exchange.calls.clear()

        status, deleted = self.request("POST", f"/v1/strategies/{strategy_id}/delete", {})

        self.assertEqual(status, 200, deleted)
        self.assertEqual(self.exchange.order_detail_reads - reads_before, len(result["orders"]))
        self.assertEqual(self.exchange.trade_writes, [])
        with self.service.store.connection() as connection:
            self.assertIsNone(connection.execute(
                "SELECT 1 FROM strategies WHERE strategy_id=?", (strategy_id,)
            ).fetchone())
            self.assertIsNone(connection.execute(
                "SELECT 1 FROM strategy_reservations WHERE strategy_id=?", (strategy_id,)
            ).fetchone())
            self.assertIsNone(connection.execute(
                "SELECT 1 FROM strategy_sync_state WHERE strategy_id=?", (strategy_id,)
            ).fetchone())

    def test_red_replacement_source_must_be_eligible_when_saved_and_before_execute(self) -> None:
        source_id, _ = self.save_draft()
        with self.service.store.transaction() as connection:
            connection.execute(
                "UPDATE strategies SET status='APPLYING', attempt_started=1, execution_id='active-run', "
                "execution_lease_until=? WHERE strategy_id=?",
                (self.now + 30, source_id),
            )
        contract = self.one_sided_contract()
        status, preview = self.request("POST", "/v1/strategies/preview", contract)
        self.assertEqual(status, 200, preview)
        status, conflict = self.request(
            "POST",
            "/v1/strategies",
            {**contract, "previewHash": preview["previewHash"], "replacementSourceId": source_id},
        )
        self.assertEqual(status, 409, conflict)
        self.assertEqual(conflict["error"], "replacement_source_unavailable")

        with self.service.store.transaction() as connection:
            connection.execute(
                "UPDATE strategies SET status='PARTIAL', execution_id=NULL, execution_lease_until=NULL "
                "WHERE strategy_id=?",
                (source_id,),
            )
        replacement_id, _ = self.save_draft(replacement_source_id=source_id)
        status, prepared = self.request(
            "POST", f"/v1/strategies/{replacement_id}/prepare-apply", {}
        )
        self.assertEqual(status, 200, prepared)
        with self.service.store.transaction() as connection:
            connection.execute(
                "UPDATE strategies SET batch_attempted=1 WHERE strategy_id=?", (source_id,)
            )
        status, conflict = self.request(
            "POST",
            f"/v1/strategies/{replacement_id}/execute-apply",
            {"confirmationToken": prepared["confirmationToken"]},
        )
        self.assertEqual(status, 409, conflict)
        self.assertEqual(conflict["error"], "replacement_source_unavailable")
        self.assertEqual(self.exchange.trade_writes, [])
        self.assertEqual(self.exchange.batch_writes, [])

    def test_green_replacement_full_acceptance_removes_source_and_sync_rows(self) -> None:
        source_id, _ = self.save_draft()
        with self.service.store.transaction() as connection:
            connection.execute(
                "UPDATE strategies SET status='COMPLETED', attempt_started=1, "
                "leverage_results_json=? WHERE strategy_id=?",
                (encode_json([{"side": "long", "status": "rejected", "errorCode": "51000"}]), source_id),
            )
            connection.execute(
                "INSERT INTO strategy_sync_state(strategy_id, next_scan_at) VALUES (?, ?)",
                (source_id, self.now + 30),
            )

        replacement_id, _ = self.save_draft(replacement_source_id=source_id)
        with self.service.store.connection() as connection:
            source_orders = json.loads(connection.execute(
                "SELECT orders_json FROM strategies WHERE strategy_id=?", (source_id,)
            ).fetchone()["orders_json"])
            replacement_orders = json.loads(connection.execute(
                "SELECT orders_json FROM strategies WHERE strategy_id=?", (replacement_id,)
            ).fetchone()["orders_json"])
        self.assertTrue(
            {row["clientOrderId"] for row in source_orders}.isdisjoint(
                {row["clientOrderId"] for row in replacement_orders}
            )
        )

        status, prepared = self.request(
            "POST", f"/v1/strategies/{replacement_id}/prepare-apply", {}
        )
        self.assertEqual(status, 200, prepared)
        status, result = self.request(
            "POST",
            f"/v1/strategies/{replacement_id}/execute-apply",
            {"confirmationToken": prepared["confirmationToken"]},
        )
        self.assertEqual(status, 200, result)
        self.assertEqual(result["status"], "APPLIED")
        self.assertFalse(result["replacementCleanupConflict"])
        self.assertEqual(len(self.exchange.batch_writes), 1)
        with self.service.store.connection() as connection:
            self.assertIsNone(connection.execute(
                "SELECT 1 FROM strategies WHERE strategy_id=?", (source_id,)
            ).fetchone())
            self.assertIsNone(connection.execute(
                "SELECT 1 FROM strategy_sync_state WHERE strategy_id=?", (source_id,)
            ).fetchone())

    def test_red_active_replacement_blocks_source_delete_until_full_acceptance(self) -> None:
        source_id, _ = self.save_draft()
        replacement_id, _ = self.save_draft(replacement_source_id=source_id)
        status, prepared = self.request(
            "POST", f"/v1/strategies/{replacement_id}/prepare-apply", {}
        )
        self.assertEqual(status, 200, prepared)
        self.exchange.pause_batch_response = True
        with ThreadPoolExecutor(max_workers=1) as pool:
            future = pool.submit(
                self.request,
                "POST",
                f"/v1/strategies/{replacement_id}/execute-apply",
                {"confirmationToken": prepared["confirmationToken"]},
            )
            self.assertTrue(self.exchange.batch_started.wait(timeout=5))
            status, listing = self.request("GET", "/v1/strategies")
            self.assertEqual(status, 200, listing)
            source = next(row for row in listing["strategies"] if row["id"] == source_id)
            self.assertFalse(source["canDelete"])
            status, conflict = self.request("POST", f"/v1/strategies/{source_id}/delete", {})
            self.assertEqual(status, 409, conflict)
            with self.service.store.connection() as connection:
                self.assertIsNotNone(connection.execute(
                    "SELECT 1 FROM strategies WHERE strategy_id=?", (source_id,)
                ).fetchone())
            self.exchange.batch_release.set()
            status, result = future.result(timeout=8)
        self.assertEqual(status, 200, result)
        self.assertEqual(result["status"], "APPLIED")
        self.assertFalse(result["replacementCleanupConflict"])
        with self.service.store.connection() as connection:
            self.assertIsNone(connection.execute(
                "SELECT 1 FROM strategies WHERE strategy_id=?", (source_id,)
            ).fetchone())
        self.assertEqual(len(self.exchange.batch_writes), 1)

    def test_red_partial_or_unknown_replacement_keeps_source_and_never_resends(self) -> None:
        for outcome in ("PARTIAL", "UNKNOWN"):
            with self.subTest(outcome=outcome):
                source_id, _ = self.save_draft()
                replacement_id, _ = self.save_draft(replacement_source_id=source_id)
                status, prepared = self.request(
                    "POST", f"/v1/strategies/{replacement_id}/prepare-apply", {}
                )
                self.assertEqual(status, 200, prepared)
                command = {"confirmationToken": prepared["confirmationToken"]}
                if outcome == "PARTIAL":
                    self.exchange.batch_ack = [{
                        "sCode": "51000",
                        "sMsg": "do not expose this exchange message",
                        "clOrdId": prepared["orders"][0]["clientOrderId"],
                    }]
                else:
                    self.exchange.batch_timeout = True
                status, result = self.request(
                    "POST", f"/v1/strategies/{replacement_id}/execute-apply", command
                )
                self.assertEqual(status, 200, result)
                self.assertEqual(result["status"], outcome)
                self.assertFalse(result["replacementCleanupConflict"])
                batch_count = len(self.exchange.batch_writes)
                status, duplicate = self.request(
                    "POST", f"/v1/strategies/{replacement_id}/execute-apply", command
                )
                self.assertEqual(status, 200, duplicate)
                self.assertEqual(len(self.exchange.batch_writes), batch_count)
                with self.service.store.connection() as connection:
                    self.assertIsNotNone(connection.execute(
                        "SELECT 1 FROM strategies WHERE strategy_id=?", (source_id,)
                    ).fetchone())
                self.exchange.batch_ack = None
                self.exchange.batch_timeout = False

    def test_green_fully_accepted_replacement_reports_guarded_cleanup_conflict(self) -> None:
        source_id, _ = self.save_draft()
        replacement_id, _ = self.save_draft(replacement_source_id=source_id)
        status, prepared = self.request(
            "POST", f"/v1/strategies/{replacement_id}/prepare-apply", {}
        )
        self.assertEqual(status, 200, prepared)
        self.exchange.pause_batch_response = True
        with ThreadPoolExecutor(max_workers=1) as pool:
            future = pool.submit(
                self.request,
                "POST",
                f"/v1/strategies/{replacement_id}/execute-apply",
                {"confirmationToken": prepared["confirmationToken"]},
            )
            self.assertTrue(self.exchange.batch_started.wait(timeout=5))
            with self.service.store.transaction() as connection:
                connection.execute(
                    "UPDATE strategies SET batch_attempted=1, status='PARTIAL' WHERE strategy_id=?",
                    (source_id,),
                )
            self.exchange.batch_release.set()
            status, result = future.result(timeout=8)
        self.assertEqual(status, 200, result)
        self.assertEqual(result["status"], "APPLIED")
        self.assertTrue(result["replacementCleanupConflict"])
        self.assertEqual(len(self.exchange.batch_writes), 1)
        completed_results = [
            {**row, "status": "filled", "filledContracts": row["contracts"]}
            for row in result["orders"]
        ]
        with self.service.store.transaction() as connection:
            connection.execute(
                "UPDATE strategies SET status='COMPLETED', results_json=? WHERE strategy_id=?",
                (encode_json(completed_results), replacement_id),
            )
        status, completed = self.request("GET", f"/v1/strategies/{replacement_id}/result")
        self.assertEqual(status, 200, completed)
        self.assertEqual(completed["status"], "COMPLETED")
        self.assertTrue(completed["replacementCleanupConflict"])
        with self.service.store.connection() as connection:
            self.assertIsNotNone(connection.execute(
                "SELECT 1 FROM strategies WHERE strategy_id=?", (source_id,)
            ).fetchone())

    def test_red_canceled_rows_without_exchange_identity_do_not_prove_full_acceptance(self) -> None:
        source_id, _ = self.save_draft()
        replacement_id, _ = self.save_draft(replacement_source_id=source_id)
        with self.service.store.transaction() as connection:
            replacement_orders = json.loads(connection.execute(
                "SELECT orders_json FROM strategies WHERE strategy_id=?", (replacement_id,)
            ).fetchone()["orders_json"])
            canceled = [{**row, "status": "canceled"} for row in replacement_orders]
            connection.execute(
                "UPDATE strategies SET status='COMPLETED', attempt_started=1, batch_attempted=1, "
                "results_json=? WHERE strategy_id=?",
                (encode_json(canceled), replacement_id),
            )

        status, result = self.request("GET", f"/v1/strategies/{replacement_id}/result")
        self.assertEqual(status, 200, result)
        self.assertFalse(result["replacementCleanupConflict"])
        with self.service.store.connection() as connection:
            self.assertIsNotNone(connection.execute(
                "SELECT 1 FROM strategies WHERE strategy_id=?", (source_id,)
            ).fetchone())

    def test_red_leverage_rejections_retain_only_bounded_error_code(self) -> None:
        cases = (
            ({"code": "0", "data": [{"sCode": "51000", "sMsg": "private exchange message"}]}, "51000"),
            ({"code": "51001", "data": [{"sMsg": "private exchange message"}]}, "51001"),
        )
        for response, expected_code in cases:
            with self.subTest(code=expected_code):
                strategy_id, _ = self.save_draft()
                status, prepared = self.request(
                    "POST", f"/v1/strategies/{strategy_id}/prepare-apply", {}
                )
                self.assertEqual(status, 200, prepared)
                self.exchange.leverage_response = response
                status, result = self.request(
                    "POST",
                    f"/v1/strategies/{strategy_id}/execute-apply",
                    {"confirmationToken": prepared["confirmationToken"]},
                )
                self.assertEqual(status, 200, result)
                self.assertEqual(result["status"], "PARTIAL")
                self.assertEqual(result["leverageResults"][0]["errorCode"], expected_code)
                self.assertNotIn("sMsg", json.dumps(result))
                self.assertNotIn("private exchange message", json.dumps(result))
                self.assertEqual(self.exchange.batch_writes, [])
                self.exchange.leverage_response = None

    def test_red_malformed_batch_code_is_unknown_and_never_a_retry_candidate(self) -> None:
        source_id, _ = self.save_draft()
        status, prepared = self.request(
            "POST", f"/v1/strategies/{source_id}/prepare-apply", {}
        )
        self.assertEqual(status, 200, prepared)
        self.exchange.batch_ack = [{
            "clOrdId": prepared["orders"][0]["clientOrderId"],
            "sCode": {"private": "51008"},
        }]
        status, result = self.request(
            "POST", f"/v1/strategies/{source_id}/execute-apply",
            {"confirmationToken": prepared["confirmationToken"]},
        )
        self.assertEqual(status, 200, result)
        self.assertEqual(result["status"], "UNKNOWN")
        self.assertEqual(result["orders"][0]["status"], "unknown")
        self.exchange.batch_ack = None

        status, candidates = self.request(
            "GET", f"/v1/strategies/{source_id}/retry-candidates"
        )
        self.assertEqual(status, 200, candidates)
        self.assertFalse(candidates["candidates"][0]["eligible"])
        self.assertEqual(candidates["blockedReason"], "reservation_active")
        self.assertEqual(candidates["candidates"][0]["reason"], "reservation_active")

    def test_red_retry_review_rejects_position_pending_reservation_and_balance_blocks(self) -> None:
        source_id, source_result, _ = self._make_rejected_source()
        status, candidates = self.request(
            "GET", f"/v1/strategies/{source_id}/retry-candidates"
        )
        self.assertEqual(status, 200, candidates)
        review = {
            "sourceRevision": candidates["sourceRevision"],
            "sourceClientOrderIds": [source_result["orders"][0]["clientOrderId"]],
        }
        writes_before = len(self.exchange.trade_writes)

        self.exchange.positions = [{"instId": INSTRUMENT, "pos": "1"}]
        status, refusal = self.request("POST", f"/v1/strategies/{source_id}/retry-preview", review)
        self.assertEqual(status, 409, refusal)
        self.assertEqual(refusal["error"], "instrument_position_exists")
        self.exchange.positions = []

        self.exchange.pending = [{"instId": INSTRUMENT}]
        status, refusal = self.request("POST", f"/v1/strategies/{source_id}/retry-preview", review)
        self.assertEqual(status, 409, refusal)
        self.assertEqual(refusal["error"], "pending_order_exists")
        self.exchange.pending = []

        self.exchange.available_balance = "1"
        status, refusal = self.request("POST", f"/v1/strategies/{source_id}/retry-preview", review)
        self.assertEqual(status, 422, refusal)
        self.assertEqual(refusal["error"], "insufficient_balance")
        self.exchange.available_balance = "100000"

        account_fingerprint = token_digest(
            "okx-account-uid:v1:" + self.exchange.account_uid, SIGNING_KEY
        )
        with self.service.store.transaction() as connection:
            connection.execute(
                "INSERT INTO strategy_reservations(account_fingerprint, instrument_id, strategy_id, created_at) "
                "VALUES (?, ?, ?, ?)",
                (account_fingerprint, INSTRUMENT, source_id, self.now),
            )
        status, refusal = self.request("POST", f"/v1/strategies/{source_id}/retry-preview", review)
        self.assertEqual(status, 409, refusal)
        self.assertEqual(refusal["error"], "retry_source_unavailable")
        with self.service.store.transaction() as connection:
            connection.execute("DELETE FROM strategy_reservations WHERE strategy_id=?", (source_id,))
        self.assertEqual(len(self.exchange.trade_writes), writes_before)

    def test_red_prepare_rejects_unavailable_or_ambiguous_usdt_balance(self) -> None:
        malformed_responses = (
            [],
            [{"details": [{"ccy": "BTC", "availBal": "100000"}]}],
            [{"details": [{"ccy": "USDT", "availBal": "NaN"}]}],
            [{"details": [{"ccy": "USDT", "availBal": "Infinity"}]}],
            [{"details": [
                {"ccy": "USDT", "availBal": "100000"},
                {"ccy": "USDT", "availBal": "100000"},
            ]}],
            [None, {"details": [{"ccy": "USDT", "availBal": "100000"}]}],
            [
                {"details": "malformed"},
                {"details": [{"ccy": "USDT", "availBal": "100000"}]},
            ],
        )
        for response in malformed_responses:
            with self.subTest(response=response):
                strategy_id, _ = self.save_draft()
                with patch.object(self.service.okx, "account_balance", return_value=response):
                    status, refusal = self.request(
                        "POST", f"/v1/strategies/{strategy_id}/prepare-apply", {}
                    )
                self.assertEqual(status, 502, refusal)
                self.assertEqual(refusal["error"], "account_preflight_unavailable")
                self.assertEqual(self.exchange.trade_writes, [])

    def test_red_prepare_maps_rate_limited_exchange_reads_to_safe_429(self) -> None:
        methods = (
            "account_config", "positions", "pending_orders", "instruments",
            "ticker", "trade_fee", "position_tiers", "account_balance",
        )
        for method in methods:
            with self.subTest(method=method):
                strategy_id, _ = self.save_draft()
                error = OKXError(
                    "upstream response must not leak", diagnostic_category="http_rejected",
                    http_status=429,
                )
                response_headers: list[tuple[str, str]] = []
                with patch.object(self.service.okx, method, side_effect=error):
                    status, refusal = self.request(
                        "POST", f"/v1/strategies/{strategy_id}/prepare-apply", {},
                        captured_headers=response_headers,
                    )
                self.assertEqual(status, 429, refusal)
                self.assertEqual(refusal["error"], "exchange_rate_limited")
                self.assertNotIn("upstream response", json.dumps(refusal))
                self.assertIn(("Retry-After", "2"), response_headers)
                self.assertEqual(self.exchange.trade_writes, [])

    def test_red_prepare_preserves_non_rate_limit_read_fallbacks(self) -> None:
        fallbacks = {
            "account_config": "exchange_unavailable",
            "positions": "account_preflight_unavailable",
            "pending_orders": "account_preflight_unavailable",
            "instruments": "preview_inputs_unavailable",
            "ticker": "preview_inputs_unavailable",
            "trade_fee": "preview_inputs_unavailable",
            "position_tiers": "preview_inputs_unavailable",
            "account_balance": "account_preflight_unavailable",
        }
        for method, expected_code in fallbacks.items():
            with self.subTest(method=method):
                strategy_id, _ = self.save_draft()
                error = OKXError(
                    "private upstream response", diagnostic_category="http_rejected",
                    http_status=503,
                )
                with patch.object(self.service.okx, method, side_effect=error):
                    status, refusal = self.request(
                        "POST", f"/v1/strategies/{strategy_id}/prepare-apply", {}
                    )
                self.assertEqual(status, 502, refusal)
                self.assertEqual(refusal["error"], expected_code)
                self.assertNotIn("private upstream response", json.dumps(refusal))
                self.assertEqual(self.exchange.trade_writes, [])

    def test_red_retry_balance_guard_shares_strict_avail_bal_semantics(self) -> None:
        source_id, source_result, _ = self._make_rejected_source()
        status, candidates = self.request("GET", f"/v1/strategies/{source_id}/retry-candidates")
        self.assertEqual(status, 200, candidates)
        review = {
            "sourceRevision": candidates["sourceRevision"],
            "sourceClientOrderIds": [source_result["orders"][0]["clientOrderId"]],
        }
        writes_before = len(self.exchange.trade_writes)

        malformed = (
            [{"details": [{"ccy": "USDT", "availBal": "NaN"}]}],
            [{"details": [
                {"ccy": "USDT", "availBal": "100000"},
                {"ccy": "USDT", "availBal": "100000"},
            ]}],
        )
        for response in malformed:
            with self.subTest(response=response):
                with patch.object(self.service.okx, "account_balance", return_value=response):
                    status, refusal = self.request(
                        "POST", f"/v1/strategies/{source_id}/retry-preview", review
                    )
                self.assertEqual(status, 502, refusal)
                self.assertEqual(refusal["error"], "account_preflight_unavailable")

        for available in ("-1", "0"):
            with self.subTest(available=available):
                rows = [{"details": [{"ccy": "USDT", "availBal": available}]}]
                with patch.object(self.service.okx, "account_balance", return_value=rows):
                    status, refusal = self.request(
                        "POST", f"/v1/strategies/{source_id}/retry-preview", review
                    )
                self.assertEqual(status, 422, refusal)
                self.assertEqual(refusal["error"], "insufficient_balance")
                self.assertEqual(refusal["available"], available)

        with patch.object(
            self.service.okx,
            "account_balance",
            return_value=[{"details": [{"ccy": "USDT", "availBal": "100000"}]}],
        ):
            status, preview = self.request(
                "POST", f"/v1/strategies/{source_id}/retry-preview", review
            )
        self.assertEqual(status, 200, preview)
        required = Decimal(preview["totalMargin"]) + Decimal(preview["estimatedOpeningFees"] or "0")
        rows = [{"details": [{"ccy": "USDT", "availBal": format(required, "f")}]}]
        with patch.object(self.service.okx, "account_balance", return_value=rows):
            status, equal_preview = self.request(
                "POST", f"/v1/strategies/{source_id}/retry-preview", review
            )
        self.assertEqual(status, 200, equal_preview)
        self.assertEqual(len(self.exchange.trade_writes), writes_before)

    def test_red_retry_review_maps_rate_limited_account_reads(self) -> None:
        source_id, source_result, _ = self._make_rejected_source()
        status, candidates = self.request("GET", f"/v1/strategies/{source_id}/retry-candidates")
        self.assertEqual(status, 200, candidates)
        review = {
            "sourceRevision": candidates["sourceRevision"],
            "sourceClientOrderIds": [source_result["orders"][0]["clientOrderId"]],
        }
        writes_before = len(self.exchange.trade_writes)
        for method in ("account_config", "positions", "pending_orders", "account_balance"):
            with self.subTest(method=method):
                error = OKXError("private upstream response", http_status=429)
                headers: list[tuple[str, str]] = []
                with patch.object(self.service.okx, method, side_effect=error):
                    status, refusal = self.request(
                        "POST", f"/v1/strategies/{source_id}/retry-preview", review,
                        captured_headers=headers,
                    )
                self.assertEqual(status, 429, refusal)
                self.assertEqual(refusal["error"], "exchange_rate_limited")
                self.assertIn(("Retry-After", "2"), headers)
                self.assertNotIn("private upstream response", json.dumps(refusal))
                self.assertEqual(len(self.exchange.trade_writes), writes_before)

    def test_red_balance_transport_rejects_malformed_rows_before_balance_parser(self) -> None:
        strategy_id, _ = self.save_draft()
        self.exchange.account_balance_response_override = True
        self.exchange.account_balance_response = {
            "code": "0",
            "data": [None, {"details": [{"ccy": "USDT", "availBal": "100000"}]}],
        }

        status, refusal = self.request(
            "POST", f"/v1/strategies/{strategy_id}/prepare-apply", {}
        )

        self.assertEqual(status, 502, refusal)
        self.assertEqual(refusal["error"], "account_preflight_unavailable")
        self.assertEqual(self.exchange.trade_writes, [])

    def test_green_prepare_reuses_one_fresh_account_snapshot_per_request(self) -> None:
        strategy_id, _ = self.save_draft()
        original = self.service.okx.account_config
        reads = 0

        def reject_second_read() -> dict[str, Any]:
            nonlocal reads
            reads += 1
            if reads > 1:
                raise OKXError("second account read rejected", http_status=429)
            return original()

        with patch.object(self.service.okx, "account_config", side_effect=reject_second_read):
            status, prepared = self.request(
                "POST", f"/v1/strategies/{strategy_id}/prepare-apply", {}
            )
        self.assertEqual(status, 200, prepared)
        self.assertEqual(reads, 1)

        second_id, _ = self.save_draft()
        start = len(self.exchange.calls)
        status, second_prepared = self.request(
            "POST", f"/v1/strategies/{second_id}/prepare-apply", {}
        )
        self.assertEqual(status, 200, second_prepared)
        config_reads = sum(
            method == "GET" and urlsplit(path).path == "/api/v5/account/config"
            for method, path, _ in self.exchange.calls[start:]
        )
        self.assertEqual(config_reads, 1)

    def test_green_prepare_balance_boundary_includes_fees_and_accepts_equality(self) -> None:
        contract = self.one_sided_contract()
        _, draft_preview = self.save_draft(contract)
        required = Decimal(contract["totalMargin"]) + Decimal(draft_preview["estimatedOpeningFees"])
        insufficient_values = (Decimal("-1"), Decimal("0"), required - Decimal("0.0001"))

        for available in insufficient_values:
            with self.subTest(available=available):
                strategy_id, _ = self.save_draft(contract)
                self.exchange.available_balance = format(available, "f")
                status, refusal = self.request(
                    "POST", f"/v1/strategies/{strategy_id}/prepare-apply", {}
                )
                self.assertEqual(status, 422, refusal)
                self.assertEqual(refusal["error"], "insufficient_balance")
                self.assertEqual(Decimal(refusal["required"]), required)
                self.assertEqual(Decimal(refusal["available"]), available)

        strategy_id, _ = self.save_draft(contract)
        self.exchange.available_balance = format(required, "f")
        status, prepared = self.request(
            "POST", f"/v1/strategies/{strategy_id}/prepare-apply", {}
        )
        self.assertEqual(status, 200, prepared)
        self.assertEqual(self.exchange.trade_writes, [])
        self.exchange.available_balance = "100000"

    def test_green_retry_preview_and_draft_reuse_source_account_snapshot(self) -> None:
        source_id, source_result, _ = self._make_rejected_source()
        status, candidates = self.request("GET", f"/v1/strategies/{source_id}/retry-candidates")
        self.assertEqual(status, 200, candidates)
        review = {
            "sourceRevision": candidates["sourceRevision"],
            "sourceClientOrderIds": [source_result["orders"][0]["clientOrderId"]],
        }

        start = len(self.exchange.calls)
        status, preview = self.request("POST", f"/v1/strategies/{source_id}/retry-preview", review)
        self.assertEqual(status, 200, preview)
        config_reads = sum(
            method == "GET" and urlsplit(path).path == "/api/v5/account/config"
            for method, path, _ in self.exchange.calls[start:]
        )
        self.assertEqual(config_reads, 1)

        draft_request = {
            **review,
            "previewHash": preview["previewHash"],
            "retryRequestId": "retry-request-snapshot-01",
        }
        start = len(self.exchange.calls)
        status, draft = self.request("POST", f"/v1/strategies/{source_id}/retry-drafts", draft_request)
        self.assertEqual(status, 200, draft)
        config_reads = sum(
            method == "GET" and urlsplit(path).path == "/api/v5/account/config"
            for method, path, _ in self.exchange.calls[start:]
        )
        self.assertEqual(config_reads, 1)

        start = len(self.exchange.calls)
        status, prepared = self.request(
            "POST", f"/v1/strategies/{draft['id']}/prepare-apply", {}
        )
        self.assertEqual(status, 200, prepared)
        config_reads = sum(
            method == "GET" and urlsplit(path).path == "/api/v5/account/config"
            for method, path, _ in self.exchange.calls[start:]
        )
        self.assertEqual(config_reads, 1)

    def test_green_batch_execute_rechecks_account_and_mode_after_leverage(self) -> None:
        mutations = (
            ("account", "987654321"),
            ("mode", "unsupported_mode"),
        )
        for kind, value in mutations:
            with self.subTest(kind=kind):
                self.exchange.account_uid = "123456789"
                self.exchange.pos_mode = "net_mode"
                self.exchange.after_leverage_write = None
                strategy_id, _ = self.save_draft()
                status, prepared = self.request(
                    "POST", f"/v1/strategies/{strategy_id}/prepare-apply", {}
                )
                self.assertEqual(status, 200, prepared)
                if kind == "account":
                    self.exchange.after_leverage_write = lambda _payload, _response: setattr(
                        self.exchange, "account_uid", value
                    )
                else:
                    self.exchange.after_leverage_write = lambda _payload, _response: setattr(
                        self.exchange, "pos_mode", value
                    )

                start = len(self.exchange.calls)
                status, result = self.request(
                    "POST", f"/v1/strategies/{strategy_id}/execute-apply",
                    {"confirmationToken": prepared["confirmationToken"]},
                )

                if kind == "account":
                    self.assertEqual(status, 409, result)
                    self.assertEqual(result["error"], "account_changed")
                else:
                    self.assertEqual(status, 200, result)
                    self.assertEqual(result["status"], "PARTIAL")
                self.assertEqual(self.exchange.batch_writes, [])
                execute_calls = self.exchange.calls[start:]
                leverage_index = next(
                    index for index, (method, path, _) in enumerate(execute_calls)
                    if method == "POST" and urlsplit(path).path == "/api/v5/account/set-leverage"
                )
                config_reads_before_leverage = sum(
                    method == "GET" and urlsplit(path).path == "/api/v5/account/config"
                    for method, path, _ in execute_calls[:leverage_index]
                )
                config_reads_after_leverage = sum(
                    method == "GET" and urlsplit(path).path == "/api/v5/account/config"
                    for method, path, _ in execute_calls[leverage_index + 1:]
                )
                self.assertEqual(config_reads_before_leverage, 1)
                self.assertGreaterEqual(config_reads_after_leverage, 1)

    def test_green_retry_dca_only_keeps_fixed_rows_ids_and_idempotent_execute(self) -> None:
        source_contract = self.id_mode_contract(
            [
                {"side": "long", "price": "59000", "levelId": "retry-entry"},
                {"side": "long", "price": "58000", "levelId": "retry-dca"},
            ],
            entry_ids={"long": "retry-entry"},
        )
        source_contract["totalMargin"] = "600"
        source_id, source_result, source_prepared = self._make_rejected_source(
            contract=source_contract, rejected_order_index=1, accepted_as_canceled=True
        )
        self.assertEqual(source_result["status"], "PARTIAL")
        source_rows = source_result["orders"]
        rejected_source_row = source_rows[1]

        status, candidates = self.request(
            "GET", f"/v1/strategies/{source_id}/retry-candidates"
        )
        self.assertEqual(status, 200, candidates)
        eligible = [row for row in candidates["candidates"] if row["eligible"]]
        self.assertEqual([row["sourceClientOrderId"] for row in eligible], [rejected_source_row["clientOrderId"]])
        self.assertEqual(eligible[0]["role"], "dca")

        review_body = {
            "sourceRevision": candidates["sourceRevision"],
            "sourceClientOrderIds": [rejected_source_row["clientOrderId"]],
        }
        status, preview = self.request(
            "POST", f"/v1/strategies/{source_id}/retry-preview", review_body
        )
        self.assertEqual(status, 200, preview)
        self.assertEqual(preview["orders"][0]["role"], "dca")
        self.assertEqual(preview["orders"][0]["limitPrice"], rejected_source_row["limitPrice"])
        self.assertEqual(preview["orders"][0]["contracts"], rejected_source_row["contracts"])
        self.assertEqual(preview["unallocatedMargin"], "0")
        self.assertEqual(
            Decimal(preview["requiredBalance"]),
            Decimal(preview["totalMargin"]) + Decimal(preview["estimatedOpeningFees"]),
        )

        request_id = "retry-request-green-001"
        draft_body = {
            **review_body,
            "previewHash": preview["previewHash"],
            "retryRequestId": request_id,
        }
        status, child = self.request(
            "POST", f"/v1/strategies/{source_id}/retry-drafts", draft_body
        )
        self.assertEqual(status, 200, child)
        self.assertEqual(child["resubmission"]["sourceStrategyId"], source_id)
        self.assertEqual(child["resubmission"]["sourceClientOrderIds"], review_body["sourceClientOrderIds"])
        child_order = child["orders"][0]
        self.assertNotEqual(child_order["clientOrderId"], rejected_source_row["clientOrderId"])
        self.assertEqual(child_order["sourceClientOrderId"], rejected_source_row["clientOrderId"])
        self.assertEqual(child_order["role"], "dca")

        with self.service.store.connection() as connection:
            stored = connection.execute(
                "SELECT contract_json, replacement_source_id FROM strategies WHERE strategy_id=?",
                (child["id"],),
            ).fetchone()
            stored_contract = json.loads(stored["contract_json"])
            count = connection.execute("SELECT COUNT(*) FROM strategies").fetchone()[0]
        self.assertIsNone(stored["replacement_source_id"])
        self.assertEqual(stored_contract["kind"], "resubmission")
        self.assertEqual(stored_contract["resubmission"]["retryRequestId"], request_id)

        writes_before_replay = len(self.exchange.trade_writes)
        status, replay = self.request(
            "POST", f"/v1/strategies/{source_id}/retry-drafts", draft_body
        )
        self.assertEqual(status, 200, replay)
        self.assertEqual(replay["id"], child["id"])
        self.assertEqual(replay["status"], "DRAFT")
        self.assertNotIn("confirmationToken", replay)
        self.assertEqual(len(self.exchange.trade_writes), writes_before_replay)
        with self.service.store.connection() as connection:
            self.assertEqual(connection.execute("SELECT COUNT(*) FROM strategies").fetchone()[0], count)
        status, conflicting_replay = self.request(
            "POST", f"/v1/strategies/{source_id}/retry-drafts",
            {**draft_body, "previewHash": "0" * 64},
        )
        self.assertEqual(status, 409, conflicting_replay)
        self.assertEqual(conflicting_replay["error"], "retry_request_conflict")

        status, prepared = self.request(
            "POST", f"/v1/strategies/{child['id']}/prepare-apply", {}
        )
        self.assertEqual(status, 200, prepared)
        self.assertEqual(prepared["id"], child["id"])
        self.assertEqual(prepared["resubmission"]["sourceStrategyId"], source_id)
        self.assertEqual(prepared["resubmission"]["sourceClientOrderIds"], review_body["sourceClientOrderIds"])
        self.assertEqual(prepared["orders"][0]["clientOrderId"], child_order["clientOrderId"])
        self.assertEqual(prepared["orders"][0]["contracts"], rejected_source_row["contracts"])
        writes_before_execute = len(self.exchange.trade_writes)
        status, applied = self.request(
            "POST", f"/v1/strategies/{child['id']}/execute-apply",
            {"confirmationToken": prepared["confirmationToken"]},
        )
        self.assertEqual(status, 200, applied)
        self.assertEqual(applied["status"], "APPLIED")
        self.assertEqual(applied["resubmission"]["sourceStrategyId"], source_id)
        self.assertEqual(len(self.exchange.trade_writes), writes_before_execute + 2)
        status, duplicate_execute = self.request(
            "POST", f"/v1/strategies/{child['id']}/execute-apply",
            {"confirmationToken": prepared["confirmationToken"]},
        )
        self.assertEqual(status, 200, duplicate_execute)
        self.assertEqual(len(self.exchange.trade_writes), writes_before_execute + 2)

    def test_green_claimed_child_permanently_consumes_source_after_cancel_and_release(self) -> None:
        source_id, source_result, _ = self._make_rejected_source()
        source_order = source_result["orders"][0]
        status, candidates = self.request("GET", f"/v1/strategies/{source_id}/retry-candidates")
        self.assertEqual(status, 200, candidates)
        review = {
            "sourceRevision": candidates["sourceRevision"],
            "sourceClientOrderIds": [source_order["clientOrderId"]],
        }
        status, preview = self.request("POST", f"/v1/strategies/{source_id}/retry-preview", review)
        self.assertEqual(status, 200, preview)
        status, child = self.request(
            "POST", f"/v1/strategies/{source_id}/retry-drafts",
            {**review, "previewHash": preview["previewHash"], "retryRequestId": "retry-settled-child-001"},
        )
        self.assertEqual(status, 200, child)
        status, prepared = self.request("POST", f"/v1/strategies/{child['id']}/prepare-apply", {})
        self.assertEqual(status, 200, prepared)
        status, applied = self.request(
            "POST", f"/v1/strategies/{child['id']}/execute-apply",
            {"confirmationToken": prepared["confirmationToken"]},
        )
        self.assertEqual(status, 200, applied)
        self.assertEqual(applied["status"], "APPLIED")

        child_order_id = child["orders"][0]["clientOrderId"]
        self.exchange.orders[child_order_id]["state"] = "canceled"
        self.exchange.orders[child_order_id]["accFillSz"] = "0"
        self.exchange.orders[child_order_id]["avgPx"] = "0"
        with self.service.store.transaction() as connection:
            connection.execute("DELETE FROM strategy_sync_state WHERE strategy_id=?", (child["id"],))
        status, settled = self.request("GET", f"/v1/strategies/{child['id']}/result")
        self.assertEqual(status, 200, settled)
        self.assertEqual(settled["status"], "PARTIAL")
        self.assertEqual(settled["orders"][0]["status"], "canceled")
        with self.service.store.connection() as connection:
            self.assertIsNone(connection.execute(
                "SELECT 1 FROM strategy_reservations WHERE strategy_id=?", (child["id"],)
            ).fetchone())

        status, refreshed = self.request("GET", f"/v1/strategies/{source_id}/retry-candidates")
        self.assertEqual(status, 200, refreshed)
        row = next(item for item in refreshed["candidates"] if item["sourceClientOrderId"] == source_order["clientOrderId"])
        self.assertFalse(row["eligible"])
        self.assertEqual(row["reason"], "selection_in_use")

        for strategy_id in (source_id, child["id"]):
            status, deletion = self.request("POST", f"/v1/strategies/{strategy_id}/delete", {})
            self.assertEqual(status, 409, deletion)
        contract = self.one_sided_contract()
        status, ordinary_preview = self.request("POST", "/v1/strategies/preview", contract)
        self.assertEqual(status, 200, ordinary_preview)
        status, replacement = self.request(
            "POST", "/v1/strategies",
            {**contract, "previewHash": ordinary_preview["previewHash"], "replacementSourceId": source_id},
        )
        self.assertEqual(status, 409, replacement)
        self.assertEqual(replacement["error"], "replacement_source_unavailable")

    def test_green_rejected_retry_child_can_supply_one_linked_grandchild(self) -> None:
        ancestor_id, ancestor_result, _ = self._make_rejected_source()
        ancestor_order = ancestor_result["orders"][0]
        status, ancestor_candidates = self.request("GET", f"/v1/strategies/{ancestor_id}/retry-candidates")
        self.assertEqual(status, 200, ancestor_candidates)
        ancestor_review = {
            "sourceRevision": ancestor_candidates["sourceRevision"],
            "sourceClientOrderIds": [ancestor_order["clientOrderId"]],
        }
        status, child_preview = self.request(
            "POST", f"/v1/strategies/{ancestor_id}/retry-preview", ancestor_review
        )
        self.assertEqual(status, 200, child_preview)
        status, child = self.request(
            "POST", f"/v1/strategies/{ancestor_id}/retry-drafts",
            {**ancestor_review, "previewHash": child_preview["previewHash"],
             "retryRequestId": "retry-grandchild-parent-001"},
        )
        self.assertEqual(status, 200, child)
        child_source_order = child["orders"][0]
        status, child_prepared = self.request("POST", f"/v1/strategies/{child['id']}/prepare-apply", {})
        self.assertEqual(status, 200, child_prepared)
        self.assertEqual(child_prepared["resubmission"]["sourceStrategyId"], ancestor_id)
        self.assertEqual(child_prepared["resubmission"]["sourceClientOrderIds"], ancestor_review["sourceClientOrderIds"])
        self.exchange.batch_ack = [{
            "clOrdId": child_source_order["clientOrderId"], "sCode": "51008",
        }]
        status, rejected_child = self.request(
            "POST", f"/v1/strategies/{child['id']}/execute-apply",
            {"confirmationToken": child_prepared["confirmationToken"]},
        )
        self.assertEqual(status, 200, rejected_child)
        self.assertEqual(rejected_child["status"], "PARTIAL")
        self.assertEqual(rejected_child["orders"][0]["status"], "rejected")
        self.exchange.batch_ack = None

        status, child_candidates = self.request("GET", f"/v1/strategies/{child['id']}/retry-candidates")
        self.assertEqual(status, 200, child_candidates)
        grandchild_review = {
            "sourceRevision": child_candidates["sourceRevision"],
            "sourceClientOrderIds": [child_source_order["clientOrderId"]],
        }
        candidate = child_candidates["candidates"][0]
        self.assertTrue(candidate["eligible"], candidate)
        self.assertEqual(candidate["sourceClientOrderId"], child_source_order["clientOrderId"])
        status, grandchild_preview = self.request(
            "POST", f"/v1/strategies/{child['id']}/retry-preview", grandchild_review
        )
        self.assertEqual(status, 200, grandchild_preview)
        status, grandchild = self.request(
            "POST", f"/v1/strategies/{child['id']}/retry-drafts",
            {**grandchild_review, "previewHash": grandchild_preview["previewHash"],
             "retryRequestId": "retry-grandchild-001"},
        )
        self.assertEqual(status, 200, grandchild)
        self.assertEqual(grandchild["resubmission"]["sourceStrategyId"], child["id"])
        self.assertEqual(grandchild["resubmission"]["sourceClientOrderIds"], [child_source_order["clientOrderId"]])
        grandchild_order = grandchild["orders"][0]
        self.assertEqual(grandchild_order["sourceClientOrderId"], child_source_order["clientOrderId"])
        self.assertNotEqual(grandchild_order["clientOrderId"], child_source_order["clientOrderId"])
        status, grandchild_prepared = self.request(
            "POST", f"/v1/strategies/{grandchild['id']}/prepare-apply", {}
        )
        self.assertEqual(status, 200, grandchild_prepared)
        self.assertEqual(grandchild_prepared["id"], grandchild["id"])
        self.assertEqual(grandchild_prepared["resubmission"]["sourceStrategyId"], child["id"])
        self.assertEqual(
            grandchild_prepared["resubmission"]["sourceClientOrderIds"],
            [child_source_order["clientOrderId"]],
        )
        writes_before_grandchild = len(self.exchange.trade_writes)
        status, applied = self.request(
            "POST", f"/v1/strategies/{grandchild['id']}/execute-apply",
            {"confirmationToken": grandchild_prepared["confirmationToken"]},
        )
        self.assertEqual(status, 200, applied)
        self.assertEqual(applied["status"], "APPLIED")
        self.assertEqual(applied["resubmission"]["sourceStrategyId"], child["id"])
        self.assertEqual(len(self.exchange.trade_writes), writes_before_grandchild + 2)
        status, duplicate = self.request(
            "POST", f"/v1/strategies/{grandchild['id']}/execute-apply",
            {"confirmationToken": grandchild_prepared["confirmationToken"]},
        )
        self.assertEqual(status, 200, duplicate)
        self.assertEqual(len(self.exchange.trade_writes), writes_before_grandchild + 2)

        grandchild_client_id = grandchild_order["clientOrderId"]
        self.exchange.orders[grandchild_client_id]["state"] = "canceled"
        self.exchange.orders[grandchild_client_id]["accFillSz"] = "0"
        self.exchange.orders[grandchild_client_id]["avgPx"] = "0"
        with self.service.store.transaction() as connection:
            connection.execute(
                "DELETE FROM strategy_sync_state WHERE strategy_id=?", (grandchild["id"],)
            )
        status, settled_grandchild = self.request(
            "GET", f"/v1/strategies/{grandchild['id']}/result"
        )
        self.assertEqual(status, 200, settled_grandchild)
        self.assertEqual(settled_grandchild["orders"][0]["status"], "canceled")
        with self.service.store.connection() as connection:
            self.assertIsNone(connection.execute(
                "SELECT 1 FROM strategy_reservations WHERE strategy_id=?", (grandchild["id"],)
            ).fetchone())

        status, ancestor_after_claim = self.request(
            "GET", f"/v1/strategies/{ancestor_id}/retry-candidates"
        )
        self.assertEqual(status, 200, ancestor_after_claim)
        ancestor_row = next(
            row for row in ancestor_after_claim["candidates"]
            if row["sourceClientOrderId"] == ancestor_order["clientOrderId"]
        )
        self.assertFalse(ancestor_row["eligible"])
        self.assertEqual(ancestor_row["reason"], "selection_in_use")

    def test_green_retry_mixed_long_short_subset_preserves_hedge_sides_and_payload(self) -> None:
        self.exchange.pos_mode = "long_short_mode"
        contract = self.id_mode_contract(
            [
                {"side": "long", "price": "59000", "levelId": "long-z"},
                {"side": "long", "price": "58000", "levelId": "long-a"},
                {"side": "short", "price": "61000", "levelId": "short-z"},
                {"side": "short", "price": "62000", "levelId": "short-a"},
            ],
            direction="both",
            entry_ids={"long": "long-z", "short": "short-z"},
        )
        contract["totalMargin"] = "1000"
        source_id, source_result, _ = self._make_rejected_source(
            contract=contract, rejected_order_indexes={0, 2}, accepted_as_canceled=True
        )
        status, candidates = self.request("GET", f"/v1/strategies/{source_id}/retry-candidates")
        self.assertEqual(status, 200, candidates)
        eligible = [row for row in candidates["candidates"] if row["eligible"]]
        self.assertEqual(len(eligible), 2)
        self.assertEqual({row["side"] for row in eligible}, {"long", "short"})
        ids = [row["sourceClientOrderId"] for row in eligible]
        source_by_id = {row["clientOrderId"]: row for row in source_result["orders"]}
        review = {"sourceRevision": candidates["sourceRevision"], "sourceClientOrderIds": ids}
        status, preview = self.request("POST", f"/v1/strategies/{source_id}/retry-preview", review)
        self.assertEqual(status, 200, preview)
        self.assertEqual({row["side"] for row in preview["orders"]}, {"long", "short"})
        self.assertEqual(
            {row["side"]: (row["limitPrice"], row["contracts"], row["role"]) for row in preview["orders"]},
            {source_by_id[row_id]["side"]: (
                source_by_id[row_id]["limitPrice"], source_by_id[row_id]["contracts"], source_by_id[row_id]["role"]
            ) for row_id in ids},
        )
        status, child = self.request(
            "POST", f"/v1/strategies/{source_id}/retry-drafts",
            {**review, "previewHash": preview["previewHash"], "retryRequestId": "retry-hedge-subset-001"},
        )
        self.assertEqual(status, 200, child)
        status, prepared = self.request("POST", f"/v1/strategies/{child['id']}/prepare-apply", {})
        self.assertEqual(status, 200, prepared)
        status, result = self.request(
            "POST", f"/v1/strategies/{child['id']}/execute-apply",
            {"confirmationToken": prepared["confirmationToken"]},
        )
        self.assertEqual(status, 200, result)
        self.assertEqual(result["status"], "APPLIED")
        submitted = {row["clOrdId"]: row for row in self.exchange.batch_writes[-1][2]}
        self.assertEqual({row["posSide"] for row in submitted.values()}, {"long", "short"})
        child_by_source = {row["sourceClientOrderId"]: row for row in child["orders"]}
        for source_id_value in ids:
            source_row = source_by_id[source_id_value]
            child_row = child_by_source[source_id_value]
            payload = submitted[child_row["clientOrderId"]]
            self.assertEqual(payload["px"], source_row["limitPrice"])
            self.assertEqual(payload["sz"], source_row["contracts"])
            self.assertEqual(payload["posSide"], source_row["side"])

    def test_green_retry_worker_resume_revalidates_fixed_hash_and_excludes_self_reservation(self) -> None:
        contract = self.multi_order_contract(2)
        source_id, source_result, _ = self._make_rejected_source(
            contract=contract, rejected_order_indexes={0, 1}
        )
        status, candidates = self.request("GET", f"/v1/strategies/{source_id}/retry-candidates")
        self.assertEqual(status, 200, candidates)
        eligible = [row for row in candidates["candidates"] if row["eligible"]]
        self.assertEqual(len(eligible), 2)
        ids = [row["sourceClientOrderId"] for row in eligible]
        review = {"sourceRevision": candidates["sourceRevision"], "sourceClientOrderIds": ids}
        status, preview = self.request("POST", f"/v1/strategies/{source_id}/retry-preview", review)
        self.assertEqual(status, 200, preview)
        status, child = self.request(
            "POST", f"/v1/strategies/{source_id}/retry-drafts",
            {**review, "previewHash": preview["previewHash"], "retryRequestId": "retry-resume-child-001"},
        )
        self.assertEqual(status, 200, child)
        status, setting = self.request(
            "POST", "/v1/strategies/settings", {"limitOrderSubmissionMode": "sequential"}
        )
        self.assertEqual(status, 200, setting)
        status, prepared = self.request("POST", f"/v1/strategies/{child['id']}/prepare-apply", {})
        self.assertEqual(status, 200, prepared)
        self.assertEqual(prepared["id"], child["id"])
        self.assertEqual(prepared["resubmission"]["sourceStrategyId"], source_id)
        self.assertEqual(prepared["resubmission"]["sourceClientOrderIds"], ids)
        status, queued = self.request(
            "POST", f"/v1/strategies/{child['id']}/execute-apply",
            {"confirmationToken": prepared["confirmationToken"]},
        )
        self.assertEqual(status, 200, queued)
        self.assertEqual(queued["queueStatus"], "pending")

        with self.service.store.transaction() as connection:
            persisted = connection.execute(
                "SELECT queue_json, results_json FROM strategies WHERE strategy_id=?", (child["id"],)
            ).fetchone()
            queue = json.loads(persisted["queue_json"])
            results = json.loads(persisted["results_json"])
            queue.update({"phase": "sending", "cursor": 1, "inFlight": None})
            results[0] = {
                **results[0], "status": "accepted", "placementState": "accepted",
                "exchangeOrderId": "accepted-before-restart",
            }
            connection.execute(
                "UPDATE strategies SET queue_json=?, results_json=?, order_placement_attempted=1, "
                "execution_lease_until=NULL, updated_at=? WHERE strategy_id=?",
                (encode_json(queue), encode_json(results), self.now, child["id"]),
            )
        self.exchange.positions = [{"instId": INSTRUMENT, "pos": "1", "posSide": "net"}]
        self.exchange.pending = [{"instId": INSTRUMENT, "clOrdId": "accepted-before-restart"}]
        self.exchange.position_reads = 0
        self.exchange.pending_reads = 0
        with self.service.store.connection() as connection:
            self.assertIsNotNone(connection.execute(
                "SELECT 1 FROM strategy_reservations WHERE strategy_id=?", (child["id"],)
            ).fetchone())

        self.assertTrue(self._worker().run_once())
        self.assertEqual(self.exchange.position_reads, 0)
        self.assertEqual(self.exchange.pending_reads, 0)
        status, result = self.request("GET", f"/v1/strategies/{child['id']}/result")
        self.assertEqual(status, 200, result)
        self.assertEqual(result["status"], "APPLIED")
        posted = [
            payload for method, path, payload in self.exchange.calls
            if method == "POST" and path.split("?", 1)[0] == "/api/v5/trade/order"
        ]
        self.assertEqual([row["clOrdId"] for row in posted], [prepared["orders"][1]["clientOrderId"]])
        self.assertEqual(posted[0]["px"], source_result["orders"][1]["limitPrice"])
        self.assertEqual(posted[0]["sz"], source_result["orders"][1]["contracts"])

    def test_green_stopped_sequential_leverage_rejection_allows_fixed_unsent_tail_retry(self) -> None:
        status, setting = self.request(
            "POST", "/v1/strategies/settings", {"limitOrderSubmissionMode": "sequential"}
        )
        self.assertEqual(status, 200, setting)
        source_contract = self.multi_order_contract(2)
        source_id, _ = self.save_draft(source_contract)
        status, source_prepared = self.request(
            "POST", f"/v1/strategies/{source_id}/prepare-apply", {}
        )
        self.assertEqual(status, 200, source_prepared)
        status, queued_source = self.request(
            "POST", f"/v1/strategies/{source_id}/execute-apply",
            {"confirmationToken": source_prepared["confirmationToken"]},
        )
        self.assertEqual(status, 200, queued_source)
        self.assertEqual(queued_source["queueStatus"], "pending")
        self.exchange.leverage_response = {"code": "51008", "data": [{}]}
        self.assertTrue(self._worker().run_once())
        self.exchange.leverage_response = None
        status, stopped = self.request("GET", f"/v1/strategies/{source_id}/result")
        self.assertEqual(status, 200, stopped)
        self.assertEqual(stopped["status"], "PARTIAL")
        self.assertEqual(stopped["queueStatus"], "stopped")
        self.assertEqual(stopped["leverageResults"][0]["status"], "rejected")
        self.assertEqual([row["status"] for row in stopped["orders"]], ["not_submitted", "not_submitted"])
        with self.service.store.connection() as connection:
            queue_row = connection.execute(
                "SELECT queue_json FROM strategies WHERE strategy_id=?", (source_id,)
            ).fetchone()
        stored_queue = json.loads(queue_row["queue_json"])
        self.assertEqual(stored_queue["phase"], "stopped")
        self.assertEqual(stored_queue["cursor"], 0)

        status, candidates = self.request("GET", f"/v1/strategies/{source_id}/retry-candidates")
        self.assertEqual(status, 200, candidates)
        tail = stopped["orders"][-1]
        row = next(item for item in candidates["candidates"] if item["sourceClientOrderId"] == tail["clientOrderId"])
        self.assertTrue(row["eligible"], row)
        self.assertEqual(row["priorOutcome"], "not_submitted")
        review = {
            "sourceRevision": candidates["sourceRevision"],
            "sourceClientOrderIds": [tail["clientOrderId"]],
        }
        status, preview = self.request("POST", f"/v1/strategies/{source_id}/retry-preview", review)
        self.assertEqual(status, 200, preview)
        self.assertEqual(preview["orders"][0]["role"], tail["role"])
        self.assertEqual(preview["orders"][0]["limitPrice"], tail["limitPrice"])
        self.assertEqual(preview["orders"][0]["contracts"], tail["contracts"])
        status, child = self.request(
            "POST", f"/v1/strategies/{source_id}/retry-drafts",
            {**review, "previewHash": preview["previewHash"], "retryRequestId": "retry-sequential-tail-001"},
        )
        self.assertEqual(status, 200, child)
        status, prepared = self.request("POST", f"/v1/strategies/{child['id']}/prepare-apply", {})
        self.assertEqual(status, 200, prepared)
        self.assertEqual(prepared["id"], child["id"])
        self.assertEqual(prepared["resubmission"]["sourceStrategyId"], source_id)
        self.assertEqual(prepared["resubmission"]["sourceClientOrderIds"], [tail["clientOrderId"]])
        status, child_queued = self.request(
            "POST", f"/v1/strategies/{child['id']}/execute-apply",
            {"confirmationToken": prepared["confirmationToken"]},
        )
        self.assertEqual(status, 200, child_queued)
        self.assertTrue(self._worker().run_once())
        status, applied = self.request("GET", f"/v1/strategies/{child['id']}/result")
        self.assertEqual(status, 200, applied)
        self.assertEqual(applied["status"], "APPLIED")
        placed = [
            payload for method, path, payload in self.exchange.calls
            if method == "POST" and path.split("?", 1)[0] == "/api/v5/trade/order"
        ]
        self.assertEqual(len(placed), 1)
        self.assertEqual(placed[0]["clOrdId"], prepared["orders"][0]["clientOrderId"])
        self.assertEqual(placed[0]["px"], tail["limitPrice"])
        self.assertEqual(placed[0]["sz"], tail["contracts"])

    def test_red_retry_prepare_rejects_changed_mode_and_freezes_current_mode(self) -> None:
        source_id, source_result, _ = self._make_rejected_source()
        source_order = source_result["orders"][0]
        status, candidates = self.request("GET", f"/v1/strategies/{source_id}/retry-candidates")
        self.assertEqual(status, 200, candidates)
        review = {
            "sourceRevision": candidates["sourceRevision"],
            "sourceClientOrderIds": [source_order["clientOrderId"]],
        }
        status, preview = self.request("POST", f"/v1/strategies/{source_id}/retry-preview", review)
        self.assertEqual(status, 200, preview)
        status, child = self.request(
            "POST", f"/v1/strategies/{source_id}/retry-drafts",
            {**review, "previewHash": preview["previewHash"], "retryRequestId": "retry-mode-review-001"},
        )
        self.assertEqual(status, 200, child)

        writes_before = len(self.exchange.trade_writes)
        self.exchange.pos_mode = "long_short_mode"
        status, stale = self.request("POST", f"/v1/strategies/{child['id']}/prepare-apply", {})
        self.assertEqual(status, 409, stale)
        self.assertEqual(stale["error"], "strategy_stale")
        self.assertEqual(len(self.exchange.trade_writes), writes_before)

        self.exchange.pos_mode = "net_mode"
        status, prepared = self.request("POST", f"/v1/strategies/{child['id']}/prepare-apply", {})
        self.assertEqual(status, 200, prepared)
        with self.service.store.connection() as connection:
            stored = connection.execute(
                "SELECT prepared_json FROM strategies WHERE strategy_id=?", (child["id"],)
            ).fetchone()
        self.assertEqual(json.loads(stored["prepared_json"])["_positionMode"], "net_mode")

    def test_red_retry_claim_consumes_source_and_protects_child_and_parent(self) -> None:
        source_id = self._make_legacy_never_sent_source()
        status, candidates = self.request("GET", f"/v1/strategies/{source_id}/retry-candidates")
        self.assertEqual(status, 200, candidates)
        self.assertTrue(candidates["candidates"][0]["eligible"])
        order_id = candidates["candidates"][0]["sourceClientOrderId"]
        preview_body = {
            "sourceRevision": candidates["sourceRevision"],
            "sourceClientOrderIds": [order_id],
        }
        status, preview = self.request("POST", f"/v1/strategies/{source_id}/retry-preview", preview_body)
        self.assertEqual(status, 200, preview)
        draft_body = {
            **preview_body, "previewHash": preview["previewHash"],
            "retryRequestId": "retry-request-consume-001",
        }
        status, child = self.request("POST", f"/v1/strategies/{source_id}/retry-drafts", draft_body)
        self.assertEqual(status, 200, child)

        status, deleted_child = self.request("POST", f"/v1/strategies/{child['id']}/delete", {})
        self.assertEqual(status, 200, deleted_child)
        status, candidates_after_delete = self.request(
            "GET", f"/v1/strategies/{source_id}/retry-candidates"
        )
        self.assertTrue(candidates_after_delete["candidates"][0]["eligible"])

        draft_body["retryRequestId"] = "retry-request-consume-002"
        status, child = self.request("POST", f"/v1/strategies/{source_id}/retry-drafts", draft_body)
        self.assertEqual(status, 200, child)
        status, setting = self.request("POST", "/v1/strategies/settings", {"limitOrderSubmissionMode": "sequential"})
        self.assertEqual(status, 200, setting)
        status, prepared = self.request("POST", f"/v1/strategies/{child['id']}/prepare-apply", {})
        self.assertEqual(status, 200, prepared)
        status, queued = self.request(
            "POST", f"/v1/strategies/{child['id']}/execute-apply",
            {"confirmationToken": prepared["confirmationToken"]},
        )
        self.assertEqual(status, 200, queued)
        self.assertTrue(queued["queueStatus"] in {"pending", "sending"})
        self.assertFalse(queued["orderPlacementAttempted"])

        status, deleted_child = self.request("POST", f"/v1/strategies/{child['id']}/delete", {})
        self.assertEqual(status, 409, deleted_child)
        self.assertEqual(deleted_child["error"], "strategy_immutable")
        status, deleted_source = self.request("POST", f"/v1/strategies/{source_id}/delete", {})
        self.assertEqual(status, 409, deleted_source)
        self.assertEqual(deleted_source["error"], "strategy_immutable")
        status, duplicate_preview = self.request(
            "POST", f"/v1/strategies/{source_id}/retry-preview", preview_body
        )
        self.assertEqual(status, 409, duplicate_preview)
        self.assertEqual(duplicate_preview["error"], "retry_source_unavailable")

        replacement_contract = self.one_sided_contract()
        status, ordinary_preview = self.request("POST", "/v1/strategies/preview", replacement_contract)
        self.assertEqual(status, 200, ordinary_preview)
        status, replacement = self.request(
            "POST", "/v1/strategies",
            {**replacement_contract, "previewHash": ordinary_preview["previewHash"],
             "replacementSourceId": source_id},
        )
        self.assertEqual(status, 409, replacement)
        self.assertEqual(replacement["error"], "replacement_source_unavailable")
        with self.service.store.connection() as connection:
            self.assertIsNotNone(connection.execute(
                "SELECT 1 FROM strategies WHERE strategy_id=?", (source_id,)
            ).fetchone())

    def test_green_retry_sequential_worker_revalidates_fixed_preview_with_self_reservation(self) -> None:
        source_id, source_result, _ = self._make_rejected_source()
        source_order = source_result["orders"][0]
        status, candidates = self.request("GET", f"/v1/strategies/{source_id}/retry-candidates")
        self.assertEqual(status, 200, candidates)
        review = {
            "sourceRevision": candidates["sourceRevision"],
            "sourceClientOrderIds": [source_order["clientOrderId"]],
        }
        status, preview = self.request("POST", f"/v1/strategies/{source_id}/retry-preview", review)
        self.assertEqual(status, 200, preview)
        status, child = self.request(
            "POST", f"/v1/strategies/{source_id}/retry-drafts",
            {**review, "previewHash": preview["previewHash"], "retryRequestId": "retry-worker-green-01"},
        )
        self.assertEqual(status, 200, child)
        status, setting = self.request(
            "POST", "/v1/strategies/settings", {"limitOrderSubmissionMode": "sequential"}
        )
        self.assertEqual(status, 200, setting)
        status, prepared = self.request("POST", f"/v1/strategies/{child['id']}/prepare-apply", {})
        self.assertEqual(status, 200, prepared)
        status, queued = self.request(
            "POST", f"/v1/strategies/{child['id']}/execute-apply",
            {"confirmationToken": prepared["confirmationToken"]},
        )
        self.assertEqual(status, 200, queued)
        self.assertEqual(queued["queueStatus"], "pending")
        writes_before_worker = len(self.exchange.trade_writes)

        self.assertTrue(self._worker().run_once())
        status, applied = self.request("GET", f"/v1/strategies/{child['id']}/result")
        self.assertEqual(status, 200, applied)
        self.assertEqual(applied["status"], "APPLIED")
        self.assertEqual(len(self.exchange.trade_writes), writes_before_worker + 2)
        placed = [
            payload for method, path, payload in self.exchange.calls
            if method == "POST" and path.split("?", 1)[0] == "/api/v5/trade/order"
        ]
        self.assertEqual(len(placed), 1)
        self.assertEqual(placed[0]["clOrdId"], prepared["orders"][0]["clientOrderId"])
        self.assertEqual(placed[0]["px"], source_order["limitPrice"])
        self.assertEqual(placed[0]["sz"], source_order["contracts"])

    def test_red_persisted_ordinary_replacement_blocks_retry_source(self) -> None:
        source_id = self._make_legacy_never_sent_source()
        replacement_id, _ = self.save_draft(replacement_source_id=source_id)
        with self.service.store.transaction() as connection:
            connection.execute(
                "UPDATE strategies SET status='COMPLETED', attempt_started=1, batch_attempted=0, "
                "order_placement_attempted=0 WHERE strategy_id=?",
                (source_id,),
            )
        status, candidates = self.request("GET", f"/v1/strategies/{source_id}/retry-candidates")
        self.assertEqual(status, 200, candidates)
        self.assertEqual(candidates["blockedReason"], "ordinary_replacement_exists")
        self.assertFalse(any(row["eligible"] for row in candidates["candidates"]))

        status, child_draft = self.request("GET", f"/v1/strategies/{replacement_id}/result")
        self.assertEqual(status, 200, child_draft)

    def test_red_concurrent_retry_and_ordinary_replacement_claim_only_one_source(self) -> None:
        source_id = self._make_legacy_never_sent_source()
        status, candidates = self.request("GET", f"/v1/strategies/{source_id}/retry-candidates")
        self.assertEqual(status, 200, candidates)
        source_order_id = candidates["candidates"][0]["sourceClientOrderId"]
        retry_selection = {
            "sourceRevision": candidates["sourceRevision"],
            "sourceClientOrderIds": [source_order_id],
        }
        status, retry_preview = self.request(
            "POST", f"/v1/strategies/{source_id}/retry-preview", retry_selection
        )
        self.assertEqual(status, 200, retry_preview)
        retry_body = {
            **retry_selection,
            "previewHash": retry_preview["previewHash"],
            "retryRequestId": "retry-race-request-001",
        }

        replacement_contract = self.one_sided_contract()
        status, replacement_preview = self.request("POST", "/v1/strategies/preview", replacement_contract)
        self.assertEqual(status, 200, replacement_preview)
        replacement_body = {
            **replacement_contract,
            "previewHash": replacement_preview["previewHash"],
            "replacementSourceId": source_id,
        }

        barrier = threading.Barrier(2)
        original_preview_contract = self.service.strategy._preview_contract
        original_retry_guards = self.service.strategy._retry_review_guards

        def wait_after_ordinary_preview(contract: dict[str, Any]) -> dict[str, Any]:
            value = original_preview_contract(contract)
            barrier.wait(timeout=5)
            return value

        def wait_after_retry_guards(context: dict[str, Any], preview: dict[str, Any]) -> None:
            original_retry_guards(context, preview)
            barrier.wait(timeout=5)

        with ThreadPoolExecutor(max_workers=2) as executor:
            with patch.object(
                self.service.strategy, "_preview_contract", side_effect=wait_after_ordinary_preview
            ), patch.object(
                self.service.strategy, "_retry_review_guards", side_effect=wait_after_retry_guards
            ):
                retry_future = executor.submit(
                    self.request, "POST", f"/v1/strategies/{source_id}/retry-drafts", retry_body
                )
                replacement_future = executor.submit(
                    self.request, "POST", "/v1/strategies", replacement_body
                )
                retry_result = retry_future.result(timeout=10)
                replacement_result = replacement_future.result(timeout=10)

        self.assertEqual(sorted((retry_result[0], replacement_result[0])), [200, 409])
        account_fingerprint = token_digest(
            "okx-account-uid:v1:" + self.exchange.account_uid, SIGNING_KEY
        )
        with self.service.store.connection() as connection:
            rows = connection.execute(
                "SELECT contract_json, replacement_source_id FROM strategies WHERE account_fingerprint=?",
                (account_fingerprint,),
            ).fetchall()
        dependents = []
        for row in rows:
            contract = json.loads(row["contract_json"])
            if (
                row["replacement_source_id"] == source_id
                or contract.get("resubmission", {}).get("sourceStrategyId") == source_id
            ):
                dependents.append(row)
        self.assertEqual(len(dependents), 1)

    def test_red_both_retry_claim_transactions_recheck_source_before_consumption(self) -> None:
        for mode in ("batch", "sequential"):
            with self.subTest(mode=mode):
                source_id, source_result, _ = self._make_rejected_source()
                source_order = source_result["orders"][0]
                status, candidates = self.request(
                    "GET", f"/v1/strategies/{source_id}/retry-candidates"
                )
                self.assertEqual(status, 200, candidates)
                review = {
                    "sourceRevision": candidates["sourceRevision"],
                    "sourceClientOrderIds": [source_order["clientOrderId"]],
                }
                status, preview = self.request(
                    "POST", f"/v1/strategies/{source_id}/retry-preview", review
                )
                self.assertEqual(status, 200, preview)
                status, child = self.request(
                    "POST", f"/v1/strategies/{source_id}/retry-drafts",
                    {**review, "previewHash": preview["previewHash"],
                     "retryRequestId": f"retry-claim-{mode}-request"},
                )
                self.assertEqual(status, 200, child)
                status, setting = self.request(
                    "POST", "/v1/strategies/settings", {"limitOrderSubmissionMode": mode}
                )
                self.assertEqual(status, 200, setting)
                status, prepared = self.request(
                    "POST", f"/v1/strategies/{child['id']}/prepare-apply", {}
                )
                self.assertEqual(status, 200, prepared)
                writes_before_claim = len(self.exchange.trade_writes)
                method_name = "_claim_queue" if mode == "sequential" else "_claim_execution"
                original_claim = getattr(self.service.strategy, method_name)

                def mutate_source_then_claim(*args: Any, **kwargs: Any) -> Any:
                    with self.service.store.transaction() as connection:
                        row = connection.execute(
                            "SELECT results_json FROM strategies WHERE strategy_id=?", (source_id,)
                        ).fetchone()
                        results = json.loads(row["results_json"])
                        results[0]["status"] = "unknown"
                        results[0].pop("errorCode", None)
                        connection.execute(
                            "UPDATE strategies SET status='UNKNOWN', results_json=? WHERE strategy_id=?",
                            (encode_json(results), source_id),
                        )
                    return original_claim(*args, **kwargs)

                with patch.object(
                    self.service.strategy, method_name, side_effect=mutate_source_then_claim
                ):
                    status, refusal = self.request(
                        "POST", f"/v1/strategies/{child['id']}/execute-apply",
                        {"confirmationToken": prepared["confirmationToken"]},
                    )
                self.assertEqual(status, 409, refusal)
                self.assertEqual(refusal["error"], "retry_source_stale")
                self.assertEqual(len(self.exchange.trade_writes), writes_before_claim)
                with self.service.store.connection() as connection:
                    current_child = connection.execute(
                        "SELECT status, attempt_started FROM strategies WHERE strategy_id=?",
                        (child["id"],),
                    ).fetchone()
                self.assertEqual(current_child["status"], "PREPARED")
                self.assertEqual(current_child["attempt_started"], 0)


if __name__ == "__main__":
    unittest.main()
