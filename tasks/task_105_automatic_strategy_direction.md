# Task 105 — Automatic strategy direction backend

Status: PASS
Agent Role: implementation_executor
Executor Class: E1
Target Model: gpt-6-luna
Target Effort: xhigh
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Dispatch Route Status: UNVERIFIABLE
Requested Model: gpt-6-luna
Requested Effort: xhigh
Observed Effective Model/Effort: unavailable
Plan: docs/agents/plans/2026-10-09-forms-loading-direction.md
Specification: docs/agents/specs/2026-10-09-forms-loading-direction-design.md
Plan Steps: P01
Requirements/Acceptance: REQ-003 / AC-003
Predecessors: none

## Contract and scope

Implement additive optional automatic direction long/short/both, omission=both. Follow spec interface/invariants exactly. Allowed writes: backend/strategy_automatic.py; backend/tests/test_strategy_automatic.py; test_strategy_api.py, test_strategy_queue.py, test_strategy_worker.py or test_strategy_scope.py only for actual-side proof. No operational config, dependencies, worker product rewrite or live services. Keep legacy missing direction flexible; malformed explicit direction fails closed. Scope filter before assessment; persist and hash direction; both replay paths compare it; materialization validates allowed-side scope. No trading from generation.

## Verification

RED-105 then GREEN-105 as defined in spec. Include invalid/null before provider, requestId direction conflict, transactional duplicate path and opposite-side tamper. GREEN proves long/short filtering, persisted/reopened/replay scope, legacy/explicit both compatibility and side-specific batch/sequential execution with 100% one-side budget. Stubs only. V3 ceiling relevant automatic/API/queue/worker/retry/scope tests. Task buildability required: python3.12 -m compileall -q backend after final executable edit.

## Stop and report

Return BLOCKED if protected change, unknown semantic or out-of-scope dependency required. Do not mutate docs/tasks/telemetry, create agents, commit or push. RTK first eligible output; raw exact narrow fallback. Report exact RED-before-GREEN commands/results, tests/build, paths, config actions none or precise requirement, and route telemetry envelope. Coordinator owns audit/status.

## Coordinator evidence and verdict

Audit: PASS. Reviewed complete non-protected diff for all three changed backend files and scope/execution callers. Formal RED: five boundary tests passed before six GREEN cases passed. Relevant V3: 184 tests passed. Build: python3.12 -m compileall -q backend, exit0 after final edits. Source tests prove actual preview sidePercent/totalMargin and matching order/leverage writes, not input-only expectations. Explicit route requested, effective route unavailable, no inheritance. No protected paths changed; no external actions. Detailed commands: docs/agents/validation/2026-10-09-forms-loading-direction-audit.md.
