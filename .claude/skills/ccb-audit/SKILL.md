---
name: ccb-audit
description: Independently review a Codex CLI result under the installed OptCodex baseline and selected variant's audit gates.
argument-hint: "[job.json] [report.json]"
---

# OptCodex-compatible CCB audit

1. Claude Sonnet 5.5 High is the user-selected preferred auditor/coordinator. Verify that user selection when observable; never assert programmatic runtime proof. Sol planning proposals are advisory, not independently audited code or a substitute for verification. Read `EXECUTION_AUDIT_RULES.md` for the execution cycle. Cross-check approved requirements, task manifest, route binding and user approval. Reject unsupported effective-route claims; use UNVERIFIABLE when the runtime does not reveal it.
2. Inspect path-only Git status first, then only safe non-protected task paths and permitted callers. Executor report/exit status do not establish PASS.
3. Verify the formal RED then GREEN sequence (and repeat after implementation changes), necessary focused tests and **Task Buildability Gate** for affected canonical build units. Apply verification ceilings/evidence reuse and short-circuit documented toolchain/environment failures.
4. Apply Ponytail minimal *complete* change review. For frontend variants, independently assess F0–F3 visual/design and accessibility gates. For company variants, preserve QA handoff/publication gate and user-owned configuration actions.
5. Evaluate exact contract/AC/TEST IDs. Mark only PASS / REWORK / BLOCKED and record concise grounded evidence in the canonical task checklist. REWORK uses a bounded executor remediation task; coordinator does not silently implement.
6. Before overall completion require OptCodex final integration audit AND mandatory final repository build. Publish required company Dev→QA artifacts only under the governing QA contract.
7. After genuinely independent audit, record the audit verdict in local CCB task ledger: `python3 scripts/ccb/task_ledger.py audit --project "<planning-root>" --plan-id <plan_id> --task-id <task_id> --attempt-id <attempt_id> --verdict PASS|REWORK|BLOCKED`. Never call PASS on the basis of Codex's structured report. Terra approvals, route and experiment ID must be verified independently. Only Claude coordinator writes canonical OptCodex telemetry. Do not commit, merge, reset or change Git history without separate approval.

Inputs: $ARGUMENTS
