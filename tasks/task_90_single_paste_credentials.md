# Task 90 — Single-paste OKX Credentials

Status: PASS
Agent Role: implementation_executor
Executor Class: E1
Target Model: gpt-6-luna
Target Effort: xhigh
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Dispatch Route Status: UNVERIFIABLE (explicit gpt-6-luna / xhigh submitted; effective route not exposed)
Specification: `docs/agents/specs/2026-10-07-single-paste-credentials.md`
Plan: `docs/agents/plans/2026-10-07-single-paste-credentials.md` / P01
Requirements / Acceptance: REQ-001..005 / AC-001..005

## Bounded Contract
Implement the referenced specification exactly. Allowed writes:
- `lib/features/settings/presentation/settings_trade_access_page.dart`
- `lib/features/settings/domain/okx_credential_bundle.dart`
- `test/features/settings/okx_credential_bundle_test.dart`
- `test/features/settings/settings_trade_access_page_test.dart`
Executor may return an evidence report in terminal output; coordinator owns task/checklist/telemetry writes.
Forbidden: protected config contents/writes, unrelated source, storage helper changes, backend/session behavior, dependencies, network/exchange actions, secret logging, recursive agents. Read AGENTS.md and context-optimization profile; RTK first when eligible, exact source/diff output is an allowed exception.

## Execution and Verification
Tests use synthetic values, fake storage and fake trade-session dependencies. Observe a meaningful feature regression failure before product edit when feasible; never treat compilation or runner failure as behavioral RED.
Formal RED-001 first: invalid/duplicate/missing bundle yields generic rejection and zero save calls. Then GREEN-001: valid bulk paste produces exact three storage args and saved summary. Run full two relevant files, V2 ceiling; selectively rerun evidence invalidated by edits.
Task Buildability Gate: YES. Unit: Flutter web. Command: `flutter build web --no-pub` after last executable edit. Return exact command, exit/status, behavioral test counts and order. Do not PASS without actual build success.
Stop for missing material decision, protected-config need, or required writes outside scope. Do not self-escalate route.
External configuration actions / external verification: none.

## Ledger
- [x] explicit role/model/effort binding (effective route unavailable)
- [x] baseline and formal RED/GREEN evidence in integration audit
- [x] parser and UI tests pass: 20 tests, exit 0, after T91
- [x] affected web build PASS after final executable change: `flutter build web --no-pub`, exit 0
- [x] safe scope and no protected config content access/write
- [x] coordinator audit PASS

## Coordinator Audit
Scope / AC / RED-GREEN / build / verdict: PASS. Evidence: `docs/agents/audits/2026-10-07-single-paste-credentials.md`. Existing-helper storage non-atomicity remains unchanged; no live connection verification claimed.
