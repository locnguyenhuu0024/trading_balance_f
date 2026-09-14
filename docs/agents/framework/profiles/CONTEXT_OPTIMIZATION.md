# Context Optimization Profile — RTK + Headroom

> Personal-project profile. RTK and Headroom are preferred/default context-routing layers when available. Load before the first repository inspection/verification flow that may produce shell output or large non-shell tool/data output. Applies equally to coordinator and all subagents.


## 0. Protected configuration boundary overrides optimization

The repository protected-configuration/environment boundary in `AGENTS.md` has higher priority than RTK/Headroom optimization. Optimization tools are **not** an alternate route to protected content.

- RTK must not `read`, `grep`, `find`-content, diff-content, parse, or otherwise expose protected configuration/environment files. Broad repository searches must use explicit non-protected source/test/doc allowlists or exclusions before execution.
- Headroom must not compress, summarize, ingest, cache, or retrieve protected configuration/environment contents, connection strings, credentials, secrets, tokens, certificates, or environment dumps.
- Do not send protected configuration or secret-bearing output to Headroom or any other optimizer. If a command unexpectedly emits protected content, stop the affected path; do not compress/retrieve/propagate it.
- Protected path/name/existence and name-only Git status metadata may be used only as permitted by `AGENTS.md`.
- Repository-native build/test/runtime tools may consume protected config as opaque input, but RTK/Headroom may only process their output when that output does not expose protected values. If diagnosis would require the hidden config value, ask the user for the minimum non-sensitive fact instead.
- Security beats token savings: when an optimized command cannot guarantee protected-path exclusion, use a narrower safe command or ask the user rather than running it.

## 1. Optimization precedence and responsibility split

For eligible output, optimize **before** allowing large/noisy data into the reasoning context. Use exactly one primary optimization layer for a given output stream:

- **RTK first** for supported shell-command output unless the output is trivially small or an exact/raw exception applies.
- **Headroom MCP first** for large non-shell tool output or large data not already effectively filtered by RTK.

Raw shell/direct large-output ingestion is a fallback, not a co-equal default. An eligible optimizer may be bypassed only for a concrete correctness, compatibility, exact-evidence, interactivity, security, or availability reason.

Do not stack Headroom on RTK-filtered output merely to improve compression statistics. Correctness and exact evidence take precedence over compression.

## 2. RTK — token-optimized shell commands

Default to RTK for supported shell commands when output is not already known to be trivially small, especially repository inspection, file search/listing, Git inspection, tests, builds, lint/type checks, package-manager output, logs, structured data, infrastructure commands, and GitHub CLI output. Prefer an RTK form before an equivalent raw command. RTK is an optimization layer, not a correctness guarantee.

### Executable discovery

1. Prefer `rtk` when available on PATH.
2. On Windows, if PATH resolution fails and the installation is known to exist, try `D:/CodexData/rtk/bin/rtk.exe`.
3. If RTK is unavailable, use the narrowest raw command. Do not block the task solely because RTK is missing.

### Common forms

```bash
rtk git status
rtk git diff
rtk git log
rtk git show
rtk ls <path>
rtk read <file>
rtk grep <pattern>
rtk find <pattern>
rtk diff <file>
rtk pytest <scope>
rtk cargo test
rtk test <command>
rtk tsc
rtk lint
rtk cargo build
rtk prettier --check
rtk mypy
rtk ruff check
rtk err <command>
rtk log <file>
rtk json <file>
rtk summary <command>
rtk deps
rtk env
rtk gh pr view <number>
rtk gh run list
rtk gh issue list
rtk docker ps
rtk docker logs <container>
rtk kubectl get <resource>
rtk pip list
rtk pnpm install
rtk npm run <script>
```

These are examples, not permission to broaden task scope. Use repository-native commands and the execution rules for the active project.

### Raw-output fallback

Use raw output instead of RTK when:
- exact or complete output is material to correctness;
- the command is interactive;
- binary or machine-readable output must remain unchanged;
- RTK may have hidden information needed for diagnosis;
- debugging a failure potentially caused or obscured by RTK;
- validating an exact stack trace, source file, diff, migration, lock file, security-sensitive result, or byte-sensitive artifact.

If an RTK-filtered command reports failure without enough evidence, rerun the **narrowest relevant raw command**, not the whole workflow. Use `rtk proxy <command>` when unfiltered execution is needed but RTK tracking is still useful. Do not compress already concise output.

## 3. Headroom MCP — large non-shell context

Headroom is the preferred/default context-management path for **large non-shell content** that did not originate as effectively RTK-filtered shell output. Use `headroom_compress` before injecting such content directly into the reasoning context when it is likely to save meaningful context, including:
- large JSON responses;
- long logs returned by non-shell tools;
- large database/query results;
- long issue/ticket histories;
- extensive MCP/plugin/tool output;
- generated reports/documents;
- repetitive structured data;
- content roughly larger than **200 lines or 20 KB** that must remain available for later retrieval.

The threshold is guidance, not a hard limit. Compress only when it is likely to save meaningful context.

### Do not compress

Do not use Headroom compression for:
- ordinary source files;
- small diffs;
- short command/tool output;
- output already effectively filtered by RTK;
- exact stack traces currently under diagnosis;
- migration scripts;
- lock files;
- security-sensitive findings requiring exact evidence;
- cryptographic material, credentials, or secrets;
- content where exact formatting, line numbers, signatures, values, or byte-level accuracy is material.

Do not recompress content merely to increase compression statistics.

### Retrieval and correctness

Before making a decision that depends on detail omitted by compression, use `headroom_retrieve` to recover the relevant original content. Never modify code based solely on a compressed representation when exact names, values, line numbers, signatures, error messages, or control flow are material. If compression creates ambiguity, retrieve first.

Use `headroom_stats` only after substantial work where compression was actually used, when the user asks for statistics, or when evaluating whether the integration provides value. Do not call it after every command or response.

## 4. Coordinator and subagent contract

The same priority applies to every agent:
- coordinator/planner/auditor must route eligible shell work through RTK first;
- reasoning subagents must use RTK first for eligible repository/search/review shell commands and Headroom first for eligible large non-shell results;
- implementation/remediation executors must use RTK first for eligible noisy shell verification/inspection while keeping exact-evidence fallbacks available;
- every agent must rerun the narrowest raw command when RTK-filtered evidence is insufficient;
- every agent must retrieve exact Headroom content before a decision that depends on compressed-away details;
- subagent prompts should preserve this RTK-first/Headroom-first priority when the child runtime may not automatically inherit repository-local instructions;
- neither optimizer may be used to hide failures, weaken verification, bypass scope, or justify claims not supported by observed evidence.

Do not attach large optimizer outputs to subagents when a bounded task contract plus concise evidence is sufficient.

## 5. Verification interaction

Verification escalation, diagnostic checkpoints, environment short-circuiting, and evidence reuse remain governed by `../EXECUTION_AUDIT_RULES.md`.

For tests/builds expected to be noisy:
1. run the narrowest verification level;
2. use RTK on the first pass by default when it preserves the evidence needed;
3. if failure detail is insufficient, rerun only the failing/narrowest raw command;
4. record concise command + result in executor/audit reports;
5. never claim PASS from a compressed summary unless the required scenario/result is actually established.

## 6. Optimization anti-patterns

Do not:
- force RTK onto unsupported, interactive, exact-byte, security-sensitive, or already-trivial commands merely to satisfy a metric;
- compress small non-shell results that are already concise;
- run both RTK and Headroom on the same already-filtered output;
- broaden commands to generate more data before compressing it;
- repeat optimizer statistics during active work;
- trade exact evidence for token savings when correctness depends on the exact data.

The priority is **optimizer-first when eligible, raw/direct only when justified**. Goal: minimize **context entering the reasoning model** while preserving exact evidence, not maximize optimizer call counts.
