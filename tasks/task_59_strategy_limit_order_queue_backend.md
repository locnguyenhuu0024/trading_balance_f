# Task 59 — Strategy Limit Order Queue Backend

Status: PASS
Agent Role: implementation_executor
Executor Class: E2
Target Model: gpt-6-luna
Target Effort: max
Target Route: gpt-6-luna / max
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Specification: `docs/agents/specs/2026-10-02-strategy-limit-order-queue-design.md`
Plan: `docs/agents/plans/2026-10-02-strategy-limit-order-queue.md`
Plan Steps: P01-P03
Requirements: REQ-002 through REQ-007
Acceptance Criteria: AC-001 through AC-006 (server portions)

## Dispatch and preconditions

Execution approval after plan presentation is required; no predecessor. Explicit E2 model+effort binding is mandatory. Dispatch Route Status: UNVERIFIABLE. Requested Model/Effort: gpt-6-luna / max. Effective Model/Effort: unavailable until exposed by runtime. Do not inherit a parent/default route or accept a mismatched route.

## Objective and allowed surface

Implement durable sequential submission with authenticated account preferences, frozen mode, compatibility-safe worker processing, and no duplicate ambiguous writes.

Allowed product/test/doc writes:
- `backend/store.py`
- `backend/strategy.py`
- `backend/strategy_worker.py`
- new `backend/strategy_queue.py`
- `backend/okx.py` only if needed to retain single-order per-order ACK data safely
- `backend/tests/test_strategy_api.py`
- `backend/tests/test_strategy_worker.py`
- new `backend/tests/test_strategy_queue.py`
- `docs/deployment/position-trade-api.md`

Planning/checklist/telemetry/audit files are coordinator-owned. No protected configuration read/write, dependencies, unrelated refactor, live account requests, deployment, or Git mutation. Stop if the listed surface is insufficient.

## Executor contract

1. P01: add account preference storage and GET/POST settings dispatch; reject invalid enum before write, default sequential; migrate strategy mode/attempt/queue fields additively with legacy batch defaults.
2. Bind new preparation to preference snapshot. Report submissionMode explicitly; execute token-only. Preserve old prepared entries missing mode as batch. Drafts not prepared have null mode.
3. P02: implement a bounded queue JSON ledger with cursor, deadline, in-flight marker, and phase. Atomically enqueue together with single-use execution claim/reservation. API enqueues only; worker sends.
4. Initial delivery validates full current preflight and hash/mode, applies and persists side leverage results, then repeats full preflight. Lease-aware exchange-call hooks/wrappers must fence every preflight read as well as writes; worker provides valid fingerprint checks required by StrategyService.
5. Persist each write marker before network, then validate and atomically persist its ACK/cursor under the same current fence. Reuse exact `_okx_order` payloads; retain row order and client IDs. Minimum250ms placement spacing and maximum20 placements per worker pass. No network transaction.
6. Enforce deadline enqueue+120s before external writes. Resume a committed accepted prefix only with no in-flight marker, unchanged mode/account, fresh preview hash equality, and valid deadline; omit initial no-position/no-pending/full-budget guards after own ACK prefix. Skip successful leverage writes on restart.
7. Reject/timeout/malformed ACK/interrupted marker/stale safety/deadline permanently stops untouched tail. Unknown attempts remain unknown and are never repeated. Subsequent result reads or reconciliation cannot restart a stopped tail. Known per-order rejection exposes bounded errorCode.
8. P03: retain batchAttempted meaning and generalize orderPlacementAttempted across reservations/deletion/replacement/reconciliation. Active queue bypasses batch recovery and API monitor; no lookup for intentionally unsent rows. Reconcile accepted/unknown rows after queue end. Keep historical placementState acceptance and queue progress as fill status evolves. Preserve fresh-zero-position completion and old batch behavior.
9. DTO: preference `limitOrderSubmissionMode`; frozen `submissionMode`; `orderPlacementAttempted`; `queueStatus` null or pending/sending/stopped/submitted; `queueProgress` totalCount/attemptedCount/acceptedCount/pendingCount/notSubmittedCount. Sequential rows use status queued/sending or existing exchange outcomes plus placementState provenance; unsent stopped tail status not_submitted. All counters are nonnegative bounded integers.
10. Document coordinated API+worker rollout and writer role. No env or Docker configuration changes.
11. Grounded compatibility correction: the actual OKX set-leverage success has top-level code0 and data fields instId/mgnMode/posSide/lever, without per-item sCode. Validate the reviewed payload against this success shape in queue and legacy batch paths; retain explicit bounded rejection handling and conservative malformed-response stopping. This preserves valid batch operation without changing its payload or submission mechanism.

Required invariants: INV-001 through INV-007. Do not invent a retry/resume policy, amend prices/sizes, or change top-level strategy statuses. A settings preference is application data under explicit user request, not permission to edit operational config files.

## Tests and formal evidence

Add `StrategyQueueTests` in the new test module with stable methods:
- `test_red_timeout_stops_tail_without_resend`: 3-row fixture, timeout row2; only2 placements, remaining unsent, replay/restart/reconciliation do not resend.
- `test_green_exact_fifo_single_order_submission`: 3 success ACKs; exactly3 reviewed FIFO single requests, no batch, >=250ms spacing via fake clock/sleep, durable APPLIED/submitted.

Additional cases: preference isolation/invalid modes/snapshot freeze, atomic duplicate execute, legacy prepared batch, additive migration, explicit rejection, malformed identity ACK, lost fence, crash before HTTP after marker, crash after committed ACK, deadline and stale resume validation, own pending orders on valid resume, lease renewal per preflight read, leverage ambiguity, attempted-only reads, replacement/delete/reservation safety, fill completion and legacy worker tests. Use fake exchange, clocks, and temporary DBs; no live placement.

Formal RED command: `rtk test python3 -m unittest backend.tests.test_strategy_queue.StrategyQueueTests.test_red_timeout_stops_tail_without_resend`

Expected RED: scenario assertions pass with exactly2 placements and no duplicate write after fault recovery.

Formal GREEN command after RED: `rtk test python3 -m unittest backend.tests.test_strategy_queue.StrategyQueueTests.test_green_exact_fifo_single_order_submission`

Expected GREEN: exact3 sequential reviewed placements, successful persisted outcomes, no batch call.

Relevant regression ceiling V3: `rtk test python3 -m unittest backend.tests.test_strategy_queue backend.tests.test_strategy_api backend.tests.test_strategy_worker backend.tests.test_trade_api`.

Task Buildability Gate: required YES; affected canonical unit Python backend package; after last local executable change run `python3 -m compileall -q backend`, then the related regression group. Result and exit: PENDING. Diagnostics are narrow until ready; formal RED precedes GREEN. Later edits invalidate only affected evidence. Escalate beyond V3 only for an observed shared regression not covered above.

## Configuration, stop conditions and report

External Configuration / Environment Actions: none. Runtime additive application DB migrations are in scope; operational config remains user-owned. Production verification is not attempted locally; report live exchange behavior unverified.

Return BLOCKED on unresolved architecture, required out-of-scope files/config, conflicting repository evidence, route mismatch, or unavailable verification. Do not self-escalate the executor route. Return paths, compact results, exact formal RED/GREEN/build commands/statuses, safe rollout notes, and telemetry envelope LQ-E2-T59. Do not modify this task or telemetry files.

## Coordinator checklist / audit

- [x] Approval received; explicit route compliance checked.
- [x] Allowed-source diff matches P01-P03 and AC-001 through AC-006.
- [x] RED observed before GREEN.
- [x] Regression and canonical backend buildability PASS.
- [x] Compatibility/restart/fencing invariants audited against source.
- [x] No protected content access or writes.
- [x] Verdict: PASS.

## Final observed evidence

Final RED then GREEN: `PYTHONDONTWRITEBYTECODE=1 rtk test /opt/homebrew/bin/python3.12 -m unittest backend.tests.test_strategy_queue.StrategyQueueTests.test_red_timeout_stops_tail_without_resend` then corresponding `test_green_exact_fifo_single_order_submission`; each1 test PASS. Build: `PYTHONPYCACHEPREFIX=/private/tmp/t59-pycache-312 rtk test /opt/homebrew/bin/python3.12 -m compileall -q backend` PASS, exit0 after final executable change. V3: `PYTHONDONTWRITEBYTECODE=1 rtk test /opt/homebrew/bin/python3.12 -m unittest backend.tests.test_strategy_queue backend.tests.test_strategy_api backend.tests.test_strategy_worker backend.tests.test_trade_api` PASS132 tests/38.135s, exit0, with authorized loopback escalation. System Python lacks scrypt; working interpreter3.12. Scoped diff-check PASS. Audit: `docs/agents/audits/2026-10-02-strategy-limit-order-queue-t59.md`. No external configuration actions. Live exchange unverified.
