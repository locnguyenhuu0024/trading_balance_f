# Task 62 — Ten-order Admission Backend

Status: PASS
Agent Role: implementation_executor
Executor Class: E1
Target Model: gpt-6-luna
Target Effort: xhigh
Target Route: gpt-6-luna / xhigh
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Specification: `docs/agents/specs/2026-10-03-strategy-limit-cap-resubmission-design.md`
Plan: `docs/agents/plans/2026-10-03-strategy-limit-cap-resubmission.md`
Plan Steps: P01
Requirements: REQ-001,003,004
Acceptance Criteria: AC-001,003,004

## 1. Dispatch Compliance

Bind role, class, model and effort explicitly before mutation; coordinator remains non-writing for implementation. Dispatch Route Status: UNVERIFIABLE. Requested Model: gpt-6-luna. Requested Effort: xhigh. Observed Effective Model/Effort: unavailable. Explicit request without exposed effective route may be UNVERIFIABLE; mismatch stops mutation; unavailable binding is BLOCKED_ROUTE, never inherited fallback.

## 2. Objective

Enforce at most ten newly admitted orders while preserving already confirmed historical queues through twenty.

Done when assigned acceptance tests, RED-before-GREEN, affected-unit build and independent coordinator audit all PASS.

## 3. Preconditions

Predecessors: None; post-plan execution authorization required.
Decisions: D-001..004, A-001..002 in current decision ledger. Canonical plan must be presented and explicitly authorized after presentation before dispatch. Source baseline includes audited T61 diagnostics.

## 4. Allowed Scope

- `backend/strategy.py`
- `backend/tests/test_strategy_api.py`
- `backend/tests/test_strategy_queue.py`

## 5. Forbidden Scope

No protected configuration content access or mutation, dependencies, manifests, env, Docker/scripts/CI/deployment settings, schema/store changes, live orders, external uploads, Git writes, canonical artifact/status/telemetry writes or opportunistic refactors. Listed explanatory Markdown is allowed documentation. Required work beyond this surface returns BLOCKED for coordinator replan.

## 6. Executor Contract

1. Separate new admission maximum10 from historical readable/queue capacity20. Guard normalized selected levels, persisted contract/orders and prepared orders before preparation/preflight and new batch/sequential claims.
2. Reject old unstarted DRAFT/PREPARED over10 without truncation, token consumption or placement. Preserve attempted execution no-op behavior and never reset persisted markers.
3. Keep worker envelope20, FIFO, pacing, reservations, lease/fence/deadline and global20-per-pass budget unchanged. Seed legacy confirmed20 directly in tests; do not create a new20-order strategy via the now-restricted API.
4. Preserve existing invalid_order_count code and update explanatory message. Do not introduce migration or config changes.

Preserve specification INV-001..006 where affected. Requirements/architecture are coordinator-owned; report contradictions instead of inventing semantics or escalating routes.

## 7. External Configuration / Environment Actions

Planned actions: NONE. Additional unknown configuration requirements: BLOCKED; ask minimum safe fact via coordinator. No user-applied configuration required for offline verification.

## 8. Tests

TEST-62: Affected strategy API/queue cases, including old unstarted records, token/state parity, both submission modes and historical worker scheduling.

## 9. Mandatory Verification

### RED — RED-001

Scenario: 11 new single/mixed6+5 levels and oversized unstarted persisted records refuse before placement/claim; attempted records keep markers.
Method: offline focused cases within allowed test files; executor reports exact case names and RTK/native command before terminal report. Expected: all negative safety assertions PASS with explicit call/state counts. Actual/status: PASS (formal checkpoint recorded below).

### GREEN — GREEN-001

Scenario: Exactly10 single/mixed5+5 succeeds in both modes; seeded confirmed20 queue finishes its full tail and global20/pass remains.
Method: separate offline focused cases after RED; exact command/case names recorded. Expected: successful behavior and preserved invariants PASS. Actual/status: PASS (formal checkpoint recorded below).

Run formal RED then GREEN after readiness; RED is a passing negative scenario, not a deliberately failing suite. Narrow diagnostics during editing are not formal evidence. Later executable changes invalidate affected evidence only. Verification ceiling: V3 affected groups; V4 not required. Broaden only for a concrete regression/shared-path risk and record why. RTK-first; exact/raw fallback only with evidence/compatibility reason. WSGI loopback tests may require sandbox escalation; do not diagnose by opening config.

### Task Buildability Gate

Required: YES. Unit: backend. Boundary: self-contained compatible change; no later task restores compilation.

```sh
PYTHONPYCACHEPREFIX=/private/tmp/strategy-limit-cap-pycache /Users/locnguyen/.local/bin/rtk test /opt/homebrew/bin/python3.12 -m compileall -q backend
```

Run after final task-local executable/test edit. Result: PASS; exit0; errors: none; run after last task-local edit. Tests are not substitutes for canonical application build. Code failure => REWORK; genuine toolchain pre-build failure => BLOCKED_ENVIRONMENT. Consume configs only as opaque native-tool input.

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

Scope/AC/test quality/RED/GREEN/order/contract/build: PASS. Dispatch: UNVERIFIABLE after explicit binding; inheritance NO. Evidence reused after independent source/test review; no rerun needed. Verdict: PASS. Coordinator records audit and canonical status; executor does not.

Coordinator verdict: PASS. Audit: `docs/agents/audits/2026-10-03-task62-ten-order-cap-audit.md`. Formal RED4 then GREEN3; affected76; final backend compile exit0. Exact verification commands are retained in executor completion evidence and will be consolidated in final audit.

Final exact commands, in observed order, each exit0:

```sh
rtk test /opt/homebrew/bin/python3.12 -m unittest backend.tests.test_strategy_api.StrategyApiTests.test_red_new_contract_admission_rejects_eleven_single_and_mixed_rows backend.tests.test_strategy_api.StrategyApiTests.test_red_unstarted_persisted_oversize_records_reject_before_preflight_or_claim backend.tests.test_strategy_api.StrategyApiTests.test_red_batch_and_sequential_claims_recheck_persisted_order_count backend.tests.test_strategy_api.StrategyApiTests.test_red_attempted_oversize_strategy_execute_remains_noop_and_keeps_markers
rtk test /opt/homebrew/bin/python3.12 -m unittest backend.tests.test_strategy_api.StrategyApiTests.test_green_ten_order_contracts_apply_in_both_submission_modes backend.tests.test_strategy_queue.StrategyQueueTests.test_green_ten_order_queue_finishes_the_full_tail backend.tests.test_strategy_queue.StrategyQueueTests.test_worker_pass_shares_twenty_placement_budget_and_preserves_spacing
rtk test /opt/homebrew/bin/python3.12 -m unittest backend.tests.test_strategy_api backend.tests.test_strategy_queue
PYTHONPYCACHEPREFIX=/private/tmp/strategy-limit-cap-pycache /Users/locnguyen/.local/bin/rtk test /opt/homebrew/bin/python3.12 -m compileall -q backend
```
