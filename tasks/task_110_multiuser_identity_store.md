# Task 110 — Multi-user identity and store

Status: BLOCKED_EXTERNAL_VERIFICATION — source implemented/audited; real AES/PostgreSQL verification pending
Agent Role: implementation_executor
Executor Class: E2
Target Model: gpt-6-luna
Target Effort: max
Target Route: gpt-6-luna / max
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Dispatch Route Status: UNVERIFIABLE
Requested Model / Effort: gpt-6-luna / max
Observed Effective Model / Effort: unavailable
Specification: `docs/agents/specs/2026-10-10-multi-user-okx-binance-design.md`
Plan: `docs/agents/plans/2026-10-10-multi-user-okx-binance.md`
Plan Steps: P01
Requirements: REQ-001, REQ-002
Acceptance Criteria: AC-001
Frontend Level: N/A
Frontend Design Brief: N/A
Visual Review Required: NO

## 1. Objective and preconditions

Implement P01 exactly as defined in the canonical plan. Done when the referenced behavioral contracts, relevant regression, final task build and independent audit pass.
Predecessors/readiness: none; revision 1 approval and operator-provisioned dependencies/test DB. A-001–010 and INV-001–006 are binding. No product/architecture invention by the executor.
Runtime/setup: Spec §12 dependency installation, PostgreSQL schema/test input and vault runtime inputs; PostgreSQL integration cannot PASS without the dedicated test DB.
Provisioning/installation is operator-owned and is not part of the executor write scope.

## 2. Allowed write surface

- `backend/auth.py`
- `backend/principal.py`
- `backend/store_contract.py`
- `backend/postgres_store.py`
- `backend/schema_multiuser.py`
- `backend/security.py`
- `backend/store.py`
- `backend/service.py`
- `backend/app.py`
- `backend/tests/test_multiuser_auth.py`
- `backend/tests/test_multiuser_store.py`
- `backend/tests/test_trade_api.py`

Read only the source/tests/docs needed for the listed contracts. New interfaces stage compatibility with existing consumers; leave the affected canonical unit buildable. Directory surfaces are restricted to the described hand-written source/test roles, not arbitrary settings or generated files.

## 3. Forbidden scope and reuse

All protected environment/runtime/dependency/build/CI/deployment/workspace files: content access and writes forbidden. No root recursive content search without explicit non-protected allowlist. No new dependency installation/manifest edits, source upload, secret retrieval, live account operations, migration of production data, commit/push or deployment. No unrelated feature redesign.
Reuse existing gateway/session fences/security helpers/OKX transport/native controls as applicable. If scope expands or a contract is insufficient, return BLOCKED to coordinator.

## 4. Executor contract

1. Introduce immutable principal and required owner scope; additive storage interface retains isolated legacy tests.
2. Create relational users/MFA/recovery/invites/sessions and owner-capable child schema; enforce composite relations/indexes.
3. Implement v2 login/enrollment/logout/step-up, per-user counter CAS and single-use recovery; read-only session validation with debounced last-seen.
4. Reuse existing scrypt/password policy and TOTP; isolate bounded expensive login work from trading runtime.
5. Recovery requires username+password+single-use code; revoke prior sessions atomically and issue reenrollment-only authority. No private exchange reads, trades, connection changes or step-up until TOTP recovery completes and a fresh ordinary login succeeds.

Follow P01; preserve the single backend boundary, owner filtering, decimal units, server-proven lifecycle and bounded resources. Expected unsafe-path behavior is defined by spec §8, not implementation convenience.

## 5. Tests and formal RED → GREEN

Behavioral pairs: RED/GREEN-001.
RED scenario and independently expected result: Replay one user TOTP/recovery code concurrently and attempt login with another user's counter/session. Exactly one recovery consumption; no shared replay state or private payload from invalid session.
Additional recovery RED: missing/wrong password plus valid recovery code fails without consuming authority; replayed code fails; restricted recovery session is denied sensitive/private routes. GREEN: password+code atomically revokes previous sessions, reenrolls TOTP, then fresh ordinary login succeeds.
GREEN scenario and independently expected result: Activate two separate invites, enroll independent MFA, sign in both, validate correct immutable principals, revoke one without affecting the other.

Method: `python3.12 -m unittest backend.tests.test_multiuser_auth backend.tests.test_multiuser_store backend.tests.test_trade_api -q`; name/select focused negative then success cases explicitly and record order, setup, outcome and exit. Proposed suites do not exist yet; these are implementation deliverables, not currently passing tests. Add a failing-baseline regression where new behavior is absent. Use only fabricated keys/account payloads.

Inner-loop diagnostics are narrow/non-authoritative. At readiness run formal RED before GREEN, then relevant regression and final build. Later edits rerun affected evidence only; restart pair if shared verification basis changes.
Verification ceiling: V3 (focused related tests). Full V4 belongs to T116 final integration only, justified by global auth/storage/DTO changes.
Escalation trigger: shared consumers changed, related regression failure, or task proof lacks required concurrency/runtime evidence; document reason before widening.

## 6. Task buildability and frontend evidence

Required: YES
Canonical build unit: backend Python package
Exact secret-free build command: `python3.12 -m compileall -q backend`
Run after the final executable/test change. Result/exit: PASS, exit 0 after final T117 executable changes (coordinator observed). Buildable compatibility staging required; no PASS while awaiting a successor repair.
Backend compileall is paired with import/runtime tests; mocks cannot substitute PostgreSQL multi-process checks.

Frontend gate: N/A.

## 7. External actions, stop conditions and audit

External configuration/actions are spec §12 and the setup prerequisite above, all user-owned. No agent reads/creates protected files. Integration needing unapplied inputs is BLOCKED; report exact safe target/key/placeholder and validation step already specified in the spec. Unknown production topology/paths block launch, not synthetic checks.

STOP for missing approval/predecessor/setup, observable route mismatch, missing owner/capability contract, scope expansion, secret-bearing output, unavailable required verification or broken task build. Unknown exchange outcome is retained and reconciled; never resolve it by repeating a write.

Coordinator owns canonical status/audit/telemetry. Writer returns exact safe commands, scenario results, changed path names, build exit, limits and external-action list. Audit checks scope, AC, test quality, RED order, architecture, route binding, buildability, protected-file compliance and independently observed source. Verdict: source audit PASS; full task BLOCKED_EXTERNAL_VERIFICATION for four real-runtime checks.

## 8. Pending checklist

- [x] User execution approval and predecessors ready.
- [x] Explicit implementation_executor model/effort dispatch; no inheritance.
- [ ] Required operator setup verified without reading protected values.
- [x] Listed contract implemented with buildable staged consumers.
- [x] Formal RED observed before GREEN; regression ceiling respected.
- [x] Final canonical task build recorded.
- [x] Applicable visual/device/runtime evidence recorded honestly.
- [x] No protected-content access, external secret transmission or unapproved live action.
- [ ] Independent coordinator audit PASS.

## Execution preflight — 2026-10-10

Revision 1 execution authorized by the user. Python 3.12.13 exists; psycopg and cryptography are not importable in that runtime. PostgreSQL test DB/vault readiness is unconfirmed. Required setup prevents Definition of Ready; no executor dispatched. RED/GREEN, build and audit: NOT_RUN. Preflight evidence and user-owned setup are in `docs/agents/validation/2026-10-10-multiuser-execution-preflight.md`.

## Source-first authorization — 2026-10-10

User explicitly requested implementing tasks first and providing VPS Ubuntu installation commands afterward. This overrides the setup-before-source-dispatch restriction for source-only implementation and synthetic/local tests; production semantics, required PostgreSQL/AES-GCM integration evidence, predecessor PASS gates and protected-file boundaries remain. Missing dependencies may be represented only by injected fabricated test doubles in local tests; never use substitute cryptography at runtime or claim PostgreSQL evidence from SQLite. T110 remains BLOCKED_EXTERNAL_VERIFICATION for unavailable runtime checks after source completion. No dependency installation is authorized on the Mac.

## Final source checkpoint — 2026-10-10

T110 source plus bounded T117 remediation completed. Independent R3 source audit PASS; full T110 PASS withheld. Final auth/store suite: 19 tests, 15 executed passes, four skips; coordinator reproduced this result. Earlier related legacy V3: 68 total, 64 passes, four skips; evidence reused for unchanged legacy paths. Final compileall exit 0 observed independently. Real AES-GCM and three dedicated PostgreSQL multi-process tests are pending. Operator commands: `docs/agents/runbooks/2026-10-10-ubuntu-24-04-multiuser-setup.md`. T111–T116 remain pending predecessor PASS. No local installation, VPS execution, commit, push or deployment.
