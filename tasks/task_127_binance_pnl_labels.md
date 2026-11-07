# Task 127 — Binance profit labels and percentage base

Status: PENDING
Agent Role: implementation_executor
Executor Class: E2
Target Model: gpt-6.1-terra
Target Effort: medium
Target Route: gpt-6.1-terra / medium
Routing Policy: EXECUTOR_ROUTING_POLICY.json v2 (OptCodex v1.4.0)
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Specification: `docs/agents/specs/2026-11-07-binance-web-proxy-design.md`
Plan: `docs/agents/plans/2026-11-07-binance-web-proxy.md`

## 1. Dispatch Compliance

The dispatcher passes `--model` and `model_reasoning_effort` on your command line, and your prompt states the route. `UNVERIFIABLE` is a valid state; do not stop for it.

Dispatch Route Status: UNVERIFIABLE
Requested Model: gpt-6.1-terra
Requested Effort: medium

## 2. Objective

Binance screens stop implying that interest is profit and that the profit figure covers Spot and Margin. The percentage is computed against USDⓈ-M equity only.

Done when: Tests prove the labels and the worked example below, and OKX output is unchanged.

Complete the work in this run; a long run is normal. Ending without file changes is a failed attempt.

## 3. Preconditions

Predecessors: T126 = PASS. User instruction: "Sửa nhãn, lập kế hoạch PnL".

## 4. Allowed Scope

Exact write list. Read access covers all non-protected source and tests.

- `lib/features/orders/presentation/widgets/margin_account_card.dart`
- `lib/features/portfolio/presentation/portfolio_screen.dart`
- `lib/features/portfolio/presentation/portfolio_details_screen.dart`
- `test/features/orders/orders_binance_view_test.dart`
- `test/features/portfolio/portfolio_scope_test.dart`

## 5. Forbidden Scope

Do not read or change protected configuration, `backend/` or Git state. No new dependency, no new request, no file outside the list.

## 6. Executor Contract

1. `margin_account_card.dart`: `Lãi` becomes `Lãi vay` in the cross row and both isolated rows.
2. On Binance only, the profit label becomes `Lãi / lỗ chưa thực hiện · USDⓈ-M` in `portfolio_screen.dart` and `Unrealized PnL · USDⓈ-M` in `portfolio_details_screen.dart`.
3. On Binance only, the percentage is `pnl / (usdmEquity - pnl)`, where `usdmEquity` is the sum of `valueUsdt` for balances with wallet `USD-M`. When that base is not positive, keep each screen's existing no-ratio behavior: `0.0` on Home, `null` on details.
4. Keep the displayed total and principal as they are today: the principal stays total minus profit. OKX labels, percentage and principal do not change.

Worked example: USD-M balance `valueUsdt` 1100 and `unrealizedPnl` 100, Spot balance `valueUsdt` 900, total 2000. The percentage is `+10.00%`, not `+5.26%`. Principal is 1900.

Mechanism details are yours if they satisfy these and the tests; report what you chose. Stop only for a conflict about product behavior.

## 7. External Configuration / Environment Actions

None.

## 8. Tests

- TEST-127-1: Binance worked example on Home and details: `+10.00%`, the USDⓈ-M label, principal unchanged.
- TEST-127-2: Binance with no USD-M balance: no division error and the existing no-ratio display.
- TEST-127-3: OKX on both screens: original labels and the existing percentage.
- TEST-127-4: margin card shows `Lãi vay` for cross and isolated rows, and no `Lãi:` text.

## 9. Mandatory Verification

### RED — RED-127
Scenario: Binance worked example against the previous denominator.
Expected: Fails with `+5.26%`.
Status: PENDING

### GREEN — GREEN-127
Scenario: Same example after the change.
Expected: `+10.00%`.
Status: PENDING

Verification ceiling: V3: `test/features/portfolio`, `test/features/orders`.

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
