# Task 53 — Background read-only strategy order worker

Status: PASS
Agent Role: implementation_executor
Executor Class: E2
Target Model: gpt-6-luna
Target Effort: max
Target Route: gpt-6-luna / max
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Dispatch Route Status: UNVERIFIABLE (explicit model/effort bound; runtime effective route unavailable)
Specification: `docs/agents/specs/2026-10-02-strategy-background-order-monitor.md`
Plan: `docs/agents/plans/2026-10-02-strategy-background-order-monitor.md`, P01
Requirements: REQ-001–003, REQ-006
Acceptance Criteria: AC-001–003, AC-006

## 1. Objective and preconditions

After current-plan execution authorization, implement a separately runnable backend worker that checks already-submitted OKX limit orders every 5 seconds when healthy, persists validated partial/full/terminal states, and marks COMPLETED only after all orders are terminal and a fresh positions read proves no remaining instrument position. The worker never places, amends, or cancels exchange orders. Preserve existing upfront Apply batch placement for all selected Long/Short entry/DCA rows as `ordType=limit`.

No predecessor task. Dispatch must explicitly bind `implementation_executor`, `gpt-6-luna`, and `max`; no inherited route. Runtime effective route may be recorded `UNVERIFIABLE` only after explicit binding. The user-owned worker env file is an external production action, not an executor write.

## 2. Allowed and forbidden scope

Allowed writes only: `backend/store.py`, `backend/strategy.py`, `backend/strategy_worker.py` (new), `backend/tests/test_strategy_api.py`, `backend/tests/test_strategy_worker.py` (new). No other product/test/config/migration/Docker/dependency files. Do not inspect protected configuration contents, change auth/quote wizard/UI, call live order APIs, deploy, commit, push, or edit planning/task/telemetry files. Return BLOCKED if a hard contract needs more scope or user decision.

## 3. Executor contract

1. Add RED tests for absence of autonomous sync and one-backend-only monitor. Observe them before implementation.
2. Add SQLite lease/fence and per-strategy scan metadata without losing old strategies; do not hold a DB transaction across network calls.
3. Add minimal worker settings for only `OKX_API_KEY`, `OKX_API_SECRET`, `OKX_API_PASSPHRASE`, `SESSION_SIGNING_KEY`, `OPERATION_DB_PATH`; verify OKX account fingerprint. Reuse the existing order identity/size/fill/state validation and CAS semantics.
4. Reconcile `accepted`/`live`/`partially_filled`/`unknown` orders, persist exact filled quantity and average price, retain last good state on error, back off/rate-bound. Recover after restart/lease expiry. Query positions only for completion; no completion on unknown order or failed positions read.
5. Keep API GET reconciliation as stale-worker fallback; expose `lastOrderScanAt` and `orderSyncState` in list/result. Keep all selected limit order submissions in the existing Apply batch and test their exact `ordType`, side, price, and size.

Required invariants: INV-001–005 in spec. A stale worker cannot write after losing its lease; no worker code path invokes an OKX trade write. Existing draft/prepare/execute state machine and account isolation remain intact.

## 4. RED / GREEN and buildability

RED-001/002/003: fake OKX fill with no browser GET does not update DB; duplicate worker/restart and completion scenarios are not yet handled. Run the narrowest new focused tests before implementation and record exact actual failures.

GREEN-001/002/003: partial/full statuses persist, only active owner writes, errors remain stale, restart resumes, and completion requires terminal orders plus fresh zero-position proof. GREEN-006: existing fake OKX Apply still sends all reviewed Long/Short entry and DCA rows once as `ordType=limit`; worker makes zero trade writes. Run focused tests then `python3.12 -m unittest backend.tests.test_strategy_api backend.tests.test_strategy_worker -v` as V2. Escalate only for concrete related regressions.

Task buildability: REQUIRED, affected canonical unit Python backend, exact command `python3.12 -m compileall -q backend` after final code/test edit. Record exit and whether the build actually executed. No external verification for offline acceptance. External configuration action: user creates `/etc/trading-balance/trade-api-worker.env` with the five approved keys privately; no executor write. The original home-directory target was superseded after the observed `sudoedit` refusal. Production operation remains unverified until user deploys.

## 5. Coordinator audit

Scope: PASS. Lease/fence: PASS. Account isolation: PASS. Apply limit placement preserved: PASS. Zero worker writes: PASS. RED-before-GREEN: PASS. Task buildability: PASS. Route compliance: PASS (explicit binding, effective route unavailable). Verdict: PASS. See `docs/agents/audits/2026-10-02-task-53-strategy-background-order-worker.md`.
