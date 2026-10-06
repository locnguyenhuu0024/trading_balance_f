"""Validated side scope for strategy exposure and reservations."""

from __future__ import annotations

from dataclasses import dataclass
from decimal import Decimal, InvalidOperation
from typing import Any


_POSITION_MODES = frozenset({"net_mode", "long_short_mode"})
_SIDES = frozenset({"long", "short"})


@dataclass(frozen=True)
class StrategyScope:
    position_mode: str
    side_scope: str
    valid: bool


UNKNOWN_SCOPE = StrategyScope("unknown", "all", False)


def _decimal(value: Any) -> Decimal | None:
    if value is None or isinstance(value, (bool, float)):
        return None
    try:
        parsed = Decimal(str(value))
        return parsed if parsed.is_finite() else None
    except (InvalidOperation, TypeError, ValueError):
        return None


def _order_signatures(rows: Any) -> list[tuple[str, str, Decimal]] | None:
    if not isinstance(rows, list) or not rows or len(rows) > 20:
        return None
    signatures: list[tuple[str, str, Decimal]] = []
    seen: set[str] = set()
    for row in rows:
        if not isinstance(row, dict):
            return None
        client_id = row.get("clientOrderId")
        side = row.get("side")
        size = _decimal(row.get("contracts"))
        if (
            not isinstance(client_id, str) or not client_id.strip() or client_id in seen
            or not isinstance(side, str) or side not in _SIDES or size is None or size <= 0
        ):
            return None
        signatures.append((client_id, side, size))
        seen.add(client_id)
    return signatures


def scope_for_sides(position_mode: Any, sides: Any) -> StrategyScope:
    if (
        not isinstance(position_mode, str) or position_mode not in _POSITION_MODES
        or not isinstance(sides, (list, tuple, set, frozenset))
        or any(not isinstance(side, str) for side in sides)
    ):
        return UNKNOWN_SCOPE
    side_set = set(sides)
    if not side_set or not side_set.issubset(_SIDES):
        return UNKNOWN_SCOPE
    if position_mode == "net_mode":
        if len(side_set) != 1:
            return StrategyScope("net_mode", "all", False)
        return StrategyScope("net_mode", "all", True)
    if len(side_set) == 1:
        return StrategyScope("long_short_mode", next(iter(side_set)), True)
    return StrategyScope("long_short_mode", "all", True)


def extract_persisted_scope(
    prepared: Any,
    snapshot: Any,
    stored_orders: Any,
    *,
    require_prepared_mode: bool = True,
) -> StrategyScope:
    """Derive scope only from mutually consistent persisted executable-order evidence."""
    prepared_mode_present = isinstance(prepared, dict) and "_positionMode" in prepared
    snapshot_mode_present = isinstance(snapshot, dict) and "_positionMode" in snapshot
    prepared_mode = prepared.get("_positionMode") if isinstance(prepared, dict) else None
    snapshot_mode = snapshot.get("_positionMode") if isinstance(snapshot, dict) else None

    if require_prepared_mode and not prepared_mode_present:
        return UNKNOWN_SCOPE
    mode = prepared_mode if prepared_mode_present else snapshot_mode
    if not isinstance(mode, str) or mode not in _POSITION_MODES:
        return UNKNOWN_SCOPE
    # Snapshot mode records the draft-time preview. The prepared mode is captured
    # at confirmation time and is authoritative when it is available.
    if snapshot_mode_present and (
        not isinstance(snapshot_mode, str) or snapshot_mode not in _POSITION_MODES
    ):
        return UNKNOWN_SCOPE

    prepared_orders = prepared.get("orders") if isinstance(prepared, dict) else None
    snapshot_orders = snapshot.get("orders") if isinstance(snapshot, dict) else None
    order_lists = [stored_orders, snapshot_orders]
    if require_prepared_mode or prepared_orders is not None:
        order_lists.append(prepared_orders)
    signatures = [_order_signatures(rows) for rows in order_lists]
    if any(value is None for value in signatures):
        return UNKNOWN_SCOPE
    first = signatures[0]
    if any(value != first for value in signatures[1:]):
        return UNKNOWN_SCOPE
    assert first is not None
    return scope_for_sides(mode, [side for _, side, _ in first])


def reservation_scope(position_mode: Any, side_scope: Any) -> StrategyScope:
    if not isinstance(position_mode, str) or not isinstance(side_scope, str):
        return UNKNOWN_SCOPE
    if position_mode == "net_mode" and side_scope == "all":
        return StrategyScope("net_mode", "all", True)
    if position_mode == "long_short_mode" and side_scope in (*_SIDES, "all"):
        return StrategyScope("long_short_mode", side_scope, True)
    return UNKNOWN_SCOPE


def scopes_overlap(left: StrategyScope, right: StrategyScope) -> bool:
    """Only opposite, single-sided Hedge scopes are disjoint."""
    if not left.valid or not right.valid:
        return True
    if left.position_mode != "long_short_mode" or right.position_mode != "long_short_mode":
        return True
    if (
        not isinstance(left.side_scope, str) or left.side_scope not in _SIDES
        or not isinstance(right.side_scope, str) or right.side_scope not in _SIDES
    ):
        return True
    return left.side_scope == right.side_scope


def scoped_position_rows(rows: Any, instrument_id: str, scope: StrategyScope) -> list[dict[str, Any]] | None:
    """Return nonzero positions relevant to a strategy, or None for uncertain evidence."""
    if not scope.valid or not isinstance(rows, list) or not isinstance(instrument_id, str) or not instrument_id:
        return None
    relevant: list[dict[str, Any]] = []
    for row in rows:
        if not isinstance(row, dict):
            return None
        row_instrument = row.get("instId")
        if not isinstance(row_instrument, str) or not row_instrument.strip():
            return None
        if row_instrument != instrument_id:
            continue
        size = _decimal(row.get("pos"))
        side = row.get("posSide")
        if size is None:
            return None
        if scope.position_mode == "net_mode":
            if side != "net":
                return None
        elif not isinstance(side, str) or side not in _SIDES or size < 0:
            return None
        if size == 0:
            continue
        if scope.side_scope == "all" or scope.position_mode == "net_mode" or side == scope.side_scope:
            relevant.append(row)
    return relevant


def scoped_pending_rows(rows: Any, instrument_id: str, scope: StrategyScope) -> list[dict[str, Any]] | None:
    """Return conflicting pending orders, or None when relevant evidence is malformed."""
    if not scope.valid or not isinstance(rows, list) or not isinstance(instrument_id, str) or not instrument_id:
        return None
    conflicts: list[dict[str, Any]] = []
    for row in rows:
        if not isinstance(row, dict):
            return None
        row_instrument = row.get("instId")
        if not isinstance(row_instrument, str) or not row_instrument.strip():
            return None
        if row_instrument != instrument_id:
            continue
        side = row.get("posSide")
        direction = row.get("side")
        size = _decimal(row.get("sz"))
        if (
            size is None or size <= 0 or not isinstance(direction, str)
            or direction not in {"buy", "sell"}
            or (scope.position_mode == "net_mode" and side != "net")
            or (scope.position_mode == "long_short_mode" and (
                not isinstance(side, str) or side not in _SIDES
            ))
        ):
            return None
        if (
            scope.position_mode != "long_short_mode"
            or scope.side_scope == "all"
            or side == scope.side_scope
        ):
            conflicts.append(row)
    return conflicts
