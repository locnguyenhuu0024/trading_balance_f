# ClaudeCodex Bridge v0.9 — Compatibility and transport contract

## Binding upstream

Source of truth: `locnguyenhuu0024/OptCodexRules`, governance blob hashes pinned in `optcodex.lock.json`, release `1.5.0`. Each installed target must contain the **complete** selected variant: `company`, `personal`, `frontend-company`, `frontend-personal`. Use its exact `AGENTS.md`, immutable baseline, `PLANNING_RULES.md`, `EXECUTION_AUDIT_RULES.md`, Ponytail, telemetry schema and variant-specific frontend/QA/RTK instructions. No Google Drive baselines; do not vendor or silently rewrite OptCodex governance.

`scripts/ccb/compat.py` verifies exact Git blob hashes for pinned governance files. Drift, missing paths, symlinks, unknown variant or mismatched baseline/version => BLOCKED before Codex launches. Changing hash-pinned governance requires a reviewed lock bump plus tests; changing only allowlisted routing defaults does not. A modified target OptCodex is not automatically certified.

## Domain-aware deployment and current model catalog

Use `scripts/ccb/install.py` or `/ccb-install` to choose `--domain backend|web|mobile` and `--scope company|personal`, preview, then explicitly approve apply. Only selected domain overlay and pinned OptCodex variant are copied. Backend maps to company/personal; Web maps to frontend-company/frontend-personal; Mobile maps to company/personal plus `ccb-domain-mobile.md`. Never silently delete legacy documents or overwrite custom AGENTS/CLAUDE instructions. Backups for explicit managed-file replacement are stored outside project tree.

OpenAI model catalog verified 2026-11-18 lives in `model-routing.json`: GPT-6.1 Terra = bounded low-cost executor; GPT-6.2 Sol = scoped reasoning-intensive executor; Claude Opus 5.5 Medium = default same-session Planning Advisor; GPT-6.1 Sol Medium = explicit opt-in external read-only advisor. Validated executor v3 defaults: E0 Terra/low; E1 Terra/medium; E2 Sol/low; E3 Sol/medium; E4 Sol/high; E5 Sol/xhigh. Only task-approved allowlisted overrides may depart from this mapping. Pre-v1.5 manifests must be reclassified and reapproved.

## Role substitution

Claude Code owns Coordinator/Planner/Auditor, while Codex CLI replaces the `implementation_executor` child transport **only**. Claude's user-selected `claude-opus-5-5` Medium runtime handles both the coordinator and the default in-session planning-advisor phase; an optional GPT-6.1 Sol read-only route is available only after a separate explicit user request and sharing approval. Baseline routing classes remain policy for Codex-owned roles; CCB cannot select or verify the effective Claude runtime. All material product/security/architecture decisions and audit verdicts remain coordinator-owned.

## Planning + fan-out gate

Preserve S/M/L and C/R/E planning/routing. When two independently analyzable material workstreams exist, perform mandatory reasoning fan-out through separate native Claude children if available; frontend+backend material change specifically needs two distinct workstream results. Request Opus Medium for children where runtime control exists; do not assert unobserved effective routes. A same-session sequential double-pass does not satisfy independent fan-out. Capture actual results and reconcile before approval. `planning_fanout` in the job is only a checkable declaration; Claude must verify original planning records. Valid required states are PASS with sufficient collected results, or UNAVAILABLE with exact upstream reason; valid not-required exception reasons are SINGLE_MATERIAL_WORKSTREAM and NOT_INDEPENDENT_ATOMIC_CONTRACT.

## Explicit E-route (project policy with fixed allowlist)

| Executor | Model | Effort |
|---|---|---|
| E0 | `gpt-6.1-terra` | `low` |
| E1 | `gpt-6.1-terra` | `medium` |
| E2 | `gpt-6.2-sol` | `low` |
| E3 | `gpt-6.2-sol` | `medium` |
| E4 | `gpt-6.2-sol` | `high` |
| E5 | `gpt-6.2-sol` | `xhigh` |

Mandatory `agent_role=implementation_executor`, `route_binding=EXPLICIT`, `parent_route_inheritance=FORBIDDEN`; the process must receive both `--model` and `model_reasoning_effort`. Only task-specific approved nondefault allowlisted routes may override these defaults; E0 uses GPT-6.1 Terra Low; GPT-6.2 Sol is available only at approved E2–E5 or explicit allowlisted nondefault routes. If the requested model/effort is unavailable, report BLOCKED_ROUTE; never silently inherit or fall back. If effective model/effort is not exposed, record `UNVERIFIABLE`; later revealed mismatch => stop and ROUTE_MISMATCH.

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

## Dual-model runtime routing and persistent task counting

OptCodex v1.5.0 uses E0 Terra/low; E1 Terra/medium; E2 Sol/low; E3 Sol/medium; E4 Sol/high; E5 Sol/xhigh. E5 is exceptional; Sol max or Terra high/xhigh/max are optional allowlisted task-specific routes, not automatic escalation. Nondefault routes require `route_override` and matching `--approved-route-override-id`; legacy `terra_trial` remains explicit/approval-bound and never substitutes for fresh v3 plan approval.

A separate local append-only ledger at `~/.ccb/task-ledger/events.jsonl` (override via `CCB_TASK_LEDGER_PATH`, absolute outside checkout) records stable `(project_id, approved_plan_id, task_id)`, executor attempt IDs, audit outcomes and optional Claude work units. Planner calls `task_ledger.py plan` and Claude `work` entries, dispatcher records start/finish, auditor calls `audit`. Use `task_ledger.py report --since YYYY-MM-DD --until YYYY-MM-DD --project ROOT --format json|csv`. Counts never substitute for coordinator-owned OptCodex telemetry or independent audit; no token/quota guesses. `REVIEW_REQUIRED` is not PASS. Separate checkout per comparative A/B arm, no concurrent writers on shared checkout.

## Continuous Opus 5.5 Medium planning (default)

Main Claude Desktop Opus 5.5 Medium, selected manually, is Coordinator and **default in-session Planning Advisor**. In an explicit advisory phase it analyzes approved repository evidence, risks, assumptions, interfaces and proposed tasks; in the subsequent canonical phase it reconciles results, owns SPEC/PLAN/TASK, obtains approval, delegates to executors and performs an independent evidence-based post-execution audit. An advisory phase in the same session is not an independent reviewer or separate model invocation. Claude Desktop model/effort and child effective routes are not enforced or proven by CCB.

For material independent Backend/Web/Mobile workstreams, the pinned mandatory fan-out gate still requires separate reasoning-child dispatch when available; native Claude reasoning children are preferred, with Opus Medium requested only when supported. Record actual evidence, child identifiers, and observable routing; if child dispatch is unavailable, use the policy's `RUNTIME_CHILD_DISPATCH_UNAVAILABLE` / `UNAVAILABLE` state, never a fabricated PASS. The coordinator retains canonical fan-in, plan approval and post-execution audit ownership.

`/ccb-sol-plan` and `scripts/ccb/sol_plan.py` remain installed as **explicit opt-in external advisory tools**, not default planning or a silent fallback. Before any use, require a separate user request and approved, non-protected packet for OpenAI sharing; preserve strict read-only, isolated, ephemeral execution and metadata-only planning telemetry. Sol proposals cannot approve implementations, replace actual fan-out evidence, or become audit PASS. Failure of the optional external path does not block normal Opus planning.

Hybrid compatibility: OptCodex governance is still exact SHA-pinned; only runtime EXECUTOR_ROUTING_POLICY.json defaults are configurable and checked against a fixed allowlist. The installer never overwrites an existing validated project routing policy; a nondefault executor route always requires real task approval and CLI approval-ID match. Ledger audited model attribution is based on matching task and attempt identity.


## Optional Graphify discovery (v0.9 pilot)

Graphify remains a third-party local graph index; it is NOT governance, proof of correctness, or an authority to authorize task execution. Coordinator-only `/ccb-graph-context` may use `scripts/ccb/graph_context.py` for bounded queries against a user-registered per-project/domain graph. Registries remain outside project Git, and graph access is confined to an explicitly selected local project. Graphify is not installed, rebuilt, uploaded or connected to Cloud by CCB. Graph outputs can be untrusted/stale/ambiguous and require source verification; INFERRED edges are never treated as confirmed execution paths. Failures gracefully fall back to bounded source inspection, and do not change approved task routes, protected file rules, immutable governance hashes, RED/GREEN, build or independent audit gates. Generated query stamps belong to Graphify output; keep them out of clean worker checkout/Git tracking.
