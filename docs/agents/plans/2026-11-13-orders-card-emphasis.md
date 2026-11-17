# Small Change Plan: Pair and profit emphasis in the Orders list

Status: COMPLETE
Approval: "Duyệt, commit, làm" (user, chat, 2026-11-13, on this revision)
Date: 2026-11-13
Tier: S
Plan ID: PLAN-20261113-orders-card-emphasis
Design reference: `designs/CLAUDE_DESIGN_HANDOFF.md` §Positions ("instrument, Long/Short, leverage, … large signed unrealized PnL") and `designs/handoff-assets/03-binance-orders.png`.
Domain: mobile (Flutter). Web F0–F3 does not apply. Uses the app's own `AppPalette`, `AppTokens`, `CryptoIcon` and `resolvePnlColor`.

## Objective

In `Lệnh` → `Vị thế`, the pair name and the profit or loss stand out, and the profit or loss is colored. The margin card stops being a plain block of text.

## Decisions (user requests 2026-11-13: "nổi bật tên cặp giao dịch, số tiền lãi lỗ", "phần lãi lỗ phải tô màu"; the layout details are recommendations confirmed by approving this plan)

- D-009: Margin card layout, in the same card style as the futures position card (`palette.raised`, border, `AppTokens.radiusMedium`, padding 12, margin zero):
  1. Header: `CryptoIcon` of the base asset, then the pair (`SOL/USDT`, or the asset for Cross, e.g. `SOL`) at 16 bold in `palette.ink`. A badge on the right reads `Isolated Margin` or `Cross Margin`, at 12 bold on `palette.surface`.
  2. Profit block, when an estimate figure exists: the signed amount (for example `-26.08 USDT`, or in đ with the existing rate) at 22 w800, then the percentage `(-48.69%)` at 13 w600. When capital is invalid, the percentage is omitted as in T131. Below that, `Lãi/lỗ ước tính` at 12 in `palette.muted`, then a 12 muted line: `Giá vốn TB …`, plus `· tính trên N% lượng`, `· chưa cập nhật` and the row message, as applicable.
  3. No figure but a message (`Chưa tính`, `Chưa đủ dữ liệu giá vốn`, `Đang tải lịch sử`): the message at 13 in `palette.muted`. No estimate at all, or balances hidden: no profit block, as today (AC-208).
  4. A divider, then the existing detail lines with the same strings at 12 in `palette.muted`: Net, Vay and Lãi vay for each asset, `Mức ký quỹ`, `Giá thanh lý`, `Giá chỉ số`.
- D-010: Color. The amount and the percentage use `resolvePnlColor(profit, palette, hidden: …)`, the same rule as the futures card: positive is green, negative is red, near zero is muted.
- D-011: Futures position card. The pair grows from 14 to 16 and the unrealized amount from 14 to 18 w800. It is still colored by `resolvePnlColor`. Nothing else in its layout changes.
- D-013 (user, 2026-11-13, multi-platform): both cards render only from the shared models `MarginAccountRow`, `InstrumentKey` and `ExchangePosition`, with no exchange-specific branch. Every field may be null: the pair falls back to `nativeId`, values to `—`, and the profit block is absent without an estimate. The futures card change applies equally to OKX and Binance positions. Today only Binance fills `marginRows`; any adapter that fills them later gets the same card.
- D-012: Out of scope: the `Chờ khớp` and `Lịch sử` cards, OKX-only behavior, the estimate math, and the Assets page.

## Evidence and Scope

- OBS-007: `margin_account_card.dart:32-54`. The card is plain `Text` lines with no style, and the estimate arrives as one string (`estimateText`).
- OBS-008: `orders_screen.dart:783-1000`, the futures card. The pair is 14 bold. The amount is 14 bold, colored, inside a `Lãi / Lỗ chưa thực hiện:` row.
- Allowed files:
  - `lib/features/orders/presentation/widgets/margin_account_card.dart`
  - `lib/features/orders/presentation/orders_screen.dart`
  - `lib/exchanges/binance/binance_estimated_pnl.dart`: only to add a read-only `percentage` getter on `EstimatedPnlRow`, with no behavior change; `estimatedPnlText` output must stay identical.
  - `test/features/orders/orders_binance_view_test.dart`
  - `test/features/orders/presentation/orders_screen_position_layout_test.dart`
- Preserved behavior: the `Isolated Margin` and `Cross Margin` text (tests search for it), the hide rules, polling and run rules, the Assets estimate text, the futures card keys and actions, and no overflow at width 320 with text scale 2.0.

## Implementation Step — P03

1. `MarginAccountCard` takes a structured estimate instead of a string: `EstimatedPnlRow? estimate`, `double rate`, `String unit`. `orders_screen.dart` passes what it passes today (null when hidden or not available).
2. Build the D-009 layout and the D-010 colors.
3. Apply D-011 to `_buildPositionCard`.

Worked figures, derived independently:

- W9: T131 W1 row (`SOL/USDT`, profit −20.50, capital 50). The card shows `SOL/USDT` at 16 bold, the badge `Isolated Margin`, `-20.50 USDT` at 22 colored `palette.negative`, and `(-41.00%)` colored `palette.negative`.
- W10: T131 W2 short row. The amount `+10.00 USDT` and `(+20.00%)` are colored `palette.positive`.
- W11: capital invalid (T131 W3). `-20.50 USDT` is shown, there is no `%` text, and the color is negative.
- W12: no figure, message `Chưa đủ dữ liệu giá vốn`. No amount, the message is shown in `palette.muted`.
- W13: futures card with `unrealizedPnl 64.2`. `+64.20` at 18 colored positive, pair at 16.

Tests: W9–W12 in `orders_binance_view_test.dart` (replacing the T131 card-text expectation with structured checks of text, size and color). W13 in `orders_screen_position_layout_test.dart`. The existing large-text test at 320 and scale 2.0 must still pass.
RED: W9, W10 and W13 on the current code fail on font size or color, because the current margin card text has no style and the futures pair and amount are at 14.
GREEN: both test files pass, then V3 `test/features/orders`.
Verification ceiling: V3 (`test/features/orders`).

Task buildability gate: YES. Command as in T132 (compile check on the host).
Stop if: the change needs a file outside the list, or a change to estimate math or to text used by the Assets page.

## External Verification / Configuration

None. The user checks visually after deploying.

## Planning Workstreams

Fan-out Required: NO. Skip Reason: SINGLE_MATERIAL_WORKSTREAM (mobile client UI). The Sol advisor was not used because sharing is not authorized.

## Task

T133: `tasks/task_133_orders_card_emphasis.md`. E3, `gpt-6.1-terra / high` (multi-file UI integration with layout invariants). Its write surface is disjoint from T132, but it runs after T132 because there is one writer per checkout.

## Approval Gate

- [x] no material ambiguity (D-009 to D-012, confirmed by plan approval)
- [x] scope bounded
- [x] RED then GREEN defined
- [x] build command defined
- [x] user approval obtained before implementation
- [x] no protected configuration needed
