# Integration Audit: Strategy preflight account reads
Status: PASS
Date: 2026-10-03
Branch: codex/fix-preflight-account-config
Task: T75 — PASS
Specification: docs/agents/specs/2026-10-03-strategy-preflight-account-reads.md

## Independent audit
Coordinator inspected selected non-protected source/test diffs and final path/status metadata. All source changes are bounded to approved preflight/balance/read-error/diagnostic surfaces. No unresolved findings.

| Acceptance | Evidence / verdict |
|---|---|
| AC-001/002 | One config read for ordinary prepare and retry review/draft/prepare; new requests obtain new identity; no global/service/TTL identity cache. PASS |
| AC-003 | Covered read failures return safe 429 exchange_rate_limited and application Retry-After: 2; non-429 fallback codes preserved; API/worker diagnostics retain safe reason/code without canary text. PASS |
| AC-004 | Both guards share exactly-one finite USDT availBal parsing; malformed/absent/duplicate values unavailable, true low/negative/zero amounts insufficient, equality including fees accepted; no availEq fallback. PASS |
| AC-005 | Batch execute reuses its own fresh initial account read; post-leverage preflight remains fresh; worker identity/mode changes prevent order placement. Final result ownership check preserved. PASS |
| AC-006 | Existing FIFO sequential loop advances only after validated accepted ACK is durably committed; rejected/unknown outcomes stop tail; >=250ms pacing and legacy batch behavior retained. Existing queue regressions and V3 suite PASS |

AUD-001 RESOLVED: account_balance now rejects malformed top-level rows instead of silently filtering them; raw transport malformed-row regression proves no writes.
AUD-002 RESOLVED: initial batch execute preflight reuses only that execute request's fresh identity; post-leverage and final result ownership reads remain fresh.

## Formal verification — executor evidence collected
RED before implementation: 2 tests / 15 expected failing subcases, exit 1. After implementation, failure scenarios satisfy the required safe outcomes.
Command: `python3 -m unittest backend.tests.test_strategy_api.StrategyApiTests.test_red_prepare_rejects_unavailable_or_ambiguous_usdt_balance backend.tests.test_strategy_api.StrategyApiTests.test_red_prepare_maps_rate_limited_exchange_reads_to_safe_429 -v`
GREEN focused regressions: 12 tests passed, exit 0.
Command: `rtk test python3 -m unittest backend.tests.test_strategy_api.StrategyApiTests.test_red_prepare_rejects_unavailable_or_ambiguous_usdt_balance backend.tests.test_strategy_api.StrategyApiTests.test_red_prepare_maps_rate_limited_exchange_reads_to_safe_429 backend.tests.test_strategy_api.StrategyApiTests.test_red_prepare_preserves_non_rate_limit_read_fallbacks backend.tests.test_strategy_api.StrategyApiTests.test_red_retry_balance_guard_shares_strict_avail_bal_semantics backend.tests.test_strategy_api.StrategyApiTests.test_red_retry_review_maps_rate_limited_account_reads backend.tests.test_strategy_api.StrategyApiTests.test_red_balance_transport_rejects_malformed_rows_before_balance_parser backend.tests.test_strategy_api.StrategyApiTests.test_green_prepare_reuses_one_fresh_account_snapshot_per_request backend.tests.test_strategy_api.StrategyApiTests.test_green_prepare_balance_boundary_includes_fees_and_accepts_equality backend.tests.test_strategy_api.StrategyApiTests.test_green_retry_preview_and_draft_reuse_source_account_snapshot backend.tests.test_strategy_api.StrategyApiTests.test_green_batch_execute_rechecks_account_and_mode_after_leverage backend.tests.test_strategy_queue.StrategyQueueTests.test_post_leverage_account_or_mode_change_stops_before_order_placement backend.tests.test_strategy_diagnostics.StrategyDiagnosticsTests.test_red_rate_limited_preflight_keeps_safe_diagnostic_reason_and_api_code -v`
Follow-up after final test additions: 5 tests passed, exit 0.
Command: `rtk test python3 -m unittest backend.tests.test_strategy_api.StrategyApiTests.test_green_retry_preview_and_draft_reuse_source_account_snapshot backend.tests.test_strategy_api.StrategyApiTests.test_green_batch_execute_rechecks_account_and_mode_after_leverage backend.tests.test_strategy_diagnostics.StrategyDiagnosticsTests.test_red_rate_limited_preflight_keeps_safe_diagnostic_reason_and_api_code backend.tests.test_strategy_diagnostics.StrategyDiagnosticsTests.test_red_worker_rate_limit_is_diagnosed_but_stops_with_safe_queue_reason backend.tests.test_strategy_queue.StrategyQueueTests.test_post_leverage_account_or_mode_change_stops_before_order_placement -v`
V3 after final executable/test changes: 148 tests passed, exit 0.
Command: `rtk test python3 -m unittest backend.tests.test_strategy_api backend.tests.test_strategy_diagnostics backend.tests.test_strategy_retry backend.tests.test_strategy_worker backend.tests.test_strategy_queue -q`
Executor affected backend build and selected diff whitespace checks passed. Coordinator reused behavioral evidence and independently reviewed actual source changes.

## Final repository builds — coordinator observed after final mutation
- `PYTHONPYCACHEPREFIX=/private/tmp/preflight-fix-pycache python3 -m compileall -q backend` — exit 0, no compiler/parser errors.
- `rtk err /Users/locnguyen/development/flutter/bin/flutter build web --no-pub` — exit 0, successful completion, no errors.
- `git diff --check -- backend/strategy.py backend/okx.py backend/diagnostics.py backend/app.py backend/strategy_worker.py backend/tests/test_strategy_api.py backend/tests/test_strategy_diagnostics.py backend/tests/test_strategy_queue.py` — exit 0.

## Boundaries and limitations
Protected configuration/environment files were not inspected or modified. No dependency/configuration change, external configuration action, live OKX call, live trade, deployment, commit or push. All trading verification used local fake transports. HTTP 429 remains a possible upstream outcome; the patch removes redundant phase reads and preserves it clearly, without automatic write retries. Gunicorn read-only control-server configuration issue is outside this source fix.
Executor E1 explicitly bound to gpt-6-luna/xhigh; effective route unavailable / UNVERIFIABLE. Two R2 planning runs explicitly bound to gpt-6.1-sol/medium; outputs adopted. Runtime exposes no close/release primitive, so cleanup could not be requested; no capacity blocker occurred.
