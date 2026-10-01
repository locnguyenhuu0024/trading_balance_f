# Task 37 — Uniform navigation content gap

Status: PASS
Agent Role: implementation_executor
Executor Class: E0
Target Model: gpt-6-luna
Target Effort: high
Target Route: gpt-6-luna / high
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Dispatch Route Status: UNVERIFIABLE
Requested Model: gpt-6-luna
Requested Effort: high
Observed Effective Model: unavailable
Observed Effective Effort: unavailable
Specification: `docs/agents/specs/2026-10-01-navigation-order-and-content-gap-design.md`
Plan: `docs/agents/plans/2026-10-01-navigation-order-and-content-gap.md`
Requirements: REQ-003
Acceptance Criteria: AC-004

## Objective and Preconditions

Reserve a uniform bottom gap for every screen inside the primary navigation host. User approval of this task/plan is required. T36 is scheduled before this task only to avoid shared Flutter cache collisions; it is not a semantic dependency.

## Allowed Scope

`lib/core/navigation/navigation_content_frame.dart` and `test/core/navigation/navigation_content_frame_test.dart`. Do not edit other product/test files, protected configuration/environment files, dependencies, or Git history.

## Executor Contract

Implement P03. Inside `NavigationPresentationScope`, bottom padding is the fixed bar's `crestHeight + barHeight` (76 logical pixels) plus `max(viewPadding.bottom, viewInsets.bottom)` in fixed and every floating mode. Keep outside-scope child unchanged. Use shared fixed-bar constants rather than a second magic number. Preserve existing screen content and other inset behavior. If this bounded scope cannot compile independently, return BLOCKED to coordinator.

## Mandatory RED Then GREEN

- RED-002: Test floating mode with 24-pixel bottom inset expecting 100-pixel bottom reserve; observe failure before implementation because floating currently reserves zero.
- GREEN-002: Test fixed and every floating edge with 24-pixel inset expecting 100, zero inset expecting 76, and outside-host mode expecting no padding.
- Verification ceiling V2; expand only on a concrete layout regression.

## Buildability and Audit

After final executable/test edit, run `rtk proxy flutter build web --no-pub` for the Flutter web application and record exit/status. Run focused tests in RED→GREEN order. Flutter SDK cache permissions may require sandbox escalation; distinguish startup failure from test behavior. Return changed paths, verification, no-config-change confirmation, and telemetry envelope. Coordinator independently audits before PASS. External configuration action: none.

## Coordinator Audit — PASS

- Scope: only the planned content frame and its focused test changed; no protected configuration path changed.
- RED: focused frame test failed before implementation because floating mode had no padding. GREEN: the focused file passed four tests for fixed/all floating edges, zero and larger bottom insets, and outside-host behavior.
- Task buildability: `rtk proxy flutter build web --no-pub` exited 0 after the final T37 code/test change. Diff check passed.
- Route: E0 `gpt-6-luna / high` explicitly requested; effective route unavailable (`UNVERIFIABLE`). Verdict: PASS. External configuration action: none.
