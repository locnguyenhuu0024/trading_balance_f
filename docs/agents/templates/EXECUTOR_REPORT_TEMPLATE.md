# Executor Completion Report — T<NN>

Status: DONE | BLOCKED
Executor Class: E0 | E1 | E2
Configured Route: Luna High | Luna XHigh | Luna Max
Observed Effective Route: <same | runtime-reported different | unavailable>
Escalation: none | E0->E1 | E1->E2 | exceptional — <evidence/reason>

Changed files:
- `<path>` — <one-line change>

Tests changed:
- `<path/test>` — <what it proves>

RED: PASS | FAIL | BLOCKED
- scenario: RED-<...>
- command/method: `<...>`
- observed: <actual result>

GREEN: PASS | FAIL | BLOCKED
- scenario: GREEN-<...>
- command/method: `<...>`
- observed: <actual result>

Diagnostics (non-authoritative): <none | concise commands/results used during inner loop>
Formal checkpoint: <completed | blocked>

Other verification:
- level reached: <V1 | V2 | V3 | V4>
- `<command>` -> <observed result>
- broader verification skipped: <not needed | CI-owned | blocked | reason>


Task buildability gate:
- required: YES | N/A — <reason>
- affected canonical build unit: `<project/module/solution/workspace | N/A>`
- exact secret-free build command: `<command | N/A>`
- executed after last task-local executable/source/test/generated-code change: YES | NO | N/A
- result: PASS | FAIL | BLOCKED_ENVIRONMENT | N/A
- exit/status: <code/status | N/A>
- compiler/parser/type/reference/link/build errors: none | <concise localization>
- note: harness/test compilation is not application-build evidence unless the command actually builds the affected canonical unit

Evidence validity:
- later changes after formal checkpoint: <none | paths/surfaces>
- invalidated evidence re-run: <none | RED/GREEN/TEST IDs + result>
- unaffected evidence reused: <none | RED/GREEN/TEST IDs>
- environment blocker: none | BLOCKED_ENVIRONMENT — <concise evidence>

External verification: none | required | evidence_received | obsolete_after_local_success
- subtype: <WINDOWS_INTEGRATED_AUTH_CONTEXT | other>
- auth-constraint state: <N/A | UNCONFIRMED | ACTIVE | CLEARED>
- focused Codex retry/probe: <N/A | PASS -> CLEARED | FAIL -> may activate if interactive auth is known-good>
- exact user-run command: `<secret-free command | N/A after local success>`
- proves: <RED/GREEN/TEST/AC IDs>
- expected evidence: <exit code/status + concise non-secret PASS/FAIL output | N/A>
- user-reported exit code/status: <pending | value | N/A>
- user-reported concise output: <pending | non-secret summary/output | N/A>
- local Integrated Auth later succeeded: YES | NO
- coordinator evidence acceptance: PENDING | ACCEPTED | REJECTED | OBSOLETE — <reason>

Protected configuration boundary:
- protected config/environment content read: NO
- protected config/environment file modified by agent: NO
- protected changed paths observed by name/status only: <none | paths>

External configuration/environment actions: none | required
- target file/path: `<existing or new path>`
- location/section/key: `<exact insertion point>`
- content: `<exact non-secret snippet; use <SET_BY_USER> for sensitive values>`
- environment/scope: <...>
- reason: <...>
- validation/restart: <...>
- blocks verification until applied: YES | NO

Deviations: none | <exact deviation>
Blockers: none | <blocker + evidence + required coordinator decision>

Do not repeat full requirement/plan/task prose in this report. Never include secret values or protected configuration content.

Transport return rule:
- Return this report as the terminal output of the currently assigned subagent turn.
- Do **not** resume/reopen the coordinator/main session or send to a guessed session/thread ID merely to deliver this report.
- Do not reinterpret subagent/recipient-agent IDs, turn/item/call IDs, or agent names as session IDs.
- The coordinator owns result collection and any follow-up send/resume operation.

Telemetry envelope (for coordinator logging; no chain-of-thought):
- agent_run_id: <coordinator-assigned logical ID>
- role/class: <executor E0/E1/E2>
- work_type: <short category>
- task_ids: <T/AC/TEST IDs>
- configured_route: <model + effort>
- effective_route: <runtime-reported value | unavailable>
- started_at / ended_at / duration_ms: <observed values | unavailable>
- terminal_outcome: <PASS | REWORK | BLOCKED | FAILED | UNKNOWN>
- retry_count: <integer>
- escalation: <none | from -> to + reason code>
- verification_level: <V1 | V2 | V3 | V4 | N/A>
- usage: <input/output/reasoning/cache tokens + cost when runtime exposes them; otherwise null>
- error_category: <none | environment | transport | verification | contract | other>

The coordinator may add `result_use` and `route_assessment` after fan-in/audit. Do not include chain-of-thought, full prompts, secrets, protected configuration contents, source-code bodies, diffs, or raw command output in this envelope.
