# Implementation Plan: Full-width Navigation Alignment

**Date:** 2026-08-30  
**Status:** Implemented; verification passed  
**Design:** [`../specs/2026-08-30-full-width-navigation-alignment-design.md`](../specs/2026-08-30-full-width-navigation-alignment-design.md)

## Objective

Make the navigation bar span the screen while vertically centring all unselected icons within the bar surface.

## Context and Scope

`TradingNavigationBar` currently centres a 344-pixel-wide island and translates unselected icon containers by 35% of their height. That places their icon centres above the surface midpoint. This task removes the island width cap and adjusts only the unselected-icon translation geometry.

No destinations, navigation state, labels, theme colours, APIs, persistence, dependencies, or order-management UI will change.

## Ordered Implementation Steps

1. Remove the constrained-width wrapper so the navigation surface uses the entire available width.
2. Adjust the unselected `AnimatedSlide` offset so the icon visual centres align with the surface’s vertical centre line after animation settles.
3. Update navigation widget coverage to assert full-width layout and common centre alignment for all unselected icons, while retaining checks for the raised selected circle and light/dark continuity.
4. Format modified Dart files; run focused navigation tests, `flutter test`, `flutter analyze`, and `flutter build web`.
5. Review the final diff, update this task checklist to completion and lock it. Do not commit or push.

## Risks and Rollback

The main risk is accidental regression of the selected-circle protrusion while changing stack geometry. Bounds-based widget assertions prevent that. Rollback restores the width cap and previous unselected offset; no data changes are involved.

## Acceptance Criteria

All design acceptance criteria pass and all required verification commands succeed, or any precise environmental limitation is reported.
