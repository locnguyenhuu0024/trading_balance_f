# Implementation Plan: Strategy preview failure diagnostics

Status: COMPLETE (T45 audited 2026-10-02)
Date: 2026-10-02
Tier: M
Specification: `docs/agents/specs/2026-10-02-strategy-preview-failure-diagnostics.md`
Decision Ledger: N/A

## Objective and scope

Implement REQ-001/AC-001 and REQ-002/AC-002 so the next iPhone failure identifies its safe HTTP/transport category. Do not change backend trading logic, auth, market calculations, proxy/container configuration, or protected files. Preserve current clean committed product state; only planning/telemetry files are uncommitted before execution.

## Planning workstreams

| Workstream | Material | Independent | Requested route | Logical run | Result |
| --- | --- | --- | --- | --- | --- |
| Flutter preview transport and wizard state | YES | YES | R2 / gpt-6-sol / medium, explicit | R2-001 | COMPLETE / USED |
| Backend authenticated preview response contract | YES | YES | R2 / gpt-6-sol / medium, explicit | R2-002 | COMPLETE / USED |

Fan-out Required: YES. Required Reasoning Agents: 2. Actual Reasoning Agents: 2. Fan-out Compliance: PASS. Skip Reason: N/A. Effective child routes were not exposed after explicitly bound requests. Cross-layer synthesis: expected backend failures have structured messages, while the exact screenshot is a client fallback with no such message; the authenticated request's production status remains unknown. The bounded implementation changes only client diagnostics and preserves backend authority.

## Dependency and implementation

One independently buildable task, T45, implements P01. It has no task predecessor. The implementation executor route is E1 / gpt-6-luna / xhigh, explicitly bound, role `implementation_executor`, parent route inheritance forbidden.

P01: In `lib/features/strategy/data/strategy_api_client.dart`, retain nonempty structured server messages; otherwise map Dio status/type to the failure matrix in the specification. Keep `StrategyApiException.statusCode`, `code`, and `details` safe and stable; do not inspect or surface raw response text. In `test/features/strategy/strategy_api_client_test.dart`, use a fake adapter to cover unstructured 404, 429, 5xx, connection, timeout, structured 422, and 401 status preservation. If the existing wizard test lacks explicit retry coverage, add a focused failure-then-success case only in `test/features/strategy/strategy_wizard_dialog_test.dart`; do not alter wizard product code unless a concrete test proves a retry defect, in which case return for scope review.

Allowed product/test writes: the three paths above, with wizard path tests only. Forbidden: backend, deployment/build/dependency configuration, protected configuration contents or writes, other product surfaces, and live OKX requests.

## Verification and completion

Formal RED-001 executes before GREEN-001. V1 uses focused client error tests, then V2 runs `rtk flutter test test/features/strategy/strategy_api_client_test.dart` and the focused wizard test if changed. Escalate to related strategy tests only for a concrete shared failure. Task buildability gate after the last edit: `rtk flutter build web --release` for the Flutter web app. Final integration repeats only invalidated evidence and audits the focused diff/status; no live request is included.

Risk: a status-specific message can be mistaken for a proven root cause. Wording must describe observed category and next action, not assert proxy/CORS/backend guilt. Rollback is reverting the client/test change. No migration or external configuration action. The production fault remains open until the user retries a deployed build and reports its safe marker.

Execution, commit/push, and deployment are separate authorizations under `AGENTS.md`; this plan requests only the T45 code/test execution gate next.

## Final integration audit

T45 PASS. Exact approved implementation scope was respected: one strategy API client and two focused test files. The executor explicitly bound E1 / gpt-6-luna / xhigh; the runtime did not expose the effective route, so dispatch route status is UNVERIFIABLE rather than inherited. RED unstructured HTTP and transport cases failed on the original generic message before GREEN. The client test file passed 8 tests and the wizard test file passed 9 tests, including manual retry with unchanged inputs. `rtk flutter build web --release` passed after the final code/test edit; coordinator also observed `python3.12 -m compileall -q backend` and `git diff --check` pass. No protected configuration path was read or changed. No backend, API, order, or auth behavior changed. The production preview fault remains open until a deployed build yields its HTTP/transport marker on the user's device.
