# Task 132 — Account-wide unrealized profit on Assets

Status: PASS
Agent Role: implementation_executor
Executor Class: E2
Target Model: gpt-6.1-terra
Target Effort: medium
Target Route: gpt-6.1-terra / medium
Routing Policy: EXECUTOR_ROUTING_POLICY.json v2 (OptCodex v1.4.0)
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Plan: `docs/agents/plans/2026-11-13-assets-account-unrealized-pnl.md`
Plan Steps: P02
Decisions: D-004, D-005, D-006, D-007, D-008

## Remediation R01 (current instruction)

The first pass is committed. Do not redo it. Write only `lib/features/portfolio/presentation/portfolio_screen.dart`.

AUD-132-01, the label is not switched. `_buildAssetSummary` receives `combined` but never uses it. The label at `pnlBlock` still chooses on `isBinance` only, so the combined headline shows `Lãi / lỗ chưa thực hiện · USDⓈ-M`. Coordinator GREEN: `Assets account unrealized PnL scenario 0` and `scenario 1` fail with `Found 0 widgets with text "Lãi / lỗ chưa thực hiện"`. The amounts are not reached by the assertions yet. Required: the label is `isBinance && !combined ? 'Lãi / lỗ chưa thực hiện · USDⓈ-M' : 'Lãi / lỗ chưa thực hiện'`. Change nothing else.

Not dispatched. The user granted task-specific coordinator overrides (chat, 2026-11-13, "Cho Claude tự sửa"):
- AUD-132-01: the label condition changed to `isBinance && !combined`, and nothing else.
- AUD-132-02: the plan wrongly listed the T130 expectation `(+10.00%)` in the test now named `headline adds estimates to USD-M …` as preserved. Under D-004 that test expects (100 + 20) ÷ (1200 − 120) = `(+11.11%)`. The coordinator changed that one expectation and the test name, and nothing else.

## 1. Dispatch Compliance

The CCB dispatcher passes `--model gpt-6.1-terra` and `model_reasoning_effort=medium` on your command line, and your prompt states the route. This is the explicit binding. `UNVERIFIABLE` is a valid state; do not stop for it.

Dispatch Route Status: UNVERIFIABLE
Requested Model: gpt-6.1-terra
Requested Effort: medium
Observed Effective Model: unavailable
Observed Effective Effort: unavailable

## 2. Objective

On Binance, the Assets card headline `Lãi / lỗ chưa thực hiện` shows USDⓈ-M plus the estimated Spot and Margin profit, as a percentage of `Vốn gốc`.

Done when: tests prove W6, W7 and W8 from the plan, and every existing test in `portfolio_scope_test.dart` still passes unchanged.

## 3. Preconditions

Predecessors: T131 = PASS (commit c4adb6f). Clean checkout.

## 4. Allowed Scope

Exact write list. Read access covers any non-protected source or test.

- `lib/features/portfolio/presentation/portfolio_screen.dart`
- `test/features/portfolio/portfolio_scope_test.dart`

## 5. Forbidden Scope

- Do not read or change protected configuration, `backend/` or Git state.
- Do not change `binance_estimated_pnl.dart`, `portfolio_details_screen.dart`, OKX behavior or the summary line text.
- No new dependency. No file outside the list.

## 6. Executor Contract

1. In `_buildPortfolioView` (the method that computes `totalUnrealizedPnl`, `summary`, `baseEquity`, `ratioBase`, `pnlRatio`), let `combined = summary != null && summary.covered > 0`. Do not add an exchange check (D-007). The estimate source decides, and today `summary` exists only where a cost view exists.
   - When `combined`: headline amount = `totalUnrealizedPnl + summary.profit`. Headline percentage = headline amount ÷ `baseEquity` × 100 if `baseEquity > 0`, otherwise 0. `baseEquity` stays as T131 left it: total − USDⓈ-M uPnL − summary.profit.
   - Otherwise: amount and percentage exactly as today (`totalUnrealizedPnl`, `pnlRatio` with `ratioBase`).
2. `_buildAssetSummary` gets the combined flag, or the label, through a new parameter. The Binance label is `Lãi / lỗ chưa thực hiện` when combined and `Lãi / lỗ chưa thực hiện · USDⓈ-M` otherwise. The OKX label is unchanged.
3. The amount color, the arrow icon and the percentage color use the values from step 1 through the existing `resolvePnlColor`. Hidden balances behave as today.
4. Do not change the `Ước tính Spot · Margin` line, `Tính trên N/M tài sản`, or `Vốn gốc`.

## 7. External Configuration / Environment Actions

None.

## 8. Tests

Add these to `test/features/portfolio/portfolio_scope_test.dart`, following the T131 test `Assets own capital and summary withSpot=…`: same overrides and `StreamController<BinanceCostView>`, and no `await views.close()` at the end (AUD-131-01).

- TEST-132-1 (W6): total `29.5`. The isolated row from T131 W1: `baseNet 1`, `indexPrice 80`, `quoteNet -50.5`, `quoteInterest 0.5`, cost state quantity 1, cost 100, margin. No USDⓈ-M balance. After the view is no longer loading: `Lãi / lỗ chưa thực hiện` is found, `Lãi / lỗ chưa thực hiện · USDⓈ-M` is not found, `-$20.50` is shown in the headline, and `(-41.00%)` and `$50.00` are found.
- TEST-132-2 (W7): as W6, plus `AssetBalance(wallet: 'USD-M', asset: 'USDT', total: '100', valueUsdt: '100', unrealizedPnl: '5')`, and total `129.5`. Expect `-$15.50`, `(-10.69%)` and `$145.00`.
- TEST-132-3 (W8): W7 while the view has `loading: true`. Expect `Lãi / lỗ chưa thực hiện · USDⓈ-M`, `+$5.00`, `(+5.26%)` and `$124.50`.

- TEST-132-4 (multi-exchange): the existing OKX cases in this file (labels `Lãi / lỗ chưa thực hiện` and `Unrealized PnL`, and their percentages) pass unchanged. No cost provider is built for OKX.

If the exact currency strings differ from the formatter output, keep the numbers and report the formatter strings you used. Do not change the numbers.

## 9. Mandatory Verification

### RED — RED-132
Scenario: TEST-132-1 and TEST-132-2 on the code before the change.
Command: `flutter test --no-pub test/features/portfolio/portfolio_scope_test.dart`
Expected: both fail. The label is `· USDⓈ-M`, and the headline shows 0.00 for W6 and +5.00 for W7.
Status: PENDING

### GREEN — GREEN-132
Scenario: the same command after the change, then V3 `flutter test --no-pub test/features/portfolio`.
Expected: all pass.
Status: PENDING

Verification ceiling: V3 (`test/features/portfolio`).

### Verification environment

The executor sandbox cannot run `flutter test` or compile. Write the complete code and tests. Report `red` and `green` as `NOT_RUN` with the tests named in RED then GREEN order, set `buildability` to `BLOCKED` with that reason, and set `status` to `COMPLETED`. The coordinator runs RED, GREEN and the build on the host.

### Task Buildability Gate

Required: YES
Exact secret-free build command: `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings && flutter build web --no-pub`
Result: PENDING

## 10. Stop Conditions

Return `BLOCKED` if the change needs a file outside the list, or any decision about the details screen or OKX.

## 11. Coordinator Audit

Attempts: 7fe49336363d4379b3e8d5b41b1ce428 was BLOCKED, with no change, because the dispatch section said PENDING; the contract was fixed in 91b25a9. 18503a31b81a40a18f419efb5e1f80af was REWORK (AUD-132-01). Coordinator overrides AUD-132-01 and AUD-132-02 are listed above.
Scope: PASS. Changed files: `portfolio_screen.dart` and `portfolio_scope_test.dart` only.
Contract: PASS.
- `combined = summary != null && summary.covered > 0`. No new exchange check; the summary itself exists only where a cost view exists, so OKX falls back.
- Headline = `totalUnrealizedPnl + summary.profit`. Percentage = headline ÷ `baseEquity`.
- The fallback keeps the USDⓈ-M values and label.

RED (host, HEAD code with the new tests): scenarios 0 and 1 failed with `Found 0 widgets with text "Lãi / lỗ chưa thực hiện"`. Scenario 2, the fallback, passed as expected.
GREEN (host, after the overrides): `flutter test --no-pub test/features/portfolio`: 40 passed, exit 0. This includes W6 `-$20.50` `(-41.00%)` `$50.00`, W7 `-$15.50` `(-10.69%)` `$145.00`, W8 `+$5.00` `(+5.26%)` `$124.50`, and the OKX cases unchanged.
Dispatch route compliance: UNVERIFIABLE (requested gpt-6.1-terra / medium, explicit). Parent route inheritance: NO.
Task buildability gate: PASS.
- `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings`: exit 0, 0 errors, 156 issues (unchanged).
- `flutter build web --no-pub`: exit 0.

Verdict: PASS
