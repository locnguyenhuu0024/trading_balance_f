# T119 — PostgreSQL claim-state row assertion portability

Status: PASS — mapping assertions/source audit and operator PostgreSQL persisted-state verification accepted
Agent Role: implementation_executor
Executor Class: E0
Target Model: gpt-6-luna
Target Effort: high
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Requirements: REQ-002/004; AC-002/004

AUD-111-34: operator48-test run fails at tuple(lease): actual tuple contains lease_owner/fence/operation_id column names. PostgresIdentityStore uses psycopg dict_row, so iteration yields keys; SQLite row iteration yields values. The preceding exact API connection_busy/worker claimed5 race assertion passed. compileall exit0. The worker_strategy tuple assertion has the same defect.

Allowed writes only backend/tests/test_strategy_scope.py, limited to the two PostgreSQL persisted-state assertions and necessary focused test evidence. Read backend/postgres_store.py for row representation; preserve production adapter and all exact expected owner/fence/status/operation fields, processes/barrier/cleanup. Prefer explicit named-column access in both assertions; do not change SQLite-only unrelated fixtures or add generic row adapter infrastructure.

Meaningful RED: demonstrate mapping rows cause the original actual persisted-state assertions to fail, and incorrect owner/fence/status is rejected. GREEN: corrected actual assertions accept equivalent fabricated mapping and sqlite3.Row values. A narrow reproducible local harness extracting the actual assertion statements is acceptable for this mechanical two-line test-only correction; do not merely test a separate copy of expressions. No real PostgreSQL available locally, operator rerun required. Reuse prior unaffected47-test results unless changed assertions invalidate them. Fresh canonical build python3.12 -m compileall -q backend, selected diff check. No product/config/install/secrets/VPS/live/Git/subagent action. Return exact commands/results/exits/skips/stable report. Coordinator owns independent audit, docs and Git.

## Final source audit and evidence

Executor changed only the two PG persisted-state assertion expressions to explicit named fields; expected tuples remain unchanged. Before fix, extracted actual assertions failed for correct dict mappings. Post-fix `rtk proxy python3 /private/tmp/task119_pg_row_harness.py` exits0: both mapping and sqlite3.Row accepted, all six individual incorrect persisted values rejected. This temporary fabricated-data harness is local evidence, not a PostgreSQL execution.

Coordinator independently inspected the entire two-assertion diff and actual AST-extraction harness. Fresh Python3.12 inline actual-assertion check ran six invalid-field rejections before accepting both valid row representations, exit0. Exact expected owner/fence/operation/status fields preserved; PG claim assertions, process/barrier and cleanup unchanged. Fresh `/opt/homebrew/bin/python3.12 -m compileall -q backend` exit0; selected diff whitespace check exit0. No product/config change. Prior local47 and VPS47 passing affected tests unaffected by this assertion-only correction; remaining PG state proof requires rerun. Source audit PASS; T111 overall remains BLOCKED. Existing Git authorization covers pushing this T111 verification correction; oldtelemetry2026-10-06 excluded. No additional audit child for mechanical independently reviewed assertion diff; terminal executor collected, runtime has no close/release primitive.
