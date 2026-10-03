# Implementation Plan: Strategy Limit Order Queue

Status: COMPLETED
Date: 2026-10-02
Tier: L
Specification: `docs/agents/specs/2026-10-02-strategy-limit-order-queue-design.md`
Decision Ledger: `docs/agents/decisions/2026-10-02-strategy-limit-order-queue-decisions.md`

## 1. Objective and preconditions

Implements REQ-001 through REQ-008; acceptance AC-001 through AC-007. D-001 and A-001 through A-006 resolve material semantics under the user's authority to decide. Execution requires approval after presentation under AGENTS.md section 6. Starting worktree was clean on `feature/position-strategy`; no production batch failure was reproduced.

Main coordinator workload C2: hard restart/fencing reasoning, low orchestration complexity. Runtime fixes the parent route; no claimed parent model/effort selection. A focused explicitly bound R3 child supplied backend reasoning.

## 2. Planning workstream decomposition

| Workstream | Material | Independent | Requested route | Logical agent run | Completion / adoption |
|---|---|---|---|---|---|
| Backend/API/data/worker/exchange safety | YES | YES | R3 / gpt-6.1-sol / high | LQ-BE-PLAN | COMPLETE / USED |
| Frontend/modal/session/progress | YES | YES | R2 / gpt-6.1-sol / medium | LQ-FE-PLAN | COMPLETE / USED |

Fan-out Required: YES
Required Reasoning Agents: 2
Actual Reasoning Agents: 2
Fan-out Compliance: PASS
Skip Reason: N/A
Both dispatches: explicit model + effort, parent inheritance forbidden, effective model/effort unavailable, route status UNVERIFIABLE.

Coordinator synthesis: use `/v1/strategies/settings`, preference field `limitOrderSubmissionMode`, snapshot field `submissionMode`, existing top-level statuses, and queueStatus `pending/sending/stopped/submitted`. Retain placement provenance for honest progress as exchange fill status changes. Use existing row order and a bounded JSON queue ledger. Block invalid prepared modes in the new client; legacy backend-prepared records still execute batch and new backend reports their mode explicitly.

## 3. Repository impact and write surfaces

| Task | Allowed implementation/test/doc files | Change |
|---|---|---|
| T59 | `backend/store.py`, `backend/strategy.py`, `backend/strategy_worker.py`, new `backend/strategy_queue.py`, `backend/okx.py` if required for single ACK preservation, `backend/tests/test_strategy_api.py`, `backend/tests/test_strategy_worker.py`, new `backend/tests/test_strategy_queue.py`, `docs/deployment/position-trade-api.md` | Add preferences/queue persistence and worker delivery, generalize attempt safety, compatibility and rollout docs. |
| T60 | `lib/features/strategy/data/strategy_api_client.dart`, `lib/features/strategy/domain/strategy_models.dart`, `lib/features/strategy/presentation/providers/strategy_dashboard_provider.dart`, `lib/features/strategy/presentation/strategy_screen.dart`, `lib/features/strategy/presentation/strategy_wizard_dialog.dart`, new `lib/features/strategy/presentation/strategy_settings_dialog.dart`, `test/features/strategy/strategy_api_client_test.dart`, `test/features/strategy/strategy_dashboard_controller_test.dart`, `test/features/strategy/strategy_screen_test.dart`, `test/features/strategy/strategy_wizard_dialog_test.dart`, new `test/features/strategy/strategy_settings_dialog_test.dart` | API preference transport, session-safe modal, frozen confirmation and queue visibility. |

All protected config/env/build/deployment files, dependency manifests, credentials, generated source, and unrelated product files are excluded from content access and writes. Canonical planning/checklist/audit/telemetry docs are coordinator-owned. No new external configuration action is required. Builds may consume existing configuration as opaque input only.

## 4. Dependency graph and handoff review

```text
P01 preference/snapshot + P02 durable queue/worker + P03 compatibility = T59
T59 PASS -> P04 settings/confirmation/progress = T60
T60 PASS -> coordinator integration audit
```

Wave 1: one E2 backend executor; Wave 2: one E1 frontend executor. Keep backend persistence, queue, and monitor compatibility together because they share attempt/recovery invariants. Frontend can fail independently and consumes the finalized server contract; it follows T59 rather than relying on unfinished API assumptions. Two tasks fit the Tier L handoff target and remain separately buildable. No concurrent writer/cache/runtime conflict is planned.

## 5. Ordered implementation steps

### P01 — Persist account preference and frozen mode

T59 implements REQ-002/003 and AC-001/002. Add preference storage and authenticated settings dispatch before the strategy-ID matcher. Validate enum before write. Add additive strategy fields with batch defaults for old rows. Freeze new preference in prepared data; execute uses only that snapshot, and settings changes cannot alter prepared attempts. Old prepared records without mode retain batch. Expose canonical fields in prepared/list/result DTOs, with null frozen mode for unprepared drafts.

### P02 — Durable sequential queue with fenced delivery

T59 implements REQ-004/005/006 and AC-003/004/005. Encapsulate the queue ledger/state transitions in `backend/strategy_queue.py`. Sequential claim/enqueue/confirmation consumption/reservation are atomic; API returns durable APPLYING without placing orders. Worker obtains current fingerprint and lease, paces external calls, applies initial full preflight/leverage/re-preflight, and drains at most 20 rows per pass. Persist each write marker before network, and outcome/cursor atomically after a validated ACK. Enforce the 120-second deadline and >=250ms placement spacing. Restart only untouched tail after committed ACKs and fresh resume validation. Stop conservatively on in-flight markers, rejects, uncertainty, expired deadlines, or stale safety inputs. Never retry a stopped tail.

### P03 — Integrate monitor, replacement and legacy safety

T59 implements REQ-007 and AC-006. Keep batchAttempted semantics and add generalized placement evidence. Update every deletion/replacement/reservation/recovery branch to use it when relevant. Active queues bypass interrupted-batch recovery/monitor aggregation. Reconcile only attempted rows after delivery ends; preserve placement provenance and stopped-tail PARTIAL aggregation. Keep fresh-zero-position completion. Add coordinated API/worker rollout guidance because the worker now sends sequential orders.

### P04 — Modal and honest queue experience

T60 implements REQ-001/003/008 and AC-001/002/007. Add authenticated settings API methods and bearer-scoped lifecycle-guarded preference state. Add AppBar Settings and the responsive expandable modal with first mechanism item, explicit Save/Cancel, signed-out explanation, load/save failures, and backend persistence. Both final confirmation paths display server-frozen mode and block invalid/missing modes. Guard disposal/session identity after awaits. Display queue progress and rows during APPLYING, distinguish queued success from unknown response, and keep polling read-only. Update all StrategyApi fakes within the allowed test files.

## 6. Verification plan

No live exchange writes; use fake OKX responses, fake clocks, temporary application databases, and widget/API harnesses. Expected outcomes are specified independently in the design's section 8.

| Test | Proves | Level / command |
|---|---|---|
| TEST-BE-01 | RED-BE timeout/no resend; GREEN-BE exact sequential delivery | V1: focused `backend.tests.test_strategy_queue.StrategyQueueTests` scenario methods recorded in T59 |
| TEST-BE-02 | Settings isolation/freezing/migration, reject/crash/fence/deadline/resume, legacy replacement/recovery/completion | V3: `rtk test python3 -m unittest backend.tests.test_strategy_queue backend.tests.test_strategy_api backend.tests.test_strategy_worker backend.tests.test_trade_api` |
| TEST-FE-01 | RED-FE session/disposal and failure safety | V1: focused named tests recorded in T60 |
| TEST-FE-02 | GREEN-FE modal/transport/confirmations/progress and relevant regressions | V3: `rtk flutter test --no-pub test/features/strategy/strategy_settings_dialog_test.dart test/features/strategy/strategy_api_client_test.dart test/features/strategy/strategy_dashboard_controller_test.dart test/features/strategy/strategy_screen_test.dart test/features/strategy/strategy_wizard_dialog_test.dart --reporter compact` |

Each executor uses narrow diagnostic checks until ready, then formal RED before GREEN. Record exact named methods/commands and observed results. Later changes invalidate only affected scenarios or shared fixtures. V3 is the ceiling because persistence/recovery and provider interfaces touch related strategy tests; V4 only if an observed regression escapes that boundary.

### Task buildability

| Task | Canonical unit | Required command after final task-local change | Boundary |
|---|---|---|---|
| T59 | Python backend package | `python3 -m compileall -q backend` plus the related backend test group above | Self-contained additive backend interface, legacy batch retained. |
| T60 | Flutter web application | `rtk flutter build web --no-pub --release --dart-define=TRADE_API_BASE_URL=https://api.tradingbalancef.com` | All StrategyApi consumers/fakes and UI compiled together. |

T60 also runs `rtk flutter analyze lib/features/strategy` on affected source. Existing known Wasm/Cupertino warnings are not failure evidence. Build artifacts are verification output; deployment is not included in this plan. Do not broaden tests without a concrete unresolved risk.

## 7. Risks and rollout

| Risk | Mitigation / evidence |
|---|---|
| Process crash or lease transfer around HTTP | Durable marker, singleton fencing, no retry of uncertain attempted rows; negative fault-injection tests. |
| Queue resumes against its own pending orders | Initial and resume validation differ explicitly; hash/mode/account/deadline still checked. |
| Old worker misclassifies new queue | Coordinated API/worker replacement before sequential enqueue; migration/regression tests. |
| Client reports ACK as fill or leaks settings across sessions | Placement provenance, frozen mode, guarded awaits, widget/controller tests. |
| Batch reported issue has another cause | Preserve exact payload and surface bounded per-order error codes; no unverified claim of root-cause repair. |

Rollout/rollback follows design section 9. No external configuration edits are needed. Production deployment and real orders require separately explicit user instructions.

## 8. Task decomposition and completion checklist

| Task | Steps | Requirements / AC | Dependency | Explicit executor route |
|---|---|---|---|---|
| T59 | P01-P03 | REQ-002 through 007 / AC-001 through 006 server side | None | implementation_executor, E2, gpt-6-luna / max |
| T60 | P04 | REQ-001/003/008 / AC-001/002/007 client side | T59 PASS | implementation_executor, E1, gpt-6-luna / xhigh |

Both routes require explicit model/effort binding, parent inheritance FORBIDDEN, and UNVERIFIABLE only when effective route is unexposed.

- [x] Required planning fan-out collected and reconciled.
- [x] Material decisions and user-authorized assumptions recorded.
- [x] Current plan presented and post-presentation execution approval received.
- [x] T59 PASS with RED then GREEN and backend buildability.
- [x] T60 PASS with RED then GREEN and web buildability.
- [x] Acceptance trace and final integration audit PASS.
- [x] Final name-only status and allowed-source diffs contain no unexplained/protected changes.
- [x] No protected configuration content accessed or modified; external configuration action reported as none.

Trace: REQ-002/003 -> AC-001/002 -> P01 -> T59; REQ-004/005/006 -> AC-003/004/005 -> P02 -> T59; REQ-007 -> AC-006 -> P03 -> T59; REQ-001/003/008 -> AC-001/002/007 -> P04 -> T60. Audit verdicts and RED/GREEN evidence remain pending execution.

## Completion

T59 and T60 PASS. Final integration audit: `docs/agents/audits/2026-10-02-strategy-limit-order-queue-integration.md`.132 backend and56 frontend related tests passed; ordered RED/GREEN, info-only scoped analysis and fresh final backend/web builds passed. No config action, live trade, Git mutation or deployment.
