# Task 82 — Header grouping across transaction states
Status: PASS
Dependency: T81 PASS
Plan: docs/agents/plans/2026-10-04-pending-header-order.md#P02
Agent Role: implementation_executor
Executor Class: E1
Target Model: gpt-6-luna
Target Effort: xhigh
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Dispatch Route Status: PASS

Implement P02 AC-003/004. History and position header: left coin icon/compact pair/type badge; right side/leverage. Position retains LONG/SHORT/VI THE calculation and badge, 14px pair font and missing-leverage placeholder. History MUA/BAN moves to header, replace former body sideText with state.toUpperCase so state preserved. Other bodies/metadata/action behavior untouched. Compact pair for all headers; underlying IDs unchanged. Pending completed T81 grouping must remain correct. Shared header-only helper allowed, no broader refactor.
Allowed product writes: lib/features/orders/presentation/orders_screen.dart header code/helper and history former-side label only. Allowed tests: direct affected test/features/orders/presentation/*.dart assertions and geometry tests; never alter model fixture IDs or confirmation/action payload expectations. Use source/test allowlist only; protected configs/environment/manifests/locks forbidden read/write.
RED other-state grouping before product edit then GREEN after. Regression command from P02; final build flutter build web --release --no-pub after final code/tests. Exact exit/count/freshness required. No external actions, Git mutations, recursive agents or docs/task/telemetry writes. RTK first, raw SDK cache retry with permission when needed.
Coordinator audit PASS.

Final RED: prescribed regression exit 1, 70 passed/3 expected header failures on baseline. GREEN: prescribed regression 73 passed, exit 0. Fresh final Flutter web build exit 0 after final source/test edits. Shared filter limitation at position full-page320/2 remains outside header task and reported in audit. Scope/AC-003/004 PASS.
