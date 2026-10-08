# T98 Orders and Portfolio refresh audit

Status: COMPLETE
Date: 2026-10-08
Contract: tasks/task_98_orders_portfolio_refresh.md
Verdict: PASS

## Acceptance and scope
REQ/AC001: Portfolio and every Orders filter poll every5s; loading/authentication/SPOT guards suppress inappropriate requests. Shared same-session/key gate coalesces active readers and queues re-entry behind canceled-but-unsettled transport. No success caching; manual/action invalidation remains fresh outside active work/cooldown.
REQ/AC002: transient errors back off10/20/40/60s, HTTP429 honors longer delta/date Retry-After, cooldown survives provider/widget disposal. No autonomous background retry. Cancellation does not count as transient failure or clear cooldown; abandoned same-generation429 still establishes cooldown. Terminal401/403/configuration errors stop automatic invalidation.
REQ/AC003: Portfolio shows spinner during restoration/pending first or retry read. Completed genuine error remains visible; ordinary successful-data refresh retains content.
REQ/AC004: selective watches prevent operation-only refetches. Semantic dependency reload hides prior-account values; session/generation guards reject stale completions. Existing TradeApi signature preserved for existing implements TradeApi fakes; production optional cancellation capability used.
All10 source paths and6 test paths match the approved Allowed Write Surface. Coordinator reviewed selected source/test diffs, new gate/provider integration fixtures and final name-only status; no assertion weakening or protected path changes. Existing docs/agents/telemetry/events/2026-10-06.jsonl user modification preserved without reading its diff. Targeted tracked-file diff whitespace check exit0. No Git history mutation or deployment.

## Findings and remediation
| Finding | Resolution | Status |
|---|---|---|
| AUD98-001 | Original TradeApi.getPositions signature preserved; optional cancellable GET capability | CLOSED |
| AUD98-002 | Terminal authentication/configuration automatic polling guard | CLOSED |
| AUD98-003 | Retain started canceled operation ownership; queue same-key re-entry until transport settles | CLOSED |
| AUD98-004 | HTTP403 treated as terminal authorization failure | CLOSED |
| AUD98-005 | Real Portfolio provider tested through fake Dio transport beneath provider | CLOSED |
| AUD98-006 | Invalid/unrepresentable Retry-After falls back without stranding lease; deadline overflow protected | CLOSED |
| AUD98-007 | Preserve genuine abandoned transient/429 failure before promoting queued re-entry | CLOSED |
| AUD98-008 | Dependency/session reload hides previous-account values, ordinary refresh retains content | CLOSED |
Advisory inherited-capability subclass concern withdrawn as blocker: existing repository fakes implement original TradeApi; new subclasses explicitly implement their optional capability. No current repository regression evidenced.
All product/test remediation performed by the same explicitly bound E1 executor. Coordinator remained non-writing for executable source/test behavior.

## RED then GREEN evidence
1. Negative restoration: `flutter test --no-pub --reporter expanded --plain-name 'production portfolio provider skips reads during restoration' test/features/portfolio/portfolio_loading_test.dart` —1/1 passed. Zero private transport calls while restoration pending; one after restored session.
2. `rtk test flutter test --no-pub test/core/network/foreground_read_gate_test.dart` —11/11 passed. Lifecycle/backoff/session/429/cancellation/date negatives precede the final primary success case proving fresh uncached reads. Includes Retry-After120s, cooldown preservation, ignored cancellation queue, abandoned429, queued-reader disposal and session replacement.
3. `rtk test flutter test --no-pub test/core/network/backend_data_client_test.dart test/features/orders/trade_api_retry_test.dart test/features/orders/orders_screen_refresh_test.dart test/features/orders/order_repository_all_test.dart test/features/portfolio/portfolio_dual_currency_screen_test.dart test/features/portfolio/portfolio_loading_test.dart` —45/45 passed afterward. Covers GET metadata/auth safety, actual provider restoration/operation-only state/re-entry/session fencing,5s cadence, terminal-error polling, loading/error distinction and ordinary-refresh content.
Total56 focused tests. Reused executor evidence: exact commands/counts provided; final inspected source matches tested candidate. No additional full-suite execution required by bounded V2/V3 plan. Test-harness issues were diagnosed without weakening assertions: standalone ProviderContainer Timer0 requires explicit fake-time advancement; bounded pump-until loops wait for fake Dio completion.

## Buildability and final integration
Task canonical build: executor `flutter build web --no-pub` succeeded after last executable change (26.1s), producing build/web. Unsupported RTK build wrapper failed before execution; exact Flutter fallback used.
Fresh coordinator final application build: `rtk proxy flutter build web --no-pub` —exit0,25.6s, built build/web. Existing wasm dry-run dart:html/dart:js_util incompatibility notices and missing CupertinoIcons font notice are non-blocking for standard web output; no new wasm/font capability claimed.
Fresh backend build check: first `rtk proxy python3 -m compileall -q backend` could not write macOS Python cache; compilation evidence was unavailable from that run. One focused safe retry `rtk proxy python3 -X pycache_prefix=/private/tmp/t98-python-cache -m compileall -q backend` —exit0. Only temporary bytecode cache path changed; no repository configuration action.
Flutter SDK cache permission resolved via normal test/build sandbox escalation. No persistent environment blocker.
Final integration PASS; all findings closed and buildable final state observed. External configuration/environment actions:none. Real production rate-limit origin and deployed behavior not verified; no production service calls or deployment. Shared upstream limits may still produce429, now handled by client backoff.

## Routing and lifecycle
Executor E1/gpt-6-luna/xhigh and advisory auditor R2/gpt-6.1-sol/medium explicitly bound, inheritance forbidden; effective routes unavailable/UNVERIFIABLE. Read-only auditor findings reconciled by coordinator; all terminal results collected. Runtime exposes no child close/release primitive, so lifecycle release could not be requested. No duplicate or recursive writers.
