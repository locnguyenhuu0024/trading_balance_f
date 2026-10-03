# Task 64 — Selective Limit Resubmission Backend

Status: PASS
Agent Role: implementation_executor
Executor Class: E2
Target Model: gpt-6-luna
Target Effort: max
Target Route: gpt-6-luna / max
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Specification: `docs/agents/specs/2026-10-03-strategy-limit-cap-resubmission-design.md`
Plan: `docs/agents/plans/2026-10-03-strategy-limit-cap-resubmission.md`
Plan Steps: P03
Requirements: REQ-005,006,007,009
Acceptance Criteria: AC-005,006,007,009

## 1. Dispatch Compliance

Bind role, class, model and effort explicitly before mutation; coordinator remains non-writing for implementation. Dispatch Route Status: UNVERIFIABLE. Requested Model: gpt-6-luna. Requested Effort: max. Observed Effective Model/Effort: unavailable. Explicit request without exposed effective route may be UNVERIFIABLE; mismatch stops mutation; unavailable binding is BLOCKED_ROUTE, never inherited fallback.

## 2. Objective

Provide authoritative fixed-order retry review and atomic linked attempts using existing storage and submission machinery.

Done when assigned acceptance tests, RED-before-GREEN, affected-unit build and independent coordinator audit all PASS.

## 3. Preconditions

Predecessors: T62 = PASS; may run alongside T63 on disjoint source/test surfaces.
Decisions: D-001..004, A-001..002 in current decision ledger. Canonical plan must be presented and explicitly authorized after presentation before dispatch. Source baseline includes audited T61 diagnostics.

## 4. Allowed Scope

- `backend/strategy_retry.py (new)`
- `backend/tests/test_strategy_retry.py (new)`
- `backend/strategy.py`
- `backend/strategy_worker.py`
- `backend/app.py`
- `backend/diagnostics.py`
- `backend/tests/test_strategy_api.py`
- `backend/tests/test_strategy_queue.py`
- `backend/tests/test_strategy_worker.py`
- `backend/tests/test_strategy_diagnostics.py`
- `backend/tests/test_trade_api.py`
- `docs/deployment/position-trade-api.md`

## 5. Forbidden Scope

No protected configuration content access or mutation, dependencies, manifests, env, Docker/scripts/CI/deployment settings, schema/store changes, live orders, external uploads, Git writes, canonical artifact/status/telemetry writes or opportunistic refactors. Listed explanatory Markdown is allowed documentation. Required work beyond this surface returns BLOCKED for coordinator replan.

## 6. Executor Contract

1. Implement the three source-scoped routes and strict request/response/error contracts in specification §§6–12. Reject client kind/payload injection. Authenticate account ownership before source access; perform fresh read-only reconciliation outside transactions.
2. Eligibility requires consistent persisted evidence: definitely not_submitted or bounded numeric nonzero rejection. Malformed batch codes become UNKNOWN, including historic malformed-code exclusion. Accepted/unknown/sending/canceled-after-acceptance/corrupt rows never qualify. Placement in-flight rows fail closed; a stopped leverage marker alone does not exclude a trusted unsent row.
3. Dedicated preview preserves source-order side/role/price/contracts/leverage/levelId, including DCA-only. Never call ordinary quantity allocation. Recompute fixed costs/cumulative entries/tier/liquidation with fresh market inputs; use specification formula and its independent numeric fixture. Validate lot/tick/min/passive/mode/fees/balance/zero-position/no-pending/reservation guards. Hash all reviewed semantic inputs; omit observational polling/quote timestamps but independently recheck freshness.
4. Construct linked child metadata server-side in existing JSON; leave replacement_source_id NULL; fresh child client IDs at creation, preserved on prepare. Validate retryRequestId format and bind replay to identical source/revision/ordered selection/hash. Existing matching child is returned first without minting token; conflicting reuse refuses. No schema/store/dependency change.
5. BEGIN IMMEDIATE atomic creation rejects overlap. Repeat authoritative source/lineage/selection checks inside both token claims before consumption, excluding only this child. Direct source rows become permanently consumed when child attemptStarted=1, regardless of later cancellation or outcome. Retry a rejected child from that child, never its ancestor.
6. Shared dependency/delete/replacement guards protect any referenced source and every claimed retry child, even when orderPlacementAttempted=false. Unclaimed child safe deletion releases overlap. Block retry sources with any persisted ordinary replacement child; symmetrically stop ordinary replacement create/claim/cleanup after retry child exists. Test both serialization orders. No network or diagnostics sink I/O inside transaction.
7. Child prepare freezes current account preference and uses fresh standard token. Branch fixed preflight at prepare/execute/worker without reallocating. Preserve existing queue/batch markers, unknown handling, leases/fences/deadlines/reservations and execute no-op behavior.
8. Add fixed diagnostic route/stage/code classifications only; preserve T61 bounds/privacy and correctly label GET versus POST. Update explanatory API guide for fixed retry, blocked states and history. No live exchange calls.

Preserve specification INV-001..006 where affected. Requirements/architecture are coordinator-owned; report contradictions instead of inventing semantics or escalating routes.

## 7. External Configuration / Environment Actions

Planned actions: NONE. Additional unknown configuration requirements: BLOCKED; ask minimum safe fact via coordinator. No user-applied configuration required for offline verification.

## 8. Tests

TEST-64: New retry fixtures plus affected strategy API/queue/worker/diagnostics and shared trade API tests. Deterministic barriers/transactions for create/claim/delete/replacement races; no sleeping timing assumptions or real orders.

## 9. Mandatory Verification

### RED — RED-003

Scenario: Accepted/unknown/malformed/active/stale/tampered selections, concurrent overlaps, descendant claim then delete/replacement, ordinary replacement races and safety preflight failures refuse with zero new placements; history is retained.
Method: offline focused cases within allowed test files; executor reports exact case names and RTK/native command before terminal report. Expected: all negative safety assertions PASS with explicit call/state counts. Actual/status: PASS; RED10 then GREEN9.

### GREEN — GREEN-003

Scenario: Exact eligible mixed or DCA-only subset has correct fixed costs/hash/new IDs and submits once in both modes; idempotent creation produces one child, duplicate execute one attempt; unclaimed child delete releases overlap; rejected child is eligible as a new source; observational polling does not stale-bind.
Method: separate offline focused cases after RED; exact command/case names recorded. Expected: successful behavior and preserved invariants PASS. Actual/status: PASS; RED10 then GREEN9.

Run formal RED then GREEN after readiness; RED is a passing negative scenario, not a deliberately failing suite. Narrow diagnostics during editing are not formal evidence. Later executable changes invalidate affected evidence only. Verification ceiling: V3 affected groups; V4 not required. Broaden only for a concrete regression/shared-path risk and record why. RTK-first; exact/raw fallback only with evidence/compatibility reason. WSGI loopback tests may require sandbox escalation; do not diagnose by opening config.

### Task Buildability Gate

Required: YES. Unit: backend. Boundary: self-contained compatible change; no later task restores compilation.

```sh
PYTHONPYCACHEPREFIX=/private/tmp/strategy-limit-cap-pycache /Users/locnguyen/.local/bin/rtk test /opt/homebrew/bin/python3.12 -m compileall -q backend
```

Run after final task-local executable/test edit. Result: PASS; exit0; no errors; coordinator compile repeated after final source/test state. Tests are not substitutes for canonical application build. Code failure => REWORK; genuine toolchain pre-build failure => BLOCKED_ENVIRONMENT. Consume configs only as opaque native-tool input.

### External Verification

Required: NO. Offline fake exchange only; production behavior is not verified.

## 10. Stop Conditions

Return BLOCKED for insufficient contract, ownership/lineage ambiguity, scope mismatch, predecessor invalidation, required protected facts or unavailable verification; report affected REQ/AC and concise evidence. Do not change architecture or broaden surface unilaterally.

## 11. Execution Ledger

- [x] Explicit dispatch and no parent inheritance verified.
- [x] Assigned step and tests implemented within surface.
- [x] Formal RED then GREEN PASS with exact names/commands/results.
- [x] V3 affected regressions sufficiently verified.
- [x] Final affected-unit build PASS after last executable edit.
- [x] No protected content access or modification; external actions NONE.
- [x] Compact terminal report and safe telemetry envelope returned; no runtime IDs persisted.

## 12. Coordinator Audit

Scope/AC/test quality/RED/GREEN/order/contract/build: PASS. Explicit route UNVERIFIABLE, inheritance NO. Evidence reused; narrow compile repeated for freshness clarification. Verdict: PASS. Coordinator records audit and canonical status; executor does not.

Routing blocker: runtime rejected explicit E2 Luna/max spawn with agent thread limit reached. No T64 mutation started. User decision requested for alternate existing E1 Luna/xhigh executor; planned route is not silently changed.

Routing recovery 2026-10-03: user requested retry of original executor settings. Explicit native spawn succeeded for E2-T64-02 with gpt-6-luna/max; effective route unavailable, UNVERIFIABLE; no inheritance. Prior route blocker cleared without route change.

Final audit: `docs/agents/audits/2026-10-03-task64-limit-resubmission-audit.md`. Formal RED10 then GREEN9; affected123 plus trade49 PASS; backend compile exit0. No protected configuration action or live exchange calls. Final exact focused test names retained in executor fan-in; affected commands:

```sh
/Users/locnguyen/.local/bin/rtk test /opt/homebrew/bin/python3.12 -m unittest backend.tests.test_strategy_api backend.tests.test_strategy_queue backend.tests.test_strategy_worker backend.tests.test_strategy_diagnostics backend.tests.test_strategy_retry
/Users/locnguyen/.local/bin/rtk test /opt/homebrew/bin/python3.12 -m unittest backend.tests.test_trade_api
PYTHONPYCACHEPREFIX=/private/tmp/strategy-limit-cap-pycache /Users/locnguyen/.local/bin/rtk test /opt/homebrew/bin/python3.12 -m compileall -q backend
```

Exact formal checkpoints from terminal evidence, observed RED10 then GREEN9, both exit0:

```sh
/Users/locnguyen/.local/bin/rtk test /opt/homebrew/bin/python3.12 -m unittest backend.tests.test_strategy_retry.StrategyRetryTests.test_red_malformed_batch_codes_and_fill_or_order_id_evidence_fail_closed backend.tests.test_strategy_retry.StrategyRetryTests.test_red_claimed_or_accepted_rows_are_never_retryable backend.tests.test_strategy_retry.StrategyRetryTests.test_red_exact_fixed_size_must_match_current_lot_rules backend.tests.test_strategy_api.StrategyApiTests.test_red_malformed_batch_code_is_unknown_and_never_a_retry_candidate backend.tests.test_strategy_api.StrategyApiTests.test_red_retry_review_rejects_position_pending_reservation_and_balance_blocks backend.tests.test_strategy_api.StrategyApiTests.test_red_retry_prepare_rejects_changed_mode_and_freezes_current_mode backend.tests.test_strategy_api.StrategyApiTests.test_red_retry_claim_consumes_source_and_protects_child_and_parent backend.tests.test_strategy_api.StrategyApiTests.test_red_persisted_ordinary_replacement_blocks_retry_source backend.tests.test_strategy_api.StrategyApiTests.test_red_concurrent_retry_and_ordinary_replacement_claim_only_one_source backend.tests.test_strategy_api.StrategyApiTests.test_red_both_retry_claim_transactions_recheck_source_before_consumption
/Users/locnguyen/.local/bin/rtk test /opt/homebrew/bin/python3.12 -m unittest backend.tests.test_strategy_retry.StrategyRetryTests.test_green_fixed_preview_preserves_dca_payload_and_uses_exact_costs backend.tests.test_strategy_retry.StrategyRetryTests.test_green_source_revision_ignores_poll_time_and_live_fill_amount backend.tests.test_strategy_api.StrategyApiTests.test_green_retry_dca_only_keeps_fixed_rows_ids_and_idempotent_execute backend.tests.test_strategy_api.StrategyApiTests.test_green_retry_sequential_worker_revalidates_fixed_preview_with_self_reservation backend.tests.test_strategy_api.StrategyApiTests.test_green_claimed_child_permanently_consumes_source_after_cancel_and_release backend.tests.test_strategy_api.StrategyApiTests.test_green_rejected_retry_child_can_supply_one_linked_grandchild backend.tests.test_strategy_api.StrategyApiTests.test_green_retry_mixed_long_short_subset_preserves_hedge_sides_and_payload backend.tests.test_strategy_api.StrategyApiTests.test_green_retry_worker_resume_revalidates_fixed_hash_and_excludes_self_reservation backend.tests.test_strategy_api.StrategyApiTests.test_green_stopped_sequential_leverage_rejection_allows_fixed_unsent_tail_retry
```
