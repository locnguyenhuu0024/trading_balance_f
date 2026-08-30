# Implementation Plan: Main Navigation, Asset Summary, and Order Notional

**Date:** 2026-08-29  
**Status:** Proposed; awaiting execution approval  
**Design:** [`../specs/2026-08-29-main-navigation-asset-summary-order-notional-design.md`](../specs/2026-08-29-main-navigation-asset-summary-order-notional-design.md)

## Objective

Introduce a four-destination bottom navigation shell, redesign the Home total-asset summary as a frameless responsive section, and add trustworthy monetary notional values to the Order Management list while preserving the current visual system and behavior.

## Current Repository Context

- `lib/main.dart` launches `PortfolioScreen` directly in both normal and biometric-success paths.
- `lib/features/portfolio/presentation/portfolio_screen.dart` pushes BMAG, PnL History, and Orders from AppBar icon buttons and renders total assets inside a large decorated container.
- `lib/features/fractal_tracker/presentation/fractal_screen.dart`, `lib/features/orders/presentation/orders_screen.dart`, and Portfolio own recurring refresh timers.
- Order and position API models already parse quantity, prices, leverage, and PnL but omit notional fields returned by OKX.
- `PortfolioCurrencyAmount` already formats USD, VND, and dual USDT/VND output and supports hidden values.
- Existing tests cover portfolio currency formatting and the current Portfolio dual-currency screen.
- The root `implementation_plan.md` is historical only; this file is the canonical plan for the new change.

## Scope

### In scope

- Root bottom navigation for Home, BMAG, PnL Journal, and Orders.
- Removal of duplicate destination actions from the Home AppBar.
- Responsive, frameless total-asset summary.
- Parsing, resolving, formatting, and displaying position/order notional amounts.
- Focused unit/widget regression tests and full Flutter verification.

### Out of scope

- Redesigns of the destination screens beyond integration into the navigation shell.
- New API endpoints, dependencies, fonts, icon packages, or routing packages.
- Margin/collateral calculations, fee analytics, or speculative derivative notional calculations.
- Git commit, push, release, or deployment.

## Proposed Technical Approach

### A. Main navigation

1. Add `lib/core/navigation/main_navigation_shell.dart` as a stateful root shell.
2. Define four Material 3 `NavigationDestination` entries using the application's existing icons and compact Vietnamese labels.
3. Render only the selected destination inside the shell so inactive timer-backed screens are disposed.
4. Update `TradingBalanceApp` and `BiometricAuthScreen` to enter the shell.
5. Remove BMAG, PnL History, and Orders route-push buttons and now-unused imports from the Home AppBar; retain Market, visibility, and Settings.

### B. Portfolio asset summary

1. Extract or reorganize the total summary into a focused widget/helper within the Portfolio presentation layer.
2. Replace the decorated outer `Container` with responsive padding/layout and no background, border, radius, or shadow.
3. Use a compact-width layout for phones and a horizontal layout above an evidence-based breakpoint for wider screens.
4. Reuse `PortfolioCurrencyAmount` for total assets, original capital, and unrealized PnL so all display modes and masking remain unchanged.
5. Preserve current text hierarchy, grey neutrals, and green/red directional semantics while adapting the primary text color to the flat background.

### C. Order and position monetary value

1. Add the required OKX response fields to `OkxPosition` and `OkxOrder`.
2. Regenerate the Freezed and JSON serialization artifacts with the repository's existing build tooling.
3. Add a small pure resolver/formatter helper in the Orders feature that:
   - parses values safely;
   - chooses position notional, filled order notional, estimated order notional, or SPOT/MARGIN fallback in priority order;
   - rejects unsupported derivative guesses;
   - returns unavailable state explicitly.
4. Read the active currency mode, VND rate, and hide-balance state in `OrdersScreen`.
5. Add a compact `Giá trị vị thế`/`Giá trị lệnh` presentation to position and order cards using the existing currency amount component and style tokens.

## Expected Affected Files

- `lib/main.dart`
- `lib/core/navigation/main_navigation_shell.dart` (new)
- `lib/features/portfolio/presentation/portfolio_screen.dart`
- `lib/features/orders/data/okx_position_model.dart`
- `lib/features/orders/data/okx_position_model.freezed.dart` (generated)
- `lib/features/orders/data/okx_position_model.g.dart` (generated)
- `lib/features/orders/data/okx_order_model.dart`
- `lib/features/orders/data/okx_order_model.freezed.dart` (generated)
- `lib/features/orders/data/okx_order_model.g.dart` (generated)
- `lib/features/orders/presentation/orders_screen.dart`
- `lib/features/orders/presentation/widgets/order_notional.dart` (new, exact name may be adjusted to repository conventions)
- Focused files under `test/core/navigation/`, `test/features/portfolio/`, and `test/features/orders/`

No dependency, schema, migration, Firebase, credential-storage, or API endpoint change is expected.

## Ordered Implementation Steps

1. Add focused tests for navigation destinations/selection and notional resolution before changing production behavior.
2. Implement the main navigation shell and route both app-entry paths through it.
3. Remove duplicate Home AppBar destination buttons and verify secondary Market/Settings routes remain available.
4. Implement and test the frameless responsive asset summary.
5. Extend order/position models, regenerate code, and add notional resolver tests covering missing/malformed values and instrument-type rules.
6. Render monetary values in position, pending-order, and history-order cards using current currency/masking behavior.
7. Format changed Dart files and run focused tests.
8. Run full static analysis, all tests, and a web production build.
9. Review the final diff against this plan, update the active task checklist, and report verified results and any environment limitations.

## Testing and Verification Strategy

- Unit tests:
  - Parse the newly supported OKX fields.
  - Resolve position, filled-order, pending-order, SPOT/MARGIN fallback, unavailable, malformed, and derivative-no-fallback cases.
  - Preserve sign/absolute-value and zero/unavailable handling as specified.
- Widget tests:
  - Show all four navigation destinations and switch selected content.
  - Confirm Home starts selected and duplicate AppBar actions are absent.
  - Confirm the total summary retains all monetary information and has no enclosing decoration.
  - Exercise compact and wide viewport layouts without overflow.
  - Confirm order/position notionals render in USD, VND, and dual mode and mask when balances are hidden.
- Regression verification:
  - Existing Portfolio currency, Settings, BMAG, icon, and core tests.
  - `flutter analyze`.
  - Complete `flutter test` suite.
  - `flutter build web` to validate the integrated responsive shell in a production compilation.
- Manual smoke checks when credentials/runtime services are available:
  - Destination switching, Market/Settings back navigation, refresh lifecycle, live position values, and light/dark contrast.

## Risks and Mitigations

- **Derivative units differ from spot quantities:** use OKX notional fields and prohibit unsupported contract-count multiplication.
- **Some pending orders may omit monetary fields:** use safe SPOT/MARGIN fallback only and show `--` otherwise.
- **Nested Scaffold layout with a shell:** verify FAB, AppBar, safe area, and bottom navigation on compact and wide viewports.
- **Screen disposal on tab change resets local scroll:** provider-backed selection remains; scroll retention is explicitly outside scope.
- **Generated model drift:** regenerate with `build_runner`, inspect generated diffs, and run serialization tests.
- **Text overflow in dual-currency mode:** use responsive constraints and test narrow widths.

## Rollback Considerations

The change is UI/model additive and introduces no data migration. Rollback consists of restoring direct Portfolio entry, its three AppBar route actions, the previous summary layout, and removing additive notional fields/UI. Existing API payloads and persisted preferences remain compatible.

## Acceptance Criteria

- All acceptance criteria in the linked design specification pass.
- No unapproved dependency, endpoint, data model persistence, or visual-system change appears in the final diff.
- Relevant focused tests, `flutter analyze`, complete `flutter test`, and `flutter build web` succeed, or any environment-specific limitation is reported precisely.

