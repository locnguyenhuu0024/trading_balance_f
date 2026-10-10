# Task 115 — Account-fair workers and global resource budgets

Status: PENDING — plan not approved for execution
Agent Role: implementation_executor
Executor Class: E2
Target Model: gpt-6-luna
Target Effort: max
Target Route: gpt-6-luna / max
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Dispatch Route Status: PENDING
Requested Model / Effort: PENDING (do not fill until actually dispatched)
Observed Effective Model / Effort: unavailable
Specification: `docs/agents/specs/2026-10-10-multi-user-okx-binance-design.md`
Plan: `docs/agents/plans/2026-10-10-multi-user-okx-binance.md`
Plan Steps: P06
Requirements: REQ-004, REQ-006
Acceptance Criteria: AC-004, AC-006
Frontend Level: N/A
Frontend Design Brief: N/A
Visual Review Required: NO

## 1. Objective and preconditions

Implement P06 exactly as defined in the canonical plan. Done when the referenced behavioral contracts, relevant regression, final task build and independent audit pass.
Predecessors/readiness: T113 = PASS; no concurrent backend writer. A-001–010 and INV-001–006 are binding. No product/architecture invention by the executor.
Runtime/setup: Dedicated PostgreSQL multi-process fixture and spec §11 workload; fake upstreams for load, never stress live exchanges.
Provisioning/installation is operator-owned and is not part of the executor write scope.

## 2. Allowed write surface

- `backend/worker_scheduler.py`
- `backend/strategy_worker.py`
- `backend/strategy_queue.py`
- `backend/strategy_retry.py`
- `backend/strategy.py`
- `backend/command_ledger.py`
- `backend/account_context.py`
- `backend/data_gateway.py`
- `backend/postgres_store.py`
- `backend/schema_multiuser.py`
- `backend/exchanges/binance_transport.py`
- `backend/okx.py`
- `backend/service.py`
- `backend/tests/test_worker_scheduler.py`
- `backend/tests/test_strategy_worker.py`
- `backend/tests/test_strategy_queue.py`
- `backend/tests/test_positions_read_pressure.py`

Read only the source/tests/docs needed for the listed contracts. New interfaces stage compatibility with existing consumers; leave the affected canonical unit buildable. Directory surfaces are restricted to the described hand-written source/test roles, not arbitrary settings or generated files.

## 3. Forbidden scope and reuse

All protected environment/runtime/dependency/build/CI/deployment/workspace files: content access and writes forbidden. No root recursive content search without explicit non-protected allowlist. No new dependency installation/manifest edits, source upload, secret retrieval, live account operations, migration of production data, commit/push or deployment. No unrelated feature redesign.
Reuse existing gateway/session fences/security helpers/OKX transport/native controls as applicable. If scope expands or a contract is insufficient, return BLOCKED to coordinator.

## 4. Executor contract

1. Replace singleton lease with per-connection/job CAS/fence using database time; preserve write markers, FIFO spacing, terminal/zero-position proof.
2. Account-fair due-job scheduling and bounded admission/queue; reserve capacity for reconciliation/cancel/risk reduction.
3. Shared bounded I/O executors and leased account context LRU; idle accounts have no worker/poller/pool allocation.
4. Coordinate IP/account budgets and active-account admission across processes in DB; observed 429/Retry-After feeds bounded safe-read backoff.
5. Do not evict active claims; lost lease blocks subsequent sends and unresolved attempt prevents replacement send; retain existing strategy density limits.
6. Coalesce public cache misses across processes using DB-owned fetch lease and bounded latest-value TTL snapshot. Private single-flight is per process, maximum four upstream fetches in the four-process profile and still subject to global account/IP limits.

Follow P06; preserve the single backend boundary, owner filtering, decimal units, server-proven lifecycle and bounded resources. Expected unsafe-path behavior is defined by spec §8, not implementation convenience.

## 5. Tests and formal RED → GREEN

Behavioral pairs: RED/GREEN-004 and 006.
RED scenario and independently expected result: One noisy/429 account, full queue, expired fence, two workers and lost ACK cannot starve healthy accounts, multiply global limits or duplicate a send. Overload returns bounded 429/503.
GREEN scenario and independently expected result: Admitted healthy accounts progress fairly with one write slot each and shared public coalescing; 100-user mocked reference load meets documented bounds or is honestly reported unmet.
Cross-process coalescing case: distribute 50 identical miss callers across four API processes; public resource has one deployment-owned fetch; private same-scope resource has at most one fetch/process (maximum four), never unbounded amplification. Lease loss prevents stale public publication.

Method: `python3.12 -m unittest backend.tests.test_worker_scheduler backend.tests.test_strategy_worker backend.tests.test_strategy_queue backend.tests.test_positions_read_pressure -q`; name/select focused negative then success cases explicitly and record order, setup, outcome and exit. Proposed suites do not exist yet; these are implementation deliverables, not currently passing tests. Add a failing-baseline regression where new behavior is absent. Use only fabricated keys/account payloads.

Inner-loop diagnostics are narrow/non-authoritative. At readiness run formal RED before GREEN, then relevant regression and final build. Later edits rerun affected evidence only; restart pair if shared verification basis changes.
Verification ceiling: V3 (focused related tests). Full V4 belongs to T116 final integration only, justified by global auth/storage/DTO changes.
Escalation trigger: shared consumers changed, related regression failure, or task proof lacks required concurrency/runtime evidence; document reason before widening.

## 6. Task buildability and frontend evidence

Required: YES
Canonical build unit: backend Python package
Exact secret-free build command: `python3.12 -m compileall -q backend`
Run after the final executable/test change. Result/exit: PENDING. Buildable compatibility staging required; no PASS while awaiting a successor repair.
Backend compileall is paired with import/runtime tests; mocks cannot substitute PostgreSQL multi-process checks.

Frontend gate: N/A.

## 7. External actions, stop conditions and audit

External configuration/actions are spec §12 and the setup prerequisite above, all user-owned. No agent reads/creates protected files. Integration needing unapplied inputs is BLOCKED; report exact safe target/key/placeholder and validation step already specified in the spec. Unknown production topology/paths block launch, not synthetic checks.

STOP for missing approval/predecessor/setup, observable route mismatch, missing owner/capability contract, scope expansion, secret-bearing output, unavailable required verification or broken task build. Unknown exchange outcome is retained and reconciled; never resolve it by repeating a write.

Coordinator owns canonical status/audit/telemetry. Writer returns exact safe commands, scenario results, changed path names, build exit, limits and external-action list. Audit checks scope, AC, test quality, RED order, architecture, route binding, buildability, protected-file compliance and independently observed source. Verdict: PENDING.

## 8. Pending checklist

- [ ] User execution approval and predecessors ready.
- [ ] Explicit implementation_executor model/effort dispatch; no inheritance.
- [ ] Required operator setup verified without reading protected values.
- [ ] Listed contract implemented with buildable staged consumers.
- [ ] Formal RED observed before GREEN; regression ceiling respected.
- [ ] Final canonical task build recorded.
- [ ] Applicable visual/device/runtime evidence recorded honestly.
- [ ] No protected-content access, external secret transmission or unapproved live action.
- [ ] Independent coordinator audit PASS.
