# Task <NN> — <Topic>

Status: PENDING | READY | EXECUTING | VERIFYING | PASS | REWORK | BLOCKED
Plan: <path>#P01

## Objective
<one observable implementation outcome>

## Scope
Allowed: <files/symbols>
Forbidden: unrelated refactors/contracts/dependencies/files outside allowed scope.

## Execute
1. <mechanical step>
2. <mechanical step>

Preserve: <invariant/behavior>

## Verify
RED first: <scenario>; `<command/method>`; expected <result>.
GREEN second: <scenario>; `<command/method>`; expected <result>.
If code/test-support changes after verification starts, restart from RED.

## Stop Conditions
Return `BLOCKED` if a design decision, missing information, contradictory repository evidence, or write outside Allowed scope is required.

## Ledger
- [ ] implement P01
- [ ] RED observed
- [ ] GREEN observed
- [ ] report changed files/results/blockers

## Coordinator Audit
Acceptance/scope: PENDING
RED-before-GREEN: PENDING
Verdict: PENDING
