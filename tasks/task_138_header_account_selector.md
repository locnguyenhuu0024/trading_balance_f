# Task 138 — Account selector in the header on every screen

Status: PASS
Agent Role: implementation_executor
Executor Class: E2
Target Model: gpt-6.1-terra
Target Effort: medium
Target Route: gpt-6.1-terra / medium
Routing Policy: EXECUTOR_ROUTING_POLICY.json v2 (OptCodex v1.4.0)
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Plan: `docs/agents/plans/2026-11-14-header-account-selector.md`
Plan Steps: P08
Decisions: D-021

## 1. Dispatch Compliance

The CCB dispatcher passes `--model gpt-6.1-terra` and `model_reasoning_effort=medium` on your command line, and your prompt states the route. This is the explicit binding. `UNVERIFIABLE` is a valid state; do not stop for it.

Dispatch Route Status: UNVERIFIABLE
Requested Model: gpt-6.1-terra
Requested Effort: medium

## 2. Objective

The 7 screens listed below show `ScopeBar(compact: true)` in their title row, as `portfolio_screen.dart:236-262` already does. The separate full-width `ScopeBar()` row is gone.

Done when: W24–W27 from the plan pass, and V4 passes.

## 3. Preconditions

Predecessors: T137 = PASS (e9de6d9). Clean checkout.

## 4. Allowed Scope

- `lib/features/orders/presentation/orders_screen.dart`
- `lib/features/market/presentation/market_screen.dart`
- `lib/features/fractal_tracker/presentation/fractal_screen.dart`
- `lib/features/support_resistance/presentation/support_resistance_screen.dart`
- `lib/features/settings/presentation/settings_screen.dart`
- `lib/features/tools/tools_screen.dart`
- `lib/features/connections/scope_switch_gate.dart`
- `test/features/orders/orders_binance_view_test.dart`
- `test/features/market/market_screen_test.dart`
- `test/features/connections/header_scope_bar_test.dart` (new)

## 5. Forbidden Scope

- Do not read or change protected configuration, `backend/` or Git state.
- Do not change `scope_bar.dart`, the picker, `portfolio_screen.dart` or any file outside the list.
- Do not change title text, back buttons, action icons, refresh keys or callbacks, or anything below the header.
- No new dependency.

## 6. Executor Contract

Use `portfolio_screen.dart:236-262` as the reference pattern. In every title `Row`, the title is `Expanded`, followed by `const SizedBox(width: 8)`, then `const Flexible(child: ScopeBar(compact: true))`, then the row's existing trailing widgets in their current order.

1. `orders_screen.dart`:
   - Title row (around line 278): insert the selector after the `Expanded('Lệnh')`, before the login `Tooltip` and `ManualRefreshButton`.
   - Remove the `const Padding(padding: EdgeInsets.fromLTRB(24, 8, 24, 0), child: ScopeBar())` row.
2. `market_screen.dart`:
   - Title row: insert the selector after `Expanded('Thị trường')`, before the reload button.
   - Remove the `const Padding(… child: ScopeBar())` row.
3. `fractal_screen.dart`:
   - Title row: insert the selector after `Expanded('BMAG')`, before the search `IconButton`.
   - Remove the `const Padding(… child: ScopeBar())` row.
   - Keep the coin `TextButton` row.
4. `support_resistance_screen.dart`:
   - Remove the `const ScopeBar()` and the `const SizedBox(height: 12)` above the title row.
   - In the title row, insert the selector after `Expanded(title)`, before the reload button.
   - Make sure there is a `SizedBox(height: 12)` after the title row only if there was not one before. Keep the existing spacing below the title.
5. `settings_screen.dart`:
   - In the title row, insert the selector after `Expanded('Cài đặt')`, before the reload button.
   - Remove `const ScopeBar()` below the row. Keep the `SizedBox(height: 12)` that follows it.
6. `tools_screen.dart`:
   - Replace the sequence title `Text('Công cụ', …)`, `SizedBox(height: 16)`, `ScopeBar()`, `SizedBox(height: 12)` with a `Row(children: [Expanded(child: <same Text>), const SizedBox(width: 8), const Flexible(child: ScopeBar(compact: true))])`, followed by `const SizedBox(height: 12)`.
7. `scope_switch_gate.dart`:
   - Replace the title `Text('Đang đổi tài khoản', …)`, `SizedBox(height: 16)`, `ScopeBar()` with a `Row(children: [Expanded(child: <same Text>), const SizedBox(width: 8), const Flexible(child: ScopeBar(compact: true))])`.
   - Keep the following `SizedBox(height: 64)`.
8. Tests:
   - New `test/features/connections/header_scope_bar_test.dart` (W24): a plain `test` that reads each of the 7 files with `File(path).readAsStringSync()` and expects `contains('ScopeBar(compact: true)')` and `isNot(contains('ScopeBar()'))`, with the path as `reason`.
   - `orders_binance_view_test.dart` (W25): inside the existing `Binance positions and filters web=$web proxy=$proxy` test, right after the first `pump`s, add the following. Do not change existing assertions.
     - `final bar = find.byType(ScopeBar);`
     - `expect(tester.widget<ScopeBar>(bar).compact, isTrue);`
     - Check the shared `Row`, the same way as `test/features/connections/account_state_test.dart:83-87`: some `Row` ancestor of `bar` contains `find.byKey(const Key('orders-manual-refresh'))`.
     - `expect(tester.getCenter(bar).dx, lessThan(tester.getCenter(refresh).dx));`
     - Add the `scope_bar.dart` import if it is missing.
   - `market_screen_test.dart` (W26): in the existing `RED-102 manual market refresh …` test, after the first pump, add the same three checks with `Key('market-manual-refresh')`. Do not change existing assertions.
   - Do not delete tests or weaken other assertions.

## 7. External Configuration / Environment Actions

None.

## 8. Tests

- TEST-138-1 (W24): the source check for the 7 files.
- TEST-138-2 (W25): Orders compact selector in the reload row.
- TEST-138-3 (W26): Market compact selector in the reload row.
- W27: the existing suite.

## 9. Mandatory Verification

### RED — RED-138
Scenario: the new and updated tests on the code before the change.
Command: `flutter test --no-pub test/features/connections/header_scope_bar_test.dart test/features/orders/orders_binance_view_test.dart test/features/market/market_screen_test.dart`
Expected: W24 fails (`ScopeBar()` found), and W25 and W26 fail (`compact` is false).
Status: OBSERVED (host)

### GREEN — GREEN-138
Scenario: the same command after the change, then V4 `flutter test --no-pub`.
Expected: all pass.
Status: PASS (host)

Verification ceiling: V4.

### Verification environment

The executor sandbox cannot run `flutter test` or compile. Write the complete change. Report `red` and `green` as `NOT_RUN` with the tests named in RED then GREEN order. Set `buildability` to `BLOCKED` with that reason, and `status` to `COMPLETED`.

Known Flutter pitfalls:
- `const Flexible(child: ScopeBar(compact: true))` must not be inside an already `const` list if it breaks const rules. Remove `const` from the parent list as needed.
- `Expanded` and `Flexible` must be direct children of a `Row`.
- Do not add imports that `package:flutter/material.dart` already provides.

### Task Buildability Gate

Required: YES
Exact secret-free build command: `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings && flutter build web --no-pub`
Result: PASS

## 10. Stop Conditions

Return `BLOCKED` if the change needs a file outside the list, or a change to `ScopeBar` itself.

## 11. Coordinator Audit

Attempt de2d202d59954785aa7c7634456e04ed. The executor reported `BLOCKED` only because its sandbox cannot build. No rework was needed.
Scope: PASS. Ten allowed files changed (7 screens, 2 updated tests, 1 new test). No unexpected paths.
Contract: PASS.
- All 7 screens use `Expanded(title)` → `SizedBox(8)` → `Flexible(ScopeBar(compact: true))` → their existing icons and reload.
- The old `ScopeBar()` rows are removed.
- Titles, back buttons, keys and callbacks are unchanged.
- Support/resistance keeps a 12 px gap below the header, where the old selector row had been above it.
- `scope_bar.dart` and the picker are unchanged.

RED (host, HEAD lib files with the new tests):
- `header_scope_bar_test` failed (`does not contain 'ScopeBar(compact: true)'`).
- `RED-102 manual market refresh …` failed (the compact check).
- The three `Binance positions and filters` cases failed (the compact check).

GREEN (host):
- The three task test files: 26 passed.
- V4 `flutter test --no-pub`: 681 passed.

Dispatch route compliance: UNVERIFIABLE (requested gpt-6.1-terra / medium, explicit). Parent route inheritance: NO.
Task buildability gate: PASS.
- `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings`: 0 errors, 156 issues (unchanged).
- `flutter build web --no-pub`: built.

Verdict: PASS
