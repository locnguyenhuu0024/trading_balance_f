# Task 96 — Shared fresh strategy-list observations

Status: PASS
Agent Role: implementation_executor
Executor Class: E2
Target Model: gpt-6-luna
Target Effort: max
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Specification: docs/agents/specs/2026-10-07-backend-data-gateway.md
Plan: docs/agents/plans/2026-10-07-backend-data-gateway.md
Requirements: REQ-009; Acceptance: AC-007
Predecessors: T93 PASS

## Allowed writes

backend/strategy.py; backend/tests/test_strategy_list_reads.py (new); relevant strategy API/queue/retry tests for contract regressions only. No service/gateway/transport/worker changes.

## Exact implementation contract

Extract `_refresh_result_state` from existing `_result_for` reconciliation/recovery/cleanup section, preserving ordering and active/corrupt sequential queue predicate. Extract pure result projection accepting strategy, observed account, raw positions, validity and observation timestamp; preserve scope, unavailable-vs-none, PNL, scan freshness, `_basic_result` and deletion hints. Individual `_result_for` remains a fresh-read wrapper with existing candidate behavior.

List flow: initial account fingerprint; existing ordered selected IDs; sequential reread/expire/refresh per existing record; after ALL refreshes reread surviving selected records; NEW uncached account matching original; ONE fresh `_terminal_delete_position_rows` read if any noncandidate; capture observation time; NEW identity postcheck; project all survivors. Empty/candidate-only lists need no positions. Preserve final surviving-ID filter, concurrent row deletion safety and current DB hint checks. Do not change `_basic_result`, `_can_delete_hint`, `_eligible_terminal_delete_record`, `_delete`, lease or placement logic. Display gateway cache is forbidden for proof; errors/malformed positions remain unavailable and block delete hints.

## Verification

RED negative cases first: account changes midread, malformed/unavailable positions, stale/error order scan, active/corrupt queue, replacement source removal; no stale proof/ghost rows. GREEN: N>=2 stable strategies consume one fresh SWAP observation and constant identity reads, identical DTOs/hedge scope, all reconciliation completes before observation; candidate-only/empty avoids positions. Observe failing repeated-read baseline before implementation where feasible.
Commands: `python3.12 -m unittest backend.tests.test_strategy_list_reads backend.tests.test_strategy_api backend.tests.test_strategy_queue backend.tests.test_strategy_retry backend.tests.test_strategy_automatic -q`; V3. Buildability YES/backend: `python3.12 -m compileall -q backend` after final edits.

No protected configuration/env content/writes, external calls, task/telemetry/Git changes, children or architectural redesign. Return evidence/paths/build/external actions and telemetry strategy-list-executor-96 E2 gpt-6-luna/max; no status changes.
