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

Before this task may enter `EXECUTING`, the coordinator must spawn an `implementation_executor` with both Target Model and Target Effort explicitly supplied. Omitting either or inheriting a route is prohibited.

Dispatch Route Status: PENDING
Requested Model: PENDING
Requested Effort: PENDING
Observed Effective Model: unavailable
Observed Effective Effort: unavailable

## 2. Objective

A complete Binance adapter reads USD-M, Spot and Margin with signing, credentials, classification, valuation and scoped history, using fake transports.

Done when: All wallet mappings and failure classes pass against documented fixtures. No UI selection is exposed yet.

## 3. Preconditions

Predecessors: T117 = PASS; G1 complete. Decisions: D-009, D-010, P-005.
Required state: clean checkout on branch `codex/multi-platform-view-only`. Dispatch only after explicit approval of the currently presented plan.

## 4. Allowed Scope

- `lib/exchanges/binance/*`
- `lib/features/settings/domain/binance_credential_bundle.dart` (new)
- `lib/core/security/secure_storage_helper.dart` (new Binance keys and generation state mirroring OKX; do not alter OKX keys)
- `lib/core/exchange/*` (additions only)
- `test/exchanges/binance/*`, `test/core/security/*`

## 5. Forbidden Scope

Do not:
- read, search, parse, summarize or content-diff protected configuration, including `pubspec.yaml`, `pubspec.lock`, `analysis_options.yaml` and native project configuration;
- create, modify, regenerate or delete protected files, or add or remove dependencies;
- touch `backend/` or any git history, staging or branches;
- add any Binance or OKX write route;
- make opportunistic refactors or exceed the surface above.

If required work exceeds Allowed Scope, return `BLOCKED`.

## 6. Executor Contract

1. Sign with HMAC-SHA256 hex over the exact query, appending `signature` last; send `X-MBX-APIKEY`; `recvWindow` 5000; server time offset cached per host.
2. Allow only GET routes: `/fapi/v3/account`, `/fapi/v2/account`, `/fapi/v3/positionRisk`, `/fapi/v1/openOrders`, `/fapi/v1/allOrders`, `/api/v3/account`, `/api/v3/openOrders`, `/api/v3/allOrders`, `/sapi/v1/margin/account`, `/sapi/v1/margin/isolated/account`, `/sapi/v1/margin/openOrders`, `/sapi/v1/margin/allOrders`, plus the time routes. Adjust only as G1 records.
3. Inject platform; on web, Spot and Margin return `unavailableOnPlatform` with no request.
4. Read each wallet independently; merge into `AccountSnapshot`, computing valuation per spec section 6.
5. Classify errors per spec section 12. `-1021` resyncs and retries once. Back off on 429, `-1003` and 418 using `Retry-After`.
6. History: select at most 10 symbols in the required order and load sequentially, always sending `symbol`, no time window. Return coverage metadata.
7. Mirror the credential generation fence before and after each fetch. Never include secrets in errors.

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
