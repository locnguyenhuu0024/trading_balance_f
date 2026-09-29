# Task 30 — Support/resistance screen and navigation

Status: PASS
Agent Role: implementation_executor
Executor Class: E1
Target Model: gpt-6-luna
Target Effort: xhigh
Target Route: gpt-6-luna / xhigh
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Dispatch Route Status: UNVERIFIABLE (explicit model/effort bound; effective route unavailable)
Specification: `docs/agents/specs/2026-09-29-support-resistance-watchlist-design.md`
Plan: `docs/agents/plans/2026-09-29-support-resistance-watchlist.md`
Plan Steps: P03
Requirements: REQ-001..006
Acceptance Criteria: AC-001..005

## Objective and dependency

Integrate the dedicated multi-coin, multi-timeframe screen into a seventh primary destination. Predecessors: T28 and T29 PASS. User authorized T30 on 2026-09-30 after committing T29, and that commit is complete.

## Allowed write surface

- `lib/features/support_resistance/presentation/support_resistance_screen.dart`
- `lib/features/support_resistance/presentation/providers/levels_provider.dart`
- `lib/core/navigation/navigation_destination_data.dart`
- `lib/core/navigation/main_navigation_shell.dart`
- `lib/core/navigation/trading_navigation_bar.dart`
- `test/features/support_resistance/support_resistance_screen_test.dart`
- `test/core/navigation/main_navigation_shell_test.dart`

No protected configuration/environment access or changes; no dependency or BMAG/Risk behavior edits. The seventh item requires a horizontally reachable fixed navigation layout at narrow widths because seven 48 px touch targets exceed 320 px. Floating navigation already provides scroll. Stop for coordinator review if another file becomes necessary.

## Contract

Show a searchable active USDT picker, screen-wide Spot/Perpetual and H1/H4/H6/D1/W1 controls, ordered coin cards with exact-market price and up to five nearest levels per side, fetch timestamp, and clear sparse/loading/unavailable/stale labels. First launch uses Spot/H6 with an empty list and a selection prompt. Keep results independent by coin+mode+timeframe, ignore late obsolete responses, and avoid overlapping same-key refreshes. Refresh every minute only while mounted and on manual trigger. Use `NavigationContentFrame`, theme, adaptive formatting, accessible semantics; keep seventh destination usable in fixed/floating narrow layouts.

## RED then GREEN

- RED-30: pending old-market/timeframe response after a switch and a single-coin failure. Expected: no stale overwrite; other coin remains visible; timer stops on disposal.
- GREEN-30: add two coins, show ordered results for H6, switch market/timeframe, manually refresh, and reach screen through seventh destination in narrow fixed/floating modes.
- Tests: `flutter test --no-pub test/features/support_resistance/support_resistance_screen_test.dart test/core/navigation/main_navigation_shell_test.dart`.

Verification ceiling V3. Buildability gate after final executable change: `flutter build web --no-pub`, canonical Flutter app/web unit; required PASS. Then coordinator owns final `flutter analyze --no-pub` and affected tests. Report SDK cache permission failure as `BLOCKED_ENVIRONMENT` without protected-config diagnostics.

## Audit ledger

- [x] Explicit child role/model/effort dispatch recorded; effective route UNVERIFIABLE.
- [x] RED observed before GREEN, including obsolete-response and narrow-navigation failures.
- [x] Focused tests and canonical build observed after final change: 26 affected V3 tests and Flutter web build passed.
- [x] No protected configuration content accessed or modified.
- [x] Coordinator verdict: PASS.

Audit: `docs/agents/audits/2026-09-30-task-30-support-resistance-screen.md`.
