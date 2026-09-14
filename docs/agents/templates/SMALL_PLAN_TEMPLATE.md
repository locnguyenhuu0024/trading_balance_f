# Small Change Plan: <Topic>

Status: DRAFT | BLOCKED_ON_CLARIFICATION | READY_FOR_APPROVAL | APPROVED | COMPLETE
Date: YYYY-MM-DD
Tier: S

## Objective
<one observable outcome>

## Evidence and Scope
- Current behavior: <OBS/REP or concise file:symbol evidence>
- Allowed files/symbols: <exact surface>
- Out of scope: <explicit non-goals>
- Preserved behavior: <what must not change>
- Protected configuration/environment files: unreadable and non-writable by agents; use only user-provided config facts

## Implementation Step — P01
Implements: <REQ/AC IDs if used, otherwise concise contract>
1. <exact change>
2. <exact change>

Tests: <TEST or exact test to add/update>
RED: <scenario + method + independently derived expected result>
GREEN: <scenario + method + independently derived expected result>
Inner loop: narrow diagnostics only; formal RED -> GREEN once when implementation is ready. Later edits re-run only invalidated evidence.
Verification ceiling: V2 by default (focused RED/GREEN -> relevant test file/group). No full suite unless a concrete shared-surface/regression trigger is documented.

Task buildability gate: <YES | N/A with reason>.
Affected canonical build unit: `<project/module/solution/workspace | N/A>`.
Exact secret-free build command: `<command | N/A>`.
Boundary rule: P01/T01 must leave the affected build unit buildable; do not defer compiler/parser/type/reference/link fixes to a later task. If the proposed change is compile-coupled with another change, merge it into T01 or stage a backward-compatible buildable intermediate state.
Stop if: <condition requiring clarification/scope expansion>. If any required fact depends on protected configuration/environment contents, ask the user immediately instead of inspecting it.

## External Verification
<none | WINDOWS_INTEGRATED_AUTH_CONTEXT or other constraint + exact secret-free user-run command + RED/GREEN/TEST/AC IDs proved + required returned evidence + whether completion blocks until returned>. For an established Windows Integrated Auth constraint, do not plan repeated Codex-local SSPI retries.

## External Configuration / Environment Action
<none | target file/path + location/section/key + exact non-secret content using <SET_BY_USER> for secrets + scope + reason + validation/restart>. Agents do not apply this action. Unknown details require immediate user clarification.

## Task
T01 implements P01. Use `SMALL_TASK_TEMPLATE.md`.
Executor Class: E0 | E1 | E2
Target Route: Luna High | Luna XHigh | Luna Max
Choose from implementation entropy; Tier S does not automatically mean E0.

## Approval Gate
- [ ] no material ambiguity
- [ ] scope is bounded
- [ ] RED then GREEN defined
- [ ] affected build unit + exact task build command defined, or buildability gate explicitly N/A for non-executable work
- [ ] task boundary is buildable; compile-coupled work is merged or compatibility-staged
- [ ] user approval obtained before implementation
- [ ] protected configuration/environment contents are not required to be read
- [ ] external configuration action is fully specified or N/A
