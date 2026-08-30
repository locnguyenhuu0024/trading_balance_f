# Implementation Plan: Unified Navigation and Responsive Order Management

**Date:** 2026-08-30  
**Status:** Proposed; awaiting execution approval  
**Design:** [`../specs/2026-08-30-navigation-orders-responsive-design.md`](../specs/2026-08-30-navigation-orders-responsive-design.md)

## Objective

Implement the approved navigation and order-management design: Market and Settings as root destinations, an animated single-surface bottom bar, select-based order filters, adaptive card grids, and reliable widget coverage.

## Affected Components

- `lib/core/navigation/main_navigation_shell.dart`
- `lib/core/navigation/` (a small dedicated custom navigation-bar widget/helper if extraction improves readability and testability)
- `lib/features/portfolio/presentation/portfolio_screen.dart`
- `lib/features/settings/presentation/settings_screen.dart`
- `lib/features/orders/presentation/orders_screen.dart`
- `lib/features/orders/presentation/providers/order_provider.dart` (only if the responsive column resolver is placed beside its related UI state)
- `test/widget_test.dart`
- Additional focused test file(s) under `test/core/navigation/` or `test/features/orders/` only when separation makes the test suite clearer.

No package, API, model, generated-code, persistence, or migration change is planned.

## Ordered Implementation Steps

1. Replace the invalid sample in `test/widget_test.dart` with deterministic widget tests using a `ProviderScope` and non-network destination bodies; add any small pure test helpers needed for the documented responsive breakpoints.
2. Refactor `MainNavigationShell` to define five root destinations and a test-only injectable destination-body seam while retaining the production screen mapping.
3. Implement the single-surface custom bottom bar with five accessible targets, selected-only label visibility, circular selected indicator, upward/tint/title animations, and theme-derived contrast colors.
4. Remove Market and Settings route-push buttons/imports from `PortfolioScreen`; retain the balance visibility action.
5. Adjust the Settings successful-save path to keep the user in the Settings tab rather than popping the root shell, while retaining feedback and error behavior.
6. Replace the Orders `SegmentedButton` and horizontal `ChoiceChip` controls with responsive labeled select fields that write the existing `orderTabProvider` and `orderFilterProvider` values.
7. Introduce the width-to-column layout resolver and replace populated one-column order/position lists with adaptive grid/list rendering. Preserve refresh, loading, error, empty, and card-detail behavior.
8. Format all modified Dart files; run targeted widget/unit tests, `flutter analyze`, the full `flutter test` suite, and `flutter build web`.
9. Inspect the final diff against the design and plan, update the active task checklist to completion, and report verified results and any environment limitation. Do not commit or push.

## Verification Strategy

- Widget tests at compact, tablet, and large viewports covering every required column count.
- Widget tests for navigation destinations, selected visual/semantic state, title visibility, light/dark contrast, and animated selection settling.
- Widget tests proving each select updates its existing provider and that the legacy tabs/chips do not render.
- Manual smoke validation where app credentials are available: switching all destinations; Settings API-save feedback; refresh and data states; light/dark rendering on narrow and wide screens.
- `dart format --set-exit-if-changed` or `flutter format` in check-safe use after formatting, `flutter analyze`, full tests, and production web compilation.

## Risks and Rollback

The change is UI-only and does not alter persistence or remote data. The principal compatibility risk is Settings invoking `Navigator.pop` after becoming a tab; the plan addresses this directly. If rollback is required, restore the three-tab shell, Home route actions, existing segmented/chip filters, and list layouts; no data migration is involved.

## Acceptance Criteria

All acceptance criteria in the design specification pass, all requested widget tests are implemented in or alongside `test/widget_test.dart`, and required verification succeeds or reports a precise environmental limitation.
