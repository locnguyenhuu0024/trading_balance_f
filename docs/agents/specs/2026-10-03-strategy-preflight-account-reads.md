# Design Specification: Strategy preflight account reads and balance failures
Status: READY_FOR_PLAN
Date: 2026-10-03
Tier: M
Decision Ledger: docs/agents/decisions/2026-10-03-strategy-preflight-account-reads.md

## Objective and evidence
User-provided Docker logs show repeated account_config reads, HTTP 429 masked as other, and insufficient_balance. Source confirms _prepare -> _current_strategy -> _preflight -> _preview_contract -> _load_market_inputs performs three configuration reads. Both ordinary and retry balance guards conflate absent/invalid availBal with genuinely insufficient funds. No live exchange call is authorized or required.

## Scope and requirements
REQ-001: Pass a validated operation-local account snapshot through ordinary and retry prepare/preflight/market-preview consumers. Each independent request/preflight phase reads account_config freshly once; standalone consumers default to fresh reads. Never persist/cache identity on a service/client, globally, across requests, across worker cycles, or across leverage writes.
REQ-002: Strategy read failures carrying HTTP 429 become APIError(429, exchange_rate_limited) with a safe message and Retry-After: 2 (application retry guidance, not a claimed upstream header). Preserve existing non-429 502 fallbacks. No automatic read/write retries. Diagnostics retain exchange_rate_limited rather than other/preflight_unavailable. Cover config, positions, pending orders, market inputs and balance read paths in prepare/retry review.
REQ-003: Share strict USDT availBal parsing between ordinary and retry guards. Missing, malformed, nonfinite or ambiguous duplicate USDT entries return 502 account_preflight_unavailable. A unique finite numeric available balance (including zero/negative) below required returns 422 insufficient_balance with required/available. Equality passes. Required remains totalMargin + estimatedOpeningFees using Decimal.

## Decisions and data contract
D-001: User explicitly authorized autonomous decisions and implementation after planning; no repeated approval gate.
D-002: Preserve availBal field semantics. Repository evidence does not establish an acctLv/availEq fallback; no speculative account-mode change or total equity substitution.
D-003: One snapshot makes read-only preflight coherent; a mid-prepare account change may be detected by the next fresh execution phase rather than another redundant read. Execute, post-leverage and separate worker cycles retain fresh identity/mode guards.
Data: USDT availBal and required are decimal USDT quantities. Example: margin 100 + opening fees 0.5 = required 100.5; available 100 -> reject, 100.5 -> accept, missing -> unavailable.
Public API: add exchange_rate_limited 429; unavailable balance remains account_preflight_unavailable 502; actual insufficiency unchanged. No persistence/schema change.

## Invariants and acceptance
INV-001: Never submit orders or leverage on failed prepare, malformed balance or rate-limited preflight.
INV-002: Account ownership, position mode, instrument position, pending orders, lineage/reservations, preview hash and order cap remain enforced.
AC-001: A transport rejecting any second config read permits ordinary prepare with exactly one read and no POST writes; a new request performs a new read.
AC-002: Retry prepare/review similarly reuse their local snapshot, preserving source ownership/revision guards.
AC-003: HTTP 429 at each covered read returns safe 429 and identifiable diagnostic reason/code; non-429 errors retain existing behavior.
AC-004: Missing/malformed/nonfinite/duplicate USDT data is unavailable, low/zero/negative balances are insufficient, equality passes including fees; ordinary/retry guards agree.
AC-005: Account/mode changes between prepare and execute, and after leverage, prevent order writes; worker freshness regressions pass.

## Verification and rollout
Offline injected transports only. Negative RED checkpoint precedes success GREEN, then affected API/diagnostics/retry/worker tests. Backend compileall and existing Flutter web build establish final buildability. No protected config inspection/writes, dependency updates, live trades, deployment, commit or push. Rollback is reverting approved source changes later with user authorization. External configuration actions: none. Gunicorn read-only control-server error is outside this source fix.

## User steering: acknowledged sequential placement
REQ-004 / AC-006: Preserve and verify existing default sequential queue: next order only after previous matching successful ACK with nonempty order ID is durably committed; rejected/unknown/malformed ACK stops the untouched tail. Preserve minimum 250 ms start spacing. Accepted placement is distinct from filled. Existing explicitly selected batch/legacy history remains compatible; no preference rewrite or persisted-mode rewrite. Source: strategy_worker.py _commit_order_outcome and sequential loop; existing queue spec REQ-004/005. This behavior already exists and needs regression evidence, not a new scheduler.

AUD-001 / bounded scope extension before implementation: backend/okx.py account_balance currently silently filters non-dict response rows, concealing malformed input from the strict parser. Allow modifying ONLY account_balance to reject malformed data shape/rows with content-free OKXTransportError; preserve other endpoint filtering. Injected-transport raw malformed balance test must prove 502/no writes. This implements existing REQ-003, no new business/data semantics.

AUD-002 / REQ-001 clarification: batch execute obtains a new account in _current_strategy for that execute request; pass that new snapshot into its initial preflight to avoid adjacent duplicate reads. Never reuse prepare identity. Post-leverage preflight must still obtain another new snapshot. Sequential enqueue already performs one identity read. Add execute-phase freshness/post-leverage account-switch evidence; no lifecycle semantics change.
