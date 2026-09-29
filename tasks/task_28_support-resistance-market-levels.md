# Task 28 — Support/resistance market data and levels

Status: PASS
Agent Role: implementation_executor
Executor Class: E2
Target Model: gpt-6-luna
Target Effort: max
Target Route: gpt-6-luna / max
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Dispatch Route Status: UNVERIFIABLE (explicit model/effort bound; effective route unavailable)
Specification: `docs/agents/specs/2026-09-29-support-resistance-watchlist-design.md`
Plan: `docs/agents/plans/2026-09-29-support-resistance-watchlist.md`
Plan Steps: P01
Requirements: REQ-002, REQ-003, REQ-004
Acceptance Criteria: AC-002, AC-003, AC-004

## Objective and dependency

Implement a separate public, read-only market adapter and pure deterministic level calculator. Predecessors: none. The user explicitly authorized Task 28 on 2026-09-29; Tasks 29 and 30 remain on hold. Keep all BMAG/Risk behavior unchanged.

## Allowed write surface

- `lib/features/support_resistance/domain/models.dart`
- `lib/features/support_resistance/domain/level_calculator.dart`
- `lib/features/support_resistance/data/market_repository.dart`
- `test/features/support_resistance/level_calculator_test.dart`
- `test/features/support_resistance/market_repository_test.dart`

Do not read/write protected configuration/environment contents or files, alter dependencies, modify other modules, or make live external service calls without separate authorization. Stop if the approved UTC interval cannot be implemented or validated with available evidence.

## Contract

Implement design §4 exactly: active USDT instruments by mode; exact-market ticker; newest 300 confirmed UTC-aligned candles; strict ±2 swing extrema; ascending price clusters with max/min span <=0.5%; median representative; classify against positive current price; support descending, resistance ascending; maximum five each. Reject malformed/open/duplicate or wrong-key data and expose typed failure/429 states. Public requests should reuse the foreground public request coordinator and single-flight/backoff semantics. Keep transport injectable for deterministic tests.

## RED then GREEN

- RED-28: fixture contains an open high spike, tied neighbor and crossed level. Expected: spike/tie cannot create levels; level below new price appears only as support. Run focused calculator/repository tests first and record exact result.
- GREEN-28: fixture with 300 valid closed candles and mocked Spot/Perpetual responses yields exact median level values, order and market-specific request keys. Run after RED and record exact result.
- Tests: `flutter test --no-pub test/features/support_resistance/level_calculator_test.dart test/features/support_resistance/market_repository_test.dart`.

Verification ceiling V2; escalate only on a specific adapter/calculator integration failure. Buildability gate after final task-local executable change: `flutter build web --no-pub`, canonical Flutter app/web unit; required PASS. If SDK cache permission prevents the command before compilation, report `BLOCKED_ENVIRONMENT` with exact safe error class. Run no protected-config diagnostics.

## Audit ledger

- [x] Explicit child role/model/effort dispatch recorded; effective route UNVERIFIABLE.
- [x] RED observed before GREEN: 2 RED tests, then 5 GREEN tests passed after AUD-28-01 remediation.
- [x] Focused tests and canonical build observed after final change: 10 focused tests passed; `rtk flutter build web --no-pub` succeeded.
- [x] No protected configuration content accessed or modified.
- [x] Coordinator verdict: PASS. Task 29 and Task 30 remain on hold by user instruction.

Audit: `docs/agents/audits/2026-09-29-task-28-support-resistance-market-levels.md`.
