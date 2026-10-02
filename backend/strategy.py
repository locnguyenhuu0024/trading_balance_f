"""Authenticated, durable position-strategy preview and application flow."""

from __future__ import annotations

import hmac
import re
import secrets
import sqlite3
import time
from decimal import Decimal, InvalidOperation, ROUND_CEILING, ROUND_DOWN, ROUND_FLOOR
from typing import Any

from .okx import OKXError, OKXTransportError
from .security import new_confirmation_token, new_operation_id, token_digest
from .service import APIError
from .store import decode_json, encode_json


_INTERVALS = {"6Hutc", "12Hutc", "1Dutc", "1Wutc"}
_MAX_ORDERS = 20
_PREPARE_TTL_SECONDS = 120
_EXECUTION_LEASE_SECONDS = 120
_QUOTE_MAX_AGE_MS = 15_000
_STRATEGY_ID = re.compile(r"[A-Za-z0-9_-]{8,64}\Z")


def _decimal(value: Any) -> Decimal | None:
    if value is None or isinstance(value, (bool, float)):
        return None
    try:
        result = Decimal(str(value))
        return result if result.is_finite() else None
    except (InvalidOperation, ValueError, TypeError):
        return None


def _text(value: Decimal | None) -> str | None:
    if value is None:
        return None
    if value == 0:
        return "0"
    return format(value.normalize(), "f")


def _positive(value: Any) -> Decimal | None:
    parsed = _decimal(value)
    return parsed if parsed is not None and parsed > 0 else None


def _round_up(value: Decimal, increment: Decimal) -> Decimal:
    return (value / increment).to_integral_value(rounding=ROUND_CEILING) * increment


def _round_down(value: Decimal, increment: Decimal) -> Decimal:
    return (value / increment).to_integral_value(rounding=ROUND_FLOOR) * increment


class StrategyService:
    def __init__(self, owner: Any):
        self.owner = owner
        self.store = owner.store
        self.okx = owner.okx
        self.clock = owner.clock

    def dispatch(self, method: str, path: str, body: dict[str, Any]) -> dict[str, Any]:
        if method == "POST" and path == "/v1/strategies/preview":
            return self._preview(body)
        if method == "POST" and path == "/v1/strategies":
            return self._save(body)
        if method == "GET" and path == "/v1/strategies":
            return self._list()
        match = re.fullmatch(r"/v1/strategies/([A-Za-z0-9_-]{8,64})/(prepare-apply|execute-apply|result|delete)", path)
        if match is None:
            raise APIError(404, "not_found", "The requested endpoint was not found.")
        strategy_id, action = match.groups()
        if action == "prepare-apply" and method == "POST":
            return self._prepare(strategy_id)
        if action == "execute-apply" and method == "POST":
            return self._execute(strategy_id, body)
        if action == "result" and method == "GET":
            return self._result(strategy_id)
        if action == "delete" and method == "POST":
            return self._delete(strategy_id)
        raise APIError(404, "not_found", "The requested endpoint was not found.")

    def _invalid(self, reason: str, message: str = "The strategy request is invalid.") -> APIError:
        return APIError(422, "invalid_strategy", message, details={"reason": reason})

    def _account(self) -> tuple[dict[str, Any], str]:
        try:
            account = self.okx.account_config()
        except OKXError:
            raise APIError(502, "exchange_unavailable", "Current account data is unavailable.") from None
        fingerprint = self.owner._account_fingerprint(account.get("uid"))
        if not self.owner._valid_account_fingerprint(fingerprint):
            raise APIError(
                502, "account_identity_unavailable",
                "The exchange account identity is unavailable; try again later.",
            )
        return account, fingerprint

    def _current_strategy(self, strategy_id: str) -> tuple[dict[str, Any], dict[str, Any], str]:
        if not _STRATEGY_ID.fullmatch(strategy_id):
            raise APIError(404, "strategy_not_found", "The strategy was not found.")
        account, fingerprint = self._account()
        with self.store.connection() as connection:
            row = connection.execute(
                "SELECT * FROM strategies WHERE strategy_id=?", (strategy_id,)
            ).fetchone()
        if row is None:
            raise APIError(404, "strategy_not_found", "The strategy was not found.")
        strategy = self._decode_row(row)
        if not hmac.compare_digest(strategy["accountFingerprint"], fingerprint):
            raise APIError(409, "account_changed", "This strategy belongs to a different OKX account.")
        self._expire_prepare(strategy)
        return strategy, account, fingerprint

    @staticmethod
    def _decode_row(row: Any) -> dict[str, Any]:
        return {
            "id": row["strategy_id"],
            "accountFingerprint": row["account_fingerprint"],
            "status": row["status"],
            "contract": decode_json(row["contract_json"]),
            "snapshot": decode_json(row["snapshot_json"]),
            "orders": decode_json(row["orders_json"]),
            "results": decode_json(row["results_json"]),
            "previewHash": row["preview_hash"],
            "confirmationHash": row["confirmation_hash"],
            "preparedExpiresAt": row["prepared_expires_at"],
            "prepared": None if row["prepared_json"] is None else decode_json(row["prepared_json"]),
            "attemptStarted": bool(row["attempt_started"]),
            "batchAttempted": bool(row["batch_attempted"]),
            "executionId": row["execution_id"],
            "executionLeaseUntil": row["execution_lease_until"],
            "leverageResults": decode_json(row["leverage_results_json"]),
            "failureReason": row["failure_reason"],
            "createdAt": row["created_at"],
            "updatedAt": row["updated_at"],
        }

    def _expire_prepare(self, strategy: dict[str, Any]) -> None:
        if strategy["status"] != "PREPARED" or strategy["preparedExpiresAt"] is None:
            return
        if strategy["preparedExpiresAt"] > self.clock():
            return
        with self.store.transaction() as connection:
            connection.execute(
                "UPDATE strategies SET status='DRAFT', confirmation_hash=NULL, prepared_expires_at=NULL, "
                "prepared_json=NULL, updated_at=? WHERE strategy_id=? AND status='PREPARED' "
                "AND prepared_expires_at<=? AND attempt_started=0",
                (self.clock(), strategy["id"], self.clock()),
            )
        strategy["status"] = "DRAFT"
        strategy["confirmationHash"] = None
        strategy["preparedExpiresAt"] = None
        strategy["prepared"] = None
        strategy["updatedAt"] = self.clock()

    def _normalize_contract(self, body: dict[str, Any]) -> dict[str, Any]:
        instrument_id = body.get("instrumentId")
        if not isinstance(instrument_id, str) or re.fullmatch(r"[A-Z0-9]+-USDT-SWAP", instrument_id) is None:
            raise self._invalid("invalid_instrument", "Choose one USDT linear SWAP instrument.")
        interval = body.get("interval")
        if interval not in _INTERVALS:
            raise self._invalid("invalid_interval", "Choose a supported UTC candle interval.")
        total_margin = _positive(body.get("totalMargin"))
        if total_margin is None:
            raise self._invalid("invalid_budget", "Total margin must be a positive decimal amount.")

        levels_value = body.get("selectedLevels")
        if not isinstance(levels_value, list) or not levels_value or len(levels_value) > _MAX_ORDERS:
            raise self._invalid("invalid_order_count", "Select between one and twenty levels.")
        id_mode = (
            "direction" in body
            or "entryLevelIdBySide" in body
            or any(isinstance(row, dict) and "levelId" in row for row in levels_value)
        )
        levels: list[dict[str, str]] = []
        seen: set[tuple[str, str]] = set()
        seen_ids: set[str] = set()
        for row in levels_value:
            if not isinstance(row, dict) or row.get("side") not in ("long", "short"):
                raise self._invalid("invalid_level", "Each selected level must have a Long or Short side.")
            price = _positive(row.get("price"))
            if price is None:
                raise self._invalid("invalid_level", "Selected level prices must be positive decimals.")
            key = (row["side"], _text(price) or "0")
            if id_mode:
                level_id = row.get("levelId")
                if not isinstance(level_id, str) or re.fullmatch(r"[A-Za-z0-9_-]{1,128}", level_id) is None:
                    raise self._invalid("invalid_level_id", "Each selected level needs a valid bounded ID.")
                if level_id in seen_ids:
                    raise self._invalid("duplicate_level_id", "Selected level IDs must be unique.")
                seen_ids.add(level_id)
                levels.append({"side": row["side"], "price": key[1], "levelId": level_id})
            else:
                if key in seen:
                    raise self._invalid("duplicate_level", "A strategy cannot contain duplicate levels.")
                seen.add(key)
                levels.append({"side": row["side"], "price": key[1]})
        sides = sorted({row["side"] for row in levels}, key=lambda side: (side != "long", side))

        entries: dict[str, str] = {}
        entry_ids: dict[str, str] = {}
        if id_mode:
            direction = body.get("direction")
            if direction not in ("long", "short", "both"):
                raise self._invalid("invalid_direction", "Direction must be long, short, or both.")
            expected_sides = {"long"} if direction == "long" else {"short"} if direction == "short" else {"long", "short"}
            if set(sides) != expected_sides:
                raise self._invalid("direction_mismatch", "Direction must match the submitted Long and Short levels.")

            entry_ids_value = body.get("entryLevelIdBySide")
            if not isinstance(entry_ids_value, dict) or set(entry_ids_value) != set(sides):
                raise self._invalid("entry_id_required", "Choose one entry level ID for every selected side.")
            levels_by_id = {row["levelId"]: row for row in levels}
            for side in sides:
                entry_id = entry_ids_value.get(side)
                if not isinstance(entry_id, str) or entry_id not in levels_by_id or levels_by_id[entry_id]["side"] != side:
                    raise self._invalid("entry_id_required", "The entry ID must identify a selected level on its side.")
                entry_ids[side] = entry_id
                entries[side] = levels_by_id[entry_id]["price"]

            if "entryBySide" in body:
                entries_value = body.get("entryBySide")
                if not isinstance(entries_value, dict) or set(entries_value) != set(sides):
                    raise self._invalid("entry_id_price_mismatch", "Legacy entry prices must match the selected entry IDs.")
                for side in sides:
                    entry = _positive(entries_value.get(side))
                    if entry is None or (_text(entry) or "0") != entries[side]:
                        raise self._invalid("entry_id_price_mismatch", "Legacy entry prices must match the selected entry IDs.")
        else:
            entries_value = body.get("entryBySide")
            if not isinstance(entries_value, dict) or set(entries_value) != set(sides):
                raise self._invalid("entry_required", "Choose one nearest entry level for every selected side.")
            for side in sides:
                entry = _positive(entries_value.get(side))
                if entry is None or (side, _text(entry) or "0") not in seen:
                    raise self._invalid("entry_required", "The entry level must be one of the selected levels.")
                entries[side] = _text(entry) or "0"

        leverage_value = body.get("leverage")
        if not isinstance(leverage_value, dict) or set(leverage_value) != set(sides):
            raise self._invalid("invalid_leverage", "Set leverage for every selected side.")
        leverage: dict[str, int] = {}
        for side in sides:
            value = leverage_value.get(side)
            if isinstance(value, bool) or not str(value).isdigit() or not 1 <= int(value) <= 10:
                raise self._invalid("invalid_leverage", "Side leverage must be an integer from 1 through 10.")
            leverage[side] = int(value)

        percentages_value = body.get("sidePercent")
        if percentages_value is None:
            percentages_value = {side: ("50" if len(sides) == 2 else "100") for side in sides}
        if not isinstance(percentages_value, dict) or set(percentages_value) != set(sides):
            raise self._invalid("invalid_side_split", "Set the margin percentage for every selected side.")
        percentages: dict[str, str] = {}
        for side in sides:
            value = _decimal(percentages_value.get(side))
            if value is None or value <= 0 or value > 100:
                raise self._invalid("invalid_side_split", "Each selected side needs a positive margin percentage.")
            percentages[side] = _text(value) or "0"
        if sum((Decimal(value) for value in percentages.values()), Decimal(0)) != Decimal(100):
            raise self._invalid("invalid_side_split", "Side margin percentages must sum to 100.")

        allocation = body.get("allocation", "equal")
        if allocation not in ("equal", "increasing", "decreasing"):
            raise self._invalid("invalid_allocation", "Choose equal, increasing, or decreasing allocation.")
        if id_mode:
            normalized_levels = sorted(
                levels,
                key=lambda row: (
                    sides.index(row["side"]),
                    Decimal(row["price"]),
                    row["levelId"],
                ),
            )
            return {
                "instrumentId": instrument_id,
                "interval": interval,
                "direction": direction,
                "selectedLevels": normalized_levels,
                "entryLevelIdBySide": entry_ids,
                "entryBySide": entries,
                "totalMargin": _text(total_margin) or "0",
                "leverage": leverage,
                "sidePercent": percentages,
                "allocation": allocation,
            }
        return {
            "instrumentId": instrument_id,
            "interval": interval,
            "selectedLevels": sorted(levels, key=lambda row: (sides.index(row["side"]), Decimal(row["price"]))),
            "entryBySide": entries,
            "totalMargin": _text(total_margin) or "0",
            "leverage": leverage,
            "sidePercent": percentages,
            "allocation": allocation,
        }

    def _load_market_inputs(
        self, contract: dict[str, Any]
    ) -> tuple[dict[str, Any], str, dict[str, Decimal], Decimal, list[dict[str, Decimal]]]:
        try:
            account = self.okx.account_config()
            instrument_rows = self.okx.instruments("SWAP")
            ticker = self.okx.ticker(contract["instrumentId"])
            family = contract["instrumentId"][: -len("-SWAP")]
            fee = self.okx.trade_fee(family)
            tier_rows = self.okx.position_tiers(family)
        except OKXError:
            raise APIError(
                502, "preview_inputs_unavailable",
                "Current quote, contract, maintenance-tier, or fee data is unavailable.",
            ) from None

        fingerprint = self.owner._account_fingerprint(account.get("uid"))
        if not self.owner._valid_account_fingerprint(fingerprint):
            raise APIError(502, "account_identity_unavailable", "The exchange account identity is unavailable.")
        instrument = next(
            (row for row in instrument_rows if row.get("instId") == contract["instrumentId"]), None
        )
        if not isinstance(instrument, dict):
            raise self._invalid("instrument_unavailable", "The selected USDT SWAP instrument is unavailable.")
        if (
            instrument.get("instType") != "SWAP"
            or instrument.get("state") != "live"
            or instrument.get("instFamily") != family
        ):
            raise APIError(
                502, "preview_inputs_unavailable",
                "The selected instrument is not a live member of the requested USDT SWAP family.",
            )
        instrument_group_id = instrument.get("groupId")
        if not isinstance(instrument_group_id, str) or not instrument_group_id.strip():
            raise APIError(502, "preview_inputs_unavailable", "The selected instrument's fee group is invalid.")
        base = contract["instrumentId"].split("-", 1)[0]
        instrument_base = instrument.get("baseCcy")
        instrument_quote = instrument.get("quoteCcy")
        base_matches = instrument_base is None or (
            isinstance(instrument_base, str)
            and (not instrument_base.strip() or instrument_base == base)
        )
        quote_matches = instrument_quote is None or (
            isinstance(instrument_quote, str)
            and (not instrument_quote.strip() or instrument_quote == "USDT")
        )
        contract_value = _positive(instrument.get("ctVal"))
        contract_multiplier = _positive(instrument.get("ctMult"))
        tick_size = _positive(instrument.get("tickSz"))
        lot_size = _positive(instrument.get("lotSz"))
        minimum_size = _positive(instrument.get("minSz"))
        if (
            instrument.get("ctType") != "linear"
            or not base_matches or not quote_matches
            or instrument.get("settleCcy") != "USDT"
            or instrument.get("ctValCcy") != base
            or contract_value is None or contract_multiplier is None
            or tick_size is None or lot_size is None or minimum_size is None
        ):
            raise APIError(
                502, "preview_inputs_unavailable",
                "The selected contract is not a validated linear USDT-settled SWAP.",
            )

        last = _positive(ticker.get("last"))
        timestamp = _decimal(ticker.get("ts"))
        if ticker.get("instId") != contract["instrumentId"] or last is None or timestamp is None or timestamp <= 0:
            raise APIError(502, "preview_inputs_unavailable", "The selected SWAP quote is malformed.")
        quote_age = int(self.clock() * 1000) - int(timestamp)
        if quote_age < 0 or quote_age > _QUOTE_MAX_AGE_MS:
            raise APIError(409, "quote_stale", "The selected SWAP quote is stale; refresh the preview.")

        fee_family = fee.get("instFamily")
        fee_groups = fee.get("feeGroup")
        if (
            fee.get("instType") != "SWAP"
            or (fee_family is not None and fee_family != family)
            or not isinstance(fee_groups, list)
            or not fee_groups
            or any(
                not isinstance(group, dict)
                or not isinstance(group.get("groupId"), str)
                or not group["groupId"].strip()
                for group in fee_groups
            )
        ):
            raise APIError(502, "preview_inputs_unavailable", "The account's applicable SWAP fee is invalid.")
        matching_fee_groups = [
            group for group in fee_groups if group["groupId"] == instrument_group_id
        ]
        if len(matching_fee_groups) != 1:
            raise APIError(502, "preview_inputs_unavailable", "The account's applicable SWAP fee is invalid.")
        maker_value = matching_fee_groups[0].get("maker")
        taker_value = matching_fee_groups[0].get("taker")
        maker_signed_fee = _decimal(maker_value) if isinstance(maker_value, str) else None
        taker_signed_fee = _decimal(taker_value) if isinstance(taker_value, str) else None
        if (
            maker_signed_fee is None or abs(maker_signed_fee) >= 1
            or taker_signed_fee is None or abs(taker_signed_fee) >= 1
        ):
            raise APIError(502, "preview_inputs_unavailable", "The account's applicable SWAP fee is invalid.")
        maker_fee = max(Decimal(0), -maker_signed_fee)
        taker_fee = max(Decimal(0), -taker_signed_fee)

        tiers: list[dict[str, Decimal]] = []
        for row in tier_rows:
            minimum = _decimal(row.get("minSz"))
            maximum = _positive(row.get("maxSz"))
            mmr = _decimal(row.get("mmr"))
            max_leverage = _positive(row.get("maxLever"))
            row_type = row.get("instType")
            row_mode = row.get("tdMode")
            if (
                row_type not in (None, "", "SWAP")
                or row_mode not in (None, "", "isolated")
                or row.get("instFamily") != family
                or minimum is None or minimum < 0
                or maximum is None or maximum < minimum
                or mmr is None or not 0 <= mmr < 1
                or max_leverage is None
            ):
                raise APIError(502, "preview_inputs_unavailable", "Current isolated position tiers are invalid.")
            tiers.append({"min": minimum, "max": maximum, "mmr": mmr, "maxLeverage": max_leverage})
        tiers.sort(key=lambda row: (row["min"], row["max"]))
        if not tiers:
            raise APIError(502, "preview_inputs_unavailable", "No validated isolated position tier is available.")
        return account, fingerprint, {
            "contractValue": contract_value,
            "contractMultiplier": contract_multiplier,
            "tickSize": tick_size,
            "lotSize": lot_size,
            "minimumSize": minimum_size,
            "last": last,
            "quoteTimestamp": timestamp,
            "makerFee": maker_fee,
            "takerFee": taker_fee,
        }, taker_fee, tiers

    def _preview_contract(self, contract: dict[str, Any]) -> dict[str, Any]:
        account, fingerprint, meta, fee_rate, tiers = self._load_market_inputs(contract)
        current = meta["last"]
        tick = meta["tickSize"]
        id_mode = "direction" in contract
        levels_by_side: dict[str, list[dict[str, Any]]] = {"long": [], "short": []}
        for row in contract["selectedLevels"]:
            price = Decimal(row["price"])
            if (price / tick) != (price / tick).to_integral_value():
                raise self._invalid("invalid_price_tick", "Every selected limit price must match the current price tick.")
            if row["side"] == "long":
                if price >= current:
                    raise self._invalid("entry_side_invalid", "Long support entries must remain below the current SWAP price.")
            elif price <= current:
                raise self._invalid("entry_side_invalid", "Short resistance entries must remain above the current SWAP price.")
            normalized_row: dict[str, Any] = {"price": price}
            if id_mode:
                normalized_row["levelId"] = row["levelId"]
            levels_by_side[row["side"]].append(normalized_row)

        unit = meta["contractValue"] * meta["contractMultiplier"]
        total_margin = Decimal(contract["totalMargin"])
        orders: list[dict[str, Any]] = []
        total_actual_margin = Decimal(0)
        total_fees = Decimal(0)
        for side in ("long", "short"):
            side_rows = levels_by_side[side]
            if not side_rows:
                continue
            if id_mode:
                side_rows.sort(
                    key=lambda row: (
                        -row["price"] if side == "long" else row["price"],
                        row["levelId"],
                    )
                )
            else:
                side_rows.sort(key=lambda row: row["price"], reverse=(side == "long"))
            entry = Decimal(contract["entryBySide"][side])
            nearest_distance = min(abs(current - row["price"]) for row in side_rows)
            entry_id = contract["entryLevelIdBySide"][side] if id_mode else None
            if id_mode:
                entry_row = next(row for row in side_rows if row["levelId"] == entry_id)
                entry = entry_row["price"]
            if abs(current - entry) != nearest_distance:
                raise self._invalid("entry_not_nearest", "The entry must be the nearest selected level to the current SWAP price.")

            count = len(side_rows)
            if contract["allocation"] == "increasing":
                weights = list(range(1, count + 1))
            elif contract["allocation"] == "decreasing":
                weights = list(range(count, 0, -1))
            else:
                weights = [1] * count
            weight_total = Decimal(sum(weights))
            side_budget = total_margin * Decimal(contract["sidePercent"][side]) / Decimal(100)
            cumulative_contracts = Decimal(0)
            cumulative_notional = Decimal(0)
            cumulative_margin = Decimal(0)
            side_order_start = len(orders)
            for index, (selected_row, weight) in enumerate(zip(side_rows, weights)):
                price = selected_row["price"]
                allocation = side_budget * Decimal(weight) / weight_total
                side_leverage = Decimal(contract["leverage"][side])
                intended_notional = allocation * side_leverage
                contracts = (intended_notional / (price * unit) / meta["lotSize"]).to_integral_value(
                    rounding=ROUND_DOWN
                ) * meta["lotSize"]
                if contracts < meta["minimumSize"]:
                    raise self._invalid(
                        "order_below_minimum",
                        "The margin allocation produces an order below the current contract minimum.",
                    )
                actual_notional = contracts * price * unit
                actual_margin = actual_notional / side_leverage
                opening_fee = actual_notional * fee_rate
                total_actual_margin += actual_margin
                total_fees += opening_fee
                cumulative_contracts += contracts
                cumulative_notional += contracts * price
                cumulative_margin += actual_margin
                cumulative_average = cumulative_notional / cumulative_contracts
                matching_tiers = [
                    item for item in tiers if item["min"] <= cumulative_contracts <= item["max"]
                ]
                if len(matching_tiers) != 1:
                    raise APIError(
                        502, "preview_inputs_unavailable",
                        "The projected size has no unique validated isolated position tier.",
                    )
                tier = matching_tiers[0]
                if side_leverage > tier["maxLeverage"]:
                    raise self._invalid(
                        "leverage_exceeds_tier",
                        "The selected leverage exceeds the current isolated tier limit for this size.",
                    )
                rate = tier["mmr"]
                long_denominator = unit * cumulative_contracts * (Decimal(1) - rate - fee_rate)
                short_denominator = unit * cumulative_contracts * (Decimal(1) + rate + fee_rate)
                if long_denominator <= 0 or short_denominator <= 0:
                    raise APIError(502, "preview_inputs_unavailable", "The liquidation model inputs are invalid.")
                if side == "long":
                    numerator = unit * cumulative_contracts * cumulative_average - cumulative_margin
                    liquidation = (
                        {"status": "no_positive_threshold", "price": None}
                        if numerator <= 0
                        else {"status": "estimated", "price": _text(_round_up(numerator / long_denominator, tick))}
                    )
                else:
                    numerator = unit * cumulative_contracts * cumulative_average + cumulative_margin
                    liquidation = {"status": "estimated", "price": _text(_round_down(numerator / short_denominator, tick))}
                order = {
                    "side": side,
                    "role": (
                        "entry" if selected_row["levelId"] == entry_id else "dca"
                    ) if id_mode else ("entry" if price == entry else "dca"),
                    "limitPrice": _text(price),
                    "contracts": _text(contracts),
                    "leverage": int(side_leverage),
                    "allocatedMargin": _text(allocation),
                    "margin": _text(actual_margin),
                    "notional": _text(actual_notional),
                    "openingFeeEstimate": _text(opening_fee),
                    "allocationWeight": weight,
                    "cumulativeContracts": _text(cumulative_contracts),
                    "cumulativeAverageEntry": _text(cumulative_average),
                    "liquidationEstimate": liquidation,
                }
                if id_mode:
                    order["levelId"] = selected_row["levelId"]
                orders.append(order)

            if id_mode:
                same_price_groups: dict[Decimal, list[int]] = {}
                for order_index in range(side_order_start, len(orders)):
                    price = Decimal(orders[order_index]["limitPrice"])
                    same_price_groups.setdefault(price, []).append(order_index)
                for group_indices in same_price_groups.values():
                    if len(group_indices) < 2:
                        continue
                    group_estimate = orders[group_indices[-1]]["liquidationEstimate"]
                    for order_index in group_indices:
                        orders[order_index]["liquidationEstimate"] = group_estimate
                        orders[order_index]["liquidationEstimateNote"] = (
                            "Estimated after all same-price orders fill; OKX fill order is not guaranteed."
                        )

        unallocated = total_margin - total_actual_margin
        if unallocated < 0:
            raise APIError(502, "preview_inputs_unavailable", "Rounded contract margin exceeded the entered budget.")
        normalized_meta = {
            "contractValue": _text(meta["contractValue"]),
            "contractMultiplier": _text(meta["contractMultiplier"]),
            "contractValueCurrency": "base",
            "tickSize": _text(meta["tickSize"]),
            "lotSize": _text(meta["lotSize"]),
            "minimumSize": _text(meta["minimumSize"]),
            "makerFeeRate": _text(meta["makerFee"]),
            "takerFeeRate": _text(meta["takerFee"]),
            "tiers": [
                {
                    "min": _text(row["min"]), "max": _text(row["max"]),
                    "mmr": _text(row["mmr"]), "maxLeverage": _text(row["maxLeverage"]),
                }
                for row in tiers
            ],
        }
        semantic = {
            "accountFingerprint": fingerprint,
            "contract": contract,
            "metadata": normalized_meta,
            "orders": orders,
        }
        preview_hash = token_digest(encode_json(semantic), self.owner.settings.session_signing_key)
        return {
            "id": None,
            "status": "PREVIEW",
            "instrumentId": contract["instrumentId"],
            "interval": contract["interval"],
            "sides": [side for side in ("long", "short") if levels_by_side[side]],
            "currentPrice": _text(current),
            "quoteTimestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(int(meta["quoteTimestamp"] / 1000))),
            "totalMargin": _text(total_margin),
            "plannedMargin": _text(total_actual_margin),
            "unallocatedMargin": _text(unallocated),
            "estimatedOpeningFees": _text(total_fees),
            "feesOutsideMargin": True,
            "allocation": contract["allocation"],
            "sidePercent": contract["sidePercent"],
            "orders": orders,
            "previewHash": preview_hash,
            "_internal": {
                "metadata": normalized_meta,
                "accountFingerprint": fingerprint,
                "positionMode": account.get("posMode"),
            },
        }

    @staticmethod
    def _public_preview(preview: dict[str, Any]) -> dict[str, Any]:
        return {key: value for key, value in preview.items() if not key.startswith("_")}

    @staticmethod
    def _with_client_ids(preview: dict[str, Any], old_orders: list[dict[str, Any]] | None = None) -> list[dict[str, Any]]:
        id_mode = any("levelId" in row for row in preview["orders"])
        existing: dict[Any, str] = {}
        for row in old_orders or []:
            if id_mode:
                level_id = row.get("levelId")
                if isinstance(level_id, str):
                    existing[level_id] = row.get("clientOrderId", "")
            else:
                existing[(row.get("side", ""), row.get("limitPrice", ""), row.get("role", ""))] = row.get("clientOrderId", "")
        result: list[dict[str, Any]] = []
        for row in preview["orders"]:
            order = dict(row)
            key: Any = order["levelId"] if id_mode else (order["side"], order["limitPrice"], order["role"])
            order["clientOrderId"] = existing.get(key) or "st" + secrets.token_hex(14)
            result.append(order)
        return result

    def _preview(self, body: dict[str, Any]) -> dict[str, Any]:
        contract = self._normalize_contract(body)
        preview = self._preview_contract(contract)
        return self._public_preview(preview)

    def _save(self, body: dict[str, Any]) -> dict[str, Any]:
        contract = self._normalize_contract(body)
        expected = body.get("previewHash")
        if not isinstance(expected, str):
            raise APIError(400, "preview_required", "Submit the preview hash before saving a draft.")
        preview = self._preview_contract(contract)
        if not hmac.compare_digest(preview["previewHash"], expected):
            raise APIError(
                409, "preview_stale", "The authoritative preview changed; review the latest preview before saving.",
                details={"preview": self._public_preview(preview)},
            )
        account_fingerprint = preview["_internal"]["accountFingerprint"]
        orders = self._with_client_ids(preview)
        snapshot = self._public_preview(preview)
        snapshot["orders"] = orders
        snapshot["_metadata"] = preview["_internal"]["metadata"]
        snapshot["_positionMode"] = preview["_internal"]["positionMode"]
        now = self.clock()
        strategy_id = new_operation_id()
        with self.store.transaction() as connection:
            connection.execute(
                "INSERT INTO strategies(strategy_id, account_fingerprint, status, contract_json, snapshot_json, "
                "orders_json, results_json, preview_hash, created_at, updated_at) "
                "VALUES (?, ?, 'DRAFT', ?, ?, ?, ?, ?, ?, ?)",
                (
                    strategy_id, account_fingerprint, encode_json(contract), encode_json(snapshot),
                    encode_json(orders), encode_json([{**row, "status": "not_submitted", "filledContracts": "0"} for row in orders]),
                    preview["previewHash"], now, now,
                ),
            )
        return {
            "id": strategy_id,
            "status": "DRAFT",
            "instrumentId": contract["instrumentId"],
            "interval": contract["interval"],
            "createdAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(now)),
            "orders": orders,
            "preview": self._public_preview(snapshot),
        }

    def _preflight(
        self, contract: dict[str, Any], expected_fingerprint: str
    ) -> tuple[dict[str, Any], dict[str, Any]]:
        account, fingerprint = self._account()
        if not hmac.compare_digest(expected_fingerprint, fingerprint):
            raise APIError(409, "account_changed", "The active OKX account changed; no strategy order was sent.")
        mode = account.get("posMode")
        sides = set(contract["entryBySide"])
        if len(sides) == 2 and mode != "long_short_mode":
            raise APIError(
                409, "account_mode_unsupported",
                "Two-sided strategies require OKX Hedge mode. Change the account mode manually and prepare again.",
            )
        if mode not in ("net_mode", "long_short_mode"):
            raise APIError(409, "account_mode_unsupported", "The current OKX position mode is unsupported.")
        instrument_id = contract["instrumentId"]
        try:
            positions = self.okx.positions("SWAP")
            pending = self.okx.pending_orders(instrument_id)
        except OKXError:
            raise APIError(502, "account_preflight_unavailable", "Current positions or pending orders are unavailable.") from None
        for row in positions:
            if row.get("instId") != instrument_id:
                continue
            size = _decimal(row.get("pos"))
            if size is None or size != 0:
                raise APIError(409, "instrument_position_exists", "Close the existing position for this SWAP before applying.")
        if any(row.get("instId") == instrument_id for row in pending):
            raise APIError(409, "pending_order_exists", "Cancel existing pending orders for this SWAP before applying.")
        preview = self._preview_contract(contract)
        if not hmac.compare_digest(expected_fingerprint, preview["_internal"]["accountFingerprint"]):
            raise APIError(409, "account_changed", "The active OKX account changed; no strategy order was sent.")
        try:
            balance_rows = self.okx.account_balance()
        except OKXError:
            raise APIError(502, "account_preflight_unavailable", "Available USDT balance is unavailable.") from None
        available: Decimal | None = None
        for row in balance_rows:
            details = row.get("details", [])
            if not isinstance(details, list):
                continue
            for detail in details:
                if isinstance(detail, dict) and detail.get("ccy") == "USDT":
                    available = _decimal(detail.get("availBal"))
                    break
            if available is not None:
                break
        required = Decimal(contract["totalMargin"]) + Decimal(preview["estimatedOpeningFees"] or "0")
        if available is None or available < required:
            raise APIError(
                422, "insufficient_balance", "Available USDT does not cover the margin budget and estimated fees.",
                details={"required": _text(required), "available": _text(available)},
            )
        return account, preview

    def _prepare(self, strategy_id: str) -> dict[str, Any]:
        strategy, _, fingerprint = self._current_strategy(strategy_id)
        if strategy["attemptStarted"] or strategy["status"] not in ("DRAFT",):
            raise APIError(409, "strategy_immutable", "This strategy has already entered an application attempt.")
        _, preview = self._preflight(strategy["contract"], fingerprint)
        if not hmac.compare_digest(preview["previewHash"], strategy["previewHash"]):
            raise APIError(
                409, "strategy_stale", "Contract, fee, or tier data changed; recreate and review a fresh draft.",
                details={"preview": self._public_preview(preview)},
            )
        confirmation = new_confirmation_token()
        expires_at = self.clock() + _PREPARE_TTL_SECONDS
        prepared_orders = self._with_client_ids(preview, strategy["orders"])
        prepared = self._public_preview(preview)
        prepared["orders"] = prepared_orders
        prepared["_positionMode"] = preview["_internal"]["positionMode"]
        with self.store.transaction() as connection:
            changed = connection.execute(
                "UPDATE strategies SET status='PREPARED', confirmation_hash=?, prepared_expires_at=?, "
                "prepared_json=?, updated_at=? WHERE strategy_id=? AND status='DRAFT' AND attempt_started=0",
                (
                    token_digest(confirmation, self.owner.settings.session_signing_key),
                    expires_at, encode_json(prepared), self.clock(), strategy_id,
                ),
            ).rowcount
        if changed != 1:
            raise APIError(409, "strategy_state_changed", "The strategy changed; reload it and prepare again.")
        return {
            "id": strategy_id,
            "status": "PREPARED",
            "confirmationToken": confirmation,
            "expiresAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(expires_at)),
            "orders": prepared_orders,
            "plannedMargin": prepared["plannedMargin"],
            "unallocatedMargin": prepared["unallocatedMargin"],
            "estimatedOpeningFees": prepared["estimatedOpeningFees"],
            "quoteTimestamp": prepared["quoteTimestamp"],
        }

    def _claim_execution(self, strategy_id: str, strategy: dict[str, Any], token: str) -> str | None:
        presented = token_digest(token, self.owner.settings.session_signing_key)
        if not isinstance(strategy["confirmationHash"], str) or not hmac.compare_digest(strategy["confirmationHash"], presented):
            raise APIError(403, "invalid_confirmation", "The confirmation token is invalid.")
        execution_id = secrets.token_urlsafe(24)
        now = self.clock()
        try:
            with self.store.transaction() as connection:
                changed = connection.execute(
                    "UPDATE strategies SET status='APPLYING', attempt_started=1, confirmation_hash=NULL, "
                    "execution_id=?, execution_lease_until=?, updated_at=? "
                    "WHERE strategy_id=? AND status='PREPARED' AND attempt_started=0 "
                    "AND confirmation_hash=? AND prepared_expires_at>?",
                    (
                        execution_id, now + _EXECUTION_LEASE_SECONDS, now,
                        strategy_id, presented, now,
                    ),
                ).rowcount
                if changed != 1:
                    return None
                connection.execute(
                    "INSERT INTO strategy_reservations(account_fingerprint, instrument_id, strategy_id, created_at) "
                    "VALUES (?, ?, ?, ?)",
                    (
                        strategy["accountFingerprint"], strategy["contract"]["instrumentId"],
                        strategy_id, now,
                    ),
                )
        except sqlite3.IntegrityError:
            raise APIError(
                409, "instrument_apply_in_progress",
                "Another strategy is applying or reconciling this account and instrument.",
            ) from None
        return execution_id

    def _renew_execution(self, strategy_id: str, execution_id: str) -> bool:
        now = self.clock()
        with self.store.transaction() as connection:
            changed = connection.execute(
                "UPDATE strategies SET execution_lease_until=?, updated_at=? "
                "WHERE strategy_id=? AND status='APPLYING' AND execution_id=? "
                "AND execution_lease_until>?",
                (now + _EXECUTION_LEASE_SECONDS, now, strategy_id, execution_id, now),
            ).rowcount
        return changed == 1

    def _execute(self, strategy_id: str, body: dict[str, Any]) -> dict[str, Any]:
        token = body.get("confirmationToken")
        if not isinstance(token, str) or not token:
            raise APIError(400, "invalid_request", "A confirmation token is required.")
        strategy, _, fingerprint = self._current_strategy(strategy_id)
        if strategy["status"] != "PREPARED":
            return self._basic_result(strategy)
        if strategy["preparedExpiresAt"] is None or strategy["preparedExpiresAt"] <= self.clock():
            self._expire_prepare(strategy)
            return {**self._basic_result(strategy), "prepareExpired": True}
        presented = token_digest(token, self.owner.settings.session_signing_key)
        if not isinstance(strategy["confirmationHash"], str) or not hmac.compare_digest(strategy["confirmationHash"], presented):
            raise APIError(403, "invalid_confirmation", "The confirmation token is invalid.")
        _, live_preview = self._preflight(strategy["contract"], fingerprint)
        prepared = strategy["prepared"] or {}
        if not hmac.compare_digest(live_preview["previewHash"], str(prepared.get("previewHash", ""))):
            self._reset_to_draft(strategy_id)
            raise APIError(
                409, "strategy_stale", "Contract, fee, or tier data changed; review a fresh draft before applying.",
                details={"preview": self._public_preview(live_preview)},
            )
        execution_id = self._claim_execution(strategy_id, strategy, token)
        if execution_id is None:
            latest = self._load_row(strategy_id)
            return self._basic_result(latest)

        orders = prepared.get("orders", [])
        leverage_results: list[dict[str, Any]] = []
        mode = prepared.get("_positionMode")
        if mode not in ("net_mode", "long_short_mode"):
            not_submitted = [{**row, "status": "not_submitted"} for row in orders]
            self._finish(strategy_id, execution_id, "UNKNOWN", not_submitted, "position_mode_unavailable", leverage_results)
            return self._result(strategy_id)
        for side in sorted({row["side"] for row in orders}, key=lambda value: (value != "long", value)):
            if not self._renew_execution(strategy_id, execution_id):
                return self._result(strategy_id)
            side_order = next(row for row in orders if row["side"] == side)
            pos_side = side if mode == "long_short_mode" else "net"
            request = {
                "instId": strategy["contract"]["instrumentId"],
                "lever": str(side_order["leverage"]),
                "mgnMode": "isolated",
                "posSide": pos_side,
            }
            try:
                response = self.okx.set_leverage(request)
            except OKXTransportError:
                leverage_results.append({"side": side, "status": "unknown"})
                not_submitted = [{**row, "status": "not_submitted"} for row in orders]
                self._finish(strategy_id, execution_id, "UNKNOWN", not_submitted, "leverage_unknown", leverage_results)
                return self._result(strategy_id)
            except OKXError:
                leverage_results.append({"side": side, "status": "rejected"})
                not_submitted = [{**row, "status": "not_submitted"} for row in orders]
                self._finish(strategy_id, execution_id, "PARTIAL", not_submitted, "leverage_rejected", leverage_results)
                return self._result(strategy_id)
            data = response.get("data", [])
            if (
                not isinstance(data, list) or len(data) != 1 or not isinstance(data[0], dict)
                or str(data[0].get("sCode", "")) != "0"
            ):
                leverage_results.append({"side": side, "status": "rejected"})
                not_submitted = [{**row, "status": "not_submitted"} for row in orders]
                self._finish(strategy_id, execution_id, "PARTIAL", not_submitted, "leverage_rejected", leverage_results)
                return self._result(strategy_id)
            leverage_results.append({"side": side, "status": "applied"})

        if not self._renew_execution(strategy_id, execution_id):
            return self._result(strategy_id)
        try:
            _, latest_preview = self._preflight(strategy["contract"], fingerprint)
            if not hmac.compare_digest(latest_preview["previewHash"], str(prepared.get("previewHash", ""))):
                not_submitted = [{**row, "status": "not_submitted"} for row in orders]
                self._finish(strategy_id, execution_id, "PARTIAL", not_submitted, "preflight_changed_after_leverage", leverage_results)
                return self._result(strategy_id)
        except APIError:
            not_submitted = [{**row, "status": "not_submitted"} for row in orders]
            self._finish(strategy_id, execution_id, "PARTIAL", not_submitted, "preflight_failed_after_leverage", leverage_results)
            return self._result(strategy_id)

        payload = [self._okx_order(strategy["contract"], row, mode) for row in orders]
        if not self._mark_batch_attempted(strategy_id, execution_id):
            return self._result(strategy_id)
        try:
            response = self.okx.place_batch_orders(payload)
        except OKXTransportError:
            unknown = [{**row, "status": "unknown"} for row in orders]
            self._finish(strategy_id, execution_id, "UNKNOWN", unknown, "batch_unknown", leverage_results)
            return self._result(strategy_id)
        except OKXError:
            unknown = [{**row, "status": "unknown"} for row in orders]
            self._finish(strategy_id, execution_id, "UNKNOWN", unknown, "batch_response_unavailable", leverage_results)
            return self._result(strategy_id)
        outcomes, state, error = self._parse_batch_ack(response, orders)
        self._finish(strategy_id, execution_id, state, outcomes, error, leverage_results)
        return self._result(strategy_id)

    @staticmethod
    def _okx_order(contract: dict[str, Any], row: dict[str, Any], mode: Any) -> dict[str, Any]:
        pos_side = row["side"] if mode == "long_short_mode" else "net"
        return {
            "instId": contract["instrumentId"],
            "tdMode": "isolated",
            "ccy": "USDT",
            "clOrdId": row["clientOrderId"],
            "side": "buy" if row["side"] == "long" else "sell",
            "posSide": pos_side,
            "ordType": "limit",
            "px": row["limitPrice"],
            "sz": row["contracts"],
        }

    @staticmethod
    def _parse_batch_ack(response: dict[str, Any], orders: list[dict[str, Any]]) -> tuple[list[dict[str, Any]], str, str | None]:
        top_code = str(response.get("code", ""))
        data = response.get("data")
        if top_code not in ("0", "1", "2") or not isinstance(data, list) or len(data) != len(orders):
            return [{**row, "status": "unknown"} for row in orders], "UNKNOWN", "batch_ack_malformed"
        by_client: dict[str, dict[str, Any]] = {}
        for item in data:
            if not isinstance(item, dict) or not isinstance(item.get("clOrdId"), str) or item["clOrdId"] in by_client:
                return [{**row, "status": "unknown"} for row in orders], "UNKNOWN", "batch_ack_malformed"
            by_client[item["clOrdId"]] = item
        if set(by_client) != {row["clientOrderId"] for row in orders}:
            return [{**row, "status": "unknown"} for row in orders], "UNKNOWN", "batch_ack_malformed"
        outcomes: list[dict[str, Any]] = []
        rejected = False
        for order in orders:
            item = by_client[order["clientOrderId"]]
            code = str(item.get("sCode", ""))
            if code == "0" and isinstance(item.get("ordId"), str) and item["ordId"]:
                outcomes.append({**order, "status": "accepted", "exchangeOrderId": item["ordId"]})
            elif code and code != "0":
                rejected = True
                outcomes.append({**order, "status": "rejected", "errorCode": code})
            else:
                outcomes.append({**order, "status": "unknown"})
        if any(row["status"] == "unknown" for row in outcomes):
            return outcomes, "UNKNOWN", "batch_ack_malformed"
        if rejected:
            return outcomes, "PARTIAL", "order_rejected"
        if top_code in ("1", "2"):
            return outcomes, "UNKNOWN", "batch_top_level_conflict"
        return outcomes, "APPLIED", None

    def _mark_batch_attempted(self, strategy_id: str, execution_id: str) -> bool:
        now = self.clock()
        with self.store.transaction() as connection:
            changed = connection.execute(
                "UPDATE strategies SET batch_attempted=1, execution_lease_until=?, updated_at=? "
                "WHERE strategy_id=? AND status='APPLYING' AND execution_id=? "
                "AND execution_lease_until>? AND batch_attempted=0",
                (now + _EXECUTION_LEASE_SECONDS, now, strategy_id, execution_id, now),
            )
            return changed.rowcount == 1

    def _finish(
        self,
        strategy_id: str,
        execution_id: str,
        status: str,
        orders: list[dict[str, Any]],
        error: str | None,
        leverage_results: list[dict[str, Any]],
    ) -> None:
        with self.store.transaction() as connection:
            current = connection.execute(
                "SELECT batch_attempted FROM strategies WHERE strategy_id=? AND status='APPLYING' "
                "AND execution_id=?",
                (strategy_id, execution_id),
            ).fetchone()
            changed = connection.execute(
                "UPDATE strategies SET status=?, results_json=?, prepared_json=COALESCE(prepared_json, snapshot_json), "
                "leverage_results_json=?, failure_reason=?, execution_id=NULL, execution_lease_until=NULL, "
                "updated_at=? WHERE strategy_id=? AND status='APPLYING' AND execution_id=?",
                (
                    status, encode_json(orders), encode_json(leverage_results), error,
                    self.clock(), strategy_id, execution_id,
                ),
            ).rowcount
            if (
                changed == 1 and current is not None
                and self._can_release_reservation(status, orders, bool(current["batch_attempted"]))
            ):
                connection.execute(
                    "DELETE FROM strategy_reservations WHERE strategy_id=?", (strategy_id,)
                )

    @staticmethod
    def _can_release_reservation(
        status: str, orders: list[dict[str, Any]], batch_attempted: bool
    ) -> bool:
        if status == "UNKNOWN":
            return not batch_attempted
        terminal = {"rejected", "filled", "canceled", "mmp_canceled", "not_submitted"}
        return status in ("APPLIED", "PARTIAL", "UNKNOWN") and all(
            row.get("status") in terminal for row in orders
        )

    def _reset_to_draft(self, strategy_id: str) -> None:
        with self.store.transaction() as connection:
            connection.execute(
                "UPDATE strategies SET status='DRAFT', confirmation_hash=NULL, prepared_expires_at=NULL, "
                "prepared_json=NULL, updated_at=? WHERE strategy_id=? AND status='PREPARED' AND attempt_started=0",
                (self.clock(), strategy_id),
            )

    def _load_row(self, strategy_id: str) -> dict[str, Any]:
        with self.store.connection() as connection:
            row = connection.execute("SELECT * FROM strategies WHERE strategy_id=?", (strategy_id,)).fetchone()
        if row is None:
            raise APIError(404, "strategy_not_found", "The strategy was not found.")
        return self._decode_row(row)

    def _basic_result(self, strategy: dict[str, Any]) -> dict[str, Any]:
        return {
            "id": strategy["id"],
            "status": strategy["status"],
            "instrumentId": strategy["contract"]["instrumentId"],
            "interval": strategy["contract"]["interval"],
            "sides": strategy["snapshot"].get("sides", []),
            "totalMargin": strategy["snapshot"].get("totalMargin"),
            "plannedMargin": strategy["snapshot"].get("plannedMargin"),
            "unallocatedMargin": strategy["snapshot"].get("unallocatedMargin"),
            "estimatedOpeningFees": strategy["snapshot"].get("estimatedOpeningFees"),
            "sidePercent": strategy["snapshot"].get("sidePercent", {}),
            "orders": strategy["results"] if strategy["results"] else strategy["orders"],
            "failureReason": strategy["failureReason"],
            "leverageResults": strategy["leverageResults"],
            "createdAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(strategy["createdAt"])),
            "updatedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(strategy["updatedAt"])),
        }

    def _result(self, strategy_id: str) -> dict[str, Any]:
        strategy, _, fingerprint = self._current_strategy(strategy_id)
        return self._result_for(strategy, fingerprint)

    def _result_for(self, strategy: dict[str, Any], fingerprint: str) -> dict[str, Any]:
        if strategy["status"] == "APPLYING":
            lease_until = strategy["executionLeaseUntil"]
            if lease_until is None or lease_until <= self.clock():
                strategy = self._recover_interrupted_apply(strategy)
        elif strategy["status"] in ("UNKNOWN", "APPLIED", "PARTIAL"):
            strategy = self._reconcile_orders(strategy)
        try:
            account, current_fingerprint = self._account()
            if not hmac.compare_digest(fingerprint, current_fingerprint):
                raise APIError(409, "account_changed", "The active OKX account changed.")
        except APIError:
            raise
        position_status = "available"
        position_rows: list[dict[str, Any]] = []
        try:
            raw_positions = self.okx.positions("SWAP")
        except OKXError:
            raw_positions = []
            position_status = "unavailable"
        actual = [
            row for row in raw_positions
            if row.get("instId") == strategy["contract"]["instrumentId"]
            and (_decimal(row.get("pos")) is None or _decimal(row.get("pos")) != 0)
        ]
        if position_status == "available" and actual:
            position_status = "present"
        if position_status == "available" and not actual:
            position_status = "none"
        for row in actual:
            position_rows.append({
                "side": row.get("posSide"),
                "contracts": row.get("pos"),
                "averageEntry": row.get("avgPx"),
                "markPrice": row.get("markPx"),
                "liquidationPrice": row.get("liqPx"),
                "unrealizedPnl": row.get("upl"),
                "marginMode": row.get("mgnMode"),
            })
        observed = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(self.clock()))
        filled_margin: Decimal | None = Decimal(0)
        expected_by_side = {"long": Decimal(0), "short": Decimal(0)}
        for row in strategy["results"]:
            filled = _decimal(row.get("filledContracts", "0")) or Decimal(0)
            if filled <= 0:
                continue
            order_price = _positive(row.get("averageFillPrice"))
            if order_price is None:
                filled_margin = None
                expected_by_side[row["side"]] += filled
                continue
            unit = Decimal(strategy["snapshot"]["_metadata"]["contractValue"]) * Decimal(
                strategy["snapshot"]["_metadata"]["contractMultiplier"]
            )
            margin = filled * order_price * unit / Decimal(str(row["leverage"]))
            if filled_margin is not None:
                filled_margin += margin
            expected_by_side[row["side"]] += filled
        pnl_values = [_decimal(row.get("upl")) for row in actual]
        pnl_values = [value for value in pnl_values if value is not None]
        pnl = sum(pnl_values, Decimal(0)) if pnl_values else None
        pnl_percent = (
            None
            if filled_margin is None or filled_margin <= 0 or pnl is None
            else pnl / filled_margin * Decimal(100)
        )
        attribution_changed: bool | None = None if position_status == "unavailable" else False
        actual_by_side = {"long": Decimal(0), "short": Decimal(0)}
        for row in actual:
            size = _decimal(row.get("pos"))
            if size is None:
                attribution_changed = True
                continue
            side = row.get("posSide")
            if side == "long":
                actual_by_side["long"] += abs(size)
            elif side == "short":
                actual_by_side["short"] += abs(size)
            elif side == "net":
                if size > 0:
                    actual_by_side["long"] += size
                elif size < 0:
                    actual_by_side["short"] += abs(size)
        if attribution_changed is not None and any(
            actual_by_side[side] != expected_by_side[side] for side in actual_by_side
        ):
            attribution_changed = True
        result = self._basic_result(strategy)
        result.update({
            "orders": strategy["results"],
            "positionStatus": position_status,
            "positions": position_rows,
            "unrealizedPnl": _text(pnl),
            "filledMargin": _text(filled_margin),
            "usedMargin": _text(filled_margin),
            "pnlPercent": _text(pnl_percent),
            "attributionChanged": attribution_changed,
            "observedAt": observed,
            "positionMode": account.get("posMode"),
        })
        return result

    def _recover_interrupted_apply(self, strategy: dict[str, Any]) -> dict[str, Any]:
        if strategy["executionLeaseUntil"] is not None and strategy["executionLeaseUntil"] > self.clock():
            return strategy
        if strategy["batchAttempted"]:
            return self._reconcile_orders(strategy, recovering=True)
        self._finish_recovery(
            strategy, "UNKNOWN",
            [{**row, "status": "not_submitted"} for row in strategy["orders"]],
            "interrupted_before_batch",
        )
        return self._load_row(strategy["id"])

    def _finish_recovery(
        self, strategy: dict[str, Any], status: str, results: list[dict[str, Any]], error: str | None
    ) -> None:
        now = self.clock()
        with self.store.transaction() as connection:
            changed = connection.execute(
                "UPDATE strategies SET status=?, results_json=?, failure_reason=?, execution_id=NULL, "
                "execution_lease_until=NULL, updated_at=? WHERE strategy_id=? AND status='APPLYING' "
                "AND execution_id IS ? AND (execution_lease_until IS NULL OR execution_lease_until<=?)",
                (status, encode_json(results), error, now, strategy["id"], strategy["executionId"], now),
            ).rowcount
            if changed == 1 and self._can_release_reservation(status, results, strategy["batchAttempted"]):
                connection.execute(
                    "DELETE FROM strategy_reservations WHERE strategy_id=?", (strategy["id"],)
                )

    def _reconcile_orders(self, strategy: dict[str, Any], *, recovering: bool = False) -> dict[str, Any]:
        if not strategy["batchAttempted"]:
            return strategy
        if strategy["status"] == "APPLYING" and not recovering:
            return strategy
        results = list(strategy["results"])
        changed = False
        for index, row in enumerate(results):
            if row.get("status") in ("rejected", "filled", "canceled", "mmp_canceled"):
                continue
            client_id = row.get("clientOrderId")
            if not isinstance(client_id, str) or not client_id:
                results[index] = {**row, "status": "unknown"}
                changed = True
                continue
            try:
                details = self.okx.order_details(strategy["contract"]["instrumentId"], client_id)
            except OKXError:
                if recovering:
                    results[index] = {**row, "status": "unknown"}
                    changed = True
                continue
            if details is None:
                if recovering:
                    results[index] = {**row, "status": "unknown"}
                    changed = True
                continue
            expected_size = _decimal(row.get("contracts"))
            size = _decimal(details.get("sz"))
            if (
                details.get("instId") != strategy["contract"]["instrumentId"]
                or details.get("clOrdId") != client_id
                or expected_size is None
                or size is None
                or size != expected_size
            ):
                results[index] = {**row, "status": "unknown"}
                changed = True
                continue
            filled = _decimal(details.get("accFillSz"))
            if size is None or filled is None or filled < 0 or filled > size:
                results[index] = {**row, "status": "unknown"}
                changed = True
                continue
            state = str(details.get("state", "")).lower()
            if state not in ("live", "partially_filled", "filled", "canceled", "mmp_canceled"):
                state = "unknown"
            results[index] = {
                **row,
                "status": state,
                "exchangeOrderId": details.get("ordId") or row.get("exchangeOrderId"),
                "filledContracts": _text(filled),
                "averageFillPrice": details.get("avgPx"),
            }
            changed = True
        states = {row.get("status") for row in results}
        new_status = strategy["status"]
        error: str | None = strategy["failureReason"]
        if recovering:
            if "unknown" in states or "not_submitted" in states:
                new_status = "UNKNOWN"
                error = "batch_reconciliation_incomplete"
            elif states.intersection({"rejected", "canceled", "mmp_canceled"}):
                new_status = "PARTIAL"
                error = "order_rejected_or_canceled"
            else:
                new_status = "APPLIED"
                error = None
        elif strategy["status"] == "UNKNOWN" and not (
            "unknown" in states or "not_submitted" in states or "accepted" in states
        ):
            new_status = "PARTIAL" if states.intersection({"rejected", "canceled", "mmp_canceled"}) else "APPLIED"
        elif strategy["status"] == "APPLIED" and "unknown" in states:
            new_status = "UNKNOWN"
        elif strategy["status"] == "APPLIED" and states.intersection({"rejected", "canceled", "mmp_canceled"}):
            new_status = "PARTIAL"
        elif strategy["status"] == "PARTIAL" and "unknown" in states:
            new_status = "UNKNOWN"
        if changed or new_status != strategy["status"]:
            with self.store.transaction() as connection:
                if recovering:
                    now = self.clock()
                    saved = connection.execute(
                        "UPDATE strategies SET status=?, results_json=?, failure_reason=?, execution_id=NULL, "
                        "execution_lease_until=NULL, updated_at=? WHERE strategy_id=? AND status='APPLYING' "
                        "AND execution_id IS ? AND (execution_lease_until IS NULL OR execution_lease_until<=?)",
                        (
                            new_status, encode_json(results), error, now, strategy["id"],
                            strategy["executionId"], now,
                        ),
                    ).rowcount
                else:
                    saved = connection.execute(
                        "UPDATE strategies SET status=?, results_json=?, failure_reason=?, updated_at=? "
                        "WHERE strategy_id=? AND status=? AND results_json=?",
                        (
                            new_status, encode_json(results), error, self.clock(),
                            strategy["id"], strategy["status"], encode_json(strategy["results"]),
                        ),
                    ).rowcount
                if saved == 1 and self._can_release_reservation(
                    new_status, results, strategy["batchAttempted"]
                ):
                    connection.execute(
                        "DELETE FROM strategy_reservations WHERE strategy_id=?", (strategy["id"],)
                    )
            strategy = self._load_row(strategy["id"])
        return strategy

    def _list(self) -> dict[str, Any]:
        _, fingerprint = self._account()
        with self.store.connection() as connection:
            rows = connection.execute(
                "SELECT * FROM strategies WHERE account_fingerprint=? ORDER BY created_at DESC, strategy_id DESC",
                (fingerprint,),
            ).fetchall()
        strategies: list[dict[str, Any]] = []
        for row in rows:
            strategy = self._decode_row(row)
            self._expire_prepare(strategy)
            strategies.append(self._result_for(strategy, fingerprint))
        return {"strategies": strategies}

    def _delete(self, strategy_id: str) -> dict[str, Any]:
        strategy, _, _ = self._current_strategy(strategy_id)
        if strategy["attemptStarted"] or strategy["status"] != "DRAFT":
            raise APIError(409, "strategy_immutable", "Only a never-attempted draft can be deleted.")
        with self.store.transaction() as connection:
            deleted = connection.execute(
                "DELETE FROM strategies WHERE strategy_id=? AND status='DRAFT' AND attempt_started=0",
                (strategy_id,),
            ).rowcount
        if deleted != 1:
            raise APIError(409, "strategy_state_changed", "The strategy changed; reload it before deleting.")
        return {"id": strategy_id, "status": "DELETED"}
