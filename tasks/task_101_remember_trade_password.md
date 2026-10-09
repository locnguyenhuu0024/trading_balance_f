# Task 101 — Remember trade password and optimize form

Status: PASS
Agent Role: implementation_executor
Executor Class: E1
Target Model: gpt-6-luna
Target Effort: xhigh
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Dispatch Route Status: UNVERIFIABLE
Dispatch: immediate reuse of the same E1 executor originally explicitly spawned with gpt-6-luna/xhigh for T100. No inheritance/default substitution; effective route unavailable.
Specification: docs/agents/specs/2026-10-09-app-simplification-design.md
Plan: docs/agents/plans/2026-10-09-app-simplification.md
Plan Steps: P02
Requirements/Acceptance: REQ-002/003 / AC-002/003
Frontend Level: F1
Predecessor: T100 PASS

Allowed: secure_storage_helper.dart password methods; trade_api_client.dart optional safe endpoint capability; trade_account_controls.dart login dialog/caller only; targeted auth/security tests. Implement exact specification password contract, including immediate opt-out deletion, no false deletion acknowledgment, only same-session successful save, secure web inheritance, OTP clearing, storage errors, pending/state races. Preserve TradeApi interface/fake compatibility. All other config/product/dependency/trade mutation semantics forbidden. No logging secrets, task/telemetry/Git writes or subagents.

RED-002: invalid OTP zero request, opt-out delete with canceled/failed sign-in, failed checked auth no save, storage read/delete/save failures safe, duplicate pending submit once, changed session/endpoint/disposed view cannot save stale password. GREEN-002: successful checked login saves endpoint-scoped password; reopen masked prefill/checked checkbox/empty OTP, editable/show-hide, unchecked success no password. Formal named RED tests before GREEN tests; independent expected results in spec. V3 relevant auth/security/session tests, escalate only demonstrated broader dependency. Task buildability YES `flutter build web --no-pub` after last edit. External config actions none.

- [x] implement
- [x] RED then GREEN
- [x] relevant tests/build
- [x] independent audit PASS

Audit: PASS. Coordinator inspected all three production files, additive auth tests and native secure-storage channel tests. Passwords stay in endpoint-scoped secure storage; no WebStorageHelper plaintext override. API identity guarded before transmission; session/endpoint guarded before and after save; serialized version cleanup preserves newer writes. OTP is not stored, cleared per attempt, keyboard submit respects delete-failure guard. Opt-out retains input and deletes saved record; failures get truthful generic feedback. Ordered stale-session negative then remember-success positive passed after final source change; other focused negative/success cases and two secure-store tests passed. Fresh `flutter build web --no-pub` exit0 after final source edit. Original explicitly bound E1 Luna/xhigh reused, effective route UNVERIFIABLE. No protected changes/external actions; native/browser device validation unavailable. Final full suite remains coordinator-owned.
