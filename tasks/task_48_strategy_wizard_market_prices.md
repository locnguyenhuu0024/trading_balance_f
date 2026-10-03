# Task 48 — Exact wizard prices and one-time reference quote

Status: PASS
Agent Role: implementation_executor
Executor Class: E2
Target Model: gpt-6-luna
Target Effort: max
Target Route: gpt-6-luna / max
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Dispatch Route Status: UNVERIFIABLE (explicitly bound; effective route unavailable)
Specification: `docs/agents/specs/2026-10-02-strategy-preview-market-correction.md`
Plan: `docs/agents/plans/2026-10-02-strategy-preview-market-correction.md`, P03
Requirements: REQ-002, REQ-003, REQ-004; Acceptance: AC-002, AC-003, AC-004

## Objective and scope

Show/send exact tick-aligned selected prices, preserve duplicate rounded levels via IDs, enforce Both-side selection, and fetch the public wizard ticker only once per coin/timeframe load.

Predecessor: T47 PASS. Decisions: D-001 through D-005, D-007. Allowed writes: `lib/features/strategy/data/strategy_market_repository.dart`, `lib/features/strategy/domain/strategy_calculator.dart`, `lib/features/strategy/domain/strategy_models.dart`, `lib/features/strategy/domain/strategy_selection.dart`, `lib/features/strategy/presentation/strategy_wizard_dialog.dart`, and focused `test/features/strategy/strategy_market_repository_test.dart`, `strategy_selection_test.dart`, `strategy_wizard_dialog_test.dart`, plus a new `strategy_calculator_test.dart` if needed. Forbidden: protected configuration contents or writes, dashboard provider, other app features, live order requests.

Executor contract: Preserve exact public decimal source text for candle OHLC, ticker and tick size; calculate medians/tick quantization in decimal integer units without converting an already rounded `double.toString()` artifact. Assign stable source-level IDs before quantization, use IDs for selection/entry and v2 request `direction`/`entryLevelIdBySide`, and show canonical price text on cards and request. Long floors and Short ceils. Both cannot advance unless each side has a chosen level and nearest entry; show a useful reason. Remove wizard periodic ticker/freshness timers and the 15-second UI block on preview/save/apply; show initial quote as timestamped reference and backend quote on review. Keep backend structured stale/error handling and final confirmation.

RED-003: a median/tick fixture produces floating text or merges two rounded prices; Both with one side advances; timer causes >1 ticker call and age disables preview. GREEN-003: exact expected text/IDs, two rows retained, Both gated, one public ticker call per load with no timed calls, backend preview still called and review usable after reference ages. Execute formal RED before GREEN; use focused strategy Flutter tests through `rtk flutter test`, verification ceiling V2. Buildability after final edit: `rtk flutter build web --release`, PASS required. No external configuration action.

Stop and return BLOCKED if exact source decimals cannot be preserved within allowed files or backend v2 response contradicts the approved contract. Coordinator audits displayed/sent price identity and no hidden polling.

## Completion and coordinator audit

Verdict: PASS. Formal RED: `rtk flutter test test/features/strategy/strategy_wizard_dialog_test.dart` exited 1 before the implementation, proving Both could advance with only Long and that wizard ticker calls repeated. GREEN: `rtk flutter test test/features/strategy/strategy_market_repository_test.dart test/features/strategy/strategy_selection_test.dart test/features/strategy/strategy_wizard_dialog_test.dart test/features/strategy/strategy_calculator_test.dart` exited 0. Post-edit buildability: `rtk flutter build web --release` exited 0. Coordinator inspected the permitted source/test diff: exact OHLC/tick text flows through integer-unit median and directional rounding; the same canonical text is displayed and serialized; IDs preserve equal-price rows; Both requires each side; wizard has no polling or 15-second UI gate. Backend preview remains authoritative. No protected configuration path changed. Effective child route was not exposed after explicit `gpt-6-luna` / `max` binding.
