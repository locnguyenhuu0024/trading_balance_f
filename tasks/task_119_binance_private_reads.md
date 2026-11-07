# Task 119 — Binance private reads

Status: PENDING
Agent Role: implementation_executor
Executor Class: E3
Target Model: gpt-6.1-terra
Target Effort: high
Target Route: gpt-6.1-terra / high
Routing Policy: EXECUTOR_ROUTING_POLICY.json v2 (OptCodex v1.4.0)
Route Rationale: Multi-module adapter with explicit invariants and fake transports; the contract already resolves signing, classification and valuation. Escalate to E4 only on observed evidence.
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Specification: `docs/agents/specs/2026-11-07-multi-platform-view-only-design.md`
Plan: `docs/agents/plans/2026-11-07-multi-platform-view-only.md`
Plan Steps: P04
Requirements: REQ-006, REQ-007
Acceptance Criteria: AC-006, AC-007

## 1. Dispatch Compliance

Before this task may enter `EXECUTING`, the coordinator must spawn an `implementation_executor` with both Target Model and Target Effort explicitly supplied. Omitting either or inheriting a route is prohibited. The coordinator has done this: the dispatcher passes `--model` and `model_reasoning_effort` on your command line, and your prompt states the route. You cannot observe more than that from inside the run, and `UNVERIFIABLE` is a valid state. Do not stop for it; start the task.

Dispatch Route Status: UNVERIFIABLE (explicitly bound by `scripts/ccb/dispatch.py`, runtime does not expose the effective route)
Requested Model: gpt-6.1-terra
Requested Effort: high
Observed Effective Model: unavailable
Observed Effective Effort: unavailable

## Stage instruction (current)

This task runs in stages because long runs have ended early. Stage 1 is committed: keys, signing, private client and classification are tested.

**Current stage 2 of 3, do only this:** steps 3, 4, 5, 6 and 8 of section 6.

- `exchange_models.dart`: add `MarginAccountRow` and `AccountSnapshot.marginRows`.
- `binance_market.dart` and `binance_client.dart`: add `/api/v3/ticker/price` for valuation prices.
- `binance_reader.dart`: wallet reads, valuation, positions, pending orders.
- `binance_adapter.dart`: `BinanceAdapter implements ExchangeAdapter`, plus a provider building `BinancePrivateClient` from stored keys, using `exchangeRequestCoordinatorProvider(ExchangeId.binance)` and `kIsWeb` by default with an injectable platform flag.

Tests in `binance_reader_test.dart` and `binance_adapter_test.dart`: fixtures USD-M USDT marginBalance `1000.50`, Spot BTC `0.01` at `76000`, Spot USDT `100`, cross ETH netAsset `-0.1` at `2000` give total `1660.50`, not partial; with cross failing, `1860.50`, partial. `-2015` on all wallets is terminal; `-2015` on Margin only leaves the others with a notice and a partial total. An unpriced asset such as `LDUSDT` stays listed and makes the total partial. Web: zero Spot or Margin requests. USD-M position joins `leverage` and `isolated` from `/fapi/v2/account`, with a missing field staying null. Isolated margin row maps `liquidatePrice` and `marginLevel`.

No history in this stage. Finish by returning the structured report.

## 2. Objective

A complete Binance adapter reads USD-M, Spot and Margin with signing, credentials, classification, valuation and scoped history, using fake transports.

Done when: All wallet mappings and failure classes pass against documented fixtures. No UI selection is exposed yet.

Complete the work in this run; a long run is normal. Ending without file changes is a failed attempt.

## 3. Preconditions

Predecessors: T117, T118 = PASS; G1 closed. Decisions: D-009, D-010, P-005.
Required state: clean checkout on branch `codex/multi-platform-view-only`. Plan revision 2 approved.

## 4. Allowed Scope

Exact write list across stages (new files use exactly these names); each stage may narrow it. Read access covers all non-protected source and tests.

- `lib/core/security/secure_storage_helper.dart`
- `lib/main.dart`
- `lib/core/exchange/exchange_scope.dart`
- `lib/exchanges/binance/binance_private_client.dart`
- `test/exchanges/binance/binance_private_client_test.dart`
- `lib/exchanges/binance/binance_reader.dart`
- `lib/exchanges/binance/binance_adapter.dart`
- `lib/core/exchange/exchange_models.dart`
- `test/exchanges/binance/binance_reader_test.dart`
- `test/exchanges/binance/binance_adapter_test.dart`
- `test/exchanges/binance/binance_history_test.dart`

## 5. Forbidden Scope

Do not:
- read, search, parse, summarize or content-diff protected configuration, including `pubspec.yaml`, `pubspec.lock`, `analysis_options.yaml` and native project configuration;
- create, modify, regenerate or delete protected files, or add or remove dependencies;
- touch `backend/` or any git history, staging or branches;
- add any Binance or OKX write route;
- make opportunistic refactors or exceed the surface above.

If required work exceeds Allowed Scope, return `BLOCKED`.

## 6. Executor Contract

Design is fixed; mechanism details are yours if they satisfy the invariants and tests. Report what you chose. Stop only for a conflict about product behavior.

1. Sign with HMAC-SHA256 hex over the exact query string, appending `signature` last. Send `X-MBX-APIKEY`, `recvWindow=5000`, `timestamp` from a per-host server time offset using `/fapi/v1/time` and `/api/v3/time`. Use the `crypto` package already imported by `okx_interceptor.dart`. Add no dependency.
2. GET-only allowlist: `/fapi/v3/account`, `/fapi/v2/account`, `/fapi/v3/positionRisk`, `/fapi/v1/openOrders`, `/fapi/v1/allOrders`, `/api/v3/account`, `/api/v3/openOrders`, `/api/v3/allOrders`, `/sapi/v1/margin/account`, `/sapi/v1/margin/isolated/account`, `/sapi/v1/margin/openOrders`, `/sapi/v1/margin/allOrders`, plus time routes. No write route may exist. Inject the platform; on web, Spot and Margin routes return `unavailableOnPlatform` with no request. Classify per spec section 12: 401, `-2014`, `-2015`, `-2008` credential; `-1021` resync and retry once; `-1022` terminal; 429, `-1003` transient with `Retry-After`; 418 long backoff; 5xx and network transient.
3. Wallets are read independently: USD-M `/fapi/v3/account`, Spot `/api/v3/account?omitZeroBalances=true`, cross `/sapi/v1/margin/account`, isolated `/sapi/v1/margin/isolated/account`. One failing leaves the others and marks the total partial. Value each row per spec section 6, pricing from `/api/v3/ticker/price` added to the public client allowlist through `binance_market.dart`, with stablecoin USDT as 1. An unpriced row stays listed, excluded from the total, total partial. Hide zero rows. On web the snapshot records USD-M only.
4. `AccountSnapshot` gains `marginRows`: `MarginAccountRow` for cross (per asset with non-zero net or borrowed) and isolated (per pair with base and quote net, borrowed, interest, `marginLevel`, `marginRatio`, `liquidatePrice`, `indexPrice`).
5. USD-M positions: `/fapi/v3/positionRisk`, non-zero `positionAmt`. Leverage and margin mode come from `/fapi/v2/account` position rows (`leverage`, `isolated`), joined on symbol and position side. Any missing field stays null. Base and quote come from `exchangeInfo`, never parsed from a display label.
6. Pending orders: `/fapi/v1/openOrders` without symbol; `/api/v3/openOrders` without symbol; `/sapi/v1/margin/openOrders` without symbol for cross; with `symbol` and `isIsolated=TRUE` per held isolated pair. Respect `orderFilterProvider` values: `SWAP` is USD-M, `SPOT`, `MARGIN`, `ALL`.
7. History per D-010: select at most 10 symbols in this order: open positions, held assets by descending value, Binance watchlist. Load sequentially, always sending `symbol`, no time window, `limit=100`. Return coverage metadata naming the symbols.
8. `binance_adapter.dart`: `BinanceAdapter implements ExchangeAdapter`, using `BinanceMarket` for `market`. Do not register it in the default registry; T120 does.

Required invariants and edges: INV-003, INV-004, INV-006; EDGE-004..008, EDGE-010.
Apply reuse-first, minimal complete changes. Do not invent product semantics. If the contract is insufficient, return `BLOCKED`.

## 7. External Configuration / Environment Actions

Planned action: none.
Blocks verification until user applies: NO

## 8. Tests

- TEST-119-1: signature against the published Binance HMAC example.
- TEST-119-2: valuation worked example.
- TEST-119-3: web no-request.
- TEST-119-4: classification.
- TEST-119-5: history selection.

## 9. Mandatory Verification

### RED — RED-119a/b/c/d
Scenario: (a) `-2015` on all wallets. (b) `-2015` on Margin only, USD-M succeeds. (c) Platform web. (d) `-1021` twice. Also a credential rotation mid-read.
Command/method: `rtk flutter test --no-pub <file> --plain-name '<name>'`
Expected: (a) Terminal expired, no retry. (b) Not expired, Margin notice, total partial. (c) Zero Spot or Margin requests. (d) Exactly one retry then failure. Rotated read is dropped.
Actual: PENDING
Status: PENDING

### GREEN — GREEN-119
Scenario: Fixtures: USD-M USDT marginBalance 1000.50; Spot BTC 0.01 at 76000 and USDT 100; cross ETH netAsset -0.1 at 2000.
Command/method: `rtk flutter test --no-pub <file> --plain-name '<name>'`
Expected: Total 1660.50, not partial. With cross failing, 1860.50 partial. History requests the expected symbols in order, capped at 10.
Actual: PENDING
Status: PENDING

Run RED before GREEN. Verification ceiling: V3: `test/exchanges/binance`, `test/core/security`, `test/core/exchange`.
Escalate only if: a shared provider or fixture used outside this set changes.

### Verification environment

Confirmed by the coordinator: this sandbox cannot run `flutter test`, because the test runner cannot bind 127.0.0.1, and the default SDK cache is not writable. Do not spend time on this and do not stop for it.

- Write the complete code and tests. Do not run `flutter test`.
- For a compile check, use `env HOME=/private/tmp/claude-501/-Users-locnguyen--claude-spares-spare-1YiVQu/74faedd6-f84d-41fb-aa01-a0288d74204a/scratchpad/flutter-home PUB_CACHE=/Users/locnguyen/.pub-cache /private/tmp/claude-501/-Users-locnguyen--claude-spares-spare-1YiVQu/74faedd6-f84d-41fb-aa01-a0288d74204a/scratchpad/flutter-sdk/bin/flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings`, and `env HOME=/private/tmp/claude-501/-Users-locnguyen--claude-spares-spare-1YiVQu/74faedd6-f84d-41fb-aa01-a0288d74204a/scratchpad/flutter-home PUB_CACHE=/Users/locnguyen/.pub-cache /private/tmp/claude-501/-Users-locnguyen--claude-spares-spare-1YiVQu/74faedd6-f84d-41fb-aa01-a0288d74204a/scratchpad/flutter-sdk/bin/flutter build web --no-pub` for buildability.
- In your report set `red` and `green` to `NOT_RUN`, naming the exact tests and the order RED then GREEN. Set `status` to `COMPLETED`.
- The coordinator executes RED then GREEN on the host during audit and returns any failure as a bounded remediation.

### Conflict rule

If a sentence in this contract conflicts with how OKX behaves today, REQ-012 wins: keep the existing OKX behavior, implement the rest, and name the conflict in your summary. Stop only if the conflict affects something other than OKX preservation.

### Task Buildability Gate

Required: YES
Affected canonical build unit: Flutter app `lib/` and `test/`
Exact secret-free build command: `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings && flutter build web --no-pub`
Executed after the last task-local change: PENDING
Result: PENDING

### External Verification

Required: NO for this task. The program's user-run live check follows the final audit.

## 10. Stop Conditions

Return `BLOCKED` when repository evidence contradicts this contract, a design decision is missing, a dependency appears necessary, scope is exceeded, or verification is unavailable. Report evidence, affected IDs, and the coordinator decision needed.

## 11. Execution Ledger

- [ ] confirm route binding
- [ ] inspect referenced symbols
- [ ] implement assigned step
- [ ] add or update tests
- [ ] execute formal RED, then GREEN
- [ ] run buildability gate after last change
- [ ] return compact executor report
- [ ] confirm no protected content read or modified

## 12. Coordinator Audit

Verdict: PENDING
