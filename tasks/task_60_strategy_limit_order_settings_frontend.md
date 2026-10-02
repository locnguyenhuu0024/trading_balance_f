# Task 60 — Strategy Limit Order Settings Frontend

Status: PASS
Agent Role: implementation_executor
Executor Class: E1
Target Model: gpt-6-luna
Target Effort: xhigh
Target Route: gpt-6-luna / xhigh
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Specification: `docs/agents/specs/2026-10-02-strategy-limit-order-queue-design.md`
Plan: `docs/agents/plans/2026-10-02-strategy-limit-order-queue.md`
Plan Steps: P04
Requirements: REQ-001, REQ-003, REQ-008
Acceptance Criteria: AC-001, AC-002, AC-007 (client portions)

## Dispatch and preconditions

Requires current-plan execution approval and T59=PASS. Explicit E1 model+effort binding mandatory. Dispatch Route Status: UNVERIFIABLE. Requested Model/Effort: gpt-6-luna / xhigh. Effective Model/Effort: unavailable until exposed. Inherited/default routes and mismatches cannot be accepted.

## Objective and allowed surface

Add responsive strategy Settings with persistent account mechanism selection, frozen confirmation mode, and honest queue outcomes/progress.

Allowed writes:
- `lib/features/strategy/data/strategy_api_client.dart`
- `lib/features/strategy/domain/strategy_models.dart`
- `lib/features/strategy/presentation/providers/strategy_dashboard_provider.dart`
- `lib/features/strategy/presentation/strategy_screen.dart`
- `lib/features/strategy/presentation/strategy_wizard_dialog.dart`
- new `lib/features/strategy/presentation/strategy_settings_dialog.dart`
- `test/features/strategy/strategy_api_client_test.dart`
- `test/features/strategy/strategy_dashboard_controller_test.dart`
- `test/features/strategy/strategy_screen_test.dart`
- `test/features/strategy/strategy_wizard_dialog_test.dart`
- new `test/features/strategy/strategy_settings_dialog_test.dart`

No protected configuration read/write, dependency changes, unrelated navigation/global settings, generated source modifications, deployment, live trades, or Git mutations. Planning/checklist/audit/telemetry are coordinator-owned. Builds may consume existing protected inputs opaquely. Stop if another write surface is necessary.

## Executor contract

1. Add API preference GET/POST `/v1/strategies/settings`, field `limitOrderSubmissionMode` sequential|batch. Validate responses and preserve auth/errors. Update all StrategyApi fakes in allowed tests so this unit builds coherently.
2. Add bearer-scoped preference state to existing dashboard controller, with loading/saving/error and generation/disposal guards. Backend default is authoritative; do not silently claim a saved default when GET fails. No device-global preference persistence.
3. Add AppBar `Cài đặt` action with stable key `strategy-settings-button`. Open `Cài đặt chiến thuật` modal with constrained mobile/desktop size, scrolling content and expandable first item `Cơ chế gửi lệnh limit`. Radio choices `Hàng đợi tuần tự` / `Gửi theo lô`, explanation of ACK-based advancement, `Lưu`/`Hủy`. No invented additional settings. Signed-out modal provides login explanation with saving unavailable.
4. Load persisted value; retain edited draft on save failure, disable duplicate saves while busy, show only acknowledged save success. Cancel discards unsaved selection. Owned routes/actions become disabled or close on logout/account switch; late results cannot leak to another account.
5. Both saved-draft and wizard confirmations show validated server `submissionMode` and mechanism explanation. Missing/invalid prepared mode blocks execute. Never substitute current preference for frozen mode. Guard disposal/session ownership after prepare and confirmation awaits immediately before execute.
6. Add queued apply outcome for an acknowledged sequential APPLYING queue; do not interpret enqueue as fully applied. Keep existing uncertain-response no-retry behavior. Wizard can close with a clear queued message once durable enqueue is acknowledged.
7. Show frozen mode on prepared/applied cards and queueStatus/queueProgress while APPLYING and afterward. Render individual rows for queued/sending/accepted/rejected/unknown/not_submitted plus existing fills. Preserve placementState provenance; accepted must remain distinct from filled. History drafts with no frozen mode display not-yet-confirmed appropriately.
8. Keep existing page/app visibility polling read-only. No client queue or automatic write retry. Validate integer counters/known enum values; malformed progress displays unavailable rather than invented success.

Required invariants: INV-001/002/004/005/006/007 on client-facing behavior. Consume the final T59 API contract without redesigning queue/retry semantics.

## Tests and mandatory evidence

Define named tests:
- RED-FE `logout during confirmation prevents execute and stale success` in dashboard-controller tests; settings-modal tests also cover `save failure retains selection without saved claim`.
- GREEN-FE `settings mode persists and queue confirmation stays frozen` plus mobile/desktop modal, saved-draft and wizard confirmation/progress tests.

Formal RED: `rtk flutter test --no-pub test/features/strategy/strategy_dashboard_controller_test.dart --plain-name 'logout during confirmation prevents execute and stale success' --reporter compact`.

Expected: disposed session executes zero writes and presents no cross-account success.

Formal GREEN after RED: `rtk flutter test --no-pub test/features/strategy/strategy_settings_dialog_test.dart --plain-name 'settings mode persists and queue confirmation stays frozen' --reporter compact`.

Expected: save/reload acknowledged preference, display frozen mode despite subsequent preference update, and render queued state truthfully.

Additional cases: invalid prepared mode zero execute, account A late GET/POST after B/login switch, duplicate save, cancelled edits, load error, signed-out modal, queue submitted versus filled, stop/unknown/unsent rows without retries, both confirmation paths, no overflow at mobile and desktop widths, relevant existing tests.

V3 ceiling: `rtk flutter test --no-pub test/features/strategy/strategy_settings_dialog_test.dart test/features/strategy/strategy_api_client_test.dart test/features/strategy/strategy_dashboard_controller_test.dart test/features/strategy/strategy_screen_test.dart test/features/strategy/strategy_wizard_dialog_test.dart --reporter compact`.

Static check: `rtk flutter analyze lib/features/strategy`.

Task Buildability Gate: required YES; canonical unit Flutter web application. After final task-local executable change run `rtk flutter build web --no-pub --release --dart-define=TRADE_API_BASE_URL=https://api.tradingbalancef.com`. Result/exit: PENDING. No deployment in this task. Diagnose narrowly, then formal RED -> GREEN; rerun only evidence invalidated by later edits. Escalate beyond V3 only for an observed unresolved regression outside these consumers.

## Configuration, stop conditions and report

External Configuration / Environment Actions: none. No new packages or env values. Local verification uses API fakes and does not place real trades. BLOCKED if predecessor contract differs, required scope expands, protected configuration facts are needed, route mismatches, or build verification is unavailable. Do not self-escalate route or change product semantics.

Return compact paths/results, exact RED/GREEN/static/build commands/statuses, session-isolation evidence, no-config confirmation, and telemetry envelope LQ-E1-T60. Do not modify task/status/telemetry documents.

## Coordinator checklist / audit

- [x] Approval received and T59 PASS; explicit route compliance checked.
- [x] Allowed-source diff matches P04 and AC-001/002/007.
- [x] RED observed before GREEN.
- [x] Relevant tests/static check and canonical web buildability PASS.
- [x] Both confirmations, session boundaries and honest queue progress audited.
- [x] No protected content access or writes.
- [x] Verdict: PASS.

## Final observed evidence

Coordinator reran exact prescribed RED then GREEN because executor terminal report omitted the distinct focused GREEN command. Commands: `/Users/locnguyen/.local/bin/rtk flutter test --no-pub test/features/strategy/strategy_dashboard_controller_test.dart --plain-name 'logout during confirmation prevents execute and stale success' --reporter compact`, then `/Users/locnguyen/.local/bin/rtk flutter test --no-pub test/features/strategy/strategy_settings_dialog_test.dart --plain-name 'settings mode persists and queue confirmation stays frozen' --reporter compact`. Each1 test PASS, exit0, in final source state.

Executor final V3 five-file command specified above:56 tests PASS exit0. Scoped analyze exact `/Users/locnguyen/.local/bin/rtk flutter analyze --no-fatal-infos lib/features/strategy`: exit0, no errors/warnings,10 pre-existing info lints. Standard invocation exits1 only for infos; no new settings-dialog lint. Exact affected-unit build: `/Users/locnguyen/.local/bin/rtk flutter build web --no-pub --release --dart-define=TRADE_API_BASE_URL=https://api.tradingbalancef.com`, exit0 Built build/web after last source change, existing Wasm/Cupertino notices only. No deployment or live trading. No external configuration actions.
