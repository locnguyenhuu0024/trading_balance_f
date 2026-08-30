# Design Specification: Floating Navigation Island

**Date:** 2026-08-30  
**Status:** Implemented

## Objective

Refine the existing five-destination navigation bar into a compact, continuous navigation island whose selected destination visually rises above its surface.

## Visual and Interaction Requirements

- The navigation surface is a single, compact rounded block. It must fit its icon row rather than occupy the full available width; on narrow screens it retains minimum side insets, and on wider screens it is horizontally centred with a bounded maximum width.
- The unselected destinations show only their icons inside the shared surface.
- The selected destination shows a circular icon button that translates upward so part of the circle protrudes above the navigation surface.
- The selected circle uses the same theme-derived colour as the navigation surface. This makes it appear as a seamless raised continuation of the bar, rather than as a contrasting badge.
- The icon inside the selected circle, unselected icons, and selected title retain sufficient contrast against their respective surfaces.
- The selected title remains visible only for the selected destination and is positioned in the navigation surface below the raised icon.
- Selecting another destination animates the circle and title between destinations while preserving the existing semantics, tooltips, destinations, and tap targets.

## Theme Behaviour

| Theme | Navigation island and selected circle | Icon and title colour |
| --- | --- | --- |
| Light | Black | White or an equivalent high-contrast foreground |
| Dark | White | Black or an equivalent high-contrast foreground |

## Scope and Non-goals

This change is confined to the navigation-bar presentation and its tests. It does not change destination order, routing, navigation state, app theme preferences, order management, or remote data.

## Acceptance Criteria

1. The five destinations render inside one compact, rounded navigation island instead of a full-width bottom bar.
2. The selected circular control has the same background colour as the island and its rendered bounds extend above the island’s top edge.
3. Only the selected destination’s title is rendered, and it remains readable in both light and dark modes.
4. Switching destinations preserves animation, navigation behaviour, accessibility semantics, and tap targets.
5. Widget coverage verifies the compact layout, selected-circle colour/protrusion, selected-only title, and theme contrast.
