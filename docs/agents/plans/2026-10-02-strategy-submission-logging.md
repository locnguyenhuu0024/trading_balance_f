# Implementation Plan: Strategy Submission Diagnostics

Status: COMPLETED
Date: 2026-10-02
Tier: M
Specification: `docs/agents/specs/2026-10-02-strategy-submission-logging-design.md`
Decision Ledger: N/A

## 1. Objective and preconditions

Implement REQ-001..005 / AC-001..004 in one coherent backend task. Working tree was clean at inspection. T59/T60 code is present. No live failure has been reproduced; user forgot the screenshot. Diagnostics can proceed without production evidence, but no root-cause claim is authorized.

Coordinator route classification C1: standard reasoning, low orchestration; target `gpt-6.1-sol / medium`. Main runtime route selection/effective effort unavailable; retain current coordinator without inference.

## 2. Planning workstreams

| Workstream | Material | Independent | Explicit route | Logical run | Result/adoption |
|---|---|---|---|---|---|
| Backend submission and worker evidence | YES | YES | R2 / gpt-6.1-sol / medium | R2-LOG-BACKEND-01 | COMPLETE / USED |
| Diagnostic safety and sink isolation | YES | YES | R2 / gpt-6.1-sol / medium | R2-LOG-SAFETY-01 | COMPLETE / USED |
| Frontend | NO | N/A | N/A | N/A | No UI change |

Fan-out Required: YES
Required Reasoning Agents: 2
Actual Reasoning Agents: 2
Fan-out Compliance: PASS
Skip Reason: N/A
Both children explicitly bound model/effort, role reasoning, inheritance forbidden; effective routes unavailable / UNVERIFIABLE. Coordinator synthesis chooses hashed refs and a bounded nonblocking sink instead of raw IDs or synchronous output. New counts remain read-only and do not imply a deployment diagnosis.

## 3. Repository impact / DAG

`P01 safe emitter -> P02 instrumentation -> P03 offline verification/documentation -> coordinator audit`

One writer T61 (E1) owns these coupled steps; separating them would duplicate the same safety/state-parity tests. No parallel writer wave.

Allowed files: new `backend/diagnostics.py`, new `backend/tests/test_strategy_diagnostics.py`; existing `backend/app.py`, `backend/okx.py`, `backend/strategy.py`, `backend/strategy_worker.py`, `backend/strategy_queue.py`, `backend/tests/test_strategy_api.py`, `backend/tests/test_strategy_queue.py`, `backend/tests/test_strategy_worker.py`, `backend/tests/test_trade_api.py`, `docs/deployment/position-trade-api.md` (explanatory Markdown only).

All protected operational configuration, manifests, env, Docker files/scripts, dependencies, frontend, store/schema and unrelated source are excluded. Canonical planning/status/telemetry are coordinator-owned.

## 4. Steps

- P01: Implement spec §3 schema, hashed refs, thread-local/context-local scope, process-aware bounded nonblocking sink, dropped counts and test capture support. No uncontrolled text and no enqueue/sink exception propagation.
- P02: Instrument WSGI prepare/execute failures before dispatch, preparation and durable enqueue, batch stages, worker startup/heartbeat/selection, queue preflight/writes/commits/stops, and fixed OKX endpoints. Add only optional safe error metadata. Emit after transactions; distinguish ACK observation from persistence. Preserve all existing trading invariants.
- P03: Add offline privacy, concurrency, stalled/failing/full sink, stage, code, shape, heartbeat and call/state parity tests. Document safe Docker log collection for both containers and hashed-reference matching. No runtime deployment or live trade.

Stop for missing semantics, protected configuration dependency, necessary trading change or required write outside this surface.

## 5. Verification plan

Formal checkpoint after final source: RED-001 before GREEN-001 via new focused unittest cases. Diagnostic inner loop uses only failing/focused cases. V3 ceiling: new diagnostics plus strategy queue/API/worker and trade API affected groups; shared OKX/WSGI and worker code justify these regressions. No frontend tests or web rebuild needed. Full repo suite NOT_REQUIRED.

Use `/opt/homebrew/bin/python3.12`, `PYTHONDONTWRITEBYTECODE=1`, RTK-first. Loopback WSGI tests may require sandbox escalation; configuration remains opaque. Build backend after final change:

```sh
PYTHONPYCACHEPREFIX=/private/tmp/strategy-diagnostics-pycache /Users/locnguyen/.local/bin/rtk test /opt/homebrew/bin/python3.12 -m compileall -q backend
```

Reuse valid unaffected evidence; rerun only scenarios invalidated by remediation. Independently audit privacy and state/call parity; final fresh affected build. Product failure is unverified, not a reason for retries/live trading.

## 6. External actions, risks and rollout

Required protected configuration/environment actions: NONE. No changes to external services/log retention. Logging is best effort; a full/blocked sink loses evidence, and absent events never prove no exchange write. Hash refs are diagnostic correlation, not authentication. Container logs remain local/operator controlled.

Rollout: operator updates matching API/worker image through existing process after implementation. Rollback: preserve existing durable queue and unresolved-marker rules. No deployment, commit or push authorization is inferred from this task.

## 7. Task and completion checklist

| Task | Steps / trace | Dependency | Route | Build unit |
|---|---|---|---|---|
| T61 | P01..03 / REQ-001..005 / AC-001..004 | None | E1 / gpt-6-luna / xhigh | backend compileall above |

- [x] Required planning fan-out collected and reconciled.
- [x] Explicit execution approval after plan presentation.
- [x] T61 diagnostics and docs implemented.
- [x] Formal RED then GREEN observed.
- [x] Relevant V3 regression and task buildability PASS.
- [x] Coordinator scope/privacy/invariant/final integration audit PASS.
- [x] No protected configuration access or mutation; limitations reported.

Final integration: T61 PASS; audit-02 PASS;146 affected tests and final backend/Flutter release web builds exit0. No live production diagnosis/deployment or commit/push performed.
