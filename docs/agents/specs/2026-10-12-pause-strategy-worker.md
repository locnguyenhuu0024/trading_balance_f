# Design Specification: Temporarily Pause Strategy Worker

Status: READY_FOR_PLAN  
Date: 2026-10-12  
Tier: L  
Decision Ledger: `docs/agents/decisions/2026-10-12-pause-strategy-worker-decisions.md`

## 1. Objective

Requested outcome: stop the standalone strategy worker from making background OKX calls, while retaining explicit user initiated refresh and a working path for new strategy orders.

Success conditions:
- Starting `python -m backend.strategy_worker` performs no configuration, database, worker, or OKX work and remains safely idle until stopped.
- New strategy preparations and submissions use the existing synchronous `batch` path. Sequential is visibly unavailable and rejected by the API while paused.
- Existing sequential queues remain stored and untouched; they are not converted or resent. Existing exchange order history remains readable.
- Strategy dashboard prices are fetched on initial load or explicit refresh only. The current implementation already meets this condition.

## 2. Current State

### Observed Facts

| ID | Source | Symbol/Location | Observation |
|---|---|---|---|
| OBS-001 | `backend/strategy_worker.py` | `main`, `run_forever`, `run_once` | The standalone entry point loads worker settings and scans about every five seconds; even an idle pass checks account configuration. |
| OBS-002 | `backend/app.py` | `WSGIApplication._get_service` | The API service is lazy and request driven; it does not launch the worker. |
| OBS-003 | `backend/strategy.py` | settings, prepare, execute | Saved/default settings permit sequential; prepare freezes it and execute only queues work for the worker. |
| OBS-004 | `backend/strategy.py` | `_refresh_result_state` | Manual result/list reads skip active sequential queues; they cannot replace their queue processor. |
| OBS-005 | `lib/features/strategy/presentation/providers/strategy_dashboard_provider.dart` | `load`, `refresh`, visibility, `_refreshQuoteSnapshot` | Dashboard quote requests happen on load/explicit refresh; visibility changes mark data stale without requests. |
| OBS-006 | `lib/features/strategy/presentation/strategy_screen.dart`, `lib/core/widgets/manual_refresh_button.dart` | strategy refresh action | An accessible refresh action already loads the dashboard and coalesces pending taps. |
| OBS-007 | `docs/deployment/position-trade-api.md` | worker deployment section | Worker is a separate supervised container. Pushing code does not stop an already running container; the host operator must stop/recreate it. |

## 3. Scope

### In Scope
- Disable the standalone worker entry point without reading worker environment or starting a scan.
- Force new preparations to effective `batch`; report batch from settings reads, reject attempts to save `sequential`, and protect against stale sequential prepared drafts executing.
- Explain in the existing settings control that sequential is temporarily unavailable; keep batch selectable.
- Keep old sequential queue records and exchange markers intact and paused.
- Update the deployment guide with the pause behavior and the host-side stop/recreate requirement.
- Add focused backend and Flutter regression coverage.

### Out of Scope
- Deleting worker/queue implementation or migrating old queues.
- Automatically converting any queued, prepared, accepted-prefix, or uncertain sequential work to batch.
- Deploying to or issuing commands on the production host.
- Changing user initiated dashboard refresh, wizard market reads, order status reconciliation outside active sequential queues, or authentication.

## 4. Clarifications and Decisions

Open questions: N/A.  
Resolved decisions: D-001 and D-002 in the decision ledger.  
Authorized assumptions: N/A.

## 5. Requirements

### REQ-001 — No autonomous worker traffic

The standalone module entry point MUST NOT load worker settings, instantiate `StrategyOrderWorker`, access the store, call OKX, or run background scans. It MUST remain safely idle until normal process termination so restart policies do not create an exit loop. The worker implementation remains available for a later approved re-enable.

### REQ-002 — Batch for new strategies while paused

During the pause, authenticated settings reads and every new preparation MUST report/freeze `batch`, regardless of an older stored sequential preference. Saving `sequential` MUST return a clear unavailable error. Existing batch execution, validation, one-time confirmation, and result persistence remain unchanged.

### REQ-003 — Protect old sequential state

Already queued sequential strategies and their accepted, in-flight, unknown, and not-submitted markers MUST remain unchanged and MUST NOT be automatically resent, converted, deleted, or reconciled by a global worker. An old prepared-but-not-queued sequential strategy MUST fail execution with an actionable conflict and no exchange writes; it can be safely deleted/recreated when its existing never-sent rules allow. Historical sequential states remain renderable.

### REQ-004 — Manual strategy quote refresh

The dashboard MUST continue loading a current authenticated quote on initial load and explicit refresh, with no timer/visibility-triggered request. Wizard-selected instruments/timeframes retain their explicit market-data requests. A manual quote read MUST fetch current data independently of any worker cache.

## 6. Data Contract

N/A — no schema or persisted queue data change. Historical sequential fields retain their existing meaning.

## 7. Cross-Layer Mapping

| Semantic Field | Persistence/Query | API | Frontend | Component |
|---|---|---|---|---|
| Effective submission mode | Stored preference may remain sequential for compatibility; effective value is batch while paused | GET returns batch; POST sequential rejects; prepare stores batch | Settings shows batch selected and sequential disabled with explanation | Existing Strategy settings dialog |
| Existing queue state | Existing queue JSON and order markers unchanged | Existing result/list representation unchanged | Historical queue/result rendering unchanged | Strategy dashboard/cards |
| Quote snapshot | No worker cache dependency | Existing authenticated quote route reads on demand | Load/refresh only | Strategy dashboard |

## 8. Proposed Design

```text
standalone worker module -> explicit disabled idle -> SIGTERM/SIGINT exits
new strategy draft -> settings/prepare effective batch -> user confirms -> existing synchronous batch API writes
old sequential queue -> stored state preserved and paused
dashboard load or refresh -> authenticated current quote read -> no autonomous polling
```

Keep mode policy server-enforced so older or non-UI clients cannot enqueue new sequential work. Do not rewrite any legacy setting or queue row as a migration.

## 9. Interfaces and Contracts

- Public API shape: unchanged. Settings mode is effectively `batch`; saving `sequential` returns a stable 409/400 unavailable-mode response with user-facing recovery text.
- Prepared sequential draft created before this change: execute returns 409, leaves the draft unattempted, and performs no order write.
- Worker entry point: remains the documented Python module command, but blocks without constructing runtime clients until terminated.
- Database/schema: unchanged.
- External configuration: none. Production container stop/recreation is a user-owned operational action, not configuration.

## 10. Invariants

- INV-001: The module entry point produces zero OKX reads and writes while paused.
- INV-002: New strategy submissions use the reviewed payload through the existing batch path exactly once.
- INV-003: Historical sequential in-flight markers are never reset, converted, or resent by this change.
- INV-004: Manual refresh and explicit wizard reads continue to fetch current data.
- INV-005: No protected configuration/environment file is read or modified.

## 11. Edge Cases

### EDGE-001 — Old sequential queue has an uncertain in-flight order
Condition: A queue has an accepted prefix or an unresolved write marker when the worker is stopped.  
Expected behavior: Preserve all markers and queue phase; do not retry or convert. It remains paused until an explicitly approved recovery.

### EDGE-002 — Saved preference or client still requests sequential
Condition: Existing account preference is sequential or an older client submits it.  
Expected behavior: Settings read exposes batch; server rejects a sequential save; new preparation freezes batch.

### EDGE-003 — Old prepared sequential draft
Condition: A draft was reviewed under sequential mode before rollout but has not entered a queue.  
Expected behavior: Execution returns a clear conflict without order writes; user must recreate/review under batch.

### EDGE-004 — Existing worker container
Condition: An old image is already running on the production host.  
Expected behavior: Code push alone does not stop it. User/operator stops the running container; a newly created worker process from updated code remains idle.

## 12. Failure Semantics

| Failure | Expected Response | Allowed Side Effects | Forbidden Side Effects |
|---|---|---|---|
| Sequential settings save during pause | Clear unavailable-mode response | No preference mutation | No silent coercion or sequential queue |
| Old prepared sequential execution | 409 conflict | Diagnostic event | No queue claim or exchange write |
| Worker process starts while disabled | Waits for termination | One bounded disabled diagnostic | No env/settings/store/client/OKX access |
| Existing queued row is read | Existing result/list behavior | Read-only response | No queue processing, marker rewrite, or resubmission |

## 13. RED / GREEN Behavioral Contract

### RED-001
Scenario: Start the worker module with settings/client/store constructors patched to fail on invocation.  
Expected result: Before implementation, the standalone entry point loads settings and starts worker behavior.  
Expected side effects: No real environment or OKX access in the test.

### GREEN-001
Scenario: Start the worker module with constructors patched to fail, then signal shutdown.  
Expected result: No constructor, scan, or exchange method is called; process exits on signal.

### RED-002
Scenario: Existing sequential preference is returned and can be saved; a prepared strategy freezes sequential mode.  
Expected result: Current behavior permits the queue path that requires a worker.

### GREEN-002
Scenario: Existing stored preference is sequential; read settings, save sequential, create/prepare a new draft, and execute an old sequential prepared draft.  
Expected result: Read/new prepare report batch; sequential save is rejected; batch execution remains synchronous; old sequential prepared execution conflicts without exchange writes.

### GREEN-003
Scenario: Existing queue row contains accepted and unresolved markers; dashboard idles then explicit refresh occurs.  
Expected result: No timer request or queue mutation; manual dashboard quote is fresh; existing queue markers remain byte/value equivalent.

Verification order is RED then GREEN.

## 14. Performance Contract

The paused worker must make zero periodic network calls. User initiated refresh and batch placement retain existing request counts and timing; no new polling or retries are introduced.

## 15. Compatibility

No schema change. Historical sequential records remain parseable and displayable. The temporary API policy is intentionally incompatible with sequential settings/new sequential preparations while paused; existing batch clients remain supported.

## 16. Security and Permissions

No credential/configuration reads occur in the disabled worker entry point. Existing authenticated API checks and account-scoped strategy ownership remain unchanged.

## 17. Protected Configuration / Environment Actions

Required configuration actions: none. The user/operator must stop/recreate the already running worker container on the host for deployment effect; this is not an agent-executed action and no host access is in scope.

## 18. Rollout / Rollback

Rollout: stop the currently running worker on the Docker host; deploy the approved code; do not start a worker process until the pause is lifted. New batch submissions remain available. Existing sequential queues remain paused.  
Rollback: restore the previous worker-enabled code and explicitly restart the worker only after the queue state has been reviewed. Do not clear uncertain markers during rollback.

## 19. Acceptance Criteria

### AC-001
Given the standalone worker module is started while paused, when it runs until signaled, then it performs zero settings/store/client construction, zero scans, and zero OKX calls.

### AC-002
Given an account has a stored sequential preference, when settings are read or a new strategy is prepared, then the effective mode is batch; when sequential is saved, the API rejects it.

### AC-003
Given a previously queued sequential strategy or old prepared sequential draft, when it is read or executed, then queue markers remain unchanged and no order is newly submitted.

### AC-004
Given an authenticated user opens or manually refreshes the strategy dashboard, when quote data is requested, then a current quote is fetched on demand; idle visibility changes cause no request.

## 20. Requirement Traceability

| Requirement | Acceptance Criteria | Design/Contract | RED/GREEN |
|---|---|---|---|
| REQ-001 | AC-001 | §8, INV-001 | RED-001 / GREEN-001 |
| REQ-002 | AC-002 | §8, INV-002 | RED-002 / GREEN-002 |
| REQ-003 | AC-003 | §11, INV-003 | RED-002 / GREEN-002 / GREEN-003 |
| REQ-004 | AC-004 | §8, INV-004 | GREEN-003 |

## 21. Completion Gate

- [x] No unresolved material question; D-001/D-002 recorded.
- [x] No silent assumption; old sequential queue wait and new batch policy explicitly authorized.
- [x] Requirements, contracts, edges and failure semantics defined.
- [x] RED/GREEN scenarios and traceability defined.
- [x] Protected configuration/environment contents were not used as evidence.
- [x] No protected configuration/environment action is required.

## 22. Change Log

N/A — initial revision.
