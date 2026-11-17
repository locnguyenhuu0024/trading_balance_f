# Spec: Zero analyzer issues

Status: APPROVED
Approval: "Duyệt, commit, làm" (user, chat, 2026-11-17, on this revision; includes commit on PASS)
Date: 2026-11-17
Tier: M
Domain: mobile (Flutter)
Branch: `codex/multi-platform-view-only`
Request: "sau khi xong hết task thì lên plan fix các issue đó đi, kì vọng là không còn issues" (user, 2026-11-17)

## 1. Observations (host, HEAD `a78ef9c`, Flutter 3.44.2)

- OBS-201: `flutter analyze --no-pub` reports 155 issues: 143 info, 12 warning, 0 error, in 25 `lib/` files and 24 `test/` files.
- OBS-202: By rule: `curly_braces_in_flow_control_structures` 64, `prefer_const_constructors` 40, `deprecated_member_use` 15, `unnecessary_import` 9, `unused_import` 4, `prefer_const_declarations` 4, `annotate_overrides` 4, `unused_element_parameter` 3, `prefer_function_declarations_over_variables` 3, `unnecessary_non_null_assertion` 2, and 1 each of `use_build_context_synchronously`, `unused_catch_clause`, `unnecessary_to_list_in_spreads`, `unnecessary_brace_in_string_interps`, `prefer_inlined_adds`, `invalid_use_of_visible_for_testing_member`, `invalid_use_of_protected_member`.
- OBS-203: Behavior-sensitive sites:
  - `lib/exchanges/binance/binance_adapter.dart:90` reads `controller.state` of `BinanceCostController` (a `StateNotifier`, `binance_trade_history.dart:84`) from outside the class (2 warnings).
  - `order_cancellation_flow_provider.dart:270` uses `navigator.context` after `await` (guarded by `_canContinue`, but not in a form the analyzer recognizes); 2 `!` on non-nullable values.
  - `strategy_wizard_dialog.dart`: 3 `DropdownButtonFormField.value` (deprecated → `initialValue`, L1112, L1132, L1364) and 1 `RadioListTile.groupValue/onChanged` (deprecated → `RadioGroup` ancestor, L1698–1699). `strategy_wizard_dialog_test.dart` L221 and L679 read `RadioListTile.groupValue`.
  - `fractal_screen.dart` L766, L805 `withOpacity`.
- OBS-204: Test-only deprecations: `app_theme_test.dart` L23–24 `Color.red/green/blue`; `order_filter_controls_test.dart` L38–39 `SemanticsData.hasFlag`.
- OBS-205: `analysis_options.yaml` includes `package:flutter_lints/flutter.yaml` with no extra rules. It is toolchain configuration and is not changed by this plan.

## 2. Requirements

- REQ-201: `flutter analyze --no-pub` prints `No issues found!` (0 info, 0 warning, 0 error).
- REQ-202: Fixed by changing code, not by suppression: no new `// ignore:` / `// ignore_for_file:` comments, no `analysis_options.yaml` change, no excluded paths.
- REQ-203: No behavior, text, key, layout or provider change. Deprecated APIs are replaced by their documented successors with the same behavior.
- REQ-204: `BinanceCostController` exposes its current value through a public getter; `binanceCostStateProvider` uses it (same first emission, then the stream).
- REQ-205: The Strategy wizard entry-level radio keeps the same selection, enabled/disabled state and tap behavior after the `RadioGroup` migration; the three dropdowns keep showing the selected value after the user changes it and after parent rebuilds.
- REQ-206: V4 `flutter test --no-pub` stays fully green and `flutter build web --no-pub` builds.

## 3. Acceptance Criteria

- AC-201: REQ-201 on the final tree.
- AC-202: `git diff` of the plan adds no `ignore` comment and does not touch `analysis_options.yaml`.
- AC-203: V4 all pass, web build OK, `dart format --set-exit-if-changed` clean on every touched file.
- AC-204: Strategy wizard tests that select an interval/direction/allocation and the entry radio pass unchanged in intent (only the `groupValue` accessors change to read the `RadioGroup`).

## 4. Edge cases

- EDGE-201: `DropdownButtonFormField.initialValue` must still reflect state changes made by the dialog's own `setState`. If a test shows the field no longer updates, give the field a `ValueKey` of the current value (re-creates the field) rather than keeping the deprecated `value`.
- EDGE-202: A disabled entry radio (`canBeEntry == false`) must stay disabled: use `RadioListTile.enabled: canBeEntry` inside the `RadioGroup`.
- EDGE-203: `use_build_context_synchronously`: add an explicit `if (!navigator.context.mounted) return;` (or equivalent the analyzer accepts) right before the use; `_canContinue` stays.

## 5. Decisions

- D-026: zero means zero, by fixing code (REQ-202). Rationale: suppressions or rule changes would hide the same debt.
- D-027: after this plan, every task's buildability gate expects `No issues found!` (baseline 0) instead of "not above N".
