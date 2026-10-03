# Implementation Plan: Strategy lifecycle and PnL
Status: COMPLETE
Date: 2026-10-03
Tier: L
Specification: `docs/agents/specs/2026-10-03-strategy-lifecycle-pnl.md`
Decision Ledger: docs/agents/decisions/2026-10-03-strategy-lifecycle-pnl-decisions.md
Approval: user preauthorized execution after planning; no open decisions.
Coordinator: C2 reasoning-heavy; runtime main route fixed, effective metadata unavailable; no route claim.

## Planning Workstream Decomposition
| Workstream | Material | Independent | Route | Logical run | Adoption |
|---|---|---|---|---|---|
| Frontend/UI and PnL | YES | YES | R2 gpt-6.1-sol medium, existing explicit binding | R2-UI-002 | COMPLETE / USED |
| Backend lifecycle eligibility | YES | YES | R2 gpt-6.1-sol medium, existing explicit binding | R2-API-002 | COMPLETE / USED |
Fan-out Required: YES
Required Reasoning Agents: 2
Actual Reasoning Agents: 2
Fan-out Compliance: PASS
Effective child routes: unavailable; UNVERIFIABLE. No inheritance.
Synthesis: separate deletion/replacement eligibility; canceled display does not mutate persistence; authoritative server deletion checks; dedicated PnL colors.

## Ordered steps / tasks
P01 / T71: Implement REQ-003/005 backend contracts and regression tests in backend/strategy.py and backend/tests/test_strategy_api.py. E2 gpt-6-luna max: fresh identity verification plus optimistic transaction guards have interacting invariants.
P02 / T72: Implement REQ-001/002/004/005 Flutter UI/colors/compatibility/tests. E1 gpt-6-luna xhigh: bounded existing widgets and shared resolver.
P03: Coordinator independent audit, final source diffs and build evidence; any executable remediation delegated.
P01 and P02 independent, disjoint write surfaces, separate Python/Flutter runtime; run parallel when executor routing permits.

## Verification/buildability
T71: formal focused negative deletion cases before success cases, full backend.tests.test_strategy_api plus relevant queue/worker/retry regressions only as changed dependency warrants. Ceiling V3. Canonical backend build PYTHONPYCACHEPREFIX=/private/tmp/strategy-lifecycle-pycache python3 -m compileall -q backend.
T72: formal gray/hidden/replace guard tests before sign/status/deletion success. Affected theme/PnL/strategy/orders/portfolio widget tests; ceiling V3. Canonical Flutter build /Users/locnguyen/development/flutter/bin/flutter build web --no-pub. No pub/get or generators permitted.
Final builds reuse successful post-last-change task builds if independent files did not invalidate evidence. Full suite NOT_REQUIRED; live trading/exchange writes not required/authorized.

## Risks and rollback
Risk: deletion eligibility could hide active work or expand replacement. Mitigation: explicit separate predicates, failed read and concurrency tests, no exchange writes. PnL privacy sign leak: hidden values muted tests. Opaque configuration unchanged. Code rollback cannot restore deleted local records.
Allowed Write Surfaces are exact in T71/T72. No config/manifest/lockfile/runtime secret writes, dependencies, opportunistic refactors, commit/push/deploy.
Configuration actions: none. Schema migration: none. Performance: no additional dashboard order reads beyond existing scan; terminal delete fresh checks.

## Integration ledger
- [x] mandatory frontend/backend fan-out collected and reconciled
- [x] canonical spec/plan approved under user authorization
- [x] T71 audited PASS
- [x] T72 audited PASS
- [x] final builds PASS and no unexpected changed paths
- [x] final acceptance verdict PASS

## Interim audit remediation
T73 E1 gpt-6-luna/xhigh planned only after T71 terminal. Disjoint T72 results remain valid. AUD-001 strict raw positions, AUD-002 sequential-only unsent exception, AUD-003 strict single raw order row. No concurrent backend writers.

## User pause checkpoint
Execution stopped at explicit user request. See `docs/agents/plans/2026-10-03-strategy-lifecycle-pnl-progress.md`. T72 execution36 affected tests/webbuild passed, audit pending. T71 REWORK; T73 dispatched then interrupted, unverified. No final PASS claim.

Resume 2026-10-03: user requested all remaining implementation via executor sub-agent. Fresh native E1 gpt-6-luna/xhigh explicitly dispatched; prior children absent from runtime listing; effective route unavailable UNVERIFIABLE. No duplicate writer.

T74 E0 gpt-6-luna/high frontend remediation: AUD-004 require complete sequential queue evidence, AUD-005 remove leftover intro gap; strategy source/test only. Independent of backend T73, run parallel. Final frontend build/tests must refresh after T74.

## Final closure
COMPLETE / PASS. T71-T74 accepted; all five findings resolved. Backend API76+related44 PASS/compileall exit0; refreshed strategy19 PASS/webbuild exit0; unchanged T72 PnL evidence reused. Final audit: `docs/agents/plans/2026-10-03-strategy-lifecycle-pnl-audit.md`. Earlier pause/resume entries are historical, superseded. No pending external actions, commit/push or deployment.
