# Task 130 — Estimated profit on Assets and margin cards

Status: PASS
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

## Remediation R01 (current instruction)

The first pass is committed. Do not redo it. Fix only these, writing only `lib/exchanges/binance/binance_estimated_pnl.dart`, `lib/features/portfolio/presentation/portfolio_screen.dart`, `lib/features/orders/presentation/orders_screen.dart`, `test/exchanges/binance/binance_estimated_pnl_test.dart`, `test/features/portfolio/portfolio_scope_test.dart` and `test/features/orders/orders_binance_view_test.dart`.

AUD-130-01, false state during a run. `BinanceCostController.run` returns at once when a run is in progress, so the second screen sets `_costFinished` while `view.loading` is true and its symbols are still empty. Rows then show `Chưa tính`, and the Assets summary shows `Chưa đủ dữ liệu giá vốn`, until the run ends. Required: while `view.loading` is true and a symbol has no entry, show nothing, and show no summary. `view.loading` must count as not finished. Entries that already exist keep showing. Add tests: a loading view with empty symbols gives no row and no summary; after loading ends, the states appear.

AUD-130-02, manual refresh reads too much. `_refreshCurrentRead` in `orders_screen.dart` awaits `scopedAccountProvider(scope).future` in its `finally`. That holds `_manualRefreshInFlight` open and creates an account read under `USDⓈ-M`, where none is otherwise needed. Follow the Assets screen: read `.valueOrNull`, start the run only for Binance with filter `ALL` or `MARGIN` when a value exists, and do not await the account. Add a test: pull to refresh under `USDⓈ-M` calls `readAccount` no additional time.

AUD-130-03, missing tests from section 8:
- TEST-130-6: OKX on Assets and Orders shows no estimate text, and `binanceCostStateProvider` and the controller are not built. Override the controller provider so that building it fails the test.
- TEST-130-7: the controller provider fails: total, USDⓈ-M line, balance rows and margin cards still show, with no exception and no estimate text.
- TEST-130-8 on Assets: a row with the longest text, partial coverage plus `chưa cập nhật`, at width 320 and text scale 2.0, with no exception.

Keep every other test and behavior.



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

- `lib/exchanges/binance/binance_estimated_pnl.dart`
- `lib/features/portfolio/presentation/portfolio_screen.dart`
- `lib/features/orders/presentation/orders_screen.dart`
- `lib/features/orders/presentation/widgets/margin_account_card.dart`
- `test/exchanges/binance/binance_estimated_pnl_test.dart`
- `test/features/portfolio/portfolio_scope_test.dart`
- `test/features/orders/orders_binance_view_test.dart`

## 5. Forbidden Scope

Do not read or change protected configuration, `backend/` or Git state. No new dependency, no write route, no file outside the list.

## 6. Executor Contract

1. Compute from `binanceCostStateProvider` and the account snapshot. Mark comes from the account read, with no new price request.
   T129 provides `binanceCostControllerProvider` with `run(AccountSnapshot)`, which is throttled to once per 60 seconds, and `binanceCostStateProvider` with `BinanceCostView`. Symbol keys are `<wallet>:<symbol>`, such as `Spot:BTCUSDT`, `Cross Margin:BTCUSDT`, `Isolated Margin:BTCUSDT`. Put row and summary logic in `binance_estimated_pnl.dart`, free of widgets.
   Which rows: Assets rows for wallets `Spot` and `Cross Margin`; margin cards for cross and isolated. The summary sums Spot, Cross Margin and Isolated Margin once each, in USDT. An asset in two wallets counts per wallet. `Tính trên N/M tài sản` counts holdings with a figure out of holdings that are eligible, excluding USDT.
   Holding and mark: Spot uses `total`; Cross Margin uses `net`; both take mark from `valueUsdt / amount`, and a missing or zero value means no figure. Isolated uses `baseNet` and `indexPrice`.
   State mapping: `available` false shows nothing. No entry after a finished run, or a pair that is not USDT: `Chưa tính`. Before the first run finishes: nothing. `completed` false: `Đang tải lịch sử`, with any figure kept. `stale` true: the figure plus `· chưa cập nhật`. No estimate: `Chưa đủ dữ liệu giá vốn`.
2. Section 6 defines the text. Amounts follow the existing currency and hide-balance behavior.
3. The USDⓈ-M line, total and percentage do not change. An estimate failure never replaces account data.
4. Call `run` once when a screen first has account data after it opens, and on pull to refresh. Never from a poll tick, and never from a listener that fires on every account read. A test proves that account polling makes no additional `run` calls.
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

Attempt: 84bf6def83b94e9eb88806569cfc946f
Dispatch route compliance: UNVERIFIABLE (requested gpt-6.1-terra/medium, explicit).
Parent route inheritance: NO
RED and GREEN executed by the coordinator on the host, RED first (VAL-005): Thirteen mutations were run. Twelve failed the suite. The isolated double-count mutation survived, so the coordinator added a summary test, and it then failed too. GREEN passed. The executor's final attempt returned no valid structured report, so the dispatcher marked it BLOCKED; its changed files were in scope and this verdict rests on coordinator evidence only. Coordinator corrections, test files only: a stream close that hung the run, a viewport of 3000 for the Assets large-text test because the row is off screen and unbuilt at 1200, and the summary test.
Regression and buildability, coordinator-observed: 666 tests pass in the full suite; analyzer 0 errors, 156 warnings and infos; web build passes with the define.
Task buildability gate: PASS
Verdict: PASS
