# Task 83 — Modal body and compact close-all layout
Status: PASS
Plan: docs/agents/plans/2026-10-05-modal-and-close-all-layout.md#P01
Agent Role: implementation_executor
Executor Class: E1
Target Model: gpt-6-luna
Target Effort: xhigh
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Dispatch Route Status: UNVERIFIABLE

Implement P01 AC-001–003 within its exact allowed source/test surfaces. Do not redesign action logic. Keep one positions TradeAccountControls owner; add optional filterControls slot and put filters + outlined square close-all together, retaining standalone control when slot absent. Remove positions body duplicates, preserve pending control. Detail content outer Card/Padding removed; scroll body owns spacing.
RED then GREEN: focused widget layout/style assertions using existing fixtures, failing before source changes and passing afterward. Verify narrow/wide layouts and existing destructive-action safeguards. Run relevant test files --no-pub, ceiling V2. Required task/final canonical build: flutter build web --release --no-pub after final executable edit; report exact command/exit.
Forbidden: protected configuration/environment content access or writes, unrelated refactors, external services, telemetry/task/status writes, commits/pushes. RTK-first if available and supported; narrow raw fallback for exact evidence/unsupported tooling. Do not spawn children. Stop and return concrete blocker if contract cannot be implemented safely.
External verification/configuration actions: none.

## Ledger
- [x] AC-001–003 implemented
- [x] RED then GREEN observed
- [x] Relevant regression checks passed
- [x] Task buildability passed
- [x] Scope/configuration boundary independently audited
Coordinator Audit: PASS — AC-001–003 satisfied; source/test diffs inspected; no protected paths changed; explicit route request verified; final root Flutter web build succeeded.

## Verification evidence
RED before source edits: `flutter test test/features/strategy/strategy_screen_test.dart --no-pub --plain-name "strategy details use the modal scroll body without a card"` exited 1 (old Card present); `flutter test test/features/orders/orders_screen_refresh_test.dart --no-pub --plain-name "positions filters and close-all stay aligned without overflow"` exited 1 (old visible label present).

GREEN/regression, all exit 0:
- `rtk proxy flutter test test/features/strategy/strategy_screen_test.dart --no-pub` — 16 tests.
- `rtk proxy flutter test test/features/orders/orders_screen_refresh_test.dart --no-pub` — 4 tests, including 320/390/800px and pending controls.
- `rtk proxy flutter test test/features/orders/order_filter_controls_test.dart --no-pub` — 1 test.
- `rtk proxy flutter test test/features/orders/position_actions_test.dart --no-pub` — 30 tests.
- `rtk proxy flutter build web --release --no-pub` — exit 0, after final executable edit; task and final build gates PASS. Wasm dry-run compatibility and CupertinoIcons font warnings are non-blocking.
- Coordinator `git diff --check` — exit 0.

Executor evidence reused: exact commands/results recorded, no later executable edits; tests retain functional assertions and change wrapper-specific finders only. One material UI workstream; six source/test paths within scope. External configuration/environment actions: none. Runtime exposes no child close/release primitive; terminal result collected/adopted, no further child turn planned.
