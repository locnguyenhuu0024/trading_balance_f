# Task 39 — Position Strategy Flutter

Status: PASS
Agent Role: implementation_executor
Executor Class: E1
Target Model: gpt-6-luna
Target Effort: xhigh
Target Route: gpt-6-luna / xhigh
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Dispatch Route Status: UNVERIFIABLE
Requested Model/Effort: gpt-6-luna / xhigh, explicitly bound at dispatch
Observed Effective Model/Effort: unavailable until runtime reports them
Specification: `docs/agents/specs/2026-10-01-position-strategy-design.md`
Plan: `docs/agents/plans/2026-10-01-position-strategy.md`
Plan Steps: P02
Requirements: REQ-001..REQ-005, REQ-008
Acceptance Criteria: AC-001, AC-002, AC-007

## Objective and preconditions

Build the responsive “Chiến Thuật” route, strategy-specific public market scan, three-step wizard, confirmed apply flow, and draft/applied list using the T38 authenticated API. Done when focused tests pass and Flutter web builds. Predecessor: T38 `PASS` with handed-off API schema. Decisions D-001..D-015 apply. Explicitly bind model and effort at dispatch; otherwise `BLOCKED_ROUTE`.

## Allowed write surface

- `lib/features/strategy/**`, `test/features/strategy/**`
- `lib/core/navigation/**` and `test/core/navigation/**` only for eighth destination and its layout/preference behavior
- Relevant `lib/features/settings/presentation/**` and navigation Settings tests for visibility/order
- `lib/features/orders/data/trade_api_client.dart`, `lib/features/orders/presentation/providers/trade_session_provider.dart`, and focused trade-client tests only for new strategy methods/session reuse
- `lib/features/support_resistance/domain/**` only if a strategy-specific calculator option can be added without changing the watchlist contract

All protected configuration/environment/manifest/dependency/CI content and writes are forbidden. Do not change the existing 300-candle watchlist result, existing action UI semantics, or unrelated screens. Do not commit/push or submit a live order from tests. Return `BLOCKED` if the T38 schema or permitted source surface is insufficient.

## Executor contract

Follow P02 and spec §§3–6. The popup supports H6/H12/D1/W1 and one USDT linear SWAP coin. Scan at most 500 confirmed UTC candles, show distance from same-swap last price, select nearest entry per side and no more than 20 total levels. Step 2 takes true margin budget, separate side leverage 1..10 default 5, 50/50 default editable split, equal/linear-increase/linear-decrease weights. Step 3 renders backend-authoritative contracts, cumulative average entry, conditional liquidation and separate fee estimate. Save immutable draft or prepare/confirm/apply now; saved drafts can apply later. List exchange PnL, filled-only margin, PnL percentage, entry/latest/actual liq with timestamps. Direct public OKX same-swap quote polling is one second only while visible, single-flight and stale-aware. Private calls reuse current login; no direct private OKX calls.

External configuration action: none planned. Stop on unavailable backend contract, unvalidated market data or a requirement for protected manifest changes.

## RED then GREEN verification

- RED-001/RED-003: First observe open/wrong swap candles excluded, >20 points/non-nearest entry invalid, no execute on cancelled confirmation/duplicate tap, attempted draft not deletable, and stale quote not shown as current.
- GREEN-001/GREEN-004: Then observe deterministic 500-candle/H12 levels, margin/entry review from backend, successful save/apply confirmed once, truthful list values, one-second quote freshness and working fixed/floating navigation on narrow layouts.
- Commands: `flutter test --no-pub test/features/strategy` (V1/V2), then `flutter test --no-pub test/core/navigation test/features/strategy` if shared navigation risk remains (V3 ceiling).
- Task buildability after last executable edit: `flutter build web --no-pub`; affected canonical unit is Flutter web, required PASS.

## Checklist and audit handoff

- [x] predecessor T38 PASS and API schema matched
- [x] explicit dispatch role/model/effort match and status `MATCH` or `UNVERIFIABLE`
- [x] no protected config content read or protected file modified
- [x] implementation within allowed surface
- [x] observed RED before GREEN and focused tests recorded
- [x] Flutter web buildability PASS after final change
- [x] report exact commands/results, changed paths, UI states and remaining limitations

Coordinator audit: freshness, visibility, prepared-order validation and fee-total findings remediated. Final verdict: PASS; 64 strategy/navigation tests and Flutter web build passed after the final edit. Flutter analyze reported no errors but exited with 42 informational/warning diagnostics. Live OKX behavior remains unverified.
