# Task 54 — Backend quotes and per-order applied-strategy dashboard

Status: READY
Agent Role: implementation_executor
Executor Class: E1
Target Model: gpt-6-luna
Target Effort: xhigh
Target Route: gpt-6-luna / xhigh
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Dispatch Route Status: PENDING
Specification: `docs/agents/specs/2026-10-02-strategy-background-order-monitor.md`
Plan: `docs/agents/plans/2026-10-02-strategy-background-order-monitor.md`, P02
Requirements: REQ-004–005
Acceptance Criteria: AC-004–005

## 1. Objective and preconditions

Depends on T53 PASS. The applied-strategy dashboard obtains visible one-second last-price quotes only through authenticated backend API and displays individual order activation, partial fill quantity, scan freshness, and COMPLETED status. The strategy creation wizard and other screens keep their existing market-data paths.

Dispatch must explicitly bind `implementation_executor`, `gpt-6-luna`, and `xhigh`; no inherited route. Treat the backend quote contract in the spec as authoritative; do not invent a broader unauthenticated market proxy.

## 2. Allowed and forbidden scope

Allowed writes only: `backend/strategy.py`, `backend/tests/test_strategy_api.py`, `lib/features/strategy/data/strategy_api_client.dart`, `lib/features/strategy/presentation/providers/strategy_dashboard_provider.dart`, `lib/features/strategy/presentation/strategy_screen.dart`, `test/features/strategy/strategy_api_client_test.dart`, `test/features/strategy/strategy_dashboard_controller_test.dart`, `test/features/strategy/strategy_screen_test.dart`, `test/features/strategy/strategy_wizard_dialog_test.dart` (fake API interface only). No protected configuration, dependency, Docker, wizard product code, or other feature files; no live exchange writes, commit, push, or deploy. Do not edit task/plan/spec/telemetry files.

## 3. Executor contract

1. Add RED backend test for missing authenticated `GET /v1/strategies/{id}/quote` and RED Flutter test showing dashboard direct OKX ticker use and missing per-order fill status; observe failures before source change.
2. Add owned/applied-strategy quote endpoint with current account fingerprint and ownership revalidated on every request, exact instrument/positive Decimal price/exchange timestamp validation, ≤15-second age, safe auth/error envelope, and one-second public ticker response coalescing per instrument after identity validation. Do not cache account identity across requests. It performs no trade write.
3. Route dashboard quote timer through `StrategyApi`, preserving visible one-second cadence, deduplication, out-of-order and stale handling; no applied dashboard call to `StrategyMarketRepository.getTicker`. Do not alter wizard market calls.
4. Display each order's status and filled/planned contracts, average fill price when present, stale scan/error marker, and COMPLETED label. Preserve draft apply/delete and actual position/PnL presentation from backend list/result.

## 4. RED / GREEN and buildability

RED-004/005: backend quote unavailable; applied dashboard calls direct OKX and does not display per-order fill status. Record focused test failures before implementation.

GREEN-004/005: authenticated backend quote succeeds for owned applied strategy and rejects bad identity/stale quote; visible dashboard calls backend quote once per second, hidden dashboard does not poll; direct market ticker stub is never called by applied dashboard; order rows correctly distinguish partial/full/canceled/unknown and show exact filled quantity; wizard tests remain green. Run focused backend API and Flutter strategy controller/screen/client tests at V2/V3; broaden only on concrete related failure.

Task buildability REQUIRED after final code/test edit: `python3.12 -m compileall -q backend` for backend and `rtk flutter build web --release` for Flutter. Both must PASS before task PASS. No external configuration action within this task; the worker env/container action remains user-owned for production. Report exact RED/GREEN/build commands/results, changed files, no-trade safety, and route status.

## 5. Coordinator audit

Scope: PENDING. Backend auth/quote validation: PENDING. Applied-dashboard routing: PENDING. Wizard preserved: PENDING. Per-order UI/freshness: PENDING. RED-before-GREEN: PENDING. Task buildability: PENDING. Route compliance: PENDING. Verdict: PENDING.
