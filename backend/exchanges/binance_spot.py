"""Read-only Binance Spot adapter and native-unit normalization."""

from __future__ import annotations

from datetime import datetime, timezone
from decimal import Decimal
import re
from typing import Any

from .binance_transport import BinanceTransport
from .contracts import (
    AdapterError,
    BalanceDTO,
    InstrumentMetadataDTO,
    OrderDTO,
    Product,
    TickerDTO,
    decimal_value,
    decimal_add,
    decimal_divide,
    decimal_multiply,
    is_multiple,
    metadata_version,
    required_decimal,
    utc_timestamp,
)


_SYMBOL = re.compile(r"[A-Z0-9]{3,32}\Z")


def _rows(value: Any, name: str) -> list[dict[str, Any]]:
    if not isinstance(value, list) or any(not isinstance(row, dict) for row in value):
        raise AdapterError(502, "exchange_data_unavailable", f"Exchange {name} data is unavailable.")
    return value


def _text(value: Any, *, maximum: int = 128) -> str | None:
    if not isinstance(value, (str, int)) or isinstance(value, bool):
        return None
    result = str(value)
    return result if result and len(result) <= maximum else None


def _symbol(value: Any) -> str:
    if not isinstance(value, str) or not _SYMBOL.fullmatch(value):
        raise AdapterError(400, "invalid_instrument", "The exchange instrument is invalid.")
    return value


def _timestamp(value: Any) -> str | None:
    if isinstance(value, bool) or not isinstance(value, int) or value < 0:
        return None
    try:
        return datetime.fromtimestamp(value / 1000, timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")
    except (OverflowError, OSError, ValueError):
        return None


def parse_instrument(
    row: dict[str, Any], *, product: str, environment: str, region: str
) -> InstrumentMetadataDTO:
    symbol = row.get("symbol")
    base = row.get("baseAsset")
    quote = row.get("quoteAsset")
    filters = row.get("filters")
    status = row.get("status")
    if (
        not isinstance(symbol, str) or not _SYMBOL.fullmatch(symbol)
        or not isinstance(base, str) or not re.fullmatch(r"[A-Z0-9]{1,20}", base)
        or not isinstance(quote, str) or not re.fullmatch(r"[A-Z0-9]{1,20}", quote)
        or not isinstance(filters, list) or not isinstance(status, str)
    ):
        raise AdapterError(502, "metadata_unavailable", "Exchange instrument metadata is unavailable.")
    by_type = {item.get("filterType"): item for item in filters if isinstance(item, dict)}
    price_filter = by_type.get("PRICE_FILTER")
    lot_filter = by_type.get("LOT_SIZE")
    if not isinstance(price_filter, dict) or not isinstance(lot_filter, dict):
        raise AdapterError(502, "metadata_unavailable", "Exchange instrument metadata is unavailable.")
    tick = required_decimal(price_filter.get("tickSize"), positive=True)
    lot = required_decimal(lot_filter.get("stepSize"), positive=True)
    minimum = required_decimal(lot_filter.get("minQty"), positive=True)
    notional_filter = by_type.get("MIN_NOTIONAL") or by_type.get("NOTIONAL")
    notional_value = None
    if isinstance(notional_filter, dict):
        notional_value = (
            notional_filter.get("notional") if product == Product.USD_M.value
            else notional_filter.get("minNotional")
        )
    notional = None if notional_value is None else required_decimal(notional_value, positive=True)
    contract_type = row.get("contractType")
    settlement_asset = row.get("marginAsset") or row.get("settleAsset")
    version_source = {
        "symbol": symbol,
        "status": status,
        "baseAsset": base,
        "quoteAsset": quote,
        "filters": sorted(
            [item for item in filters if isinstance(item, dict)],
            key=lambda item: str(item.get("filterType", "")),
        ),
        "contractType": contract_type,
        "settlementAsset": settlement_asset,
    }
    return InstrumentMetadataDTO(
        exchange="BINANCE",
        product=product,
        environment=environment,
        region=region,
        instrument=symbol,
        base_asset=base,
        quote_asset=quote,
        tick_size=tick,
        lot_size=lot,
        min_quantity=minimum,
        min_notional=notional,
        contract_value=None,
        contract_value_unit=None,
        contract_type=_text(contract_type, maximum=32),
        settlement_asset=_text(settlement_asset, maximum=20),
        metadata_version=metadata_version(version_source),
        status=status,
    )


def validate_quantity(
    quantity: Any,
    metadata: InstrumentMetadataDTO,
    *,
    price: Any = None,
) -> Decimal:
    value = required_decimal(quantity, positive=True)
    if value < metadata.min_quantity or not is_multiple(value, metadata.lot_size):
        raise AdapterError(422, "quantity_unsupported", "The exchange quantity does not meet instrument filters.")
    if metadata.min_notional is not None:
        parsed_price = decimal_value(price)
        if parsed_price is None or parsed_price <= 0 or decimal_multiply(value, parsed_price) < metadata.min_notional:
            raise AdapterError(422, "notional_unsupported", "The exchange quantity does not meet instrument filters.")
    return value


class BinanceSpotAdapter:
    exchange = "BINANCE"
    product = Product.SPOT.value

    def __init__(self, client: BinanceTransport, *, environment: str, region: str):
        self.client = client
        self.environment = environment
        self.region = region

    def account(self) -> dict[str, Any]:
        value = self.client.get("SPOT", "/api/v3/account", signed=True)
        if not isinstance(value, dict):
            raise AdapterError(502, "identity_unavailable", "Exchange account identity is unavailable.")
        return value

    def restrictions(self) -> dict[str, Any]:
        value = self.client.get("SPOT", "/sapi/v1/account/apiRestrictions", signed=True)
        if not isinstance(value, dict):
            raise AdapterError(502, "permission_unavailable", "Exchange permission metadata is unavailable.")
        return value

    def balances(self) -> list[BalanceDTO]:
        payload = self.account()
        rows = _rows(payload.get("balances"), "balance")
        result = []
        for row in rows:
            asset = row.get("asset")
            available = decimal_value(row.get("free"))
            locked = decimal_value(row.get("locked"))
            if not isinstance(asset, str) or not re.fullmatch(r"[A-Z0-9]{1,20}", asset) or available is None or locked is None:
                raise AdapterError(502, "exchange_data_unavailable", "Exchange balance data is unavailable.")
            result.append(BalanceDTO(
                self.exchange, self.product, self.environment, self.region,
                asset, available, locked, decimal_add(available, locked), asset,
            ))
        return result

    def positions(self, instrument: str | None = None) -> list[Any]:
        raise AdapterError(422, "capability_unsupported", "Spot positions are not supported.")

    def orders(self, instrument: str | None = None) -> list[OrderDTO]:
        params = {} if instrument is None else {"symbol": self._symbol(instrument)}
        rows = _rows(self.client.get("SPOT", "/api/v3/openOrders", params, signed=True), "order")
        result = []
        for row in rows:
            symbol = self._symbol(row.get("symbol"))
            order_id = _text(row.get("orderId"))
            quantity = decimal_value(row.get("origQty"))
            filled = decimal_value(row.get("executedQty"))
            if symbol is None or order_id is None or quantity is None or quantity < 0 or filled is None or filled < 0:
                raise AdapterError(502, "exchange_data_unavailable", "Exchange order data is unavailable.")
            cumulative_quote = decimal_value(row.get("cummulativeQuoteQty"))
            average_price = (
                decimal_divide(cumulative_quote, filled)
                if filled > 0 and cumulative_quote is not None and cumulative_quote >= 0
                else None
            )
            result.append(OrderDTO(
                self.exchange, self.product, self.environment, self.region,
                order_id, _text(row.get("clientOrderId")), symbol,
                _text(row.get("side"), maximum=16), _text(row.get("type"), maximum=32),
                (_text(row.get("status"), maximum=32) or "unknown").lower(), quantity, "base",
                filled, average_price, _timestamp(row.get("time")), None,
                None, "base",
            ))
        return result

    def instruments(self, instrument: str | None = None) -> list[InstrumentMetadataDTO]:
        params = {} if instrument is None else {"symbol": self._symbol(instrument)}
        payload = self.client.get("SPOT", "/api/v3/exchangeInfo", params)
        if not isinstance(payload, dict):
            raise AdapterError(502, "metadata_unavailable", "Exchange instrument metadata is unavailable.")
        rows = _rows(payload.get("symbols"), "instrument")
        result = [parse_instrument(row, product=self.product, environment=self.environment, region=self.region) for row in rows]
        if instrument is not None and not result:
            raise AdapterError(404, "instrument_unavailable", "The exchange instrument is unavailable.")
        return result

    def ticker(self, instrument: str) -> TickerDTO:
        symbol = self._symbol(instrument)
        payload = self.client.get("SPOT", "/api/v3/ticker/price", {"symbol": symbol})
        if isinstance(payload, list):
            if len(payload) != 1 or not isinstance(payload[0], dict):
                raise AdapterError(502, "ticker_unavailable", "Exchange quote data is unavailable.")
            payload = payload[0]
        price = decimal_value(payload.get("price")) if isinstance(payload, dict) else None
        if price is None or price <= 0 or payload.get("symbol") != symbol:
            raise AdapterError(502, "ticker_unavailable", "Exchange quote data is unavailable.")
        return TickerDTO(self.exchange, self.product, self.environment, self.region, symbol, price, time_now())

    @staticmethod
    def _symbol(value: Any) -> str:
        return _symbol(value)


def time_now() -> str:
    import time

    return utc_timestamp(time.time)
