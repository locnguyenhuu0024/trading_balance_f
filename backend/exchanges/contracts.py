"""Typed, decimal-safe exchange read contracts shared by adapters."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
from decimal import Decimal, InvalidOperation, localcontext
from enum import Enum
import hashlib
import json
from typing import Any


_MAX_DECIMAL_DIGITS = 256
_MAX_DECIMAL_EXPONENT = 256
_MAX_DECIMAL_WIRE_LENGTH = 512


class Exchange(str, Enum):
    OKX = "OKX"
    BINANCE = "BINANCE"


class Product(str, Enum):
    SPOT = "SPOT"
    MARGIN = "MARGIN"
    SWAP = "SWAP"
    FUTURES = "FUTURES"
    USD_M = "USD_M"


EXCHANGE_PRODUCTS = {
    Exchange.OKX.value: frozenset({Product.SPOT.value, Product.MARGIN.value, Product.SWAP.value, Product.FUTURES.value}),
    Exchange.BINANCE.value: frozenset({Product.SPOT.value, Product.USD_M.value}),
}


class AdapterError(RuntimeError):
    """Sanitized adapter error with a stable HTTP mapping."""

    def __init__(self, status: int, code: str, message: str, *, retry_after: str | None = None):
        super().__init__(message)
        self.status = status
        self.code = code
        self.message = message
        self.retry_after = retry_after


def decimal_value(value: Any) -> Decimal | None:
    if value is None or isinstance(value, (bool, float)):
        return None
    if isinstance(value, Decimal):
        result = value
    elif isinstance(value, (str, int)):
        token = str(value)
        if len(token) > 128:
            return None
        try:
            result = Decimal(token)
        except (InvalidOperation, ValueError):
            return None
    else:
        return None
    if not result.is_finite():
        return None
    parts = result.as_tuple()
    if len(parts.digits) > _MAX_DECIMAL_DIGITS or abs(parts.exponent) > _MAX_DECIMAL_EXPONENT:
        return None
    if result != 0 and abs(result.adjusted()) > _MAX_DECIMAL_WIRE_LENGTH - 1:
        return None
    return result


def utc_timestamp(clock: Any) -> str:
    return datetime.fromtimestamp(float(clock()), tz=timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def decimal_text(value: Decimal | None) -> str | None:
    if value is None:
        return None
    if value == 0:
        return "0"
    if decimal_value(value) is None:
        raise ValueError("decimal value is outside the supported representation")
    text = format(value, "f")
    if len(text) > _MAX_DECIMAL_WIRE_LENGTH:
        raise ValueError("decimal value is outside the supported representation")
    return text


def decimal_add(left: Decimal, right: Decimal) -> Decimal:
    with localcontext() as context:
        context.prec = 512
        return left + right


def decimal_subtract(left: Decimal, right: Decimal) -> Decimal:
    with localcontext() as context:
        context.prec = 512
        return left - right


def decimal_multiply(left: Decimal, right: Decimal) -> Decimal:
    with localcontext() as context:
        context.prec = 512
        return left * right


def decimal_divide(left: Decimal, right: Decimal) -> Decimal:
    with localcontext() as context:
        context.prec = 128
        return left / right


def required_decimal(value: Any, *, positive: bool = False) -> Decimal:
    parsed = decimal_value(value)
    if parsed is None or (positive and parsed <= 0):
        raise AdapterError(502, "metadata_unavailable", "Exchange metadata is unavailable.")
    return parsed


def is_multiple(value: Decimal, step: Decimal) -> bool:
    if step <= 0:
        return False
    try:
        with localcontext() as context:
            # Inputs are bounded to 256 significant digits and exponents in
            # [-256, 256], so this preserves the exact aligned quotient/remainder.
            context.prec = 1024
            return value % step == 0
    except (InvalidOperation, ValueError):
        return False


@dataclass(frozen=True, slots=True)
class BalanceDTO:
    exchange: str
    product: str
    environment: str
    region: str
    asset: str
    available: Decimal | None
    locked: Decimal | None
    total: Decimal | None
    unit: str

    def to_dict(self) -> dict[str, Any]:
        return {
            "exchange": self.exchange, "product": self.product, "environment": self.environment,
            "region": self.region, "asset": self.asset, "available": decimal_text(self.available),
            "locked": decimal_text(self.locked), "total": decimal_text(self.total), "unit": self.unit,
        }


@dataclass(frozen=True, slots=True)
class PositionDTO:
    exchange: str
    product: str
    environment: str
    region: str
    instrument: str
    native_quantity: Decimal
    native_unit: str | None
    base_quantity: Decimal | None
    contract_value: Decimal | None
    contract_value_unit: str | None
    contract_type: str | None
    settlement_asset: str | None
    entry_price: Decimal | None
    mark_price: Decimal | None
    unrealized_pnl: Decimal | None
    side: str | None
    position_mode: str | None
    metadata_version: str | None
    native_asset: str | None = None
    margin_mode: str | None = None
    margin_currency: str | None = None
    position_id: str | None = None

    def to_dict(self) -> dict[str, Any]:
        return {
            "exchange": self.exchange, "product": self.product, "environment": self.environment,
            "region": self.region, "instrument": self.instrument,
            "nativeQuantity": decimal_text(self.native_quantity), "quantityUnit": self.native_unit,
            "nativeAsset": self.native_asset,
            "baseQuantity": decimal_text(self.base_quantity), "contractValue": decimal_text(self.contract_value),
            "contractValueUnit": self.contract_value_unit, "contractType": self.contract_type,
            "settlementAsset": self.settlement_asset, "entryPrice": decimal_text(self.entry_price),
            "markPrice": decimal_text(self.mark_price), "unrealizedPnl": decimal_text(self.unrealized_pnl),
            "side": self.side, "positionMode": self.position_mode, "metadataVersion": self.metadata_version,
            "marginMode": self.margin_mode, "marginCurrency": self.margin_currency,
            "positionId": self.position_id,
        }


@dataclass(frozen=True, slots=True)
class OrderDTO:
    exchange: str
    product: str
    environment: str
    region: str
    order_id: str
    client_order_id: str | None
    instrument: str
    side: str | None
    order_type: str | None
    status: str
    native_quantity: Decimal
    native_unit: str | None
    filled_quantity: Decimal | None
    average_price: Decimal | None
    created_at: str | None
    metadata_version: str | None
    native_asset: str | None = None
    filled_quantity_unit: str | None = None
    limit_price: Decimal | None = None

    def to_dict(self) -> dict[str, Any]:
        return {
            "exchange": self.exchange, "product": self.product, "environment": self.environment,
            "region": self.region, "orderId": self.order_id, "clientOrderId": self.client_order_id,
            "instrument": self.instrument, "side": self.side, "orderType": self.order_type,
            "status": self.status, "nativeQuantity": decimal_text(self.native_quantity),
            "quantityUnit": self.native_unit, "filledQuantity": decimal_text(self.filled_quantity),
            "filledQuantityUnit": self.filled_quantity_unit,
            "averagePrice": decimal_text(self.average_price), "eventTime": self.created_at,
            "metadataVersion": self.metadata_version, "nativeAsset": self.native_asset,
            "limitPrice": decimal_text(self.limit_price),
        }


@dataclass(frozen=True, slots=True)
class InstrumentMetadataDTO:
    exchange: str
    product: str
    environment: str
    region: str
    instrument: str
    base_asset: str | None
    quote_asset: str | None
    tick_size: Decimal
    lot_size: Decimal
    min_quantity: Decimal
    min_notional: Decimal | None
    contract_value: Decimal | None
    contract_value_unit: str | None
    contract_type: str | None
    settlement_asset: str | None
    metadata_version: str
    status: str | None

    def to_dict(self) -> dict[str, Any]:
        return {
            "exchange": self.exchange, "product": self.product, "environment": self.environment,
            "region": self.region, "instrument": self.instrument, "baseAsset": self.base_asset,
            "quoteAsset": self.quote_asset, "tickSize": decimal_text(self.tick_size),
            "lotStep": decimal_text(self.lot_size), "minQuantity": decimal_text(self.min_quantity),
            "minNotional": decimal_text(self.min_notional), "contractValue": decimal_text(self.contract_value),
            "contractValueUnit": self.contract_value_unit, "contractType": self.contract_type,
            "settlementAsset": self.settlement_asset, "metadataVersion": self.metadata_version,
            "status": self.status,
        }


@dataclass(frozen=True, slots=True)
class TickerDTO:
    exchange: str
    product: str
    environment: str
    region: str
    instrument: str
    price: Decimal
    fetched_at: str
    event_time: str | None = None

    def to_dict(self) -> dict[str, Any]:
        return {
            "exchange": self.exchange, "product": self.product, "environment": self.environment,
            "region": self.region, "instrument": self.instrument, "price": decimal_text(self.price),
            "fetchedAt": self.fetched_at, "eventTime": self.event_time,
        }


def metadata_version(value: dict[str, Any]) -> str:
    encoded = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True).encode("ascii")
    return hashlib.sha256(encoded).hexdigest()[:24]


@dataclass(frozen=True, slots=True)
class BinanceQuantityFilter:
    """A native Binance quantity bound and optional exact increment grid."""

    min_quantity: Decimal
    max_quantity: Decimal
    step_size: Decimal

    def to_dict(self) -> dict[str, str]:
        return {
            "minQty": decimal_text(self.min_quantity) or "0",
            "maxQty": decimal_text(self.max_quantity) or "0",
            "stepSize": decimal_text(self.step_size) or "0",
        }

    def accepts(self, quantity: Decimal) -> bool:
        return (
            quantity >= self.min_quantity
            and quantity <= self.max_quantity
            and (self.step_size == 0 or is_multiple(decimal_subtract(quantity, self.min_quantity), self.step_size))
        )


@dataclass(frozen=True, slots=True)
class BinanceUSDMOrderFilters:
    """The distinct native quantity filters used by USD-M order intents."""

    symbol: str
    lot_size: BinanceQuantityFilter
    market_lot_size: BinanceQuantityFilter
    metadata_version: str

    def raw_binding(self) -> dict[str, dict[str, str]]:
        return {
            "LOT_SIZE": self.lot_size.to_dict(),
            "MARKET_LOT_SIZE": self.market_lot_size.to_dict(),
        }

    def validate_market_quantity(self, quantity: Any) -> Decimal:
        value = required_decimal(quantity, positive=True)
        if not self.lot_size.accepts(value) or not self.market_lot_size.accepts(value):
            raise AdapterError(422, "quantity_unsupported", "The exchange quantity does not meet instrument filters.")
        return value
