# Task 56 — Never-Sent Strategy Backend

Status: PASS
Agent Role: implementation_executor
Executor Class: E2
Target Model: gpt-6-luna
Target Effort: max
Target Route: gpt-6-luna / max
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Dispatch Route Status: UNVERIFIABLE
Observed Effective Model: unavailable
Observed Effective Effort: unavailable
Specification: `docs/agents/specs/2026-10-02-strategy-never-sent-replacement.md`
Plan: `docs/agents/plans/2026-10-02-strategy-never-sent-replacement.md`
Plan Steps: P01
Requirements: REQ-001, REQ-002, REQ-003, REQ-004
Acceptance Criteria: AC-001, AC-002, AC-004, AC-005, AC-006

## Objective and boundaries

Implement the backend contract in P01. Allowed write surface: `backend/strategy.py`, `backend/strategy_worker.py`, `backend/okx.py`, `backend/store.py`, `backend/tests/test_strategy_api.py`, `backend/tests/test_strategy_worker.py`, and focused `backend/tests/test_okx.py` only if it exists. Do not modify protected configuration or unrelated code. No production DB access or exchange writes.

## RED / GREEN

- RED-001: a leverage-rejected, batch-unattempted row with zero position must not become `COMPLETED`; its failure reason and delete eligibility persist.
- RED-002: an applying or batch-attempted row cannot be deleted or used as replacement source; no exchange batch is retried.
- GREEN-001: a fresh replacement receives new IDs; full batch acceptance removes its eligible source and dependent rows exactly once.
- GREEN-002: partial/unknown response retains source and performs no automatic resend.

Run focused RED before GREEN after implementation. Buildability: `python -m compileall -q backend` after the final task-local change. Test ceiling V3 (affected backend strategy and OKX tests); expand only on concrete regression evidence. Report exact commands, statuses, and any migration/compatibility risk.
