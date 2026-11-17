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

## Remediation R02 (current instruction)

R01 (attempt 97141d8c) is in the working tree; host analyze on the 21 files: only one defect left, plus formatting. Do not redo.

- AUD-142-01, syntax error. `lib/features/strategy/presentation/strategy_screen.dart:214` `Future<void?> openDetails() => showDialog<void>(` — `void?` is not valid Dart (8 parse errors, 1 undefined `openDetails`). Required: `Future<void> openDetails() => showDialog<void>(` . Nothing else in that function changes.
- AUD-142-02, formatting. `dart format` still changes `lib/features/orders/presentation/orders_screen.dart`, `lib/features/strategy/presentation/strategy_settings_dialog.dart`, `lib/main.dart` (`strategy_screen.dart` could not be parsed yet). Required: format these four files to `dart format` style (80 columns). No logic change.

## Remediation R01 (done)

Attempt af43dec9 changed nothing because the sandbox cannot run Dart to locate issues. You do not need any tool: every issue is listed below with its exact `file:line:column` from the host analyzer (HEAD `e8f273e`). Fix exactly these 60 sites by reading the source, following §6. Hand-format to `dart format` style (80 columns, trailing commas as in the surrounding code); the coordinator runs `dart format` and the analyzer on the host. Line numbers refer to the file before your edits — work bottom-up within a file or re-locate by content.

- `lib/core/exchange/exchange_registry.dart:15:5` prefer_const_constructors : Use 'const' with the constructor to improve performance.
- `lib/core/exchange/exchange_registry.dart:23:5` prefer_const_constructors : Use 'const' with the constructor to improve performance.
- `lib/core/network/okx_data_client.dart:1:8` unnecessary_import : The import of 'dart:typed_data' is unnecessary because all of the used elements are also provided by the import of 'package:flutter/foundation.dart'.
- `lib/core/network/okx_read_scope.dart:80:9` curly_braces_in_flow_control_structures : Statements in an if should be enclosed in a block.
- `lib/core/network/okx_read_scope.dart:82:9` curly_braces_in_flow_control_structures : Statements in an if should be enclosed in a block.
- `lib/core/theme/app_theme.dart:1:8` unnecessary_import : The import of 'dart:ui' is unnecessary because all of the used elements are also provided by the import of 'package:flutter/material.dart'.
- `lib/core/widgets/responsive_form_content.dart:49:15` prefer_const_constructors : Use 'const' with the constructor to improve performance.
- `lib/core/widgets/responsive_form_content.dart:152:19` prefer_const_constructors : Use 'const' with the constructor to improve performance.
- `lib/exchanges/binance/binance_estimated_pnl.dart:79:5` curly_braces_in_flow_control_structures : Statements in an if should be enclosed in a block.
- `lib/exchanges/binance/binance_estimated_pnl.dart:177:7` curly_braces_in_flow_control_structures : Statements in an if should be enclosed in a block.
- `lib/exchanges/binance/binance_estimated_pnl.dart:183:7` curly_braces_in_flow_control_structures : Statements in an if should be enclosed in a block.
- `lib/exchanges/binance/binance_estimated_pnl.dart:204:7` curly_braces_in_flow_control_structures : Statements in an if should be enclosed in a block.
- `lib/exchanges/binance/binance_market.dart:21:7` curly_braces_in_flow_control_structures : Statements in an if should be enclosed in a block.
- `lib/exchanges/binance/binance_market.dart:81:9` curly_braces_in_flow_control_structures : Statements in an if should be enclosed in a block.
- `lib/exchanges/binance/binance_market.dart:149:9` curly_braces_in_flow_control_structures : Statements in an if should be enclosed in a block.
- `lib/exchanges/binance/binance_market.dart:149:15` prefer_const_constructors : Use 'const' with the constructor to improve performance.
- `lib/exchanges/binance/binance_private_client.dart:129:13` curly_braces_in_flow_control_structures : Statements in an if should be enclosed in a block.
- `lib/exchanges/binance/binance_private_client.dart:131:13` curly_braces_in_flow_control_structures : Statements in an if should be enclosed in a block.
- `lib/exchanges/binance/binance_private_client.dart:190:7` curly_braces_in_flow_control_structures : Statements in an if should be enclosed in a block.
- `lib/exchanges/binance/binance_private_client.dart:227:7` curly_braces_in_flow_control_structures : Statements in an if should be enclosed in a block.
- `lib/exchanges/binance/binance_reader.dart:51:15` curly_braces_in_flow_control_structures : Statements in an if should be enclosed in a block.
- `lib/exchanges/binance/binance_reader.dart:57:15` curly_braces_in_flow_control_structures : Statements in an if should be enclosed in a block.
- `lib/exchanges/binance/binance_reader.dart:84:15` curly_braces_in_flow_control_structures : Statements in an if should be enclosed in a block.
- `lib/exchanges/binance/binance_reader.dart:88:17` curly_braces_in_flow_control_structures : Statements in an if should be enclosed in a block.
- `lib/exchanges/binance/binance_reader.dart:117:11` curly_braces_in_flow_control_structures : Statements in an if should be enclosed in a block.
- `lib/exchanges/binance/binance_reader.dart:128:7` curly_braces_in_flow_control_structures : Statements in an if should be enclosed in a block.
- `lib/exchanges/binance/binance_reader.dart:263:7` curly_braces_in_flow_control_structures : Statements in an if should be enclosed in a block.
- `lib/exchanges/binance/binance_reader.dart:265:7` curly_braces_in_flow_control_structures : Statements in an if should be enclosed in a block.
- `lib/exchanges/binance/binance_reader.dart:337:13` curly_braces_in_flow_control_structures : Statements in an if should be enclosed in a block.
- `lib/exchanges/okx/okx_adapter.dart:121:7` curly_braces_in_flow_control_structures : Statements in an if should be enclosed in a block.
- `lib/exchanges/okx/okx_adapter.dart:123:7` curly_braces_in_flow_control_structures : Statements in an if should be enclosed in a block.
- `lib/exchanges/okx/okx_adapter.dart:128:7` curly_braces_in_flow_control_structures : Statements in an if should be enclosed in a block.
- `lib/features/connections/binance_connection_form.dart:1:8` unnecessary_import : The import of 'package:flutter/foundation.dart' is unnecessary because all of the used elements are also provided by the import of 'package:flutter/material.dart'.
- `lib/features/connections/binance_connection_form.dart:124:9` curly_braces_in_flow_control_structures : Statements in an if should be enclosed in a block.
- `lib/features/connections/scope_picker.dart:85:29` curly_braces_in_flow_control_structures : Statements in an if should be enclosed in a block.
- `lib/features/fractal_tracker/presentation/fractal_screen.dart:164:23` curly_braces_in_flow_control_structures : Statements in an if should be enclosed in a block.
- `lib/features/fractal_tracker/presentation/fractal_screen.dart:294:7` curly_braces_in_flow_control_structures : Statements in an if should be enclosed in a block.
- `lib/features/fractal_tracker/presentation/fractal_screen.dart:296:7` curly_braces_in_flow_control_structures : Statements in an if should be enclosed in a block.
- `lib/features/fractal_tracker/presentation/fractal_screen.dart:766:26` deprecated_member_use : 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss.
- `lib/features/fractal_tracker/presentation/fractal_screen.dart:805:49` deprecated_member_use : 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss.
- `lib/features/market/presentation/market_screen.dart:8:8` unnecessary_import : The import of 'dart:ui' is unnecessary because all of the used elements are also provided by the import of 'package:flutter/material.dart'.
- `lib/features/orders/presentation/orders_screen.dart:129:11` curly_braces_in_flow_control_structures : Statements in an if should be enclosed in a block.
- `lib/features/orders/presentation/orders_screen.dart:156:7` curly_braces_in_flow_control_structures : Statements in an if should be enclosed in a block.
- `lib/features/orders/presentation/orders_screen.dart:433:21` curly_braces_in_flow_control_structures : Statements in an if should be enclosed in a block.
- `lib/features/orders/presentation/orders_screen.dart:523:28` unnecessary_to_list_in_spreads : Unnecessary use of 'toList' in a spread.
- `lib/features/portfolio/presentation/portfolio_screen.dart:299:31` curly_braces_in_flow_control_structures : Statements in an if should be enclosed in a block.
- `lib/features/portfolio/presentation/portfolio_screen.dart:492:23` curly_braces_in_flow_control_structures : Statements in an if should be enclosed in a block.
- `lib/features/portfolio/presentation/portfolio_screen.dart:541:41` curly_braces_in_flow_control_structures : Statements in an if should be enclosed in a block.
- `lib/features/strategy/presentation/providers/strategy_dashboard_provider.dart:349:24` unused_catch_clause : The exception variable 'error' isn't used, so the 'catch' clause can be removed.
- `lib/features/strategy/presentation/strategy_screen.dart:214:11` prefer_function_declarations_over_variables : Use a function declaration rather than a variable assignment to bind a function to a name.
- `lib/features/strategy/presentation/strategy_screen.dart:244:11` prefer_function_declarations_over_variables : Use a function declaration rather than a variable assignment to bind a function to a name.
- `lib/features/strategy/presentation/strategy_settings_dialog.dart:406:37` prefer_const_constructors : Use 'const' with the constructor to improve performance.
- `lib/features/support_resistance/data/market_repository.dart:87:45` annotate_overrides : The member 'getInstruments' overrides an inherited member but isn't annotated with '@override'.
- `lib/features/support_resistance/data/market_repository.dart:159:35` annotate_overrides : The member 'getTicker' overrides an inherited member but isn't annotated with '@override'.
- `lib/features/support_resistance/data/market_repository.dart:192:41` annotate_overrides : The member 'getCandles' overrides an inherited member but isn't annotated with '@override'.
- `lib/features/support_resistance/data/market_repository.dart:327:43` annotate_overrides : The member 'loadLevels' overrides an inherited member but isn't annotated with '@override'.
- `lib/main.dart:4:8` unnecessary_import : The import of 'dart:ui' is unnecessary because all of the used elements are also provided by the import of 'package:flutter/material.dart'.
- `lib/main.dart:393:7` curly_braces_in_flow_control_structures : Statements in an if should be enclosed in a block.
- `lib/main.dart:414:7` curly_braces_in_flow_control_structures : Statements in an if should be enclosed in a block.
- `lib/main.dart:425:11` curly_braces_in_flow_control_structures : Statements in an if should be enclosed in a block.

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
