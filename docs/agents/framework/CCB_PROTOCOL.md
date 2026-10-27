# ClaudeCodex Bridge v0.5 — Compatibility and transport contract

## Binding upstream

Source of truth: `locnguyenhuu0024/OptCodexRules`, GitHub tree SHA pinned in `optcodex.lock.json`, release `1.2.0`. Each installed target must contain the **complete** selected variant: `company`, `personal`, `frontend-company`, `frontend-personal`. Use its exact `AGENTS.md`, immutable baseline, `PLANNING_RULES.md`, `EXECUTION_AUDIT_RULES.md`, Ponytail, telemetry schema and variant-specific frontend/QA/RTK instructions. No Google Drive baselines; do not vendor or silently rewrite OptCodex governance.

`scripts/ccb/compat.py` verifies exact Git blob hashes for pinned governance files. Drift, missing paths, symlinks, unknown variant or mismatched baseline/version => BLOCKED before Codex launches. Changing upstream requires an explicit reviewed lock bump plus parity tests. A modified target OptCodex is not automatically certified.

## Domain-aware deployment and current model catalog

Use `scripts/ccb/install.py` or `/ccb-install` to choose `--domain backend|web|mobile` and `--scope company|personal`, preview, then explicitly approve apply. Only selected domain overlay and pinned OptCodex variant are copied. Backend maps to company/personal; Web maps to frontend-company/frontend-personal; Mobile maps to company/personal plus `ccb-domain-mobile.md`. Never silently delete legacy documents or overwrite custom AGENTS/CLAUDE instructions. Backups for explicit managed-file replacement are stored outside project tree.

OpenAI model catalog verified 2026-10-27 lives in `model-routing.json`: Luna = focused executor, GPT-6.1 Terra = visual/computer-use analysis candidate, GPT-6.1 Sol = demanding reasoning candidate, Astra = exceptional capability. Baseline E0/E1/E2 defaults to Luna. Pinned OptCodex v1.2.0 also permits Terra/high E1 and Terra/xhigh E2 trials after separate explicit user approval, full experiment manifest and CLI experiment-id match. All other alternatives BLOCKED_ROUTE. Claude planning subagents use Claude models, not Codex models.

## Role substitution

Claude Code owns Coordinator/Planner/Auditor, while Codex CLI replaces the `implementation_executor` child transport **only**. Claude's runtime model is not an alias for `gpt-6.1-sol`; baseline routing classes remain the policy for Codex-owned roles, while Claude coordinator capability varies with Claude product settings. All material product/security/architecture decisions and audit verdicts remain coordinator-owned.

## Planning + fan-out gate

Preserve S/M/L and C/R/E planning/routing. When two independently analyzable material workstreams exist, perform mandatory reasoning fan-out; frontend+backend material change specifically needs two planning workstreams. Capture actual results and reconcile before approval. `planning_fanout` in the job is only a checkable declaration; Claude must verify original planning records. Valid required states are PASS with sufficient collected results, or UNAVAILABLE with exact upstream reason; valid not-required exception reasons are SINGLE_MATERIAL_WORKSTREAM and NOT_INDEPENDENT_ATOMIC_CONTRACT.

## Explicit E-route (default plus separately approved trial)

| Executor | Model | Effort |
|---|---|---|
| E0 | `gpt-6-luna` | `high` |
| E1 | `gpt-6-luna` | `xhigh` |
| E2 | `gpt-6-luna` | `max` |

Mandatory `agent_role=implementation_executor`, `route_binding=EXPLICIT`, `parent_route_inheritance=FORBIDDEN`; the process must receive both `--model` and `model_reasoning_effort`. Only task-specific approved Terra E1/high or E2/xhigh trial may override these defaults; E0 never uses Terra. If the requested model/effort is unavailable, report BLOCKED_ROUTE; never silently inherit or fall back. If effective model/effort is not exposed, record `UNVERIFIABLE`; later revealed mismatch => stop and ROUTE_MISMATCH.

## Execution states + safety

`PLANNED -> PRESENTED -> APPROVED -> READY -> RUNNING -> REVIEW_REQUIRED -> PASS | REWORK | BLOCKED`.

- Approval requires the user's explicit action on **current** presented plan; the CLI plan-ID match alone cannot prove approval.
- Preserve predecessors PASS, RED-before-GREEN, smallest independently auditable task, plan validation on false assumptions, and one writer per clean checkout in v0.2. More than one writer requires separately authorized isolated worktrees and future CCB parallel support.
- Job manifests must be under the planning root's `jobs/<safe-name>.json` or `docs/agents/ccb/jobs/<safe-name>.json`. Manifest task files must be under `tasks/*.md`; no symlink task/allowlist paths, no protected configuration writes. `workspace-write` sandbox + Git name-only checks do not prevent protected reads, ignored-file writes, or time-of-check/time-of-use races. Use an isolated container/VM with carefully curated files for higher assurance.
- On timeout/unknown writer state, terminate best effort and BLOCK; do not automatically retry or delete user changes.
- Full executor output is not retained; review the structured report. The report itself is untrusted and not an independent audit.

## Verification and variant gates

Claude audit independently verifies RED then GREEN, tests, Task Buildability Gate for every code-changing task, and the mandatory final repository build after final integration. Reuse valid evidence and stop wasteful environment retries. Use Ponytail reuse-first/minimal **complete** change review, never as permission to omit safety, tests or necessary caller updates.

`company`: preserve Dev→QA handoff and protected configuration boundary.
`personal`: preserve RTK/Headroom and personal context/security boundaries.
`frontend-company`: combine company QA/safety with F0–F3 design, relevant pinned frontend skills and accessibility/visual review.
`frontend-personal`: combine personal RTK/Headroom with F0–F3, pinned frontend skills and accessibility/visual review.

Coordinator owns canonical telemetry JSONL, route fit, true observed usage, retry/escalation and weekly metrics. No executor writes shared telemetry. CCB output can supply bounded metadata but is not a substitute for the original OptCodex schema.

## Pilot acceptance

Run against a disposable, correctly pinned variant checkout, after explicit plan/Git approvals. Confirm missing/wrong version, null route, wrong effort, task symlink, missing fan-out, dirty checkout, out-of-scope edit, invalid report and timeout all BLOCK; valid fake CLI dispatch yields REVIEW_REQUIRED; independent audit requires task and final build evidence. No claim of live end-to-end verification without testing the real Claude + Codex runtime.

## Optional Terra executor trials and persistent task counting

OptCodex v1.2.0 retains Luna default routes, adds GPT-6.1 Terra/high for E1 or Terra/xhigh for E2 only with separate explicit per-task trial approval (experiment ID and reason). `--approved-experiment-id` is required for a Terra execution. Never infer authorization from JSON; verify user intent and exact plan. Fail closed on unavailable/mismatched model.

A separate local append-only ledger at `~/.ccb/task-ledger/events.jsonl` (override via `CCB_TASK_LEDGER_PATH`, absolute outside checkout) records stable `(project_id, approved_plan_id, task_id)`, executor attempt IDs, audit outcomes and optional Claude work units. Planner calls `task_ledger.py plan` and Claude `work` entries, dispatcher records start/finish, auditor calls `audit`. Use `task_ledger.py report --since YYYY-MM-DD --until YYYY-MM-DD --project ROOT --format json|csv`. Counts never substitute for coordinator-owned OptCodex telemetry or independent audit; no token/quota guesses. `REVIEW_REQUIRED` is not PASS. Separate checkout per comparative A/B arm, no concurrent writers on shared checkout.

## Sonnet 5.5 High + Sol Medium planning pilot

Main Claude Desktop Sonnet 5.5 High, selected manually, stays Orchestrator, canonical SPEC/PLAN/TASK owner, current-plan approver, independent auditor and final builder. GPT-6.1 Sol Medium may prepare bounded BE/FE/mobile planning proposals using the `scripts/ccb/sol_plan.py` **advisory** transport. Each workstream is a separate approved non-protected packet. Sol runs against an empty temporary directory, schema-constrained and read-only, not a source repo; output is transient and cannot authorize implementation. Read-only is not a complete host-filesystem security sandbox. Company data-sharing restrictions and protected paths still apply. Claude must independently collect/reconcile BE/FE workstreams, write the canonical plan and request approval before executor dispatch. Planner attempts are separate ledger events, not implementation tasks or audited PASS. The Claude Desktop model menu cannot be programmatically set by CCB.
