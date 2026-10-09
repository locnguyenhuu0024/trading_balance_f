"""Automatic candidate generation, Jev enrichment, and candidate-stage persistence."""

from __future__ import annotations

import hashlib
import hmac
import json
import logging
import math
import re
import time
from datetime import datetime, timezone
from decimal import Decimal, localcontext
from typing import Any, Callable

from .okx import OKXError
from .security import new_operation_id, token_digest
from .service import APIError
from .store import decode_json, encode_json
from .strategy_jev import (
    STRUCTURAL_QUALITY_RUBRIC,
    ProviderOutcome,
    TypesafeJevProvider,
)
from .strategy_levels import (
    CandleDataError,
    calculate_levels,
    decimal_text,
    normalize_candles,
    parse_decimal,
    timestamp_milliseconds,
)


_AUTOMATIC_PATH = "/v1/strategies/automatic-drafts"
_REQUEST_ID = re.compile(r"[A-Za-z0-9_-]{8,64}\Z")
_INSTRUMENT_ID = re.compile(r"[A-Z0-9]+-USDT-SWAP\Z")
_INTERVALS = ("6Hutc", "1Dutc", "1Wutc")
_DIRECTIONS = frozenset({"long", "short", "both"})
_BARS = {"6Hutc": "6Hutc", "1Dutc": "1Dutc", "1Wutc": "1Wutc"}
_CONTEXT_CANDLE_COUNT = 20
_MAX_AGE_MS = 15_000
_RECOMMENDATION_VERSION = "ai-jev-selection-v1"
_RECOMMENDATION_MAX_PER_SIDE = 5
_RECOMMENDATION_MIN_QUALITY = 4
_RECOMMENDATION_MIN_SUITABILITY = 0.6
_RECOMMENDATION_MAX_FAILURE_RISK = 0.4
_ERROR_CODES = frozenset({
    "disabled", "key_missing", "sdk_unavailable", "settings_invalid",
    "deadline_exceeded", "timeout", "provider_error", "provider_unavailable",
    "invalid_response", "invalid_model",
})
_LOGGER = logging.getLogger("backend.strategy.jev")


def _json_hash(value: Any) -> str:
    encoded = json.dumps(value, ensure_ascii=False, separators=(",", ":"), sort_keys=True).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def _iso_from_epoch_ms(value: int) -> str:
    seconds, milliseconds = divmod(value, 1000)
    instant = datetime.fromtimestamp(seconds, timezone.utc).replace(microsecond=milliseconds * 1000)
    return instant.isoformat(timespec="milliseconds").replace("+00:00", "Z")


def _utc_now(epoch_seconds: float) -> str:
    return datetime.fromtimestamp(epoch_seconds, timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def _numeric(value: Any, minimum: float, maximum: float) -> float | None:
    if isinstance(value, bool) or not isinstance(value, (int, float, Decimal)):
        return None
    try:
        numeric = float(value)
    except (TypeError, ValueError, OverflowError):
        return None
    if not math.isfinite(numeric) or numeric < minimum or numeric > maximum:
        return None
    return numeric


def _outcome_value(outcome: Any, snake: str, camel: str | None = None, default: Any = None) -> Any:
    if isinstance(outcome, dict):
        if snake in outcome:
            return outcome[snake]
        return outcome.get(camel, default) if camel else default
    if hasattr(outcome, snake):
        return getattr(outcome, snake)
    return getattr(outcome, camel, default) if camel else default


class AutomaticStrategyService:
    """Backend-only candidate API manager attached to the existing strategy service."""

    def __init__(self, strategy_service: Any):
        self.strategy = strategy_service
        self.provider_factory: Callable[[], Any] = TypesafeJevProvider

    @staticmethod
    def _generation_direction(generation: Any) -> str | None:
        if not isinstance(generation, dict):
            return None
        direction = generation.get("direction", "both")
        return direction if isinstance(direction, str) and direction in _DIRECTIONS else None

    def dispatch(
        self,
        method: str,
        path: str,
        body: dict[str, Any],
        *,
        request_guard: Callable[[], Any] | None = None,
    ) -> dict[str, Any] | None:
        if path != _AUTOMATIC_PATH:
            return None
        if method != "POST":
            raise APIError(405, "method_not_allowed", "The requested method is not allowed.")
        return self._create(body, request_guard=request_guard)

    def public_candidate_result(self, strategy: dict[str, Any]) -> dict[str, Any]:
        generation = strategy["snapshot"].get("aiGeneration")
        if not isinstance(generation, dict):
            raise APIError(500, "strategy_data_unavailable", "The saved automatic draft is unavailable.")
        created_at = _utc_now(strategy["createdAt"])
        updated_at = _utc_now(strategy["updatedAt"])
        return {
            "id": strategy["id"],
            "status": "DRAFT",
            "draftStage": "candidates",
            "canApply": False,
            "canReview": True,
            "canDelete": True,
            "canReplace": False,
            "instrumentId": strategy["contract"]["instrumentId"],
            "interval": strategy["contract"]["interval"],
            "orders": [],
            "results": [],
            "aiGeneration": generation,
            "createdAt": created_at,
            "updatedAt": updated_at,
        }

    @staticmethod
    def is_candidate_stage(strategy: dict[str, Any]) -> bool:
        return strategy.get("snapshot", {}).get("draftStage") == "candidates"

    @staticmethod
    def assert_not_candidate(strategy: dict[str, Any]) -> None:
        if AutomaticStrategyService.is_candidate_stage(strategy):
            raise APIError(
                409,
                "candidate_not_materialized",
                "Select and size saved candidates before applying or retrying this strategy.",
            )

    def load_candidate_for_materialization(
        self, candidate_id: str, contract: dict[str, Any], account_fingerprint: str
    ) -> dict[str, Any]:
        if not isinstance(candidate_id, str) or re.fullmatch(r"[A-Za-z0-9_-]{8,64}", candidate_id) is None:
            raise APIError(422, "candidate_selection_invalid", "The saved candidate selection is invalid.")
        with self.strategy.store.connection() as connection:
            row = connection.execute(
                "SELECT * FROM strategies WHERE strategy_id=? AND account_fingerprint=?",
                (candidate_id, account_fingerprint),
            ).fetchone()
        if row is None:
            raise APIError(404, "strategy_not_found", "The saved automatic draft was not found.")
        saved = self.strategy._decode_row(row)
        self._verify_candidate_selection(saved, contract)
        return saved

    def verify_candidate_materialization(
        self, saved: dict[str, Any], contract: dict[str, Any]
    ) -> None:
        self._verify_candidate_selection(saved, contract)

    def _verify_candidate_selection(
        self, saved: dict[str, Any], contract: dict[str, Any]
    ) -> None:
        snapshot = saved.get("snapshot")
        generation = snapshot.get("aiGeneration") if isinstance(snapshot, dict) else None
        saved_contract = saved.get("contract")
        if (
            not self.is_candidate_stage(saved)
            or saved.get("status") != "DRAFT"
            or saved.get("attemptStarted")
            or saved.get("orderPlacementAttempted")
            or saved.get("replacementSourceId") is not None
            or saved.get("prepared") is not None
            or saved.get("orders") != []
            or saved.get("results") != []
            or not isinstance(generation, dict)
            or not isinstance(saved_contract, dict)
        ):
            raise APIError(409, "candidate_not_materializable", "This saved candidate draft cannot be materialized.")
        direction = self._generation_direction(generation)
        if direction is None:
            raise APIError(409, "candidate_not_materializable", "The saved candidate direction is invalid.")
        saved_direction = saved_contract.get("direction")
        if "direction" in generation:
            if saved_direction != direction:
                raise APIError(409, "candidate_not_materializable", "The saved candidate direction is invalid.")
        elif saved_direction not in (None, "both"):
            raise APIError(409, "candidate_not_materializable", "The saved candidate direction is invalid.")
        if (
            contract.get("instrumentId") != saved_contract.get("instrumentId")
            or contract.get("interval") != saved_contract.get("interval")
            or generation.get("instrumentId") != contract.get("instrumentId")
            or generation.get("interval") != contract.get("interval")
        ):
            raise APIError(409, "candidate_selection_mismatch", "The selection does not match the saved candidate draft.")
        selected = contract.get("selectedLevels")
        if not isinstance(selected, list) or not selected:
            raise APIError(422, "candidate_selection_invalid", "Select at least one saved candidate level.")
        allowed_sides = {"long", "short"} if direction == "both" else {direction}
        saved_levels: dict[str, tuple[str, str]] = {}
        for group in (generation.get("supports"), generation.get("resistances")):
            if not isinstance(group, list):
                raise APIError(409, "candidate_not_materializable", "The saved candidate data is invalid.")
            for candidate in group:
                if not isinstance(candidate, dict):
                    raise APIError(409, "candidate_not_materializable", "The saved candidate data is invalid.")
                level_id = candidate.get("levelId")
                side = candidate.get("side")
                price = candidate.get("price")
                if (
                    not isinstance(level_id, str) or not isinstance(side, str)
                    or not isinstance(price, str) or level_id in saved_levels
                ):
                    raise APIError(409, "candidate_not_materializable", "The saved candidate data is invalid.")
                if side not in allowed_sides:
                    raise APIError(409, "candidate_selection_mismatch", "A candidate is outside the saved direction.")
                saved_levels[level_id] = (side, price)
        seen: set[str] = set()
        for level in selected:
            if not isinstance(level, dict):
                raise APIError(422, "candidate_selection_invalid", "The selected candidate data is invalid.")
            level_id = level.get("levelId")
            if not isinstance(level_id, str) or level_id in seen:
                raise APIError(422, "candidate_selection_invalid", "Selected candidate IDs must be unique.")
            if level.get("side") not in allowed_sides:
                raise APIError(409, "candidate_selection_mismatch", "A selected candidate is outside the saved direction.")
            seen.add(level_id)
            expected = saved_levels.get(level_id)
            if expected is None or (level.get("side"), level.get("price")) != expected:
                raise APIError(409, "candidate_selection_mismatch", "A selected level changed from its saved candidate.")

    def _create(
        self,
        body: dict[str, Any],
        *,
        request_guard: Callable[[], Any] | None = None,
    ) -> dict[str, Any]:
        if request_guard is not None:
            request_guard()
        required_fields = {"instrumentId", "interval", "requestId"}
        if (
            not isinstance(body, dict)
            or not required_fields.issubset(body)
            or set(body).difference(required_fields | {"direction"})
        ):
            raise APIError(422, "invalid_automatic_request", "The automatic strategy request is invalid.")
        instrument_id = body.get("instrumentId")
        interval = body.get("interval")
        request_id = body.get("requestId")
        direction = body.get("direction", "both")
        if not isinstance(direction, str) or direction not in _DIRECTIONS:
            raise APIError(422, "invalid_automatic_request", "Choose long, short, or both for strategy direction.")
        if not isinstance(instrument_id, str) or _INSTRUMENT_ID.fullmatch(instrument_id) is None:
            raise APIError(422, "invalid_automatic_request", "Choose a valid USDT SWAP instrument.")
        if interval not in _INTERVALS:
            raise APIError(422, "invalid_automatic_request", "Choose H6, D1, or W1 UTC candles.")
        if not isinstance(request_id, str) or _REQUEST_ID.fullmatch(request_id) is None:
            raise APIError(422, "invalid_automatic_request", "The request ID must contain 8 to 64 safe characters.")

        _, fingerprint = self.strategy._account()
        existing = self._find_request(fingerprint, request_id)
        if existing is not None:
            replay = self._replay_or_conflict(existing, instrument_id, interval, direction)
            if request_guard is not None:
                request_guard()
            return replay

        screening_thresholds = self.strategy._jev_screening_thresholds(fingerprint)

        instrument, tick_size = self._instrument(instrument_id)
        quote = self._quote(instrument_id)
        observed_ms = timestamp_milliseconds(quote.get("ts"))
        reference_price = parse_decimal(quote.get("last"))
        if observed_ms is None or reference_price is None or reference_price <= 0:
            raise APIError(502, "automatic_market_invalid", "The selected SWAP quote is invalid.")
        now_ms = int(self.strategy.clock() * 1000)
        age = now_ms - observed_ms
        if age < 0 or age > _MAX_AGE_MS:
            raise APIError(409, "quote_stale", "The selected SWAP quote is stale; refresh the request.")
        observed_at = _iso_from_epoch_ms(observed_ms)

        generation_candles = self._load_candles(
            instrument_id, interval, snapshot_time_ms=observed_ms, required_count=500,
        )
        context_candles: dict[str, list[dict[str, Any]]] = {}
        for context_interval in _INTERVALS:
            if context_interval == interval:
                rows = generation_candles
            else:
                try:
                    rows = self._load_candles(
                        instrument_id, context_interval,
                        snapshot_time_ms=observed_ms,
                        required_count=_CONTEXT_CANDLE_COUNT,
                    )
                except APIError:
                    rows = []
            context_candles[context_interval] = rows[-_CONTEXT_CANDLE_COUNT:]

        try:
            supports, resistances = calculate_levels(
                generation_candles,
                reference_price=decimal_text(reference_price),
                tick_size=tick_size,
                interval=interval,
            )
        except CandleDataError:
            raise APIError(502, "automatic_candles_invalid", "Closed candle data is invalid.") from None

        if direction == "long":
            resistances = []
        elif direction == "short":
            supports = []

        candidates = supports + resistances
        contexts: list[dict[str, Any]] = []
        context_hashes: list[str] = []
        for candidate in candidates:
            context = self._level_context(
                candidate,
                instrument_id=instrument_id,
                source_interval=interval,
                observed_at=observed_at,
                reference_price=decimal_text(reference_price),
                candles=context_candles,
            )
            contexts.append(context)
            context_hashes.append(_json_hash(context))

        outcomes = self._evaluate(contexts)
        assessments: list[dict[str, Any]] = []
        for outcome, context_hash in zip(outcomes, context_hashes):
            try:
                assessments.append(self._assessment(outcome, context_hash=context_hash))
            except Exception:
                # A malformed injected/provider response cannot discard its candidate.
                assessments.append(self._assessment(
                    ProviderOutcome(
                        status="failed", error_code="provider_error",
                        model_requested="jev-latest",
                    ),
                    context_hash=context_hash,
                ))
        for candidate, assessment in zip(candidates, assessments):
            candidate["assessment"] = assessment
            self._log_assessment(instrument_id, candidate, assessment)
        self._rank(supports)
        self._rank(resistances)

        # A long-running read/evaluation request cannot persist into a different
        # authenticated exchange-account context.
        _, current_fingerprint = self.strategy._account()
        if not hmac.compare_digest(fingerprint, current_fingerprint):
            raise APIError(409, "account_changed", "The active OKX account changed during generation.")
        if request_guard is not None:
            request_guard()

        generation = self._generation_snapshot(
            instrument_id=instrument_id,
            interval=interval,
            request_id=request_id,
            direction=direction,
            tick_size=tick_size,
            reference_price=decimal_text(reference_price),
            observed_at=observed_at,
            generation_candles=generation_candles,
            context_candles=context_candles,
            supports=supports,
            resistances=resistances,
            screening_thresholds=screening_thresholds,
        )
        candidate_id = self._persist_candidate(
            fingerprint=fingerprint,
            instrument_id=instrument_id,
            interval=interval,
            request_id=request_id,
            direction=direction,
            generation=generation,
        )
        strategy, _, current_fingerprint = self.strategy._current_strategy(candidate_id)
        if not hmac.compare_digest(fingerprint, current_fingerprint):
            raise APIError(409, "account_changed", "The active OKX account changed during generation.")
        result = (
            self.public_candidate_result(strategy)
            if self.is_candidate_stage(strategy)
            else self.strategy._result_for(strategy, fingerprint)
        )
        if request_guard is not None:
            request_guard()
        return result

    def _find_request(self, fingerprint: str, request_id: str) -> dict[str, Any] | None:
        with self.strategy.store.connection() as connection:
            rows = connection.execute(
                "SELECT * FROM strategies WHERE account_fingerprint=? ORDER BY created_at DESC",
                (fingerprint,),
            ).fetchall()
        for row in rows:
            snapshot = decode_json(row["snapshot_json"])
            generation = snapshot.get("aiGeneration") if isinstance(snapshot, dict) else None
            if isinstance(generation, dict) and generation.get("requestId") == request_id:
                return self.strategy._decode_row(row)
        return None

    def _replay_or_conflict(
        self, strategy: dict[str, Any], instrument_id: str, interval: str, direction: str
    ) -> dict[str, Any]:
        generation = strategy["snapshot"].get("aiGeneration")
        saved_direction = self._generation_direction(generation)
        if (
            strategy["contract"].get("instrumentId") != instrument_id
            or strategy["contract"].get("interval") != interval
            or not isinstance(generation, dict)
            or generation.get("instrumentId") != instrument_id
            or generation.get("interval") != interval
            or saved_direction is None
            or saved_direction != direction
        ):
            raise APIError(409, "automatic_request_conflict", "This request ID is already bound to different input.")
        if self.is_candidate_stage(strategy):
            return self.public_candidate_result(strategy)
        return self.strategy._result_for(strategy, strategy["accountFingerprint"])

    def _instrument(self, instrument_id: str) -> tuple[dict[str, Any], str]:
        family = instrument_id[:-len("-SWAP")]
        base = instrument_id.split("-", 1)[0]
        try:
            rows = self.strategy.okx.instruments("SWAP")
        except OKXError as exc:
            raise self.strategy._read_failure(
                exc,
                fallback_code="automatic_market_unavailable",
                fallback_message="Current public market data is unavailable.",
            ) from None
        matches = [row for row in rows if row.get("instId") == instrument_id]
        if len(matches) != 1:
            raise APIError(422, "instrument_unavailable", "The selected live USDT SWAP is unavailable.")
        instrument = matches[0]
        tick = parse_decimal(instrument.get("tickSz"))
        metadata_base = instrument.get("baseCcy")
        metadata_quote = instrument.get("quoteCcy")
        if (
            instrument.get("instType") != "SWAP"
            or instrument.get("state") != "live"
            or instrument.get("instFamily") != family
            or instrument.get("ctType") != "linear"
            or instrument.get("settleCcy") != "USDT"
            or instrument.get("ctValCcy") != base
            or (metadata_base not in (None, "") and metadata_base != base)
            or (metadata_quote not in (None, "") and metadata_quote != "USDT")
            or tick is None
            or tick <= 0
        ):
            raise APIError(422, "instrument_unavailable", "The selected live USDT SWAP metadata is invalid.")
        return instrument, decimal_text(tick)

    def _quote(self, instrument_id: str) -> dict[str, Any]:
        try:
            quote = self.strategy.okx.ticker(instrument_id)
        except OKXError as exc:
            raise self.strategy._read_failure(
                exc,
                fallback_code="automatic_market_unavailable",
                fallback_message="Current public market data is unavailable.",
            ) from None
        if not isinstance(quote, dict) or quote.get("instId") != instrument_id:
            raise APIError(502, "automatic_market_invalid", "The selected SWAP quote is invalid.")
        return quote

    def _load_candles(
        self,
        instrument_id: str,
        interval: str,
        *,
        snapshot_time_ms: int,
        required_count: int,
    ) -> list[dict[str, Any]]:
        bar = _BARS[interval]
        collected: list[Any] = []
        cursor: str | None = None
        previous_oldest: int | None = None
        for _ in range(10):
            try:
                page = self.strategy.okx.market_candles(
                    instrument_id,
                    bar,
                    after=cursor,
                    limit=300,
                )
            except OKXError as exc:
                raise self.strategy._read_failure(
                    exc,
                    fallback_code="automatic_market_unavailable",
                    fallback_message="Closed public candles are unavailable.",
                ) from None
            if not isinstance(page, list) or len(page) > 300:
                raise APIError(502, "automatic_candles_invalid", "Closed candle data is invalid.")
            if not page:
                break
            collected.extend(page)
            timestamps = [
                timestamp_milliseconds(row[0])
                for row in page
                if isinstance(row, (list, tuple)) and row
            ]
            timestamps = [value for value in timestamps if value is not None]
            if not timestamps:
                break
            page_oldest = min(timestamps)
            if previous_oldest is not None and page_oldest >= previous_oldest:
                raise APIError(502, "automatic_candle_pagination_invalid", "Candle pagination did not move to older data.")
            previous_oldest = page_oldest
            try:
                normalized = normalize_candles(
                    collected,
                    interval=interval,
                    snapshot_time_ms=snapshot_time_ms,
                )
            except CandleDataError:
                raise APIError(502, "automatic_candles_invalid", "Closed candle data is invalid.") from None
            if len(normalized) >= required_count or len(page) < 300:
                break
            cursor = str(page_oldest)
        try:
            normalized = normalize_candles(
                collected,
                interval=interval,
                snapshot_time_ms=snapshot_time_ms,
            )
        except CandleDataError:
            raise APIError(502, "automatic_candles_invalid", "Closed candle data is invalid.") from None
        return normalized[-required_count:]

    @staticmethod
    def _level_context(
        candidate: dict[str, Any],
        *,
        instrument_id: str,
        source_interval: str,
        observed_at: str,
        reference_price: str,
        candles: dict[str, list[dict[str, Any]]],
    ) -> dict[str, Any]:
        price = Decimal(candidate["price"])
        reference = Decimal(reference_price)
        with localcontext() as context:
            context.prec = 4096
            distance = (price - reference) / reference * Decimal(100)
        observed = datetime.fromisoformat(observed_at.replace("Z", "+00:00"))
        last_touch = datetime.fromisoformat(candidate["lastTouchAt"].replace("Z", "+00:00"))
        first_touch = datetime.fromisoformat(candidate["firstTouchAt"].replace("Z", "+00:00"))
        age_seconds = max(0, int((observed - first_touch).total_seconds()))
        time_since_last_swing_seconds = max(0, int((observed - last_touch).total_seconds()))
        compact = {
            interval: [
                {
                    "timestamp": row["timestamp"],
                    "open": row["open"],
                    "high": row["high"],
                    "low": row["low"],
                    "close": row["close"],
                    "volume": row["volume"],
                }
                for row in candle_rows
            ]
            for interval, candle_rows in candles.items()
        }
        return {
            "version": "level-context-v1",
            "candidate": {
                "levelId": candidate["levelId"],
                "type": "support" if candidate["side"] == "long" else "resistance",
                "side": candidate["side"],
                "price": candidate["price"],
                "sourceTimeframe": source_interval,
            },
            "symbol": instrument_id,
            "snapshotTimestamp": observed_at,
            "currentPrice": reference_price,
            "signedDistancePercentage": decimal_text(distance),
            "candles": compact,
            "confluenceCount": None,
            "sourceSwing": {
                "touchCount": candidate["touchCount"],
                "firstTouchAt": candidate["firstTouchAt"],
                "lastTouchAt": candidate["lastTouchAt"],
                "ageSeconds": age_seconds,
                "timeSinceLastSwingSeconds": time_since_last_swing_seconds,
            },
        }

    def _evaluate(self, contexts: list[dict[str, Any]]) -> list[Any]:
        if not contexts:
            return []
        try:
            provider = self.provider_factory()
            outcomes = provider.evaluate_many(contexts)
        except Exception:
            outcomes = [
                ProviderOutcome(
                    status="failed", error_code="provider_error", model_requested="jev-latest"
                )
                for _ in contexts
            ]
        if not isinstance(outcomes, list):
            outcomes = []
        outcomes = outcomes[:len(contexts)]
        while len(outcomes) < len(contexts):
            outcomes.append(ProviderOutcome(
                status="failed", error_code="provider_error", model_requested="jev-latest"
            ))
        return outcomes

    @staticmethod
    def _assessment(outcome: Any, *, context_hash: str) -> dict[str, Any]:
        status = _outcome_value(outcome, "status", default="failed")
        status = status if isinstance(status, str) and status in {"success", "failed", "disabled"} else "failed"
        raw_code = _outcome_value(outcome, "error_code", "errorCode")
        error_code = raw_code if isinstance(raw_code, str) and raw_code in _ERROR_CODES else None
        requested = _outcome_value(outcome, "model_requested", "modelRequested", default="jev-latest")
        if (
            not isinstance(requested, str) or not requested.strip() or len(requested) > 128
            or any(ord(char) < 32 for char in requested)
        ):
            requested = "jev-latest"
        model_used = _outcome_value(outcome, "model_used", "modelUsed")
        quality = _numeric(_outcome_value(outcome, "structural_quality", "structuralQuality"), 0, 5)
        suitability = _numeric(
            _outcome_value(outcome, "entry_suitability_probability", "entrySuitabilityProbability"), 0, 1
        )
        failure_risk = _numeric(
            _outcome_value(outcome, "failure_risk_probability", "failureRiskProbability"), 0, 1
        )
        if status == "success" and (
            not isinstance(model_used, str) or not model_used.strip() or len(model_used) > 128
            or any(ord(char) < 32 for char in model_used)
        ):
            status, error_code = "failed", "invalid_model"
        elif status == "success" and any(value is None for value in (quality, suitability, failure_risk)):
            status, error_code = "failed", "invalid_response"
        if status != "success":
            model_used = None
            quality = suitability = failure_risk = None
            if error_code is None:
                error_code = "provider_error" if status == "failed" else "disabled"
        latency = _outcome_value(outcome, "latency_ms", "latencyMs", default=0)
        latency = latency if isinstance(latency, int) and not isinstance(latency, bool) else 0
        evaluated_at = _outcome_value(outcome, "evaluated_at", "evaluatedAt")
        timestamp_valid = False
        if isinstance(evaluated_at, str) and evaluated_at and len(evaluated_at) <= 40:
            try:
                parsed_timestamp = datetime.fromisoformat(evaluated_at.replace("Z", "+00:00"))
                timestamp_valid = (
                    parsed_timestamp.tzinfo is not None
                    and parsed_timestamp.utcoffset() == timezone.utc.utcoffset(parsed_timestamp)
                )
            except ValueError:
                timestamp_valid = False
        if not timestamp_valid:
            evaluated_at = _utc_now(time.time())
        return {
            "provider": "typesafe",
            "contextVersion": "level-context-v1",
            "evaluationVersion": "level-eval-v1",
            "modelRequested": requested,
            "modelUsed": model_used,
            "status": status,
            "evaluatedAt": evaluated_at,
            "latencyMs": min(12_000, max(0, latency)),
            "structuralQuality": quality,
            "structuralQualityRubric": list(STRUCTURAL_QUALITY_RUBRIC),
            "entrySuitabilityProbability": suitability,
            "failureRiskProbability": failure_risk,
            "contextHash": context_hash,
            "errorCode": error_code,
        }

    @staticmethod
    def _log_assessment(
        instrument_id: str, candidate: dict[str, Any], assessment: dict[str, Any]
    ) -> None:
        candidate_id = candidate.get("levelId")
        if not isinstance(candidate_id, str) or re.fullmatch(r"[A-Za-z0-9_-]{1,128}", candidate_id) is None:
            candidate_id = None
        event = {
            "event": "ai_jev_assessment",
            "provider": "typesafe",
            "candidateId": candidate_id,
            "symbol": instrument_id,
            "contextVersion": "level-context-v1",
            "evaluationVersion": "level-eval-v1",
            "status": assessment["status"],
            "errorCode": assessment["errorCode"],
            "latencyMs": assessment["latencyMs"],
        }
        try:
            _LOGGER.info(json.dumps(event, separators=(",", ":"), sort_keys=True))
        except Exception:
            # Diagnostics remain best-effort and must not affect draft creation.
            pass

    @staticmethod
    def _rank(candidates: list[dict[str, Any]]) -> None:
        candidates.sort(key=lambda candidate: (
            candidate["assessment"]["status"] != "success",
            -(candidate["assessment"]["entrySuitabilityProbability"] or 0)
                if candidate["assessment"]["status"] == "success" else 0,
            -(candidate["assessment"]["structuralQuality"] or 0)
                if candidate["assessment"]["status"] == "success" else 0,
            candidate["assessment"]["failureRiskProbability"] or 0
                if candidate["assessment"]["status"] == "success" else 0,
            candidate["generationOrder"],
        ))
        for rank, candidate in enumerate(candidates, start=1):
            candidate["rank"] = rank

    @staticmethod
    def _recommendation(
        supports: list[dict[str, Any]],
        resistances: list[dict[str, Any]],
        screening_thresholds: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        thresholds = screening_thresholds or {
            "minStructuralQuality": _RECOMMENDATION_MIN_QUALITY,
            "minEntrySuitabilityProbability": _RECOMMENDATION_MIN_SUITABILITY,
            "maxFailureRiskProbability": _RECOMMENDATION_MAX_FAILURE_RISK,
        }

        def eligible_ids(candidates: list[dict[str, Any]], side: str) -> list[str]:
            eligible: list[tuple[int, dict[str, Any]]] = []
            seen_ids: set[str] = set()
            for candidate in candidates:
                if not isinstance(candidate, dict) or candidate.get("side") != side:
                    continue
                level_id = candidate.get("levelId")
                rank = candidate.get("rank")
                price = parse_decimal(candidate.get("price"))
                assessment = candidate.get("assessment")
                if (
                    not isinstance(level_id, str) or not level_id or level_id in seen_ids
                    or not isinstance(rank, int) or isinstance(rank, bool) or rank < 1
                    or price is None or price <= 0
                    or not isinstance(assessment, dict)
                    or assessment.get("status") != "success"
                ):
                    continue
                quality = _numeric(
                    assessment.get("structuralQuality"), thresholds["minStructuralQuality"], 5
                )
                suitability = _numeric(
                    assessment.get("entrySuitabilityProbability"),
                    thresholds["minEntrySuitabilityProbability"], 1,
                )
                failure_risk = _numeric(
                    assessment.get("failureRiskProbability"),
                    0,
                    thresholds["maxFailureRiskProbability"],
                )
                if quality is None or suitability is None or failure_risk is None:
                    continue
                seen_ids.add(level_id)
                eligible.append((rank, candidate))

            eligible.sort(key=lambda item: item[0])
            return [
                candidate["levelId"]
                for _, candidate in eligible[:_RECOMMENDATION_MAX_PER_SIDE]
            ]

        return {
            "version": _RECOMMENDATION_VERSION,
            "maxPerSide": _RECOMMENDATION_MAX_PER_SIDE,
            "minStructuralQuality": thresholds["minStructuralQuality"],
            "minEntrySuitabilityProbability": thresholds["minEntrySuitabilityProbability"],
            "maxFailureRiskProbability": thresholds["maxFailureRiskProbability"],
            "longLevelIds": eligible_ids(supports, "long"),
            "shortLevelIds": eligible_ids(resistances, "short"),
        }

    @staticmethod
    def _generation_snapshot(
        *,
        instrument_id: str,
        interval: str,
        request_id: str,
        direction: str,
        tick_size: str,
        reference_price: str,
        observed_at: str,
        generation_candles: list[dict[str, Any]],
        context_candles: dict[str, list[dict[str, Any]]],
        supports: list[dict[str, Any]],
        resistances: list[dict[str, Any]],
        screening_thresholds: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        def candle_metadata(rows: list[dict[str, Any]]) -> dict[str, Any]:
            compact = [{key: row[key] for key in (
                "timestamp", "open", "high", "low", "close", "volume"
            )} for row in rows]
            return {
                "count": len(rows),
                "firstAt": rows[0]["timestamp"] if rows else None,
                "lastAt": rows[-1]["timestamp"] if rows else None,
                "sha256": _json_hash(compact),
                "candles": compact,
            }

        return {
            "version": "ai-jev-generation-v1",
            "instrumentId": instrument_id,
            "interval": interval,
            "tickSize": tick_size,
            "referencePrice": reference_price,
            "observedAt": observed_at,
            "requestId": request_id,
            "direction": direction,
            "candles": candle_metadata(generation_candles),
            "contextCandles": {
                key: candle_metadata(rows) for key, rows in context_candles.items()
            },
            "recommendation": AutomaticStrategyService._recommendation(
                supports, resistances, screening_thresholds
            ),
            "supports": supports,
            "resistances": resistances,
        }

    def _persist_candidate(
        self,
        *,
        fingerprint: str,
        instrument_id: str,
        interval: str,
        request_id: str,
        direction: str,
        generation: dict[str, Any],
    ) -> str:
        if direction not in _DIRECTIONS or self._generation_direction(generation) != direction:
            raise APIError(422, "invalid_automatic_request", "The automatic strategy direction is invalid.")
        now = self.strategy.clock()
        strategy_id = new_operation_id()
        contract = {
            "instrumentId": instrument_id,
            "interval": interval,
            "direction": direction,
            "selectedLevels": [],
        }
        snapshot = {"draftStage": "candidates", "aiGeneration": generation}
        digest = token_digest(
            encode_json({
                "instrumentId": instrument_id,
                "interval": interval,
                "requestId": request_id,
                "direction": direction,
            }),
            self.strategy.owner.settings.session_signing_key,
        )
        with self.strategy.store.transaction() as connection:
            rows = connection.execute(
                "SELECT * FROM strategies WHERE account_fingerprint=?",
                (fingerprint,),
            ).fetchall()
            for row in rows:
                saved = decode_json(row["snapshot_json"])
                saved_generation = saved.get("aiGeneration") if isinstance(saved, dict) else None
                if isinstance(saved_generation, dict) and saved_generation.get("requestId") == request_id:
                    existing = self.strategy._decode_row(row)
                    existing_direction = self._generation_direction(saved_generation)
                    if (
                        existing["contract"].get("instrumentId") != instrument_id
                        or existing["contract"].get("interval") != interval
                        or existing_direction is None
                        or existing_direction != direction
                    ):
                        raise APIError(409, "automatic_request_conflict", "This request ID is already bound to different input.")
                    return existing["id"]
            connection.execute(
                "INSERT INTO strategies(strategy_id, account_fingerprint, status, contract_json, snapshot_json, "
                "orders_json, results_json, preview_hash, replacement_source_id, submission_mode, created_at, updated_at) "
                "VALUES (?, ?, 'DRAFT', ?, ?, '[]', '[]', ?, NULL, NULL, ?, ?)",
                (
                    strategy_id,
                    fingerprint,
                    encode_json(contract),
                    encode_json(snapshot),
                    digest,
                    now,
                    now,
                ),
            )
        return strategy_id
