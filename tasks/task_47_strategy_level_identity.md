# Task 47 — Persist distinct strategy level identities

Status: PASS
Agent Role: implementation_executor
Executor Class: E2
Target Model: gpt-6-luna
Target Effort: max
Target Route: gpt-6-luna / max
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Dispatch Route Status: UNVERIFIABLE (explicitly bound; effective route unavailable)
Specification: `docs/agents/specs/2026-10-02-strategy-preview-market-correction.md`
Plan: `docs/agents/plans/2026-10-02-strategy-preview-market-correction.md`, P02
Requirements: REQ-002, REQ-003; Acceptance: AC-002, AC-003

## Objective and scope

Implement an additive ID-based selected-level API and keep distinct equal-price orders through preview, draft, prepare, execute, and reconciliation. Preserve no-ID legacy draft JSON and preview hashes.

Predecessor: T46 PASS. Decisions: D-002, D-003, D-004, D-007. Allowed writes: `backend/strategy.py`, `backend/tests/test_strategy_api.py`. Forbidden: protected configuration contents or writes, schema migration, auth/preflight weakening, UI or unrelated source.

Executor contract: New requests use `direction`, bounded unique `levelId` per row, and `entryLevelIdBySide`; all-or-none ID mode. Require direction equal to sides, a nearest-price chosen ID per side, price alignment, <=20 rows, and consistency if legacy `entryBySide` is also present. Sort canonically by side, numeric price, ID; use ID for role, client-order identity and saved/reconciled result mapping. Keep the legacy branch byte-compatible for persisted draft/hash behavior. Two same-side same-price IDs yield two orders and distinct client IDs. Group their modeled liquidation estimate after all group orders and label the estimate/fill-order caveat. Both direction requires Long and Short; Hedge preflight and separate side limit payloads remain.

RED-002: equal same-side price or ID mode currently rejects/merges and cannot preserve separate orders. GREEN-002: two equal-price IDs produce two durable orders; reordered input has same hash; Both produces both sides; malformed/missing/duplicate IDs, mismatched direction/entry and 21 orders fail before side effects; legacy saved draft/hash still works. Formal RED before GREEN using `python3.12 -m unittest backend.tests.test_strategy_api -v`; verification ceiling V2. Buildability after last edit: `python3.12 -m compileall -q backend`, PASS required. No external configuration action.

Stop and return BLOCKED for any incompatible persisted legacy shape, unresolvable grouped liquidation semantics, or required write outside scope. Coordinator audits ID lifecycle, compatibility and order-side effects.

## Completion and coordinator audit

Verdict: PASS. RED was observed before the implementation: 28 tests with nine failures, including equal-price ID rejection and missing validation. GREEN: `rtk test python3.12 -m unittest backend.tests.test_strategy_api -v` (28 tests, exit 0). Post-edit buildability: `rtk proxy python3.12 -m compileall -q backend` (exit 0); `rtk proxy git diff --check -- backend/strategy.py backend/tests/test_strategy_api.py` also exited 0. Coordinator inspected the source and test diff and traced ID-preserving preview, draft, prepare, batch, and result paths; Both retains two side-specific orders and Hedge preflight; legacy preview hash has a fixed regression assertion. No protected configuration path changed. Effective child route was not exposed after explicit `gpt-6-luna` / `max` binding.
