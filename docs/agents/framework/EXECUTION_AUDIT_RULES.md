# Execution and Audit Rules

> Load this file after explicit execution authorization, before the first implementation/audit cycle. Do not automatically load planning templates again.

## 1. Dispatch contract

Default to one bounded executor task at a time. Parallel work is allowed only when tasks are demonstrably independent, have no conflicting write surfaces, and cannot invalidate one another's assumptions.

The executor receives:
- the active task contract;
- exact referenced contract excerpts only when the task alone is insufficient;
- the smallest relevant repository context.

Do not attach entire specs/plans/history merely for convenience.

The executor must not expand scope, redesign architecture, reinterpret requirements/acceptance criteria, perform opportunistic refactors, solve unrelated defects, weaken valid tests, create/rename task files, change checklist status, or commit/push without authorization.

If the task cannot be completed exactly within contract, return `BLOCKED` with blocker, evidence, why proceeding is unsafe, and required coordinator decision.

## 2. Mandatory wait

After dispatching critical-path implementation, the coordinator must wait for the executor's terminal result. While it runs, the coordinator must not implement the same task, mark it complete, or produce final completion output.

## 3. RED then GREEN execution

For every implementation/remediation task:
1. execute the defined RED scenario first;
2. observe and record actual RED result;
3. only then execute GREEN;
4. observe and record GREEN;
5. if implementation or test-support code changes after the attempt, restart from RED.

Report separately:

```text
RED: PASS|FAIL|BLOCKED — scenario, method/command, observed result
GREEN: PASS|FAIL|BLOCKED — scenario, method/command, observed result
```

Do not derive expected values from current output. A generic passing suite is insufficient unless it proves both required flows and their order.

## 4. Executor completion report

The executor should return the compact schema in `docs/agents/templates/EXECUTOR_REPORT_TEMPLATE.md`. Do not restate full task/spec text in the report.

## 5. Independent audit

Executor completion is not task completion. The coordinator must independently inspect repository ground truth before changing task status.

Minimum audit:
- active task and referenced requirements/acceptance criteria;
- `git status` and relevant `git diff`;
- every changed file in task scope;
- tests/test quality and attempts to weaken coverage;
- relevant config/schema/migrations/generated artifacts;
- compiler/type/lint/build/test/runtime evidence as applicable;
- proof that RED was executed/observed before GREEN;
- proof that expected outcomes were independently derived;
- scope creep, TODO/FIXME shortcuts, unnecessary mocks, compatibility/security/performance issues as applicable.

Return exactly one verdict:
- `PASS`: contract satisfied with adequate evidence;
- `REWORK`: materially fixable implementation fails one or more requirements;
- `BLOCKED`: missing information/capability/upstream decision prevents safe progress.

Use `AUDIT_TEMPLATE.md` for non-trivial audits. Small Tier-S audits may be compact but must still map acceptance criteria, scope, RED/GREEN, and final verdict.

## 6. Remediation

On `REWORK`:
1. assign stable `AUD-*` findings;
2. state expected vs observed behavior and evidence;
3. create a bounded remediation contract addressing only those findings;
4. delegate remediation to the executor;
5. wait;
6. audit again;
7. repeat until `PASS` or genuine `BLOCKED`.

The coordinator must not silently patch the executor's implementation merely because remediation looks trivial.

## 7. Final integration audit

After all tasks pass, verify the system as a whole:
- callers/callees and cross-layer contracts agree;
- data model/schema/migration/application code agree;
- independently completed tasks do not conflict;
- no task invalidated another task's assumptions;
- representative integration/end-to-end path covers changed behavior when applicable;
- each implementation/remediation task has RED then GREEN evidence;
- repository status has no unexplained modifications;
- final implementation still satisfies the original approved user outcome.

Only after this audit passes may the change be reported complete.

## 8. Evidence discipline

Prefer inspected code over assumptions, observed command output over predictions, actual diffs over executor summaries, and tests/reproductions over claims. Never claim a test/build/command/RED/GREEN result that was not actually observed.
