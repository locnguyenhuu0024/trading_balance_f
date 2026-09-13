# Implementation Plan: Separate Risk Dashboard and Restore Portfolio

Status: COMPLETE
Date: 2026-09-13
Tier: M
Specification: `docs/agents/specs/2026-09-13-separate-risk-dashboard-restore-portfolio-design.md`
Decision Ledger: `docs/agents/decisions/2026-09-13-separate-risk-dashboard-restore-portfolio-decisions.md`

## 1. Objective

Implements: REQ-001 through REQ-004
Acceptance: AC-001 through AC-005

## 2. Preconditions

Decisions/assumptions: D-001; no authorized assumptions.
Predecessor/environment/repository state:
- Preserve all existing user-owned working-tree changes.
- Copy the Risk Dashboard from current HEAD `79f2f04...`, plus any later user-owned working-tree refinements present at execution time, before restoring `PortfolioScreen`.
- No protected configuration content is required.

## 3. Repository Impact

| Area | File | Symbol | Change Type |
|---|---|---|---|
| Portfolio | `lib/features/portfolio/presentation/portfolio_screen.dart` | `PortfolioScreen`, shared UI providers | MODIFY |
| Risk UI | `lib/features/portfolio/presentation/risk_dashboard_screen.dart` | `RiskDashboardScreen` | ADD |
| Navigation | `lib/core/navigation/main_navigation_shell.dart` | imports, `_buildSelectedScreen` | MODIFY |
| Navigation | `lib/core/navigation/navigation_destination_data.dart` | `navigationItems` | MODIFY |
| Navigation docs | `lib/core/navigation/floating_navigation_buttons.dart` | class documentation | MODIFY |
| Portfolio test | `test/features/portfolio/portfolio_dual_currency_screen_test.dart` | Portfolio widget cases | MODIFY |
| Risk tests | `test/features/portfolio/risk/risk_dashboard_test.dart` | Risk screen harness | MODIFY |
| Risk tests | `test/features/portfolio/risk/risk_editors_test.dart` | Risk screen harness | MODIFY |
| Navigation tests | `test/core/navigation/main_navigation_shell_test.dart` | six-item routing assertions | MODIFY |
| Navigation tests | `test/core/navigation/floating_navigation_buttons_test.dart` | six-item accessibility/layout assertions | MODIFY |
| Navigation tests | `test/core/navigation/navigation_presentation_host_test.dart` | last destination assertion | MODIFY |
| Root test | `test/widget_test.dart` | six-item root assertions | MODIFY |
| Shared icon test | `test/features/crypto_icon_urls/crypto_icon_url_test.dart` | screen source list | MODIFY |

New files: `lib/features/portfolio/presentation/risk_dashboard_screen.dart`
Explicitly not modified: Risk domain/application/data/runtime/notification code, `portfolio_details_screen.dart`, navigation preference persistence, unrelated dirty files, dependency/build/CI/deployment files, and all protected configuration/environment files.

## 4. External Configuration / Environment Actions

Required actions: none.

## 5. Dependency Graph

```text
P01 -> P02 -> P03 -> verification/audit
             \------ compile-coupled in T23 ------/
```

## 6. Ordered Implementation Steps

### P01 — Relocate the current Risk Dashboard

Objective: create a dedicated Risk screen without losing current committed or later working-tree behavior.
Implements: REQ-002, AC-003, AC-005
Files: `portfolio_screen.dart`, new `risk_dashboard_screen.dart`, Risk test imports/harnesses
Symbols: `PortfolioScreen` risk implementation -> `RiskDashboardScreen`
Dependencies: none

Required changes:
1. Copy the complete Risk Dashboard from current HEAD `79f2f04...`, including any later user-owned working-tree refinements found at execution time, to `risk_dashboard_screen.dart`.
2. Rename the public widget/state ownership to `RiskDashboardScreen`; retain constructor test seams and private widgets.
3. Import shared `hideBalanceProvider` and `isDarkModeProvider` from `portfolio_screen.dart`; retain `PortfolioDetailsScreen` and all current Risk behavior.
4. Update Risk screen tests to instantiate the new class.

Required behavior: exact current Risk UI behavior, including the refinements committed in `79f2f04...`.
Must preserve: INV-002 through INV-005.
Must NOT: edit any Risk engine/repository/runtime/storage/notification contract.
Edge cases: EDGE-003, EDGE-004.
Tests: TEST-001.

RED verification:
- scenario: RED-001 before the new class exists.
- command/method: `flutter test test/features/portfolio/risk/risk_dashboard_test.dart test/features/portfolio/risk/risk_editors_test.dart --reporter compact`
- expected: new-screen import/ownership assertions cannot pass before implementation.

GREEN verification:
- scenario: Risk behavior is preserved under `RiskDashboardScreen`.
- command/method: same focused Risk test command.
- expected: all existing Risk Dashboard/editor cases pass against the new screen.

Stop conditions:
- any current working-tree Risk change cannot be preserved exactly;
- relocation requires changing a Risk domain/runtime contract.

### P02 — Restore the pre-risk Portfolio home

Objective: restore the Portfolio implementation from the immediate pre-risk commit `a028c632...` at destination zero.
Implements: REQ-001, AC-001, AC-005
Files: `portfolio_screen.dart`, `portfolio_dual_currency_screen_test.dart`
Symbols: `PortfolioScreen`, `hideBalanceProvider`, `isDarkModeProvider`
Dependencies: P01

Required changes:
1. Restore the behavioral implementation of `portfolio_screen.dart` from `a028c632f3d7b4d0802af4d3566d7a731112eabb` after Risk code is safely relocated.
2. Keep the provider names/import path used by `main.dart`, Orders, Market, Settings, and tests.
3. Restore direct Portfolio assertions for summary, PnL, dual currency, hiding, compact layout, live prices, and asset list behavior.

Required behavior: REQ-001.
Must preserve: INV-002, INV-004, INV-005.
Must NOT: substitute the newer `PortfolioDetailsScreen` semantics for the explicitly requested former Portfolio page.
Edge cases: EDGE-003.
Tests: TEST-002.

RED verification:
- scenario: current `PortfolioScreen` renders Risk Home and lacks the former Portfolio summary.
- command/method: `flutter test test/features/portfolio/portfolio_dual_currency_screen_test.dart --reporter compact`
- expected: restored direct-Portfolio expectations fail before implementation.

GREEN verification:
- scenario: restored Portfolio renders former balances/PnL behavior directly.
- command/method: same focused Portfolio test command.
- expected: former summary, dual-currency, masking, and compact-layout assertions pass.

Stop conditions:
- restore would overwrite a user-owned Risk change not already preserved in P01;
- restored provider exports break existing consumers.

### P03 — Append the sixth primary navigation destination

Objective: make Risk Dashboard independently reachable at index five in fixed and floating navigation.
Implements: REQ-003, REQ-004, AC-002 through AC-005
Files: navigation source/doc and navigation/root/shared-icon tests listed in §3
Symbols: `navigationItems`, `_buildSelectedScreen`, hard-coded test counts/last indices
Dependencies: P01, P02

Required changes:
1. Append `Risk` with shield-style outlined/selected icons to `navigationItems`; do not reorder indices zero through four.
2. Route index five to `RiskDashboardScreen`.
3. Update fixed, floating, root, and presentation-host tests from five to six items and assert the sixth item remains reachable in constrained/large-text layouts.
4. Add the new Risk screen to the shared icon-source invariant test while retaining Portfolio coverage.

Required behavior: REQ-003 and REQ-004.
Must preserve: INV-001 through INV-005.
Must NOT: redesign navigation geometry/preferences or change saved preference encoding.
Edge cases: EDGE-001, EDGE-002.
Tests: TEST-003, TEST-004.

RED verification:
- scenario: root shell lacks index five and cannot switch from Portfolio to Risk.
- command/method: `flutter test test/core/navigation/main_navigation_shell_test.dart test/core/navigation/floating_navigation_buttons_test.dart test/core/navigation/navigation_presentation_host_test.dart test/widget_test.dart --reporter compact`
- expected: six-item/index-five assertions fail before implementation.

GREEN verification:
- scenario: all six items are accessible and route correctly.
- command/method: same focused navigation/root command.
- expected: destination zero is Portfolio, destination five is Risk Home, and fixed/floating layout assertions pass without exceptions.

Stop conditions:
- the sixth item is not reachable in a supported compact/large-text/navigation-edge case;
- implementation requires changing navigation preference persistence.

## 7. Test and Verification Plan

| Test | Proves | Level | Command/Method |
|---|---|---|---|
| TEST-001 | REQ-002 / AC-003 / GREEN-001 | widget | focused Risk Dashboard/editor test files |
| TEST-002 | REQ-001 / AC-001 / AC-005 / GREEN-001 | widget | Portfolio dual-currency test file |
| TEST-003 | REQ-003 / AC-002 / AC-003 | widget/integration | main shell and root widget test files |
| TEST-004 | REQ-003 / AC-004 | widget | floating navigation and presentation-host test files |
| TEST-005 | INV-004 and shared icon usage | widget/static source | Orders notional and crypto icon URL test files |

Inner-loop diagnostics: run only the changed focused test file after each coherent edit.
Formal checkpoint: after implementation is ready, run RED-001 evidence then the complete GREEN-001 affected set once in that order.
Later changes: re-run only the affected screen/navigation group unless shared imports or navigation data changed, in which case re-run all affected files.

Verification ladder: V1 focused RED/GREEN -> V2 complete relevant files -> V3 affected set -> V4 full suite.
Task verification ceiling: V3.
Final integration ceiling: V4.
Escalate when: shared provider imports, root routing, or navigation geometry causes a regression outside the focused files.

### External verification constraints

Known environment constraint: none.
User-executed verification required: NO.
Exact secret-free command: N/A.
Proves: N/A.
Evidence required back: N/A.
Completion blocked until evidence supplied: NO.

Full-suite ownership: CODEX_ONCE — the root destination and shared providers affect multiple features.

Regression coverage: Portfolio dual currency/privacy/live price, Risk UI/editors, Orders privacy consumption, fixed/floating navigation, compact/large-text reachability, and root routing.
Other checks: `flutter analyze`; task buildability via `flutter build web --no-pub` after final task-local edits; one `flutter test --reporter compact` final integration run if focused V3 passes.

## 8. Migration / Data Plan

N/A — no persistence, schema, or user-data migration.

## 9. Performance Verification

N/A — existing Portfolio refresh and Risk monitoring cadences are restored/preserved without new work.

## 10. Risks

| Risk ID | Risk | Impact | Detection | Mitigation |
|---|---|---|---|---|
| RISK-001 | Dirty Risk presentation edits are overwritten during restore. | User work loss. | compare moved screen with working-tree source before overwrite; audit diff. | Relocate first; never restore/revert the whole file blindly. |
| RISK-002 | Provider declarations move and break Orders/Market/Settings/main imports. | Compile/runtime failure. | analyze/build and provider consumer tests. | Keep provider exports in `portfolio_screen.dart`. |
| RISK-003 | Six controls become too narrow or unreachable. | Navigation usability regression. | compact, scale, edge, scroll-fallback widget tests. | Preserve dynamic layout and assert index five. |
| RISK-004 | Risk tests pass while root route points to the wrong screen. | Incorrect product behavior. | main shell test taps both index zero and index five. | Explicit mapping assertions. |
| RISK-005 | Restored Portfolio code diverges from the immediate pre-risk snapshot. | Visual/behavior regression. | targeted comparison and tests. | Restore `a028c632...` behavior while retaining required current shared APIs only. |

## 11. Rollout / Rollback

N/A — no deployment or migration in scope. Any rollback must be limited to T23-owned files and must not revert unrelated working-tree changes.

## 12. Decision/Assumption Dependency Registry

| Decision/Assumption | Used By | Evidence/Authorization | Invalidated By |
|---|---|---|---|
| D-001 | REQ-001-REQ-004, P01-P03, T23 | user confirmation on 2026-09-13 | user requests different destination ownership/order |

## 13. Task Decomposition

| Task | Plan Steps | Requirements/AC | Depends On | Executor Class | Allowed Write Surface |
|---|---|---|---|---|---|
| T23 | P01-P03 | REQ-001-REQ-004 / AC-001-AC-005 | — | E1 | exact source/test files in §3 |

Handoff-cost review: one task is retained because the screen extraction, restore, imports, navigation route, and tests are compile-coupled and share one RED/GREEN integration path. Splitting would create a broken intermediate build or duplicate handoff/audit cost.

### Task Buildability Plan

| Task | Required | Affected Canonical Build Unit | Exact Secret-Free Build Command | Boundary Strategy |
|---|---|---|---|---|
| T23 | YES | Flutter application | `flutter build web --no-pub` | self-contained merged compile-coupled change |

## 14. Completion Gate

- [x] every task PASS
- [x] T23 task buildability gate PASS after final executable change
- [x] no compile-coupled intermediate state is marked PASS
- [x] every affected AC has implementation/verification evidence
- [x] RED precedes GREEN
- [x] focused and final repository checks observed
- [x] final diff matches approved scope and preserves unrelated dirty work
- [x] final integration audit PASS
- [x] no protected configuration/environment file was read or modified
- [x] external configuration actions remain N/A

## 15. Change Log

| Revision | Change | Reason |
|---|---|---|
| 1 | Initial plan ready for approval. | D-001 resolved the destination split. |
| 2 | Marked complete after T23 audit PASS. | RED/GREEN, V4 suite, changed-source analysis, and final web build passed. |
