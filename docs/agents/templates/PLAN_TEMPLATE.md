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
Explicitly not modified: <important exclusions>

## 4. Dependency Graph

```text
P01 -> P02 -> P03
```

## 5. Ordered Implementation Steps

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

## 6. Test and Verification Plan

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
Full-suite ownership: <NOT_REQUIRED | CODEX_ONCE | CI_AUTHORITATIVE> — <reason>

Regression coverage: <specific preserved behavior>
Other checks: <type/lint/build/runtime or N/A>

## 7. Migration / Data Plan

Tier L/data work: forward behavior, representative data, validation, rollback. Otherwise `N/A — <reason>`.

## 8. Performance Verification

Performance-sensitive work: baseline, dataset/input, measurement, threshold, semantic parity. Otherwise `N/A — <reason>`.

## 9. Risks

| Risk ID | Risk | Impact | Detection | Mitigation |
|---|---|---|---|---|

## 10. Rollout / Rollback

Sequence: <...>
Rollback trigger: <...>
Rollback steps: <...>
Or one concise `N/A — <reason>` where genuinely irrelevant.

## 11. Decision/Assumption Dependency Registry

| Decision/Assumption | Used By | Evidence/Authorization | Invalidated By |
|---|---|---|---|

Include only material entries.

## 12. Task Decomposition

| Task | Plan Steps | Requirements/AC | Depends On | Allowed Write Surface |
|---|---|---|---|---|
| T01 | P01 | REQ-001 / AC-001 | — | `<paths>` |

Prefer the smallest independently auditable unit, not one task per file.

## 13. Completion Gate

- [ ] every task PASS
- [ ] every affected AC has implementation/verification evidence
- [ ] RED precedes GREEN for every implementation/remediation task
- [ ] relevant repository checks observed
- [ ] final diff matches approved scope
- [ ] final integration audit PASS

## 14. Change Log

Add only after a material user-visible revision.

| Revision | Change | Reason |
|---|---|---|
