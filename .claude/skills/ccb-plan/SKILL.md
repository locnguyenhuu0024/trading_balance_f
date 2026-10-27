---
name: ccb-plan
description: Plan within the selected pinned OptCodex variant and prepare bounded Claude-to-Codex implementation jobs.
disable-model-invocation: true
argument-hint: "[feature request]"
---

# OptCodex-compatible CCB planning

1. Verify variant version and read its pinned `AGENTS.md` → `BASELINE_AGENTS_*.md`. If no variant is installed or lock drifts, STOP.
2. Confirm installed project domain by the single `ccb-domain-*.md` rule. For web load upstream frontend F0–F3; for mobile use platform-native domain rules and **do not** assume web tooling; for backend follow API/data/concurrency domain rules. `model-routing.json` is advisory; it does not authorize changing OptCodex E0/E1/E2. Follow `PLANNING_RULES.md`: choose S/M/L and C/R/E classification by actual work, inspect only allowed non-protected context, resolve ambiguities before canonical SPEC/PLAN/TASK.
3. Classify material planning workstreams. For each suitable, explicitly share-authorized Backend/Frontend/Mobile workstream, curate a minimal non-protected Sol planning packet at `.ccb/sol-planning/packets/<work-id>.json`; preview and run `scripts/ccb/sol_plan.py` for GPT-6.1 Sol Medium proposals after authorization (or invoke the auto-invocable `/ccb-sol-plan` skill). Material backend+frontend requires **separate** planning workstreams; collect proposals independently and reconcile their assumptions, contracts and conflicts. Claude—not Sol—writes the canonical SPEC/PLAN/TASK. Preserve all OptCodex clarification, approval, buildability and protected-config rules. If Sol is blocked, disclose and seek user-authorized alternative; do not invent results or claim completed fan-out. Material frontend + material backend mandates at least two distinct reasoning workstreams unless a documented permitted exception/unavailability applies. Record the actual fan-out status/evidence.
4. On frontend variants, apply `FRONTEND_DESIGN_RULES.md` and F0–F3. All variants apply `PONYTAIL_RULES.md` for minimal complete change. Personal variants preserve RTK/Headroom; company variants record QA impact.
5. For each newly finalized canonical TASK, record a task event once using `python3 scripts/ccb/task_ledger.py plan --project <planning-root> --plan-id <plan_id> --task-id <task_id> --domain <backend|web|mobile>`. This log must be durable outside Git. A retry/rework does not create a new task ID unless it is genuinely a distinct task contract. Record a separately approved `terra_trial` only for E1 Terra/high or E2 Terra/xhigh, never E0, and only if user specifically authorized this model/experiment for this task. Tasks must match OptCodex `TASK_TEMPLATE.md`: explicit Agent Role, E0/E1/E2, Target Model, Target Effort, predecessors, Allowed Write Surfaces, RED/GREEN, Task Buildability Gate and verification ceiling.
6. Present plan and checklist. Do not code. Wait for explicit approval of this version of the plan before dispatch; Git worktree operations require separate approval.
7. After authorization, prepare `CCB_JOB_TEMPLATE.json`-shaped manifest with exact variant/version/revision, E-route binding and truthfully recorded planning fan-out.

Request: $ARGUMENTS
