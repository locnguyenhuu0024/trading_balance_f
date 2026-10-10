# Task 116 — Offline migration, recovery and measured release evidence

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
Plan Steps: P07
Requirements: REQ-006, REQ-007
Acceptance Criteria: AC-006, AC-007; integration AC-001–005
Frontend Level: F0 performance validation only
Frontend Design Brief: docs/agents/specs/2026-10-10-multi-user-okx-binance-frontend-brief.md
Visual Review Required: integration evidence from T114 required

## 1. Objective and preconditions

Implement P07 exactly as defined in the canonical plan. Done when the referenced behavioral contracts, relevant regression, final task build and independent audit pass.
Predecessors/readiness: T113, T114, T115 = PASS. A-001–010 and INV-001–006 are binding. No product/architecture invention by the executor.
Runtime/setup: Isolated test DB, restore fixture/key and reference profile hardware. Actual production config/runbook targets require operator-provided safe facts; live cutover remains separately authorized.
Provisioning/installation is operator-owned and is not part of the executor write scope.

## 2. Allowed write surface

- `backend/migrate_multiuser.py`
- `backend/benchmarks/multiuser_load.py`
- `backend/tests/test_multiuser_migration.py`
- `backend/tests/test_multiuser_load.py`
- `test/multiuser/performance_test.dart`
- `docs/deployment/multiuser-okx-binance.md`

Read only the source/tests/docs needed for the listed contracts. New interfaces stage compatibility with existing consumers; leave the affected canonical unit buildable. Directory surfaces are restricted to the described hand-written source/test roles, not arbitrary settings or generated files.

## 3. Forbidden scope and reuse

All protected environment/runtime/dependency/build/CI/deployment/workspace files: content access and writes forbidden. No root recursive content search without explicit non-protected allowlist. No new dependency installation/manifest edits, source upload, secret retrieval, live account operations, migration of production data, commit/push or deployment. No unrelated feature redesign.
Reuse existing gateway/session fences/security helpers/OKX transport/native controls as applicable. If scope expands or a contract is insufficient, return BLOCKED to coordinator.

## 4. Executor contract

1. Implement offline explicit ownership-mapping dry run/import using safe test DB, preserve IDs/decimal values/unknown markers; quarantine ambiguity and invalidate old sessions/prepares.
2. Import code has no exchange mutation capability; freeze/drain/reconcile prerequisite, no implicit auto-resume or dual writer.
3. Verify counts/relations/statuses/attempt markers and vault restore with fabricated fixtures; rehearse rollback before/after new writes.
4. Run spec §11 baseline/new synthetic load and UI profile; record environment and achieved p50/p95/p99/resources/fairness/weights, no performance claim without evidence.
5. Write operator rollout/rollback/kill-switch runbook from safe supplied runtime facts; missing actual target paths block deployment section.
6. Return local integration evidence for independent final audit; no production SQL, deploy, commit or push.

Follow P07; preserve the single backend boundary, owner filtering, decimal units, server-proven lifecycle and bounded resources. Expected unsafe-path behavior is defined by spec §8, not implementation convenience.

## 5. Tests and formal RED → GREEN

Behavioral pairs: RED/GREEN-007 then 006.
RED scenario and independently expected result: Unmapped rows, orphan replacements, unresolved legacy attempt and old-backup rollback after new writes are rejected/quarantined; no order placement from import. 500-user burst stays bounded.
GREEN scenario and independently expected result: Explicit mapped fixture preserves counts/ownership/native IDs/decimals/results; staged recovery proves no lost ledger; admitted reference load and UI targets pass with full evidence.

Method: `python3.12 -m unittest backend.tests.test_multiuser_migration backend.tests.test_multiuser_load -q`; name/select focused negative then success cases explicitly and record order, setup, outcome and exit. Proposed suites do not exist yet; these are implementation deliverables, not currently passing tests. Add a failing-baseline regression where new behavior is absent. Use only fabricated keys/account payloads.

Inner-loop diagnostics are narrow/non-authoritative. At readiness run formal RED before GREEN, then relevant regression and final build. Later edits rerun affected evidence only; restart pair if shared verification basis changes.
Verification ceiling: V3 (focused related tests). Full V4 belongs to T116 final integration only, justified by global auth/storage/DTO changes.
Escalation trigger: shared consumers changed, related regression failure, or task proof lacks required concurrency/runtime evidence; document reason before widening.

## 6. Task buildability and frontend evidence

Required: YES
Canonical build unit: backend package and Flutter application
Exact secret-free build command: `python3.12 -m compileall -q backend; then flutter build web --no-pub (separate commands)`
Run after the final executable/test change. Result/exit: PENDING. Buildable compatibility staging required; no PASS while awaiting a successor repair.
Backend compileall is paired with import/runtime tests; mocks cannot substitute PostgreSQL multi-process checks.

Integration consumes T114 rendered/a11y evidence and records actual UI profile; no visual redesign. Missing device/performance evidence prevents the corresponding launch gate from PASS.

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
