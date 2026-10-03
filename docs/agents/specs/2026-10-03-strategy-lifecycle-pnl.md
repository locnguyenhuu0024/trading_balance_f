# Design Specification: Strategy lifecycle deletion and PnL colors
Status: READY_FOR_PLAN
Date: 2026-10-03
Tier: L
Decision Ledger: docs/agents/decisions/2026-10-03-strategy-lifecycle-pnl-decisions.md

## Objective and current state
Remove strategy introduction card, expose strategy status, allow safe cleanup after external cancellation, and restore profit/loss colors. Evidence: strategy_screen.dart uses canDelete for delete and recreate; strategy.py permits only never-sent deletion; app_theme.dart positive/negative roles are grayscale. No live exchange reproduction was performed; source evidence confirms these causes.

## Scope and decisions
D01: User authorized execution after planning and delegated product choices. Keep current branch feat/compact-strategy-trade-cards; no commit/push/deploy requested for this follow-up.
D02: Delete only local strategy/dependents; never cancel orders or close positions implicitly. Preserve never-sent replacement semantics using additive canReplace.
D03: Dedicated PnL colors leave general monochrome palette untouched. Absolute finite values below 0.005 (USDT or percentage points before formatting) use muted gray; threshold equality is signed. Positive green, negative red in both themes. Invalid/missing/nonfinite and hidden values gray.
D04: Summary status uses existing Vietnamese labels/never-sent behavior. A nonempty complete list of canceled/mmp_canceled rows, with no active/corrupt queue or APPLYING execution, displays Đã hủy; persistence status remains unchanged.
Open questions: none.

## Requirements and acceptance
REQ-001 / AC-001: Remove whole introduction card and its gap; preserve create/settings entry points and signed-out guidance.
REQ-002 / AC-002: Every compact strategy card displays current Vietnamese status, including draft, prepared, applying, applied, partial, unknown, completed, and all-canceled cases; wrap at narrow widths and large text; live dashboard updates must update summary.
REQ-003 / AC-003: Existing never-sent deletion remains. Submitted strategies can be deleted only after complete terminal evidence, no active execution/queue/lineage dependencies, and valid current same-account zero position for instrument. Dashboard canDelete is advisory; endpoint freshly verifies before deletion and rejects changed account/revision or uncertainty without removal or exchange writes.
REQ-004 / AC-004: Visible PnL amount and percent in orders, portfolio aggregate/details and strategy details use green/red/gray rules; hidden values and invalid data stay gray. Do not change calculations or formatting.
REQ-005 / AC-005: canReplace keeps old never-sent predicate; canDelete expansion must not enable recreation or reclassify attempted strategies as never sent. Backward compatibility for old servers only when original no-placement facts support it.

## Backend contract
Keep _eligible_never_sent_record unchanged. Add separate local terminal eligibility: nonempty results match saved orders one-to-one by stable client ID and quantities/side identity, no missing/duplicate rows; statuses filled/canceled/mmp_canceled/rejected/not_submitted only. Submitted rows require valid exchange identity, contracts and filled bounds. Rejected/not_submitted require durable evidence of no placement (do not trust status alone). Never-submitted rows can qualify only stopped/completed sequential queues with no pending/sending/in-flight markers; block corrupt/malformed queue, APPLYING, non-null executionId or active/malformed lease. Preserve retry-child/unsafe-lineage and active replacement checks.
Hint uses the same local predicate plus validated positions already fetched for result; unavailable/malformed data must not imply zero. Terminal result hint must not be true on stale/error order evidence. canReplace always original eligibility and never broadens.
DELETE: retain original never-sent path. For terminal path, freshly read every accepted/submitted order including cached terminal rows, validate instrument/client/exchange identity, size, side and fill bounds, require explicit terminal state. Read current account before/after reads, validate all position rows and require no nonzero/unknown size for strategy instrument across sides. Force account/position failures to safe existing API errors. No exchange write. Transactionally reload same account/revision/orders/queue/execution facts and lineage before dependent cleanup, reject concurrent changes. Existing store transaction serialization handles deletion vs claim: any earlier claim changes snapshot or eligibility; later claims find removed row.
Position transport evidence: backend/okx.py positions() silently filters non-dict data items and defaults missing data to empty. Terminal hint/deletion must validate raw response data list via existing okx.request(GET, /api/v5/account/positions, params={instType: SWAP}) in an allowed strategy.py helper, or equivalently strict raw transport; do not treat filtered/missing payload as proof of zero exposure. Preserve other callers.
No schema migration. canReplace is additive. No worker changes; no changes to order-placement behavior.

## Invariants and failure semantics
INV-001: Never delete if exchange state, position, account, identity or concurrent lifecycle is uncertain.
INV-002: No exchange mutation; no widening replacement/retry contracts.
INV-003: Source/test changes only; protected configs unreadable and unwritable. Native build/test may consume opaque config.
EDGE-001: Partial fills with active position block; fully closed terminal positions permit cleanup.
EDGE-002: Mixed live/unknown/missing/queued rows block. Retry children and active replacement block. Terminal canceled rows in PARTIAL/APPLIED need not await worker COMPLETED.
EDGE-003: Hidden, NaN, infinity, negative zero and abs(value)<0.005 gray; exactly +/-0.005 signed.

## Cross-layer mapping
Persisted order/queue/execution state -> strategy API canDelete/canReplace -> existing dashboard maps -> summary actions/confirmation. Deletion confirmation describes local removal only and must not say never-sent for submitted strategies.

## Verification
RED-B: live/unknown/malformed/incomplete/account-changed/position-present/concurrent state rejects deletion with no local removal or exchange write.
GREEN-B: externally canceled all orders with fresh valid no-position evidence removes strategy/dependents; canReplace false; legacy never-sent behavior preserved.
RED-U: zero/nearzero/invalid/hidden PnL gray; delete-only strategy has no recreate action; active/unknown no derived delete.
GREEN-U: sign colors both themes and consumer widgets; status/live updates and canceled confirmed delete; intro absent and responsive layout.
Formal RED then GREEN after implementation, then affected-file V2/V3 tests. Final builds Flutter web --no-pub and backend compileall.

## Security, rollout, rollback and configuration
Existing authenticated account boundary retained. No configuration/environment actions. Rollout code + backend together, additive compatibility guard. Rollback revert code before production deletion; removed local records are not restored by code rollback. User confirmation is required for each actual strategy deletion, retained in UI.
Performance: reuse result positions for hints; fresh exchange reads only on explicit deletion, no additional polling.
