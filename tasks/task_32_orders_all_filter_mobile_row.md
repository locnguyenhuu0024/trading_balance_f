# Task 32 — ALL transaction filter and mobile filter row

Status: PASS
Agent Role: implementation_executor
Executor Class: E1
Target Model: gpt-6-luna
Target Effort: xhigh
Target Route: gpt-6-luna / xhigh
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Dispatch Route Status: UNVERIFIABLE (explicit model and effort bound; effective route not exposed)
Specification: `docs/agents/specs/2026-09-30-orders-all-filter-mobile-row.md`
Plan: `docs/agents/plans/2026-09-30-orders-all-filter-mobile-row.md#P01`

## Objective and scope

Implement REQ-001/002 and prove AC-001..004. No predecessors. Allowed changes: the four orders source files and focused tests under `test/features/orders/` listed in the plan. Do not change protected configuration/environment files, generated files, dependencies, other screens, or Git history.

## Executor contract

Implement P01 exactly. ALL positions cover MARGIN/SWAP/FUTURES. ALL pending/history cover SPOT/MARGIN/SWAP/FUTURES. Never send literal ALL to the API. Fail the whole load if any subtype fails. Sort merged orders by valid numeric `cTime` descending, invalid last, stable ties. Preserve default MARGIN, single-type behavior, SPOT positions explanation, and pull-to-refresh. Mobile selectors remain on one row and fit 390 px. ALL automatic polling is 5 seconds without overlapping active automatic loads; single-type interval remains 1 second.

## Verification and report

RED first: execute focused ALL partial-failure and SPOT-position cases; expect error for partial failure and no SPOT position request.

GREEN second: execute focused mixed-type aggregation and 390 px widget cases; expect all specified types, no ALL request, newest-first merged orders, same-row controls, callback ALL, and no overflow.

Use V1 focused tests, V2 only if directly affected tests warrant it. After the final executable edit run `flutter build web --no-pub`; a passing test harness alone is insufficient. Report exact commands, exit/status, changed files, RED/GREEN order and results, build result, and any blockers. External verification/configuration action: none. If contract evidence conflicts or allowed scope is insufficient, return BLOCKED to coordinator. No protected configuration content may be read or modified.

## Coordinator audit

Scope: PASS — three approved source files and three focused tests. Acceptance: PASS — ALL expands to the required types, keeps atomic failure semantics and merged ordering, and mobile controls share a row. RED-before-GREEN: PASS — the focused repository and widget tests failed before source edits, then passed after implementation. Buildability: PASS — executor's final `rtk proxy flutter build web --no-pub` exited 0 after the last code/test edit. Independent V2 check: `rtk proxy flutter test --no-pub test/features/orders/order_repository_all_test.dart test/features/orders/order_filter_controls_test.dart test/features/orders/orders_screen_refresh_test.dart` exited 0 with 8 tests passed. `git diff --check` exited 0. Dispatch route: UNVERIFIABLE, with explicit `gpt-6-luna` / `xhigh` binding and no inherited route. Protected configuration files: no content read or write. External configuration action: none. Verdict: PASS.
