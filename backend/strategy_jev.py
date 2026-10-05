"""Lazy, bounded adapter for the optional Typesafe Jev assessment provider."""

from __future__ import annotations

import importlib
import math
import os
import queue
import threading
import time
from concurrent.futures import TimeoutError as FutureTimeout
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any


STRUCTURAL_QUALITY_RUBRIC = (
    "extremely weak",
    "weak",
    "below average",
    "average",
    "strong",
    "very strong",
)
def _entry_instructions(state: dict[str, Any]) -> str:
    candidate = state.get("candidate") if isinstance(state, dict) else None
    side = candidate.get("side") if isinstance(candidate, dict) else None
    if side == "long":
        return (
            "Return only the probability from 0 to 1 that this support is suitable for a "
            "potential DCA LONG entry if reached. Do not provide an explanation."
        )
    if side == "short":
        return (
            "Return only the probability from 0 to 1 that this resistance is suitable for a "
            "potential DCA SHORT entry if reached. Do not provide an explanation."
        )
    return "Return only a numeric probability from 0 to 1. Do not provide an explanation."


def _failure_risk_instructions(state: dict[str, Any]) -> str:
    candidate = state.get("candidate") if isinstance(state, dict) else None
    side = candidate.get("side") if isinstance(candidate, dict) else None
    if side == "long":
        return (
            "Return only the probability from 0 to 1 that substantial evidence indicates this "
            "support would materially fail when retested as a DCA LONG level. Do not provide an explanation."
        )
    if side == "short":
        return (
            "Return only the probability from 0 to 1 that substantial evidence indicates this "
            "resistance would materially fail when retested as a DCA SHORT level. Do not provide an explanation."
        )
    return "Return only a numeric probability from 0 to 1. Do not provide an explanation."
STRUCTURAL_QUALITY_INSTRUCTIONS = (
    "Assess the structural quality of this candidate level using the ordered criteria. "
    "Return the probability-weighted score on the 0 to 5 scale. Do not provide an explanation."
)
_OVERALL_DEADLINE_SECONDS = 12.0
_MAX_TIMEOUT_SECONDS = 10.0
_MAX_CONCURRENCY = 8


@dataclass(frozen=True)
class ProviderOutcome:
    status: str
    error_code: str | None
    model_requested: str
    model_used: str | None = None
    structural_quality: Any = None
    entry_suitability_probability: Any = None
    failure_risk_probability: Any = None
    latency_ms: int = 0
    evaluated_at: str = ""


def _evaluated_at() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def _number_setting(value: str | None, *, default: float, minimum: float, maximum: float) -> float:
    if value is None or not value.strip():
        return default
    try:
        parsed = float(value)
    except (TypeError, ValueError, OverflowError):
        return default
    if not math.isfinite(parsed):
        return default
    return min(maximum, max(minimum, parsed))


def _integer_setting(value: str | None, *, default: int, minimum: int, maximum: int) -> int:
    if value is None or not value.strip():
        return default
    try:
        parsed = int(value)
    except (TypeError, ValueError, OverflowError):
        return default
    return min(maximum, max(minimum, parsed))


def _failed(
    model_requested: str,
    *,
    code: str,
    status: str = "failed",
    latency_ms: int = 0,
) -> ProviderOutcome:
    return ProviderOutcome(
        status=status,
        error_code=code,
        model_requested=model_requested,
        latency_ms=max(0, latency_ms),
        evaluated_at=_evaluated_at(),
    )


class TypesafeJevProvider:
    """Evaluate one candidate per System One call with worker-owned clients."""

    def evaluate_many(self, contexts: list[dict[str, Any]]) -> list[ProviderOutcome]:
        # Process environment is read only at this optional provider boundary.
        enabled = os.environ.get("JEV_ENABLED", "").strip().lower() == "true"
        model_requested = os.environ.get("TYPESAFE_DEFAULT_MODEL", "jev-latest").strip() or "jev-latest"
        if len(model_requested) > 128 or any(ord(char) < 32 for char in model_requested):
            return [_failed("jev-latest", code="settings_invalid") for _ in contexts]
        if not enabled:
            return [
                _failed(model_requested, code="disabled", status="disabled")
                for _ in contexts
            ]
        if not os.environ.get("TYPESAFE_API_KEY", "").strip():
            return [
                _failed(model_requested, code="key_missing", status="disabled")
                for _ in contexts
            ]

        timeout_seconds = _number_setting(
            os.environ.get("JEV_TIMEOUT_SECONDS"), default=3.0, minimum=0.05,
            maximum=_MAX_TIMEOUT_SECONDS,
        )
        concurrency = _integer_setting(
            os.environ.get("JEV_MAX_CONCURRENCY"), default=4, minimum=1,
            maximum=_MAX_CONCURRENCY,
        )
        try:
            sdk = importlib.import_module("typesafe_sdk")
            client_type = sdk.TypeSafeClient
            score_type = sdk.Score
            noul_type = sdk.Noul
            retry_policy_type = sdk.RetryPolicy
        except (ImportError, AttributeError):
            return [
                _failed(model_requested, code="sdk_unavailable", status="disabled")
                for _ in contexts
            ]
        if not contexts:
            return []

        worker_count = min(concurrency, len(contexts))
        jobs: queue.Queue[Any] = queue.Queue(maxsize=worker_count)
        completed: queue.Queue[tuple[int, ProviderOutcome]] = queue.Queue()
        sentinel = object()
        deadline = time.monotonic() + _OVERALL_DEADLINE_SECONDS

        def consume(client: Any) -> None:
            while True:
                job = jobs.get()
                if job is sentinel:
                    return
                index, state = job
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    completed.put((index, _failed(model_requested, code="deadline_exceeded")))
                    continue
                started = time.monotonic()
                call_timeout = min(timeout_seconds, remaining)
                try:
                    questions = {
                        "structural_quality": score_type(
                            instructions=STRUCTURAL_QUALITY_INSTRUCTIONS,
                            criteria=list(STRUCTURAL_QUALITY_RUBRIC),
                        ),
                        "entry_suitability": noul_type(instructions=_entry_instructions(state)),
                        "failure_risk": noul_type(instructions=_failure_risk_instructions(state)),
                    }
                    response = client.system_one(
                        state=state,
                        questions=questions,
                        timeout=call_timeout,
                    )
                    scores = response.scores
                    nouls = response.nouls
                    model_used = response.model
                    score = scores["structural_quality"].score
                    suitability = nouls["entry_suitability"].noul
                    failure_risk = nouls["failure_risk"].noul
                    if (
                        not isinstance(model_used, str)
                        or not model_used.strip()
                        or len(model_used) > 128
                        or any(ord(char) < 32 for char in model_used)
                    ):
                        outcome = _failed(
                            model_requested, code="invalid_model",
                            latency_ms=int((time.monotonic() - started) * 1000),
                        )
                    else:
                        outcome = ProviderOutcome(
                            status="success",
                            error_code=None,
                            model_requested=model_requested,
                            model_used=model_used,
                            structural_quality=score,
                            entry_suitability_probability=suitability,
                            failure_risk_probability=failure_risk,
                            latency_ms=max(0, int((time.monotonic() - started) * 1000)),
                            evaluated_at=_evaluated_at(),
                        )
                except (TimeoutError, FutureTimeout):
                    outcome = _failed(
                        model_requested, code="timeout",
                        latency_ms=int((time.monotonic() - started) * 1000),
                    )
                except (KeyError, AttributeError, TypeError, ValueError, OverflowError):
                    outcome = _failed(
                        model_requested, code="invalid_response",
                        latency_ms=int((time.monotonic() - started) * 1000),
                    )
                except Exception:
                    # Provider exception text and objects are intentionally discarded.
                    outcome = _failed(
                        model_requested, code="provider_error",
                        latency_ms=int((time.monotonic() - started) * 1000),
                    )
                completed.put((index, outcome))

        def worker() -> None:
            try:
                client = client_type(
                    model=model_requested,
                    timeout=timeout_seconds,
                    retry=retry_policy_type(max_retries=0),
                )
            except Exception:
                # A client construction or context-entry failure is converted to a
                # fixed outcome for each task this worker drains.
                while True:
                    job = jobs.get()
                    if job is sentinel:
                        return
                    index, _ = job
                    completed.put((index, _failed(model_requested, code="provider_unavailable")))
            else:
                try:
                    scoped_client = client.__enter__()
                except Exception:
                    try:
                        client.__exit__(None, None, None)
                    except Exception:
                        pass
                    while True:
                        job = jobs.get()
                        if job is sentinel:
                            return
                        index, _ = job
                        completed.put((index, _failed(model_requested, code="provider_unavailable")))
                try:
                    consume(scoped_client)
                finally:
                    try:
                        client.__exit__(None, None, None)
                    except Exception:
                        pass

        threads = [threading.Thread(target=worker, name="jev-worker", daemon=False) for _ in range(worker_count)]
        for thread in threads:
            thread.start()

        outcomes: list[ProviderOutcome | None] = [None] * len(contexts)
        submitted = 0
        pending = 0
        while submitted < worker_count and deadline - time.monotonic() >= timeout_seconds:
            jobs.put((submitted, contexts[submitted]))
            submitted += 1
            pending += 1

        abort_submissions = submitted < worker_count
        while pending:
            index, outcome = completed.get()
            if time.monotonic() >= deadline:
                outcome = _failed(
                    model_requested,
                    code="deadline_exceeded",
                    latency_ms=outcome.latency_ms,
                )
            outcomes[index] = outcome
            pending -= 1
            if outcome.error_code == "provider_unavailable":
                abort_submissions = True
            remaining = deadline - time.monotonic()
            if (
                not abort_submissions and submitted < len(contexts)
                and remaining >= timeout_seconds
            ):
                jobs.put((submitted, contexts[submitted]))
                submitted += 1
                pending += 1
            elif submitted < len(contexts) and remaining < timeout_seconds:
                abort_submissions = True

        for index in range(submitted, len(contexts)):
            outcomes[index] = _failed(model_requested, code="deadline_exceeded")
        for _ in threads:
            jobs.put(sentinel)
        for thread in threads:
            thread.join()

        return [
            outcome if outcome is not None else _failed(model_requested, code="deadline_exceeded")
            for outcome in outcomes
        ]
