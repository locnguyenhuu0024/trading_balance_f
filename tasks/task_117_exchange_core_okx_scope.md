# Task 117 — Exchange core and OKX behind it

Status: PENDING
Agent Role: implementation_executor
Executor Class: E4
Target Model: gpt-6.1-terra
Target Effort: xhigh
Target Route: gpt-6.1-terra / xhigh
Routing Policy: EXECUTOR_ROUTING_POLICY.json v2 (OptCodex v1.4.0)
Route Rationale: Concurrency and interdependent invariants: late responses, cancellation, per-exchange lanes, generation fence, plus migrating large read screens.
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Specification: `docs/agents/specs/2026-11-07-multi-platform-view-only-design.md`
Plan: `docs/agents/plans/2026-11-07-multi-platform-view-only.md`
Plan Steps: P02
Requirements: REQ-004, REQ-005, REQ-012
Acceptance Criteria: AC-004, AC-005, AC-012

## 1. Dispatch Compliance

Before this task may enter `EXECUTING`, the coordinator must spawn an `implementation_executor` with both Target Model and Target Effort explicitly supplied. Omitting either or inheriting a route is prohibited. The coordinator has done this: the dispatcher passes `--model` and `model_reasoning_effort` on your command line, and your prompt states the route. You cannot observe more than that from inside the run, and `UNVERIFIABLE` is a valid state. Do not stop for it; start the task.

Dispatch Route Status: UNVERIFIABLE (explicitly bound by `scripts/ccb/dispatch.py`, runtime does not expose the effective route)
Requested Model: gpt-6.1-terra
Requested Effort: xhigh
Observed Effective Model: unavailable
Observed Effective Effort: unavailable

## 2. Objective

Portfolio and Orders read through the neutral exchange contract and scope providers, with OKX as the only registered exchange and no visible behavior change.

Done when: Those screens render through a registered adapter, a fake second adapter proves scope isolation, and existing OKX tests pass.

## 3. Preconditions

Predecessors: T116 = PASS. Decisions: D-001, D-004, D-008.
Required state: clean checkout on branch `codex/multi-platform-view-only`. Plan revision 2 approved.

## 4. Allowed Scope

Exact write list (new files use exactly these names). Read access covers all non-protected source and tests.

- `lib/core/exchange/exchange_models.dart`
- `lib/core/exchange/exchange_adapter.dart`
- `lib/core/exchange/exchange_registry.dart`
- `lib/core/exchange/exchange_scope.dart`
- `lib/core/exchange/scoped_read.dart`
- `lib/exchanges/okx/okx_adapter.dart`
- `lib/core/network/okx_read_scope.dart`
- `lib/features/portfolio/presentation/portfolio_screen.dart`
- `lib/features/portfolio/presentation/portfolio_details_screen.dart`
- `lib/features/portfolio/presentation/providers/portfolio_provider.dart`
- `lib/features/portfolio/presentation/widgets/portfolio_currency_amount.dart`
- `lib/features/orders/presentation/orders_screen.dart`
- `lib/features/orders/presentation/providers/order_provider.dart`
- `lib/features/orders/presentation/widgets/order_notional.dart`
- `lib/features/orders/presentation/widgets/order_filter_controls.dart`
- `lib/features/orders/presentation/widgets/responsive_order_grid.dart`
- `lib/main.dart`
- `lib/core/security/secure_storage_helper.dart`
- `lib/core/widgets/app_startup.dart`
- `test/core/exchange/exchange_models_test.dart`
- `test/core/exchange/exchange_scope_test.dart`
- `test/core/exchange/okx_adapter_test.dart`
- `test/support/fake_exchange_adapter.dart`
- `test/features/portfolio/portfolio_scope_test.dart`
- `test/features/orders/orders_scope_test.dart`
- `test/features/portfolio/monochrome_portfolio_preview_test.dart`
- `test/features/portfolio/portfolio_currency_amount_test.dart`
- `test/features/portfolio/portfolio_dual_currency_screen_test.dart`
- `test/features/portfolio/portfolio_loading_test.dart`
- `test/features/orders/order_filter_controls_test.dart`
- `test/features/orders/order_provider_defaults_test.dart`
- `test/features/orders/orders_screen_refresh_test.dart`
- `test/features/orders/position_actions_test.dart`
- `test/features/orders/order_cancellation_flow_test.dart`
- `test/features/orders/backend_position_actions_dialog_test.dart`
- `test/features/orders/presentation/order_timezone_test.dart`
- `test/features/orders/presentation/orders_screen_history_layout_test.dart`
- `test/features/orders/presentation/orders_screen_mobile_layout_test.dart`
- `test/features/orders/presentation/orders_screen_notional_test.dart`
- `test/features/orders/presentation/orders_screen_position_layout_test.dart`
- `test/features/orders/presentation/orders_screen_price_formatting_test.dart`
- `test/features/orders/presentation/widgets/order_notional_test.dart`
- `test/core/backend_features_test.dart`
- `test/core/widgets/app_startup_test.dart`
- `test/widget_test.dart`

## 5. Forbidden Scope

Do not:
- read, search, parse, summarize or content-diff protected configuration, including `pubspec.yaml`, `pubspec.lock`, `analysis_options.yaml` and native project configuration;
- create, modify, regenerate or delete protected files, or add or remove dependencies;
- touch `backend/` or any git history, staging or branches;
- add any Binance or OKX write route;
- make opportunistic refactors or exceed the surface above.

If required work exceeds Allowed Scope, return `BLOCKED`.

## 6. Executor Contract

Design is fixed; follow it.

1. `exchange_models.dart`: plain Dart types from spec section 6, with numerics as verbatim `String?`. Required fields so existing OKX screens keep rendering:
   - `AssetBalance`: wallet, asset, total, available, frozen, borrowed, interest, net, unrealizedPnl, valueUsdt (`coin.ccy`, `eq`, `upl`, `eqUsd`).
   - `ExchangePosition`: key, productLabel, side, direction, size, entry, mark, liquidation, leverage, marginMode, unrealizedPnl, unrealizedPnlRatio, notional, positionId, positionCurrency, marginCurrency, `Object? native`.
   - `ExchangeOrder`: id, key, productLabel, type, side, price, quantity, filled, average, notional, filledNotional, leverage, state, createdAtMs, `Object? native`.
   If a screen needs one more existing display value, add it as a nullable text field by the same rule and list it in your report. That is not a design decision; do not stop for it.
2. `exchange_adapter.dart`: `ExchangeAdapter` with `id`, `capabilities`, `readAccount(Ref, ExchangeScope)`, `readPositions(Ref, ExchangeScope)`, `readOrders(Ref, ExchangeScope)`, plus `invalidateAccount`, `invalidatePositions`, `invalidateOrders`, each taking `void Function(ProviderOrFamily) invalidate`, and `classify(Object error)`.
3. `exchange_registry.dart`: `exchangeRegistryProvider`, a `Provider<List<ExchangeRegistration>>` holding profile and adapter, defaulting to OKX only. Tests override it with a fake exchange.
4. `exchange_scope.dart`: `selectedConnectionIdProvider` (`StateProvider<String>`, overridden at startup, unknown value falls back to `okx-default`), `exchangeScopeProvider`, `exchangeRequestCoordinatorProvider` and `exchangeReadGateProvider` as `Provider.family` on `ExchangeId`. For OKX these return the existing `requestCoordinatorProvider` and `okxDirectReadGateProvider`; other exchanges get their own instance. Do not change `RequestCoordinator` or `ForegroundReadGate`.
5. `scoped_read.dart`: `runPrivateRead` taking the adapter's classifier; `runOkxPrivateRead` stays as a thin wrapper. Add `scopedAccountProvider`, `scopedPositionsProvider`, `scopedOrdersProvider` as `FutureProvider.autoDispose.family` keyed by `ExchangeScope`, each delegating to the adapter from the registry.
6. `okx_adapter.dart`: `readAccount` does `ref.watch(portfolioFutureProvider.future)` and maps; likewise `positionsFutureProvider` and `ordersFutureProvider`. Keep those three OKX providers and their names, so existing test overrides stay valid and OKX reads keep their fences. Map field by field and put the freezed record in `native`. Map OKX values as the existing models give them, including `@Default('0')` values: per spec INV-003 and VAL-001 this existing behavior is preserved, and the OKX model files are not changed.
7. Screens watch the scoped family with `ref.watch(exchangeScopeProvider)`. Refresh goes through the adapter's invalidate methods. Never use `.value` from a former scope: a family key change gives a new element, which is why the family is required.
8. `PortfolioScreen` and `PortfolioDetailsScreen` render from `AccountSnapshot`. The displayed OKX total stays as `PortfolioScreen` computes it today, from asset balances and live prices; do not switch it to `totalEq`. Live price valuation stays OKX-only and is reached only when scope is OKX.
9. `OrdersScreen` cards render from neutral types. Only gate-true backend widgets cast `native` to `OkxPosition` or `OkxOrder`.
10. Reset filters structurally: `orderFilterProvider` and `orderTabProvider` initial builders `ref.watch(selectedConnectionIdProvider)`.
11. Add `getSelectedConnectionId` and `saveSelectedConnectionId` to `SecureStorageHelper` and to `WebStorageHelper` in `main.dart`, key `SELECTED_CONNECTION_ID`; load at startup in the same way as other settings, with failure falling back to `okx-default`. No UI for selecting yet.
12. Add the fake adapter in `test/support/fake_exchange_adapter.dart` and the tests below. Change existing tests only for wiring; do not weaken assertions.

Required invariants and edges: INV-001, INV-002, INV-003, INV-004; EDGE-001, EDGE-003.
Apply reuse-first, minimal complete changes. Do not invent product semantics. If the contract is insufficient, return `BLOCKED`.

## 7. External Configuration / Environment Actions

Planned action: none.
Blocks verification until user applies: NO

## 8. Tests

- TEST-117-1: late response dropped.
- TEST-117-2: per-exchange lane independence.
- TEST-117-3: credential rotation drops in-flight result under the wrapper.
- TEST-117-4: fake adapter renders through both screens.

## 9. Mandatory Verification

### RED — RED-117a/b/c
Scenario: (a) OKX balance read pending, switch to fake exchange, resolve OKX late. (b) Fake exchange 429 with OKX idle. (c) Filter set to SWAP, then switch.
Command/method: `rtk flutter test --no-pub <file> --plain-name '<name>'`
Expected: (a) Amount never appears and token is cancelled. (b) OKX lane still accepts a read. (c) Filter is ALL and tab is positions.
Actual: PENDING
Status: PENDING

### GREEN — GREEN-117
Scenario: OKX adapter drives the existing Portfolio and Orders tests; a fake exchange shows its own balances after switching.
Command/method: `rtk flutter test --no-pub <file> --plain-name '<name>'`
Expected: Existing tests pass unchanged except wiring; fake data appears only under its own scope.
Actual: PENDING
Status: PENDING

Run RED before GREEN. Verification ceiling: V3: `test/core/network`, `test/core/exchange`, `test/features/portfolio`, `test/features/orders`.
Escalate only if: a shared provider or fixture used outside this set changes.

### Verification environment

Confirmed by the coordinator: this sandbox cannot run `flutter test`, because the test runner cannot bind 127.0.0.1, and the default SDK cache is not writable. Do not spend time on this and do not stop for it.

- Write the complete code and tests. Do not run `flutter test`.
- For a compile check, use `env HOME=/private/tmp/claude-501/-Users-locnguyen--claude-spares-spare-1YiVQu/74faedd6-f84d-41fb-aa01-a0288d74204a/scratchpad/flutter-home PUB_CACHE=/Users/locnguyen/.pub-cache /private/tmp/claude-501/-Users-locnguyen--claude-spares-spare-1YiVQu/74faedd6-f84d-41fb-aa01-a0288d74204a/scratchpad/flutter-sdk/bin/flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings`, and `env HOME=/private/tmp/claude-501/-Users-locnguyen--claude-spares-spare-1YiVQu/74faedd6-f84d-41fb-aa01-a0288d74204a/scratchpad/flutter-home PUB_CACHE=/Users/locnguyen/.pub-cache /private/tmp/claude-501/-Users-locnguyen--claude-spares-spare-1YiVQu/74faedd6-f84d-41fb-aa01-a0288d74204a/scratchpad/flutter-sdk/bin/flutter build web --no-pub` for buildability.
- In your report set `red` and `green` to `NOT_RUN`, naming the exact tests and the order RED then GREEN. Set `status` to `COMPLETED`.
- The coordinator executes RED then GREEN on the host during audit and returns any failure as a bounded remediation.

### Conflict rule

If a sentence in this contract conflicts with how OKX behaves today, REQ-012 wins: keep the existing OKX behavior, implement the rest, and name the conflict in your summary. Stop only if the conflict affects something other than OKX preservation.

### Task Buildability Gate

Required: YES
Affected canonical build unit: Flutter app `lib/` and `test/`
Exact secret-free build command: `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings && flutter build web --no-pub`
Executed after the last task-local change: PENDING
Result: PENDING

### External Verification

Required: NO for this task. The program's user-run live check follows the final audit.

## 10. Stop Conditions

Return `BLOCKED` when repository evidence contradicts this contract, a design decision is missing, a dependency appears necessary, scope is exceeded, or verification is unavailable. Report evidence, affected IDs, and the coordinator decision needed.

## 11. Execution Ledger

- [ ] confirm route binding
- [ ] inspect referenced symbols
- [ ] implement assigned step
- [ ] add or update tests
- [ ] execute formal RED, then GREEN
- [ ] run buildability gate after last change
- [ ] return compact executor report
- [ ] confirm no protected content read or modified

## 12. Coordinator Audit

Verdict: PENDING
