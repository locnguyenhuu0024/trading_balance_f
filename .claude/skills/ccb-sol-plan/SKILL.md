---
name: ccb-sol-plan
description: Preview and dispatch a bounded read-only GPT-6.1 Sol Medium planning proposal, while Claude Sonnet High owns canonical plans.
argument-hint: "[planning-root] [backend|web|mobile|cross_layer] [work-id]"
---

# Sol Medium planning advisor (read-only)

1. Main Claude Desktop chat is user-selected **Sonnet 5.5 High**; CCB cannot set/verify that effective model. Claude alone owns source-of-truth, approved SPEC/PLAN/TASK, fan-in, approval, QA, audit, and final build.
2. Load OptCodex baseline. Identify independent material Backend, Web and Mobile workstreams. Do not use one packet to falsely claim two separate workstreams completed.
3. For each bounded workstream build an explicit coordinator-curated `.ccb/sol-planning/packets/<work-id>.json` packet. Required fields: plan_id, work_id, workstream, requirements[], repo_facts[], constraints[], questions[], source_classification="non_protected", approved_for_sol=true, approval_id. Review user/service sharing authorization before setting the flag. Never read/pass protected config, credentials, secrets or unapproved content; flag is not evidence of approval.
4. Run `python3 scripts/ccb/sol_plan.py --plan-root "<root>" --packet "<root>/.ccb/sol-planning/packets/<work-id>.json"` as a **local preview**; it does not call Codex.
5. After actual approval, call again with `--execute --approval-id <approved-id>`. Sol CLI is explicitly bound to `gpt-6.1-sol/medium`, read-only, ephemeral, isolated working directory, JSON schema output. It must not write SPEC/PLAN/TASK or code.
6. Sol returns only an untrusted, non-canonical advisory proposal. Claude verifies evidence, reconciles workstreams, resolves ambiguity and writes canonical docs. Explicit approved plan remains mandatory before Luna/Terra execution. If Sol is blocked, stop and request an authorized alternative; never silently manufacture results.
7. Planning attempts are logged separately from implementation tasks and executor attempts; do not estimate quota/tokens. Read-only CLI is not a complete filesystem read-isolation guarantee.

Request: $ARGUMENTS
