# Design Specification: Full-width Navigation Alignment

**Date:** 2026-08-30  
**Status:** Implemented

## Objective

Expand the floating navigation surface to the full available screen width and centre every unselected icon precisely on the surface’s horizontal centre line.

## Requirements

- The navigation surface spans the full width made available by the scaffold, with no side inset or maximum-width cap.
- The raised selected circle continues to share the surface colour and protrudes above its top edge.
- Every unselected icon moves down enough that its visual centre equals the vertical centre of the navigation surface. All unselected icons therefore share one straight horizontal centre line.
- The selected-only title, selection animation, five destinations, tap targets, semantics, tooltips, and theme contrast remain unchanged.

## Acceptance Criteria

1. At a 390 logical-pixel viewport, the surface width is 390 logical pixels.
2. After animation settles, each unselected indicator’s vertical centre equals the surface’s vertical centre.
3. The selected circle remains above and intersects the surface boundary, uses the same surface colour, and selection still switches destinations.
4. Widget tests cover the width and alignment requirements in addition to the existing visual behaviour.
