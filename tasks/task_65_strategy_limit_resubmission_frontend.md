# Task 65 — Selective Limit Resubmission Frontend

Status: PASS
Agent Role: implementation_executor
Executor Class: E1
Target Model: gpt-6-luna
Target Effort: xhigh
Target Route: gpt-6-luna / xhigh
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Specification: `docs/agents/specs/2026-10-03-strategy-limit-cap-resubmission-design.md`
Plan: `docs/agents/plans/2026-10-03-strategy-limit-cap-resubmission.md`
Plan Steps: P04
Requirements: REQ-008,009
Acceptance Criteria: AC-008,009

## 1. Dispatch Compliance

Bind role, class, model and effort explicitly before mutation; coordinator remains non-writing for implementation. Dispatch Route Status: UNVERIFIABLE. Requested Model: gpt-6-luna. Requested Effort: xhigh. Observed Effective Model/Effort: unavailable. Explicit request without exposed effective route may be UNVERIFIABLE; mismatch stops mutation; unavailable binding is BLOCKED_ROUTE, never inherited fallback.

## 2. Objective

Add an explicit review-and-confirm retry modal backed by authoritative candidates and one linked child execution.

Done when assigned acceptance tests, RED-before-GREEN, affected-unit build and independent coordinator audit all PASS.

## 3. Preconditions

Predecessors: T63 and T64 = PASS.
Decisions: D-001..004, A-001..002 in current decision ledger. Canonical plan must be presented and explicitly authorized after presentation before dispatch. Source baseline includes audited T61 diagnostics.

## 4. Allowed Scope

- `lib/features/strategy/domain/strategy_models.dart`
- `lib/features/strategy/data/strategy_api_client.dart`
- `lib/features/strategy/presentation/providers/strategy_dashboard_provider.dart`
- `lib/features/strategy/presentation/strategy_screen.dart`
- `lib/features/strategy/presentation/strategy_retry_dialog.dart (new)`
- `test/features/strategy/strategy_retry_dialog_test.dart (new)`
- `test/features/strategy/strategy_api_client_test.dart`
- `test/features/strategy/strategy_dashboard_controller_test.dart`
- `test/features/strategy/strategy_screen_test.dart`
- `test/features/strategy/strategy_wizard_dialog_test.dart`
- `test/features/strategy/strategy_settings_dialog_test.dart`

## 5. Forbidden Scope

No protected configuration content access or mutation, dependencies, manifests, env, Docker/scripts/CI/deployment settings, schema/store changes, live orders, external uploads, Git writes, canonical artifact/status/telemetry writes or opportunistic refactors. Listed explanatory Markdown is allowed documentation. Required work beyond this surface returns BLOCKED for coordinator replan.

## 6. Executor Contract

1. Add strict typed candidate/preview/child lineage DTOs and three API client methods per specification. Update existing API fakes in wizard/settings/controller/screen tests in the same buildable boundary.
2. Add separate Gửi lại lệnh limit card action and responsive scrolling modal. Fetch authoritative candidates; select by sourceClientOrderId, never index. Display excluded reasons; require an explicit1..10 subset, especially when historical eligible count exceeds10. No truncation or entry-nearest rule.
3. Flow: candidates -> fixed preview -> linked draft -> prepare -> exact confirmation -> single execute -> read-only refresh. Show exact retained price/contracts/leverage, fresh costs, current frozen mode and original/child history links. Do not repurpose ordinary recreate wizard.
4. Generate random retryRequestId using Dart standard library and retain for this flow. Capture immutable reviewed selection/hash. Validate returned source/child linkage, exact ordered source/child payload, financial review and mode before confirmation/execute; malformed or mismatched responses stop.
5. Use the existing controller action lock across Apply/retry and source/child; check ownsSession after every await, including before execute. Cancel/logout/account switch/double tap cannot execute. Uncertain create/execute responses trigger read-only refresh, never automatic write retry.
6. Keep unclaimed PREPARED child visible when confirmation is canceled or token lost; normal expiry/refresh applies. Do not automatically delete, recreate or mint another token. Explain positions/pending/reservation/stale blockers and direct the user to fresh review.

Preserve specification INV-001..006 where affected. Requirements/architecture are coordinator-owned; report contradictions instead of inventing semantics or escalating routes.

## 7. External Configuration / Environment Actions

Planned actions: NONE. Additional unknown configuration requirements: BLOCKED; ask minimum safe fact via coordinator. No user-applied configuration required for offline verification.

## 8. Tests

TEST-65: API DTO/route tests, retry modal, dashboard controller and screen plus existing wizard/settings fake compatibility. Use controlled completers to verify session changes at each asynchronous stage and call counts.

## 9. Mandatory Verification

### RED — RED-004

Scenario: Malformed/oversized/wrong-source/review mismatches, cancel, logout/account switch, double tap and uncertain responses produce zero extra execute writes; excluded rows cannot be selected.
Method: offline focused cases within allowed test files; executor reports exact case names and RTK/native command before terminal report. Expected: all negative safety assertions PASS with explicit call/state counts. Actual/status: PASS; coordinator formal RED15 then GREEN2, exit0, exact commands below.

### GREEN — GREEN-004

Scenario: Mixed eligible<=10 is reviewed exactly and confirmed once; source/new child links and safety blockers render; modal is usable at narrow and desktop widths.
Method: separate offline focused cases after RED; exact command/case names recorded. Expected: successful behavior and preserved invariants PASS. Actual/status: PASS; coordinator formal RED15 then GREEN2, exit0, exact commands below.

Run formal RED then GREEN after readiness; RED is a passing negative scenario, not a deliberately failing suite. Narrow diagnostics during editing are not formal evidence. Later executable changes invalidate affected evidence only. Verification ceiling: V3 affected groups; V4 not required. Broaden only for a concrete regression/shared-path risk and record why. RTK-first; exact/raw fallback only with evidence/compatibility reason. WSGI loopback tests may require sandbox escalation; do not diagnose by opening config.

### Task Buildability Gate

Required: YES. Unit: Flutter web. Boundary: self-contained compatible change; no later task restores compilation.

```sh
/Users/locnguyen/.local/bin/rtk flutter build web --no-pub --release --dart-define=TRADE_API_BASE_URL=https://api.tradingbalancef.com
```

Run after final task-local executable/test edit. Result/status/exit/errors: PASS / exit0 / no build errors; release completed after final executable/test edits. Tests are not substitutes for canonical application build. Code failure => REWORK; genuine toolchain pre-build failure => BLOCKED_ENVIRONMENT. Consume configs only as opaque native-tool input.

### External Verification

Required: NO. Offline fake exchange only; production behavior is not verified.

## 10. Stop Conditions

Return BLOCKED for insufficient contract, ownership/lineage ambiguity, scope mismatch, predecessor invalidation, required protected facts or unavailable verification; report affected REQ/AC and concise evidence. Do not change architecture or broaden surface unilaterally.

## 11. Execution Ledger

- [x] Explicit dispatch and no parent inheritance verified.
- [x] Assigned step and tests implemented within surface.
- [x] Formal RED then GREEN PASS with exact names/commands/results.
- [x] V3 affected regressions sufficiently verified.
- [x] Final affected-unit build PASS after last executable edit.
- [x] No protected content access or modification; external actions NONE.
- [x] Compact terminal report and safe telemetry envelope returned; no runtime IDs persisted.

## 12. Coordinator Audit

Scope/AC/test quality/RED/GREEN/order/contract/dispatch/build: PASS. Evidence reuse: affected81 and final release build; coordinator reran focused RED15 then GREEN2 to provide exact readiness evidence. Verdict: PASS. Audit: `docs/agents/audits/2026-10-03-task65-limit-resubmission-audit.md`. Coordinator records audit and canonical status; executor does not.

## 13. Final Evidence

```sh
/Users/locnguyen/.local/bin/rtk flutter test test/features/strategy/strategy_api_client_test.dart test/features/strategy/strategy_dashboard_controller_test.dart test/features/strategy/strategy_retry_dialog_test.dart --name 'retry DTOs require|T65 stops on wrong|T65 rejects excluded|T65 desktop keeps|T65 cancel during pending|T65 session switch|T65 serializes retry and Apply|T65 uncertain create and execute writes|T65 malformed execute acknowledgment|T65 cancel after PREPARED'
# PASS15, exit0
/Users/locnguyen/.local/bin/rtk flutter test test/features/strategy/strategy_dashboard_controller_test.dart test/features/strategy/strategy_retry_dialog_test.dart --name 'T65 retries the exact linked order|T65 narrow dialog follows fixed preview'
# PASS2, exit0
```

Affected commands, all exit0: `/Users/locnguyen/.local/bin/rtk flutter test <file>` for:

- `test/features/strategy/strategy_api_client_test.dart`:10 PASS.
- `test/features/strategy/strategy_dashboard_controller_test.dart`:35 PASS.
- `test/features/strategy/strategy_retry_dialog_test.dart`:4 PASS.
- `test/features/strategy/strategy_screen_test.dart`:6 PASS.
- `test/features/strategy/strategy_wizard_dialog_test.dart`:16 PASS.
- `test/features/strategy/strategy_settings_dialog_test.dart`:10 PASS.

Canonical build in §9 PASS after final edit. Effective route unavailable UNVERIFIABLE; executor terminal result collected. Optional separate widget executor was unavailable due runtime thread limit; original E1 executor completed all widget work. No alternate route, configuration action or production verification.
