# Task 115 — Freeze backend action-entry generation

Status: PASS
Agent Role: implementation_executor
Executor Class: E1
Target Model: gpt-6-luna
Target Effort: xhigh
Route Binding: EXPLICIT
Dispatch Route Status: UNVERIFIABLE
Requested Model/Effort: gpt-6-luna / xhigh (reused original explicitly bound E1 executor)
Observed Effective Model/Effort: unavailable
Specification: docs/agents/specs/2026-10-14-direct-okx-reads-design.md
Plan Steps: P04
Requirements: REQ-004
Acceptance Criteria: AC-004
Frontend Level: F0

Independent consumer audit found mutable BackendDataSession.generation read inside showDialog builder in TradeAccountControls._showBackendPositionTargets. Route rebuild can adopt newer generation rather than preserve action-entry identity. Capture generation as immutable int before showDialog; use captured value inside builder. No other behavior change. In-scope session-ownership remediation authorized by approved contract, no additional product decision/approval.

Allowed product file: lib/features/orders/presentation/widgets/trade_account_controls.dart. Allowed test file: test/features/orders/backend_position_actions_dialog_test.dart (or existing position_actions_test.dart if real entry test requires its harness). No other writes; coordinator owns docs/tasks/telemetry. Protected files unreadable/non-writable. No Git/external/nested agent actions. Reuse explicitly bound E1 gpt-6-luna/xhigh executor; effective route unavailable. Serialize after T114 terminal result.

RED-115 deterministic actual entry through TradeAccountControls: open targets dialog, increment shared session generation through null then same-session restore and trigger route rebuild; dialog must retain old entry generation and show no actionable/reloaded target. Existing direct dialog tests alone do not exercise captured closure. No timer sleeps; controlled frames/completers. GREEN-115 normal entry loads authoritative targets; existing dialog/position-actions regression retained. Run RED then GREEN, affected dialog/position-actions tests --no-pub and fresh rtk flutter build web --no-pub after last executable change. No full suite; coordinator owns final V4 once.

Report exact commands/counts/results and changed files. Coordinator audit PASS; no protected modifications/config actions/live-key QA.

## Regression Seam Adjustment
Controlled route push/pop and MediaQuery change did not reexecute DialogRoute builder in existing harness. Adopt deterministic earlier builder boundary: invoke real action entry, clear/restore same shared session before first frame builds the route. Old expression adopts new generation and test fails; immutable capture rejects it with zero target loads/actions. This directly tests the action-entry capture contract without assuming route internals. Existing actual-entry positive test remains GREEN.

## Accepted Evidence
Independent R2 audit PASS: immutable generation captured before showDialog and reused by closure; real-entry test advances same-session generation before first frame and proves zero target loads/actions. Old source failed; current test passes. Coordinator final ordered RED-115 `rtk flutter test --no-pub test/features/orders/backend_position_actions_dialog_test.dart --plain-name 'dialog entry keeps its generation before the route first builds'` exit0 1 passed; then GREEN-115 same command with `--plain-name 'loads only explicit backend targets and scrolls the bounded dialog'` exit0 1 passed. Executor affected dialog+position_actions files:52 passed; fresh task `rtk flutter build web --no-pub` succeeded after last edit. Final full Flutter suite coordinator:564 passed, exit0. No protected changes.
