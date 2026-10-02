# Task 46 — Accept live OKX isolated tiers

Status: PASS
Agent Role: implementation_executor
Executor Class: E0
Target Model: gpt-6-luna
Target Effort: high
Target Route: gpt-6-luna / high
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Dispatch Route Status: UNVERIFIABLE (explicitly bound; effective route unavailable)
Specification: `docs/agents/specs/2026-10-02-strategy-preview-market-correction.md`
Plan: `docs/agents/plans/2026-10-02-strategy-preview-market-correction.md`, P01
Requirements: REQ-001; Acceptance: AC-001

## Objective and scope

Accept an OKX `position-tiers` row that omits or blanks duplicated `instType`/`tdMode`, while rejecting explicit conflicts or malformed values. Preserve all other tier/family/numeric validation. No order-side effects from invalid data.

Predecessor: none. Required decision: D-001 only as context. Allowed writes: `backend/strategy.py`, `backend/tests/test_strategy_api.py`. Forbidden: protected configuration contents or writes, unrelated source, network order actions, API schema changes outside tier parsing.

Executor contract: Update only `_load_market_inputs` row validation and focused tests. The request already pins SWAP/isolated; missing, `None`, or empty string fields are acceptable. A nonempty wrong string or non-string field is invalid. Exact family and all existing Decimal bounds remain. Return the existing structured 502 for invalid tier data.

RED-001: fake public OKX tier row without row type/mode currently fails preview. GREEN-001: same row previews; explicit conflicting or malformed row fails with 502 and no order action. Execute formal RED before GREEN. Test: `python3.12 -m unittest backend.tests.test_strategy_api -v` after focused edit; verification ceiling V2. Task buildability after final source/test edit: `python3.12 -m compileall -q backend`, PASS required. Record exact results and route status. No external configuration or verification action.

Stop and return BLOCKED if public OKX response shape contradicts this contract or allowed scope is insufficient. Coordinator audit must confirm no weakened family/numeric validation and no protected file access.

## Completion and coordinator audit

Verdict: PASS. The executor observed RED before the source edit, then GREEN with `rtk test python3.12 -m unittest backend.tests.test_strategy_api -v` (24 tests, exit 0). Post-edit buildability: `rtk test python3.12 -m compileall -q backend` (exit 0). Coordinator inspected the two-file diff: omitted/null/blank duplicated tier metadata is accepted; conflicting and malformed values fail with structured 502 and no trade writes; family and numeric checks remain in place. No protected configuration path changed. Effective child route was not exposed after explicit `gpt-6-luna` / `high` binding.
