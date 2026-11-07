# Task 130 — Estimated profit on Assets and margin cards

Status: PENDING
Agent Role: implementation_executor
Executor Class: E2
Target Model: gpt-6.1-terra
Target Effort: medium
Target Route: gpt-6.1-terra / medium
Routing Policy: EXECUTOR_ROUTING_POLICY.json v2 (OptCodex v1.4.0)
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Specification: `docs/agents/specs/2026-11-07-binance-estimated-pnl-design.md`
Plan: `docs/agents/plans/2026-11-07-binance-estimated-pnl.md`

## 1. Dispatch Compliance

The dispatcher passes `--model` and `model_reasoning_effort` on your command line, and your prompt states the route. `UNVERIFIABLE` is a valid state; do not stop for it.

Dispatch Route Status: UNVERIFIABLE
Requested Model: gpt-6.1-terra
Requested Effort: medium

## 2. Objective

Assets rows, a separate summary and margin cards show estimated profit as in section 6 of the specification.

Done when: Tests prove each display state, separation from USDⓈ-M, hiding and OKX unchanged.

Complete the work in this run; a long run is normal. Ending without file changes is a failed attempt.

## 3. Preconditions

Predecessors: T129 = PASS.

## 4. Allowed Scope

Exact write list. Read access covers all non-protected source and tests.

- `lib/features/portfolio/presentation/portfolio_screen.dart`
- `lib/features/orders/presentation/orders_screen.dart`
- `lib/features/orders/presentation/widgets/margin_account_card.dart`
- `test/features/portfolio/portfolio_scope_test.dart`
- `test/features/orders/orders_binance_view_test.dart`

## 5. Forbidden Scope

Do not read or change protected configuration, `backend/` or Git state. No new dependency, no write route, no file outside the list.

## 6. Executor Contract

1. Compute from `binanceCostStateProvider` and the account snapshot. Mark comes from the account read, with no new price request.
2. Section 6 defines the text. Amounts follow the existing currency and hide-balance behavior.
3. The USDⓈ-M line, total and percentage do not change. An estimate failure never replaces account data.
4. Add a run trigger on screen open and on pull to refresh only.
5. Long text must not overflow at width 320 with text scale 2.0.
6. An estimate with `ratio` below 0.01 shows `Chưa đủ dữ liệu giá vốn`, because floating-point or real dust would read as `0%`.
7. Margin interest argument: cross uses the row's `interest`. Isolated uses `baseInterest + quoteInterest / mark`. Holding is the margin net asset, signed. Isolated holding is `baseNet`.

Mechanism details are yours if they satisfy these and the tests; report what you chose. Stop only for a conflict about product behavior.

## 7. External Configuration / Environment Actions

Planned action: user-owned nginx change in the plan, U3. Blocks this task: NO.

## 8. Tests

- TEST-130-1: full coverage row and margin card text.
- TEST-130-2: partial coverage text.
- TEST-130-3: insufficient data, `Chưa tính`, `Đang tải lịch sử`.
- TEST-130-4: summary is separate; USDⓈ-M figures are unchanged.
- TEST-130-5: hidden balance hides estimates.
- TEST-130-6: OKX shows none and makes no such read.
- TEST-130-7: history failure leaves total and rows.
- TEST-130-8: no overflow at large text.

## 9. Mandatory Verification

### RED — RED-130
Scenario: Summary added into the USDⓈ-M figure by mutation.
Expected: TEST-130-4 fails.
Status: PENDING

### GREEN — GREEN-130
Scenario: All tests.
Expected: Pass.
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
