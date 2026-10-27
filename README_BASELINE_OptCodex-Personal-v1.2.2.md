# OptCodex-Personal v1.2.2




Personal-project fork of the token-efficient planner → executor → auditor workflow. This variant keeps the same planning tiers, bounded low-model execution, verification escalation, selective evidence invalidation, executor patience/stall detection, and final integration audit as OptCodex, while enabling **RTK + Headroom MCP** for context optimization.




## Install into a repository




Copy:




```text
OptCodex-Personal/AGENTS.md
→ <repo-root>/AGENTS.md




OptCodex-Personal/docs/agents/
→ <repo-root>/docs/agents/
```




Result:




```text
<repo-root>/
├── AGENTS.md
└── docs/agents/
    ├── framework/
    │   ├── PLANNING_RULES.md
    │   ├── EXECUTION_AUDIT_RULES.md
    │   └── profiles/
    │       └── CONTEXT_OPTIMIZATION.md
    └── templates/
        ├── SMALL_PLAN_TEMPLATE.md
        ├── SMALL_TASK_TEMPLATE.md
        ├── SPEC_TEMPLATE.md
        ├── PLAN_TEMPLATE.md
        ├── TASK_TEMPLATE.md
        ├── DECISIONS_TEMPLATE.md
        ├── PLAN_VALIDATION_TEMPLATE.md
        ├── EXECUTOR_REPORT_TEMPLATE.md
        └── AUDIT_TEMPLATE.md
```




`README.md` itself is optional in the repository.




## RTK + Headroom behavior




`AGENTS.md` routes noisy shell/tool-heavy work to `docs/agents/framework/profiles/CONTEXT_OPTIMIZATION.md`. The profile is progressive-loaded once per relevant context rather than embedded in the always-loaded core.




Responsibility split:




```text
shell output             → RTK
large non-shell output   → Headroom MCP
exact evidence needed    → raw/retrieve original
```




Coordinator and subagents follow the same profile. RTK/Headroom are context optimizers only; they never override planning approval, bounded scope, Git safety, RED/GREEN evidence, environment-failure classification, or audit requirements.




## Expected prerequisites




- RTK installed and callable as `rtk`, or on Windows optionally at `D:/CodexData/rtk/bin/rtk.exe`.
- Headroom MCP connected/available to Codex when Headroom compression is desired.




If either optimizer is unavailable, work continues using narrow raw/local commands and normal tool output. The optimizer being unavailable is not itself a task blocker.




## Progressive loading




Normal flow:




```text
AGENTS.md
  ↓
PLANNING_RULES.md only during planning
  ↓
selected templates only
  ↓ user approval
EXECUTION_AUDIT_RULES.md during execution/audit
  ↓
CONTEXT_OPTIMIZATION.md only when shell/tool output warrants it
```




Do not load every template/profile for completeness.








## v1.2 model routing




The active Sol baseline is now `gpt-6.1-sol`: `medium` is the default orchestrator, `high` handles hard coding/planning, `xhigh` handles very hard debugging/architecture, and `max` handles extreme reasoning. Executor routing remains on `gpt-6-luna` (`high` → `xhigh` → `max`). Reserve `gpt-6-astra` / `max` for absolute-ceiling or special workloads. `gpt-6-sol` is compatibility/legacy-benchmark only.


## v1.2.2 sub-agent lifecycle patch


This patch adds explicit sub-agent thread lifecycle and capacity management. After a terminal child result is collected, the coordinator closes/releases the child unless an immediate follow-up is planned. Before each spawn wave it cleans up terminal children, preserves reserve capacity below the runtime hard ceiling when known, and treats `agent thread limit reached` as a recoverable orchestration-capacity condition: cleanup first, retry once, then serialize/reuse safely or report `BLOCKED_ROUTE / AGENT_THREAD_LIMIT_REACHED`. UI `Done` / `Active: 0` is not treated as proof that backend thread capacity has been reclaimed.