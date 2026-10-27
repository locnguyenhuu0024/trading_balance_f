---
name: ccb-install
description: Preview and, after explicit approval, install exact OptCodexRules and CCB rules for backend, web or mobile projects without deleting old work.
disable-model-invocation: true
argument-hint: "[project path] [backend|web|mobile] [company|personal]"
---

# Safe project-specific CCB installer

1. Identify project root, domain (backend / web / mobile), and scope (company / personal) from the user's request and allowed non-protected repository evidence. If a field is unknown, choose a safe explicit default from evidence or ask before applying.
2. Use `python3 scripts/ccb/install.py --project "<target>" --domain <domain> --scope <scope>` from a trusted local ClaudeCodexBridge checkout. The installer reads the pinned GitHub-only OptCodexRules release. Provide `--optcodex-source "<trusted local clone>"` to avoid private-network clone/authentication.
3. The default is **preview only**. Present selected upstream variant, file list and **all conflicts**. Do not edit files, secrets or config, or create/commit Git branches in this phase.
4. Apply only after the user explicitly approves that exact preview: rerun with `--apply`. If conflicts exist, first require explicit permission to replace specific managed paths and preserve backups outside the target project using `--replace-existing`.
5. Never delete `docs/agents` history, SPEC/PLAN/TASK, local custom rules or application files. Never overwrite an existing `AGENTS.md`/`CLAUDE.md` blindly. Manual merge of a project-specific governance file will fail strict pinning and requires a separate compatibility assessment.
6. On completion, validate selected variant against the pinned lock, list new/changed files and backup location, then ask the user to complete review/Git handling. Do not start Codex implementation or create Git commits without separate authorization.
7. Model alternatives in `model-routing.json` are advice only; strict OptCodex writer routes remain binding.

Request: $ARGUMENTS
