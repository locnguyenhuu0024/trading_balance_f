# Task 122 — Classify Binance request timeouts

Status: READY (dispatch pending; worktree must be clean)
Agent Role: implementation_executor
Executor Class: E0
Target Model: gpt-6-luna
Target Effort: high
Target Route: gpt-6-luna / high
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Plan: `docs/agents/plans/2026-10-28-binance-failure-visibility.md`
Plan Steps: T122 (D-012)
Acceptance Criteria: a Dio timeout is reported as `binance_timeout`, nothing else changes

## 1. Dispatch Compliance
Spawn an `implementation_executor` with both model `gpt-6-luna` and effort `high` supplied explicitly. No inherited route.
Dispatch Route Status: PENDING
Requested Model: gpt-6-luna
Requested Effort: high
Observed Effective Model: unavailable
Observed Effective Effort: unavailable

## 2. Objective
`BinanceDataClient` returns a `BinanceDataException` with code `binance_timeout` and a safe message (no URL, key, signature or body) when Dio fails with `DioExceptionType.connectionTimeout`, `sendTimeout` or `receiveTimeout`. Every other transport failure keeps its current code (`binance_network_error`, 418, 429, auth, timestamp, http error, cancel).

## 3. Preconditions
Predecessors: none. Decision D-012 approved.

## 4. Allowed Scope
Source: `lib/core/network/binance_data_client.dart` (classify timeouts in the same place that currently turns a response-less `DioException` into `_networkError()`, both in `_safeTransportFailure` and in the outer `on DioException` handlers; add one const factory next to `_networkError`).
Tests: `test/core/network/binance_data_client_test.dart`.

## 5. Forbidden Scope
No protected configuration/environment files read or modified. No dependency, lock or build change. Do not change time synchronization, retry logic, request coordination, signing, credential handling or timeouts' durations. No other files. No Git state changes. Do not edit canonical plans/tasks or telemetry.

## 6. Executor Contract
1. Add RED tests first and show them failing.
2. Implement the smallest change.
3. Re-run until green; do not weaken existing tests.
Preserved: all other error codes and messages; a timeout must not be retried as a timestamp error.

## 7. External Configuration / Environment Actions
None. Blocks verification: NO.

## 8. Tests
Table-driven: connect, send and receive timeout each yield `binance_timeout` for a public and a signed route; a response-less `connectionError` still yields `binance_network_error`; 418, 429, `-2015` and `-1021` behavior unchanged; the exception message and `toString()` contain none of: the API key, signature, query string, URL.

## 9. Mandatory Verification
### RED — RED-122
Command: `rtk flutter test --no-pub test/core/network/binance_data_client_test.dart`
Expected before the change: the new timeout cases fail (actual code `binance_network_error`); all existing cases pass.
Actual: PENDING
Status: PENDING

### GREEN — GREEN-122
Same command. Expected: all pass.
Actual: PENDING
Status: PENDING

Regression (V3): `rtk flutter test --no-pub test/core/exchange test/core/network`

### Task Buildability Gate
Required: YES
Affected canonical build unit: full Flutter application
Exact secret-free build command: `rtk flutter build web --no-pub`
Executed after the last task-local change: PENDING
Result: PENDING

### External Verification
Required: NO

## 10. Stop Conditions
Return `BLOCKED` if timeouts cannot be distinguished without changing request coordination or Dio options, or the change needs files outside section 4.

## 11. Execution Ledger
- [ ] dispatch role, class, model and effort match; no inherited route
- [ ] RED observed before the change
- [ ] GREEN observed
- [ ] V3 regression run
- [ ] task build after last change
- [ ] compact executor report returned
- [ ] no protected content read or modified

## 12. Coordinator Audit
PENDING
