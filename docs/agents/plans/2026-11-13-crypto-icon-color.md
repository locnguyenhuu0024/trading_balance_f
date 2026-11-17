# Small Change Plan: Coin icons in color, compact margin details

Status: COMPLETE
Approval: "Duyệt, commit, làm" (user, chat, 2026-11-13, on revision 2; includes commit on PASS)
Date: 2026-11-13
Tier: S
Plan ID: PLAN-20261113-crypto-icon-color
Domain: mobile (Flutter).

## Objective

1. Coin icons show their original colors instead of being forced to grayscale.
2. The details under the divider on the Margin card (Orders) are compact, and every number there is rounded to 2 decimals.

## Decisions (user requests 2026-11-13: "làm cái icon có màu đi, đừng ép nó sang màu xám nữa"; "chú ý phần tôi tô đỏ … làm gọn nó đi, các số thập phân làm tròn đến 2 chữ số", screenshot of the SOL/USDT Isolated Margin card)

- D-018: Remove only the grayscale `ColorFiltered` wrapper around the network image in `CryptoIcon`. The image, its fallback chain and the letter fallback stay the same. This narrows the 2026-10-03 monochrome design (REQ-001) for coin logos only. The app palette, the letter fallback colors and every other icon stay monochrome. It works for every exchange, because `CryptoIcon` takes only a symbol.
- D-019: The Margin card details become a small table and one summary line.
  - Header row: an empty cell, then `Net`, `Vay`, `Lãi vay`.
  - Isolated: one row for the base asset and one for the quote asset. Cross: one row for the asset.
  - Numbers are right-aligned, size 12, with tabular figures.
  - Summary line (a `Wrap`, so it wraps on narrow screens):
    - Isolated: `Mức ký quỹ 1.53 · Giá thanh lý 54.64 · Giá chỉ số 79.77`.
    - Cross: `Mức ký quỹ 1.53`.
  - A missing value shows `—`.
  - The header, the PnL amount, the % and the `Giá vốn TB` line are unchanged.
  - This reads only `MarginAccountRow`, so it works for any exchange that fills it.
- D-020: These numbers use 2 decimals (`1.031967` → `1.03`, `-53.69700399` → `-53.70`, `0` → `0.00`).
  - Recommendation: a non-zero value below 0.01 keeps 2 significant digits instead of turning into `0.00`. For example, an amount of `0.00123` shows `0.0012`, and the price of a very cheap coin does not read as zero.
  - A non-numeric value is shown as is.

## Evidence and Scope

- OBS-013: `lib/core/widgets/crypto_icon.dart:223-263` wraps `Image.network` in `ColorFiltered(ColorFilter.matrix([0.2126, 0.7152, 0.0722, …]))`, a grayscale filter added by commit 3d12b7d (monochrome design).
- OBS-014: `CryptoIcon` is the shared coin icon for Market, Orders, Assets and the Margin card. No test asserts the filter.
- OBS-015: `lib/features/orders/presentation/widgets/margin_account_card.dart:66-83`. Under the divider, the card prints each value as a raw string in a long text line (`SOL: Net 1.031967 · Vay 0 · Lãi vay 0`, `Mức ký quỹ: 1.53270549`, …), with no rounding.
- OBS-016: `test/features/orders/orders_binance_view_test.dart:408` expects `Lãi vay` 3 times. After D-019 that is 2: one table header for each of the two cards.
- Allowed files:
  - T136: `lib/core/widgets/crypto_icon.dart`, `test/features/crypto_icon_urls/crypto_icon_url_test.dart`
  - T137: `lib/features/orders/presentation/widgets/margin_account_card.dart`, `test/features/orders/orders_binance_view_test.dart`
- Out of scope: the palette, the letter fallback, `ScopeBar`, other icons, the Futures/Spot cards, the estimate math.

## Implementation Steps

### P06 (T136)

`_CryptoIconState.build`: the `child` for a non-empty URL list is the `Image.network(...)` itself, with no `ColorFiltered`.

- W20: `CryptoIcon(symbol: 'BTC', …)` renders one `Image` and no `ColorFiltered`.

### P07 (T137)

Rebuild the part of `MarginAccountCard` under the divider as in D-019, with a private formatter as in D-020.

Worked expectations, using the screenshot row:
- Isolated SOL/USDT:
  - `baseNet 1.031967`, `baseBorrowed 0`, `baseInterest 0`;
  - `quoteNet -53.69700399`, `quoteBorrowed 53.56029479`, `quoteInterest 0.1759292`;
  - `marginLevel 1.53270549`, `liquidation 54.63722695`, `indexPrice 79.77249833`.
- W21: the cells show `1.03`, `0.00`, `-53.70`, `53.56` and `0.18`. The summary shows `Mức ký quỹ 1.53`, `Giá thanh lý 54.64` and `Giá chỉ số 79.77`. No raw text such as `1.031967` or `53.697` remains. `Net`, `Vay` and `Lãi vay` appear once each.
- W22: `baseNet 0.00123` shows `0.0012`. A missing `baseBorrowed` shows `—`.
- W23: at width 320 with text scale 2, there is no exception (the existing narrow test).

RED: the new tests fail on the current code. GREEN: the task files pass, then V3.

## Verification

- V3: `flutter test --no-pub test/features/crypto_icon_urls test/features/orders test/features/portfolio test/features/market`.
- Task buildability gate for both tasks: `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings && flutter build web --no-pub`.

## Planning Workstreams

Fan-out Required: NO. Skip Reason: SINGLE_MATERIAL_WORKSTREAM (mobile UI only).

## Tasks

The tasks run in sequence, with one writer per checkout.

1. T136: `tasks/task_136_crypto_icon_color.md`. E1, `gpt-6.1-terra / low`.
2. T137: `tasks/task_137_margin_card_compact_details.md`. E2, `gpt-6.1-terra / medium`. Depends on T136 = PASS.

## Approval Gate

- [x] no material ambiguity (D-018 to D-020; the small-value rule in D-020 is a recommendation, confirmed by approving this plan)
- [x] scope bounded
- [x] RED then GREEN defined
- [x] build command defined
- [x] user approval obtained before implementation
- [x] no protected configuration needed
