# Implementation Plan: Estimated profit for Binance Spot and Margin

Status: COMPLETE (code); U3 pending
Approval: "Duyệt, làm đi" (user, chat, 2026-11-07)
Date: 2026-11-07
Tier: M
Plan ID: PLAN-20261107-binance-estimated-pnl
Specification: `docs/agents/specs/2026-11-07-binance-estimated-pnl-design.md`

## Planning Workstream Decomposition

Fan-out Required: NO. Skip Reason: SINGLE_MATERIAL_WORKSTREAM. Client only. The nginx change is a user-owned action. Backend application: not touched.

## Tasks

`T128 -> T129 -> T130 -> final audit -> U3 (user updates nginx, builds, checks live)`

| Task | Content | Class | Route |
|---|---|---|---|
| T128 | Pure calculation: moving average, coverage, profit | E3 | gpt-6.1-terra / high |
| T129 | Trade pages, budget, resume, store, provider | E3 | gpt-6.1-terra / high |
| T130 | Assets rows, summary, margin cards | E2 | gpt-6.1-terra / medium |

Executors write code and tests; the coordinator runs RED then GREEN on the host.

Verification: V3 per task; V4, analyzer, web build at the end. No new dependency.

## U3, user-owned

Add `myTrades` to both groups of the existing location, then `nginx -t` and reload:

`api/v3/(?:account|openOrders|allOrders|myTrades)` and `sapi/v1/margin/(?:account|isolated/account|openOrders|allOrders|myTrades)`.

Do this before deploying the new build. Then check live with a read-only key.

## Risks

| Risk | Mitigation |
|---|---|
| Figures read as exact | `Ước tính` label; never added to USDⓈ-M |
| Coins from deposits, transfers or non-USDT pairs have no cost | Coverage check against the holding; insufficient-data state |
| Spot to Margin transfers leave trades in one wallet and coins in the other | Same coverage check |
| History retention unknown | Live check in U3; older trades missing lowers coverage |
| Trade history passes through Cloudflare and the VPS on web | Already the case for orders; no access log; read-only key |
| Weight limit on the VPS IP | 30-page budget, 60-second minimum, no polling |
| Margin route limits come from a search summary | Tests do not depend on them; T129 pages by `fromId`; live check |

## Rollback

Remove the provider use from the UI, or remove `myTrades` from nginx: the app then shows insufficient data and everything else is unaffected.
