# Task 113 — Gated Binance USD-M One-way commands

Status: SOURCE PASS — fixture checkpoint complete; PostgreSQL runtime/venue pending; activation locked
Agent Role: implementation_executor
Executor Class: E2
Target Model: gpt-6-luna
Target Effort: max
Target Route: gpt-6-luna / max
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Dispatch Route Status: UNVERIFIABLE
Requested Model / Effort: gpt-6-luna / max (explicit spawn)
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
Predecessors/readiness: T112 source/runtime = PASS for source-only dispatch under D-007; venue acceptance remains pending and blocks feature activation. A-001–010 and INV-001–006 are binding. No product/architecture invention by the executor.
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
- `backend/tests/test_binance_reads.py`

Read only the source/tests/docs needed for the listed contracts. New interfaces stage compatibility with existing consumers; leave the affected canonical unit buildable. Directory surfaces are restricted to the described hand-written source/test roles, not arbitrary settings or generated files.

## 3. Forbidden scope and reuse

All protected environment/runtime/dependency/build/CI/deployment/workspace files: content access and writes forbidden. No root recursive content search without explicit non-protected allowlist. No new dependency installation/manifest edits, source upload, secret retrieval, live account operations, migration of production data, commit/push or deployment. No unrelated feature redesign.
Reuse existing gateway/session fences/security helpers/OKX transport/native controls as applicable. If scope expands or a contract is insufficient, return BLOCKED to coordinator.

Binding implementation details: `docs/agents/validation/2026-10-11-t113-preflight.md`. Read this in full before implementation. Public Binance admission remains locked.

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
Run after the final executable/test change. Result/exit: PASS, exit 0 after last executable edit; coordinator independently repeated. See source audit. Buildable compatibility staging required; no PASS while awaiting a successor repair.
Backend compileall is paired with import/runtime tests; mocks cannot substitute PostgreSQL multi-process checks.

Frontend gate: N/A.

## 7. External actions, stop conditions and audit

External configuration/actions are spec §12 and the setup prerequisite above, all user-owned. No agent reads/creates protected files. Integration needing unapplied inputs is BLOCKED; report exact safe target/key/placeholder and validation step already specified in the spec. Unknown production topology/paths block launch, not synthetic checks.

STOP for missing approval/predecessor/setup, observable route mismatch, missing owner/capability contract, scope expansion, secret-bearing output, unavailable required verification or broken task build. Unknown exchange outcome is retained and reconciled; never resolve it by repeating a write.

Coordinator owns canonical status/audit/telemetry. Writer returns exact safe commands, scenario results, changed path names, build exit, limits and external-action list. Audit checks scope, AC, test quality, RED order, architecture, route binding, buildability, protected-file compliance and independently observed source. Source verdict: PASS; PostgreSQL runtime/venue verdict remains pending. See source audit.

## 8. Pending checklist

- [x] User execution approval and source predecessors ready under D-007.
- [x] Explicit implementation_executor model/effort dispatch; no inheritance.
- [ ] Required operator setup verified without reading protected values.
- [x] Listed source contract implemented with buildable staged consumers.
- [x] Formal RED observed before GREEN; V3 ceiling respected.
- [x] Final canonical backend source build recorded.
- [ ] Applicable visual/device/runtime evidence recorded honestly.
- [x] No protected-content access, external secret transmission or unapproved live action.
- [x] Independent source/fixture coordinator audit PASS under D-007; runtime/venue acceptance pending.

## D-007 execution staging

User explicitly authorized fixture-first codeT113, keeping trading locked until demo verification before feature activation. No real venue request/write, key retrieval or external configuration is authorized. Source preflight has two independent material workstreams, R2 gpt-6.1-sol/medium (native contracts and ledger/API integration); both requested routes were explicitly bound in their original reusable advisor dispatches, effective routes unavailable. Source implementation starts only after coordinator synthesis/Definition of Ready, with E2 gpt-6-luna/max as declared above. No source-only fixture result establishes venue PASS.

## User pause — 2026-10-11

Progress saved; T113 paused before coordinator contract synthesis and executor dispatch. Both independent R2 reports are collected. No T113 executable changes begun. Resume from `docs/agents/checkpoints/2026-10-11-t113-preflight-paused.md`; D-007 remains valid, trading stays locked, venue verification remains pending.

## Resume — 2026-10-11

User requested continuation from checkpoint. Both R2 reports reconciled; fan-out 2/2 PASS. Source Definition of Ready PASS under D-007; native venue/runtime setup is not a fixture prerequisite. Binding source preflight finalized. No activation or Git authorization.

## Baseline evidence — E2-T113-001

Before production-source edits, `/opt/homebrew/bin/python3.12 -m unittest backend.tests.test_binance_commands.BinanceCommandBaselineTests.test_injected_transport_can_send_a_reduce_only_market_order -q` exited 1: missing BinanceTransport.post. Fabricated keys and injected callback only. This is absent-behavior baseline evidence, not the final formal negative RED checkpoint. Implementation remains in progress.

## Early independent audit remediation — R3-T113-AUDIT-001

All findings delegated to the running E2 writer; formal verification not yet complete. AUD-113-001 read-only compatibility; 002 exact filter subtraction; 003 retained live multi-target claim; 004 bounded native decimals; 005 aggregate recovery; 006 live partial fill stays UNKNOWN; 007 strict sanitized malformed evidence; 008 losing execute cannot mutate winner; 009 final-clock confirmation CAS; 010 unknown native error classification; 011 crash between targets recovery; 012 read-only same-UID recovery. Production/API native write lock independently confirmed intact. Coordinator clarified initial invalid ACK must remain UNKNOWN until explicit reconciliation. Final audit PENDING.

## Independent final review / R01

E2-T113-001 reported formal negatives 9 before V3 48 tests/1 PostgreSQL skip, compileall 0. Independent R3 reviewed all six executable paths: AUD-113-001–010 and 012–013 resolved, gates remain closed. SOURCE REWORK for AUD-113-011 recovery re-crash and AUD-113-014 required fixture coverage. R01 delegated to the same explicitly bound E2 writer: expired RECONCILING takeover, full binding negative/positive cases, real-adapter fabricated end-to-end SQLite case. No activation/Git. Before correction, second recovery-crash regression failed with actual RECONCILING vs expected PARTIAL. Final evidence/audit PENDING.

## R02 classifier correction

R01 independent SOURCE PASS collected, then coordinator exact final diff found AUD-113-010 residual: unfamiliar negative code with HTTP4xx still definite via generic rule; prior tests covered HTTP200 only. SOURCE readiness reopened for this branch. R02 independently classified E0 mechanical: only transport classifier and test_binance_commands.py, explicitly bound existing gpt-6-luna/high executor; no concurrent writer. E2 writer interrupted before R02 mutation. Unknown coded HTTP4xx must remain UNKNOWN; known failures and rate-limit mapping retained. Final affected evidence/build/audit PENDING.

## Final source checkpoint — 2026-10-11

`docs/agents/validation/2026-10-11-t113-source-audit.md`: AUD-113-001–014 resolved; final ordered negative2 → positive1; final V3 59 run / 58 passed / 1 PostgreSQL skip; fresh compileall0 and scoped diffcheck0. Trading/API/real transport remain locked. Source PASS only; full runtime/venue acceptance is pending. Operator VPS commands are in the audit. No new configuration/install action or Git writes. No successor task started.
