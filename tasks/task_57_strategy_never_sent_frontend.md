# Task 57 — Never-Sent Strategy Frontend

Status: PENDING
Agent Role: implementation_executor
Executor Class: E1
Target Model: gpt-6-luna
Target Effort: xhigh
Target Route: gpt-6-luna / xhigh
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Dispatch Route Status: PENDING
Observed Effective Model: unavailable
Observed Effective Effort: unavailable
Specification: `docs/agents/specs/2026-10-02-strategy-never-sent-replacement.md`
Plan: `docs/agents/plans/2026-10-02-strategy-never-sent-replacement.md`
Plan Steps: P02
Requirements: REQ-001, REQ-002, REQ-003, REQ-004
Acceptance Criteria: AC-001, AC-002, AC-003, AC-004
Predecessor: T56 PASS

## Objective and boundaries

Implement P02 after the backend API contract passes audit. Allowed write surface: `lib/features/strategy/data/strategy_api_client.dart`, `lib/features/strategy/presentation/providers/strategy_dashboard_provider.dart`, `lib/features/strategy/presentation/strategy_screen.dart`, `lib/features/strategy/presentation/strategy_wizard_dialog.dart`, and the four focused `test/features/strategy/strategy_*_test.dart` files named in TEST-002. Do not modify protected configuration or unrelated UI.

## RED / GREEN

- RED-003: legacy false-completed row with server eligibility displays the never-sent warning and actions; rows lacking eligibility or with an attempted batch do not.
- RED-004: cancel confirmation, duplicate tap and unknown outcome never cause an extra execute call or old-row deletion.
- GREEN-003: replacement wizard fetches new candles, requires new level selection, displays prepared orders and submits once after confirmation; the server result removes the source only after all accepted.

Run focused RED before GREEN after implementation. Buildability: `flutter build web --release` after the final task-local change; if the Codex Flutter runtime hangs, obtain the exact user-run command result. Test ceiling V3 (focused strategy suite); expand only on concrete regression evidence.
