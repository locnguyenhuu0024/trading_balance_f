# Decisions: Binance direct reads and combined exchange views

Status: ACTIVE
Specification: `docs/agents/specs/2026-10-25-binance-direct-reads-design.md`
Plan: `docs/agents/plans/2026-10-25-binance-direct-reads.md`

## User Decisions

### D-001 — Supported Binance account products
Decision: Support Binance Spot and USDⓈ-M Futures (USDT-M).
Source: User response on 2026-10-25.

### D-002 — Combined exchange views
Decision: Show OKX and Binance together on the same screens, identifying each source with its platform icon.
Source: User response on 2026-10-25.

### D-003 — Direct feature parity
Decision: Include the features currently available through direct OKX calls. Exclude backend-driven functionality from the Binance addition.
Source: User response on 2026-10-25.
Repository evidence: Direct account reads, market listings, Fractal candles, support/resistance analysis, and strategy market inputs exist. Strategy application resources and trading actions retain backend authority.

## Clarification Questions

### Q-001 — Binance Spot history coverage
Status: ANSWERED
Question: Select one or more symbols to load Spot history, or scan all Spot symbols?
Why it matters: Binance Spot `GET /api/v3/allOrders` requires `symbol`. Discovering symbols from current balances/open orders alone cannot prove complete historic coverage.
Evidence: https://developers.binance.com/en/docs/catalog/core-trading-spot-trading/api/rest-api/account#all-orders-user_data

### Q-002 — Partial exchange failure
Status: ANSWERED
Question: Show available exchange data with an incomplete-total warning when another exchange fails or lacks credentials, or require both exchanges before displaying a total?
Why it matters: Missing/unavailable exchange data must not silently become a zero balance or a complete combined total.

### Q-003 — Existing-screen scope and aggregation proposal
Status: ANSWERED
Question: Approve a combined portfolio headline with source/wallet details, one merged Top 50, Spot-only Market/Fractal parity, ten combined watchlist entries per existing market mode, and retaining OKX-only Strategy flows because those flows call backend resources?
Why it matters: The strategy wizard combines direct market discovery with backend preview/submission and cannot safely receive Binance instruments without changing the excluded backend contract. Ranking and watchlist limits need an explicit combined-exchange meaning.
Repository evidence: `lib/features/strategy/presentation/strategy_wizard_dialog.dart`, `lib/features/strategy/domain/strategy_selection.dart`, `lib/features/market/presentation/market_screen.dart`, `lib/features/support_resistance/data/watchlist_store.dart`.

## User-Authorized Assumptions

None.

## Additional User Decisions

### D-004 — All-pair Spot history
Source question: Q-001
Decision: Scan every Spot pair to aggregate history instead of requiring symbol selection.
Impacts: REQ-003 / AC-003 / P02,P03 / T117,T118.

### D-005 — Partial results
Source question: Q-002
Decision: Show successful source data and explicitly warn when totals are incomplete.
Impacts: REQ-004 / AC-004 / P03 / T118.

### D-006 — Preserve existing screen scope
Source question: Q-003
Decision: Combined portfolio headline plus exchange/wallet details; one merged Top 50; Market/Fractal remain Spot; support/resistance adds Binance with ten selections shared across exchanges per mode; Strategy remains OKX-only because its flows call backend resources.
Impacts: REQ-004..008 / AC-004..008 / P03,P04 / T118,T119.

Source for D-004..006: explicit user responses on 2026-10-25.

## Approval State
All clarification questions are answered; D-007 supersedes the analytical portions of D-003/D-006. Await execution authorization after presenting the canonical plan and checklist. Agreement with scope does not authorize a subsequently written implementation plan.

### D-007 — Keep all analytical views on existing OKX
Source: explicit user correction on 2026-10-25 after presentation of revision 1.
Decision: Remove Binance expansion for Market, Fractal and support/resistance. These screens and Strategy continue using OKX as currently implemented. No combined Top 50, Binance analytical candles/search, watchlist v2 migration or changed selection limits. Preserve source-specific Binance quotes only where needed to value Binance account data.
Supersedes: analytical portions of D-003/D-006 and P04/T119; narrows REQ-005/AC-005; removes REQ-006/AC-006.
Retains: D-001/D-002/D-004/D-005 and combined portfolio/order/position views, source icons and independent credentials.
Impacts: revision 2 of specification/plan and active T116..T118; T119 marked REMOVED. No implementation authorization inferred from this scope correction.
