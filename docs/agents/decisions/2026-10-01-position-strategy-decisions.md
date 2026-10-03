# Decisions: Position Strategy

Status: ACTIVE
Specification: `docs/agents/specs/2026-10-01-position-strategy-design.md`
Plan: `docs/agents/plans/2026-10-01-position-strategy.md`

## User Decisions

| ID | Decision | Consequence |
|---|---|---|
| D-001 | Offer H6, H12, D1, and W1 in the creation popup. | Fetch the actual selected UTC candle interval; analyze up to 500 available closed candles. |
| D-002 | Applying a strategy submits every selected limit order to OKX immediately. A saved draft can be applied later without editing. | A final confirmation shows the exact orders before any live write. |
| D-003 | The entered USDT amount is real margin before leverage and is shared by Long and Short. | Let the user enter the side split, defaulting to 50/50. Order notional equals allocated margin times side leverage. |
| D-004 | Use isolated margin. | Leverage defaults to 5 and is at most 10, separately configured per selected side. |
| D-005 | Select one entry level per side; other selected levels are DCA. | Entry must be the selected level nearest the current price on its side. |
| D-006 | For increasing/decreasing allocation, use linear weights in entry-to-farthest-DCA order. | Equal uses identical weights; increasing uses 1..n; decreasing uses n..1. |
| D-007 | Limit a strategy to 20 selected orders in total. | One OKX batch request can hold the strategy's order set. |
| D-008 | In two-sided mode, block application when the OKX account is in Net mode and guide the user to switch to Hedge mode. | The app never changes account position mode automatically. |
| D-009 | Reject application when the selected coin already has an OKX position or pending order. | Preflight and immediately-before-write checks must detect both. |
| D-010 | Before execution show estimated liquidation after each sequential fill; after execution show actual OKX `liqPx`. | The review must label estimates as estimates and never imply exchange certainty. |
| D-011 | The frontend obtains the one-second public price feed directly from OKX, consistent with the existing app approach. | Private account/order data continues through the authenticated backend at a suitable independent cadence. |
| D-012 | Running PnL uses the actual OKX position, and used capital counts only filled orders' margin. | PnL percent uses filled margin as its denominator; no filled position has unavailable PnL percent rather than division by zero. |
| D-013 | A saved draft can be applied later and cannot be edited. | Draft deletion is permitted; any strategy with an application attempt is immutable. |
| D-014 | Both immediate application and later draft application require a final order-list confirmation. | Cancel or dismiss sends no live trade write. |
| D-015 | The USDT budget covers margin only; estimated opening fees are additional. | Review shows estimated fees separately and never counts them as used margin. |

## Repository Evidence

- `backend/service.py` exposes authenticated position actions but no strategy or batch-order route.
- `backend/store.py` has no durable strategy records.
- `lib/features/support_resistance` is scoped to 300 candles and lacks H12, so its existing result is not the strategy's 500-candle contract.
- Official OKX API documentation describes 12H UTC candles and a batch-order endpoint limited to 20 orders with possible per-order partial success: https://www.okx.com/docs-v5/en/

## Change Log

| Revision | Change | Reason |
|---|---|---|
| 1 | Recorded decisions D-001..D-015. | Direct user replies during 2026-10-01 planning. |
