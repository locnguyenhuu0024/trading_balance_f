# Implementation Plan: Ten-order Cap and Selective Limit Resubmission

Status: COMPLETE
Date: 2026-10-03
Tier: L
Specification: `docs/agents/specs/2026-10-03-strategy-limit-cap-resubmission-design.md`
Decision Ledger: `docs/agents/decisions/2026-10-03-strategy-limit-cap-resubmission-decisions.md`
Execution Authorization: User authorized implementation after presentation on 2026-10-03: execute tasks once planning is complete.

## 1. Objective

Implement REQ-001..009 and AC-001..009 through T62..65. Authoritative cap10 for new admission, preserve confirmed legacy queue20, and explicit fixed-order resubmission of only safe eligible rows with new linked history.

## 2. Preconditions

D-001..004 resolved by user; A-001..002 coordinator decisions under explicit delegation. T61 diagnostics audited and committed e56e991. Baseline before this cycle: no implementation had started. AGENTS.md §6 requires authorization after this plan is presented; previous commit/push authorization does not cover these changes.

## 3. Repository Impact

| Area | Files / symbols | Change |
|---|---|---|
| Backend admission | strategy.py normalization/prepare/both claims; API/queue tests | MODIFY |
| UI admission | strategy domain/selection/wizard/screen/controller; affected tests | MODIFY |
| Retry service | strategy_retry.py and test_strategy_retry.py | ADD |
| Retry integration | strategy/worker/app/diagnostics; affected API/queue/worker/trade/diagnostic tests | MODIFY |
| Retry UI | domain DTOs/API client/controller/screen + strategy_retry_dialog.dart/test | MODIFY/ADD |
| API guide | docs/deployment/position-trade-api.md, explanatory documentation | MODIFY |

Exact path allowlists are in task §4. New files: backend/strategy_retry.py, backend/tests/test_strategy_retry.py, lib/features/strategy/presentation/strategy_retry_dialog.dart, test/features/strategy/strategy_retry_dialog_test.dart. No schema/store, exchange transport, dependency or protected configuration changes. Coordinator may update canonical docs/status/audits/telemetry only.

## 4. External Configuration / Environment Actions

Required actions: NONE. No content access, content diff or mutation of protected files. Native tools consume config opaquely. Production deployment/build publication is not included in this authorization request.

## Planning Workstream Decomposition

| Workstream | Material | Independent | Requested route | Logical run | Completion / adoption |
|---|---|---|---|---|---|
| Backend/API/fixed math/atomic lineage | YES | YES | R3 / gpt-6.1-sol / high | R3-RETRY-BACKEND-01 | COMPLETE / USED; focused contract validation collected |
| Frontend/modal/session/confirmation | YES | YES | R2 / gpt-6.1-sol / medium | R2-RETRY-FRONTEND-01 | COMPLETE / USED |
| Cross-layer synthesis | YES | NO; coordinator-owned | C2 target gpt-6.1-sol/high | MAIN-RETRY-01 | COMPLETE |

Fan-out Required: YES. Required Reasoning Agents: 2. Actual Reasoning Agents: 2. Fan-out Compliance: PASS. Skip Reason: N/A. Both child routes explicitly bound, inheritance forbidden, effective model/effort unavailable and dispatch UNVERIFIABLE. Main runtime route not asserted as observed.

Synthesis: dedicated fixed-order preview instead of ordinary reallocating wizard; source-order IDs and stable semantic revision; fresh client IDs; current preference at prepare; atomic create/claims and permanent direct-source consumption; shared deletion/replacement guards; reject sources with any ordinary replacement child; keep all preflight/reservation blockers; read-only recovery after uncertain writes; separate historical20 and admission10 validators. No open material decisions.

## 5. Dependency Graph

```text
T62/P01 -> T63/P02 --+-> T65/P04 -> final integration
        -> T64/P03 --+
```

T63 and T64 may share a wave after T62 PASS: disjoint frontend/backend product/test files, no generated outputs or shared mutation, no cross-task compilation dependency. Serialize if tool contention or changed evidence makes this unsafe. T65 follows both audited PASS boundaries.

## 6. Ordered Implementation Steps

### P01 — Ten-order Admission Backend (T62)

Objective: Enforce at most ten newly admitted orders while preserving already confirmed historical queues through twenty.
Implements: REQ-001,003,004 / AC-001,003,004.
Dependencies: None; post-plan execution authorization required.
Files/symbols: exact allowed surface and concrete implementation contract in `tasks/task_62_strategy_ten_order_cap_backend.md`; source admission/claims, UI validators, retry routes/lineage or modal/controller respectively.
Required changes: follow that task's numbered executor contract and specification §§6–12; no unresolved decisions are delegated.
Required behavior/preservation: specification INV-001..006; no automatic resend, truncation, financial recalculation of quantity or safety bypass.
RED-001: 11 new single/mixed6+5 levels and oversized unstarted persisted records refuse before placement/claim; attempted records keep markers.
GREEN-001: Exactly10 single/mixed5+5 succeeds in both modes; seeded confirmed20 queue finishes its full tail and global20/pass remains.
Method/expected: focused offline cases, explicit call/state counts, negative tests PASS before positive tests PASS; executor reports exact commands and case names. Stop on contract/scope/protected facts or verification blockers.

### P02 — Ten-order Admission Frontend (T63)

Objective: Apply the combined ten-order selection and confirmation limit without breaking historical twenty-row rendering.
Implements: REQ-002,003,004 / AC-002,003,004.
Dependencies: T62 = PASS.
Files/symbols: exact allowed surface and concrete implementation contract in `tasks/task_63_strategy_ten_order_cap_frontend.md`; source admission/claims, UI validators, retry routes/lineage or modal/controller respectively.
Required changes: follow that task's numbered executor contract and specification §§6–12; no unresolved decisions are delegated.
Required behavior/preservation: specification INV-001..006; no automatic resend, truncation, financial recalculation of quantity or safety bypass.
RED-002: 11th toggle and forged11-order preview/prepared response cannot Save/confirm/execute; oversized unstarted card cannot Apply.
GREEN-002: Mixed10 selection shows correct counter and supports one normal execute; historical20 progress still renders.
Method/expected: focused offline cases, explicit call/state counts, negative tests PASS before positive tests PASS; executor reports exact commands and case names. Stop on contract/scope/protected facts or verification blockers.

### P03 — Selective Limit Resubmission Backend (T64)

Objective: Provide authoritative fixed-order retry review and atomic linked attempts using existing storage and submission machinery.
Implements: REQ-005,006,007,009 / AC-005,006,007,009.
Dependencies: T62 = PASS; may run alongside T63 on disjoint source/test surfaces.
Files/symbols: exact allowed surface and concrete implementation contract in `tasks/task_64_strategy_limit_resubmission_backend.md`; source admission/claims, UI validators, retry routes/lineage or modal/controller respectively.
Required changes: follow that task's numbered executor contract and specification §§6–12; no unresolved decisions are delegated.
Required behavior/preservation: specification INV-001..006; no automatic resend, truncation, financial recalculation of quantity or safety bypass.
RED-003: Accepted/unknown/malformed/active/stale/tampered selections, concurrent overlaps, descendant claim then delete/replacement, ordinary replacement races and safety preflight failures refuse with zero new placements; history is retained.
GREEN-003: Exact eligible mixed or DCA-only subset has correct fixed costs/hash/new IDs and submits once in both modes; idempotent creation produces one child, duplicate execute one attempt; unclaimed child delete releases overlap; rejected child is eligible as a new source; observational polling does not stale-bind.
Method/expected: focused offline cases, explicit call/state counts, negative tests PASS before positive tests PASS; executor reports exact commands and case names. Stop on contract/scope/protected facts or verification blockers.

### P04 — Selective Limit Resubmission Frontend (T65)

Objective: Add an explicit review-and-confirm retry modal backed by authoritative candidates and one linked child execution.
Implements: REQ-008,009 / AC-008,009.
Dependencies: T63 and T64 = PASS.
Files/symbols: exact allowed surface and concrete implementation contract in `tasks/task_65_strategy_limit_resubmission_frontend.md`; source admission/claims, UI validators, retry routes/lineage or modal/controller respectively.
Required changes: follow that task's numbered executor contract and specification §§6–12; no unresolved decisions are delegated.
Required behavior/preservation: specification INV-001..006; no automatic resend, truncation, financial recalculation of quantity or safety bypass.
RED-004: Malformed/oversized/wrong-source/review mismatches, cancel, logout/account switch, double tap and uncertain responses produce zero extra execute writes; excluded rows cannot be selected.
GREEN-004: Mixed eligible<=10 is reviewed exactly and confirmed once; source/new child links and safety blockers render; modal is usable at narrow and desktop widths.
Method/expected: focused offline cases, explicit call/state counts, negative tests PASS before positive tests PASS; executor reports exact commands and case names. Stop on contract/scope/protected facts or verification blockers.

## 7. Test and Verification Plan

| Tests | Proves | Level / scope |
|---|---|---|
| TEST-62 / RED-GREEN001 | cap and legacy tail | focused then strategy API/queue |
| TEST-63 / RED-GREEN002 | selection/ACK cap, history | selection/wizard/controller/screen |
| TEST-64 / RED-GREEN003 | eligibility/fixed math/lineage/idempotency | retry + affected API/queue/worker/diagnostics/trade API |
| TEST-65 / RED-GREEN004 | modal/review/session/one execute | API/retry modal/controller/screen + wizard/settings compatibility |

Formal readiness checkpoint RED then GREEN per task; exact focused commands/cases must be recorded. Diagnostic checks are not formal evidence. Re-run only dependency-invalidated evidence after edits. Task and final integration ceiling V3. Full-suite ownership NOT_REQUIRED: bounded affected paths give contract evidence. Escalate only for observed shared behavior risk/missing AC evidence. No production order tests.

Final integration: inspect exact source/test/doc diffs excluding protected paths; confirm every AC/INV and immutable final executable state; reuse valid task evidence and run both canonical build units after final executable edit:

```sh
PYTHONPYCACHEPREFIX=/private/tmp/strategy-limit-cap-pycache /Users/locnguyen/.local/bin/rtk test /opt/homebrew/bin/python3.12 -m compileall -q backend
/Users/locnguyen/.local/bin/rtk flutter build web --no-pub --release --dart-define=TRADE_API_BASE_URL=https://api.tradingbalancef.com
```

Known environment: WSGI localhost bind may need local sandbox escalation. External user verification required: NO. Toolchain errors are localized without protected config inspection; unresolved evidence BLOCKED, not PASS. RTK-first, narrow raw fallback only for exact evidence/compatibility.

## 8. Migration / Data Plan

No schema migration. New internal subtype metadata in existing JSON only; old records remain intact. Representative seeded fixtures: historical20 applying/unstarted, partial accepted/rejected/unknown, leverage-stopped unsent, permanent consumed lineage, ordinary replacement races. Validate history preservation and exact client IDs. No automatic record repair/truncation. Retry-specific deletion guards retain claim history.

## 9. Performance Verification

No throughput increase intended. Keep global20/pass and existing pacing. Account-narrowed JSON lineage decoding without optional JSON1 or dependency; no network inside transactions. Concurrency tests use deterministic barriers and bounded joins. No arbitrary benchmark threshold or extra production polling.

## 10. Risks

| ID | Risk | Detection / mitigation |
|---|---|---|
| RISK-001 | Duplicate order via uncertain evidence or lost write response | fail-closed eligibility, durable claims, idempotent create, read-only UI recovery |
| RISK-002 | Reallocation changes requested trade | independent fixed-cost fixtures and exact payload/hash assertions |
| RISK-003 | Deleted descendant reopens ancestor | permanent consumption and shared deletion/replacement guards, both race orders |
| RISK-004 | Cap corrupts historical queue | keep envelope20, seeded tail completion and no-reset tests |
| RISK-005 | Account switch executes old review | session checks after every await and shared action lock tests |
| RISK-006 | Retry blocked by current live orders/reservations | preserve existing safety admission, display reason; no bypass |

## 11. Rollout / Rollback

When separately authorized: deploy backend API and worker together before frontend; retry subtype requires both updated. Verify offline tests first, then diagnostics without live automated orders. Stop new retry use on regression. Do not roll old binaries over active retry children; drain/resolve using compatible updated code, then roll back UI/features safely without deleting claimed history. Current plan does not deploy, commit or push.

## 12. Decision/Assumption Dependency Registry

| Item | Used by | Evidence | Invalidated by |
|---|---|---|---|
| D-001 max10 | T62..65 | user selection | changed cap |
| D-002 block old unstarted | T62/T63 | latest explicit reply | new legacy policy |
| D-003 finish confirmed tail | T62/T64 | explicit user decision | new queue policy |
| D-004 trusted retry after review | T64/T65 | latest explicit reply | wider eligibility request |
| A-001 fixed linked attempt/current mode/safety blockers | T64/T65 | user delegated decisions, coordinator synthesis | changed retry semantics |
| A-002 permanent consumption/history protection | T64/T65 | race analysis adopted | lineage design revision |

## 13. Task Decomposition

| Task | Step | Requirements / AC | Depends on | Executor | Allowed write surface |
|---|---|---|---|---|---|
| T62 | P01 | REQ-001,003,004 / AC-001,003,004 | None | E1 / Luna xhigh | `tasks/task_62_strategy_ten_order_cap_backend.md` §4 |
| T63 | P02 | REQ-002,003,004 / AC-002,003,004 | T62 = PASS. | E1 / Luna xhigh | `tasks/task_63_strategy_ten_order_cap_frontend.md` §4 |
| T64 | P03 | REQ-005,006,007,009 / AC-005,006,007,009 | T62 = PASS | E2 / Luna max | `tasks/task_64_strategy_limit_resubmission_backend.md` §4 |
| T65 | P04 | REQ-008,009 / AC-008,009 | T63 and T64 = PASS. | E1 / Luna xhigh | `tasks/task_65_strategy_limit_resubmission_frontend.md` §4 |

All dispatch contracts: agent_role=implementation_executor; exact gpt-6-luna plus effort from table; route_binding_mode=EXPLICIT; parent_route_inheritance=FORBIDDEN. E2 chosen for intricate fixed math/transaction/lineage invariants after decisions are resolved, not merely impact/file count. Coordinator owns independent audit and canonical state.

### Task Buildability Plan

| Task | Required | Unit | Exact command | Boundary |
|---|---|---|---|---|
| T62 | YES | backend | `PYTHONPYCACHEPREFIX=/private/tmp/strategy-limit-cap-pycache /Users/locnguyen/.local/bin/rtk test /opt/homebrew/bin/python3.12 -m compileall -q backend` | self-contained compatible |
| T63 | YES | Flutter web | `/Users/locnguyen/.local/bin/rtk flutter build web --no-pub --release --dart-define=TRADE_API_BASE_URL=https://api.tradingbalancef.com` | self-contained compatible |
| T64 | YES | backend | `PYTHONPYCACHEPREFIX=/private/tmp/strategy-limit-cap-pycache /Users/locnguyen/.local/bin/rtk test /opt/homebrew/bin/python3.12 -m compileall -q backend` | self-contained compatible |
| T65 | YES | Flutter web | `/Users/locnguyen/.local/bin/rtk flutter build web --no-pub --release --dart-define=TRADE_API_BASE_URL=https://api.tradingbalancef.com` | self-contained compatible |

## 14. Completion Gate

- [x] Required planning fan-out collected/reconciled PASS.
- [x] Revised plan presented and post-plan execution authorization recorded.
- [x] All T62..65 audited PASS with RED-before-GREEN and final task build.
- [x] AC-001..009 and preserved INV-001..006 have observable evidence.
- [x] Final executable state has both canonical builds PASS and integration audit PASS.
- [x] Protected configuration boundary maintained; external actions NONE reported.
- [x] Final diff matches approved scope and production limitations reported.

## 15. Change Log

Revision1: combined prior cap plan with resolved legacy decisions and new selective resubmission. Previous Oct2 cap artifacts superseded; no prior execution authorization reused.

Execution progress: T62 PASS, T63 PASS. T64 BLOCKED_ROUTE (agent thread limit rejected explicit Luna/max spawn); task-specific alternate existing Luna/xhigh route decision pending. T65 PENDING on T64. Current backend compile and release web builds PASS; entire combined feature/integration remains incomplete.

Routing recovery 2026-10-03: original E2 Luna/max dispatch retried at user request and accepted. T64 EXECUTING; T65 follows audited T64 PASS. No alternate route was adopted.

Execution progress: T64 independently audited PASS; T65 explicitly dispatched E1 Luna/xhigh, effective route unavailable UNVERIFIABLE. Original route recovery resolved; final integration pending T65.

Final integration: T62..65 independently audited PASS. Coordinator RED15 then GREEN2 for T65, affected frontend81 and backend123+trade49 reused after audit. T64 snapshots unchanged9/9. Final backend compile exit0 and final Flutter release build exit0 after last executable/test edits. Scope/configuration/privacy audit PASS; external actions NONE. Production deployment, commit and push remain outside this cycle. Audit: `docs/agents/audits/2026-10-03-limit-cap-resubmission-integration-audit.md`.
