# Task 120 — Binance catalog reuse, Spot unpriced orders, zero-balance rows

Status: APPROVED (plan and D-008..D-010 approved by user 2026-10-27); dispatch needs a clean writer checkout
Agent Role: implementation_executor
Executor Class: E1
Target Model: gpt-6-luna
Target Effort: xhigh
Target Route: gpt-6-luna / xhigh
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Specification: `docs/agents/specs/2026-10-25-binance-direct-reads-design.md`
Plan: `docs/agents/plans/2026-10-27-binance-direct-reads-remediation.md`
Plan Steps: P01
Requirements: REQ-002, REQ-004, REQ-005 (corrections)
Acceptance Criteria: RAC-001 (AUD-001), RAC-002 (AUD-002), RAC-003 (AUD-003)

## 1. Dispatch Compliance
Spawn an `implementation_executor` with both model `gpt-6-luna` and effort `xhigh` supplied explicitly. No inherited route. No Terra.
Dispatch Route Status: PENDING
Requested Model: PENDING
Requested Effort: PENDING
Observed Effective Model: unavailable
Observed Effective Effort: unavailable

## 2. Objective
Make the Binance Spot catalog read once per credential generation (60-minute lifetime) for Portfolio refreshes, make Spot order prices that are not positive unavailable, and hide Binance asset rows with an exactly zero total.
Done when: RAC-001..003 pass, V3 group and full-app web build pass, OKX behavior is unchanged.

## 3. Preconditions
Predecessors: none (T116, T117, T118 = PASS in the parent plan).
Required decisions: D-008, D-009, D-010 approved by the user. Do not start otherwise.
State: clean checkout on `codex/binance-direct-reads`.

## 4. Allowed Scope
Source:
- `lib/core/exchange/binance_exchange_reader.dart`
- `lib/core/exchange/exchange_account_providers.dart`

Tests (Dart behavioral tests and their in-file fixtures only):
- `test/core/exchange/exchange_readers_test.dart`
- `test/features/portfolio/combined_exchange_portfolio_test.dart`

## 5. Forbidden Scope
Do not read, search within, parse, summarize or content-diff protected configuration/environment files, and do not create, modify, delete or regenerate them. No dependency, lock, build or CI change. Do not change the route registry, weights, scheduler, credential storage, history scan logic, OKX readers, backend actions, Strategy, canonical plans/tasks/status or telemetry. No Git state changes. No unrelated refactors. Return `BLOCKED` if the contract is insufficient.

## 6. Executor Contract
1. Reader (`binance_exchange_reader.dart`): store the last successful Spot catalog with its credential generation and fetch time from the reader clock. Add an optional `getSpotCatalog` parameter, default off, that returns the stored catalog without a request only when all hold: `knownSymbols` is empty, the stored generation equals the captured generation, and age is under 60 minutes. Every successful network fetch updates the store. Clear it on credential generation change and on dispose. `readSpotHistoryPage`, the history scan and `_ensureSpotCatalog` semantics stay as they are (the history scan must keep reading a fresh catalog).
2. Provider (`exchange_account_providers.dart`): `_readBinanceSpotCatalog` passes the reuse flag, so repeated `binanceSpotPortfolioSourceProvider` evaluations in one generation send at most one exchangeInfo request.
3. `_spotOrder`: price is available only when the parsed native price is positive and the quote currency is known; otherwise unavailable with a short reason. No derived average. Futures behavior unchanged.
4. `_portfolioRows`: skip a Binance balance when `_balanceTotal(balance)` is available and exactly zero. Keep it when unavailable. OKX rows unchanged. Do not change equity, completeness or warning logic.

Invariants: INV-001..005 and D-001..D-010 as approved. Preserved: combined equity fixture 195, 15 s quote freshness, per-source independent refresh, generation fencing.
Do not self-escalate the route.

## 7. External Configuration / Environment Actions
Planned: none. Discovered: none expected; if one appears, stop and report target, location and placeholders. Blocks verification: NO.

## 8. Tests
- TEST-120-1: through the production reader with an injected transport, two Spot portfolio-source refreshes in one generation send one exchangeInfo request; a request after 61 minutes; a request after a credential generation change; a history scan still sends its own.
- TEST-120-2: Spot MARKET row with `price: "0.00000000"` has an unavailable price; a limit row with a positive price keeps it.
- TEST-120-3: Binance Spot and Futures zero rows are hidden; an unavailable-amount row stays; a zero OKX row stays; total equity and completeness are unchanged.
Name the formal cases with prefixes `RED-120` and `GREEN-120`.

## 9. Mandatory Verification
### RED — RED-120
Scenario: behaviors described in plan P01 fail against the current code (two exchangeInfo requests, available zero price, zero rows listed).
Command: `rtk flutter test --no-pub test/core/exchange/exchange_readers_test.dart test/features/portfolio/combined_exchange_portfolio_test.dart --plain-name RED-120`
Expected: the new RED cases fail on the pre-change code for exactly those reasons; derive expectations from this contract, not from output.
Actual: PENDING
Status: PENDING

### GREEN — GREEN-120
Scenario: the success behaviors of TEST-120-1..3.
Command: `rtk flutter test --no-pub test/core/exchange/exchange_readers_test.dart test/features/portfolio/combined_exchange_portfolio_test.dart --plain-name GREEN-120`
Expected: all GREEN cases pass after the change.
Actual: PENDING
Status: PENDING

Run RED before GREEN. Use narrow diagnostics while implementing.
Verification ceiling: V3 — `rtk flutter test --no-pub test/core/exchange test/features/portfolio test/features/orders`. No full suite per task. Escalate only for a demonstrated shared-surface regression.

### Task Buildability Gate
Required: YES
Affected canonical build unit: full Flutter application
Exact secret-free build command: `rtk flutter build web --no-pub`
Executed after the last task-local executable/source/test change: PENDING
Result: PENDING
No later task may repair this task's build. Changed-source build error is `REWORK`; a pre-build toolchain failure is `BLOCKED_ENVIRONMENT`.

### External Verification
Required: NO. Live private-account, device and CORS checks are unavailable and must not be claimed.

## 10. Stop Conditions
Return `BLOCKED` if: repository evidence contradicts this contract; reuse requires editing files outside section 4; a required fact is in protected configuration; verification is genuinely unavailable.

## 11. Execution Ledger
- [ ] dispatch role, class, model and effort match this task; no inherited route
- [ ] implement P01 steps 1–4
- [ ] add TEST-120-1..3
- [ ] formal RED then GREEN observed
- [ ] V3 group run
- [ ] task build after last change
- [ ] compact executor report returned (changed paths, AC mapping, evidence, limitations)
- [ ] no protected content read or modified; External Configuration actions reported as none

## 12. Coordinator Audit
Scope / RAC-001..003 / test quality / RED-before-GREEN / buildability / route compliance: PENDING
Verdict: PENDING (PASS | REWORK | BLOCKED)
