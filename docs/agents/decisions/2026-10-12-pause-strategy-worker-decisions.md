# Decisions: Temporarily Pause Strategy Worker

Status: ACTIVE  
Specification: `docs/agents/specs/2026-10-12-pause-strategy-worker.md`  
Plan: `docs/agents/plans/2026-10-12-pause-strategy-worker.md`

## Clarification Questions

### Q-001 — Effect on existing sequential work
Status: ANSWERED  
Question: During the pause, may already queued sequential strategies remain waiting, with open orders no longer monitored by the worker until it is re-enabled?  
Why it matters: The worker both submits queued sequential orders and monitors submitted order state.  
Repository evidence: `backend/strategy_worker.py`, `backend/strategy.py`, `docs/deployment/position-trade-api.md`.  
Possible interpretations:
- A: Preserve queued work and do not convert/resend it; wait until worker re-enablement.
- B: Keep some sequential processing active by another request-driven mechanism.

### Q-002 — Submission mode for new strategies
Status: ANSWERED  
Question: While the worker is off, should new strategy submissions use existing batch mode so new confirmed orders remain functional, or should sequential submissions also wait?  
Why it matters: New preparations default to sequential and the API only enqueues that mode.  
Repository evidence: `backend/strategy.py` settings/prepare/execute and `lib/features/strategy/presentation/strategy_settings_dialog.dart`.  
Possible interpretations:
- A: Force batch for new work, disable the sequential setting, and leave old queues untouched.
- B: Leave sequential selectable and accept that new queues will wait.

## User Decisions

### D-001 — Preserve existing sequential work while paused
Source question: Q-001  
Decision: Accept that already queued sequential strategies remain waiting and open orders are not worker-monitored until re-enablement. Preserve queue data/markers; never automatically convert, retry, or delete it.  
Impacts: REQ-003, AC-003, P01, T01.

### D-002 — Use batch for new strategy work
Source question: Q-002  
Decision: Disable the worker and use the existing synchronous batch mode for new strategy preparations/submissions during the pause.  
Impacts: REQ-002, REQ-003, AC-002, AC-003, P01, T01.

## User-Authorized Assumptions

N/A.

## Change Log

N/A — initial revision.
