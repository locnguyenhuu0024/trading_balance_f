# Task 118 — Analysis screens and Binance public market

Status: PENDING
Agent Role: implementation_executor
Executor Class: E3
Target Model: gpt-6.1-terra
Target Effort: high
Target Route: gpt-6.1-terra / high
Routing Policy: EXECUTOR_ROUTING_POLICY.json v2 (OptCodex v1.4.0)
Route Rationale: Multi-module integration across three analysis features with an established adapter contract.
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Specification: `docs/agents/specs/2026-11-07-multi-platform-view-only-design.md`
Plan: `docs/agents/plans/2026-11-07-multi-platform-view-only.md`
Plan Steps: P03
Requirements: REQ-008
Acceptance Criteria: AC-008

## 1. Dispatch Compliance

Before this task may enter `EXECUTING`, the coordinator must spawn an `implementation_executor` with both Target Model and Target Effort explicitly supplied. Omitting either or inheriting a route is prohibited. The coordinator has done this: the dispatcher passes `--model` and `model_reasoning_effort` on your command line, and your prompt states the route. You cannot observe more than that from inside the run, and `UNVERIFIABLE` is a valid state. Do not stop for it; start the task.

Dispatch Route Status: UNVERIFIABLE (explicitly bound by `scripts/ccb/dispatch.py`, runtime does not expose the effective route)
Requested Model: gpt-6.1-terra
Requested Effort: high
Observed Effective Model: unavailable
Observed Effective Effort: unavailable

## Stage instruction (current)

This task runs in stages because long runs have ended early. Stages 1 to 3 are committed: Market and BMAG follow the selected exchange.

**Current stage 4 of 4, do only these two things:**

1. BMAG audit finding AUD-118-01: `fractal_screen.dart` uses `skipLoadingOnReload: true` on `fractalDataProvider`, and that provider rebuilds in place on a scope change, so the former exchange's fractal data stays visible while the new read loads. Key `fractalDataProvider` by `ExchangeScope` as a family, so a switch shows loading and never former data. Keep the same-scope reload behavior. Add a test: with Binance selected after OKX and the new read pending, no OKX value is visible.
2. The Support/Resistance parts of steps 5, 6 and 7 of section 6: `supportResistanceMarketRepositoryProvider` returns the selected exchange's `MarketSource`, levels and watchlist providers follow scope, watchlists are stored per exchange with the exact keys given, identifier validation is per exchange, and the screen shows `Nguồn giá: <exchange label>`. OKX watchlist value and behavior stay identical. Tests: an OKX watchlist already stored survives selecting Binance and back; `BTCUSDT` is accepted for Binance and not validated by the OKX patterns; levels from fixture klines with hand-derived values.

Finish by returning the structured report.

## 2. Objective

Market, BMAG and Support/Resistance read the selected exchange with Binance public data and per-exchange watchlists.

Done when: with scope set to Binance by provider override, these screens show Binance data and source copy, and OKX behavior is unchanged.

Complete the work in this run. Expect to write every needed file; a long run is normal. Ending without file changes is a failed attempt.

## 3. Preconditions

Predecessors: T117, T123, T124 = PASS. Decisions: D-005.
Required state: clean checkout on branch `codex/multi-platform-view-only`. Plan revision 2 approved.

## 4. Allowed Scope

Exact write list (new files use exactly these names). Read access covers all non-protected source and tests.

- `lib/exchanges/binance/binance_client.dart`
- `lib/exchanges/binance/binance_market.dart`
- `lib/exchanges/okx/okx_adapter.dart`
- `lib/core/exchange/exchange_adapter.dart`
- `lib/core/exchange/exchange_models.dart`
- `lib/core/exchange/market_source.dart`
- `lib/features/market/presentation/market_screen.dart`
- `lib/features/fractal_tracker/presentation/providers/fractal_provider.dart`
- `lib/features/fractal_tracker/presentation/fractal_screen.dart`
- `lib/features/support_resistance/data/market_repository.dart`
- `lib/features/support_resistance/data/watchlist_store.dart`
- `lib/features/support_resistance/domain/models.dart`
- `lib/features/support_resistance/presentation/providers/levels_provider.dart`
- `lib/features/support_resistance/presentation/providers/watchlist_provider.dart`
- `lib/features/support_resistance/presentation/support_resistance_screen.dart`
- `test/exchanges/binance/binance_client_test.dart`
- `test/exchanges/binance/binance_market_test.dart`
- `test/support/fake_exchange_adapter.dart`
- `test/features/market/market_screen_test.dart`
- `test/features/fractal_tracker/fractal_provider_test.dart`
- `test/features/fractal_tracker/fractal_screen_price_formatting_test.dart`
- `test/features/support_resistance/market_repository_test.dart`
- `test/features/support_resistance/support_resistance_screen_test.dart`
- `test/features/support_resistance/watchlist_provider_test.dart`
- `test/features/tools/tools_screen_test.dart`
- `test/features/portfolio/portfolio_scope_test.dart`
- `test/features/orders/orders_scope_test.dart`
- `test/core/exchange/exchange_scope_test.dart`

## 5. Forbidden Scope

Do not:
- read, search, parse, summarize or content-diff protected configuration, including `pubspec.yaml`, `pubspec.lock`, `analysis_options.yaml` and native project configuration;
- create, modify, regenerate or delete protected files, or add or remove dependencies;
- touch `backend/` or any git history, staging or branches;
- add any Binance or OKX write route;
- make opportunistic refactors or exceed the surface above.

If required work exceeds Allowed Scope, return `BLOCKED`.

## 6. Executor Contract

Design is fixed; mechanism details below it are yours if they satisfy the invariants and tests. Report what you chose. Stop only for a conflict about product behavior.

1. `market_source.dart`: `abstract class MarketSource` with `Future<List<MarketRow>> topTickers(String product)`, `Future<List<SupportResistanceInstrument>> instruments(SupportResistanceMarketMode)`, `Future<SupportResistanceTicker> ticker(...)`, `Future<List<SupportResistanceCandle>> candles(...)`, `Future<SupportResistanceMarketSnapshot> loadLevels(...)`, and `Future<List<RawCandle>> fractalCandles({coin, bar, limit, endTime})`. Match the signatures that exist on `SupportResistanceRepository`. Add `MarketSource market(Ref ref)` and `List<String> marketProducts` to `ExchangeAdapter`.
2. OKX: `SupportResistanceRepository` implements `MarketSource`, unchanged endpoints and behavior, so existing tests keep working. `topTickers` keeps today's query, filter and Top 50 in `marketListProvider`.
3. `binance_client.dart`: unsigned GET allowlist only: `/fapi/v1/exchangeInfo`, `/api/v3/exchangeInfo`, `/fapi/v1/ticker/24hr`, `/api/v3/ticker/24hr`, `/fapi/v1/klines`, `/api/v3/klines`. Hosts `https://fapi.binance.com` and `https://api.binance.com`. Never send `X-MBX-APIKEY`. Route through `exchangeRequestCoordinatorProvider(ExchangeId.binance)` on the public lane, applying 429 and `Retry-After` handling as the OKX client does.
4. `binance_market.dart`: spot mode maps to `/api/v3`, perpetual mode to `/fapi/v1`. Keep status `TRADING`, quote `USDT`; USD-M also requires contract type `PERPETUAL`. Top list: `^[A-Z0-9]+USDT$`, `quoteVolume` above 5,000,000, sort descending, take 50; base asset is the symbol without `USDT`, for display only. Kline row indexes: 0 open time, 1 open, 2 high, 3 low, 4 close, 5 volume. Fractal bars map to `1d`, `1w`, `1M`, using `endTime` paging. Levels reuse `SupportResistanceCalculator`.
5. `market_screen.dart`, `fractal_provider.dart`, `levels_provider.dart`, `watchlist_provider.dart`: select the source through the registry with `ref.watch(exchangeScopeProvider)`; each provider rebuilds on scope change, and `selectedCoinProvider` resets on selection in the same way as `orderFilterProvider`. In `fractal_provider.dart` a transport failure now surfaces as a provider error; a successful response with no rows stays empty data.
6. Watchlist: OKX keeps `WatchlistStore.storageKey`. Binance uses `support_resistance_watchlist_snapshot_binance`. The store receives the exchange and validates identifiers with that exchange's rule; the OKX `-USDT` and `-USDT-SWAP` patterns stay for OKX only.
7. Add `Nguồn giá: <exchange label>` to Market, BMAG and Support/Resistance using existing text styles. For Binance add product chips on Market from `marketProducts`, default USD-M. Do not restyle otherwise; T121 does that.
8. Do not register Binance in `exchangeRegistryProvider`; T120 does. Tests register it by override.
9. Update `FakeExchangeAdapter` for the new members. Change existing tests for wiring only.

Required invariants and edges: INV-002, INV-006; OKX REQ-012.
Apply reuse-first, minimal complete changes. Do not invent product semantics. If the contract is insufficient, return `BLOCKED`.

## 7. External Configuration / Environment Actions

Planned action: none.
Blocks verification until user applies: NO

## 8. Tests

- TEST-118-1: candle failure surfaces.
- TEST-118-2: separate watchlists.
- TEST-118-3: Binance symbol path.

## 9. Mandatory Verification

### RED — RED-118a/b
Scenario: (a) A candle transport failure in the fractal provider. (b) Binance `BTCUSDT` through S/R with an OKX watchlist already stored. (c) A Binance 429 with OKX public reads idle.
Command/method: `rtk flutter test --no-pub <file> --plain-name '<name>'`
Expected: (a) Provider error, not empty data. (b) No `-USDT` parsing used, no public request has an API key header, OKX watchlist value unchanged. (c) OKX lane stays open.
Actual: PENDING
Status: PENDING

### GREEN — GREEN-118
Scenario: Scope Binance with fixture responses for USD-M and Spot.
Command/method: `rtk flutter test --no-pub <file> --plain-name '<name>'`
Expected: Market rows, BMAG fractals and S/R levels computed from fixtures with hand-derived expected values; source copy names Binance.
Actual: PENDING
Status: PENDING

Run RED before GREEN. Verification ceiling: V3: `test/features/{market,fractal_tracker,support_resistance}`, `test/exchanges/binance`.
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
