# Task 40 — Restore strategy contract list

Status: PASS (coordinator audit 2026-10-01)
Agent Role: implementation_executor
Executor Class: E1
Target Model: gpt-6-luna
Target Effort: xhigh
Target Route: gpt-6-luna / xhigh
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Dispatch Route Status: UNVERIFIABLE (explicit model and effort binding; runtime did not expose effective route)
Specification: `docs/agents/specs/2026-10-01-strategy-coin-and-trade-header.md`
Plan: `docs/agents/plans/2026-10-01-strategy-coin-and-trade-header.md`
Plan Steps: P01
Requirements: REQ-001
Acceptance Criteria: AC-001

## Objective

Make valid live linear USDT SWAPs selectable when OKX supplies blank or absent `baseCcy`; retain strict validation for nonblank metadata and all existing filters.

## Scope

Allowed writes: `lib/features/strategy/data/strategy_market_repository.dart`, `test/features/strategy/strategy_market_repository_test.dart`.
Forbidden: other behavior, protected configuration/environment files, dependencies, Git mutation, live order placement.

## Verification contract

- RED-001: add a case with blank and absent `baseCcy`, plus a conflicting nonblank case; the existing parser must fail to include the first two. Run this before the fix.
- GREEN-001: run the same case after the fix; valid instruments appear and conflicting metadata stays excluded. Run existing catalog test and the full relevant test file.
- Buildability: `flutter build web --release` after final source/test change; affected canonical unit is Flutter web app.
- Ceiling V2; escalate only on a concrete related failure.
- No external configuration action.

Stop and report BLOCKED if safe repository evidence contradicts the contract or the fix requires a protected configuration change. Return concise RED/GREEN/build results; coordinator owns audit and final task status.

## Audit result

AC-001 PASS. The changed parser derives base from the strict SWAP ID only when metadata is empty or missing, rejects conflicting nonempty metadata, and retains existing market filters, sorting, and immutable result. RED-001 failed before the fix as expected; GREEN-001 and all six tests in the relevant file passed. The affected Flutter web unit built after the final T40 code/test edit with `rtk flutter build web --release` (exit 0). Changed product/test paths match the allowed surface; no protected configuration path changed. External configuration actions: none.
