# Implementation Plan: Direct OKX reads

Status: COMPLETE
Date: 2026-10-14
Tier: L
Specification: docs/agents/specs/2026-10-14-direct-okx-reads-design.md
Decision Ledger: docs/agents/decisions/2026-10-14-direct-okx-reads-decisions.md

## Objective and Preconditions
REQ-001..005 / AC-001..005. Clean initial worktree, branch `codex/direct-okx-api-reads`. User explicitly authorizes immediate execution following plan, D-001. No protected content required.

## Planning Workstreams
| Workstream | Material / Independent | Route | Logical run | Adoption |
|---|---|---|---|---|
| Native API integration/security | YES / YES | R2 gpt-6.1-sol medium | api-plan-01 | COMPLETE / USED |
| Frontend auth/action behavior | YES / YES | R2 gpt-6.1-sol medium | auth-plan-01 | COMPLETE / USED |
| Backend implementation | NO | N/A | N/A | unchanged |
Fan-out Required: YES. Required/actual reasoning agents: 2/2. Fan-out Compliance: PASS. Effective routes unavailable; both spawn requests explicitly bound model/effort with inheritance forbidden. Runtime exposes no close/release primitive; terminal results collected, no guessed cleanup call.
Synthesis: native display reads cannot supply backend trading authority. Separate explicit action selection from render reads. D-002 resolves non-OKX currency source.

## Frontend Gate
F0 for transport/read wiring; F1 for the bounded backend action dialog using existing design primitives. No visual redesign/brief. Scoped interaction/a11y audit for new action dialog using local pinned web checklist, no React skills. Rendered visual review not mandatory; widget behavior/size coverage required.

## Impact / Scope
P01: new core network direct client; safe signing/legacy Dio reuse as needed; storage credential notification lifecycle plus web overrides in main; direct-client tests.
P02: market/fractal/SR/strategy-market repositories/pollers; portfolio/orders repositories/providers/screens; backend action entry dialog and refresh callbacks; currency provider/dedicated CoinGecko client; affected source/test callers.
Protected configuration/manifests/lockfiles, backend implementation and unrelated UI are forbidden surfaces.
External configuration actions: none.

## DAG and Steps
`T112/P01 -> T113/P02 -> T114/P03 lifecycle remediation -> T115/P04 action generation capture -> independent integration audit -> fresh final web build`.
Serial writers: shared Flutter build state and compile-coupled consumer types make concurrent consumer migration unsafe.
P01 adds buildable direct GET seam, final destination guards, safe signing/errors, credential generation notifications, cancellation and private scheduler behavior. Existing consumers remain buildable during this stage.
P02 migrates all production display consumers, native ALL/quotes, removes backend read gates, introduces explicit backend authority selection on action, preserves backend mutation/strategy contracts, direct CoinGecko and tests.
Reuse existing DTO parsers, storage UX, RequestCoordinator, ForegroundReadGate, authoritative PositionActionControls and prepare/confirm/execute. Two tasks separate transport/security proof from coherent consumer integration; no broken-build intermediate state.

## Tests / Verification
T112 V1 RED-001 before GREEN-001, then V2 direct client/security/storage tests; task build `flutter build web --no-pub`.
T113 V1 RED-002 before GREEN-002; V3 affected core/network and market/fractal/SR/portfolio/orders/strategy market/API/widget tests. Task build `flutter build web --no-pub`.
Final build same command freshly observed after last executable change. Full Flutter suite once at final integration is justified if shared client/provider mutation coverage cannot be bounded by V3; backend suite not required because no backend changes.
Escalation: unexpected shared provider regressions or interface consumers outside scoped tests. Evidence selectively invalidated by later changes. Formal scenarios use independently specified expected outcomes.
Live OKX/CoinGecko/browser CORS/private key check unavailable without credentials; source/mock transport and web compile cannot establish live connectivity or latency.

## Risks / Rollout
RISK-001 browser CORS/network denial -> safe surfaced error, no implicit proxy.
RISK-002 local/backend different accounts -> explicit backend account and authoritative target selection, never synthesize authority from OKX display.
RISK-003 credential rotation -> generation fences/cache invalidation at save/clear start and completion.
RISK-004 ALL partial history -> atomic failure and stable sort.
No data migration; user-owned release and authorized code rollback only.

## Task / Buildability Registry
| Task | Steps / AC | Executor | Build unit / command | Boundary |
|---|---|---|---|---|
| T112 | P01 / AC-001,002 | E1 gpt-6-luna xhigh | Flutter app / flutter build web --no-pub | additive compatible seam |
| T113 | P02 / AC-001..005 | E1 gpt-6-luna xhigh | Flutter app / flutter build web --no-pub | merged compile-coupled consumers |
| T114 | P03 / AC-002 | E1 gpt-6-luna xhigh | Flutter app / flutter build web --no-pub | internal disposal guard remediation |
| T115 | P04 / AC-004 | E1 gpt-6-luna xhigh | Flutter app / flutter build web --no-pub | immutable action-entry generation |
Explicit role implementation_executor, model AND effort bound; inheritance forbidden for each dispatch. Coordinator audits without patching product/tests.

## Completion
- [x] T112 PASS with RED/GREEN/build
- [x] T113 PASS with RED/GREEN/build
- [x] T114 lifecycle remediation PASS
- [x] T115 action generation capture PASS
- [x] relevant regressions and interaction audit
- [x] independent final diff/scope audit
- [x] final fresh repository build
- [x] no protected modifications or unexplained files
- [x] report live verification limitations; no commit/push

## In-scope Audit Remediation
P03/T114 addresses AUD-transport-lifecycle-01, independently confirmed injected-Dio disposal gap. No product/API/architecture change or new user decision; automatic remediation under approved REQ-002. Serialize after T113 to avoid shared tooling collisions. Final full Flutter suite once is justified by shared transport lifecycle change after consumer migration. Owned runtime Dio remains force-closed; injected guard must persist through active managed pipelines.

Final aggregate build scope also includes unchanged Python backend syntax build, established by prior allowed audit docs: `rtk proxy /opt/homebrew/bin/python3.12 -X pycache_prefix=/private/tmp/direct-okx-final-pycache -m compileall -q backend`. Existing configuration is opaque compiler input. No backend behavioral suite is duplicated because backend source is unchanged.

P04/T115 freezes backend generation at action entry before route builder execution, addressing independent consumer audit. Product contract unchanged; in-scope session fencing remediation. E1 gpt-6-luna/xhigh, explicit original binding reused; fresh task web build required.

Final acceptance: T112..T115 PASS; independent transport and consumer remediation audits PASS. Coordinator V4 `rtk flutter test --no-pub`564 passed exit0; fresh final `rtk flutter build web --no-pub` exit0 Built build/web22.6s. Unchanged backend syntax compile exit0 using temporary pycache. Final name-only scope and diff-check PASS. No protected content changes, external configuration, commits or pushes. Real API-key/private browser/native-device behavior and latency remain unverified; public credential-free connectivity probes succeeded. Existing Wasm dependency/Cupertino font build warnings and unrelated analyzer warnings remain. Runtime has no close/release primitive; all child terminal results collected without fabricated cleanup.
