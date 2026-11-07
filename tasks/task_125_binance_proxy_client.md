# Task 125 — Binance client routes Spot and Margin through the web proxy

Status: PENDING
Agent Role: implementation_executor
Executor Class: E3
Target Model: gpt-6.1-terra
Target Effort: high
Target Route: gpt-6.1-terra / high
Routing Policy: EXECUTOR_ROUTING_POLICY.json v2 (OptCodex v1.4.0)
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Specification: `docs/agents/specs/2026-11-07-binance-web-proxy-design.md`
Plan: `docs/agents/plans/2026-11-07-binance-web-proxy.md`

## 1. Dispatch Compliance

The dispatcher passes `--model` and `model_reasoning_effort` on your command line, and your prompt states the route. `UNVERIFIABLE` is a valid state; do not stop for it.

Dispatch Route Status: UNVERIFIABLE
Requested Model: gpt-6.1-terra
Requested Effort: high

## 2. Objective

On web with `BINANCE_PROXY_URL` set, Spot and Margin private reads go through the proxy; otherwise behavior is unchanged.

Done when: Tests prove routing, no secret in requests, and unchanged no-proxy behavior.

Complete the work in this run; a long run is normal. Ending without file changes is a failed attempt.

## 3. Preconditions

Predecessors: Approved plan. The user approved this plan and told the coordinator to proceed. The VPS check is a user-owned gate before deployment and does not block this code.

## 4. Allowed Scope

Exact write list. Read access covers all non-protected source and tests.

- `lib/exchanges/binance/binance_private_client.dart`
- `lib/exchanges/binance/binance_reader.dart`
- `lib/exchanges/binance/binance_adapter.dart`
- `lib/features/connections/binance_connection_form.dart`
- `test/exchanges/binance/binance_private_client_test.dart`
- `test/exchanges/binance/binance_reader_test.dart`
- `test/exchanges/binance/binance_history_test.dart`
- `test/exchanges/binance/binance_adapter_test.dart`
- `test/features/connections/binance_connection_form_test.dart`

## 5. Forbidden Scope

Do not read or change protected configuration, `backend/` or Git state. No new dependency, no write route, no file outside the list.

## 6. Executor Contract

1. `binanceProxyBaseUrlProvider`: `const String.fromEnvironment('BINANCE_PROXY_URL')`, trimmed of a trailing slash; a value that is not `https`, or that has a query or fragment, counts as empty. `binanceSpotMarginAvailableProvider`: not web, or proxy non-empty.
2. `BinancePrivateClient` gains `proxyBaseUrl` and `spotMarginAvailable`. On web with a proxy, a private `/api/v3/*` or `/sapi/*` request uses `<proxy><path>?<signed query>` with the same headers. `/fapi/*` and the time routes stay direct. Native ignores the proxy. Without a proxy on web, those routes keep returning `unavailableOnPlatform` with no request.
3. Replace `client.isWeb` gates in `binance_reader.dart` with `client.spotMarginAvailable`. The app-only issue is added only when unavailable.
4. The connection test in `binance_connection_form.dart` tries Spot and Margin when available.
5. Classify `451` and `403` as `other`. Each wallet already fails independently; keep that.

Mechanism details are yours if they satisfy these and the tests; report what you chose. Stop only for a conflict about product behavior.

## 7. External Configuration / Environment Actions

Planned action: user-owned nginx location and build flag, in `docs/deployment/binance-read-proxy.md`. Blocks this task: NO.

## 8. Tests

- TEST-125-1: web with proxy: Spot and Margin hosts are the proxy, the path is intact, the signature verifies over the sent query, `X-MBX-APIKEY` present, secret absent from URL and headers.
- TEST-125-2: `/fapi/*` and time stay direct.
- TEST-125-3: web without proxy: zero Spot or Margin requests.
- TEST-125-4: native with proxy configured: direct to Binance.
- TEST-125-5: invalid proxy values count as empty.
- TEST-125-6: `451` on Spot leaves USD-M and a partial total.

## 9. Mandatory Verification

### RED — RED-125
Scenario: Web without proxy, invalid proxy values, and `451` from the proxy.
Expected: No Spot or Margin request where unavailable; with `451`, USD-M present and total partial.
Status: PENDING

### GREEN — GREEN-125
Scenario: Web with proxy using fixture responses; worked example from the parent spec.
Expected: Total `1660.50`, all Spot and Margin requests on the proxy host, secret never sent.
Status: PENDING

Verification ceiling: V3: `test/exchanges/binance`, `test/features/connections`.

### Verification environment

Confirmed by the coordinator: this sandbox cannot run `flutter test`, because the test runner cannot bind 127.0.0.1, and the default SDK cache is not writable. Do not spend time on this and do not stop for it.

- Write the complete code and tests. Do not run `flutter test`.
- Compile checks are not available in the sandbox; the coordinator runs them on the host. Set `buildability` to `BLOCKED` with that reason and `status` to `COMPLETED`.
- In your report set `red` and `green` to `NOT_RUN`, naming the exact tests and the order RED then GREEN. Set `status` to `COMPLETED`.
- The coordinator executes RED then GREEN on the host during audit and returns any failure as a bounded remediation.

### Conflict rule

If a sentence in this contract conflicts with how OKX behaves today, REQ-012 wins: keep the existing OKX behavior, implement the rest, and name the conflict in your summary. Stop only if the conflict affects something other than OKX preservation.

### Task Buildability Gate

Required: YES
Exact secret-free build command: `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings && flutter build web --no-pub`
Result: PENDING

## 10. Stop Conditions

Return `BLOCKED` if the fix needs a file outside the list.

## 11. Coordinator Audit

Verdict: PENDING
