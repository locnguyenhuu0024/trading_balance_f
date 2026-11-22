# Adaptive Context Discipline — long-task and compaction rules

> Phase-loaded supplement to immutable baseline, planning and execution/audit. Load only for substantive long-task, noisy-context, compact/resume work. Never weaken protected-config, current-plan approval, E0–E5 binding, RED/GREEN, audit, buildability, final build or QA. This file installs no hooks or settings.

## 1. Evidence-first context

Coordinator owns canonical SPEC/PLAN/TASK. Executor return `REVIEW_REQUIRED`, its claimed PASS and any compaction summary are **not independent audit PASS**. A summary, transcript and auto memory are not authority for approval, tests or routing. Load baseline and phase rules as directed, then only relevant source ranges, contracts and evidence; avoid loading complete repos, histories, raw tool logs, many skills or all SPEC/PLAN documents. Reference precise file/symbol and test/command results. Never read, summarize, search within or otherwise expose protected configuration or secrets.

## 2. Anti-drift frame for long TASKs

Maintain this minimal frame at material milestones in existing TASK/PLAN/ledger or a concise status; **do not create a new file every turn**:
- **TARGET:** approved PLAN/TASK IDs, current acceptance criteria.
- **BOUNDARY:** allowed write surfaces, protected paths, dependencies, exact model/effort and approval.
- **EVIDENCE:** proven file/symbol, failing/passing tests, distinguish fact vs hypothesis.
- **NEXT:** one action, expected evidence and stop condition.
- **OPEN:** only unresolved blockers/decisions, with owner.

Use path-restricted searches and bounded file slices before broadening. Prefer smallest relevant caller/test/contract; delegate verbose independent research to a bounded read-only subagent when permitted, returning referenced findings rather than raw logs. A delegated investigation is not automatically evidence of mandatory multi-workstream planning fan-out. No speculative architecture or unrelated fixes. If two consecutive attempts at the same hypothesis produce **no new evidence**, stop that approach, summarize facts and one alternative, then escalate true scope/architecture ambiguity to coordinator. Never expand write permissions or E-route to hide a blocker. Progress updates = completed evidence, current blocker, next step; do not repeatedly narrate full PLAN.

## 3. Adaptive compact policy

Keep Claude Code **auto-compact enabled** as fallback. Do NOT compact after every TASK, use a fixed compact schedule, disable/deny emergency auto-compact or install PreCompact/PostCompact hooks by default. Inspect `/context` at meaningful phase boundaries or when context seems noisy, not each turn. These **heuristic** ranges are NOT proven universal thresholds or programmatic gates:

| Reported occupancy | Advisory action at safe boundary |
| --- | --- |
| below ~40% | KEEP; avoid unnecessary summary overhead |
| ~40–70% | CONSIDER focused compact only if stale logs dominate and next task differs materially |
| ~70–85% | PREFER focused compact after safe checkpoint if old detail has low reuse |
| above ~85% / nearing limit | CHECKPOINT promptly, compact if available or allow native auto-compact and verify recovery |

A strong trigger is **audited boundary + accumulated stale context + low anticipated reuse**, not context percentage alone. For unrelated new work, propose `/clear` only after preserving state and when authorized; never abandon running tasks to clear. `/context`, `/compact <instructions>` and `/clear` are Claude Code UI commands: only recommend them or invoke through an actual supported runtime interface, never shell-emulate or claim to have triggered compaction without observation.

A safe completed-task boundary requires collected terminal result, **independent audit PASS**, required RED/GREEN and buildability evidence, reconciled canonical task ledger/PLAN and known dependencies. `REVIEW_REQUIRED`, executor self-report, provisional GREEN and an active/UNKNOWN writer are **not** audited completion. If auto-compact nears mid-TASK, checkpoint verified progress and executor handles without marking PASS; do not block native compaction or duplicate writer dispatch.

## 4. Pre-compact checkpoint and focus

Before an intentional compact, reconcile to existing durable artifacts (no redundant files):
1. SPEC/PLAN revision and approval of the **currently presented** plan; immutable decisions, contracts and unresolved questions.
2. TASK ID/status, predecessor wave, E-route/effort, approval, permitted surfaces and protected exclusions.
3. Changed paths and exact references to RED/GREEN, test/build, audit evidence; keep unresolved failures, not raw megabytes of logs.
4. RUNNING/UNKNOWN executor handles, correct native wait/collect identifier; never respawn an active task after context loss.
5. Next bounded action, verification target, stop condition and user-owned external configuration work.

Suggested `/compact` focus text:

```text
Preserve canonical SPEC/PLAN/TASK IDs/revisions; observed current-plan approval; architecture/API/data invariants; exact E0-E5 routes and approved scope; active executor handles, dependencies and task states; protected boundaries; modified paths and RED/GREEN/test/build/audit evidence refs; unresolved blockers and next bounded action. Distinguish facts from hypotheses, REVIEW_REQUIRED from audited PASS. Drop obsolete logs, repeated prose and failed speculative branches. Never infer approval or completion.
```

Compaction is lossy and never authorizes implementation, protected-file access or a PASS verdict.

## 5. Post-compact/resume recovery

After **manual OR automatic** compact or a new session, reestablish baseline/phase requirements from authoritative files. When relevant reread matching source files to activate path-scoped rules and nested CLAUDE.md, which may not be re-injected automatically. Reload personal RTK/Headroom, company QA or frontend F0–F3 only when applicable. Verify current SPEC/PLAN/TASK revision, plan approval, E-route, status/ledger, outstanding decisions, changed repo state, actual running handles and needed test/build evidence. If a summary conflicts, stop new dispatch/audit PASS; record `CONTEXT_RECOVERY_CONFLICT` and recover from canonical artifacts/runtime. UNKNOWN remains UNKNOWN. Never infer effective model/effort from remembered selection. Re-run only the narrowest missing verification.

## 6. Measurement and safety

Prompt caching lowers the price of repeated history; compaction itself adds summary/recovery work. Never claim universal cost/quota savings. Observe context, compact count (manual/auto), cached/input/output tokens if exposed, recovery turns, duration, REWORK, drift/scope incidents and verification quality; unknown values remain null. For A/B evaluation compare matched TASKs on clean equivalent checkouts: auto-only vs adaptive-boundary + auto fallback. Judge end-to-end coordinator/executor quality and rework, not merely context size. Do not change user/global Claude settings, install hooks or modify Git without separate authorization.

Official references: https://code.claude.com/docs/en/best-practices ; https://code.claude.com/docs/en/context-window ; https://code.claude.com/docs/en/memory ; https://code.claude.com/docs/en/costs ; https://code.claude.com/docs/en/hooks
