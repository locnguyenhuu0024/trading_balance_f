# Implementation Plan: Square Navigation Surface

**Date:** 2026-08-30  
**Status:** Implemented; verification passed

## Objective

Remove rounding from the full-width navigation surface while preserving its selected-circle effect, full-width layout, centred unselected icons, navigation semantics, and existing destinations.

## Implementation Steps

1. Remove the `Material` border-radius configuration from `TradingNavigationBar`.
2. Retain the independent rounded ink response for destination tap feedback, because it does not affect the visual surface geometry.
3. Update the focused navigation widget test to assert the surface has no border radius.
4. Format and run focused widget tests, `flutter test`, `flutter analyze`, and a web build.
5. Review the final diff, update and lock the task checklist. Do not commit or push.

## Acceptance Criteria

The navigation surface has square corners, all Task 07 layout behavior remains intact, and verification succeeds.
