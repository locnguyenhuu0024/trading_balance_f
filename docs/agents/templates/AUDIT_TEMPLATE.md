# Coordinator Audit — T<NN>

Task: `<task path>`
Verdict: PENDING | PASS | REWORK | BLOCKED

## Evidence Reviewed

- task/requirement IDs: <...>
- `git status`: <summary>
- relevant diff/files: <...>
- tests/checks: <...>

## Contract Mapping

| Acceptance Criterion | Implementation Evidence | Verification Evidence | Result |
|---|---|---|---|
| AC-001 | `<path:symbol>` | RED/GREEN/TEST | PASS/FAIL |

## Scope Review

Allowed write surface respected: PASS | FAIL
Unexplained changes: none | <...>
Architecture/contract conformance: PASS | FAIL
Test quality: PASS | FAIL

## RED / GREEN

RED executed and observed before GREEN: PASS | FAIL
RED expected result independently derived: PASS | FAIL
GREEN expected result independently derived: PASS | FAIL
Fresh RED->GREEN cycle after later code/test-support change: PASS | FAIL | N/A

## Findings

### AUD-001 — <short title>
Severity: BLOCKING | NON_BLOCKING
Expected: <approved contract>
Observed: <repository ground truth>
Evidence: `<path:symbol>` / `<command/result>`
Affected: REQ-<...>, AC-<...>, P<...>, T<...>
Required remediation: <bounded correction>

Omit the findings section when there are no findings.

## Verdict

PASS | REWORK | BLOCKED

Reason: <concise evidence-based reason>
