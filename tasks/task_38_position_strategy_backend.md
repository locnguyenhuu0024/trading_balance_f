# Task 38 — Position Strategy Backend

Status: PASS
Agent Role: implementation_executor
Executor Class: E2
Target Model: gpt-6-luna
Target Effort: max
Target Route: gpt-6-luna / max
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Dispatch Route Status: UNVERIFIABLE
Requested Model/Effort: gpt-6-luna / max, explicitly bound at dispatch
Observed Effective Model/Effort: unavailable until runtime reports them
Specification: `docs/agents/specs/2026-10-01-position-strategy-design.md`
Plan: `docs/agents/plans/2026-10-01-position-strategy.md`
Plan Steps: P01
Requirements: REQ-004..REQ-008
Acceptance Criteria: AC-003..AC-007

## Objective and preconditions

Implement the complete authenticated, durable backend strategy preview/save/apply/status/delete contract. Done when focused fake-transport tests prove both rejection and correct one-time batch placement, and the Python backend compiles. Predecessors: none. Required decisions: D-001..D-015. Obtain explicit execution approval before dispatch. If the runtime cannot explicitly bind **both** model and effort, mark `BLOCKED_ROUTE`; never inherit the coordinator route.

## Allowed write surface

- `backend/service.py`, `backend/okx.py`, `backend/store.py`
- New non-config backend strategy module(s), `backend/tests/test_strategy_api.py`
- Existing backend test file(s) only where the new API must share fixtures or prove no regression

Protected configuration/environment/manifest/dependency/CI files are forbidden for both content reads and writes. Do not modify unrelated position-action behavior, introduce a dependency, execute a live OKX order, or commit/push. If the specified contract requires a broader surface, return `BLOCKED` for coordinator replanning.

## Executor contract

Follow P01 and spec §§3–6. Reuse session/account-fingerprint and operation safety patterns. Backend preview is authoritative for Decimal sizing, side budgets/linear weights, tick/lot/minimum validation, per-step cumulative entry and conditional liquidation with current tier and fee inputs. Isolated USDT SWAP only; no existing instrument position or pending order at apply; two-sided Net mode blocked; <=20 selected limit orders; one stable `clOrdId` each. Persist the attempt before the batch call. Do not resend after timeout/unknown response. Save/retrieve/delete only never-attempted drafts. Status displays actual OKX position PnL/entry/liq and filled-only used margin.

The existing backend settings remain opaque. External configuration action: none planned. Stop if live OKX field semantics are missing/contradictory, if preview cannot safely produce the estimate, or if account mode/metadata cannot be validated. Return the finalized JSON request/response and error schema to the coordinator for T39.

## RED then GREEN verification

- RED-002/RED-003: Run focused fake-transport scenarios before primary GREEN: unauthenticated/wrong account, invalid metadata/tier/fee or sizing, Net mode two-sided, existing position/order, expired prepare, duplicate execute and partial/unknown batch. Expected: zero unauthorized/duplicate OKX batch writes, truthful durable state, no deletion after attempt.
- GREEN-002/GREEN-003: Then run eligible prepared strategy, explicit confirmation and one <=20 limit-order batch with correct isolated side leverages, client IDs and per-order statuses. Restart/read status without another write. Independently verify a known Decimal sizing/liquidation fixture.
- Command: `python3.12 -m unittest backend.tests.test_strategy_api -v` (V1, V2 ceiling; V3 only if existing action safety is affected).
- Task buildability after last executable edit: `python3.12 -m compileall -q backend`; affected canonical unit is `backend`, required PASS.

## Checklist and audit handoff

- [x] explicit dispatch role/model/effort match and status `MATCH` or `UNVERIFIABLE`
- [x] no protected config content read or protected file modified
- [x] implementation within allowed surface; no live order
- [x] observed RED before GREEN and focused tests recorded
- [x] backend buildability PASS after final change
- [x] report exact commands/results, changed paths, API schema, partial/unknown handling and remaining limitations

Coordinator audit: AUD-001..AUD-006 remediated. Final verdict: PASS; 21 focused strategy tests, 70 backend tests, and Python compile passed after the final edit. Live OKX behavior remains unverified.
