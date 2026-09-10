# Planning Rules

> Load this file only when a repository change enters a planning cycle. Do not load execution/audit templates during planning unless required to define verification.

## 1. Planning objective

Produce the minimum set of artifacts that makes implementation mechanical, bounded, independently verifiable, and safe. Do not optimize for document length alone; optimize for **decision entropy removed per token**.

The planner owns unresolved product, business, data, security, compatibility, and architecture decisions. The executor must not invent them.

## 2. Planning tiers

Choose the smallest tier that preserves correctness.

### Tier S — small/local

Use when all are true:
- behavior is local and low-risk;
- architecture/public contracts/data/security/migration/concurrency are unaffected;
- required behavior is unambiguous after targeted inspection;
- one bounded task can implement and verify it;
- no material user decision is open.

Artifacts:
- compact canonical plan using `SMALL_PLAN_TEMPLATE.md`;
- one compact task using `SMALL_TASK_TEMPLATE.md`.

A separate design spec is optional. Do not create placeholder spec/decision/validation files merely to satisfy structure.

### Tier M — normal feature or bug

Use when behavior spans multiple symbols/files or requires non-trivial acceptance criteria but does not have L-level risk.

Artifacts:
- design specification using `SPEC_TEMPLATE.md`;
- implementation plan using `PLAN_TEMPLATE.md`;
- one or more tasks using `TASK_TEMPLATE.md`;
- decision ledger only when material clarification/decision/authorized assumption exists.

### Tier L — high-risk/cross-cutting

Use for architecture, data semantics, migrations, security/permissions, compatibility, concurrency, performance-sensitive changes, multi-service/cross-layer work, or changes whose failure has material operational impact.

Artifacts:
- full design specification;
- decision ledger when any material clarification/decision exists;
- full implementation plan;
- bounded tasks;
- full requirement traceability, rollout/rollback, and integration evidence;
- plan-validation report when repository reality invalidates an approved assumption.

When uncertain between M and L because consequences are unclear, inspect first; if risk remains materially ambiguous, ask the user.

## 3. Clarification gate

Before finalizing a specification or plan:
1. inspect authoritative repository code/config/schema/tests/docs that can answer the question;
2. separate facts from hypotheses;
3. identify all remaining material ambiguities;
4. batch related questions where practical;
5. ask the user for every unresolved material decision.

Do not infer business semantics from naming alone. Do not choose defaults merely because they are common. Do not treat current implementation as desired behavior when the user requested a behavior change.

A user may explicitly authorize an assumption. Record it as `A-*` and trace affected requirements/plan steps.

## 4. Stable identifiers

Use only the IDs needed by the selected tier:

```text
Q-001      clarification question
D-001      user decision
A-001      user-authorized assumption
OBS-001    observed repository fact
REP-001    reproduced behavior/failure
HYP-001    hypothesis
REQ-001    requirement
INV-001    invariant
EDGE-001   edge case
AC-001     acceptance criterion
P01        implementation plan step
T01        bounded execution task
TEST-001   test case
RED-001    negative/boundary/failure scenario
GREEN-001  intended-success scenario
VAL-001    plan-validation finding
AUD-001    audit finding
R01        remediation iteration
RISK-001   risk
```

Do not invent IDs merely to fill a template. After user approval, do not silently renumber stable IDs; mark removed items `REMOVED`/`SUPERSEDED`.

## 5. Source-of-truth precedence

When evidence/artifacts conflict:
1. direct user instruction and explicit user decisions;
2. repository/company policy and hard repository constraints;
3. latest user-approved specification;
4. latest user-approved canonical plan;
5. active task contract;
6. observed current implementation behavior.

Observed behavior is evidence, not automatically a requirement. If hard repository constraints invalidate an approved plan, use the Plan Validation Report process; do not silently redesign.

## 6. Traceability without duplication

For non-trivial work, maintain the minimum trace:

```text
REQ -> AC -> P-step -> T-task -> RED/GREEN -> audit verdict
```

Later artifacts should reference IDs instead of restating long semantics. Repeat only the exact contract fragment needed to make a task self-contained enough for execution.

Example:

```text
REQ-004 -> AC-006 -> P03 -> T07 -> RED-002/GREEN-002 -> PASS
```

No task can pass while a referenced requirement/acceptance criterion lacks implementation and verification evidence.

## 7. Artifact states

Use states only where useful:

```text
DRAFT -> BLOCKED_ON_CLARIFICATION -> READY_FOR_APPROVAL -> APPROVED
      -> EXECUTING -> VERIFYING -> PASS | REWORK | BLOCKED -> COMPLETE
```

Specifications may use `READY_FOR_PLAN` before `READY_FOR_APPROVAL`.

A material requirement change invalidates approval for affected artifacts until revised and re-approved.

## 8. Canonical locations

```text
docs/agents/specs/YYYY-MM-DD-<topic>-design.md
docs/agents/plans/YYYY-MM-DD-<topic>.md
docs/agents/decisions/YYYY-MM-DD-<topic>-decisions.md
docs/agents/validation/YYYY-MM-DD-<topic>-plan-validation.md
tasks/task_<two-digit-sequence>_<short-topic>.md
```

The plan under `docs/agents/plans/` is canonical. Do not create/update root `implementation_plan.md` unless the user explicitly requests it.

For task sequence allocation: inspect `tasks/task_*.md`, find the largest valid number, allocate the next number, and recheck the target filename immediately before creation. Only the coordinator allocates/creates task files. Completed task files are immutable; follow-up work gets a new task file.

## 9. Artifact loading

Load only what is needed:

- Tier S: `SMALL_PLAN_TEMPLATE.md`, then `SMALL_TASK_TEMPLATE.md`.
- Tier M/L specification: `SPEC_TEMPLATE.md`.
- Plan: `PLAN_TEMPLATE.md`.
- Task: `TASK_TEMPLATE.md`.
- Material clarification/decision: `DECISIONS_TEMPLATE.md`.
- Approved-plan mismatch: `PLAN_VALIDATION_TEMPLATE.md`.

Do not read all templates “for completeness”.

## 10. Task sizing and decision entropy

A task is ready for a lower-capability executor when:
- outcome is singular and observable;
- relevant design decisions are already resolved;
- allowed/forbidden write surfaces are explicit;
- implementation sequence is concrete enough to avoid architectural invention;
- RED/GREEN scenarios and expected outcomes are defined;
- stop conditions are clear.

Prefer **one independently auditable unit** over one task per file. Keep tightly coupled changes together when they implement one requirement and share one verification path. Split when objectives can fail independently, write surfaces are unrelated/conflicting, or one task would require substantial design judgment.

## 11. Token Budget / Handoff Budget

Treat token use as a constrained engineering resource, but never trade away correctness, requirement fidelity, safety, or auditability merely to hit a numeric target. Handoff count is the primary controllable budget; processed-token totals are soft planning targets because runtime context, caching, hidden reasoning, and tool payloads may not be directly observable.

### Default handoff targets

- **Tier S:** target **1 executor task** and therefore one primary executor -> audit cycle.
- **Tier M:** target **1-3 executor tasks**.
- **Tier L:** target **2-5 executor tasks**.

Exceeding these targets is allowed only when dependency boundaries, conflicting write surfaces, safety constraints, materially different verification paths, or independent auditability require additional tasks. Record the reason in the plan's task-decomposition section. Do not split work merely by file, directory, architectural layer, technology, or implementation step.

Before finalizing task decomposition, perform a **handoff-cost review**:
1. identify adjacent tasks that implement the same requirement or acceptance criterion;
2. identify tasks that share the same write surface and RED/GREEN verification path;
3. merge them when doing so does not increase decision entropy, scope ambiguity, write conflict, or audit difficulty;
4. keep them separate when they can fail independently or require materially different evidence.

Prefer the fewest executor handoffs that still leave every task independently auditable. One task may span DTO, repository, service, API, UI, and tests when those edits implement one bounded contract and are best verified as one coherent RED/GREEN path.

### Soft processed-token targets

Use these only as planning heuristics when token estimates are available:

```text
Tier S: target < 35k processed tokens
Tier M: target 50k-90k processed tokens
Tier L: target 120k-220k processed tokens
```

These ranges are not quota guarantees and do not include reliably unknowable hidden runtime costs. If a correct change requires exceeding them, exceed them rather than weakening the plan or verification.

When a workflow is projected to exceed the tier target, optimize in this order before removing required evidence:
1. remove duplicated requirement prose from later artifacts and reference stable IDs instead;
2. narrow repository reads to relevant files/symbols/tests;
3. avoid re-reading unchanged framework/template files in the same context;
4. merge safe adjacent executor tasks to reduce handoffs;
5. avoid repeating full spec/plan text in executor prompts; include only the bounded contract and required excerpts;
6. keep audit evidence focused on changed surfaces and referenced acceptance criteria.

Never save tokens by skipping clarification of material ambiguity, RED/GREEN verification, required tests, independent audit, or final integration checks.

### Verification budget and escalation ceiling

Plan the **smallest verification scope that can prove the approved contract**, then define explicit escalation triggers instead of defaulting to the full suite. Use this scope ladder:

```text
V1 — focused RED/GREEN scenario (single test/case or narrowest reproducible check)
V2 — complete relevant test file or tightly related test group
V3 — affected/related/changed test set
V4 — full repository/package suite
```

Default planning targets:
- **Tier S:** V1 is mandatory; V2 is the normal ceiling. Do not plan V3/V4 unless a concrete shared-surface or regression risk requires it.
- **Tier M:** V1 per task, then V2/V3 only where affected-surface risk warrants it. V4 is not a per-task default; use it at final integration only when broad regression risk justifies it or when no authoritative CI covers it.
- **Tier L:** V1 per task plus planned V2/V3 integration coverage. V4 may run once at final integration when appropriate; if trusted CI is the authoritative full-regression gate, record CI ownership instead of duplicating the same full suite locally.

Every plan/task should state the intended verification ceiling and the conditions that justify escalation. Do not run a broader level merely because it exists. Full-suite execution is evidence, not a ritual.

Plan verification as two phases: a cheap **diagnostic inner loop** during implementation, followed by one formal RED -> GREEN checkpoint when the executor declares the implementation ready. Later edits invalidate only the verification scenarios whose dependency path, test/support surface, expected result, or shared/global basis may have changed; plan selective re-runs instead of unconditional full RED/GREEN restarts.

When a test runner supports low-noise output, prefer a reporter/mode that preserves failures and final summaries while suppressing repetitive passing-test logs. Do not suppress diagnostics needed to evaluate a failure.

## 12. Definition of Ready

Before dispatch, confirm applicable items:
- objective and requirements are unambiguous;
- no material question remains open;
- no silent assumption remains;
- user-authorized assumptions are recorded;
- architecture/significant design decisions are resolved;
- dependencies/predecessors are known;
- allowed and forbidden scope are explicit;
- interfaces/contracts and important edge/failure behavior are defined;
- required tests are defined;
- at least one meaningful RED and the primary GREEN have independently derived expected results;
- RED is ordered before GREEN;
- diagnostic method, formal RED/GREEN checkpoint, verification ceiling, escalation triggers, evidence-invalidation rules, and completion evidence are defined;
- no significant decision is intentionally left to the executor.

If missing information cannot be resolved from authoritative repository evidence, STOP and ask the user.

## 13. Plan validation

If inspection reveals that an approved plan/spec assumption is false, incomplete, incompatible with repository reality, or unsafe:
1. stop the affected branch;
2. do not redesign silently;
3. create/update `docs/agents/validation/...` using `PLAN_VALIDATION_TEMPLATE.md`;
4. identify affected `REQ/AC/P/T` IDs;
5. require `REPLAN`, `USER_CLARIFICATION`, or `NO_CHANGE` explicitly;
6. revise affected artifacts and obtain fresh approval when the contract materially changes.
