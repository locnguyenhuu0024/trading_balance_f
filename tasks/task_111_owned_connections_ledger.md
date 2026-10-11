# Task 111 — Owned connections, encrypted credentials and durable commands

Status: BLOCKED_EXTERNAL_VERIFICATION — T119 mapping assertions corrected/audited; PG persisted-state rerun pending
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
- `backend/strategy_automatic.py` — only coupled owner-scope/store/route wiring of existing automatic strategy behavior; no new generation semantics.
- `backend/strategy_scope.py`
- `backend/strategy_queue.py`
- `backend/strategy_worker.py`
- `backend/tests/test_multiuser_ownership.py`
- `backend/tests/test_credential_vault.py`
- `backend/tests/test_command_claims.py`
- `backend/tests/test_trade_api.py`
- `backend/tests/test_strategy_scope.py`
- `backend/tests/test_multiuser_store.py` — only the schema-version expectation affected by the approved additive version 1→2 upgrade; preserve other assertions and runtime gates.

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
Run after the final executable/test change. Result/exit: final `/opt/homebrew/bin/python3.12 -m compileall -q backend` observed exit0 on 2026-10-11 after AUD-111-32 remediation. Buildable compatibility staging required; no PASS while awaiting a successor repair.
Backend compileall is paired with import/runtime tests; mocks cannot substitute PostgreSQL multi-process checks.

Frontend gate: N/A.

## 7. External actions, stop conditions and audit

External configuration/actions are spec §12 and the setup prerequisite above, all user-owned. No agent reads/creates protected files. Integration needing unapplied inputs is BLOCKED; report exact safe target/key/placeholder and validation step already specified in the spec. Unknown production topology/paths block launch, not synthetic checks.

STOP for missing approval/predecessor/setup, observable route mismatch, missing owner/capability contract, scope expansion, secret-bearing output, unavailable required verification or broken task build. Unknown exchange outcome is retained and reconciled; never resolve it by repeating a write.

Coordinator owns canonical status/audit/telemetry. Writer returns exact safe commands, scenario results, changed path names, build exit, limits and external-action list. Audit checks scope, AC, test quality, RED order, architecture, route binding, buildability, protected-file compliance and independently observed source. Verdict: PENDING.

## 8. Pending checklist

- [x] User execution approval and predecessors ready.
- [x] Explicit implementation_executor model/effort dispatch; no inheritance.
- [ ] Required operator setup verified without reading protected values.
- [x] Listed source contract implemented with buildable staged consumers; real runtime proof pending.
- [x] Formal RED observed before GREEN; regression ceiling respected.
- [x] Final canonical task build recorded.
- [ ] Applicable visual/device/runtime evidence recorded honestly.
- [x] No protected-content access, external secret transmission or unapproved live action.
- [x] Independent source audit PASS; full task verdict remains BLOCKED until required runtime evidence.

## Predecessor readiness — 2026-10-10

T110 coordinator PASS after user-provided Ubuntu real AES/PostgreSQL evidence and 69-test focused V3 with no skips. Existing source-first authorization remains applicable: no dependency install on Mac or agent VPS access; T111 runtime evidence must be obtained separately after its implementation. Executor has not been dispatched for T111 at this checkpoint.

## Source dispatch — 2026-10-10

User explicitly requested continuation after T110 PASS. E2 implementation executor dispatched with gpt-6-luna/max, explicit role/model/effort, fork none and no parent inheritance. Effective route unavailable. Source-first authorization retained: no packages installed on Mac, no agent access to VPS/config/secrets/live exchanges. Local fake-cipher/SQLite checks cannot establish real AES/PostgreSQL T111 behavior. Independent R3 source/concurrency audit and separate operator runtime evidence required before full PASS. No close/release primitive available for collected terminal children; no existing writer is running.

## Supported-region implementation mapping

D-006 resolves the existing supported-code boundary: explicit `region=global` maps only to the current `www.okx.com` transport. Reject all other regions/hostname inputs before upstream calls. No regional eligibility inference or `backend/okx.py` write is authorized. Demo requests must carry the documented simulation marker through an allowed scoped transport wrapper; never silently route them as live.

## Affected test-contract amendment

The additive T111 schema upgrade advances version 1→2; the existing T110 store assertion at `backend/tests/test_multiuser_store.py:127` is a compile/test-coupled consumer. Permit only updating that expected schema version to 2. Keep all identity, composite-owner, idempotency and PostgreSQL race assertions unchanged. Add actual upgrade/preserved-row behavior coverage in T111-owned tests. This is a required affected-test alignment within approved additive schema behavior, not a new product feature or weakening of tests.

## Coupled automatic-strategy consumer

R3 inspection confirms `StrategyService.dispatch` calls `AutomaticStrategyService` first, and `backend/strategy_automatic.py` directly reads/writes legacy strategy rows. Preserve approved existing OKX strategy behavior by permitting only necessary owned table/row predicates, scoped store and route wiring in this helper. Existing strategy-generation/sizing/risk semantics stay unchanged; no arbitrary SQL text rewrite or cloned algorithm. This closes a required affected-caller surface of P02, not a new strategy capability.

## Pause checkpoint

User requested saving progress and pausing. Writer interrupted, no active writer remains. Source/tests preserved locally; formal final verification/audit and owner strategy/worker integration incomplete. Resume from `docs/agents/validation/2026-10-10-t111-resume-checkpoint.md`. Do not claim T111 PASS, dispatch successors or deploy this checkpoint.

## Resume — 2026-10-10

User explicitly requested continuing from the saved checkpoint. Existing interrupted E2 implementation executor resumed with its original explicit gpt-6-luna/max binding and same bounded task contract; no duplicate writer. Prior checkpoint remains historical evidence. Complete strategy/worker integration and current-source verification/audit remain required; no install, VPS, deployment or Git action is authorized by resumption.

## Related regression remediation — 2026-10-11

Stable-snapshot V3 related tests found AUD-111-30 (T110 auth fixture initialization rejects the newly required connection vault) and AUD-111-31 (legacy batch-marker refusal returns HTTP500). Permit `backend/tests/test_multiuser_auth.py` only for the required fabricated connection-vault fixture alignment; retain all security assertions and real AES gate. Existing production missing-vault rejection must remain fail closed. Permit `backend/tests/test_strategy_api.py` only for a necessary changed private marker signature alignment, retaining refusal/no-network/persisted-state assertions. These are coupled callers of the approved changes, not new product semantics or weaker coverage. Reuse the existing explicitly bound E2 executor for remediation. Coordinator cannot modify executable behavior.

## Source completion checkpoint — 2026-10-11

AUD-111-01–32 reconciled (14 withdrawn); independent R3 source audit PASS and coordinator source/verification synthesis accepted. AUD32 final worker/scope regression46 tests OK/skipped1; prior unaffected related198 and core107 checkpoints remain valid only for their unchanged paths. Final coordinator ordered safety6 then intended-success5 tests all pass, exit0, followed by backend compileall exit0. Exact evidence is in the audit. No full task PASS: six T111 AES/PG cases and four affected T110 runtime cases must pass with no skips on the operator VPS. Runbook: `docs/agents/runbooks/2026-10-11-t111-vps-verification.md`; existing T110 dedicated test setup is reused, with no additional installation. No successor, commit/push, feature activation or deployment is authorized by this source checkpoint.
