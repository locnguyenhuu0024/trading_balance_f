"""Read-only Binance standard USD-M adapter."""

from __future__ import annotations

from decimal import Decimal
import re
from typing import Any

from .binance_spot import _rows, _symbol as _spot_symbol, _text, _timestamp, parse_instrument
from .binance_transport import BinanceTransport, BinanceTransportError
from .contracts import (
    AdapterError,
    BalanceDTO,
    BinanceQuantityFilter,
    BinanceUSDMOrderFilters,
    InstrumentMetadataDTO,
    OrderDTO,
    PositionDTO,
    Product,
    TickerDTO,
    decimal_value,
    decimal_subtract,
    metadata_version,
)


class BinanceUSDMAdapter:
    exchange = "BINANCE"
    product = Product.USD_M.value
    _ORDER_ID_RE = re.compile(r"[1-9][0-9]{0,19}\Z")
    _CLIENT_ORDER_ID_RE = re.compile(r"[A-Za-z0-9._:-]{1,36}\Z")

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

    def position_mode(self) -> bool:
        """Return the authoritative dual-side mode flag from Binance."""
        value = self.client.get("USD_M", "/fapi/v1/positionSide/dual", signed=True)
        if not isinstance(value, dict) or not isinstance(value.get("dualSidePosition"), bool):
            raise AdapterError(502, "account_mode_unavailable", "The USD-M account mode is unavailable.")
        return value["dualSidePosition"]

    def position_rows(self, instrument: str | None = None) -> list[dict[str, Any]]:
        symbol = None if instrument is None else self._symbol(instrument)
        params = {} if symbol is None else {"symbol": symbol}
        return _rows(self.client.get("USD_M", "/fapi/v2/positionRisk", params, signed=True), "position")

    def order_filters(self, instrument: str) -> BinanceUSDMOrderFilters:
        symbol = self._symbol(instrument)
        payload = self.client.get("USD_M", "/fapi/v1/exchangeInfo")
        if not isinstance(payload, dict):
            raise AdapterError(502, "metadata_unavailable", "Exchange instrument metadata is unavailable.")
        rows = _rows(payload.get("symbols"), "instrument")
        matches = [row for row in rows if row.get("symbol") == symbol]
        if len(matches) != 1:
            raise AdapterError(404, "instrument_unavailable", "The exchange instrument is unavailable.")
        row = matches[0]
        if row.get("status") != "TRADING":
            raise AdapterError(422, "instrument_unsupported", "The exchange instrument is not available for this action.")
        filters = row.get("filters")
        if not isinstance(filters, list) or any(not isinstance(item, dict) for item in filters):
            raise AdapterError(502, "metadata_unavailable", "Exchange instrument metadata is unavailable.")
        by_type: dict[str, list[dict[str, Any]]] = {"LOT_SIZE": [], "MARKET_LOT_SIZE": []}
        for item in filters:
            kind = item.get("filterType")
            if not isinstance(kind, str):
                raise AdapterError(502, "metadata_unavailable", "Exchange instrument metadata is unavailable.")
            if kind in by_type:
                by_type[kind].append(item)
        if any(len(items) != 1 for items in by_type.values()):
            raise AdapterError(502, "metadata_unavailable", "Exchange instrument metadata is unavailable.")

        def parse_filter(raw: dict[str, Any]) -> BinanceQuantityFilter:
            minimum = decimal_value(raw.get("minQty"))
            maximum = decimal_value(raw.get("maxQty"))
            step = decimal_value(raw.get("stepSize"))
            if (
                minimum is None or maximum is None or step is None
                or minimum < 0 or maximum <= 0 or step < 0 or minimum > maximum
            ):
                raise AdapterError(502, "metadata_unavailable", "Exchange instrument metadata is unavailable.")
            return BinanceQuantityFilter(minimum, maximum, step)

        lot_raw = by_type["LOT_SIZE"][0]
        market_raw = by_type["MARKET_LOT_SIZE"][0]
        binding = {
            "symbol": symbol,
            "filters": {
                "LOT_SIZE": {key: lot_raw.get(key) for key in ("minQty", "maxQty", "stepSize")},
                "MARKET_LOT_SIZE": {key: market_raw.get(key) for key in ("minQty", "maxQty", "stepSize")},
            },
        }
        return BinanceUSDMOrderFilters(
            symbol=symbol,
            lot_size=parse_filter(lot_raw),
            market_lot_size=parse_filter(market_raw),
            metadata_version=metadata_version(binding),
        )

    def order_by_id(
        self, instrument: str, *, order_id: str | None = None, client_order_id: str | None = None
    ) -> dict[str, Any] | None:
        symbol = self._symbol(instrument)
        if (order_id is None) == (client_order_id is None):
            raise AdapterError(400, "invalid_query", "The exchange order identity is invalid.")
        params = {"symbol": symbol}
        if order_id is not None:
            if (
                isinstance(order_id, bool) or not isinstance(order_id, (str, int))
                or self._ORDER_ID_RE.fullmatch(str(order_id)) is None
            ):
                raise AdapterError(400, "invalid_query", "The exchange order identity is invalid.")
            params["orderId"] = str(order_id)
        else:
            if not isinstance(client_order_id, str) or self._CLIENT_ORDER_ID_RE.fullmatch(client_order_id) is None:
                raise AdapterError(400, "invalid_query", "The exchange order identity is invalid.")
            params["origClientOrderId"] = client_order_id
        try:
            value = self.client.get("USD_M", "/fapi/v1/order", params, signed=True)
        except BinanceTransportError as error:
            if error.native_code == -2013:
                return None
            raise
        if not isinstance(value, dict):
            raise AdapterError(502, "order_unavailable", "The exchange order could not be verified.")
        return value

    def place_market_reduce(self, request: dict[str, str]) -> dict[str, Any]:
        required = {"symbol", "side", "type", "quantity", "positionSide", "reduceOnly", "newClientOrderId"}
        if (
            not isinstance(request, dict) or set(request) != required
            or request.get("type") != "MARKET" or request.get("positionSide") != "BOTH"
            or request.get("reduceOnly") != "true"
            or not isinstance(request.get("side"), str) or request.get("side") not in {"BUY", "SELL"}
            or not isinstance(request.get("quantity"), str)
            or decimal_value(request.get("quantity")) is None or decimal_value(request.get("quantity")) <= 0
            or not isinstance(request.get("newClientOrderId"), str)
            or self._CLIENT_ORDER_ID_RE.fullmatch(request.get("newClientOrderId")) is None
        ):
            raise AdapterError(422, "capability_unsupported", "The requested USD-M order is unsupported.")
        self._symbol(request.get("symbol"))
        value = self.client.post("USD_M", "/fapi/v1/order", request, signed=True)
        if not isinstance(value, dict):
            raise AdapterError(502, "order_ack_unavailable", "The exchange order could not be confirmed.")
        return value

    def cancel_regular_order(self, request: dict[str, str]) -> dict[str, Any]:
        if (
            not isinstance(request, dict) or set(request) != {"symbol", "orderId"}
            or isinstance(request.get("orderId"), bool)
            or not isinstance(request.get("orderId"), (str, int))
            or self._ORDER_ID_RE.fullmatch(str(request.get("orderId"))) is None
        ):
            raise AdapterError(422, "capability_unsupported", "The requested USD-M order is unsupported.")
        normalized = {"symbol": self._symbol(request.get("symbol")), "orderId": str(request.get("orderId"))}
        value = self.client.delete("USD_M", "/fapi/v1/order", normalized, signed=True)
        if not isinstance(value, dict):
            raise AdapterError(502, "order_ack_unavailable", "The exchange order could not be confirmed.")
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
