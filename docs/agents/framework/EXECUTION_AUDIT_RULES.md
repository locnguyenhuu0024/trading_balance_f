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

### Executor patience and stall detection

Executor silence is not a failure condition. Elapsed time, lack of a response, or absence of a repository diff alone must not be used to classify the task as `BLOCKED`, restart the executor, or request coordinator takeover.

Treat executor state as one of the following:

```text
RUNNING   — active execution is observed, or no terminal result exists and the runtime still considers the executor usable
TERMINAL  — executor returned a final PASS/FAIL/BLOCKED result or the runtime reports normal completion
STALLED   — runtime explicitly reports termination/failure, the executor handle/thread is unusable, or a required tool/approval state is proven unable to progress
UNKNOWN   — current state cannot be established from available runtime evidence
```

Coordinator behavior:
- `RUNNING`: continue waiting. Do not duplicate the task, restart the executor, or infer failure from silence.
- `TERMINAL`: process the returned result normally and proceed to audit/rework/blocker handling as applicable.
- `STALLED`: record the concrete runtime evidence, then follow the recovery order below.
- `UNKNOWN`: do not reinterpret uncertainty as `BLOCKED`. When the runtime exposes a non-destructive status/resume mechanism, use at most one focused status/recovery probe; otherwise preserve the task as waiting/unknown and do not start conflicting implementation.

Do not use a fixed impatience timeout as proof of executor failure unless the runtime itself supplies an authoritative timeout/error. A long-running executor may still be valid when performing repository inspection, tests, tool calls, or high-reasoning implementation.

### Executor recovery order

When execution is genuinely stalled, recover in this order:
1. preserve the existing executor and inspect its terminal/runtime status when supported;
2. resume or nudge the same executor when the runtime explicitly supports doing so safely;
3. restart/replace the executor only after the existing execution is proven terminated or unusable;
4. coordinator direct implementation is a last resort and requires explicit user authorization unless the already-approved workflow expressly permits coordinator implementation.

Never spawn a replacement executor while the original executor is `RUNNING` or `UNKNOWN` if both could write the same task surface. Never classify `no response yet` or `no diff yet` as a terminal executor failure.

## 3. RED then GREEN verification checkpoints

Do not run the full formal RED/GREEN pair after every implementation edit. Separate the **implementation inner loop** from the **formal verification checkpoint**.

During the inner loop:
1. implement or remediate the bounded task;
2. use only the narrowest diagnostic test/check needed to guide the next edit;
3. diagnostic runs may repeat as needed and do not need to execute the full RED/GREEN pair;
4. diagnostic results do not satisfy final RED/GREEN evidence requirements.

When the executor believes the implementation is ready for verification, start one formal checkpoint:
1. execute the defined RED scenario first;
2. observe and record actual RED result;
3. only then execute GREEN;
4. observe and record GREEN;
5. escalate beyond V1 only when the planned verification ceiling or an explicit escalation trigger requires it.

Report formal evidence separately:

```text
RED: PASS|FAIL|BLOCKED — scenario, method/command, observed result
GREEN: PASS|FAIL|BLOCKED — scenario, method/command, observed result
```

After a formal checkpoint, a later code/test/config change invalidates only evidence that the change can materially affect. Re-run a scenario when at least one is true:
- code on its behavioral dependency path changed;
- its test, fixture, setup, mock, or test-support code changed;
- its expected result or approved contract changed;
- a shared/global dependency, configuration, schema, or runtime behavior that can affect it changed;
- the prior result is incomplete, contradictory, or unreliable.

Re-run only invalidated evidence. Restart the complete RED -> GREEN sequence only when both scenarios may be affected or their shared verification basis changed. If neither scenario is invalidated, reuse the existing formal evidence.

Do not derive expected values from current output. A generic passing suite is insufficient unless it proves the required flows and their order.

## 4. Environment and toolchain failure short-circuit

A command that fails before the test, build, runtime, or verification target actually starts must not be classified as an application-behavior failure. Distinguish **verification failure** from **verification infrastructure failure** before assigning RED/GREEN status.

Examples of environment/toolchain failures include:
- process-spawn denial such as `spawn EPERM`;
- sandbox or OS permission denial;
- shell execution-policy rejection;
- missing/unavailable executable or runtime dependency;
- filesystem/lock/antivirus/EDR denial unrelated to the implementation contract;
- test runner or build tool failing during bootstrap/config loading before the target tests execute.

When such a failure is observed:
1. record the exact command, failure stage, and error;
2. determine whether the target test/build/runtime actually started and, for tests, whether any relevant test executed;
3. perform at most **one focused diagnostic retry or alternate invocation** when it can distinguish project failure from environment/tooling failure;
4. do not repeatedly retry an identical command that fails for the same environment reason;
5. do not modify application code, tests, Vite/Vitest configuration, dependencies, or machine security policy merely to make a sandbox/tooling restriction disappear;
6. continue unaffected local verification when it provides useful evidence;
7. classify the blocked verification as `BLOCKED_ENVIRONMENT` and state the minimum external/manual verification required.

`BLOCKED_ENVIRONMENT` is not equivalent to `RED: FAIL` or `GREEN: FAIL`. If the relevant RED or GREEN scenario never executed, report it as blocked, for example:

```text
RED: BLOCKED — test infrastructure failed before the scenario executed
Environment: BLOCKED_ENVIRONMENT — <command>; <failure stage>; <error>
Tests executed: 0 relevant tests
Behavioral correctness: NOT DETERMINED
Required verification: <smallest external/manual command>
```

If an alternate invocation successfully starts the same tool and executes the required scenario, use the observed result normally and do not retain `BLOCKED_ENVIRONMENT` for that verification.

### Native Windows command convention

On native Windows/PowerShell, use repository-local executable wrappers when available, especially when PowerShell execution policy blocks npm/npx `.ps1` shims. Do not change machine execution policy unless the user explicitly authorizes that security-policy change.

Preferred order for a locally installed JavaScript test tool:

```text
1. direct repository-local `.cmd` executable
2. package-manager `.cmd` wrapper only when no working local executable exists
3. generic shell shim only when known to work in the current environment
```

#### Vitest direct invocation

When the repository uses Vitest on native Windows and `.\node_modules\.bin\vitest.cmd` exists, Codex **must invoke that executable directly** for diagnostic and formal verification. Do not route Vitest through `npm test`, `npm run test`, `npx vitest`, or equivalent package-manager indirection while the working repository-local executable is available.

For **Vitest-only verification, do not start a Vite dev/preview server** and do not run commands such as `node node_modules/vite/bin/vite.js ...` merely as a prerequisite to Vitest. Starting a Vite server is allowed only when the active contract explicitly requires a served application/browser/E2E flow; it is not part of normal Vitest RED/GREEN verification.

Choose the narrowest test scope first. On a normal environment, use the direct local Vitest executable with the repository's normal config. If the Codex/Windows environment is known to fail during Vite/Vitest config bundling or worker startup with `spawn EPERM`, use the sandbox-compatible invocation below instead of retrying the failing paths.

### Windows/Codex sandbox-compatible Vitest baseline

When all of the following have been observed:
- default config loading fails before tests execute with `[plugin externalize-deps] Error: spawn EPERM`;
- `--configLoader runner` is unsupported or fails while evaluating CommonJS/ESM dependencies (for example `ReferenceError: require is not defined`);
- `--configLoader native` successfully reaches the Vitest run phase;
- the default `forks` pool then fails to start a child process with `spawn EPERM`;

use `native` config loading plus the `threads` pool with one worker and disabled file parallelism:

```powershell
# V1 — exact test case when practical
.\node_modules\.bin\vitest.cmd run <relevant-test-file> -t "<test-name>" --config <vitest-config> --configLoader native --pool=threads --maxWorkers=1 --no-file-parallelism --reporter=minimal --silent=passed-only

# V2 — exact test file
.\node_modules\.bin\vitest.cmd run <relevant-test-file> --config <vitest-config> --configLoader native --pool=threads --maxWorkers=1 --no-file-parallelism --reporter=minimal --silent=passed-only
```

For V3/V4, preserve the same loader/pool/worker flags and broaden only the **test scope** when the verification-escalation rules require it.

This combination has distinct purposes:
- `--configLoader native` avoids the config-bundling path that can trigger `externalize-deps -> spawn EPERM`;
- `--pool=threads` avoids Vitest's `forks` pool and therefore avoids `node:child_process.fork()` for test workers;
- `--maxWorkers=1` and `--no-file-parallelism` keep execution serial and minimize worker creation inside the constrained environment.

Once this invocation successfully executes the required test scope, reuse it as the working Vitest command for equivalent diagnostic/formal checks in the current repository/environment. Do not probe `bundle`, `runner`, `forks`, npm/npx wrappers, or Vite dev-server startup again merely for completeness.

If a later run using this known-working baseline fails, first determine whether the failure is an actual test/application failure or a new environment/toolchain failure. Do not classify a worker/config startup error as RED/GREEN behavior evidence.

If the installed Vitest version does not support an optional output flag such as `--reporter=minimal` or `--silent=passed-only`, remove only the unsupported output flag. Preserve the direct executable, `native` loader, `threads` pool, single-worker, and no-file-parallelism settings when those are the known-working environment requirements.

If `.\node_modules\.bin\vitest.cmd` is missing or cannot be executed for a reason unrelated to application behavior, use the narrowest valid fallback and record why direct invocation was unavailable. Do not install/reinstall dependencies solely to change invocation style unless the task or user explicitly requires it.

## 5. Verification escalation and evidence reuse

Use the narrowest verification level that can prove the active contract:

```text
V1 — focused RED/GREEN scenario (single test/case or narrowest reproducible check)
V2 — complete relevant test file or tightly related test group
V3 — affected/related/changed test set
V4 — full repository/package suite
```

Start at V1. Escalate only when the current evidence is insufficient, the plan/task explicitly requires a broader level, or observed risk justifies it. Do not jump directly to V4 merely because a full-suite command exists. Typical V4 triggers include changes to global test/build configuration, shared foundational modules, migrations/schema/public contracts, cross-cutting infrastructure, or evidence of broader regression risk.

Tier defaults:
- **Tier S:** V1, then V2 when useful; no full suite by default.
- **Tier M:** V1 per task; V2/V3 only as needed; V4 at most once at final integration when warranted.
- **Tier L:** V1 per task plus planned V2/V3 integration checks; V4 at most once at final integration when warranted, unless trusted CI is explicitly the authoritative full-regression gate.

### Evidence reuse

Independent audit does **not** require blind re-execution of checks the executor already ran. The coordinator should reuse executor test evidence when all are true:
- the exact command/method and observed result are recorded;
- the evidence proves the referenced RED/GREEN/TEST/AC;
- no later change invalidated that specific evidence under the rules in §3;
- the test itself is not obviously weak, bypassed, over-mocked, or inconsistent with repository ground truth.

When later changes exist, perform an **evidence invalidation review** instead of assuming every prior result is stale. Map each changed surface to the scenarios/checks it can affect, preserve unaffected evidence, and re-run only invalidated checks. Re-run independently only when evidence is incomplete or contradictory, test quality is suspect, runtime state makes the result unreliable, or a high-risk contract explicitly requires reproduction. Execute the **narrowest missing or invalidated level**, not the entire suite by default.

### Output discipline

Prefer low-noise test/build output that preserves failures, warnings relevant to the contract, and final summaries while suppressing repetitive logs from passing checks. Do not stream or restate long successful output into the executor report; record command + concise result. On failure, retain the smallest diagnostic slice that explains the failure.

For Vitest when the installed version supports these flags, a focused native-Windows example is:

```powershell
.\node_modules\.bin\vitest.cmd run <relevant-test-file> -t "<test-name>" --reporter=minimal --silent=passed-only
```

Use broader Vitest scopes (`<test-file>`, `related`, `--changed`, or the full suite) only at the corresponding V2/V3/V4 level and only when their assumptions are valid for the repository.

## 6. Executor completion report

The executor should return the compact schema in `docs/agents/templates/EXECUTOR_REPORT_TEMPLATE.md`. Do not restate full task/spec text in the report.

## 7. Independent audit

Executor completion is not task completion. The coordinator must independently inspect repository ground truth before changing task status.

Minimum audit:
- active task and referenced requirements/acceptance criteria;
- `git status` and relevant `git diff`;
- every changed file in task scope;
- tests/test quality and attempts to weaken coverage;
- relevant config/schema/migrations/generated artifacts;
- compiler/type/lint/build/test/runtime evidence as applicable, reusing valid executor evidence instead of re-running it by default;
- proof that RED was executed/observed before GREEN;
- proof that expected outcomes were independently derived;
- scope creep, TODO/FIXME shortcuts, unnecessary mocks, compatibility/security/performance issues as applicable.

Return exactly one verdict:
- `PASS`: contract satisfied with adequate evidence;
- `REWORK`: materially fixable implementation fails one or more requirements;
- `BLOCKED`: missing information/capability/upstream decision prevents safe progress.

Use `AUDIT_TEMPLATE.md` for non-trivial audits. Small Tier-S audits may be compact but must still map acceptance criteria, scope, RED/GREEN, and final verdict. If the coordinator re-runs a previously observed check, record why evidence reuse was insufficient.

## 8. Remediation

On `REWORK`:
1. assign stable `AUD-*` findings;
2. state expected vs observed behavior and evidence;
3. create a bounded remediation contract addressing only those findings;
4. delegate remediation to the executor;
5. wait;
6. audit again;
7. repeat until `PASS` or genuine `BLOCKED`.

The coordinator must not silently patch the executor's implementation merely because remediation looks trivial.

## 9. Final integration audit

After all tasks pass, verify the system as a whole:
- callers/callees and cross-layer contracts agree;
- data model/schema/migration/application code agree;
- independently completed tasks do not conflict;
- no task invalidated another task's assumptions;
- representative integration/end-to-end path covers changed behavior when applicable;
- verification escalates only as far as needed for the selected tier/risk; a full suite is run at most once locally unless new changes invalidate it;
- when trusted CI owns authoritative full-regression coverage, record that ownership rather than duplicating the same V4 run locally;
- each implementation/remediation task has RED then GREEN evidence;
- repository status has no unexplained modifications;
- final implementation still satisfies the original approved user outcome.

Only after this audit passes may the change be reported complete.

## 10. Evidence discipline

Prefer inspected code over assumptions, observed command output over predictions, actual diffs over executor summaries, and tests/reproductions over claims. Never claim a test/build/command/RED/GREEN result that was not actually observed.
