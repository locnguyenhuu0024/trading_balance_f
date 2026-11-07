# Task 124 — Orders on the neutral scope

Status: PASS
Agent Role: implementation_executor
Executor Class: E3
Target Model: gpt-6.1-terra
Target Effort: high
Target Route: gpt-6.1-terra / high
Routing Policy: EXECUTOR_ROUTING_POLICY.json v2 (OptCodex v1.4.0)
Route Rationale: Multi-file frontend migration on an established contract from T117.
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Specification: `docs/agents/specs/2026-11-07-multi-platform-view-only-design.md`
Plan: `docs/agents/plans/2026-11-07-multi-platform-view-only.md`
Plan Steps: P02c
Requirements: REQ-004, REQ-005, REQ-012
Acceptance Criteria: AC-004, AC-005, AC-012

## 1. Dispatch Compliance

Before this task may enter `EXECUTING`, the coordinator must spawn an `implementation_executor` with both Target Model and Target Effort explicitly supplied. Omitting either or inheriting a route is prohibited. The coordinator has done this: the dispatcher passes `--model` and `model_reasoning_effort` on your command line, and your prompt states the route. You cannot observe more than that from inside the run, and `UNVERIFIABLE` is a valid state. Do not stop for it; start the task.

Dispatch Route Status: UNVERIFIABLE (explicitly bound by `scripts/ccb/dispatch.py`, runtime does not expose the effective route)
Requested Model: gpt-6.1-terra
Requested Effort: high
Observed Effective Model: unavailable
Observed Effective Effort: unavailable

## Remediation R01 (current instruction)

Attempt 6e88e4588e2e4d22b3b7448f9e665e83 is committed as work in progress and reviewed. One finding remains: the adapter now maps `size` from `OkxPosition.size`, which correctly preserves what the Orders card shows today, but `test/core/exchange/okx_adapter_test.dart` still has a fixture without `size`, so it fails at the `p.size` assertion.

Do only this: in that test's `OkxPosition` fixture, add `size: '0.10'`, keeping `pos`. Change nothing else, and do not change `okx_adapter.dart`. Sections below describe the already completed work.

## 2. Objective

`OrdersScreen` cards render from neutral types through the scoped providers, with no visible OKX change.

Complete the work in this run. Expect to write every listed file; a long run is normal. Ending without file changes is a failed attempt.

Done when: OKX tests pass, and a fake exchange renders through the same screen with no OKX rows.

## 3. Preconditions

Predecessors: T123 = PASS. Decisions: D-001, D-004, D-008.
Required state: clean checkout on branch `codex/multi-platform-view-only`. Plan revision 2 approved.

## 4. Allowed Scope

Exact write list (new files use exactly these names). Read access covers all non-protected source and tests.

- `lib/features/orders/presentation/orders_screen.dart`
- `lib/features/orders/presentation/widgets/order_notional.dart`
- `lib/features/orders/presentation/widgets/order_filter_controls.dart`
- `lib/features/orders/presentation/widgets/responsive_order_grid.dart`
- `lib/core/exchange/exchange_models.dart`
- `lib/exchanges/okx/okx_adapter.dart`
- `test/features/orders/orders_scope_test.dart`
- `test/features/orders/orders_screen_refresh_test.dart`
- `test/features/orders/position_actions_test.dart`
- `test/features/orders/order_cancellation_flow_test.dart`
- `test/features/orders/backend_position_actions_dialog_test.dart`
- `test/features/orders/presentation/order_timezone_test.dart`
- `test/features/orders/presentation/orders_screen_history_layout_test.dart`
- `test/features/orders/presentation/orders_screen_mobile_layout_test.dart`
- `test/features/orders/presentation/orders_screen_notional_test.dart`
- `test/features/orders/presentation/orders_screen_position_layout_test.dart`
- `test/features/orders/presentation/orders_screen_price_formatting_test.dart`
- `test/features/orders/presentation/widgets/order_notional_test.dart`
- `test/core/backend_features_test.dart`

## 5. Forbidden Scope

Do not:
- read, search, parse, summarize or content-diff protected configuration, including `pubspec.yaml`, `pubspec.lock`, `analysis_options.yaml` and native project configuration;
- create, modify, regenerate or delete protected files, or add or remove dependencies;
- touch `backend/` or any git history, staging or branches;
- add any Binance or OKX write route;
- make opportunistic refactors or exceed the surface above.

If required work exceeds Allowed Scope, return `BLOCKED`.

## 6. Executor Contract

1. Watch `scopedPositionsProvider` and `scopedOrdersProvider`; refresh through the adapter's invalidate methods.
2. Move card builders to `ExchangePosition` and `ExchangeOrder`. Keep formatting and layout.
3. Only gate-true backend widgets cast `native` to `OkxPosition` or `OkxOrder`; with no OKX native record they are not shown.
4. Filter chips stay as they are for now; T120 adapts them to capabilities.
5. Add any extra display field as a nullable text field and list it in your report.
6. Change existing tests for wiring only. Do not weaken assertions.

Required invariants and edges: INV-001, INV-002, INV-003, INV-004; EDGE-001, EDGE-003.
Apply reuse-first, minimal complete changes. Do not invent product semantics. If the contract is insufficient, return `BLOCKED`.

## 7. External Configuration / Environment Actions

Planned action: none.
Blocks verification until user applies: NO

## 8. Tests

- TEST-124-1 in `orders_scope_test.dart`: late OKX positions do not render under the fake exchange.
- TEST-124-2: fake exchange positions, pending orders and history render with no backend controls, even with the gate true.

## 9. Mandatory Verification

### RED — RED-124
Scenario: OKX positions read pending, select the fake exchange, resolve OKX late; then the same for pending orders.
Command/method: `rtk flutter test --no-pub <file> --plain-name '<name>'`
Expected: No OKX row appears; fake rows appear.
Actual: PENDING
Status: PENDING

### GREEN — GREEN-124
Scenario: Existing orders tests with OKX; fake exchange fixture on all three tabs.
Command/method: `rtk flutter test --no-pub <file> --plain-name '<name>'`
Expected: All pass unchanged except wiring.
Actual: PENDING
Status: PENDING

Run RED before GREEN. Verification ceiling: V3: `test/features/orders`, `test/core/backend_features_test.dart`, `test/core/exchange`.
Escalate only if: a shared provider or fixture used outside this set changes.

### Verification environment

Confirmed by the coordinator: this sandbox cannot run `flutter test`, because the test runner cannot bind 127.0.0.1, and the default SDK cache is not writable. Do not spend time on this and do not stop for it.

- Write the complete code and tests. Do not run `flutter test`.
- For a compile check, use `env HOME=/private/tmp/claude-501/-Users-locnguyen--claude-spares-spare-1YiVQu/74faedd6-f84d-41fb-aa01-a0288d74204a/scratchpad/flutter-home PUB_CACHE=/Users/locnguyen/.pub-cache /private/tmp/claude-501/-Users-locnguyen--claude-spares-spare-1YiVQu/74faedd6-f84d-41fb-aa01-a0288d74204a/scratchpad/flutter-sdk/bin/flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings`, and `env HOME=/private/tmp/claude-501/-Users-locnguyen--claude-spares-spare-1YiVQu/74faedd6-f84d-41fb-aa01-a0288d74204a/scratchpad/flutter-home PUB_CACHE=/Users/locnguyen/.pub-cache /private/tmp/claude-501/-Users-locnguyen--claude-spares-spare-1YiVQu/74faedd6-f84d-41fb-aa01-a0288d74204a/scratchpad/flutter-sdk/bin/flutter build web --no-pub` for buildability.
- In your report set `red` and `green` to `NOT_RUN`, naming the exact tests and the order RED then GREEN. Set `status` to `COMPLETED`.
- The coordinator executes RED then GREEN on the host during audit and returns any failure as a bounded remediation.

### Conflict rule

If a sentence in this contract conflicts with how OKX behaves today, REQ-012 wins: keep the existing OKX behavior, implement the rest, and name the conflict in your summary. Stop only if the conflict affects something other than OKX preservation.

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

Attempt: c280d66023904891a283976d33a6a70c
Dispatch route compliance: UNVERIFIABLE (requested gpt-6.1-terra/high, explicit).
Parent route inheritance: NO
RED and GREEN executed by the coordinator on the host, RED first (VAL-005): late OKX positions and pending orders do not render under the fake exchange; then existing orders tests and the fake exchange on all tabs
Regression and buildability, coordinator-observed: 217 tests passed in orders, portfolio, exchange, gate, widget, navigation, settings; analyzer 0 errors; web build pass. The second attempt returned an invalid structured report, but its one-line diff was reviewed directly. Follow-up for T120: cards split nativeId on '-', Binance needs base and quote from metadata. Existing: direct OKX reads leave position size empty on the card, addressed in T121.
Task buildability gate: PASS
Verdict: PASS
