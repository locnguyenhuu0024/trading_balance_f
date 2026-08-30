# Implementation Plan: Transparent Navigation Overflow

**Date:** 2026-08-30  
**Status:** Implemented; verification passed

## Objective

Make the selected navigation circle paint above the bar without reserving a coloured or empty layout strip above the navigation surface.

## Context

`TradingNavigationBar` currently reserves a 76-pixel bottom-navigation layout box while its visible 60-pixel surface begins 16 pixels below that box’s top. The 16-pixel layout reservation prevents the body from using the area behind the raised circle. The desired result is a 60-pixel navigation layout footprint with only the selected circle visually overflowing upward.

## Technical Approach

- Reduce the navigation layout box to the 60-pixel visible surface height and make the surface fill it.
- Position indicator containers 16 pixels above the layout box, retaining the current 50% unselected translation. This puts unselected icons at the surface centre and the selected circle 16 pixels above the surface without a separate background layer.
- Keep the stack’s non-clipping behaviour, full-width surface, colours, labels, semantics, tap targets, and animations unchanged.
- Add a layout key and widget assertions proving that the surface and layout box share the same bounds while the selected indicator extends above them.

## Affected Files

- `lib/core/navigation/trading_navigation_bar.dart`
- `test/widget_test.dart`

## Verification Strategy

- Run focused navigation widget tests, full `flutter test`, `flutter analyze`, and `flutter build web`.
- Verify that the bottom-navigation layout height equals 60 pixels, the surface fills it, and the selected circle has rendered bounds above it.

## Risks and Rollback

The main risk is an ancestor clipping the overflowing selected circle. Bounds-based widget tests cover its rendered position. Rollback restores the 76-pixel wrapper and 16-pixel surface inset; no data or API changes are involved.

## Acceptance Criteria

1. No reserved coloured or transparent strip exists above the navigation surface.
2. The selected circle remains visible above the bar, while unselected icons remain centred within the bar.
3. Existing navigation functionality and theme behaviour remain intact.
