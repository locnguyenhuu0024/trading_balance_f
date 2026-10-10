# Task 117 — T110 final-audit remediation

Status: SOURCE_REMEDIATION_PASS — independent source audit accepted; parent real-runtime verification pending
Agent Role: implementation_executor
Executor Class: E1
Target Model: gpt-6-luna
Target Effort: xhigh
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Dispatch Route Status: UNVERIFIABLE
Requested Model / Effort: gpt-6-luna / xhigh
Observed Effective Model / Effort: unavailable
Parent task: T110; specification/plan revision 1 unchanged.
Dependencies: T110 writer result collected; preliminary final audit REWORK. No other writer is active.

## Contract and allowed surface

Write only `backend/auth.py`, `backend/service.py`, `backend/tests/test_multiuser_auth.py`, `backend/tests/test_multiuser_store.py`.

- AUD-110-07: Cookie-mode GET /v2/session must not rotate the CSRF token or write csrf_hash on every read. Use the existing keyed token-digest helper with a distinct purpose/session-ID binding to derive a stable per-session CSRF secret. Persist only its hash at session issuance; return the same secret from login/activation/restore after read-only current persisted authority validation. No session bearer in web JSON. Retain idle last-seen debounce. Concurrent restores must not invalidate a prepared legitimate POST; no extra writes inside the debounce interval.
- AUD-110-08: PostgreSQL enrollment/recovery race test must accept exactly both safe serialization orders: completion succeeds, competing old recovery code gets 401, final ACTIVE; or recovery succeeds, stale completion gets 401, final MFA_RECOVERY. Reject both-success and verify MFA/recovery material matches the winning transition. Use the explicit dedicated DB only; local SQLite evidence does not replace real PG.

No product semantic expansion, protected content access/writes, dependencies/install, VPS/live network, docs/tasks/telemetry/Git mutations or subagents. Fabricated local test cipher remains test-only; real AES/PG verification remains pending. RTK-first eligible output; narrow raw exact source/evidence allowed.

## Verification

Meaningful baseline regression for unstable CSRF, observed before correction. Formal RED: repeated/concurrent restores leave a prior valid POST authorized, forged/missing CSRF denied and no csrf/session-write regression within debounce. GREEN: ordinary web restore/enrollment succeeds with stable CSRF token. Observe negative before positive; exact commands/results required. Focused full auth/store suites after final changes. Reuse prior unaffected legacy V3: 68 tests total, 64 pass/4 skips, observed by coordinator before remediation; rerun legacy only if changed code can affect those routes. Build after final executable change: `python3.12 -m compileall -q backend`. Independent source audit required; full task PASS withheld pending actual PG/AES runtime evidence.

- [x] Explicit E1 dispatch.
- [x] Baseline regression and source corrections.
- [x] Formal RED then GREEN and auth/store regression.
- [x] Final backend build.
- [x] Independent audit; runtime limitations recorded.

## Evidence

Baseline CSRF regression failed before correction: GET restore opened a transaction. Final formal negative CSRF contract passed before activation/restore/enrollment GREEN, each one test. Auth/store 19 total, 15 passes/four runtime skips; compileall exit 0. Independent R3 source audit PASS for AUD-110-07/08; no remaining actionable source finding. Coordinator reproduced suite and final build. Real AES and three PostgreSQL checks remain pending under T110; PostgreSQL oracle correction has not been verified against a real database.
