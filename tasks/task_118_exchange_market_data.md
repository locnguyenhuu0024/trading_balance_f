# Task 118 — Analysis screens and Binance public market

Status: PENDING
Agent Role: implementation_executor
Executor Class: E3
Target Model: gpt-6.1-terra
Target Effort: high
Target Route: gpt-6.1-terra / high
Routing Policy: EXECUTOR_ROUTING_POLICY.json v2 (OptCodex v1.4.0)
Route Rationale: Multi-module integration across three analysis features with an established adapter contract.
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Specification: `docs/agents/specs/2026-11-07-multi-platform-view-only-design.md`
Plan: `docs/agents/plans/2026-11-07-multi-platform-view-only.md`
Plan Steps: P03
Requirements: REQ-008
Acceptance Criteria: AC-008

## 1. Dispatch Compliance

Before this task may enter `EXECUTING`, the coordinator must spawn an `implementation_executor` with both Target Model and Target Effort explicitly supplied. Omitting either or inheriting a route is prohibited.

Dispatch Route Status: PENDING
Requested Model: PENDING
Requested Effort: PENDING
Observed Effective Model: unavailable
Observed Effective Effort: unavailable

## 2. Objective

Market, BMAG and Support/Resistance read the selected exchange with Binance public data and per-exchange watchlists.

Done when: With scope set to Binance by provider override, these screens show Binance data and source copy, and OKX behavior is unchanged.

## 3. Preconditions

Predecessors: T117 = PASS. Decisions: D-005.
Required state: clean checkout on branch `codex/multi-platform-view-only`. Plan revision 2 approved.

## 4. Allowed Scope

- `lib/exchanges/binance/binance_client.dart` (new, public GET allowlist only)
- `lib/exchanges/binance/binance_market.dart` (new)
- `lib/exchanges/okx/okx_adapter.dart`
- `lib/core/exchange/*` (market contract additions)
- `lib/features/market/**`, `lib/features/fractal_tracker/**`, `lib/features/support_resistance/**`
- `lib/core/network/okx_websocket_service.dart` only if a neutral ticker seam requires it
- Related tests under `test/features/{market,fractal_tracker,support_resistance}`, `test/exchanges/binance/*` (new)

## 5. Forbidden Scope

Do not:
- read, search, parse, summarize or content-diff protected configuration, including `pubspec.yaml`, `pubspec.lock`, `analysis_options.yaml` and native project configuration;
- create, modify, regenerate or delete protected files, or add or remove dependencies;
- touch `backend/` or any git history, staging or branches;
- add any Binance or OKX write route;
- make opportunistic refactors or exceed the surface above.

If required work exceeds Allowed Scope, return `BLOCKED`.

## 6. Executor Contract

1. Add catalog, ticker and candle methods; Binance uses `/fapi/v1/exchangeInfo`, `/api/v3/exchangeInfo`, `/fapi/v1/ticker/24hr`, `/api/v3/ticker/24hr`, `/fapi/v1/klines`, `/api/v3/klines`, with no API key header.
2. Move symbol shapes behind `InstrumentKey`; OKX parsing stays in the OKX adapter.
3. Page Binance candles with `startTime` and `endTime` for BMAG ranges.
4. Keep `support_resistance_watchlist_snapshot` for OKX; add a separate Binance key; provider keyed by exchange.
5. Replace the swallowed catch in `fractal_provider.dart` with a surfaced failure state.
6. Add `Nguồn giá: <exchange>` to the three screens using existing layouts.
7. Binance candle arrays parse by documented index: open time, open, high, low, close, volume.

Required invariants and edges: INV-002, INV-006; OKX REQ-012.
Apply reuse-first, minimal complete changes. Do not invent product semantics. If the contract is insufficient, return `BLOCKED`.

## 7. External Configuration / Environment Actions

Planned action: none.
Blocks verification until user applies: NO

## 8. Tests

- TEST-118-1: candle failure surfaces.
- TEST-118-2: separate watchlists.
- TEST-118-3: Binance symbol path.

## 9. Mandatory Verification

### RED — RED-118a/b
Scenario: (a) Candle read fails on fractal provider. (b) Binance `BTCUSDT` through S/R with an OKX watchlist already stored.
Command/method: `rtk flutter test --no-pub <file> --plain-name '<name>'`
Expected: (a) Error state, not empty data. (b) No `-USDT` parsing used, no public request has an API key header, OKX watchlist bytes unchanged.
Actual: PENDING
Status: PENDING

### GREEN — GREEN-118
Scenario: Scope Binance with fixture responses for USD-M and Spot.
Command/method: `rtk flutter test --no-pub <file> --plain-name '<name>'`
Expected: Market rows, BMAG fractals and S/R levels computed from fixtures with hand-derived expected values; source copy names Binance.
Actual: PENDING
Status: PENDING

Run RED before GREEN. Verification ceiling: V3: `test/features/{market,fractal_tracker,support_resistance}`, `test/exchanges/binance`.
Escalate only if: a shared provider or fixture used outside this set changes.

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
