# OptCodex + Ponytail — personal v1.2.0

This is the self-contained `personal` rule bundle, maintained **only on GitHub**.

## Binding baseline

- OptCodex-Personal v1.2.2 remains authoritative in `BASELINE_AGENTS_OptCodex-Personal-v1.2.2.md`. The snapshot is preserved unchanged.
- `AGENTS.md` provides a small startup layer; `docs/agents/framework/PONYTAIL_RULES.md` is loaded on demand.
- The coordinator handles S/M/L, R0–R5, C1–C3 and E0–E2 directly with baseline rules. Models: Sol `gpt-6.1-sol`, Luna `gpt-6-luna`, exceptional Astra `gpt-6-astra`, with explicit effort binding.
- No external AI classification API, credential, SDK or decision adapter is needed.
- Ponytail means reuse-first and the smallest **complete** change, never reduced security, approval, RED/GREEN, independent audit, compile/build evidence or user-requested behavior.
- RTK + Headroom context optimization remains active through `docs/agents/framework/profiles/CONTEXT_OPTIMIZATION.md`.

## Install / use

Copy the entire contents of this variant into the root of the target repository. Preserve all `docs/agents/framework` and `docs/agents/templates` paths. Do not replace an existing project-specific `AGENTS.md` without reviewing and merging higher-priority project requirements.

Do **not** automatically install the upstream Ponytail plugin or turn on codebase-map hooks. This bundle includes a carefully scoped instruction adapter, not a plugin runtime. Any third-party plugin must be separately approved and audited for protected-path compliance.

## Verification

From the OptCodexRules monorepo root, run `python scripts/validate-rules.py`. Repo-local work additionally requires all checks in the binding OptCodex baseline.

## Optional Terra implementation A/B trial

Luna remains the E0/E1/E2 default. With task-specific user approval and a recorded trial reason/ID, E1 may use GPT-6.1 Terra/high and E2 Terra/xhigh. Never silently change route or accept an executor report as an independent audit.
