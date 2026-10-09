# Orders and Portfolio foreground refresh

Status: READY_FOR_PLAN
Date: 2026-10-08
Tier: M

## Objective and evidence
Reduce foreground API request amplification and replace Portfolio startup/retry error flashes with loading.
OBS-001: orders_screen.dart polls single filters every second and ALL every five seconds. Authenticated positions use tradePositionsProvider for a full snapshot; filtering is local.
OBS-002: portfolio_screen.dart polls every second. portfolioFutureProvider throws session_loading during restoration; the screen renders it as a connection error. AsyncValue can retain a prior error while retrying.
OBS-003: backend/service.py /v1/positions reads three position groups with additional forced identity checks. This read route does not consume the action-rate budget. Request amplification is confirmed by source; the deployed 429 origin has not been reproduced.
OBS-004: repositories lose HTTP429/header metadata; TradeApiException retains status but loses Retry-After. Full TradeSessionState watches can refetch after operation-only changes.

## Proposed requirements — approval pending
REQ-001 / AC-001: Use a five-second automatic refresh interval for Portfolio and every Orders filter. Never overlap reads for the same session/request key. Skip automatic refresh while authentication is restoring or absent; SPOT open positions still makes no request.
REQ-002 / AC-002: On transient read failures, next eligible attempt is delayed by 10,20,40,60 seconds on consecutive failures; success resets the counter. HTTP429 additionally respects a valid Retry-After, including values above60 seconds. Accept nonnegative delta seconds or a valid HTTP date; malformed values fall back to local delay. Cooldown applies to automatic/manual reads and screen re-entry, survives widget disposal, and resets on semantic session replacement/logout. No retries occur in the background merely because a screen was disposed. Authentication/configuration failures do not enter a retry loop.
REQ-003 / AC-003: Portfolio with no successful data shows the existing spinner while session restoration or an initial/retry read is pending (including cooldown wait). A completed real failure still shows its error. Successful balance remains displayed while a refresh is pending. Completed refresh failures retain the existing error behavior; no indefinite blanket loading.
REQ-004 / AC-004: Operation-only session state updates do not trigger private reads. Session/authentication changes still reload data and reject stale results. Preserve order filtering, position actions, confirmation flows, currency display and manual/action refresh after successful reads.

## Design and boundaries
A session-scoped foreground read gate, retained in ProviderScope independently of widgets, owns per-request-key in-flight coalescing, failure count and next eligible attempt. Keys distinguish balance, authenticated positions snapshot, raw positions/filter, pending/filter and history/filter. Authenticated positions uses one key across UI filters. Gate stores no credentials in keys/logs; scope is current BackendDataSession generation. Waiting callers must check generation/authentication before starting transport; old-generation completions cannot modify the new generation's gate state. Transport/provider lifecycle checks prevent sending a read for a disposed caller; a shared active caller may keep the coalesced read alive. The gate schedules no autonomous retry. Successful reads are not cached by this change, so manual/action invalidation remains fresh outside an active request/cooldown.
Optional retryAfter metadata is added to existing exception types. Data and trade HTTP transports preserve it, with localized repository error messages retained. Do not change POST/action retry behavior. Select session loading/identity fields for the four foreground providers rather than the full operation state.
UI rendering guard is explicitly based on no successful value plus session/loading status, before AsyncValue.when.

## Verification contract
RED-001: delayed session restoration, completed error followed by pending retry,429 cooldown, disposed/re-entered widgets, overlapping/manual reads and stale session replacement must never produce error flashes, early/duplicate transport calls or stale data respectively.
GREEN-001: successful initial data, one automatic refresh at5s, ordinary manual/action refresh, successful retry/reset and unchanged filter/currency/action rendering.
Use fake time and fake transports; test Retry-After120s and10/20/40/60 progression. Execute formal negative cases before primary success cases. No production calls or exchange actions.

## Compatibility, security and rollout
No backend/API payload/schema/dependency/protected configuration change. Optional exception metadata is backward compatible. Existing session fencing and authorization stay intact. No external configuration action. Deploy only after verified implementation and separate deployment authorization; this task does not deploy. Local rollback is removal of the approved source change, without data migration.
Residual risk: slower automatic display updates (5s); upstream limits shared with other clients/workers can still cause429. A production trace may be needed if rate limiting persists after mitigation.
Traceability: REQ/AC001-004 -> plan P01 -> T98 -> RED001/GREEN001 -> coordinator audit.
