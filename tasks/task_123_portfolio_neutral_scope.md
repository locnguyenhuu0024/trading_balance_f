# Task 123 — Portfolio on the neutral scope

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
Plan Steps: P02b
Requirements: REQ-004, REQ-005, REQ-012
Acceptance Criteria: AC-004, AC-005, AC-012

## 1. Dispatch Compliance

Before this task may enter `EXECUTING`, the coordinator must spawn an `implementation_executor` with both Target Model and Target Effort explicitly supplied. Omitting either or inheriting a route is prohibited. The coordinator has done this: the dispatcher passes `--model` and `model_reasoning_effort` on your command line, and your prompt states the route. You cannot observe more than that from inside the run, and `UNVERIFIABLE` is a valid state. Do not stop for it; start the task.

Dispatch Route Status: UNVERIFIABLE (explicitly bound by `scripts/ccb/dispatch.py`, runtime does not expose the effective route)
Requested Model: gpt-6.1-terra
Requested Effort: high
Observed Effective Model: unavailable
Observed Effective Effort: unavailable

## 2. Objective

`PortfolioScreen` and `PortfolioDetailsScreen` render from `AccountSnapshot` through `scopedAccountProvider(ref.watch(exchangeScopeProvider))`, with no visible OKX change.

Complete the work in this run. Expect to write every listed file; a long run is normal. Ending without file changes is a failed attempt.

Done when: OKX tests pass, and a fake exchange renders through the same screens with no OKX amount.

## 3. Preconditions

Predecessors: T117 = PASS. Decisions: D-001, D-004, D-008.
Required state: clean checkout on branch `codex/multi-platform-view-only`. Plan revision 2 approved.

## 4. Allowed Scope

Exact write list (new files use exactly these names). Read access covers all non-protected source and tests.

- `lib/features/portfolio/presentation/portfolio_screen.dart`
- `lib/features/portfolio/presentation/portfolio_details_screen.dart`
- `lib/features/portfolio/presentation/widgets/portfolio_currency_amount.dart`
- `lib/core/exchange/exchange_models.dart`
- `lib/exchanges/okx/okx_adapter.dart`
- `test/features/portfolio/portfolio_scope_test.dart`
- `test/features/portfolio/monochrome_portfolio_preview_test.dart`
- `test/features/portfolio/portfolio_currency_amount_test.dart`
- `test/features/portfolio/portfolio_dual_currency_screen_test.dart`
- `test/features/portfolio/portfolio_loading_test.dart`

## 5. Forbidden Scope

Do not:
- read, search, parse, summarize or content-diff protected configuration, including `pubspec.yaml`, `pubspec.lock`, `analysis_options.yaml` and native project configuration;
- create, modify, regenerate or delete protected files, or add or remove dependencies;
- touch `backend/` or any git history, staging or branches;
- add any Binance or OKX write route;
- make opportunistic refactors or exceed the surface above.

If required work exceeds Allowed Scope, return `BLOCKED`.

## 6. Executor Contract

1. Watch the scoped family instead of `portfolioFutureProvider`; refresh through the adapter's `invalidateAccount`.
2. Render from `AccountSnapshot` and `AssetBalance`. Keep masking, currency and formatting logic.
3. Keep the OKX total as computed today from balances and live prices; reach live prices only when scope is OKX. For other exchanges use the adapter's total and balance values.
4. Add any extra display field as a nullable text field and list it in your report.
5. Change existing tests for wiring only. Do not weaken assertions.

Required invariants and edges: INV-001, INV-002, INV-003, INV-004; EDGE-001, EDGE-003.
Apply reuse-first, minimal complete changes. Do not invent product semantics. If the contract is insufficient, return `BLOCKED`.

## 7. External Configuration / Environment Actions

Planned action: none.
Blocks verification until user applies: NO

## 8. Tests

- TEST-123-1 in `portfolio_scope_test.dart`: late OKX response does not render under the fake exchange.
- TEST-123-2: fake exchange balances render, and OKX live price subscription is not started for it.

## 9. Mandatory Verification

### RED — RED-123
Scenario: OKX balance read pending, select the fake exchange, resolve OKX late.
Command/method: `rtk flutter test --no-pub <file> --plain-name '<name>'`
Expected: The OKX amount never appears on screen; the fake exchange amount appears.
Actual: PENDING
Status: PENDING

### GREEN — GREEN-123
Scenario: Existing portfolio tests with OKX; fake exchange fixture.
Command/method: `rtk flutter test --no-pub <file> --plain-name '<name>'`
Expected: All pass unchanged except wiring.
Actual: PENDING
Status: PENDING

Run RED before GREEN. Verification ceiling: V3: `test/features/portfolio`, `test/core/exchange`.
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

Attempt: 082acd74d2f04417b456f19d1283d988
Dispatch route compliance: UNVERIFIABLE (requested gpt-6.1-terra/high, explicit).
Parent route inheritance: NO
RED and GREEN executed by the coordinator on the host, RED first (VAL-005): late OKX response never renders under fake exchange on both screens; then existing portfolio tests
Regression and buildability, coordinator-observed: 54 tests passed in portfolio, exchange, widget, backend gate, navigation; analyzer 0 errors; web build pass. Follow-up for T120: non-OKX absent amounts and terminal-failure refresh checks use the adapter.
Task buildability gate: PASS
Verdict: PASS
