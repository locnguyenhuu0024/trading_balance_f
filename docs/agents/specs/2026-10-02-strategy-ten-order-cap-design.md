# Design Specification: Ten Orders Per Strategy

Status: BLOCKED_ON_CLARIFICATION
Date: 2026-10-02
Tier: M
Decision Ledger: `docs/agents/decisions/2026-10-02-strategy-ten-order-cap-decisions.md`

## Objective and current evidence

User selected a maximum of ten orders per strategy, combined across buy/long and sell/short, for both batch and sequential submission. This is an application policy, not a diagnosed OKX rate limit.

- OBS-001: `backend/strategy.py` `_MAX_ORDERS=20`, `_normalize_contract` bounds combined selected levels; preview and draft save use this normalization.
- OBS-002: `_prepare` does not revalidate saved counts; `_claim_queue` validates the prepared list but batch execute lacks the same count bound. New guards must cover both contract and prepared count before claims/writes.
- OBS-003: `strategy_queue.py` queue envelope and worker reconciliation retain capacity20 for historical data. Existing active queues may have unsent rows; changing the envelope globally could misclassify a valid historical queue as corrupt.
- OBS-004: `lib/features/strategy/domain/strategy_selection.dart` accepts20; wizard selection shares one map across sides. Shared prepared validator and queue DTO also accept20 for distinct purposes.
- OBS-005: Saved DRAFT Apply is status-based. Recreate starts a fresh wizard and depends on backend `canDelete`; PREPARED has refresh but no resumed-confirmation UI.

## Decisions and open questions

D-001: User explicitly selected at most10 total orders per strategy.
Q-001: Block oversized historical DRAFT/PREPARED from new preparation/execution, or grandfather these records? Awaiting user.
Q-002: Let preexisting APPLYING queues >10 finish their confirmed tail, or stop their unsent tail? Awaiting user.

Do not finalize affected legacy behavior or dispatch implementation until both choices are resolved. No evidence proves a production root cause. T61 diagnostic logging is implemented and audited PASS; deployment and production diagnosis remain outside that task.

## Proposed contract, subject to Q-001/Q-002

- REQ-001 / AC-001: Backend rejects a new preview or draft with11+ combined selected levels using existing invalid-order-count semantics and an updated message. Exactly10, including5+5, remains valid subject to other existing rules.
- REQ-002 / AC-002: Wizard/domain admission, Next, preview, save and apply agree on the new maximum10. Show `Đã chọn N/10 lệnh · Long B · Short S`. Reject the11th attempted selection without dropping prior IDs/entry choices or invalidating an otherwise valid preview. An oversized server preview cannot enable Save/Apply.
- REQ-003 / AC-003: Apply fresh submission-specific validation to prepared ACKs and execution paths. Legacy DRAFT/PREPARED behavior depends on Q-001; no silent truncation or split.
- REQ-004 / AC-004: Historical results/queue progress up to20 remain readable and fully reconciled. Already-sent orders are never deleted, cancelled or resent by this change. Active queue tail policy depends on Q-002.

Separate new-admission maximum10 from historical readable capacity20 and global worker budget20. Do not change preview hashes, allocation math, payloads, pacing, leverage, lease/deadline, reservations, auth/session ownership, execute-once behavior or exchange retries. No migrations/config/dependencies or live financial verification.

## RED / GREEN

RED-001: New preview/save with11 total levels (one-sided and mixed6+5) rejects with no new draft; oversized legacy cases follow the user-selected policy with unchanged durable markers and no unauthorized writes.
GREEN-001: Exactly10 (one-sided and mixed5+5) previews/saves/prepares/executes in both modes with ten exact fake payloads. Historical20 rows remain readable/reconciled under the selected policy.
RED-002: Wizard11th selection preserves first10 and explains the cap; forged11-order preview/prepared ACK cannot save/confirm/execute.
GREEN-002: Ten selected entries produce a correct10/10 indicator and allow normal preview/save/confirm/single execute; historical progress20 is still displayed.

## Compatibility and rollout

No protected configuration content access or writes. No external actions presently required. Deploy authoritative backend before frontend; older frontend may offer >10 and must receive a safe rejection. No automatic truncation/repair of stored plans. Final rollout/rollback and legacy guards will be specified after Q-001/Q-002.

Completion requires backend/frontend tasks, formal RED then GREEN, affected tests, task builds and integration audit. Pending production diagnosis is separate from this application policy.
