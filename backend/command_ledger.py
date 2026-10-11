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

from .account_context import AccountContextError, VerifiedOKXIdentity, verify_okx_identity
from .connections import ConnectionServiceError, ConnectionContext, OwnedConnections
from .okx import OKXError, OKXTransportError
from .principal import Principal


class CommandLedgerError(Exception):
    def __init__(self, status: int, code: str, message: str):
        super().__init__(message)
        self.status = status
        self.code = code
        self.message = message


class CommandLedger:
    """Prepare and execute only existing OKX close-position and cancel-order actions."""

    CONFIRMATION_SECONDS = 30
    LEASE_SECONDS = 45
    _POSITION_TYPES = frozenset({"SWAP", "FUTURES", "MARGIN"})
    _CANCEL_TYPES = frozenset({"SPOT", "MARGIN", "SWAP", "FUTURES"})
    _TARGET_ID_RE = re.compile(r"[A-Z0-9-]{2,40}\Z")
    _IDEMPOTENCY_RE = re.compile(r"[A-Za-z0-9._:-]{8,128}\Z")

    def __init__(
        self,
        store: Any,
        connections: OwnedConnections,
        *,
        clock: Callable[[], float],
        trade_enabled: bool,
    ):
        self.store = store
        self.connections = connections
        self._clock = clock
        self._trade_enabled = trade_enabled

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

    def _preflight(self, context: ConnectionContext, action: str, identity: dict[str, Any]) -> dict[str, Any]:
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
        if action not in {"close_position", "cancel_order"} or set(body) != {"action", "targetIdentity"}:
            raise CommandLedgerError(422, "capability_unsupported", "Only typed close-position and cancel-order actions are supported.")
        identity = self._identity(action, body["targetIdentity"])
        now = self._clock()
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
            prepared = self._preflight(context, action, identity)
        except ConnectionServiceError as error:
            raise CommandLedgerError(error.status, error.code, error.message) from None
        except OKXError:
            raise CommandLedgerError(502, "preflight_unavailable", "The selected exchange target could not be verified.") from None

        intent_json = json.dumps({"action": action, "identity": identity}, sort_keys=True, separators=(",", ":"))
        request_hash = hashlib.sha256(intent_json.encode("utf-8")).hexdigest()
        operation_id = uuid.uuid4().hex
        confirmation = secrets.token_urlsafe(32)
        confirmation_digest = self._digest(confirmation)
        now = self._clock()
        expires_at = now + self.CONFIRMATION_SECONDS
        payload = {
            "action": action,
            "identity": identity,
            "target": prepared["target"],
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
                target = prepared["target"]
                connection.execute(
                    "INSERT INTO multiuser_command_targets(user_id, connection_id, operation_id, target_index, request_json, status, updated_at) VALUES (?, ?, ?, 0, ?, 'PREPARED', ?)",
                    (principal.user_id, connection_id, operation_id, json.dumps(target, sort_keys=True, separators=(",", ":")), now),
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

    def _load_execute(self, principal: Principal, connection_id: str, operation_id: str, confirmation: str, idempotency_key: str) -> tuple[Any, Any, Any] | dict[str, Any]:
        now = self._clock()
        expired = False
        loaded: tuple[Any, Any, Any] | None = None
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
            if len(targets) != 1:
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
                    loaded = operation, targets[0], owned
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
                "SELECT lease_owner, fence, lease_until FROM multiuser_connection_leases WHERE user_id=? AND connection_id=?" + self._suffix(),
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
        operation, target_row, owned = loaded
        payload = self._decode(operation["payload_json"])
        target = self._decode(target_row["request_json"])
        if not isinstance(payload, dict) or not isinstance(target, dict):
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
