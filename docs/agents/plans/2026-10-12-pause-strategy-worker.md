# Implementation Plan: Temporarily Pause Strategy Worker

Status: IMPLEMENTED  
Date: 2026-10-12  
Tier: L  
Specification: `docs/agents/specs/2026-10-12-pause-strategy-worker.md`  
Decision Ledger: `docs/agents/decisions/2026-10-12-pause-strategy-worker-decisions.md`

## 1. Objective

Implements REQ-001–004 and AC-001–004. Stop autonomous OKX traffic from the separate worker while preserving user initiated refresh and new batch order submissions.

## 2. Preconditions

Decisions: D-001, D-002.  
Repository state: clean `main` observed; user requested a new branch from `main`. Execution is authorized by the user's repeated request after the plan presentation; create `codex/pause-strategy-worker` from `main` before implementation.

## 3. Repository Impact

| Area | File | Symbol | Change Type |
|---|---|---|---|
| Backend worker | `backend/strategy_worker.py` | `main` | MODIFY |
| Backend mode policy | `backend/strategy.py` | settings, prepare, execute | MODIFY |
| Backend regression tests | `backend/tests/test_strategy_worker.py`, `backend/tests/test_strategy_api.py`, `backend/tests/test_strategy_settings.py` | worker/API cases | MODIFY |
| Flutter settings | `lib/features/strategy/presentation/strategy_settings_dialog.dart` | submission mode choices | MODIFY |
| Flutter tests | `test/features/strategy/strategy_settings_dialog_test.dart` and focused settings/provider tests as needed | pause contract | MODIFY |
| Deployment guide | `docs/deployment/position-trade-api.md` | worker pause/restart instructions | MODIFY |

New files: none beyond these planning artifacts.  
Explicit exclusions: all protected configuration/environment files, dependency/build manifests, Docker/container configuration, database schema, worker queue internals, dashboard polling, wizard market reads, and unrelated docs.

## 4. External Configuration / Environment Actions

Required configuration actions: none. The production host must stop/recreate an already running worker to apply the pause; that user-owned deployment is outside this code task and will not be executed here.

## Planning Workstream Decomposition

| Workstream | Material | Independently Analyzable | Reasoning Route | Agent Run | Status / Adoption |
|---|---|---|---|---|---|
| Backend/runtime and strategy mode | YES | YES | R2 / gpt-6.1-sol / medium | R2-BACKEND-PAUSE-001 | COMPLETE / USED |
| Frontend/settings and dashboard refresh | YES | YES | R2 / gpt-6.1-sol / medium | R2-FRONTEND-PAUSE-001 | COMPLETE / PARTIAL (settings contract used; dashboard already manual) |
| Frontend submission-mode control refinement | YES | YES | R2 / gpt-6.1-sol / medium | R2-FRONTEND-MODE-002 | COMPLETE / USED |

Fan-out Required: YES  
Required Reasoning Agents: 2  
Actual Reasoning Agents: 3  
Fan-out Compliance: PASS  
Skip Reason: N/A  
Cross-workstream synthesis: Backend policy is authoritative; Flutter disables the unavailable choice; existing dashboard quote reads are already explicit/manual and need no code change.

## Frontend Design Gate

Frontend Level: F0  
Frontend Design Brief: N/A — established settings controls and design system; no visual redesign.  
Brief Status: N/A  
Required guidance: N/A for implementation; apply the pinned web-interface checklist to the changed disabled-state copy/control during audit.  
Visual Review Required: NO — functional control availability/copy only.  
Repository design-system evidence: existing `RadioGroup`/`RadioListTile` in the strategy settings dialog.  
Open visual/product decisions: none.

## 5. Dependency Graph

```text
Plan approval -> T01 worker + mode policy + settings UI + docs -> integration audit -> user-owned host stop/deploy
```

## 6. Ordered Implementation Steps

### P01 — Pause background worker and route new work through batch

Objective: implement REQ-001–004 / AC-001–004 in one compile-coupled task.  
Files: paths listed in §3.  
Dependencies: none.

Required changes:
1. Make `backend.strategy_worker`'s standalone entry point wait for shutdown without loading settings, constructing clients/store/worker, or calling `run_forever`; preserve queue code for later re-enable.
2. Make effective settings and new preparation use `batch` even when a stored legacy preference is sequential; reject sequential writes. Reject execution of old prepared sequential drafts with a clear conflict and no exchange write. Keep queued sequential data and markers untouched.
3. Disable the sequential radio choice in the existing settings UI with concise temporary-unavailable text. Keep loading/error/save acknowledgement and historical queue rendering intact.
4. Update the deployment guide to state that an existing worker container must be stopped/recreated on the host; pushing code alone has no effect on a running container.
5. Add the planned tests before implementation; do not reset or migrate existing queue rows.

RED verification:
- RED-001: tests demonstrate worker module startup loads settings/constructs worker or starts periodic work, and saved sequential mode still permits new queue preparation.
- Expected before implementation: the negative assertions fail against the current behavior using patched fakes only.

GREEN verification:
- GREEN-001: patched worker entry point makes no settings/store/client/OKX calls and exits cleanly when signaled.
- GREEN-002: stored sequential settings read as effective batch; sequential save is rejected; new preparations freeze batch; batch execute places once; old prepared sequential execute conflicts without writes.
- GREEN-003: previously queued sequential markers remain unchanged; dashboard idles without calls and an explicit refresh fetches current quote once per eligible instrument.

Stop conditions:
- If preserving legacy queue markers requires schema or protected deployment configuration changes, stop and replan.
- If the server cannot safely reject an old prepared sequential token without mutating its state, preserve it and return BLOCKED for that edge rather than converting it silently.

## 7. Test and Verification Plan

| Test | Proves | Level | Command/Method |
|---|---|---|---|
| TEST-001 | AC-001; worker entry point has no periodic calls | V1 | `python3.12 -m unittest backend.tests.test_strategy_worker -v` |
| TEST-002 | AC-002/003; settings/prepare/execute behavior and no queue rewrite | V2 | `python3.12 -m unittest backend.tests.test_strategy_settings backend.tests.test_strategy_api backend.tests.test_strategy_queue -v` |
| TEST-003 | AC-002; settings selection/disabled state and save acknowledgements | V2 | `flutter test test/features/strategy/strategy_settings_dialog_test.dart` |
| TEST-004 | AC-004; idle/no polling and explicit refresh still fetches | V2 | `flutter test test/features/strategy/strategy_dashboard_controller_test.dart test/features/strategy/strategy_screen_test.dart` |
| TEST-005 | backend task buildability | build | `python3.12 -m compileall -q backend` |
| TEST-006 | frontend task buildability | build | `flutter build web --no-pub` |
| TEST-007 | scope/whitespace | V1 | `git diff --check` after name-only status review |

Formal checkpoint: complete RED before GREEN. Run relevant backend and Flutter focused cases; do not run the full repository suite absent a concrete risk.  
Verification ladder: V1 -> V2; final integration ceiling V2 plus backend compile and Flutter web build.  
Escalate only for failures in queue compatibility, mode acknowledgements, or manual quote freshness.  
External verification: production container behavior requires a user-owned host stop/recreate; local tests cannot verify the running host.

## 8. Migration / Data Plan

N/A — no database schema or queue data migration. Preserve all legacy preferences and queue records; apply batch policy at the effective API boundary.

## 9. Performance Verification

The disabled standalone entry point must make zero exchange calls over a bounded wait interval. Manual refresh counts are verified with fakes; no live OKX load test.

## 10. Risks

| Risk ID | Risk | Impact | Detection | Mitigation |
|---|---|---|---|---|
| RISK-001 | Existing worker container continues running | OKX limiting continues after code push | Host container status | Document explicit stop/recreate; report production action pending |
| RISK-002 | Legacy queue contains uncertain/partly sent order | Duplicate order or silent loss | Frozen queue marker test | Never convert/resend/delete; keep paused |
| RISK-003 | Stale client requests sequential | New strategy queue strands | API regression test | Server rejects sequential and forces batch on prepare |

## 11. Rollout / Rollback

Sequence: stop current worker container on the host; merge/deploy approved code; use batch submissions while paused; do not start a new worker process.  
Rollback trigger: explicit decision to resume sequential submissions/monitoring.  
Rollback: re-enable the worker only after reviewing preserved queues/unknown markers; restore sequential settings only with the corresponding worker active.

## 12. Decision/Assumption Dependency Registry

| Decision | Used By | Evidence/Authorization | Invalidated By |
|---|---|---|---|
| D-001 | REQ-003, P01 | User selected preserve and wait | User requests migration/recovery |
| D-002 | REQ-002, P01 | User selected batch for new work | User requests different active submission path |

## 13. Task Decomposition

| Task | Plan Steps | Requirements/AC | Depends On | Executor Class | Allowed Write Surface |
|---|---|---|---|---|---|
| T01 | P01 | REQ-001–004 / AC-001–004 | — | E1 | `backend/strategy_worker.py`, `backend/strategy.py`, specified backend tests and affected legacy queue fixtures, settings dialog/test, deployment guide |

### Task Buildability Plan

| Task | Required | Affected Canonical Build Unit | Exact Secret-Free Build Command | Boundary Strategy |
|---|---|---|---|---|
| T01 | YES | Python backend and Flutter web application | `python3.12 -m compileall -q backend`; `flutter build web --no-pub` | One coherent backend/frontend contract and tests; build each unit after final edits |

## 14. Completion Gate

- [x] T01 PASS with RED before GREEN
- [x] T01 backend and Flutter buildability PASS after final code edits
- [x] old queue records and uncertain markers preserved
- [x] updated worker entry point makes zero autonomous OKX calls
- [x] batch mode is server-enforced and user-visible while paused
- [x] pinned interface checklist audit passes for changed control
- [x] final integration audit PASS
- [x] protected configuration/environment files remain unchanged; earlier disclosed read incident was handled through user-approved independent sources
- [x] deployment limitation/current host action reported clearly

## 15. Change Log

Revision 2: re-presented the plan at user request, retained D-001/D-002, and included affected legacy sequential test fixtures. The user explicitly requested implementation, new branch, commit, and push after planning.

Revision 3: T110 and independent coordinator integration audit PASS. Exact verification and pending production stop action are recorded in the task. Commit/push integration follows the authorized workflow.
