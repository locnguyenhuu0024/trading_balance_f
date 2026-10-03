# Implementation Plan: Strategy preflight account reads
Status: COMPLETE
Date: 2026-10-03
Tier: M
Specification: docs/agents/specs/2026-10-03-strategy-preflight-account-reads.md
Decision Ledger: docs/agents/decisions/2026-10-03-strategy-preflight-account-reads.md

## Planning workstreams
| Workstream | Material | Independent | Route | Run | Adoption |
|---|---|---|---|---|---|
| Account read boundaries / upstream 429 | YES | YES | R2 / gpt-6.1-sol / medium | R2-READS | COMPLETE / USED |
| Available-balance parsing / required fees | YES | YES | R2 / gpt-6.1-sol / medium | R2-BALANCE | COMPLETE / USED |
| Frontend | NO | N/A | N/A | N/A | Existing generic API behavior retained |
Fan-out Required: YES. Required Reasoning Agents: 2. Actual Reasoning Agents: 2. Fan-out Compliance: PASS. Skip Reason: N/A.
Cross-workstream synthesis: local account snapshot, safe explicit 429 errors, shared fail-closed availBal parser; no speculative availEq fallback.
Coordinator class C1; main runtime route fixed/unavailable, not claimed as selected. Child effective routes unavailable; explicit dispatch status UNVERIFIABLE. Runtime has no close/release child primitive; completed results collected, lifecycle cleanup unavailable.

## Dependency graph and task
P01/T75 -> coordinator audit -> final repository builds.
P01 implements REQ-001..003 / AC-001..005 as one buildable bounded backend task to avoid overlapping strategy.py writers.
Allowed: backend/strategy.py, backend/diagnostics.py, backend/app.py; backend/tests/test_strategy_api.py, backend/tests/test_strategy_diagnostics.py, backend/tests/test_strategy_worker.py, backend/tests/test_strategy_retry.py. No other source writes without coordinator remediation contract.
Executor: E1 / gpt-6-luna / xhigh; role implementation_executor; explicit binding; inheritance forbidden.

## Verification
Formal RED: selected negative cases for malformed/low balances, 429, changed identity/mode and no writes. Formal GREEN: one-read adequate/equal balance ordinary/retry prepare and independent-request freshness. Coordinator reuses observed evidence, audits explicit source diffs and runs final builds after final mutation.
V3 ceiling because shared ordinary/retry/worker preflight is touched. Tests: python3 -m unittest backend.tests.test_strategy_api backend.tests.test_strategy_diagnostics backend.tests.test_strategy_retry backend.tests.test_strategy_worker backend.tests.test_strategy_queue -q.
Task canonical build: PYTHONPYCACHEPREFIX=/private/tmp/preflight-fix-pycache python3 -m compileall -q backend.
Final top-level builds: same backend command and /Users/locnguyen/development/flutter/bin/flutter build web --no-pub (existing documented route). Build tools consume config opaquely only; no generators/dependency install/config mutation.
Baseline: 91 existing strategy API/diagnostics tests passed before implementation.
External configuration/actions: none. No live verification, commit, push or deploy.
Authorization: direct user instruction explicitly permits autonomous decisions and immediate execution after plan, overriding repeated post-plan confirmation. Plan presented in commentary before dispatch.

User steering incorporated before dispatch: REQ-004/AC-006 preserves ACK-gated sequential queue already in code. Worker pacing/ACK safety evidence is derived from existing implementation and queue spec; no third independently material design workstream or state-machine change. Include queue negative timeout/malformed ACK and successful ordered placement verification. Worker _queue_validation_reason may be updated only to preserve exchange_rate_limited diagnostics, not alter queue lifecycle.

AUD-001 / bounded scope extension before implementation: backend/okx.py account_balance currently silently filters non-dict response rows, concealing malformed input from the strict parser. Allow modifying ONLY account_balance to reject malformed data shape/rows with content-free OKXTransportError; preserve other endpoint filtering. Injected-transport raw malformed balance test must prove 502/no writes. This implements existing REQ-003, no new business/data semantics.

AUD-002 / REQ-001 clarification: batch execute obtains a new account in _current_strategy for that execute request; pass that new snapshot into its initial preflight to avoid adjacent duplicate reads. Never reuse prepare identity. Post-leverage preflight must still obtain another new snapshot. Sequential enqueue already performs one identity read. Add execute-phase freshness/post-leverage account-switch evidence; no lifecycle semantics change.

## Completion
T75 PASS; AC-001..006 PASS. V3 148 tests PASS; final backend compileall and Flutter web build exit 0. Independent audit: docs/agents/audits/2026-10-03-strategy-preflight-account-reads.md. No external configuration actions, commit, push or deployment.
