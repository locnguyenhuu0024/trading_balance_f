# Plan Validation Report: OKX MARGIN identity and interrupted execution

Status: INVALID (bounded replan required)
Date: 2026-09-30
Specification: `docs/agents/specs/2026-09-30-position-actions-design.md`
Plan: `docs/agents/plans/2026-09-30-live-position-actions.md`
Affected Tasks: T34, T35

## Summary

The approved fail-closed contract remains achievable, but the initial backend implementation assumed MARGIN direction and trade capacity fields that the official OKX contract does not support. T34 must correct identity and currency handling, disable unproven MARGIN market actions, and recover journal rows that were never attempted after process interruption.

## Findings

### VAL-001 — MARGIN direction and order currency

Plan assumption: P01 could normalize MARGIN position direction from the signed position size and use position currency as the order `ccy`.
Observed reality: OKX documents MARGIN `pos` as always positive, with `posCcy` equal to base currency for long and quote currency for short. Its Place order `ccy` denotes the isolated margin currency. The first implementation used signed size and sent position currency.
Evidence: Official OKX [positions](https://www.okx.com/docs-v5/en/#rest-api-account-get-positions) and [place-order](https://www.okx.com/docs-v5/en/#rest-api-trade-place-order) contracts; `backend/service.py:_normalize_position`, `backend/service.py:_build_target`.
Affected: REQ-001, REQ-003, REQ-004, AC-001, AC-003, AC-004, P01, T34, T35.
Impact: A real MARGIN short could be mislabeled and an order could target the wrong isolated currency.
Required action: REPLAN within the approved fail-closed eligibility matrix. Derive MARGIN direction only from a verified base/quote `posCcy`; reject missing/other values. Send MARGIN order `ccy` from the confirmed margin currency.

### VAL-002 — Unproven exact MARGIN market capacity

Plan assumption: verified `availPos` and debt fields could establish exact trade capacity for the first-release MARGIN short DCA and long partial-close cases.
Observed reality: OKX defines `availPos` as closable position size, not additional DCA capacity, and debt may be denominated in a different currency than the base-sized sell order. The implementation compared unlike units and a test used synthetic debt units.
Evidence: Official OKX [positions](https://www.okx.com/docs-v5/en/#rest-api-account-get-positions) contract; `backend/service.py:_eligibility`, `backend/service.py:_build_target`, `backend/tests/test_trade_api.py` MARGIN fixtures.
Affected: REQ-003, REQ-004, AC-003, AC-004, P01, T34, T35.
Impact: An unsupported MARGIN market order could exceed available capacity or fail to represent the user's exact position-unit request.
Required action: REPLAN by disabling MARGIN DCA and partial close in this release with an explicit reason, while retaining eligible isolated add-margin and 100% close. This follows D-014 and the existing fail-closed contract; later enablement requires a separate documented capacity design.

### VAL-003 — Interrupted operation before first write

Plan assumption: a persisted `ATTEMPT_STARTED` row covered restart safety for every operation step.
Observed reality: the service persists `IN_PROGRESS` before preflight, while some target rows are still `PENDING`. A process stop at that point leaves those rows blocking later preparation without a way to complete them.
Evidence: `backend/service.py:_execute`, `backend/service.py:_get_result`, `backend/service.py:_pending_target_conflict`.
Affected: REQ-006, REQ-009, AC-006, AC-009, P01, T34.
Impact: A position can remain permanently blocked even though its write was never attempted.
Required action: REPLAN within the journal contract. On result lookup after restart, mark `PENDING` rows in an `IN_PROGRESS` operation as unattempted/conflicted; never send them automatically. Retain `ATTEMPT_STARTED` as UNKNOWN. Add restart tests for single action and a later close-all target.

## Execution Decision

Affected branch: STOPPED for T35 until T34 passes the revised contract and whole-backend buildability gate. T34 remediation may continue on non-protected code/tests.
Reason: Real-trade MARGIN interpretation and journal recovery require correction before client integration.

## Required Artifact Updates

- Specification: clarify REQ-001/003/004 and journal restart semantics in sections 5 and 7.
- Decisions: none; D-014 already authorizes fail-closed MARGIN cases.
- Plan: P01/P02 and verification matrix.
- Tasks: T34 correction and T35 eligible-action projection.
- Fresh user approval required: NO — all corrections tighten the approved fail-closed contract and add no live action.
