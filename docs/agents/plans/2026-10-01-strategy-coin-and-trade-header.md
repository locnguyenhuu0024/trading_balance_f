# Implementation Plan: Strategy contract catalog and trade header

Status: COMPLETE (approved and audited 2026-10-01)
Date: 2026-10-01
Tier: M
Specification: `docs/agents/specs/2026-10-01-strategy-coin-and-trade-header.md`
Decision Ledger: N/A

## Objective and scope

Implement REQ-001/AC-001 and REQ-002/AC-002 in two independently auditable Flutter tasks. No backend, order execution, configuration, dependency, or deployment change. Working tree was clean on `feature/position-strategy` at planning start.

## Planning workstreams

| Workstream | Material | Independent | Route | Logical run | Result |
| --- | --- | --- | --- | --- | --- |
| Strategy catalog/data and wizard | YES | YES | R2 / gpt-6-sol / medium, explicit | R2-001 | COMPLETE, USED |
| Trade Management layout/session presentation | YES | YES | R2 / gpt-6-sol / medium, explicit | R2-002 | COMPLETE, USED |

Fan-out Required: YES. Required Reasoning Agents: 2. Actual Reasoning Agents: 2. Fan-out Compliance: PASS. Skip Reason: N/A. The coordinator reconciled both results: preserve strict catalog validation and retain operation-recovery UI outside the compact close-all area.

## Dependency graph and write surfaces

```text
T40 (catalog)    T41 (trade header)
       \          /
        final integration audit
```

Tasks are logically independent. Run writers serially because both use the same Flutter build/test workspace. Protected configuration files are excluded from all write surfaces.

| Task | Plan step | Allowed product/test files | Route |
| --- | --- | --- | --- |
| T40 | P01 — accept empty SWAP base metadata, preserve strict filtering, add regression cases | `lib/features/strategy/data/strategy_market_repository.dart`, `test/features/strategy/strategy_market_repository_test.dart` | E1 / gpt-6-luna / xhigh |
| T41 | P02 — compact action area, AppBar status icon, preserve diagnostics, add widget coverage | `lib/features/orders/presentation/orders_screen.dart`, `lib/features/orders/presentation/widgets/trade_account_controls.dart`, relevant `test/features/orders/**` Dart tests | E1 / gpt-6-luna / xhigh |

## Verification

| Task | Formal RED before GREEN | Focused command | Buildability gate |
| --- | --- | --- | --- |
| T40 | RED-001 then GREEN-001 | `flutter test test/features/strategy/strategy_market_repository_test.dart` | `flutter build web --release` |
| T41 | RED-002 then GREEN-002 | `flutter test test/features/orders/position_actions_test.dart test/features/orders/presentation/orders_screen_position_layout_test.dart` | `flutter build web --release` |

Diagnostic inner loop: run only the failing focused test while editing. Formal checkpoint after implementation: execute each task's RED case before its GREEN case, then relevant file(s). Verification ceiling V2 per task; final integration V3 for both affected groups only if shared UI risk warrants it. Escalate on a concrete regression or compiler failure. No live OKX request or production order is needed to verify this correction.

## Risks and completion

- A compact button could obscure pending-operation recovery. Keep that UI in a separate conditional diagnostic section and verify existing lookup tests.
- A permissive fallback could admit malformed or mismatched contracts. Keep the strict ID pattern and nonblank metadata consistency check.
- Task boundaries are self-contained and each must leave the Flutter web application buildable.
- Final audit checks diff/name-only status, acceptance criteria, RED-before-GREEN evidence, focused tests, and protected-configuration compliance.
- No external configuration action, migration, or rollout step is required.

Execution requires user approval after this plan is presented. Commit, push, and deployment require separate authorization.

## Final integration audit

T40 and T41 passed independently, with observed RED before GREEN evidence. The final repository web build `rtk flutter build web --release` passed after both task changes (exit 0, `build/web` produced). `git diff --check` passed for all five changed product/test files. The changed surfaces do not conflict. No protected configuration path changed, and no external configuration action is required. Final verdict: PASS.
