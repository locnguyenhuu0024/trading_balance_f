# Design Specification: Independent Long and Short Strategies
Status: READY_FOR_PLAN
Date: 2026-10-06
Tier: L
Decision Ledger: N/A — requested independence and existing Hedge/Net semantics resolve the contract.

## Objective and evidence
Allow independent Long and Short strategies on the same SWAP in verified OKX Hedge mode, including positions and live pending queues. strategy.py _preflight/_retry_review_guards currently reject any matching instrument. _result_for aggregates both sides; worker completion and deletion clearance also inspect the whole instrument. Frontend already preserves direction and strategy ID. SQLite reservations currently enforce one strategy per account/instrument.

## Requirements and acceptance
REQ-001 / AC-001: In Hedge mode ignore only explicitly valid opposite-side exposure; same-side positions/pending orders block, Both conflicts with either side. Net mode remains instrument-wide. Invalid relevant size/side/mode evidence fails closed. Test both Long-with-Short and Short-with-Long, prepare/execute, initial queue and retry selected orders.
REQ-002 / AC-002: Scope reservations by account, instrument, persisted prepared mode and executable sides. Only opposite single-sided Hedge scopes are disjoint. Same-side, Both, Net, unknown/legacy conflicts remain atomic under BEGIN IMMEDIATE. Preserve token/state rollback on refusal, leases, unknown acknowledgments and own-ID release. Allow opposite active queues/reservations.
REQ-003 / AC-003: Retry candidates use per-order overlap eligibility; exact selected scope revalidates at review/prepare/claim/resume. Keep source revisions, lineage, child identity, self-exclusion and replacement invariants.
REQ-004 / AC-004: Hedge result positions, PnL, attribution, completion and deletion refer to the strategy's executed sides. Opposite live position must not keep a closed strategy active or contaminate PnL. Fresh terminal order evidence remains required. Missing scope evidence must remain conservative; Net remains instrument-wide.
REQ-005 / AC-005: Existing database initializes repeatably without lost reservations. Legacy entries migrate conservatively. An owned legacy entry may be treated as a narrowed Hedge scope ONLY when its persisted prepared mode and exact executable order sides are validated and consistent with persisted snapshot/order evidence using the same scope validation as new claims; malformed/missing/orphan evidence stays all-instrument. Preserve identity/time and rollback migration failure.
REQ-006 / AC-006: Current mode must match prepared mode before both batch and queue claims/exchange writes. Existing balance checks and insufficient/partial/unknown outcomes remain; this change does not promise simultaneous budgets or add funding semantics.

## Interface, scope and invariants
No public API, frontend behavior, configuration or dependencies change. Add internal reservation position_mode and side_scope (long/short/all), retaining one unique strategy_id. Overlap checked atomically; all/Net/unknown scopes intersect both directions. Source-owned SQLite schema migration permitted; protected configuration unreadable/non-writable. Unknown position data never proves lifecycle clearance.
Allowed product surfaces: backend/strategy.py, backend/store.py, backend/strategy_worker.py; optional dedicated non-configuration backend/strategy_scope.py for shared pure helpers; focused strategy API/worker/queue/retry tests and a dedicated scope/migration test file. No real exchange calls, deployment, commit or push.

## Rollout and rollback
Backend restart loads source-owned migration. No user-owned configuration action required. Schema migration is forward compatible only with new code: do not run an older writer against the scoped table. Rollback requires stopping backend/worker and a user-managed database backup from before migration; agents do not manipulate live data. Legacy unknown entries intentionally stay conservative.

## Repository-evidenced compatibility clarification — D-001
Existing ordinary flow creates a draft in Net mode and prepares after switching to Hedge (test_strategy_api.py apply_strategy helper). A recognized draft snapshot mode can be stale. Valid persisted prepared mode is authoritative if prepared/snapshot/stored executable order signatures agree. Malformed/unrecognized snapshot mode still fails closed. Without prepared mode, validated snapshot fallback is lifecycle-only. Fresh current mode must match prepared mode before execution. This preserves existing supported behavior within REQ-005/006; no product scope expansion or user assumption.
