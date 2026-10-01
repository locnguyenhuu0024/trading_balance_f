# Design Specification: Position Strategy

Status: READY_FOR_PLAN
Date: 2026-10-01
Tier: L
Decision Ledger: `docs/agents/decisions/2026-10-01-position-strategy-decisions.md`

## 1. Objective and scope

Create a durable, authenticated USDT perpetual strategy workflow: scan up to 500 confirmed candles at H6/H12/D1/W1, select support/resistance limit levels, size orders from a real USDT margin budget, review projected sequential fills, save a draft or confirm immediate batch placement, and monitor applied strategies. No strategy editing, automatic cancellation, stop-loss, take-profit, or account-mode change is requested.

## 2. Evidence and decisions

- OBS-001: `lib/core/navigation/main_navigation_shell.dart` and `navigation_destination_data.dart` own fixed screen IDs and saved navigation integration.
- OBS-002: `lib/features/support_resistance/data/market_repository.dart` and `domain/level_calculator.dart` scan 300 confirmed candles with at most five levels per side; `domain/models.dart` lacks H12.
- OBS-003: `backend/service.py` exposes session-protected existing-position actions, but no strategy/batch route; existing DCA submits a single market order for an existing position.
- OBS-004: `backend/store.py` persists session/action state but not strategies. `backend/okx.py` has only single-order placement.
- OBS-005: `backend/service.py` already normalizes actual position `avgPx`, `markPx`, `liqPx`, `upl`, and leverage.
- OBS-006: [OKX API documentation](https://www.okx.com/docs-v5/en/) supports `12Hutc`, candle pages of at most 300, side-specific isolated leverage in Hedge mode, and batch placement of at most 20 orders. Batch results can be partial.

User decisions D-001..D-015 in the decision ledger are binding. Frontend and backend planning workstreams were independently reviewed and reconciled here.

## 3. Requirements

| ID | Contract |
|---|---|
| REQ-001 | Add a Vietnamese “Chiến Thuật” destination compatible with existing navigation visibility/order preferences. Its “Dựng chiến thuật” popup selects one live USDT linear SWAP coin, H6/H12/D1/W1, and Long, Short, or both, then opens the three-step flow. |
| REQ-002 | Fetch the newest available **up to 500 confirmed UTC candles** for the selected swap and interval, excluding open/malformed/duplicate/wrong-instrument candles. Use the existing strict two-neighbor swing and 0.5% clustering rules over this window, without changing the separate 300-candle watchlist feature. Show only real derived support/resistance points, their distance from a timestamped same-swap last price, and sparse/error states. |
| REQ-003 | Step 1 shows selectable level cards and one entry radio per selected side. Long uses supports; Short uses resistances. Entry must be nearest the current price among that side's selected levels; remaining selected levels are DCA in outward price order. At least one selected point per selected side, at most 20 total. |
| REQ-004 | Step 2 accepts total real USDT margin, side leverage 1..10 (default 5), side split default 50/50 when both sides, and equal/increasing/decreasing capital weights. Allocate margin per side, then per order in entry-to-farthest order using weights 1 or 1..n or n..1. Show unallocated remainder caused by contract rounding and estimated opening fees separately; fees are additional to the margin budget. Reject non-positive or below-minimum orders. |
| REQ-005 | Step 3 shows exact order side, entry/DCA role, limit price, contracts, margin, leverage, cumulative average entry, and estimated liquidation after each sequential fill. Estimates are visibly hypothetical. Recompute/invalidate the review after upstream edits or stale market/instrument data. Saving creates an immutable draft. |
| REQ-006 | Applying now or applying a saved draft presents a final exact-order confirmation. After authenticated prepare, the backend checks account identity, live swap metadata, mode, no existing position/pending order for that instrument, budget/lot/minimum/price precision and freshness, sets isolated leverage per side, then sends at most one 20-order OKX batch. It records per-order IDs and outcomes before/after the write, does not blindly retry uncertain writes, and reports partial/unknown outcomes honestly. Two-sided mode requires Hedge mode; Net mode produces guidance rather than an automatic switch. |
| REQ-007 | Strategy records are durable and account-scoped. Drafts can be listed, applied, or deleted; any application attempt makes a strategy immutable and non-deletable, including partial/unknown attempts. No strategy edit or cancellation API is provided. |
| REQ-008 | The strategy list shows draft/applied/partial/unknown status; live current position PnL, PnL divided by filled-order margin, used margin from fills only, entry/latest/actual OKX liquidation, and data timestamps. The frontend polls the **same swap's public OKX ticker every 1 second while visible**, without overlapping requests or stale-response overwrite. Authenticated backend position/order reconciliation has an independent bounded cadence; absent/stale data is labeled unavailable, never presented as current. |

## 4. Data and calculation contract

One strategy is one instrument/timeframe/side selection with a frozen set of selected levels, budget, leverages and allocation rule. A strategy order has side, role, limit price, integer-lot-compatible contract size, planned margin, client order ID, exchange order ID if known, and fill state. Money and contracts use decimal arithmetic on the backend; UI formatting does not become the source of truth.

For side `s`, `sideBudget = totalMargin * sidePercent/100`; order `i` receives `sideBudget * weight_i/sum(weights)`. Planned notional is `orderMargin * sideLeverage`. For a linear SWAP with validated base-denominated contract value `C = ctVal * ctMult`, `contracts_i = floor_to_lot(plannedNotional / (limitPrice_i * C))`; actual planned margin is `contracts_i * limitPrice_i * C / sideLeverage`, never exceeding allocation. Validate `ctValCcy`, multiplier, tick size, lot size and minimum size from the current instrument response. No order is silently rounded up. Opening fees are estimated from the account's applicable rate and shown outside this budget.

After the first `k` hypothetical full fills on a side: `N = sum(contracts_i)`, `E = sum(contracts_i * limitPrice_i)/N`, and `M = sum(actualPlannedMargin_i)`. Let `C = ctVal * ctMult` base units per contract, `r` be the validated isolated maintenance-margin rate at the cumulative position tier, and `f` be the applicable taker-fee-rate proxy for liquidation cost. The conditional mark-price liquidation estimate is `long = (C*N*E - M)/(C*N*(1-r-f))` or `short = (C*N*E + M)/(C*N*(1+r+f))`. Re-select the tier and recompute after every assumed fill. Show “no positive modeled threshold” rather than zero if the long numerator is nonpositive. Round displayed Long thresholds upward and Short thresholds downward to the price tick. If contract multiplier, tier, fee rate or denominator cannot be validated, review and application are blocked rather than showing invented precision. Real fills, fees, funding, mark price and margin adjustments can shift actual liquidation. Actual applied `liqPx` comes from OKX position records, not this projection. PnL percentage is `OKX upl / filledMargin * 100` only when filledMargin is positive; otherwise show unavailable. [OKX isolated formula](https://www.okx.com/en-gb/help/vii-introduction-to-the-isolated-mode-of-single-multi-currency-portfolio-margin) and [API reference](https://www.okx.com/docs-v5/en/) support the modeled inputs and limitations.

Worked allocation example: 90 USDT of margin over three Long points at 5x gives equal `[30,30,30]`, increasing `[15,30,45]`, and decreasing `[45,30,15]` USDT **before** contract rounding. At a 60/40 split of 100 USDT, Long receives 60 and Short 40; each is then weighted independently.

## 5. Cross-layer control flow

```text
Flutter direct OKX public SWAP instruments/ticker/candles
  -> validated 500-candle levels -> selection and budget
  -> authenticated backend preview (authoritative sizing/liquidation)
  -> three-step review -> save draft or prepare apply
  -> final confirmation -> authenticated execute once
  -> OKX isolated leverage + batch-orders -> durable per-order result
  -> authenticated list/status + direct 1-second SWAP ticker
```

The 500-candle scanner is a strategy-specific extension or separate repository/calculator instance; the existing watchlist keeps its current 300-candle and five-per-side behavior. The browser never receives API credentials and never sends private OKX writes. A saved draft is revalidated against live instrument/account state at application; its price levels are not silently rewritten.

Private API additions (all require the existing session): `POST /v1/strategies/preview` (authoritative sizing and conditional liquidation from selected levels/budget with current instrument, tier and fee metadata), `POST /v1/strategies` (save validated preview as draft), `GET /v1/strategies` (list/status), `POST /v1/strategies/{id}/prepare-apply` (fresh authoritative normalized order summary and short-lived confirmation token), `POST /v1/strategies/{id}/execute-apply` (consume token once), `GET /v1/strategies/{id}/result` (reconcile without resending), `POST /v1/strategies/{id}/delete` (draft-only). JSON responses include a stable strategy ID and per-order statuses; every write is account-bound and rate-limited. The existing bearer/session, origin, request-size, and account-fingerprint protections apply. No protected configuration file changes are required.

States: `DRAFT -> PREPARED -> APPLYING -> APPLIED | PARTIAL | UNKNOWN`. An expired/cancelled prepare returns to `DRAFT` only if no live mutation began. A failed or uncertain leverage/order write cannot be reported as a clean draft without reconciliation. Batch acknowledgement means acceptance or per-order rejection, not fill. Pending, partial-fill, filled, cancelled/rejected, and unknown order states remain distinct.

## 6. Invariants and failure behavior

- INV-001: A strategy uses one USDT linear SWAP, one selected UTC candle interval and one account fingerprint; Spot prices and another account never enter its calculation or execution.
- INV-002: The summed planned and normalized order margin never exceeds the entered total margin; total selected orders never exceeds 20.
- INV-003: Every order has a stable unique `clOrdId`. Once a batch attempt is durably marked started, duplicate execute/status requests cannot send it again.
- INV-004: Draft deletion is atomic and allowed only before any application attempt; applied/partial/unknown strategies have no mutation action in this feature.
- INV-005: Private data and OKX trade writes require the existing authenticated backend session. Frontend public polling never carries private credentials.
- INV-006: Pre-trade liquidation values are marked estimates; after fills, use only exchange `liqPx` for the actual current position.

| ID | Case | Required result |
|---|---|---|
| EDGE-001 | Fewer than five valid candles or no swing on a requested side | Show sparse/no-level state; cannot advance with a side lacking an entry. |
| EDGE-002 | Selection exceeds 20, entry is not nearest, duplicate/cross-side level, invalid budget or undersized contract | Reject before save/prepare; no OKX write. |
| EDGE-003 | Account Net mode for two sides; existing swap position or pending order; wrong account/session | Prepare fails with actionable reason; no leverage or batch write. |
| EDGE-004 | Quote or candle fetch fails/ages; account poll fails | Show last successful timestamp and stale/unavailable label; never silently substitute Spot or old data. |
| EDGE-005 | Batch partially accepted, times out, or returns malformed per-order acknowledgement | Persist partial/unknown state, reconcile via client order IDs; never resubmit the same batch automatically. |
| EDGE-006 | Application price/metadata changes after draft save | Present fresh normalized preview or reject stale contract; require a new confirmation before a write. |

## 7. RED / GREEN and acceptance

- RED-001 / AC-001: Given open/wrong-instrument candles and a requested H12 SWAP, they create no selected level; fewer valid candles are honestly reported. A fixture with exactly 500 valid candles never uses candle 501.
- GREEN-001 / AC-002: A known 500-candle H6 fixture yields deterministic support/resistance cards; selected closest entry and outward DCA produce the independently calculated margin weights and contract sizes within the budget.
- RED-002 / AC-003: With an existing position/pending order, wrong account, Net mode for two sides, stale confirmation, or duplicate execute, the backend emits zero new batch placements.
- GREEN-002 / AC-004: After explicit confirmation, one eligible strategy sets each side's isolated leverage and sends one batch of at most 20 correct limit orders; saved per-order IDs/status survive restart and later status reads do not resend.
- RED-003 / AC-005: A partial/unknown batch, unfunded size, or an already attempted strategy cannot be represented as a deletable draft or as fully successful.
- GREEN-003 / AC-006: An authenticated draft can be saved, listed, applied later, and only a never-attempted draft can be deleted.
- GREEN-004 / AC-007: The applied list displays exchange PnL/entry/liq and filled-only used margin with a 1-second direct SWAP quote timestamp, while no fills give an unavailable PnL percentage.

Formal verification order per implementation task is RED then GREEN. Tests use fake OKX transport and local state; no live order is sent during automated tests.

## 8. Security, compatibility and rollout

Use the current login and account fingerprint. Before live application, inspect live account position mode, target instrument positions and pending orders with a fresh backend request. Keep the existing position-action API unchanged. UI may display account-derived PnL, but any external trade that changes the account position must be indicated as a source/attribution change instead of claiming it is purely strategy PnL.

Backend SQLite schema initialization adds only strategy/order records; existing rows remain readable. Rollout is additive: deploy backend API first, then Flutter client/UI. A backend failure must not cause the client to send direct private OKX requests. Rollback hides the new UI/API without deleting strategy records or cancelling exchange orders. Live verification of actual trading remains user-directed after deployment; fake-transport tests establish request shape/idempotency locally.

Protected configuration/environment actions: none planned. Agents must not inspect or modify protected files. If deployment requires a new setting not evidenced by current code, stop and ask for the minimum non-sensitive target/location fact.

## 9. Traceability and completion gate

| Requirements | Acceptance | Plan step | Task |
|---|---|---|---|
| REQ-001..REQ-005 | AC-001, AC-002, AC-007 | P02 | T39 |
| REQ-006..REQ-007 | AC-003..AC-006 | P01 | T38 |
| REQ-008 | AC-007 | P01, P02 | T38, T39 |

- [x] liquidation estimate method and required OKX inputs finalized
- [x] all material questions resolved and plan presented for approval
- [ ] no protected configuration content read or modified
- [ ] task RED/GREEN, buildability, and final integration audit pass

## Change Log

| Revision | Change | Reason |
|---|---|---|
| 1 | Initial cross-layer contract. | User request and D-001..D-015. |
