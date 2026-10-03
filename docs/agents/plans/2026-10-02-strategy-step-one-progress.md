# Implementation Plan: Strategy step-one progress and contract continuity

Status: COMPLETE (approved and audited 2026-10-02)
Date: 2026-10-02
Tier: L
Specification: `docs/agents/specs/2026-10-02-strategy-step-one-progress.md`
Decision Ledger: N/A

## Objective and preconditions

Implement REQ-001/AC-001, REQ-002/AC-002, and REQ-003/AC-003. Preserve the existing uncommitted T40–T42 product/test/planning changes. User reported a checked level and no visible error. No live exchange verification is authorized; use local fake market/exchange tests.

## Planning workstreams

| Workstream | Material | Independent | Route | Logical run | Result |
| --- | --- | --- | --- | --- | --- |
| Wizard selection and disabled-state UX | YES | YES | R2 / gpt-6-sol / medium, explicit | R2-005 | COMPLETE / USED |
| Strategy quote freshness and market-data state | YES | YES | R2 / gpt-6-sol / medium, explicit | R2-006 | COMPLETE / USED |
| Backend preview metadata continuity | YES | YES | R2 / gpt-6-sol / medium, explicit | R2-007 | COMPLETE / USED |

Fan-out Required: YES. Required Reasoning Agents: 3. Actual Reasoning Agents: 3. Fan-out Compliance: PASS. Skip Reason: N/A. The coordinator reconciled the cross-layer contract: Step 1 navigation does not require a current quote; preview and live actions remain gated. The strategy-specific public quote age aligns to the backend's existing 15-second limit. Backend accepts only blank optional metadata when stronger ID/family/settlement/contract-value checks agree. Effective child routes were not exposed after explicit binding.

## Dependency graph and write surfaces

```text
T43 Flutter UI/market ─┐
                       ├─ final integration audit
T44 backend preview ───┘
```

Both tasks are independently buildable, use disjoint source/test paths and toolchains, and may run in one wave if runtime/worktree conditions permit. No task relies on the other's unfinished implementation. Protected configuration files are excluded.

| Task | Plan step | Allowed writes | Route |
| --- | --- | --- | --- |
| T43 | P01 — diagnostic Step 1, reconcile levels, align strategy ticker age | `lib/features/strategy/presentation/strategy_wizard_dialog.dart`, `lib/features/strategy/data/strategy_market_repository.dart`, focused `test/features/strategy/**` Dart tests | E1 / gpt-6-luna / xhigh |
| T44 | P02 — strict backend preview metadata continuity | `backend/strategy.py`, `backend/tests/test_strategy_api.py` | E1 / gpt-6-luna / xhigh |

## P01 — Flutter navigation and market freshness

Keep `_selectionOrNull`/domain checks for valid selected levels and nearest entry. Make Step 1's navigation depend on that selection, not transient quote freshness. Display a specific nearby reason when disabled and an actionable stale quote notice. On refreshed analysis, discard invalid/moved selected levels, retain valid choices, recalculate entries, and announce the change. Use a strategy-specific 15-second quote age in repository/wizard without modifying `StrategyTicker`'s default age for other screens. `_requestPreview`, save, and apply continue to require current quote and backend approval.

## P02 — backend metadata validation

Validate the strict SWAP ID and expected family/base. Permit only absent/blank base/quote fields; reject nonblank conflicts. Explicitly require linear `ctType`, USDT settlement, base-denominated contract value, positive size/value metadata, and existing live/fee/tier/quote checks. Add a fake-exchange preview matrix for blank/missing vs conflicting/inverse rows, with zero trade writes on rejection. If a fixture lacks required `ctType`, update only the focused test fixture to reflect valid metadata.

## RED / GREEN and build gates

| Task | Formal RED before GREEN | V1/V2 commands | Task buildability |
| --- | --- | --- | --- |
| T43 | RED-001/002 then GREEN-001 | `rtk flutter test test/features/strategy/strategy_wizard_dialog_test.dart`; `rtk flutter test test/features/strategy/strategy_market_repository_test.dart` | Flutter web app: `rtk flutter build web --release` after final task-local edit |
| T44 | RED-003 then GREEN-002 | `python3.12 -m unittest backend.tests.test_strategy_api -v` (focused case with `-k` where supported, then file) | Python backend: `python3.12 -m compileall -q backend` after final task-local edit |

Use narrow diagnostics during implementation, then one formal RED→GREEN checkpoint per task. V2 task ceiling; escalate to V3 only for concrete related failures. Re-run only evidence invalidated by subsequent changes. Final repository buildability requires both canonical units after all remediation: `python3.12 -m compileall -q backend` and `rtk flutter build web --release`. Final audit checks changed non-protected diffs, tests, quote safety, error states, backend no-write invariants, and status-by-name for protected paths. No external configuration action or live service verification.

## Risk, rollout, and rollback

- A stale quote must never authorize preview or orders; test the gate separately from navigation.
- A price crossing must not silently flip an existing Long/Short selection.
- Relaxing optional metadata must not admit inverse or mismatched contracts.
- Rollout is a code build/deploy after a separate deployment request; rollback is reverting these task changes. No data migration.

Execution requires user approval after this plan is presented. Commit, push, and deployment require separate authorization.

## Final integration audit

T43 and T44 passed independently. T43 required one bounded AUD-001 remediation so manual stale-quote retry works during automatic backoff without overlapping an in-flight request. RED cases preceded their respective GREEN checks. The final repository build units passed after all task code/test edits: `python3.12 -m compileall -q backend` (exit 0) and `rtk flutter build web --release` (exit 0, `build/web` produced). The backend strategy API suite passed 23 tests; the Flutter wizard and market repository files passed eight and seven tests respectively. The changed source/test paths match the approved scope alongside preserved uncommitted T40–T42 work. No protected configuration path changed; no external configuration action is required. Final verdict: PASS.
