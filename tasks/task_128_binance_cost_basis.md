# Task 128 — Binance cost basis calculation

Status: PASS
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

A pure calculation turns ordered trades and a holding into average cost, coverage and estimated profit, as in section 4 of the specification.

Done when: Worked examples 1 to 3 and the edge cases pass.

Complete the work in this run; a long run is normal. Ending without file changes is a failed attempt.

## 3. Preconditions

Predecessors: Approved plan.

## 4. Allowed Scope

Exact write list. Read access covers all non-protected source and tests.

- `lib/exchanges/binance/binance_cost_basis.dart`
- `test/exchanges/binance/binance_cost_basis_test.dart`

## 5. Forbidden Scope

Do not read or change protected configuration, `backend/` or Git state. No new dependency, no write route, no file outside the list.

## 6. Executor Contract

1. No Flutter, Riverpod or network import. Doubles are acceptable, and the state must serialize to JSON and resume.
2. `CostState` holds signed quantity, cost, and last trade id. `apply(trade)` is incremental, so applying trades in two batches equals one batch.
3. Follow section 4 exactly: fees, Spot floor at zero, margin zero crossing.
4. `estimate(state, holding, mark, interestInBase)` returns average, covered quantity, ratio, profit and percentage, or an insufficient-data result. Invalid mark or holding returns insufficient data, never NaN.

Mechanism details are yours if they satisfy these and the tests; report what you chose. Stop only for a conflict about product behavior.

## 7. External Configuration / Environment Actions

Planned action: user-owned nginx change in the plan, U3. Blocks this task: NO.

## 8. Tests

- TEST-128-1: worked example 1.
- TEST-128-2: worked example 2.
- TEST-128-3: worked example 3.
- TEST-128-4: two batches equal one batch; JSON round trip.
- TEST-128-5: Spot sale beyond known quantity floors at zero.
- TEST-128-6: margin long crossing into short restarts the average.
- TEST-128-7: opposite signs, zero trades, zero mark: insufficient data.
- TEST-128-8: BNB fee is ignored.

## 9. Mandatory Verification

### RED — RED-128
Scenario: Worked example 1 against a proportional-cost mutation.
Expected: Profit differs from `+149.6375`.
Status: PENDING

### GREEN — GREEN-128
Scenario: All tests.
Expected: Values in the specification.
Status: PENDING

Verification ceiling: V3: `test/exchanges/binance/binance_cost_basis_test.dart`.

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

Attempt: 0a1717bbb6c742049e6b174e1024746b
Dispatch route compliance: UNVERIFIABLE (requested gpt-6.1-terra/high, explicit).
Parent route inheritance: NO
RED and GREEN executed by the coordinator on the host, RED first (VAL-005): Ten mutations of cost, floor, crossing, interest, coverage, sign and fees were run. Nine failed the suite. The Spot floor mutation survived because no test sold from zero quantity, so the coordinator added TEST-128-5b, test file only; that mutation then failed too. GREEN passed with the specification's worked examples. Noted for T129 and T130: apply throws on malformed trades, and estimates with very small coverage need an insufficient-data display.
Regression and buildability, coordinator-observed: 9 tests pass in binance_cost_basis_test.dart; analyzer 0 errors; web build passes. Full suite runs at the plan's final gate.
Task buildability gate: PASS
Verdict: PASS
