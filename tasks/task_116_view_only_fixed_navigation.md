# Task 116 — View-only mode and fixed navigation

Status: PASS (via T122 remediation, 2026-11-07)
Route Note: dispatched under pre-v1.4 rules as legacy E1 gpt-6-luna/xhigh; kept as the user excluded this task from reclassification.
Agent Role: implementation_executor
Executor Class: E1
Target Model: gpt-6-luna
Target Effort: xhigh
Target Route: gpt-6-luna / xhigh
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Specification: `docs/agents/specs/2026-11-07-multi-platform-view-only-design.md`
Plan: `docs/agents/plans/2026-11-07-multi-platform-view-only.md`
Plan Steps: P01
Requirements: REQ-001, REQ-002, REQ-003
Acceptance Criteria: AC-001, AC-002, AC-003

## 1. Dispatch Compliance

Before this task may enter `EXECUTING`, the coordinator must spawn an `implementation_executor` with both Target Model and Target Effort explicitly supplied. Omitting either or inheriting a route is prohibited.

Dispatch Route Status: PENDING
Requested Model: PENDING
Requested Effort: PENDING
Observed Effective Model: unavailable
Observed Effective Effort: unavailable

## 2. Objective

The app makes no backend request, hides every backend feature, and shows a fixed four-item bar with a Tools screen.

Done when: With the gate false, a counting adapter sees zero backend requests across retained screens and the bar shows Tài sản, Lệnh, Thị trường, Thêm.

## 3. Preconditions

Predecessors: none. PRE-1 and PRE-2 applied. Decisions: D-003, D-006, D-007, P-001, P-002, P-004.
Required state: clean checkout on branch `codex/multi-platform-view-only`. Dispatch only after explicit approval of the currently presented plan.

## 4. Allowed Scope

- `lib/core/backend_features.dart` (new)
- `lib/features/orders/presentation/providers/trade_session_provider.dart` (`tradeApiProvider` only)
- `lib/features/strategy/data/strategy_api_client.dart` (`strategyApiProvider` only, plus a disabled implementation)
- `lib/features/orders/data/trade_api_client.dart` (add a disabled `TradeApi` implementation only)
- `lib/features/orders/presentation/orders_screen.dart` (gating at lines near 117, 166, 197, 345, 1106, 1334)
- `lib/features/settings/presentation/settings_screen.dart`, `settings_trade_access_page.dart`
- `lib/core/navigation/main_navigation_shell.dart`, `navigation_destination_data.dart`, `navigation_presentation_host.dart`, `trading_navigation_bar.dart`
- Delete `lib/core/navigation/floating_navigation_buttons.dart`, `navigation_preferences.dart`, `navigation_preferences_provider.dart`
- `lib/main.dart`, `lib/core/security/secure_storage_helper.dart` (navigation preference removal only; keep storage of everything else)
- `lib/features/tools/tools_screen.dart` (new)
- `lib/core/navigation/navigation_content_frame.dart`, `lib/core/widgets/app_startup.dart` (only if they reference removed navigation preferences)
- New tests and helper: `test/core/backend_features_test.dart`, `test/features/tools/tools_screen_test.dart`, `test/support/backend_features_override.dart`
- Delete: `test/core/navigation/floating_navigation_buttons_test.dart`, `navigation_preferences_test.dart`, `navigation_preferences_provider_test.dart`, `test/features/settings/settings_navigation_preferences_test.dart`
- Rewrite: `test/core/navigation/main_navigation_shell_test.dart`, `navigation_presentation_host_test.dart`
- Wiring only (gate override or removed-preference fixtures); leave assertions intact: `test/widget_test.dart`, `test/core/navigation/navigation_content_frame_test.dart`, `app_page_transition_test.dart`, `test/core/security/biometric_auth_default_test.dart`, `test/core/widgets/app_startup_test.dart`, `test/features/orders/order_cancellation_flow_test.dart`, `orders_screen_refresh_test.dart`, `position_actions_test.dart`, `backend_position_actions_dialog_test.dart`, `test/features/orders/presentation/orders_screen_{history_layout,mobile_layout,notional,position_layout,price_formatting}_test.dart`, `test/features/portfolio/{monochrome_portfolio_preview,portfolio_dual_currency_screen,portfolio_loading}_test.dart`, `test/features/settings/{settings_currency_option,settings_timezone_option,settings_trade_access_page,vnd_exchange_rate_provider}_test.dart`, `test/features/strategy/strategy_screen_test.dart`

## 5. Forbidden Scope

Do not:
- read, search, parse, summarize or content-diff protected configuration, including `pubspec.yaml`, `pubspec.lock`, `analysis_options.yaml` and native project configuration;
- create, modify, regenerate or delete protected files, or add or remove dependencies;
- touch `backend/` or any git history, staging or branches;
- add any Binance or OKX write route;
- make opportunistic refactors or exceed the surface above.

If required work exceeds Allowed Scope, return `BLOCKED`.

## 6. Executor Contract

1. Add `backendFeaturesEnabledProvider` as `Provider<bool>` returning false.
2. When false, `tradeApiProvider` and `strategyApiProvider` return implementations that throw `backend_disabled` before any network call.
3. Gate at parent call sites only. In Orders do not watch `tradeSessionProvider` when false, show `filterControls` directly at the position tab using the pattern already at the non-position branch, and omit cancel controls. Do not edit child widgets, dialogs or flow providers.
4. In Settings hide the backend entry; keep the OKX credential editor reachable; omit `TradeSessionControls` when false.
5. Fix `navigationItems` to Tài sản, Lệnh, Thị trường, Thêm; add Chiến thuật as third only when the gate is true. Remove customization code and settings tiles. Remove preference read and write methods but no storage deletion call.
6. Add `ToolsScreen` with four cards that push `FractalScreen`, `SupportResistanceScreen`, `SettingsScreen`, and a temporary push of the existing OKX credential page for `Sàn & tài khoản`.
7. Add the override to existing Orders and trade-access tests so they run with the gate true.

Required invariants and edges: INV-005; REQ-012 preserved.
Apply reuse-first, minimal complete changes. Do not invent product semantics. If the contract is insufficient, return `BLOCKED`.

## 7. External Configuration / Environment Actions

Planned action: none.
Blocks verification until user applies: NO

## 8. Tests

- TEST-116-1: counting adapter across Lệnh and Cài đặt with gate false.
- TEST-116-2: stored floating preference renders the fixed bar.
- TEST-116-3: Tools cards navigate.
- Existing Orders, trade-access and Strategy tests pass with the override.

## 9. Mandatory Verification

### RED — RED-116
Scenario: Gate false, counting HTTP adapter, stored preference with floating mode; pump shell and open Lệnh and Cài đặt. Before implementation this fails on backend requests and a floating presentation.
Command/method: `rtk flutter test --no-pub <file> --plain-name '<name>'`
Expected: Zero backend requests; no `Đã đăng nhập` or `Chưa đăng nhập`, close, close-all or cancel; a bar with exactly four items.
Actual: PENDING
Status: PENDING

### GREEN — GREEN-116
Scenario: Gate false: Thêm reaches the four tools and position filter chips remain. Gate true: existing screen tests pass and Chiến thuật is third.
Command/method: `rtk flutter test --no-pub <file> --plain-name '<name>'`
Expected: All selected cases pass.
Actual: PENDING
Status: PENDING

Run RED before GREEN. Verification ceiling: V3: `test/core/navigation`, `test/features/orders`, `test/features/settings`, `test/widget_test.dart`.
Escalate only if: a shared provider or fixture used outside this set changes.

### Task Buildability Gate

Required: YES
Affected canonical build unit: Flutter app `lib/` and `test/`
Exact secret-free build command: `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings && flutter build web --no-pub`
Executed after the last task-local change: PENDING
Result: PENDING

### External Verification

Required: NO for this task. The program's user-run live check follows the final audit.

## 10. Stop Conditions

Return `BLOCKED` when repository evidence contradicts this contract, a design decision is missing, a dependency appears necessary, scope is exceeded, or verification is unavailable. Report evidence, affected IDs, and the coordinator decision needed.

## 11. Execution Ledger

- [ ] confirm route binding
- [ ] inspect referenced symbols
- [ ] implement assigned step
- [ ] add or update tests
- [ ] execute formal RED, then GREEN
- [ ] run buildability gate after last change
- [ ] return compact executor report
- [ ] confirm no protected content read or modified

## 12. Coordinator Audit

Attempt: 7d41604a679d4abaa9b4d288b07ed94a
Dispatcher result: BLOCKED. Cause: governance files were upgraded to OptCodex v1.4.0 in the checkout at 16:06 during execution, so they appeared as out-of-scope changes; the executor also reported its chained gate as blocked. Executor write surface itself: all 41 changed `lib/` and `test/` paths are inside the manifest.
Dispatch route compliance: UNVERIFIABLE (requested gpt-6-luna/xhigh, explicit).
Parent route inheritance: NO
Coordinator-observed tests: V3 set, 222 passed. Web build: PASS. Analyzer: 0 errors, 10 warnings, 68 infos; `flutter analyze` exits non-zero on infos, so the original gate command was a plan defect, corrected in revision 2.
RED evidence: executor report only, in prose; test structure is consistent.
Task buildability gate: PASS under the corrected command.

Findings:
- AUD-116-01 Must fix: `settings_screen.dart:555` gates the `Ẩn số dư mặc định` and biometric card on `backendFeaturesEnabled`. With the gate false the user loses both, and the section title stays above nothing. Violates REQ-012 and handoff section 7. The test suite does not catch it.
- AUD-116-02 Must fix: `test/core/backend_features_test.dart` asserts zero cancel controls against empty order lists, so that part of AC-002 is unproven. Needs an active limit order row and a position row, with and without the gate.

Verdict on this attempt: REWORK. Remediation: `tasks/task_122_t116_settings_gate_remediation.md`, verdict PASS, closes both findings, so the task is PASS.
