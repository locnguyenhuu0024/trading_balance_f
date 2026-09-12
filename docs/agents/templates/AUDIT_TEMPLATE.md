# Coordinator Audit — T<NN>

Task: `<task path>`
Verdict: PENDING | PASS | REWORK | BLOCKED

## Evidence Reviewed

- task/requirement IDs: <...>
- executor class/route: <E0/E1/E2 + configured Luna effort>
- executor routing review: PASS | FAIL — <implementation entropy matched selected class; escalation evidence if any>
- `git status --short` / `git diff --name-only`: <summary>
- non-protected relevant diff/files: <...>
- protected configuration/environment changed paths (name/status only; never content): <none | paths>
- tests/checks: <...>
- verification level reached: <V1 | V2 | V3 | V4>
- executor evidence reused: YES | NO
- evidence invalidation review: <no later changes | changed surfaces -> affected RED/GREEN/TEST IDs>
- rerun reason: N/A | <invalidated/incomplete/suspect/high-risk evidence>
- external verification state: none | BLOCKED_EXTERNAL_VERIFICATION | evidence_received | obsolete_after_local_success
- external verification subtype: N/A | WINDOWS_INTEGRATED_AUTH_CONTEXT | <other>
- auth-constraint state: N/A | UNCONFIRMED | ACTIVE | CLEARED
- focused Codex retry/probe: N/A | PASS | FAIL — <concise evidence>
- external verification command/evidence: <N/A | secret-free command + user-reported exit code/status + concise non-secret output>
- external verification accepted: N/A | YES | NO | OBSOLETE — <reason>

## Contract Mapping

| Acceptance Criterion | Implementation Evidence | Verification Evidence | Result |
|---|---|---|---|
| AC-001 | `<path:symbol>` | RED/GREEN/TEST | PASS/FAIL |

## Scope Review

Allowed write surface respected: PASS | FAIL
Unexplained changes: none | <...>
Architecture/contract conformance: PASS | FAIL
Test quality: PASS | FAIL
Protected configuration boundary respected: PASS | FAIL
Protected config/environment content read by any agent: NO | SECURITY_VIOLATION
Protected config/environment file modified by any agent: NO | SECURITY_VIOLATION
External configuration/environment actions sufficiently specified: PASS | FAIL | N/A

## RED / GREEN

RED executed and observed before GREEN: PASS | FAIL
RED expected result independently derived: PASS | FAIL
GREEN expected result independently derived: PASS | FAIL
Selective invalidation handled correctly: PASS | FAIL | N/A
Full RED->GREEN rerun only when both/shared basis affected: PASS | FAIL | N/A
External user-run evidence mapped to the exact planned RED/GREEN/TEST contract: PASS | FAIL | N/A
SSPI constraint activation required interactive-known-good + failed focused Codex retry/probe: PASS | FAIL | N/A
Later equivalent local Integrated Auth success cleared `WINDOWS_INTEGRATED_AUTH_CONTEXT` and obsolete external verification was not requested/reused unnecessarily: PASS | FAIL | N/A


## Task Buildability Gate

Required: YES | N/A — <reason>
Affected canonical build unit: `<project/module/solution/workspace | N/A>`
Exact build command: `<secret-free command | N/A>`
Build executed after last task-local executable/source/test/generated-code change: YES | NO | N/A
Build result: PASS | FAIL | BLOCKED_ENVIRONMENT | N/A
Exit/status: <code/status | N/A>
Compiler/parser/type/reference/link/build errors: none | <AUD-* IDs + concise localization>
Evidence source: executor reused | auditor rerun | N/A
Harness-only evidence incorrectly treated as application build evidence: NO | YES
Compile-coupled work deferred to later task: NO | YES — <tasks/surface>

Rules:
- A code-producing task verdict cannot be `PASS` unless this gate is `PASS`.
- Exact command + affected target/scope + observed exit/status + freshness are required; an unrecorded “build exit 0” is insufficient.
- Successful RED/GREEN or a compiled test harness cannot substitute for the affected canonical application build unless it actually builds that unit.
- Build failure attributable to the task is `REWORK`; a broken boundary intentionally awaiting a later task requires merge/replan and cannot `PASS`.
- Genuine environment/toolchain inability or proven out-of-scope pre-existing breakage yields `BLOCKED`, not `PASS`.

## Final Repository Build Gate

Canonical build command: `<secret-free command>`
Build scope: <aggregate repo/solution/workspace | all canonical top-level units>
Final post-remediation build executed: YES | NO
Build result: PASS | FAIL | BLOCKED_ENVIRONMENT
Exit/status: <code/status>
Compiler/parser/type/reference/link errors: none | <AUD-* IDs + concise localization>
Build failure classification: N/A | introduced/affected-path | pre-existing/out-of-scope | environment/toolchain | protected-config-dependent
Remediation cycles caused by build gate: <integer>
Final rebuild after last executable change: PASS | FAIL | BLOCKED_ENVIRONMENT
Protected configuration/build files consumed only as opaque tool input: YES | NO | N/A

Rules:
- `PASS` verdict is forbidden unless the final repository build gate is `PASS`.
- Code/build failures require localization and bounded remediation when they remain within approved scope.
- A proven unrelated/pre-existing build failure that requires scope expansion yields `BLOCKED`, not `PASS`.
- A genuine pre-build environment/toolchain failure sets the build gate to `BLOCKED_ENVIRONMENT` and the audit verdict to `BLOCKED`, not `PASS`.

## Findings

### AUD-001 — <short title>
Severity: BLOCKING | NON_BLOCKING
Expected: <approved contract>
Observed: <repository ground truth>
Evidence: `<path:symbol>` / `<command/result>`
Affected: REQ-<...>, AC-<...>, P<...>, T<...>
Required remediation: <bounded permitted-code correction OR user-owned external configuration action; never delegate protected config edits>

Omit the findings section when there are no findings.

## Routing / Telemetry Assessment

Route fit: FIT | UNDERPOWERED | OVERPOWERED | UNKNOWN
Reason: <one concise evidence-based sentence>
Executor first-pass success: YES | NO | N/A
Executor retry/escalation count: <integer | unavailable>
Environment/transport noise affected outcome: NO | YES — <category>
Telemetry envelope complete: PASS | DEGRADED — <missing runtime-only fields are allowed when unavailable>

## Verdict

PASS | REWORK | BLOCKED

Task buildability gate satisfied before task PASS: YES | NO | N/A
Final build gate satisfied before final PASS: YES | NO

Reason: <concise evidence-based reason>
