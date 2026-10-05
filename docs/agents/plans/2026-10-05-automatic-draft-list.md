# Small Change Plan: Visible automatic draft entries
Status: COMPLETE
Date: 2026-10-05
Tier: S

## Objective
Show saved JEV-selected draft entries before manual sizing, directly on the strategy card and details.

## Evidence and Scope
Backend candidate output deliberately has empty executable orders; frontend card/detail currently only display executable orders. Saved recommendation already contains ordered IDs. Material workstream: frontend presentation and bounded validation, independent YES. Backend/runtime non-material: existing contracts preserved. Fan-out Required: NO; required/actual reasoning agents: 0/1; Compliance: EXCEPTION; reason SINGLE_MATERIAL_WORKSTREAM. Advisory R2-DRAFT-LIST-001 explicitly gpt-6.1-sol/medium; effective route unavailable. Coordinator C1 requested preference Sol medium, active runtime fixed/unexposed. Prior terminal child reports collected; safe close/release primitive unavailable; capacity 21 with two reserved.
Allowed: new domain draft-display helper, strategy_screen.dart, corresponding helper/screen tests, ai-jev-strategy.md. No backend, wizard, runtime/dependency/config changes.

## Implementation Step — P01
Use immutable saved recommendation only: header/version/threshold values consistent with wizard; maximum five IDs per side, no duplicate IDs globally, correct side and unique candidate resolution, positive exact decimal, successful assessment with finite legal score ranges. Preserve ID order, no reranking/recalculation/threshold reevaluation. Invalid or legacy metadata produces no entries with actionable notice. Valid empty selection distinguishes no candidates, disabled/failed assessments, and successfully assessed candidates without qualifying recommendations. Partial successful selection shows chosen rows plus safe notice if remaining assessments disabled/failed. Never print raw provider errors.
Display a compact draft count and Long/Short exact prices directly on candidate cards and details. Label as draft entries, pending capital and review. Candidate cards avoid misleading executable total zero and fill statistics. Use the same validated helper for the save snackbar counts/reason, preserving its widget key. Ordinary strategy presentation and review behavior unchanged. No sizing, submissions, synthetic fallback, repeated requests or timers.

Tests: positive both sides, short-only up to five, maximum ten, invalid/legacy atomic rejection, empty diagnostics, precise prices, card/detail/review and no API writes/polling. RED: new regression assertions fail before implementation. GREEN: domain/screen/wizard focused tests pass.
Verification ceiling V2; no full suite needed for isolated display-only change.
Task buildability YES: Flutter web; exact command /Users/locnguyen/development/flutter/bin/flutter build web --release. Build consumes configuration opaquely; no config reads/writes.
External verification: deployed behavior and actual JEV provider status not observable locally. User asked safely for recommended counts; does not gate UI work.
External Configuration / Environment Action: none. User deployment required after completion.
Approval: existing session authorizes execution after planning, commit and push. No material unresolved decision. Task T93 below.

## Task T93
Status: PASS
Agent Role: implementation_executor
Executor Class: E1
Target Model: gpt-6-luna
Target Effort: xhigh
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Dispatch Route Status: UNVERIFIABLE only after explicit spawn
Allowed writes: lib/features/strategy/domain/strategy_draft_entries.dart; lib/features/strategy/presentation/strategy_screen.dart; test/features/strategy/strategy_draft_entries_test.dart; test/features/strategy/strategy_screen_test.dart; docs/development/ai-jev-strategy.md.
No other writes, no protected configuration content access, no children/Git/telemetry. Return RED/GREEN evidence, build status, files and telemetry E1-DRAFT-LIST-001. Coordinator independently audits and integrates. Stop for scope/contract ambiguity.
Coordinator Audit: PASS — scoped source/test/doc diff inspected; candidate orders and execution semantics unchanged; RED missing card count observed, focused 50 tests GREEN, web release build PASS to build/web. Scoped analysis retains three existing diagnostics only. No protected configuration content accessed or modified. Remote deployment/provider status remain unverified. Completion: 2026-10-06.
