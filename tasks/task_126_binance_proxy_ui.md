# Task 126 — UI follows Spot and Margin availability; Margin chip filter

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

## Remediation R01 (current instruction)

The first pass is committed. Items 1 and 2 of the contract in section 6 are done; do not redo them. Coordinator audit found these defects. Fix only these, writing only:

- `lib/features/orders/presentation/orders_screen.dart`
- `test/features/orders/orders_binance_view_test.dart`
- `test/exchanges/binance/binance_adapter_test.dart`

AUD-126-01, false empty state. On the Vị thế tab for Binance with filter `ALL` or `MARGIN`, margin rows come from `scopedAccountProvider`, read with `.value`. When there are no positions and no rows, the screen shows `Chưa có vị thế trên ...` even if that account read is still loading, failed, or lost a margin wallet. The Margin chip always has no positions, so a proxy failure there reads as "no positions". Required rule, for Binance with filter `ALL` or `MARGIN` when positions are empty and rows are empty:

- Account read loading with no value: the same progress indicator the tab uses.
- Account read failed: `AccountStateView.fromError` as the positions branch does, with `onRetry: _refreshCurrentRead`.
- Account data where `walletResults` marks `Cross Margin` or `Isolated Margin` unavailable: `PartialAccountNotice`, not the empty state.
- Otherwise: the existing empty state.

AUD-126-02, silent omission. For Binance with filter `ALL` or `MARGIN`, when rows or positions exist and a margin wallet is unavailable, also show `PartialAccountNotice` on this tab. Pull to refresh must keep working in every state above. OKX, `SWAP` and `SPOT` output is unchanged.

AUD-126-03, unreliable test. `Binance positions and filters on web proxy=true` fails on the host. The screen is correct: a temporary probe with timed pumps showed the cards under Margin. Returning to `Tất cả` re-reads the account. Replace the bare double `pump()` after each chip tap with a small helper that pumps a few times with a short duration. Keep every expectation.

AUD-126-04, lost coverage. The first pass replaced the `web=false` case. Restore a native case with no proxy: Spot and Margin chips present. Cover three states: native, web without proxy, web with proxy.

AUD-126-05, adapter coverage. `_Fake` reimplements the filter, so the real adapter is covered only for `MARGIN`. In `binance_adapter_test.dart`, override `binanceReaderProvider` to throw a sentinel and prove `ALL` and `SWAP` reach the reader, while `MARGIN` and `SPOT` return empty without it.

New tests in `orders_binance_view_test.dart`, all on the Margin chip with no positions:
- account never completes: progress indicator, no empty-state text;
- account fails: no empty-state text, error view present;
- `Cross Margin` unavailable: `Không thể tải ví Margin chéo`, no empty-state text;
- all wallets available and no rows: the empty-state text.

## 1. Dispatch Compliance

The dispatcher passes `--model` and `model_reasoning_effort` on your command line, and your prompt states the route. `UNVERIFIABLE` is a valid state; do not stop for it.

Dispatch Route Status: UNVERIFIABLE
Requested Model: gpt-6.1-terra
Requested Effort: medium

## 2. Objective

Product line, chips and notices follow availability, and the Margin chip stops listing USD-M positions.

Done when: Tests prove both states on web and the chip filter.

Complete the work in this run; a long run is normal. Ending without file changes is a failed attempt.

## 3. Preconditions

Predecessors: T125 = PASS.

## 4. Allowed Scope

Exact write list. Read access covers all non-protected source and tests.

- `lib/core/widgets/scope_bar.dart`
- `lib/core/widgets/account_state_view.dart`
- `lib/features/connections/connections_screen.dart`
- `lib/features/connections/scope_picker.dart`
- `lib/features/orders/presentation/orders_screen.dart`
- `lib/features/portfolio/presentation/portfolio_screen.dart`
- `lib/features/portfolio/presentation/portfolio_details_screen.dart`
- `lib/exchanges/binance/binance_adapter.dart`
- `test/features/orders/orders_binance_view_test.dart`
- `test/features/connections/account_state_test.dart`
- `test/features/connections/scope_bar_test.dart`
- `test/features/connections/connections_screen_test.dart`
- `test/exchanges/binance/binance_adapter_test.dart`

## 5. Forbidden Scope

Do not read or change protected configuration, `backend/` or Git state. No new dependency, no write route, no file outside the list.

## 6. Executor Contract

1. Replace `kIsWeb` and `binanceIsWebProvider` gates for Spot and Margin with `binanceSpotMarginAvailableProvider`: product line `USDⓈ-M · Spot · Margin` or `USDⓈ-M`; filter chips; the `Spot và Margin chỉ có trên ứng dụng` notice.
2. `BinanceAdapter.readPositions` watches `orderFilterProvider`: `ALL` and `SWAP` read USD-M; `MARGIN` returns empty, so only margin cards show; `SPOT` keeps the existing message. OKX is unchanged.

Mechanism details are yours if they satisfy these and the tests; report what you chose. Stop only for a conflict about product behavior.

## 7. External Configuration / Environment Actions

Planned action: user-owned nginx location and build flag, in `docs/deployment/binance-read-proxy.md`. Blocks this task: NO.

## 8. Tests

- TEST-126-1: web with proxy shows Spot and Margin chips, the full product line and no notice.
- TEST-126-2: web without proxy shows the existing reduced state.
- TEST-126-3: Margin chip shows margin cards and no USD-M position; `Tất cả` shows both; `USDⓈ-M` shows positions only.

## 9. Mandatory Verification

### RED — RED-126
Scenario: Web without proxy, and the Margin chip with USD-M positions present.
Expected: Reduced chips and notice; no USD-M card under Margin.
Status: PENDING

### GREEN — GREEN-126
Scenario: Web with proxy.
Expected: Full chips and product line, no notice.
Status: PENDING

Verification ceiling: V3: `test/features/orders`, `test/features/connections`, `test/exchanges/binance`.

### Verification environment

Confirmed by the coordinator: this sandbox cannot run `flutter test`, because the test runner cannot bind 127.0.0.1, and the default SDK cache is not writable. Do not spend time on this and do not stop for it.

- Write the complete code and tests. Do not run `flutter test`.
- Compile checks are not available in the sandbox; the coordinator runs them on the host. Set `buildability` to `BLOCKED` with that reason and `status` to `COMPLETED`.
- In your report set `red` and `green` to `NOT_RUN`, naming the exact tests and the order RED then GREEN. Set `status` to `COMPLETED`.
- The coordinator executes RED then GREEN on the host during audit and returns any failure as a bounded remediation.

### Conflict rule

If a sentence in this contract conflicts with how OKX behaves today, REQ-012 wins: keep the existing OKX behavior, implement the rest, and name the conflict in your summary. Stop only if the conflict affects something other than OKX preservation.

### Task Buildability Gate

Required: YES
Exact secret-free build command: `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings && flutter build web --no-pub`
Result: PENDING

## 10. Stop Conditions

Return `BLOCKED` if the fix needs a file outside the list.

## 11. Coordinator Audit

Verdict: PENDING
