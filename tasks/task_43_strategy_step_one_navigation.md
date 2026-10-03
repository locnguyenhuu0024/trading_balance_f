# Task 43 — Explain and enable valid step-one navigation

Status: PASS (coordinator audit after AUD-001 remediation 2026-10-02)
Agent Role: implementation_executor
Executor Class: E1
Target Model: gpt-6-luna
Target Effort: xhigh
Target Route: gpt-6-luna / xhigh
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Dispatch Route Status: UNVERIFIABLE (explicit model and effort binding; runtime did not expose effective route)
Specification: `docs/agents/specs/2026-10-02-strategy-step-one-progress.md`
Plan: `docs/agents/plans/2026-10-02-strategy-step-one-progress.md`
Plan Steps: P01
Requirements: REQ-001, REQ-002
Acceptance Criteria: AC-001, AC-002

## Objective and scope

Allow a valid selected level to advance from Step 1 despite a temporarily stale quote, explain any disabled condition, reconcile selections after price crossing, and align strategy-only public quote age to the backend's existing 15 seconds.

Allowed writes: `lib/features/strategy/presentation/strategy_wizard_dialog.dart`, `lib/features/strategy/data/strategy_market_repository.dart`, focused Dart tests under `test/features/strategy/`.
Forbidden: backend, order/auth behavior, general `StrategyTicker` default freshness, dependencies, protected configuration/environment files, Git mutations, existing T40–T42 product changes beyond task-local edits.

## Verification contract

- RED-001: widget test with valid checked level and >15-second-old public quote shows Step 1 can advance but preview refuses the quote; current Step 1 button remains disabled. A separate 5–15-second case verifies the aligned strategy freshness threshold.
- RED-002: ticker crossing selected level removes/informs about invalid choice while retaining unaffected choices; current state keeps invisible selected level.
- GREEN-001: no-selection reason, stale reason/retry, valid navigation, crossed-level reconciliation, and preview freshness gate pass. Run relevant wizard and strategy repository test files.
- Buildability: Flutter web app, exact `rtk flutter build web --release` after final source/test edit, exit 0 required.
- V2 ceiling; V3 only on concrete related regression. External configuration action: none.

Stop if this requires weakening backend or live-order safety. Return exact RED/GREEN/build evidence. Coordinator owns audit/status.

## AUD-001 remediation contract

Finding: The stale-quote `Làm mới báo giá` button invokes `_refreshTicker`, but `_refreshTicker` returns before a network attempt while `_tickerRetryAt` is in the future. The UI instructs users to press the button yet can silently do nothing. Expected: an explicit manual tap performs one immediate retry even during automatic backoff, without overlapping an in-flight request; automatic polling keeps its existing backoff. Add a focused widget regression using a failed/stale ticker followed by a fresh response. Scope remains the T43 allowed Flutter source/test files. Re-run only invalidated RED/GREEN evidence, then the affected Flutter web build after the final edit.

## Audit result

AC-001/002 PASS after AUD-001. Step 1 navigation now depends on valid selected levels, with a visible no-selection reason. Strategy-specific public quote age is 15 seconds; stale quotes still block preview while navigation is available. Crossed levels are removed with a visible notice; unaffected choices remain. RED-001/002 failed as expected before the source fix; the manual-refresh RED case failed before AUD-001 remediation. After the final edit, all eight wizard widget tests passed, the seven repository tests remained valid from their unaffected GREEN checkpoint, and `rtk flutter build web --release` exited 0. The manual retry now bypasses backoff without overlap. Changed paths match allowed scope; no protected configuration path changed. External configuration actions: none.
