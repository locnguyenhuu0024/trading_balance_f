# Design Specification: Navigation order and content gap

Status: IMPLEMENTED
Revision: 1

## 1. Objective and Current State

Users can currently toggle seven primary destinations in Settings, but their order is fixed by `navigationItems`. `NavigationPreferences` stores enabled IDs as membership and normalizes them back to canonical order. `MainNavigationShell` filters in canonical order. `NavigationContentFrame` reserves `60 + bottomInset` logical pixels in fixed mode and no space in floating mode. The fixed navigation widget is `16 + 60 + bottomInset` pixels tall.

## 2. Scope and Decisions

- REQ-001: The existing page visibility modal allows drag-handle reordering of all seven destinations, including Settings and currently hidden destinations. Checkbox toggles continue to work. Settings stays checked and cannot be hidden, but can move. User decisions D-001 and D-002; full-list behavior follows the approved design for D-004.
- REQ-002: Persist the full seven-destination order. A hidden destination keeps its position and returns there when reenabled. Existing saved visibility and appearance values remain intact. User decision D-004.
- REQ-003: Every screen shown with the primary navigation reserves bottom content space equal to the fixed bar's full 76 logical-pixel height, plus the existing bottom system/keyboard inset. Apply this in fixed and floating modes, regardless of floating edge or button scale. This is the total reserved space, not an additional 76 pixels. Screens opened outside the primary navigation host remain unaffected. User decisions D-005, D-006, D-007.

## 3. Data and UI Contract

- Add optional `destinationOrderIds` to the existing version-1 `NavigationPreferences` JSON. Missing field decodes to the canonical seven IDs without resetting mode, edge, scale, opacity, or enabled membership. Normalize malformed/partial/duplicate order by retaining known IDs in their first listed order and appending missing IDs in canonical order. The result always contains each known ID exactly once.
- Keep `enabledDestinationIds` as membership with Settings always enabled. Keep it independent of order; toggling a checkbox never changes its stored position. Existing auto-save, optimistic preview, serialized write, error display, and whole-record rollback apply to order changes.
- The modal renders rows in `destinationOrderIds` order using stable IDs/keys. Each row keeps its checkbox and has a drag handle. Reordering an item uses the framework's adjusted destination index, saves once, and reflects the confirmed order or rollback. Bound the reorderable list's height so the modal scrolls on small screens.
- `MainNavigationShell` builds the visible destination sequence from stored order filtered by enabled membership. Visible index maps to each item's stable `screenIndex`, so tapping after reordering opens the same screen. A reorder does not change the selected screen; hiding the selected page keeps the existing Home/Settings fallback.
- `NavigationContentFrame` remains a no-op outside `NavigationPresentationScope`. Inside it, reserve `TradingNavigationBar.crestHeight + TradingNavigationBar.barHeight + max(viewPadding.bottom, viewInsets.bottom)` at the bottom in either display mode. No per-screen padding edits or extra external configuration.

## 4. Invariants, Edges, and Failure Semantics

- INV-001: The order is a permutation of the seven stable IDs; visibility remains independent; Settings is always enabled.
- INV-002: The selected screen identity survives a reorder in either navigation mode.
- INV-003: Navigation content bottom reserve is exactly `76 + bottomInset` logical pixels inside the host, with no duplicate reserve.
- EDGE-001: Reenable a hidden page after reordering; it returns to its stored slot.
- EDGE-002: Decode old version-1 records and malformed order without losing valid appearance/visibility values.
- EDGE-003: Failed order save restores confirmed order and exposes the existing error message; reordering is disabled during an in-flight save.
- EDGE-004: Floating top, bottom, left, and right modes all use the same bottom reserve; detail routes without the primary navigation remain unchanged.

## 5. RED / GREEN and Acceptance

- RED-001: With the default order, drag BMAG after Risk in the modal. Before implementation, no reorder control exists; the expected new order cannot be observed.
- GREEN-001: After drag, both fixed and floating bars place BMAG after Risk, a tap still opens BMAG, and the order survives preference encode/decode and a new provider instance. Hidden pages keep their positions when toggled back on.
- RED-002: In floating mode within the navigation host and a 24-pixel bottom inset, the content frame currently has zero bottom reserve; the required 100-pixel reserve is absent.
- GREEN-002: Fixed and every floating edge reserve `76 + 24 = 100` pixels at the bottom; a direct screen outside the host remains unpadded. With zero inset, reserve is 76 pixels.
- AC-001: Drag-handle ordering works for all seven rows, with Settings draggable but permanently checked.
- AC-002: Saved order and hidden-page slot survive restart; malformed/legacy data normalize safely; failed save rolls back.
- AC-003: Reordered visible controls preserve screen routing and selected screen in both navigation modes.
- AC-004: All primary-navigation pages get the specified bottom reserve in fixed and floating modes; direct/detail routes do not.

## 6. Boundaries

No backend, schema migration, dependency, protected configuration, external service, permission, or new navigation route is needed. No external configuration action is required.
