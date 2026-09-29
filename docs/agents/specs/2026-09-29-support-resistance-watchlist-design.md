# Design Specification: Support and Resistance Watchlist

Status: READY_FOR_PLAN
Date: 2026-09-29
Tier: L — cross-layer market data, persistence, and primary navigation
Decision Ledger: `docs/agents/decisions/2026-09-29-support-resistance-watchlist-decisions.md`

## 1. Objective and evidence

Provide a dedicated Flutter screen for one to ten selected USDT coins, a Spot/Perpetual switch, and H1/H4/H6/D1/W1 selection. For each coin, show the current price and successive support/resistance levels on the chosen timeframe.

Observed non-protected repository facts:

| ID | Source | Observation |
|---|---|---|
| OBS-001 | `lib/core/navigation/navigation_destination_data.dart`, `main_navigation_shell.dart` | Six fixed destinations exist; the new destination needs list, screen mapping, and navigation test changes. |
| OBS-002 | `lib/features/fractal_tracker/presentation/providers/fractal_provider.dart` | BMAG uses a single selected coin; its D1 is a display period composed from 1H candles. This state and timeframe meaning must not be reused. |
| OBS-003 | `lib/features/market/presentation/market_screen.dart` | The market screen gets public OKX Spot USDT tickers but filters to a liquid top 50. |
| OBS-004 | `lib/features/portfolio/data/risk/risk_market_repository.dart`, `domain/risk/market_risk_engine.dart` | The typed risk adapter accepts only 1H/4H and the risk engine calculates one prior-window support/resistance pair. Reusing that pair would not meet successive-level behavior. |
| OBS-005 | `lib/features/portfolio/data/risk/risk_request_coordinator.dart` | A public request lane already offers spacing and 429 backoff. |
| OBS-006 | `lib/features/portfolio/presentation/providers/risk_dashboard_provider.dart` | SharedPreferences is already used for local, nonsensitive state. |

## 2. Scope

In scope: a new primary destination and screen; public OKX USDT instrument discovery, current prices and UTC closed candles for Spot and Perpetual; deterministic level calculation; persisted watchlists/mode/timeframe; periodic/manual refresh; focused tests.

Out of scope: trading, alerts, chart drawing, manual level editing, changes to BMAG/Risk calculations, authentication, configuration/environment files, new dependencies, and data migration.

## 3. Requirements

- REQ-001: Offer one screen-wide Spot/Perpetual mode. A searchable picker shows all currently trading USDT instruments available in that mode. The selected watchlist is ordered, unique, persisted separately per mode, and capped at 10. A fresh installation starts in Spot with an empty list and a selection prompt.
- REQ-002: Offer one screen-wide H1/H4/H6/D1/W1 timeframe and persist the last mode/timeframe. On first launch, select H6. These labels mean actual UTC-aligned intervals, independently of BMAG's period labels.
- REQ-003: For every selected coin, use its active-market current price and the newest 300 confirmed candles at the selected interval. Open, malformed, duplicate, out-of-order, or wrong-instrument candles may not create levels. Historical pagination is permitted to obtain 300 confirmed candles.
- REQ-004: Derive reproducible swing levels, merge close candidates, classify against current price, and show up to the five nearest levels on each side in distance order. Never fabricate missing levels.
- REQ-005: Load and refresh each coin independently. Refresh once per minute only while the screen is mounted, plus on explicit refresh or selection/mode/timeframe change. Show per-coin loading, unavailable, and sparse-results states; one coin failure must not hide another coin's result.
- REQ-006: Make the seventh navigation destination usable in fixed and floating modes, on narrow screens, with accessible controls and adaptive number formatting.

## 4. Data and calculation contract

Grain: one watchlist result per `(market mode, OKX instrument ID, UTC timeframe)`.

| Field | Meaning |
|---|---|
| `marketMode` | `SPOT` or `SWAP`; one value for the whole screen. |
| `instrumentId` | Validated active USDT instrument from the selected mode. Spot: `BASE-USDT`; perpetual: `BASE-USDT-SWAP`. |
| `timeframe` | H1→1H, H4→4H, H6→6Hutc, D1→1Dutc, W1→1Wutc. Exchange response and UTC alignment must be checked at the adapter boundary. |
| `referencePrice` | Latest valid public ticker last price for this exact instrument; finite and positive. An unavailable ticker makes classification unavailable. |
| `candles` | Newest 300 confirmed, finite positive OHLC records, ordered oldest to newest; timestamps unique and at the selected UTC interval. |
| `level` | Representative positive price, earliest/latest contributing candle times, touch count, and side relative to `referencePrice`. |

Calculation:

1. Exclude open candles. Inspect only the newest 300 closed candles. For every index with two candles on either side, a strict swing high has `high[i] > high[i±1,i±2]`; a strict swing low has `low[i] < low[i±1,i±2]`. Equal neighboring extrema are not confirmed swings. Both high and low candidates may arise from a candle.
2. Combine both candidate sets and sort by price ascending, then timestamp for deterministic ties. Build non-overlapping clusters in that order. A candidate joins the current cluster only if `(candidatePrice - clusterMinimumPrice) / clusterMinimumPrice <= 0.005`; otherwise start a new cluster. The representative is the median candidate price (midpoint of the two middle prices for an even count). This prevents transitive chains wider than 0.5%.
3. A representative below `referencePrice` is support; above it is resistance. At exact equality it is omitted until the next price changes. Crossing a level changes its side. Sort support descending and resistance ascending, take five of each. If fewer exist, show only those found and an explicit count/empty state.
4. Do not extrapolate or interpolate levels. Do not mix Spot and Perpetual candles or tickers. A result is timestamped and may be displayed as stale only with a visible stale label; a failed refresh must not silently appear current.

Independent example: with current price 100, representative levels 95, 97, 100, 103, 110 produce supports `[97,95]`, resistances `[103,110]`; equality is omitted. A crossing to 104 changes 103 to support, ordered before 97.

## 5. Architecture and interfaces

`SupportResistanceRepository` (new, public read-only OKX adapter) discovers instruments and obtains ticker/candle data through an injectable Dio client and the existing public request coordinator. It validates response shape, mode, interval, UTC alignment, pagination, and 429/backoff behavior. It is separate from the risk repository so existing risk acceptance of only 1H/4H remains intact.

`SupportResistanceCalculator` (new pure domain function) receives validated candles and a reference price and returns ordered level lists. It performs no network or persistence work.

`WatchlistStore`/controller (new) persists two ordered coin lists plus mode/timeframe as one versioned snapshot using the existing SharedPreferences dependency. It sanitizes malformed/duplicate/over-limit stored records and invalid mode/timeframe values; syntactically valid saved instruments that have since been delisted remain visible for removal. Only active instruments from the mode-specific catalog may be newly added. Failed writes preserve the last confirmed selection and show a recoverable error. The screen watches selected keys and exposes independent async states per coin. Selection changes invalidate only affected requests; late responses from an old key must not overwrite the current view.

The screen uses `NavigationContentFrame`, app theme, adaptive price formatter, and distinct sections per coin. It displays the market mode, timeframe, reference price, fetch time, count and ascending/descending level sequences with nearest first. Coin picker offers search and clear selected state, with add/remove disabled at the 10-coin limit as appropriate. A seventh nav item receives a short Vietnamese label and accessible semantics.

## 6. Invariants and edge cases

- INV-001: Each coin card uses only its own instrument, mode and timeframe; no cross-market result leakage.
- INV-002: Each displayed support is strictly below the current reference price, each resistance strictly above it, and each list is correctly nearest-first.
- INV-003: Closed candles only; 300 is a maximum calculation window, and a smaller valid history is allowed with a sparse-data indication.
- INV-004: Refreshes do not overlap for the same key; public requests obey spacing/backoff. Timers stop with screen disposal.
- EDGE-001: An instrument disappears or is no longer trading: retain its saved choice for user visibility, mark unavailable, and offer removal; do not silently substitute another market.
- EDGE-002: One API call fails/returns 429 or invalid data: only affected coin/picker state reports failure; other cards stay usable. Cached prior data, if displayed, is labeled stale.
- EDGE-003: Rapid switches or removals: render only the latest mode, timeframe and watchlist generation.
- EDGE-004: Zero, one or fewer than five levels on a side: show the actual count, without duplicates or invented values.
- EDGE-005: Persistence corruption or write failure: sanitize on load, avoid crash, and surface save failure with selection rollback.

## 7. Acceptance and verification

- AC-001: A fresh user sees an empty watchlist; can add up to ten active USDT pairs in Spot, switch to Perpetual with a separate list, reopen the app, and recover both lists plus last mode/timeframe.
- AC-002: Choosing H6 or D1 changes the candle request/UTC interval and recomputes each selected coin independently; a spot result never appears under Perpetual.
- AC-003: A 300-candle fixture with known swings/clusters yields at most five correctly ordered values per side, and recategorizes crossed levels without fabricated entries.
- AC-004: Open/invalid candles, equality, sparse history, and a single failed coin produce the specified non-success states while another coin remains visible.
- AC-005: Manual and mounted-only one-minute refresh work without overlapping stale writes; navigation works in fixed/floating narrow layouts.

RED-001: Given an open candle with a very high price and a complete older fixture, that high must never appear as a resistance; with a ticker at 104, a former level at 103 must be support.

GREEN-001: Given two valid coins, 300 closed candles each, a price between several clustered levels, and H6 selected, the screen shows their independently ordered nearest five supports/resistances and the persisted choices return after reload.

RED must be observed before GREEN for each implementation task with task-specific focused fixtures.

## 8. Compatibility, security and rollout

No existing public API, database schema, BMAG calculation, or Risk calculation changes. All market requests are public read-only; no credentials are needed or requested. No protected configuration/environment contents may be read and none may be modified. No external configuration action is required. Rollout is a new destination; rollback is removal of that destination/feature code, with only nonsensitive local watchlist keys left behind.

The exact UTC bar identifiers above are the planned adapter contract. If the locally available integration cannot establish exchange support/UTC alignment without unauthorized external access, stop that verification branch and report it; do not silently substitute a different interval.
