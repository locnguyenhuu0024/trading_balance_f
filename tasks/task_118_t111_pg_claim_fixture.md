# T118 — Repair T111 PostgreSQL claim-race fixture

Status: PASS — fixture correction/source audit and operator PostgreSQL rerun verified
Agent Role: implementation_executor
Executor Class: E1
Target Model: gpt-6-luna
Target Effort: xhigh
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Predecessor: T111 source audit PASS, runtime REWORK
Requirements: REQ-002/004; AC-002/004

AUD-111-33: operator PostgreSQL regression307 tests fails one expected race result: API returns invalid_strategy instead of connection_busy. Source shows the seeded api-prepared-strategy contract has only instrumentId, while StrategyService._claim_execution calls _ensure_new_order_cap before lease acquisition and requires a nonempty selectedLevels list. The fixture never reaches the lease boundary it claims to test. Production validation must not change or be bypassed.

Allowed writes: backend/tests/test_strategy_scope.py only. Align the fabricated persisted API contract with the existing one-order cap contract, inspect other pre-claim prerequisites. Add a focused local SQLite equivalent if necessary to ensure the same exact PostgreSQL fixture passes real validation and reaches the busy-connection guard without monkeypatching validation/claim logic. Keep PostgreSQL multiprocessing/barrier, exact connection_busy assertion, fence5 worker claim, preserved API confirmation/state, cleanup and no-resend boundaries. No product code, configurations, dependencies, Git, VPS, secrets, live calls or unrelated tests.

RED: reproduce current malformed fixture giving invalid_strategy before the lease guard using the narrow local harness. GREEN: corrected fixture reaches connection_busy under the existing queued-worker barrier while preserving API state; valid normal fixture and malformed-contract negative coverage remain meaningful. V2/V3 scope: focused new regression then strategy_scope/strategy_worker; actual PG case remains operator-owned. Canonical build: python3.12 -m compileall -q backend after final test edit. Report exact commands/results/exits/skips and limitations. Independent read-only audit mandatory. Coordinator owns task status, docs and telemetry.

## Final source audit

Coordinator inspected the entire fixture-only diff: shared seed helper reuses the actual race rows, adds a valid one-level API contract, and is called by both local and PostgreSQL tests. Production validation/claim code, PostgreSQL spawning/barrier, connection_busy/fence5 assertions, API confirmation/state assertions and cleanup remain unchanged. No optional additional audit child: this single localized test contract can be independently reviewed by the non-writing coordinator without duplicating handoff context.

Executor failing baseline: `rtk proxy python3.12 -m unittest backend.tests.test_strategy_scope.OwnedStrategyLookupTests.test_owned_api_claim_race_fixture_reaches_busy_guard` ran1, expected failure/exit1 (invalid_strategy before busy guard). Final local47-test scope passed, exit0: `rtk proxy python3.12 -m unittest backend.tests.test_strategy_scope.StrategyScopeContractTests backend.tests.test_strategy_scope.StrategyReservationMigrationTests backend.tests.test_strategy_scope.OwnedStrategyLookupTests backend.tests.test_strategy_worker`. PG class intentionally not executed.

Coordinator exact post-edit formal commands, in order, each exit0/one test OK:
1. `/Users/locnguyen/.local/bin/rtk test /opt/homebrew/bin/python3.12 -m unittest backend.tests.test_strategy_scope.OwnedStrategyLookupTests.test_owned_api_claim_rejects_malformed_race_fixture_before_busy_guard -q`
2. `/Users/locnguyen/.local/bin/rtk test /opt/homebrew/bin/python3.12 -m unittest backend.tests.test_strategy_scope.OwnedStrategyLookupTests.test_owned_api_claim_race_fixture_reaches_busy_guard -q`

Fresh coordinator `/opt/homebrew/bin/python3.12 -m compileall -q backend`: exit0. Selected diff whitespace check exit0. Source audit PASS, effective route UNVERIFIABLE after explicit binding, no protected content/action. Operator must rerun affected strategy_scope/strategy_worker with the existing dedicated PostgreSQL test environment. No full T111 PASS until that race passes. Existing commit/push authorization applies to this bounded T111 correction for the VPS verification loop; unrelated telemetry2026-10-06 excluded.
