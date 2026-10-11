from __future__ import annotations

import unittest
from decimal import Decimal
from urllib.parse import parse_qs, urlsplit

from backend.exchanges import AdapterError, BinanceTransport, BinanceUSDMAdapter
from backend.exchanges.binance_transport import BinanceTransportError
from backend.exchanges.contracts import BinanceQuantityFilter, BinanceUSDMOrderFilters


class BinanceCommandBaselineTests(unittest.TestCase):
    def test_operation_error_keeps_unrecognized_native_http_errors_ambiguous(self) -> None:
        for status in (400, 429, 500):
            with self.subTest(status=status):
                error = BinanceTransport._operation_error(
                    {"code": -98765, "msg": "FABRICATED"}, http_status=status,
                )
                self.assertFalse(error.definite_failure)
                self.assertEqual(error.native_code, -98765)
                if status == 429:
                    self.assertEqual((error.status, error.code), (429, "rate_limited"))

        for native_code in (-1008, -2022, -4118):
            with self.subTest(native_code=native_code):
                error = BinanceTransport._operation_error(
                    {"code": native_code, "msg": "FABRICATED"}, http_status=400,
                )
                self.assertTrue(error.definite_failure)
                self.assertEqual(error.native_code, native_code)

        known_503 = BinanceTransport._operation_error(
            {"code": -12345, "msg": "Service Unavailable."}, http_status=503,
        )
        self.assertTrue(known_503.definite_failure)

    def test_injected_transport_can_send_a_reduce_only_market_order(self) -> None:
        calls: list[tuple[str, str, dict[str, str]]] = []
        now = 1_700_000_000.0

        def fake_transport(method: str, path: str, headers: dict[str, str], _body: bytes | None):
            calls.append((method, path, dict(headers)))
            if path == "/fapi/v1/time":
                return {"serverTime": int(now * 1000)}
            if method == "POST" and urlsplit(path).path == "/fapi/v1/order":
                return {"symbol": "BTCUSDT", "orderId": 7, "clientOrderId": "btf_fixture_00"}
            raise AssertionError("unexpected fixture request")

        transport = BinanceTransport(
            "fabricated-key", "fabricated-secret", environment="demo", region="global",
            transport=fake_transport, clock=lambda: now, monotonic_clock=lambda: 100.0,
        )
        response = transport.post("USD_M", "/fapi/v1/order", {
            "symbol": "BTCUSDT", "side": "SELL", "type": "MARKET", "quantity": "0.01",
            "positionSide": "BOTH", "reduceOnly": "true", "newClientOrderId": "btf_fixture_00",
        }, signed=True)

        self.assertEqual(response["clientOrderId"], "btf_fixture_00")
        method, path, headers = calls[-1]
        query = parse_qs(urlsplit(path).query)
        self.assertEqual(method, "POST")
        self.assertEqual(urlsplit(path).path, "/fapi/v1/order")
        self.assertEqual(query["quantity"], ["0.01"])
        self.assertEqual(query["reduceOnly"], ["true"])
        self.assertEqual(headers["X-MBX-APIKEY"], "fabricated-key")

    def test_native_write_is_denied_without_an_injected_transport(self) -> None:
        transport = BinanceTransport(
            "fabricated-key", "fabricated-secret", environment="demo", region="global",
            clock=lambda: 1_700_000_000.0,
        )
        with self.assertRaises(AdapterError) as denied:
            transport.post("USD_M", "/fapi/v1/order", {
                "symbol": "BTCUSDT", "side": "SELL", "type": "MARKET", "quantity": "1",
                "positionSide": "BOTH", "reduceOnly": "true", "newClientOrderId": "btf_fixture_00",
            }, signed=True)
        self.assertEqual(denied.exception.code, "capability_unsupported")

    def test_market_quantity_filter_uses_exact_subtraction_at_high_significance(self) -> None:
        filters = BinanceUSDMOrderFilters(
            symbol="BTCUSDT",
            lot_size=BinanceQuantityFilter(Decimal("1"), Decimal("100000000000000000000000000000"), Decimal("2")),
            market_lot_size=BinanceQuantityFilter(Decimal("1"), Decimal("100000000000000000000000000000"), Decimal("2")),
            metadata_version="fabricated-version",
        )
        accepted = filters.validate_market_quantity("10000000000000000000000000001")
        self.assertEqual(accepted, Decimal("10000000000000000000000000001"))
        with self.assertRaises(AdapterError):
            filters.validate_market_quantity("10000000000000000000000000002")

    def test_read_adapter_still_accepts_read_only_futures_account_metadata(self) -> None:
        class FakeClient:
            def get(self, _product: str, path: str, *_args, **_kwargs):
                if path == "/fapi/v2/account":
                    return {
                        "assets": [], "positions": [], "canTrade": False,
                        "multiAssetsMargin": False,
                    }
                raise AssertionError("unexpected fixture request")

        adapter = BinanceUSDMAdapter(FakeClient(), environment="demo", region="global")
        account = adapter.account()
        self.assertIs(account["canTrade"], False)

    def test_malformed_market_quantity_filter_is_rejected(self) -> None:
        class FakeClient:
            def get(self, _product: str, path: str, *_args, **_kwargs):
                if path == "/fapi/v1/exchangeInfo":
                    return {"symbols": [{
                        "symbol": "BTCUSDT", "status": "TRADING", "filters": [
                            {"filterType": "LOT_SIZE", "minQty": "0.001", "maxQty": "100", "stepSize": "0.001"},
                            {"filterType": "MARKET_LOT_SIZE", "minQty": "0.001", "maxQty": "100", "stepSize": "1e999"},
                        ],
                    }]}
                raise AssertionError("unexpected fixture request")

        adapter = BinanceUSDMAdapter(FakeClient(), environment="demo", region="global")
        with self.assertRaises(AdapterError) as malformed:
            adapter.order_filters("BTCUSDT")
        self.assertEqual(malformed.exception.code, "metadata_unavailable")

    def test_untyped_filter_enum_is_safely_rejected(self) -> None:
        class FakeClient:
            def get(self, _product: str, path: str, *_args, **_kwargs):
                if path == "/fapi/v1/exchangeInfo":
                    return {"symbols": [{
                        "symbol": "BTCUSDT", "status": "TRADING", "filters": [
                            {"filterType": ["LOT_SIZE"], "minQty": "0.001", "maxQty": "100", "stepSize": "0.001"},
                            {"filterType": "LOT_SIZE", "minQty": "0.001", "maxQty": "100", "stepSize": "0.001"},
                            {"filterType": "MARKET_LOT_SIZE", "minQty": "0.001", "maxQty": "100", "stepSize": "0.001"},
                        ],
                    }]}
                raise AssertionError("unexpected fixture request")

        adapter = BinanceUSDMAdapter(FakeClient(), environment="demo", region="global")
        with self.assertRaises(AdapterError) as malformed:
            adapter.order_filters("BTCUSDT")
        self.assertEqual(malformed.exception.code, "metadata_unavailable")

    def test_post_and_delete_unknown_native_codes_remain_ambiguous(self) -> None:
        now = 1_700_000_000.0
        native_code = -1000

        def fake_transport(method: str, path: str, _headers: dict[str, str], _body: bytes | None):
            if urlsplit(path).path == "/fapi/v1/time":
                return {"serverTime": int(now * 1000)}
            if method in {"POST", "DELETE"} and urlsplit(path).path == "/fapi/v1/order":
                return {"code": native_code, "msg": ["FIXTURE_PRIVATE_MESSAGE"]}
            raise AssertionError("unexpected fixture request")

        transport = BinanceTransport(
            "fabricated-key", "fabricated-secret", environment="demo", region="global",
            transport=fake_transport, clock=lambda: now, monotonic_clock=lambda: 100.0,
        )
        for method in ("POST", "DELETE"):
            with self.subTest(method=method):
                native_code = -1000
                with self.assertRaises(BinanceTransportError) as unknown:
                    if method == "POST":
                        transport.post("USD_M", "/fapi/v1/order", {
                            "symbol": "BTCUSDT", "side": "SELL", "type": "MARKET", "quantity": "1",
                            "positionSide": "BOTH", "reduceOnly": "true", "newClientOrderId": "fixture-001",
                        }, signed=True)
                    else:
                        transport.delete("USD_M", "/fapi/v1/order", {"symbol": "BTCUSDT", "orderId": "8801"}, signed=True)
                self.assertFalse(unknown.exception.definite_failure)
                self.assertEqual(unknown.exception.native_code, -1000)
                self.assertNotIn("FIXTURE_PRIVATE_MESSAGE", str(unknown.exception))

                native_code = -98765
                with self.assertRaises(BinanceTransportError) as unrecognized:
                    if method == "POST":
                        transport.post("USD_M", "/fapi/v1/order", {
                            "symbol": "BTCUSDT", "side": "SELL", "type": "MARKET", "quantity": "1",
                            "positionSide": "BOTH", "reduceOnly": "true", "newClientOrderId": "fixture-002",
                        }, signed=True)
                    else:
                        transport.delete("USD_M", "/fapi/v1/order", {"symbol": "BTCUSDT", "orderId": "8802"}, signed=True)
                self.assertFalse(unrecognized.exception.definite_failure)
                self.assertEqual(unrecognized.exception.native_code, -98765)

                native_code = -2022
                with self.assertRaises(BinanceTransportError) as rejected:
                    if method == "POST":
                        transport.post("USD_M", "/fapi/v1/order", {
                            "symbol": "BTCUSDT", "side": "SELL", "type": "MARKET", "quantity": "1",
                            "positionSide": "BOTH", "reduceOnly": "true", "newClientOrderId": "fixture-003",
                        }, signed=True)
                    else:
                        transport.delete("USD_M", "/fapi/v1/order", {"symbol": "BTCUSDT", "orderId": "8803"}, signed=True)
                self.assertTrue(rejected.exception.definite_failure)
                self.assertEqual(rejected.exception.native_code, -2022)


if __name__ == "__main__":
    unittest.main()
