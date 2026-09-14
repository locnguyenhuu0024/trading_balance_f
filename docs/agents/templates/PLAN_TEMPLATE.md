# Implementation Plan: <Topic>

Status: DRAFT | BLOCKED_ON_CLARIFICATION | READY_FOR_APPROVAL | APPROVED | EXECUTING | COMPLETE | SUPERSEDED
Date: YYYY-MM-DD
Tier: M | L
Specification: `<path>`
Decision Ledger: `<path>` or N/A

## 1. Objective

Implements: REQ-<...>
Acceptance: AC-<...>

Do not repeat full requirement prose unless implementation cannot be understood without a short excerpt.

## 2. Preconditions

Decisions/assumptions: D-<...>, A-<...> or N/A
Predecessor/environment/repository state:
- ...

## 3. Repository Impact

| Area | File | Symbol | Change Type |
|---|---|---|---|
| <area> | `<path>` | `<symbol>` | ADD/MODIFY/DELETE |

New files: <exact paths or N/A>
Explicitly not modified: <important exclusions, including all protected configuration/environment files>

Protected configuration/environment contents must not be read or content-diffed; protected files must not appear in Allowed Write Surface.

## 4. External Configuration / Environment Actions

User-owned only; agents do not read or modify protected configuration/environment files.

Required actions: <none | list>

For each action:
- Target file/path: `<user-confirmed or safely known path>`
- Location/section/key: `<exact insertion point>`
- Content: `<exact non-secret snippet; use <SET_BY_USER> for secrets>`
- Environment/scope: <...>
- Reason: <REQ/AC/P-step>
- Validation/restart: <...>
- Blocks verification until user applies: YES | NO

Unknown target/location/semantics -> stop and ask user; never inspect config to infer them.

## 5. Dependency Graph

```text
P01 -> P02 -> P03
```

## 6. Ordered Implementation Steps

### P01 — <concrete title>

Objective: <one implementation state transition>
Implements: REQ-<...>, AC-<...>
Files: `<paths>`
Symbols: `<symbols>`
Dependencies: <P/T predecessor or none>

Required changes:
1. <exact implementation action>
2. <exact implementation action>

Required behavior: <short reference/excerpt>
Must preserve: INV-<...> / <behavior>
Must NOT: <scope exclusions>
Edge cases: EDGE-<...>
Tests: TEST-<...>

RED verification:
- scenario: RED-<...>
- command/method: `<...>`
- expected: <independently derived result>

GREEN verification:
- scenario: GREEN-<...>
- command/method: `<...>`
- expected: <independently derived result>

Stop conditions:
- <condition requiring BLOCKED/user clarification/replan>

Repeat P* sections only as needed.

## 7. Test and Verification Plan

| Test | Proves | Level | Command/Method |
|---|---|---|---|
| TEST-001 | <REQ/AC/RED/GREEN> | unit/integration/... | `<...>` |

Inner-loop diagnostics: <narrowest test/check used while editing; non-authoritative evidence>.
Formal checkpoint: after implementation is believed ready, execute RED then GREEN once in that order.
Later changes: invalidate and re-run only scenarios whose dependency path/test-support/expected/shared basis may have changed; restart full RED -> GREEN only when both scenarios or their shared basis are affected.

Verification ladder: V1 focused RED/GREEN -> V2 relevant file/group -> V3 affected/related set -> V4 full suite.
Task verification ceiling: <V1 | V2 | V3>
Final integration ceiling: <V2 | V3 | V4>
Escalate when: <specific risk/evidence condition>

### External verification constraints

Known environment constraint: <none | WINDOWS_INTEGRATED_AUTH_CONTEXT | other>
User-executed verification required: YES | NO
Exact secret-free command: `<command>`
Proves: <RED/GREEN/TEST/AC IDs>
Evidence required back: <exit code/status + concise non-secret PASS/FAIL output>
Completion blocked until evidence supplied: YES | NO

For `WINDOWS_INTEGRATED_AUTH_CONTEXT`, do not plan repeated Codex-local Integrated Authentication retries or a SQL-auth credential workaround unless the user explicitly requests a different auth strategy.
Full-suite ownership: <NOT_REQUIRED | CODEX_ONCE | CI_AUTHORITATIVE> — <reason>

Regression coverage: <specific preserved behavior>
Other checks: <type/lint/build/runtime or N/A>

## 8. Migration / Data Plan

Tier L/data work: forward behavior, representative data, validation, rollback. Otherwise `N/A — <reason>`.

## 9. Performance Verification

Performance-sensitive work: baseline, dataset/input, measurement, threshold, semantic parity. Otherwise `N/A — <reason>`.

## 10. Risks

| Risk ID | Risk | Impact | Detection | Mitigation |
|---|---|---|---|---|

## 11. Rollout / Rollback

Sequence: <...>
Rollback trigger: <...>
Rollback steps: <...>
Or one concise `N/A — <reason>` where genuinely irrelevant.

## 12. Decision/Assumption Dependency Registry

| Decision/Assumption | Used By | Evidence/Authorization | Invalidated By |
|---|---|---|---|

Include only material entries.

## 13. Task Decomposition

| Task | Plan Steps | Requirements/AC | Depends On | Executor Class | Allowed Write Surface |
|---|---|---|---|---|---|
| T01 | P01 | REQ-001 / AC-001 | — | E0/E1/E2 | `<paths>` |

Prefer the smallest independently auditable unit, not one task per file. Select `E0`/`E1`/`E2` from implementation entropy according to `PLANNING_RULES.md`; do not derive it mechanically from Tier S/M/L.

### Task Buildability Plan

| Task | Required | Affected Canonical Build Unit | Exact Secret-Free Build Command | Boundary Strategy |
|---|---|---|---|---|
| T01 | YES/N/A | `<project/module/solution/workspace>` | `<command-or-N/A-reason>` | <self-contained / merged-compile-coupled / compatibility-staged> |

Rules:
- Every code-producing task boundary must be buildable before that task may reach `PASS`.
- If adjacent proposed tasks are compile-coupled such that an earlier boundary would fail with compiler/parser/type/reference/link/build errors, merge them or design a backward-compatible staged transition. Do not plan a broken intermediate state on the assumption that a later task will repair it.
- A test harness build is not a substitute for the affected canonical application build unit unless it actually compiles that unit.

## 14. Completion Gate

- [ ] every task PASS
- [ ] every code-producing task had a `PASS` task buildability gate at its final task-local executable state
- [ ] compile-coupled changes were merged or compatibility-staged; no task was passed while relying on a later task to restore buildability
- [ ] every affected AC has implementation/verification evidence
- [ ] RED precedes GREEN for every implementation/remediation task
- [ ] relevant repository checks observed
- [ ] final diff matches approved scope
- [ ] final integration audit PASS
- [ ] no protected configuration/environment file was read or modified by an agent
- [ ] every external configuration/environment action is reported with target/location/content placeholder/validation or N/A

## 15. Change Log

Add only after a material user-visible revision.

| Revision | Change | Reason |
|---|---|---|
