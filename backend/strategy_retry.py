"""Pure validation and fixed-order preview helpers for strategy resubmission."""

from __future__ import annotations

import re
import time
from decimal import Decimal, ROUND_CEILING, ROUND_DOWN, ROUND_FLOOR, InvalidOperation
from typing import Any

from .okx import bounded_error_code
from .security import token_digest
from .store import encode_json
from .strategy_queue import normalize_queue


_DIGEST = re.compile(r"[0-9a-f]{64}\Z")
_CLIENT_ID = re.compile(r"[A-Za-z0-9_-]{8,64}\Z")
_LEVEL_ID = re.compile(r"[A-Za-z0-9_-]{1,128}\Z")
_ACCEPTED = frozenset({"accepted", "live", "partially_filled", "filled", "canceled", "mmp_canceled"})


class RetryDataError(ValueError):
    """A stored retry source is malformed or contradictory."""

    def __init__(self, reason: str = "evidence_malformed"):
        super().__init__(reason)
        self.reason = reason


def _decimal(value: Any) -> Decimal | None:
    if value is None or isinstance(value, (bool, float)):
        return None
    try:
        parsed = Decimal(str(value))
        return parsed if parsed.is_finite() else None
    except (InvalidOperation, ValueError, TypeError):
        return None


def _text(value: Decimal | None) -> str | None:
    if value is None:
        return None
    if value == 0:
        return "0"
    return format(value.normalize(), "f")


def _safe_scalar(value: Any) -> Any:
    if value is None or isinstance(value, (str, int, bool)):
        return value
    if isinstance(value, float):
        return "invalid_float"
    return f"invalid_{type(value).__name__}"


def is_resubmission_contract(contract: Any) -> bool:
    return isinstance(contract, dict) and contract.get("kind") == "resubmission"


def retry_metadata(contract: Any) -> dict[str, Any] | None:
    if not isinstance(contract, dict) or "kind" not in contract and "resubmission" not in contract:
        return None
    if contract.get("kind") != "resubmission":
        raise RetryDataError()
    metadata = contract.get("resubmission")
    if not isinstance(metadata, dict):
        raise RetryDataError()
    if set(metadata) != {
        "sourceStrategyId", "sourceClientOrderIds", "sourceRevision",
        "sourceSelectionHash", "retryRequestId",
    }:
        raise RetryDataError()
    source_id = metadata.get("sourceStrategyId")
    selection = metadata.get("sourceClientOrderIds")
    if (
        not isinstance(source_id, str) or not _CLIENT_ID.fullmatch(source_id)
        or not isinstance(selection, list) or not 1 <= len(selection) <= 10
        or any(not isinstance(value, str) or not _CLIENT_ID.fullmatch(value) for value in selection)
        or len(set(selection)) != len(selection)
        or not isinstance(metadata.get("sourceRevision"), str)
        or not _DIGEST.fullmatch(metadata["sourceRevision"])
        or not isinstance(metadata.get("sourceSelectionHash"), str)
        or not _DIGEST.fullmatch(metadata["sourceSelectionHash"])
        or not isinstance(metadata.get("retryRequestId"), str)
        or not re.fullmatch(r"[A-Za-z0-9_-]{16,64}\Z", metadata["retryRequestId"])
    ):
        raise RetryDataError()
    if contract.get("instrumentId") is None or not isinstance(contract.get("instrumentId"), str):
        raise RetryDataError()
    return metadata


def _financial_tuple(row: dict[str, Any]) -> dict[str, Any]:
    return {
        key: _safe_scalar(row.get(key))
        for key in ("clientOrderId", "side", "role", "limitPrice", "contracts", "leverage", "levelId")
        if key in row
    }


def _status_class(value: Any) -> str:
    if not isinstance(value, str):
        return "unknown"
    if value in _ACCEPTED:
        return "accepted"
    if value == "rejected":
        return "rejected"
    if value == "not_submitted":
        return "not_submitted"
    return "unknown"


def _queue_projection(source: dict[str, Any]) -> dict[str, Any] | None:
    if source.get("submissionMode") != "sequential":
        return None
    queue = normalize_queue(source.get("queue"))
    if queue is None:
        return {"invalid": True}
    marker = queue.get("inFlight")
    marker_projection = None
    if isinstance(marker, dict):
        marker_projection = {
            "kind": _safe_scalar(marker.get("kind")),
            "index": _safe_scalar(marker.get("index")),
            "side": _safe_scalar(marker.get("side")),
        }
    return {
        "phase": queue["phase"],
        "cursor": queue["cursor"],
        "totalCount": queue["totalCount"],
        "previewHash": queue["previewHash"],
        "inFlight": marker_projection,
        "stopReason": queue.get("stopReason"),
    }


def _leverage_projection(source: dict[str, Any]) -> list[dict[str, Any]]:
    raw = source.get("leverageResults")
    if not isinstance(raw, list):
        return [{"malformed": True}] if raw is not None else []
    return [
        {
            "side": _safe_scalar(row.get("side")),
            "status": _safe_scalar(row.get("status")),
            "errorCode": bounded_error_code(row.get("errorCode")),
        }
        if isinstance(row, dict) else {"malformed": True}
        for row in raw
    ]


def _outcome_evidence(result: Any) -> dict[str, Any]:
    if not isinstance(result, dict):
        return {"status": "malformed"}
    error = bounded_error_code(result.get("errorCode"))
    exchange_id = result.get("exchangeOrderId")
    return {
        "status": _status_class(result.get("status")),
        "placementState": _safe_scalar(result.get("placementState")),
        "errorCode": error,
        "hasExchangeOrderId": isinstance(exchange_id, str) and bool(exchange_id.strip()),
    }


def source_revision(source: dict[str, Any], signing_key: bytes) -> str:
    """Hash stable source evidence while excluding polling timestamps and fills."""
    contract = source.get("contract")
    orders = source.get("orders")
    results = source.get("results")
    if not isinstance(contract, dict):
        contract = {}
    if not isinstance(orders, list):
        orders = []
    if not isinstance(results, list):
        results = []
    status = source.get("status")
    lifecycle = "applying" if status == "APPLYING" else (
        "settled" if isinstance(status, str) and status in {"APPLIED", "PARTIAL", "UNKNOWN", "COMPLETED"} else "invalid"
    )
    payload = {
        "sourceStrategyId": _safe_scalar(source.get("id")),
        "accountFingerprint": _safe_scalar(source.get("accountFingerprint")),
        "instrumentId": _safe_scalar(contract.get("instrumentId")),
        "lifecycle": lifecycle,
        "attemptStarted": _safe_scalar(source.get("attemptStarted")),
        "batchAttempted": _safe_scalar(source.get("batchAttempted")),
        "orderPlacementAttempted": _safe_scalar(source.get("orderPlacementAttempted")),
        "submissionMode": _safe_scalar(source.get("submissionMode")),
        "queue": _queue_projection(source),
        "leverageResults": _leverage_projection(source),
        "rows": [
            {
                "financial": _financial_tuple(order) if isinstance(order, dict) else {"malformed": True},
                "outcome": _outcome_evidence(results[index]) if index < len(results) else {"missing": True},
            }
            for index, order in enumerate(orders)
        ],
        "resultCount": len(results),
    }
    return token_digest(encode_json(payload), signing_key)


def source_rows(source: dict[str, Any]) -> list[tuple[int, dict[str, Any], dict[str, Any]]]:
    orders = source.get("orders")
    results = source.get("results")
    if (
        not isinstance(orders, list) or not orders or len(orders) > 20
        or not isinstance(results, list) or len(results) != len(orders)
    ):
        raise RetryDataError()
    seen: set[str] = set()
    pairs: list[tuple[int, dict[str, Any], dict[str, Any]]] = []
    for index, (order, result) in enumerate(zip(orders, results)):
        if not isinstance(order, dict) or not isinstance(result, dict):
            raise RetryDataError()
        client_id = order.get("clientOrderId")
        price = _decimal(order.get("limitPrice"))
        contracts = _decimal(order.get("contracts"))
        leverage = order.get("leverage")
        if (
            not isinstance(client_id, str) or not _CLIENT_ID.fullmatch(client_id) or client_id in seen
            or order.get("side") not in ("long", "short")
            or order.get("role") not in ("entry", "dca")
            or price is None or price <= 0 or contracts is None or contracts <= 0
            or isinstance(leverage, bool) or not isinstance(leverage, int) or not 1 <= leverage <= 10
            or ("levelId" in order and (not isinstance(order.get("levelId"), str) or not _LEVEL_ID.fullmatch(order["levelId"])))
        ):
            raise RetryDataError()
        seen.add(client_id)
        for key in ("clientOrderId", "side", "role", "limitPrice", "contracts", "leverage", "levelId"):
            if order.get(key) != result.get(key):
                raise RetryDataError()
        if "sourceClientOrderId" in order and order.get("sourceClientOrderId") != result.get("sourceClientOrderId"):
            raise RetryDataError()
        pairs.append((index, order, result))
    return pairs


def _valid_fill_evidence(result: dict[str, Any]) -> bool:
    if "filledContracts" in result:
        filled = _decimal(result.get("filledContracts"))
        if filled is None or filled != 0:
            return False
    if "averageFillPrice" in result:
        average = result.get("averageFillPrice")
        if average not in (None, ""):
            parsed_average = _decimal(average)
            if parsed_average is None or parsed_average != 0:
                return False
    return True


def classify_row(
    source: dict[str, Any], index: int, order: dict[str, Any], result: dict[str, Any]
) -> tuple[str, str | None]:
    """Return priorOutcome and a fixed ineligibility code, if any."""
    state = result.get("status")
    exchange_id = result.get("exchangeOrderId")
    if exchange_id is not None and not isinstance(exchange_id, str):
        return "other", "evidence_malformed"
    if isinstance(exchange_id, str):
        if exchange_id.strip():
            return "other", "exchange_order_exists"
        if exchange_id != "":
            return "other", "evidence_malformed"
    if not _valid_fill_evidence(result):
        return "other", "fill_evidence_invalid"
    source_status = source.get("status")
    if not isinstance(source_status, str) or source_status not in {"APPLIED", "PARTIAL", "UNKNOWN", "COMPLETED"}:
        return "other", "source_not_attempted"
    if source.get("attemptStarted") is not True:
        return "other", "source_not_attempted"

    mode = source.get("submissionMode")
    placement = result.get("placementState")
    if mode == "sequential":
        queue = normalize_queue(source.get("queue"))
        if (
            queue is None or queue["phase"] != "stopped"
            or queue["totalCount"] != len(source.get("orders", []))
        ):
            return "other", "queue_evidence_invalid"
        cursor = queue["cursor"]
        rows = source.get("results")
        if not isinstance(rows, list) or len(rows) != queue["totalCount"]:
            return "other", "queue_evidence_invalid"
        if any(not isinstance(item, dict) or item.get("placementState") != "accepted" for item in rows[:cursor]):
            return "other", "queue_evidence_invalid"
        marker = queue.get("inFlight")
        if isinstance(marker, dict) and marker.get("kind") == "placement" and marker.get("index") == index:
            return "other", "placement_in_flight"
        if state == "not_submitted":
            if placement != "not_submitted" or index < cursor:
                return "other", "placement_evidence_invalid"
            return "not_submitted", None
        if state == "rejected":
            code = bounded_error_code(result.get("errorCode"))
            if placement != "rejected" or code is None or int(code) == 0 or index != cursor:
                return "other", "rejection_evidence_invalid"
            return "rejected", None
        if isinstance(state, str) and state in _ACCEPTED:
            return "other", "accepted_or_canceled"
        return "other", "outcome_unknown"

    batch_attempted = source.get("batchAttempted")
    placement_attempted = source.get("orderPlacementAttempted")
    if (
        mode not in ("batch", None)
        or not isinstance(batch_attempted, bool)
        or not isinstance(placement_attempted, bool)
        or batch_attempted != placement_attempted
    ):
        return "other", "placement_evidence_invalid"
    if state == "not_submitted":
        if batch_attempted or placement not in (None, "not_submitted"):
            return "other", "placement_evidence_invalid"
        return "not_submitted", None
    if state == "rejected":
        code = bounded_error_code(result.get("errorCode"))
        if not batch_attempted or code is None or int(code) == 0 or placement is not None:
            return "other", "rejection_evidence_invalid"
        return "rejected", None
    if isinstance(state, str) and state in _ACCEPTED:
        return "other", "accepted_or_canceled"
    return "other", "outcome_unknown"


def ordered_selection(
    source: dict[str, Any], selected_ids: Any
) -> list[tuple[int, dict[str, Any], dict[str, Any]]]:
    if (
        not isinstance(selected_ids, list) or not 1 <= len(selected_ids) <= 10
        or any(not isinstance(value, str) or not _CLIENT_ID.fullmatch(value) for value in selected_ids)
        or len(set(selected_ids)) != len(selected_ids)
    ):
        raise RetryDataError("selection_invalid")
    pairs = source_rows(source)
    wanted = set(selected_ids)
    selected = [pair for pair in pairs if pair[1]["clientOrderId"] in wanted]
    if len(selected) != len(wanted):
        raise RetryDataError("selection_invalid")
    return selected


def ordered_ids(selected: list[tuple[int, dict[str, Any], dict[str, Any]]]) -> list[str]:
    return [row[1]["clientOrderId"] for row in selected]


def selection_hash(
    source: dict[str, Any],
    selected: list[tuple[int, dict[str, Any], dict[str, Any]]],
    revision: str,
    signing_key: bytes,
) -> str:
    evidence = []
    for index, order, result in selected:
        prior, reason = classify_row(source, index, order, result)
        evidence.append({
            "sourceClientOrderId": order.get("clientOrderId"),
            "financial": _financial_tuple(order),
            "priorOutcome": prior,
            "reason": reason,
            "placementState": _safe_scalar(result.get("placementState")),
            "errorCode": bounded_error_code(result.get("errorCode")),
            "hasExchangeOrderId": bool(isinstance(result.get("exchangeOrderId"), str) and result["exchangeOrderId"].strip()),
        })
    return token_digest(encode_json({
        "sourceStrategyId": source.get("id"),
        "sourceRevision": revision,
        "rows": evidence,
    }), signing_key)


def fixed_preview(
    *,
    source_id: str,
    source_revision_value: str,
    selection_hash_value: str,
    selected: list[tuple[int, dict[str, Any], dict[str, Any]]],
    instrument_id: str,
    interval: str,
    current_price: Decimal,
    quote_timestamp_ms: Decimal,
    contract_value: Decimal,
    contract_multiplier: Decimal,
    tick_size: Decimal,
    lot_size: Decimal,
    minimum_size: Decimal,
    maker_fee: Decimal,
    taker_fee: Decimal,
    tiers: list[dict[str, Decimal]],
    account_fingerprint: str,
    position_mode: str,
    signing_key: bytes,
) -> dict[str, Any]:
    unit = contract_value * contract_multiplier
    per_side: dict[str, dict[str, Decimal]] = {
        "long": {"contracts": Decimal(0), "notional": Decimal(0), "margin": Decimal(0)},
        "short": {"contracts": Decimal(0), "notional": Decimal(0), "margin": Decimal(0)},
    }
    totals_margin = Decimal(0)
    totals_fees = Decimal(0)
    orders: list[dict[str, Any]] = []
    for _, source_order, _ in selected:
        side = source_order["side"]
        price = _decimal(source_order.get("limitPrice"))
        contracts = _decimal(source_order.get("contracts"))
        leverage = source_order.get("leverage")
        if (
            price is None or contracts is None or price <= 0 or contracts <= 0
            or isinstance(leverage, bool) or not isinstance(leverage, int) or leverage <= 0
        ):
            raise RetryDataError("selection_invalid")
        if price % tick_size != 0 or contracts % lot_size != 0 or contracts < minimum_size:
            raise RetryDataError("exact_order_incompatible")
        if (side == "long" and price >= current_price) or (side == "short" and price <= current_price):
            raise RetryDataError("passive_price_invalid")
        notional = contracts * price * unit
        margin = notional / Decimal(leverage)
        fee = notional * taker_fee
        bucket = per_side[side]
        bucket["contracts"] += contracts
        bucket["notional"] += contracts * price
        bucket["margin"] += margin
        cumulative_contracts = bucket["contracts"]
        cumulative_average = bucket["notional"] / cumulative_contracts
        matching = [tier for tier in tiers if tier["min"] <= cumulative_contracts <= tier["max"]]
        if len(matching) != 1:
            raise RetryDataError("tier_unavailable")
        tier = matching[0]
        if Decimal(leverage) > tier["maxLeverage"]:
            raise RetryDataError("leverage_exceeds_tier")
        rate = tier["mmr"]
        long_denominator = unit * cumulative_contracts * (Decimal(1) - rate - taker_fee)
        short_denominator = unit * cumulative_contracts * (Decimal(1) + rate + taker_fee)
        if long_denominator <= 0 or short_denominator <= 0:
            raise RetryDataError("tier_unavailable")
        if side == "long":
            numerator = unit * cumulative_contracts * cumulative_average - bucket["margin"]
            liquidation = (
                {"status": "no_positive_threshold", "price": None}
                if numerator <= 0
                else {"status": "estimated", "price": _text((numerator / long_denominator / tick_size).to_integral_value(rounding=ROUND_CEILING) * tick_size)}
            )
        else:
            numerator = unit * cumulative_contracts * cumulative_average + bucket["margin"]
            liquidation = {
                "status": "estimated",
                "price": _text((numerator / short_denominator / tick_size).to_integral_value(rounding=ROUND_FLOOR) * tick_size),
            }
        row = {
            "sourceClientOrderId": source_order["clientOrderId"],
            "side": side,
            "role": source_order["role"],
            "limitPrice": _text(price),
            "contracts": _text(contracts),
            "leverage": leverage,
            "allocatedMargin": _text(margin),
            "margin": _text(margin),
            "notional": _text(notional),
            "openingFeeEstimate": _text(fee),
            "allocationWeight": 1,
            "cumulativeContracts": _text(cumulative_contracts),
            "cumulativeAverageEntry": _text(cumulative_average),
            "liquidationEstimate": liquidation,
        }
        if "levelId" in source_order:
            row["levelId"] = source_order["levelId"]
        orders.append(row)
        totals_margin += margin
        totals_fees += fee

    if totals_margin <= 0:
        raise RetryDataError("selection_invalid")
    for side in ("long", "short"):
        by_price: dict[Decimal, list[int]] = {}
        for index, order in enumerate(orders):
            if order["side"] == side and "levelId" in order:
                by_price.setdefault(Decimal(order["limitPrice"]), []).append(index)
        for indices in by_price.values():
            if len(indices) > 1:
                estimate = orders[indices[-1]]["liquidationEstimate"]
                for index in indices:
                    orders[index]["liquidationEstimate"] = dict(estimate)
                    orders[index]["liquidationEstimateNote"] = (
                        "Estimated after all same-price orders fill; OKX fill order is not guaranteed."
                    )

    sides = [side for side in ("long", "short") if per_side[side]["contracts"] > 0]
    side_percent: dict[str, str] = {}
    allocated_percent = Decimal(0)
    for side in sides[:-1]:
        value = per_side[side]["margin"] / totals_margin * Decimal(100)
        side_percent[side] = _text(value) or "0"
        allocated_percent += value
    side_percent[sides[-1]] = _text(Decimal(100) - allocated_percent) or "0"

    metadata = {
        "contractValue": _text(contract_value),
        "contractMultiplier": _text(contract_multiplier),
        "contractValueCurrency": "base",
        "tickSize": _text(tick_size),
        "lotSize": _text(lot_size),
        "minimumSize": _text(minimum_size),
        "makerFeeRate": _text(maker_fee),
        "takerFeeRate": _text(taker_fee),
        "tiers": [
            {"min": _text(row["min"]), "max": _text(row["max"]), "mmr": _text(row["mmr"]),
             "maxLeverage": _text(row["maxLeverage"])}
            for row in tiers
        ],
    }
    required_balance = totals_margin + totals_fees
    semantic = {
        "accountFingerprint": account_fingerprint,
        "positionMode": position_mode,
        "instrumentId": instrument_id,
        "sourceStrategyId": source_id,
        "sourceRevision": source_revision_value,
        "sourceSelectionHash": selection_hash_value,
        "selectedSourceClientOrderIds": [row["sourceClientOrderId"] for row in orders],
        "orders": orders,
        "metadata": metadata,
        "totalMargin": _text(totals_margin),
        "estimatedOpeningFees": _text(totals_fees),
        "requiredBalance": _text(required_balance),
        "sidePercent": side_percent,
    }
    preview_hash = token_digest(encode_json(semantic), signing_key)
    quote_ms = int(quote_timestamp_ms)
    observed = (
        time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(quote_ms // 1000))
        + f".{quote_ms % 1000:03d}Z"
    )
    return {
        "id": None,
        "status": "PREVIEW",
        "instrumentId": instrument_id,
        "interval": interval,
        "sides": sides,
        "currentPrice": _text(current_price),
        "quoteTimestamp": observed,
        "totalMargin": _text(totals_margin),
        "plannedMargin": _text(totals_margin),
        "unallocatedMargin": "0",
        "estimatedOpeningFees": _text(totals_fees),
        "requiredBalance": _text(required_balance),
        "feesOutsideMargin": True,
        "allocation": "fixed",
        "sidePercent": side_percent,
        "orders": orders,
        "previewHash": preview_hash,
        "sourceStrategyId": source_id,
        "sourceRevision": source_revision_value,
        "selectedSourceClientOrderIds": [row["sourceClientOrderId"] for row in orders],
        "_internal": {
            "metadata": metadata,
            "accountFingerprint": account_fingerprint,
            "positionMode": position_mode,
        },
    }


def fixed_order_compatible(value: Any, increment: Decimal, minimum: Decimal) -> bool:
    parsed = _decimal(value)
    return parsed is not None and parsed >= minimum and parsed % increment == 0
