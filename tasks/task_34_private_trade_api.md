# Task 34 — Private Python trade API

Status: PASS
Agent Role: implementation_executor
Executor Class: E2
Target Model: gpt-6-luna
Target Effort: max
Target Route: gpt-6-luna / max
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Dispatch Route Status: UNVERIFIABLE
Specification: `docs/agents/specs/2026-09-30-position-actions-design.md`
Plan: `docs/agents/plans/2026-09-30-live-position-actions.md`
Plan Steps: P01
Requirements: REQ-001..009
Acceptance Criteria: AC-001..009 (server portions)

## Objective

Implement the dependency-free Python WSGI trade API, fake-transport tests, and deployment guide according to P01. This task must be independently runnable with no production secret, network access, or protected configuration edit.

Predecessors: none. Governing user decisions: D-001..015. Allowed writes: new `backend/*.py`, new `backend/tests/*.py`, and `docs/deployment/position-trade-api.md` only. No protected configuration/environment contents may be read or files written. Do not write `requirements.txt`, `.env`, Dockerfile, Compose, CI/deploy config, or Flutter code. Do not execute live OKX requests, commit, push, or deploy.

## Contract

1. Implement spec §4..9 and P01's exact JSON routes, server-only Trade signer, safe prepared-operation journal, account-owned positions, authentication, and per-target status/reconciliation. Use `Decimal` for trade sizes and exact documented OKX product/mode eligibility. Fail closed on unknown metadata, MARGIN size units, and close-all ineligible targets. Persist attempts before network calls and return stored state on duplicate execute.
2. Add a user-run helper for generating password hash, TOTP seed, and session key without printing them during agent tests. Tests use fixed disposable values. The guide states all user-owned environment fields and gives the plan §3 Dockerfile recipe and exact container run command for an Ubuntu 24.04 LTS host, Python runtime image, single production WSGI worker, UID 10001 writable persistent SQLite mount, loopback-only exposure to HTTPS, distinct web/API origins, no Withdraw permission, optional fixed-IP restriction, startup/restart/rollback, and a safe small first-trade verification process. The guide must not contain real credentials or instruct baking them into the image. It must check `GET /v1/health`, allowed/denied origins, backend positions, and persistence of operation/TOTP replay state after container restart.
3. Use one process/worker deployment until storage concurrency has been verified. Never log password, TOTP, Trade credentials, signatures, bearer tokens, or business payloads.

## Verification

Formal RED-001: with fake transport, invalid/replayed TOTP, stale position, duplicate execute, MARGIN inexact size, or ineligible close-all yields no unintended OKX write. Formal GREEN-001: valid login and prepared eligible actions produce exactly the documented fake requests and verified per-target outcomes. Run RED then GREEN after implementation stabilizes; narrow diagnostics may precede the checkpoint. V2 ceiling: all backend tests; escalate only on a concrete cross-path failure.

- `python3 -m unittest discover -s backend/tests -v` — behavior tests, including restart/replay, 401/429, timeout/UNKNOWN, top-level/item-level OKX error, close-all drift, and partial outcome.
- Task buildability gate: `python3 -m compileall -q backend` after the final task-local executable change. Record exact exit/status. A passing unit test does not substitute for this gate.

External configuration: user-owned `/etc/trading-balance/trade-api.env` with keys and placeholders in plan §3; user-owned `backend/Dockerfile` applied from the guide; future Ubuntu 24.04 LTS Docker/HTTPS host, persistent journal directory, and Trade-enabled key. These do not block local code/test completion; they block live production verification. Stop and report BLOCKED if the standard-library approach cannot safely meet the approved auth/idempotency contract or needs a protected dependency/configuration write.

## Coordinator audit

Scope: PASS — `backend/settings.py` and `backend/setup.py` were deleted under the user's explicit authorization without reading their contents; no protected path remains in `backend/`. Acceptance: PASS for the local fake-transport contract after R03, AUD-034-006, account-UID binding, and close-all aggregate/final-account remediation. RED-before-GREEN: PASS (initial 20 then 9, plus focused failing regressions before each audit fix); final affected suite 42 PASS on Python 3.12. Buildability: PASS — Python 3.12 `compileall -q backend` passed after the final backend edit; coordinator also verified with `PYTHONPYCACHEPREFIX=/private/tmp/t34-final-build-cache python3.12 -m compileall -q backend` (exit 0). A redundant coordinator test rerun was blocked by automatic approval review usage limits for the local WSGI loopback; the executor's post-edit full-suite result and independent final-guard audit remain valid evidence. Route compliance: UNVERIFIABLE after explicit binding. Verdict: PASS. Live production verification remains user-owned per the approved deliverable.

- AUD-034-001: An OKX top-level success with missing/malformed item acknowledgement is classified as definite failure. Treat the mutation outcome as UNKNOWN and block a replacement action pending reconciliation; add a fake-transport case.
- AUD-034-002: A canceled order with nonzero `accFillSz` is classified as no fill. Preserve and report partial execution in immediate and later reconciliation; add a fake-transport case.
- AUD-034-003: A `PARTIAL` order result remains blocked forever because the result route does not revisit it. Reconcile progression to filled/canceled terminal state without sending another write; add a fake-transport case.
- AUD-034-004: The deployment guide creates the environment file without first creating `/etc/trading-balance`; make the user-owned command sequence complete. Add an assertion that full-close requests include `autoCxl=true`.
- AUD-034-005: R01 rechecks `PARTIAL` market orders, but a partially filled canceled order remains `PARTIAL` and `_pending_target_conflict` treats all `PARTIAL` results as unresolved. This blocks every later action on that position even after OKX reports a terminal cancellation. Preserve the partial outcome while distinguishing terminal canceled/rejected-with-fill from still-working partial orders; a fresh prepare may proceed only after terminal exchange state and current position are verified. Add a regression case for the later prepare and zero duplicate writes.

## Validation remediation R03

Implement VAL-001..003 from `docs/agents/plans/2026-09-30-live-position-actions-validation.md` on originally allowed non-protected backend source/tests only. MARGIN `pos` is positive even for shorts; derive direction from valid `posCcy` versus instrument base/quote metadata. Do not fall back when `posCcy` is missing. MARGIN order `ccy` is confirmed margin currency. Disable MARGIN DCA and partial close in this release with explicit eligibility reasons, retaining eligible add-margin and full close. Reconcile interrupted `IN_PROGRESS` rows with `PENDING` targets as unattempted/conflicted after restart, never resend. Tests use realistic MARGIN long/short and restart fixtures. Preserve all prior RED/GREEN behavior and rerun affected checkpoints. Exact whole-backend compile gate remains pending protected-path cleanup.

- AUD-034-006: The deployment guide still says MARGIN short DCA is supported, contradicting VAL-002 and the current backend behavior. Update only that guide sentence to state MARGIN DCA and partial close are disabled in this release. This documentation-only remediation does not invalidate backend test evidence.

## Final security audit remediation

- AUD-034-007: Bind prepared operations to an HMAC fingerprint of the full OKX account UID. Reject missing UID and legacy unbound journals; verify the account before each write and during result reconciliation. Focused changed-account, missing-UID, legacy, and close-all-switch regressions passed.
- AUD-034-008: Reconcile synthetic close-all UNKNOWN rows after a later same-account full-position query. Retain uncertainty while a supported position remains, and never send an exchange write from status lookup. Focused transient-query and unconfirmed-position regressions passed.
- AUD-034-009: A changed account at final close-all verification or an interrupted all-targets-SUCCEEDED journal cannot become overall SUCCEEDED without a same-account final snapshot. Two focused regressions and the independent final-guard audit passed.
