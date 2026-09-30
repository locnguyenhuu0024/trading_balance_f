# Implementation Plan: Navigation visibility and Settings modals

Status: COMPLETE
Revision: 1
Specification: `docs/agents/specs/2026-09-30-navigation-visibility-settings-modals.md`

## 1. Objective and Preconditions

Implement REQ-001 through REQ-005 after explicit approval of this plan and `tasks/task_31_navigation-visibility-settings-modals.md`. Current working tree was clean at planning start. Existing navigation preference storage is reused; no protected configuration is read or changed.

## 2. Planning Workstreams

| Workstream | Material | Independent | Requested route | Run | Result |
|---|---|---|---|---|---|
| Settings and navigation UI | Yes | Yes | R2, gpt-6-sol / medium, explicit | ui-analysis-1 | Collected, used |
| Persistence and selection state | Yes | Yes | R2, gpt-6-sol / medium, explicit | state-analysis-1 | Collected, used |

Fan-out Required: YES. Required Reasoning Agents: 2. Actual Reasoning Agents: 2. Fan-out Compliance: PASS. Cross-layer synthesis: the coordinator adopts stable IDs and visible-position mapping, and user-confirmed Settings/Home fallback semantics. Effective child routes and usage are unavailable; dispatch was explicitly bound.

## 3. Dependency Graph and Steps

One compile-coupled task, T31, implements the shared visibility contract across preferences, shell, both presentation styles, Settings, and focused tests. There is no safe independently passing intermediate task because the model and two navigation styles must agree on selection identity.

1. P01: Add stable IDs and normalized enabled membership to the navigation model. Keep version-1 legacy decode and existing storage key; use controller save/rollback.
2. P02: Filter fixed and floating navigation by membership; convert visible positions to original screen identities. Resolve hidden selected page to Home when enabled, otherwise Settings.
3. P03: Add Settings visibility checkbox modal and single appearance-settings modal. Move the four existing navigation controls into the latter; leave app text scale in place.
4. P04: Add focused model/controller/widget coverage and update impacted existing tests.

## 4. Verification

Formal task checkpoint: run RED-001 before GREEN-001 using focused Flutter tests. RED asserts absence and correct remaining-page mapping; GREEN asserts restoration and modal appearance behavior. V2 ceiling for affected test files; expand to V3 only if shared navigation regressions or failed checks require it. Buildability gate after final code change: `flutter build web --no-pub` for the Flutter application. Run `flutter analyze lib test` for affected static checks if the build/test output indicates a code issue or for final integration. Final audit checks the changed non-protected paths and confirms no configuration writes.

## 5. Compatibility, Risk, and Rollback

Old version-1 records lack enabled IDs and decode to all pages visible while retaining appearance settings. Invalid enabled IDs normalize safely. Main risk is positional index mismatch in layout, callbacks, or animations when the list shrinks; targeted tests cover both modes and selections after gaps. Implementation can be rolled back as a code change; the optional stored field remains harmless to older code. No external configuration action.

## 6. Task and Route

| Task | Requirements | Dependencies | Allowed write surface | Executor |
|---|---|---|---|---|
| T31 | REQ-001–005, AC-001–005 | None | Relevant `lib/core/navigation/`, `lib/features/settings/presentation/settings_screen.dart`, focused `test/core/navigation/`, `test/features/settings/` | E1, implementation_executor, gpt-6-luna / xhigh, explicit |

Task build unit: Flutter web application; exact command `flutter build web --no-pub`. Dispatch role and both model/effort must be explicit. Coordinator remains non-writing for product/test code and audits the executor result.

## 7. Completion Gate

Approval received on 2026-09-30. T31 passed RED then GREEN, 28 navigation tests, 7 Settings tests, task buildability, scope audit, and the coordinator's final Flutter web build (exit 0). One new unused-local warning was remediated; unrelated analyzer infos remain. No Git history operation was performed.
