# Implementation Plan: Single-paste OKX Credentials

Status: COMPLETE
Date: 2026-10-07
Tier: M
Specification: `docs/agents/specs/2026-10-07-single-paste-credentials.md`

## Authorization and Routing
User explicitly authorized planning and execution together after accepting the described approach. C1 standard reasoning / low orchestration; current coordinator runtime retained (effective model/effort unavailable).

## Planning Workstreams
| Workstream | Material | Independent | Requested route | Logical run | Status |
|---|---|---|---|---|---|
| Local credential-entry UI/parser/lifecycle | YES | single atomic contract | R1 / gpt-6.1-sol / low | R1-CREDENTIAL-001 | COMPLETE / USED; masking and duplicate constraints incorporated |
| Persistence/API/backend | NO | N/A; unchanged helper | N/A | N/A | observed unchanged |
Fan-out Required: NO. Required Reasoning Agents: 0. Actual Reasoning Agents: 1 optional review.
Fan-out Compliance: EXCEPTION. Skip Reason: SINGLE_MATERIAL_WORKSTREAM.
The parser's validation is part of the UI input contract; storage/security architecture remains unchanged.

## P01 / T90 — Bulk Entry and Saved Summary
Implement REQ-001..005 / AC-001..005 as one independently buildable task.
Allowed product files: page `lib/features/settings/presentation/settings_trade_access_page.dart`, new parser `lib/features/settings/domain/okx_credential_bundle.dart`.
Allowed tests: new `test/features/settings/okx_credential_bundle_test.dart`, new `test/features/settings/settings_trade_access_page_test.dart`.
No helper/backend/configuration/dependency modifications. No exchange/network operations during tests; fake storage/session providers.
1. Add independent behavioral tests and observe baseline feature failure.
2. Implement exact parser contract, page state, masked paste/manual entry and saved summary.
   Use an explicit clipboard paste button to preserve multiline text; verified native Flutter single-line formatter otherwise removes newlines. Clipboard reads occur only after that user action.
3. Execute formal negative-path RED then primary-success GREEN, followed by the two relevant files (V2 ceiling).
4. Run `flutter build web --no-pub` after final executable edits, then return evidence.
5. Coordinator audits scope, tests, route, and final build; any permitted remediation is delegated.

## Verification Budget and Stop Conditions
Commands: `flutter test --no-pub --reporter compact test/features/settings/okx_credential_bundle_test.dart test/features/settings/settings_trade_access_page_test.dart`; selected test names for narrow checkpoints.
Canonical affected/final build unit: Flutter web app; `flutter build web --no-pub`.
Repository-native tools consume configuration as opaque input only; do not inspect it. If native tools mutate protected paths, stop and report metadata without content diff. V3 only if shared behavior is actually changed; V4 not planned. Build evidence is reusable for final audit if no later executable edit occurred. Exact command/status required.
External configuration/environment actions: none. External service verification: none. Toolchain failure: diagnose narrowly and use one safe native retry, never change config to bypass it.
Rollback: revert only new parser/tests and page implementation; saved storage keys are unchanged.

## Completion Gate
- [x] bounded requirements and direct execution authorization
- [x] planning coverage classified
- [x] T90 implementation and behavioral evidence; T91 bounded test-finder remediation PASS
- [x] post-change affected/final web build PASS, `flutter build web --no-pub`, exit 0
- [x] coordinator audit PASS, `docs/agents/audits/2026-10-07-single-paste-credentials.md`
