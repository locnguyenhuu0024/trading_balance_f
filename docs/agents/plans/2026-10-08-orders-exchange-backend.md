# Implementation Plan: Orders exchange read pressure
Status: COMPLETE
Date: 2026-10-08
Tier: L
Specification: docs/agents/specs/2026-10-08-orders-exchange-backend.md
Decision Ledger: docs/agents/decisions/2026-10-08-orders-exchange-backend.md

## Objective and preconditions
Implement REQ-001–004 / AC-001–004. T98 is PASS; user confirms both deployments contain 4dbd004. New backend scope is outside T98; await fresh execution authorization.
Coordinator class C2 (hard reasoning, low orchestration); preferred gpt-6.1-sol/high. Current main runtime is fixed; effective route unavailable, no route claim.

## Repository impact and configuration
Modify only backend/data_gateway.py (bundle/cache/identity cooldown), backend/service.py (_fetch_display_snapshot), backend/tests/test_data_gateway.py; add backend/tests/test_positions_read_pressure.py. Include backend/okx.py and backend/tests/test_okx_pool.py solely for sanitized Retry-After metadata propagation (VAL-001).
No frontend, action/strategy behavior, dependencies, protected configuration or persisted schema changes. External configuration actions: none.

## Planning workstream decomposition
| Workstream | Material | Independent | Explicit reasoning route | Logical run | Result |
|---|---|---|---|---|---|
| Backend pressure/concurrency | YES | YES | R3 / gpt-6.1-sol / high | R3-PRESSURE-001 | COMPLETE / USED |
| Account/session isolation | YES | YES | R2 / gpt-6.1-sol / medium | R2-SAFETY-001 | COMPLETE / USED |
| Frontend | NO | N/A | N/A | N/A | compatible consumer |
Fan-out Required: YES. Required agents: 2. Actual agents: 2. Compliance: PASS. Skip reason: N/A.
Both requests explicitly bound role/model/effort; parent inheritance forbidden; effective routes unavailable (UNVERIFIABLE). Safety follow-up accepted the fixed bundle design subject to spec invariants. No close/release runtime primitive exists; terminal outputs collected.
Coordinator synthesis: standalone child-cache sharing deferred; one bundle in existing bounded domain avoids staged child-flight redesign. Postcheck ordering changes explicitly documented. One service retry owner prevents nested retries.

## Dependency graph and ordered steps
P01 -> P02 -> P03, all within T99 (compile-coupled).
P01: Add deterministic fake-exchange service/gateway tests covering count, causal429, cooldown and identity/session boundaries. Use counters/barriers/controlled time; no sleeps or real exchange. Preserve standalone regression coverage.
P02: Implement fixed bundle, staged publication and display identity cooldown exactly as spec. Preserve generation fences/bounds/action reads. Wire service bundle consumption, public metadata and final validation. Preserve exactly one freshness retry owner.
P03: Formal RED negative cases then GREEN successful/count/regression cases; affected backend compile; executor report; coordinator scope/security/concurrency audit and final integration build.
Stop/replan on contradictory account contract, unbounded state, lock/executor deadlock, configuration need or writes outside allowed paths.

## Verification plan
TEST-001: deterministic service count and concurrent bundle sharing (AC-001).
TEST-002: identity429 followers, zero-read cooldown, remaining Retry-After and expiry recovery (AC-002).
TEST-003: temporal pre/post proof; acquisition deadline; account switch; final action invalidation; revoked leader/valid follower; error revocation precedence; mixed standalone reads (AC-003).
TEST-004: partial sibling cleanup; exact two freshness attempts; deep copies; bounded cache/inflight; existing action/strategy freshness (AC-004).
Formal RED: run the newly implemented negative-case classes FIRST, validating AC-002/003 and failure/cleanup/two-attempt boundaries. GREEN follows with the focused modules and existing gateway tests. Exact class commands must be recorded in executor report before execution, with observed counts/status; do not use an artificial failed assertion as negative evidence.
GREEN command: rtk test python3.12 -m unittest backend.tests.test_data_gateway backend.tests.test_positions_read_pressure -q
Verification ceiling V3: targeted deterministic integration + existing backend regression suite once; do not repeat unaffected checks.
Full backend regression owner: CODEX_ONCE, rtk test python3.12 -m unittest discover -s backend/tests -q (opaque tooling input only).
Task canonical build: rtk proxy python3.12 -X pycache_prefix=/private/tmp/t99-python-cache -m compileall -q backend
Final integration: fresh backend compile plus rtk proxy flutter build web --no-pub, after last executable change; inspect only concise diagnostics. Escalate only SDK-cache sandbox write if needed, never config inspection.
External live verification: not required for offline contract; production rate-limit origin remains unverified. Deployment and Git mutations need separate authorization.

## Migration, risks and rollout
No migration. Representative data: empty/nonempty three-type positions, changing fingerprint, revoked sessions, slow/failed reads.
RISK-001: stale/account data -> enforce staged validation/final fence.
RISK-002: leader session leakage -> session-free shared observation work and per-waiter auth.
RISK-003: deadlock/resource leak -> bounded executor/admission tests and cleanup audit.
RISK-004: other processes still hit exchange limits -> instance-local limitation documented.
After separate deployment authorization, backend rollout only; rollback artifact on correctness/security regressions, no data restoration needed.
D-001 is used by all steps: Open Positions affected and both deployments current. Invalidated by user correction only.

## Task and completion gate
T99 owns P01–03 / all requirements and acceptance; E2 gpt-6-luna/max due interacting cache/flight/generation/cooldown invariants. Write surfaces as repository impact above.
- [x] Required planning fan-out reconciled
- [x] User authorizes this plan/task
- [x] T99 PASS with RED before GREEN and task build PASS
- [x] All AC evidence, final build and coordinator audit PASS
- [x] Diff confined to scope; no protected config accessed/written

## VAL-001 — Transport metadata integration correction
Observed during implementation: backend/okx.py::OKXError and OKXClient._retry_after discard HTTP-date and clamp numeric Retry-After to24hours. This contradicts already-approved REQ-003. Extend the bounded write surface to these two source/test paths solely to sanitize/canonicalize valid duration/date metadata without shortening valid delays. No HTTP request, action retry, signing, pool, configuration or public response changes. This is an acceptance-preserving integration correction under existing execution authorization, not a new product decision. Add an offline actual HTTP transport -> OKXError -> gateway cooldown test; include test_okx_pool in formal RED/GREEN.

## Final integration evidence
T99 PASS. Final backend regression354 PASS (43.587s), backend compile exit0, web build exit0 (25.9s). AUD-001 cooldown race and AUD-002 deterministic fixture resolved through explicitly bound executors. Full audit: docs/agents/audits/2026-10-08-orders-exchange-backend.md. No deployment or Git mutation in this execution.
