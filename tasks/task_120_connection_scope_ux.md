# Task 120 — Connection experience and account states

Status: PENDING
Agent Role: implementation_executor
Executor Class: E3
Target Model: gpt-6.1-terra
Target Effort: high
Target Route: gpt-6.1-terra / high
Routing Policy: EXECUTOR_ROUTING_POLICY.json v2 (OptCodex v1.4.0)
Route Rationale: Multi-file frontend integration with explicit invariants, on contracts delivered by T117 to T119.
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Specification: `docs/agents/specs/2026-11-07-multi-platform-view-only-design.md`
Plan: `docs/agents/plans/2026-11-07-multi-platform-view-only.md`
Plan Steps: P05
Requirements: REQ-009, REQ-010
Acceptance Criteria: AC-009, AC-010

## 1. Dispatch Compliance

Before this task may enter `EXECUTING`, the coordinator must spawn an `implementation_executor` with both Target Model and Target Effort explicitly supplied. Omitting either or inheriting a route is prohibited.

Dispatch Route Status: PENDING
Requested Model: PENDING
Requested Effort: PENDING
Observed Effective Model: unavailable
Observed Effective Effort: unavailable

## 2. Objective

A user can connect Binance, switch between connections, manage them, and see correct state for each.

Done when: OKX and Binance are both registered and selectable, and switching follows the design with fake transports.

## 3. Preconditions

Predecessors: T118 and T119 = PASS. Decisions: D-001, D-004, D-008, D-009, D-010, P-003.
Required state: clean checkout on branch `codex/multi-platform-view-only`. Plan revision 2 approved.

## 4. Allowed Scope

- `lib/core/widgets/scope_bar.dart`, `lib/features/connections/**` (new)
- `lib/core/exchange/exchange_registry.dart` (register Binance)
- `lib/core/navigation/main_navigation_shell.dart`
- `lib/features/tools/tools_screen.dart`
- `lib/features/settings/presentation/settings_trade_access_page.dart` (extract `OkxCredentialForm`, keep every `settings-okx-*` key)
- `lib/features/portfolio/presentation/**`, `lib/features/orders/presentation/orders_screen.dart`, `lib/features/market/presentation/**`, `lib/features/fractal_tracker/presentation/**`, `lib/features/support_resistance/presentation/**` (insert bar, states, margin section, app-only notice, history coverage copy)
- Related tests, `test/features/connections/*` (new)

## 5. Forbidden Scope

Do not:
- read, search, parse, summarize or content-diff protected configuration, including `pubspec.yaml`, `pubspec.lock`, `analysis_options.yaml` and native project configuration;
- create, modify, regenerate or delete protected files, or add or remove dependencies;
- touch `backend/` or any git history, staging or branches;
- add any Binance or OKX write route;
- make opportunistic refactors or exceed the surface above.

If required work exceeds Allowed Scope, return `BLOCKED`.

## 6. Executor Contract

1. Add `ScopeBar` with no locked mode, 48-minimum hit area and a button semantic label naming exchange and account.
2. Add picker with `Đang xem`, `Chuyển sang tài khoản này`, `Quản lý kết nối`, listing configured connections only.
3. Add `ScopeSwitchGate`: pop pushed routes, key subtree by connectionId, show target loading from frame 08 without the prototype button, then land on Tài sản with a live region.
4. Add `Sàn & tài khoản`, catalog with disabled `Sàn khác`, OKX form using the extracted form, and Binance form with key and secret, read-only guidance and `Kiểm tra kết nối`. A test succeeds if any platform-available wallet read succeeds.
5. Add states: expired, empty, partial, app-only, retry card; replace raw errors at orders_screen near lines 266 and 309.
6. Add Margin section under Lệnh with cross and isolated cards, using `—` for unavailable. Spot stays in Tài sản.
7. Show coverage copy on Binance history.

Required invariants and edges: INV-001, INV-003, INV-004; EDGE-002, EDGE-004, EDGE-005, EDGE-010.
Apply reuse-first, minimal complete changes. Do not invent product semantics. If the contract is insufficient, return `BLOCKED`.

## 7. External Configuration / Environment Actions

Planned action: none.
Blocks verification until user applies: NO

## 8. Tests

- TEST-120-1: persistence across restart.
- TEST-120-2: fallback when keys are removed.
- TEST-120-3: state rendering.
- TEST-120-4: OKX settings keys intact.

## 9. Mandatory Verification

### RED — RED-120a/b
Scenario: (a) Picker opened with Binance keys removed while selected. (b) Binance expired on Tài sản. Also: a raw exception string from the read.
Command/method: `rtk flutter test --no-pub <file> --plain-name '<name>'`
Expected: (a) Fallback to OKX with no crash. (b) `Cần kiểm tra lại kết nối`, OKX remains selectable, and no raw error text anywhere.
Actual: PENDING
Status: PENDING

### GREEN — GREEN-120
Scenario: Fake transports: OKX to Binance to OKX; restart with Binance selected; web platform Binance.
Command/method: `rtk flutter test --no-pub <file> --plain-name '<name>'`
Expected: Target loading shown; no former data; lands on Tài sản; Binance restored after restart; web shows USD-M plus `Chỉ có trên ứng dụng`.
Actual: PENDING
Status: PENDING

Run RED before GREEN. Verification ceiling: V3: `test/features/connections`, `test/features/settings`, `test/features/portfolio`, `test/features/orders`.
Escalate only if: a shared provider or fixture used outside this set changes.

### Verification environment

Try plain `rtk flutter test --no-pub <file>` first; earlier executors ran it successfully here. If it fails with a write denial on the Flutter SDK cache or home directory, use this prepared SDK clone instead, for RED, GREEN and buildability:

`env HOME=/private/tmp/claude-501/-Users-locnguyen--claude-spares-spare-1YiVQu/74faedd6-f84d-41fb-aa01-a0288d74204a/scratchpad/flutter-home PUB_CACHE=/Users/locnguyen/.pub-cache /private/tmp/claude-501/-Users-locnguyen--claude-spares-spare-1YiVQu/74faedd6-f84d-41fb-aa01-a0288d74204a/scratchpad/flutter-sdk/bin/flutter <subcommand>`

An environment failure never stops implementation. Finish the code and tests, then report the exact error with `BLOCKED_ENVIRONMENT` for the verification steps you could not run, and the coordinator will run them on the host. Observed RED remains required wherever the tools work.

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

Verdict: PENDING
