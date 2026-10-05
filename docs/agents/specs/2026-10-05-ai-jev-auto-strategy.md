# AI Jev Automatic Strategy Drafts

Status: READY_FOR_PLAN
Date: 2026-10-05
Tier: L
Decision Ledger: docs/agents/decisions/2026-10-05-ai-jev-auto-strategy.md

## Objective and repository evidence

Add the Vietnamese icon/title action `Dựng chiến thuật tự động` to the Strategy screen. Select a live USDT linear SWAP and candle interval, request backend generation, persist every candidate with Jev assessments, and resume manual review. Existing trading execution remains authoritative.

OBS-001: Flutter `StrategyLevelCalculator` uses up to 500 available confirmed candles, strict five-candle swings, exact decimal 0.5% clusters, median, directional tick rounding, stable earliest source IDs, and untruncated candidate lists. The separate watchlist calculator is not this feature's algorithm.
OBS-002: Python backend is synchronous WSGI (`backend/app.py`), dictionary models, SQLite JSON snapshots (`backend/store.py`). `StrategyService._save` currently requires selection, sizing, and an authoritative preview hash.
OBS-003: `StrategyWizardDialog` loads market data locally; `StrategyScreen` currently permits Apply on ordinary DRAFTs. `StrategyService._prepare` / `_execute` and strategy worker own OKX execution.

## Requirements and acceptance

| Requirement | Acceptance |
|---|---|
| REQ-001 / AC-001 | Responsive icon/title action, explicit coin and H6/D1/W1 selection, authenticated backend request; show and reopen saved review. |
| REQ-002 / AC-002 | Backend generation matches existing Strategy calculator, including IDs/decimals/touches/order, without changing manual generation. Preserve all candidates and snapshot-time-only data. |
| REQ-003 / AC-003 | One official SDK System One call per candidate when enabled and within bounded request budget, centralized Score + two Noul questions. Invalid/failed/disabled enrichment preserves every candidate with explicit status. |
| REQ-004 / AC-004 | Store candidate Drafts in existing strategies JSON, no migration, no orders/sizing/reservations. Rank supports and resistances separately; no selected/recommended defaults. Old Drafts remain readable. |
| REQ-005 / AC-005 | Manual selection/sizing materializes the same candidate Draft through current preview/save, retaining immutable full AI provenance; only then existing approval/confirmation applies. |
| REQ-006 / AC-006 | Zero Jev authority over OKX; candidate prepare/execute/retry blocked; account and session changes fail closed. All CI tests mocked. |

## Data and API contract

Authenticated `POST /v1/strategies/automatic-drafts`: `{instrumentId, interval, requestId}`. Intervals: `6Hutc`, `1Dutc`, `1Wutc`; requestId is 8–64 safe ASCII ID characters, stable across retries. Persist/return the same request per account; changed input for the same ID conflicts. Backend validates live linear USDT SWAP/tick metadata and obtains public ticker and closed candles using existing transport with `private=False`. The 500-candle limit is a maximum, never a minimum: newer instruments use available history; fewer than five candles may produce an empty reviewable candidate list. Missing optional non-selected timeframe context is represented as unavailable/empty without blocking selected-timeframe generation.

Candidate-stage record: `status=DRAFT`, `draftStage=candidates`, `canApply=false`, `canReview=true`, `orders=[]`, `results=[]`. Snapshot `aiGeneration` contains version, instrumentId, interval, tickSize, referencePrice, observedAt/evaluation snapshot, requestId, candle counts/ranges/hash, and `supports` / `resistances`. Each candidate carries levelId, side (`long`/`short`), exact price string, touchCount, firstTouchAt, lastTouchAt, generationOrder, rank, assessment. API list/result exposes the full same metadata so closing/reopening never regenerates or loses it.

Manual save accepts optional `candidateDraftId`. Server verifies account ownership, unchanged candidate stage, instrument/interval, and every selected ID/price/side against immutable saved candidates. Existing normal preview validation/sizing remains in force. Transactionally update the same record to order-ready DRAFT; merge all `aiGeneration` metadata into its new snapshot. Candidate metadata supplied by clients is never trusted.

`level-context-v1`: candidate identity/type/price/source timeframe, symbol, snapshot timestamp, current price, signed distance percentage, supplied H6/D1/W1 closed-candle compact context, confluence count where actually known, source swing touchCount/first/last touch and age. Unavailable ATR/momentum/volume/rejection evidence is absent/null; source swing count is not advertised as literal retest count. Include deterministic serialized context hash. Context includes no account, credential, balance, quantity, leverage, or execution tools. Exclude candles closing after snapshot time.

`level-eval-v1`: structural quality Score criteria ordered `[extremely weak, weak, below average, average, strong, very strong]`, numeric expected score 0–5; retain the rubric (SDK Score is a fractional probability-weighted result). Support suitability asks about potential DCA LONG entry if reached; resistance asks about DCA SHORT. Failure risk asks whether substantial evidence suggests the respective level materially fails on retest. No natural-language instructions or explanations requested.

Assessment: provider=typesafe, context/evaluation versions, modelRequested, modelUsed (SDK `response.model`), status=success/failed/disabled, evaluatedAt, latencyMs, structuralQuality (0–5), structuralQualityRubric, entrySuitabilityProbability (0–1), failureRiskProbability (0–1), contextHash, sanitized bounded errorCode. Reject booleans/nonfinite/out-of-range/missing values and invalid model metadata. Never retain exception text/provider headers/internal client objects.

Ranking: successful results first, suitability descending, quality descending, risk ascending, original generationOrder ascending; failed/disabled remain in original order after successes. Store rank within each side; do not filter or select by rank.

## Provider and bounded execution

Official references verified 2026-10-05: https://docs.typesafe.ai/sdk/python, https://docs.typesafe.ai/sdk/python/api/clients/sync, https://docs.typesafe.ai/sdk/python/api/types/responses, https://docs.typesafe.ai/primitives/score, https://github.com/typesafe-ai/typesafe-sdk-python/releases . Latest observed SDK release: 0.7.2. Sync `TypeSafeClient` supports context-manager cleanup, `timeout`, `RetryPolicy(max_retries=0)`, `Score(criteria=list)`, Noul, and response `.scores` / `.nouls` / `.model`.

Use lazy optional SDK import in a narrow provider adapter; disabled/missing SDK/key never breaks startup or Draft creation. Bounded worker pool (default 4, hard bound 1–8), one client per worker with cleanup, no unbounded per-candidate task queue. Per-call timeout default 3 seconds, no retries; overall enrichment admission/acceptance deadline 12 seconds. Deadline-exhausted and late-return candidates receive failed/deadline status and remain reviewable; no background mutation after returning. Workers drain and close before responding, so SDK timeout or cleanup scheduling may extend wall-clock response duration beyond that budget. Cap configurable timeout at 10 seconds and concurrency at 8. A slow provider may leave incomplete assessments explicitly visible; no generated candidate is lost. Settings are read only at the adapter boundary from process environment, never from protected files or existing RuntimeSettings sections.

## Safety, compatibility and failure

INV-001: generation/evaluation never calls leverage/order submit/amend/cancel or prepares execution. Evaluator has no OKX or TradeService dependency.
INV-002: only confirmed, valid, UTC-aligned, unique closed candles available at snapshot time enter generation/context. Preserve decimal exactness, including equal tick-rounded prices with distinct IDs.
INV-003: candidates are not selected orders. Existing ten-order selection cap stays unchanged; candidate-stage drafts cannot be prepared/executed/retried.
INV-004: old Drafts and normal/manual clients keep current behavior. API errors expose fixed safe categories only. UI uses saved immutable snapshot and session-generation guards.

Market/auth/database failure uses existing API error policy; Jev failures are degradable. No quality threshold, automatic recommendation, execution, sizing, backtesting or financial success claim is introduced.

## Verification, rollout and external setup

RED-084: invalid/timeout/disabled/provider failure, future/open data, unauthenticated/account-changed requests, candidate apply/execute, tampered materialization; zero OKX writes and all candidates retained.
GREEN-084: calculator golden parity, successful provider mapping/ranking, persisted list/read/store reopen, manual materialization retaining assessments, old Draft compatibility.
RED-085: failed/disabled scores remain visible/unselected, stale session responses discarded, candidate Apply unavailable.
GREEN-085: action -> selectors -> backend -> stored review -> explicit selection/sizing -> existing preview/save/confirmation; close/reopen retains candidates/rankings.

Mock provider and exchange in normal tests. Backend build: `python3.12 -m compileall -q backend`; Flutter builds: `flutter build web --no-pub --release`, `flutter build macos --no-pub --release`. No deploy/commit/push. Feature disabled by default. Rollback: disable JEV_ENABLED; manual generation/review remains available and saved metadata readable.

External setup is user-owned: backend Python runtime needs `typesafe-sdk==0.7.2`; process environment keys JEV_ENABLED, TYPESAFE_API_KEY, TYPESAFE_DEFAULT_MODEL, JEV_TIMEOUT_SECONDS, JEV_MAX_CONCURRENCY. No repository manifest/env/config is opened or modified. Local mocked verification does not require setup; live scoring requires user installation/key and backend restart. Exact steps are documented in docs/development/ai-jev-strategy.md.
