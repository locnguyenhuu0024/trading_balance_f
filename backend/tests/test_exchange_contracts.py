from __future__ import annotations

import unittest
from decimal import Decimal, getcontext

from backend.exchanges.contracts import (
    PositionDTO,
    decimal_add,
    decimal_multiply,
    decimal_subtract,
    decimal_text,
    decimal_value,
    is_multiple,
)
from backend.exchanges.okx_adapter import OKXReadAdapter


class _FabricatedOKX:
    def __init__(self):
        self.calls: list[tuple[str, dict[str, str] | None, bool]] = []
        self.positions: list[dict] = []
        self.orders: list[dict] = []
        self.details = [{"ccy": "BTC", "availBal": "0.03", "frozenBal": "0", "cashBal": "0.03"},
                        {"ccy": "USDT", "availBal": "100", "frozenBal": "5", "cashBal": "105"}]
        self.contract_value_currency = "BTC"
        self.contract_type = "linear"
        self.derivative_instrument = "BTC-USDT-SWAP"

    def request(self, method, path, *, params=None, private=None, **_kwargs):
        self.calls.append((path, None if params is None else dict(params), bool(private)))
        if path == "/api/v5/account/balance":
            return {"code": "0", "data": [{"details": self.details}]}
        if path == "/api/v5/account/positions":
            return {"code": "0", "data": self.positions}
        if path == "/api/v5/public/instruments":
            product = (params or {}).get("instType", "SPOT")
            instrument = (params or {}).get(
                "instId", self.derivative_instrument if product in {"SWAP", "FUTURES"} else "BTC-USDT"
            )
            row = {"instId": instrument, "tickSz": "0.01", "lotSz": "0.003", "minSz": "0.003", "state": "live"}
            if product in {"SWAP", "FUTURES"}:
                row.update({
                    "ctVal": "0.01", "ctValCcy": self.contract_value_currency,
                    "ctType": self.contract_type, "settleCcy": "USDT",
                })
            return {"code": "0", "data": [row]}
        if path == "/api/v5/trade/orders-pending":
            return {"code": "0", "data": self.orders}
        raise AssertionError(f"unexpected fabricated OKX read {method} {path}")


class ExchangeContractTests(unittest.TestCase):
    def test_decimal_arithmetic_preserves_precision_beyond_default_context(self) -> None:
        previous = getcontext().prec
        getcontext().prec = 28
        try:
            left = decimal_value("123456789012345678901234567890.12345678901234567890")
            right = decimal_value("0.00000000000000000011")
            self.assertIsNotNone(left)
            self.assertIsNotNone(right)
            self.assertEqual(
                decimal_text(decimal_add(left, right)),
                "123456789012345678901234567890.12345678901234567901",
            )
            self.assertEqual(
                decimal_text(decimal_subtract(left, right)),
                "123456789012345678901234567890.12345678901234567879",
            )
            self.assertEqual(
                decimal_text(decimal_multiply(decimal_value("0.003"), decimal_value("0.01"))),
                "0.00003",
            )
        finally:
            getcontext().prec = previous

    def test_malformed_and_unbounded_decimal_values_fail_closed(self) -> None:
        for value in (float("nan"), float("inf"), True, "1e257", "9" * 129, Decimal("1e1000000")):
            with self.subTest(value=str(value)):
                self.assertIsNone(decimal_value(value))
        with self.assertRaises(ValueError):
            decimal_text(Decimal("1e1000000"))

    def test_position_wire_contract_uses_native_units_and_camel_case_only(self) -> None:
        position = PositionDTO(
            "BINANCE", "USD_M", "live", "global", "BTCUSDT", Decimal("-0.03"),
            "base", Decimal("-0.03"), None, None, "PERPETUAL", "USDT", None, None,
            Decimal("0"), "short", "one_way", "meta-v1", "BTC",
        ).to_dict()
        self.assertEqual(position["nativeQuantity"], "-0.03")
        self.assertEqual(position["quantityUnit"], "base")
        self.assertEqual(position["baseQuantity"], "-0.03")
        self.assertEqual(position["nativeAsset"], "BTC")
        self.assertIn("contractType", position)
        self.assertIn("settlementAsset", position)
        self.assertIn("metadataVersion", position)
        self.assertNotIn("native_quantity", position)

    def test_okx_balances_and_current_positions_preserve_full_native_observations(self) -> None:
        client = _FabricatedOKX()
        adapter = OKXReadAdapter(client, environment="demo", region="global")
        balances = adapter.balances("SPOT")
        self.assertEqual([row.asset for row in balances], ["BTC", "USDT"])
        balance_call = next(call for call in client.calls if call[0] == "/api/v5/account/balance")
        self.assertIsNone(balance_call[1])

        client.calls.clear()
        client.positions = [
            {"instId": "BTC-USDT-SWAP", "pos": "3", "posSide": "net", "posCcy": "BTC", "markPx": "100"}
            for _ in range(101)
        ]
        positions = adapter.positions("SWAP", position_mode="net_mode")
        self.assertEqual(len(positions), 101)
        self.assertEqual(positions[0].native_quantity, Decimal("3"))
        self.assertEqual(positions[0].base_quantity, Decimal("0.03"))
        self.assertEqual(positions[0].native_unit, "contracts")
        self.assertEqual(positions[0].contract_value, Decimal("0.01"))
        position_calls = [call for call in client.calls if call[0] == "/api/v5/account/positions"]
        self.assertEqual(position_calls, [("/api/v5/account/positions", {"instType": "SWAP"}, True)])
        metadata_call = next(call for call in client.calls if call[0] == "/api/v5/public/instruments")
        self.assertEqual(metadata_call[1], {"instType": "SWAP"})
        metadata = adapter.instruments("SWAP")[0]
        self.assertEqual(metadata.lot_size, Decimal("0.003"))
        self.assertTrue(is_multiple(Decimal("0.006"), metadata.lot_size))
        self.assertFalse(is_multiple(Decimal("0.004"), metadata.lot_size))

        long_native = "123456789012345678901234567890.12345678901234567890"
        client.positions = [{
            "instId": "BTC-USDT-SWAP", "pos": long_native, "posSide": "short", "posCcy": "BTC", "markPx": "100",
        }]
        short = adapter.positions("SWAP")[0]
        self.assertEqual(
            decimal_text(short.base_quantity),
            "-1234567890123456789012345678.9012345678901234567890",
        )

    def test_okx_inverse_and_market_order_units_remain_explicit_or_unavailable(self) -> None:
        client = _FabricatedOKX()
        adapter = OKXReadAdapter(client, environment="demo", region="global")
        client.positions = [{
            "instId": "BTC-USD-SWAP", "pos": "3", "posSide": "net", "posCcy": "BTC", "markPx": "100",
        }]
        client.contract_type = "inverse"
        client.contract_value_currency = "USD"
        client.derivative_instrument = "BTC-USD-SWAP"
        inverse = adapter.positions("SWAP")[0]
        self.assertEqual(inverse.native_quantity, Decimal("3"))
        self.assertEqual(inverse.base_quantity, Decimal("0.0003"))
        client.contract_value_currency = "BTC"
        unknown_inverse = adapter.positions("SWAP")[0]
        self.assertIsNone(unknown_inverse.base_quantity)

        client.orders = [{
            "instId": "BTC-USDT", "ordId": "1", "clOrdId": "client-1", "sz": "100",
            "accFillSz": "0.03", "side": "buy", "ordType": "market", "tgtCcy": "quote_ccy",
            "state": "live",
        }]
        order = adapter.orders("SPOT")[0].to_dict()
        self.assertEqual(order["nativeQuantity"], "100")
        self.assertIsNone(order["quantityUnit"])
        self.assertEqual(order["nativeAsset"], "USDT")
        self.assertEqual(order["filledQuantity"], "0.03")
        self.assertEqual(order["filledQuantityUnit"], "base")

        client.orders = [{
            "instId": "BTC-USDT", "ordId": "2", "clOrdId": "client-2", "sz": "100",
            "accFillSz": "0.03", "side": "buy", "ordType": "market", "tgtCcy": "unknown",
            "state": "live",
        }]
        unknown = adapter.orders("SPOT")[0].to_dict()
        self.assertIsNone(unknown["quantityUnit"])
        self.assertIsNone(unknown["nativeAsset"])

    def test_okx_margin_market_buy_uses_quote_but_sell_and_limit_use_base(self) -> None:
        client = _FabricatedOKX()
        client.orders = [
            {"instId": "BTC-USDT", "ordId": "buy", "sz": "100", "accFillSz": "0.03", "side": "buy", "ordType": "market", "state": "live"},
            {"instId": "BTC-USDT", "ordId": "sell", "sz": "0.03", "accFillSz": "0.01", "side": "sell", "ordType": "market", "state": "live"},
            {"instId": "BTC-USDT", "ordId": "limit", "sz": "0.03", "accFillSz": "0.01", "side": "buy", "ordType": "limit", "state": "live"},
        ]
        rows = OKXReadAdapter(client, environment="demo", region="global").orders("MARGIN")
        self.assertEqual([(row.native_unit, row.native_asset) for row in rows], [
            (None, "USDT"), ("base", "BTC"), ("base", "BTC"),
        ])
        self.assertEqual([row.filled_quantity_unit for row in rows], ["base", "base", "base"])


if __name__ == "__main__":
    unittest.main()
