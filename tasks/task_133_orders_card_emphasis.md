# Task 133 — Pair and profit emphasis in the Orders list

Status: READY
Agent Role: implementation_executor
Executor Class: E3
Target Model: gpt-6.1-terra
Target Effort: high
Target Route: gpt-6.1-terra / high
Routing Policy: EXECUTOR_ROUTING_POLICY.json v2 (OptCodex v1.4.0)
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Plan: `docs/agents/plans/2026-11-13-orders-card-emphasis.md`
Plan Steps: P03
Decisions: D-009, D-010, D-011, D-012

## 1. Dispatch Compliance

Dispatch Route Status: PENDING
Requested Model: PENDING
Requested Effort: PENDING
Observed Effective Model: unavailable
Observed Effective Effort: unavailable

## 2. Objective

The margin card and the futures position card in `Lệnh` → `Vị thế` show the pair and the profit or loss prominently, with the profit or loss colored.

Done when: tests prove W9 to W13 from the plan, and every existing test in `test/features/orders` passes.

## 3. Preconditions

Predecessors: none by contract. T132 runs first only because there is one writer per checkout; this task uses none of T132's files. Clean checkout.

## 4. Allowed Scope

Exact write list. Read access covers any non-protected source or test.

- `lib/features/orders/presentation/widgets/margin_account_card.dart`
- `lib/features/orders/presentation/orders_screen.dart`
- `lib/exchanges/binance/binance_estimated_pnl.dart`: only a read-only `double? get percentage` on `EstimatedPnlRow` (`estimate.profit / capital * 100`, or null when `estimate` or `capital` is null). `estimatedPnlText` may use it, but its output must stay byte-identical.
- `test/features/orders/orders_binance_view_test.dart`
- `test/features/orders/presentation/orders_screen_position_layout_test.dart`

## 5. Forbidden Scope

- Do not read or change protected configuration, `backend/` or Git state.
- Do not change the estimate math, the Assets page, or the `Chờ khớp` and `Lịch sử` cards.
- No new dependency. No file outside the list.

## 6. Executor Contract

1. `MarginAccountCard({required row, EstimatedPnlRow? estimate, double rate = 1, String unit = 'USDT'})` replaces `estimateText`. In `orders_screen.dart`, pass the same estimate it builds today: null when hidden or when the account or cost view is missing. For VNĐ, pass `rate = exchangeRate` and `unit = 'đ'`, as today.
2. Card shell, matching `_buildPositionCard`: `Card(elevation: 0, color: palette.raised, margin: EdgeInsets.zero, shape: RoundedRectangleBorder(radius AppTokens.radiusMedium, side palette.border))`, padding 12.
3. Header row:
   - Left: `CryptoIcon(symbol: base, size 20, backgroundColor palette.surface, textColor palette.ink, textSize 10)`, then the pair text at 16 bold in `palette.ink`. Isolated shows `${base}/${quote}` (or `nativeId` when base or quote is null). Cross shows `row.asset ?? '—'`.
   - Right: a badge reading `Isolated Margin` or `Cross Margin`, 12 bold, `palette.surface` background, `AppTokens.radiusSmall`.
   - Wrap the sides so nothing overflows at width 320 and text scale 2.0. `Flexible` or `FittedBox`, as in the futures header, is acceptable.
4. Profit block, D-009 item 2. `e = estimate?.estimate`.
   - If `e != null`, show the amount `${sign}${(e.profit * rate).toStringAsFixed(2)} $unit` at 22 w800. If `estimate.percentage` is not null, follow it with `(${sign}${pct.toStringAsFixed(2)}%)` at 13 w600. Both are colored `resolvePnlColor(e.profit, palette, hidden: false)`. Below them, `Lãi/lỗ ước tính` at 12 muted. Then one muted 12 line: `Giá vốn TB ${(e.average * rate).toStringAsFixed(2)}`, plus ` · tính trên N% lượng` when `e.ratio < 0.999999`, ` · chưa cập nhật` when stale, and ` · ${message}` when a message exists.
   - If `e == null` and `estimate?.message != null`, show the message at 13 in `palette.muted`.
   - If `estimate == null`, show no block.
5. Then `Divider(height: 16, color: palette.border)`, then the existing detail lines with the same strings, each at 12 in `palette.muted`.
6. In `_buildPositionCard`, change `instrumentFontSize` from 14 to 16, and the unrealized amount `Text` to font size 18 with `FontWeight.w800`. Keep its color, the ratio text, the keys and everything else.

## 7. External Configuration / Environment Actions

None.

## 8. Tests

- TEST-133-1 (W9): isolated `BTCUSDT` row as in the T131 orders test (`baseNet 1`, `indexPrice 80`, `quoteNet -50.5`, `quoteInterest 0.5`; cost state quantity 1, cost 100, margin). Assert:
  - `BTC/USDT` text, font size 16, bold.
  - `Isolated Margin` text.
  - `-20.50 USDT` text, font size 22, color `AppPalette.light.negative`.
  - `(-41.00%)` text, color `AppPalette.light.negative`.
  - `Giá vốn TB 100.00` found by `textContaining`.

  This replaces the T131 single-string expectation on the card.
- TEST-133-2 (W10): short (`baseNet -1`, `indexPrice 90`, `quoteNet 150`; quantity −1). `+10.00 USDT` and `(+20.00%)` are colored `AppPalette.light.positive`.
- TEST-133-3 (W11): `quoteNet -100.5`. `-20.50 USDT` is shown, and no text containing `%)` is found inside the card.
- TEST-133-4 (W12): estimate row with message `Chưa đủ dữ liệu giá vốn` and no figure. The message is colored `AppPalette.light.muted`, and no `USDT` amount text is shown.
- TEST-133-5 (W13), in `orders_screen_position_layout_test.dart`: a futures position with `unrealizedPnl '64.2'`. `+64.20 ` (current format, with a trailing space) has font size 18 and color `AppPalette.light.positive`. The pair text has font size 16.
- TEST-133-6 (D-013, sparse data): an isolated row whose `InstrumentKey` has only its required fields, `nativeId: 'ETH-USDT'` and null base and quote, every other field null, and no estimate. It renders `ETH-USDT`, the `Isolated Margin` badge, the `—` detail values, and no profit block, with no exception. A cross row with `asset: null` renders `—` as the pair.
- TEST-133-7 (D-013): run W13 for both an OKX and a Binance `ExchangePosition`. Both have the pair at 16 and the amount at 18, colored positive.
- The card code contains no `ExchangeId` check.
- The existing large-text test at 320 and scale 2.0, and the hide test, still pass. Adapt only the widget constructor call (`estimate:` instead of `estimateText:`), not their assertions.

## 9. Mandatory Verification

### RED — RED-133
Scenario: TEST-133-1 and TEST-133-5 on the code before the change. For TEST-133-1, the coordinator compiles it against the old card through a temporary shim only if needed; otherwise a compile failure on `estimate:` counts as the observed RED.
Command: `flutter test --no-pub test/features/orders/orders_binance_view_test.dart test/features/orders/presentation/orders_screen_position_layout_test.dart`
Expected: they fail (missing parameter, font size 14 instead of 16 or 18, no color).
Status: PENDING

### GREEN — GREEN-133
Scenario: the same command after the change, then V3 `flutter test --no-pub test/features/orders`.
Expected: all pass.
Status: PENDING

Verification ceiling: V3 (`test/features/orders`).

### Verification environment

The executor sandbox cannot run `flutter test` or compile. Write the complete code and tests. Report `red` and `green` as `NOT_RUN` with the tests named in RED then GREEN order, set `buildability` to `BLOCKED` with that reason, and set `status` to `COMPLETED`. In widget tests that use a `StreamController`, do not `await controller.close()` after dispose (AUD-131-01).

### Task Buildability Gate

Required: YES
Exact secret-free build command: `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings && flutter build web --no-pub`
Result: PENDING

## 10. Stop Conditions

Return `BLOCKED` if the change needs a file outside the list, a change to estimate math, or a change to text used by the Assets page.

## 11. Coordinator Audit

Verdict: PENDING
