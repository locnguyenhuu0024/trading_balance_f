"""Bounded durable ledger helpers for sequential strategy order submission."""

from __future__ import annotations

import math
from decimal import Decimal, InvalidOperation
from typing import Any

from .okx import bounded_error_code
from .store import encode_json


QUEUE_DEADLINE_SECONDS = 120
MAX_PLACEMENTS_PER_PASS = 20
MIN_PLACEMENT_SPACING_SECONDS = 0.250

_PHASES = frozenset({"pending", "sending", "stopped", "submitted"})
_ATTEMPTED_PLACEMENT_STATES = frozenset({"sending", "accepted", "rejected", "unknown"})
_SAFE_STOP_REASONS = frozenset({
    "account_changed",
    "account_mode_unsupported",
    "balance_unavailable",
    "deadline_before_write",
    "insufficient_balance",
    "interrupted_leverage_attempt",
    "interrupted_order_attempt",
    "leverage_ack_malformed",
    "leverage_rejected",
    "leverage_unknown",
    "order_ack_malformed",
    "order_rejected",
    "order_unknown",
    "pending_order_exists",
    "position_mode_changed",
    "position_exists",
    "preflight_unavailable",
    "preview_changed",
    "queue_expired",
    "resume_validation_failed",
    "worker_fence_lost",
})


def new_queue(*, enqueued_at: float, total_count: int, preview_hash: str) -> dict[str, Any]:
    """Create the persisted state for a newly claimed sequential attempt."""
    return {
        "phase": "pending",
        "cursor": 0,
        "enqueuedAt": float(enqueued_at),
        "deadlineAt": float(enqueued_at) + QUEUE_DEADLINE_SECONDS,
        "inFlight": None,
        "stopReason": None,
        "totalCount": max(0, min(int(total_count), 20)),
        "previewHash": str(preview_hash),
        "submissionMode": "sequential",
    }


def initial_results(orders: list[dict[str, Any]]) -> list[dict[str, Any]]:
    return [{**row, "status": "queued", "placementState": "pending"} for row in orders]


def normalize_queue(value: Any) -> dict[str, Any] | None:
    if not isinstance(value, dict):
        return None
    phase = value.get("phase")
    cursor = value.get("cursor")
    total = value.get("totalCount")
    deadline = value.get("deadlineAt")
    enqueued = value.get("enqueuedAt")
    preview_hash = value.get("previewHash")
    if (
        phase not in _PHASES
        or isinstance(cursor, bool) or not isinstance(cursor, int)
        or isinstance(total, bool) or not isinstance(total, int) or not 0 <= total <= 20
        or not 0 <= cursor <= total
        or isinstance(deadline, bool) or not isinstance(deadline, (int, float))
        or isinstance(enqueued, bool) or not isinstance(enqueued, (int, float))
        or not math.isfinite(float(deadline)) or not math.isfinite(float(enqueued))
        or not isinstance(preview_hash, str) or not preview_hash
        or value.get("submissionMode") != "sequential"
    ):
        return None
    marker = value.get("inFlight")
    if marker is not None:
        if not isinstance(marker, dict) or marker.get("kind") not in ("leverage", "placement"):
            return None
        if marker.get("kind") == "placement":
            index = marker.get("index")
            if isinstance(index, bool) or not isinstance(index, int) or not 0 <= index < total:
                return None
        elif not isinstance(marker.get("side"), str) or marker.get("side") not in ("long", "short"):
            return None
    reason = value.get("stopReason")
    if reason is not None and not isinstance(reason, str):
        return None
    normalized_reason = reason if reason in _SAFE_STOP_REASONS else None
    return {
        **value,
        "phase": phase,
        "cursor": cursor,
        "totalCount": total,
        "enqueuedAt": float(enqueued),
        "deadlineAt": float(deadline),
        "inFlight": None if marker is None else dict(marker),
        "stopReason": normalized_reason,
        "previewHash": preview_hash,
        "submissionMode": value["submissionMode"],
    }


def safe_stop_reason(reason: Any, fallback: str = "preflight_unavailable") -> str:
    candidate = reason if isinstance(reason, str) else ""
    return candidate if candidate in _SAFE_STOP_REASONS else fallback


def stop_queue(
    queue: dict[str, Any],
    results: list[dict[str, Any]],
    reason: str,
    *,
    unknown_index: int | None = None,
) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    stopped = {**queue, "phase": "stopped", "stopReason": safe_stop_reason(reason)}
    updated = [dict(row) for row in results]
    for index, row in enumerate(updated):
        if index == unknown_index:
            updated[index] = {**row, "status": "unknown", "placementState": "unknown"}
        elif row.get("placementState", "pending") == "pending":
            updated[index] = {**row, "status": "not_submitted", "placementState": "not_submitted"}
    return stopped, updated


def progress(queue: Any, results: Any) -> dict[str, int] | None:
    normalized = normalize_queue(queue)
    if normalized is None or not isinstance(results, list):
        return None
    total = normalized["totalCount"]
    attempted = accepted = not_submitted = 0
    for row in results[:total]:
        if not isinstance(row, dict):
            continue
        state = row.get("placementState")
        if state in _ATTEMPTED_PLACEMENT_STATES:
            attempted += 1
            if state == "accepted":
                accepted += 1
        elif state == "not_submitted":
            not_submitted += 1
    attempted = min(total, attempted)
    accepted = min(attempted, accepted)
    not_submitted = min(max(0, total - attempted), not_submitted)
    pending = max(0, total - attempted - not_submitted)
    return {
        "totalCount": total,
        "attemptedCount": attempted,
        "acceptedCount": accepted,
        "pendingCount": pending,
        "notSubmittedCount": not_submitted,
    }


def parse_order_ack(response: Any, client_order_id: str) -> tuple[str, str | None, str | None, str]:
    """Return a validated accepted/rejected/unknown single-order outcome."""
    if not isinstance(response, dict):
        return "unknown", None, None, "order_ack_malformed"
    raw_top_code = response.get("code")
    top_code = bounded_error_code(raw_top_code)
    if top_code is None:
        return "unknown", None, None, "order_ack_malformed"
    if top_code != "0":
        return "rejected", None, top_code, "order_rejected"
    data = response.get("data")
    if not isinstance(data, list) or len(data) != 1 or not isinstance(data[0], dict):
        return "unknown", None, None, "order_ack_malformed"
    item = data[0]
    if item.get("clOrdId") != client_order_id:
        return "unknown", None, None, "order_ack_malformed"
    code = bounded_error_code(item.get("sCode"))
    if code is None:
        return "unknown", None, None, "order_ack_malformed"
    if code != "0":
        return "rejected", None, code, "order_rejected"
    exchange_order_id = item.get("ordId")
    if not isinstance(exchange_order_id, str) or not exchange_order_id.strip():
        return "unknown", None, None, "order_ack_malformed"
    return "accepted", exchange_order_id, None, ""


def parse_leverage_ack(
    response: Any,
    *,
    expected_pos_side: str,
    expected_instrument_id: str,
    expected_leverage: Any,
) -> tuple[str, str | None]:
    """Validate a set-leverage acknowledgement, including the echoed request fields."""
    if not isinstance(response, dict):
        return "unknown", None
    top_code = bounded_error_code(response.get("code"))
    if top_code is None:
        return "unknown", None
    if top_code != "0":
        return "rejected", top_code
    data = response.get("data")
    if not isinstance(data, list) or len(data) != 1 or not isinstance(data[0], dict):
        return "unknown", None
    item = data[0]
    if "sCode" in item:
        sub_code = bounded_error_code(item.get("sCode"))
        if sub_code is None:
            return "unknown", None
        if sub_code != "0":
            return "rejected", sub_code
    actual = _ack_decimal(item.get("lever"))
    expected = _ack_decimal(expected_leverage)
    if (
        item.get("instId") == expected_instrument_id
        and item.get("mgnMode") == "isolated"
        and item.get("posSide") == expected_pos_side
        and actual is not None
        and expected is not None
        and actual == expected
    ):
        return "applied", None
    return "unknown", None


def _ack_decimal(value: Any) -> Decimal | None:
    if value is None or isinstance(value, (bool, float)):
        return None
    try:
        result = Decimal(str(value))
        return result if result.is_finite() else None
    except (InvalidOperation, ValueError, TypeError):
        return None


class StrategyQueueLedger:
    """Persist one queue transition under the current monitor lease fence."""

    def __init__(
        self,
        store: Any,
        *,
        owner_id: str,
        fence: int,
        lease_seconds: float,
        clock: Any,
    ):
        self.store = store
        self.owner_id = owner_id
        self.fence = fence
        self.lease_seconds = lease_seconds
        self.clock = clock

    def persist_transition(
        self,
        strategy: dict[str, Any],
        *,
        queue: dict[str, Any],
        results: list[dict[str, Any]],
        status: str,
        failure_reason: str | None,
        leverage_results: list[dict[str, Any]],
        mark_placement_attempted: bool = False,
    ) -> bool:
        """Commit ledger, outcome, and cursor together, refusing a stale fence or row."""
        strategy_id = strategy["id"]
        expected_queue = strategy.get("queueJsonRaw")
        if not isinstance(expected_queue, str):
            return False
        attempted = bool(strategy["orderPlacementAttempted"]) or mark_placement_attempted
        with self.store.transaction() as connection:
            # Transaction entry can wait for SQLite's write lock. Sample the lease
            # clock after that wait so an expired fence cannot commit stale state.
            now = self.clock()
            lease = connection.execute(
                "SELECT lease_until FROM strategy_monitor_lease WHERE singleton=1 "
                "AND owner_id=? AND fence=?",
                (self.owner_id, self.fence),
            ).fetchone()
            if lease is None or lease["lease_until"] <= now:
                return False
            renewed = connection.execute(
                "UPDATE strategy_monitor_lease SET lease_until=? WHERE singleton=1 "
                "AND owner_id=? AND fence=? AND lease_until>?",
                (now + self.lease_seconds, self.owner_id, self.fence, now),
            ).rowcount
            if renewed != 1:
                return False
            current = connection.execute(
                "SELECT account_fingerprint, status, queue_json, results_json, updated_at "
                "FROM strategies WHERE strategy_id=?",
                (strategy_id,),
            ).fetchone()
            if (
                current is None
                or current["status"] != "APPLYING"
                or current["account_fingerprint"] != strategy["accountFingerprint"]
                or current["queue_json"] != expected_queue
                or current["results_json"] != encode_json(strategy["results"])
                or current["updated_at"] != strategy["updatedAt"]
            ):
                return False
            updated = connection.execute(
                "UPDATE strategies SET status=?, queue_json=?, results_json=?, leverage_results_json=?, "
                "order_placement_attempted=?, failure_reason=?, updated_at=?, execution_id=NULL, "
                "execution_lease_until=NULL WHERE strategy_id=? AND status='APPLYING' "
                "AND account_fingerprint=? AND queue_json=? AND results_json=? AND updated_at=?",
                (
                    status, encode_json(queue), encode_json(results), encode_json(leverage_results),
                    1 if attempted else 0, failure_reason, now, strategy_id,
                    strategy["accountFingerprint"], expected_queue, encode_json(strategy["results"]),
                    strategy["updatedAt"],
                ),
            ).rowcount
            if updated != 1:
                return False
            if self._can_release_reservation(status, results, attempted):
                connection.execute(
                    "DELETE FROM strategy_reservations WHERE strategy_id=?",
                    (strategy_id,),
                )
        return True

    @staticmethod
    def _can_release_reservation(
        status: str, results: list[dict[str, Any]], placement_attempted: bool
    ) -> bool:
        if status == "UNKNOWN":
            return not placement_attempted
        terminal = {"rejected", "filled", "canceled", "mmp_canceled", "not_submitted"}
        return status in ("APPLIED", "PARTIAL", "UNKNOWN", "COMPLETED") and all(
            row.get("status") in terminal for row in results
        )
