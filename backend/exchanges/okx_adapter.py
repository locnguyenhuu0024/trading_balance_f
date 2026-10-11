"""Normalized read adapter that preserves the existing native OKX client."""

from __future__ import annotations

from datetime import datetime, timezone
from decimal import Decimal
from typing import Any

from ..okx import OKXClient, OKXError
from .contracts import (
    AdapterError,
    BalanceDTO,
    InstrumentMetadataDTO,
    OrderDTO,
    PositionDTO,
    Product,
    TickerDTO,
    decimal_value,
    decimal_multiply,
    decimal_divide,
    metadata_version,
    required_decimal,
)


_PRODUCT_TYPES = {
    Product.SPOT.value: "SPOT",
    Product.MARGIN.value: "MARGIN",
    Product.SWAP.value: "SWAP",
    Product.FUTURES.value: "FUTURES",
}
_MAX_NATIVE_ROWS = 10_000
_NATIVE_PAGE_SIZE = 100


class OKXReadAdapter:
    exchange = "OKX"

    def __init__(self, client: OKXClient, *, environment: str, region: str):
        self.client = client
        self.environment = environment
        self.region = region

    def _request(self, path: str, params: dict[str, str] | None = None, *, private: bool = True) -> Any:
        try:
            response = self.client.request("GET", path, params=params, private=private)
        except OKXError as error:
            status = 429 if error.http_status == 429 else 502
            code = "rate_limited" if status == 429 else "exchange_unavailable"
            raise AdapterError(status, code, "The exchange read is unavailable.", retry_after=error.retry_after) from None
        data = response.get("data")
        if not isinstance(data, list) or any(not isinstance(row, dict) for row in data):
            raise AdapterError(502, "exchange_data_unavailable", "Exchange read data is unavailable.")
        return data

    def balances(self, product: str) -> list[BalanceDTO]:
        if product not in _PRODUCT_TYPES:
            raise AdapterError(422, "capability_unsupported", "The exchange product is unsupported.")
        rows = self._request("/api/v5/account/balance")
        if len(rows) != 1 or not isinstance(rows[0].get("details"), list):
            raise AdapterError(502, "exchange_data_unavailable", "Exchange balance data is unavailable.")
        result = []
        for row in rows[0]["details"]:
            if not isinstance(row, dict) or not isinstance(row.get("ccy"), str):
                raise AdapterError(502, "exchange_data_unavailable", "Exchange balance data is unavailable.")
            available = decimal_value(row.get("availBal"))
            locked = decimal_value(row.get("frozenBal"))
            total = decimal_value(row.get("cashBal"))
            result.append(BalanceDTO(
                self.exchange, product, self.environment, self.region, row["ccy"],
                available, locked, total, row["ccy"],
            ))
        return result

    def positions(self, product: str, instrument: str | None = None, *, position_mode: str | None = None) -> list[PositionDTO]:
        native_type = _PRODUCT_TYPES.get(product)
        if native_type in {None, Product.SPOT.value}:
            raise AdapterError(422, "capability_unsupported", "Spot positions are not supported.")
        params = {"instType": native_type}
        if instrument is not None:
            params["instId"] = self._instrument(instrument)
        rows = self._request("/api/v5/account/positions", params)
        if len(rows) > _MAX_NATIVE_ROWS:
            raise AdapterError(503, "snapshot_capacity", "The exchange read exceeds the supported snapshot size.")
        metadata = {item.instrument: item for item in self.instruments(product)}
        result = []
        for row in rows:
            inst = self._instrument(row.get("instId"))
            native_quantity = decimal_value(row.get("pos"))
            item = metadata.get(inst)
            if native_quantity is None or item is None:
                raise AdapterError(502, "metadata_unavailable", "Exchange position metadata is unavailable.")
            position_side = row.get("posSide")
            side = position_side if position_side in {"long", "short", "net"} else None
            native_asset = self._text(row.get("posCcy"), maximum=20)
            if product == Product.MARGIN.value:
                quantity_unit = "base" if native_asset == item.base_asset else None
                base_quantity = native_quantity if quantity_unit == "base" else None
            else:
                quantity_unit = "contracts"
                base_quantity = self._base_quantity(native_quantity, item, row)
            if side == "short" and base_quantity is not None and base_quantity > 0:
                base_quantity = base_quantity.copy_negate()
            result.append(PositionDTO(
                self.exchange, product, self.environment, self.region, inst,
                native_quantity, quantity_unit, base_quantity, item.contract_value,
                item.contract_value_unit, item.contract_type, item.settlement_asset,
                decimal_value(row.get("avgPx")), decimal_value(row.get("markPx")),
                decimal_value(row.get("upl")), side, position_mode, item.metadata_version, native_asset,
            ))
        return result

    def orders(self, product: str, instrument: str | None = None) -> list[OrderDTO]:
        native_type = _PRODUCT_TYPES.get(product)
        if native_type is None:
            raise AdapterError(422, "capability_unsupported", "The exchange product is unsupported.")
        params = {"instType": native_type, "limit": str(_NATIVE_PAGE_SIZE)}
        if instrument is not None:
            params["instId"] = self._instrument(instrument)
        rows = self._paged_rows("/api/v5/trade/orders-pending", params, cursor_field="ordId")
        metadata = {item.instrument: item for item in self.instruments(product)}
        result = []
        for row in rows:
            inst = self._instrument(row.get("instId"))
            item = metadata.get(inst)
            order_id = self._text(row.get("ordId"))
            quantity = decimal_value(row.get("sz"))
            filled = decimal_value(row.get("accFillSz"))
            if item is None or order_id is None or quantity is None or quantity < 0:
                raise AdapterError(502, "exchange_data_unavailable", "Exchange order data is unavailable.")
            order_type = (self._text(row.get("ordType"), maximum=32) or "").lower()
            side = (self._text(row.get("side"), maximum=16) or "").lower()
            if product in {"SWAP", "FUTURES"}:
                quantity_unit, native_asset = "contracts", item.contract_value_unit
            elif product == "MARGIN" and order_type == "market" and side == "buy":
                quantity_unit, native_asset = None, item.quote_asset
            elif product == "SPOT" and order_type == "market":
                target_currency = row.get("tgtCcy")
                if target_currency == "base_ccy":
                    quantity_unit, native_asset = "base", item.base_asset
                elif target_currency == "quote_ccy":
                    quantity_unit, native_asset = None, item.quote_asset
                else:
                    quantity_unit, native_asset = None, None
            else:
                quantity_unit, native_asset = "base", item.base_asset
            result.append(OrderDTO(
                self.exchange, product, self.environment, self.region,
                order_id, self._text(row.get("clOrdId")), inst,
                self._text(row.get("side"), maximum=16), self._text(row.get("ordType"), maximum=32),
                (self._text(row.get("state"), maximum=32) or "unknown").lower(), quantity,
                quantity_unit,
                filled, decimal_value(row.get("avgPx")), self._timestamp(row.get("cTime")), item.metadata_version,
                native_asset, "contracts" if product in {"SWAP", "FUTURES"} else "base",
            ))
        return result

    def instruments(self, product: str, instrument: str | None = None) -> list[InstrumentMetadataDTO]:
        native_type = _PRODUCT_TYPES.get(product)
        if native_type is None:
            raise AdapterError(422, "capability_unsupported", "The exchange product is unsupported.")
        params = {"instType": native_type}
        if instrument is not None:
            params["instId"] = self._instrument(instrument)
        rows = self._request("/api/v5/public/instruments", params, private=False)
        result = []
        for row in rows:
            inst = self._instrument(row.get("instId"))
            tick = required_decimal(row.get("tickSz"), positive=True)
            lot = required_decimal(row.get("lotSz"), positive=True)
            minimum = required_decimal(row.get("minSz"), positive=True)
            contract_value = decimal_value(row.get("ctVal"))
            if product in {"SWAP", "FUTURES"} and (contract_value is None or contract_value <= 0):
                raise AdapterError(502, "metadata_unavailable", "Exchange contract metadata is unavailable.")
            contract_type = self._text(row.get("ctType"), maximum=16)
            contract_unit = self._text(row.get("ctValCcy"), maximum=20)
            settlement = self._text(row.get("settleCcy"), maximum=20)
            base, quote = self._assets(inst)
            metadata_source = {
                "instId": inst, "instType": native_type, "state": row.get("state"),
                "tickSz": row.get("tickSz"), "lotSz": row.get("lotSz"), "minSz": row.get("minSz"),
                "ctVal": row.get("ctVal"), "ctValCcy": contract_unit, "ctType": contract_type,
                "settleCcy": settlement,
            }
            result.append(InstrumentMetadataDTO(
                self.exchange, product, self.environment, self.region, inst, base, quote,
                tick, lot, minimum, None, contract_value, contract_unit, contract_type, settlement,
                metadata_version(metadata_source), self._text(row.get("state"), maximum=24),
            ))
        if instrument is not None and not result:
            raise AdapterError(404, "instrument_unavailable", "The exchange instrument is unavailable.")
        return result

    def ticker(self, product: str, instrument: str, *, fetched_at: str) -> TickerDTO:
        inst = self._instrument(instrument)
        rows = self._request("/api/v5/market/ticker", {"instId": inst}, private=False)
        if len(rows) != 1 or rows[0].get("instId") != inst:
            raise AdapterError(502, "ticker_unavailable", "Exchange quote data is unavailable.")
        price = decimal_value(rows[0].get("last"))
        if price is None or price <= 0:
            raise AdapterError(502, "ticker_unavailable", "Exchange quote data is unavailable.")
        return TickerDTO(
            self.exchange, product, self.environment, self.region, inst, price,
            fetched_at, self._timestamp(rows[0].get("ts")),
        )

    def _paged_rows(self, path: str, params: dict[str, str], *, cursor_field: str) -> list[dict[str, Any]]:
        result: list[dict[str, Any]] = []
        cursor = None
        for _ in range((_MAX_NATIVE_ROWS // _NATIVE_PAGE_SIZE) + 2):
            page_params = dict(params)
            if cursor is not None:
                page_params["after"] = cursor
            page = self._request(path, page_params)
            if len(result) + len(page) > _MAX_NATIVE_ROWS:
                raise AdapterError(503, "snapshot_capacity", "The exchange read exceeds the supported snapshot size.")
            result.extend(page)
            if len(page) < _NATIVE_PAGE_SIZE:
                return result
            next_cursor = page[-1].get(cursor_field)
            if not isinstance(next_cursor, str) or not next_cursor or next_cursor == cursor:
                raise AdapterError(502, "exchange_data_unavailable", "The exchange read could not be completed.")
            cursor = next_cursor
        raise AdapterError(503, "snapshot_capacity", "The exchange read exceeds the supported snapshot size.")

    @staticmethod
    def _base_quantity(native_quantity: Decimal, item: InstrumentMetadataDTO, row: dict[str, Any]) -> Decimal | None:
        if item.contract_value is None:
            return None
        if item.contract_type == "linear" and item.contract_value_unit == item.base_asset:
            return decimal_multiply(native_quantity, item.contract_value)
        if item.contract_type == "inverse" and item.contract_value_unit == item.quote_asset:
            mark = decimal_value(row.get("markPx"))
            if mark is None or mark <= 0:
                return None
            return decimal_divide(decimal_multiply(native_quantity, item.contract_value), mark)
        return None

    @staticmethod
    def _assets(instrument: str) -> tuple[str | None, str | None]:
        parts = instrument.split("-")
        if len(parts) < 2:
            return None, None
        return parts[0], parts[1]

    @staticmethod
    def _instrument(value: Any) -> str:
        if not isinstance(value, str) or len(value) > 64 or not value.isascii() or not all(ch.isalnum() or ch == "-" for ch in value):
            raise AdapterError(400, "invalid_instrument", "The exchange instrument is invalid.")
        return value.upper()

    @staticmethod
    def _text(value: Any, *, maximum: int = 128) -> str | None:
        if not isinstance(value, (str, int)) or isinstance(value, bool):
            return None
        result = str(value)
        return result if result and len(result) <= maximum else None

    @staticmethod
    def _timestamp(value: Any) -> str | None:
        if not isinstance(value, str) or not value.isdigit():
            return None
        try:
            return datetime.fromtimestamp(int(value) / 1000, timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")
        except (OverflowError, OSError, ValueError):
            return None
