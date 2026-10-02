# Implementation Plan: Never-Sent Strategy Replacement

Status: READY_FOR_APPROVAL
Date: 2026-10-02
Tier: L
Specification: `docs/agents/specs/2026-10-02-strategy-never-sent-replacement.md`
Decision Ledger: `docs/agents/decisions/2026-10-02-strategy-never-sent-replacement.md`

## 1. Objective and preconditions

Implement REQ-001 through REQ-004 and AC-001 through AC-006. Execution requires user authorization after this plan is presented. Existing T53–T55 dirty documentation and task files are unrelated and must be preserved. No protected configuration file is read or written. No external configuration action is required. Production deployment and any database backup/restoration remain user-run.

## 2. Planning workstreams

| Workstream | Material | Independent | Route | Logical run | Result |
|---|---|---|---|---|---|
| Backend/API, DB and worker | YES | YES | R2 / gpt-6-sol / medium | replacement-backend-01 | COMPLETE / USED |
| Frontend/UI flow | YES | YES | R2 / gpt-6-sol / medium | replacement-frontend-01 | COMPLETE / USED |
| External OKX rejection reason | NO, bounded by API data contract | N/A | N/A | N/A | Current historical code unavailable |

Fan-out Required: YES
Required Reasoning Agents: 2
Actual Reasoning Agents: 2
Fan-out Compliance: PASS
Skip Reason: N/A

Cross-workstream synthesis: the server alone computes eligibility; the UI uses it only to show actions. The wizard fetches fresh candles and produces a new draft. The backend records the replacement association and owns conditional cleanup after complete acceptance.

## 3. Impact and dependency graph

```text
T56 backend contract, worker and persistence -> T57 frontend flow -> integration audit
```

| Task | Main files | Executor route |
|---|---|---|
| T56 | `backend/strategy.py`, `backend/strategy_worker.py`, `backend/okx.py`, `backend/store.py`, focused backend tests | E2 / gpt-6-luna / max |
| T57 | `lib/features/strategy/data/strategy_api_client.dart`, provider, screen, wizard and focused Flutter tests | E1 / gpt-6-luna / xhigh |

Any other source file requires coordinator re-scope before mutation. Protected configuration and environment files are forbidden write surfaces.

## 4. Ordered implementation

### P01 — Backend eligibility, result and exchange diagnostics (T56)

1. Add a single account-scoped eligibility predicate for never-batched, all-`not_submitted`, non-applying strategies; use it for `canDelete`, replacement association validation and guarded transactional deletion.
2. Preserve `failureReason` and prevent false `COMPLETED` in worker. Project old false-completed records as never sent in API results. Do not scan non-batched terminal failures as if exchange orders were live.
3. Retain only bounded OKX leverage error codes, without raw exchange messages.
4. Persist a nullable replacement source link on a new draft. Use new client order IDs and current preview/prepare data. On full batch acceptance, guarded-delete the old row and its reservation/sync rows; carry this rule through interrupted-apply reconciliation. Never delete old on partial/unknown result.
5. RED: reproduce leverage-rejected/no-batch false completion and unsafe delete/duplicate-send attempts in focused tests. GREEN: prove corrected state, eligibility and full-acceptance cleanup with one batch write.

### P02 — User-visible replacement flow (T57)

1. Add a `Tạo lại` action only when the server marks the source eligible. Open the existing wizard with replacement source context, fetch fresh candles and require new level selection; do not preselect old levels.
2. Reuse the server preview/prepare confirmation dialog and one execute call. Show `Xóa chiến thuật` for `canDelete` rows and explain that deletion removes the local record only.
3. For never-batched leverage rejection, show `Không có lệnh nào được gửi lên OKX` and the safe rejection code when available; suppress stale order-scan text. Show a cleanup warning if the server reports that a fully accepted replacement could not remove its old source.
4. RED: widget/controller cases for absent eligibility, canceled confirmation, duplicate tap, and legacy false-completed display. GREEN: fresh wizard selection, one confirmed execute, and old-row removal reflected after success.

## 5. Verification and audit

| Test | Contract | Command/method |
|---|---|---|
| TEST-001 | AC-001, AC-002, AC-004, AC-005, AC-006 | `python -m unittest backend.tests.test_strategy_api backend.tests.test_strategy_worker` with Python 3.12 runtime |
| TEST-002 | AC-001, AC-003, AC-004 | `flutter test test/features/strategy/strategy_api_client_test.dart test/features/strategy/strategy_dashboard_controller_test.dart test/features/strategy/strategy_screen_test.dart test/features/strategy/strategy_wizard_dialog_test.dart` |
| TEST-003 | Backend canonical buildability | `python -m compileall -q backend` |
| TEST-004 | Web canonical buildability | `flutter build web --release` |

Formal per-task RED then GREEN checkpoint is required, followed by affected build after the last code/test edit. The Codex Flutter runtime previously hung; if that repeats, use the exact user-run commands above and accept exit code plus concise result as external evidence. Audit name-only Git status first, then only non-protected diffs. Audit production safety predicates and replace-source cleanup independently. Do not deploy, delete production data, commit or push under this plan.

## 6. Rollout, rollback and limitations

Release API and worker together before enabling the web action. Existing production row is read through compatibility projection; the new delete action can remove it once server eligibility is true. The old strategy remains when the new batch is partial or uncertain. OKX leverage rejection may repeat until its separate exchange/account cause is resolved; this plan makes the next code visible but does not claim to fix that external rejection.
