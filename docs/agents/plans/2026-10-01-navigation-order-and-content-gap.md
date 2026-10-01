# Implementation Plan: Navigation order and content gap

Status: COMPLETE
Revision: 1
Specification: `docs/agents/specs/2026-10-01-navigation-order-and-content-gap-design.md`
Decisions: `docs/agents/decisions/2026-10-01-navigation-order-and-content-gap-decisions.md`

## 1. Objective and Preconditions

Implement REQ-001 through REQ-003 after explicit user approval of this plan and tasks T36–T37. The working tree was clean at planning start. Preserve task 31 visibility and appearance behavior.

## 2. Repository Impact and Planning Workstreams

| Workstream | Material | Independent | Requested route | Run | Result |
|---|---|---|---|---|---|
| Order, persistence, modal, shell routing | Yes | Yes | R2, gpt-6-sol / medium, explicit | reorder-analysis-1 | Collected, used |
| Global content reserve/layout | Yes | Yes | R2, gpt-6-sol / medium, explicit | spacing-analysis-1 | Collected, used |

Fan-out Required: YES. Required Reasoning Agents: 2. Actual Reasoning Agents: 2. Fan-out Compliance: PASS. The coordinator reconciled stable-ID order with the existing membership and selected-screen mapping, then obtained the user decisions in the ledger. Effective child routes and usage were unavailable; both spawn requests explicitly bound model and effort.

## 3. Dependency Graph and Ordered Steps

T36 and T37 are logically independent and each leaves the Flutter web build unit buildable. Execute them serially because both verification paths use Flutter's shared build/test cache and there is no useful critical-path gain from simultaneous writers.

1. P01 / T36: Add and normalize the full destination order in preferences while retaining version-1 compatibility; add controller update and persistent rollback tests.
2. P02 / T36: Make the visibility modal a bounded reorderable checkbox list with drag handles; render both navigation styles from stored visible order and preserve stable screen selection/routing.
3. P03 / T37: Replace the frame's mode-specific reserve with a uniform bottom reserve of 76 logical pixels plus existing bottom inset for any screen inside the navigation host. Keep outside-host behavior unchanged.

## 4. Tests and Verification

- T36 formal RED-001 precedes GREEN-001. Focused tests cover drag, Settings movement, hidden-page position, stored decode/rollback, selected-screen identity, and bar/floating routing. V2 ceiling; expand to V3 only for a concrete shared navigation regression.
- T37 formal RED-002 precedes GREEN-002. Update `navigation_content_frame_test.dart` to assert 76 plus inset in fixed/all floating edges and no reserve outside the host. V2 ceiling; expand only for a concrete layout regression.
- Each task after its final executable change must build the canonical Flutter web application with `rtk proxy flutter build web --no-pub` (or the same Flutter command directly when optimizer behavior obscures evidence). The coordinator audits each task's evidence, changed non-protected files, and buildability before PASS.
- Final integration runs the canonical web build again after all code changes and checks the combined diff/status. Reuse focused tests where still valid; rerun only invalidated scenarios. No protected configuration content is inspected; Flutter may consume it opaquely as normal build input.

## 5. Compatibility, Risk, and Rollback

The optional order field in the existing version-1 record defaults to canonical order for old records; visibility and appearance remain unchanged. Partial or corrupt order is normalized. Main risks are an incorrect visual-to-screen index mapping and a reorderable modal overflow on narrow viewports; both have targeted tests. Code rollback restores prior canonical order and prior content reserve behavior; the extra optional stored order field is ignored by older code. No external configuration or environment action is required.

## 6. Task Decomposition and Buildability

| Task | Requirements | Dependencies | Allowed source/test surface | Executor |
|---|---|---|---|---|
| T36 | REQ-001/002, AC-001/002/003 | None | Preferences/provider, shell, Settings modal, focused navigation/Settings tests | E1, gpt-6-luna / xhigh, explicit |
| T37 | REQ-003, AC-004 | None; scheduled after T36 for shared tooling | NavigationContentFrame and its focused test | E0, gpt-6-luna / high, explicit |

Both task boundaries require the Flutter web build unit to pass. No compile-coupled broken intermediate state is permitted. Coordinator remains non-writing for product/test code and owns audit/remediation routing.

## 7. Completion Gate

Approval received on 2026-10-01 for the current feature branch. T36 and T37 passed RED then GREEN, focused tests, post-task buildability, and scope audits. Final navigation integration passed 35 tests; the coordinator's final `rtk proxy flutter build web --no-pub` exited 0. Scoped analysis found only two pre-existing Settings deprecation infos. No commit, push, or protected configuration write occurred.
