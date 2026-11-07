# Design Specification: Multi-platform view-only restructure

Status: READY_FOR_PLAN
Date: 2026-11-07
Tier: L
Decision Ledger: `docs/agents/decisions/2026-11-07-multi-platform-view-only-decisions.md`

## 1. Objective

Requested outcome:
- Restructure the Flutter app from main so it serves multiple trading platforms well, following `designs/Trading Balance F - Multi Platform.figcraft`, initially OKX and Binance.
- The app becomes view-only and every request goes directly to an exchange.

Success conditions:
- Selecting a connection changes every data screen, and no data from the former exchange can appear under the new one.
- Adding another exchange requires one adapter folder and one registry entry, with no feature-screen changes other than copy.
- No request reaches the private backend at runtime.

## 2. Current State

Sources are non-protected code and docs on main, or measurements noted below. Protected manifests and configuration were not read.

### Observed Facts

| ID | Source | Symbol/Location | Observation |
|---|---|---|---|
| OBS-001 | `lib/core/network/okx_data_client.dart` | `OkxDataClient` | OKX display reads are already direct, GET-only, host pinned to www.okx.com |
| OBS-002 | `lib/features/orders/presentation/providers/trade_session_provider.dart:19-24` | `tradeSessionProvider` | Creating the provider calls `restore()`, which requests the backend session; `orders_screen.dart:117` watches it, so opening Lệnh contacts the backend |
| OBS-003 | `lib/features/orders/presentation/orders_screen.dart:197,345,1106,1334` | `TradeAccountControls`, `OrderCancellationControl` | Backend action widgets live inside the order lists; line 197 also hosts the filter chips |
| OBS-004 | `lib/features/settings/presentation/settings_trade_access_page.dart:339` | `TradeSessionControls` | The same page hosts the OKX credential editor and the backend login |
| OBS-005 | `lib/core/navigation/main_navigation_shell.dart`, `navigation_preferences*.dart`, `floating_navigation_buttons.dart` | shell | Seven destinations with preference-driven order, visibility and floating mode |
| OBS-006 | `lib/core/network/request_coordinator.dart:10` | `RequestLane` | Two lanes per instance, one shared instance today; a Binance 429 would close the OKX lane if shared |
| OBS-007 | `lib/core/network/foreground_read_gate.dart` | `ForegroundReadGate` | Exchange-agnostic; cancels on session identity or generation change |
| OBS-008 | `lib/features/fractal_tracker/presentation/providers/fractal_provider.dart:~227` | `catch (_) {}` | Candle read errors are swallowed and appear as empty data |
| OBS-009 | `lib/features/orders/presentation/providers/order_provider.dart:11-13` | `orderTabProvider`, `orderFilterProvider` | Plain `StateProvider`s that survive any switch unless reset |
| OBS-010 | curl OPTIONS, 2026-11-07, header `x-mbx-apikey` | Binance hosts | `fapi` and `papi` allow the header. `api.binance.com` `/api/v3/*` and `/sapi/v1/margin/*` send no `allow-headers`, so a browser blocks them. Not reproduced inside a browser |
| OBS-011 | curl with dummy key, 2026-11-07 | routes | `/fapi/v3/account`, `/fapi/v3/positionRisk`, `/fapi/v1/openOrders`, `/fapi/v1/allOrders`, `/api/v3/account`, `/api/v3/openOrders`, `/api/v3/allOrders`, `/sapi/v1/margin/{account,isolated/account,openOrders,allOrders}` all exist. Public klines and 24h tickers answer with `access-control-allow-origin: *` |
| OBS-012 | developers.binance.com, read 2026-11-07 | docs | Cross margin weight 10, `userAssets[{asset,borrowed,free,interest,locked,netAsset}]`. Isolated weight 10, `assets[{symbol,marginLevel,marginRatio,indexPrice,liquidatePrice,baseAsset,quoteAsset}]`, no entry price. Spot account weight 20, `balances[{asset,free,locked}]`, supports `omitZeroBalances`. Spot `openOrders` 6 with symbol, 80 without. Spot `allOrders` weight 20, `symbol` required, range at most 24 h when times are sent. USD-M account v3 weight 5 has no leverage or margin type; v2 account position rows have `leverage` and `isolated`. USD-M `allOrders` weight 5, at most 7 days per query, 90-day retention |
| OBS-013 | `lib/core/theme/app_theme.dart` | `AppPalette` | Light and dark palettes already equal the design tokens |

### Reproduced Behavior

None. Live private reads have not been exercised; agents hold no exchange keys.

### Hypotheses

| ID | Hypothesis | Evidence | Status |
|---|---|---|---|
| HYP-001 | `/fapi/v3/positionRisk` returns entry, mark, liquidation and unrealized PnL but not leverage or margin type | Docs page truncated at this section | UNCONFIRMED; closed by gate G1 |
| HYP-002 | USD-M `allOrders` needs `symbol` | Fetched doc table reads as optional, which contradicts general knowledge | UNCONFIRMED; contract sends `symbol` always, which is valid either way |

## 3. Scope

### In Scope
- Runtime view-only mode; hidden backend features.
- Fixed navigation, `Công cụ`, scope bar, picker, switch loading, connection management.
- Neutral exchange contract, registry, scope providers, OKX adapter, Binance adapter.
- Binance public market data; USD-M, Spot and Margin private reads.
- Per-exchange Market, BMAG and Support/Resistance.
- Design shell and account states for the retained screens.

### Out of Scope
- Any trading, cancel or close operation on any exchange; Binance write routes.
- Strategy screens and the design's strategy frames (04, 05, 06, success).
- Backend code, server operation and worker state.
- Multi-connection per exchange, COIN-M, Portfolio Margin, Funding, Earn valuation.
- The two earlier branches.
- Dependency changes and any protected configuration.
- Binance Spot/Margin on web.

## 4. Clarifications and Decisions

Open questions: N/A.
Resolved decisions: D-001..D-011.
Coordinator proposals pending plan approval: P-001..P-005.
Authorized assumptions: N/A.

## 5. Requirements

### REQ-001 — No backend traffic
The app MUST NOT issue any request to the private backend while `backendFeaturesEnabledProvider` is false, including at startup and on opening any screen.
Failure behavior: `tradeApiProvider` and `strategyApiProvider` return a disabled implementation that throws `backend_disabled` without creating network traffic.
Preserved behavior: `TradeApiClient`, `StrategyApiClient`, dialogs, and flow providers remain in source unchanged.

### REQ-002 — Hidden backend features
With the gate false, the UI MUST NOT show login status, close, close-all, cancel, Strategy, or the backend section of the trade-access page.
Preserved behavior: Order filter chips stay available. With the gate true, existing behavior and tests are unchanged. D-006.

### REQ-003 — Fixed navigation and tools
The bottom bar MUST show exactly `Tài sản`, `Lệnh`, `Thị trường`, `Thêm`. `Thêm` opens `Công cụ` with `BMAG`, `Hỗ trợ / kháng cự`, `Sàn & tài khoản`, `Cài đặt`. Stored navigation preferences are ignored and never written. With the gate true, `Chiến thuật` is the third item.

### REQ-004 — Exchange contract and registry
Feature code MUST read exchange data through neutral contracts in `lib/core/exchange/`. Each exchange is declared in one registry entry that supplies identity, label, capabilities, credential form descriptor and adapter.

### REQ-005 — Scope isolation
Selecting a connection MUST clear the former connection's data before the next frame shows new content, and a response started under one scope MUST NOT render under another. Rate-limit state MUST be per exchange. Credential changes keep the existing generation fence.
Failure behavior: discarded responses are silent; they never produce an error on the new scope.

### REQ-006 — Binance private reads
The app MUST read USD-M, Spot and Margin as separate wallets of one connection, using signed requests without any new dependency. One wallet failing MUST NOT hide the others. On web no request may go to Spot or Margin private routes; the UI shows `Chỉ có trên ứng dụng`.

### REQ-007 — Binance history coverage
History MUST load at most 10 symbols chosen by the order: open positions, held assets by descending value, watchlist. It MUST state the coverage on screen, and load sequentially under the rate lane. D-010.

### REQ-008 — Exchange-scoped analysis
Market, BMAG and Support/Resistance MUST use the selected exchange, show `Nguồn giá: <exchange>`, and never substitute another exchange's quote. Watchlists are stored per exchange; `support_resistance_watchlist_snapshot` stays OKX and keeps working. Candle read failures MUST surface as errors rather than empty data.

### REQ-009 — Connection experience
Scope bar on all retained top-level and tool screens; picker per design; selection persists; `Quản lý kết nối` opens management; forms per exchange test and save credentials. The picker lists configured connections only. No screen shows a sum across exchanges.

### REQ-010 — Account states
Expired, empty, app-only, partial and generic failure are shown per connection, with retry or repair where it helps. Raw error strings are not shown.

### REQ-011 — Design shell and accessibility
Retained screens follow the design's layout, tokens and Vietnamese copy, while using safe areas and scrolling rather than fixed coordinates. Primary targets are at least 48 logical pixels; text scaling and reduced motion are honored; state is not conveyed by color alone.

### REQ-012 — Preserved OKX behavior
OKX reads, exact decimal text, masking, currency, time zone, generation guard, rate-limit behavior and credential storage keys stay as they are.

## 6. Data Contract

Neutral types are plain Dart in new files. All numeric fields are the exchange's text verbatim (`String?`, absent means unavailable, never zero). Values become `double` only at the display or valuation edge, as today.

| Type | Fields |
|---|---|
| `ExchangeId` | `okx`, `binance` value identity |
| `ConnectionProfile` | `connectionId` (`okx-default`, `binance-default`), `exchange`, `label`, `products` |
| `ExchangeScope` | `connectionId`, `exchange`, `credentialGeneration`, `switchEpoch`, equality on all |
| `ExchangeCapabilities` | readable products, unavailable-on-this-platform products |
| `InstrumentKey` | `exchange`, `product`, `nativeId`; base and quote from exchange metadata; never parsed from a display label |
| `AccountSnapshot` | total, total currency, `isPartial`, balances, wallet results, issues |
| `AssetBalance` | wallet, asset, total, available, frozen, borrowed, interest, net, unrealized PnL, value in USDT |
| `ExchangePosition` | key, product label, side, direction, size, entry, mark, liquidation, leverage, margin mode, unrealized PnL and ratio, notional, position id, position and margin currency, native record |
| `MarginAccountRow` | cross per asset, or isolated per pair: borrowed, interest, net, margin level, liquidation, index price |
| `ExchangeOrder` | id, key, product label, type, side, price, quantity, filled, average, notional and filled notional, leverage, state, created time, native record |
| `Ticker`, `Candle` | key, last, 24h change; open time, OHLCV |

Binance grain: one connection, three wallets. Margin is not forced into `ExchangePosition`; it has no entry price per OBS-012, and has its own card with `—` for nothing invented.

Field mapping:
- USD-M positions: `/fapi/v3/positionRisk`. Leverage and margin mode come from `/fapi/v2/account` position rows (OBS-012), subject to G1. Unavailable fields render `—`.
- Spot: `/api/v3/account?omitZeroBalances=true`, total = free + locked.
- Cross: `netAsset`, rows with zero net and zero borrowed hidden. Isolated: base and quote `netAsset`.

Valuation (P-005): `value(asset) = amount × last(asset/USDT)`, USDT itself is 1. USD-M uses `assets[].marginBalance`. Spot uses free + locked. Margin uses signed `netAsset`. An asset without a USDT price is listed unpriced, excluded from the total, and makes the total partial. A failed wallet makes the total partial.

Independent worked example: USD-M USDT marginBalance `1000.50`; Spot BTC `0.01` at `76000` = `760`, Spot USDT `100`; cross ETH netAsset `-0.1` at `2000` = `-200`. Total = 1000.50 + 760 + 100 − 200 = `1660.50`, not partial. If the cross read fails: `1860.50`, partial.

OKX keeps its existing displayed total, computed by `PortfolioScreen` from asset balances and live prices, not from `totalEq` (REQ-012, VAL-004).

## 7. Cross-Layer Mapping

N/A — no backend or API contract changes. Client-only.

## 8. Proposed Design

```text
Feature screens (portfolio, orders, market, fractal, support_resistance)
        │ watch scoped providers, keyed by ExchangeScope
lib/core/exchange/
  exchange_models.dart, exchange_adapter.dart, exchange_registry.dart,
  exchange_scope.dart (selected connection + scope), scoped_read.dart
        │ registry resolves one adapter
lib/exchanges/okx/okx_adapter.dart  ──> existing OkxDataClient, repositories
lib/exchanges/binance/              ──> binance_client, signer, reader, market
```

Scope and late responses:
1. `selectedConnectionProvider` holds the id, persisted, loaded at startup like other settings.
2. `exchangeScopeProvider` composes it with that connection's credential generation and a switch epoch incremented by every selection, so returning to a connection within one frame still makes a new key; selection also invalidates adapter providers, cancelling in-flight reads (VAL-006).
3. Read providers are `autoDispose.family<_, ExchangeScope>`. A former scope's element is disposed, its `CancelToken` cancelled, and a late result has no listener. This is structural rather than a check at each call site.
4. `ScopeSwitchGate` keys the screen subtree by connectionId, shows `Đang tải <account>` until the first read settles, then lands on `Tài sản`. Pushed tool routes are popped first.
5. `RequestCoordinator` and `ForegroundReadGate` are unchanged classes, instantiated per exchange through `Provider.family`.
6. `runOkxPrivateRead` becomes a thin wrapper over a general `runPrivateRead` taking the adapter's failure classifier, so existing callers and tests compile.

OKX freezed models stay. The adapter maps them to neutral types. Backend action widgets stay OKX-typed and hidden.

## 9. Interfaces and Contracts

Public API: N/A.
Internal interface: `ExchangeAdapter { capabilities; readAccount(scope); readPositions(scope); readOpenOrders(scope, filter); readHistory(scope, filter); catalog(product); tickers(product); candles(key, bar, range); classify(error) }`. `classify` returns `transient(retryAfter) | credential | permission | unavailableOnPlatform | other`.
Database/schema: N/A.
External configuration: none.
Authorization: Binance `X-MBX-APIKEY` plus HMAC-SHA256 hex signature over the exact query with `timestamp` and `recvWindow` 5000, using the `crypto` import already used by `okx_interceptor.dart`. The key is never sent on public routes.

## 10. Invariants

- INV-001: No aggregate across exchanges anywhere.
- INV-002: A `BTC / USDT` label is never an identifier.
- INV-003: Absent numeric data is shown as unavailable, never zero, for every value an adapter parses itself. The OKX adapter maps values from existing OKX models as they are; their `@Default('0')` deserialization is existing behavior preserved by REQ-012 and is not changed by this plan (VAL-001).
- INV-004: Secrets never appear in logs, errors, state exposed to widgets or telemetry.
- INV-005: With the gate false, no code path constructs a live backend client call.
- INV-006: `Binance` private routes are an allowlist of GET paths only; no write route exists in the client.

## 11. Edge Cases

### EDGE-001 — Rapid OKX → Binance → OKX
Expected: only the last scope's fresh reads render; older responses are dropped.

### EDGE-002 — Selected connection's keys removed
Expected: fall back to the other configured connection; if none, OKX's existing no-key state.

### EDGE-003 — Stored selection unreadable
Expected: default to OKX, no crash.

### EDGE-004 — One Binance wallet denied, others fine
Condition: Margin returns a permission or credential code while USD-M succeeds.
Expected: that wallet shows a notice; total partial; the connection is not marked expired. Marked expired only when every attempted wallet returns a credential failure.

### EDGE-005 — Web with Binance selected
Expected: USD-M only, no Spot or Margin requests, app-only notice, total labeled as USD-M only.

### EDGE-006 — Clock drift
`-1021` resyncs time and retries once. `-1022` is terminal.

### EDGE-007 — Earn and unknown assets, such as `LDUSDT`
Expected: listed unpriced, total partial.

### EDGE-008 — Portfolio Margin account
Expected: classic route errors are shown as wallet failures; no attempt to read `papi`.

### EDGE-009 — Stored floating navigation preference
Expected: fixed bar, value neither read nor written.

### EDGE-010 — History with no eligible symbol
Expected: empty state explaining coverage, no requests.

## 12. Failure Semantics

| Failure | Response | Allowed Side Effects | Forbidden Side Effects |
|---|---|---|---|
| 401, `-2014`, `-2015`, `-2008` on all wallets | Expired state with `Kiểm tra kết nối` | Stop polling this scope | Retry loop; affecting other connections |
| Same on some wallets | Wallet notice, partial total | Others continue | Zero balance |
| 429, `-1003` | Back off using `Retry-After` in that exchange's lane | Stale data retained on same scope | Closing another exchange's lane |
| 418 | Long backoff in that exchange's lane | — | Automatic retry before expiry |
| 5xx, network | Transient retry per existing lane rules, then retry card | — | Raw error text |
| Candle read failure | Error with retry | — | Empty chart presented as data |

## 13. RED / GREEN Behavioral Contract

Per-task pairs are in the plan and task files. Program-level pairs:

### RED-001
Scenario: late response. Setup: OKX balance read pending, switch to Binance, then OKX resolves. Expected: Binance screen never shows the OKX amount; OKX token cancelled.

### RED-002
Scenario: backend isolation. Setup: counting HTTP adapter, gate false, pump Lệnh and Cài đặt. Expected: zero backend requests, no login control.

### GREEN-001
Scenario: OKX → Binance with fake transports. Expected: target account loading, then Binance assets on `Tài sản`, filters at defaults; reopen restores Binance.

Verification order is RED then GREEN.

## 14. Performance Contract

N/A — no numeric target. Binance reads stay within documented weights through per-exchange lanes; history loads sequentially with at most 10 symbols.

## 15. Compatibility

Existing OKX keys and watchlist are retained. Stored navigation values are ignored. Web keeps working with reduced Binance scope. Existing tests stay valid through a gate override, except navigation customization tests, which are removed with their code.

## 16. Security and Permissions

Keys stay on the device in existing secure storage, under new Binance keys. Form copy tells the user to create a read-only key. Permission inspection is not attempted because `/sapi` is unreachable on web. On web, keys entered in a browser share the existing OKX web posture.

## 17. Protected Configuration / Environment Actions

Required external actions: none. No dependency is added; if an executor finds one necessary, it returns BLOCKED.

## 18. Rollout / Rollback

Rollout: one feature branch, a task at a time, with user-run live check before any merge.
Rollback trigger: wrong data scoping, or OKX regression.
Rollback procedure: do not merge the branch, or revert it. No data migration exists. Setting the gate true restores backend features and the fifth nav item without restoring customization.

## 19. Acceptance Criteria

### AC-001
Given the gate is false, when any retained screen is opened, then the counting adapter records zero backend requests.

### AC-002
Given the gate is false, then login status, close, close-all, cancel and Strategy are absent, and order filter chips remain. Given the gate is true, existing screen tests pass.

### AC-003
The bar shows four items in the specified order, including when a floating preference is stored. `Thêm` reaches all four tools.

### AC-004
Feature screens import no `OkxDataClient` for retained read paths; a test adapter registered in the registry renders through the same screens.

### AC-005
RED-001 holds; filters return to defaults on switch; a Binance 429 leaves OKX's lane open; a credential rotation still drops in-flight results.

### AC-006
With fake transports, each wallet maps per section 6, the worked example yields `1660.50` and `1860.50` partial, and a wallet failure leaves others displayed. With platform set to web, no Spot or Margin private request occurs.

### AC-007
History requests at most 10 symbols in the specified order, sequentially, with coverage copy.

### AC-008
Each analysis screen shows the source; OKX watchlist survives unchanged and a Binance watchlist is separate; a candle failure shows an error; `BTCUSDT` never passes through the OKX `-USDT` parsing.

### AC-009
Selection survives restart; picker rows use `Đang xem` and `Chuyển sang tài khoản này`; forms save and test per exchange; no sum across exchanges exists.

### AC-010
Expired, empty, app-only, partial and failure states render per section 12 with no raw error text.

### AC-011
Rendered light and dark review of retained frames passes; 390-wide and narrow widths at large text scale do not overflow; targets at least 48; reduced motion respected.

### AC-012
Existing OKX tests for portfolio, orders, market, BMAG, S/R and credentials pass, with only gate overrides or scope wiring added.

## 20. Requirement Traceability

| Requirement | Acceptance Criteria | Design/Contract | RED/GREEN |
|---|---|---|---|
| REQ-001, 002, 003 | AC-001..003 | §8 | RED-002 |
| REQ-004, 005, 012 | AC-004, 005, 012 | §8, §9 | RED-001 |
| REQ-006, 007 | AC-006, 007 | §6, §12 | T119 pairs |
| REQ-008 | AC-008 | §8 | T118 pairs |
| REQ-009, 010 | AC-009, 010 | §8, §12 | GREEN-001 |
| REQ-011 | AC-011 | Handoff §5 | T121 pairs |

## 21. Completion Gate

- [x] no unresolved material question
- [x] no silent assumption
- [x] requirements/contracts are unambiguous, except G1 closing HYP-001 before T119
- [x] edge/failure semantics defined
- [x] RED/GREEN expected outcomes independently derived
- [x] acceptance criteria complete
- [x] traceability complete for affected requirements
- [x] protected configuration/environment contents were not read
- [x] required external configuration/environment actions are fully specified or N/A
