# Adaptive prices and position card height

Status: COMPLETE on 2026-09-09. Tasks A/B and final integration audit PASS; see checklist for evidence and existing analyzer info lints.
Specification: [2026-09-09-adaptive-prices-position-height-design.md](../specs/2026-09-09-adaptive-prices-position-height-design.md)
Checklist: ../../../tasks/task_17_adaptive-prices-position-height.md

## Scope and approach
Implement the specification in two serial, independently audited executor tasks. No dependencies, models, networking, calculations or navigation changes. Preserve pre-existing working-tree changes, including test/widget_test.dart. No commit or push.

## Task A: shared number formatting
Allowed: new lib/core/formatting/adaptive_number_format.dart; formatting imports/helper/call sites in orders_screen.dart and fractal_screen.dart; new focused tests under test/core/formatting and test/features/fractal_tracker, plus a dedicated Orders price regression test.
1. Extract `_formatNumber` unchanged into the named shared helper; delegate existing Orders formatting to it or replace call sites.
2. Replace the four Fractal price format calls; retain intl for DateFormat.
3. Unit-test empty, invalid, zero, 0.09117, 0.00001234, eight-decimal rounding, 1, 999.99999, 1000 and large grouped values against existing behavior.
4. Add provider-overridden screen tests proving Fractal current/open/high/low labels use the helper and missing prices stay `--`; verify Orders entry/mark/liquidation outputs remain unchanged. Dispose screens to stop timers; no live network dependency.
Acceptance: specification price criteria and observed passing focused tests. Stop BLOCKED for unresolved inputs/contracts or necessary out-of-scope changes.

## Task B: content-sized positions (after A PASS)
Allowed: responsive_order_grid.dart; position grid invocation and position Column sizing in orders_screen.dart; new test/features/orders/presentation/widgets/responsive_order_grid_test.dart and dedicated position layout tests.
1. Make cardExtent optional and retain supplied-extent behavior.
2. Implement the row-list branch exactly as specified; preserve ordering, scrolling, padding and incomplete-row widths.
3. Remove position extent 270 and set its content Column mainAxisSize.min. Leave order extent 190.
4. Widget-test widths 390, 600, 900, 1600; incomplete rows, unequal content heights, multiple rows and scroll reachability. Verify actual position card height follows content using last price bounds plus existing padding, currency modes and supported text scaling. Check no Flutter layout exceptions. Retain fixed-extent grid compatibility coverage without editing existing widget_test.dart.
Acceptance: specification layout criteria and observed passing tests. Stop BLOCKED if content requires architecture changes outside scope.

## Verification and audit
For each task run dart format --output=none --set-exit-if-changed on changed Dart files, flutter analyze on changed production/test paths, and flutter test on added/affected tests. Return exact files, commands, results and deviations. Coordinator reviews every diff and acceptance criterion independently; verdict PASS/REWORK/BLOCKED, with delegated remediation as needed.
After both pass run `flutter test` and `flutter analyze`, compare failures with baseline when necessary, inspect final git diff/status, and update checklist. Existing working tree is dirty in unrelated navigation/settings/platform files; do not attribute baseline failures to this change without evidence.

## Risks and rollback
Natural-height rows may have whitespace outside shorter cards; no equal-height stretching is intended. Existing eight-decimal precision is preserved and does not promise arbitrary exchange tick-size support. Avoid opportunistic formatter policy changes. Rollback only this change's hunks/files; never discard unrelated work.
