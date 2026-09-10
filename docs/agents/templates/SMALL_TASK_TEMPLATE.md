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
Inner loop: use the narrowest diagnostic test/check while editing; it is not formal evidence.
Formal checkpoint when implementation is ready:
RED first: <scenario>; `<command/method>`; expected <result>.
GREEN second: <scenario>; `<command/method>`; expected <result>.
Later edits re-run only invalidated evidence; rerun the full pair only if both scenarios/shared basis may be affected.
Verification ceiling: V2. Do not run the full suite unless the approved plan names a concrete escalation trigger. Prefer concise runner output.

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
