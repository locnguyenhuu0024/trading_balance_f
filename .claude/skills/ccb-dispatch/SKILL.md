---
name: ccb-dispatch
description: Send one approved OptCodex task to Codex CLI with strict E-route and compatibility guards.
disable-model-invocation: true
argument-hint: "[path/to/ccb-job.json]"
---

# OptCodex-compatible CCB dispatch

1. Verify the job is a canonical `jobs/T01.json` (or `docs/agents/ccb/jobs/T01.json`) manifest **inside** the selected plan root. Independently verify **conversation-level authorization** for the currently presented and unchanged SPEC/PLAN/TASK. A matching CLI `approved-plan-id` is not authorization by itself.
2. Verify required planning workstream fan-out and reconciled workstream results (or an explicitly allowed and recorded `UNAVAILABLE`/exception), all predecessor tasks PASS, no in-flight writer, safe allowed write surfaces, testable RED/GREEN, and Task Buildability criteria.
3. Confirm exact OptCodexRules variant/version and pinned governance files. Require Luna default E0/high, E1/xhigh, E2/max. Only a specifically approved Terra trial may use E1 Terra/high or E2 Terra/xhigh, with `terra_trial` manifest object and exact `--approved-experiment-id <id>`. Independently verify explicit user authorization; the JSON flag alone cannot establish consent. No null/inherited/fallback route.
4. Read `EXECUTION_AUDIT_RULES.md` and variant rules for this execution cycle; pass only the bounded task contract and necessary non-protected context to Codex.
5. From a **clean** checkout containing the full selected variant:
   `python3 scripts/ccb/dispatch.py --manifest <job> --repo <worker-root> --plan-root <plan-root> --execute --approved-plan-id <current-plan-id>`
   Run without `--execute` first for safe preflight. If and only if a Terra trial is individually approved, also supply `--approved-experiment-id <id>` for the execution command. Codex execution records `ATTEMPT_STARTED` and `ATTEMPT_FINISHED` automatically in the task ledger outside Git. On Windows use `py -3`.
6. Do not pass `--yolo`, `danger-full-access` or untrusted override flags. Never create worktrees, commit, stage, reset or merge without separate specific Git authorization.
7. On REVIEW_REQUIRED, invoke `/ccb-audit`; on BLOCKED preserve all changes. If model/effort or effective route mismatch becomes observable, record ROUTE_MISMATCH and stop.

Job: $ARGUMENTS
