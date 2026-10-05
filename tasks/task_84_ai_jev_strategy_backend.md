# Task 84 — Jev Strategy Candidate Draft Backend

Status: PASS
Agent Role: implementation_executor
Executor Class: E2
Target Model: gpt-6-luna
Target Effort: max
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Dispatch Route Status: UNVERIFIABLE
Specification: docs/agents/specs/2026-10-05-ai-jev-auto-strategy.md
Plan: docs/agents/plans/2026-10-05-ai-jev-auto-strategy.md
Plan Steps: P01
Requirements/Acceptance: REQ-002–006 / AC-002–006
Predecessors: none

## Allowed write surfaces

backend/strategy.py; backend/okx.py (public candle wrapper only); new backend/strategy_levels.py; new backend/strategy_jev.py; new backend/strategy_automatic.py if cohesive; backend/tests/test_strategy_automatic.py and related new permitted fixtures/tests; docs/development/ai-jev-strategy.md. Audit remediation additionally permits backend/service.py business dispatch/session-validator wiring only; never RuntimeSettings/configuration sections. Existing backend tests may be adjusted only when necessary to verify this contract. No manifests/env/container/build/CI, credentials/helper changes, task/status/telemetry edits, unrelated refactors, commit/push or live external calls.

## Contract

Implement specification APIs/JSON contracts precisely. Source parity is lib/features/strategy/domain/strategy_calculator.dart, not watchlist algorithm. Candidate-stage same-row materialization uses candidateDraftId; verify selections against saved source and retain full AI metadata. Zero OKX mutations from generation; candidate apply/execute/retry forbidden. Existing manual/sized drafts unchanged. Use injectable provider boundary and existing owner transport for explicitly public market reads. Lazy optional SDK and env handling only inside business evaluator adapter; never inspect existing environment values/configuration files. Official SDK 0.7.2 contract documented in spec. All provider failures sanitize by fixed category, never exception text. Workers bounded and drained before returning, overall deadline exhaustion preserves pending candidates as failed.

External actions: user installs typesafe-sdk==0.7.2 in backend Python environment and supplies process environment with TYPESAFE_API_KEY=<SET_BY_USER>, JEV_ENABLED=true, TYPESAFE_DEFAULT_MODEL=jev-latest, JEV_TIMEOUT_SECONDS=3, JEV_MAX_CONCURRENCY=4, then restarts backend. Docs explain no protected files changed, live verification pending; no local mocked verification blocked.

## Required evidence

- RED-084: disabled/missing SDK/key, timeout/provider exception/invalid numeric/model responses, future/open data, unauthorized/account mismatch, duplicate changed request, candidate prepare/execute/retry, tampered selected ID/price; no mutation and full retention.
- GREEN-084: exact golden generator output including IDs/tick rounding/touches and duplicate rounded price identity; H6/D1/W1 context, deterministic hash, LONG/SHORT wording, actual model/rubric values, stable separate ranks; persisted creation/list/read/reopen; same-row manual materialization retains assessments; legacy draft works.
- Formal RED cases run and observed before GREEN cases; then related unittest modules. List exact commands/results and any missing coverage.
- Buildability required YES: python3.12 -m compileall -q backend, after last code/test executable change; no compilation failures.

Stop on contract/scope contradiction; ask coordinator, do not invent architecture or widen writes. Return terminal report with changed files, exact checks, RED/GREEN order, build status, safety and external actions, compact telemetry envelope logical agent_run_id=E2-JEV-T84-001. Do not update this task.

## Completion evidence

Initial RED: five automatic API tests returned 404 before implementation. Final new backend module: 20 tests passed; retry module five tests and existing account-snapshot regression passed. Independent calculator parity: 45 fixtures passed with unchanged final generator hash. Audit found four issues; bounded executor remediation and post-fix regression coverage resolved them, independent R2-JEV-BE-REAUDIT-001 PASS. Final `python3.12 -m compileall -q backend` succeeded; full backend discovery with permitted localhost fake servers passed 249 tests in 40.689 seconds. Root observed the complete redirected result in /tmp/jev-backend-final.log. Optional live SDK/key activation remains user-owned per developer guide; no live provider/exchange mutation verification performed.
