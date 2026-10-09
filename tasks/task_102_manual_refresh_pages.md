# Task 102 — Manual refresh on every page

Status: PASS
Agent Role: implementation_executor
Executor Class: E1
Target Model: gpt-6-luna
Target Effort: xhigh
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Dispatch Route Status: UNVERIFIABLE
Dispatch: immediate reuse of the same E1 executor originally explicitly bound gpt-6-luna/xhigh; no parent/default substitution.
Specification: docs/agents/specs/2026-10-09-app-simplification-design.md
Plan: docs/agents/plans/2026-10-09-app-simplification.md
Plan Steps: P03
Requirements/Acceptance: REQ-004 / AC-004
Frontend Level: F1
Predecessor: T101 PASS

Allowed: nine page files named in P03 and focused page tests, optional core/widgets/manual_refresh_button.dart only if useful. Add/reuse one consistent accessible button per page with `Làm mới dữ liệu` tooltip, visible during empty/error/signed-out states, disable pending/unavailable controls; await reads and coalesce double taps. Orders refreshes current tab/provider preserving filters. Settings exchange rate refresh only, API saved summary refresh keeps editor/controllers + stale generation fence. Preserve pull refresh and automatic polling/session terminal guards, no trade writes or authentication/logout. Do not alter drafts or preference values. No dependencies/config/protected content/Git/task/telemetry writes/subagents.

RED-003: double pending taps one request; signed-out no private read; errors recoverable; settings preferences/API drafts/current Orders tab/filter retained after completion. GREEN-003: every seven destinations + two detail pages rendered refresh invokes proper read once and shows fresh response. Existing BMAG/Support/Strategy controls reused. Formal negative RED before positive GREEN, V3 affected pages tests; final full suite coordinator-owned. Task buildability YES `flutter build web --no-pub` after last executable edit. F1 pinned UI checklist self-check, small viewport/keyboard overflow tests. External configuration actions none. Return exact commands, behavioral results, build freshness, visual evidence limits and explicit-route metadata.

- [x] implement
- [x] RED then GREEN
- [x] affected tests/build
- [x] independent audit PASS

Audit: PASS. Coordinator inspected all nine production pages, shared control and eight affected test diffs. AUD-102-001 fixed with page-level shared toolbar/pull guards; Orders retained pull handlers use guarded current-tab read. Pending rate completion after Portfolio disposal starts no private read. Settings compact timezone dropdown preserves native key/value semantics. Negative RED-102 group passed 3/3 before final affected positive group (74 tests); final Portfolio lifecycle-negative and file9/9 followed its last local edit. Fresh elevated RTK Flutter build web --no-pub exit0 after final source edit. Explicit original E1 Luna/xhigh reuse, effective UNVERIFIABLE. No protected changes/external configuration action; screenshot/native evidence unavailable. Final independent integration audit remains separately pending.

AUD-102-001 (in-flight source audit): Portfolio rate+balance handler and Market handler require a page-level guard shared by toolbar and pull refresh, because the shared toolbar widget lock cannot cover RefreshIndicator callbacks. Add cross-control pending behavioral coverage; rerun invalidated negative then primary positive and build after remediation. This is the existing coalescing contract, not added scope.
