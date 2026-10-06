# Implementation Plan: Independent Long and Short Strategies
Status: COMPLETE
Date: 2026-10-06
Tier: L
Specification: docs/agents/specs/2026-10-06-independent-long-short-design.md

## Authorization and routing
The user explicitly instructed execution immediately after planning and checkout of a new branch. This task-specific instruction overrides the repository default separate approval round. Branch: fix/independent-long-short-strategies. Coordinator C1 preferred, current runtime retained; no effective route inferred.

## Planning workstreams
| Workstream | Material | Independent | Requested route | Logical run | Adoption |
| --- | --- | --- | --- | --- | --- |
| Backend exposure/lifecycle/data | YES | YES | R2 gpt-6.1-sol medium | longshort-backend-analysis; longshort-reservation-analysis | COMPLETE / USED |
| Frontend identity/creation | YES during discovery; no implementation required | YES | R2 gpt-6.1-sol medium | longshort-frontend-analysis | COMPLETE / USED |
Fan-out Required: YES. Required Reasoning Agents: 2. Actual Reasoning Agents: 2 (one backend follow-up). Fan-out Compliance: PASS. Interface synthesis: retain API and frontend; scope backend guards and results internally.
Child bindings explicitly requested both model and effort; effective routes unavailable/UNVERIFIABLE. Runtime has no close/release primitive; terminal child results collected, no fabricated cleanup operation.

## P01 / T86 — One atomic auditable backend change
Implements REQ-001..006 / AC-001..006. DAG: approved contract -> T86 -> coordinator audit -> final builds. One E2 implementation_executor gpt-6-luna/max; many interacting migration/reservation/retry/lifecycle invariants justify E2. One writer prevents shared migration/test conflicts.
1. Shared validated strategy scope helpers; Hedge disjoint sides, conservative unknown/Net.
2. Transactional reservation migration and overlap checks; safe proven legacy scope support, all consumers consistent.
3. Preflight/retry positions/pending, per-candidate overlap, prepare/claim and mode validation.
4. Side-aware result attribution and lifecycle clearance with unchanged fresh evidence requirements.
5. Regression/migration/concurrency coverage in listed non-protected tests.
Allowed scope is defined in specification. No protected file content access or mutation. Existing telemetry change predates task; coordinator appends operational events only.

## Verification
RED first: formal negative/boundary cases reject same-side/Both/Net/ambiguous exposure, conflicting reservation and invalid migration scope before writes. GREEN second: opposite Hedge prepare/execute, active queues, selected retries, PnL, completion/delete, migrations and opposite concurrent claims succeed without touching other side. Executor names exact unittest methods and records commands/observations in terminal report. Before implementation, observe at least one new opposite-side regression fail against old code if feasible.
V3 ceiling: affected strategy API/queue/worker/retry tests; scope/shared data risk justifies one backend discovery suite at final integration. No repeated full suite. Existing frontend serialization/ID tests may be reused, or narrow strategy tests if cross-layer evidence needed.
Task Buildability Gate YES: python3.12 -m compileall -q backend, after last change.
Final repository builds: python3.12 -m compileall -q backend; flutter build web --no-pub --release; flutter build macos --no-pub --release (known canonical units from README and prior approved plan). Consume manifests only opaquely. No release_build.sh (deploys).
Stop on unresolved contract, unknown protected setting, scope expansion, live-data need, or environment blocker; preserve unaffected work. External configuration/environment actions: none. Live trading verification not authorized/required; local fake exchange proves contract.

## Compatibility evidence revision
D-001: API group exposed 19 regressions because ordinary draft-time Net mode can differ from later prepared Hedge mode. Prepared mode is authoritative under validated exact order evidence; invalid snapshot modes still fail closed. Re-run affected API/worker/scope evidence; early helper/migration source-audit freshness is invalidated. Existing scope and authorization remain valid.

## Completion
T86 PASS. Final coordinator RED 4 then GREEN 8 pass, backend discovery 273 pass, targeted Flutter 68 pass, Python compileall/web/macOS builds exit 0. Final source/test audit PASS. See docs/agents/audits/2026-10-06-independent-long-short.md. No protected configuration mutation, commit, push or deployment.
