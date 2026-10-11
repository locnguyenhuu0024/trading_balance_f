"""Read-only Binance standard USD-M adapter."""

from __future__ import annotations

from decimal import Decimal
import re
from typing import Any

from .binance_spot import _rows, _symbol as _spot_symbol, _text, _timestamp, parse_instrument
from .binance_transport import BinanceTransport
from .contracts import AdapterError, BalanceDTO, InstrumentMetadataDTO, OrderDTO, PositionDTO, Product, TickerDTO, decimal_value, decimal_subtract


class BinanceUSDMAdapter:
    exchange = "BINANCE"
    product = Product.USD_M.value

    def __init__(self, client: BinanceTransport, *, environment: str, region: str):
        self.client = client
        self.environment = environment
        self.region = region

    def account(self) -> dict[str, Any]:
        value = self.client.get("USD_M", "/fapi/v2/account", signed=True)
        if not isinstance(value, dict):
            raise AdapterError(502, "account_mode_unavailable", "The USD-M account configuration is unavailable.")
        assets = value.get("assets")
        positions = value.get("positions")
        multi_assets = value.get("multiAssetsMargin")
        portfolio_margin = value.get("portfolioMargin")
        if (
            not isinstance(assets, list) or any(not isinstance(row, dict) for row in assets)
            or not isinstance(positions, list) or any(not isinstance(row, dict) for row in positions)
            or not isinstance(multi_assets, bool)
            or (portfolio_margin is not None and (not isinstance(portfolio_margin, bool) or portfolio_margin))
            or isinstance(value.get("canTrade"), bool) is False
        ):
            raise AdapterError(502, "account_mode_unavailable", "The USD-M account configuration is unavailable.")
        return value

    def balances(self) -> list[BalanceDTO]:
        rows = _rows(self.client.get("USD_M", "/fapi/v2/balance", signed=True), "balance")
        result = []
        for row in rows:
            asset = row.get("asset")
            available = decimal_value(row.get("availableBalance"))
            wallet = decimal_value(row.get("balance"))
            if not isinstance(asset, str) or not re.fullmatch(r"[A-Z0-9]{1,20}", asset) or available is None or wallet is None:
                raise AdapterError(502, "exchange_data_unavailable", "Exchange balance data is unavailable.")
            result.append(BalanceDTO(
                self.exchange, self.product, self.environment, self.region,
                asset, available, None, wallet, asset,
            ))
        return result

    def positions(self, instrument: str | None = None) -> list[PositionDTO]:
        symbol = None if instrument is None else self._symbol(instrument)
        params = {} if symbol is None else {"symbol": symbol}
        rows = _rows(self.client.get("USD_M", "/fapi/v2/positionRisk", params, signed=True), "position")
        meta = {item.instrument: item for item in self.instruments(symbol)}
        result = []
        for row in rows:
            current_symbol = self._symbol(row.get("symbol"))
            quantity = decimal_value(row.get("positionAmt"))
            if quantity is None:
                raise AdapterError(502, "exchange_data_unavailable", "Exchange position data is unavailable.")
            if quantity == 0:
                continue
            metadata = meta.get(current_symbol)
            if metadata is None:
                raise AdapterError(502, "metadata_unavailable", "Exchange instrument metadata is unavailable.")
            entry = decimal_value(row.get("entryPrice"))
            mark = decimal_value(row.get("markPrice"))
            pnl = decimal_value(row.get("unRealizedProfit"))
            position_side = _text(row.get("positionSide"), maximum=16)
            if position_side not in {"BOTH", "LONG", "SHORT"}:
                raise AdapterError(502, "exchange_data_unavailable", "Exchange position data is unavailable.")
            side = position_side.lower() if position_side != "BOTH" else ("long" if quantity > 0 else "short")
            mode = "hedge" if position_side in {"LONG", "SHORT"} else "one_way"
            result.append(PositionDTO(
                self.exchange, self.product, self.environment, self.region,
                current_symbol, quantity, "base", quantity,
                None, None, metadata.contract_type, metadata.settlement_asset,
                entry, mark, pnl, side, mode, metadata.metadata_version, metadata.base_asset,
            ))
        return result

    def orders(self, instrument: str | None = None) -> list[OrderDTO]:
        symbol = None if instrument is None else self._symbol(instrument)
        params = {} if symbol is None else {"symbol": symbol}
        rows = _rows(self.client.get("USD_M", "/fapi/v1/openOrders", params, signed=True), "order")
        metadata = {item.instrument: item for item in self.instruments(symbol)}
        result = []
        for row in rows:
            current_symbol = self._symbol(row.get("symbol"))
            order_id = _text(row.get("orderId"))
            quantity = decimal_value(row.get("origQty"))
            filled = decimal_value(row.get("executedQty"))
            if current_symbol is None or order_id is None or quantity is None or quantity < 0 or filled is None or filled < 0:
                raise AdapterError(502, "exchange_data_unavailable", "Exchange order data is unavailable.")
            item_metadata = metadata.get(current_symbol)
            if item_metadata is None:
                raise AdapterError(502, "metadata_unavailable", "Exchange instrument metadata is unavailable.")
            result.append(OrderDTO(
                self.exchange, self.product, self.environment, self.region,
                order_id, _text(row.get("clientOrderId")), current_symbol,
                _text(row.get("side"), maximum=16), _text(row.get("type"), maximum=32),
                (_text(row.get("status"), maximum=32) or "unknown").lower(), quantity,
                "base", filled, decimal_value(row.get("avgPrice")),
                _timestamp(row.get("time")), item_metadata.metadata_version,
                item_metadata.base_asset, "base",
            ))
        return result

    def instruments(self, instrument: str | None = None) -> list[InstrumentMetadataDTO]:
        symbol = None if instrument is None else self._symbol(instrument)
        payload = self.client.get("USD_M", "/fapi/v1/exchangeInfo")
        if not isinstance(payload, dict):
            raise AdapterError(502, "metadata_unavailable", "Exchange instrument metadata is unavailable.")
        rows = _rows(payload.get("symbols"), "instrument")
        result = [
            parse_instrument(row, product=self.product, environment=self.environment, region=self.region)
            for row in rows if symbol is None or row.get("symbol") == symbol
        ]
        if symbol is not None and not result:
            raise AdapterError(404, "instrument_unavailable", "The exchange instrument is unavailable.")
        return result

    def ticker(self, instrument: str) -> TickerDTO:
        symbol = self._symbol(instrument)
        payload = self.client.get("USD_M", "/fapi/v1/ticker/price", {"symbol": symbol})
        if isinstance(payload, list):
            if len(payload) != 1 or not isinstance(payload[0], dict):
                raise AdapterError(502, "ticker_unavailable", "Exchange quote data is unavailable.")
            payload = payload[0]
        price = decimal_value(payload.get("price")) if isinstance(payload, dict) else None
        if price is None or price <= 0 or payload.get("symbol") != symbol:
            raise AdapterError(502, "ticker_unavailable", "Exchange quote data is unavailable.")
        from .binance_spot import time_now

        return TickerDTO(self.exchange, self.product, self.environment, self.region, symbol, price, time_now())

    @staticmethod
    def _symbol(value: Any) -> str:
        return _spot_symbol(value)
