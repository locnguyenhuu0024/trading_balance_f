# Task 49 — Poll only started strategies

Status: PASS
Agent Role: implementation_executor
Executor Class: E1
Target Model: gpt-6-luna
Target Effort: xhigh
Target Route: gpt-6-luna / xhigh
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Dispatch Route Status: UNVERIFIABLE (both executor requests explicitly bound; effective routes unavailable)
Specification: `docs/agents/specs/2026-10-02-strategy-preview-market-correction.md`
Plan: `docs/agents/plans/2026-10-02-strategy-preview-market-correction.md`, P04
Requirements: REQ-004; Acceptance: AC-004

## Objective and scope

Retain one-second quote polling while the strategy dashboard is visible only for already-started strategies (`APPLIED`, `PARTIAL`, `UNKNOWN`). Do not poll `DRAFT` or `PREPARED` strategies.

Predecessor: T48 PASS. Decision: D-006. Allowed writes: `lib/features/strategy/presentation/providers/strategy_dashboard_provider.dart`, `lib/features/strategy/presentation/strategy_screen.dart`, `test/features/strategy/strategy_dashboard_controller_test.dart`, and focused `test/features/strategy/strategy_screen_test.dart` if needed. Forbidden: protected configuration contents or writes, wizard/backend/other app features, status polling cadence changes.

Executor contract: Derive the ticker instrument set from started statuses, dedupe by instrument, preserve current visibility, overlap and backoff guards, and keep the separate 20-second authenticated status refresh. Remove or ignore stale quote cache for an instrument only if needed to avoid misrepresenting draft state; do not make draft detail values appear live.

RED-004: a visible draft-only dashboard currently calls public ticker. GREEN-004: draft/prepared-only lists make zero ticker calls over >1 second, while an applied/partial/unknown item calls it at the existing cadence and hidden pages stop. Execute formal RED before GREEN with `rtk flutter test test/features/strategy/strategy_dashboard_controller_test.dart`; verification ceiling V2. Buildability after final edit: `rtk flutter build web --release`, PASS required. No external configuration action.

Stop and return BLOCKED if a real started status is absent from the approved set or allowed scope is insufficient. Coordinator audits cadence and draft filtering.

## Audit finding and bounded remediation

AUD-001 (REWORK): The initial T49 implementation correctly filters ticker requests to started statuses, but `strategy_screen.dart` still passes a shared instrument quote to every card. When a draft and started strategy use the same instrument, the draft card displays a fresh quote. Expected: only started cards show the live ticker; draft/prepared cards do not display a live quote merely because another strategy shares the coin. Remediation is limited to quote-to-card wiring and a focused regression test for the mixed-status same-instrument case. Keep the existing T49 provider filter, one-second cadence, visibility/backoff, and 20-second authenticated status refresh. Re-run invalidated RED/GREEN evidence and `rtk flutter build web --release` after the last edit.

## Completion and coordinator audit

Verdict: PASS after AUD-001 remediation. Initial RED: `rtk flutter test test/features/strategy/strategy_dashboard_controller_test.dart` observed two ticker calls for DRAFT/PREPARED (expected zero). Initial GREEN: 17 tests passed and post-edit `rtk flutter build web --release` exited 0. AUD-001 RED observed a draft card showing the started strategy's same-instrument quote. Remediation GREEN: `rtk flutter test test/features/strategy/strategy_screen_test.dart test/features/strategy/strategy_dashboard_controller_test.dart` (18 tests passed), followed by `rtk flutter build web --release` (exit 0) after the final edit. Coordinator inspected the provider, card wiring, and tests: only APPLIED/PARTIAL/UNKNOWN instruments are polled; only their cards receive cached quotes; visibility/backoff and 20-second authenticated status refresh remain. No protected configuration path changed. Effective routes were not exposed after explicit E1 `gpt-6-luna` / `xhigh` and E0 `gpt-6-luna` / `high` binding.
