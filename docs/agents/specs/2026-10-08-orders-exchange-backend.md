# Design Specification: Orders exchange read pressure
Status: READY_FOR_PLAN
Date: 2026-10-08
Tier: L
Decision Ledger: docs/agents/decisions/2026-10-08-orders-exchange-backend.md

## Objective and current evidence
Reduce exchange calls for Open Positions without weakening account/session isolation.
OBS-001: backend/service.py::_fetch_display_snapshot fans out three private position reads and forces identity after collecting public metadata.
OBS-002: backend/data_gateway.py::_read_cached forces identity for each private miss; _identity_snapshot(force=True) serializes but does not reuse completed forced checks.
REP-001: Offline fake-exchange service/gateway measurement: cold request = 5 config + 3 positions + 3 instruments (11 calls); five-second refresh = 5 config + 3 positions (8 calls).
REP-002: Controlled postcheck-429 race returned leader 429 and follower 409. Subsequent identity reads ignored the previous Retry-After interval.
HYP-001: This excess traffic contributes to the deployed limit error. Production HTTP status/endpoint is unobserved; offline evidence establishes the defect, not the complete production cause.
User confirms Open Positions is affected and both deployments include 4dbd004 (D-001).

## Scope and requirements
REQ-001: Acquire a fixed MARGIN/SWAP/FUTURES display-position bundle using one common pre-identity proof, parallel private acquisitions, and one forced post-identity proof that starts after ALL private acquisitions complete.
REQ-002: Coalesce concurrent bundle callers in the existing bounded private cache/inflight domain. Preserve caller-specific authorization and fail closed on identity change, invalidation or stale data.
REQ-003: Identity-read 429 establishes instance-wide display cooldown. During it, perform zero identity exchange calls, propagate causal 429 to affected shared readers and return remaining Retry-After. Uncached action/strategy reads retain their existing semantics.
REQ-004: Preserve API output, position normalization, public metadata TTL/admission limits and exactly one service-owned freshness retry.

## Data and interface contracts
GET /v1/positions response fields and normalization remain compatible. No schema, dependency or configuration change.
Internal bundle returns all three raw position groups, account identity/generation and earliest acquisition deadline. Its private key includes fingerprint + generation and is distinct from standalone position cache keys. Existing standalone APIs remain compatible.
Public metadata continues through existing instruments reads/cache. Normalization remains service-owned.

## Proposed design
Authorized caller -> pre-identity (reuse at most 1 second) -> bounded shared bundle flight -> three parallel private acquisitions -> forced post-identity -> staged bundle validation/publication -> public metadata/normalization -> final caller authorization/identity/deadline checks -> response.
The gateway owns the bundle acquisition and shared observations; it must not capture a leader's environment/session authority in shared work. Each caller validates before admission, after waiting, on errors and before return.
Capture each child deadline immediately at acquisition completion, using the existing one-second private TTL. Publish deep copies only if all child deadlines remain valid and fingerprint/generation match. Final freshness uses the earliest child deadline. No successful error cache.
The bundle is separate from standalone child entries; avoid a new unbounded cache or staged child-flight redesign. Mixed reads must remain isolated and safe.
Unlike the former ordering, post-identity now runs after private acquisition, before completion of public metadata. Final publication uses the permitted one-second identity reuse and generation fence; no redundant forced check after public metadata.
Cooldown uses monotonic deadlines; accept a valid Retry-After duration or HTTP date and convert to remaining seconds (ceil). Invalid/missing values use the existing one-second fallback. Do not shorten an active deadline. Retain only sanitized rate-limit metadata. Generation changes cannot bypass cooldown. On expiry, coalesce recovery verification; errors are never stored as successful identity/data.

## Invariants and edge cases
INV-001: A cached identity is at most one second old; postcheck upstream START follows every private acquisition completion. Deadline starts at acquisition, never publication.
INV-002: Every caller has independent session validation. Revoked caller receives 401 even when shared success/error exists; revoked leader cannot poison an authorized follower.
INV-003: Explicit action/account invalidation atomically fences staged bundles and followers with 409. Causal identity 429 survives its own invalidation; a subsequent independent invalidation may supersede it with 409.
INV-004: Existing cache/inflight/read admission bounds, deep copies and uncached action/strategy freshness remain intact. No lock-held network wait or executor recursion deadlock.
INV-005: Only service owns the one freshness refresh: maximum two bundle attempts. Partial sibling failure, identity error, 429, 401 or 409 never trigger freshness retry.
EDGE-001: Account switches after private acquisition or during final publication -> 409, no data/cache leakage.
EDGE-002: Partial sibling failure -> cancel/drain safely, release admission, no partial publication.
EDGE-003: Mixed standalone/bundle readers -> existing fence semantics; display cooldown also suppresses standalone display identity requests.
EDGE-004: Slow public metadata expires earliest private deadline -> at most one freshness refresh, then 503 data_stale.

## Failure semantics
429 exchange_rate_limited: preserve causal error for followers, cooldown, no success cache or automatic immediate retry.
401 revoked session: caller-local, no other caller failure.
409 account_changed: independent invalidation dominates old observations.
503 data_stale: only freshness retry, exactly one.
Other exchange errors: preserve existing mapped errors, no success cache.

## Behavioral and performance acceptance
AC-001 / GREEN-001: Normal cold attempt <=2 config + 3 positions + 3 instruments; refresh after five seconds <=2 config + 3 positions, with warm instruments. Concurrent cold callers share one bundle. Counts exclude the permitted second freshness attempt and unrelated callers/endpoints.
AC-002 / RED-001: Two authorized callers encountering identity 429 receive causal 429; requests during Retry-After cause zero identity exchange reads. One shared recovery after expiry.
AC-003 / RED-002: Account invalidation/revocation/expired acquisition data cannot publish success; valid follower of revoked leader remains authorized.
AC-004 / GREEN-002: Existing normalized results/API, bounded resources and uncached action/strategy reads remain compatible; deterministic slow-data test proves at most two bundle attempts.
Measurement uses fake exchange counters, barriers and controlled clock, never live account calls. Existing baseline: 32 gateway tests pass.

## Security, rollout and risks
No protected configuration content access/writes; no live exchange request, deployment or external upload in this task.
Scope is one backend instance. Other processes/clients and exchange policy may still cause 429; this reduces pressure and observes cooldown rather than guaranteeing zero exchange limits.
Rollout after separate authorization: deploy tested backend build; frontend stays compatible. Roll back backend artifact if position correctness, authorization or freshness regressions occur. No migration or persisted data change.

## Traceability and completion
REQ-001 -> AC-001 -> GREEN-001; REQ-002 -> AC-003 -> RED-002; REQ-003 -> AC-002 -> RED-001; REQ-004 -> AC-004 -> GREEN-002.
All material questions resolved for offline implementation; production origin remains explicitly unverified.
Planning safety/performance fan-in reconciled. Code execution requires approval of the linked plan/task.
