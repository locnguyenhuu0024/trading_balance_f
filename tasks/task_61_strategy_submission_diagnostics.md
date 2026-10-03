# Task 61 — Strategy Submission Diagnostics

Status: PASS
Agent Role: implementation_executor
Executor Class: E1
Target Model: gpt-6-luna
Target Effort: xhigh
Target Route: gpt-6-luna / xhigh
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Dispatch Route Status: UNVERIFIABLE
Requested Model: gpt-6-luna
Requested Effort: xhigh
Observed Effective Model: unavailable
Observed Effective Effort: unavailable

Specification: `docs/agents/specs/2026-10-02-strategy-submission-logging-design.md`
Plan: `docs/agents/plans/2026-10-02-strategy-submission-logging.md`
Plan Steps: P01..P03
Requirements: REQ-001..005
Acceptance Criteria: AC-001..004

## 1. Objective and preconditions

Implement safe local JSON diagnostics for both sequential and batch strategy submissions and their worker, with unchanged trading behavior. User execution authorization after plan presentation is required before dispatch. No root cause or live production reproduction has been established.

## 2. Allowed write surface

- `backend/diagnostics.py` (new)
- `backend/tests/test_strategy_diagnostics.py` (new)
- `backend/app.py`
- `backend/okx.py`
- `backend/strategy.py`
- `backend/strategy_worker.py`
- `backend/strategy_queue.py`
- `backend/tests/test_strategy_api.py`
- `backend/tests/test_strategy_queue.py`
- `backend/tests/test_strategy_worker.py`
- `backend/tests/test_trade_api.py`
- `docs/deployment/position-trade-api.md` (explanatory Markdown, already authorized doc surface)

No protected configuration content access or mutation; no manifest/env/Docker/script/CI/frontend/store/schema changes, new dependencies, live exchange calls, Git writes or canonical artifact/status/telemetry writes. Return BLOCKED if contract or surface is insufficient.

## 3. Implementation contract

Follow spec §§2–4 and plan P01..03. Central strict field/enumeration validation, UTC JSON lines <=4 KiB, hashed strategy/order refs, numeric code sanitization independent of stored results, fixed shape/reason labels. Never emit payloads, auth/confirmation/account values, raw IDs, raw messages/exception text/stack traces, prices/sizes/margin/leverage amounts or paths from settings.

Bounded queue256, nonblocking producers, process-aware lazy daemon stderr sink, drop when full/invalid/sink failure; optional shutdown drain <=250 ms outside order processing. No sink write inside request/order processing or DB transactions. Context correlations isolated across concurrent requests. Log records are not authoritative markers.

WSGI instrumentation covers only classified prepare/execute requests, including errors before dispatch. API includes frozen prepare mode, successful durable enqueue and execution no-op. Worker emits startup/shutdown/fatal and <=1 heartbeat/60s (first pass included), lease/account/no-due outcomes and bounded read-only eligible/matching counts. Submission instrumentation covers preflight, leverage, per-order/batch attempts and outcomes, queue stop and commit refusal. Observed ACK and committed outcome remain distinct, including fence/CAS loss.

Safe optional OKX error category/HTTP status preserves existing public contracts. Fixed endpoint labels cover submission writes and existing preflight reads; never query/headers/body. Preserve INV-001..005: no extra exchange calls, no retries, unchanged payload/state/pacing/deadline/lease/reservation/unknown semantics.

Guide documents Docker stderr logs for `trading-balance-trade-api` and `trading-balance-strategy-worker`, hashed-ref correlation, heartbeat/stage/code interpretation, no-resend handling and best-effort limitations. Commands contain no secrets. Real production failure remains pending evidence.

## 4. Tests and formal checkpoint

RED-001: hostile credentials/codes/messages/IDs, unexpected/nested/huge data; rejecting/uncertain ACK; fence refusal; raising/full/stalled sink. Assert privacy, bounded output, stable state/call counts, untouched tail/no resend, and prompt producers while sink is blocked. Use fake transports, events/barriers and bounded joins rather than flaky timing sleeps.

GREEN-001: successful sequential FIFO log trail with stable cross-component refs and persisted flags; batch mixed outcomes; distinct fake HTTP/JSON categories; heartbeat throttling; concurrent context isolation. Assert identical exchange calls/payloads/durable outcomes to baseline.

After implementation declares readiness, run RED then GREEN as separate focused unittest cases and report exact names/commands/order/exits. Then V3 new diagnostic + affected strategy API/queue/worker/trade API tests. Escalate only for concrete missing coverage/regression. No full repository suite.

Task Buildability Gate: required YES; unit backend.

```sh
PYTHONPYCACHEPREFIX=/private/tmp/strategy-diagnostics-pycache /Users/locnguyen/.local/bin/rtk test /opt/homebrew/bin/python3.12 -m compileall -q backend
```

Execute after final executable edit. Use RTK-first; narrow exact-source/test fallback permitted. Do not inspect build configs. WSGI loopback permissions may need escalation. No production verification is claimed.

External configuration/environment action: NONE.

## 5. Execution ledger and report

- [x] Explicit role/model/effort dispatch recorded; no inheritance.
- [x] Scope and protected boundary maintained.
- [x] P01..03 implemented; invariant parity tests exist.
- [x] Formal RED then GREEN PASS with exact commands/results.
- [x] V3 affected regressions PASS; final task build PASS.
- [x] Terminal report: changed files, event coverage, safe logging limits, verification, remaining blockers; compact telemetry envelope with effective route unavailable if unexposed.

Coordinator audit: PASS (audit-02). Scope, acceptance, privacy, test quality, RED/GREEN order, state/call parity, route compliance, buildability and final integration must be independently assessed before PASS.

Execution authorization: User instructed “Thực hiện tasks” on 2026-10-02 after plan presentation. Logical executor run: E1-T61-01. Explicit requested route bound at native spawn; effective route unavailable.

Final evidence: 5 formal RED then9 GREEN cases PASS; V3 146 tests PASS; task backend compile and final backend/web builds PASS. AUD-T61-001 resolved. Final audit: docs/agents/audits/2026-10-02-strategy-submission-diagnostics-audit-02.md. Production root cause/deployment not verified; external configuration actions NONE.
