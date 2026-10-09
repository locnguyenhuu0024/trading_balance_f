# Task 99 — Orders exchange backend read pressure
Status: PASS
Agent Role: implementation_executor
Executor Class: E2
Target Model: gpt-6-luna
Target Effort: max
Target Route: gpt-6-luna / max
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Specification: docs/agents/specs/2026-10-08-orders-exchange-backend.md
Plan: docs/agents/plans/2026-10-08-orders-exchange-backend.md
Plan Steps: P01–P03
Requirements: REQ-001–004
Acceptance Criteria: AC-001–004

## Dispatch and preconditions
Dispatch Route Status: UNVERIFIABLE. Requested Model/Effort: gpt-6-luna / max. Effective Model/Effort: unavailable.
User authorized current plan and execution on 2026-10-08. Explicit model AND effort binding mandatory; no inherited writer. No predecessor implementation remains.

## Objective and bounded scope
Deliver fixed safe display-position bundle and identity429 cooldown; done when all acceptance evidence/build/audit pass.
Allowed Write Surface:
- backend/data_gateway.py
- backend/service.py
- backend/tests/test_data_gateway.py
- backend/tests/test_positions_read_pressure.py (new)
- backend/okx.py (sanitized Retry-After metadata only; VAL-001)
- backend/tests/test_okx_pool.py (transport metadata regression only; VAL-001)
Do not write docs/status/telemetry (coordinator-owned), frontend, unrelated product code, dependencies or any protected configuration. No config content read, broad root search, live exchange, external tools, Git mutations, deployment or child spawn.

## Executor contract
Follow P01–P03 and spec invariants INV-001–005; do not redesign missing semantics. Share observations without caller authority. Stage bundle separately from standalone children, preserve bounds, force one postproof after all private completion; use acquisition deadlines. 429 preserves causal failure unless subsequent independent invalidation supersedes it; session revocation wins per caller. Cooldown honors remaining Retry-After with existing 1-second fallback. Action/strategy reads stay uncached. Only service performs one freshness retry.
Return BLOCKED on ambiguity, out-of-scope need, protected configuration need or unavailable required verification. No self-escalation.
External configuration/environment actions: none. External verification: NO for offline contract.

## Tests and mandatory verification
TEST-001–004 in plan are mandatory; fake exchange/clock/barriers only.
RED-001/002: causal429/cooldown and isolation/freshness/cleanup negative tests. Exact unittest class commands selected after naming tests and recorded before formal run. Expected no forbidden calls/publication or authority leakage; observe RED before GREEN.
GREEN-001/002: normal cold <=2 config/3 positions/3 instruments, five-second refresh <=2 config/3 positions with warm metadata, concurrent sharing and compatible existing behavior.
GREEN command: rtk test python3.12 -m unittest backend.tests.test_data_gateway backend.tests.test_positions_read_pressure -q
Actual RED/GREEN: PENDING. Ceiling: V3; full backend regression once per plan, no broad repetition unless changed evidence requires it.
Task Buildability Gate: REQUIRED; backend canonical unit; rtk proxy python3.12 -X pycache_prefix=/private/tmp/t99-python-cache -m compileall -q backend; after final executable change. Result PENDING.

## Execution ledger
- [x] Explicit role/class/model/effort binding, no parent inheritance
- [x] Inspect scoped source/test evidence
- [x] P01 tests and P02 implementation
- [x] RED then GREEN with exact commands and observed results
- [x] Task build PASS after final executable edit
- [x] No protected config content access/write; no external call
- [x] Return compact report with changed paths, AC/test mapping, route envelope, blockers and residual risks

## Coordinator audit
Scope, AC, negative-test quality, retry ownership, identity/session fences, admission cleanup, bounds, dispatch and final build: PENDING.

## R01 / AUD-001 — Preserve cooldown across concurrent identity success
Confirmed offline: old identity flight A blocked; explicit action invalidates A/generation; new current flight B starts; A returns429 and records29second instance cooldown; B succeeds and unconditionally resets cooldown to0, permitting an immediate third exchange read. Violates REQ-003/AC-002.
Bounded remediation E2 gpt-6-luna/max on backend/data_gateway.py and backend/tests/test_positions_read_pressure.py only. Fence identity success publication against cooldown established during that request; never clear active cooldown. A retains independent409; current B and its authorized followers receive causal429, no successfulidentity/cache publication. Current-generation causal429 invalidation must preserve quota deadline, while later independentinvalid409 stillwins. Add deterministic A/invalidation/B/429/success regression incl zeroadditionalcalls until expiry and one recovery. Formal negativeRED thenGREEN focusedmodules; backendcompile after finaledit. Fullsuite environmentblocked: localWSGI socketbind PermissionError; coordinator will execute fullsuite with loopbackpermission after finalcodefreeze.

## R02 / AUD-002 — Deterministic partial-failure fixture
E0 gpt-6-luna/high, implementation_executor, EXPLICIT, no parent inheritance. Write only backend/tests/test_positions_read_pressure.py. MARGIN fixture failure is immediate while testrequires all three childrenentered; valid queued-sibling cancellation makes assertion scheduler-dependent. Add failure-release event, await all acquisitionsentered beforetriggeringfailure, hold running siblings toverify draining, finallycleanup allthreads/events/executors. No product change. Negative BundleSafetyRedTests beforefocusedGREEN; backendcompileafterlastedit. Full354 regressionwithloopback permission firsthad1failure butRTK1MBlogtruncatedtrace; diagnosticrunnerwithfixturelogredirect thenpassed354. R02 addresses independently observed schedulingdefect; aftereditcoordinatorreruns affectedfullregression/finalbuilds.

## Final execution and audit result
PASS. R01 E2 explicit gpt-6-luna/max and R02 E0 explicit gpt-6-luna/high completed. Effective routes unavailable (UNVERIFIABLE), no inheritance. Negative7 then focused55 PASS after final fixture change; full backend354 PASS with loopback permission. Task backend compile and fresh final backend compile/web build exit0 after last executable edit. Audit: docs/agents/audits/2026-10-08-orders-exchange-backend.md. No protected configuration access/write, external actions or deployment.
