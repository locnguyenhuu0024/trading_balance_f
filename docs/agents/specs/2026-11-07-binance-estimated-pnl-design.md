# Specification: Estimated profit for Binance Spot and Margin

Status: APPROVED
Date: 2026-11-07
Plan: `docs/agents/plans/2026-11-07-binance-estimated-pnl.md`

## 1. Problem

Binance balance endpoints return no entry price, cost or profit for Spot, Cross Margin or Isolated Margin. Only USDⓈ-M reports unrealized profit. A figure for the other wallets must be computed from the user's trade history, and it is an estimate.

## 2. Evidence

| Fact | Source |
|---|---|
| `/api/v3/account` has `free` and `locked` only | Binance Spot account docs, read 2026-11-07 |
| Cross and isolated margin account responses have no cost or profit field | Binance Margin docs, read 2026-11-07 |
| `/api/v3/myTrades`: `symbol` required, weight 20, limit 500 to 1000, fields `id`, `price`, `qty`, `quoteQty`, `commission`, `commissionAsset`, `time`, `isBuyer` | Binance Spot account docs |
| `/sapi/v1/margin/myTrades`: `symbol` required, `isIsolated` optional, weight 10, limit 500 to 1000, `fromId` pages, without `fromId` only 24 hours return | Binance docs through a search summary; the page text was not readable directly |

The margin trade route has no `quoteQty`, so its value is `price * qty`.

Unknown until the live check: how far back trade history goes, and whether `fromId=0` returns the oldest trade on both routes.

## 3. Requirements

- REQ-201: Each non-stablecoin Spot, Cross Margin and Isolated Margin holding shows average cost and an estimated unrealized profit, or says that data is insufficient.
- REQ-202: Every figure is labeled `Ước tính`. It is never added to the USDⓈ-M profit figure.
- REQ-203: A figure covers only the quantity that trades explain, and says so when that is less than the holding.
- REQ-204: Reading history does not slow the account read and does not run on the 5-second poll.
- REQ-205: History failure leaves balances, totals and USDⓈ-M unchanged.
- REQ-206: Stored cost data is derived values only, and is removed when the Binance connection is deleted or its key changes.
- REQ-207: The hide-balance setting hides these figures. OKX is unchanged.
- REQ-208: A web build without the proxy makes no trade request and shows no estimate.

## 4. Calculation

Per wallet and symbol, trades are applied oldest first with moving average cost, in USDT.

- Buy: quantity increases; cost increases by `quoteQty`. A fee in the base asset reduces quantity; a fee in USDT adds to cost.
- Sell: cost falls in proportion to quantity sold. A fee in USDT reduces proceeds on a short.
- A fee in any other asset, such as BNB, is ignored.
- Spot quantity never goes below zero. A sale beyond known quantity sold coins of unknown cost, so the excess is dropped.
- Margin quantity is signed. Short cost is net proceeds. Crossing zero restarts the average at that trade's price for the remainder.

Coverage compares trade quantity `t` with the holding `h`, the Spot total or the margin net asset:

- Opposite signs, or `t` is zero: insufficient data.
- Otherwise `covered = min(|t|, |h|)` and `ratio = covered / |h|`.

Profit on the covered quantity:

- Long: `covered * (mark - average)`. Short: `covered * (average - mark)`.
- Margin rows subtract current unpaid interest, valued at mark. Interest already paid is not known and is not subtracted.
- Percentage: profit divided by `covered * average`. Amended 2026-11-13 for Isolated Margin rows, the Assets summary and `Vốn gốc`: see `docs/agents/plans/2026-11-13-binance-margin-own-capital-pnl.md` (D-001 to D-003).

Mark comes from the account read: `valueUsdt / amount` for balances, `indexPrice` for isolated rows.

### Worked example 1, Spot

Buy 1 BTC at 100, fee 0.001 BTC. Buy 1 BTC at 200, fee 0.2 USDT. Sell 0.5 BTC at 300. Holding 1.499 BTC, mark 250.
Average `150.1751`, cost `225.1125`, profit `+149.6375`, percentage `+66.47%`, coverage 100%.

### Worked example 2, Margin short

Sell 2 BTC at 100, fee 0.2 USDT. Buy 1 BTC at 80. Net asset -1 BTC, unpaid interest 0.01 BTC, mark 90.
Average `99.9`, profit before interest `+9.9`, after interest `+9.0`.

### Worked example 3, partial coverage

Buy 1 BTC at 100. Holding 4 BTC, mark 110. Covered 1, ratio 25%, profit `+10.00`, labeled `tính trên 25% lượng`.

## 5. Reading history

- Symbols: `<asset>USDT` where that instrument exists, for Spot and Cross Margin; isolated symbols with quote USDT. Top 20 holdings by value; others show `Chưa tính`.
- Pages: `limit=1000`, `fromId` starts at 0 and then continues after the last stored trade id.
- Budget: at most 30 pages per run, about 600 weight at most. A symbol still unfinished is marked `Đang tải lịch sử` and resumes on the next run.
- A run starts when the Assets or Orders screen opens, or on pull to refresh, at most once per 60 seconds. It never joins the 5-second poll.
- A credential failure ends the run with no retry. Other failures keep previous data for that symbol and mark it stale.
- Store: `SharedPreferences`, per product and symbol: last trade id, quantity, cost, completed flag. No raw trades.

## 6. Display

- Assets row: `Giá vốn TB 150.18 · Ước tính +149.64 USDT (+66.47%)`.
- Margin card: same line.
- Partial: append `· tính trên 25% lượng`.
- No figure: `Chưa đủ dữ liệu giá vốn`.
- Assets summary, separate from the USDⓈ-M line: `Ước tính Spot · Margin: +X (Y%)`, with `Tính trên N/M tài sản`.
- USDT shows nothing.

## 7. Acceptance Criteria

- AC-201: Worked examples 1 to 3 produce the stated values.
- AC-202: Deposited coins with no trades show `Chưa đủ dữ liệu giá vốn`.
- AC-203: Second run requests only trades after the stored id.
- AC-204: 30-page budget is enforced and resumes.
- AC-205: Account poll triggers no `myTrades` request.
- AC-206: History failure leaves the total unchanged and shows no false figure.
- AC-207: Deleting the connection removes stored data; another key does not read it.
- AC-208: Hidden balance hides the figures. OKX screens are unchanged.
- AC-209: Web without proxy: zero trade requests.

## 8. Non-Goals

Realized profit, tax reporting, fees in other assets, non-USDT pairs, transfer history, manual cost entry, the details screen.
