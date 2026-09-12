# Execution and Audit Rules

> Load this file after explicit execution authorization, before the first implementation/audit cycle. Do not automatically load planning templates again.

## 1. Dispatch contract

Execute implementation/remediation from the approved dependency DAG in **bounded parallel waves**. Serial execution is required for dependent/conflicting work; independently ready work should share a wave when parallel execution materially reduces the critical path and the coordination/merge risk is acceptably low.

Before dispatching two writer tasks concurrently, the coordinator must establish all of the following:
- all required predecessors for both tasks are already `PASS`;
- write surfaces are disjoint and neither task can overwrite/generated-edit the other's files;
- neither task depends on the other's unfinished output, schema, contract, or assumptions;
- neither task can materially invalidate the other's planned RED/GREEN evidence;
- shared mutable state such as generated artifacts, lock files, caches, ports, DB/schema state, fixtures, services, or package-manager operations will not collide;
- the available runtime/shared-worktree behavior is known to be safe for those exact concurrent operations. When uncertain, serialize writers.

Reasoning/read-only audit or evidence subagents may fan out more broadly than writers, but they remain advisory and must be reconciled by the coordinator. Only the coordinator expands the execution wave by default; executors do not recursively create writer subagents unless the active contract explicitly permits it.

### Subagent result transport and coordinator fan-in

Executor/reasoning/audit subagents do **not** report completion by trying to inject a visible message into the coordinator/main chat session. Each subagent ends its assigned turn with its structured terminal result; the coordinator then collects that result with the runtime-native wait/collect/subagent-result mechanism and performs synthesis/audit. Absence of a user-visible subagent message bubble is normal and is not evidence that the result was lost.

Identifier safety is mandatory:
- session/thread IDs, subagent/recipient-agent IDs, turn IDs, item/call IDs, and agent names are separate opaque namespaces;
- never substitute or convert one into another; never manufacture a UUID or add/remove a UUID prefix to make an ID fit;
- only the coordinator may send follow-up input, resume, interrupt, or close a subagent, using the exact runtime-returned subagent identifier required by that primitive;
- a subagent must never resume/reopen the main/coordinator session solely to send its completion report.

If orchestration returns `invalid session id` or an equivalent identifier-type error, classify it as `ORCHESTRATION_TRANSPORT_ERROR`, not implementation/test failure. Do not repeat the malformed resume/send call. Preserve already-produced task changes/evidence, then recover through the correct wait/collect/list-subagent-result path when exposed. If no safe collection mechanism exists, keep the task state `UNKNOWN`/pending rather than spawning a conflicting writer or claiming the task failed.

### Runtime telemetry emission

The coordinator records execution/audit telemetry after each material lifecycle transition. Subagents/executors **return telemetry metadata in their terminal result**; they do not write the shared telemetry log themselves.

For each agent run, preserve when observable:
- logical `agent_run_id`, role (`coordinator|reasoning|executor|auditor`), route class (`C*|R*|E*`), work type, task/AC/TEST IDs;
- configured model/effort and runtime-reported effective model/effort; never infer an unreported effective route;
- start/end timestamps and duration when observable;
- terminal outcome (`PASS|REWORK|BLOCKED|FAILED|UNKNOWN`) and blocker/error category;
- retry count, escalation path, verification level reached, and whether external verification was required;
- runtime-reported input/output/reasoning/cache tokens and cost only when exposed; otherwise `null`;
- for reasoning subagents, coordinator adoption: `USED|PARTIAL|DISCARDED`;
- after audit, route assessment: `FIT|UNDERPOWERED|OVERPOWERED|UNKNOWN` with one concise evidence-based reason.

Do not log every shell/tool call or raw output. Aggregate tool activity as counts/categories when useful; formal verification commands may remain in normal executor/audit evidence, while telemetry stores only the verification ID/level/outcome/duration summary.

Transport failures such as `ORCHESTRATION_TRANSPORT_ERROR`, environment blockers, SSPI activation/clear events, and telemetry-write failures should each produce a concise event so weekly analysis can distinguish model quality from infrastructure noise.

### Executor-model selection at dispatch

For every implementation/remediation task, dispatch using the executor class recorded in the task/plan:
- `E0` -> `gpt-5.6-luna` / `high`;
- `E1` -> `gpt-5.6-luna` / `xhigh` (**default**);
- `E2` -> `gpt-5.6-luna` / `max`.

If no class is recorded, the coordinator must classify implementation entropy before dispatch rather than silently defaulting to Max. Escalate only after evidence that the selected route is insufficient. An executor failure caused by unresolved requirement/design/architecture ambiguity returns to coordinator reasoning/replanning; it is not solved by blindly increasing executor effort. Terra is not a default writer route.

The executor receives:
- the active task contract;
- exact referenced contract excerpts only when the task alone is insufficient;
- the smallest relevant repository context.

Do not attach entire specs/plans/history merely for convenience.

The executor must not expand scope, redesign architecture, reinterpret requirements/acceptance criteria, perform opportunistic refactors, solve unrelated defects, weaken valid tests, create/rename task files, change checklist status, or commit/push without authorization.

If the task cannot be completed exactly within contract, return `BLOCKED` with blocker, evidence, why proceeding is unsafe, and required coordinator decision.

### Protected configuration/environment execution boundary

The protected-configuration boundary in `AGENTS.md` is mandatory during execution and audit. Executors/auditors must not read, search within, parse, summarize, content-diff, create, modify, delete, rename, reformat, or regenerate protected repository configuration/environment files. Configuration/environment changes are user-owned external actions.

Safe repository inspection pattern:
1. use `git status --short` and/or `git diff --name-only` to identify changed paths;
2. classify protected paths by name/purpose without opening them;
3. inspect content diffs only for explicitly selected non-protected paths;
4. if a protected path is changed, record the path/status only and do not open its diff; determine with the user whether it is a pre-existing/user-owned change;
5. never run repository-root recursive content search unless protected configuration paths are excluded; prefer explicit source/test/doc allowlists.

Repository-native build/test/runtime commands may load protected configuration as opaque input. Do not inspect or echo the values. When failure diagnosis requires protected configuration contents/state, stop and ask the user immediately for the minimum non-sensitive fact. If output unexpectedly prints protected content or a secret, do not quote or analyze it; stop the affected diagnostic path.

If code implementation introduces a new configuration/environment requirement, do not edit configuration. Record an **External Configuration Action** containing target file/path, insertion location/section/key, exact non-secret snippet with `<SET_BY_USER>` placeholders for sensitive values, environment/scope, reason, and validation/restart step. If target/location or semantics are unknown, ask the user immediately instead of guessing.

## 2. Mandatory wait

After dispatching an execution wave, the coordinator must wait for every in-flight task whose result gates the next dependent work. Independent tasks in the same wave may complete/audit in any order, but the coordinator must not duplicate an already running/unknown task, implement that same task itself, mark it complete before audit, or produce final completion output while required wave work remains unresolved.

A failure/rework in one task does not automatically invalidate successful sibling tasks. Preserve sibling results/evidence unless the finding changes a shared dependency, assumption, contract, runtime basis, or other evidence-invalidating surface.

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
- `UNKNOWN`: do not reinterpret uncertainty as `BLOCKED`. When the runtime exposes a non-destructive **subagent-scoped** status/resume mechanism, use at most one focused status/recovery probe with the exact required ID type; never substitute a session/thread resume call. Otherwise preserve the task as waiting/unknown and do not start conflicting implementation.

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


### Transient-aware Windows Integrated Authentication / SSPI constraint

SSPI/client-credential failures can be transient. Do not turn one failed trusted-auth attempt into a permanent repository/environment constraint.

State model:

```text
UNCONFIRMED
  first Codex SSPI failure
  -> one focused retry/equivalent trusted-auth probe

UNCONFIRMED -> ACTIVE
  only if:
  1. user-confirmed equivalent interactive Windows trusted-auth command succeeds; and
  2. the focused Codex retry/equivalent probe still fails with the same auth-context class before SQL verification executes

ACTIVE -> CLEARED
  immediately when an equivalent Codex/runtime Integrated Authentication command later succeeds
```

Behavior by state:
- `UNCONFIRMED`: record the exact failure stage/error and perform at most one focused retry/equivalent probe when safe. Continue unaffected checks. Do not inspect protected configuration files, connection strings, environment values, credentials, SPNs, or secrets as a workaround.
- `ACTIVE`: do **not** keep retrying the same trusted-auth path merely to reconfirm the known failure. Continue unaffected compilation/static/source/unit verification. Mark only the gated SQL evidence as `BLOCKED_EXTERNAL_VERIFICATION / WINDOWS_INTEGRATED_AUTH_CONTEXT`, provide one exact minimal secret-free user-run command, and request only exit/status + concise non-secret PASS/FAIL evidence.
- `CLEARED`: cancel/obsolete any pending external-verification requirement that existed solely because of `WINDOWS_INTEGRATED_AUTH_CONTEXT`; return to normal local SQL/integration verification and use the successful local command as evidence where it proves the contract.

Self-healing rules:
- Any later equivalent `sqlcmd -E`, trusted-connection harness, or equivalent Windows Integrated Authentication command that succeeds inside Codex/runtime **immediately clears** an `ACTIVE` constraint for the current repository/environment.
- Once cleared, historical SSPI failures must not cause future SQL verification to be skipped or externalized. A later failure starts a fresh `UNCONFIRMED` cycle and must satisfy the activation criteria again.
- If a local success occurs before external evidence is returned, prefer the local success, mark the external request obsolete, and continue audit without asking the user to run the redundant command.
- If local success occurs after external evidence was already returned, keep whichever evidence is relevant to traceability, but the constraint still becomes `CLEARED` and future equivalent checks run locally by default.
- If the external interactive command fails behaviorally, treat that as normal verification evidence. If it fails with the same auth problem outside Codex, the Codex-only premise is invalid; stop and ask the user to resolve the Windows/SQL environment.

This path does not weaken independent audit. Never mark a task `PASS` solely because an SSPI issue is known or was previously known; `PASS` requires the required SQL evidence from a successful local run, accepted external evidence, or an approved contract that explicitly makes that SQL check non-blocking.
### Native Windows command convention

On native Windows/PowerShell, use repository-local executable wrappers when available, especially when PowerShell execution policy blocks npm/npx `.ps1` shims. Do not change machine execution policy unless the user explicitly authorizes that security-policy change.

Preferred order for a locally installed JavaScript test tool:

```text
1. direct repository-local `.cmd` executable
2. package-manager `.cmd` wrapper only when no working local executable exists
3. generic shell shim only when known to work in the current environment
```

#### Known Vite-family config-loader constraint

When the current repository/environment has already demonstrated that Vite config bundling fails before the target starts with `[plugin externalize-deps] Error: spawn EPERM`, treat that failure signature as a known environment constraint for subsequent Vite-family commands that load repository configuration. Do not repeat the same default `bundle` invocation merely to reconfirm the known failure.

For a Vite-family CLI command that supports `--configLoader native`:
1. keep using the repository-local executable when available;
2. preserve the intended command scope;
3. change only the config-loader path to `native`;
4. if `native` successfully loads config and execution reaches a later stage, classify any later failure separately instead of attributing it to the prior config-loader issue;
5. if `native` itself fails before the target starts for an environment/toolchain reason, apply the environment short-circuit rules above and stop blind retries.

Example native-Windows Vite build baseline after the bundle-path `spawn EPERM` signature is established:

```powershell
.\node_modules\.bin\vite.cmd build --configLoader native
```

This rule applies only after the repository/environment has established the bundle-path failure or other authoritative evidence makes the constraint known. On unaffected environments, use the repository's normal invocation. Do not use `runner` as a generic fallback when it has already demonstrated CommonJS/ESM incompatibility in the same repository/environment.

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

The executor should return the compact schema in `docs/agents/templates/EXECUTOR_REPORT_TEMPLATE.md`. Do not restate full task/spec text in the report. The report must always include `External configuration/environment actions: none | required`. For every required action, provide target file/path, insertion location/section/key, exact non-secret content with secret placeholders, applicable environment/scope, reason, validation/restart step, and whether pending user application blocks verification.

## 7. Independent audit

Executor completion is not task completion. The coordinator must independently inspect repository ground truth before changing task status.

The auditor may delegate bounded **read-only evidence collection or analysis** to one or more reasoning subagents using the complexity/model routing defined in the governing `AGENTS.md`. Independent audit dimensions may run in parallel (for example diff/scope review, test-quality review, contract/traceability review, or risk review) when fan-out reduces critical-path latency or coordinator context. Such subagents are advisory only: they must not modify repository behavior, and their conclusions do not replace the auditor's own reconciliation, inspection, or final verdict.

Minimum audit:
- active task and referenced requirements/acceptance criteria;
- `git status --short` and `git diff --name-only` before any content diff;
- content diff for every changed **non-protected** file in task scope;
- protected configuration/environment path changes by path/status only, never content;
- proof that no agent modified a protected configuration/environment file;
- required external configuration/environment actions and whether they are sufficiently specified for the user;
- tests/test quality and attempts to weaken coverage;
- relevant schema/migrations/generated application artifacts that are not protected configuration;
- task-local compiler/type/lint/test/runtime evidence as applicable, reusing valid executor evidence instead of re-running it by default; final repository build evidence is governed separately by the mandatory final build gate in §9 and must be freshly observed in the final post-remediation state;
- mandatory task buildability evidence for every code-producing implementation/remediation task;
- proof that RED was executed/observed before GREEN;
- proof that expected outcomes were independently derived;
- scope creep, TODO/FIXME shortcuts, unnecessary mocks, compatibility/security/performance issues as applicable.


### Mandatory task buildability gate

Before any implementation/remediation task is changed to `PASS`, independently confirm the task's planned **affected canonical build unit** is buildable in the post-task state. This is an early-attribution gate and is separate from the final repository build gate.

Evidence requirements:
- the task/plan identifies whether the gate is `YES` or legitimately `N/A`; `N/A` is reserved for work that cannot affect executable buildability;
- for `YES`, evidence includes the affected project/module/solution/workspace, the **exact secret-free build command**, observed exit/status, and confirmation the build was run after the last task-local executable/source/test/generated-code change;
- a statement such as “focused build exit 0” without the exact command and target/scope is insufficient;
- a compiled/executed test harness proves only what its build graph actually compiles. It must not be treated as evidence that an application project/solution builds unless that command actually includes the canonical affected build unit.

Outcome rules:
1. `PASS`: affected build unit actually builds successfully in the post-task state.
2. Compiler/parser/type/reference/link/build failure on the task's changed or affected dependency path is a blocking task finding and yields `REWORK`; localize it and create bounded remediation before reconsidering `PASS`.
3. `Fixed by a later task` is not a valid task verdict. When the current planned boundary is compile-coupled with later work and cannot build independently, return the task/plan to coordinator decomposition: merge the compile-coupled work or design backward-compatible intermediate states that build at every boundary.
4. A proven unrelated/pre-existing build failure that cannot be repaired within approved scope yields `BLOCKED`, not `PASS`.
5. A genuine failure before compilation/build execution because of environment/toolchain restrictions is `BLOCKED_ENVIRONMENT` under §4; it does not waive buildability.
6. Any later task-local executable change invalidates prior task-build evidence and requires the affected-unit build to be rerun.

The auditor may reuse executor build evidence only when all required fields above are present, the command/target is appropriate, freshness is established, and the result is trustworthy. Otherwise rerun the build or mark evidence insufficient.

Return exactly one verdict:
- `PASS`: contract satisfied with adequate evidence;
- `REWORK`: materially fixable implementation fails one or more requirements;
- `BLOCKED`: missing information/capability/upstream decision prevents safe progress.

Use `AUDIT_TEMPLATE.md` for non-trivial audits. Small Tier-S audits may be compact but must still map acceptance criteria, scope, RED/GREEN, and final verdict. If the coordinator re-runs a previously observed check, record why evidence reuse was insufficient.

## 8. Remediation

On `REWORK`:

If a finding requires a protected configuration/environment change, do **not** delegate that change to an executor and do not edit the protected file. Convert only the permitted code/test/migration portion into remediation work; report the configuration portion as a user-owned External Configuration Action. If the required protected target/location/semantics are unknown, ask the user immediately.

For permitted non-configuration remediation:
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
- each code-producing implementation/remediation task has a `PASS` affected-unit Task Buildability Gate from its final task-local executable state;
- no prior task was marked `PASS` while relying on a later task to repair compiler/parser/type/reference/link/build errors;
- repository status has no unexplained modifications; protected configuration/environment paths are assessed by name/status only, never content;
- final implementation still satisfies the original approved user outcome.

### Mandatory final repository build gate

A final integration audit **cannot return `PASS` unless the repository builds successfully in its final post-remediation state**. Task-local tests, focused project builds, static review, or executor claims do not substitute for this gate.

Build selection and safety:
- execute the repository's canonical aggregate/root/solution/workspace build when one exists;
- for a monorepo with no single aggregate build, execute every canonical top-level build unit required to establish that the repository is buildable as a whole;
- use the normal repository-native build path already known from direct user instruction, allowed documentation, repository policy, or safe path metadata; do not read protected configuration/build-manifest contents merely to discover a command; if the canonical build command cannot be determined without protected-content access, ask the user for the minimum non-sensitive command/fact and keep final audit `BLOCKED` until it is available;
- repository-native build tooling may consume protected configuration/build files as opaque input under the existing security boundary; never inspect or echo their protected contents.

Build outcome rules:
1. **PASS** requires an actually observed successful final build (normally exit code `0`) after all implementation and remediation changes are complete. Warnings do not fail the gate unless repository policy treats them as errors.
2. A compiler/parser/type/reference/link/build error is a **blocking audit finding**, not an ignorable test gap. Localize it using build diagnostics plus inspection of permitted non-protected source/test/generated-code surfaces.
3. If the build failure was introduced by the approved change, lies on an affected dependency path, or can be fixed without changing approved requirements/architecture/scope, create a bounded remediation contract, classify it independently as `E0`/`E1`/`E2`, delegate it under §9 remediation rules, wait, audit the diff, then rerun the canonical final build. Repeat until the build passes or a genuine blocker exists.
4. If the failure is proven pre-existing/unrelated and fixing it would expand approved scope or materially change behavior/architecture, do **not** silently ignore or patch it. Final audit remains `BLOCKED`; report the concrete build failure and request the required scope/decision.
5. If the build fails before compilation/build execution because of a genuine environment/toolchain restriction, apply §4 environment short-circuit rules. The build gate is `BLOCKED_ENVIRONMENT` and the final audit verdict remains `BLOCKED`; do not convert it to `PASS` merely because focused tests succeeded.
6. If build success requires a protected configuration/environment change, report the required user-owned External Configuration Action and keep final audit `BLOCKED` until it is applied and the final build is rerun successfully.
7. Any remediation after a successful build invalidates that build evidence. The canonical final build must be rerun after the **last** code/test/migration/generated executable change.

Record the exact build command (secret-free), exit/status, concise compiler/build result, any `AUD-*` findings/remediation cycles, and the final rebuild result in the audit evidence. Also emit the normal `verification_completed`/`audit_completed` telemetry so weekly analysis can measure build-failure and remediation rates.

### Mandatory final-audit remediation delegation

If the final integration audit finds **any issue whose resolution requires modifying permitted application code, test code, migration code, generated application/runtime code, or other non-protected executable repository behavior**, the auditor/coordinator must not patch it directly. The finding must be converted into a bounded remediation contract, classified independently as `E0`/`E1`/`E2` from the remediation's implementation entropy, and automatically delegated using that selected route.

**Protected configuration/environment changes are the exception:** they must never be patched or delegated. Report them as user-owned External Configuration Actions with target file/path, insertion location/section/key, exact non-secret content/placeholder, scope, reason, and validation/restart step. If applying the external action is required to establish correctness, final audit remains `BLOCKED` until the user applies it and verification can be rerun safely.

For each such finding:
1. assign or preserve a stable `AUD-*` finding ID;
2. describe expected vs observed behavior, concrete evidence, affected requirement/acceptance criterion, and the exact remediation scope;
3. create the smallest independently auditable remediation contract that fixes only the finding;
4. classify the remediation contract as `E0`/`E1`/`E2` from its own implementation entropy, then automatically dispatch it using that route;
5. wait for the executor's terminal result under the patience/stall rules in §2;
6. independently audit the resulting diff and verification evidence;
7. rerun only evidence invalidated by the remediation;
8. repeat the remediation -> delegate -> wait -> audit loop until the final audit reaches `PASS` or a genuine `BLOCKED` condition exists.

Do not ask the user for fresh execution authorization for a remediation that remains within the already approved requirements, scope, architecture, and execution authorization. Do not use auditor/coordinator direct implementation as a shortcut, even for a trivial one-line code or test fix.

If resolving the finding would materially change approved requirements, product behavior, architecture, dependency policy, migration strategy, security posture, or task scope, do **not** dispatch implementation under the old contract. Report `BLOCKED`, describe the required decision, obtain user authorization for the revised contract, then delegate the approved remediation to the implementation executor.

Only after this audit passes **and the mandatory final repository build gate is PASS** may the change be reported complete.

## 10. Evidence discipline

Prefer inspected non-protected code over assumptions, observed safe command output over predictions, actual non-protected diffs over executor summaries, and tests/reproductions over claims. Protected configuration/environment contents are never admissible inspection evidence; use only user-provided non-sensitive facts and safe path/status metadata. Never claim a test/build/command/RED/GREEN result that was not actually observed.
