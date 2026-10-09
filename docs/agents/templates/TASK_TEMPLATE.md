# Task <NN> — <Topic>

Status: PENDING | READY | EXECUTING | VERIFYING | PASS | REWORK | BLOCKED | BLOCKED_ROUTE
Agent Role: implementation_executor
Executor Class: E0 | E1 | E2
Target Model: gpt-6-luna
Target Effort: high | xhigh | max
Target Route: gpt-6-luna / <high|xhigh|max>
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Specification: `<path>`
Plan: `<path>`
Plan Steps: P<...>
Requirements: REQ-<...>
Acceptance Criteria: AC-<...>
Frontend Level: F0 | F1 | F2 | F3 | N/A
Frontend Design Brief: `<path | N/A>`
Required Frontend Guidance: <frontend-design | web-design-guidelines | react-best-practices | composition-patterns | react-view-transitions | N/A>
Visual Review Required: YES | NO

## 1. Dispatch Compliance

Before this task may enter `EXECUTING`, the coordinator must spawn an `implementation_executor` with **both Target Model and Target Effort explicitly supplied to the runtime**. Omitting either field or inheriting the coordinator/parent route is prohibited.

Dispatch Route Status: PENDING | MATCH | UNVERIFIABLE | MISMATCH | ROUTE_UNAVAILABLE
Requested Model: PENDING
Requested Effort: PENDING
Observed Effective Model: unavailable | <runtime value>
Observed Effective Effort: unavailable | <runtime value>

- `MATCH`: runtime reports the configured route.
- `UNVERIFIABLE`: explicit model+effort binding succeeded but runtime does not expose the effective route.
- `MISMATCH`: stop further mutation and return the task to coordinator recovery/redispatch; a stronger route still counts as mismatch.
- `ROUTE_UNAVAILABLE`: do not spawn an inherited/default writer; mark `BLOCKED_ROUTE` and obtain a task-specific routing decision.

## 2. Objective

<one bounded implementation outcome>

Done when: <observable completion condition>

## 3. Preconditions

Predecessors: T<...> = PASS or none
Required decisions/assumptions: D-<...>, A-<...> or none
Required repository/environment state: <...>

## 4. Allowed Scope

Files/modules/APIs/data structures/symbols:
- `<exact path/symbol>`

## 5. Forbidden Scope

Do not:
- read, search within, parse, summarize, or content-diff protected repository configuration/environment files;
- create, modify, delete, rename, reformat, or regenerate protected configuration/environment files;
- modify unrelated files/modules;
- change contracts not listed in the plan;
- perform opportunistic refactors;
- add/remove dependencies unless explicitly allowed;
- exceed the stated write surface.

If required work exceeds Allowed Scope, return `BLOCKED`. If a required fact depends on protected configuration/environment contents, ask the user immediately through the coordinator; never inspect the file.

## 6. Executor Contract

Follow P<...> in order:
1. <mechanical implementation step>
2. <mechanical implementation step>

Required invariants: INV-<...>
Required edge behavior: EDGE-<...>
Preserved behavior: <...>

Do not invent missing architecture/product semantics. If the contract is insufficient, return `BLOCKED`. Do not self-escalate the executor model/effort; report evidence to the coordinator, which owns any `E0 -> E1 -> E2` escalation.

## 7. External Configuration / Environment Actions

Agents do not apply protected configuration/environment changes.

Planned action: <none | target file/path + location/section/key + exact non-secret snippet with <SET_BY_USER> placeholders + environment/scope + reason + validation/restart>
Discovered additional action during execution: <none | same schema; if target/location/semantics unknown, BLOCKED and ask user>
Blocks verification until user applies: YES | NO

## Frontend Gate — frontend variant

Approved visual/design decisions fixed before executor dispatch: YES | N/A
Existing design-system primitives to reuse: <paths/components/tokens | N/A>
Pinned web-guidelines audit required after implementation: YES | NO
React/Next performance review required: YES | NO
Composition review required: YES | NO
View-transition review required: YES | NO

Executor rules:
- implement the approved visual contract; do not invent new aesthetic/product semantics;
- do not add packages/framework features solely because a third-party skill mentions them;
- preserve reduced-motion, keyboard/focus and responsive requirements in scope;
- if exact visual intent is missing for F2/F3, return `BLOCKED` rather than improvising.

## 8. Tests

- TEST-001: <test to add/update and what it proves>

## 9. Mandatory Verification

### RED — RED-001
Scenario: <...>
Command/method: `<...>`
Expected: <independently derived result>
Actual: <fill during execution>
Status: PENDING | PASS | FAIL | BLOCKED

### GREEN — GREEN-001
Scenario: <...>
Command/method: `<...>`
Expected: <independently derived result>
Actual: <fill during execution>
Status: PENDING | PASS | FAIL | BLOCKED

During implementation, use only the narrowest diagnostic check needed; diagnostics are not formal evidence. When implementation is ready, run one formal RED -> GREEN checkpoint in order. Later changes invalidate only affected evidence; re-run the full pair only if both scenarios or their shared basis may be affected.

Verification ceiling: <V1 | V2 | V3; never V4 per-task unless explicitly justified>
Escalate only if: <specific missing evidence/risk condition>
Do not run a broader verification level when the current evidence already proves the task contract. Prefer concise test output and record only command + relevant result.


### Task Buildability Gate

Required: YES | N/A — <reason only for work that cannot affect executable buildability>
Affected canonical build unit: `<project/module/solution/workspace>`
Exact secret-free build command: `<command>`
Executed after the last task-local executable/source/test/generated-code change: YES | NO
Result: PENDING | PASS | FAIL | BLOCKED_ENVIRONMENT | N/A
Exit/status: <code/status>
Compiler/parser/type/reference/link/build errors: none | <concise localization>

Rules:
- A code-producing task cannot reach `PASS` unless this gate is `PASS`.
- Run the recorded affected-unit build after the task's final executable change. Exact command + target/scope + observed exit/status are required evidence; an unrecorded claim such as “focused build exit 0” is insufficient.
- A focused harness/test compile or successful behavioral test does not substitute for the affected application build unit unless the command actually builds that canonical unit.
- Compiler/parser/type/reference/link/build failure attributable to the task is `REWORK`; localize and remediate it before task `PASS`.
- Do not defer a broken build to a later planned task. If completing the compile-coupled change exceeds Allowed Scope, return `BLOCKED` so the coordinator can merge/replan the task boundary.
- Genuine pre-build environment/toolchain failure uses `BLOCKED_ENVIRONMENT`; do not disguise code errors as environment failures.
- Repository-native build tools may consume protected configuration/build files only as opaque input under the governing security boundary.

### External Verification

Required: NO | YES
Subtype: <WINDOWS_INTEGRATED_AUTH_CONTEXT | other>
Exact secret-free user-run command: `<command>`
Proves: <RED/GREEN/TEST/AC IDs>
Expected returned evidence: <exit code/status + concise non-secret PASS/FAIL output>
Task/verification blocked until returned: YES | NO

If subtype is `WINDOWS_INTEGRATED_AUTH_CONTEXT` and the constraint is already established, do not retry the same Codex-local trusted-auth path merely to reconfirm SSPI failure.

## 10. Stop Conditions

Return `BLOCKED` when:
- repository evidence contradicts the approved contract;
- material information/design decision is missing;
- required protected configuration/environment information is unknown;
- required change exceeds allowed scope;
- predecessor assumption is invalid;
- required verification is genuinely unavailable.

Report blocker + evidence + affected IDs + coordinator decision required.

## 11. Execution Ledger

- [ ] confirm dispatch role/class/model/effort match this task and `Route Binding = EXPLICIT`
- [ ] confirm parent/default route inheritance was not used
- [ ] inspect referenced symbols
- [ ] implement assigned P-step(s)
- [ ] add/update required tests
- [ ] use narrow diagnostics during implementation as needed
- [ ] execute/observe formal RED
- [ ] execute/observe formal GREEN
- [ ] run/record the Task Buildability Gate after the last task-local executable change, or record legitimate N/A
- [ ] stop at the planned verification ceiling unless escalation trigger is met
- [ ] return compact executor report
- [ ] confirm no protected configuration/environment file content was read or modified
- [ ] report External Configuration / Environment Actions as none or fully specified
- [ ] satisfy applicable frontend skill gates without out-of-scope redesign/dependency expansion
- [ ] report visual-review handoff requirement/evidence status

## 12. Coordinator Audit

Scope: PENDING
Acceptance criteria: PENDING
Test quality: PENDING
RED evidence: PENDING
GREEN evidence: PENDING
RED-before-GREEN: PENDING
Evidence reused vs rerun: PENDING
Rerun reason: N/A | <why executor evidence was insufficient>
Architecture/contract conformance: PENDING
Dispatch route compliance: PENDING | MATCH | UNVERIFIABLE | MISMATCH | ROUTE_UNAVAILABLE
Parent route inheritance: PENDING | NO | YES
Task buildability gate: PENDING | PASS | FAIL | BLOCKED_ENVIRONMENT | N/A
Verdict: PENDING

Use `AUDIT_TEMPLATE.md` for detailed findings when needed.
