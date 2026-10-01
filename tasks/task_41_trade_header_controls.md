# Task 41 — Compact close-all controls and show session icon

Status: PASS (coordinator audit 2026-10-01)
Agent Role: implementation_executor
Executor Class: E1
Target Model: gpt-6-luna
Target Effort: xhigh
Target Route: gpt-6-luna / xhigh
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Dispatch Route Status: UNVERIFIABLE (explicit model and effort binding; runtime did not expose effective route)
Specification: `docs/agents/specs/2026-10-01-strategy-coin-and-trade-header.md`
Plan: `docs/agents/plans/2026-10-01-strategy-coin-and-trade-header.md`
Plan Steps: P02
Requirements: REQ-002
Acceptance Criteria: AC-002

## Objective

Put a simple accessible authenticated/signed-out icon beside the Trade Management title. Make the close-all area contain just a compact button when authenticated; retain actionable diagnostics and feedback separately.

## Scope

Allowed writes: `lib/features/orders/presentation/orders_screen.dart`, `lib/features/orders/presentation/widgets/trade_account_controls.dart`, relevant Dart tests under `test/features/orders/`.
Forbidden: order/auth/session logic, Settings login controls, protected configuration/environment files, dependencies, Git mutation.

## Verification contract

- RED-002: add widget expectations for title icon state and compact close-all area. Existing layout must fail those expectations before the fix.
- GREEN-002: new widget expectations pass after the fix; run existing close-all confirmation and pending-operation recovery tests.
- Ensure signed-out state shows no empty close-all container; operation recovery/error/result feedback stays visible where relevant; preserve disabled conditions.
- Buildability: `flutter build web --release` after final source/test change; affected canonical unit is Flutter web app.
- Ceiling V2; escalate only on a concrete related failure.
- No external configuration action.

Stop and report BLOCKED if the specified diagnostics cannot remain accessible within allowed scope. Return concise RED/GREEN/build results; coordinator owns audit and final task status.

## Audit result

AC-002 PASS. The AppBar shows an accessible session icon beside the unchanged title. The authenticated close-all action is compact and outside a Card; signed-out state has no empty action container. Pending-operation lookup, errors, progress, result feedback, and disabled conditions remain visible in the inspected diff. RED-002 failed before the fix; GREEN-002 and 34 relevant action/layout tests passed. The affected Flutter web unit built after the final task-local edit with `rtk proxy flutter build web --release` (exit 0). Changed paths match the allowed surface; no protected configuration path changed. External configuration actions: none.
