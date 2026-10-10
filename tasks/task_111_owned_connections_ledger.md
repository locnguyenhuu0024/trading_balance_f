# Task 111 — Owned connections, encrypted credentials and durable commands

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
Plan Steps: P02
Requirements: REQ-002, REQ-004
Acceptance Criteria: AC-002, AC-004
Frontend Level: N/A
Frontend Design Brief: N/A
Visual Review Required: NO

## 1. Objective and preconditions

Implement P02 exactly as defined in the canonical plan. Done when the referenced behavioral contracts, relevant regression, final task build and independent audit pass.
Predecessors/readiness: T110 = PASS. A-001–010 and INV-001–006 are binding. No product/architecture invention by the executor.
Runtime/setup: Spec §12 vetted encryption dependency, vault key/key IDs, remote-identity key, session key and isolated PostgreSQL are required. Use fabricated credentials only.
Provisioning/installation is operator-owned and is not part of the executor write scope.

## 2. Allowed write surface

- `backend/connections.py`
- `backend/credential_vault.py`
- `backend/account_context.py`
- `backend/command_ledger.py`
- `backend/schema_multiuser.py`
- `backend/postgres_store.py`
- `backend/service.py`
- `backend/app.py`
- `backend/data_gateway.py`
- `backend/strategy.py`
- `backend/strategy_scope.py`
- `backend/strategy_queue.py`
- `backend/strategy_worker.py`
- `backend/tests/test_multiuser_ownership.py`
- `backend/tests/test_credential_vault.py`
- `backend/tests/test_command_claims.py`
- `backend/tests/test_trade_api.py`
- `backend/tests/test_strategy_scope.py`

Read only the source/tests/docs needed for the listed contracts. New interfaces stage compatibility with existing consumers; leave the affected canonical unit buildable. Directory surfaces are restricted to the described hand-written source/test roles, not arbitrary settings or generated files.

## 3. Forbidden scope and reuse

All protected environment/runtime/dependency/build/CI/deployment/workspace files: content access and writes forbidden. No root recursive content search without explicit non-protected allowlist. No new dependency installation/manifest edits, source upload, secret retrieval, live account operations, migration of production data, commit/push or deployment. No unrelated feature redesign.
Reuse existing gateway/session fences/security helpers/OKX transport/native controls as applicable. If scope expands or a contract is insufficient, return BLOCKED to coordinator.

## 4. Executor contract

1. Verify remote connection identity, encrypt typed credentials with AEAD/AAD and separate keys, enforce one canonical remote account owner including revoked tombstones.
2. Apply owner-first connection/operation/strategy/result/preference/reservation/conflict queries; v2 cannot fall back to singleton v1.
3. Bind prepare to owner/connection/product/versions/expiry; implement CAS command lease/fence and durable pre-send marker.
4. Make polling respect active execution leases; unresolved sent intent blocks replacement writer, permission rotation/revoke stops unsent tail.
5. Guard web cookie mutations by Origin/CSRF; native bearer remains scoped; add safe connection lifecycle routes.
6. Reserve canonical remote identity through revoked tombstones/REVOKING/UNKNOWN; same-owner relink retains connection_id and all unresolved barriers. No ownership transfer or fresh UUID bypass. Key-digest rotation preserves mapping uniqueness.

Follow P02; preserve the single backend boundary, owner filtering, decimal units, server-proven lifecycle and bounded resources. Expected unsafe-path behavior is defined by spec §8, not implementation convenience.

## 5. Tests and formal RED → GREEN

Behavioral pairs: RED/GREEN-002 and 004.
RED scenario and independently expected result: B guesses A's IDs/results/cursors and same symbol exists in both accounts: B gets uniform 404, no A upstream call. Concurrent execute/result and crash-after-send create one send marker and never blind retry; vault AAD tamper fails closed.
GREEN scenario and independently expected result: A securely connects/uses two owned OKX contexts, independent conflicts are correct, one supported confirmed command submits once and reconciles its owner-bound outcome.
Additional RED: revoke after an unknown send, relink the same remote account and try a new command → blocked until original uncertainty is resolved. A different owner cannot claim that remote identity. GREEN: controlled same-owner reactivation preserves the stable ID and allows a new operation only after reconciliation; restricted recovery sessions cannot rotate credentials or enable trading.

Method: `python3.12 -m unittest backend.tests.test_multiuser_ownership backend.tests.test_credential_vault backend.tests.test_command_claims backend.tests.test_trade_api backend.tests.test_strategy_scope -q`; name/select focused negative then success cases explicitly and record order, setup, outcome and exit. Proposed suites do not exist yet; these are implementation deliverables, not currently passing tests. Add a failing-baseline regression where new behavior is absent. Use only fabricated keys/account payloads.

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
