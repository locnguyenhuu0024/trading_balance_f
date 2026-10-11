from __future__ import annotations

import hashlib
import hmac
import unittest
from urllib.parse import parse_qs, urlencode, urlsplit

from backend.account_context import (
    AccountContextError,
    BinanceClientBundle,
    create_exchange_client,
    create_okx_client,
    verify_exchange_identity,
)
from backend.exchanges import AdapterError, BinanceSpotAdapter, BinanceTransport, BinanceUSDMAdapter
from backend.exchanges.contracts import decimal_add, decimal_value
from backend.exchanges.binance_spot import parse_instrument, validate_quantity


def instrument(symbol: str, *, product: str) -> dict:
    row = {
        "symbol": symbol,
        "status": "TRADING",
        "baseAsset": "BTC" if symbol.startswith("BTC") else "ETH",
        "quoteAsset": "USDT",
        "filters": [
            {"filterType": "PRICE_FILTER", "tickSize": "0.01"},
            {"filterType": "LOT_SIZE", "stepSize": "0.001", "minQty": "0.001"},
        ],
    }
    row["filters"].append(
        {"filterType": "MIN_NOTIONAL", "notional" if product == "USD_M" else "minNotional": "5"}
    )
    if product == "USD_M":
        row.update({"contractType": "PERPETUAL", "marginAsset": "USDT"})
    return row


class BinanceReadAdapterTests(unittest.TestCase):
    def setUp(self) -> None:
        self.requests: list[tuple[str, str, dict[str, str]]] = []
        self.now = 1_700_000_000.0
        self.position_quantity = "-0.03"
        self.spot_orders = [{
            "symbol": "BTCUSDT", "orderId": 11, "clientOrderId": "spot-client",
            "origQty": "0.03", "executedQty": "0.01", "side": "BUY", "type": "LIMIT",
            "status": "NEW", "price": "100", "time": 1700000000000,
        }]

        def transport(method: str, path: str, headers: dict[str, str], _body: bytes | None):
            self.requests.append((method, path, dict(headers)))
            if path == "/api/v3/time" or path == "/fapi/v1/time":
                return {"serverTime": int(self.now * 1000)}
            if path.startswith("/api/v3/account?") or path == "/api/v3/account":
                return {
                    "uid": 123456,
                    "balances": [{"asset": "BTC", "free": "0.03", "locked": "0.01"}],
                }
            if path.startswith("/sapi/v1/account/apiRestrictions?") or path == "/sapi/v1/account/apiRestrictions":
                return {"enableReading": True, "enableWithdrawals": False, "enableFutures": False}
            if path == "/fapi/v2/account?recvWindow=5000&timestamp=1700000000000&signature=" + "x":
                return {}
            if path.startswith("/fapi/v2/account?") or path == "/fapi/v2/account":
                return {
                    "canTrade": False, "multiAssetsMargin": True,
                    "assets": [], "positions": [],
                }
            if path == "/fapi/v2/balance?recvWindow=5000&timestamp=1700000000000&signature=" + "x":
                return []
            if path.startswith("/fapi/v2/balance?") or path == "/fapi/v2/balance":
                return [{"asset": "BTC", "balance": "100", "availableBalance": "110"}]
            if path.startswith("/fapi/v2/positionRisk?") or path == "/fapi/v2/positionRisk":
                return [{
                    "symbol": "BTCUSDT", "positionAmt": self.position_quantity, "positionSide": "BOTH",
                    "entryPrice": "60000", "markPrice": "61000", "unRealizedProfit": "-30",
                }]
            if path.startswith("/api/v3/openOrders?") or path == "/api/v3/openOrders":
                return self.spot_orders
            if path.startswith("/fapi/v1/openOrders?") or path == "/fapi/v1/openOrders":
                return [{
                    "symbol": "BTCUSDT", "orderId": 12, "clientOrderId": "future-client",
                    "origQty": "0.03", "executedQty": "0.01", "side": "BUY", "type": "LIMIT",
                    "status": "NEW", "avgPrice": "100", "time": 1700000000000,
                }]
            if path == "/fapi/v1/exchangeInfo":
                return {"symbols": [instrument("BTCUSDT", product="USD_M"), instrument("ETHUSDT", product="USD_M")]}
            if path == "/api/v3/exchangeInfo":
                return {"symbols": [instrument("BTCUSDT", product="SPOT"), instrument("ETHUSDT", product="SPOT")]}
            return []

        self.transport = BinanceTransport(
            "fabricated-key", "fabricated-secret", environment="live", region="global",
            transport=transport, clock=lambda: self.now, monotonic_clock=lambda: 100.0,
        )
        self.spot = BinanceSpotAdapter(self.transport, environment="live", region="global")
        self.usdm = BinanceUSDMAdapter(self.transport, environment="live", region="global")

    def test_spot_read_is_signed_and_preserves_native_balance(self) -> None:
        rows = self.spot.balances()
        self.assertEqual(rows[0].to_dict()["available"], "0.03")
        self.assertEqual(rows[0].to_dict()["locked"], "0.01")
        signed = next(row for row in self.requests if row[1].startswith("/api/v3/account?"))
        self.assertEqual(signed[0], "GET")
        self.assertEqual(signed[2]["X-MBX-APIKEY"], "fabricated-key")
        query = parse_qs(urlsplit(signed[1]).query)
        signature = query.pop("signature")[0]
        canonical = urlencode(sorted((key, value[0]) for key, value in query.items()))
        expected = hmac.new(b"fabricated-secret", canonical.encode("ascii"), hashlib.sha256).hexdigest()
        self.assertEqual(signature, expected)
        self.assertEqual(query["recvWindow"], ["5000"])
        self.assertEqual(query["timestamp"], ["1700000000000"])

    def test_usdm_keeps_signed_native_quantity_and_does_not_infer_locked(self) -> None:
        balance = self.usdm.balances()[0].to_dict()
        self.assertEqual(balance["available"], "110")
        self.assertIsNone(balance["locked"])
        self.assertEqual(balance["total"], "100")
        position = self.usdm.positions()[0].to_dict()
        self.assertEqual(position["nativeQuantity"], "-0.03")
        self.assertEqual(position["quantityUnit"], "base")
        self.assertEqual(position["baseQuantity"], "-0.03")
        self.assertEqual(position["nativeAsset"], "BTC")

    def test_okx_contract_and_binance_base_positions_share_independent_point_three_oracle(self) -> None:
        from backend.tests.test_exchange_contracts import _FabricatedOKX
        from backend.exchanges.okx_adapter import OKXReadAdapter

        client = _FabricatedOKX()
        client.positions = [{
            "instId": "BTC-USDT-SWAP", "pos": "3", "posSide": "net", "posCcy": "BTC", "markPx": "100",
        }]
        okx = OKXReadAdapter(client, environment="demo", region="global").positions("SWAP")[0]
        self.position_quantity = "0.03"
        binance = self.usdm.positions()[0]
        self.assertEqual(str(okx.base_quantity), "0.03")
        self.assertEqual(binance.to_dict()["baseQuantity"], "0.03")

    def test_binance_order_fill_unit_and_native_step_notional_filters_are_explicit(self) -> None:
        spot_order = self.spot.orders()[0].to_dict()
        usdm_order = self.usdm.orders()[0].to_dict()
        self.assertEqual(spot_order["filledQuantityUnit"], "base")
        self.assertEqual(usdm_order["filledQuantityUnit"], "base")

        native = instrument("BTCUSDT", product="SPOT")
        next(item for item in native["filters"] if item["filterType"] == "LOT_SIZE")["stepSize"] = "0.003"
        metadata = parse_instrument(native, product="SPOT", environment="live", region="global")
        self.assertEqual(str(metadata.lot_size), "0.003")
        self.assertEqual(validate_quantity("0.006", metadata, price="1000"), decimal_value("0.006"))
        with self.assertRaises(AdapterError) as step:
            validate_quantity("0.004", metadata, price="1000")
        self.assertEqual(step.exception.code, "quantity_unsupported")
        with self.assertRaises(AdapterError) as notional:
            validate_quantity("0.003", metadata, price="1000")
        self.assertEqual(notional.exception.code, "notional_unsupported")

    def test_exact_large_quantity_step_and_notional_boundaries_do_not_round(self) -> None:
        native = instrument("BTCUSDT", product="SPOT")
        next(item for item in native["filters"] if item["filterType"] == "LOT_SIZE").update({
            "stepSize": "0.003", "minQty": "0.003",
        })
        large_quantity = "300000000000000000000000000000000000000000000000000.006"
        exact_notional = "900000000000000000000000000000000000000000000000000.018"
        next(item for item in native["filters"] if item["filterType"] == "MIN_NOTIONAL")["minNotional"] = exact_notional
        metadata = parse_instrument(native, product="SPOT", environment="live", region="global")
        self.assertEqual(validate_quantity(large_quantity, metadata, price="3"), decimal_value(large_quantity))
        from dataclasses import replace
        above_boundary = replace(metadata, min_notional=decimal_add(decimal_value(exact_notional), decimal_value("0.001")))
        with self.assertRaises(AdapterError) as rejected:
            validate_quantity(large_quantity, above_boundary, price="3")
        self.assertEqual(rejected.exception.code, "notional_unsupported")

    def test_spot_order_average_uses_filled_quote_amount_not_requested_limit_price(self) -> None:
        self.assertIsNone(self.spot.orders()[0].to_dict()["averagePrice"])
        self.spot_orders = [{
            "symbol": "BTCUSDT", "orderId": 13, "clientOrderId": "partial-client",
            "origQty": "3", "executedQty": "2", "cummulativeQuoteQty": "0.3",
            "side": "BUY", "type": "LIMIT", "status": "PARTIALLY_FILLED",
            "price": "0.2", "time": 1700000000000,
        }]
        self.assertEqual(self.spot.orders()[0].to_dict()["averagePrice"], "0.15")

    def test_usdm_exchange_info_is_fetched_without_symbol_then_filtered_locally(self) -> None:
        rows = self.usdm.instruments("BTCUSDT")
        self.assertEqual([row.instrument for row in rows], ["BTCUSDT"])
        call = next(row for row in self.requests if row[1] == "/fapi/v1/exchangeInfo")
        self.assertEqual(call[0], "GET")
        self.assertEqual(rows[0].min_notional, 5)
        with self.assertRaises(AdapterError) as missing:
            self.usdm.instruments("DOGEUSDT")
        self.assertEqual((missing.exception.status, missing.exception.code), (404, "instrument_unavailable"))

    def test_read_only_allowlist_and_spot_position_capability_fail_closed(self) -> None:
        count = len(self.requests)
        with self.assertRaises(AdapterError) as denied:
            self.transport.get("SPOT", "/api/v3/order", {"symbol": "BTCUSDT"}, signed=True)
        self.assertEqual(denied.exception.status, 422)
        with self.assertRaises(AdapterError) as positions:
            self.spot.positions()
        self.assertEqual(positions.exception.code, "capability_unsupported")
        self.assertEqual(len(self.requests), count)

    def test_exchange_specific_credential_factory_and_demo_verification_gate(self) -> None:
        with self.assertRaises(AccountContextError):
            create_exchange_client(
                {"apiKey": "key", "apiSecret": "secret", "passphrase": "invented"},
                exchange="BINANCE", environment="live", region="global",
            )
        with self.assertRaises(AccountContextError):
            create_okx_client(
                {"apiKey": "key", "apiSecret": "secret", "passphrase": "pass"},
                exchange="BINANCE", environment="live", region="global",
            )
        demo = create_exchange_client(
            {"apiKey": "key", "apiSecret": "secret"},
            exchange="BINANCE", environment="demo", region="global",
            transport=lambda *_args: self.fail("demo private verification must not call upstream"),
        )
        with self.assertRaises(AccountContextError) as unavailable:
            verify_exchange_identity(demo)
        self.assertEqual((unavailable.exception.status, unavailable.exception.code), (503, "verification_unavailable"))

    def test_identity_requires_actual_boolean_permissions_and_accepts_multi_asset_mode(self) -> None:
        class Spot:
            def account(self):
                return {"uid": 123456}

            def restrictions(self):
                return {"enableReading": True, "enableWithdrawals": False, "enableFutures": True}

        class USDM:
            def account(self):
                return {"canTrade": False, "multiAssetsMargin": True, "assets": [], "positions": []}

        bundle = BinanceClientBundle(None, Spot(), USDM(), "live", "global")
        identity = verify_exchange_identity(bundle)
        self.assertIn("read:USD_M", identity.capabilities)

        class MalformedRestrictions(Spot):
            def restrictions(self):
                return {"enableReading": True, "enableWithdrawals": False, "enableFutures": 0}

        with self.assertRaises(AccountContextError):
            verify_exchange_identity(BinanceClientBundle(None, MalformedRestrictions(), USDM(), "live", "global"))


if __name__ == "__main__":
    unittest.main()
