# Task 142 — Mechanical analyzer cleanup in `lib/`

Status: APPROVED
Agent Role: implementation_executor
Executor Class: E2
Target Model: gpt-6.1-terra
Target Effort: medium
Target Route: gpt-6.1-terra / medium
Routing Policy: EXECUTOR_ROUTING_POLICY.json v2 (OptCodex v1.4.0)
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Plan: `docs/agents/plans/2026-11-17-analyzer-zero.md`
Spec: `docs/agents/specs/2026-11-17-analyzer-zero-design.md`
Plan Steps: P01
Requirements: REQ-201..REQ-203
Decisions: D-026

## 1. Dispatch Compliance

The CCB dispatcher passes `--model gpt-6.1-terra` and `model_reasoning_effort=medium` on your command line, and your prompt states the route. This is the explicit binding. `UNVERIFIABLE` is a valid state; do not stop for it.

Dispatch Route Status: pending
Requested Model: gpt-6.1-terra
Requested Effort: medium

## 2. Objective

Remove all 60 analyzer issues in the 21 files below without changing behavior.

Done when: `flutter analyze --no-pub <these 21 files>` prints `No issues found!`, V4 passes, buildability passes.

## 3. Preconditions

Predecessors: motion polish COMPLETE (`a78ef9c`). Clean checkout.

## 4. Allowed Scope (host analyzer issues per file, 2026-11-17)

| File | Issues |
|---|---|
| `lib/core/exchange/exchange_registry.dart` | prefer_const_constructors ×2 |
| `lib/core/network/okx_data_client.dart` | unnecessary_import ×1 |
| `lib/core/network/okx_read_scope.dart` | curly_braces ×2 |
| `lib/core/theme/app_theme.dart` | unnecessary_import ×1 |
| `lib/core/widgets/responsive_form_content.dart` | prefer_const_constructors ×2 |
| `lib/exchanges/binance/binance_estimated_pnl.dart` | curly_braces ×4 |
| `lib/exchanges/binance/binance_market.dart` | curly_braces ×3, prefer_const_constructors ×1 |
| `lib/exchanges/binance/binance_private_client.dart` | curly_braces ×4 |
| `lib/exchanges/binance/binance_reader.dart` | curly_braces ×9 |
| `lib/exchanges/okx/okx_adapter.dart` | curly_braces ×3 |
| `lib/features/connections/binance_connection_form.dart` | unnecessary_import ×1, curly_braces ×1 |
| `lib/features/connections/scope_picker.dart` | curly_braces ×1 |
| `lib/features/fractal_tracker/presentation/fractal_screen.dart` | curly_braces ×3, deprecated `withOpacity` ×2 (L766, L805) |
| `lib/features/market/presentation/market_screen.dart` | unnecessary_import `dart:ui` ×1 |
| `lib/features/orders/presentation/orders_screen.dart` | curly_braces ×3, unnecessary_to_list_in_spreads ×1 |
| `lib/features/portfolio/presentation/portfolio_screen.dart` | curly_braces ×3 |
| `lib/features/strategy/presentation/providers/strategy_dashboard_provider.dart` | unused_catch_clause ×1 (L349) |
| `lib/features/strategy/presentation/strategy_screen.dart` | prefer_function_declarations_over_variables ×2 |
| `lib/features/strategy/presentation/strategy_settings_dialog.dart` | prefer_const_constructors ×1 |
| `lib/features/support_resistance/data/market_repository.dart` | annotate_overrides ×4 |
| `lib/main.dart` | unnecessary_import ×1, curly_braces ×3 |

## 5. Forbidden Scope

- Every file not listed (in particular `binance_adapter.dart`, `binance_trade_history.dart`, `order_cancellation_flow_provider.dart`, `strategy_wizard_dialog.dart` — they belong to T143), `analysis_options.yaml`, protected configuration (`pubspec.yaml`, lockfiles, `android/`, `ios/`, `web/`, `macos/`), `backend/`, Git state.
- No `// ignore:` / `// ignore_for_file:` comments. No behavior, text, key, layout or provider change. No new dependency.

## 6. Executor Contract

1. `curly_braces_in_flow_control_structures`: wrap the single statement of the flagged `if`/`else`/`for` in `{ }`. Do not change conditions.
2. `prefer_const_constructors`: add `const` where the analyzer flags it (only there).
3. `unnecessary_import`: delete the import whose elements are provided by another import (e.g. `dart:ui` when `package:flutter/material.dart` is imported). Keep anything still needed.
4. `unnecessary_to_list_in_spreads`: drop the `.toList()` inside the spread.
5. `annotate_overrides`: add `@override` to the four flagged members.
6. `prefer_function_declarations_over_variables`: turn `final x = (…) { … };` into a local function `ReturnType x(…) { … }` with the same parameters and body.
7. `unused_catch_clause`: `on Object catch (error) {` → `on Object {` (body unchanged, `rethrow` still works).
8. `withOpacity(a)` → `withValues(alpha: a)`.
9. `dart format` every touched file (80 columns).

## 7. External Configuration / Environment Actions

None.

## 8. Tests

No new test. Existing V4 protects behavior.

## 9. Mandatory Verification

### RED — RED-142
Command: `flutter analyze --no-pub` on the 21 files listed in §4 (pass the paths), before the change.
Expected: 60 issues.

### GREEN — GREEN-142
Same command after the change: `No issues found!`. Then V4 `flutter test --no-pub`: all pass. `dart format --set-exit-if-changed` on the 21 files: 0 changed.
Verification ceiling: V4.

### Task Buildability Gate
Required: YES
Command: `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings && flutter build web --no-pub`
Expected: 0 errors; total ≤ 95 issues.

### Verification environment
The executor sandbox cannot run Flutter. Write the complete change. Report `red`/`green` as `NOT_RUN` (RED then GREEN order named), `buildability` `BLOCKED` with that reason, `status` `COMPLETED`. Return a valid structured report.

## 10. Stop Conditions

`BLOCKED` if an issue can only be fixed in a file outside §4, or only by an `ignore` comment or a behavior change.

## 11. Execution Ledger
(coordinator fills)

## 12. Coordinator Audit
(coordinator fills)
