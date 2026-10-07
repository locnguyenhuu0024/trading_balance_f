# Task 93 — Backend read gateway and transport reuse

Status: PASS
Agent Role: implementation_executor
Executor Class: E2
Target Model: gpt-6-luna
Target Effort: max
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Specification: docs/agents/specs/2026-10-07-backend-data-gateway.md
Plan: docs/agents/plans/2026-10-07-backend-data-gateway.md
Requirements: REQ-001..005; Acceptance: AC-001..003
Predecessors: none

Dispatch Route Status: UNVERIFIABLE
Requested Model: gpt-6-luna
Requested Effort: max
Observed Effective Model/Effort: unavailable

## Allowed writes

backend/data_gateway.py (new); backend/okx.py; backend/service.py; backend/app.py; backend/tests/test_data_gateway.py (new); backend/tests/test_okx_pool.py (new); backend/tests/test_trade_api.py only compatibility coverage for normalized display reads.

Read governing AGENTS and optimization/audit rules. No configuration/environment/manifests read/write, external service, telemetry/task writes, commits or child agents.

Authorized extension D8, REQ-010/AC-008: backend/currency.py and fake-only currency gateway tests are also allowed. Fixed CoinGecko host/path/query, public no-query currency/usdt-vnd route, positive finite rate validation, 60-second bounded cache; no outgoing credentials/redirects or live external calls. Preserve existing test injection without altering protected settings.

## Contract

Implement exact gateway registry/query validation/envelope/auth/cache/pool/fan-out defined in specification. Reuse existing origin and session policy. Distinguish unavailable/empty. Public quotes filter cached SPOT ticker rows to <=100 requested full ids. Private identity observations and cache generations fail closed; every hit requires session. Identity and data must agree before publication. Bound single-flight entries/network and connection leases; reserve fresh-action capacity. No write retries. Map upstream errors safely including 429 Retry-After.

Integrate additive routes through TradeService.dispatch. For `/v1/positions` only, use an explicit display snapshot path with shared gateway reads and bounded parallel independent type groups; preserve normalization/identity ambiguity/action eligibility. Keep `_fetch_snapshot` default and prepare/execute/delete/terminal proof uncached and unchanged. Do not modify strategy.py or worker.

Action-driven freshness: expose gateway.invalidate_private() with generation fencing plus identity/entry clearing. Service dispatch invalidates in finally after authorized execute/strategy POST processing (including ambiguous/failed outcomes after potential mutation). Test cached display then immediate post-action read and delayed pre-action flight publication. Existing display fixtures may advance/inject monotonic TTL but must not weaken fresh action/preflight assertions.

## Verification

RED: unauthenticated/expired cached private read or changed account cannot return data; invalid query/unsupported method makes zero upstream calls; failed aggregate never returns partial success. Observe negative before primary GREEN.
GREEN: fake transport verifies all-currency balance, query/pagination parity, ALL aggregation, shared concurrent reads and reused exclusive connections. Add failing behavioral baseline before fixes where feasible. Cover TTL, bounds/eviction, deep copies, shared failures, malformed rows, current identity, 429 headers and POST no-replay/discard.
Commands: `python3.12 -m unittest backend.tests.test_data_gateway backend.tests.test_okx_pool backend.tests.test_trade_api -q`; V3 ceiling, escalate only affected regressions. Buildability YES/backend: `python3.12 -m compileall -q backend` after final executable changes.

Return exact RED then GREEN commands/exits and test counts, changed paths, build result, external actions (none or blocker), and telemetry logical run backend-executor-93, role implementation_executor E2, explicitly requested gpt-6-luna/max; effective route unavailable if unexposed. Do not mark task status.

## Bounded review corrections

Resolve AUD93-1..4 in docs/agents/audits/2026-10-07-backend-data-gateway-review.md: final child freshness with one bounded refresh then503, bounded normalized executor admission, preserved child401 and identity429/Retry-After. Same source surface/route; explicit affected RED then GREEN/regression/build after final fix. No fresh baseline reset for unaffected scenarios.

Completed bounded extensions: AUD93-5 acquisition-time TTL/fetchedAt; AUD93-6 non-multiplying freshness retries; deterministic AC-002 bounds/failure/admission lifecycle tests. Existing test_trade_api direct SQLite fixtures close handles using closing plus connection transaction context, with causal native77-test confirmation. Final87 focused tests and backend compileall exit0; exact formal order and coordinator PASS are recorded in the canonical audit. No protected configuration or external action.
