# Task 18 — Position metrics and stress engine

Status: PASS
Executor: implementation executor (configured target gpt-5.6-luna / max; verify effective routing)
Specification: `docs/agents/specs/2026-09-10-isolated-margin-risk-dashboard-design.md`
Plan: `docs/agents/plans/2026-09-10-isolated-margin-risk-dashboard.md`
Plan Steps: P01
Requirements: REQ-001, REQ-002, REQ-003, REQ-005, REQ-006
Acceptance Criteria: AC-001, AC-002, AC-003, AC-005, AC-006

## 1. Objective

Complete the single auditable outcome in canonical plan §5 P01. Done when the referenced ACs and required negative/success scenarios are observed, scope is audited and coordinator verdict is PASS. Do not substitute a summary for repository evidence.

## 2. Preconditions

Predecessors: none.
Required decisions: D-001–005, A-001. Explicit execution approval of the presented plan is mandatory before dispatch. Coordinator confirms Definition of Ready and reads execution/audit rules. Inspect applicable AGENTS and context optimization profile; preserve existing user changes. Read only relevant specification sections and P01, not all framework/templates.

## 3. Allowed Scope

- `lib/features/portfolio/domain/risk/risk_models.dart`
- `lib/features/portfolio/domain/risk/risk_policy.dart`
- `lib/features/portfolio/domain/risk/risk_engine.dart`
- `lib/features/portfolio/data/risk/okx_risk_dto.dart`
- `lib/features/portfolio/data/risk/risk_repository.dart`
- `test/features/portfolio/risk/risk_engine_test.dart`
- `test/features/portfolio/risk/risk_repository_test.dart`

Synthetic fixtures may be created under `test/features/portfolio/risk/fixtures/`. No real account payloads. Executor reports evidence to coordinator; coordinator owns planning/audit metadata and task allocation.

## 4. Forbidden Scope

No unrelated refactors, generated Orders DTO changes, trading API writes, dependency changes, deployment, Git mutations, real credential reads or private API calls. No external services beyond explicitly authorized official OKX documentation. No product-semantic decisions outside the specification. Return BLOCKED if required work exceeds the write surface.

## 5. Executor Contract

Follow canonical P01 in order. Use specification formulas/defaults and missing-data behavior exactly. Domain functions are pure and platform code must reuse them. Honor all applicable INV/EDGE entries called out by P01. Incomplete API data uses specified quality states; do not invent neutral or zero values. User-authored plan text remains text, never a trading command.

Before handoff inspect the diff, scope, changed symbols and test evidence. Do not claim runtime/native verification from mocks. If effective executor model is explicitly reported different from configured target, report BLOCKED.

## 6. Tests

Test files above implement RED-001/GREEN-001 prefixes and independently derived expectations below. Use injected time, storage, HTTP and platform interfaces. Narrow diagnostics first; do not run broad suites during each edit. Existing compatibility checks are listed in the canonical plan.

## 7. Mandatory Verification

### RED — RED-001

Scenario and expected outcome: Missing/invalid P gives unavailable buffer, E=0 gives CRITICAL, ambiguous debt has no invented holding cost, and F2 collateral changes equity by 150 for a 1 USDT drop. Exercise exact 20/30/45% and 4/6x/110/150% boundaries.

Command: `flutter test test/features/portfolio/risk/risk_engine_test.dart test/features/portfolio/risk/risk_repository_test.dart --plain-name RED-001 --reporter compact`
Actual: PENDING
Status: PENDING

### GREEN — GREEN-001

Scenario and expected outcome: F1: buffer 40%, leverage 2x, sensitivity 1 USDT per 0.01, holding/day 0.28752, T 11.042042042. -10% gives equity 400, leverage 2.25 and buffer 33.333333%; -20% gives equity 300 and buffer 25%. User quantity gives 52.775681 sensitivity. GET-only fake adapter and old/new accounting fixtures pass.

Command: `flutter test test/features/portfolio/risk/risk_engine_test.dart test/features/portfolio/risk/risk_repository_test.dart --plain-name GREEN-001 --reporter compact`
Actual: PENDING
Status: PENDING

Execute RED before GREEN at the formal checkpoint. After implementation/test-support changes restart the pair under the governing direct-user AGENTS instruction. Verification ceiling: V2. Escalation only for an evidenced shared-surface regression or missing AC evidence. Final full-suite ownership belongs to coordinator integration, not each task.

## 8. Stop Conditions

Return BLOCKED for missing material contract, incompatible API semantics beyond explicit unavailable handling, scope expansion, failed prerequisite, unavailable necessary verification or an explicit model mismatch. Include evidence, affected IDs and needed coordinator decision. Do not silently reduce full scope.

## 9. Execution Ledger

- [x] Definition of Ready and authorization confirmed
- [ ] Referenced symbols inspected
- [ ] Assigned P01 implemented within allowed scope
- [ ] Required tests/fixtures added or updated
- [ ] Formal RED executed and observed
- [ ] Formal GREEN executed and observed afterward
- [ ] Verification ceiling respected
- [ ] Compact report: changed files, behavior, commands/results, unresolved limits

## 10. Coordinator Audit

Scope: PASS — implementation changes remain within the seven allowed T18 files.
Acceptance criteria: PASS — AC-001, AC-002, AC-003, AC-005 and AC-006 are implemented and evidenced.
Test quality: PASS — real-shape OKX loan type, identity/selection, coverage, freshness, stress and Recovery/Overall boundaries are covered.
RED evidence: PASS — focused RED-001 completed after the final implementation change.
GREEN evidence: PASS — focused GREEN-001 completed after RED-001.
RED-before-GREEN: PASS
Architecture/contract conformance: PASS — AUD-T18-001 through AUD-T18-012 are closed.
Evidence reuse vs rerun: Fresh post-remediation RED-001 passed before GREEN-001; focused analyze, format and diff checks pass.
Verdict: PASS

### Audit findings

- AUD-T18-001 (HIGH): `interest-accrued` attribution requires a response `posId`, but the official OKX response does not define it. Attribute by the documented instrument/currency/mode and verified episode time window without accepting cross-episode rows; replace the fabricated test payload with the actual response shape.
- AUD-T18-002 (HIGH): full True Exit trusts `coverage.complete` while `completeForPosition` permits missing coverage timestamps. Require explicit verified ledger coverage, unchanged size and a timestamped non-overlap boundary before exposing True Exit.
- AUD-T18-003 (HIGH): stale position quality can be promoted to complete, and position freshness uses source `uTime` as fetch observation time. Preserve stale/unavailable quality and keep fetch observation time distinct from the exchange source timestamp.
- AUD-T18-004 (HIGH): stress evaluations omit entry, liquidation, True Exit and supplied action-zone/map levels. Produce deduplicated per-price scenarios with equity, leverage, buffer and overall state while retaining the required pinned percentage ordering.
- AUD-T18-005 (MEDIUM): old-mode eligibility validates raw `pos` instead of normalized `Q=pos-margin`. Reject normalized Q<=0 and use a supported old/base fixture that proves this boundary.
- AUD-T18-006 (MEDIUM): debt reconciliation warnings and precision limitations are not carried into metric quality/evidence; recovery and scenario reasons omit required source/time/value evidence. Preserve explainable quality and satisfy INV-007 for every engine-generated reason.
- AUD-T18-007 (HIGH): `hasTimestampedCoverage` accepts `coverageTo < nonOverlapAt`, allowing a gap before the rollover boundary. Verified coverage must extend through the boundary; add a negative gap test.
- AUD-T18-008 (HIGH): the cost contract lacks actual interest accrued today with configured/local-day coverage and known subtotal semantics, plus the explicitly projected True Exit between coherent cost fetches (bounded by the 10-minute cost freshness window). Add typed metrics/quality without substituting estimates for verified True Exit.
- AUD-T18-009 (HIGH): `RiskEvaluation` does not preserve the active `RiskPolicy.version`. Carry it in every evaluation so later snapshots cannot be reinterpreted under a different policy.
- AUD-T18-010 (MEDIUM): AC-001 tests do not prove vanished-selection lexical fallback/announcement, explicit short/FUTURES rejection, missing-uid ephemeral behavior, or two-account namespace isolation.
- AUD-T18-011 (HIGH): AC-005 tests do not prove exact Recovery distance 10/20%, holding-burden 1/3%, max(Position, Market, Recovery), partial qualification, or reason changes. Add independently derived boundary assertions and correct the direct old-mode engine fixture to supported base collateral.
- AUD-T18-012 (HIGH): `interest-accrued.type` is the documented loan-type code (`2` = market loan), but DTO matching treats it as textual event prose. Accept the official code semantics, reject incompatible explicit types, and prove an actual-shape `type: "2"` row in repository tests.
