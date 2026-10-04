# Small Change Plan: Pending header order
Status: COMPLETE
Date: 2026-10-04
Tier: S

## Objective / P01
Reverse pending card header groups directly on current main branch: left coin icon + compact pair label (SUIUSDT) + separate instType badge (SWAP), right MUA/BAN + optional leverage. Preserve within-group order, existing styles/fit/no-wrap behavior, body/footer, history/position cards and red close-all styling.
AC-001: icon/pair/type group anchors to left; side/leverage anchors to right at phone and desktop widths.
AC-002: existing phone width/text-scale/absent-value regressions stay valid; underlying data/action payloads unchanged.
Allowed: pending header Row only in orders_screen.dart; existing mobile header geometry assertions in orders_screen_mobile_layout_test.dart.
Single material frontend workstream, atomic; fanout required NO, required/actual reasoning 0/0, EXCEPTION/SINGLE_MATERIAL_WORKSTREAM. Coordinator C1 fixed runtime.
Implementation: move instrument group before side group, update positional keys/alignments and keep flex5 for instrument/flex2 for side. Preserve leverage visibility and badge styles.
RED: update expected left/right group geometry; focused test should fail on old ordering before code edit. GREEN: same fixtures pass on reversed order.
Regression: flutter test test/features/orders/presentation test/features/orders/order_cancellation_flow_test.dart --no-pub.
Task/final build gate YES: Flutter web app, flutter build web --release --no-pub after final executable changes.
No protected content access/write; no external configuration action.
T81 E0 gpt-6-luna/high, explicit binding, no inheritance. User requested direct modification on main and previously authorized autonomous choices/execution after planning. No commit/push/deploy included in this refinement.

## P02 — Other transaction states (user scope extension)
Apply same header grouping to history and position cards. Compact instrument display joins first two segments for all card headers. Left icon/pair/instType; right side/leverage. Position direction semantics remain LONG/SHORT/VI THE exactly as currently calculated; keep its side badge style and 14px instrument font. Missing type omits badge; retain position missing leverage placeholder. Keep position metadata below header unchanged, even if type also appears there. History side MUA/BAN moves to header; replace the old body side label with state.toUpperCase() to preserve state information without duplication. Preserve history timestamp/price/quantity/notional/body layout and all actions. Pending continues completed P01.
AC-003: every card state follows common group order, retains type/status/direction semantics and compact pair display. AC-004: no overflow phone widths/scales; position actions, history amounts/timezone and existing bodies remain correct.
One material frontend workstream remains; no backend/security/data changes. Fanout exception remains SINGLE_MATERIAL_WORKSTREAM. P02/T82 depends on T81 PASS. Allowed product surface: card headers and header-only helper in orders_screen.dart plus history body former-side label to preserve state. Allowed tests: directly affected order presentation test files, assertion updates only plus geometry tests. Model IDs/action payload assertions remain full and unchanged. Shared header helper is allowed to avoid divergent layout, but avoid broader refactors.
T82 E1 gpt-6-luna/xhigh EXPLICIT. RED expected other-state grouping before source edit; GREEN after. Regression: flutter test test/features/orders/presentation test/features/orders/position_actions_test.dart test/features/orders/order_cancellation_flow_test.dart --no-pub. Task/final build Flutter web: flutter build web --release --no-pub. No deployment/commit/push in current request.

## Verification scope clarification
Position full-page 320px/text scale2 hits an unchanged order-tab dropdown internal RenderFlex overflow, not the header. Shared filter controls remain outside this header-only task. Position full-page valid matrix: 320/1,375/1.3,430/2; pending/history retain original coverage. Header-only 320/2 may be verified independently where feasible without suppressing exceptions. Report the unrelated full-page filter limitation explicitly; do not claim it fixed. Header AC-004 remains header-scoped.
