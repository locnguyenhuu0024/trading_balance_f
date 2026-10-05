from __future__ import annotations

import io
import hashlib
import json
import logging
import math
import os
import time
import unittest
from copy import deepcopy
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from types import SimpleNamespace
from unittest.mock import patch
from urllib.parse import parse_qs, urlsplit

from backend.app import create_application
from backend.security import token_digest
from backend.service import RuntimeSettings, TradeService
from backend.strategy_automatic import AutomaticStrategyService
from backend.strategy_jev import ProviderOutcome, STRUCTURAL_QUALITY_RUBRIC, TypesafeJevProvider
from backend.strategy_levels import calculate_levels, normalize_candles


NOW = 1_798_848_000.0
SIGNING_KEY = bytes(range(32))
TOKEN = "automatic-strategy-test-session"
ORIGIN = "https://strategy.example.test"
INSTRUMENT = "BTC-USDT-SWAP"


def _interval_ms(bar: str) -> int:
    return {
        "6Hutc": 6 * 60 * 60 * 1000,
        "1Dutc": 24 * 60 * 60 * 1000,
        "1Wutc": 7 * 24 * 60 * 60 * 1000,
    }[bar]


class AutomaticExchange:
    """Offline public-market fixture that records every exchange request."""

    def __init__(self) -> None:
        self.calls: list[tuple[str, str, dict[str, Any] | None, dict[str, str]]] = []
        self.account_uid = "automatic-test-account"
        self.clock_ms = int(NOW * 1000)
        self.instrument = {
            "instId": INSTRUMENT,
            "instType": "SWAP",
            "instFamily": "BTC-USDT",
            "state": "live",
            "ctType": "linear",
            "baseCcy": "BTC",
            "quoteCcy": "USDT",
            "settleCcy": "USDT",
            "ctValCcy": "BTC",
            "tickSz": "0.1",
        }
        self.bars: dict[str, list[list[str]]] = {
            bar: self._make_bars(bar) for bar in ("6Hutc", "1Dutc", "1Wutc")
        }

    def _make_bars(self, bar: str) -> list[list[str]]:
        width = _interval_ms(bar)
        if bar == "1Wutc":
            monday_offset = 4 * 24 * 60 * 60 * 1000
            anchor = self.clock_ms - ((self.clock_ms - monday_offset) % width)
        else:
            anchor = self.clock_ms - self.clock_ms % width
        newest_closed_open = anchor - width
        rows: list[list[str]] = []
        for index in range(600):
            timestamp = newest_closed_open - (599 - index) * width
            high = 1010 + index % 3
            low = 990 - index % 3
            if index == 40:
                low = 900
            elif index == 60:
                low = 906
            elif index == 80:
                high = 1093
            elif index == 100:
                high = 1099
            rows.append([
                str(timestamp), "1000", str(high), str(low), "1000", "12.5", "12.5", "12500", "1"
            ])
        return rows

    def transport(
        self, method: str, path: str, headers: dict[str, str], body: bytes | None
    ) -> dict[str, Any]:
        parsed = urlsplit(path)
        params = {key: values[-1] for key, values in parse_qs(parsed.query).items()}
        payload = None if body is None else json.loads(body.decode("utf-8"))
        self.calls.append((method, path, payload, dict(headers)))
        if method == "GET" and parsed.path == "/api/v5/account/config":
            return {"code": "0", "data": [{"uid": self.account_uid, "posMode": "net_mode"}]}
        if method == "GET" and parsed.path == "/api/v5/public/instruments":
            return {"code": "0", "data": [deepcopy(self.instrument)]}
        if method == "GET" and parsed.path == "/api/v5/market/ticker":
            return {"code": "0", "data": [{"instId": params.get("instId"), "last": "1000", "ts": str(self.clock_ms)}]}
        if method == "GET" and parsed.path == "/api/v5/market/candles":
            bar = params["bar"]
            rows = self.bars[bar]
            limit = int(params.get("limit", "300"))
            after = int(params["after"]) if "after" in params else None
            if after is not None:
                rows = [row for row in rows if int(row[0]) < after]
            return {"code": "0", "data": deepcopy(list(reversed(rows[-limit:])))}
        raise AssertionError(f"Unexpected fake exchange request: {method} {parsed.path}")


class FixedProvider:
    def __init__(self, evaluator: Any = None) -> None:
        self.evaluator = evaluator
        self.contexts: list[dict[str, Any]] = []

    def evaluate_many(self, contexts: list[dict[str, Any]]) -> list[Any]:
        self.contexts = contexts
        if self.evaluator is not None:
            return self.evaluator(contexts)
        return [
            ProviderOutcome(
                status="success",
                error_code=None,
                model_requested="test-requested",
                model_used="test-actual",
                structural_quality=4.25,
                entry_suitability_probability=(
                    0.9 if context["candidate"]["levelId"].endswith("40") else 0.6
                ),
                failure_risk_probability=0.2,
                latency_ms=12,
                evaluated_at="2026-10-05T00:00:00.000Z",
            )
            for context in contexts
        ]


class DisabledProvider:
    def evaluate_many(self, contexts: list[dict[str, Any]]) -> list[ProviderOutcome]:
        return [
            ProviderOutcome(
                status="disabled",
                error_code="disabled",
                model_requested="test-disabled",
                evaluated_at="2026-10-05T00:00:00.000Z",
            )
            for _ in contexts
        ]


def _candle(timestamp_ms: int, open_price: str, high: str, low: str, close: str) -> dict[str, Any]:
    return {
        "timestampMs": timestamp_ms,
        "timestamp": datetime.fromtimestamp(timestamp_ms / 1000, tz=timezone.utc)
        .isoformat(timespec="milliseconds").replace("+00:00", "Z"),
        "open": open_price,
        "high": high,
        "low": low,
        "close": close,
    }


class FakeTypesafeClient:
    instances: list["FakeTypesafeClient"] = []
    response_factory: Any = None
    error: Exception | None = None

    def __init__(self, **kwargs: Any) -> None:
        self.kwargs = kwargs
        self.calls: list[dict[str, Any]] = []
        self.exit_count = 0
        type(self).instances.append(self)

    def __enter__(self) -> "FakeTypesafeClient":
        return self

    def __exit__(self, *_args: Any) -> None:
        self.exit_count += 1

    def system_one(self, **kwargs: Any) -> Any:
        self.calls.append(kwargs)
        if type(self).error is not None:
            raise type(self).error
        return type(self).response_factory(kwargs)


class FakeScore:
    def __init__(self, *, instructions: str, criteria: list[str]) -> None:
        self.instructions = instructions
        self.criteria = criteria


class FakeNoul:
    def __init__(self, *, instructions: str) -> None:
        self.instructions = instructions


class FakeRetryPolicy:
    def __init__(self, *, max_retries: int) -> None:
        self.max_retries = max_retries


class AutomaticStrategyApiTests(unittest.TestCase):
    def setUp(self) -> None:
        self.db_path = Path(__file__).resolve().parents[2] / (
            f".strategy-automatic-test-{os.getpid()}-{id(self)}.sqlite3"
        )
        self.exchange = AutomaticExchange()
        self.now = NOW
        settings = RuntimeSettings(
            okx_api_key="test-key",
            okx_api_secret="test-secret",
            okx_api_passphrase="test-passphrase",
            admin_password_hash="unused-in-this-session-fixture",
            totp_secret="unused-in-this-session-fixture",
            session_signing_key=SIGNING_KEY,
            allowed_web_origin=ORIGIN,
            operation_db_path=str(self.db_path),
        )
        self.service = TradeService(settings, transport=self.exchange.transport, clock=lambda: self.now)
        self.service.strategy.automatic.provider_factory = DisabledProvider
        self.app = create_application(service=self.service)
        with self.service.store.transaction() as connection:
            connection.execute(
                "INSERT INTO sessions(token_hash, expires_at, created_at) VALUES (?, ?, ?)",
                (token_digest(TOKEN, SIGNING_KEY), self.now + 3600, self.now),
            )

    def tearDown(self) -> None:
        self.db_path.unlink(missing_ok=True)

    def request(
        self,
        method: str,
        path: str,
        body: dict[str, Any] | None = None,
        *,
        authenticated: bool = True,
    ) -> tuple[int, dict[str, Any]]:
        raw = b"" if body is None else json.dumps(body).encode("utf-8")
        environ: dict[str, Any] = {
            "REQUEST_METHOD": method,
            "PATH_INFO": path,
            "REMOTE_ADDR": "127.0.0.1",
            "HTTP_ORIGIN": ORIGIN,
            "CONTENT_TYPE": "application/json",
            "CONTENT_LENGTH": str(len(raw)),
            "wsgi.input": io.BytesIO(raw),
        }
        if authenticated:
            environ["HTTP_AUTHORIZATION"] = f"Bearer {TOKEN}"
        response: dict[str, Any] = {}

        def start_response(status: str, _headers: list[tuple[str, str]]) -> None:
            response["status"] = int(status.split(" ", 1)[0])

        payload = b"".join(self.app(environ, start_response))
        return response["status"], {} if not payload else json.loads(payload.decode("utf-8"))

    @staticmethod
    def generation_request(request_id: str = "request-0001") -> dict[str, str]:
        return {"instrumentId": INSTRUMENT, "interval": "6Hutc", "requestId": request_id}

    def create_candidates(self, request_id: str = "request-0001") -> dict[str, Any]:
        status, result = self.request(
            "POST", "/v1/strategies/automatic-drafts", self.generation_request(request_id)
        )
        self.assertEqual(status, 200, result)
        return result

    @staticmethod
    def _selection_candidates(side: str, count: int) -> list[dict[str, Any]]:
        return [
            {
                "levelId": f"{side}-{index}",
                "side": side,
                "price": str(100 + index),
                "generationOrder": index + 1,
                "rank": index + 1,
                "assessment": {
                    "status": "success",
                    "structuralQuality": 4.5,
                    "entrySuitabilityProbability": 0.9 - index / 100,
                    "failureRiskProbability": 0.1,
                },
            }
            for index in range(count)
        ]

    def test_recommendation_caps_each_side_independently_and_preserves_candidates(self) -> None:
        supports = self._selection_candidates("long", 8)
        resistances = self._selection_candidates("short", 8)
        before = deepcopy((supports, resistances))

        recommendation = AutomaticStrategyService._recommendation(supports, resistances)

        self.assertEqual(recommendation, {
            "version": "ai-jev-selection-v1",
            "maxPerSide": 5,
            "minStructuralQuality": 4,
            "minEntrySuitabilityProbability": 0.6,
            "maxFailureRiskProbability": 0.4,
            "longLevelIds": [f"long-{index}" for index in range(5)],
            "shortLevelIds": [f"short-{index}" for index in range(5)],
        })
        self.assertEqual((supports, resistances), before)

    def test_recommendation_keeps_partial_side_counts_without_transferring_quota(self) -> None:
        supports = self._selection_candidates("long", 8)
        resistances = self._selection_candidates("short", 8)
        for candidate in supports:
            candidate["assessment"]["structuralQuality"] = 3.99

        recommendation = AutomaticStrategyService._recommendation(supports, resistances)

        self.assertEqual(recommendation["longLevelIds"], [])
        self.assertEqual(recommendation["shortLevelIds"], [f"short-{index}" for index in range(5)])

    def test_recommendation_preserves_two_eligible_levels_and_caps_other_side_at_five(self) -> None:
        supports = self._selection_candidates("long", 8)
        resistances = self._selection_candidates("short", 8)
        for candidate in supports[2:]:
            candidate["assessment"]["structuralQuality"] = 3.99

        recommendation = AutomaticStrategyService._recommendation(supports, resistances)

        self.assertEqual(recommendation["longLevelIds"], ["long-0", "long-1"])
        self.assertEqual(recommendation["shortLevelIds"], [f"short-{index}" for index in range(5)])

    def test_recommendation_excludes_all_weak_failed_and_disabled_candidates(self) -> None:
        supports = self._selection_candidates("long", 3)
        resistances = self._selection_candidates("short", 3)
        for candidate in supports:
            candidate["assessment"]["structuralQuality"] = 3.99
        resistances[0]["assessment"]["status"] = "failed"
        resistances[1]["assessment"]["status"] = "disabled"
        resistances[2]["assessment"]["failureRiskProbability"] = 0.41

        recommendation = AutomaticStrategyService._recommendation(supports, resistances)

        self.assertEqual(recommendation["longLevelIds"], [])
        self.assertEqual(recommendation["shortLevelIds"], [])

    def test_recommendation_accepts_inclusive_thresholds_and_rejects_invalid_scores_or_prices(self) -> None:
        supports = self._selection_candidates("long", 1)
        supports[0]["assessment"].update({
            "structuralQuality": 4,
            "entrySuitabilityProbability": 0.6,
            "failureRiskProbability": 0.4,
        })
        resistances = self._selection_candidates("short", 6)
        resistances[0]["assessment"]["structuralQuality"] = True
        resistances[1]["assessment"]["entrySuitabilityProbability"] = float("nan")
        resistances[2]["assessment"]["failureRiskProbability"] = 1.01
        resistances[3]["price"] = "0"
        resistances[4]["price"] = "-1"
        resistances[5]["price"] = "not-a-price"

        recommendation = AutomaticStrategyService._recommendation(supports, resistances)

        self.assertEqual(recommendation["longLevelIds"], ["long-0"])
        self.assertEqual(recommendation["shortLevelIds"], [])

    def test_recommendation_uses_saved_rank_for_ties_and_excludes_failed_or_disabled_assessments(self) -> None:
        tied = self._selection_candidates("long", 3)
        for candidate in tied:
            candidate["assessment"].update({
                "structuralQuality": 4,
                "entrySuitabilityProbability": 0.6,
                "failureRiskProbability": 0.4,
            })
        tied[0]["generationOrder"] = 3
        tied[1]["generationOrder"] = 1
        tied[2]["generationOrder"] = 2
        AutomaticStrategyService._rank(tied)
        short = self._selection_candidates("short", 3)
        short[0]["assessment"]["status"] = "failed"
        short[1]["assessment"]["status"] = "disabled"
        short[2]["assessment"].update({
            "structuralQuality": 3.99,
            "entrySuitabilityProbability": 0.99,
            "failureRiskProbability": 0.01,
        })

        recommendation = AutomaticStrategyService._recommendation(tied, short)

        self.assertEqual(recommendation["longLevelIds"], ["long-1", "long-2", "long-0"])
        self.assertEqual(recommendation["shortLevelIds"], [])

    def test_recommendation_attaches_to_saved_snapshot_and_replays_without_recomputation(self) -> None:
        created = self.create_candidates("recommendation-replay-01")
        generation = created["aiGeneration"]
        recommendation = generation["recommendation"]
        self.assertEqual(set(recommendation), {
            "version", "maxPerSide", "minStructuralQuality",
            "minEntrySuitabilityProbability", "maxFailureRiskProbability",
            "longLevelIds", "shortLevelIds",
        })
        self.assertEqual(recommendation["version"], "ai-jev-selection-v1")
        self.assertEqual(recommendation["longLevelIds"], [])
        self.assertEqual(recommendation["shortLevelIds"], [])
        replay = self.create_candidates("recommendation-replay-01")
        self.assertEqual(replay["aiGeneration"]["recommendation"], recommendation)
        self.assertEqual(replay["aiGeneration"], generation)

    @patch.dict(os.environ, {"JEV_ENABLED": "false"})
    def test_disabled_enrichment_keeps_every_candidate_reviewable_and_idempotent(self) -> None:
        created = self.create_candidates()
        self.assertEqual(created["status"], "DRAFT")
        self.assertEqual(created["draftStage"], "candidates")
        self.assertFalse(created["canApply"])
        self.assertTrue(created["canReview"])
        self.assertEqual(created["orders"], [])
        self.assertEqual(created["results"], [])
        generation = created["aiGeneration"]
        self.assertTrue(generation["supports"] or generation["resistances"])
        self.assertTrue(all(
            candidate["assessment"]["status"] == "disabled"
            for group in (generation["supports"], generation["resistances"])
            for candidate in group
        ))
        market_calls = [call for call in self.exchange.calls if "/market/candles" in call[1]]
        replay = self.create_candidates()
        self.assertEqual(replay["id"], created["id"])
        self.assertEqual(
            len([call for call in self.exchange.calls if "/market/candles" in call[1]]),
            len(market_calls),
        )
        status, listed = self.request("GET", "/v1/strategies")
        self.assertEqual(status, 200)
        self.assertEqual(next(row for row in listed["strategies"] if row["id"] == created["id"])["aiGeneration"], generation)

    def test_same_request_id_with_changed_input_conflicts_without_regeneration(self) -> None:
        self.create_candidates()
        changed = self.generation_request()
        changed["interval"] = "1Dutc"
        status, result = self.request("POST", "/v1/strategies/automatic-drafts", changed)
        self.assertEqual(status, 409, result)
        self.assertEqual(result["error"], "automatic_request_conflict")

    def test_generation_requires_authentication_and_valid_snapshot_request(self) -> None:
        status, _ = self.request(
            "POST", "/v1/strategies/automatic-drafts", self.generation_request(), authenticated=False
        )
        self.assertEqual(status, 401)
        invalid = self.generation_request("bad id")
        status, result = self.request("POST", "/v1/strategies/automatic-drafts", invalid)
        self.assertEqual(status, 422, result)

    @patch.dict(os.environ, {"JEV_ENABLED": "false"})
    def test_candidate_cannot_prepare_execute_retry_or_be_used_as_replacement_source(self) -> None:
        candidate = self.create_candidates()
        before_writes = [call for call in self.exchange.calls if call[0] == "POST"]
        for action, method, body in (
            ("prepare-apply", "POST", {}),
            ("execute-apply", "POST", {"confirmationToken": "ignored"}),
            ("retry-candidates", "GET", None),
        ):
            status, result = self.request(method, f"/v1/strategies/{candidate['id']}/{action}", body)
            self.assertEqual(status, 409, (action, result))
            self.assertEqual(result["error"], "candidate_not_materialized")
        self.assertEqual([call for call in self.exchange.calls if call[0] == "POST"], before_writes)
        level = candidate["aiGeneration"]["supports"][0]
        side = level["side"]
        contract = {
            "instrumentId": INSTRUMENT,
            "interval": candidate["interval"],
            "selectedLevels": [
                {"levelId": level["levelId"], "side": side, "price": level["price"]}
            ],
            "direction": side,
            "entryLevelIdBySide": {side: level["levelId"]},
            "totalMargin": "60",
            "leverage": {side: 5},
            "sidePercent": {side: "100"},
            "allocation": "equal",
            "replacementSourceId": candidate["id"],
            "previewHash": "0" * 64,
        }
        _, fingerprint = self.service.strategy._account()
        fake_preview = {
            "previewHash": "0" * 64,
            "orders": [{
                "levelId": level["levelId"], "side": side,
                "limitPrice": level["price"], "role": "entry",
            }],
            "_internal": {"accountFingerprint": fingerprint, "metadata": {}, "positionMode": "net_mode"},
        }
        with patch.object(self.service.strategy, "_preview_contract", return_value=fake_preview):
            status, result = self.request("POST", "/v1/strategies", contract)
        self.assertEqual(status, 409, result)
        self.assertEqual(result["error"], "candidate_not_materialized")

    @patch.dict(os.environ, {"JEV_ENABLED": "false"})
    def test_market_reads_are_public_and_no_order_mutation_is_sent(self) -> None:
        self.create_candidates()
        market_calls = [call for call in self.exchange.calls if "/market/" in call[1] or "/public/instruments" in call[1]]
        self.assertTrue(market_calls)
        self.assertTrue(all("OK-ACCESS-KEY" not in headers for _, _, _, headers in market_calls))
        self.assertEqual([call for call in self.exchange.calls if call[0] == "POST"], [])

    def test_successful_enrichment_is_side_ranked_saved_and_reopenable(self) -> None:
        contexts: list[dict[str, Any]] = []

        def evaluate(states: list[dict[str, Any]]) -> list[ProviderOutcome]:
            contexts.extend(states)
            seen: dict[str, int] = {"long": 0, "short": 0}
            outcomes: list[ProviderOutcome] = []
            for state in states:
                side = state["candidate"]["side"]
                index = seen[side]
                seen[side] += 1
                outcomes.append(ProviderOutcome(
                    status="success",
                    error_code=None,
                    model_requested="jev-test-requested",
                    model_used="jev-test-actual",
                    structural_quality=3.5 + index / 10,
                    entry_suitability_probability=0.2 if index == 0 else 0.9,
                    failure_risk_probability=0.4 if index == 0 else 0.1,
                    latency_ms=18,
                    evaluated_at="2026-10-05T00:00:00.000Z",
                ))
            return outcomes

        self.service.strategy.automatic.provider_factory = lambda: FixedProvider(evaluate)
        created = self.create_candidates("ranked-request-001")
        generation = created["aiGeneration"]
        for group, selected_ids in (
            (generation["supports"], generation["recommendation"]["longLevelIds"]),
            (generation["resistances"], generation["recommendation"]["shortLevelIds"]),
        ):
            eligible_ids = [
                row["levelId"] for row in group
                if row["price"] != "0"
                and row["assessment"]["status"] == "success"
                and row["assessment"]["structuralQuality"] >= 4
                and row["assessment"]["entrySuitabilityProbability"] >= 0.6
                and row["assessment"]["failureRiskProbability"] <= 0.4
            ][:5]
            self.assertEqual(selected_ids, eligible_ids)
        for group in (generation["supports"], generation["resistances"]):
            self.assertEqual([row["rank"] for row in group], list(range(1, len(group) + 1)))
            self.assertTrue(all(row["assessment"]["status"] == "success" for row in group))
            self.assertTrue(all(row["assessment"]["modelUsed"] == "jev-test-actual" for row in group))
        self.assertTrue(contexts)
        self.assertEqual(set(generation["contextCandles"]), {"6Hutc", "1Dutc", "1Wutc"})
        for interval, metadata in generation["contextCandles"].items():
            self.assertLessEqual(metadata["count"], 20)
            self.assertEqual(len(metadata["candles"]), metadata["count"])
            self.assertEqual(metadata["sha256"], hashlib.sha256(json.dumps(
                metadata["candles"], ensure_ascii=False, separators=(",", ":"), sort_keys=True
            ).encode("utf-8")).hexdigest())
        candidates_by_id = {
            row["levelId"]: row
            for group in (generation["supports"], generation["resistances"])
            for row in group
        }
        for context in contexts:
            serialized = json.dumps(context, ensure_ascii=False, separators=(",", ":"), sort_keys=True)
            expected_hash = hashlib.sha256(serialized.encode("utf-8")).hexdigest()
            self.assertEqual(
                candidates_by_id[context["candidate"]["levelId"]]["assessment"]["contextHash"],
                expected_hash,
            )
        serialized_contexts = json.dumps(contexts, sort_keys=True)
        for forbidden in ("account", "credential", "balance", "quantity", "leverage", "execution"):
            self.assertNotIn(forbidden, serialized_contexts.lower())
        self.assertTrue(all("contextHash" in row["assessment"] for group in (
            generation["supports"], generation["resistances"]
        ) for row in group))
        status, result = self.request("GET", f"/v1/strategies/{created['id']}/result")
        self.assertEqual(status, 200, result)
        self.assertEqual(result["aiGeneration"], generation)
        status, listed = self.request("GET", "/v1/strategies")
        self.assertEqual(status, 200)
        self.assertEqual(next(row for row in listed["strategies"] if row["id"] == created["id"])["aiGeneration"], generation)

    def _materialization_contract(self, candidate: dict[str, Any]) -> dict[str, Any]:
        generation = candidate["aiGeneration"]
        level = (generation["supports"] or generation["resistances"])[0]
        side = level["side"]
        return {
            "instrumentId": candidate["instrumentId"],
            "interval": candidate["interval"],
            "selectedLevels": [{
                "levelId": level["levelId"], "side": side, "price": level["price"],
            }],
            "direction": side,
            "entryLevelIdBySide": {side: level["levelId"]},
            "totalMargin": "60",
            "leverage": {side: 5},
            "sidePercent": {side: "100"},
            "allocation": "equal",
        }

    def _fake_preview(self, contract: dict[str, Any]) -> dict[str, Any]:
        level = contract["selectedLevels"][0]
        _, fingerprint = self.service.strategy._account()
        return {
            "status": "PREVIEW",
            "instrumentId": contract["instrumentId"],
            "interval": contract["interval"],
            "previewHash": "a" * 64,
            "orders": [{
                "levelId": level["levelId"], "side": level["side"],
                "limitPrice": level["price"], "role": "entry",
            }],
            "_internal": {
                "accountFingerprint": fingerprint,
                "metadata": {"fixture": True},
                "positionMode": "net_mode",
            },
        }

    def test_candidate_materializes_same_row_and_preserves_all_ai_metadata(self) -> None:
        candidate = self.create_candidates("materialize-request-01")
        contract = self._materialization_contract(candidate)
        body = {
            **contract,
            "candidateDraftId": candidate["id"],
            "previewHash": "a" * 64,
        }
        with patch.object(
            self.service.strategy, "_preview_contract", return_value=self._fake_preview(contract)
        ):
            status, saved = self.request("POST", "/v1/strategies", body)
        self.assertEqual(status, 200, saved)
        self.assertEqual(saved["id"], candidate["id"])
        self.assertEqual(saved["draftStage"], "materialized")
        self.assertEqual(saved["aiGeneration"], candidate["aiGeneration"])
        self.assertEqual(
            saved["aiGeneration"]["recommendation"],
            candidate["aiGeneration"]["recommendation"],
        )
        persisted = self.service.strategy._load_row(candidate["id"])
        self.assertEqual(persisted["snapshot"]["draftStage"], "materialized")
        self.assertEqual(persisted["snapshot"]["aiGeneration"], candidate["aiGeneration"])
        status, listed = self.request("GET", "/v1/strategies")
        self.assertEqual(status, 200)
        listed_row = next(row for row in listed["strategies"] if row["id"] == candidate["id"])
        self.assertEqual(listed_row["aiGeneration"], candidate["aiGeneration"])

    def test_candidate_materialization_rejects_tampered_id_or_price_before_preview(self) -> None:
        candidate = self.create_candidates("tampered-request-01")
        contract = self._materialization_contract(candidate)
        original = contract["selectedLevels"][0]
        for selection in (
            {**original, "levelId": "not-a-saved-candidate"},
            {**original, "price": str(float(original["price"]) + 1)},
        ):
            with self.subTest(selection=selection):
                tampered = {**contract, "selectedLevels": [selection]}
                if selection["levelId"] != original["levelId"]:
                    tampered["entryLevelIdBySide"] = {selection["side"]: selection["levelId"]}
                body = {**tampered, "candidateDraftId": candidate["id"], "previewHash": "0" * 64}
                with patch.object(self.service.strategy, "_preview_contract") as preview:
                    status, result = self.request("POST", "/v1/strategies", body)
                self.assertEqual(status, 409, result)
                self.assertEqual(result["error"], "candidate_selection_mismatch")
                preview.assert_not_called()

    def test_account_change_after_provider_evaluation_prevents_candidate_persistence(self) -> None:
        marker = "PROVIDER_EXCEPTION_SECRET_MARKER"

        def switch_account(contexts: list[dict[str, Any]]) -> list[ProviderOutcome]:
            self.exchange.account_uid = "different-automatic-test-account"
            raise RuntimeError(marker)

        self.service.strategy.automatic.provider_factory = lambda: FixedProvider(switch_account)
        with self.assertLogs("backend.strategy.jev", level="INFO") as captured:
            status, result = self.request(
                "POST", "/v1/strategies/automatic-drafts",
                self.generation_request("account-change-001"),
            )
        self.assertEqual(status, 409, result)
        self.assertEqual(result["error"], "account_changed")
        with self.service.store.connection() as connection:
            count = connection.execute("SELECT COUNT(*) FROM strategies").fetchone()[0]
        self.assertEqual(count, 0)
        self.assertNotIn(marker, "\n".join(captured.output))

    def test_revoked_session_during_enrichment_prevents_candidate_persistence(self) -> None:
        contexts: list[dict[str, Any]] = []

        def revoke(context_rows: list[dict[str, Any]]) -> list[ProviderOutcome]:
            contexts.extend(context_rows)
            with self.service.store.transaction() as connection:
                connection.execute(
                    "DELETE FROM sessions WHERE token_hash=?",
                    (token_digest(TOKEN, SIGNING_KEY),),
                )
            return [
                ProviderOutcome(
                    status="success", error_code=None, model_requested="test",
                    model_used="test", structural_quality=4,
                    entry_suitability_probability=0.8, failure_risk_probability=0.1,
                    evaluated_at="2026-10-05T00:00:00Z",
                )
                for _ in context_rows
            ]

        self.service.strategy.automatic.provider_factory = lambda: FixedProvider(revoke)
        status, result = self.request(
            "POST", "/v1/strategies/automatic-drafts",
            self.generation_request("revoked-session-01"),
        )
        self.assertEqual(status, 401, result)
        self.assertTrue(contexts)
        self.assertNotIn(TOKEN, json.dumps(contexts))
        with self.service.store.connection() as connection:
            count = connection.execute("SELECT COUNT(*) FROM strategies").fetchone()[0]
        self.assertEqual(count, 0)

    def test_candidate_delete_requires_empty_unattempted_draft_state(self) -> None:
        candidate = self.create_candidates("delete-request-001")
        status, deleted = self.request(
            "POST", f"/v1/strategies/{candidate['id']}/delete", {}
        )
        self.assertEqual(status, 200, deleted)
        self.assertEqual(deleted["status"], "DELETED")
        with self.service.store.connection() as connection:
            self.assertIsNone(connection.execute(
                "SELECT 1 FROM strategies WHERE strategy_id=?", (candidate["id"],)
            ).fetchone())

        unsafe = self.create_candidates("delete-unsafe-001")
        with self.service.store.transaction() as connection:
            connection.execute(
                "UPDATE strategies SET attempt_started=1 WHERE strategy_id=?",
                (unsafe["id"],),
            )
        status, result = self.request(
            "POST", f"/v1/strategies/{unsafe['id']}/delete", {}
        )
        self.assertEqual(status, 409, result)
        self.assertEqual(result["error"], "strategy_immutable")

    def test_concurrent_request_replay_returns_persisted_stage_not_candidate_shape(self) -> None:
        manager = self.service.strategy.automatic
        persist = manager._persist_candidate

        def persist_then_transition(**kwargs: Any) -> str:
            strategy_id = persist(**kwargs)
            with self.service.store.transaction() as connection:
                row = connection.execute(
                    "SELECT snapshot_json FROM strategies WHERE strategy_id=?", (strategy_id,)
                ).fetchone()
                snapshot = json.loads(row["snapshot_json"])
                snapshot["draftStage"] = "materialized"
                connection.execute(
                    "UPDATE strategies SET snapshot_json=? WHERE strategy_id=?",
                    (json.dumps(snapshot, separators=(",", ":")), strategy_id),
                )
            return strategy_id

        with patch.object(manager, "_persist_candidate", side_effect=persist_then_transition):
            status, result = self.request(
                "POST", "/v1/strategies/automatic-drafts",
                self.generation_request("concurrent-request-01"),
            )
        self.assertEqual(status, 200, result)
        self.assertEqual(result["draftStage"], "materialized")
        self.assertIn("aiGeneration", result)
        self.assertNotIn("canReview", result)


class StrategyLevelParityTests(unittest.TestCase):
    @staticmethod
    def _basic_candles(low_swings: dict[int, str], high_swings: dict[int, str]) -> list[dict[str, Any]]:
        start = 1_704_067_200_000  # 2024-01-01 00:00 UTC, Monday.
        rows = [
            _candle(start + index * 6 * 60 * 60 * 1000, "100", "105", "95", "100")
            for index in range(18)
        ]
        for index, value in low_swings.items():
            rows[index]["low"] = value
        for index, value in high_swings.items():
            rows[index]["high"] = value
        return rows

    def test_golden_swings_keep_equal_rounded_ids_zero_levels_touches_and_order(self) -> None:
        candles = self._basic_candles(
            {3: "0.9", 7: "0.8", 11: "90", 15: "90.45"},
            {5: "111", 10: "111.5"},
        )
        supports, resistances = calculate_levels(
            candles, reference_price="100", tick_size="1", interval="6Hutc"
        )
        self.assertEqual(
            [(row["price"], row["touchCount"]) for row in supports],
            [("90", 2), ("0", 1), ("0", 1)],
        )
        self.assertEqual(supports[0]["levelId"], f"low_{candles[11]['timestampMs']}")
        self.assertEqual(supports[0]["firstTouchAt"], candles[11]["timestamp"])
        self.assertEqual(supports[0]["lastTouchAt"], candles[15]["timestamp"])
        self.assertNotEqual(supports[1]["levelId"], supports[2]["levelId"])
        self.assertEqual(
            [(row["price"], row["touchCount"]) for row in resistances], [("112", 2)]
        )
        self.assertEqual(resistances[0]["levelId"], f"high_{candles[5]['timestampMs']}")

    def test_clustering_boundary_preserves_more_than_28_digit_decimal_precision(self) -> None:
        from decimal import Decimal, localcontext

        with localcontext() as context:
            context.prec = 4096
            first = Decimal("10000000000000000000000000000.0000000000000000001")
            epsilon = Decimal("0.0000000000000000001")
            boundary = first + first / Decimal(200)
            just_below = boundary - epsilon
            just_above = boundary + epsilon
            baseline = first * 2
            high = baseline * 2
            body = baseline + (high - baseline) / 2
            reference = first * 5

        start = 1_704_067_200_000
        lows = {3: first, 8: just_below, 13: just_above}
        candles = [
            _candle(
                start + index * 6 * 60 * 60 * 1000,
                str(body), str(high), str(lows.get(index, baseline)), str(body),
            )
            for index in range(18)
        ]
        supports, resistances = calculate_levels(
            candles,
            reference_price=str(reference),
            tick_size="0.0000000000000000001",
            interval="6Hutc",
        )
        self.assertEqual(resistances, [])
        self.assertEqual(sorted(row["touchCount"] for row in supports), [1, 2])
        two_touch = next(row for row in supports if row["touchCount"] == 2)
        one_touch = next(row for row in supports if row["touchCount"] == 1)
        self.assertEqual(two_touch["levelId"], f"low_{candles[3]['timestampMs']}")
        self.assertEqual(one_touch["levelId"], f"low_{candles[13]['timestampMs']}")

    def test_normalization_excludes_unconfirmed_future_and_non_monday_weekly_candles(self) -> None:
        from backend.strategy_levels import normalize_candles

        monday = 1_704_067_200_000
        week = 7 * 24 * 60 * 60 * 1000
        rows = [
            [str(monday), "10", "12", "9", "11", "1", "1", "11", "1"],
            [str(monday + week), "10", "12", "9", "11", "1", "1", "11", "1"],
            [str(monday + 1), "10", "12", "9", "11", "1", "1", "11", "1"],
            [str(monday - week), "10", "12", "9", "11", "1", "1", "11", "0"],
        ]
        candles = normalize_candles(
            rows, interval="1Wutc", snapshot_time_ms=monday + week
        )
        self.assertEqual([row["timestampMs"] for row in candles], [monday])


class TypesafeJevProviderTests(unittest.TestCase):
    def setUp(self) -> None:
        FakeTypesafeClient.instances = []
        FakeTypesafeClient.error = None
        FakeTypesafeClient.response_factory = None
        self.sdk = SimpleNamespace(
            TypeSafeClient=FakeTypesafeClient,
            Score=FakeScore,
            Noul=FakeNoul,
            RetryPolicy=FakeRetryPolicy,
        )

    @staticmethod
    def _contexts() -> list[dict[str, Any]]:
        return [
            {"candidate": {"type": "support", "side": "long"}, "symbol": "BTC-USDT-SWAP"},
            {"candidate": {"type": "resistance", "side": "short"}, "symbol": "BTC-USDT-SWAP"},
        ]

    def test_mock_sdk_calls_exact_contract_and_uses_side_specific_questions(self) -> None:
        FakeTypesafeClient.response_factory = lambda _call: SimpleNamespace(
            scores={"structural_quality": SimpleNamespace(score=4.25)},
            nouls={
                "entry_suitability": SimpleNamespace(noul=0.8),
                "failure_risk": SimpleNamespace(noul=0.2),
            },
            model="jev-actual-model",
        )
        environment = {
            "JEV_ENABLED": "true",
            "TYPESAFE_API_KEY": "TEST_ONLY_API_KEY_DO_NOT_LOG",
            "TYPESAFE_DEFAULT_MODEL": "jev-requested-model",
            "JEV_TIMEOUT_SECONDS": "2.5",
            "JEV_MAX_CONCURRENCY": "1",
        }
        with patch.dict(os.environ, environment, clear=True), patch(
            "backend.strategy_jev.importlib.import_module", return_value=self.sdk
        ):
            outcomes = TypesafeJevProvider().evaluate_many(self._contexts())
        self.assertEqual([outcome.status for outcome in outcomes], ["success", "success"])
        self.assertEqual([outcome.model_requested for outcome in outcomes], ["jev-requested-model"] * 2)
        self.assertEqual([outcome.model_used for outcome in outcomes], ["jev-actual-model"] * 2)
        self.assertEqual([outcome.structural_quality for outcome in outcomes], [4.25, 4.25])
        self.assertEqual(len(FakeTypesafeClient.instances), 1)
        client = FakeTypesafeClient.instances[0]
        self.assertEqual(client.kwargs["model"], "jev-requested-model")
        self.assertEqual(client.kwargs["timeout"], 2.5)
        self.assertEqual(client.kwargs["retry"].max_retries, 0)
        self.assertEqual(client.exit_count, 1)
        self.assertEqual(len(client.calls), 2)
        support_questions = client.calls[0]["questions"]
        resistance_questions = client.calls[1]["questions"]
        self.assertEqual(support_questions["structural_quality"].criteria, list(STRUCTURAL_QUALITY_RUBRIC))
        self.assertIn("DCA LONG", support_questions["entry_suitability"].instructions)
        self.assertIn("support", support_questions["entry_suitability"].instructions)
        self.assertIn("DCA SHORT", resistance_questions["entry_suitability"].instructions)
        self.assertIn("resistance", resistance_questions["entry_suitability"].instructions)
        self.assertIn("DCA LONG", support_questions["failure_risk"].instructions)
        self.assertIn("DCA SHORT", resistance_questions["failure_risk"].instructions)
        self.assertTrue(all(call["timeout"] <= 2.5 for call in client.calls))

    def test_disabled_missing_key_and_missing_sdk_are_fixed_sanitized_outcomes(self) -> None:
        with patch.dict(os.environ, {"JEV_ENABLED": "false"}, clear=True), patch(
            "backend.strategy_jev.importlib.import_module"
        ) as import_sdk:
            disabled = TypesafeJevProvider().evaluate_many(self._contexts())
            import_sdk.assert_not_called()
        self.assertTrue(all(row.status == "disabled" and row.error_code == "disabled" for row in disabled))

        with patch.dict(os.environ, {"JEV_ENABLED": "true"}, clear=True), patch(
            "backend.strategy_jev.importlib.import_module"
        ) as import_sdk:
            missing_key = TypesafeJevProvider().evaluate_many(self._contexts())
            import_sdk.assert_not_called()
        self.assertTrue(all(row.status == "disabled" and row.error_code == "key_missing" for row in missing_key))

        with patch.dict(os.environ, {
            "JEV_ENABLED": "true", "TYPESAFE_API_KEY": "TEST_ONLY_KEY",
        }, clear=True), patch(
            "backend.strategy_jev.importlib.import_module", side_effect=ImportError("must not escape")
        ):
            unavailable = TypesafeJevProvider().evaluate_many(self._contexts())
        self.assertTrue(all(row.status == "disabled" and row.error_code == "sdk_unavailable" for row in unavailable))
        self.assertNotIn("must not escape", repr(unavailable))

    def test_timeout_and_provider_exceptions_are_sanitized_and_clients_close(self) -> None:
        marker = "SENSITIVE_TEST_API_KEY_MARKER"
        environment = {
            "JEV_ENABLED": "true", "TYPESAFE_API_KEY": marker,
            "TYPESAFE_DEFAULT_MODEL": "jev-requested", "JEV_TIMEOUT_SECONDS": "1",
            "JEV_MAX_CONCURRENCY": "1",
        }
        for exception, expected in ((TimeoutError(marker), "timeout"), (RuntimeError(marker), "provider_error")):
            with self.subTest(expected=expected):
                FakeTypesafeClient.instances = []
                FakeTypesafeClient.error = exception
                with patch.dict(os.environ, environment, clear=True), patch(
                    "backend.strategy_jev.importlib.import_module", return_value=self.sdk
                ):
                    outcomes = TypesafeJevProvider().evaluate_many(self._contexts()[:1])
                self.assertEqual(outcomes[0].error_code, expected)
                self.assertEqual(outcomes[0].status, "failed")
                self.assertNotIn(marker, repr(outcomes))
                self.assertEqual(FakeTypesafeClient.instances[0].exit_count, 1)

    def test_provider_success_arriving_after_overall_deadline_is_downgraded_and_drained(self) -> None:
        FakeTypesafeClient.response_factory = lambda _call: (
            time.sleep(0.25) or SimpleNamespace(
                scores={"structural_quality": SimpleNamespace(score=5)},
                nouls={
                    "entry_suitability": SimpleNamespace(noul=1),
                    "failure_risk": SimpleNamespace(noul=0),
                },
                model="late-model",
            )
        )
        environment = {
            "JEV_ENABLED": "true", "TYPESAFE_API_KEY": "TEST_ONLY_KEY",
            "TYPESAFE_DEFAULT_MODEL": "jev-test", "JEV_TIMEOUT_SECONDS": "0.05",
            "JEV_MAX_CONCURRENCY": "1",
        }
        with patch.dict(os.environ, environment, clear=True), patch(
            "backend.strategy_jev._OVERALL_DEADLINE_SECONDS", 0.1
        ), patch("backend.strategy_jev.importlib.import_module", return_value=self.sdk):
            outcomes = TypesafeJevProvider().evaluate_many(self._contexts()[:1])
        self.assertEqual(outcomes[0].status, "failed")
        self.assertEqual(outcomes[0].error_code, "deadline_exceeded")
        self.assertIsNone(outcomes[0].model_used)
        self.assertEqual(FakeTypesafeClient.instances[0].exit_count, 1)

    def test_invalid_provider_numbers_models_and_logs_never_retain_exception_text(self) -> None:
        invalid = AutomaticStrategyService._assessment(
            ProviderOutcome(
                status="success", error_code=None, model_requested="model\nsecret",
                model_used="jev-model", structural_quality=float("nan"),
                entry_suitability_probability=0.5, failure_risk_probability=0.1,
                latency_ms=50_000, evaluated_at="",
            ),
            context_hash="a" * 64,
        )
        self.assertEqual(invalid["status"], "failed")
        self.assertEqual(invalid["errorCode"], "invalid_response")
        self.assertIsNone(invalid["structuralQuality"])
        self.assertEqual(invalid["modelRequested"], "jev-latest")
        self.assertTrue(invalid["evaluatedAt"].endswith("Z"))
        self.assertLessEqual(invalid["latencyMs"], 12_000)

        invalid_model = AutomaticStrategyService._assessment(
            ProviderOutcome(
                status="success", error_code=None, model_requested="jev-test",
                model_used="bad\nmodel", structural_quality=4,
                entry_suitability_probability=0.5, failure_risk_probability=0.1,
                evaluated_at="2026-10-05T00:00:00+07:00",
            ),
            context_hash="b" * 64,
        )
        self.assertEqual(invalid_model["status"], "failed")
        self.assertEqual(invalid_model["errorCode"], "invalid_model")
        self.assertIsNone(invalid_model["modelUsed"])

        marker = "SENSITIVE_PROVIDER_EXCEPTION_TEXT"
        safe_assessment = {
            **invalid,
            "errorCode": "provider_error",
            "latencyMs": 12,
        }
        with self.assertLogs("backend.strategy.jev", level=logging.INFO) as captured:
            AutomaticStrategyService._log_assessment(
                INSTRUMENT,
                {"levelId": "low_1704067200000"},
                safe_assessment,
            )
        logs = "\n".join(captured.output)
        self.assertIn('"errorCode":"provider_error"', logs)
        self.assertNotIn(marker, logs)
        self.assertNotIn("TEST_ONLY_API_KEY_DO_NOT_LOG", logs)
