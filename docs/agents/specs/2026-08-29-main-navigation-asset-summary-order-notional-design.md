# Main Navigation, Asset Summary, and Order Notional Design

**Date:** 2026-08-29  
**Status:** Proposed; awaiting execution approval

## Context

The current Portfolio screen is the application root. BMAG Matrix, PnL History, and Orders are opened from individual AppBar actions with pushed routes. The total-asset summary is contained in a large decorated card. Orders and positions show quantity and price, but not the monetary exposure represented by each item.

This change must preserve the application's current monochrome light/dark palette, typography weights and sizes, Material icon vocabulary, Riverpod state, and existing OKX/Firebase behavior.

## User Outcome

1. Home, BMAG Matrix, PnL Journal, and Order Management are first-class destinations in a persistent bottom navigation bar.
2. The total-asset summary uses the available width more efficiently and no longer has an enclosing card/frame.
3. Each order or position exposes the monetary value being traded, using the application's selected currency display mode.

## Design Decisions

### 1. Application navigation shell

- Add a root navigation shell with four destinations in this order:
  1. `Trang chủ` using the existing home icon family.
  2. `BMAG` using the existing `donut_small` icon family.
  3. `Nhật ký` using the existing `history_edu` icon family.
  4. `Lệnh` using the existing `receipt_long` icon family.
- Use Material 3 `NavigationBar` so the control inherits the current theme and icon system.
- The shell owns the selected index and renders the selected screen in place instead of pushing a new route. Timer-backed screens are therefore disposed when inactive and restarted when selected, avoiding concurrent one-second/two-second polling across hidden destinations.
- Keep the Market, balance-visibility, and Settings actions in the Home AppBar. Remove the BMAG, PnL History, and Orders AppBar actions because those destinations move to the navigation bar.
- Both the normal launch path and the post-biometric-authentication path enter the same shell.
- Settings and Market remain secondary pushed routes and are not added to the bottom navigation bar.

### 2. Frameless, responsive total-asset summary

- Replace the decorated top card with a flat, full-width summary section made from spacing and typography only.
- Remove the enclosing background fill, border, corner radius, and shadow.
- Retain all current information: total assets, original capital, unrealized PnL amount, unrealized PnL percentage, currency conversion, and hidden-balance behavior.
- Use the current neutral text colors and green/red PnL semantics. The primary amount follows the current screen text color so it remains readable without the black card background.
- On compact widths, place the total first and arrange original capital and PnL as two balanced columns below it. On wider widths, use the horizontal space for a denser multi-column summary.
- Keep a lightweight spacing/divider boundary before `Tài sản chi tiết`; this separates content without recreating an outer card.

### 3. Monetary value in Order Management

For this design, “the money being traded” means **notional exposure**, not raw quantity, fees, realized PnL, or an estimate of margin after leverage.

- Extend the position model with OKX's `notionalUsd` response field.
- Extend the order model with the monetary and execution fields required to resolve an order value, including `notionalUsd`, `fillNotionalUsd`, `avgPx`, `accFillSz`, and `tradeQuoteCcy` where returned by OKX.
- Resolve the displayed amount in this order:
  - Open position: use `notionalUsd`.
  - Filled or partially filled order: prefer `fillNotionalUsd`.
  - Pending order: use `notionalUsd` when supplied.
  - SPOT/MARGIN fallback only: derive quote value from a valid effective price and size because those quantities have defined base/quote semantics.
  - FUTURES/SWAP fallback: display `--` when OKX does not provide notional data; do not multiply contract quantity by price without contract metadata.
- Display the resolved USD/USDT-equivalent notional through the existing currency amount formatter so the selected `USD`, `VNĐ`, or `USDT + VND` mode is respected.
- Respect the existing hide-balance state for these newly displayed amounts.
- Add the value as a compact labeled row/column within the existing order and position cards. Preserve the cards' current borders, fonts, colors, status badges, and crypto icons.
- Invalid, empty, zero-only, or unavailable values render as `--` instead of a misleading amount.

The OKX API documentation identifies position `notionalUsd` as the USD notional value and order `fillNotionalUsd` as the filled USD notional. It also documents derivative size in contracts, which is why derivative multiplication is explicitly excluded from the fallback: <https://www.okx.com/docs-v5>.

## State and Lifecycle

- Navigation selection is local UI state owned by the root shell and resets to Home on a fresh app launch.
- Existing Riverpod providers retain selected BMAG coin, order tab/filter, theme, currency mode, and balance visibility while the app remains alive.
- Local scroll position is not guaranteed when switching destinations because inactive timer-backed screens are disposed. Persisting per-tab scroll offsets is outside this change.

## Accessibility and Responsive Behavior

- Every navigation destination has an icon and visible text label.
- Selected/unselected states maintain sufficient contrast in both light and dark modes.
- Monetary text can wrap or use the existing two-line currency presentation without horizontal clipping on narrow screens.
- Existing tooltips remain for AppBar actions.

## Non-Goals

- Redesigning BMAG, PnL History, Market, Settings, or the individual asset cards.
- Changing the application's palette, font family, icon library, or general visual identity.
- Changing OKX endpoints, polling intervals, authentication, Firebase persistence, or trade execution behavior.
- Showing fees, collateral/margin used, liquidation risk, or additional trade analytics beyond notional value.
- Adding a routing dependency or changing deep-link behavior.

## Acceptance Criteria

- The four requested destinations are reachable from a bottom navigation bar, with Home selected initially.
- Switching destinations does not grow the Navigator route stack and hidden timer-backed destination screens do not continue polling.
- Home no longer duplicates BMAG, PnL, or Orders in its AppBar.
- The total-asset summary has no enclosing decoration and retains all existing values, conversion modes, color semantics, and masking behavior.
- The summary remains readable at narrow phone and wide web/tablet widths.
- Position and order cards show a notional monetary value when trustworthy source data exists, in the active currency display mode.
- Derivative cards never present a guessed notional based only on contract count and price.
- Existing light/dark tone, fonts, Material icons, filters, refresh behavior, and data loading states remain intact.

