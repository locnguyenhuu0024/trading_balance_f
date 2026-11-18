---
name: ccb-sol-plan
description: Optional external GPT-6.1 Sol Medium planning proposal, only on explicit user request and approved sharing; default advisor is Claude Opus 5.5 Medium.
argument-hint: "[planning-root] [backend|web|mobile|cross_layer] [work-id]"
---

# Optional external Sol Medium planning advisor (read-only)

1. **Do not invoke as part of default planning.** Default Planning Advisor and Coordinator are user-selected **Opus 5.5 Medium** in the same Claude Code session, via `/ccb-plan`. Invoke this skill only after the user explicitly requests an additional external Sol advisory proposal. CCB cannot set/verify the Claude runtime model. Claude alone owns canonical SPEC/PLAN/TASK, fan-in, approval, QA, audit and final build.
2. Load OptCodex baseline. Identify material Backend, Web and Mobile workstreams. Do not use one packet to falsely claim two separate workstreams or native Claude subagents completed. Optional Sol planning is not a substitute for the pinned mandatory fan-out gate.
3. For each bounded workstream build an explicit coordinator-curated `.ccb/sol-planning/packets/<work-id>.json` packet. Required fields: plan_id, work_id, workstream, requirements[], repo_facts[], constraints[], questions[], source_classification="non_protected", approved_for_sol=true, approval_id. Review user/service sharing authorization before setting the flag. Never read/pass protected config, credentials, secrets or unapproved content; flag is not evidence of approval.
4. Run `python3 scripts/ccb/sol_plan.py --plan-root "<root>" --packet "<root>/.ccb/sol-planning/packets/<work-id>.json"` as a **local preview**; it does not call Codex.
5. After actual approval, call again with `--execute --approval-id <approved-id>`. Sol CLI is explicitly bound to `gpt-6.1-sol/medium`, read-only, ephemeral, isolated working directory, JSON schema output. It must not write SPEC/PLAN/TASK or code.
6. Sol returns only an untrusted, non-canonical advisory proposal. Claude verifies evidence, reconciles workstreams, resolves ambiguity and writes canonical docs. Explicit approved plan remains mandatory before Terra/Sol executor dispatch. If optional Sol is blocked, report the optional path as unavailable; default Opus planning remains available without it. Never fabricate results.
7. Planning attempts are logged separately from implementation tasks and executor attempts; do not estimate quota/tokens. Read-only CLI is not a complete filesystem read-isolation guarantee.

Request: $ARGUMENTS
