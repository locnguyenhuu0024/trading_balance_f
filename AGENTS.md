# AGENTS.md — OptCodex + Ponytail v1.4.0

> Thin bootstrap for personal OptCodex. GitHub is the only maintained source of truth.

## 0. Binding baseline

Before repository work, read `BASELINE_AGENTS_OptCodex-Personal-v1.2.2.md` in full. It is the binding source of truth for roles, planning, approval, source-of-truth precedence, protected configuration, external services, task scope, mandatory explicit child model/effort binding, verification, audit, and telemetry. This overlay does not weaken or replace any baseline rule.

Executor routing uses validated `docs/agents/framework/EXECUTOR_ROUTING_POLICY.json` (v2): E0 Luna/xhigh, E1 Terra/low, E2 Terra/medium, E3 Terra/high, E4 Terra/xhigh, E5 Terra/max; only a separately approved task-specific override may use an allowlisted alternative. Governance, scope, audit, approval and protected-config rules remain binding; no silent model/effort substitution.

## 1. Progressive Ponytail integration

For planning/implementation/change review, load `docs/agents/framework/PONYTAIL_RULES.md` once for the applicable workflow phase. Apply reuse-first and minimal **complete** changes after requirements are understood; never skip approval, protected-file boundaries, independent audit, RED/GREEN, buildability or necessary tests. Do not auto-install the upstream plugin or activate its hooks.

Use the baseline's local coordinator for task classification (S/M/L), reasoning classes (R0–R5), executor classes (E0–E5), retry decisions and audits. No external decision service is required or authorized by this adapter.

## 2. Workflow

1. Follow the baseline's clarification and planning approval gate; load `docs/agents/framework/PLANNING_RULES.md` only in the planning cycle.
2. Choose the narrowest safe implementation, including affected callers and test contracts.
3. After explicit approval, load `docs/agents/framework/EXECUTION_AUDIT_RULES.md`; delegate each bounded task to the correctly bound executor.
4. Execute RED then GREEN, build and test at the required scope; independent coordinator audit includes minimality without downgrading safety.
5. Use existing telemetry and release/documentation conventions. Do not modify Git history or push without the requisite user authorization.

## 3. Personal context optimization

Preserve RTK-first for eligible shell output and Headroom-first for eligible large non-shell output. Before applicable inspection or verification, load `docs/agents/framework/profiles/CONTEXT_OPTIMIZATION.md`. Never let optimization tools access protected content or override exact evidence.
