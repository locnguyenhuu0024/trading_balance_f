# Task 87 — Show Strategy Direction on Cards
Status: PASS
Plan: docs/agents/plans/2026-10-06-strategy-card-direction.md#P01
Agent Role: implementation_executor
Executor Class: E0
Target Model: gpt-6-luna
Target Effort: high
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Dispatch Route Status: UNVERIFIABLE

## Objective and allowed scope
Implement P01 display contract. Allowed files only lib/features/strategy/presentation/strategy_screen.dart and test/features/strategy/strategy_screen_test.dart. Plan defines exact sides/legacy/candidate/unknown label semantics, Wrap layout and test scenarios. No product/architecture decisions open.
Forbidden: protected configuration content access/mutation; unrelated files/refactors, backend/API/dependencies, generated code, task/checklist/telemetry writes, Git mutations, external services or child spawning.

## Verification
Capture baseline missing-label failure if practical. Formal RED negative evidence first, GREEN exact per-card directions second; record exact commands/status. Then flutter test --no-pub test/features/strategy/strategy_screen_test.dart (V2), format only changed Dart files, targeted analyze if appropriate. Task build flutter build web --no-pub --release after last executable edit; consumes config opaquely. Coordinator handles final macOS and Python builds. Stop on concrete contract/environment blocker; no configuration changes to resolve it.
Return terminal compact report: changed files, test names/commands and RED-before-GREEN results, build status/freshness, protected-access confirmation and external actions none; telemetry envelope E0-T87-001 with unavailable effective route unless exposed. Coordinator owns task status/audit.

## Coordinator audit
PASS: exact source/test diff, labels and fallbacks, RED-before-GREEN, 25 screen tests, E0 explicit route, final Python/web/macOS builds. No protected content access/mutation or external actions. Audit: docs/agents/audits/2026-10-06-strategy-card-direction.md.
