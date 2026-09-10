# Context Optimization Profile — RTK + Headroom

> Personal-project profile. Load only when shell output or large non-shell tool/data output is likely to consume meaningful context. Applies equally to coordinator and subagents.

## 1. Responsibility split

Use exactly one primary optimization layer for a given output stream:

- **RTK** for shell-command output.
- **Headroom MCP** for large non-shell tool output or large data not already effectively filtered by RTK.

Do not stack Headroom on RTK-filtered output merely to improve compression statistics. Correctness and exact evidence take precedence over compression.

## 2. RTK — token-optimized shell commands

Use RTK primarily when a supported shell command is expected to produce large or repetitive output, including repository inspection, file search/listing, Git inspection, tests, builds, lint/type checks, package-manager output, logs, structured data, infrastructure commands, and GitHub CLI output. RTK is an optimization layer, not a correctness guarantee.

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

Headroom is optional context management for content that did not originate as RTK-filtered shell output. Consider `headroom_compress` for:
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

The same policy applies to every agent:
- coordinator should prefer RTK for noisy shell inspection and verification;
- executor should use RTK only when its bounded command output is large enough to benefit;
- executor must rerun the narrowest raw command if filtered evidence is insufficient;
- coordinator must retrieve exact Headroom content before an audit decision that depends on compressed-away details;
- neither optimizer may be used to hide failures, weaken verification, bypass scope, or justify claims not supported by observed evidence.

Do not attach large optimizer outputs to subagents when a bounded task contract plus concise evidence is sufficient.

## 5. Verification interaction

Verification escalation, diagnostic checkpoints, environment short-circuiting, and evidence reuse remain governed by `../EXECUTION_AUDIT_RULES.md`.

For tests/builds expected to be noisy:
1. run the narrowest verification level;
2. use RTK on the first pass when it preserves the evidence needed;
3. if failure detail is insufficient, rerun only the failing/narrowest raw command;
4. record concise command + result in executor/audit reports;
5. never claim PASS from a compressed summary unless the required scenario/result is actually established.

## 6. Optimization anti-patterns

Do not:
- prefix every shell command with RTK mechanically;
- compress every non-shell result;
- run both RTK and Headroom on the same already-filtered output;
- broaden commands to generate more data before compressing it;
- repeat optimizer statistics during active work;
- trade exact evidence for token savings when correctness depends on the exact data.

Goal: minimize **context entering the reasoning model**, not maximize optimizer usage.
