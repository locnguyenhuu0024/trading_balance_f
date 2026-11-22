@AGENTS.md

# ClaudeCodex Bridge v0.9 — OptCodexRules v1.5.1 adapter

This file is installed **beside** the chosen complete OptCodexRules variant, never in place of its `AGENTS.md`. Read that variant's pinned `BASELINE_AGENTS_*.md` in full before repository work as required by OptCodex. Its baseline, planning/audit framework, Ponytail adapter and variant-specific instructions outrank this bridge. Do not use the obsolete Google Drive baseline.

## Project domain and safe installation

If installation is requested, run the `/ccb-install` skill from a trusted CCB checkout. Identify domain backend/web/mobile and scope company/personal, show a no-write preview from `scripts/ccb/install.py`, obtain explicit user approval, then apply. Never silently replace existing project governance, delete old task artifacts, or alter Git state. Selected domain instructions are `.claude/rules/ccb-domain-{backend|web|mobile}.md` (only one should be installed). Mobile uses generic OptCodex baseline plus native rules; web uses upstream frontend variant with F0–F3. For multi-repo work select and install each repo separately.

Read `model-routing.json` as advisory only; the validated project `docs/agents/framework/EXECUTOR_ROUTING_POLICY.json` is the runtime source of truth for E0–E5 defaults. CCB enforces the fixed allowlist and non-default approval. Claude Opus 5.5 Medium is the default Planning Advisor in the same Claude Code session as Coordinator; GPT-6.1 Sol is an explicit opt-in external advisor only. GPT-6.2 Sol remains an approved bounded implementation writer for E2–E5.

## Selected planning/orchestration workflow

- Main Claude Code Desktop chat: **Opus 5.5 Medium**, selected by the user. CCB cannot change or verify the effective Claude runtime model/effort; confirm the UI when required.
- **Default Planning Advisor: Claude Opus 5.5 Medium in the SAME coordinator session.** Use a distinct advisory analysis phase (requirements, repository evidence, assumptions, risks, API contracts, alternatives and proposed tasks), then reconcile and author canonical SPEC/PLAN/TASK without a cross-provider packet handoff. A phase is not an independent subagent.
- **Mandatory fan-out is unchanged.** Where two or more material workstreams are independently analyzable (including material backend + frontend), dispatch separate native Claude reasoning children when available, collect distinct actual results, and reconcile them in the coordinator session. Request Opus 5.5 Medium for children if runtime selection is supported; never assert child model/effort when not observable. If dispatch is unavailable, record the permitted `UNAVAILABLE` state and exact reason; never claim single-session analysis satisfied a required independent fan-out.
- **GPT-6.1 Sol Medium via `/ccb-sol-plan` is opt-in ONLY**, requiring a distinct user request and separately authorized non-protected data-sharing packet; never launch it automatically, silently fall back, or claim its output is an approved plan.
- Claude alone owns canonical requirements, SPEC/PLAN/TASK, fan-in, approval, delegation, independent post-execution audit, final build and QA. No planning phase authorizes implementation until the currently presented plan is approved.
- Validated executor defaults are unchanged: E0 Terra/low; E1 Terra/medium; E2 Sol/low; E3 Sol/medium; E4 Sol/high; E5 Sol/xhigh.

## Role translation (coordinator remains Claude)

- **Claude Code** is the coordinator/planner/auditor, owns requirements, SPEC/PLAN/TASK, approvals, dependency fan-out/fan-in, routing, acceptance, integration and telemetry. Its own model is chosen by the Claude runtime, not by OptCodex's `gpt-6.1-sol` coordinator route.
- **Codex CLI** provides the bounded **implementation_executor** transport. A separate read-only Sol Medium advisory transport remains installed only for explicit opt-in; default planning never invokes Codex. Neither replaces Claude's canonical ownership, QA role or independent audit.
- Keep OptCodex tiers S/M/L, C/R/E classification semantics, mandatory material-workstream planning fan-out, task buildability, mandatory final build, RED-before-GREEN, QA handoff, and protected-config/Git boundaries.

## Compatibility is fail-closed

- Install one of `company`, `personal`, `frontend-company`, `frontend-personal` from OptCodexRules; install CCB only after the complete variant is present.
- Verify `optcodex.lock.json` and `scripts/ccb/compat.py` before dispatch. If pinned governance files drift or a version/variant is unsupported, stop and reconcile; never silently bypass the lock.
- Validated route policy v3 defaults: E0 Terra/low; E1 Terra/medium; E2 Sol/low; E3 Sol/medium; E4 Sol/high; E5 Sol/xhigh. Only approved and allowlisted task-specific overrides are permitted; E5 is exceptional, not a blanket escalation. Both model and effort must be explicitly bound and unavailable requested route means BLOCKED_ROUTE. Legacy v1.4 E0–E5 task manifests must be reclassified and reapproved, never silently reinterpreted.
- The user must approve the **currently presented** plan, not merely a manifest carrying the same plan ID. Do not dispatch when approval provenance is unclear.

## Optional Graphify context discovery (pilot, coordinator only)

If a user-provided, project-local graph exists and a structural codebase question or cross-module change would benefit, use /ccb-graph-context. Its Python adapter reads the selected graph under a validated project/domain registry stored outside Git; company and personal data must not be mixed. Graph evidence, even EXTRACTED edges, is not a substitute for reading actual approved source lines and tests. Never allow graph results to become task approval, route escalation or independent audit PASS. Do not run Graphify install/update or enable strict read hooks via CCB. The Graphify CLI may touch its own generated query-stamp cache; graph outputs must stay out of writer checkouts/Git status. A failed/stale/missing graph is a recoverable discovery limitation; use bounded permitted source search.

## Phase-specific loading

- Planning: baseline → `PLANNING_RULES.md` → relevant template(s), mandatory fan-out. Frontend: additionally `frontend/FRONTEND_DESIGN_RULES.md` (F0–F3).
- Execution/audit: `EXECUTION_AUDIT_RULES.md` → task-specific contract → Ponytail minimal *complete* change → RED/GREEN → Task Buildability Gate → independent audit → final repository build.
- Company variants: preserve Dev→QA publication gate. Personal variants: preserve RTK/Headroom profile. Telemetry follows OptCodex's `AGENT_TELEMETRY_SCHEMA.md` and is coordinator-written only.
- For substantive long TASKs, context drift, compact or resume, load pinned `docs/agents/framework/CONTEXT_DISCIPLINE_RULES.md` **on demand**, not in every short session. Keep TARGET/BOUNDARY/EVIDENCE/NEXT/OPEN concise; preserve audit and approvals in canonical artifacts.

## Context and compaction safety

Default: keep Claude Code auto-compact enabled; **do not compact after every TASK**. Suggest focused `/compact` only at useful phase boundaries after *independent audit PASS* and durable evidence/ledger reconciliation; an executor `REVIEW_REQUIRED` is not completion. A session summary cannot approve the plan or prove model routing, test/build evidence or audit. Before compact protect running/UNKNOWN writer handles; after manual/auto compact re-verify current-plan approval, TASK state, source and applicable rules. Claude Code slash commands are user/runtime actions, not shell commands or automated CCB hooks. No global setting or PreCompact hook is installed.

## Git, concurrency and safety

Do not alter Git history, stage, commit, push or create/delete worktrees without separate specific user approval. CCB v0.9 serializes writers in a clean checkout. Never read or modify protected configuration/environment content. JSON reports, task manifests and Git path checks are **not security sandboxes**. Do not mark an executor result PASS: always audit independently. Load `docs/agents/framework/CCB_PROTOCOL.md` only when preparing or reviewing a CCB handoff.

## Mandatory task accounting for Claude

For every newly created canonical task, call `python3 scripts/ccb/task_ledger.py plan --project "<planning-root>" --plan-id <approved_plan_id> --task-id <task_id>`. For substantive Claude coordinator/reasoning/audit work, pair `work --role coordinator|reasoning|auditor --work-id <stable_run_id> --state STARTED|FINISHED` when observable. Codex dispatch writes start/finish attempts automatically. After independent audit call `task_ledger.py audit --project ... --plan-id ... --task-id ... --attempt-id ... --verdict PASS|REWORK|BLOCKED`. The ledger is local and outside Git; do not invent usage or count retries as tasks. Report with `/ccb-report`. Always preserve canonical OptCodex coordinator telemetry separately. A missing/degraded ledger is a blocker for new Codex writers until repaired.

## Planning attempt accounting

Default same-session Opus planning is recorded via coordinator/reasoning work events and canonical OptCodex planning telemetry when observable; never manufacture subagent dispatches, model binding or quota metrics. Optional, explicitly requested `scripts/ccb/sol_plan.py` records external planning attempts under the synthetic `__planning__` key. These events must **not** count as implementation tasks; only actual TASK IDs count.
