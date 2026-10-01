# Decisions: Navigation order and content gap

Status: COMPLETE
Specification: `docs/agents/specs/2026-10-01-navigation-order-and-content-gap-design.md`
Plan: `docs/agents/plans/2026-10-01-navigation-order-and-content-gap.md`

## Clarification Questions and User Decisions

| ID | Question | User decision on 2026-10-01 | Impacts |
|---|---|---|---|
| D-001 | Reordering interaction | Drag by a handle in the existing visibility modal | REQ-001, AC-001, T36 |
| D-002 | Settings row | It stays enabled, but may be dragged like other pages | REQ-001, AC-001, T36 |
| D-004 | Reenabling a hidden page | Preserve and restore its previously arranged position | REQ-002, AC-002, T36 |
| D-005 | Placement of gap | Always at the end/bottom of the page, even for top/side floating navigation | REQ-003, AC-004, T37 |
| D-006 | Size of gap | Total reserve uses the fixed bar's full 76 logical pixels, rather than adding another height to the current reserve or using floating group height | REQ-003, AC-004, T37 |
| D-007 | Page scope | Only screens displayed with the primary navigation; separately pushed detail pages are excluded | REQ-003, AC-004, T37 |

The design keeps hidden rows in the modal's full order so D-004 can restore their saved positions. The user approves that implementation contract through the specification and plan approval gate.

## Change Log

Revision 1: Decisions recorded for the initial plan.
