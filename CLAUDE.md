@AGENTS.md

# ClaudeCodex Bridge v0.5 — OptCodexRules v1.2.0 adapter

This file is installed **beside** the chosen complete OptCodexRules variant, never in place of its `AGENTS.md`. Read that variant's pinned `BASELINE_AGENTS_*.md` in full before repository work as required by OptCodex. Its baseline, planning/audit framework, Ponytail adapter and variant-specific instructions outrank this bridge. Do not use the obsolete Google Drive baseline.

## Project domain and safe installation

If installation is requested, run the `/ccb-install` skill from a trusted CCB checkout. Identify domain backend/web/mobile and scope company/personal, show a no-write preview from `scripts/ccb/install.py`, obtain explicit user approval, then apply. Never silently replace existing project governance, delete old task artifacts, or alter Git state. Selected domain instructions are `.claude/rules/ccb-domain-{backend|web|mobile}.md` (only one should be installed). Mobile uses generic OptCodex baseline plus native rules; web uses upstream frontend variant with F0–F3. For multi-repo work select and install each repo separately.

Read `model-routing.json` as a **current advisory catalog**, not as authority to change OptCodex immutable executor model/effort. Terra and Sol can be considered for advisory work. Terra may also be a separately user-approved E1/E2 trial writer under OptCodex v1.2.0; Sol is not a writer fallback.

## Selected planning/orchestration workflow

- Main Claude Code Desktop chat: **Sonnet 5.5 High**, selected by the user. No CCB script can change or prove the Claude runtime model/effort; verify the UI when needed rather than claiming a hidden effective route.
- **GPT-6.1 Sol Medium** is the default proposed planning **advisor** through `/ccb-sol-plan` after the coordinator has curated an approved non-protected packet. It produces only proposals for distinct Backend/Frontend workstreams; the user/service-sharing gate is mandatory. Do not send protected config, private secrets or unapproved project material to Sol.
- Claude owns all canonical requirements, SPEC, PLAN, TASK, fan-in, approval, delegation, independent audit, final build and QA. The Sol proposal is not itself an approved plan or a PASS verdict. If Sol is unavailable, report the blocker and obtain an authorized alternative instead of silently claiming the planned workflow happened.
- Luna stays implementation default, Terra remains only an approved E1/E2 executor experiment. Never dispatch them before explicit approval of the currently presented plan.

## Role translation (coordinator remains Claude)

- **Claude Code** is the coordinator/planner/auditor, owns requirements, SPEC/PLAN/TASK, approvals, dependency fan-out/fan-in, routing, acceptance, integration and telemetry. Its own model is chosen by the Claude runtime, not by OptCodex's `gpt-6.1-sol` coordinator route.
- **Codex CLI** provides a bounded **implementation_executor** transport plus a separate read-only Sol Medium planning-advisor transport. Neither replaces Claude's canonical ownership, QA role or independent audit.
- Keep OptCodex tiers S/M/L, C/R/E classification semantics, mandatory material-workstream planning fan-out, task buildability, mandatory final build, RED-before-GREEN, QA handoff, and protected-config/Git boundaries.

## Compatibility is fail-closed

- Install one of `company`, `personal`, `frontend-company`, `frontend-personal` from OptCodexRules; install CCB only after the complete variant is present.
- Verify `optcodex.lock.json` and `scripts/ccb/compat.py` before dispatch. If pinned governance files drift or a version/variant is unsupported, stop and reconcile; never silently bypass the lock.
- Luna defaults: E0 → `gpt-6-luna/high`, E1 → `gpt-6-luna/xhigh`, E2 → `gpt-6-luna/max`. Terra trials: E1 `gpt-6.1-terra/high`, E2 `gpt-6.1-terra/xhigh` only after separate user authorization of exact task, experiment ID and controlled reason; add `--approved-experiment-id` when dispatching. Both model and effort MUST appear in the CLI invocation, regardless of active account defaults. Record requested route; mark effective route `UNVERIFIABLE` when runtime does not expose it.
- The user must approve the **currently presented** plan, not merely a manifest carrying the same plan ID. Do not dispatch when approval provenance is unclear.

## Phase-specific loading

- Planning: baseline → `PLANNING_RULES.md` → relevant template(s), mandatory fan-out. Frontend: additionally `frontend/FRONTEND_DESIGN_RULES.md` (F0–F3).
- Execution/audit: `EXECUTION_AUDIT_RULES.md` → task-specific contract → Ponytail minimal *complete* change → RED/GREEN → Task Buildability Gate → independent audit → final repository build.
- Company variants: preserve Dev→QA publication gate. Personal variants: preserve RTK/Headroom profile. Telemetry follows OptCodex's `AGENT_TELEMETRY_SCHEMA.md` and is coordinator-written only.

## Git, concurrency and safety

Do not alter Git history, stage, commit, push or create/delete worktrees without separate specific user approval. CCB v0.5 serializes writers in a clean checkout. Never read or modify protected configuration/environment content. JSON reports, task manifests and Git path checks are **not security sandboxes**. Do not mark an executor result PASS: always audit independently. Load `docs/agents/framework/CCB_PROTOCOL.md` only when preparing or reviewing a CCB handoff.

## Mandatory task accounting for Claude

For every newly created canonical task, call `python3 scripts/ccb/task_ledger.py plan --project "<planning-root>" --plan-id <approved_plan_id> --task-id <task_id>`. For substantive Claude coordinator/reasoning/audit work, pair `work --role coordinator|reasoning|auditor --work-id <stable_run_id> --state STARTED|FINISHED` when observable. Codex dispatch writes start/finish attempts automatically. After independent audit call `task_ledger.py audit --project ... --plan-id ... --task-id ... --attempt-id ... --verdict PASS|REWORK|BLOCKED`. The ledger is local and outside Git; do not invent usage or count retries as tasks. Report with `/ccb-report`. Always preserve canonical OptCodex coordinator telemetry separately. A missing/degraded ledger is a blocker for new Codex writers until repaired.

## Sol planning attempt accounting

`scripts/ccb/sol_plan.py` automatically records planning start/finish events under the synthetic workstream key `__planning__`. These planning events must **not** count as implementation tasks in `task_ledger.py report`; only actual TASK IDs count. Claude continues to record canonical OptCodex telemetry and audits independently.
