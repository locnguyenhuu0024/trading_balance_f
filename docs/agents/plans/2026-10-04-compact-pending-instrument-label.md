# Small Change Plan: Compact pending instrument label
Status: COMPLETE
Date: 2026-10-04
Tier: S

## Objective / P01
Display `SUIUSDT` and a separate `SWAP` badge in the pending-order header. Display pair label by joining the first two hyphen-separated instrument segments; retain a single-segment identifier unchanged. Keep instrument type badge derived from instType, coin icon and underlying instrument ID unchanged. Preserve history/position rendering and all other T77 behavior.
AC-001: SUI-USDT-SWAP renders SUIUSDT plus separate SWAP badge; full instrument ID remains in model/action payloads.
AC-002: Missing instType still renders pair; history/positions unaffected.
Allowed: pending card label expression in orders_screen.dart and corresponding focused mobile layout tests.
Single material frontend workstream; independent workstreams 1; fanout required NO; required/actual reasoning count 0/0; EXCEPTION/SINGLE_MATERIAL_WORKSTREAM. Coordinator C1, main runtime fixed.
RED: update expected displayed strings to SUIUSDT, run focused fixture before product edit and observe failure. GREEN: run focused fixtures after edit, expect 3 pass. Run existing order presentation/cancellation group.
Task/final build gate YES: Flutter web app; `flutter build web --release --no-pub` after final edit.
No config/external action. User directly requested this bounded refinement and previously authorized autonomous execution after planning.
T78, E0, gpt-6-luna/high, explicit binding, parent inheritance forbidden.

## R01 — AUD-001
Add existing pending/history loop in orders_screen_position_layout_test.dart to allowed test surface only to adapt the pending expected label. History expectation remains full identifier. T79 E0 gpt-6-luna/high follows T78 REWORK; same bound child reused. No changed product requirements.
