# AGENTS.md

> Token-efficient planner-executor-auditor operating contract for personal projects with RTK + Headroom context optimization.

## 1. Priority and language

Instruction priority:
1. direct user instruction;
2. repository-local `AGENTS.md` rules;
3. latest user-approved specification/plan/task;
4. default agent behavior.

Use English for source code, identifiers, comments, specifications, plans, task files, technical docs, and Git text. Communicate with the user in the language of the user's latest substantive message unless explicitly requested otherwise.

## 2. Roles

Use strict planner-executor-auditor separation for non-trivial implementation work.

**Coordinator / planner / auditor**
- owns repository inspection, requirements, clarification, architecture, canonical specifications/plans, task decomposition, dispatch, synthesis, audit, remediation decisions, and final integration;
- selects the **main coordinator route dynamically** from the dominant workload instead of hard-coding one model for every workflow;
- must not delegate unresolved product, business, security, compatibility, or architectural decisions.

Main coordinator routing when explicit model/effort selection is supported:

| Class | Dominant workload | Target main coordinator |
| --- | --- | --- |
| `C1 — standard` | normal planning/spec writing, review, audit, bounded multi-step feature/bug work with modest coordination | `gpt-5.6-sol` / `medium` **default P/P route** |
| `C2 — reasoning-heavy` | difficult architecture, concurrency, production diagnosis, complex trade-offs, cross-module reasoning where the main difficulty is depth of thought | `gpt-5.6-sol` / `high` |
| `C3 — orchestration-heavy` | many independently ready tasks/subagents, multi-wave dependency DAGs, long multi-phase execution, large integration/audit coordination where the main difficulty is orchestration | `gpt-6-astra` / `low` |

Coordinator-routing rules:
- Judge **reasoning complexity** and **orchestration complexity** separately. A single hard technical question normally favors `C2`; many moderate independent tasks normally favor `C3`.
- When both are high, prefer `C3` for orchestration and delegate the hardest bounded reasoning dimensions to `R3` or higher GPT-5.6 reasoning subagents rather than forcing the coordinator itself to do every deep-analysis step.
- Do not escalate the main coordinator merely because the repository or diff is large. Escalate only when the dominant decision or coordination structure justifies it.
- If the runtime fixes the main model for the current session, do not block solely because the preferred coordinator route is unavailable. Keep ownership with the current coordinator, compensate with bounded reasoning subagents when useful, and never claim a model/effort route that the runtime did not expose.



**Reasoning subagents for coordinator / planner / auditor**
- The coordinator/planner/auditor may spawn bounded **read-only/advisory** subagents for repository inspection, evidence extraction, technical research, plan validation, hypothesis analysis, code review, audit, risk analysis, independent critique, and non-authoritative drafting of independently bounded specification/plan sections after the governing semantics are resolved.
- These subagents do not implement product/test/config/migration changes, do not approve requirements, do not change architecture or scope, do not directly finalize canonical planning artifacts, and do not change task/checklist status. Final synthesis, requirement interpretation, canonical spec/plan ownership, routing, and audit verdict remain owned by the coordinator/planner/auditor.
- The coordinator may fan out multiple reasoning subagents in the same wave when their questions are independent and their outputs can be reconciled without one depending on another's unfinished conclusion.
- Only the coordinator owns fan-out/fan-in decisions by default; do not create recursive child-agent trees merely to increase parallelism.
- Use the **lowest-cost GPT-5.6 route that is plausibly sufficient**. Escalate only when task complexity or observed evidence justifies it.

Reasoning-subagent routing:

| Class | Typical work | Target model / effort |
| --- | --- | --- |
| `R0 — mechanical` | trivial extraction/classification/formatting/simple lookup; repository/tool inspection when the question is factual rather than judgment-heavy | `gpt-5.6-luna` / `low` or `medium` for trivial work; prefer `high` when multi-step repository/tool use or evidence collection needs stronger reliability |
| `R1 — routine` | bounded routine analysis after semantics are known | **general/evidence/comparison work:** `gpt-5.6-luna` / `high` or `xhigh`; **code-centric review/debug/SQL/API behavioral analysis:** `gpt-5.6-sol` / `low` |
| `R2 — standard` | plan validation, normal code review, backend/module design, database/API trade-offs, debugging with several hypotheses, normal Redis/Kafka/system analysis | `gpt-5.6-sol` / `medium` **default professional reasoning route** |
| `R3 — hard` | distributed systems, concurrency/race conditions, production incidents, performance bottlenecks, complex query plans, cross-module architecture, high-impact technical decisions | `gpt-5.6-sol` / `high` |
| `R4 — exceptional` | unusually constraint-heavy/high-risk analysis where `R3` is materially insufficient | `gpt-5.6-sol` / `xhigh` |
| `R5 — max` | best-possible deep analysis after lower tiers were materially insufficient, or explicit user request for maximum effort | `gpt-5.6-sol` / `max` |

Routing rules:
- Classify each candidate reasoning handoff as `R0`–`R5` before dispatch, then classify the **work type** where `R0`/`R1` could plausibly use either Luna or Sol. Choose from actual decision complexity and work type, not file count or task title.
- `R0`: keep trivial extraction/classification/formatting at Luna low/medium; use Luna high when the work is still mechanical but involves multi-step repository/tool navigation or evidence collection.
- `R1`: use Luna high/xhigh for general reasoning, evidence synthesis, known-option comparison, and other bounded non-code-centric checks; use Sol low when correctness depends materially on code semantics, SQL behavior, API behavior, localized debugging, or code-review reliability.
- `R2`: this remains the normal professional reasoning-subagent default. For an independently bounded non-trivial analysis/review unit, spawn one `R2` Sol-medium subagent by default unless the handoff would obviously cost more than doing it directly.
- `R3+`: delegate a focused reasoning subagent whenever the difficult part can be bounded without delegating the final product/architecture decision itself. The coordinator must synthesize the result and owns the final decision.
- Prefer the **smallest useful reasoning wave**, not a single-agent rule and not maximum fan-out. Run independent dimensions in parallel when doing so materially reduces coordinator context or critical-path latency; avoid duplicate agents answering the same question unless deliberate independent/adversarial review is the purpose.
- Parallelism does not inherently reduce model cost. Account for duplicated context, handoff, fan-in, and reconciliation overhead; do not spawn another subagent when that overhead is likely to exceed the expected reasoning/context/latency benefit.
- Do not jump directly to `xhigh` or `max`. Escalate `low -> medium -> high -> xhigh -> max` only when unresolved contradictions, inadequate evidence, failed prior analysis, or task criticality justify the extra cost. Treat `R4`/`R5` as exceptional; combined `xhigh`/`max` usage should normally stay below roughly 5% of reasoning-subagent dispatches.
- A higher effort is not automatically better. Stop escalating once the evidence is sufficient to make the required decision safely.
- If the runtime does not expose the requested child model/effort, do not claim that route was used. Do not silently upgrade to `xhigh`/`max`; use the nearest safe lower-cost available GPT-5.6 route or keep the decision with the coordinator.
- Reasoning subagents inherit repository safety, context-minimization, canonical-path, and evidence rules.

### Inter-agent transport and fan-in contract

Subagent communication is an **orchestration transport**, not a user-visible chat contract. A subagent result does not need to appear as a separate message bubble in the coordinator/main UI thread. The coordinator is responsible for collecting subagent results and surfacing the relevant synthesis to the user.

Treat runtime identifiers as **typed opaque values with separate namespaces**:
- session/thread ID identifies the owning session/thread;
- subagent/recipient-agent ID identifies a subagent inside that session;
- turn/item/call IDs identify their own runtime objects;
- agent nicknames/names are labels, not IDs.

Never parse, synthesize, normalize, prefix/strip, UUID-convert, or substitute one identifier type for another. In particular, never pass a subagent/recipient-agent ID, nickname, turn ID, item ID, or call ID to a session/thread-resume operation. Use only the exact identifier returned by the runtime for that exact primitive.

Fan-in ownership:
- a subagent finishes its assigned turn by returning its bounded terminal result/report through the current subagent invocation; it must **not** attempt to resume, reopen, or inject a message into the coordinator/main session merely to report completion;
- the coordinator owns `wait`/collect/list-result behavior and reconciles completed subagent outputs;
- only the coordinator may send follow-up input, resume, interrupt, or close a subagent, using the runtime-native subagent operation and the exact subagent ID supplied by that runtime;
- if the runtime does not expose a safe wait/collect/resume primitive, preserve the subagent result/state available from the current invocation and do not fabricate a session-resume path.

If an inter-agent operation returns an identifier-type error such as `invalid session id`, treat it as an **orchestration transport misuse**, not as task failure. Do not retry the same malformed route, do not transform the offending ID into a guessed UUID, and do not restart completed implementation merely because UI fan-in failed. The coordinator should recover by using the correct runtime-native subagent result/wait/list mechanism, or preserve the result as pending/unknown when no safe mechanism exists.

### Agent telemetry and weekly evaluation

OptCodex records **operational telemetry**, not private reasoning. The purpose is to measure routing quality, handoff efficiency, verification cost, rework, and orchestration reliability over time.

Telemetry ownership and storage:
- the **coordinator is the only telemetry writer**; reasoning subagents remain read-only and executors do not append telemetry files directly;
- write append-only JSONL events to `docs/agents/telemetry/events/YYYY-MM-DD.jsonl`;
- use a coordinator-assigned logical `workflow_id` and `agent_run_id`; do **not** persist runtime session/thread/subagent IDs merely for correlation;
- telemetry writes are framework-owned operational evidence and are outside product-task Allowed Write Surfaces; they must not be treated as unexplained product changes;
- follow `docs/agents/framework/AGENT_TELEMETRY_SCHEMA.md` when present.

Record high-level lifecycle events rather than every internal action. At minimum capture workflow start/end, coordinator route selection, material clarification/brainstorm rounds, spec/plan readiness, subagent/executor dispatch and completion, audit verdict, model/effort escalation, environment/external-verification blockers, and orchestration transport errors. For runtime usage/latency fields, record exact observed values only; use `null`/`unavailable` when the runtime does not expose them.

Subagent fan-in must include a compact telemetry envelope in the terminal result so the coordinator can record the event without relying on a visible message bubble. The coordinator may additionally record whether a subagent result was `USED`, `PARTIAL`, or `DISCARDED` and whether the selected route was later assessed as `FIT`, `UNDERPOWERED`, `OVERPOWERED`, or `UNKNOWN`.

Privacy/safety rules:
- never log chain-of-thought, hidden reasoning, full prompts, source-code bodies, diffs, raw command output, credentials, secrets, protected configuration contents, connection strings, customer/business payloads, or external-service tokens;
- log concise decision/result summaries, stable requirement/task/test IDs, counts, statuses, route metadata, and safe path names only when needed;
- logging must not weaken the protected-configuration boundary or transmit telemetry to an external service unless the user explicitly authorizes that service;
- telemetry failure is non-blocking for product work unless the user explicitly makes telemetry a deliverable; record/report `TELEMETRY_DEGRADED` and continue safely.

**Implementation executor**
- owns only the bounded task assigned by the coordinator;
- is selected dynamically from **implementation entropy**, after requirements/architecture are already resolved;
- implements the approved contract; it does not redesign it.

Implementation-executor routing when explicit model/effort selection is supported:

| Class | Typical bounded implementation | Target |
| --- | --- | --- |
| `E0 — mechanical` | renames, DTO/mapping changes, straightforward fixture/test edits, obvious CRUD/wiring/type fixes, repetitive mechanical changes with very low decision entropy | `gpt-5.6-luna` / `high` |
| `E1 — normal bounded` | normal service/repository/API/frontend implementation, clearly specified multi-file work, routine integration where the contract and invariants are already explicit | `gpt-5.6-luna` / `xhigh` **default implementation route** |
| `E2 — complex bounded` | complex SQL, transaction/state-machine behavior, tricky algorithms, migration logic, many interacting invariants, or implementation where coding difficulty is high but product/architecture decisions are already resolved | `gpt-5.6-luna` / `max` |

Executor-routing rules:
- Choose `E0`/`E1`/`E2` from **implementation entropy**, not task tier, file count, or perceived importance. A high-impact task can still be `E0` after the coordinator has made it mechanical; a small task can be `E2` if the coding itself is intricate.
- Escalate `E0 -> E1 -> E2` only when observed implementation difficulty, failed attempts, or evidence shows the lower route is insufficient. Do not start at `E2` merely for safety when the task is mechanical.
- If `E2` cannot complete the approved contract, the coordinator must diagnose **why** before selecting a stronger writer: implementation difficulty may justify an exceptional stronger executor, but requirement/design/architecture ambiguity returns to coordinator reasoning/replanning instead of blind writer escalation.
- Do not route implementation through Terra by default. Terra is an exception route only when workload-specific evidence or runtime availability demonstrates a concrete advantage.

If the runtime does not expose the effective child model/effort, do not claim a specific route was used. If it explicitly reports an executor model/effort different from the selected task route, report the mismatch; do not silently claim the configured route executed.

## 3. Personal-project security and tool policy

This personal variant is **fail-closed** for repository configuration and environment data. The coordinator and every reasoning/implementation/audit subagent inherit this boundary.

### Protected configuration boundary — content access forbidden

Do **not** read, open, `cat`, print, parse, summarize, search within, grep through, diff the contents of, copy, upload, transmit, or ask another agent/tool/service to retrieve the contents of any repository configuration/environment file. Do not bypass this rule through generated summaries, search indexes, cached tool output, Git history, or indirect commands.

Classify by purpose, not only extension. Protected files include any repository file whose primary purpose is environment, secrets/credentials, application/runtime settings, dependency/package configuration, build/test/toolchain configuration, CI/CD, container/orchestration/deployment, infrastructure-as-code, proxy/server configuration, IDE/workspace settings, or equivalent operational configuration. Examples include `.env*`, secret/credential files, `package.json` and dependency lockfiles, build manifests, `pyproject.toml`/dependency manifests, `application*.yml|yaml|properties`, `config.*`/`settings.*`, `vite|vitest|webpack|jest|eslint|prettier|tsconfig` configuration, CI workflow files, Docker/Compose files, Kubernetes/Helm/Terraform files, and server/proxy configuration. If classification is ambiguous, treat the file as protected until the user explicitly says otherwise.

Allowed metadata is limited to what is necessary to avoid accidental access: protected file/path name, existence/non-existence, and name-only Git status/change metadata. Do not inspect file contents to decide whether the file is protected. Broad recursive content searches from repository root are forbidden unless they explicitly exclude all protected configuration paths; prefer explicit source/test/doc allowlists.

For Git inspection, first use `git status --short` and/or `git diff --name-only`. If protected paths appear, never run a content diff for those paths. Content diffs may be run only against explicitly selected non-protected source/test/doc paths.

Repository-native build/test/runtime commands may consume protected configuration **only as opaque input** when that is normal tool behavior and the agent does not inspect, echo, derive, or request the protected values. If a command fails and diagnosis would require configuration contents or values, stop that diagnostic branch and ask the user immediately for the minimum non-sensitive fact needed. If tool output unexpectedly exposes protected configuration content or secrets, do not quote, summarize, propagate, or use that content; stop the affected path and ask the user for safe guidance.

### Configuration/environment writes are user-owned

Agents must not create, modify, delete, rename, reformat, regenerate, or chmod protected configuration/environment files. This includes “small” edits, dependency-manifest changes, test/build config changes, CI/CD edits, `.env` additions, container/deployment settings, and configuration remediation discovered during audit.

If implementation requires a configuration/environment setting:
1. do not inspect the target file contents;
2. if the required target file/path, section/location, or non-secret setting semantics are not already known from direct user instruction or safe path metadata, **ask the user immediately**;
3. never ask the user to paste an entire configuration file, secret, token, password, certificate, or credential; request only the minimum non-sensitive fact, or ask the user to verify a condition and answer with a non-secret/boolean result;
4. implement only the approved non-configuration code surface;
5. report the required configuration action in the task completion output using exact non-secret content and placeholders such as `<SET_BY_USER>` for sensitive values.

Each required configuration/environment action must state: target file/path (existing or new), insertion location/section/key, exact content to add or change using secret placeholders, applicable environment/scope, why it is required, and the minimum validation/restart step. If applying the external configuration is required before the approved behavior can be verified, return `BLOCKED` for that verification until the user applies it; otherwise the code task may complete only when the contract explicitly treats configuration as a user-owned external action and the pending action is reported prominently.

### External-service and data handling

Except for RTK/Headroom explicitly configured for this personal variant, do not use other external plugins, MCP servers, third-party services, external AI services, remote paste/upload services, or repository integrations unless the user explicitly authorizes the specific service.

Do not transmit source code, diffs, logs, configuration, credentials, secrets, business/customer data, internal documentation, or repository-derived content to an external service without authorization.

Local shell commands, repository-provided tooling, and explicitly approved local/project infrastructure may be used within their existing permissions subject to the protected-configuration boundary above. If approval or classification is uncertain, STOP and ask the user.


### Transient-aware Windows-integrated SQL verification constraint

Treat SSPI/client-credential failures inside Codex as **potentially transient** until persistence is demonstrated. A single failed Integrated Authentication attempt must not create a sticky repository/environment constraint.

Use the following state model for `WINDOWS_INTEGRATED_AUTH_CONTEXT`:

```text
UNCONFIRMED
  -> ACTIVE only after interactive Windows auth succeeds AND one focused Codex retry/equivalent probe still fails
ACTIVE
  -> CLEARED immediately when an equivalent Codex/runtime Integrated Authentication command later succeeds
CLEARED
  -> normal local SQL verification resumes; prior external-verification requirements for the same auth issue are obsolete
```

Rules:
- On the **first** Codex/runtime SSPI/client-credential/integrated-auth-context failure, classify the affected check as a provisional environment failure and perform at most **one focused retry or equivalent trusted-auth probe** when safe. Do not inspect protected configuration, connection strings, credentials, SPNs, environment files, or secrets to diagnose it.
- Activate `WINDOWS_INTEGRATED_AUTH_CONTEXT` only when both are established: (1) the user has confirmed an equivalent `sqlcmd -E`/trusted-auth check succeeds from normal interactive Windows PowerShell against the intended SQL Server/database; and (2) the focused Codex retry/equivalent probe still fails with the same auth-context class before SQL verification executes.
- While `ACTIVE`, do not repeatedly retry the same failing auth path merely for reassurance. Continue unaffected build/static/source/unit verification and use `BLOCKED_EXTERNAL_VERIFICATION / WINDOWS_INTEGRATED_AUTH_CONTEXT` only for the SQL evidence that remains unavailable locally.
- While `ACTIVE`, emit one exact secret-free external verification command for the user and accept user-returned exit/status + concise non-secret output as evidence when it proves the planned contract.
- **Self-heal immediately:** if any later equivalent Integrated Authentication command succeeds inside Codex/runtime, set the constraint state to `CLEARED`, discard any pending external-verification requirement that existed only because of this auth constraint, and resume normal local SQL verification. Do not keep preferring external verification because of an older SSPI incident.
- After `CLEARED`, a future SSPI failure starts again as `UNCONFIRMED`; do not reactivate from historical evidence alone. Re-establish persistence with the same activation criteria.
- If the interactive user-run command itself later fails with SSPI/authentication, stop treating the issue as Codex-only and ask the user to resolve the Windows/SQL environment.

User-provided external verification evidence is evidence, not permission to read protected configuration or secrets.
### RTK / Headroom context routing
This personal variant uses **RTK-first / Headroom-first context routing** when those tools are available. They are the preferred/default optimization path for eligible output, not optional conveniences. Before the first repository inspection, verification, or external-tool operation in a context that can produce shell output or large non-shell output, read `docs/agents/framework/profiles/CONTEXT_OPTIMIZATION.md` once and follow it.

Default routing:
- supported shell command whose output is not trivially small -> **RTK first**;
- large non-shell/MCP/plugin/tool/data output -> **Headroom first**;
- exact-evidence, interactive, unsupported, unavailable, or optimizer-obscured cases -> narrow raw/direct fallback according to the profile.

Do not bypass an eligible optimizer merely out of habit or convenience. When an eligible operation is intentionally run raw/direct, there must be a concrete correctness, compatibility, evidence, or availability reason. Do not add a second optimization layer to already-effective RTK output.

RTK and Headroom optimize context; they do not override correctness, planning, approval, Git, verification, privacy, or evidence rules. The coordinator and every reasoning/implementation subagent inherit the same RTK/Headroom priority. If either tool is unavailable, continue with the narrowest safe raw/local alternative rather than blocking solely because the optimizer is missing.

Other external plugins, MCP servers, remote services, or uploads remain unauthorized unless the user explicitly permits them. RTK/Headroom remain subject to the protected-configuration boundary above. Never send credentials, secrets, cryptographic material, protected configuration content, or sensitive personal data to an external optimization service.

## 4. Progressive loading and token discipline

Correctness and fidelity come first; after that, minimize context and repeated reasoning.

- Do not read every framework/template file by default.
- In this personal variant, load `docs/agents/framework/profiles/CONTEXT_OPTIMIZATION.md` before the first repository inspection/verification flow that may use shell commands or large non-shell tool output; do not wait until output has already flooded context. Re-read it only if context was lost or the file changed.
- For planning, read `docs/agents/framework/PLANNING_RULES.md` once for the current planning cycle, then load only the template required by the selected planning tier/artifact.
- After execution authorization, read `docs/agents/framework/EXECUTION_AUDIT_RULES.md` before the first delegated implementation/audit cycle. Re-read it only if context was lost or the file changed.
- Inspect the narrowest repository surface that can answer the question: targeted files/symbols/tests before broad scans.
- Do not re-read unchanged large files merely to restate known facts.
- Canonical artifacts own their information. Later artifacts should reference stable IDs/paths instead of duplicating long requirement text.
- Executor prompts should include the bounded task contract and only the repository context needed to execute it. Do not attach the full specification/plan unless the task cannot be executed safely without them.
- Batch related clarification questions into one concise request when practical.
- Prefer the smallest **independently auditable unit**, not the smallest possible code edit. Keep tightly coupled changes that share one contract and one verification path in one task when that reduces handoffs without increasing ambiguity.

### Canonical repository-relative paths

Resolve canonical OptCodex paths from the **active repository/component root**, not from the shell's incidental current working directory. For this contract, `<repo-root>` is the root that owns the governing OptCodex `AGENTS.md` for the target being planned/executed. If the user explicitly targets a repository/component root, honor that target; otherwise resolve the governing `AGENTS.md` location before using relative paths.

```text
AGENTS_FILE    = <repo-root>/AGENTS.md
FRAMEWORK_DIR  = <repo-root>/docs/agents/framework
TEMPLATE_DIR   = <repo-root>/docs/agents/templates
PROFILE_DIR    = <repo-root>/docs/agents/framework/profiles
SPEC_DIR       = <repo-root>/docs/agents/specs
PLAN_DIR       = <repo-root>/docs/agents/plans
DECISION_DIR   = <repo-root>/docs/agents/decisions
VALIDATION_DIR = <repo-root>/docs/agents/validation
TASK_DIR       = <repo-root>/tasks
```

`templates/` is a sibling of `framework/`; never infer `docs/agents/framework/templates/`. Before reporting a canonical file as missing, first resolve `<repo-root>` and verify the exact canonical path from that root. If the shell is currently inside another component/worktree, either change directory to `<repo-root>` or use absolute paths rooted there. Never mix an absolute path from one repository/component with relative paths resolved from another current working directory. A path-resolution mistake is not evidence that the repository artifact is absent.

## 5. Mandatory clarification gate

During requirements analysis, specification writing, and planning, inspect authoritative **non-protected** repository evidence first. Protected repository configuration/environment files are never an inspectable evidence source. If required information may exist only in protected configuration/environment data, or if any implementation-relevant requirement, business rule, field meaning, permission rule, interface contract, edge case, dependency, acceptance criterion, rollout constraint, or materially different interpretation remains unclear, missing, contradictory, or ambiguous, STOP that branch and ask the user immediately for the minimum non-sensitive fact needed.

Do not guess, silently assume, choose a default merely to avoid asking, invent product semantics, infer protected configuration values, or defer the decision to the executor. Never ask the user to paste an entire configuration file or secret. Planning may resume only after the user answers or explicitly authorizes a stated assumption. Record material decisions/authorized assumptions according to `PLANNING_RULES.md`.

## 6. Mandatory planning and approval gate

Before modifying product code, tests, migrations, generated application artifacts, dependencies implemented outside protected manifests, or any other permitted repository file that affects behavior:
1. inspect relevant repository context;
2. resolve material clarification questions;
3. create/update the required planning artifacts;
4. create a new task checklist under `tasks/`;
5. present the current plan/checklist to the user;
6. receive explicit execution authorization **after** the current plan is presented.

Initial modification requests are planning-only even when phrased as “fix”, “implement”, or “do it now”. Planning-only phrases include `tạo tasks`, `create tasks`, `create a plan`, and `plan this change`. Execution phrases such as `thực hiện tasks`, `tiến hành code`, `làm task`, `execute tasks`, `implement the plan`, or `proceed with coding` authorize execution only when they clearly refer to the currently presented plan/checklist.

If the user materially changes requirements after approval, stop affected work, revise the affected artifacts, present the revised scope, and obtain fresh execution authorization.

Before authorization, non-protected repository inspection, protected-path name/existence checks, name-only/read-only Git, non-destructive diagnostics that do not expose protected configuration, existing tests, and planning-document creation/update are allowed. Protected configuration/environment contents remain unreadable at all times, and protected configuration/environment files remain non-writable even after execution authorization. Do not modify implementation/test/dependency/migration behavior before authorization.

## 7. Planning tier and artifact routing

Select the smallest tier that preserves correctness. Exact rules are in `docs/agents/framework/PLANNING_RULES.md`.

- **S — small/local:** compact plan + compact task; no separate design spec unless semantics are non-obvious.
- **M — normal feature/bug:** specification + plan + tasks; decision ledger only when material clarification/decision exists.
- **L — architecture/data/security/migration/performance/cross-cutting:** full specification + plan + tasks + decision ledger when applicable; full traceability and rollout/rollback evidence.

Use only the templates needed for the selected tier. Do not create empty artifacts for completeness.

## 8. Execution loop

Maintain an explicit dependency DAG for implementation/remediation work. Execute by **waves**: dispatch the smallest useful set of independently ready tasks in parallel when doing so shortens the critical path without creating coordination risk; otherwise keep the affected work serial.

A writer task is parallel-safe only when all are true:
- every predecessor it depends on is already `PASS`;
- its write surface does not overlap another in-flight writer's surface;
- it does not depend on another in-flight task's unfinished output or assumptions;
- it cannot materially invalidate another in-flight task's RED/GREEN evidence or verification basis;
- shared mutable artifacts/state (generated files, schema state, lock files, caches, ports, test fixtures, runtime services) will not collide;
- the runtime/shared-worktree semantics are known to be safe for the exact concurrent operations. If isolation/safety is uncertain, serialize writers.

For each execution wave:
1. coordinator confirms Definition of Ready for every task in the wave and records dependency/write-surface boundaries;
2. dispatch one bounded executor per ready task, using only the concurrency that materially improves the critical path;
3. WAIT for each in-flight executor that gates further work; never duplicate an already running/unknown writer task;
4. audit each terminal result against repository ground truth, not only the executor summary;
5. return exactly `PASS`, `REWORK`, or `BLOCKED` per task;
6. on `REWORK`, issue a bounded remediation contract for only the affected task/finding; unaffected parallel results remain valid unless the remediation invalidates them;
7. open the next wave only when each task's required predecessors have reached `PASS`.

Parallelism is primarily a wall-clock optimization, not a free token/cost reduction. Prefer the fewest concurrent executors that materially reduce critical-path latency. The coordinator must not silently patch executor failures merely because a fix seems small.

## 9. RED then GREEN

Every implementation/remediation task must define and execute:
1. a meaningful **RED** negative/boundary/failure scenario;
2. the primary **GREEN** intended-success scenario.

RED must be executed and observed before GREEN. Expected results must be derived independently from the implementation output. After a formal checkpoint, later changes invalidate only evidence they can materially affect. Re-run only invalidated evidence; restart the complete RED→GREEN pair only when both scenarios or their shared verification basis may have changed. Exact invalidation rules are in `EXECUTION_AUDIT_RULES.md`.

A generic passing suite is insufficient unless it proves the required RED and GREEN flows and their order. If no automated harness exists, use the strongest reproducible alternative available locally (focused command, harness, simulation, dry run, validator, compile-time check, or documented manual reproduction).

## 10. Git safety

Read-only Git operations are allowed when needed (`git status`, `git diff`, `git log`, `git show`, `git branch`).

Do not `git add`, commit, push, tag, merge, rebase, cherry-pick, reset, clean, restore, force-push, or otherwise alter history/worktree state unless the user explicitly authorizes the specific action. Authorization to implement does not imply authorization to commit or push. Do not discard user/other-agent changes.

## 11. Completion

Do not claim completion until:
- every required implementation/remediation task is `PASS`;
- required RED then GREEN evidence exists;
- relevant tests/type checks/linters/builds/validation have been observed;
- final diff/status has no unexplained changes;
- the implementation matches the approved requirements and scope;
- final cross-task integration audit passes;
- every required external configuration/environment action is reported with target file/path, insertion location/section/key, exact non-secret content or secret placeholder, scope, reason, and validation/restart step;
- no protected configuration/environment file content was read and no protected configuration/environment file was modified by any agent.

Report unverified behavior, skipped checks, environment limitations, routing mismatches, protected-configuration blockers, pending external configuration actions, and unresolved risks explicitly. Completion never implies commit/push authorization.
