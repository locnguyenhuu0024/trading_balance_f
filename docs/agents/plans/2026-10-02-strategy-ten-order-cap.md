# Implementation Plan: Ten Orders Per Strategy

Superseded by `docs/agents/specs/2026-10-03-strategy-limit-cap-resubmission-design.md` and `docs/agents/plans/2026-10-03-strategy-limit-cap-resubmission.md` on 2026-10-03; resolved decisions and selective retry are canonical there.

Status: SUPERSEDED
Date: 2026-10-02
Tier: M
Specification: `docs/agents/specs/2026-10-02-strategy-ten-order-cap-design.md`
Decision Ledger: `docs/agents/decisions/2026-10-02-strategy-ten-order-cap-decisions.md`

## Planning workstreams

| Workstream | Material | Independent | Explicit route | Logical run | Result/adoption |
|---|---|---|---|---|---|
| Backend admission and legacy lifecycle | YES | YES | R2 / gpt-6.1-sol / medium | R2-TEN-BACKEND-01 | COMPLETE / USED |
| Frontend selection and confirmation | YES | YES | R2 / gpt-6.1-sol / medium | R2-TEN-FRONTEND-01 | COMPLETE / USED |

Fan-out Required: YES
Required Reasoning Agents: 2
Actual Reasoning Agents: 2
Fan-out Compliance: PASS
Skip Reason: N/A

Frontend spawn encountered runtime agent-thread capacity; reused a completed explicitly bound R2 reasoning child through native followup. No inherited/default writer and no duplicate implementation. Effective routes unavailable / UNVERIFIABLE. Coordinator C1 standard/low orchestration, preferred gpt-6.1-sol medium; main effective route unexposed.

Coordinator synthesis: retain historical readers/global worker budget20; enforce10 only at agreed new-admission boundaries. Resolve Q-001/Q-002 before finalizing legacy contract. No product files changed.

## Draft decomposition / dependency graph

Proposed T62 backend -> T63 frontend -> integration audit. Task numbers are provisional until canonical task creation after clarification. T61 diagnostic work is complete (PASS). Any later cap writer must preserve the new diagnostics and serially own the shared backend surface.

- P01: Backend new-admission max10, shared prepare/execute count checks and selected legacy policy; affected API/queue tests. Leave canonical backend buildable.
- P02: Frontend selection limit/indicator, preview/prepared validation, saved strategy notices/guards and historical reader compatibility; affected domain/controller/widget tests.
- P03: Cross-layer audit of10 success,11 rejection, historical20 and selected queue policy.

Expected executor route E1 / gpt-6-luna / xhigh for both bounded tasks, EXPLICIT model and effort, role implementation_executor, parent inheritance forbidden. If Q-002 chooses an active-queue stop transition, assess implementation entropy again before final task route selection.

## Verification and permitted surfaces

Formal RED-001 before GREEN-001 for backend; RED-002 before GREEN-002 for frontend. V3 ceiling: affected strategy API/queue and selection/controller/wizard/screen groups. Include worker regressions if active-tail policy changes. Replace a newly created20-order shared-budget fixture with compliant strategies proving the unchanged20-per-pass budget.

Affected sources: `backend/strategy.py`; queue/worker only if chosen active-tail semantics require it; `lib/features/strategy/domain/strategy_selection.dart`, `strategy_models.dart`, dashboard provider, wizard and screen. Tests confined to corresponding backend and strategy test paths. Detailed exact write allowlists will be finalized in tasks. No configuration/env/manifest/container/dependency/schema changes.

Backend build: `PYTHONPYCACHEPREFIX=/private/tmp/ten-order-cap-pycache /Users/locnguyen/.local/bin/rtk test /opt/homebrew/bin/python3.12 -m compileall -q backend`.
Frontend build: `/Users/locnguyen/.local/bin/rtk flutter build web --no-pub --release --dart-define=TRADE_API_BASE_URL=https://api.tradingbalancef.com`.

Build after final task-local executable changes and final integration. No live OKX trades or deployment; no commit/push inferred. External configuration actions NONE presently.

## Pending gates

- [x] D-001 scoped and fan-out reconciled.
- [ ] Q-001 and Q-002 resolved.
- [ ] Canonical tasks allocated; exact legacy AC and allowed surfaces finalized.
- [ ] Ready plan presented; explicit post-plan execution approval received.
- [ ] Tasks PASS, RED before GREEN, affected regressions/builds and final integration audit PASS.
