"""Owner-scoped close/cancel operations with durable send and reconciliation fences."""

from __future__ import annotations

import hashlib
import hmac
import json
import re
import secrets
import uuid
from datetime import datetime, timezone
from decimal import Decimal, InvalidOperation
from typing import Any, Callable

from .account_context import (
    AccountContextError,
    BinanceClientBundle,
    VerifiedOKXIdentity,
    verify_okx_identity,
)
from .connections import ConnectionServiceError, ConnectionContext, OwnedConnections
from .exchanges.binance_transport import BinanceTransportError
from .exchanges.contracts import AdapterError, decimal_subtract, decimal_value
from .okx import OKXError, OKXTransportError
from .principal import Principal


class CommandLedgerError(Exception):
    def __init__(self, status: int, code: str, message: str):
        super().__init__(message)
        self.status = status
        self.code = code
        self.message = message


class CommandLedger:
    """Prepare and execute owner-scoped OKX and fixture-gated Binance actions."""

    CONFIRMATION_SECONDS = 30
    LEASE_SECONDS = 45
    _POSITION_TYPES = frozenset({"SWAP", "FUTURES", "MARGIN"})
    _CANCEL_TYPES = frozenset({"SPOT", "MARGIN", "SWAP", "FUTURES"})
    _TARGET_ID_RE = re.compile(r"[A-Z0-9-]{2,40}\Z")
    _BINANCE_SYMBOL_RE = re.compile(r"[A-Z0-9]{3,32}\Z")
    _BINANCE_ID_RE = re.compile(r"[1-9][0-9]{0,19}\Z")
    _BINANCE_CLIENT_ORDER_ID_RE = re.compile(r"[A-Za-z0-9._:-]{1,36}\Z")
    _BINANCE_ORDER_STATES = frozenset({
        "NEW", "PARTIALLY_FILLED", "FILLED", "CANCELED", "REJECTED", "EXPIRED", "EXPIRED_IN_MATCH",
    })
    _BINANCE_ACTIONS = frozenset({"close_position", "partial_close", "cancel_order", "close_all"})
    _IDEMPOTENCY_RE = re.compile(r"[A-Za-z0-9._:-]{8,128}\Z")

    def __init__(
        self,
        store: Any,
        connections: OwnedConnections,
        *,
        clock: Callable[[], float],
        trade_enabled: bool,
        allow_binance_fixtures: bool = False,
    ):
        self.store = store
        self.connections = connections
        self._clock = clock
        self._trade_enabled = trade_enabled
        self._allow_binance_fixtures = allow_binance_fixtures is True

    def _suffix(self) -> str:
        return " FOR UPDATE" if self.store.dialect == "postgresql" else ""

    def _require_principal(self, connection: Any, principal: Principal, *, step_up: bool) -> None:
        try:
            self.connections._require_principal(connection, principal, self._clock(), step_up=step_up)
        except ConnectionServiceError as error:
            raise CommandLedgerError(error.status, error.code, error.message) from None

    @staticmethod
    def _timestamp(value: Any) -> str | None:
        if value is None:
            return None
        return datetime.fromtimestamp(float(value), tz=timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")

    @staticmethod
    def _digest(value: str) -> str:
        return hashlib.sha256(value.encode("ascii")).hexdigest()

    @staticmethod
    def _decimal(value: Any, name: str, *, positive: bool = True) -> Decimal:
        if not isinstance(value, str) or len(value) > 32 or value != value.strip():
            raise CommandLedgerError(400, "action_invalid", f"The {name} value is invalid.")
        try:
            parsed = Decimal(value)
        except InvalidOperation:
            raise CommandLedgerError(400, "action_invalid", f"The {name} value is invalid.") from None
        if not parsed.is_finite() or (positive and parsed <= 0) or (not positive and parsed < 0):
            raise CommandLedgerError(400, "action_invalid", f"The {name} value is invalid.")
        return parsed

    @staticmethod
    def _decimal_text(value: Decimal) -> str:
        return format(value, "f")

    @classmethod
    def _identity(cls, action: str, value: Any) -> dict[str, Any]:
        binance_identity = (
            action in {"partial_close", "close_all"}
            or action in {"close_position", "cancel_order"} and isinstance(value, dict) and "product" in value
        )
        if action in cls._BINANCE_ACTIONS and binance_identity:
            if action == "close_all":
                if not isinstance(value, dict) or value != {"product": "USD_M"}:
                    raise CommandLedgerError(400, "action_invalid", "The USD-M close-all identity is invalid.")
                return {"product": "USD_M"}
            expected = {
                "close_position": {"product", "instrumentId", "positionSide"},
                "partial_close": {"product", "instrumentId", "positionSide", "quantity"},
                "cancel_order": {"product", "instrumentId", "orderId"},
            }[action]
            if not isinstance(value, dict) or set(value) != expected or value.get("product") != "USD_M":
                raise CommandLedgerError(400, "action_invalid", "The USD-M action identity is invalid.")
            symbol = value.get("instrumentId")
            if not isinstance(symbol, str) or not cls._BINANCE_SYMBOL_RE.fullmatch(symbol):
                raise CommandLedgerError(400, "action_invalid", "The USD-M instrument is invalid.")
            result = {key: value[key] for key in expected}
            if action in {"close_position", "partial_close"}:
                if result["positionSide"] != "BOTH":
                    raise CommandLedgerError(422, "capability_unsupported", "Only one-way USD-M positions are supported.")
                if action == "partial_close":
                    raw_quantity = result["quantity"]
                    quantity = decimal_value(raw_quantity) if isinstance(raw_quantity, str) else None
                    if quantity is None or quantity <= 0:
                        raise CommandLedgerError(400, "action_invalid", "The quantity value is invalid.")
                    result["quantity"] = cls._decimal_text(quantity)
            else:
                order_id = result["orderId"]
                if isinstance(order_id, bool) or not isinstance(order_id, (str, int)):
                    raise CommandLedgerError(400, "action_invalid", "The USD-M order identifier is invalid.")
                result["orderId"] = str(order_id)
                if not cls._BINANCE_ID_RE.fullmatch(result["orderId"]):
                    raise CommandLedgerError(400, "action_invalid", "The USD-M order identifier is invalid.")
            return result
        if action == "close_position":
            allowed = {"instrumentType", "instrumentId", "positionId", "positionSide", "marginMode", "marginCurrency"}
            required = {"instrumentType", "instrumentId", "positionSide", "marginMode"}
            if not isinstance(value, dict) or not required <= set(value) or set(value) - allowed:
                raise CommandLedgerError(400, "action_invalid", "A complete position identity is required.")
            result = dict(value)
            if result["instrumentType"] not in cls._POSITION_TYPES:
                raise CommandLedgerError(422, "capability_unsupported", "This position type cannot be closed through this connection.")
            if not isinstance(result["instrumentId"], str) or not cls._TARGET_ID_RE.fullmatch(result["instrumentId"]):
                raise CommandLedgerError(400, "action_invalid", "The position instrument is invalid.")
            if result["positionSide"] not in {"net", "long", "short"} or result["marginMode"] not in {"cross", "isolated"}:
                raise CommandLedgerError(400, "action_invalid", "The position mode is invalid.")
            if "positionId" in result and (not isinstance(result["positionId"], str) or not result["positionId"] or len(result["positionId"]) > 128):
                raise CommandLedgerError(400, "action_invalid", "The position identifier is invalid.")
            if result["instrumentType"] == "MARGIN":
                currency = result.get("marginCurrency")
                if (
                    result["positionSide"] != "net"
                    or not isinstance(currency, str)
                    or not re.fullmatch(r"[A-Z0-9]{2,16}", currency)
                ):
                    raise CommandLedgerError(400, "action_invalid", "The margin currency is invalid.")
            elif "marginCurrency" in result:
                raise CommandLedgerError(400, "action_invalid", "The position identity contains unsupported fields.")
            return result

        keys = ("instType", "instId", "ordId", "ordType", "side", "px", "sz")
        if not isinstance(value, dict) or set(value) != set(keys):
            raise CommandLedgerError(400, "action_invalid", "A complete selected order identity is required.")
        result = dict(value)
        if (
            result["instType"] not in cls._CANCEL_TYPES
            or result["ordType"] != "limit"
            or result["side"] not in {"buy", "sell"}
            or not isinstance(result["instId"], str)
            or not cls._TARGET_ID_RE.fullmatch(result["instId"])
            or not isinstance(result["ordId"], str)
            or not result["ordId"]
            or len(result["ordId"]) > 128
        ):
            raise CommandLedgerError(422, "capability_unsupported", "Only an active OKX limit order can be canceled.")
        result["px"] = cls._decimal_text(cls._decimal(result["px"], "price"))
        result["sz"] = cls._decimal_text(cls._decimal(result["sz"], "size"))
        return result

    def _verify_context(
        self,
        context: ConnectionContext,
        *,
        require_trade: bool = True,
        expected_identity_digest: str | None = None,
    ) -> VerifiedOKXIdentity:
        if context.exchange == "BINANCE":
            identity = self._verify_binance_context(context, require_trade=require_trade)
            if require_trade and identity.get("canTrade") is not True:
                raise CommandLedgerError(403, "trade_not_permitted", "The exchange connection does not permit this action.")
            digest = identity["uidDigest"]
            expected_digest = context.remote_identity_digest if expected_identity_digest is None else expected_identity_digest
            if not hmac.compare_digest(digest, context.remote_identity_digest) or not hmac.compare_digest(digest, expected_digest):
                raise CommandLedgerError(409, "account_changed", "The exchange credentials resolve to a different account.")
            return identity  # type: ignore[return-value]
        try:
            identity = verify_okx_identity(context.client)
        except (AccountContextError, OKXError):
            raise CommandLedgerError(502, "account_unavailable", "The exchange account could not be verified.") from None
        digest = self.connections._identity_digest(
            context.exchange, context.environment, context.region, identity.uid
        )
        expected_digest = context.remote_identity_digest if expected_identity_digest is None else expected_identity_digest
        if not hmac.compare_digest(digest, context.remote_identity_digest) or not hmac.compare_digest(digest, expected_digest):
            raise CommandLedgerError(409, "account_changed", "The exchange credentials resolve to a different account.")
        if require_trade and ("trade" not in context.capabilities or "trade" not in identity.capabilities):
            raise CommandLedgerError(403, "trade_not_permitted", "The exchange connection does not permit this action.")
        return identity

    def _verify_binance_context(
        self, context: ConnectionContext, *, require_trade: bool = True,
    ) -> dict[str, Any]:
        """Require fixture policy, injected transport, and authoritative USD-M proof."""
        if (
            not self._allow_binance_fixtures
            or context.environment not in {"live", "demo"}
            or context.region != "global"
            or not isinstance(context.client, BinanceClientBundle)
            or not context.client.transport.has_injected_transport
            or "read:USD_M" not in context.capabilities
        ):
            raise CommandLedgerError(422, "capability_unsupported", "This USD-M command is unavailable in this runtime.")
        try:
            spot_account = context.client.spot.account()
            restrictions = context.client.spot.restrictions()
            futures = context.client.usdm.account()
            dual_side = context.client.usdm.position_mode()
        except (AdapterError, BinanceTransportError):
            raise CommandLedgerError(502, "account_unavailable", "The exchange account could not be verified.") from None
        uid_value = spot_account.get("uid") if isinstance(spot_account, dict) else None
        if isinstance(uid_value, bool) or not isinstance(uid_value, (str, int)):
            raise CommandLedgerError(502, "account_unavailable", "The exchange account could not be verified.")
        uid = str(uid_value)
        if not uid.isascii() or not uid.isdigit() or uid.startswith("0") or len(uid) > 20:
            raise CommandLedgerError(502, "account_unavailable", "The exchange account could not be verified.")
        if (
            not isinstance(restrictions, dict)
            or restrictions.get("enableReading") is not True
            or restrictions.get("enableWithdrawals") is not False
            or restrictions.get("enableFutures") is not True
            or not isinstance(futures, dict)
            or not isinstance(futures.get("canTrade"), bool)
            or (require_trade and futures.get("canTrade") is not True)
            or futures.get("portfolioMargin") is not False
            or not isinstance(futures.get("multiAssetsMargin"), bool)
            or dual_side is not False
        ):
            raise CommandLedgerError(422, "capability_unsupported", "The exchange account mode is not supported for USD-M commands.")
        digest = self.connections._identity_digest(context.exchange, context.environment, context.region, uid)
        return {
            "uid": uid,
            "uidDigest": digest,
            "enableReading": True,
            "enableWithdrawals": False,
            "enableFutures": True,
            "canTrade": futures["canTrade"],
            "portfolioMargin": False,
            "multiAssetsMargin": futures["multiAssetsMargin"],
            "dualSidePosition": False,
        }

    @staticmethod
    def _binance_decimal(value: Any) -> Decimal | None:
        return decimal_value(value)

    @classmethod
    def _native_binance_order_id(cls, value: Any) -> str | None:
        if isinstance(value, bool) or not isinstance(value, (str, int)):
            return None
        token = str(value)
        return token if cls._BINANCE_ID_RE.fullmatch(token) is not None else None

    def _binance_position_snapshot(
        self, context: ConnectionContext, symbol: str, *, allow_empty: bool = False,
    ) -> dict[str, Any]:
        try:
            rows = context.client.usdm.position_rows(symbol)
        except (AdapterError, BinanceTransportError):
            raise CommandLedgerError(502, "position_unavailable", "The USD-M position could not be verified.") from None
        matches: list[dict[str, Any]] = []
        for row in rows:
            if not isinstance(row, dict):
                raise CommandLedgerError(502, "position_unavailable", "The USD-M position could not be verified.")
            row_symbol = row.get("symbol")
            if row_symbol != symbol:
                raise CommandLedgerError(502, "position_unavailable", "The USD-M position could not be verified.")
            if row.get("positionSide") != "BOTH":
                raise CommandLedgerError(422, "capability_unsupported", "Only one-way USD-M positions are supported.")
            amount = self._binance_decimal(row.get("positionAmt"))
            margin_type = row.get("marginType")
            if amount is None or not isinstance(margin_type, str) or margin_type not in {"cross", "isolated"}:
                raise CommandLedgerError(502, "position_unavailable", "The USD-M position could not be verified.")
            matches.append({
                "symbol": symbol,
                "signedSize": amount,
                "positionSign": 1 if amount > 0 else (-1 if amount < 0 else 0),
                "size": amount.copy_abs(),
                "marginType": margin_type,
            })
        if not matches and allow_empty:
            return {
                "symbol": symbol, "signedSize": Decimal("0"), "positionSign": 0,
                "size": Decimal("0"), "marginType": "cross",
            }
        if len(matches) != 1:
            raise CommandLedgerError(409, "stale_target", "The USD-M position identity is unavailable or ambiguous.")
        return matches[0]

    @staticmethod
    def _binance_error(error: Exception) -> tuple[str, dict[str, Any]]:
        if isinstance(error, BinanceTransportError):
            return ("FAILED" if error.definite_failure else "UNKNOWN", {
                "reason": "exchange_rejected" if error.definite_failure else "exchange_outcome_unknown",
                "category": error.code,
                **({"nativeCode": error.native_code} if error.native_code is not None else {}),
                **({"httpStatus": error.http_status} if error.http_status is not None else {}),
            })
        if isinstance(error, AdapterError):
            return ("UNKNOWN", {"reason": "exchange_outcome_unknown", "category": error.code})
        return "UNKNOWN", {"reason": "exchange_outcome_unknown"}

    @staticmethod
    def _position_identity(raw: dict[str, Any], instrument_type: str) -> dict[str, Any] | None:
        instrument_id = raw.get("instId")
        margin_mode = raw.get("mgnMode")
        side = raw.get("posSide") or "net"
        if (
            not isinstance(instrument_id, str) or not instrument_id
            or margin_mode not in {"cross", "isolated"}
            or side not in {"net", "long", "short"}
        ):
            return None
        identity: dict[str, Any] = {
            "instrumentType": instrument_type,
            "instrumentId": instrument_id,
            "positionSide": side,
            "marginMode": margin_mode,
        }
        if raw.get("posId") not in (None, ""):
            identity["positionId"] = str(raw["posId"])
        if instrument_type == "MARGIN":
            currency = raw.get("ccy") or raw.get("marginCcy")
            if not isinstance(currency, str) or not currency:
                return None
            identity["marginCurrency"] = currency
        return identity

    @staticmethod
    def _signed_size(raw: dict[str, Any], position_mode: str) -> Decimal | None:
        value = raw.get("pos")
        if isinstance(value, bool) or value is None:
            return None
        try:
            size = Decimal(str(value))
        except (InvalidOperation, ValueError, TypeError):
            return None
        if not size.is_finite():
            return None
        if position_mode == "long_short_mode" and size < 0:
            return None
        return size

    def _read_position(self, context: ConnectionContext, identity: dict[str, Any]) -> dict[str, Any] | None:
        instrument_type = str(identity["instrumentType"])
        configuration = context.client.account_config()
        position_mode = configuration.get("posMode")
        if position_mode not in {"net_mode", "long_short_mode"}:
            raise CommandLedgerError(409, "capability_unsupported", "The exchange position mode is not supported.")
        instruments = context.client.instruments(instrument_type)
        if not isinstance(instruments, list) or not any(
            isinstance(item, dict) and item.get("instId") == identity["instrumentId"] for item in instruments
        ):
            raise CommandLedgerError(409, "stale_target", "The selected position instrument is no longer available.")
        positions = context.client.positions(instrument_type)
        if not isinstance(positions, list):
            raise CommandLedgerError(502, "position_unavailable", "The selected position could not be verified.")
        matches: list[dict[str, Any]] = []
        for raw in positions:
            if not isinstance(raw, dict):
                raise CommandLedgerError(502, "position_unavailable", "The selected position could not be verified.")
            found = self._position_identity(raw, instrument_type)
            if raw.get("instId") != identity["instrumentId"]:
                continue
            if found is None:
                raise CommandLedgerError(502, "position_unavailable", "The selected position identity is incomplete.")
            same_slot = all(
                found.get(key) == identity.get(key)
                for key in ("instrumentType", "instrumentId", "positionSide", "marginMode", "marginCurrency")
            )
            if not same_slot:
                continue
            if "positionId" in identity and found.get("positionId") != identity["positionId"]:
                continue
            signed_size = self._signed_size(raw, position_mode)
            if signed_size is None:
                raise CommandLedgerError(502, "position_unavailable", "The selected position could not be verified.")
            if position_mode == "net_mode" and identity["positionSide"] != "net":
                raise CommandLedgerError(409, "stale_target", "The selected position mode changed.")
            if position_mode == "long_short_mode" and identity["positionSide"] == "net":
                raise CommandLedgerError(409, "stale_target", "The selected position mode changed.")
            if instrument_type == "MARGIN" and position_mode != "net_mode":
                raise CommandLedgerError(409, "capability_unsupported", "Margin positions are supported only in net mode.")
            if signed_size == 0:
                continue
            matches.append({
                "identity": found,
                "positionMode": position_mode,
                "signedSize": self._decimal_text(signed_size),
                "size": self._decimal_text(abs(signed_size)),
                "marginMode": identity["marginMode"],
            })
        if len(matches) > 1:
            raise CommandLedgerError(409, "stale_target", "The selected position identity is ambiguous.")
        return matches[0] if matches else None

    def _read_order(self, context: ConnectionContext, identity: dict[str, Any]) -> dict[str, Any] | None:
        instruments = context.client.instruments(identity["instType"])
        if not isinstance(instruments, list) or not any(
            isinstance(item, dict) and item.get("instId") == identity["instId"] for item in instruments
        ):
            return None
        order = context.client.order_details_by_id(identity["instId"], identity["ordId"])
        if not isinstance(order, dict):
            return None
        for key in ("instId", "ordId", "ordType", "side"):
            if order.get(key) != identity[key]:
                return None
        for key in ("px", "sz"):
            try:
                if Decimal(str(order.get(key))) != Decimal(identity[key]):
                    return None
            except (InvalidOperation, ValueError, TypeError):
                return None
        state = order.get("state")
        size, filled = self._order_sizes(order)
        if state not in {"live", "partially_filled", "canceled", "mmp_canceled", "filled"} or size is None or filled is None:
            return None
        if filled < 0 or filled > size:
            return None
        return {
            "state": state,
            "filledSize": self._decimal_text(filled),
            "remainingSize": self._decimal_text(size - filled),
        }

    @staticmethod
    def _order_sizes(order: dict[str, Any]) -> tuple[Decimal | None, Decimal | None]:
        try:
            size = Decimal(str(order.get("sz")))
            filled = Decimal(str(order.get("accFillSz")))
        except (InvalidOperation, ValueError, TypeError):
            return None, None
        if not size.is_finite() or not filled.is_finite():
            return None, None
        return size, filled

    def _binance_binding(self, context: ConnectionContext, proof: dict[str, Any]) -> dict[str, Any]:
        return {
            "environment": context.environment,
            "region": context.region,
            "credentialVersion": context.credential_version,
            "permissionVersion": context.permission_version,
            "uidDigest": proof["uidDigest"],
            "enableReading": proof["enableReading"],
            "enableWithdrawals": proof["enableWithdrawals"],
            "enableFutures": proof["enableFutures"],
            "canTrade": proof["canTrade"],
            "portfolioMargin": proof["portfolioMargin"],
            "multiAssetsMargin": proof["multiAssetsMargin"],
            "dualSidePosition": proof["dualSidePosition"],
        }

    def _binance_filters(self, context: ConnectionContext, symbol: str) -> Any:
        try:
            return context.client.usdm.order_filters(symbol)
        except (AdapterError, BinanceTransportError):
            raise CommandLedgerError(502, "metadata_unavailable", "USD-M quantity filters could not be verified.") from None

    def _binance_close_target(
        self,
        context: ConnectionContext,
        proof: dict[str, Any],
        action: str,
        identity: dict[str, Any],
        operation_id: str,
        target_index: int,
    ) -> dict[str, Any]:
        symbol = identity["instrumentId"]
        current = self._binance_position_snapshot(context, symbol)
        if current["size"] <= 0:
            raise CommandLedgerError(409, "stale_target", "The selected USD-M position is no longer open.")
        requested = current["size"] if action in {"close_position", "close_all"} else decimal_value(identity["quantity"])
        if requested is None:
            raise CommandLedgerError(400, "action_invalid", "The quantity value is invalid.")
        if requested <= 0 or requested > current["size"]:
            raise CommandLedgerError(409, "stale_target", "The requested USD-M quantity exceeds the current position.")
        filters = self._binance_filters(context, symbol)
        try:
            filters.validate_market_quantity(requested)
        except AdapterError as error:
            raise CommandLedgerError(error.status, error.code, error.message) from None
        side = "SELL" if current["signedSize"] > 0 else "BUY"
        client_order_id = f"btf_{operation_id[:24]}_{target_index:02d}"
        target_identity = {
            "product": "USD_M", "instrumentId": symbol, "positionSide": "BOTH",
        }
        snapshot = {
            "identity": target_identity,
            "binding": self._binance_binding(context, proof),
            "positionSign": current["positionSign"],
            "positionSize": self._decimal_text(current["size"]),
            "marginType": current["marginType"],
            "requestedQuantity": self._decimal_text(requested),
            "side": side,
            "filters": filters.raw_binding(),
            "metadataVersion": filters.metadata_version,
        }
        request = {
            "symbol": symbol,
            "side": side,
            "type": "MARKET",
            "quantity": self._decimal_text(requested),
            "positionSide": "BOTH",
            "reduceOnly": "true",
            "newClientOrderId": client_order_id,
        }
        return {"identity": target_identity, "snapshot": snapshot, "request": request, "action": action}

    def _binance_cancel_target(
        self,
        context: ConnectionContext,
        proof: dict[str, Any],
        identity: dict[str, Any],
    ) -> dict[str, Any]:
        symbol = identity["instrumentId"]
        try:
            order = context.client.usdm.order_by_id(symbol, order_id=identity["orderId"])
        except (AdapterError, BinanceTransportError):
            raise CommandLedgerError(502, "order_unavailable", "The USD-M order could not be verified.") from None
        if not isinstance(order, dict):
            raise CommandLedgerError(409, "stale_target", "The selected USD-M order is no longer available.")
        order_id = self._native_binance_order_id(order.get("orderId"))
        if order_id is None or order_id != identity["orderId"]:
            raise CommandLedgerError(409, "stale_target", "The selected USD-M order identity changed.")
        order_type = order.get("type")
        side = order.get("side")
        state = order.get("status")
        client_order_id = order.get("clientOrderId")
        orig_qty = self._binance_decimal(order.get("origQty"))
        price = self._binance_decimal(order.get("price"))
        executed = self._binance_decimal(order.get("executedQty"))
        if (
            order.get("symbol") != symbol
            or not isinstance(order_type, str) or order_type not in {"LIMIT", "MARKET"}
            or not isinstance(side, str) or side not in {"BUY", "SELL"}
            or not isinstance(client_order_id, str)
            or self._BINANCE_CLIENT_ORDER_ID_RE.fullmatch(client_order_id) is None
            or orig_qty is None or orig_qty <= 0 or price is None or price < 0
            or executed is None or executed < 0 or executed > orig_qty
        ):
            raise CommandLedgerError(422, "capability_unsupported", "Only a verified regular USD-M order can be canceled.")
        if not isinstance(state, str) or state not in {"NEW", "PARTIALLY_FILLED"}:
            raise CommandLedgerError(409, "stale_target", "The selected USD-M order is no longer open.")
        filters = self._binance_filters(context, symbol)
        target_identity = {"product": "USD_M", "instrumentId": symbol, "orderId": identity["orderId"]}
        snapshot = {
            "identity": target_identity,
            "binding": self._binance_binding(context, proof),
            "orderId": identity["orderId"],
            "clientOrderId": client_order_id,
            "type": order_type,
            "side": side,
            "originalQuantity": self._decimal_text(orig_qty),
            "price": self._decimal_text(price),
            "filters": filters.raw_binding(),
            "metadataVersion": filters.metadata_version,
        }
        return {
            "identity": target_identity,
            "snapshot": snapshot,
            "request": {"symbol": symbol, "orderId": identity["orderId"]},
            "action": "cancel_order",
        }

    def _preflight_binance(
        self,
        context: ConnectionContext,
        action: str,
        identity: dict[str, Any],
        operation_id: str,
    ) -> dict[str, Any]:
        proof = self._verify_binance_context(context)
        if not hmac.compare_digest(proof["uidDigest"], context.remote_identity_digest):
            raise CommandLedgerError(409, "account_changed", "The exchange credentials resolve to a different account.")
        if action == "cancel_order":
            target = self._binance_cancel_target(context, proof, identity)
            return {
                "targets": [target],
                "summary": {"action": action, "identity": target["identity"], "orderId": identity["orderId"]},
                "product": "USD_M",
                "uidDigest": proof["uidDigest"],
            }
        if action == "close_all":
            try:
                rows = context.client.usdm.position_rows()
            except (AdapterError, BinanceTransportError):
                raise CommandLedgerError(502, "position_unavailable", "USD-M positions could not be verified.") from None
            seen: set[str] = set()
            open_positions: list[tuple[str, Decimal]] = []
            for row in rows:
                if not isinstance(row, dict):
                    raise CommandLedgerError(502, "position_unavailable", "USD-M positions could not be verified.")
                symbol = row.get("symbol")
                amount = self._binance_decimal(row.get("positionAmt"))
                if (
                    not isinstance(symbol, str) or not self._BINANCE_SYMBOL_RE.fullmatch(symbol)
                    or symbol in seen or row.get("positionSide") != "BOTH"
                    or amount is None or not isinstance(row.get("marginType"), str)
                    or row.get("marginType") not in {"cross", "isolated"}
                ):
                    raise CommandLedgerError(422, "capability_unsupported", "The USD-M position scope contains unsupported rows.")
                seen.add(symbol)
                if amount != 0:
                    open_positions.append((symbol, amount))
            if not open_positions:
                raise CommandLedgerError(409, "stale_target", "No open USD-M positions are available to close.")
            if len(open_positions) > 20:
                raise CommandLedgerError(422, "capability_unsupported", "The USD-M position scope exceeds the action limit.")
            targets = [
                self._binance_close_target(
                    context, proof, "close_all",
                    {"product": "USD_M", "instrumentId": symbol, "positionSide": "BOTH"},
                    operation_id, index,
                )
                for index, (symbol, _) in enumerate(sorted(open_positions), start=0)
            ]
            return {
                "targets": targets,
                "summary": {"action": action, "targetCount": len(targets), "symbols": [row["identity"]["instrumentId"] for row in targets]},
                "product": "USD_M",
                "uidDigest": proof["uidDigest"],
            }
        target = self._binance_close_target(context, proof, action, identity, operation_id, 0)
        summary = {
            "action": action,
            "identity": target["identity"],
            "side": target["request"]["side"],
            "currentSize": target["snapshot"]["positionSize"],
            "requestedQuantity": target["request"]["quantity"],
        }
        return {"targets": [target], "summary": summary, "product": "USD_M", "uidDigest": proof["uidDigest"]}

    def _preflight(
        self,
        context: ConnectionContext,
        action: str,
        identity: dict[str, Any],
        *,
        operation_id: str | None = None,
    ) -> dict[str, Any]:
        if context.exchange == "BINANCE":
            if action not in self._BINANCE_ACTIONS or operation_id is None:
                raise CommandLedgerError(422, "capability_unsupported", "This exchange action is unsupported.")
            return self._preflight_binance(context, action, identity, operation_id)
        if action not in {"close_position", "cancel_order"}:
            raise CommandLedgerError(422, "capability_unsupported", "This exchange action is unsupported.")
        verified = self._verify_context(context)
        if action == "close_position":
            current = self._read_position(context, identity)
            if current is None:
                raise CommandLedgerError(409, "stale_target", "The selected position is no longer open.")
            request: dict[str, Any] = {
                "instId": identity["instrumentId"],
                "mgnMode": identity["marginMode"],
                "autoCxl": True,
            }
            if identity["positionSide"]:
                request["posSide"] = identity["positionSide"]
            if identity["instrumentType"] == "MARGIN":
                request["ccy"] = identity["marginCurrency"]
            target = {"identity": identity, "snapshot": current, "request": request, "action": action}
            direction = identity["positionSide"] if current["positionMode"] == "long_short_mode" else (
                "long" if Decimal(current["signedSize"]) > 0 else "short"
            )
            summary = {"action": action, "identity": identity, "direction": direction, "currentSize": current["size"]}
        else:
            current = self._read_order(context, identity)
            if current is None or current["state"] not in {"live", "partially_filled"} or Decimal(current["remainingSize"]) <= 0:
                raise CommandLedgerError(409, "stale_target", "The selected limit order is no longer current.")
            target = {"identity": identity, "snapshot": current, "request": {"instId": identity["instId"], "ordId": identity["ordId"]}, "action": action}
            summary = {"action": action, "identity": identity, "price": identity["px"], "originalSize": identity["sz"], "filledSize": current["filledSize"], "remainingSize": current["remainingSize"]}
        return {"target": target, "summary": summary, "product": identity.get("instrumentType", identity.get("instType")), "uidDigest": self.connections._identity_digest(context.exchange, context.environment, context.region, verified.uid)}

    @staticmethod
    def _decode(raw: Any) -> Any:
        try:
            return json.loads(raw) if raw else None
        except (TypeError, ValueError):
            return None

    def _public(self, operation: Any, targets: list[Any], *, effective_status: str | None = None) -> dict[str, Any]:
        payload = self._decode(operation["payload_json"]) or {}
        result = self._decode(operation["result_json"])
        return {
            "operationId": str(operation["operation_id"]),
            "connectionId": str(operation["connection_id"]),
            "product": str(operation["product"]),
            "action": str(payload.get("action", "unknown")),
            "status": effective_status or str(operation["status"]),
            "createdAt": self._timestamp(operation["created_at"]),
            "expiresAt": self._timestamp(operation["expires_at"]),
            "result": result,
            "targets": [
                {"index": int(row["target_index"]), "status": str(row["status"]), "result": self._decode(row["result_json"])}
                for row in targets
            ],
        }

    def _event(self, connection: Any, user_id: str, connection_id: str, operation_id: str, event_type: str, payload: dict[str, Any], now: float) -> None:
        connection.execute(
            "INSERT INTO multiuser_operation_events(user_id, connection_id, operation_id, event_id, event_type, payload_json, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
            (user_id, connection_id, operation_id, uuid.uuid4().hex, event_type, json.dumps(payload, sort_keys=True, separators=(",", ":")), now),
        )

    def prepare(self, principal: Principal, connection_id: str, body: dict[str, Any]) -> dict[str, Any]:
        if not self._trade_enabled:
            raise CommandLedgerError(403, "trade_disabled", "Multi-user trading is disabled.")
        action = body.get("action")
        if not isinstance(action, str) or action not in {"close_position", "cancel_order", *self._BINANCE_ACTIONS} or set(body) != {"action", "targetIdentity"}:
            raise CommandLedgerError(422, "capability_unsupported", "The typed exchange action is unsupported.")
        identity = self._identity(action, body["targetIdentity"])
        operation_id = uuid.uuid4().hex
        now = self._clock()
        with self.store.transaction() as connection:
            self._require_principal(connection, principal, step_up=True)
            owned = self.connections._connection_row(connection, principal.user_id, connection_id, lock=True)
            if owned is None:
                raise CommandLedgerError(404, "not_found", "The requested resource was not found.")
            connection.execute(
                "INSERT INTO multiuser_connection_leases(user_id, connection_id, updated_at) VALUES (?, ?, ?) ON CONFLICT(user_id, connection_id) DO NOTHING",
                (principal.user_id, connection_id, self._clock()),
            )
            lease = connection.execute(
                "SELECT lease_until FROM multiuser_connection_leases WHERE user_id=? AND connection_id=?" + self._suffix(),
                (principal.user_id, connection_id),
            ).fetchone()
            now = self._clock()
            if owned["status"] != "ACTIVE":
                raise CommandLedgerError(409, "connection_unavailable", "The exchange connection is not ready.")
            if lease is not None and lease["lease_until"] is not None and float(lease["lease_until"]) > now:
                raise CommandLedgerError(409, "connection_busy", "An exchange operation is active.")
            if self.connections._has_unresolved_activity(connection, principal.user_id, connection_id, now):
                raise CommandLedgerError(409, "reconciliation_required", "An earlier exchange operation must be reconciled first.")
            version = int(owned["credential_version"])
            permission_version = int(owned["permission_version"])
        try:
            context = self.connections.account_context(principal, connection_id)
            prepared = self._preflight(context, action, identity, operation_id=operation_id)
        except ConnectionServiceError as error:
            raise CommandLedgerError(error.status, error.code, error.message) from None
        except OKXError:
            raise CommandLedgerError(502, "preflight_unavailable", "The selected exchange target could not be verified.") from None

        intent_json = json.dumps({"action": action, "identity": identity}, sort_keys=True, separators=(",", ":"))
        request_hash = hashlib.sha256(intent_json.encode("utf-8")).hexdigest()
        confirmation = secrets.token_urlsafe(32)
        confirmation_digest = self._digest(confirmation)
        now = self._clock()
        expires_at = now + self.CONFIRMATION_SECONDS
        payload = {
            "action": action,
            "identity": identity,
            "targets": prepared.get("targets", [prepared.get("target")]),
            "summary": prepared["summary"],
            "remoteIdentityDigest": prepared["uidDigest"],
        }
        try:
            with self.store.transaction() as connection:
                self._require_principal(connection, principal, step_up=True)
                owned = self.connections._connection_row(connection, principal.user_id, connection_id, lock=True)
                if owned is None:
                    raise CommandLedgerError(404, "not_found", "The requested resource was not found.")
                lease = connection.execute(
                    "SELECT lease_until FROM multiuser_connection_leases WHERE user_id=? AND connection_id=?" + self._suffix(),
                    (principal.user_id, connection_id),
                ).fetchone()
                now = self._clock()
                if (
                    owned["status"] != "ACTIVE"
                    or int(owned["credential_version"]) != version
                    or int(owned["permission_version"]) != permission_version
                    or (lease is not None and lease["lease_until"] is not None and float(lease["lease_until"]) > now)
                    or self.connections._has_unresolved_activity(connection, principal.user_id, connection_id, now)
                ):
                    raise CommandLedgerError(409, "connection_changed", "The connection changed during action preparation.")
                self._require_principal(connection, principal, step_up=True)
                now = self._clock()
                connection.execute(
                    "INSERT INTO multiuser_operations(user_id, connection_id, operation_id, product, idempotency_key, request_hash, status, created_at, updated_at, payload_json, connection_version, permission_version, expires_at, confirmation_digest) "
                    "VALUES (?, ?, ?, ?, ?, ?, 'PREPARED', ?, ?, ?, ?, ?, ?, ?)",
                    (principal.user_id, connection_id, operation_id, prepared["product"], "prepared:" + operation_id,
                     request_hash, now, now, json.dumps(payload, sort_keys=True, separators=(",", ":")), version,
                     permission_version, expires_at, confirmation_digest),
                )
                for target_index, target in enumerate(payload["targets"]):
                    if not isinstance(target, dict):
                        raise CommandLedgerError(409, "action_corrupt", "The prepared action is unavailable.")
                    connection.execute(
                        "INSERT INTO multiuser_command_targets(user_id, connection_id, operation_id, target_index, request_json, status, updated_at) VALUES (?, ?, ?, ?, ?, 'PREPARED', ?)",
                        (principal.user_id, connection_id, operation_id, target_index,
                         json.dumps(target, sort_keys=True, separators=(",", ":")), now),
                    )
                self._event(connection, principal.user_id, connection_id, operation_id, "action_prepared", {"action": action}, now)
                operation = connection.execute(
                    "SELECT * FROM multiuser_operations WHERE user_id=? AND connection_id=? AND operation_id=?",
                    (principal.user_id, connection_id, operation_id),
                ).fetchone()
                targets = connection.execute(
                    "SELECT * FROM multiuser_command_targets WHERE user_id=? AND connection_id=? AND operation_id=? ORDER BY target_index",
                    (principal.user_id, connection_id, operation_id),
                ).fetchall()
        except Exception:
            raise
        result = self._public(operation, targets)
        result["confirmationToken"] = confirmation
        result["summary"] = prepared["summary"]
        return result

    def _load_execute(self, principal: Principal, connection_id: str, operation_id: str, confirmation: str, idempotency_key: str) -> tuple[Any, list[Any], Any] | dict[str, Any]:
        now = self._clock()
        expired = False
        loaded: tuple[Any, list[Any], Any] | None = None
        with self.store.transaction() as connection:
            self._require_principal(connection, principal, step_up=False)
            owned = self.connections._connection_row(connection, principal.user_id, connection_id, lock=True)
            if owned is None:
                raise CommandLedgerError(404, "not_found", "The requested resource was not found.")
            operation = connection.execute(
                "SELECT * FROM multiuser_operations WHERE user_id=? AND connection_id=? AND operation_id=?" + self._suffix(),
                (principal.user_id, connection_id, operation_id),
            ).fetchone()
            if operation is None:
                raise CommandLedgerError(404, "not_found", "The requested resource was not found.")
            by_key = connection.execute(
                "SELECT * FROM multiuser_operations WHERE user_id=? AND connection_id=? AND idempotency_key=?" + self._suffix(),
                (principal.user_id, connection_id, idempotency_key),
            ).fetchone()
            if by_key is not None:
                if by_key["request_hash"] != operation["request_hash"]:
                    raise CommandLedgerError(409, "idempotency_conflict", "The idempotency key belongs to a different action.")
                targets = connection.execute(
                    "SELECT * FROM multiuser_command_targets WHERE user_id=? AND connection_id=? AND operation_id=? ORDER BY target_index",
                    (principal.user_id, connection_id, by_key["operation_id"]),
                ).fetchall()
                return self._public(by_key, targets)
            if operation["status"] != "PREPARED":
                raise CommandLedgerError(409, "confirmation_used", "This action has already been claimed.")
            if not isinstance(confirmation, str) or len(confirmation) > 256 or operation["confirmation_digest"] is None:
                raise CommandLedgerError(403, "invalid_confirmation", "A valid action confirmation is required.")
            if not hmac.compare_digest(str(operation["confirmation_digest"]), self._digest(confirmation)):
                raise CommandLedgerError(403, "invalid_confirmation", "A valid action confirmation is required.")
            now = self._clock()
            if operation["expires_at"] is None or float(operation["expires_at"]) <= now:
                expired = True
                connection.execute(
                    "UPDATE multiuser_command_targets SET status='CANCELED', updated_at=? "
                    "WHERE user_id=? AND connection_id=? AND operation_id=? AND status='PREPARED'",
                    (now, principal.user_id, connection_id, operation_id),
                )
                connection.execute(
                    "UPDATE multiuser_operations SET status='EXPIRED', confirmation_digest=NULL, "
                    "failure_code='confirmation_expired', updated_at=? "
                    "WHERE user_id=? AND connection_id=? AND operation_id=? AND status='PREPARED'",
                    (now, principal.user_id, connection_id, operation_id),
                )
                self._event(connection, principal.user_id, connection_id, operation_id, "action_expired", {}, now)
            targets = connection.execute(
                "SELECT * FROM multiuser_command_targets WHERE user_id=? AND connection_id=? AND operation_id=? ORDER BY target_index",
                (principal.user_id, connection_id, operation_id),
            ).fetchall()
            if not 1 <= len(targets) <= 20 or [int(row["target_index"]) for row in targets] != list(range(len(targets))):
                raise CommandLedgerError(409, "action_corrupt", "The prepared action is unavailable.")
            if not expired:
                # New submissions are sensitive, while a same-key replay above
                # is only an owner-scoped read of a durable operation.
                self._require_principal(connection, principal, step_up=True)
                now = self._clock()
                if operation["expires_at"] is None or float(operation["expires_at"]) <= now:
                    expired = True
                    connection.execute(
                        "UPDATE multiuser_command_targets SET status='CANCELED', updated_at=? "
                        "WHERE user_id=? AND connection_id=? AND operation_id=? AND status='PREPARED'",
                        (now, principal.user_id, connection_id, operation_id),
                    )
                    connection.execute(
                        "UPDATE multiuser_operations SET status='EXPIRED', confirmation_digest=NULL, "
                        "failure_code='confirmation_expired', updated_at=? "
                        "WHERE user_id=? AND connection_id=? AND operation_id=? AND status='PREPARED'",
                        (now, principal.user_id, connection_id, operation_id),
                    )
                    self._event(connection, principal.user_id, connection_id, operation_id, "action_expired", {}, now)
                else:
                    loaded = operation, list(targets), owned
        if expired:
            raise CommandLedgerError(409, "confirmation_expired", "The action confirmation has expired.")
        if loaded is None:
            raise CommandLedgerError(409, "action_changed", "The prepared action changed before execution.")
        return loaded

    def _finish_without_send(self, principal: Principal, connection_id: str, operation_id: str, status: str, reason: str) -> dict[str, Any]:
        now = self._clock()
        with self.store.transaction() as connection:
            self._require_principal(connection, principal, step_up=True)
            self.connections._connection_row(connection, principal.user_id, connection_id, lock=True)
            operation = connection.execute(
                "SELECT * FROM multiuser_operations WHERE user_id=? AND connection_id=? AND operation_id=?" + self._suffix(),
                (principal.user_id, connection_id, operation_id),
            ).fetchone()
            if operation is None or operation["status"] != "PREPARED":
                raise CommandLedgerError(409, "action_changed", "The prepared action changed before execution.")
            target = connection.execute(
                "SELECT * FROM multiuser_command_targets WHERE user_id=? AND connection_id=? AND operation_id=? AND target_index=0" + self._suffix(),
                (principal.user_id, connection_id, operation_id),
            ).fetchone()
            now = self._clock()
            self._require_principal(connection, principal, step_up=True)
            connection.execute(
                "UPDATE multiuser_command_targets SET status=?, result_json=?, updated_at=? WHERE user_id=? AND connection_id=? AND operation_id=? AND target_index=0 AND status='PREPARED'",
                (status, json.dumps({"reason": reason}, separators=(",", ":")), now, principal.user_id, connection_id, operation_id),
            )
            connection.execute(
                "UPDATE multiuser_operations SET status=?, confirmation_digest=NULL, failure_code=?, result_json=?, updated_at=? WHERE user_id=? AND connection_id=? AND operation_id=? AND status='PREPARED'",
                (status, reason, json.dumps({"status": status, "reason": reason}, separators=(",", ":")), now, principal.user_id, connection_id, operation_id),
            )
            self._event(connection, principal.user_id, connection_id, operation_id, "action_not_sent", {"status": status, "reason": reason}, now)
            operation = connection.execute(
                "SELECT * FROM multiuser_operations WHERE user_id=? AND connection_id=? AND operation_id=?",
                (principal.user_id, connection_id, operation_id),
            ).fetchone()
            targets = connection.execute(
                "SELECT * FROM multiuser_command_targets WHERE user_id=? AND connection_id=? AND operation_id=? ORDER BY target_index",
                (principal.user_id, connection_id, operation_id),
            ).fetchall()
        return self._public(operation, targets)

    def _claim_and_mark(self, principal: Principal, connection_id: str, operation_id: str, confirmation: str, idempotency_key: str, prepared_context: ConnectionContext) -> tuple[int, dict[str, Any]] | dict[str, Any]:
        now = self._clock()
        rejection: tuple[int, str, str] | None = None
        already: dict[str, Any] | None = None
        fence: int | None = None
        target_body: dict[str, Any] | None = None
        with self.store.transaction() as connection:
            self._require_principal(connection, principal, step_up=False)
            owned = self.connections._connection_row(connection, principal.user_id, connection_id, lock=True)
            if owned is None:
                raise CommandLedgerError(404, "not_found", "The requested resource was not found.")
            connection.execute(
                "INSERT INTO multiuser_connection_leases(user_id, connection_id, updated_at) VALUES (?, ?, ?) ON CONFLICT(user_id, connection_id) DO NOTHING",
                (principal.user_id, connection_id, now),
            )
            lease = connection.execute(
                "SELECT lease_owner, fence, lease_until, operation_id FROM multiuser_connection_leases WHERE user_id=? AND connection_id=?" + self._suffix(),
                (principal.user_id, connection_id),
            ).fetchone()
            operation = connection.execute(
                "SELECT * FROM multiuser_operations WHERE user_id=? AND connection_id=? AND operation_id=?" + self._suffix(),
                (principal.user_id, connection_id, operation_id),
            ).fetchone()
            if operation is None:
                raise CommandLedgerError(404, "not_found", "The requested resource was not found.")
            by_key = connection.execute(
                "SELECT * FROM multiuser_operations WHERE user_id=? AND connection_id=? AND idempotency_key=?" + self._suffix(),
                (principal.user_id, connection_id, idempotency_key),
            ).fetchone()
            if by_key is not None:
                if by_key["request_hash"] != operation["request_hash"]:
                    raise CommandLedgerError(409, "idempotency_conflict", "The idempotency key belongs to a different action.")
                rows = connection.execute(
                    "SELECT * FROM multiuser_command_targets WHERE user_id=? AND connection_id=? AND operation_id=? ORDER BY target_index",
                    (principal.user_id, connection_id, by_key["operation_id"]),
                ).fetchall()
                already = self._public(by_key, rows)
            elif operation["status"] != "PREPARED":
                raise CommandLedgerError(409, "confirmation_used", "This action has already been claimed.")
            else:
                target = connection.execute(
                    "SELECT * FROM multiuser_command_targets WHERE user_id=? AND connection_id=? AND operation_id=? AND target_index=0" + self._suffix(),
                    (principal.user_id, connection_id, operation_id),
                ).fetchone()
                if target is None:
                    raise CommandLedgerError(409, "action_corrupt", "The prepared action is unavailable.")
                now = self._clock()
                if operation["confirmation_digest"] is None or not hmac.compare_digest(str(operation["confirmation_digest"]), self._digest(confirmation)):
                    rejection = (403, "invalid_confirmation", "A valid action confirmation is required.")
                elif operation["expires_at"] is None or float(operation["expires_at"]) <= now:
                    connection.execute(
                        "UPDATE multiuser_command_targets SET status='CANCELED', updated_at=? WHERE user_id=? AND connection_id=? AND operation_id=? AND status='PREPARED'",
                        (now, principal.user_id, connection_id, operation_id),
                    )
                    connection.execute(
                        "UPDATE multiuser_operations SET status='EXPIRED', confirmation_digest=NULL, failure_code='confirmation_expired', updated_at=? WHERE user_id=? AND connection_id=? AND operation_id=? AND status='PREPARED'",
                        (now, principal.user_id, connection_id, operation_id),
                    )
                    rejection = (409, "confirmation_expired", "The action confirmation has expired.")
                elif not self._trade_enabled:
                    rejection = (403, "trade_disabled", "Multi-user trading is disabled.")
                elif owned["status"] != "ACTIVE" or int(owned["credential_version"]) != int(operation["connection_version"]) or int(owned["permission_version"]) != int(operation["permission_version"]):
                    connection.execute(
                        "UPDATE multiuser_command_targets SET status='CANCELED', updated_at=? WHERE user_id=? AND connection_id=? AND operation_id=? AND status='PREPARED'",
                        (now, principal.user_id, connection_id, operation_id),
                    )
                    connection.execute(
                        "UPDATE multiuser_operations SET status='CANCELED', confirmation_digest=NULL, failure_code='connection_changed', updated_at=? WHERE user_id=? AND connection_id=? AND operation_id=? AND status='PREPARED'",
                        (now, principal.user_id, connection_id, operation_id),
                    )
                    rejection = (409, "connection_changed", "The connection changed after action preparation.")
                elif lease["lease_until"] is not None and float(lease["lease_until"]) > now:
                    rejection = (409, "connection_busy", "Another exchange operation is active.")
                elif self.connections._has_unresolved_activity(connection, principal.user_id, connection_id, now):
                    rejection = (409, "reconciliation_required", "An earlier exchange operation must be reconciled first.")
                elif prepared_context.credential_version != int(owned["credential_version"]) or prepared_context.permission_version != int(owned["permission_version"]):
                    connection.execute(
                        "UPDATE multiuser_command_targets SET status='CANCELED', updated_at=? WHERE user_id=? AND connection_id=? AND operation_id=? AND status='PREPARED'",
                        (now, principal.user_id, connection_id, operation_id),
                    )
                    connection.execute(
                        "UPDATE multiuser_operations SET status='CANCELED', confirmation_digest=NULL, failure_code='connection_changed', updated_at=? WHERE user_id=? AND connection_id=? AND operation_id=? AND status='PREPARED'",
                        (now, principal.user_id, connection_id, operation_id),
                    )
                    rejection = (409, "connection_changed", "The connection changed during action preflight.")
                else:
                    self._require_principal(connection, principal, step_up=True)
                    now = self._clock()
                    # This is the last blocking lock acquisition. Recheck every
                    # authority/version/lease predicate against a fresh clock
                    # immediately before atomically writing the durable marker.
                    if (
                        operation["confirmation_digest"] is None
                        or not hmac.compare_digest(str(operation["confirmation_digest"]), self._digest(confirmation))
                        or operation["expires_at"] is None or float(operation["expires_at"]) <= now
                        or owned["status"] != "ACTIVE"
                        or int(owned["credential_version"]) != int(operation["connection_version"])
                        or int(owned["permission_version"]) != int(operation["permission_version"])
                        or (lease["lease_until"] is not None and float(lease["lease_until"]) > now)
                        or prepared_context.credential_version != int(owned["credential_version"])
                        or prepared_context.permission_version != int(owned["permission_version"])
                        or self.connections._has_unresolved_activity(connection, principal.user_id, connection_id, now)
                    ):
                        rejection = (409, "action_changed", "The action changed before submission.")
                    else:
                        fence = int(lease["fence"]) + 1
                        lease_changed = connection.execute(
                            "UPDATE multiuser_connection_leases SET lease_owner=?, fence=?, lease_until=?, operation_id=?, updated_at=? WHERE user_id=? AND connection_id=? AND fence=? AND (lease_until IS NULL OR lease_until<=?)",
                            (operation_id, fence, now + self.LEASE_SECONDS, operation_id, now, principal.user_id, connection_id, lease["fence"], now),
                        ).rowcount
                        target_body = self._decode(target["request_json"])
                        target_changed = connection.execute(
                            "UPDATE multiuser_command_targets SET status='ATTEMPT_STARTED', pre_send_at=?, updated_at=? WHERE user_id=? AND connection_id=? AND operation_id=? AND target_index=0 AND status='PREPARED'",
                            (now, now, principal.user_id, connection_id, operation_id),
                        ).rowcount
                        operation_changed = connection.execute(
                            "UPDATE multiuser_operations SET status='SENDING', idempotency_key=?, lease_owner=?, lease_fence=?, lease_until=?, pre_send_at=?, confirmation_digest=NULL, confirmation_used_at=?, updated_at=? WHERE user_id=? AND connection_id=? AND operation_id=? AND status='PREPARED' AND confirmation_digest=? AND expires_at> ?",
                            (idempotency_key, operation_id, fence, now + self.LEASE_SECONDS, now, now, now, principal.user_id, connection_id, operation_id, self._digest(confirmation), now),
                        ).rowcount
                        if lease_changed != 1 or target_changed != 1 or operation_changed != 1 or not isinstance(target_body, dict):
                            raise CommandLedgerError(409, "action_claim_lost", "The action changed before submission.")
                        self._event(connection, principal.user_id, connection_id, operation_id, "action_send_marked", {"fence": fence}, now)
        if already is not None:
            return already
        if rejection is not None:
            raise CommandLedgerError(*rejection)
        if fence is None or target_body is None:
            raise CommandLedgerError(409, "action_claim_lost", "The action changed before submission.")
        return fence, target_body

    def _has_other_unresolved_activity(self, connection: Any, user_id: str, connection_id: str, operation_id: str, now: float) -> bool:
        queries = (
            ("SELECT 1 FROM multiuser_command_targets WHERE user_id=? AND connection_id=? AND operation_id<>? AND status IN ('ATTEMPT_STARTED','UNKNOWN') LIMIT 1", (user_id, connection_id, operation_id)),
            ("SELECT 1 FROM multiuser_operations WHERE user_id=? AND connection_id=? AND operation_id<>? AND status IN ('UNKNOWN','SENDING') AND pre_send_at IS NOT NULL LIMIT 1", (user_id, connection_id, operation_id)),
            ("SELECT 1 FROM multiuser_strategy_claims WHERE user_id=? AND connection_id=? AND lease_until>? LIMIT 1", (user_id, connection_id, now)),
            ("SELECT 1 FROM multiuser_strategies WHERE user_id=? AND connection_id=? AND status IN ('APPLYING','UNKNOWN','RECONCILING','QUEUED','PREPARED') LIMIT 1", (user_id, connection_id)),
            ("SELECT 1 FROM multiuser_strategy_reservations WHERE user_id=? AND connection_id=? LIMIT 1", (user_id, connection_id)),
        )
        return any(connection.execute(query, params).fetchone() is not None for query, params in queries)

    def _claim_binance_target(
        self,
        principal: Principal,
        connection_id: str,
        operation_id: str,
        target_index: int,
        confirmation: str,
        idempotency_key: str,
        context: ConnectionContext,
    ) -> tuple[int, dict[str, Any]]:
        target_body: dict[str, Any] | None = None
        fence: int | None = None
        with self.store.transaction() as connection:
            self._require_principal(connection, principal, step_up=False)
            owned = self.connections._connection_row(connection, principal.user_id, connection_id, lock=True)
            if owned is None:
                raise CommandLedgerError(404, "not_found", "The requested resource was not found.")
            connection.execute(
                "INSERT INTO multiuser_connection_leases(user_id, connection_id, updated_at) VALUES (?, ?, ?) ON CONFLICT(user_id, connection_id) DO NOTHING",
                (principal.user_id, connection_id, self._clock()),
            )
            lease = connection.execute(
                "SELECT lease_owner, fence, lease_until, operation_id FROM multiuser_connection_leases WHERE user_id=? AND connection_id=?" + self._suffix(),
                (principal.user_id, connection_id),
            ).fetchone()
            operation = connection.execute(
                "SELECT * FROM multiuser_operations WHERE user_id=? AND connection_id=? AND operation_id=?" + self._suffix(),
                (principal.user_id, connection_id, operation_id),
            ).fetchone()
            target = connection.execute(
                "SELECT * FROM multiuser_command_targets WHERE user_id=? AND connection_id=? AND operation_id=? AND target_index=?" + self._suffix(),
                (principal.user_id, connection_id, operation_id, target_index),
            ).fetchone()
            if operation is None or target is None or lease is None:
                raise CommandLedgerError(409, "action_corrupt", "The prepared action is unavailable.")
            prior = connection.execute(
                "SELECT status FROM multiuser_command_targets WHERE user_id=? AND connection_id=? AND operation_id=? AND target_index<? ORDER BY target_index",
                (principal.user_id, connection_id, operation_id, target_index),
            ).fetchall()
            now = self._clock()
            def lease_current(at: float) -> bool:
                if target_index == 0:
                    return lease["lease_until"] is None or float(lease["lease_until"]) <= at
                return (
                    lease["lease_until"] is not None and float(lease["lease_until"]) > at
                    and lease["lease_owner"] == operation_id
                    and lease["operation_id"] == operation_id
                    and operation["lease_owner"] == operation_id
                    and operation["lease_fence"] is not None
                    and int(operation["lease_fence"]) == int(lease["fence"])
                    and operation["lease_until"] is not None
                    and float(operation["lease_until"]) == float(lease["lease_until"])
                )

            if (
                owned["status"] != "ACTIVE"
                or int(owned["credential_version"]) != int(operation["connection_version"])
                or int(owned["permission_version"]) != int(operation["permission_version"])
                or context.credential_version != int(owned["credential_version"])
                or context.permission_version != int(owned["permission_version"])
                or not lease_current(now)
                or target["status"] != "PREPARED"
                or any(row["status"] != "SUCCEEDED" for row in prior)
                or operation["status"] != ("PREPARED" if target_index == 0 else "SENDING")
                or self._has_other_unresolved_activity(connection, principal.user_id, connection_id, operation_id, now)
            ):
                raise CommandLedgerError(409, "action_changed", "The connection or target changed before submission.")
            if target_index == 0:
                digest = operation["confirmation_digest"]
                if (
                    not isinstance(confirmation, str) or digest is None
                    or not hmac.compare_digest(str(digest), self._digest(confirmation))
                    or operation["expires_at"] is None or float(operation["expires_at"]) <= now
                    or not self._trade_enabled
                ):
                    raise CommandLedgerError(409, "action_changed", "The action confirmation is no longer current.")
                existing_key = connection.execute(
                    "SELECT operation_id FROM multiuser_operations WHERE user_id=? AND connection_id=? AND idempotency_key=?" + self._suffix(),
                    (principal.user_id, connection_id, idempotency_key),
                ).fetchone()
                if existing_key is not None and existing_key["operation_id"] != operation_id:
                    raise CommandLedgerError(409, "idempotency_conflict", "The idempotency key belongs to a different action.")
            elif operation["idempotency_key"] != idempotency_key:
                raise CommandLedgerError(409, "action_changed", "The action idempotency binding changed.")
            self._require_principal(connection, principal, step_up=True)
            now = self._clock()
            if (
                owned["status"] != "ACTIVE"
                or int(owned["credential_version"]) != int(operation["connection_version"])
                or int(owned["permission_version"]) != int(operation["permission_version"])
                or context.credential_version != int(owned["credential_version"])
                or context.permission_version != int(owned["permission_version"])
                or not lease_current(now)
                or target["status"] != "PREPARED"
                or any(row["status"] != "SUCCEEDED" for row in prior)
                or self._has_other_unresolved_activity(connection, principal.user_id, connection_id, operation_id, now)
            ):
                raise CommandLedgerError(409, "action_changed", "The action changed before submission.")
            confirmation_digest: str | None = None
            if target_index == 0:
                digest = operation["confirmation_digest"]
                if (
                    not isinstance(confirmation, str) or not isinstance(digest, str)
                    or not hmac.compare_digest(digest, self._digest(confirmation))
                    or operation["expires_at"] is None or float(operation["expires_at"]) <= now
                    or not self._trade_enabled
                ):
                    raise CommandLedgerError(409, "action_changed", "The action confirmation is no longer current.")
                confirmation_digest = digest
            if target_index == 0:
                fence = int(lease["fence"]) + 1
                lease_changed = connection.execute(
                    "UPDATE multiuser_connection_leases SET lease_owner=?, fence=?, lease_until=?, operation_id=?, updated_at=? WHERE user_id=? AND connection_id=? AND fence=? AND (lease_until IS NULL OR lease_until<=?)",
                    (operation_id, fence, now + self.LEASE_SECONDS, operation_id, now, principal.user_id, connection_id, lease["fence"], now),
                ).rowcount
            else:
                fence = int(lease["fence"])
                lease_changed = connection.execute(
                    "UPDATE multiuser_connection_leases SET lease_until=?, updated_at=? WHERE user_id=? AND connection_id=? AND lease_owner=? AND fence=? AND operation_id=? AND lease_until=? AND lease_until>?",
                    (now + self.LEASE_SECONDS, now, principal.user_id, connection_id, operation_id, fence, operation_id, lease["lease_until"], now),
                ).rowcount
            target_changed = connection.execute(
                "UPDATE multiuser_command_targets SET status='ATTEMPT_STARTED', pre_send_at=?, updated_at=? WHERE user_id=? AND connection_id=? AND operation_id=? AND target_index=? AND status='PREPARED'",
                (now, now, principal.user_id, connection_id, operation_id, target_index),
            ).rowcount
            if target_index == 0:
                operation_changed = connection.execute(
                    "UPDATE multiuser_operations SET status='SENDING', idempotency_key=?, lease_owner=?, lease_fence=?, lease_until=?, pre_send_at=?, confirmation_digest=NULL, confirmation_used_at=?, updated_at=? WHERE user_id=? AND connection_id=? AND operation_id=? AND status='PREPARED' AND confirmation_digest=? AND expires_at>?",
                    (idempotency_key, operation_id, fence, now + self.LEASE_SECONDS, now, now, now, principal.user_id, connection_id, operation_id, confirmation_digest, now),
                ).rowcount
            else:
                operation_changed = connection.execute(
                    "UPDATE multiuser_operations SET lease_until=?, updated_at=? WHERE user_id=? AND connection_id=? AND operation_id=? AND status='SENDING' AND lease_owner=? AND lease_fence=? AND lease_until=?",
                    (now + self.LEASE_SECONDS, now, principal.user_id, connection_id, operation_id, operation_id, fence, operation["lease_until"]),
                ).rowcount
            target_body = self._decode(target["request_json"])
            if lease_changed != 1 or target_changed != 1 or operation_changed != 1 or not isinstance(target_body, dict):
                raise CommandLedgerError(409, "action_claim_lost", "The action changed before submission.")
            self._event(connection, principal.user_id, connection_id, operation_id, "action_send_marked", {"fence": fence, "targetIndex": target_index}, now)
        if fence is None or target_body is None:
            raise CommandLedgerError(409, "action_claim_lost", "The action changed before submission.")
        return fence, target_body

    def _record_binance_target(
        self,
        user_id: str,
        connection_id: str,
        operation_id: str,
        target_index: int,
        fence: int,
        status: str,
        result: dict[str, Any],
        target_count: int,
    ) -> bool:
        now = self._clock()
        continue_operation = False
        with self.store.transaction() as connection:
            self.connections._connection_row(connection, user_id, connection_id, lock=True)
            lease = connection.execute(
                "SELECT lease_owner, fence, lease_until FROM multiuser_connection_leases WHERE user_id=? AND connection_id=?" + self._suffix(),
                (user_id, connection_id),
            ).fetchone()
            operation = connection.execute(
                "SELECT status, lease_owner, lease_fence, lease_until FROM multiuser_operations WHERE user_id=? AND connection_id=? AND operation_id=?" + self._suffix(),
                (user_id, connection_id, operation_id),
            ).fetchone()
            target = connection.execute(
                "SELECT status FROM multiuser_command_targets WHERE user_id=? AND connection_id=? AND operation_id=? AND target_index=?" + self._suffix(),
                (user_id, connection_id, operation_id, target_index),
            ).fetchone()
            now = self._clock()
            if (
                lease is None or lease["lease_owner"] != operation_id or int(lease["fence"]) != fence
                or lease["lease_until"] is None or float(lease["lease_until"]) <= now
                or operation is None or operation["status"] != "SENDING"
                or operation["lease_owner"] != operation_id or operation["lease_fence"] is None
                or int(operation["lease_fence"]) != fence or operation["lease_until"] is None
                or float(operation["lease_until"]) != float(lease["lease_until"])
                or target is None or target["status"] != "ATTEMPT_STARTED"
            ):
                return False
            target_changed = connection.execute(
                "UPDATE multiuser_command_targets SET status=?, result_json=?, updated_at=? WHERE user_id=? AND connection_id=? AND operation_id=? AND target_index=? AND status='ATTEMPT_STARTED'",
                (status, json.dumps(result, sort_keys=True, separators=(",", ":")), now, user_id, connection_id, operation_id, target_index),
            ).rowcount
            if target_changed != 1:
                return False
            prior_successes = connection.execute(
                "SELECT COUNT(*) AS n FROM multiuser_command_targets WHERE user_id=? AND connection_id=? AND operation_id=? AND target_index<? AND status IN ('SUCCEEDED','PARTIAL')",
                (user_id, connection_id, operation_id, target_index),
            ).fetchone()["n"]
            if status == "SUCCEEDED" and target_index + 1 < target_count:
                continue_operation = True
            else:
                final_status = status
                if status == "FAILED" and prior_successes:
                    final_status = "PARTIAL"
                if status == "SUCCEEDED":
                    final_status = "SUCCEEDED"
                connection.execute(
                    "UPDATE multiuser_command_targets SET status='CANCELED', result_json=?, updated_at=? WHERE user_id=? AND connection_id=? AND operation_id=? AND target_index>? AND status='PREPARED'",
                    (json.dumps({"reason": "not_attempted"}, separators=(",", ":")), now, user_id, connection_id, operation_id, target_index),
                )
                summary = {
                    "status": final_status,
                    "reason": result.get("reason", "target_outcome_recorded"),
                    "completedTargets": int(prior_successes) + (1 if status in {"SUCCEEDED", "PARTIAL"} else 0),
                    "targetCount": target_count,
                }
                operation_changed = connection.execute(
                    "UPDATE multiuser_operations SET status=?, result_json=?, lease_owner=NULL, lease_until=NULL, failure_code=?, updated_at=? WHERE user_id=? AND connection_id=? AND operation_id=? AND status='SENDING' AND lease_owner=? AND lease_fence=? AND lease_until=?",
                    (final_status, json.dumps(summary, sort_keys=True, separators=(",", ":")), result.get("reason"), now, user_id, connection_id, operation_id, operation_id, fence, lease["lease_until"]),
                ).rowcount
                if operation_changed != 1:
                    raise CommandLedgerError(409, "action_claim_lost", "The exchange result could not be recorded.")
            if not continue_operation:
                lease_changed = connection.execute(
                    "UPDATE multiuser_connection_leases SET lease_owner=NULL, lease_until=NULL, operation_id=NULL, updated_at=? WHERE user_id=? AND connection_id=? AND lease_owner=? AND operation_id=? AND fence=? AND lease_until=? AND lease_until>?",
                    (now, user_id, connection_id, operation_id, operation_id, fence, lease["lease_until"], now),
                ).rowcount
                if lease_changed != 1:
                    raise CommandLedgerError(409, "action_claim_lost", "The exchange result could not be recorded.")
            self._event(connection, user_id, connection_id, operation_id, "action_outcome_recorded", {"status": status, "targetIndex": target_index}, now)
        return continue_operation

    def _finish_binance_before_target(
        self,
        principal: Principal,
        connection_id: str,
        operation_id: str,
        target_index: int,
        reason: str,
    ) -> dict[str, Any]:
        with self.store.transaction() as connection:
            self._require_principal(connection, principal, step_up=True)
            self.connections._connection_row(connection, principal.user_id, connection_id, lock=True)
            operation = connection.execute(
                "SELECT * FROM multiuser_operations WHERE user_id=? AND connection_id=? AND operation_id=?" + self._suffix(),
                (principal.user_id, connection_id, operation_id),
            ).fetchone()
            if operation is None or operation["status"] not in {"PREPARED", "SENDING"}:
                raise CommandLedgerError(409, "action_changed", "The prepared action changed before submission.")
            lease = connection.execute(
                "SELECT lease_owner, fence, lease_until, operation_id FROM multiuser_connection_leases WHERE user_id=? AND connection_id=?" + self._suffix(),
                (principal.user_id, connection_id),
            ).fetchone()
            now = self._clock()
            if lease is None:
                raise CommandLedgerError(409, "action_changed", "The prepared action changed before submission.")
            live_lease = lease["lease_until"] is not None and float(lease["lease_until"]) > now
            owns_live_lease = (
                live_lease
                and lease["lease_owner"] == operation_id
                and lease["operation_id"] == operation_id
                and operation["lease_owner"] == operation_id
                and operation["lease_fence"] is not None
                and int(operation["lease_fence"]) == int(lease["fence"])
                and operation["lease_until"] is not None
                and float(operation["lease_until"]) == float(lease["lease_until"])
            )
            if operation["status"] == "PREPARED":
                if target_index != 0 or live_lease or lease["lease_owner"] not in {None, operation_id}:
                    raise CommandLedgerError(409, "action_changed", "The prepared action changed before submission.")
            elif not owns_live_lease:
                # A caller that lost or never held the active claim must not finalize it.
                raise CommandLedgerError(409, "action_changed", "The prepared action changed before submission.")
            tail = connection.execute(
                "SELECT target_index, status FROM multiuser_command_targets WHERE user_id=? AND connection_id=? AND operation_id=? ORDER BY target_index" + self._suffix(),
                (principal.user_id, connection_id, operation_id),
            ).fetchall()
            if (
                not tail or target_index >= len(tail)
                or any(int(row["target_index"]) >= target_index and row["status"] != "PREPARED" for row in tail)
                or any(int(row["target_index"]) < target_index and row["status"] not in {"SUCCEEDED", "PARTIAL"} for row in tail)
            ):
                raise CommandLedgerError(409, "action_changed", "The prepared action changed before submission.")
            previous = connection.execute(
                "SELECT COUNT(*) AS n FROM multiuser_command_targets WHERE user_id=? AND connection_id=? AND operation_id=? AND target_index<? AND status IN ('SUCCEEDED','PARTIAL')",
                (principal.user_id, connection_id, operation_id, target_index),
            ).fetchone()["n"]
            final_status = "PARTIAL" if previous else "CONFLICT"
            canceled = connection.execute(
                "UPDATE multiuser_command_targets SET status='CANCELED', result_json=?, updated_at=? WHERE user_id=? AND connection_id=? AND operation_id=? AND target_index>=? AND status='PREPARED'",
                (json.dumps({"reason": "not_attempted"}, separators=(",", ":")), now, principal.user_id, connection_id, operation_id, target_index),
            ).rowcount
            if canceled != len(tail) - target_index:
                raise CommandLedgerError(409, "action_changed", "The prepared action changed before submission.")
            result = {
                "status": final_status, "reason": reason,
                "completedTargets": int(previous),
            }
            if operation["status"] == "SENDING":
                operation_changed = connection.execute(
                    "UPDATE multiuser_operations SET status=?, result_json=?, failure_code=?, confirmation_digest=NULL, lease_owner=NULL, lease_until=NULL, updated_at=? WHERE user_id=? AND connection_id=? AND operation_id=? AND status='SENDING' AND lease_owner=? AND lease_fence=? AND lease_until=?",
                    (final_status, json.dumps(result, sort_keys=True, separators=(",", ":")), reason, now, principal.user_id, connection_id, operation_id, operation_id, lease["fence"], lease["lease_until"]),
                ).rowcount
                lease_changed = connection.execute(
                    "UPDATE multiuser_connection_leases SET lease_owner=NULL, lease_until=NULL, operation_id=NULL, updated_at=? WHERE user_id=? AND connection_id=? AND lease_owner=? AND operation_id=? AND fence=? AND lease_until=? AND lease_until>?",
                    (now, principal.user_id, connection_id, operation_id, operation_id, lease["fence"], lease["lease_until"], now),
                ).rowcount
                if operation_changed != 1 or lease_changed != 1:
                    raise CommandLedgerError(409, "action_changed", "The prepared action changed before submission.")
            else:
                operation_changed = connection.execute(
                    "UPDATE multiuser_operations SET status=?, result_json=?, failure_code=?, confirmation_digest=NULL, lease_owner=NULL, lease_until=NULL, updated_at=? WHERE user_id=? AND connection_id=? AND operation_id=? AND status='PREPARED' AND confirmation_digest=?",
                    (final_status, json.dumps(result, sort_keys=True, separators=(",", ":")), reason, now, principal.user_id, connection_id, operation_id, operation["confirmation_digest"]),
                ).rowcount
                if operation_changed != 1:
                    raise CommandLedgerError(409, "action_changed", "The prepared action changed before submission.")
            self._event(connection, principal.user_id, connection_id, operation_id, "action_not_sent", {"status": final_status, "reason": reason, "targetIndex": target_index}, now)
        return self.get_result(principal, connection_id, operation_id)

    @staticmethod
    def _binance_ack(target: dict[str, Any], response: Any) -> tuple[bool, str | None]:
        request = target.get("request")
        if not isinstance(request, dict) or not isinstance(response, dict):
            return False, "ack_unusable"
        action = target.get("action")
        if action == "cancel_order":
            return CommandLedger._binance_cancel_ack(target, response)
        try:
            quantity = decimal_value(request["quantity"])
            original = decimal_value(response.get("origQty"))
        except (KeyError, TypeError):
            return False, "ack_unusable"
        order_id = CommandLedger._native_binance_order_id(response.get("orderId"))
        valid_order_id = order_id is not None
        valid_reduce_only = response.get("reduceOnly") is True or response.get("reduceOnly") == "true"
        if (
            response.get("symbol") != request.get("symbol")
            or response.get("clientOrderId") != request.get("newClientOrderId")
            or response.get("side") != request.get("side")
            or response.get("type") != "MARKET"
            or response.get("positionSide") != "BOTH"
            or not valid_reduce_only
            or not valid_order_id
            or quantity is None or original is None or original != quantity
            or not isinstance(response.get("status"), str)
            or response.get("status") not in CommandLedger._BINANCE_ORDER_STATES
        ):
            return False, "ack_unusable"
        return True, None

    @staticmethod
    def _binance_cancel_ack(target: dict[str, Any], response: Any) -> tuple[bool, str | None]:
        if not isinstance(response, dict):
            return False, "ack_unusable"
        snapshot = target.get("snapshot")
        if not isinstance(snapshot, dict):
            return False, "ack_unusable"
        order_id = CommandLedger._native_binance_order_id(response.get("orderId"))
        original = decimal_value(response.get("origQty"))
        valid_order_id = order_id is not None and order_id == snapshot.get("orderId")
        if (
            response.get("symbol") != target.get("request", {}).get("symbol")
            or not valid_order_id
            or order_id is None
            or response.get("clientOrderId") != snapshot.get("clientOrderId")
            or response.get("side") != snapshot.get("side")
            or response.get("type") != snapshot.get("type")
            or original is None
            or original != decimal_value(snapshot.get("originalQuantity"))
            or not isinstance(response.get("status"), str)
            or response.get("status") not in CommandLedger._BINANCE_ORDER_STATES
        ):
            return False, "ack_unusable"
        return True, None

    def _observe_binance(
        self,
        context: ConnectionContext,
        target: dict[str, Any],
        expected_identity_digest: str,
    ) -> tuple[str, dict[str, Any]]:
        try:
            proof = self._verify_binance_context(context, require_trade=False)
            if not hmac.compare_digest(proof["uidDigest"], expected_identity_digest):
                return "UNKNOWN", {"reason": "account_changed"}
        except CommandLedgerError:
            return "UNKNOWN", {"reason": "account_unavailable"}
        request = target["request"]
        snapshot = target["snapshot"]
        if target["action"] == "cancel_order":
            try:
                order = context.client.usdm.order_by_id(request["symbol"], order_id=request["orderId"])
            except (AdapterError, BinanceTransportError):
                return "UNKNOWN", {"reason": "order_state_unavailable"}
            if not isinstance(order, dict):
                return "UNKNOWN", {"reason": "order_state_unavailable"}
            executed = self._binance_decimal(order.get("executedQty"))
            original = self._binance_decimal(order.get("origQty"))
            price = self._binance_decimal(order.get("price"))
            state = order.get("status")
            order_id = self._native_binance_order_id(order.get("orderId"))
            if (
                order.get("symbol") != request["symbol"]
                or order_id is None
                or order_id != snapshot["orderId"]
                or order.get("clientOrderId") != snapshot["clientOrderId"]
                or order.get("type") != snapshot["type"]
                or order.get("side") != snapshot["side"]
                or original is None or original != decimal_value(snapshot["originalQuantity"])
                or executed is None or executed < 0 or executed > original
                or price is None or price != decimal_value(snapshot["price"])
                or not isinstance(state, str)
                or state not in self._BINANCE_ORDER_STATES
            ):
                return "UNKNOWN", {"reason": "order_state_unavailable"}
            details = {
                "orderState": state,
                "executedQuantity": self._decimal_text(executed),
                "remainingQuantity": self._decimal_text(decimal_subtract(original, executed)),
            }
            if state == "CANCELED":
                return ("PARTIAL" if executed > 0 else "SUCCEEDED"), {"reason": "cancellation_verified", **details}
            if state == "FILLED":
                return "FAILED", {"reason": "order_filled_before_cancellation", **details}
            return "UNKNOWN", {"reason": "cancellation_not_confirmed", **details}

        try:
            order = context.client.usdm.order_by_id(
                request["symbol"], client_order_id=request["newClientOrderId"]
            )
        except (AdapterError, BinanceTransportError):
            return "UNKNOWN", {"reason": "order_state_unavailable"}
        if not isinstance(order, dict):
            return "UNKNOWN", {"reason": "order_state_unavailable"}
        original = self._binance_decimal(order.get("origQty"))
        executed = self._binance_decimal(order.get("executedQty"))
        requested = self._binance_decimal(request.get("quantity"))
        order_id = self._native_binance_order_id(order.get("orderId"))
        if (
            order.get("symbol") != request["symbol"]
            or order.get("clientOrderId") != request["newClientOrderId"]
            or order_id is None
            or order.get("side") != request["side"]
            or order.get("type") != "MARKET"
            or order.get("positionSide") != "BOTH"
            or not (order.get("reduceOnly") is True or order.get("reduceOnly") == "true")
            or original is None or original != requested
            or executed is None or executed < 0 or executed > requested
        ):
            return "UNKNOWN", {"reason": "order_state_unavailable"}
        state = order.get("status")
        if not isinstance(state, str) or state not in self._BINANCE_ORDER_STATES:
            return "UNKNOWN", {"reason": "order_state_unavailable"}
        details = {
            "orderState": state,
            "executedQuantity": self._decimal_text(executed),
            "requestedQuantity": self._decimal_text(requested),
        }
        try:
            current = self._binance_position_snapshot(context, request["symbol"], allow_empty=True)
        except CommandLedgerError:
            return "UNKNOWN", {"reason": "position_state_unavailable", **details}
        before_size = Decimal(snapshot["positionSize"])
        expected_size = max(Decimal("0"), decimal_subtract(before_size, executed))
        sign = int(snapshot["positionSign"])
        exposure_matches = current["size"] == expected_size and (
            expected_size == 0 or current["positionSign"] == sign
        )
        details["remainingPosition"] = self._decimal_text(current["size"])
        if not exposure_matches:
            return "UNKNOWN", {"reason": "position_state_changed", **details}
        if state == "FILLED" and executed == requested:
            return "SUCCEEDED", {"reason": "reduce_only_order_verified", "positionVerified": True, **details}
        if executed > 0 and state in {"CANCELED", "EXPIRED", "EXPIRED_IN_MATCH"}:
            return "PARTIAL", {"reason": "reduce_only_order_partially_filled", "positionVerified": True, **details}
        if state in {"NEW", "PARTIALLY_FILLED"}:
            return "UNKNOWN", {"reason": "reduce_only_order_unresolved", **details}
        if state in {"CANCELED", "EXPIRED", "EXPIRED_IN_MATCH"}:
            return "FAILED", {"reason": "reduce_only_order_not_filled", "positionVerified": True, **details}
        return "UNKNOWN", {"reason": "reduce_only_order_unresolved", **details}

    def _binance_scope_proof(
        self,
        context: ConnectionContext,
        expected_identity_digest: str,
    ) -> tuple[str, dict[str, Any]]:
        try:
            proof = self._verify_binance_context(context, require_trade=False)
            if not hmac.compare_digest(proof["uidDigest"], expected_identity_digest):
                return "UNKNOWN", {"reason": "account_changed"}
            rows = context.client.usdm.position_rows()
        except (AdapterError, BinanceTransportError, CommandLedgerError):
            return "UNKNOWN", {"reason": "scope_unavailable"}
        symbols: set[str] = set()
        for row in rows:
            if not isinstance(row, dict):
                return "UNKNOWN", {"reason": "scope_unavailable"}
            symbol = row.get("symbol")
            amount = self._binance_decimal(row.get("positionAmt"))
            if (
                not isinstance(symbol, str) or not self._BINANCE_SYMBOL_RE.fullmatch(symbol)
                or symbol in symbols or row.get("positionSide") != "BOTH"
                or not isinstance(row.get("marginType"), str)
                or row.get("marginType") not in {"cross", "isolated"} or amount is None
            ):
                return "UNKNOWN", {"reason": "scope_unavailable"}
            symbols.add(symbol)
            if amount != 0:
                return "PARTIAL", {"reason": "unexpected_exposure", "remainingSymbol": symbol}
        return "SUCCEEDED", {"reason": "scope_flat_verified", "positionScopeVerified": True}

    def _execute_binance(
        self,
        principal: Principal,
        connection_id: str,
        operation: Any,
        target_rows: list[Any],
        payload: dict[str, Any],
        confirmation: str,
        idempotency_key: str,
    ) -> dict[str, Any]:
        operation_id = str(operation["operation_id"])
        expected_digest = payload.get("remoteIdentityDigest")
        if not isinstance(expected_digest, str):
            raise CommandLedgerError(409, "action_corrupt", "The action identity binding is unavailable.")
        action = payload.get("action")
        target_count = len(target_rows)
        for target_index, row in enumerate(target_rows):
            target = self._decode(row["request_json"])
            if not isinstance(target, dict) or not isinstance(target.get("identity"), dict):
                return self._finish_binance_before_target(principal, connection_id, operation_id, target_index, "action_corrupt")
            try:
                context = self.connections.account_context(principal, connection_id)
                if action == "close_all":
                    proof = self._verify_binance_context(context)
                    if not hmac.compare_digest(proof["uidDigest"], expected_digest):
                        raise CommandLedgerError(409, "account_changed", "The exchange account changed before submission.")
                    current_target = self._binance_close_target(
                        context, proof, "close_all", target["identity"], operation_id, target_index,
                    )
                else:
                    current = self._preflight_binance(context, str(action), payload["identity"], operation_id)
                    current_target = current["targets"][0]
            except ConnectionServiceError as error:
                return self._finish_binance_before_target(principal, connection_id, operation_id, target_index, error.code)
            except CommandLedgerError as error:
                return self._finish_binance_before_target(principal, connection_id, operation_id, target_index, error.code)
            if (
                current_target.get("snapshot") != target.get("snapshot")
                or current_target.get("request") != target.get("request")
                or not hmac.compare_digest(str(current_target.get("snapshot", {}).get("binding", {}).get("uidDigest", "")), expected_digest)
            ):
                return self._finish_binance_before_target(principal, connection_id, operation_id, target_index, "target_changed_before_send")
            try:
                fence, send_target = self._claim_binance_target(
                    principal, connection_id, operation_id, target_index,
                    confirmation, idempotency_key, context,
                )
            except CommandLedgerError as error:
                # A contender rejected by another live claim must not mutate its owner’s operation.
                try:
                    if target_index == 0:
                        raise error
                    return self._finish_binance_before_target(principal, connection_id, operation_id, target_index, error.code)
                except CommandLedgerError:
                    raise error
            outcome_status: str
            outcome_result: dict[str, Any]
            try:
                if send_target["action"] == "cancel_order":
                    response = context.client.usdm.cancel_regular_order(send_target["request"])
                    accepted, reason = self._binance_ack(send_target, response)
                else:
                    response = context.client.usdm.place_market_reduce(send_target["request"])
                    accepted, reason = self._binance_ack(send_target, response)
                if not accepted:
                    # Keep an unusable/mismatched native acknowledgement unresolved.
                    # Only explicit reconciliation may interpret a later order lookup.
                    outcome_status, outcome_result = "UNKNOWN", {"reason": reason or "ack_unusable"}
                else:
                    outcome_status, outcome_result = self._observe_binance(context, send_target, expected_digest)
            except (BinanceTransportError, AdapterError) as error:
                outcome_status, outcome_result = self._binance_error(error)
            except Exception:
                outcome_status, outcome_result = "UNKNOWN", {"reason": "exchange_outcome_unknown"}
            if action == "close_all" and outcome_status == "SUCCEEDED" and target_index + 1 == target_count:
                try:
                    final_context = self.connections.account_context(principal, connection_id)
                    scope_status, scope_result = self._binance_scope_proof(final_context, expected_digest)
                    if scope_status != "SUCCEEDED":
                        outcome_status, outcome_result = scope_status, scope_result
                except ConnectionServiceError:
                    outcome_status, outcome_result = "UNKNOWN", {"reason": "scope_unavailable"}
            continue_operation = self._record_binance_target(
                principal.user_id, connection_id, operation_id, target_index,
                fence, outcome_status, outcome_result, target_count,
            )
            if not continue_operation:
                break
        return self.get_result(principal, connection_id, operation_id)

    @staticmethod
    def _ack(response: Any) -> tuple[bool, str | None]:
        if not isinstance(response, dict) or response.get("code") != "0":
            return False, "ack_unusable"
        data = response.get("data")
        if not isinstance(data, list) or len(data) != 1 or not isinstance(data[0], dict):
            return False, "ack_unusable"
        code = data[0].get("sCode")
        if code is None:
            return False, "ack_unusable"
        return str(code) == "0", None if str(code) == "0" else "exchange_rejected"

    def _observe(self, context: ConnectionContext, target: dict[str, Any]) -> tuple[str, dict[str, Any]]:
        action = target["action"]
        identity = target["identity"]
        if action == "close_position":
            current = self._read_position(context, identity)
            if current is None:
                return "SUCCEEDED", {"reason": "position_closed_verified", "positionVerified": True}
            return "UNKNOWN", {"reason": "position_still_open", "currentSize": current["size"]}
        current = self._read_order(context, identity)
        if current is None:
            return "UNKNOWN", {"reason": "order_state_unavailable"}
        if current["state"] in {"canceled", "mmp_canceled"}:
            status = "PARTIAL" if Decimal(current["filledSize"]) > 0 else "SUCCEEDED"
            return status, {"reason": "cancellation_verified", "orderState": current["state"], "filledSize": current["filledSize"], "remainingSize": current["remainingSize"]}
        if current["state"] == "filled":
            return "FAILED", {"reason": "order_filled_before_cancellation", "orderState": current["state"], "filledSize": current["filledSize"]}
        return "UNKNOWN", {"reason": "cancellation_not_confirmed", "orderState": current["state"], "filledSize": current["filledSize"], "remainingSize": current["remainingSize"]}

    def execute(self, principal: Principal, connection_id: str, operation_id: str, body: dict[str, Any]) -> dict[str, Any]:
        confirmation = body.get("confirmationToken")
        idempotency_key = body.get("idempotencyKey")
        if set(body) != {"confirmationToken", "idempotencyKey"} or not isinstance(idempotency_key, str) or not self._IDEMPOTENCY_RE.fullmatch(idempotency_key):
            raise CommandLedgerError(400, "action_invalid", "A valid confirmation and idempotency key are required.")
        loaded = self._load_execute(principal, connection_id, operation_id, confirmation, idempotency_key)
        if isinstance(loaded, dict):
            return loaded
        operation, target_rows, owned = loaded
        payload = self._decode(operation["payload_json"])
        if not isinstance(payload, dict) or not target_rows:
            raise CommandLedgerError(409, "action_corrupt", "The prepared action is unavailable.")
        if str(operation["product"]) == "USD_M" and payload.get("action") in self._BINANCE_ACTIONS:
            return self._execute_binance(
                principal, connection_id, operation, target_rows, payload,
                confirmation, idempotency_key,
            )
        target_row = target_rows[0]
        target = self._decode(target_row["request_json"])
        if not isinstance(target, dict):
            raise CommandLedgerError(409, "action_corrupt", "The prepared action is unavailable.")
        try:
            context = self.connections.account_context(principal, connection_id)
            current = self._preflight(context, str(payload["action"]), payload["identity"])
        except ConnectionServiceError as error:
            raise CommandLedgerError(error.status, error.code, error.message) from None
        except (OKXError, CommandLedgerError) as error:
            if isinstance(error, CommandLedgerError):
                return self._finish_without_send(principal, connection_id, operation_id, "CONFLICT", error.code)
            raise CommandLedgerError(502, "preflight_unavailable", "The action could not be rechecked before submission.") from None
        if current["target"]["snapshot"] != target.get("snapshot") or current["uidDigest"] != payload.get("remoteIdentityDigest"):
            return self._finish_without_send(principal, connection_id, operation_id, "CONFLICT", "target_changed_before_send")
        claimed = self._claim_and_mark(principal, connection_id, operation_id, confirmation, idempotency_key, context)
        if isinstance(claimed, dict):
            return claimed
        fence, target = claimed
        try:
            if target["action"] == "close_position":
                response = context.client.close_position(target["request"])
            else:
                response = context.client.cancel_order(target["request"])
            accepted, reason = self._ack(response)
            if not accepted:
                outcome = ("UNKNOWN", {"reason": reason or "ack_unusable"}) if reason == "ack_unusable" else ("FAILED", {"reason": "exchange_rejected"})
            else:
                outcome = self._observe(context, target)
        except OKXTransportError:
            outcome = ("UNKNOWN", {"reason": "exchange_outcome_unknown"})
        except OKXError as error:
            outcome = ("FAILED", {"reason": "exchange_rejected"}) if error.error_code else ("UNKNOWN", {"reason": "exchange_outcome_unknown"})
        except Exception:
            outcome = ("UNKNOWN", {"reason": "exchange_outcome_unknown"})
        self._record_outcome(principal.user_id, connection_id, operation_id, fence, outcome[0], outcome[1])
        return self.get_result(principal, connection_id, operation_id)

    def _finish_binance_reconciliation(
        self,
        user_id: str,
        connection_id: str,
        operation_id: str,
        target_index: int,
        owner: str,
        fence: int,
        status: str,
        result: dict[str, Any],
        target_count: int,
    ) -> None:
        now = self._clock()
        with self.store.transaction() as connection:
            self.connections._connection_row(connection, user_id, connection_id, lock=True)
            lease = connection.execute(
                "SELECT lease_owner, fence, lease_until, operation_id FROM multiuser_connection_leases WHERE user_id=? AND connection_id=?" + self._suffix(),
                (user_id, connection_id),
            ).fetchone()
            operation = connection.execute(
                "SELECT status, lease_owner, lease_fence, lease_until FROM multiuser_operations WHERE user_id=? AND connection_id=? AND operation_id=?" + self._suffix(),
                (user_id, connection_id, operation_id),
            ).fetchone()
            target = connection.execute(
                "SELECT status FROM multiuser_command_targets WHERE user_id=? AND connection_id=? AND operation_id=? AND target_index=?" + self._suffix(),
                (user_id, connection_id, operation_id, target_index),
            ).fetchone()
            now = self._clock()
            if (
                lease is None or lease["lease_owner"] != owner or int(lease["fence"]) != fence
                or lease["operation_id"] != operation_id
                or lease["lease_until"] is None or float(lease["lease_until"]) <= now
                or operation is None or operation["status"] != "RECONCILING"
                or operation["lease_owner"] != owner or operation["lease_fence"] is None
                or int(operation["lease_fence"]) != fence or operation["lease_until"] is None
                or float(operation["lease_until"]) != float(lease["lease_until"])
                or target is None or target["status"] not in {"UNKNOWN", "ATTEMPT_STARTED"}
            ):
                return
            target_changed = connection.execute(
                "UPDATE multiuser_command_targets SET status=?, result_json=?, updated_at=? WHERE user_id=? AND connection_id=? AND operation_id=? AND target_index=? AND status IN ('UNKNOWN','ATTEMPT_STARTED')",
                (status, json.dumps(result, sort_keys=True, separators=(",", ":")), now, user_id, connection_id, operation_id, target_index),
            ).rowcount
            if target_changed != 1:
                return
            connection.execute(
                "UPDATE multiuser_command_targets SET status='CANCELED', result_json=?, updated_at=? WHERE user_id=? AND connection_id=? AND operation_id=? AND target_index>? AND status='PREPARED'",
                (json.dumps({"reason": "not_attempted"}, separators=(",", ":")), now, user_id, connection_id, operation_id, target_index),
            )
            resolved_rows = connection.execute(
                "SELECT status, result_json FROM multiuser_command_targets WHERE user_id=? AND connection_id=? AND operation_id=? ORDER BY target_index",
                (user_id, connection_id, operation_id),
            ).fetchall()
            statuses = [str(row["status"]) for row in resolved_rows]
            if any(value in {"UNKNOWN", "ATTEMPT_STARTED"} for value in statuses):
                final_status = "UNKNOWN"
            elif statuses and all(value == "SUCCEEDED" for value in statuses):
                final_status = "SUCCEEDED"
                operation_row = connection.execute(
                    "SELECT payload_json FROM multiuser_operations WHERE user_id=? AND connection_id=? AND operation_id=?",
                    (user_id, connection_id, operation_id),
                ).fetchone()
                payload = self._decode(operation_row["payload_json"]) if operation_row is not None else None
                if isinstance(payload, dict) and payload.get("action") == "close_all":
                    scope_verified = False
                    for resolved_row in resolved_rows:
                        resolved_result = self._decode(resolved_row["result_json"])
                        if isinstance(resolved_result, dict) and resolved_result.get("positionScopeVerified") is True:
                            scope_verified = True
                            break
                    if not scope_verified:
                        final_status = "PARTIAL"
            elif any(value in {"SUCCEEDED", "PARTIAL"} for value in statuses):
                final_status = "PARTIAL"
            else:
                final_status = "FAILED"
            prior = sum(value in {"SUCCEEDED", "PARTIAL"} for value in statuses[:target_index])
            summary = {
                "status": final_status,
                "reason": result.get("reason", "reconciled"),
                "completedTargets": int(prior) + (1 if status in {"SUCCEEDED", "PARTIAL"} else 0),
                "targetCount": target_count,
            }
            operation_changed = connection.execute(
                "UPDATE multiuser_operations SET status=?, result_json=?, failure_code=?, lease_owner=NULL, lease_until=NULL, updated_at=? WHERE user_id=? AND connection_id=? AND operation_id=? AND status='RECONCILING' AND lease_owner=? AND lease_fence=? AND lease_until=?",
                (final_status, json.dumps(summary, sort_keys=True, separators=(",", ":")), result.get("reason"), now, user_id, connection_id, operation_id, owner, fence, lease["lease_until"]),
            ).rowcount
            lease_changed = connection.execute(
                "UPDATE multiuser_connection_leases SET lease_owner=NULL, lease_until=NULL, operation_id=NULL, updated_at=? WHERE user_id=? AND connection_id=? AND lease_owner=? AND operation_id=? AND fence=? AND lease_until=? AND lease_until>?",
                (now, user_id, connection_id, owner, operation_id, fence, lease["lease_until"], now),
            ).rowcount
            if operation_changed != 1 or lease_changed != 1:
                raise CommandLedgerError(409, "reconciliation_claim_lost", "The action changed before reconciliation completed.")
            self._event(connection, user_id, connection_id, operation_id, "action_reconciled", {"status": final_status, "targetIndex": target_index}, now)
            owned = self.connections._connection_row(connection, user_id, connection_id, lock=True)
            unresolved = self.connections._has_unresolved_activity(connection, user_id, connection_id, now)
            credential = connection.execute(
                "SELECT 1 FROM multiuser_credentials WHERE user_id=? AND connection_id=?",
                (user_id, connection_id),
            ).fetchone()
            if owned is not None and owned["status"] == "RECONCILING" and not unresolved and credential is not None:
                connection.execute(
                    "UPDATE exchange_connections SET status='ACTIVE', updated_at=? WHERE user_id=? AND connection_id=? AND status='RECONCILING'",
                    (now, user_id, connection_id),
                )

    def _finish_binance_crash_recovery(
        self,
        principal: Principal,
        connection_id: str,
        operation_id: str,
        owner: str,
        fence: int,
        target_count: int,
    ) -> None:
        now = self._clock()
        with self.store.transaction() as connection:
            self._require_principal(connection, principal, step_up=True)
            self.connections._connection_row(connection, principal.user_id, connection_id, lock=True)
            lease = connection.execute(
                "SELECT lease_owner, fence, lease_until, operation_id FROM multiuser_connection_leases WHERE user_id=? AND connection_id=?" + self._suffix(),
                (principal.user_id, connection_id),
            ).fetchone()
            operation = connection.execute(
                "SELECT status, lease_owner, lease_fence, lease_until FROM multiuser_operations WHERE user_id=? AND connection_id=? AND operation_id=?" + self._suffix(),
                (principal.user_id, connection_id, operation_id),
            ).fetchone()
            rows = connection.execute(
                "SELECT target_index, status FROM multiuser_command_targets WHERE user_id=? AND connection_id=? AND operation_id=? ORDER BY target_index" + self._suffix(),
                (principal.user_id, connection_id, operation_id),
            ).fetchall()
            now = self._clock()
            if (
                lease is None or lease["lease_owner"] != owner or int(lease["fence"]) != fence
                or lease["operation_id"] != operation_id or lease["lease_until"] is None
                or float(lease["lease_until"]) <= now
                or operation is None or operation["status"] != "RECONCILING"
                or operation["lease_owner"] != owner or int(operation["lease_fence"]) != fence
                or operation["lease_until"] is None or float(operation["lease_until"]) != float(lease["lease_until"])
                or len(rows) != target_count or not any(row["status"] == "PREPARED" for row in rows)
                or any(row["status"] in {"UNKNOWN", "ATTEMPT_STARTED"} for row in rows)
            ):
                return
            canceled = connection.execute(
                "UPDATE multiuser_command_targets SET status='CANCELED', result_json=?, updated_at=? WHERE user_id=? AND connection_id=? AND operation_id=? AND status='PREPARED'",
                (json.dumps({"reason": "not_attempted"}, separators=(",", ":")), now, principal.user_id, connection_id, operation_id),
            ).rowcount
            if canceled == 0:
                return
            statuses = [str(row["status"]) for row in rows]
            if any(value in {"UNKNOWN", "ATTEMPT_STARTED"} for value in statuses):
                return
            completed = sum(value in {"SUCCEEDED", "PARTIAL"} for value in statuses)
            final_status = "PARTIAL" if completed else "FAILED"
            summary = {
                "status": final_status,
                "reason": "process_interrupted",
                "completedTargets": completed,
                "targetCount": target_count,
            }
            operation_changed = connection.execute(
                "UPDATE multiuser_operations SET status=?, result_json=?, failure_code='process_interrupted', lease_owner=NULL, lease_until=NULL, updated_at=? WHERE user_id=? AND connection_id=? AND operation_id=? AND status='RECONCILING' AND lease_owner=? AND lease_fence=? AND lease_until=?",
                (final_status, json.dumps(summary, sort_keys=True, separators=(",", ":")), now, principal.user_id, connection_id, operation_id, owner, fence, lease["lease_until"]),
            ).rowcount
            lease_changed = connection.execute(
                "UPDATE multiuser_connection_leases SET lease_owner=NULL, lease_until=NULL, operation_id=NULL, updated_at=? WHERE user_id=? AND connection_id=? AND lease_owner=? AND operation_id=? AND fence=? AND lease_until=? AND lease_until>?",
                (now, principal.user_id, connection_id, owner, operation_id, fence, lease["lease_until"], now),
            ).rowcount
            if operation_changed != 1 or lease_changed != 1:
                raise CommandLedgerError(409, "reconciliation_claim_lost", "The action changed before recovery completed.")
            self._event(connection, principal.user_id, connection_id, operation_id, "action_reconciled", {
                "status": final_status, "reason": "process_interrupted",
            }, now)
            owned = self.connections._connection_row(connection, principal.user_id, connection_id, lock=True)
            unresolved = self.connections._has_unresolved_activity(connection, principal.user_id, connection_id, now)
            credential = connection.execute(
                "SELECT 1 FROM multiuser_credentials WHERE user_id=? AND connection_id=?",
                (principal.user_id, connection_id),
            ).fetchone()
            if owned is not None and owned["status"] == "RECONCILING" and not unresolved and credential is not None:
                connection.execute(
                    "UPDATE exchange_connections SET status='ACTIVE', updated_at=? WHERE user_id=? AND connection_id=? AND status='RECONCILING'",
                    (now, principal.user_id, connection_id),
                )

    def _reconcile_binance(self, principal: Principal, connection_id: str, operation_id: str) -> dict[str, Any]:
        reconcile_owner = "reconcile-" + uuid.uuid4().hex
        target: dict[str, Any] | None = None
        fence: int | None = None
        operation: Any = None
        target_index: int | None = None
        crash_recovery = False
        with self.store.transaction() as connection:
            self._require_principal(connection, principal, step_up=True)
            owned = self.connections._connection_row(connection, principal.user_id, connection_id, lock=True)
            if owned is None:
                raise CommandLedgerError(404, "not_found", "The requested resource was not found.")
            connection.execute(
                "INSERT INTO multiuser_connection_leases(user_id, connection_id, updated_at) VALUES (?, ?, ?) ON CONFLICT(user_id, connection_id) DO NOTHING",
                (principal.user_id, connection_id, self._clock()),
            )
            lease = connection.execute(
                "SELECT lease_owner, fence, lease_until, operation_id FROM multiuser_connection_leases WHERE user_id=? AND connection_id=?" + self._suffix(),
                (principal.user_id, connection_id),
            ).fetchone()
            operation = connection.execute(
                "SELECT * FROM multiuser_operations WHERE user_id=? AND connection_id=? AND operation_id=?" + self._suffix(),
                (principal.user_id, connection_id, operation_id),
            ).fetchone()
            if operation is None:
                raise CommandLedgerError(404, "not_found", "The requested resource was not found.")
            rows = connection.execute(
                "SELECT * FROM multiuser_command_targets WHERE user_id=? AND connection_id=? AND operation_id=? ORDER BY target_index" + self._suffix(),
                (principal.user_id, connection_id, operation_id),
            ).fetchall()
            unresolved = [row for row in rows if row["status"] in {"UNKNOWN", "ATTEMPT_STARTED"}]
            if not rows:
                raise CommandLedgerError(409, "action_corrupt", "The action result is unavailable.")
            if not unresolved:
                prepared_indices = [int(row["target_index"]) for row in rows if row["status"] == "PREPARED"]
                if operation["status"] not in {"SENDING", "RECONCILING"} or not prepared_indices:
                    return self._public(operation, rows)
                first_prepared = min(prepared_indices)
                if prepared_indices != list(range(first_prepared, len(rows))) or any(
                    row["status"] not in {"SUCCEEDED", "PARTIAL", "PREPARED"} for row in rows
                ):
                    raise CommandLedgerError(409, "action_corrupt", "The action result is unavailable.")
                now = self._clock()
                if lease["lease_until"] is not None and float(lease["lease_until"]) > now:
                    raise CommandLedgerError(409, "connection_busy", "An exchange operation is still active.")
                prior_owner = operation["lease_owner"]
                if operation["status"] == "SENDING":
                    prior_owner = operation_id
                if (
                    prior_owner is None or operation["lease_owner"] != prior_owner
                    or lease["lease_owner"] != prior_owner or lease["operation_id"] != operation_id
                    or operation["lease_fence"] is None or int(operation["lease_fence"]) != int(lease["fence"])
                    or operation["lease_until"] is None or lease["lease_until"] is None
                    or float(operation["lease_until"]) != float(lease["lease_until"])
                ):
                    raise CommandLedgerError(409, "action_corrupt", "The action result is unavailable.")
                self._require_principal(connection, principal, step_up=True)
                now = self._clock()
                if lease["lease_until"] is not None and float(lease["lease_until"]) > now:
                    raise CommandLedgerError(409, "connection_busy", "An exchange operation is still active.")
                fence = int(lease["fence"]) + 1
                lease_changed = connection.execute(
                    "UPDATE multiuser_connection_leases SET lease_owner=?, fence=?, lease_until=?, operation_id=?, updated_at=? WHERE user_id=? AND connection_id=? AND fence=? AND lease_owner=? AND operation_id=? AND lease_until=? AND lease_until<=?",
                    (reconcile_owner, fence, now + self.LEASE_SECONDS, operation_id, now, principal.user_id, connection_id, lease["fence"], prior_owner, operation_id, lease["lease_until"], now),
                ).rowcount
                operation_changed = connection.execute(
                    "UPDATE multiuser_operations SET status='RECONCILING', lease_owner=?, lease_fence=?, lease_until=?, updated_at=? WHERE user_id=? AND connection_id=? AND operation_id=? AND status=? AND lease_owner=? AND lease_fence=? AND lease_until=?",
                    (reconcile_owner, fence, now + self.LEASE_SECONDS, now, principal.user_id, connection_id, operation_id, operation["status"], prior_owner, operation["lease_fence"], operation["lease_until"]),
                ).rowcount
                if lease_changed != 1 or operation_changed != 1:
                    raise CommandLedgerError(409, "reconciliation_claim_lost", "The action changed before recovery.")
                target_count = len(rows)
                crash_recovery = True
                self._event(connection, principal.user_id, connection_id, operation_id, "action_reconciliation_started", {
                    "fence": fence, "reason": "process_interrupted",
                }, now)
            elif len(unresolved) != 1:
                raise CommandLedgerError(409, "action_corrupt", "The action result is unavailable.")
            else:
                row = unresolved[0]
                target_index = int(row["target_index"])
                now = self._clock()
                if lease["lease_until"] is not None and float(lease["lease_until"]) > now:
                    raise CommandLedgerError(409, "connection_busy", "An exchange operation is still active.")
                self._require_principal(connection, principal, step_up=True)
                now = self._clock()
                fence = int(lease["fence"]) + 1
                lease_changed = connection.execute(
                    "UPDATE multiuser_connection_leases SET lease_owner=?, fence=?, lease_until=?, operation_id=?, updated_at=? WHERE user_id=? AND connection_id=? AND fence=? AND (lease_until IS NULL OR lease_until<=?)",
                    (reconcile_owner, fence, now + self.LEASE_SECONDS, operation_id, now, principal.user_id, connection_id, lease["fence"], now),
                ).rowcount
                operation_changed = connection.execute(
                    "UPDATE multiuser_operations SET status='RECONCILING', lease_owner=?, lease_fence=?, lease_until=?, updated_at=? WHERE user_id=? AND connection_id=? AND operation_id=? AND status IN ('UNKNOWN','SENDING','RECONCILING')",
                    (reconcile_owner, fence, now + self.LEASE_SECONDS, now, principal.user_id, connection_id, operation_id),
                ).rowcount
                if lease_changed != 1 or operation_changed != 1:
                    raise CommandLedgerError(409, "reconciliation_claim_lost", "The action changed before reconciliation.")
                target = self._decode(row["request_json"])
                self._event(connection, principal.user_id, connection_id, operation_id, "action_reconciliation_started", {"fence": fence, "targetIndex": target_index}, now)
                target_count = len(rows)
        if crash_recovery:
            if fence is None:
                raise CommandLedgerError(409, "reconciliation_unavailable", "The action result could not be recovered.")
            self._finish_binance_crash_recovery(
                principal, connection_id, operation_id, reconcile_owner, fence, target_count,
            )
            return self.get_result(principal, connection_id, operation_id)
        if target is None or fence is None or target_index is None:
            raise CommandLedgerError(409, "reconciliation_unavailable", "The action result could not be reconciled.")
        try:
            context = self.connections.account_context_for_job(
                principal.user_id, connection_id, operation_id, reconcile_owner, fence,
            )
            payload = self._decode(operation["payload_json"])
            expected_digest = payload.get("remoteIdentityDigest") if isinstance(payload, dict) else None
            if not isinstance(expected_digest, str):
                raise CommandLedgerError(409, "action_corrupt", "The action identity binding is unavailable.")
            self._verify_context(context, require_trade=False, expected_identity_digest=expected_digest)
            if "read:USD_M" not in context.capabilities:
                raise CommandLedgerError(403, "read_not_permitted", "The connection cannot read recovery state.")
            status, result = self._observe_binance(context, target, expected_digest)
            if payload.get("action") == "close_all" and status == "SUCCEEDED" and target_index + 1 == target_count:
                status, result = self._binance_scope_proof(context, expected_digest)
        except (ConnectionServiceError, CommandLedgerError, AdapterError, BinanceTransportError):
            status, result = "UNKNOWN", {"reason": "reconciliation_unavailable"}
        self._finish_binance_reconciliation(
            principal.user_id, connection_id, operation_id, target_index,
            reconcile_owner, fence, status, result, target_count,
        )
        return self.get_result(principal, connection_id, operation_id)

    def _record_outcome(self, user_id: str, connection_id: str, operation_id: str, fence: int, status: str, result: dict[str, Any]) -> None:
        now = self._clock()
        with self.store.transaction() as connection:
            self.connections._connection_row(connection, user_id, connection_id, lock=True)
            lease = connection.execute(
                "SELECT lease_owner, fence, lease_until FROM multiuser_connection_leases WHERE user_id=? AND connection_id=?" + self._suffix(),
                (user_id, connection_id),
            ).fetchone()
            operation = connection.execute(
                "SELECT status FROM multiuser_operations WHERE user_id=? AND connection_id=? AND operation_id=?" + self._suffix(),
                (user_id, connection_id, operation_id),
            ).fetchone()
            target = connection.execute(
                "SELECT status FROM multiuser_command_targets WHERE user_id=? AND connection_id=? AND operation_id=? AND target_index=0" + self._suffix(),
                (user_id, connection_id, operation_id),
            ).fetchone()
            now = self._clock()
            if (
                lease is None or lease["lease_owner"] != operation_id or int(lease["fence"]) != fence
                or lease["lease_until"] is None or float(lease["lease_until"]) <= now
                or operation is None or operation["status"] != "SENDING"
                or target is None or target["status"] != "ATTEMPT_STARTED"
            ):
                return
            result_json = json.dumps(result, sort_keys=True, separators=(",", ":"))
            connection.execute(
                "UPDATE multiuser_command_targets SET status=?, result_json=?, updated_at=? WHERE user_id=? AND connection_id=? AND operation_id=? AND target_index=0 AND status='ATTEMPT_STARTED'",
                (status, result_json, now, user_id, connection_id, operation_id),
            )
            connection.execute(
                "UPDATE multiuser_operations SET status=?, result_json=?, updated_at=? WHERE user_id=? AND connection_id=? AND operation_id=? AND status='SENDING' AND lease_owner=? AND lease_fence=?",
                (status, json.dumps({"targetStatus": status}, separators=(",", ":")), now, user_id, connection_id, operation_id, operation_id, fence),
            )
            connection.execute(
                "UPDATE multiuser_connection_leases SET lease_owner=NULL, lease_until=NULL, operation_id=NULL, updated_at=? WHERE user_id=? AND connection_id=? AND lease_owner=? AND fence=?",
                (now, user_id, connection_id, operation_id, fence),
            )
            self._event(connection, user_id, connection_id, operation_id, "action_outcome_recorded", {"status": status}, now)

    def get_result(self, principal: Principal, connection_id: str, operation_id: str) -> dict[str, Any]:
        now = self._clock()
        with self.store.transaction() as connection:
            self._require_principal(connection, principal, step_up=False)
            operation = connection.execute(
                "SELECT * FROM multiuser_operations WHERE user_id=? AND connection_id=? AND operation_id=?",
                (principal.user_id, connection_id, operation_id),
            ).fetchone()
            if operation is None:
                raise CommandLedgerError(404, "not_found", "The requested resource was not found.")
            targets = connection.execute(
                "SELECT * FROM multiuser_command_targets WHERE user_id=? AND connection_id=? AND operation_id=? ORDER BY target_index",
                (principal.user_id, connection_id, operation_id),
            ).fetchall()
            lease = connection.execute(
                "SELECT lease_until FROM multiuser_connection_leases WHERE user_id=? AND connection_id=?",
                (principal.user_id, connection_id),
            ).fetchone()
            effective = str(operation["status"])
            active = lease is not None and lease["lease_until"] is not None and float(lease["lease_until"]) > now
            if effective in {"SENDING", "RECONCILING"} and not active:
                effective = "UNKNOWN"
            if any(row["status"] == "ATTEMPT_STARTED" for row in targets) and not active:
                effective = "UNKNOWN"
            return self._public(operation, targets, effective_status=effective)

    def reconcile(self, principal: Principal, connection_id: str, operation_id: str) -> dict[str, Any]:
        with self.store.transaction() as connection:
            self._require_principal(connection, principal, step_up=False)
            operation_identity = connection.execute(
                "SELECT product FROM multiuser_operations WHERE user_id=? AND connection_id=? AND operation_id=?",
                (principal.user_id, connection_id, operation_id),
            ).fetchone()
        if operation_identity is not None and operation_identity["product"] == "USD_M":
            return self._reconcile_binance(principal, connection_id, operation_id)
        reconcile_owner = "reconcile-" + uuid.uuid4().hex
        now = self._clock()
        rejection: tuple[int, str, str] | None = None
        target: dict[str, Any] | None = None
        fence: int | None = None
        with self.store.transaction() as connection:
            self._require_principal(connection, principal, step_up=True)
            owned = self.connections._connection_row(connection, principal.user_id, connection_id, lock=True)
            if owned is None:
                raise CommandLedgerError(404, "not_found", "The requested resource was not found.")
            connection.execute(
                "INSERT INTO multiuser_connection_leases(user_id, connection_id, updated_at) VALUES (?, ?, ?) ON CONFLICT(user_id, connection_id) DO NOTHING",
                (principal.user_id, connection_id, now),
            )
            lease = connection.execute(
                "SELECT lease_owner, fence, lease_until FROM multiuser_connection_leases WHERE user_id=? AND connection_id=?" + self._suffix(),
                (principal.user_id, connection_id),
            ).fetchone()
            operation = connection.execute(
                "SELECT * FROM multiuser_operations WHERE user_id=? AND connection_id=? AND operation_id=?" + self._suffix(),
                (principal.user_id, connection_id, operation_id),
            ).fetchone()
            if operation is None:
                raise CommandLedgerError(404, "not_found", "The requested resource was not found.")
            row = connection.execute(
                "SELECT * FROM multiuser_command_targets WHERE user_id=? AND connection_id=? AND operation_id=? AND target_index=0" + self._suffix(),
                (principal.user_id, connection_id, operation_id),
            ).fetchone()
            if row is None:
                raise CommandLedgerError(409, "action_corrupt", "The action result is unavailable.")
            now = self._clock()
            if lease["lease_until"] is not None and float(lease["lease_until"]) > now:
                rejection = (409, "connection_busy", "An exchange operation is still active.")
            elif row["status"] not in {"UNKNOWN", "ATTEMPT_STARTED"}:
                rows = connection.execute(
                    "SELECT * FROM multiuser_command_targets WHERE user_id=? AND connection_id=? AND operation_id=? ORDER BY target_index",
                    (principal.user_id, connection_id, operation_id),
                ).fetchall()
                return self._public(operation, rows)
            else:
                self._require_principal(connection, principal, step_up=True)
                now = self._clock()
                fence = int(lease["fence"]) + 1
                lease_changed = connection.execute(
                    "UPDATE multiuser_connection_leases SET lease_owner=?, fence=?, lease_until=?, operation_id=?, updated_at=? WHERE user_id=? AND connection_id=? AND fence=? AND (lease_until IS NULL OR lease_until<=?)",
                    (reconcile_owner, fence, now + self.LEASE_SECONDS, operation_id, now, principal.user_id, connection_id, lease["fence"], now),
                ).rowcount
                operation_changed = connection.execute(
                    "UPDATE multiuser_operations SET status='RECONCILING', lease_owner=?, lease_fence=?, lease_until=?, updated_at=? WHERE user_id=? AND connection_id=? AND operation_id=? AND status IN ('UNKNOWN','SENDING','RECONCILING')",
                    (reconcile_owner, fence, now + self.LEASE_SECONDS, now, principal.user_id, connection_id, operation_id),
                ).rowcount
                if lease_changed != 1 or operation_changed != 1:
                    raise CommandLedgerError(409, "reconciliation_claim_lost", "The action changed before reconciliation.")
                target = self._decode(row["request_json"])
                self._event(connection, principal.user_id, connection_id, operation_id, "action_reconciliation_started", {"fence": fence}, now)
        if rejection is not None:
            raise CommandLedgerError(*rejection)
        if target is None or fence is None:
            raise CommandLedgerError(409, "reconciliation_unavailable", "The action result could not be reconciled.")
        try:
            context = self.connections.account_context_for_job(
                principal.user_id, connection_id, operation_id, reconcile_owner, fence
            )
            payload = self._decode(operation["payload_json"])
            expected_digest = payload.get("remoteIdentityDigest") if isinstance(payload, dict) else None
            if not isinstance(expected_digest, str):
                raise CommandLedgerError(409, "action_corrupt", "The action identity binding is unavailable.")
            self._verify_context(context, require_trade=False, expected_identity_digest=expected_digest)
            if "read" not in context.capabilities:
                raise CommandLedgerError(403, "read_not_permitted", "The connection cannot read recovery state.")
            status, result = self._observe(context, target)
        except (ConnectionServiceError, CommandLedgerError, OKXError):
            status, result = "UNKNOWN", {"reason": "reconciliation_unavailable"}
        self._finish_reconciliation(principal.user_id, connection_id, operation_id, reconcile_owner, fence, status, result)
        return self.get_result(principal, connection_id, operation_id)

    def _finish_reconciliation(self, user_id: str, connection_id: str, operation_id: str, owner: str, fence: int, status: str, result: dict[str, Any]) -> None:
        now = self._clock()
        with self.store.transaction() as connection:
            self.connections._connection_row(connection, user_id, connection_id, lock=True)
            lease = connection.execute(
                "SELECT lease_owner, fence, lease_until FROM multiuser_connection_leases WHERE user_id=? AND connection_id=?" + self._suffix(),
                (user_id, connection_id),
            ).fetchone()
            operation = connection.execute(
                "SELECT status FROM multiuser_operations WHERE user_id=? AND connection_id=? AND operation_id=?" + self._suffix(),
                (user_id, connection_id, operation_id),
            ).fetchone()
            target = connection.execute(
                "SELECT status FROM multiuser_command_targets WHERE user_id=? AND connection_id=? AND operation_id=? AND target_index=0" + self._suffix(),
                (user_id, connection_id, operation_id),
            ).fetchone()
            now = self._clock()
            if (
                lease is None or lease["lease_owner"] != owner or int(lease["fence"]) != fence
                or lease["lease_until"] is None or float(lease["lease_until"]) <= now
                or operation is None or operation["status"] != "RECONCILING"
                or target is None or target["status"] not in {"UNKNOWN", "ATTEMPT_STARTED"}
            ):
                return
            target_changed = connection.execute(
                "UPDATE multiuser_command_targets SET status=?, result_json=?, updated_at=? WHERE user_id=? AND connection_id=? AND operation_id=? AND target_index=0",
                (status, json.dumps(result, sort_keys=True, separators=(",", ":")), now, user_id, connection_id, operation_id),
            ).rowcount
            operation_changed = connection.execute(
                "UPDATE multiuser_operations SET status=?, result_json=?, lease_owner=NULL, lease_until=NULL, updated_at=? WHERE user_id=? AND connection_id=? AND operation_id=? AND lease_owner=? AND lease_fence=?",
                (status, json.dumps({"targetStatus": status}, separators=(",", ":")), now, user_id, connection_id, operation_id, owner, fence),
            ).rowcount
            lease_changed = connection.execute(
                "UPDATE multiuser_connection_leases SET lease_owner=NULL, lease_until=NULL, operation_id=NULL, updated_at=? WHERE user_id=? AND connection_id=? AND lease_owner=? AND fence=?",
                (now, user_id, connection_id, owner, fence),
            ).rowcount
            if target_changed != 1 or operation_changed != 1 or lease_changed != 1:
                return
            self._event(connection, user_id, connection_id, operation_id, "action_reconciled", {"status": status}, now)
            owned = self.connections._connection_row(connection, user_id, connection_id, lock=True)
            unresolved = self.connections._has_unresolved_activity(connection, user_id, connection_id, now)
            credential = connection.execute(
                "SELECT 1 FROM multiuser_credentials WHERE user_id=? AND connection_id=?",
                (user_id, connection_id),
            ).fetchone()
            if owned is not None and owned["status"] == "RECONCILING" and not unresolved and credential is not None:
                connection.execute(
                    "UPDATE exchange_connections SET status='ACTIVE', updated_at=? WHERE user_id=? AND connection_id=? AND status='RECONCILING'",
                    (now, user_id, connection_id),
                )
