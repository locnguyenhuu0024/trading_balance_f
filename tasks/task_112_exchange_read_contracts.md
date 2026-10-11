# Task 112 — Normalized OKX and Binance read adapters

Status: BLOCKED_EXTERNAL_VERIFICATION — source audit PASS; operator runtime and venue evidence pending
Agent Role: implementation_executor
Executor Class: E1
Target Model: gpt-6-luna
Target Effort: xhigh
Target Route: gpt-6-luna / xhigh
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Dispatch Route Status: UNVERIFIABLE
Requested Model / Effort: gpt-6-luna / xhigh (explicit spawn request)
Observed Effective Model / Effort: unavailable
Specification: `docs/agents/specs/2026-10-10-multi-user-okx-binance-design.md`
Plan: `docs/agents/plans/2026-10-10-multi-user-okx-binance.md`
Plan Steps: P03
Requirements: REQ-003, REQ-006
Acceptance Criteria: AC-003
Frontend Level: N/A
Frontend Design Brief: N/A
Visual Review Required: NO

## 1. Objective and preconditions

Implement P03 exactly as defined in the canonical plan. Done when the referenced behavioral contracts, relevant regression, final task build and independent audit pass.
Predecessors/readiness: T111 = PASS. A-001–010 and INV-001–006 are binding. No product/architecture invention by the executor.
Runtime/setup: No new dependency beyond predecessors. Demo read integration requires separately authorized operator-provisioned credentials; mock PASS is not venue PASS.
Provisioning/installation is operator-owned and is not part of the executor write scope.

## 2. Allowed write surface

- `backend/exchanges/__init__.py`
- `backend/exchanges/contracts.py`
- `backend/exchanges/okx_adapter.py`
- `backend/exchanges/binance_transport.py`
- `backend/exchanges/binance_spot.py`
- `backend/exchanges/binance_usdm.py`
- `backend/okx.py`
- `backend/data_gateway.py`
- `backend/service.py`
- `backend/strategy.py`
- `backend/account_context.py`
- `backend/connections.py`
- `backend/credential_vault.py`
- `backend/tests/test_exchange_contracts.py`
- `backend/tests/test_binance_reads.py`
- `backend/tests/test_data_gateway.py`
- `backend/tests/test_positions_read_pressure.py`
- `backend/tests/test_multiuser_ownership.py`
- `backend/tests/test_credential_vault.py`
- `backend/tests/test_exchange_read_routes.py`

Read only the source/tests/docs needed for the listed contracts. New interfaces stage compatibility with existing consumers; leave the affected canonical unit buildable. Directory surfaces are restricted to the described hand-written source/test roles, not arbitrary settings or generated files.

## 3. Forbidden scope and reuse

All protected environment/runtime/dependency/build/CI/deployment/workspace files: content access and writes forbidden. No root recursive content search without explicit non-protected allowlist. No new dependency installation/manifest edits, source upload, secret retrieval, live account operations, migration of production data, commit/push or deployment. No unrelated feature redesign.
Reuse existing gateway/session fences/security helpers/OKX transport/native controls as applicable. If scope expands or a contract is insufficient, return BLOCKED to coordinator.

## 4. Executor contract

1. Introduce adapter contract/decimal-string DTOs/native units and preserve existing OKX behavior through a wrapper.
2. Implement signed Binance standard Spot/USD-M read calls, authoritative account identity and supported metadata; allowlisted regional/live/demo routing.
3. Normalize balances/positions/orders/freshness/capabilities; absent/unsupported never becomes zero or tradable.
4. Separate exchange/product/instrument public keys from isolated private keys; implement scoped stable cursor pagination.
5. Replace per-row synchronous strategy list reconciliation with persisted projection and bounded explicit refresh queue hook.

Binding preflight: `docs/agents/validation/2026-10-11-t112-preflight.md` defines authoritative identity, demo gates, DTOs, exact routes/limits/pagination and request-bound read-only refresh. Legacy v1 list behavior is preserved. Two independent R2 workstreams collected; fan-out PASS.

Follow P03; preserve the single backend boundary, owner filtering, decimal units, server-proven lifecycle and bounded resources. Expected unsafe-path behavior is defined by spec §8, not implementation convenience.

## 5. Tests and formal RED → GREEN

Behavioral pairs: RED/GREEN-003.
RED scenario and independently expected result: BTC in OKX spot/SWAP and Binance spot/USD-M must not share price/metadata/private scope. Wrong step, malformed metadata, unknown account identity or unsupported product fails closed without write.
GREEN scenario and independently expected result: Independent 0.01 BTC contract ×3 and 0.03 BTC base fixtures produce exposure 0.03 with distinct native quantities; own normalized OKX/Binance reads and pagination preserve values and scope.

Method: `python3.12 -m unittest backend.tests.test_exchange_contracts backend.tests.test_binance_reads backend.tests.test_data_gateway backend.tests.test_positions_read_pressure -q`; name/select focused negative then success cases explicitly and record order, setup, outcome and exit. Proposed suites do not exist yet; these are implementation deliverables, not currently passing tests. Add a failing-baseline regression where new behavior is absent. Use only fabricated keys/account payloads.

Inner-loop diagnostics are narrow/non-authoritative. At readiness run formal RED before GREEN, then relevant regression and final build. Later edits rerun affected evidence only; restart pair if shared verification basis changes.
Verification ceiling: V3 (focused related tests). Full V4 belongs to T116 final integration only, justified by global auth/storage/DTO changes.
Escalation trigger: shared consumers changed, related regression failure, or task proof lacks required concurrency/runtime evidence; document reason before widening.

## 6. Task buildability and frontend evidence

Required: YES
Canonical build unit: backend Python package
Exact secret-free build command: `python3.12 -m compileall -q backend`
Run after the final executable/test change. Result/exit: PASS / 0; executor and fresh coordinator compile observed. Buildable compatibility staging required; no PASS while awaiting a successor repair.
Backend compileall is paired with import/runtime tests; mocks cannot substitute PostgreSQL multi-process checks.

Frontend gate: N/A.

## 7. External actions, stop conditions and audit

External configuration/actions are spec §12 and the setup prerequisite above, all user-owned. No agent reads/creates protected files. Integration needing unapplied inputs is BLOCKED; report exact safe target/key/placeholder and validation step already specified in the spec. Unknown production topology/paths block launch, not synthetic checks.

STOP for missing approval/predecessor/setup, observable route mismatch, missing owner/capability contract, scope expansion, secret-bearing output, unavailable required verification or broken task build. Unknown exchange outcome is retained and reconciled; never resolve it by repeating a write.

Coordinator owns canonical status/audit/telemetry. Writer returns exact safe commands, scenario results, changed path names, build exit, limits and external-action list. Audit checks scope, AC, test quality, RED order, architecture, route binding, buildability, protected-file compliance and independently observed source. Verdict: SOURCE_PASS; full task BLOCKED pending the external evidence below.

## 8. Pending checklist

- [x] User execution approval and predecessors ready.
- [x] Explicit implementation_executor model/effort dispatch; no inheritance.
- [x] Required operator setup verified without reading protected values.
- [x] Listed contract implemented with buildable staged consumers.
- [x] Formal RED observed before GREEN; regression ceiling respected.
- [x] Final canonical task build recorded.
- [ ] Applicable visual/device/runtime evidence recorded honestly.
- [x] No protected-content access, external secret transmission or unapproved live action.
- [x] Independent coordinator audit PASS.

## Final source checkpoint — 2026-10-11

Independent audit SOURCE PASS, AUD-112-001–030 and residuals resolved. Ordered negative32/2skips before intended-success22/3skips; related119/5skips; additional existing strategy-list/scope/trade-API consumers92/1skip. Counts include skips. Both relevant V3 sets exited0; canonical backend compileall and scoped diff-check exited0 after final executable changes. Exact formal selectors: `docs/agents/validation/2026-10-11-t112-checkpoint-commands.md`; full reconciliation: `docs/agents/validation/2026-10-11-t112-read-adapters-audit.md`.

Full task remains BLOCKED_EXTERNAL_VERIFICATION: new real AES Binance envelope and dedicated PostgreSQL consumer checks must run on the existing operator test runtime without skips. Venue acceptance remains separately authorized and unverified; demo activation stays fail-closed. Process-local snapshots/refresh do not establish T115 deployment-wide coordination. T113/T114 predecessor gate remains closed. Operator commands: `docs/agents/runbooks/2026-10-11-t112-vps-verification.md`. No new dependencies/configuration, live calls, installation, deployment, commit or push performed.
