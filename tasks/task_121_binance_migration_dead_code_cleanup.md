# Task 121 — Remove dead code left by the Binance migration

Status: PASS (independent audit 2026-10-27)
Agent Role: implementation_executor
Executor Class: E0
Target Model: gpt-6-luna
Target Effort: high
Target Route: gpt-6-luna / high
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Specification: `docs/agents/specs/2026-10-25-binance-direct-reads-design.md`
Plan: `docs/agents/plans/2026-10-27-binance-direct-reads-remediation.md`
Plan Steps: P02
Requirements: Ponytail minimal complete change (no new behavior)
Acceptance Criteria: RAC-004 (AUD-004)

## 1. Dispatch Compliance
Spawn an `implementation_executor` with both model `gpt-6-luna` and effort `high` supplied explicitly. No inherited route.
Dispatch Route Status: DISPATCHED via scripts/ccb/dispatch.py, attempt fd75e6fc75d742a9bc0afba5c87b8d57
Requested Model: gpt-6-luna
Requested Effort: high
Observed Effective Model: unavailable
Observed Effective Effort: unavailable

## 2. Objective
Delete only the unused code and imports that the migration left behind. No behavior change.
Done when: the 10 findings below no longer appear in the analyzer output, related tests pass and the web build passes.

## 3. Preconditions
Predecessors: T120 = PASS (shared file `binance_exchange_reader.dart`).
Decisions: none beyond plan approval.

## 4. Allowed Scope
Source, remove only the listed items:
- `lib/core/exchange/binance_exchange_reader.dart`: unused import `binance_read_routes.dart` (line 8)
- `lib/core/exchange/exchange_quote_service.dart`: unused import `binance_read_routes.dart` (line 9)
- `lib/core/network/binance_data_client.dart`: unused local `response` in `_performTimeSync` (line 345); keep the awaited call
- `lib/features/orders/presentation/orders_screen.dart`: unreferenced `_buildEmptyState` (line 1045)
- `lib/features/portfolio/presentation/portfolio_details_screen.dart`: unused import `providers/portfolio_provider.dart` (line 19), unused local `amount` (line 354), unreferenced `_DetailsContent` (line 488)
- `lib/features/portfolio/presentation/portfolio_screen.dart`: unused import `providers/portfolio_provider.dart` (line 18), unreferenced `_buildPortfolioData` (line 686), `_buildErrorState` (line 1058)

Line numbers are from the audit baseline and shift after T120. Match by symbol. Also remove private helpers or imports that these removals orphan, only in these six files and only when the analyzer flags them. No test files.

## 5. Forbidden Scope
Do not read, search within, parse or modify protected configuration/environment files. No dependency, lock or build change. Do not touch pre-existing findings (`order_cancellation_flow_provider.dart` `!` warnings, `strategy_dashboard_provider.dart` catch clause), analyzer `info` lints, or test files. No behavior, formatting-only churn or refactors. No Git state changes. Do not edit canonical plans/tasks/status or telemetry.

## 6. Executor Contract
1. Record the analyzer baseline (RED) before editing.
2. Remove the items in section 4.
3. Re-run the analyzer on the same files; remove only newly orphaned private items it flags.
4. If any target is still referenced, stop and report `BLOCKED`.
Preserved: all runtime behavior, public APIs, test expectations.

## 7. External Configuration / Environment Actions
None. Blocks verification: NO.

## 8. Tests
No new tests; static analysis is the RED/GREEN basis and the existing suites are the regression guard.

## 9. Mandatory Verification
### RED — RED-121
Command: `rtk flutter analyze --no-pub lib/core/exchange/binance_exchange_reader.dart lib/core/exchange/exchange_quote_service.dart lib/core/network/binance_data_client.dart lib/features/orders/presentation/orders_screen.dart lib/features/portfolio/presentation/portfolio_details_screen.dart lib/features/portfolio/presentation/portfolio_screen.dart`
Expected before edits: the 10 warnings in section 4 (unused_import x4, unused_local_variable x2, unused_element x4). Pre-existing `info` lints may also print and are ignored.
Actual: PENDING
Status: PENDING

### GREEN — GREEN-121
Same command. Expected: no `unused_import`, `unused_local_variable` or `unused_element` warning remains in those files.
Actual: PENDING
Status: PENDING

Regression (V3): `rtk flutter test --no-pub test/core/exchange test/core/network/binance_data_client_test.dart test/features/portfolio test/features/orders`

### Task Buildability Gate
Required: YES
Affected canonical build unit: full Flutter application
Exact secret-free build command: `rtk flutter build web --no-pub`
Executed after the last task-local change: PENDING
Result: PENDING

### External Verification
Required: NO

## 10. Stop Conditions
Return `BLOCKED` if a removal target is still referenced, if removal needs edits outside the six files, or the analyzer baseline differs materially from section 4 (report the difference).

## 11. Execution Ledger
- [ ] dispatch role, class, model and effort match; no inherited route
- [ ] RED baseline recorded before edits
- [ ] removals done, GREEN observed
- [ ] V3 regression run
- [ ] task build after last change
- [ ] compact executor report returned
- [ ] no protected content read or modified

## 12. Coordinator Audit
Scope: only the 6 allowed files changed, none staged, no test or protected file touched; deletions only (1 insertion-free line edit in binance_data_client.dart).
RAC-004: the 10 listed warnings are gone; the executor also removed items orphaned by those removals (`_PnlBlock`, `_BalanceTile`, `_DetailsState`, `_buildAssetSummary`, imports `intl`, `okx_balance_model`) in the allowed files only. No remaining reference to any removed symbol (grep over lib). `flutter analyze lib`: 49 -> 39 issues; the remaining warnings are the 3 pre-existing out-of-scope ones.
Independent runs: regression group 237 passed; full `rtk flutter test --no-pub` 671 passed (664 baseline + 7 from T120); `rtk flutter build web --no-pub` exit 0 after the last change.
Limitations: `git diff --check` reports a trailing blank line at EOF in `portfolio_details_screen.dart` (cosmetic, not fixed by the coordinator); effective executor route UNVERIFIABLE.
Verdict: PASS
