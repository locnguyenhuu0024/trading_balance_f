# Implementation Plan: Floating Navigation Island

**Date:** 2026-08-30  
**Status:** Implemented; verification passed  
**Design:** [`../specs/2026-08-30-floating-navigation-island-design.md`](../specs/2026-08-30-floating-navigation-island-design.md)

## Objective

Refine `TradingNavigationBar` into a compact, floating navigation island with a selected icon circle that seamlessly rises from the island surface.

## Repository Context

`TradingNavigationBar` currently uses a full-width, 72-pixel-tall rectangular surface. Its selected indicator uses the opposite colour from that surface and only moves slightly upward. The current widget tests encode the now-obsolete contrasting indicator expectation.

## Technical Approach

- Keep the existing five destinations, selection state, semantic labels, tooltips, and callbacks intact.
- Place the icon row inside a horizontally centred, rounded, constrained `navigation-bar-surface` island with responsive side insets.
- Reserve vertical space for the selected label within the island and allow the selected circle to paint beyond the island’s top edge using a non-clipping parent.
- Use the navigation-surface colour for the selected circle and the existing contrasting foreground colour for its icon and title.
- Retain the current animated selection transition, increasing the upward offset enough for a clear raised appearance.
- Update focused widget coverage to assert island bounds, selected-circle colour/protrusion, theme behaviour, and selected-only labels.

## Affected Files

- `lib/core/navigation/trading_navigation_bar.dart`
- `test/widget_test.dart`
- `test/core/navigation/main_navigation_shell_test.dart` only if its navigation expectations need adjustment

No package, API, persistence, configuration, migration, or destination mapping change is planned.

## Ordered Implementation Steps

1. Update the navigation widget layout, sizing, clipping, and theme-derived colours to render the compact floating island and seamless raised selected circle.
2. Preserve existing accessibility, destination selection, tooltips, and selected-title behaviour while adjusting animation geometry.
3. Update affected widget tests to replace the contrasting-indicator assertion and verify visual bounds, surface-colour continuity, and title visibility in both themes.
4. Format modified Dart files and run focused navigation tests, full `flutter test`, `flutter analyze`, and a web build if practical.
5. Review the final diff against the design, update the task checklist, and report results without committing or pushing.

## Risks and Rollback

The primary risk is clipping the selected circle or reducing touch-target usability while compacting the visual surface. The implementation will keep each destination's tap area independent from the visual circle and test the selected circle’s bounds relative to the island. Rollback is limited to restoring the previous navigation widget and test assertions; no data changes are involved.

## Acceptance Criteria

All criteria in the linked design specification pass, the existing five root destinations still work, and the required verification succeeds or reports a precise environmental limitation.
