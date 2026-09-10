# Design Specification: <Topic>

Status: DRAFT | BLOCKED_ON_CLARIFICATION | READY_FOR_PLAN | SUPERSEDED
Date: YYYY-MM-DD
Tier: M | L
Decision Ledger: <path or N/A — no material decision ledger needed>

## 1. Objective

Requested outcome:
- <observable outcome>

Success conditions:
- <observable condition>

## 2. Current State

### Observed Facts

| ID | Source | Symbol/Location | Observation |
|---|---|---|---|
| OBS-001 | `<path>` | `<symbol>` | <fact> |

### Reproduced Behavior

| ID | Method/Command | Observed Result |
|---|---|---|
| REP-001 | `<method>` | <actual result> |

### Hypotheses

| ID | Hypothesis | Evidence | Status |
|---|---|---|---|
| HYP-001 | <hypothesis> | <evidence> | CONFIRMED / UNCONFIRMED |

## 3. Scope

### In Scope
- ...

### Out of Scope
- ...

## 4. Clarifications and Decisions

Open questions: <Q-* or N/A>
Resolved decisions: <D-* or N/A>
Authorized assumptions: <A-* or N/A>

If any material Q-* remains open, set status `BLOCKED_ON_CLARIFICATION` and stop before finalizing the plan.

## 5. Requirements

### REQ-001 — <name>

The system MUST <exact requirement>.

Inputs: <exact input contract>
Outputs: <exact output contract>
Required behavior: <behavior>
Failure behavior: <behavior>
Permission behavior: <behavior or N/A>
Preserved behavior: <behavior>

## 6. Data Contract

Use only when data semantics matter; otherwise write `N/A — no material data contract change`.

| Field | Type | Required | Meaning | Unit | Null/Zero/Absent Semantics |
|---|---|---:|---|---|---|

Grain: <one record/result represents ...>
Source tables/fields: <...>
Date boundary/timezone: <...>
Formula: `<...>`
Independent worked example: <input -> independently calculated expected output>

## 7. Cross-Layer Mapping

Use for cross-layer work; otherwise `N/A — change is local to ...`.

| Semantic Field | Persistence/Query | DTO | API | Frontend Normalization | Component | Export |
|---|---|---|---|---|---|---|

## 8. Proposed Design

Architecture/control flow:
```text
<flow>
```

State transitions/side effects:
- ...

## 9. Interfaces and Contracts

Public API: <contract or N/A>
Internal interface: <symbol/input/output/errors/side effects>
Database/schema/config: <contract or N/A>
Authorization: <contract or N/A>

## 10. Invariants

- INV-001: <must remain true>

## 11. Edge Cases

### EDGE-001 — <name>
Condition: <...>
Expected behavior: <...>
Expected side effects: <...>

## 12. Failure Semantics

| Failure | Expected Response/Error/Status | Allowed Side Effects | Forbidden Side Effects |
|---|---|---|---|

## 13. RED / GREEN Behavioral Contract

### RED-001
Scenario: <meaningful negative/boundary/failure path>
Input/setup: <...>
Expected result: <independently derived result>
Expected side effects: <...>

### GREEN-001
Scenario: <primary intended-success path>
Input/setup: <...>
Expected result: <independently derived result>
Expected side effects: <...>

Verification order is RED then GREEN.

## 14. Performance Contract

For performance-sensitive work: baseline inputs, measurement method, target threshold, semantic parity, and response when evidence is unavailable. Otherwise: `N/A — no material performance requirement`.

## 15. Compatibility

Backward/API/data/schema/runtime compatibility: <... or N/A with reason>

## 16. Security and Permissions

Authentication/authorization/sensitive data/privilege boundaries: <... or N/A with reason>

## 17. Rollout / Rollback

Rollout sequence: <...>
Rollback trigger: <...>
Rollback procedure/data implications: <...>

For low-risk Tier M work with no deployment/migration concern, state one concise `N/A — <reason>` line.

## 18. Acceptance Criteria

### AC-001
Given <precondition>, when <action>, then <observable independently verifiable outcome>.

## 19. Requirement Traceability

| Requirement | Acceptance Criteria | Design/Contract | RED/GREEN |
|---|---|---|---|
| REQ-001 | AC-001 | §<section> | RED-001 / GREEN-001 |

## 20. Completion Gate

- [ ] no unresolved material question
- [ ] no silent assumption
- [ ] requirements/contracts are unambiguous
- [ ] edge/failure semantics defined
- [ ] RED/GREEN expected outcomes independently derived
- [ ] acceptance criteria complete
- [ ] traceability complete for affected requirements

## 21. Change Log

Add only after a material user-visible revision.

| Revision | Change | Reason |
|---|---|---|
