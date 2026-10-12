# Task 110 — Pause strategy worker and use batch submissions

Status: PASS
Agent Role: implementation_executor
Executor Class: E1
Target Model: gpt-6-luna
Target Effort: xhigh
Target Route: gpt-6-luna / xhigh
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Specification: `docs/agents/specs/2026-10-12-pause-strategy-worker.md`
Plan: `docs/agents/plans/2026-10-12-pause-strategy-worker.md`
Plan Steps: P01
Requirements: REQ-001–004
Acceptance Criteria: AC-001–004
Frontend Level: F0
Frontend Design Brief: N/A
Required Frontend Guidance: N/A during implementation; pinned web-interface checklist at audit
Visual Review Required: NO

## 1. Dispatch Compliance

Dispatch Route Status: UNVERIFIABLE  
Requested Model: gpt-6-luna  
Requested Effort: xhigh  
Observed Effective Model: unavailable  
Observed Effective Effort: unavailable

## 2. Objective

Stop the standalone worker from autonomously reading/writing OKX while paused; make all new strategy preparations use the existing synchronous batch mode; preserve old sequential queue state. Done when AC-001–004 pass and both affected build units build.

## 3. Preconditions

Predecessors: none.  
Required decisions: D-001, D-002.  
Repository: user explicitly repeated execution/new-branch/commit/push instructions after the prior plan presentation. Create `codex/pause-strategy-worker` from `main` first.

## 4. Allowed Scope

- `backend/strategy_worker.py`
- `backend/strategy.py`
- `backend/tests/test_strategy_worker.py`
- `backend/tests/test_strategy_api.py`
- `backend/tests/test_strategy_settings.py`
- Existing `backend/tests/*.py` only for directly affected legacy sequential fixtures/mode-policy assertions (including queue, retry, diagnostics); retain historical queue safety coverage.
- `lib/features/strategy/presentation/strategy_settings_dialog.dart`
- `test/features/strategy/strategy_settings_dialog_test.dart`
- `test/features/strategy/strategy_dashboard_controller_test.dart` only if needed to prove manual refresh contract
- `docs/deployment/position-trade-api.md`

## 5. Forbidden Scope

Do not read/write protected configuration/environment files, manifests, Dockerfiles, CI, deployment settings, database schema, or unrelated files. Do not deploy, access production host, clear/migrate queues, convert sequential work, change wizard quote behavior, change dashboard polling (already manual), or perform live exchange calls.

## 6. Executor Contract

1. Add RED tests for worker module startup and effective submission-mode policy before code changes.
2. Make the standalone module idle until signal without constructing settings, store, client, worker, or calling run loops.
3. Force batch in effective settings and new preparations; reject sequential saves and old prepared sequential execution without exchange writes.
4. Disable the sequential option and explain temporary unavailability in the existing settings dialog. Keep historical sequential records renderable.
5. Keep existing queue records/markers byte/value-equivalent; update deployment instructions to require stopping/recreating the current host container.

Invariants: INV-001–005. Preserve batch payload, order validation, one-time confirmation, queue history, user initiated quote refresh and wizard read behavior. No migrations or dependency changes.

## 7. External Configuration / Environment Actions

None. The already running worker container must be stopped/recreated by the user/operator on its Docker host. This task does not perform a production deployment.

## 8. Tests

- TEST-001: patched worker entry point creates no settings/store/client/worker and makes no network call; shutdown signal exits.
- TEST-002: effective GET settings and new prepare return batch despite stored sequential; sequential save rejected; old sequential prepared execute returns conflict and records no write.
- TEST-003: existing sequential queue markers remain unchanged; existing batch behavior remains synchronous and one-time.
- TEST-004: strategy dashboard remains idle after initial load/visibility changes; explicit refresh fetches current quote.
- TEST-005: settings dialog displays batch and disables sequential with explanation; save acknowledgement and JEV settings remain correct.

## 9. Mandatory Verification

### RED — RED-001
Scenario: Current worker startup constructs settings/worker and sequential mode can be saved/prepared.
Command/method: focused unittest and Flutter settings test.  
Expected: new assertions fail before production change.  
Actual: Four backend policy assertions and the Flutter disabled-control assertion failed against the original behavior before implementation. All passed after the corresponding changes.  
Status: PASS

### GREEN — GREEN-001
Scenario: Worker entry point makes zero background calls; API forces batch; old queue is not mutated; user can still explicitly refresh.  
Command/method: focused backend unit tests and focused Flutter tests.  
Expected: AC-001–004 pass with fakes; no live API calls.  
Actual: 171 backend tests and 89 Flutter tests passed. Backend compile and Flutter web build succeeded; legacy accepted/unknown/inFlight markers remained byte-equivalent through result/list/duplicate execute.  
Status: PASS

Verification ceiling: V2 plus builds.  
Task buildability gate: REQUIRED.  
Python command: `python3.12 -m compileall -q backend`.  
Flutter command: `flutter build web --no-pub`.  
External verification: production host stop/recreate is user-operated and remains outside task verification.

## 10. Stop Conditions

Return BLOCKED if old uncertain queue markers cannot be preserved, if the only safe transition requires a schema/protected configuration change, or if an old sequential prepared token cannot be rejected without a trade write.

## 11. Execution Ledger

- [x] Explicitly bind `implementation_executor`, `gpt-6-luna`, `xhigh` at dispatch
- [x] Recheck branch and working tree before starting
- [x] Implement RED then GREEN
- [x] Run backend tests/build and Flutter tests/build
- [x] Audit only allowed source/test/docs paths; do not inspect protected configuration
- [x] Independent coordinator audit PASS
- [ ] Commit and push the approved branch after all gates PASS

## 12. Coordinator Audit

Scope: PASS — only approved source/tests/Markdown paths changed.  
Acceptance criteria: PASS — AC-001–004.  
Test quality: PASS — independent assertions cover mode enforcement, stale drafts, duplicate requests, accepted/unknown/inFlight marker preservation, and existing batch/queue safeguards. Legacy fixtures seed historical rows without reopening sequential creation.  
RED-before-GREEN: PASS — observed executor evidence.  
Queue preservation: PASS — exact stored marker comparison and retained historical engine tests.  
Dispatch route compliance: PASS — explicitly requested Luna/xhigh, effective route unavailable.  
Task buildability: PASS — builds current for their affected units.  
Pinned interface checklist audit: PASS — established labeled radio control is disabled with explanatory copy; existing loading/error/keyboard/scroll behavior retained; F0 visual review not required.  
Verdict: PASS

## 13. Final Verification Evidence

- `rtk test python3.12 -m unittest backend.tests.test_strategy_worker backend.tests.test_strategy_settings backend.tests.test_strategy_api backend.tests.test_strategy_queue backend.tests.test_strategy_diagnostics -v`: 171 passed (16 worker, 7 settings, 103 API, 28 queue, 17 diagnostics).
- `flutter test test/features/strategy/strategy_settings_dialog_test.dart test/features/strategy/strategy_dashboard_controller_test.dart test/features/strategy/strategy_screen_test.dart`: 89 passed.
- `flutter build web --no-pub`: succeeded after all Flutter/product edits; subsequent backend-only fixture changes do not invalidate this build. Existing Wasm/font warnings remain.
- `python3.12 -m compileall -q backend`: exited 0 after all edits.
- `git diff --check`: clean.
- No live OKX calls or production deployment. Flutter commands required escalation for the toolchain cache outside the workspace.
- Earlier protected-file read incident was disclosed and user authorized independent-source continuation; its contents were discarded. No protected file was changed.
- Runtime exposes no child close/release primitive; completed child results were collected, with no conflicting writers.
- Production action remains user-owned: on the Docker host run `sudo docker stop trading-balance-strategy-worker`, verify it is stopped, then deploy the updated API/frontend. Push alone does not pause the old running image.
