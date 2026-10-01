# Implementation Plan: Position Strategy

Status: IMPLEMENTED
Date: 2026-10-01
Tier: L
Specification: `docs/agents/specs/2026-10-01-position-strategy-design.md`
Decision Ledger: `docs/agents/decisions/2026-10-01-position-strategy-decisions.md`

## 1. Objective and preconditions

Implement REQ-001..REQ-008 and AC-001..AC-007 from the specification. The branch is `feature/position-strategy`. D-001..D-015 are resolved. Execution requires explicit authorization after this plan and task checklist are presented. Existing protected configuration is opaque; no protected file is in scope.

## 2. Planning workstreams and routing

| Workstream | Material | Independent | Route | Logical run | Result |
|---|---|---|---|---|---|
| Frontend/UI, public market data and navigation | YES | YES | R2 / gpt-6-sol / medium | R2-001 | COMPLETE; USED |
| Backend/API, persistence and OKX order lifecycle | YES | YES | R2 / gpt-6-sol / medium | R2-002 | COMPLETE; USED |
| Conditional liquidation math | YES, bounded specialist review | YES | R3 / gpt-6-sol / high | R3-003 | COMPLETE; USED |

Fan-out Required: YES. Required Reasoning Agents: 2. Actual Reasoning Agents: 3. Fan-out Compliance: PASS. Skip Reason: N/A. All three child requests explicitly bound both model and effort; the runtime did not expose effective routes, so dispatch status is UNVERIFIABLE. Coordinator synthesis: Flutter owns public candle/last-price collection and selection; backend owns authoritative decimal sizing, conditional liquidation preview, durable strategy state and private OKX writes. The existing 300-candle watchlist is unchanged.

Coordinator route selection: C3 (`gpt-6-sol` / `medium`) is the repository target for this cross-layer coordination; the current main runtime route is fixed/unexposed and is not claimed to match that target. The hard liquidation dimension used the bounded R3 analysis above.

## 3. Repository impact and exclusions

| Area | Expected non-protected write surface | Purpose |
|---|---|---|
| Backend | `backend/service.py`, `backend/okx.py`, `backend/store.py`, focused new backend strategy module(s), `backend/tests/test_strategy_api.py` | Authenticated preview, persistence, prepare/execute/result/delete, leverage, pending-order preflight, batch/order reconciliation. |
| Flutter market/domain | `lib/features/strategy/**`, selected `lib/features/support_resistance/domain/**` only if reused without changing watchlist semantics, `test/features/strategy/**` | 500-candle strategy scan, level selection, review, one-second quote and status model. |
| Flutter integration | `lib/core/navigation/**`, `lib/features/settings/presentation/**` as needed for the new destination, `lib/features/orders/data/trade_api_client.dart`, `lib/features/orders/presentation/providers/trade_session_provider.dart` if needed, related navigation/trade client tests | Navigation and reuse of current login/session. |

Do not edit or inspect contents of any configuration/environment/build/dependency/CI file, including manifests. Do not change existing position actions or the 300-candle watchlist contract. Do not commit, push, deploy, or send a live OKX order during local tests. New SQLite tables are initialized from permitted backend source, not a protected config file.

External configuration actions: none known. If a new setting becomes necessary, stop for user-provided non-sensitive path/location details and leave the protected file to the user.

## 4. Dependency graph and steps

```text
P01 / T38 backend authenticated contract + fake OKX tests
   -> P02 / T39 Flutter scanner, wizard, list + fake client tests
   -> P03 coordinator integration audit
```

P01 and P02 are serial because the frontend consumes the finalized backend preview/apply/status contract. Both tasks must independently leave their affected build unit buildable. The handoff review kept backend stateful trading and Flutter presentation separate because their failure paths and build gates are independent.

### P01 — Backend strategy contract (T38)

1. Add durable account-fingerprint-scoped strategy and order rows with immutable normalized snapshot and explicit `DRAFT/PREPARED/APPLYING/APPLIED/PARTIAL/UNKNOWN` transitions. A prepare can expire to draft only before any mutation attempt. Draft-only deletion is atomic.
2. Add session-protected preview/save/list/prepare-apply/execute-apply/result/delete endpoints exactly as §5 of the spec. Validate request size, source/rate, account identity, one live linear USDT SWAP, levels, nearest entry, 20-order ceiling, margin split/weights, decimal tick/lot/contract sizing and separate fees. Preview uses current OKX contract/tier/fee metadata and returns exact per-order contracts, margin, fee estimate, cumulative entry and conditional liquidation; reject unavailable or contradictory inputs.
3. On prepare and immediately before the first trade write, recheck account identity, position mode, target instrument's positions and pending orders, instrument metadata and current same-swap quote. Reject marketable/side-invalid stale entry, Net mode for two sides, insufficient funds or changed normalized order set. Prepare returns short-lived token and exact summary; execute consumes it once.
4. Extend `OKXClient` with the minimum account/tier/fee/pending-order/leverage/batch methods needed. Set isolated leverage once per selected side; persist a batch attempt and stable `clOrdId` for each order before network write; submit one batch of at most 20 limit orders. Parse per-order `sCode`/IDs; reconcile accepted, rejected, partial, and unknown results by client order ID without automatic batch retry. Result/status reads never place orders.
5. Report actual filled-only used margin and account position `upl`, `avgPx`, `markPx`, `liqPx` with observation time. If account activity outside this strategy changes the tracked position, mark attribution/refresh state rather than asserting pure strategy ownership.

Preserve INV-001..INV-006. Stop for a missing OKX metadata/fee field, unsupported account mode, or any change requiring protected configuration. Backend public API schema and error codes become the handoff to P02.

### P02 — Flutter strategy workflow (T39)

1. Add the eighth stable navigation destination, Settings visibility/order integration and responsive screen. Keep prior saved preference IDs valid.
2. Build a strategy-only public OKX adapter for live USDT SWAP discovery, same-swap last ticker and up to 500 confirmed UTC candles (`6Hutc`, `12Hutc`, `1Dutc`, `1Wutc`), using the existing request coordinator. Reuse swing/cluster math only through a strategy-specific 500-candle option/instance so the watchlist remains 300/five-per-side. Reject open/invalid/duplicate/wrong-market candles; show sparse/loading/stale states.
3. Build popup and three steps. Step 1 presents side-specific cards, absolute/percent distance to latest same-swap price, checkbox and one nearest-entry radio per side; require 1..20 total. Step 2 accepts positive margin, 1..10 leverage default 5 per side, side percentage default 50/50, allocation weights. Step 3 renders backend-authoritative preview, conditional liquidation rows and fees outside margin, then Save draft or Apply now.
4. Reuse the current authenticated trade session/client for all private strategy calls. Applying a new or saved draft shows the exact server-prepared order list in a final dialog; cancel sends no execute. Disable duplicate submit and surface partial/unknown operation IDs/results instead of retrying.
5. List draft and applied strategies. Drafts can apply/delete but not edit; attempted strategies have no delete/edit action. Poll public same-swap ticker every second only while visible, with one in-flight request per strategy/instrument, out-of-order response protection, backoff and stale timestamp. Poll authenticated status on an independent bounded interval; display current OKX PnL, used margin from fills, percentage, entry/latest/actual `liqPx`, and unavailable values honestly.

Preserve navigation modes and current order/session screens. Stop if the P01 response differs from the recorded schema, or if Flutter build would require a protected manifest change.

### P03 — Coordinator audit

Audit source/test diff by explicit non-protected paths; verify auth, order idempotency, partial/unknown truthfulness, formula/source labels, 20-order ceiling, draft-only deletion, 1-second direct SWAP quote, and navigation. Run the narrow final related test sets and whole affected build once. No production trade is part of local verification.

## 5. RED then GREEN and verification

| Test | Required negative RED first | Primary GREEN second | Command/level |
|---|---|---|---|
| TEST-001 / T38 | Unauthenticated, Net mode two-sided, existing position/order, invalid size, stale token, duplicate execute and unknown batch cause no extra write. | Eligible fake account confirms and submits one correct <=20 order batch; per-order outcomes survive restart. | `python3.12 -m unittest backend.tests.test_strategy_api -v` (V1/V2) |
| TEST-002 / T38 | Missing/ambiguous tier/fee/contract metadata or step already beyond modeled liquidation blocks preview. | Known Decimal fixture gives independent weights, rounded contracts, cumulative entry and conditional liquidation. | `python3.12 -m unittest backend.tests.test_strategy_api -v` (V1/V2) |
| TEST-003 / T39 | Open/wrong swap candles, >20 levels, non-nearest entry and stale response never reach apply. | 500-candle fixture and H12 yield expected levels, wizard state and exact backend preview. | `flutter test --no-pub test/features/strategy` (V1/V2) |
| TEST-004 / T39 | Cancel confirmation, draft delete of attempted strategy, duplicate tap and quote failure have no live execute or false current values. | Apply confirmed draft once; status and 1-second direct quote render expected values; navigation modes remain usable. | `flutter test --no-pub test/features/strategy test/core/navigation` (V2/V3) |

Use focused diagnostics while editing. At the formal checkpoint execute each task's RED before GREEN and record observed result. Later edits invalidate only tests on changed dependency paths; rerun both only if shared basis changed. T38 buildability: `python3.12 -m compileall -q backend` after its final backend edit. T39 buildability: `flutter build web --no-pub` after its final Flutter edit. These commands consume build config only as opaque tool input. Final integration: focused backend and Flutter tests, `flutter analyze --no-pub`, `flutter build web --no-pub`, `git diff --check`; V3 ceiling unless a concrete shared regression warrants V4. Full-suite ownership: NOT_REQUIRED because focused stateful backend + navigation/trade integration cover affected surfaces; escalate on unexplained shared failures.

External verification constraint: none established. Local tests use fake transport and temporary SQLite only; a live exchange acceptance test requires a separate user-directed deployment/operation decision and is not claimed here.

## 6. Data migration, risk and rollout

SQLite forward change is additive: initialize strategy/order tables without deleting sessions/operations. Validate old database initialization and restart persistence under tests. Rollback may stop exposing new endpoints/UI but must retain strategy records and must not cancel exchange orders. Existing 300-candle watchlist output and existing action operation journal remain unchanged.

| Risk | Detection and handling |
|---|---|
| OKX batch is partially accepted or transport times out after submission | Durable attempt record, unique client IDs, per-order result reconciliation; `PARTIAL/UNKNOWN` is never called success and is never auto-resubmitted. |
| Actual liquidation differs from conditional preview | Use validated tiers/fee proxy, show sequential assumed-fill label; switch to OKX `liqPx` after actual fills and display timestamp. |
| UI one-second requests age, overlap or hit rate limits | Single-flight public request, backoff, no stale-response overwrite, timestamp/unavailable state. |
| External trade changes instrument state | Fresh preflight blocks initial application; later status marks position attribution changed. |
| Navigation adds an eighth item on narrow screens | Widget coverage for fixed/floating modes and Settings visibility/order; repair layout within T39. |

## 7. Tasks, route binding and buildability

| Task | Scope | Depends | Role/class | Exact requested model/effort | Build unit and command |
|---|---|---|---|---|---|
| T38 | P01, REQ-004..REQ-008 | none | implementation_executor / E2 | gpt-6-luna / max, EXPLICIT | Python backend: `python3.12 -m compileall -q backend` |
| T39 | P02, REQ-001..REQ-005, REQ-008 | T38 PASS | implementation_executor / E1 | gpt-6-luna / xhigh, EXPLICIT | Flutter web: `flutter build web --no-pub` |

Parent route inheritance is FORBIDDEN for both. Dispatch route status is PENDING until explicit spawn. Both tasks require RED then GREEN and a passing task-local build boundary. The coordinator audits each result before opening the dependent task.

## 8. Completion gate

- [x] explicit execution approval received after this plan/checklist was presented
- [x] T38 and T39 each PASS with compliant route binding, RED-before-GREEN, and task buildability PASS
- [x] AC-001..AC-007 have observed fake-transport/widget evidence; final integration audit PASS
- [x] final changed-path status/diff contains no unexplained or protected-file changes
- [x] no protected configuration contents were read and no protected file was modified
- [x] live OKX behavior is reported as unverified unless separately user-directed and observed

## Change Log

| Revision | Change | Reason |
|---|---|---|
| 1 | Initial ready plan. | Resolved decisions and three planning reasoning results. |
| 2 | Implemented T38 and T39; completed audit and verification. | User approval and observed task evidence. |
