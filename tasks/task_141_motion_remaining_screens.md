# Task 141 — Skeleton and entrance on the remaining screens

Status: APPROVED
Agent Role: implementation_executor
Executor Class: E2
Target Model: gpt-6.1-terra
Target Effort: medium
Target Route: gpt-6.1-terra / medium
Routing Policy: EXECUTOR_ROUTING_POLICY.json v2 (OptCodex v1.4.0)
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Plan: `docs/agents/plans/2026-11-17-motion-polish.md`
Spec: `docs/agents/specs/2026-11-17-motion-polish-design.md`
Plan Steps: P03
Requirements: REQ-106, REQ-107, REQ-108
Decisions: D-024, D-025

## 1. Dispatch Compliance

The CCB dispatcher passes `--model gpt-6.1-terra` and `model_reasoning_effort=medium` on your command line, and your prompt states the route. This is the explicit binding. `UNVERIFIABLE` is a valid state; do not stop for it.

Dispatch Route Status: pending
Requested Model: gpt-6.1-terra
Requested Effort: medium

## 2. Objective

Apply the T140 widgets (`AppSkeleton`, `AppEntranceScope`, `AppEntrance` in `lib/core/widgets/app_motion.dart`) to Strategy, Support-resistance, Tools, Settings and Connections. No change to `app_motion.dart`.

Done when: AC-106 and AC-107 hold for these screens, RED-141 then GREEN-141 pass, buildability passes.

## 3. Preconditions

Predecessors: T140 = PASS. Clean checkout.

## 4. Allowed Scope

- `lib/features/strategy/presentation/strategy_screen.dart`
- `lib/features/support_resistance/presentation/support_resistance_screen.dart`
- `lib/features/tools/tools_screen.dart`
- `lib/features/settings/presentation/settings_screen.dart`
- `lib/features/connections/connections_screen.dart`
- `test/core/widgets/app_motion_screens_test.dart` (new)

## 5. Forbidden Scope

- `app_motion.dart` and every file not listed; protected configuration; `backend/`; Git state; new dependencies.
- No change to providers, texts, keys, callbacks, layout spacing, inline spinners or dialogs.

## 6. Executor Contract

Pattern: put `AppEntranceScope` directly around the screen's main `ListView`; wrap each top-level card in `AppEntrance(index: i)` with `i` counting from 0 in display order (headers/titles are not wrapped).

1. `strategy_screen.dart`: the `FormPendingStatus('Đang tải chiến thuật…')` block (~L162–169) → `const SizedBox(height: 320, child: AppSkeleton(caption: 'Đang tải chiến thuật…', itemCount: 3, itemHeight: 96, padding: EdgeInsets.zero))` (the parent is a `ListView`, so the skeleton's own `ListView` must have a bounded height). Wrap the `ListView` (~L107) in `AppEntranceScope`; wrap `_SignedOutCard`, `_EmptyStrategiesCard` and each `_buildStrategyCard(...)` in `AppEntrance` with running index.
2. `support_resistance_screen.dart`: instrument picker loading (~L504) → `const AppSkeleton(caption: 'Đang tải danh sách coin…', itemHeight: 48)`. Coin `_CoinLevelsCard`s (~L241): wrap their list in `AppEntranceScope`, each card in `AppEntrance(index: i)`. The picker `ListView.separated` rows: no entrance (search filtering would re-trigger it).
3. `tools_screen.dart`: `ListView` (~L18) in `AppEntranceScope`; each of the 4 `_ToolCard`s in `AppEntrance(index: 0..3)`.
4. `settings_screen.dart`: main `ListView` in `AppEntranceScope`; each top-level `Card` (~L459, ~L569, ~L650 and any other top-level card) in `AppEntrance` with running index. The exchange-rate inline `loading` text (~L369) stays.
5. `connections_screen.dart`: loading (~L26) → `const AppSkeleton(caption: 'Đang tải kết nối…', itemCount: 3, itemHeight: 64)`; data `ListView` in `AppEntranceScope`, each connection entry tile in `AppEntrance(index: i)`.
6. New test `app_motion_screens_test.dart`:
   - TEST-141-1 (source check, plain `test`): each of the 5 files contains `AppEntranceScope(` and `AppEntrance(`; strategy, support_resistance and connections also contain `AppSkeleton(`; strategy and support_resistance no longer contain `FormPendingStatus(` for those two captions (check that `'Đang tải chiến thuật…'` and `'Đang tải danh sách coin…'` appear only inside an `AppSkeleton(` call — simplest: `contains("AppSkeleton(caption: 'Đang tải chiến thuật…'")` etc.).
   - TEST-141-2 (widget): pump `ToolsScreen` in a `ProviderScope`/`MaterialApp` the same way existing tool tests do (if none exists, use the minimal overrides `tools_screen.dart` needs); after `pump(100 ms)` the first `_ToolCard`'s ancestor `FadeTransition` opacity < 1; after `pumpAndSettle` all four cards are fully visible and tapping the first card still navigates as before.

## 7. External Configuration / Environment Actions

None.

## 8. Tests

TEST-141-1, TEST-141-2, plus the existing tests of the five screens.

## 9. Mandatory Verification

### RED — RED-141
Command: `flutter test --no-pub test/core/widgets/app_motion_screens_test.dart` on the T140 code.
Expected: TEST-141-1 and TEST-141-2 fail.

### GREEN — GREEN-141
Same command: pass. Then V4 `flutter test --no-pub`: all pass.
Verification ceiling: V4.

### Task Buildability Gate
Required: YES
Command: `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings && flutter build web --no-pub`
Expected: 0 errors; issue count not above the baseline recorded after T140.

### Verification environment
The executor sandbox cannot run Flutter. Write the complete change. Report `red`/`green` as `NOT_RUN` (RED then GREEN order named), `buildability` `BLOCKED` with that reason, `status` `COMPLETED`.

## 10. Stop Conditions

`BLOCKED` if `app_motion.dart` must change, or a screen needs a file outside §4.

## 11. Execution Ledger
(coordinator fills)

## 12. Coordinator Audit
(coordinator fills)
