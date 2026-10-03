# Design Specification: Limit Cap and Explicit Resubmission

Status: IMPLEMENTED
Date: 2026-10-03
Tier: L
Decision Ledger: docs/agents/decisions/2026-10-03-strategy-limit-cap-resubmission-decisions.md

## 1. Objective

Enforce10 total new limit orders per strategy and let the operator explicitly review and resubmit eligible failed/unsent rows without duplicating accepted or uncertain writes. Preserve already confirmed legacy queues and immutable retry lineage.

## 2. Current state and evidence

| ID | Source | Observation |
|---|---|---|
| OBS-001 | backend/strategy.py, _normalize_contract/_prepare/_execute/_claim_queue | Admission allows20; historical prepare and batch claim need explicit count guards. |
| OBS-002 | backend/strategy_queue.py, backend/strategy_worker.py | Historical queue reader and global placement budget allow20; these must remain. |
| OBS-003 | backend/strategy.py, _preview_contract | Filtering selectedLevels reallocates quantity; exact retry needs fixed-order preview. |
| OBS-004 | backend/store.py, transaction | BEGIN IMMEDIATE serializes creation/claims; existing JSON columns can persist lineage without schema changes. |
| OBS-005 | backend/strategy.py, _parse_batch_ack | Arbitrary nonempty str(sCode) can currently appear as rejection; malformed codes cannot prove rejection. |
| OBS-006 | backend/strategy.py, _eligible_never_sent_record/replacement cleanup | Replacement may delete a never-sent source; retry lineage requires extra dependency/permanence guards. |
| OBS-007 | lib/features/strategy | Wizard/domain/new confirmation admit20; no retry action or authoritative retry DTO exists. |
| OBS-008 | backend/diagnostics.py | T61 diagnostics are implemented, audited and pushed in e56e991; preserve privacy/sink/state invariants. |

No production failure reproduced, no live exchange request, no planning tests executed. Actual OKX rate-limit diagnosis is outside this change.

## 3. Scope

In scope: new cap, agreed legacy compatibility, server-owned retry eligibility, fixed-order preview, new linked/idempotent draft, lineage/claim/deletion guards, authenticated API and modal UI, offline tests and explanatory guide.
Out of scope: live trades/deployment, automatic retries/cancellation, retry of accepted/canceled-after-acceptance/unknown rows, partial-source position/pending exceptions or reservation transfer, new dependencies/schema/config, changes to existing allocation design, pacing/fences/deadlines, or source-history reset.

## 4. Decisions

D-001..004 and A-001..002 govern this revision. Open questions: NONE. Prior cap artifacts are superseded by this combined plan; their user decisions remain valid. Execution is pending presentation and post-plan authorization.

## 5. Requirements

- REQ-001: New preview/save and persisted prepare/execute admission enforce1..10 combined rows for both modes. Guard persisted selectedLevels/orders/prepared orders as applicable before preflight/claim. Preserve existing invalid_order_count semantics; update message. Never silently truncate/split.
- REQ-002: Wizard/domain/Next/preview/save/confirmation/controller/screen enforce10 and show `Đã chọn N/10 lệnh · Long B · Short S`. Rejected11th toggle preserves previous IDs/entry selections and valid preview; forged oversize server previews/prepared responses cannot save/confirm/execute.
- REQ-003: Block historical oversize unstarted DRAFT/PREPARED from new apply, with recreate/refresh guidance respecting existing canDelete eligibility. Already attempted execute calls retain conservative no-op behavior; no cap-induced ledger reset.
- REQ-004: Legacy APPLYING confirmed queues through20 continue; results/progress remain readable/reconciled. Historical capacity20 and global worker20-per-pass budget remain independent from new cap10.
- REQ-005: Retry candidates are derived from authenticated authoritative persisted rows plus fresh read-only exchange reconciliation. Only definitely not_submitted/rejected rows can be selected; corrupt, contradictory, accepted, sending, live, filled, canceled-after-acceptance and unknown evidence fails closed. Source cannot be APPLYING or have a live execution lease. No source deletion/replacement race or overlapping descendant can reopen eligibility.
- REQ-006: Retry preserves exact source side/role/price/contracts/leverage/optional levelId; validates fresh market metadata, quote, ticks/lots/minimum, passive prices, mode/fees/tiers/balance and unchanged position/pending/reservation blockers. No allocation, price/size rounding, entry-nearest requirement, or automatic quantity adjustment. Changing metadata invalidates a reviewed hash.
- REQ-007: Create a linked new DRAFT with fresh client IDs, idempotent request binding, durable source row consumption at token claim and original-history preservation. Standard child prepare/execute freezes current account preference, requires fresh token and uses existing batch/queue machinery once.
- REQ-008: Add `Gửi lại lệnh limit` as a separate card/modal action: authoritative candidates -> choose1..10 -> fresh preview -> new child draft -> prepare -> exact reviewed confirmation -> one execute -> refresh. Cancellation/session switch/invalid response/stale selection has zero execute calls. Uncertain writes are refreshed read-only and never automatically repeated. Show old/new attempt links and clear blockers.
- REQ-009: Preserve authentication/account ownership and T61 bounded diagnostics. No payload/key/token/raw exception logging, no live verification or protected configuration access/write.

## 6. Data contract

One retry child is one independently confirmed submission, selecting unique rows of one direct source. Identity is source clientOrderId, never array index or levelId alone. At most10 are selected, normalized into persisted source order.

Server-owned JSON metadata inside child contract:

| Field | Type | Meaning |
|---|---|---|
| kind | fixed string resubmission | Select fixed-order validation; ordinary client contracts cannot inject this mode. |
| resubmission.sourceStrategyId | bounded strategy ID | Direct parent in same account/instrument. |
| resubmission.sourceClientOrderIds | unique ordered string list1..10 | Original selected row identities. |
| resubmission.sourceRevision | keyed digest | Eligibility-relevant source state at review. |
| resubmission.sourceSelectionHash | keyed digest | Immutable selected source payload and evidence binding. |
| resubmission.retryRequestId | random client ID16..64, [A-Za-z0-9_-] | Idempotent draft creation only; never confirmation/execute authority. |

Retain existing contract envelope instrumentId/interval/selectedLevels/entryBySide/leverage/sidePercent/totalMargin for current shared readers, derived server-side. Fixed-order preview dispatch bypasses allocation and entry-nearest validation only; never position/pending/balance/auth guards. Orders carry sourceClientOrderId plus new child clientOrderId. Public lineage summary exposes sourceStrategyId and ordered sourceClientOrderIds; internal account identity/hashes remain private except opaque review digests.

SourceRevision canonicalizes source ID/account/instrument, immutable ordered original financial payloads and eligibility-relevant status/placement/error/attempt/queue marker evidence. Normalize accepted lifecycle states to one ineligible category; normalize allowed non-APPLYING lifecycle distinctions that cannot alter eligibility. Exclude updatedAt, synchronization times, quote times, fill observations and other polling-only fields. Separate live-lease, child-overlap and reservation checks always apply. SourceSelectionHash binds selected tuples to the same safety evidence. Never let polling timestamps alone invalidate a draft.

Fixed-order formulas, Decimal arithmetic:

`unit=contractValue*contractMultiplier`
`notional=contracts*limitPrice*unit`
`margin=notional/leverage`
`openingFeeEstimate=notional*currentTakerFeeRate`
`totalMargin=plannedMargin=sum(margin); unallocatedMargin=0`
`requiredBalance=sum(margin)+sum(openingFeeEstimate)`

Example: source row qty2, price100, unit0.1, leverage5, fee0.001 -> notional20, margin4, opening fee0.02, required balance4.02; exact order price100/qty2/lever5 remain unchanged. Fees follow current existing nonnegative fee conventions.

Recompute cumulative quantity/weighted entry, unique applicable tier, leverage bounds and liquidation estimate per side in preserved order, using existing formulas. Role may remain DCA even when no source entry was selected; no fabricated entry/order is added. Review hash binds account, position mode, lineage/revision/selection, exact fixed rows and resulting financial totals, contract/tick/lot/fee/tier metadata. Quote price/time are excluded from the stable digest but fresh/passive-price validity is independently checked at every preview/preflight.

## 7. Cross-layer mapping

| Semantic | Persistence | API/DTO | UI |
|---|---|---|---|
| New cap10 | admission guards | fresh-order validator | wizard/confirmation/selection counters |
| Legacy20 | existing queue/results JSON | existing readers | history/progress |
| Source eligibility | validated prepared/orders/results and children | retry-candidates | selectable rows and fixed reasons |
| Fixed review | server preview/hash | retry-preview | exact source price/qty/leverage and fresh costs |
| New attempt | child strategy JSON, new client IDs | retry-drafts then existing prepare/execute | linked card and exact confirmation |

## 8. Architecture and atomic lifecycle

`source -> candidates -> selected fixed preview -> idempotent child DRAFT -> PREPARED -> one token claim -> APPLYING -> existing final/reconciliation states`

Add backend/strategy_retry.py for bounded validators/fixed-order calculations/lineage helpers; integrate through StrategyService, existing worker/store interfaces. No schema migration. Parse account-narrowed existing child JSON locally; instrument/source filter before conflict checks, no unsafe truncation or dependence on optional SQLite JSON extensions. Network I/O stays outside transactions.

Creation in BEGIN IMMEDIATE:
1. Scope request ID by account+direct source. If persisted same request/selection/revision/review exists, return that child ID/status without token minting or source mutation; changed payload409.
2. Re-read source; require same revision/selection hash and current eligibility.
3. Reject selected overlap with another DRAFT/PREPARED/APPLYING child, or any child with attemptStarted=1 regardless of outcome.
4. Insert child with server lineage, fresh client IDs and replacement_source_id=NULL.

Prepare and BOTH claim paths re-read source/check conflicts; claims perform the checks in the same existing transaction as token CAS/reservation insertion. Exclude only the current child from its own conflict scan. Once any child claim succeeds, that direct source selection is permanently consumed, including leverage-only failure; retry later comes from that child. Worker initial/resume preflight validates the fixed payload/lineage while excluding itself; no ancestor replay or old client-ID reuse.

Guard source references symmetrically in delete eligibility, canDelete, replacement creation/claim and automatic replacement cleanup. Any claimed retry child is non-deletable/non-replaceable even if orderPlacementAttempted=false. Any source referenced by a persisted retry child is protected. Unclaimed never-sent child can be explicitly deleted under existing safe rules, releasing only unclaimed overlap. Retry source with any persisted ordinary replacement child is blocked because ordinary replacement lacks row lineage; transaction ordering prevents ordinary replacement/retry from both claiming the source.

## 9. Interfaces and contracts

All routes remain authenticated with existing account/origin/body policy.

| Operation | Request | Response |
|---|---|---|
| GET /v1/strategies/{source}/retry-candidates | no body | sourceStrategyId, sourceRevision, ordered candidates, blockedReason, linked child summaries |
| POST /v1/strategies/{source}/retry-preview | sourceRevision, sourceClientOrderIds | sourceStrategyId, sourceRevision, selectedSourceClientOrderIds, fixed preview fields/orders, previewHash |
| POST /v1/strategies/{source}/retry-drafts | prior selection+revision+previewHash+retryRequestId | child id/status/orders and public resubmission summary; replay returns existing child, no confirmation token |
| Existing child prepare/execute | current contracts | frozen mode/exact child orders and resubmission summary, then queued/batch outcome |

Candidate fields: sourceClientOrderId, side, role, limitPrice, contracts, leverage, priorOutcome (fixed not_submitted/rejected/other), eligible boolean, reason (fixed code), optional existing levelId. Include ineligible rows for clear explanation; client must not infer eligibility from raw prior status. malformed candidate/review DTO fails closed. Client cannot send financial values/lineage/kind via retry endpoints; unexpected fields reject. Cardinality/uniqueness/order bindings validated server-side.

Structured errors: existing auth/account/instrument guard errors plus retry_source_unavailable, retry_selection_invalid, retry_source_stale, retry_selection_in_use, retry_request_conflict, retry_preview_stale. Error bodies follow existing safe API contracts; stale review may return authoritative preview but never auto-confirms it. Public lineage contains no credentials/account fingerprint.

Current preference freezes at child prepare, not source mode. Cancellation after child preparation leaves a visible PREPARED child; refresh/expiry (existing TTL) and existing safe deletion of an unclaimed draft permit later recreation. Do not mint another token for idempotent draft replay. On uncertain draft/execute response, fetch candidates/list/result; never auto-replay write requests.

## 10. Invariants

- INV-001: New submission<=10; legacy confirmed20 continues unchanged.
- INV-002: Only trusted not_submitted or definite rejected row can be newly submitted; accepted/unknown/canceled-after-acceptance never selected.
- INV-003: Exact frozen source payloads, fresh client IDs, explicit fresh confirmation and at most one execute write per flow.
- INV-004: Direct-source consumption cannot reopen via descendant cancellation/deletion/replacement; original claimed history remains.
- INV-005: Existing reservations, zero-position/no-pending/balance/mode/passive-price preflight, markers/no-resend/lease/fence/pacing/deadline remain; no source-aware bypass or reservation transfer.
- INV-006: No network/sink I/O inside DB transactions; T61 privacy/nonblocking behavior remains.

## 11. Edge cases and eligibility

Historical batch row with malformed/non-numeric/boolean/stringified-object errorCode is ineligible. Tighten new _parse_batch_ack to bounded numeric nonzero rejection; invalid/missing code remains UNKNOWN with existing conservative semantics, not false rejected. Numeric persisted rejection plus no exchange ID/no positive fill and consistent evidence is strongest available legacy proof; absent evidence fails closed.

Sequential not_submitted requires matching placementState and valid stopped ledger. Selected placement inFlight index/sending/unknown excludes that row. Stopped leverage marker alone does not create order ambiguity, but all normal instrument/lease/reservation guards still apply. Batch never-sent requires no placement/batch marker, including existing safe legacy-never-sent normalization. Unstarted ordinary DRAFT/PREPARED has no retry action; use normal compliant apply/recreate.

Accepted siblings with live pending orders/positions or unresolved reservation block a new attempt. Missing order-details response never becomes definitive rejection. Refresh accepted/unknown outstanding rows read-only before candidate evaluation; no extra exchange write or reconciliation shortcut. Tier/tick/lot/fee/unit change requires fresh review or blocks incompatible exact sizes; no rounding/reallocation. Source deletion during preview/create/claim is fenced by same transaction guards; missing source fails closed.

## 12. Failure semantics

| Failure | Result | Allowed side effect | Forbidden |
|---|---|---|---|
| 11 new orders | existing invalid-order-count rejection | none beyond ordinary reads | truncate/split/claim |
| stale/invalid/consumed source selection | safe4xx | read-only reconciliation | child claim/exchange write |
| quote/positions/pending/reservation/balance block | existing safe preflight error | reads, existing reconciliation | bypass/cancel/order placement |
| identical retryRequestId | existing child | no new draft/token | duplicate child/execute |
| cancel/stale session/malformed prepared ACK | no execute | unclaimed child may remain | auto send/token replay |
| uncertain send/ACK/fence loss | existing UNKNOWN/recovery | read-only refresh and conservative ledger handling | resend or reopen ancestor |

## 13. RED / GREEN

- RED-001 backend cap:11 combined/new and legacy unstarted oversize reject before writes; attempted queues are not reset.
- GREEN-001 backend cap:10 single/mixed works in both modes; seeded legacy confirmed20 finishes; global20/pass remains.
- RED-002 UI cap:11th toggle/forged11 preview/prepared/saved oversize stops while preserving previous10; no save/confirm/execute.
- GREEN-002 UI cap:10/10 mixed selection through single execute; historical20 display.
- RED-003 retry backend: accepted/unknown/canceled/malformed codes, stale/tampered source, concurrent overlap, old ancestor after child claim/deletion/replacement, active ordinary replacement, positions/pending/reservation/metadata/passive-price failure all refuse with zero new placements; no source-history deletion.
- GREEN-003 retry backend: exact eligible subset (including DCA-only) -> fresh costs/hash/new client IDs -> normal batch/queue; one child on idempotent create and one write on duplicate execute; rejected child can be explicitly retried; delete unclaimed child releases overlap; observational polling does not stale-bind.
- RED-004 retry UI: malformed eligibility/11 selected/wrong source or reviewed payload, cancel/logout/account switch/double tap/uncertain response cannot execute again; no accepted/unknown row enters selection.
- GREEN-004 retry UI: select mixed eligible<=10, review exact payload/new mode, confirm one execute, source/new history links and clear preflight blockers; responsive modal.

## 14. Performance

No background retry polling/writes. Additional local lineage scans occur only in retry/deletion/claim paths and are account/instrument filtered; never truncate a safety scan to improve speed. No material throughput target; normal worker budget/pacing remain. Tests use real SQLite transactions and deterministic barriers for concurrent claims.

## 15. Compatibility

Additive retry routes/DTOs and server-owned JSON subtype; ordinary rows unchanged. Legacy missing retry metadata stays ordinary. Backward frontend receives safe cap errors. Unchanged historical20 readers. Old binaries do not understand retry subtype; rollback must not process active retry children with an old worker.

## 16. Security

Current session/account ownership at every endpoint/claim. Source identities must uniquely match same-account stored rows. Server alone constructs payload/lineage; opaque request/digests are not confirmation tokens. Keep sensitive information out of logs/errors and no new exchange write in candidate/preview paths.

## 17. Protected configuration/environment actions

NONE. Agents never inspect or modify manifests/env/container/scripts/CI/protected config. Standard native tests/builds may consume configuration opaquely.

## 18. Rollout / rollback

Operator deploys matching backend/API and worker first, then frontend after implementation approval/audit. Keep source/child rows and no-resend markers. If retry correctness fails, stop starting new retries and retain matching binaries for active retry reconciliation; do not run pre-feature workers on retry subtype or rewrite data. No deployment/commit/push authorization inferred.

## 19. Acceptance

AC-001..004 correspond one-to-one to REQ-001..004 and RED/GREEN-001/002. AC-005 verifies authoritative eligibility and rejection safety; AC-006 verifies exact fixed math/hash/preflight; AC-007 verifies atomic lineage/idempotency/deletion/claims; AC-008 verifies modal/session/one-execute/history; AC-009 verifies ownership/diagnostics/config boundary. All require offline observable tests and source audit, never live orders.

## 20. Traceability

| Requirements | AC | Steps/tasks | Evidence |
|---|---|---|---|
| REQ-001,003,004 | AC-001,003,004 | P01/T62 | RED-001 then GREEN-001 |
| REQ-002,003,004 | AC-002,003,004 | P02/T63 | RED-002 then GREEN-002 |
| REQ-005,006,007,009 | AC-005,006,007,009 | P03/T64 | RED-003 then GREEN-003 |
| REQ-008,009 | AC-008,009 | P04/T65 | RED-004 then GREEN-004 |

## 21. Completion gate

- [x] Material decisions resolved and required fan-out reconciled.
- [x] Contracts/edge behavior/invariants/verification defined; no protected-content evidence.
- [x] Current plan presented and post-plan execution authorized.
- [x] T62..65 independently PASS with RED-before-GREEN and affected-unit builds.
- [x] Final integration audit and final backend/Flutter builds PASS.

## 22. Change log

Revision1 combines confirmed cap legacy semantics with new selective resubmission; supersedes the blocked2026-10-02 cap draft. Baseline at Revision1: implementation had not started.

Revision2: implementation and final integration audited PASS through T62..65. All acceptance criteria have offline evidence; no production exchange execution or deployment performed.
