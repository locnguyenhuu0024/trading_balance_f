# Jev Automatic Strategy Implementation Plan

Status: COMPLETE
Date: 2026-10-05
Tier: L
Specification: docs/agents/specs/2026-10-05-ai-jev-auto-strategy.md
Decisions: docs/agents/decisions/2026-10-05-ai-jev-auto-strategy.md
Authorization: User explicitly permits execution after planning for this session and self-answered clarifications.
Coordinator: C2, current runtime model fixed; preferred gpt-6.1-sol/high not claimed as observed.

## Workstream gate

| Workstream | Material | Independent | Requested route | Logical run | Adoption |
|---|---|---|---|---|---|
| Frontend/review | YES | YES | R2 / gpt-6.1-sol / medium | R2-JEV-FE-001 | COMPLETE / USED |
| Backend/data/provider boundary | YES | YES | R2 / gpt-6.1-sol / medium | R2-JEV-BE-001 | COMPLETE / USED |

Fan-out Required: YES; Required Reasoning Agents: 2; Actual Reasoning Agents: 2; Fan-out Compliance: PASS; Skip Reason: N/A. Both requests explicitly bound model/effort and forbade inheritance; effective routes unavailable (UNVERIFIABLE). Coordinator resolved incomplete Draft semantics with same-record materialization and immutable provenance.

## DAG and task boundaries

P01 / T84 (backend, E2 Luna/max) || P02 / T85 (Flutter, E1 Luna/xhigh) -> individual audit/build -> final integration audit.

Execution decomposition revision: the finalized API/JSON specification is the shared predecessor and is READY. Backend and frontend writers have disjoint source/test/doc write surfaces and independent mocked verification/build graphs (Python versus Flutter). Neither depends on unfinished implementation output; source algorithms remain read-only to backend. SQLite test state is temporary, Flutter cache is used only by frontend, and no manifests/generated shared schema are edited. Both are independently buildable. Two writers may share the first wave; cross-layer audit follows both terminal reports.

T84: port existing calculator faithfully, public market candle acquisition, versioned context and official SDK adapter, candidate-stage persistence/API/idempotency, materialization/apply guards, backend mocked tests, developer setup documentation. Write only backend permitted business source/test and docs/development/ai-jev-strategy.md. Never touch configuration sections/manifests/credentials.
T85: optional automatic API capability, candidate parsing, icon/title entry action, selectors, saved-review wizard initialization/rank display, manual materialization, dashboard action guards, Flutter focused tests. Write only strategy source/tests. Avoid adding a new mandatory abstract method to StrategyApi that breaks unrelated fake implementors; separate capability interface is acceptable.

## Verification

T84 formal RED-084 before GREEN-084: `python3.12 -m unittest backend.tests.test_strategy_automatic -v`, individual red cases then green cases as listed by executor. V3 ceiling includes existing strategy API/worker/retry/queue tests. Affected build `python3.12 -m compileall -q backend` after last code change.
T85 formal RED-085 before GREEN-085: focused newly added tests first, then strategy tests `flutter test --no-pub test/features/strategy`; format `dart format` only permitted changed Dart files; analyze targeted strategy source. Affected build `flutter build web --no-pub --release`.
Final: one full backend discovery suite plus Flutter suite as justified for cross-layer feature, final web and macOS release builds (README declares both platforms). Builds consume protected inputs opaquely; do not run release_build.sh because it deploys. Reuse trustworthy post-change build evidence; rerun only invalidated evidence.

## Rollout, limitations and completion

Default disabled. Install/configure provider in backend process only for live use, documented exact placeholders/restart steps; mocked acceptance does not require live secrets. No migration. No production thresholds/calibration/backtesting. Candidate-generation latency includes public data reads and bounded AI deadline. No executor recursion, no direct coordinator implementation, no commit/push/deploy. Completion requires task PASS, RED/GREEN, successful final canonical builds, focused diff and zero protected file access/mutation.

## Final integration

T84 PASS and T85 PASS. Backend 249 tests pass; Strategy Flutter 123 pass; calculator parity 45 fixtures pass. Full Flutter has 481 passes and four pre-existing source/test navigation mismatches confirmed by independent source review. Final compileall, web release and macOS release builds pass. Both independent final reviews pass after four backend remediations. Live provider activation is the explicitly external user-owned action. No protected configuration mutation; one stopped mixed-file inspection deviation is documented in decisions/audit, so the original zero-access objective was not fully met. Product behavior and build acceptance completed; no commit/push/deploy.

Follow-up navigation repair completed under WF-20261005-NAV-002: all four reported test failures resolved; full Flutter now passes 485 tests. Final release builds pass. See 2026-10-05-navigation-test-repair.md for bounded scope and RED/GREEN evidence.
