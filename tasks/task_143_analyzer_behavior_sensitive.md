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

## Remediation R01 (current instruction)

Attempt effb49d4 is in the working tree (host: 23/24 issues gone, V4 689 pass / 2 fail). Do not redo. Write only files in §4.

- AUD-143-01, keys moved (coordinator's §6.3 fallback was wrong). `test/features/strategy/strategy_screen_test.dart:782` (outside scope, unchanged) does `tester.widget<DropdownButtonFormField<dynamic>>(find.byKey(const Key('strategy-direction-select')))`; the key now sits on a `KeyedSubtree`, so 2 tests fail with `Bad state: No element`. `DropdownButtonFormField` already follows `initialValue` changes in `didUpdateWidget`, so re-creating the field is unnecessary. Required in `strategy_wizard_dialog.dart`: remove both `KeyedSubtree` wrappers (~L1111, ~L1133) and put `Key('strategy-interval-select')` / `Key('strategy-direction-select')` back directly on their `DropdownButtonFormField` exactly as before; remove `key: ValueKey(_interval)`, `key: ValueKey(_direction)` and `key: ValueKey(_allocation)` (~L1371; that field had no key before). Keep `initialValue:`. Leave the existing `ValueKey('strategy-level-${level.id}')` (~L1294) untouched.
- AUD-143-02, analyzer. `order_cancellation_flow_provider.dart:271` still reports `use_build_context_synchronously` ("guarded by an unrelated 'mounted' check"): `navigator.context.mounted` is not accepted. Required: replace the added line with `final dialogContext = navigator.context; if (!dialogContext.mounted) return;` and pass `dialogContext` (not `navigator.context`) to `showTradeActionConfirmation`. Nothing else changes.
- AUD-143-03, formatting. `dart format` still changes `test/features/strategy/strategy_wizard_dialog_test.dart`. Required: format it (80 columns). Keep all touched files formatted.

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

## 4a. Exact issue locations (binding)

The executor sandbox cannot run Dart. All 24 sites below come from the host analyzer at HEAD `e8f273e` (`file:line:column`; line numbers are before your edits — work bottom-up within a file or re-locate by content). Fix exactly these; hand-format to `dart format` style. The coordinator runs the analyzer and `dart format` on the host.

- `lib/exchanges/binance/binance_adapter.dart:90:20` invalid_use_of_visible_for_testing_member : The member 'state' can only be used within 'package:state_notifier/state_notifier.dart' or a test
- `lib/exchanges/binance/binance_adapter.dart:90:20` invalid_use_of_protected_member : The member 'state' can only be used within instance members of subclasses of 'StateNotifier'
- `lib/exchanges/binance/binance_trade_history.dart:110:7` curly_braces_in_flow_control_structures : Statements in an if should be enclosed in a block.
- `lib/exchanges/binance/binance_trade_history.dart:130:11` curly_braces_in_flow_control_structures : Statements in an if should be enclosed in a block.
- `lib/exchanges/binance/binance_trade_history.dart:189:17` curly_braces_in_flow_control_structures : Statements in an if should be enclosed in a block.
- `lib/exchanges/binance/binance_trade_history.dart:191:17` curly_braces_in_flow_control_structures : Statements in an if should be enclosed in a block.
- `lib/exchanges/binance/binance_trade_history.dart:221:13` curly_braces_in_flow_control_structures : Statements in an if should be enclosed in a block.
- `lib/exchanges/binance/binance_trade_history.dart:229:13` curly_braces_in_flow_control_structures : Statements in an if should be enclosed in a block.
- `lib/features/orders/presentation/providers/order_cancellation_flow_provider.dart:242:67` unnecessary_non_null_assertion : The '!' will have no effect because the receiver can't be null.
- `lib/features/orders/presentation/providers/order_cancellation_flow_provider.dart:270:9` use_build_context_synchronously : Don't use 'BuildContext's across async gaps.
- `lib/features/orders/presentation/providers/order_cancellation_flow_provider.dart:351:65` unnecessary_non_null_assertion : The '!' will have no effect because the receiver can't be null.
- `lib/features/orders/presentation/providers/order_cancellation_flow_provider.dart:592:9` curly_braces_in_flow_control_structures : Statements in an if should be enclosed in a block.
- `lib/features/strategy/presentation/strategy_wizard_dialog.dart:411:11` curly_braces_in_flow_control_structures : Statements in an if should be enclosed in a block.
- `lib/features/strategy/presentation/strategy_wizard_dialog.dart:1112:11` deprecated_member_use : 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre.
- `lib/features/strategy/presentation/strategy_wizard_dialog.dart:1132:11` deprecated_member_use : 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre.
- `lib/features/strategy/presentation/strategy_wizard_dialog.dart:1310:9` prefer_const_constructors : Use 'const' with the constructor to improve performance.
- `lib/features/strategy/presentation/strategy_wizard_dialog.dart:1357:104` unnecessary_brace_in_string_interps : Unnecessary braces in a string interpolation.
- `lib/features/strategy/presentation/strategy_wizard_dialog.dart:1364:11` deprecated_member_use : 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre.
- `lib/features/strategy/presentation/strategy_wizard_dialog.dart:1389:21` curly_braces_in_flow_control_structures : Statements in an if should be enclosed in a block.
- `lib/features/strategy/presentation/strategy_wizard_dialog.dart:1698:15` deprecated_member_use : 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre.
- `lib/features/strategy/presentation/strategy_wizard_dialog.dart:1699:15` deprecated_member_use : 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre.
- `test/features/strategy/strategy_wizard_dialog_test.dart:2:8` unnecessary_import : The import of 'dart:typed_data' is unnecessary because all of the used elements are also provided by the import of 'package:flutter/services.dart'.
- `test/features/strategy/strategy_wizard_dialog_test.dart:221:33` deprecated_member_use : 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre.
- `test/features/strategy/strategy_wizard_dialog_test.dart:679:63` deprecated_member_use : 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre.

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

- effb49d4dd8b4afeae68bff044763bbd: REWORK — AUD-143-01 dropdown keys moved onto `KeyedSubtree` (coordinator fallback in §6.3 was wrong; 2 strategy_screen tests failed), AUD-143-02 `use_build_context_synchronously` still reported, AUD-143-03 format; WIP `aa5cb15`.
- 1e82dad2aeb84f599dd11b1e89e8b97a (R01): PASS. All attempts in §4 scope; route gpt-6.1-terra/high, effective UNVERIFIABLE.

## 12. Coordinator Audit

Verdict: PASS (2026-11-17).

- RED-143 (host, `e8f273e`): 24 issues in the 5 files.
- GREEN-143: `flutter analyze --no-pub <5 files>` → `No issues found!`. V4: 691/691 pass (incl. strategy wizard dropdown/radio tests, cancellation flow, Binance cost view).
- Buildability: whole repo 71 issues (target ≤ 71), 0 errors; web build OK. `dart format` clean on the 5 files. No `// ignore`; `analysis_options.yaml` untouched.
- Review: `BinanceCostController.current` getter, provider yields it first then the stream (unchanged order); cancellation flow keeps `_canContinue`, adds a local `dialogContext.mounted` guard before the dialog; dropdowns use `initialValue` with original keys (no forced re-creation); entry radio in `RadioGroup` with `enabled: canBeEntry` (disabled state preserved), tap still calls `onEntry()`; test accessors read `RadioGroup.groupValue` with unchanged expectations.
