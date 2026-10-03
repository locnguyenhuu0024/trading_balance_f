# Design Specification: Compact Strategy and Trade Cards
Status: APPROVED
Date: 2026-10-03
Tier: L (authenticated cancellation write)
Decision Ledger: N/A; direct user authorized all bounded product decisions.

## Objective and Evidence
REQ-001: Saved strategy cards show coin, total capital, total order count, and unfilled/filled count; tapping opens live details.
REQ-002: Strategy and position action controls are icon-only, accessible, and named through long-press tooltips; preserve action eligibility and confirmations.
REQ-003: Pending active limit cards allow confirmed cancellation through the authenticated trade operation journal.
OBS-001: strategy_screen.dart:_StrategyCard currently renders detailed metrics/outcomes inline. backend/strategy.py:_public_summary exposes totalMargin and orders.
OBS-002: PositionActionControls uses labels and durable page-independent action flows.
OBS-003: OkxOrder lacks ordId/ordType; trade service operations currently handle positions only.

## Decisions / Scope
A-001 (user-authorized): duplicated unfilled wording means Chưa khớp / Đã khớp. Count explicit live/partially_filled as awaiting and explicit filled as filled; canceled/rejected/unknown/queued/unsubmitted do not imply exchange-pending. Totals cover all saved order rows, including historical >10 rows. Missing list/value displays --; explicit empty list displays 0. Capital uses totalMargin (USDT), never filledMargin. Compact tooltip explains stale/unavailable counts and non-partition semantics.
A-002: Keep icon action footer on summaries and details; full information moves into a scrollable detail modal watching the existing dashboard by captured token + strategy ID. Session change removes old account data/actions; removed strategy shows unavailable notice.
A-003: Create strategy and close-all controls are also icons; confirmation/input dialogs retain textual labels.
A-004: Cancellation removes only remaining quantity; prior fills remain. No automatic retries of writes.
In scope: existing strategy/orders Flutter presentation/tests; additive order identity serialization; backend service/OKX cancellation methods/tests.
Out of scope: protected configuration/environment/dependency files, deploy/commit/push, other features, live trading, dependency/schema changes.

## Cancellation Contract
Reuse POST v1/actions/prepare action cancel_order, existing execute and result endpoints.
targetIdentity = {instType, instId, ordId, ordType, side, px, sz}; bounded nonempty strings; SPOT/MARGIN/SWAP/FUTURES, limit, buy/sell, positive finite decimal px/sz. Client must validate prepared action/one target/identity before confirming/executing.
Server resolves order by instId+ordId under its account, compares all displayed fields (numeric equivalence accepted), requires live/partially_filled with remaining size >0. Read stable account fingerprint before/after authoritative resolution. Store existing journal shape/account binding; conflict cancellation identities by instId+ordId, not mutable price/size.
Add OKXClient.order_details_by_id and cancel_order sending exactly {instId,ordId}; existing clOrdId strategy lookup remains unchanged.
Prepare -> one-use expiring confirmation -> mutation-locked execute -> recheck account and order immutable/fill facts -> ATTEMPT_STARTED durable journal -> one cancel POST -> authoritative read -> existing result response.
Explicit cancellation branches avoid all position/placement fallbacks. Confirmed canceled/mmp_canceled => SUCCEEDED with retained fills; filled => FAILED; still active/unavailable/malformed/ambiguous => UNKNOWN. Known rejection => FAILED with safe code. getResult/crash reconciliation performs reads only and never repeats writes.

## Invariants and Edges
INV-001: Existing strategy eligibility/oversized guards and position authorization/identity/eligibility/unresolved-operation guards remain.
INV-002: No write from long-press, dialog dismissal, missing auth/identity/type, mismatch, stale preflight, expired/wrong confirmation, changed account.
INV-003: Duplicate execute and unknown recovery never duplicate cancel writes.
EDGE-001: Missing values are unavailable, not zero; partial fills remain pending; canceled/rejected/unknown excluded from awaiting.
EDGE-002: Live details track polling and busy state; sign-out/account change/removal cannot expose stale actionable content.
EDGE-003: History/non-limit cards have no cancel action. Refresh/card removal cannot orphan cancellation confirmation or status; pending unknown operation remains available via existing status UI. Serialize with existing account action lock.

## Acceptance / Verification
AC-001 / REQ-001: Requested summary only; tap shows full preserved details and live updates; unavailable/stale/partial state cases truthful.
AC-002 / REQ-002: Icons have semantic Vietnamese labels/48px targets/tooltips; hold does not execute; tap retains flow and guards.
AC-003 / REQ-003: Active authenticated matching limit order confirmation causes one exact cancel request; verified result refreshes pending list; terminal/invalid/session changed cases never write; unknowns remain tracked.
RED-001 then GREEN-001: UI disabled/long-press/session/oversized boundaries then summary/detail/icon success.
RED-002 then GREEN-002: Backend invalid/stale/account/fill/duplicate/timeout boundaries then confirmed SPOT/derivative and partial-filled cancellation success.
RED-003 then GREEN-003: Client nonlimit/history/missing identity/prepared mismatch/dismiss/session/doubletap boundaries then confirmed success/list refresh and unknown persistence.
Tests: focused Flutter strategy/orders groups; offline unittest trade API and relevant regressions. No live exchange writes.

## Compatibility / Rollout / Security
Additive DTO defaults preserve old JSON. No migration/config/environment action. Deploy backend before enabling frontend cancellation; old server rejects unsupported action safely. Deploy is outside current request. Rollback release code through normal user-owned deployment; already journaled operations must retain read-only reconciliation support until resolved.
Existing auth, one-use tokens, expiry, account fingerprint, durable journal and operation status access remain enforced. No secrets/config read or edits.
Performance: no extra dashboard polling loop; modal shares existing controller.
Completion: all tasks PASS, RED before GREEN, affected builds and final integration build PASS, status/diff explained.
