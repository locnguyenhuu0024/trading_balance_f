# Executor Completion Report — T<NN>

Status: DONE | BLOCKED

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

Evidence validity:
- later changes after formal checkpoint: <none | paths/surfaces>
- invalidated evidence re-run: <none | RED/GREEN/TEST IDs + result>
- unaffected evidence reused: <none | RED/GREEN/TEST IDs>
- environment blocker: none | BLOCKED_ENVIRONMENT — <concise evidence>

Deviations: none | <exact deviation>
Blockers: none | <blocker + evidence + required coordinator decision>

Do not repeat full requirement/plan/task prose in this report.
