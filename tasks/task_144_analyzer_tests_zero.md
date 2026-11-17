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

## Remediation R01 (current instruction)

Attempt cfc0958c is in the working tree (host: whole repo 2 issues, V4 691/691). Do not redo. Two follow-on issues created by the added `const`:

- AUD-144-01: `test/features/orders/order_cancellation_flow_test.dart:110:13` unnecessary_const — the enclosing expression is now `const`, so the inner `identity: const {` must become `identity: {`.
- AUD-144-02: `test/features/strategy/strategy_dashboard_controller_test.dart:845:7` prefer_const_declarations — `final uncertain = const StrategyApiException(` → `const uncertain = StrategyApiException(`.

No other change. (Pre-existing whole-file `dart format` differences in `scope_bar_test.dart` and `orders_screen_position_layout_test.dart` were present at `e8f273e`; do not reformat those whole files.)

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

## 4a. Exact issue locations (binding)

The executor sandbox cannot run Dart. All 71 sites below come from the host analyzer at HEAD `e8f273e` (`file:line:column`; line numbers are before your edits — work bottom-up within a file or re-locate by content). Fix exactly these; hand-format to `dart format` style. The coordinator runs the analyzer and `dart format` on the host.

- `test/core/navigation/app_page_transition_test.dart:5:8` unused_import : Unused import: 'package:trading_balance_f/core/theme/app_theme.dart'.
- `test/core/navigation/navigation_content_frame_test.dart:18:15` prefer_const_constructors : Use 'const' with the constructor to improve performance.
- `test/core/network/okx_data_client_test.dart:18:50` prefer_const_constructors : Use 'const' with the constructor to improve performance.
- `test/core/network/okx_data_client_test.dart:60:48` prefer_const_constructors : Use 'const' with the constructor to improve performance.
- `test/core/network/okx_data_client_test.dart:107:28` prefer_const_constructors : Use 'const' with the constructor to improve performance.
- `test/core/network/okx_data_client_test.dart:143:21` prefer_const_constructors : Use 'const' with the constructor to improve performance.
- `test/core/network/okx_data_client_test.dart:166:50` prefer_const_constructors : Use 'const' with the constructor to improve performance.
- `test/core/network/okx_data_client_test.dart:212:28` prefer_const_constructors : Use 'const' with the constructor to improve performance.
- `test/core/network/okx_data_client_test.dart:254:48` prefer_const_constructors : Use 'const' with the constructor to improve performance.
- `test/core/network/okx_data_client_test.dart:274:16` prefer_const_constructors : Use 'const' with the constructor to improve performance.
- `test/core/network/okx_data_client_test.dart:291:16` prefer_const_constructors : Use 'const' with the constructor to improve performance.
- `test/core/network/okx_data_client_test.dart:325:20` prefer_const_constructors : Use 'const' with the constructor to improve performance.
- `test/core/network/okx_data_client_test.dart:356:50` prefer_const_constructors : Use 'const' with the constructor to improve performance.
- `test/core/network/okx_data_client_test.dart:389:21` prefer_const_constructors : Use 'const' with the constructor to improve performance.
- `test/core/network/okx_data_client_test.dart:428:23` prefer_const_constructors : Use 'const' with the constructor to improve performance.
- `test/core/network/okx_data_client_test.dart:520:24` prefer_const_constructors : Use 'const' with the constructor to improve performance.
- `test/core/network/okx_data_client_test.dart:532:18` prefer_const_constructors : Use 'const' with the constructor to improve performance.
- `test/core/network/okx_data_client_test.dart:615:50` prefer_const_constructors : Use 'const' with the constructor to improve performance.
- `test/core/network/okx_data_client_test.dart:640:50` prefer_const_constructors : Use 'const' with the constructor to improve performance.
- `test/core/network/okx_data_client_test.dart:657:50` prefer_const_constructors : Use 'const' with the constructor to improve performance.
- `test/core/network/okx_data_client_test.dart:675:9` prefer_const_declarations : Use 'const' for final variables initialized to a constant value.
- `test/core/network/okx_data_client_test.dart:789:57` unused_element_parameter : A value for optional parameter 'headers' isn't ever given.
- `test/core/theme/app_theme_test.dart:23:24` deprecated_member_use : 'red' is deprecated and shouldn't be used. Use (*.r * 255.0).round().clamp(0, 255).
- `test/core/theme/app_theme_test.dart:23:35` deprecated_member_use : 'green' is deprecated and shouldn't be used. Use (*.g * 255.0).round().clamp(0, 255).
- `test/core/theme/app_theme_test.dart:24:24` deprecated_member_use : 'green' is deprecated and shouldn't be used. Use (*.g * 255.0).round().clamp(0, 255).
- `test/core/theme/app_theme_test.dart:24:37` deprecated_member_use : 'blue' is deprecated and shouldn't be used. Use (*.b * 255.0).round().clamp(0, 255).
- `test/core/widgets/app_startup_preview_test.dart:123:7` prefer_const_constructors : Use 'const' with the constructor to improve performance.
- `test/core/widgets/app_startup_preview_test.dart:125:16` prefer_const_constructors : Use 'const' with the constructor to improve performance.
- `test/core/widgets/app_startup_preview_test.dart:127:17` prefer_const_constructors : Use 'const' with the constructor to improve performance.
- `test/core/widgets/app_startup_test.dart:186:7` prefer_const_constructors : Use 'const' with the constructor to improve performance.
- `test/core/widgets/app_startup_test.dart:187:15` prefer_const_constructors : Use 'const' with the constructor to improve performance.
- `test/exchanges/binance/binance_private_client_test.dart:138:9` curly_braces_in_flow_control_structures : Statements in an if should be enclosed in a block.
- `test/exchanges/binance/binance_private_client_test.dart:277:9` curly_braces_in_flow_control_structures : Statements in an if should be enclosed in a block.
- `test/exchanges/binance/binance_private_client_test.dart:279:9` curly_braces_in_flow_control_structures : Statements in an if should be enclosed in a block.
- `test/exchanges/binance/binance_reader_test.dart:80:7` curly_braces_in_flow_control_structures : Statements in an if should be enclosed in a block.
- `test/exchanges/binance/binance_reader_test.dart:82:7` curly_braces_in_flow_control_structures : Statements in an if should be enclosed in a block.
- `test/exchanges/binance/binance_reader_test.dart:87:7` curly_braces_in_flow_control_structures : Statements in an if should be enclosed in a block.
- `test/exchanges/binance/binance_reader_test.dart:89:7` curly_braces_in_flow_control_structures : Statements in an if should be enclosed in a block.
- `test/exchanges/binance/binance_reader_test.dart:95:7` curly_braces_in_flow_control_structures : Statements in an if should be enclosed in a block.
- `test/exchanges/binance/binance_reader_test.dart:103:7` curly_braces_in_flow_control_structures : Statements in an if should be enclosed in a block.
- `test/exchanges/binance/binance_reader_test.dart:201:9` curly_braces_in_flow_control_structures : Statements in an if should be enclosed in a block.
- `test/exchanges/binance/binance_reader_test.dart:203:9` curly_braces_in_flow_control_structures : Statements in an if should be enclosed in a block.
- `test/exchanges/binance/binance_reader_test.dart:285:9` curly_braces_in_flow_control_structures : Statements in an if should be enclosed in a block.
- `test/exchanges/binance/binance_reader_test.dart:287:9` curly_braces_in_flow_control_structures : Statements in an if should be enclosed in a block.
- `test/exchanges/binance/binance_trade_history_test.dart:313:5` prefer_const_declarations : Use 'const' for final variables initialized to a constant value.
- `test/features/connections/scope_bar_test.dart:106:16` prefer_const_constructors : Use 'const' with the constructor to improve performance.
- `test/features/connections/scope_bar_test.dart:107:17` prefer_const_constructors : Use 'const' with the constructor to improve performance.
- `test/features/fractal_tracker/fractal_screen_price_formatting_test.dart:4:8` unnecessary_import : The import of 'dart:typed_data' is unnecessary because all of the used elements are also provided by the import of 'package:flutter/services.dart'.
- `test/features/orders/order_cancellation_flow_test.dart:101:28` prefer_const_constructors : Use 'const' with the constructor to improve performance.
- `test/features/orders/order_cancellation_flow_test.dart:120:26` unused_element_parameter : A value for optional parameter 'configured' isn't ever given.
- `test/features/orders/order_filter_controls_test.dart:38:21` deprecated_member_use : 'hasFlag' is deprecated and shouldn't be used. Use flagsCollection instead. This feature was deprecated after v3.32.0-0.0.pre.
- `test/features/orders/order_filter_controls_test.dart:39:21` deprecated_member_use : 'hasFlag' is deprecated and shouldn't be used. Use flagsCollection instead. This feature was deprecated after v3.32.0-0.0.pre.
- `test/features/orders/orders_binance_view_test.dart:689:9` curly_braces_in_flow_control_structures : Statements in an if should be enclosed in a block.
- `test/features/orders/orders_binance_view_test.dart:691:9` curly_braces_in_flow_control_structures : Statements in an if should be enclosed in a block.
- `test/features/orders/orders_binance_view_test.dart:693:9` curly_braces_in_flow_control_structures : Statements in an if should be enclosed in a block.
- `test/features/orders/orders_binance_view_test.dart:761:16` prefer_const_constructors : Use 'const' with the constructor to improve performance.
- `test/features/orders/orders_binance_view_test.dart:762:17` prefer_const_constructors : Use 'const' with the constructor to improve performance.
- `test/features/orders/position_actions_test.dart:66:10` unused_element_parameter : A value for optional parameter 'configured' isn't ever given.
- `test/features/orders/presentation/orders_screen_history_layout_test.dart:11:8` unused_import : Unused import: 'package:trading_balance_f/features/portfolio/presentation/portfolio_screen.dart'.
- `test/features/orders/presentation/orders_screen_position_layout_test.dart:579:11` prefer_const_declarations : Use 'const' for final variables initialized to a constant value.
- `test/features/portfolio/monochrome_portfolio_preview_test.dart:2:8` unnecessary_import : The import of 'dart:typed_data' is unnecessary because all of the used elements are also provided by the import of 'package:flutter/services.dart'.
- `test/features/portfolio/monochrome_portfolio_preview_test.dart:92:12` prefer_const_constructors : Use 'const' with the constructor to improve performance.
- `test/features/settings/settings_trade_access_page_test.dart:221:5` prefer_const_declarations : Use 'const' for final variables initialized to a constant value.
- `test/features/strategy/strategy_dashboard_controller_test.dart:845:25` prefer_const_constructors : Use 'const' with the constructor to improve performance.
- `test/features/strategy/strategy_market_repository_test.dart:16:11` prefer_function_declarations_over_variables : Use a function declaration rather than a variable assignment to bind a function to a name.
- `test/features/strategy/strategy_retry_dialog_test.dart:14:8` unused_import : Unused import: 'package:trading_balance_f/features/strategy/presentation/providers/strategy_dashboard_provider.dart'.
- `test/features/strategy/strategy_retry_dialog_test.dart:400:14` prefer_inlined_adds : The addition of a list item could be inlined.
- `test/features/strategy/strategy_retry_dialog_test.dart:401:13` prefer_const_constructors : Use 'const' with the constructor to improve performance.
- `test/features/strategy/strategy_screen_test.dart:3:8` unnecessary_import : The import of 'dart:typed_data' is unnecessary because all of the used elements are also provided by the import of 'package:flutter/services.dart'.
- `test/features/strategy/strategy_screen_test.dart:16:8` unused_import : Unused import: 'package:trading_balance_f/core/widgets/responsive_form_content.dart'.
- `test/features/strategy/strategy_screen_test.dart:212:38` prefer_const_constructors : Use 'const' with the constructor to improve performance.

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
