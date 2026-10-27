---
name: ccb-status
description: Read-only status of CCB OptCodex task DAG, route binding, planning fan-out and verification gates.
disable-model-invocation: true
---

# Read-only CCB status

Summarize selected OptCodex variant/version/source pin, presented-plan approval, required/actual planning workstreams, S/M/L and E-route per task, exact requested model/effort, predecessors, current task states (PASS/REWORK/BLOCKED/REVIEW_REQUIRED), Codex writer state, RED/GREEN/Task Buildability evidence, final build/QA handoff obligations and next independently ready task. Expose unknown/unavailable fields as such; never imply PASS from executor output. Do not start writers or mutate files.

For quantified historical work, use `python3 scripts/ccb/task_ledger.py report --project "<planning-root>"`; distinguish unique logical tasks, executor attempts and audits. Never infer finished PASS from REVIEW_REQUIRED. Local report is supplementary to OptCodex canonical telemetry.
