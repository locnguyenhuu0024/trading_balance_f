# Task 113 — Gated Binance USD-M One-way commands

Status: PENDING — execution authorized; waiting for predecessor PASS
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
Plan Steps: P04
Requirements: REQ-003, REQ-004
Acceptance Criteria: AC-003, AC-004
Frontend Level: N/A
Frontend Design Brief: N/A
Visual Review Required: NO

## 1. Objective and preconditions

Implement P04 exactly as defined in the canonical plan. Done when the referenced behavioral contracts, relevant regression, final task build and independent audit pass.
Predecessors/readiness: T112 = PASS. A-001–010 and INV-001–006 are binding. No product/architecture invention by the executor.
Runtime/setup: Operator-authorized Binance demo endpoints/credentials/permissions only for venue gate. No live trades; demo success is not live-performance evidence.
Provisioning/installation is operator-owned and is not part of the executor write scope.

## 2. Allowed write surface

- `backend/exchanges/binance_usdm.py`
- `backend/exchanges/binance_transport.py`
- `backend/exchanges/contracts.py`
- `backend/command_ledger.py`
- `backend/service.py`
- `backend/account_context.py`
- `backend/tests/test_binance_commands.py`
- `backend/tests/test_command_claims.py`
- `backend/tests/test_exchange_contracts.py`

Read only the source/tests/docs needed for the listed contracts. New interfaces stage compatibility with existing consumers; leave the affected canonical unit buildable. Directory surfaces are restricted to the described hand-written source/test roles, not arbitrary settings or generated files.

## 3. Forbidden scope and reuse

All protected environment/runtime/dependency/build/CI/deployment/workspace files: content access and writes forbidden. No root recursive content search without explicit non-protected allowlist. No new dependency installation/manifest edits, source upload, secret retrieval, live account operations, migration of production data, commit/push or deployment. No unrelated feature redesign.
Reuse existing gateway/session fences/security helpers/OKX transport/native controls as applicable. If scope expands or a contract is insufficient, return BLOCKED to coordinator.

## 4. Executor contract

1. Add One-way regular-order close/reduce/cancel intents using actual filters and fresh account/position/mode preflight.
2. Map command to native symbol/side/quantity/client ID; preserve close-all per-target scope and final proof.
3. Classify definite failure versus unknown 503/timeout; use ledger and lookup reconciliation before any retry.
4. Reject Hedge/conditional algo/Portfolio Margin/Spot writes/strategy execution before send; do not auto-change position mode/leverage.
5. Record safe per-target partial/canceled/filled/unknown outcomes and capability version; keep real-money switch disabled until launch approval.

Follow P04; preserve the single backend boundary, owner filtering, decimal units, server-proven lifecycle and bounded resources. Expected unsafe-path behavior is defined by spec §8, not implementation convenience.

## 5. Tests and formal RED → GREEN

Behavioral pairs: RED/GREEN-003 and 004.
RED scenario and independently expected result: Hedge or algo capability, revoked permission or expired prepare yields no write; accepted request followed by lost response/restart yields UNKNOWN and lookup, no duplicate placement. Cancel racing fill preserves exposure.
GREEN scenario and independently expected result: One-way demo/mock close and cancellation use correct native units and exactly one durable command attempt; terminal outcome is independently proven from exchange lookup.

Method: `python3.12 -m unittest backend.tests.test_binance_commands backend.tests.test_command_claims backend.tests.test_exchange_contracts -q`; name/select focused negative then success cases explicitly and record order, setup, outcome and exit. Proposed suites do not exist yet; these are implementation deliverables, not currently passing tests. Add a failing-baseline regression where new behavior is absent. Use only fabricated keys/account payloads.

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
