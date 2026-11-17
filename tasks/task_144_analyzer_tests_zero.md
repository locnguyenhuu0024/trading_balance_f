# Task 144 — Analyzer cleanup in tests and final zero gate

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
Plan Steps: P03
Requirements: REQ-201, REQ-202, REQ-206
Decisions: D-026, D-027

## 1. Dispatch Compliance

The CCB dispatcher passes `--model gpt-6.1-terra` and `model_reasoning_effort=medium` on your command line, and your prompt states the route. This is the explicit binding. `UNVERIFIABLE` is a valid state; do not stop for it.

Dispatch Route Status: pending
Requested Model: gpt-6.1-terra
Requested Effort: medium

## 2. Objective

Remove all 71 analyzer issues in the 23 test files below without weakening any test, so the whole repository reports `No issues found!`.

Done when: `flutter analyze --no-pub` (whole repo) prints `No issues found!`, V4 passes, web build passes.

## 3. Preconditions

Predecessors: T143 = PASS. Clean checkout.

## 4. Allowed Scope (host analyzer issues per file, 2026-11-17)

| File | Issues |
|---|---|
| `test/core/navigation/app_page_transition_test.dart` | unused_import ×1 |
| `test/core/navigation/navigation_content_frame_test.dart` | prefer_const_constructors ×1 |
| `test/core/network/okx_data_client_test.dart` | prefer_const_constructors ×18, prefer_const_declarations ×1, unused_element_parameter ×1 (L789) |
| `test/core/theme/app_theme_test.dart` | deprecated `Color.red/green/blue` ×4 (L23–24) |
| `test/core/widgets/app_startup_preview_test.dart` | prefer_const_constructors ×3 |
| `test/core/widgets/app_startup_test.dart` | prefer_const_constructors ×2 |
| `test/exchanges/binance/binance_private_client_test.dart` | curly_braces ×3 |
| `test/exchanges/binance/binance_reader_test.dart` | curly_braces ×10 |
| `test/exchanges/binance/binance_trade_history_test.dart` | prefer_const_declarations ×1 |
| `test/features/connections/scope_bar_test.dart` | prefer_const_constructors ×2 |
| `test/features/fractal_tracker/fractal_screen_price_formatting_test.dart` | unnecessary_import ×1 |
| `test/features/orders/order_cancellation_flow_test.dart` | prefer_const_constructors ×1, unused_element_parameter ×1 (L120) |
| `test/features/orders/order_filter_controls_test.dart` | deprecated `SemanticsData.hasFlag` ×2 (L38–39) |
| `test/features/orders/orders_binance_view_test.dart` | curly_braces ×3, prefer_const_constructors ×2 |
| `test/features/orders/position_actions_test.dart` | unused_element_parameter ×1 (L66) |
| `test/features/orders/presentation/orders_screen_history_layout_test.dart` | unused_import ×1 |
| `test/features/orders/presentation/orders_screen_position_layout_test.dart` | prefer_const_declarations ×1 |
| `test/features/portfolio/monochrome_portfolio_preview_test.dart` | unnecessary_import ×1, prefer_const_constructors ×1 |
| `test/features/settings/settings_trade_access_page_test.dart` | prefer_const_declarations ×1 |
| `test/features/strategy/strategy_dashboard_controller_test.dart` | prefer_const_constructors ×1 |
| `test/features/strategy/strategy_market_repository_test.dart` | prefer_function_declarations_over_variables ×1 |
| `test/features/strategy/strategy_retry_dialog_test.dart` | unused_import ×1, prefer_inlined_adds ×1, prefer_const_constructors ×1 |
| `test/features/strategy/strategy_screen_test.dart` | unnecessary_import ×1, unused_import ×1, prefer_const_constructors ×1 |

## 5. Forbidden Scope

- `lib/`, every file not listed, `analysis_options.yaml`, protected configuration, `backend/`, Git state, new dependencies.
- No `// ignore:` comments. No deleted or weakened expectation; no deleted test.

## 6. Executor Contract

1. Mechanical rules as in T142 (braces, `const`, `final`→`const` declarations, imports, local function declaration, inline `add` into the list literal).
2. `unused_element_parameter`: remove the never-passed optional parameter from the private helper and use its default value inside the body.
3. `app_theme_test.dart` L23–24: compare the 8-bit channels with the non-deprecated API, e.g. `int c8(double v) => (v * 255.0).round().clamp(0, 255);` then `expect(c8(color.r), c8(color.g)); expect(c8(color.g), c8(color.b));` — same assertion (grayscale).
4. `order_filter_controls_test.dart` L38–39: replace the two `hasFlag` checks with one `expect(tester.getSemantics(find.bySemanticsLabel('Vị thế')), isSemantics(isSelected: true, isButton: true));` (or `flagsCollection` with the same meaning). Same assertion strength.
5. `dart format` every touched file.

## 7. External Configuration / Environment Actions

None.

## 8. Tests

The edited tests themselves; V4.

## 9. Mandatory Verification

### RED — RED-144
Command: `flutter analyze --no-pub` (whole repo) before the change.
Expected: exactly the 71 issues of §4 (T142 and T143 already removed the rest).

### GREEN — GREEN-144
Same command: `No issues found!`. V4 `flutter test --no-pub`: all pass, same test count as before. `dart format --set-exit-if-changed` clean. `git diff a78ef9c..HEAD -- . ':!docs' ':!tasks' | grep -E '^\+.*ignore(_for_file)?:'` → no output; `analysis_options.yaml` unchanged.
Verification ceiling: V4.

### Task Buildability Gate
Required: YES
Command: `flutter analyze --no-pub && flutter build web --no-pub`
Expected: `No issues found!` and web build OK (strict: infos and warnings are fatal from now on, D-027).

### Verification environment
The executor sandbox cannot run Flutter. Write the complete change. Report `red`/`green` as `NOT_RUN` (RED then GREEN order named), `buildability` `BLOCKED` with that reason, `status` `COMPLETED`. Return a valid structured report.

## 10. Stop Conditions

`BLOCKED` if an issue can only be removed by weakening or deleting a test, or by touching `lib/`.

## 11. Execution Ledger
(coordinator fills)

## 12. Coordinator Audit
(coordinator fills)
