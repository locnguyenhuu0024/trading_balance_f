# Design Specification: Navigation visibility and Settings modals

Status: IMPLEMENTED
Revision: 1

## 1. Objective

Let users choose which primary navigation pages appear, and move the existing navigation appearance controls into one Settings modal.

## 2. Current State

Seven destinations are defined in `lib/core/navigation/navigation_destination_data.dart`: Home, BMAG, Orders, Market, Settings, Risk, and Support. The shell selects screens with original indexes 0–6. Both fixed and floating presentations render every destination. Settings currently shows display mode, floating edge, button size, and opacity as separate rows. `NavigationPreferences` saves those values as a version-1 JSON record with optimistic update and rollback.

## 3. Scope and Decisions

- REQ-001: Settings offers a button that opens a modal containing the seven current destinations as labeled checkbox rows. A checked row is visible in both navigation presentations; an unchecked row is absent. Changes save automatically through existing navigation preferences.
- REQ-002: Settings remains visible and its checkbox is checked and disabled. This is the recovery route when every optional page is hidden. User confirmed this on 2026-09-30.
- REQ-003: If the selected page becomes hidden, navigate to Home when Home is enabled; otherwise navigate to Settings. User chose Home as the preferred fallback on 2026-09-30.
- REQ-004: A single Settings row/button opens a separate modal containing the existing display mode, floating edge when applicable, button size, and opacity controls. Keep app text scale in the main Settings list.
- REQ-005: Preserve existing saved mode, edge, size, and opacity values, including version-1 records written before this change. Preserve save-failure rollback and show the failure in Settings or the open modal.

## 4. Data and Interface Contract

- Give each destination a stable string ID independent of its visual position. Define the canonical order alongside the seven navigation items. The shell can continue mapping original indexes to screens, but filtered controls must map visible positions back to original destination identity.
- Add an optional enabled-ID field to the existing version-1 navigation preference JSON. An absent field means all seven enabled. Normalize decoded data to known IDs in canonical order, always include Settings, and use all defaults for a malformed/empty unusable field. Preserve valid legacy display values rather than increasing the record version without migration.
- Both navigation presentations receive a filtered destination list and selected visible position. Their layout widths/heights, painter counts, animation endpoints, callback mapping, and accessibility labels derive from that filtered list. Existing full-list behavior remains when all pages are enabled.
- Opening/dismissing a modal does not reset or replace the selected screen. A failed save restores the confirmed visibility and appearance values.

## 5. Invariants and Edge Cases

- INV-001: Settings is always present and reachable. The enabled list is never empty.
- INV-002: A visible control opens its own screen after any preceding controls are hidden.
- INV-003: Hidden destinations have no tappable or semantic navigation control in fixed or floating mode.
- EDGE-001: Hiding Home leaves Settings available; a hidden selected page falls back to Settings if Home is hidden.
- EDGE-002: Unknown, duplicate, missing, or malformed persisted IDs cannot create an invalid selection or remove Settings.
- EDGE-003: Rapid checkbox changes respect existing serialized save behavior; controls disable while saving, then reflect confirmed state or rollback.

## 6. Acceptance and Verification

- AC-001: Visibility modal lists seven pages in canonical order, all checked initially; Settings cannot be unchecked.
- AC-002: Unchecking a page removes it immediately from both navigation modes; checking it restores it without changing relative order. Taps still open the correct page.
- AC-003: Selection falls back as REQ-003 specifies, including when Home is hidden.
- AC-004: The main Settings list shows one navigation appearance entry; its modal retains the four current controls and conditional floating edge. Text scale stays on the main list.
- AC-005: Restart/hydration, old version-1 records, malformed IDs, and save failure behave as defined above.
- RED-001: With a non-Settings page unchecked, its navigation control is absent and a tap on another remaining control never opens the hidden page.
- GREEN-001: Rechecking that page restores its control and opens the correct screen; appearance controls also work from their modal.

## 7. Boundaries

No backend, dependency, protected configuration, external service, permission, or schema change is required. No user-owned configuration action is required.
