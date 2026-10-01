# Task 44 — Validate blank SWAP metadata consistently at preview

Status: PASS (coordinator audit 2026-10-02)
Agent Role: implementation_executor
Executor Class: E1
Target Model: gpt-6-luna
Target Effort: xhigh
Target Route: gpt-6-luna / xhigh
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Dispatch Route Status: UNVERIFIABLE (explicit model and effort binding; runtime did not expose effective route)
Specification: `docs/agents/specs/2026-10-02-strategy-step-one-progress.md`
Plan: `docs/agents/plans/2026-10-02-strategy-step-one-progress.md`
Plan Steps: P02
Requirements: REQ-003
Acceptance Criteria: AC-003

## Objective and scope

Accept absent/blank optional `baseCcy` and `quoteCcy` in backend strategy preview only when the strict live linear USDT SWAP identity and required valuation metadata agree; preserve rejection of conflicts/inverse contracts.

Allowed writes: `backend/strategy.py`, `backend/tests/test_strategy_api.py`.
Forbidden: other backend behavior, storage/API schema, order-placement changes, dependencies, protected configuration/environment files, Git mutations.

## Verification contract

- RED-003: fake-exchange preview with blank/missing optional base/quote metadata currently returns unavailable; expected preview success. Include conflicting nonblank and inverse rows that must reject with zero trade writes.
- GREEN-002: new matrix and existing strategy API tests pass, with existing fee/tier/quote and order guards intact.
- Buildability: Python backend, exact `python3.12 -m compileall -q backend` after final source/test edit, exit 0 required.
- V2 ceiling; V3 only on concrete related regression. External configuration action: none.

Stop if strict validation cannot be retained within scope. Return exact RED/GREEN/build evidence. Coordinator owns audit/status.

## Audit result

AC-003 PASS. The backend derives the canonical base from the previously validated strict ID, accepts only absent/blank optional base/quote metadata, and requires linear USDT settlement with base-denominated contract value and positive sizing metadata. Focused RED tests failed in the expected blank/conflict/inverse cases before the fix. All 23 strategy API tests passed after the fix with `rtk test python3.12 -m unittest backend.tests.test_strategy_api -v`; `python3.12 -m compileall -q backend` exited 0 after the final edit. Rejection cases assert zero exchange trade writes. Only approved backend source/test paths changed; no protected configuration path changed. External configuration actions: none.
