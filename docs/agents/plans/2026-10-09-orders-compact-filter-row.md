# Small Change Plan: Compact Orders filter row

Status: COMPLETE
Date: 2026-10-09
Tier: S
Frontend Level: F1
Required Frontend Guidance: pinned web-design-guidelines
Visual Review Required: YES (reuse actual Orders screenshot harness)

## Objective and evidence
Two selects and close-all appear on a single compact row. User explicitly requested reduced overall dimensions and horizontal widths, then authorized automatic execution after planning, a new branch, commit and push.
Current `OrderFilterControls.build` stacks selects below 340px available width or above 1.2 text scale. `TradeAccountControls.build` expands filters to all remaining width and paints a 48px close-all border.
Only one material frontend workstream; fan-out EXCEPTION / SINGLE_MATERIAL_WORKSTREAM. Coordinator C1 preferred Sol medium; effective route not exposed.

## P01 / T109
- Keep a single row at 320, 390 and 1280px and text scale 1.6; constrain each select to at most 140px (pair max286px including 6px gap), flex narrower within available width.
- Select text13px, icon18px, horizontal padding8px, visible bordered face40px high; retain native dropdown keyboard/focus behavior, full accessible labels and untruncated menu options. Selected label may ellipsize when enlarged text requires it.
- Remove floating-label vertical footprint; retain status/type labels through semantic labels and tooltips. Use existing theme colors/font family/radii.
- Close-all visible bordered face36px, icon18px, keep48px native IconButton hit target and all visibility, disable, confirmation and session safety behavior.
- Outer row vertical padding4px top/0 bottom; gap6px. Keep48px interactive heights. Avoid inert duplicate control overlays/custom gesture replacements.
- Allowed sources: order_filter_controls.dart, trade_account_controls.dart in Orders widgets; orders_screen.dart only if necessary for caller layout. Tests: order_filter_controls_test.dart, orders_screen_refresh_test.dart, position_actions_test.dart only if impacted visual assertion needs updating.
- Preserve provider callbacks, current values, pending/history behavior and live trade safety. No backend/configuration/dependencies changes.

## Verification
RED first: signed-out/disabled close-all remains unavailable and 320px/enlarged-text/longest selections cannot overflow; execute focused boundary test before GREEN.
GREEN second: full focused filter and Orders refresh test files prove three controls same row, compact capped widths/visible dimensions, unchanged selection callbacks. Include relevant position_actions_test.dart for shared close-all invariants (V2 related group). No full suite absent regression trigger.
Reuse existing screenshot harness with actual fonts; inspect320/390 enlarged/desktop captures.
Buildability/final build: Flutter application, `C:\Users\Loc\develop\flutter\bin\flutter.bat build web --no-pub`, once after final source/test edits. Unchanged backend byte-compilation may be reused from previous task; no backend runtime changes.
No external verification/configuration actions. Native device QA not claimed.

## Execution contract and approval
One task/wave, E1 gpt-6-luna/xhigh; role implementation_executor; EXPLICIT model and effort; parent inheritance FORBIDDEN. Effective route unavailable must be UNVERIFIABLE.
User's direct instruction to plan then execute supersedes approval timing in baseline; plan presented before dispatch. Branch `codex/orders-compact-filter-row` created from existing delivered feature branch without merging.
Stop on protected config need, behavior ambiguity, or write-surface expansion. Coordinator audits allowed diffs and pinned interface rules before commit/push.

## Completion evidence
T109 PASS; allfive allowed source/test files reviewed independently. Formal final negative RED (signed-out disabled refresh) then GREEN (actual Orders compact row) both exit0; relevant57-test group passed; fresh webbuild exit0 after all executable edits. Actual-font fiveviewport previews regenerated and coordinator accepted320px/1.6 and1280px after centering correction. See task ledger for exact commands/limits. No protected path changes or configuration actions. Commit/push are separately verified after artifact completion.
