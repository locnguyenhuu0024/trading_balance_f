# Task 122 — Classify Binance request timeouts

Status: PASS (independent audit 2026-10-28)
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
Dispatch Route Status: DISPATCHED via scripts/ccb/dispatch.py, attempt ff0029b30dd14d8ab6dd7fd0d25a5e0e
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
Actual: independent run on the old client: only 'classifies Dio timeouts on public and signed routes safely' failed; the connection-error case and 26 others passed
Status: PASS

### GREEN — GREEN-122
Same command. Expected: all pass.
Actual: 28 passed
Status: PASS

Regression (V3): `rtk flutter test --no-pub test/core/exchange test/core/network`

### Task Buildability Gate
Required: YES
Affected canonical build unit: full Flutter application
Exact secret-free build command: `rtk flutter build web --no-pub`
Executed after the last task-local change: YES
Result: PASS (exit 0)

### External Verification
Required: NO

## 10. Stop Conditions
Return `BLOCKED` if timeouts cannot be distinguished without changing request coordination or Dio options, or the change needs files outside section 4.

## 11. Execution Ledger
- [x] dispatch role, class, model and effort match; no inherited route
- [x] RED observed before the change
- [x] GREEN observed
- [x] V3 regression run
- [x] task build after last change
- [x] compact executor report returned
- [x] no protected content read or modified

## 12. Coordinator Audit
Scope: only the two allowed files changed, none staged, no protected file touched. Client change: `_isTimeout`/`_timeoutError` added; timeouts classified in `_safeTransportFailure` and in both outer `on DioException` handlers; every other branch and the -1021 retry path are untouched.
AC: connect, send and receive timeouts on a public and a signed route give `binance_timeout` with a constant safe message; a response-less `connectionError` stays `binance_network_error`.
Independent runs: RED against the old client (new timeout test fails, rest pass), GREEN 28 passed, V3 `test/core/exchange test/core/network` 129 passed, full suite 673 passed (671 + 2), `rtk flutter build web --no-pub --release` exit 0, `git diff --check` clean. Analyzer on the client shows only the pre-existing `prefer_null_aware_operators` info at line 558.
Limitations: the sentinel assertions in the new test check `fixture-binance-api-key` while the injected Dio message uses `fixture-api-key`, so that leak check is weak; the message is a constant so no leak is possible by construction. Effective executor route UNVERIFIABLE.
Verdict: PASS
