# Task 45 — Strategy preview failure diagnostics

Status: PASS
Agent Role: implementation_executor
Executor Class: E1
Target Model: gpt-6-luna
Target Effort: xhigh
Target Route: gpt-6-luna / xhigh
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Specification: `docs/agents/specs/2026-10-02-strategy-preview-failure-diagnostics.md`
Plan: `docs/agents/plans/2026-10-02-strategy-preview-failure-diagnostics.md`
Plan Steps: P01
Requirements: REQ-001, REQ-002
Acceptance Criteria: AC-001, AC-002

## Dispatch and objective

Dispatch Route Status: UNVERIFIABLE. Requested route: gpt-6-luna / xhigh. Observed effective route: unavailable. The coordinator explicitly dispatched an `implementation_executor` with the exact model and effort above. The safe strategy preview failure messages, structured-error preservation, and manual retry are implemented.

## Scope

Allowed writes: `lib/features/strategy/data/strategy_api_client.dart`, `test/features/strategy/strategy_api_client_test.dart`, and, only for a focused retry regression test, `test/features/strategy/strategy_wizard_dialog_test.dart`. No wizard product-code change is preauthorized. Do not read or modify protected configuration/environment files. Do not modify backend, trading logic, API contracts, dependencies, or other files. Stop and report if a wider fix is required.

## Contract

1. Preserve nonempty structured backend `message`, `statusCode`, `code`, and `details` as today, including 401 session-expiry behavior in the wizard.
2. For a missing message, map HTTP status or Dio failure type to concise Vietnamese guidance and a safe diagnostic marker per the specification. Never show raw body, token, URL, request payload, or exception internals. Do not auto-retry.
3. Add focused fake-adapter tests for unstructured 404/429/5xx, connection/timeout, structured 422, and 401. Add a wizard retry test only if current coverage does not prove failure then success.

## RED then GREEN

RED-001: Before a success check, execute focused failure cases and observe safe distinguishable markers for unstructured HTTP and no-response failures. Independently expected: `HTTP 404` differs from `CONNECTION`; neither reveals server body. Current implementation would produce the same generic English message.

GREEN-001: Execute structured 422 and successful preview/retry cases. Independently expected: structured message is unchanged, success reaches Step 3, and manual retry causes one additional request without resetting user inputs. Record actual results and order.

Verification ceiling: V2 focused client and, if changed, wizard test files. Escalate only for a related failure. Buildability gate: `rtk flutter build web --release` after final code/test edit; must PASS before task PASS. No external service verification in this task; production marker requires a separately authorized deploy and user retry.

## Stop conditions and audit

Return BLOCKED if the required response depends on protected configuration facts, the existing client contract is contradicted, or a fix needs a write outside allowed scope. Coordinator audited exact diff, RED-before-GREEN, focused test results, build result, route binding, and absence of protected-path changes. Verdict: PASS.

## Execution evidence

- RED: focused unstructured HTTP and timeout/connection tests failed on the original generic message before implementation.
- GREEN: `rtk flutter test test/features/strategy/strategy_api_client_test.dart` passed 8 tests; `rtk flutter test test/features/strategy/strategy_wizard_dialog_test.dart` passed 9 tests, including one manual retry with preserved inputs.
- Task buildability: `rtk flutter build web --release` passed after the final code/test edit, producing `build/web`.
- Final repository build: Flutter build above and `python3.12 -m compileall -q backend` passed. `git diff --check` passed.
- Scope: only the three approved product/test files changed. No protected configuration file content was read or modified. No external configuration action required. Production error marker awaits a separately authorized deployment and user retry.
