# Task 117 — Exchange core and OKX behind it

Status: READY
Agent Role: implementation_executor
Executor Class: E2
Target Model: gpt-6-luna
Target Effort: max
Target Route: gpt-6-luna / max
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Specification: `docs/agents/specs/2026-11-07-multi-platform-view-only-design.md`
Plan: `docs/agents/plans/2026-11-07-multi-platform-view-only.md`
Plan Steps: P02
Requirements: REQ-004, REQ-005, REQ-012
Acceptance Criteria: AC-004, AC-005, AC-012

## 1. Dispatch Compliance

Before this task may enter `EXECUTING`, the coordinator must spawn an `implementation_executor` with both Target Model and Target Effort explicitly supplied. Omitting either or inheriting a route is prohibited.

Dispatch Route Status: PENDING
Requested Model: PENDING
Requested Effort: PENDING
Observed Effective Model: unavailable
Observed Effective Effort: unavailable

## 2. Objective

Portfolio and Orders read through the neutral exchange contract and scope providers, with OKX as the only registered exchange and no visible behavior change.

Done when: Those screens render through a registered adapter, a fake second adapter proves scope isolation, and existing OKX tests pass.

## 3. Preconditions

Predecessors: T116 = PASS. Decisions: D-001, D-004, D-008.
Required state: clean checkout on branch `codex/multi-platform-view-only`. Dispatch only after explicit approval of the currently presented plan.

## 4. Allowed Scope

- `lib/core/exchange/*` (new)
- `lib/exchanges/okx/okx_adapter.dart` (new)
- `lib/core/network/okx_read_scope.dart` (general `runPrivateRead`, keep `runOkxPrivateRead` wrapper)
- `lib/features/portfolio/presentation/portfolio_screen.dart`, `portfolio_details_screen.dart`, `presentation/providers/portfolio_provider.dart`, `presentation/widgets/*`
- `lib/features/orders/presentation/orders_screen.dart`, `presentation/providers/order_provider.dart`, read-only widgets under `presentation/widgets/` that render orders
- `lib/main.dart` (load selected connection at startup)
- `lib/core/security/secure_storage_helper.dart` (selected connection read and write)
- `test/core/exchange/*` (new), and existing portfolio and orders tests for wiring only

## 5. Forbidden Scope

Do not:
- read, search, parse, summarize or content-diff protected configuration, including `pubspec.yaml`, `pubspec.lock`, `analysis_options.yaml` and native project configuration;
- create, modify, regenerate or delete protected files, or add or remove dependencies;
- touch `backend/` or any git history, staging or branches;
- add any Binance or OKX write route;
- make opportunistic refactors or exceed the surface above.

If required work exceeds Allowed Scope, return `BLOCKED`.

## 6. Executor Contract

1. Add neutral types per spec section 6 with text-verbatim numerics.
2. Add `ExchangeAdapter`, registry, `selectedConnectionProvider`, `exchangeScopeProvider`, and `Provider.family` instances of `RequestCoordinator` and `ForegroundReadGate` per exchange, without changing those two classes.
3. Implement the OKX adapter by mapping existing repositories and freezed models field by field.
4. Convert Portfolio and Orders read providers to `autoDispose.family` on `ExchangeScope`, cancelling through the existing lease in `ref.onDispose`.
5. Reset `orderFilterProvider` and `orderTabProvider` on scope change.
6. Keep backend-typed widgets OKX-typed and untouched; keep the OKX `totalEq` path.

Required invariants and edges: INV-001, INV-002, INV-003, INV-004; EDGE-001, EDGE-003.
Apply reuse-first, minimal complete changes. Do not invent product semantics. If the contract is insufficient, return `BLOCKED`.

## 7. External Configuration / Environment Actions

Planned action: none.
Blocks verification until user applies: NO

## 8. Tests

- TEST-117-1: late response dropped.
- TEST-117-2: per-exchange lane independence.
- TEST-117-3: credential rotation drops in-flight result under the wrapper.
- TEST-117-4: fake adapter renders through both screens.

## 9. Mandatory Verification

### RED — RED-117a/b/c
Scenario: (a) OKX balance read pending, switch to fake exchange, resolve OKX late. (b) Fake exchange 429 with OKX idle. (c) Filter set to SWAP, then switch.
Command/method: `rtk flutter test --no-pub <file> --plain-name '<name>'`
Expected: (a) Amount never appears and token is cancelled. (b) OKX lane still accepts a read. (c) Filter is ALL and tab is positions.
Actual: PENDING
Status: PENDING

### GREEN — GREEN-117
Scenario: OKX adapter drives the existing Portfolio and Orders tests; a fake exchange shows its own balances after switching.
Command/method: `rtk flutter test --no-pub <file> --plain-name '<name>'`
Expected: Existing tests pass unchanged except wiring; fake data appears only under its own scope.
Actual: PENDING
Status: PENDING

Run RED before GREEN. Verification ceiling: V3: `test/core/network`, `test/core/exchange`, `test/features/portfolio`, `test/features/orders`.
Escalate only if: a shared provider or fixture used outside this set changes.

### Task Buildability Gate

Required: YES
Affected canonical build unit: Flutter app `lib/` and `test/`
Exact secret-free build command: `flutter analyze --no-pub && flutter build web --no-pub`
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
