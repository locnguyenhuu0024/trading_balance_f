# Task 132 — Account-wide unrealized profit on Assets

Status: READY
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

## 1. Dispatch Compliance

Dispatch Route Status: PENDING
Requested Model: PENDING
Requested Effort: PENDING
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

Verdict: PENDING
