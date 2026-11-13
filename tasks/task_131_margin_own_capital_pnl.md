# Task 131 — Margin profit percentage on own capital

Status: PASS
Agent Role: implementation_executor
Executor Class: E2
Target Model: gpt-6.1-terra
Target Effort: medium
Target Route: gpt-6.1-terra / medium
Routing Policy: EXECUTOR_ROUTING_POLICY.json v2 (OptCodex v1.4.0)
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Specification: `docs/agents/specs/2026-11-07-binance-estimated-pnl-design.md` (amended by the plan)
Plan: `docs/agents/plans/2026-11-13-binance-margin-own-capital-pnl.md`
Plan Steps: P01
Decisions: D-001, D-002, D-003

## Remediation R01 (current instruction)

The first pass is committed. Do not redo it. Write only `test/features/portfolio/portfolio_scope_test.dart`.

AUD-131-01, the test run hangs. In the new test `Assets own capital and summary withSpot=…`, the final `await views.close();` never completes inside `testWidgets` after the container is disposed. Because of that, `flutter test test/features/portfolio/portfolio_scope_test.dart` stops at that test until it times out, and the 15 tests after it never run. Required: delete only that `await views.close();` line, so the test matches the existing test that ends with `container.dispose();` and no close. Change nothing else: no other assertion, fixture or test.

Executor Class for R01: E0, `gpt-6-luna / xhigh` (policy v2 default for a mechanical edit).

Not dispatched. The user granted a task-specific coordinator override for T131 / AUD-131-01 ("Cho Claude tự sửa", chat, 2026-11-13). The coordinator removed that one line and nothing else.

## 1. Dispatch Compliance

Before execution, spawn the executor with model and effort both passed explicitly. Do not inherit either.

Dispatch Route Status: PENDING
Requested Model: PENDING
Requested Effort: PENDING
Observed Effective Model: unavailable
Observed Effective Effort: unavailable

## 2. Objective

On Binance, the estimated percentage for an Isolated Margin pair and for the Spot and Margin summary is computed on the user's own capital. `Vốn gốc` no longer includes the estimated Spot and Margin profit.

Done when: the W1–W5 figures in the plan are proven by tests, and every existing Spot, OKX and USDⓈ-M expectation still passes.

## 3. Preconditions

Predecessors: T130 = PASS.
Required decisions: D-001, D-002 and D-003, all in the plan.
Repository state: clean checkout on `codex/multi-platform-view-only`.

## 4. Allowed Scope

The exact write list is below. You may read any non-protected source or test.

- `lib/exchanges/binance/binance_estimated_pnl.dart`
- `lib/features/portfolio/presentation/portfolio_screen.dart`
- `test/exchanges/binance/binance_estimated_pnl_test.dart`
- `test/features/portfolio/portfolio_scope_test.dart`
- `test/features/orders/orders_binance_view_test.dart`

## 5. Forbidden Scope

- Protected configuration, `backend/` and Git state: do not read or change.
- `lib/exchanges/binance/binance_cost_basis.dart`: no change. `CostEstimate.percentage` and AC-201 stay as they are.
- `orders_screen.dart` or `margin_account_card.dart`: no change. The margin card already prints `estimatedPnlText(row)`.
- No new dependency, no Cross Margin capital rule and no text layout change.

If the work needs anything outside the list above, return `BLOCKED`.

## 6. Executor Contract

1. `EstimatedPnlRow` gets the own capital in USDT used for its displayed percentage. The value is null when capital is invalid.
   - Spot and Cross Margin rows: capital = `estimate.coveredQuantity × estimate.average`. The result is the same as today.
   - Isolated rows from `estimatedMargin` with `row.key != null`: capital = `baseNet × mark + quoteNet − estimate.profit`, where mark is `indexPrice` and `quoteNet` is `_number(row.quoteNet)`. Capital is null if `quoteNet` is missing, or if the result is not finite or is ≤ 0.
2. `estimatedPnlText` prints `(signed profit ÷ capital × 100 %)` with 2 decimals. When capital is null, it leaves out the ` (…%)` part and keeps `Giá vốn TB … · Ước tính … USDT` and every suffix.
3. `EstimatedPnlSummary.cost` becomes the sum of covered rows' capital. If any covered row has null capital, or the sum is ≤ 0, the summary percentage is unavailable. `portfolio_screen.dart` then prints the summary amount without ` (…%)`. The covered and eligible counts do not change.
4. In `portfolio_screen.dart`, set `baseEquity = total − USDⓈ-M uPnL − summary.profit` when all of these hold: Binance, `costView` not null, `available`, `_costFinished`, not `loading`, and `summary.covered > 0`. Hiding balances does not change the value; it only masks it. Otherwise keep the current value. Leave `ratioBase` and `pnlRatio` (the USDⓈ-M figures) unchanged. Compute the summary once and reuse it for the line and for `baseEquity`.
5. Do not touch the message states, staleness, the `ratio < 0.01` rule, hiding, the run and poll rules, or OKX.

Preserved behavior: everything in T128–T130 not named here.

## 7. External Configuration / Environment Actions

Planned action: none. Blocks verification: NO.

## 8. Tests

The expected values are in the plan, W1–W5. They were derived independently.

- TEST-131-1: W1 Isolated long text `Giá vốn TB 100.00 · Ước tính -20.50 USDT (-41.00%)`, in the unit test and on the Orders margin card.
- TEST-131-2: W2 Isolated short, text ends in `(+20.00%)`.
- TEST-131-3: W3, capital 0, text `Giá vốn TB 100.00 · Ước tính -20.50 USDT`, with no percentage.
- TEST-131-4: W4 summary `-10.50 USDT (-7.00%)`, as a unit test and on Assets.
- TEST-131-5: W5. `Vốn gốc` is 50.00 USDT with the summary available, and 29.50 USDT while the cost view is loading.
- Existing Spot `(+10.00%)` and USDⓈ-M `(+0.00%)`, `(+5.26%)` and `(+10.00%)` expectations stay unchanged.

## 9. Mandatory Verification

### RED — RED-131
Scenario: run TEST-131-1, TEST-131-4 and TEST-131-5 against the code before the change.
Command: `flutter test test/exchanges/binance/binance_estimated_pnl_test.dart test/features/portfolio/portfolio_scope_test.dart test/features/orders/orders_binance_view_test.dart`
Expected: these fail, showing `(-20.50%)`, `(-5.25%)` and 29.50 where the tests expect `(-41.00%)`, `(-7.00%)` and 50.00.
Status: PENDING

### GREEN — GREEN-131
Scenario: the same command after the change.
Expected: all tests in the three files pass.
Status: PENDING

Verification ceiling: V2. Escalate to V3 (`test/exchanges/binance`, `test/features/portfolio`, `test/features/orders`) only if a shared provider or widget changed.

### Verification environment

As in T130, the executor sandbox cannot run `flutter test` or compile. Write the complete code and tests. In the report, set `red` and `green` to `NOT_RUN` and name the tests in RED then GREEN order. Set `buildability` to `BLOCKED` with that reason. The coordinator runs RED, then GREEN, then the build on the host.

### Task Buildability Gate

Required: YES
Affected canonical build unit: Flutter app at the repository root
Exact secret-free build command: `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings && flutter build web --no-pub`
Result: PENDING

## 10. Stop Conditions

Return `BLOCKED` if the change needs a file outside the list, a rule for Cross Margin, or a change to `binance_cost_basis.dart`.

## 11. Coordinator Audit

Attempt: 4b3879c5853745a79db3e6f4182faff7. The executor reported `BLOCKED` only because its sandbox cannot run tests or builds, which this contract expects. Its changed paths equal the allowed list.
Scope: PASS. Five allowed files changed. Not touched: `binance_cost_basis.dart`, `orders_screen.dart`, the card widget, protected config. The coordinator changed one test line under the R01 override, plus this file.
Contract: PASS.
- D-001: isolated capital = `baseNet × indexPrice + quoteNet − profit`. It is null when `quoteNet` is missing or the result is ≤ 0 or not finite.
- D-002: Spot and Cross capital = covered × average, unchanged.
- D-003: `baseEquity` subtracts `summary.profit` when the summary is available and `covered > 0`, including while hidden. The summary is computed once. `ratioBase` and `pnlRatio` are untouched.
- The summary percentage is null on incomplete capital, and the text then leaves out `(…%)`.
Tests: the W1–W5 figures are asserted exactly, plus invalid `quoteNet` (`-101`, `NaN`, `Infinity`, empty). No existing expectation was weakened.
RED evidence (host, before GREEN): with the new tests against the HEAD versions of the two lib files, these widget tests failed:
- `Assets own capital … withSpot=false`: no `$50.00`.
- `withSpot=true`: no `Ước tính Spot · Margin: -$10.50 (-7.00%)`.
- `isolated margin card shows profit on own capital`: no `(-41.00%)`.

The unit file failed to compile because `EstimatedPnlRow.capital` was not defined. The lib files were then restored.
AUD-131-01 (the hang on `await views.close()` in teardown) was found on the first GREEN and fixed by the coordinator under the user's override. It changed only teardown, after the assertions, so the RED evidence stays valid.
GREEN evidence (host): `flutter test --no-pub` on the three task files: 42 passed, exit 0.
V3 regression (host): `flutter test --no-pub test/features/portfolio test/features/orders test/exchanges/binance`: 248 passed, exit 0.
Dispatch route compliance: UNVERIFIABLE (requested gpt-6.1-terra / medium, explicit). Parent route inheritance: NO.
Task buildability gate: PASS, run after the last change.
- `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings`: exit 0, 0 errors, 156 infos/warnings (same count as T130).
- `flutter build web --no-pub`: exit 0, `Built build\web`.

Verdict: PASS
