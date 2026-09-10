# Coordinator Audit — T<NN>

Task: `<task path>`
Verdict: PENDING | PASS | REWORK | BLOCKED

## Evidence Reviewed

- task/requirement IDs: <...>
- `git status`: <summary>
- relevant diff/files: <...>
- tests/checks: <...>
- verification level reached: <V1 | V2 | V3 | V4>
- executor evidence reused: YES | NO
- evidence invalidation review: <no later changes | changed surfaces -> affected RED/GREEN/TEST IDs>
- rerun reason: N/A | <invalidated/incomplete/suspect/high-risk evidence>

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
Selective invalidation handled correctly: PASS | FAIL | N/A
Full RED->GREEN rerun only when both/shared basis affected: PASS | FAIL | N/A

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
