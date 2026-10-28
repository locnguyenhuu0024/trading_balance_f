# Task 123 — Curated Binance failure messages

Status: READY (T122 = PASS, committed in 3ed75c5; first dispatch attempt c6dba1b3d7ca42c090284b3ac80aaddc was a false BLOCKED)
Agent Role: implementation_executor
Executor Class: E1
Target Model: gpt-6-luna
Target Effort: xhigh
Target Route: gpt-6-luna / xhigh
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Plan: `docs/agents/plans/2026-10-28-binance-failure-visibility.md`
Plan Steps: T123 (D-011, D-013)
Acceptance Criteria: each Binance failure code shows the section 4 copy of the plan; a failing source never hides other sources

## 1. Dispatch Compliance
Spawn an `implementation_executor` with both model `gpt-6-luna` and effort `xhigh` supplied explicitly. No inherited route.
Dispatch Route Status: PENDING
Requested Model: gpt-6-luna
Requested Effort: xhigh
Observed Effective Model: unavailable
Observed Effective Effort: unavailable

## 2. Objective
In `lib/core/exchange/exchange_account_providers.dart`, `_safeReadError` returns curated, safe English copy for `ExchangeReadException` codes from Binance instead of the raw client message. `ExchangeAccountResult` keeps its shape. `_isTerminalReadFailure` semantics are unchanged.

Copy (exact text is the contract; codes that are not listed use the safe generic fallback `The exchange account data is unavailable. Retry the account read.`):
- `binance_network_error`: `Cannot reach Binance. Check your connection and retry.`; when `kIsWeb` is true: `Cannot reach Binance from this browser. Check your connection; browser or network restrictions may also block requests.` Never mention CORS as the cause.
- `binance_timeout`: `Binance did not respond in time. Retry in a moment.`
- `binance_rate_limited`: `Binance rate limit reached. Retry shortly.`
- `binance_ip_banned`: `Binance temporarily blocked reads from this network. Retry later.`
- `binance_host_paused` and `binance_budget_metadata_unavailable`: `Binance reads are paused. Retry after HH:mm.` using the local time of a future `retryAt` (24-hour `HH:mm`, no new dependency); `Binance reads are paused. Retry later.` when `retryAt` is null or not in the future.
- `binance_authentication_failed`: `Binance rejected the API key. Check the key, secret and permissions.`
- `binance_timestamp_invalid`: `Binance rejected the request time. Check your device clock and retry.`
- `binance_http_error`, `binance_api_error`, `binance_invalid_response`: `Binance could not complete the request. Retry later.`
- `binance_credentials_required`, `binance_credentials_unavailable`, `request_cancelled`, `credentials_changed`: keep today's behavior (message as now).
OKX errors and `DioException` text are unchanged.

## 3. Preconditions
Predecessors: T122 = PASS and already committed. The code `binance_timeout` exists in `lib/core/network/binance_data_client.dart` (`_timeoutError`, read-only for this task; it is outside the allowed write scope on purpose) and is tested in `test/core/network/binance_data_client_test.dart`. Do not treat its absence from the allowed files as a missing predecessor. Decisions D-011 and D-013 approved.

## 4. Allowed Scope
Source: `lib/core/exchange/exchange_account_providers.dart`.
Tests: `test/features/portfolio/combined_exchange_portfolio_test.dart` (and `test/core/exchange/exchange_readers_test.dart` only if needed).

## 5. Forbidden Scope
No protected configuration/environment files read or modified. No dependency, lock or build change. No widget, screen, `ExchangeAccountResult` shape, reader, client, request-coordinator, signing or credential change. No OKX behavior change. No Git state changes. Do not edit canonical plans/tasks or telemetry.

## 6. Executor Contract
1. Add RED tests first and show them failing.
2. Implement the smallest change.
3. Keep messages free of any key, signature, URL or response body; unknown codes never echo `ExchangeReadException.message`.
If a screen cannot render the mapped string without a widget change, stop with `BLOCKED`.

## 7. External Configuration / Environment Actions
None. Blocks verification: NO. Live Binance and browser behavior stay unverified.

## 8. Tests
Drive failures through the provider path with a fake reader throwing `ExchangeReadException` (and with `DioException` for the generic path). Cover: every listed code; `retryAt` in the future (shown HH:mm), null and in the past (no time); unknown code and a hostile `message` containing sentinel key, signature, URL and body text that must not appear in `result.error` or in the warning string; `isTerminalFailure` unchanged; a Binance Spot failure with a successful OKX source and a successful Binance Futures source leaves those sources present with `isPartial` true; the `kIsWeb` variant is covered only if the mapping can be tested without changing Flutter platform globals, otherwise state that gap in the report.

## 9. Mandatory Verification
### RED — RED-123
Command: `rtk flutter test --no-pub test/features/portfolio/combined_exchange_portfolio_test.dart`
Expected before the change: the new copy and sentinel cases fail; existing cases pass.
Actual: PENDING
Status: PENDING

### GREEN — GREEN-123
Same command. Expected: all pass.
Actual: PENDING
Status: PENDING

Regression (V3): `rtk flutter test --no-pub test/core/exchange test/core/network test/features/portfolio test/features/orders`

### Task Buildability Gate
Required: YES
Affected canonical build unit: full Flutter application
Exact secret-free build command: `rtk flutter build web --no-pub`
Executed after the last task-local change: PENDING
Result: PENDING

### External Verification
Required: NO

## 10. Stop Conditions
Return `BLOCKED` if scope must grow past section 4, if T122's code is absent, or the copy cannot reach the UI as a string.

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
