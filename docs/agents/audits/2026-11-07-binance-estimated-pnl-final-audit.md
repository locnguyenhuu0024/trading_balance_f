# Final audit: Estimated profit for Binance Spot and Margin

Plan: `PLAN-20261107-binance-estimated-pnl`
Date: 2026-11-07
Verdict: PASS for code. Live behavior is pending U3.

## Coordinator-observed results

- Full suite: 666 tests pass.
- Analyzer: 0 errors, 156 warnings and infos, up from 138.
- `flutter build web --release` passes with `BINANCE_PROXY_URL`.
- The proxy does not allow `myTrades` yet: `GET /binance-proxy/api/v3/myTrades` returns 404 from the live host.
- RED by mutation: T128 ten, T129 fourteen, T130 thirteen. Two T129 survivors are equivalent. Two others exposed missing tests, which the coordinator added.

## Tasks

| Task | Attempts | Verdict | Notes |
|---|---|---|---|
| T128 | 1 | PASS | Coordinator added a test for a Spot sale from zero |
| T129 | 2 | PASS | Margin route has no `quoteQty`; the first pass failed every margin symbol and its fixture hid it |
| T130 | 2 | PASS | False state during a run; three coordinator test corrections |

The final attempts of T129 and T130 returned no valid executor report. Those verdicts rest on coordinator evidence only.

## Not verified

- Any read of real trades: `fromId=0` behavior, page order and history retention on both routes.
- The margin route's documented limits, which came from search summaries and a generated client model, not the page itself.
- Native iOS and Android builds, still pending from the parent plan.

## Known limits

- USDT pairs only. Fees in other assets are ignored. Paid interest is unknown. Unrealized only.
- The mark comes from `valueUsdt`, rounded to 2 decimals, so very small holdings have a less exact percentage.
- A run starts when a screen first has account data and on pull to refresh. A screen kept alive does not start another run until pull to refresh.
- Before `myTrades` is added to nginx, a deployed web build shows `Chưa đủ dữ liệu giá vốn`, and balances are unaffected.
