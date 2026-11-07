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

## Remediation R02 (current instruction)

R01 is committed. Its new test `Margin account state: error` fails on the host, and audit found more. Fix only these, writing only `lib/features/orders/presentation/orders_screen.dart` and `test/features/orders/orders_binance_view_test.dart`.

AUD-126-06, crash. `accountAsync?.value` rethrows when the account read is an error with no previous value, so `OrdersScreen` throws during build: `Exception: failure` at `orders_screen.dart:384`. Use `valueOrNull`. The expected view is `AccountStateView`. Add a test: filter `ALL`, positions present, account read fails: positions still show and nothing throws.

AUD-126-07, polling after a credential failure. On the Margin chip `readPositions` returns `[]`, so the 5-second timer checks a positions read that can never fail and keeps re-reading the account with a rejected key. Other tabs stop in this case. Required, in both the timer and `_refreshCurrentRead`, for Binance with filter `ALL` or `MARGIN` when the positions read has data:

- Account read loading: skip this tick.
- Timer only: `isTerminalAccountFailure` on the account read's error: skip, the same as the existing positions check.
- A non-terminal account error keeps being retried.

Do not create an account read for `SWAP`, `SPOT`, or OKX. Tests on the Margin chip with no positions, using a fake that counts `readAccount` calls and whose `classify` returns the credential kind for its error: after pumping past 11 seconds the count stays 1. With a non-terminal error the count grows.

AUD-126-08, behavior changed beyond scope. Remove `_AlwaysScrollableBehavior` and the `ScrollConfiguration` wrapper: it applies to every exchange and drops platform scroll physics, such as the iOS bounce, and the requirement was that OKX stays unchanged. Restore the original `loading` and `error` widgets of the positions `.when`. Use `_scrollableState` only for the new Binance account states. `ResponsiveOrderGrid` and `_buildEmptyState` already scroll.

AUD-126-09, overflow risk. `_scrollableState` uses a fixed `SizedBox(height: constraints.maxHeight)`, which overflows when the content is taller at large text. Use `ConstrainedBox(constraints: BoxConstraints(minHeight: constraints.maxHeight), child: Center(child: child))`. Add a test: account error state at width 320, height 480, text scale 2.0, no exception.

Keep every other test and all R01 behavior.

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
