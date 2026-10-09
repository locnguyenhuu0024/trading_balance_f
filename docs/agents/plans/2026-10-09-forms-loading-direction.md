# Implementation Plan: Forms, loading and automatic direction

Status: COMPLETE
Date: 2026-10-09
Tier: L
Specification: docs/agents/specs/2026-10-09-forms-loading-direction-design.md
Decision Ledger: docs/agents/decisions/2026-10-09-forms-loading-direction-decisions.md
Frontend Level: F2
Frontend Design Brief: docs/agents/specs/2026-10-09-forms-loading-direction-frontend-brief.md (APPROVED)

## Planning coverage and approval

| Workstream | Material | Independent | Route | Logical run | Adoption |
|---|---|---|---|---|---|
| Frontend/UI/startup | YES | YES | R2 / gpt-6.1-sol / medium | R2-FE-001 | COMPLETE / USED |
| Backend/API/persistence | YES | YES | R2 / gpt-6.1-sol / medium | R2-BE-001 | COMPLETE / USED |

Fan-out Required: YES. Required/actual reasoning agents: 2/2. Fan-out Compliance: PASS. Skip reason: N/A. Effective routes unavailable; explicit binding verified from dispatch. Runtime has no close/release primitive; collected bounded runs are terminal; scoped followups use the same explicitly bound routes and are recorded. Coordinator remains runtime-fixed; C3 preferred workload route, no effective route claim.

Synthesis: automatic direction is allowed-side scope; both preserves existing subset materialization. Backend and frontend use additive optional field and legacy default. No migration. Frontend source files named settings are UI, not protected operational settings. web/index.html is application markup; only presentation DOM/CSS and first-frame removal permitted, existing bootstrap/base/manifest settings untouched. No new bootstrap config file.

Approval: concrete plan presented in chat; D-001 authorizes execution immediately after planning. D-002 authorizes new branch, reviewed scoped commit and push. Branch: codex/forms-loading-strategy-direction. Initial tree clean, base main 109b5c0.

## DAG and implementation

```text
P01/T105 backend -------+---------------- audit/integration -> commit/push
P02/T106 forms + client +-> P03/T107 startup/navigation ----+
```

Wave1: backend and frontend writers have disjoint Python/Dart surfaces, independent stubs and no shared build cache. Wave2 startup begins only after frontend PASS, serializing Flutter build/runtime state. Backend cannot invalidate fixed optional API semantics; shared cross-layer audit follows both.

| Task | Plan step | Requirements/AC | Executor | Surface |
|---|---|---|---|---|
| T105 | P01: Automatic direction persistence/filtering/replay/materialization | REQ-003 / AC-003 | E1 / gpt-6-luna / xhigh | backend/strategy_automatic.py; backend/tests/test_strategy_automatic.py; related strategy API/queue/worker test files only if behavioral proof requires |
| T106 | P02: All forms, async feedback and automatic client direction | REQ-001/002/003/005 / AC-001/002/003/005 | E1 / gpt-6-luna / xhigh | app_theme.dart; core form/loading widgets; inventoried forms; strategy API and affected Dart test fakes/tests/render harness |
| T107 | P03: Startup and destination/route continuity | REQ-004/005 / AC-004/005 | E1 / gpt-6-luna / xhigh | main.dart; startup widgets; main_navigation_shell.dart; web/index.html presentation; associated tests |

Handoff review: combine all form surfaces because they share layout primitives/visual evidence and avoid duplicate shared-theme writers. Couple automatic client interface and every fake consumer for buildability. Separate backend and startup because they fail independently with different runtime evidence. No implementation decisions left open.

## Verification and buildability

Every task executes its specification RED scenario before GREEN at one formal checkpoint; focused diagnostic runs are separate. V1 -> V2/V3 affected group ceiling per task. Escalate only for observed caller/shared-surface risk. Final V4 once justified by global theme/startup and public automatic API; full Flutter tests and backend unittest discovery. Preserve unaffected evidence after edits; rerun affected scenarios and build after executable changes.

- T105 build: python3.12 -m compileall -q backend. Behavioral: automatic suite plus relevant API/queue/worker/retry/scope.
- T106/T107 build: flutter build web --no-pub. Behavioral: focused Flutter widget/API/form/startup/navigation tests. Run Flutter commands serially. Use native opaque manifests; no dependency fetch/regeneration.
- Final fresh builds: python3.12 -m compileall -q backend; flutter build web --no-pub.
- Final inspection: name-only status, then explicit non-protected file diffs; git diff --check scoped paths; independent audit including pinned local guidelines.
- Visual: real Flutter render harness mobile/desktop, loading/strategy/forms and large-text boundary. Review PNGs; record limitations. Native OS/device packaging and live exchange remain unverified.

## Data, performance and risk

No schema migration/external config action. JSON additive direction, omission=both; fail closed on malformed explicit data. No claimed latency benchmark. Preserve stale-read fencing, explicit trade confirmation, existing risk/budget calculations. Startup cannot delay with decorative timers or reset overrides. Route animation must not retain outgoing page reads/interactions. Toolchain/build caches may require sandbox escalation; no app changes to work around permission failures.

Rollout: reviewed branch push only. Owner deploys compatible frontend/backend. Rollback: revert feature commit, no schema reversal. Requirement traceability is in specification and task contracts. Completion requires all task verdicts PASS, final build, responsive/interface audit and explained clean status.

Observed T107 caller extension FE107005: trading_navigation_bar.dart/tests, and floating_navigation_buttons.dart/tests only for both-accessibility-flag consistency. Static reduced-motion label avoids durationzero AnimatedSize layout mutation; real-shell coverage retained. This is a necessary existing-caller fix under REQ-005, not unrelated scope.
P04/T108 observed integration remediation: full Flutter530 tests had529 PASS and1 legacy same-row geometry expectation after intentional320px filter stacking. Correct responsive test contract, validate actual caller alignment and14px controls; scoped files in task108. E1 explicitLuna/xhigh. Finalfullsuite/build pending after remediation.



All implementation/audit/build gates complete:532FlutterPASS,365backendPASS, finalcompile/webbuildexit0, formalRED/GREENeachboundedtask and21actualvisualrendersPASS. Authorized branchdelivery proceeding; no merge/deploy/nativeQAclaim.
