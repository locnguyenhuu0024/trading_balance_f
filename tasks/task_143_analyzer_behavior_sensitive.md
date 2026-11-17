# Task 143 — Behavior-sensitive analyzer fixes (cost controller, cancellation flow, strategy wizard)

Status: APPROVED
Agent Role: implementation_executor
Executor Class: E3
Target Model: gpt-6.1-terra
Target Effort: high
Target Route: gpt-6.1-terra / high
Routing Policy: EXECUTOR_ROUTING_POLICY.json v2 (OptCodex v1.4.0)
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Plan: `docs/agents/plans/2026-11-17-analyzer-zero.md`
Spec: `docs/agents/specs/2026-11-17-analyzer-zero-design.md`
Plan Steps: P02
Requirements: REQ-201..REQ-205
Decisions: D-026

## 1. Dispatch Compliance

The CCB dispatcher passes `--model gpt-6.1-terra` and `model_reasoning_effort=high` on your command line, and your prompt states the route. This is the explicit binding. `UNVERIFIABLE` is a valid state; do not stop for it.

Dispatch Route Status: pending
Requested Model: gpt-6.1-terra
Requested Effort: high

## 2. Objective

Remove all 24 analyzer issues in the five files below, migrating deprecated APIs to their successors with identical behavior.

Done when: `flutter analyze --no-pub <these 5 files>` prints `No issues found!`, V4 passes, buildability passes.

## 3. Preconditions

Predecessors: T142 = PASS. Clean checkout.

## 4. Allowed Scope (host analyzer issues per file, 2026-11-17)

| File | Issues |
|---|---|
| `lib/exchanges/binance/binance_adapter.dart` | invalid_use_of_protected_member + invalid_use_of_visible_for_testing_member (L90 `controller.state`) |
| `lib/exchanges/binance/binance_trade_history.dart` | curly_braces ×6 |
| `lib/features/orders/presentation/providers/order_cancellation_flow_provider.dart` | unnecessary_non_null_assertion ×2 (L242, L351), use_build_context_synchronously ×1 (L270), curly_braces ×1 |
| `lib/features/strategy/presentation/strategy_wizard_dialog.dart` | deprecated `DropdownButtonFormField.value` ×3 (L1112, L1132, L1364), deprecated `RadioListTile.groupValue` + `onChanged` (L1698–1699), curly_braces ×2, prefer_const_constructors ×1, unnecessary_brace_in_string_interps ×1 |
| `test/features/strategy/strategy_wizard_dialog_test.dart` | unnecessary_import ×1, deprecated `RadioListTile.groupValue` reads ×2 (L221, L679) |

## 5. Forbidden Scope

- Every file not listed, `analysis_options.yaml`, protected configuration, `backend/`, Git state, new dependencies.
- No `// ignore:` comments. No change to texts, keys, providers, trade/cancel logic, emitted values or selection behavior.

## 6. Executor Contract

1. `BinanceCostController` (`binance_trade_history.dart`): add `BinanceCostView get current => state;` with a one-line doc comment. In `binance_adapter.dart` `binanceCostStateProvider`, replace `yield controller.state;` with `yield controller.current;`. Nothing else in the provider changes. Fix the 6 brace issues in `binance_trade_history.dart`.
2. `order_cancellation_flow_provider.dart`:
   - L242 and L351: `_sessionMatches(initialSession!)` → `_sessionMatches(initialSession)` (it is already non-nullable there).
   - L270: immediately before `showTradeActionConfirmation(navigator.context, …)` add `if (!navigator.context.mounted) return;` (keep `_canContinue` as is). If the analyzer still flags it, capture `final context = navigator.context;` after that check and pass `context`. Do not change the order of other checks.
   - Fix the brace issue.
3. `strategy_wizard_dialog.dart`:
   - The three `DropdownButtonFormField` `value: X` → `initialValue: X`. The dialog changes `_interval`, `_direction`, `_allocation` with `setState` and other code paths may change them programmatically: if, after the change, the field would no longer show the new value on rebuild, also give that field `key: ValueKey(X)` combined with its existing key (e.g. keep `Key('strategy-interval-select')` on a wrapping `KeyedSubtree` and put `ValueKey(_interval)` on the field) so existing `find.byKey` lookups still work. State in your report which you did and why.
   - Entry radio (L1696–1703): wrap in `RadioGroup<String>(groupValue: entryLevelId, onChanged: (_) => onEntry(), child: RadioListTile<String>(value: level.id, enabled: canBeEntry, title: …, dense: true, visualDensity: VisualDensity.compact))`. Disabled state, title, density and tap → `onEntry()` stay the same.
   - Fix braces, `const`, and string-interpolation braces.
4. `strategy_wizard_dialog_test.dart`: remove the unnecessary import. Replace the two `RadioListTile.groupValue` reads with the `groupValue` of the enclosing `RadioGroup<String>`: `tester.widget<RadioGroup<String>>(find.ancestor(of: <radio finder>, matching: find.byType(RadioGroup<String>)).first).groupValue`. Expectations stay the same.
5. `dart format` every touched file.

## 7. External Configuration / Environment Actions

None.

## 8. Tests

Existing tests are the behavior contract: `test/features/strategy/strategy_wizard_dialog_test.dart` (dropdown + entry radio), `test/features/orders/order_cancellation_flow_test.dart`, `test/features/orders/orders_binance_view_test.dart` (cost state). Only the two accessor updates in §6.4 are allowed in tests.

## 9. Mandatory Verification

### RED — RED-143
Command: `flutter analyze --no-pub` on the 5 files in §4, before the change.
Expected: 24 issues.

### GREEN — GREEN-143
Same command: `No issues found!`. Then `flutter test --no-pub test/features/strategy test/features/orders` and V4 `flutter test --no-pub`: all pass. `dart format --set-exit-if-changed` clean.
Verification ceiling: V4.

### Task Buildability Gate
Required: YES
Command: `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings && flutter build web --no-pub`
Expected: 0 errors; total ≤ 71 issues.

### Verification environment
The executor sandbox cannot run Flutter. Write the complete change. Report `red`/`green` as `NOT_RUN` (RED then GREEN order named), `buildability` `BLOCKED` with that reason, `status` `COMPLETED`. Return a valid structured report.

## 10. Stop Conditions

`BLOCKED` if `RadioGroup`/`initialValue` is unavailable in this Flutter SDK, if a behavior test would have to change beyond §6.4, or if a file outside §4 is needed.

## 11. Execution Ledger
(coordinator fills)

## 12. Coordinator Audit
(coordinator fills)
