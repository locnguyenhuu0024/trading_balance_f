# Task 120 — Persisted strategy projection freshness

Status: PASS — audited source remediation; operator T112 rerun remains separate
Tier: S; single material gateway/projection contract, no independent planning fan-out required.
Agent Role: implementation_executor
Executor Class: E1
Requested Model / Effort: gpt-6-luna / xhigh
Route Binding: EXPLICIT; Parent Route Inheritance: FORBIDDEN
Effective route: unavailable; dispatch UNVERIFIABLE
Independent audit: existing R3 gpt-6.1-sol / high, explicitly bound, read-only.

## Problem and approved correction

Operator T112 regression119 failed at the first owned strategy page with data_stale. Existing strategy/scope/trade regression92 passed without skips; operator compileall exit0. Source gateway sets a one-second deadline before constructing a 501-row persisted projection and rejects elapsed deadlines before snapshot publication. Hardware latency makes this legitimate local read fail.

Keep one-second freshness timestamps truthful and frozen snapshot retention60s unchanged. Permit stale persisted owned strategy projections to be frozen/returned with dataMeta.stale=true, without interpreting them as current venue observations. Restrict the exception to the owned strategies resource; normalized exchange/private/public reads retain stale rejection. Do not increase TTL, invent a later asOf timestamp, skip authority/generation guards, or freeze fewer rows. Authorization is the existing approved T112 correction workflow, not new product scope.

## Write surface and verification

Allowed: backend/data_gateway.py, backend/service.py, backend/tests/test_data_gateway.py, backend/tests/test_exchange_read_routes.py. No other executable change. Coordinator owns documentation/status. No protected content, installs, live venue access, Git mutations or configuration action.

Before edit: deterministic fake-monotonic-clock reproduction advancing beyond1s during local projection construction must fail against current source. Formal negative before success: expired venue reads remain rejected; logout/invalidation during slow local projection prevent publication; then slow local owned projection returns501 rows, stable first/continuation pages, accurate stale=true/asOf, zero vault/upstream calls. Use clock advance rather than sleeping or relaxing expected timing. Preserve existing real SQLite paging assertions.

Related V3: exchange_read_routes and data_gateway; reuse unchanged operator92-test evidence. Fresh backend compileall after last executable/test edit. Exact commands/counts/skips, scoped diff-check and terminal report required. Coordinator independently audits scope/guards and final build. Full T112 remains blocked pending repaired operator119 rerun and separate venue evidence.

## Checklist

- [x] Existing T112 approval and bounded remediation authorization verified.
- [x] Contract presented in commentary; no requirements change.
- [x] Deterministic failing baseline and ordered negative/success observed.
- [x] Implementation and affected regression pass.
- [x] Independent audit and fresh backend build pass.
- [ ] Operator rerun accepted; T112 full verdict remains separate.

## Terminal verification

Before source change: `rtk test /opt/homebrew/bin/python3.12 -m unittest backend.tests.test_exchange_read_routes.ExchangeReadRouteTests.test_slow_owned_strategy_projection_freezes_stale_rows_with_truthful_timestamps -v` failed503 data_stale after deterministic1.1s fake-clock advance. Formal negative5 then intended success2 passed/no skips. Related `rtk test /opt/homebrew/bin/python3.12 -m unittest backend.tests.test_data_gateway backend.tests.test_exchange_read_routes -q`:68 passed/no skips. Executor and independently fresh coordinator `rtk proxy /opt/homebrew/bin/python3.12 -m compileall -q backend`:exit0. Scoped diff-check0. Only gateway and two test files changed; no service modification needed.

Independent R3-T120-AUDIT-001 SOURCE PASS collected: entire three-file diff and realistic501-row/negative fixtures reconciled, no findings remain. Executor effective route and auditor effective route unavailable; original requests explicitly bound. T120 source remediation PASS; T112 full123 runtime/venue verdict remains pending. Commit/push delivery on the same T112 branch follows the existing user-authorized delivery request.
