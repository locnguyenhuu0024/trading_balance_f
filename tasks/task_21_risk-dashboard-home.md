# Task 21 — Complete risk-first Portfolio Home

Status: PASS
Executor: implementation executor (configured target gpt-5.6-luna / max; verify effective routing)
Specification: `docs/agents/specs/2026-09-10-isolated-margin-risk-dashboard-design.md`
Plan: `docs/agents/plans/2026-09-10-isolated-margin-risk-dashboard.md`
Plan Steps: P04
Requirements: REQ-006, REQ-007, REQ-008, REQ-010
Acceptance Criteria: AC-006, AC-007, AC-008, AC-010

## 1. Objective

Complete the single auditable outcome in canonical plan §5 P04. Done when the referenced ACs and required negative/success scenarios are observed, scope is audited and coordinator verdict is PASS. Do not substitute a summary for repository evidence.

## 2. Preconditions

Predecessors: T20 = PASS.
Required decisions: D-001–005, A-001. Explicit execution approval of the presented plan is mandatory before dispatch. Coordinator confirms Definition of Ready and reads execution/audit rules. Inspect applicable AGENTS and context optimization profile; preserve existing user changes. Read only relevant specification sections and P04, not all framework/templates.

## 3. Allowed Scope

- `lib/features/portfolio/presentation/portfolio_screen.dart`
- `lib/features/portfolio/presentation/portfolio_details_screen.dart`
- `lib/features/portfolio/presentation/providers/risk_dashboard_provider.dart`
- `lib/features/portfolio/presentation/widgets/risk/risk_overview.dart`
- `lib/features/portfolio/presentation/widgets/risk/risk_market_card.dart`
- `lib/features/portfolio/presentation/widgets/risk/risk_stress_view.dart`
- `lib/features/portfolio/presentation/widgets/risk/risk_recovery_view.dart`
- `lib/features/portfolio/presentation/widgets/risk/risk_plan_editor.dart`
- `lib/features/portfolio/presentation/widgets/risk/risk_history_view.dart`
- `lib/features/portfolio/presentation/widgets/risk/risk_settings_sheet.dart`
- `lib/features/portfolio/presentation/widgets/risk/risk_price_map.dart`
- `lib/features/portfolio/application/risk_monitor_bridge.dart` (remediation only: extend the immutable typed view state with the already-approved plan/settings/market/history/session-comparison data required by P04; no monitor lifecycle implementation)
- `test/features/portfolio/portfolio_dual_currency_screen_test.dart`
- `test/features/portfolio/risk/risk_dashboard_test.dart`
- `test/features/portfolio/risk/risk_editors_test.dart`

Synthetic fixtures may be created under `test/features/portfolio/risk/fixtures/`. No real account payloads. Executor reports evidence to coordinator; coordinator owns planning/audit metadata and task allocation.

Coordinator escalation note: the first T21 audit proved that the P03 bridge state omitted authoritative persisted plan/settings/history inputs required by approved AC-007/008. The existing plan explicitly permits escalation for an evidenced shared-surface regression. This narrow bridge-state extension resolves that contract gap without changing product semantics or beginning T22 runtime ownership.

## 4. Forbidden Scope

No unrelated refactors, generated Orders DTO changes, trading API writes, dependency changes, deployment, Git mutations, real credential reads or private API calls. No external services beyond explicitly authorized official OKX documentation. No product-semantic decisions outside the specification. Return BLOCKED if required work exceeds the write surface.

## 5. Executor Contract

Follow canonical P04 in order. Use specification formulas/defaults and missing-data behavior exactly. Domain functions are pure and platform code must reuse them. Honor all applicable INV/EDGE entries called out by P04. Incomplete API data uses specified quality states; do not invent neutral or zero values. User-authored plan text remains text, never a trading command.

Before handoff inspect the diff, scope, changed symbols and test evidence. Do not claim runtime/native verification from mocks. If effective executor model is explicitly reported different from configured target, report BLOCKED.

## 6. Tests

Test files above implement RED-004/GREEN-004 prefixes and independently derived expectations below. Use injected time, storage, HTTP and platform interfaces. Narrow diagnostics first; do not run broad suites during each edit. Existing compatibility checks are listed in the canonical plan.

## 7. Mandatory Verification

### RED — RED-004

Scenario and expected outcome: Empty/failed/stale/partial data do not say safe, stable or no threshold by default. Hidden PnL absent from text and semantics. Invalid rule cannot save. At 320px and 200% text there is no overflow and controls remain scroll-accessible.

Command: `flutter test test/features/portfolio/risk/risk_dashboard_test.dart test/features/portfolio/risk/risk_editors_test.dart --plain-name RED-004 --reporter compact`
Actual: PASS — coordinator observed 7/7 focused RED-004 cases after the final test-support change.
Status: PASS

### GREEN — GREEN-004

Scenario and expected outcome: F1 view presents all seven priority answers; -10 shows scenario-specific current engine result (including recovery floor), not a hard-coded WATCH. All detail sheets, user rules/settings, custom scenario prices, price map/history/daily summary work. Details reveal PnL deliberately while dual currency/privacy remain correct. Inspect light/dark 390x844 and desktop 1280x900 synthetic screenshots.

Command: `flutter test test/features/portfolio/risk/risk_dashboard_test.dart test/features/portfolio/risk/risk_editors_test.dart --plain-name GREEN-004 --reporter compact`
Actual: PASS — coordinator observed 10/10 focused GREEN-004 cases after RED-004.
Status: PASS

Execute RED before GREEN at the formal checkpoint. After implementation/test-support changes restart the pair under the governing direct-user AGENTS instruction. Verification ceiling: V3. Escalation only for an evidenced shared-surface regression or missing AC evidence. Final full-suite ownership belongs to coordinator integration, not each task.

## 8. Stop Conditions

Return BLOCKED for missing material contract, incompatible API semantics beyond explicit unavailable handling, scope expansion, failed prerequisite, unavailable necessary verification or an explicit model mismatch. Include evidence, affected IDs and needed coordinator decision. Do not silently reduce full scope.

## 9. Execution Ledger

- [x] Definition of Ready and authorization confirmed
- [x] Referenced symbols inspected
- [x] Assigned P04 implemented within allowed scope
- [x] Required tests/fixtures added or updated
- [x] Formal RED executed and observed
- [x] Formal GREEN executed and observed afterward
- [x] Verification ceiling respected
- [x] Compact report: changed files, behavior, commands/results, unresolved limits

## 10. Coordinator Audit

Scope: PASS — only approved T21 presentation/tests plus the documented narrow typed-state bridge escalation.
Acceptance criteria: PASS — AC-006, AC-007, AC-008 and AC-010 are represented by the responsive Home, functional drill-downs/editors, local-state presentation, privacy and data-quality flows.
Test quality: PASS — boundary/failure tests, reactive mutations, account switching, privacy semantics, prior-check data and real rendered screenshots use independently asserted outcomes.
RED evidence: PASS — 7/7.
GREEN evidence: PASS — 10/10.
RED-before-GREEN: PASS — coordinator reran the complete ordered pair after the final test-only remediation.
Architecture/contract conformance: PASS — UI consumes immutable typed bridge state and reuses domain evaluation logic; no T22 runtime ownership was implemented.
Evidence reuse vs rerun: PASS — coordinator reran invalidated RED/GREEN, dual-currency compatibility and scoped analyzer after implementation changes; final test-only change was followed by another complete RED/GREEN pair and analyzer.
Verdict: PASS — independent auditor final verdict PASS.

### Remediation R21-001

First audit verdict: REWORK. Required remediation remains within the approved product requirements:

- replace hand-painted placeholder PNGs with actual rendered `RepaintBoundary` widget captures using synthetic account data;
- make bridge view state authoritative for persisted plan, settings, market input, history samples, daily summaries and previous-check comparison, with immutable collections/copy semantics;
- keep open scenario/history/plan surfaces reactive after accepted commands and prevent stale captured settings from losing sequential changes;
- make state-level stale/error/partial quality override cached evaluation freshness;
- render actual since-last-check deltas and first-visit behavior;
- restore the approved compact mobile hierarchy, component chips and volatility multiple;
- mask numeric reason/event content in visible text and semantics when privacy is enabled;
- expose approved retention/timing settings and complete market/daily-summary evidence;
- preserve the existing principal/base-capital dual-currency detail and assertions;
- strengthen RED/GREEN evidence for cached stale data, real captures, viewport/large-text access, semantics privacy, persisted reload/account switch, zone CRUD, live custom scenarios/history, prior-check data, keyboard/focus, and independently expected -10 results.

All formal RED/GREEN evidence is pending again because the shared UI/test basis must change.

### Remediation R21-003

Third audit verdict: REWORK. Remaining bounded items:

- derive Position/Market/Recovery qualifiers from each component assessment quality and missing reasons, while transport freshness remains a separate qualifier; retain known severity and qualify incomplete NORMAL rather than presenting it as unconditionally safe;
- stack/wrap the overview title and quality chip at narrow widths or large text so 320px at 200% remains readable and all controls remain scroll-accessible;
- compact the 390px priority block so the seven required answers are reachable within one short continuation after the first viewport, and verify concrete rendered positions rather than allowing two viewport heights;
- after these changes, regenerate readable rendered screenshots and restart the formal RED-004 then GREEN-004 sequence.

### Final Evidence

- Formal RED-004: PASS, 7/7, executed before GREEN-004.
- Formal GREEN-004: PASS, 10/10.
- Dual-currency Portfolio Details compatibility: PASS, 2/2.
- Scoped `flutter analyze --no-pub`: PASS, no issues.
- `dart format --output=none --set-exit-if-changed`: PASS, 15 files unchanged.
- `git diff --check`: PASS.
- Real rendered synthetic screenshots inspected at 390x844 light/dark, 1280x900 desktop and 320x844 at 200% text under `/tmp/risk-dashboard-review/`.
- Independent final audit: PASS.
- Runtime/native monitor persistence remains assigned to T22 and was not claimed by T21.
