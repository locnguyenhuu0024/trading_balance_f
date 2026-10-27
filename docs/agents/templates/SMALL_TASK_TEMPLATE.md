# Task <NN> — <Topic>

Status: PENDING | READY | EXECUTING | VERIFYING | PASS | REWORK | BLOCKED | BLOCKED_ROUTE
Plan: <path>#P01
Agent Role: implementation_executor
Executor Class: E0 | E1 | E2
Target Model: gpt-6-luna
Target Effort: high | xhigh | max
Target Route: gpt-6-luna / <high|xhigh|max>
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Dispatch Route Status: PENDING | MATCH | UNVERIFIABLE | MISMATCH | ROUTE_UNAVAILABLE

Before execution, the coordinator must pass Target Model + Target Effort explicitly in the child spawn call. Parent/default inheritance is prohibited. `MISMATCH` or `ROUTE_UNAVAILABLE` blocks execution/PASS; `UNVERIFIABLE` is valid only after verified explicit binding.

## Objective
<one observable implementation outcome>

## Scope
Allowed: <files/symbols>
Forbidden: unrelated refactors/contracts/dependencies/files outside allowed scope; reading/content-diffing or modifying any protected repository configuration/environment file.

## Execute
1. <mechanical step>
2. <mechanical step>

Preserve: <invariant/behavior>

## Verify
Inner loop: use the narrowest diagnostic test/check while editing; it is not formal evidence.
Formal checkpoint when implementation is ready:
RED first: <scenario>; `<command/method>`; expected <result>.
GREEN second: <scenario>; `<command/method>`; expected <result>.
Later edits re-run only invalidated evidence; rerun the full pair only if both scenarios/shared basis may be affected.
Verification ceiling: V2. Do not run the full suite unless the approved plan names a concrete escalation trigger. Prefer concise runner output.

### Task Buildability Gate
Required: YES | N/A — <reason>.
Affected build unit: `<project/module/solution/workspace>`.
Exact secret-free build command: `<command>`.
After final executable change, run it and record `PASS | FAIL | BLOCKED_ENVIRONMENT | N/A` plus exit/status. A code-producing task cannot `PASS` on harness/RED/GREEN evidence alone when its affected application build unit has not been proven buildable. `Fixed by a later task` is invalid; compile-coupled work must be merged/replanned or compatibility-staged.

## External Verification

Required: NO | YES
Subtype: <WINDOWS_INTEGRATED_AUTH_CONTEXT | other>
Exact secret-free user-run command: `<command>`
Proves: <RED/GREEN/TEST/AC IDs>
Evidence required back: <exit code/status + concise non-secret PASS/FAIL output>
Blocked until returned: YES | NO

## External Configuration / Environment Action
<none | target file/path + location/section/key + exact non-secret snippet using <SET_BY_USER> for secrets + scope + reason + validation/restart>. Do not apply it. If target/location/semantics are unknown, ask the user immediately.

Do not self-escalate model/effort. If the selected executor route is insufficient, report the observed implementation difficulty to the coordinator for `E0 -> E1 -> E2` reclassification. If the runtime-reported role/model/effort does not match this task contract, stop further mutation and return `ROUTE_MISMATCH` rather than continuing on the inherited/default route.

## Stop Conditions
Return `BLOCKED` if a design decision, missing information, contradictory non-protected repository evidence, required protected configuration/environment information, or write outside Allowed scope is required. Never inspect protected config to resolve a blocker.

## Ledger
- [ ] implement P01
- [ ] RED observed
- [ ] GREEN observed
- [ ] affected build unit PASS after final executable change, or legitimate N/A
- [ ] report changed files/results/blockers
- [ ] confirm no protected configuration/environment content was read or modified
- [ ] report external configuration/environment action as none or fully specified

## Coordinator Audit
Acceptance/scope: PENDING
RED-before-GREEN: PENDING
Task buildability: PENDING | PASS | FAIL | BLOCKED_ENVIRONMENT | N/A
Verdict: PENDING
