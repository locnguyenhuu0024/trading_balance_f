# Task 19 — Market environment and explainable risk

Status: PASS
Executor: implementation executor (configured target gpt-5.6-luna / max; verify effective routing)
Specification: `docs/agents/specs/2026-09-10-isolated-margin-risk-dashboard-design.md`
Plan: `docs/agents/plans/2026-09-10-isolated-margin-risk-dashboard.md`
Plan Steps: P02
Requirements: REQ-004, REQ-005
Acceptance Criteria: AC-004, AC-005

## 1. Objective

Complete the single auditable outcome in canonical plan §5 P02. Done when the referenced ACs and required negative/success scenarios are observed, scope is audited and coordinator verdict is PASS. Do not substitute a summary for repository evidence.

## 2. Preconditions

Predecessors: T18 = PASS.
Required decisions: D-001–005, A-001. Explicit execution approval of the presented plan is mandatory before dispatch. Coordinator confirms Definition of Ready and reads execution/audit rules. Inspect applicable AGENTS and context optimization profile; preserve existing user changes. Read only relevant specification sections and P02, not all framework/templates.

## 3. Allowed Scope

- `lib/features/portfolio/domain/risk/market_risk_engine.dart`
- `lib/features/portfolio/data/risk/risk_market_repository.dart`
- `lib/features/portfolio/domain/risk/risk_models.dart (market integration only)`
- `lib/features/portfolio/domain/risk/risk_engine.dart (typed market input integration only)`
- `test/features/portfolio/risk/market_risk_engine_test.dart`
- `test/features/portfolio/risk/risk_market_repository_test.dart`

Synthetic fixtures may be created under `test/features/portfolio/risk/fixtures/`. No real account payloads. Executor reports evidence to coordinator; coordinator owns planning/audit metadata and task allocation.

## 4. Forbidden Scope

No unrelated refactors, generated Orders DTO changes, trading API writes, dependency changes, deployment, Git mutations, real credential reads or private API calls. No external services beyond explicitly authorized official OKX documentation. No product-semantic decisions outside the specification. Return BLOCKED if required work exceeds the write surface.

## 5. Executor Contract

Follow canonical P02 in order. Use specification formulas/defaults and missing-data behavior exactly. Domain functions are pure and platform code must reuse them. Honor all applicable INV/EDGE entries called out by P02. Incomplete API data uses specified quality states; do not invent neutral or zero values. User-authored plan text remains text, never a trading command.

Before handoff inspect the diff, scope, changed symbols and test evidence. Do not claim runtime/native verification from mocks. If effective executor model is explicitly reported different from configured target, report BLOCKED.

## 6. Tests

Test files above implement RED-002/GREEN-002 prefixes and independently derived expectations below. Use injected time, storage, HTTP and platform interfaces. Narrow diagnostics first; do not run broad suites during each edit. Existing compatibility checks are listed in the canonical plan.

## 7. Mandatory Verification

### RED — RED-002

Scenario and expected outcome: Position CRITICAL + favorable complete market stays CRITICAL. Missing OI, zero volatility and incomplete candles are unavailable/partial; funding alone cannot classify bullish/bearish. Derivatives context must not accrue margin holding costs.

Command: `flutter test test/features/portfolio/risk/market_risk_engine_test.dart test/features/portfolio/risk/risk_market_repository_test.dart --plain-name RED-002 --reporter compact`
Actual: Coordinator observed 8/8 RED-002 tests pass after final remediation.
Status: PASS

### GREEN — GREEN-002

Scenario and expected outcome: Synthetic four price/OI quadrants yield documented factor labels/points; normalized 8h funding uses actual interval; asset breakdown and BTC modifier produce HIGH; a WATCH position plus HIGH market yields HIGH with source/time/value reasons. Confirmed support recovery clears the adverse factor only.

Command: `flutter test test/features/portfolio/risk/market_risk_engine_test.dart test/features/portfolio/risk/risk_market_repository_test.dart --plain-name GREEN-002 --reporter compact`
Actual: Coordinator observed 6/6 GREEN-002 tests pass after RED at the final checkpoint.
Status: PASS

Execute RED before GREEN at the formal checkpoint. After implementation/test-support changes restart the pair under the governing direct-user AGENTS instruction. Verification ceiling: V2. Escalation only for an evidenced shared-surface regression or missing AC evidence. Final full-suite ownership belongs to coordinator integration, not each task.

## 8. Stop Conditions

Return BLOCKED for missing material contract, incompatible API semantics beyond explicit unavailable handling, scope expansion, failed prerequisite, unavailable necessary verification or an explicit model mismatch. Include evidence, affected IDs and needed coordinator decision. Do not silently reduce full scope.

## 9. Execution Ledger

- [x] Definition of Ready and authorization confirmed
- [x] Referenced symbols inspected
- [x] Assigned P02 implemented within allowed scope
- [x] Required tests/fixtures added or updated
- [x] Formal RED executed and observed
- [x] Formal GREEN executed and observed afterward
- [x] Verification ceiling respected
- [x] Compact report: changed files, behavior, commands/results, unresolved limits

## 10. Coordinator Audit

Scope: PASS — final changes remain within the allowed T19 surface.
Acceptance criteria: PASS — public OKX shapes, market factors, missing/stale semantics and explainable evidence match P02.
Test quality: PASS — independently derived boundary, malformed-data, source-quality and public-query fixtures cover the contract.
RED evidence: PASS — 8/8 observed by coordinator after final code/test-support change.
GREEN evidence: PASS — 6/6 observed by coordinator after RED.
RED-before-GREEN: PASS
Architecture/contract conformance: PASS
Evidence reuse vs rerun: Coordinator reran final RED then GREEN; focused analyzer reported no issues. Independent advisor returned PASS.
Verdict: PASS

Audit findings:

- AUD-T19-001: `GET /api/v5/market/candles` does not accept a `confirm` request parameter. Remove it from the request while continuing to retain only response rows whose `confirm` field is `1`; update tests to prove both behaviors.
- AUD-T19-002: `GET /api/v5/public/open-interest` returns current OI and does not accept `limit`. Remove the history/limit contract and represent the response as current observation(s). Historical samples remain injected/persisted by P03 before the engine computes a 4-hour delta.
- AUD-T19-003: Map only `oiCcy` for currency-unit OI. Do not substitute contract-count `oi` when `oiCcy` is absent; expose the factor as unavailable until a valid `oiCcy` sample exists.
- AUD-T19-004: Strengthen repository tests to assert the exact public query shapes and a realistic single-row current-OI response, while preserving the first-four-hours missing-delta behavior in the domain engine.
- AUD-T19-005: Explainable factor reasons currently stamp evaluation time instead of their source observation/candle time. Carry the relevant confirmed candle, funding or OI timestamp into each reason so history/event identity can trace the actual evidence.
- AUD-T19-006: Expand focused domain evidence for the nonzero volatility estimator and 3%/6% boundaries, EMA/support/breakdown boundaries, positive-funding conjunction, and OI time tolerances/stale-current rejection. Use independently derived expected values rather than mirroring implementation helpers.
- AUD-T19-007: Duplicate or out-of-order OI timestamps must make the OI relationship unavailable/partial under EDGE-004. Do not sort and silently deduplicate malformed history into usable evidence; add RED coverage at the repository/domain boundary.
- AUD-T19-008: Preserve per-source failure semantics for funding and OI. Request failure (including status/endpoint), missing matching instrument, and malformed payload must not collapse to indistinguishable `null`/empty data; carry typed quality/missing metadata into the snapshot/evaluation and test the distinctions without exposing secrets.
- AUD-T19-009: When the engine rejects the current OI observation for exceeding the 5-minute freshness window, derive and expose `RiskQualityStatus.stale` through both evaluation and typed market input. Do not leave source-specific OI quality as `complete`; assert the propagation in the stale-current RED fixture.
