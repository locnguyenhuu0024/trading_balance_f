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

### Coordinator routing gate

Choose the main coordinator route separately from the planning tier. Planning tier measures change/risk scope; coordinator routing measures the **dominant cognitive workload**.

Evaluate two axes:
- **reasoning complexity:** `STANDARD` or `HARD`;
- **orchestration complexity:** `LOW` or `HIGH` based on dependency graph size, independently ready work, number of waves/subagents, and integration/audit coordination.

Default routing when the runtime supports explicit main-model selection:

| Reasoning | Orchestration | Main coordinator |
| --- | --- | --- |
| `STANDARD` | `LOW` | `gpt-5.6-sol` / `medium` |
| `HARD` | `LOW` | `gpt-5.6-sol` / `high` |
| `STANDARD` | `HIGH` | `gpt-6-astra` / `low` |
| `HARD` | `HIGH` | `gpt-6-astra` / `low`, with hard bounded reasoning delegated to `gpt-5.6-sol` / `high` reasoning subagents |

Do not map planning tier directly to coordinator model. A Tier-L decision can still be one hard reasoning problem suited to Sol High; a Tier-M change can become orchestration-heavy when it has many independent tasks and integration waves. If the current runtime fixes the main model, treat this table as best-effort routing guidance, not a reason to block planning.

### Specification/planning decomposition and parallel reasoning

The coordinator owns every canonical specification/plan and all final requirement/architecture interpretations, but it should offload independently bounded analysis/drafting units when doing so improves performance/price or reduces coordinator context.

After material ambiguities are resolved, candidate reasoning units include:
- repository facts/current behavior/evidence extraction -> usually `R0`/`R1`;
- requirement-to-acceptance-criterion mapping, edge cases, normal failure modes, bounded interface/database analysis -> usually `R2`;
- architecture/concurrency/distributed-system/performance/high-impact trade-offs -> usually `R3`;
- independent critique/adversarial review -> choose the lowest sufficient route from `R1`–`R3`, escalating only with evidence.

Independent units may run in parallel. Each subagent returns a bounded proposal/evidence package keyed to the relevant stable IDs; it does not finalize product semantics, approve architecture, or directly own the canonical artifact. The coordinator reconciles contradictions, resolves source-of-truth precedence, deduplicates prose, and writes/finalizes the canonical specification/plan.

#### Planning-subagent result transport

Planning/reasoning subagents return their bounded proposal/evidence package as the terminal output of their own assigned turn. They do not need to post a visible message into the main/coordinator chat thread, and they must not call session/thread resume merely to report completion. The coordinator performs fan-in using the runtime's native wait/collect/subagent-result mechanism and then writes the canonical planning artifact.

All runtime IDs are typed opaque identifiers. Never use a subagent/recipient-agent ID, agent name, turn/item/call ID, or other handle as a session/thread ID. Only the coordinator may send/resume a subagent for follow-up, and only with the exact ID type required by that runtime primitive. An `invalid session id` during fan-in is a transport misuse: stop that malformed route and recover through the correct subagent collection primitive rather than retrying or coercing the ID.

Treat parallel reasoning as a latency/context optimization, not an automatic cost saving. Fan out only when the expected benefit exceeds duplicated context + handoff + fan-in/reconciliation overhead.

### Planning telemetry

During planning/brainstorm/spec/plan work, the coordinator records only high-level telemetry required for later evaluation:
- `workflow_started` with planning tier and selected coordinator route;
- one `clarification_round` event per material user decision/brainstorm round, with counts of open/resolved decisions but without copying the full conversation;
- `spec_ready` / `plan_ready` with requirement/AC/task counts and revision number;
- reasoning-subagent dispatch/completion with `R0`-`R5`, work type, configured/effective route when exposed, outcome, duration/usage when exposed, and coordinator adoption (`USED|PARTIAL|DISCARDED`);
- `route_escalated` only when a route actually changes.

Do not optimize the workflow to make telemetry look good. Telemetry observes the normal planning contract; it does not replace clarification, source-of-truth precedence, approval, or traceability.

### Implementation-executor routing gate

Before finalizing each task, classify its **implementation entropy** separately from planning tier and reasoning complexity:

| Executor class | Use when | Target |
| --- | --- | --- |
| `E0 — mechanical` | implementation is repetitive/obvious and requires almost no coding judgment | `gpt-5.6-luna` / `high` |
| `E1 — normal bounded` | normal clearly specified implementation with explicit invariants/AC and moderate coding judgment | `gpt-5.6-luna` / `xhigh` **default** |
| `E2 — complex bounded` | coding is intrinsically intricate (complex SQL/transactions/state machines/algorithms/migrations/many invariants) while product and architecture decisions are already resolved | `gpt-5.6-luna` / `max` |

Planning rules:
- Record the selected executor class in each task artifact. Do not derive executor class mechanically from Tier S/M/L.
- Lower executor cost by reducing **decision entropy**: resolve requirements, architecture, edge cases, write surfaces, invariants, and RED/GREEN expectations before dispatch.
- Prefer `E0`/`E1` when the task has been made mechanical enough; do not use `E2` as a blanket safety default.
- If the task still requires product/architecture invention, it is not ready for any executor class; return to clarification/planning.
- Terra is not part of the default implementation ladder. Use it only when explicit workload/runtime evidence justifies an exception.

### Protected configuration/environment planning boundary

Repository configuration/environment contents are **not an inspectable planning source** in this protected-config variant. The planner may use only protected path/name/existence metadata plus configuration facts explicitly supplied by the user. Never read, search within, diff, summarize, or infer values from protected configuration files. If a required planning fact depends on protected configuration, ask the user immediately for the minimum non-sensitive fact; never request a whole config file or a secret.

When a change requires configuration/environment setup, model it as a **user-owned external configuration action**, not an executor write. The plan/spec/task must identify, from user-provided facts or safe path metadata:
- target file/path, or that a new protected file must be created by the user;
- insertion location/section/key;
- exact non-secret content to add/change, using `<SET_BY_USER>` or another explicit placeholder for sensitive values;
- environment/scope;
- reason/dependency;
- validation/restart step;
- whether verification can complete before the user applies the action.

If the target path/location or required semantics are unknown, do not guess: ask the user before finalizing the affected plan/task. Protected configuration actions are never placed in an executor Allowed Write Surface.


### External Windows-auth SQL verification planning

When planned SQL integration verification depends on Windows Integrated Authentication and the repository/environment has an established `WINDOWS_INTEGRATED_AUTH_CONTEXT` constraint, plan that check as **user-executed external verification** rather than a repeated Codex-local retry. The plan/task must state the exact secret-free command to run, expected evidence to return (exit code/status plus concise non-secret output), the RED/GREEN/TEST IDs it proves, and whether completion is blocked until that evidence is supplied. Do not add a SQL username/password or inspect protected connection configuration merely to bypass the Codex SSPI limitation.

## 3. Clarification gate

Before finalizing a specification or plan:
1. inspect authoritative non-protected repository code/schema/tests/docs that can answer the question; never inspect protected configuration/environment contents;
2. if a needed fact depends on protected configuration/environment data, ask the user immediately for the minimum non-sensitive fact;
3. separate facts from hypotheses;
4. identify all remaining material ambiguities;
5. batch related non-configuration questions where practical; configuration-dependent questions are asked immediately when they block safe planning;
6. ask the user for every unresolved material decision.

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
- protected configuration/environment files are explicitly outside executor write/read scope;
- any required configuration/environment action is documented as user-owned external work with target/location/content placeholders;
- relevant design decisions are already resolved;
- allowed/forbidden write surfaces are explicit;
- implementation sequence is concrete enough to avoid architectural invention;
- RED/GREEN scenarios and expected outcomes are defined;
- stop conditions are clear.

Prefer **one independently auditable unit** over one task per file. Keep tightly coupled changes together when they implement one requirement and share one verification path. Split when objectives can fail independently, write surfaces are unrelated/conflicting, or one task would require substantial design judgment.

For every multi-task plan, build a dependency DAG and identify execution waves. A task may share a wave with another task only when:
- neither depends on the other's unfinished output;
- their allowed write surfaces are disjoint;
- they cannot invalidate one another's assumptions or planned evidence;
- shared mutable runtime/build/test state will not collide.

Do not split one coherent contract solely to manufacture parallelism. Conversely, when two independently auditable tasks are both ready and parallel-safe, do not serialize them merely by default if a parallel wave materially reduces the critical path.

### Buildable task boundaries and compile coupling

Every code-producing implementation/remediation task must leave its **affected canonical build unit buildable** before that task may reach `PASS`. A dependency chain is allowed; a broken-build chain is not.

Planning rules:
- identify the smallest canonical project/module/solution/workspace build unit that compiles the task's changed executable sources together with the compile-time consumers needed to prove the task boundary is coherent;
- record the exact secret-free build command in the plan/task when it is known from user instruction, allowed documentation/repository policy, prior safe evidence, or safe path metadata; never inspect protected build/configuration contents merely to discover it;
- if the task changes only non-executable docs/data and cannot affect compilation/buildability, the task buildability gate may be `N/A` with a concise reason; otherwise a code-producing task requires the gate;
- if two or more proposed tasks must coexist before the affected build unit can compile, they are **compile-coupled** and must not be independently marked `PASS` in a broken intermediate state; either merge them into one independently auditable task or stage the change through backward-compatible intermediate states where every task boundary remains buildable;
- changing an interface/type/signature in one task and deferring required implementations/consumers/import disambiguation to a later task is invalid when the earlier boundary would not build;
- `fixed by a later task` is never valid evidence for a current task's `PASS`;
- a focused test harness compiling/running does not prove the affected application build unit compiles unless that harness command actually builds that canonical unit.

The per-task buildability gate complements rather than replaces the mandatory final repository build gate: task-level builds provide early attribution; final audit still proves whole-repository integration.

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

### Parallelism budget

Use **smallest useful concurrency**. Parallelism primarily reduces wall-clock latency; additional agents can increase total model cost through duplicated context, startup/handoff, and merge/audit overhead.

Soft concurrency guidance across reasoning + implementation subagents:
- **Tier S:** normally `1-2` concurrent subagents; normally at most **1 writer**.
- **Tier M:** normally `2-4` concurrent subagents; normally at most **2 concurrent writers**.
- **Tier L:** normally `3-6` concurrent subagents; normally at most **3 concurrent writers** unless the runtime already provides stronger isolation and the plan proves the write/runtime surfaces are independent.

These are not quotas or targets to fill. Use fewer agents when the work is small or coordination overhead dominates. Reasoning/read-only fan-out may be broader than writer fan-out because it has lower merge risk. Only the coordinator should expand concurrency by default; nested subagents should not recursively fan out unless the coordinator explicitly delegates that authority for a bounded reason.

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
2. narrow repository reads to relevant non-protected files/symbols/tests and never use protected configuration contents as a token-saving shortcut;
3. avoid re-reading unchanged framework/template files in the same context;
4. merge safe adjacent executor tasks when handoff/merge overhead exceeds any parallel critical-path benefit;
5. parallelize only genuinely independent ready work whose latency benefit exceeds duplicated-context/fan-in cost;
6. avoid repeating full spec/plan text in executor prompts; include only the bounded contract and required excerpts;
7. keep audit evidence focused on changed surfaces and referenced acceptance criteria.

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
- no significant decision is intentionally left to the executor;
- protected configuration/environment contents are not required to be read by the executor;
- any required external configuration/environment action is documented with target path/location, exact non-secret content or placeholder, scope, reason, and validation step.

If missing information cannot be resolved from authoritative non-protected repository evidence, STOP and ask the user. If the missing information concerns protected configuration/environment state, ask the user immediately and do not attempt repository inspection of that content.

## 13. Plan validation

If permitted non-protected inspection reveals that an approved plan/spec assumption is false, incomplete, incompatible with repository reality, or unsafe:
1. stop the affected branch;
2. do not redesign silently;
3. create/update `docs/agents/validation/...` using `PLAN_VALIDATION_TEMPLATE.md`;
4. identify affected `REQ/AC/P/T` IDs;
5. require `REPLAN`, `USER_CLARIFICATION`, or `NO_CHANGE` explicitly;
6. revise affected artifacts and obtain fresh approval when the contract materially changes.

If validation would require reading protected configuration/environment contents, do not inspect them. Ask the user for the minimum non-sensitive fact needed and record that user-provided fact/decision as the validation evidence source.
