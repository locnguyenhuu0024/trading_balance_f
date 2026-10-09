# Implementation plan: Backend-owned app data

Status: COMPLETED
Date: 2026-10-07
Tier: L
Specification: docs/agents/specs/2026-10-07-backend-data-gateway.md
Decision Ledger: docs/agents/decisions/2026-10-07-backend-data-gateway.md
Branch: codex/backend-data-gateway (created from local main)
Verified branch base: c46dc54753546125ae3fcdd9274e10a7f9a35dd8, matching local main at creation.
Authorization: User explicitly authorized writing the plan and immediately executing its tasks; D3.

## Planning workstreams and synthesis

| Workstream | Material | Independent | Route | Logical runs | Adoption |
|---|---|---|---|---|---|
| Flutter data, polling and native ownership | YES | YES | R2 / gpt-6.1-sol / medium | frontend-data-01,frontend-plan-02 | COMPLETE / USED |
| Backend gateway, pooling, cache and strategy reads | YES | YES | R2 / gpt-6.1-sol / medium | backend-data-01,backend-plan-02,backend-list-plan-03 | COMPLETE / USED |

Fan-out Required: YES; Required Reasoning Agents: 2; Actual Reasoning Agents: 2 distinct children with immediate bounded follow-ups; Fan-out Compliance: PASS; Skip Reason: N/A. Coordinator owns accepted routes, TTLs, auth, handoff and fresh-proof synthesis. Main route fixed by runtime; workload C2. Child routes explicitly bound, parent inheritance forbidden, effective routes unavailable/UNVERIFIABLE. Runtime has no close/release primitive; terminal evidence collected, no fabricated lifecycle operation.

## Tasks, dependency graph and write boundaries

```text
T93 backend gateway ------> T96 strategy list
T94 frontend core -------> T95 risk/native
T93 + T94 + T95 + T96 ---> T97 verification-fixture correction ---> final independent integration audit/build
```

Wave 1: T93 and T94 independently implement the frozen gateway contract, disjoint backend/Flutter sources and fake-transport tests. Wave 2: T95 after T94 PASS; T96 after T93 PASS. Tests use temporary stores/fakes; no concurrent real services, protected config or shared generated mutation. Formal full-suite/build integration occurs after all writers finish. No task may PASS while depending on a later task to repair compilation.

| Task | Contract | Executor | Allowed source surface |
|---|---|---|---|
| T93 | REQ-001..005; gateway/display position reads | E2 / gpt-6-luna / max | backend/data_gateway.py,backend/okx.py,backend/service.py,backend/app.py; dedicated backend tests |
| T94 | REQ-006..007; transport/foreground market/account clients | E2 / gpt-6-luna / max | explicit Flutter transport/repository/provider/screen files in task |
| T95 | REQ-008; Risk foreground/background session lifecycle | E2 / gpt-6-luna / max | explicit Risk/native files in task |
| T96 | REQ-009; sequential refresh then shared fresh projection | E2 / gpt-6-luna / max | backend/strategy.py; strategy list tests |

E2 is justified by connection leasing/cache concurrency (T93), asynchronous session/result fencing and polling lifecycle (T94), cross-isolate acknowledged auth/owner fencing (T95), and interacting state-machine/terminal-proof invariants (T96). Architecture and semantics are resolved in the specification; executors do not redesign.

Authorized extension D8: T93 also owns backend/currency.py and the fixed cached USDT/VND route; T94 owns only the VND provider portion of the settings presentation source. REQ-010/AC-008. No additional independent material workstream: one fixed read transport and an existing derived consumer within the analyzed backend/frontend ownership. User approved inclusion during execution; revised contract sent to both executors.

## Verification and build gates

Each task executes meaningful RED negative/boundary then GREEN intended-success scenarios, independently derived expectations, and a behavioral failing baseline where feasible. Focused V2/V3 checks only until integration; no full suite per task. Task build gates: Python compileall for backend, Flutter web --no-pub for Flutter after final executable task edits. Final freshly observed same builds after all remediation, plus backend discovery and Flutter suite once. Test/build commands consume manifests only as opaque input; no manifest/configuration inspection or writes.

No live exchange order, cancel/amend/retry, production read or remote upload. Preserve pre-existing telemetry modification and unrelated dirty paths. Only coordinator writes task status/telemetry; only executors write product/tests. Every terminal report includes exact commands/exits, RED/GREEN order, allowed diff paths, external-action status and safe telemetry envelope.

## Rollout, rollback and external actions

External configuration/environment actions: none required for code/local verification. Existing TRADE_API_BASE_URL is reused unchanged. Existing operational files are protected and untouched. Deployment requires publishing backend and rebuilding frontend with the user's existing HTTPS definition; it is not performed. Deploy backend first (additive routes), then frontend. If runtime regressions occur, redeploy prior frontend/backend versions; no database migration or history rewrite is involved. The old frontend still uses old backend routes during staged rollout.

Native Android session/ownership is covered with local fake channel tests; an actual-device background/expiry check and any unavailable native build must be explicitly reported. Latency evidence is request counts/cache reuse/connection behavior, not an invented production millisecond improvement.

## Checklist

- [x] T93 backend gateway and read optimization PASS
- [x] T94 foreground migration and shared polling PASS
- [x] T95 Risk/native session integration PASS
- [x] T96 strategy list fresh shared projection PASS
- [x] T97 deterministic verification fixture compatibility PASS
- [x] Independent audit and final tests/build PASS

## Bounded final verification remediation

AUD-INT-1..5 / T97 corrects seven verification fixtures: pending Settings navigation animation, three unclosed direct SQLite fixture connections on Windows, a fake HTTPResponse lacking getheader, navigation Risk source isolation, and two Strategy dialog fake constructor signatures. Runtime behavior and existing financial/cancellation/migration/navigation assertions remain unchanged. Coordinator records necessary harness maintenance for the approved final verification. TierS, one mechanical verification workstream; fan-out skip SINGLE_MATERIAL_WORKSTREAM. E0 gpt-6-luna/high explicitly bound; effective route unavailable/UNVERIFIABLE. Backend fixture verification proceeded independently of T95; Flutter commands were serialized after T95 released the runtime. One reserve slot was used for remediation, with eight allocated agents out of nine and no close/release primitive. No protected configuration or new dependency.

Final acceptance: backend discovery329 tests PASS (unchanged backend after that run), final Flutter582 tests PASS, fresh backend compileall PASS, and final native webbuild PASS after all executable/test edits. Optional APK build unavailable because Android SDK is absent; actual-device background and production latency remain unverified. Detailed evidence and resolved findings are in the canonical audit. Code remains uncommitted on codex/backend-data-gateway; no push or deployment performed.
