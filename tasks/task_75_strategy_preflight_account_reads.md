# Task 75 — Strategy preflight account reads, 429 and balance failures
Status: PASS
Agent Role: implementation_executor
Executor Class: E1
Target Model: gpt-6-luna
Target Effort: xhigh
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Dispatch Route Status: UNVERIFIABLE
Observed Effective Model/Effort: unavailable
Specification: docs/agents/specs/2026-10-03-strategy-preflight-account-reads.md
Plan: docs/agents/plans/2026-10-03-strategy-preflight-account-reads.md
Requirements: REQ-001..003; acceptance AC-001..005; predecessors none.

## Contract and checklist
- [x] P01: Explicit local account snapshot propagation ordinary/retry prepare and nested preview/preflight, fresh defaults outside a phase.
- [x] P01: Map covered HTTP 429 read failures to safe exchange_rate_limited with Retry-After: 2; diagnostics reason/code retained; non-429 fallbacks unchanged.
- [x] P01: Shared strict unique finite USDT availBal validation; unavailable distinguished from true insufficiency; required margin+fees preserved.
- [x] RED: negative/failure scenarios first, no exchange writes.
- [x] GREEN: one-read prepare/retry success, exact boundary and per-request freshness.
- [x] Affected tests, backend build, coordinator independent audit and final builds.

Allowed source/tests exactly as plan. No configuration/environment/manifests/lockfiles contents or writes; no dependencies, unrelated refactors, external services, Git mutation or telemetry writes. Executor does not change checklist statuses; coordinator owns them. Return bounded report with commands/status, changed files, remaining issues and telemetry envelope (logical E1-T75, requested route, effective unavailable, no runtime IDs). RED/GREEN expected outcomes from spec, formal negative checkpoint before success. Tests V3 ceiling as plan; task build compileall after last mutation. No external configuration actions.

REQ-004/AC-006: Verify existing ACK-gated durable sequential queue and >=250 ms pacing; no next order after rejection/unknown, no POST retries. backend/strategy_worker.py allowed solely for exchange_rate_limited diagnostic classification; backend/tests/test_strategy_queue.py allowed only for required regression tests if existing coverage insufficient. No preference or batch migration changes.

AUD-001 / bounded scope extension before implementation: backend/okx.py account_balance currently silently filters non-dict response rows, concealing malformed input from the strict parser. Allow modifying ONLY account_balance to reject malformed data shape/rows with content-free OKXTransportError; preserve other endpoint filtering. Injected-transport raw malformed balance test must prove 502/no writes. This implements existing REQ-003, no new business/data semantics.

AUD-002 / REQ-001 clarification: batch execute obtains a new account in _current_strategy for that execute request; pass that new snapshot into its initial preflight to avoid adjacent duplicate reads. Never reuse prepare identity. Post-leverage preflight must still obtain another new snapshot. Sequential enqueue already performs one identity read. Add execute-phase freshness/post-leverage account-switch evidence; no lifecycle semantics change.

## Completion evidence
Requested Model: gpt-6-luna
Requested Effort: xhigh
Observed effective route: unavailable / UNVERIFIABLE
Formal RED -> GREEN and final V3 148 tests PASS. Affected backend build exit 0 after last mutation. Coordinator final repository backend/Flutter builds and independent audit PASS. Evidence: docs/agents/audits/2026-10-03-strategy-preflight-account-reads.md. No unresolved findings or external actions.
