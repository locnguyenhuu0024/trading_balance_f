# Task 104 — Remove introduced refresh analyzer diagnostics

Status: PASS
Agent Role: implementation_executor
Executor Class: E0
Target Model: gpt-6-luna
Target Effort: high
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Dispatch Route Status: UNVERIFIABLE
Finding: AUD-104-001
Predecessor: T100–T103 coordinator PASS; final suite504 PASS

Final analyzer produced seven new unused_result warnings on `await ref.refresh(provider.future)` statements across Fractal, Market, Orders(two), PortfolioDetails, Portfolio rate, and Settings rate. Awaiting while discarding annotated result triggers the rule. Use canonical invalidate followed by await read(provider.future), preserving existing guards, captured provider/tab, error handling and awaited completion. Strategy's newly added dashboard null ternary yields prefer_null_aware_operators; use dashboard?.refresh. Newly added test-only const diagnostics may be corrected at their exact new statements after confirming baseline, without unrelated cleanup.

Allowed: only affected refresh statements in seven page files and strategy_screen.dart; narrow new const statements in introduced Orders/API/auth tests if confirmed. No behavior redesign, auth storage change, tests weakened, other lint cleanup, docs/tasks/Git/telemetry/protected writes or subagents. Return exact changed lines and commands. Protected configuration remains opaque.

RED: focused Market cross-control pending/coalescing test plus Portfolio disposal/pending before primary refresh positive. GREEN: affected page test files; unchanged fullsuite504 evidence reused except changed dependency surfaces. Do not rerun full suite. Run analyzer --no-pub to prove new seven warnings absent, record remaining preexisting diagnostics truthfully. Fresh `flutter build web --no-pub` after final executable edit. Existing elevated RTK Flutter path C:/Users/Loc/develop/flutter/bin/flutter.bat. Task buildability YES. Formatter on source/test files only. External configuration actions none.

- [x] bounded diagnostics correction
- [x] negative then positive tests
- [x] analyzer assessment and fresh web build
- [x] coordinator audit PASS

Audit: PASS. Coordinator and independent R2 source auditor verified seven invalidate+awaitread replacements preserve the same provider/future, guards/error boundaries, and nullable Strategy callback. Test-only const fixture changes have no data or behavioral change; existing fixture const canonicalization accepted as mechanical within affected test surface. Three negative cases passed before affected page positive coverage52/52; final Orders8 and auth stale-write1 passed. Analyzer exit1 with59 remaining diagnostics (13warnings46infos), no introduced refresh/null-aware diagnostics. Existing warning/import/parameter statements inspected against HEAD; unrelated warnings not fixed. Exact fresh RTK Flutter build web --no-pub exit0 after final edits,62.9seconds. Formatter infrastructure failed/stopped without writes; compilation/tests/build succeed. E0 Luna/high explicit spawn, effective UNVERIFIABLE. No protected/external changes. Final root repository build separately pending.
