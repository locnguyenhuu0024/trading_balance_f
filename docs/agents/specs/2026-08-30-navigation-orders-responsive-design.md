# Design Specification: Unified Navigation and Responsive Order Management

**Date:** 2026-08-30  
**Status:** Proposed; awaiting execution approval

## Objective

Make Market and Settings first-class destinations in the application navigation, introduce a compact high-contrast bottom navigation bar with a floating selected icon treatment, and redesign Order Management controls and collection layouts for phone, tablet, and large-screen use.

## Repository Evidence

- `MainNavigationShell` currently has three destinations: Home, BMAG, and Orders.
- `PortfolioScreen` opens `MarketScreen` and `SettingsScreen` with AppBar route-push buttons.
- `OrdersScreen` presents `OrderTab` with a `SegmentedButton`, instrument type with horizontal `ChoiceChip`s, and all position/order cards in a one-column `ListView`.
- The staged `test/widget_test.dart` is Flutter's sample counter test and fails to compile because it instantiates the removed `MyApp` class.

## Information Architecture

The root shell will own five destination screens, in this order:

1. Trang chủ (`PortfolioScreen`)
2. BMAG (`FractalScreen`)
3. Lệnh (`OrdersScreen`)
4. Thị trường (`MarketScreen`)
5. Cài đặt (`SettingsScreen`)

Market and Settings will no longer be opened from the Home AppBar. The Home AppBar retains only balance-visibility behavior. Settings save behavior must remain in place without attempting to pop the root navigation route.

## Navigation Bar Interaction and Visual Contract

- Render one continuous full-width navigation block with one background surface, rather than separate destination containers or Material 3's default selected pill.
- Use an inverse high-contrast palette: light theme has a black navigation surface and white selected circle; dark theme has a white navigation surface and black selected circle.
- Every destination always exposes an accessible Vietnamese label/tooltip. Visually, unselected destinations show only their icon.
- The selected icon appears inside a circular indicator whose foreground contrasts with the circle. Its animated vertical lift makes room for the selected label beneath it.
- Only the selected title is painted, using a color that contrasts with the navigation surface. Selection changes animate position, circle/icon state, and title appearance without clipping or overflow.
- Preserve `SafeArea`, touch targets of at least 48 logical pixels, semantic selection state, and tab switching without route pushes.

## Order Management Controls

Replace the tab/chip strip with two labeled select controls:

- **Trạng thái:** Vị thế, Đang chờ, Lịch sử, mapped to the existing `OrderTab` provider.
- **Loại giao dịch:** SPOT, MARGIN, SWAP, FUTURES, mapped to the existing filter provider.

On compact widths the controls stack; on wider widths they share a row. Existing provider values, API requests, refresh behavior, empty states, error states, and SPOT-position restriction stay unchanged.

## Responsive Card Collection

Card data and the current position/order card details remain intact. The list container adapts by available width:

| Available screen width | Columns |
| --- | --- |
| Under 600 px (phone) | 1 |
| 600–899 px (tablet portrait/compact landscape) | 2 |
| 900–1199 px (wide tablet) | 3 |
| 1200–1599 px (large screen) | 3 |
| 1600 px and above (large screen) | 4 |

Multi-column layouts use a grid with sufficient fixed vertical extent for the respective position or order card, consistent gutters, and content padding. One-column layouts retain scrolling and card density suitable for phones. The actual grid is selected from a reusable width-to-column calculation so breakpoints can be unit tested.

## Testability and Widget Coverage

`MainNavigationShell` will expose a narrowly scoped test injection seam for destination bodies while retaining its production default destinations. This prevents navigation-widget tests from calling OKX, secure storage, background-service, or WebSocket integrations.

Widget tests will replace the invalid sample in `test/widget_test.dart` and verify:

- the five destinations, initial Home state, selection, and selected-only label behavior;
- the navigation bar's contrast contract in light and dark mode, selected circular indicator, and selection animation completion;
- the absence of Market/Settings route-push buttons from Home;
- select controls update the existing order providers;
- one, two, three, and four column outcomes at representative viewport widths.

## Scope and Non-goals

### In scope

- Navigation shell, Home AppBar cleanup, Market/Settings tab integration, and necessary Settings save-flow adaptation.
- Custom navigation bar presentation and accessibility.
- Orders filters redesign and adaptive position/order grid.
- Focused widget/unit coverage, formatting, analysis, full tests, and a production web build.

### Out of scope

- Changes to OKX endpoints, models, request filters, persisted preference schema, theme preference behavior, or third-party dependencies.
- A masonry/staggered grid, changes to the contents of position/order cards, data pagination, or persistent navigation history per tab.
- Git commit, push, release, or deployment.

## Risks and Mitigations

- **Five tabs on small phones:** selected-only visual label and five evenly sized targets retain usable width; widget tests cover a narrow viewport.
- **Contrast regression across themes:** calculate foregrounds from the navigation surface and assert theme-specific colors in widget tests.
- **Settings used as a tab:** prevent API-save success from popping the root navigator while preserving the success notification.
- **Fixed-height grid cards:** size separately for position versus order card layouts and test narrow cards for overflow.
- **External data during tests:** use destination injection and Riverpod overrides so tests stay local and deterministic.

## Acceptance Criteria

- Market and Settings are reachable from the root navigation bar and no longer from Home's AppBar.
- The bottom bar is visually one continuous block; only the selected destination shows a title; its icon is circularly highlighted, animated upward, and has sufficient contrast in light and dark modes.
- Order state and instrument filters are selects, not tabs/chips.
- Position, pending-order, and history-order collections show 1/2/3/3/4 columns at the documented breakpoints while retaining existing states and card content.
- `test/widget_test.dart` no longer references `MyApp` and the planned coverage passes together with analysis and the production web build.
