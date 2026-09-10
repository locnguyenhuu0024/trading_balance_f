# Task <NN> — <Topic>

Status: PENDING | READY | EXECUTING | VERIFYING | PASS | REWORK | BLOCKED
Executor: implementation executor
Specification: `<path>`
Plan: `<path>`
Plan Steps: P<...>
Requirements: REQ-<...>
Acceptance Criteria: AC-<...>

## 1. Objective

<one bounded implementation outcome>

Done when: <observable completion condition>

## 2. Preconditions

Predecessors: T<...> = PASS or none
Required decisions/assumptions: D-<...>, A-<...> or none
Required repository/environment state: <...>

## 3. Allowed Scope

Files/modules/APIs/data structures/symbols:
- `<exact path/symbol>`

## 4. Forbidden Scope

Do not:
- modify unrelated files/modules;
- change contracts not listed in the plan;
- perform opportunistic refactors;
- add/remove dependencies unless explicitly allowed;
- exceed the stated write surface.

If required work exceeds Allowed Scope, return `BLOCKED`.

## 5. Executor Contract

Follow P<...> in order:
1. <mechanical implementation step>
2. <mechanical implementation step>

Required invariants: INV-<...>
Required edge behavior: EDGE-<...>
Preserved behavior: <...>

Do not invent missing architecture/product semantics. If the contract is insufficient, return `BLOCKED`.

## 6. Tests

- TEST-001: <test to add/update and what it proves>

## 7. Mandatory Verification

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

GREEN may run only after RED is executed and observed. If implementation or test-support code changes after either attempt, restart from RED.

## 8. Stop Conditions

Return `BLOCKED` when:
- repository evidence contradicts the approved contract;
- material information/design decision is missing;
- required change exceeds allowed scope;
- predecessor assumption is invalid;
- required verification is genuinely unavailable.

Report blocker + evidence + affected IDs + coordinator decision required.

## 9. Execution Ledger

- [ ] inspect referenced symbols
- [ ] implement assigned P-step(s)
- [ ] add/update required tests
- [ ] execute/observe RED
- [ ] execute/observe GREEN
- [ ] return compact executor report

## 10. Coordinator Audit

Scope: PENDING
Acceptance criteria: PENDING
Test quality: PENDING
RED evidence: PENDING
GREEN evidence: PENDING
RED-before-GREEN: PENDING
Architecture/contract conformance: PENDING
Verdict: PENDING

Use `AUDIT_TEMPLATE.md` for detailed findings when needed.
