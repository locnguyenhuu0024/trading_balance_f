# Task 129 — Binance trade pages and cost store

Status: PENDING
Agent Role: implementation_executor
Executor Class: E3
Target Model: gpt-6.1-terra
Target Effort: high
Target Route: gpt-6.1-terra / high
Routing Policy: EXECUTOR_ROUTING_POLICY.json v2 (OptCodex v1.4.0)
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Specification: `docs/agents/specs/2026-11-07-binance-estimated-pnl-design.md`
Plan: `docs/agents/plans/2026-11-07-binance-estimated-pnl.md`

## 1. Dispatch Compliance

The dispatcher passes `--model` and `model_reasoning_effort` on your command line, and your prompt states the route. `UNVERIFIABLE` is a valid state; do not stop for it.

Dispatch Route Status: UNVERIFIABLE
Requested Model: gpt-6.1-terra
Requested Effort: high

## 2. Objective

Trade history is read in budgeted pages, folded into stored cost state, and exposed through a provider that never slows the account read.

Done when: Tests prove paging, budget, resume, no polling, failure isolation and data removal.

Complete the work in this run; a long run is normal. Ending without file changes is a failed attempt.

## 3. Preconditions

Predecessors: T128 = PASS.

## 4. Allowed Scope

Exact write list. Read access covers all non-protected source and tests.

- `lib/exchanges/binance/binance_private_client.dart`
- `lib/exchanges/binance/binance_trade_history.dart`
- `lib/exchanges/binance/binance_adapter.dart`
- `lib/features/connections/binance_connection_form.dart`
- `test/exchanges/binance/binance_private_client_test.dart`
- `test/exchanges/binance/binance_trade_history_test.dart`
- `test/features/connections/binance_connection_form_test.dart`

## 5. Forbidden Scope

Do not read or change protected configuration, `backend/` or Git state. No new dependency, no write route, no file outside the list.

## 6. Executor Contract

1. Add `/api/v3/myTrades` and `/sapi/v1/margin/myTrades` to the client's private paths. On web they use the proxy like other Spot and Margin routes.
2. Section 5 of the specification defines symbols, paging, budget, run triggers, failures and the store.
3. Store key includes a short SHA-256 of the API key. Another key never reads it. Deleting the Binance connection removes all entries, and the key itself is never stored here.
4. `binanceCostStateProvider` exposes per-symbol state, stale and loading flags. It watches no order filter or poll, and no account read depends on it.
5. `spotMarginAvailable` false: no request and an unavailable state.
6. A cancellation or generation change discards the run without writing partial state for that page.
7. Use `CostState.apply` from `binance_cost_basis.dart`. It throws `ArgumentError` on a malformed trade: treat that as a failed symbol, which keeps old state and is stale. Trades in a symbol with base not ending the symbol, or quote other than USDT, are out of scope.

Mechanism details are yours if they satisfy these and the tests; report what you chose. Stop only for a conflict about product behavior.

## 7. External Configuration / Environment Actions

Planned action: user-owned nginx change in the plan, U3. Blocks this task: NO.

## 8. Tests

- TEST-129-1: first run pages from `fromId=0`; second run starts after the stored id.
- TEST-129-2: budget stops at 30 pages; next run resumes.
- TEST-129-3: top 20 by value; USDT and missing instruments skipped.
- TEST-129-4: isolated request sends `isIsolated=TRUE`.
- TEST-129-5: credential failure ends the run with no further request.
- TEST-129-6: a failed symbol keeps old state and is stale; others continue.
- TEST-129-7: reading the account makes no trade request.
- TEST-129-8: web without proxy: zero requests. Web with proxy: proxy host.
- TEST-129-9: another key reads nothing; deleting the connection clears the store.
- TEST-129-10: no secret in stored data.

## 9. Mandatory Verification

### RED — RED-129
Scenario: Second run with stored state, against a mutation that restarts at 0.
Expected: The test fails.
Status: PENDING

### GREEN — GREEN-129
Scenario: All tests.
Expected: Pass, and the worked example 1 trades produce its stored state.
Status: PENDING

Verification ceiling: V3: `test/exchanges/binance`, `test/features/connections`.

### Verification environment

Confirmed by the coordinator: this sandbox cannot run `flutter test`, because the test runner cannot bind 127.0.0.1, and the default SDK cache is not writable. Do not spend time on this and do not stop for it.

- Write the complete code and tests. Do not run `flutter test`.
- Compile checks are not available in the sandbox; the coordinator runs them on the host. Set `buildability` to `BLOCKED` with that reason and `status` to `COMPLETED`.
- In your report set `red` and `green` to `NOT_RUN`, naming the exact tests and the order RED then GREEN. Set `status` to `COMPLETED`.
- The coordinator executes RED then GREEN on the host during audit and returns any failure as a bounded remediation.

### Conflict rule

If a sentence in this contract conflicts with how OKX behaves today, keep the existing OKX behavior, implement the rest, and name the conflict in your summary. Stop only if the conflict affects something other than OKX preservation.

### Task Buildability Gate

Required: YES
Exact secret-free build command: `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings && flutter build web --no-pub`
Result: PENDING

## 10. Stop Conditions

Return `BLOCKED` if the fix needs a file outside the list.

## 11. Coordinator Audit

Verdict: PENDING
