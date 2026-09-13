# Task 23 — Split Risk Dashboard and Restore Portfolio

Status: PASS
Executor: implementation executor
Executor Class: E1
Target Route: Luna XHigh
Specification: `docs/agents/specs/2026-09-13-separate-risk-dashboard-restore-portfolio-design.md`
Plan: `docs/agents/plans/2026-09-13-separate-risk-dashboard-restore-portfolio.md`
Plan Steps: P01-P03
Requirements: REQ-001-REQ-004
Acceptance Criteria: AC-001-AC-005

## 1. Objective

Restore the former Portfolio at destination zero and expose the preserved current Risk Dashboard as destination five, the sixth primary navigation item.

Done when: both screens are independently reachable, all six fixed/floating controls remain accessible, focused affected tests pass, and the Flutter web build passes.

## 2. Preconditions

Predecessors: none.
Required decisions/assumptions: D-001; no assumptions.
Required repository/environment state: current baseline HEAD is `79f2f04...`; preserve every later user-owned working-tree change and extract the current Risk implementation before replacing `portfolio_screen.dart`.

## 3. Allowed Scope

Files/modules/APIs/data structures/symbols:
- `lib/features/portfolio/presentation/portfolio_screen.dart`
- `lib/features/portfolio/presentation/risk_dashboard_screen.dart` (new)
- `lib/core/navigation/main_navigation_shell.dart`
- `lib/core/navigation/navigation_destination_data.dart`
- `lib/core/navigation/floating_navigation_buttons.dart` (documentation only unless tests prove a six-item layout defect)
- `test/features/portfolio/portfolio_dual_currency_screen_test.dart`
- `test/features/portfolio/risk/risk_dashboard_test.dart`
- `test/features/portfolio/risk/risk_editors_test.dart`
- `test/core/navigation/main_navigation_shell_test.dart`
- `test/core/navigation/floating_navigation_buttons_test.dart`
- `test/core/navigation/navigation_presentation_host_test.dart`
- `test/widget_test.dart`
- `test/features/crypto_icon_urls/crypto_icon_url_test.dart`
- `test/features/orders/presentation/orders_screen_notional_test.dart` only if a provider-compatibility fixture/import update is required

## 4. Forbidden Scope

Do not:
- read, search within, parse, summarize, or content-diff protected repository configuration/environment files;
- create, modify, delete, rename, reformat, or regenerate protected configuration/environment files;
- modify Risk domain/application/data/runtime/storage/notification behavior;
- delete or redesign `portfolio_details_screen.dart`;
- change Portfolio data/formula contracts or navigation preference persistence;
- revert or overwrite unrelated working-tree changes;
- add/remove dependencies or perform opportunistic refactors;
- exceed the stated write surface.

If required work exceeds Allowed Scope, return `BLOCKED`.

## 5. Executor Contract

Follow P01-P03 in order:
1. Relocate the exact current Risk Dashboard from baseline `79f2f04...`, plus later user-owned refinements, to `RiskDashboardScreen`, preserving constructor seams and all current UI behavior.
2. Restore the immediate pre-`cdf01ff` Portfolio behavior from `a028c632...` in `PortfolioScreen`, keeping shared provider exports at the existing path.
3. Append `Risk` at index five, route it to the new screen, and update affected tests for six destinations and independent screen ownership.

Required invariants: INV-001-INV-005.
Required edge behavior: EDGE-001-EDGE-004.
Preserved behavior: existing indices zero through four, shared providers, Risk monitor/domain behavior, Portfolio behavior from `a028c632...`, fixed/floating navigation preferences and accessibility.

Do not invent missing architecture/product semantics. If the contract is insufficient, return `BLOCKED`.

## 6. External Configuration / Environment Actions

Planned action: none.
Discovered additional action during execution: none expected; if required, return `BLOCKED` without inspecting protected configuration.
Blocks verification until user applies: NO.

## 7. Tests

- TEST-001: update Risk Dashboard/editor harnesses to use `RiskDashboardScreen` and retain existing behavioral coverage.
- TEST-002: restore direct Portfolio summary, dual-currency, masking, and compact-layout expectations.
- TEST-003: assert six-item ordering and index-five routing in root/main shell.
- TEST-004: assert six fixed/floating destinations and constrained/large-text reachability.
- TEST-005: retain shared provider/icon-source compatibility coverage.

## 8. Mandatory Verification

### RED — RED-001

Scenario: the existing application cannot satisfy independent Portfolio-at-zero and Risk-at-five expectations.
Command/method: add/restore the approved assertions, then run the focused affected tests before implementation.
Expected: at least one approved assertion fails because index five/new Risk screen/restored Portfolio is absent.
Actual: the focused shell/root tests failed because five destinations were rendered while six were expected.
Status: PASS.

### GREEN — GREEN-001

Scenario: independent Portfolio and Risk destinations plus six-item navigation.
Command/method: `flutter test test/features/portfolio/portfolio_dual_currency_screen_test.dart test/features/portfolio/risk/risk_dashboard_test.dart test/features/portfolio/risk/risk_editors_test.dart test/core/navigation/main_navigation_shell_test.dart test/core/navigation/floating_navigation_buttons_test.dart test/core/navigation/navigation_presentation_host_test.dart test/features/crypto_icon_urls/crypto_icon_url_test.dart test/features/orders/presentation/orders_screen_notional_test.dart test/widget_test.dart --reporter compact`
Expected: all affected tests pass; index zero renders Portfolio, index five renders Risk Home, and all six controls remain accessible.
Actual: all 42 affected tests passed.
Status: PASS.

Verification ceiling: V3.
Escalate only if: shared provider/navigation changes produce an evidenced regression outside the affected set.

### Task Buildability Gate

Required: YES.
Affected canonical build unit: Flutter application.
Exact secret-free build command: `flutter build web --no-pub`.
Executed after the last task-local executable/source/test change: YES.
Result: PASS.
Exit/status: 0.
Compiler/parser/type/reference/link/build errors: none.

### External Verification

Required: NO.
Subtype: N/A.
Exact secret-free user-run command: N/A.
Proves: N/A.
Expected returned evidence: N/A.
Task/verification blocked until returned: NO.

## 9. Stop Conditions

Return `BLOCKED` when:
- any dirty Risk UI change would be lost;
- repository evidence contradicts D-001 or the `a028c632...` restore reference;
- the sixth destination requires a navigation persistence redesign;
- required work exceeds Allowed Scope;
- required verification is genuinely unavailable;
- a required fact depends on protected configuration content.

Report blocker, evidence, affected IDs, and the coordinator decision required.

## 10. Execution Ledger

- [x] inspect referenced symbols and current name-only Git status
- [x] capture formal RED evidence
- [x] implement P01-P03 in order
- [x] add/update required tests
- [x] execute formal GREEN affected set
- [x] run `flutter analyze`
- [x] run Task Buildability Gate after final executable change
- [x] stop at V3 unless escalation is triggered
- [x] return compact executor report
- [x] confirm no protected configuration/environment content was read or modified
- [x] report External Configuration / Environment Actions as none

## 11. Coordinator Audit

Scope: PASS
Acceptance criteria: PASS (AC-001-AC-005)
Test quality: PASS
RED evidence: PASS
GREEN evidence: PASS — 42 affected tests
RED-before-GREEN: PASS
Evidence reused vs rerun: executor RED/GREEN/build reused; coordinator ran V4, changed-source analyze, and final web build
Rerun reason: N/A
Architecture/contract conformance: PASS
Task buildability gate: PASS — `flutter build web --no-pub`, exit 0
Verdict: PASS
