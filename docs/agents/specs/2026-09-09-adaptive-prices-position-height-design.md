# Adaptive prices and content-sized position cards

## Requirements and evidence
Fractal currently formats current/open/high/low prices using `#,##0.00` in fractal_screen.dart. Orders `_formatNumber` already uses value-based precision: zero has two decimals, values >= 1000 have two decimals, values >= 1 have two to four decimals, smaller values have two to eight decimals. This is magnitude-based display precision, not exchange tick-size metadata.

Orders position cards are forced to 270 logical pixels through ResponsiveOrderGrid.mainAxisExtent on widths >= 600. Their content is shorter, producing the reported blank area. Mobile already uses natural-height list items.

## Decisions
Extract the existing Orders string formatter unchanged into `lib/core/formatting/adaptive_number_format.dart` as `formatAdaptiveNumber(String value)`. Preserve empty (`--`), invalid (original string), zero, sign and rounding behavior. Use it for existing Orders call sites and all four Fractal price labels, converting numeric inputs to strings and retaining missing-price placeholders. Preserve USD prefix, percentages, dates, balances, quantities and price calculations. Precision is chosen per value; no symbol-specific mapping or API calls.

Make ResponsiveOrderGrid.cardExtent optional. A supplied extent retains current list/grid behavior. An omitted extent uses a lazily built ListView of rows with the existing column breakpoints (600/900/1600), 12-pixel outer padding and horizontal/vertical gaps on multi-column screens; preserve mobile's 8-pixel gap. Rows top-align equal-width children and reserve empty slots in incomplete final rows. Cards take natural height; rows advance by their tallest card. Do not stretch cards or use intrinsic-height measurement. Omit extent only for positions, retaining order/history extent 190. Set position card Column.mainAxisSize to min explicitly.

## Acceptance
Fractal shows 0.09117 and 0.00001234 without rounding to 0.09 or 0.00, and keeps large-price grouping. Position card bounds end after content plus existing padding across mobile/tablet/desktop; variable-height neighbors, currency modes and supported text scales do not force blank card interiors or overlap following rows. Existing pending/history layout and grid API behavior remain compatible.
