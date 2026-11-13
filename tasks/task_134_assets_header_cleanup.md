# Task 134 — Assets header and info cleanup

Status: READY
Agent Role: implementation_executor
Executor Class: E2
Target Model: gpt-6.1-terra
Target Effort: medium
Target Route: gpt-6.1-terra / medium
Routing Policy: EXECUTOR_ROUTING_POLICY.json v2 (OptCodex v1.4.0)
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Plan: `docs/agents/plans/2026-11-13-assets-header-cleanup.md`
Plan Steps: P04
Decisions: D-014, D-015, D-016

## 1. Dispatch Compliance

The CCB dispatcher passes `--model gpt-6.1-terra` and `model_reasoning_effort=medium` on your command line, and your prompt states the route. This is the explicit binding. `UNVERIFIABLE` is a valid state; do not stop for it.

Dispatch Route Status: UNVERIFIABLE
Requested Model: gpt-6.1-terra
Requested Effort: medium

## 2. Objective

The Assets page no longer shows the Spot·Margin estimate line or the `Phạm vi dữ liệu` and `Tiền tệ hiển thị` rows. The account selector is a compact pill in the title row, next to reload.

Done when: tests prove W14–W17 from the plan, and V3 passes.

## 3. Preconditions

Predecessors: T132 and T133 = PASS (commits 9016257 and fdbe814). Clean checkout.

## 4. Allowed Scope

Exact write list. Read access covers any non-protected source or test.

- `lib/features/portfolio/presentation/portfolio_screen.dart`
- `lib/core/widgets/scope_bar.dart`
- `test/features/portfolio/portfolio_scope_test.dart`
- `test/features/connections/account_state_test.dart`
- `test/features/connections/scope_bar_test.dart`

## 5. Forbidden Scope

- Do not read or change protected configuration, `backend/` or Git state.
- Do not change other screens, `ScopePicker`, estimate math, or the T132 headline and `Vốn gốc` values.
- No new dependency. No file outside the list.

## 6. Executor Contract

1. `scope_bar.dart`: add `const ScopeBar({super.key, this.compact = false})` and a `final bool compact` field.
   - Keep `Semantics(button: true, onTap: openPicker, label: '${profile.label}, Chính')` and the same `openPicker`.
   - The non-compact branch stays byte-for-byte the same as today.
   - Compact branch: `Material(color: palette.surface, shape: RoundedRectangleBorder(borderRadius: 20, side: palette.border))` → `InkWell(borderRadius 20, onTap: openPicker)` → `ConstrainedBox(minHeight: 40)` → `Padding(horizontal 10, vertical 4)` → `Row(mainAxisSize: MainAxisSize.min)` with:
     - a 22×22 square in `palette.ink`, radius 6, holding `profile.label.substring(0, 1)` in `palette.onStrong`, bold, size 12;
     - `SizedBox(width: 8)`;
     - `Flexible(child: Text(profile.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)))`;
     - `SizedBox(width: 2)`;
     - `Icon(Icons.expand_more, size: 18)`.
2. `portfolio_screen.dart` title row: `Expanded(child: Text('Tài sản' …))`, then `const SizedBox(width: 8)`, then `Flexible(child: const ScopeBar(compact: true))`, then `ManualRefreshButton(…)` unchanged, then the visibility `IconButton` unchanged. If `Expanded` plus `Flexible` squeezes the title badly, use `Flexible(flex: …)` values so the title stays readable. Report what you chose. Remove the `Padding(… child: ScopeBar())` row under the title.
3. `portfolio_screen.dart` body: remove the `Builder` that renders `Ước tính Spot · Margin` and `Tính trên …`, and the `Padding` holding the `Phạm vi dữ liệu` and `Tiền tệ hiển thị` `_infoRow`s. Keep `summary`, `combined`, `baseEquity`, `headlinePnl` and `headlineRatio`. Delete `_infoRow` and any import that becomes unused. Keep `PartialAccountNotice`, the divider and `Tài sản chi tiết`.
4. Tests:
   - Update assertions that expect removed text: `Ước tính Spot · Margin`, `Tính trên N/M tài sản`, `Phạm vi dữ liệu`, `Tiền tệ hiển thị`, and `Binance / Chính` on the Assets page. Each becomes `findsNothing`, or is replaced by the equivalent headline or row assertion that still proves the original intent. For example, the T130 test `headline adds estimates to USD-M …` still checks `(+11.11%)` and the run count, and replaces its summary-line checks with the asset row text `Giá vốn TB 80.00`.
   - Do not delete tests. Do not weaken unrelated assertions.

## 7. External Configuration / Environment Actions

None.

## 8. Tests

- TEST-134-1 (W14), in `portfolio_scope_test.dart`: Binance with an estimate (reuse the T132 scenario 0 setup). `Ước tính Spot · Margin`, `Tính trên`, `Phạm vi dữ liệu` and `Tiền tệ hiển thị` are `findsNothing`. `-$20.50` and `(-41.00%)` are still found.
- TEST-134-2 (W15), in `account_state_test.dart`, around the existing test at line 77:
  - On Assets, `Binance` is found inside `find.byType(ScopeBar)`, and `Binance / Chính` and `USDⓈ-M · Spot · Margin` are not found.
  - The `ScopeBar` and `Key('portfolio-manual-refresh')` share the same `Row` ancestor, with the `ScopeBar` center x less than the refresh center x.
  - The existing tap test (lines 236–238) still opens the picker and shows `OKX / Chính`.
- TEST-134-3 (W16), in `scope_bar_test.dart`: `ScopeBar(compact: true)` with the label `Binance Futures Account 01` at width 320 and `textScaler: TextScaler.linear(2.0)` gives no exception. The compact height is less than 54, and tapping it opens the picker.
- TEST-134-4 (W17): the existing default-height test (height greater than 54) passes unchanged.

## 9. Mandatory Verification

### RED — RED-134
Scenario: TEST-134-1 and TEST-134-2 on the code before the change.
Command: `flutter test --no-pub test/features/portfolio/portfolio_scope_test.dart test/features/connections/account_state_test.dart test/features/connections/scope_bar_test.dart`
Expected: they fail (`Phạm vi dữ liệu` is found, and `compact` is missing or `Binance / Chính` is shown).
Status: PENDING

### GREEN — GREEN-134
Scenario: the same command after the change, then V3 `flutter test --no-pub test/features/portfolio test/features/connections`.
Expected: all pass.
Status: PENDING

Verification ceiling: V3.

### Verification environment

The executor sandbox cannot run `flutter test` or compile. Write the complete code and tests. Report `red` and `green` as `NOT_RUN` with the tests named in RED then GREEN order. Set `buildability` to `BLOCKED` with that reason, and `status` to `COMPLETED`.

Known Flutter pitfalls to avoid:
- `Wrap` has no baseline alignment.
- The app palette (`AppPalette.positive/negative`) is grayscale; profit colors come from `resolvePnlColor` and `PnlColors`.
- In `testWidgets`, do not `await streamController.close()` after the container is disposed.

### Task Buildability Gate

Required: YES
Exact secret-free build command: `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings && flutter build web --no-pub`
Result: PENDING

## 10. Stop Conditions

Return `BLOCKED` if the change needs another screen, the picker, or a file outside the list.

## 11. Coordinator Audit

Verdict: PENDING
