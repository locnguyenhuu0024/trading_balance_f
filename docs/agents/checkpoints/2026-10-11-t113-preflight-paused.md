# T113 preflight pause checkpoint — 2026-10-11

Status: PAUSED at the user's explicit request. Resume only when requested.

## Accepted evidence and authorization

- Branch `codex/multi-user-okx-binance-plan`; HEAD `43dbafe18aba6ad5fa347f6c70b50d14a99ae8f4`, previously pushed. T112 implementation `bf76c67`, T120 repair `732e279`, accepted runtime documentation `43dbafe`.
- T112 source/runtime PASS: operator reported 123 related tests passing without skips, including the two targeted projection cases; earlier 92 related tests passed. Combined related coverage is 215, not 217. Venue/demo acceptance remains pending. No fresh VPS compile result for the last repair was supplied; local final compile evidence exists.
- D-007 authorizes T113 fixture-first code, keeping trading locked and requiring demo verification before activation. Source/runtime predecessor acceptance permits source work; fixtures cannot establish venue PASS.
- No new Git commit/push, installation, protected configuration access, live exchange operation or activation is authorized for T113.

## Exact stopping point

Both independent read-only R2 reports are collected: `t112_adapter_preflight` (native contracts) and `t112_gateway_preflight` (ledger/API integration), explicitly requested as `gpt-6.1-sol/medium`; effective routes unavailable. Both are completed. All listed child agents are terminal; no child-close primitive is available.

No T113 writer has been dispatched and no T113 executable source/test changes have begun. Coordinator synthesis and binding preflight/Definition of Ready remain pending. The proposals below are not a finalized executor contract.

## Findings to retain

- Full/partial reduce: signed POST `/fapi/v1/order`, MARKET, opposite side, exact positive base quantity, `positionSide=BOTH`, `reduceOnly=true`, durable unique client order ID. Never change leverage or position mode.
- Cancel/lookup: DELETE/GET `/fapi/v1/order`, bound symbol and original order/client ID. ACK alone is insufficient; historical order absence does not prove failure. Timeout, lost response, uncertain 503 and duplicate IDs require lookup without resubmission.
- Require authoritative boolean `dualSidePosition=false`; BOTH rows alone do not prove One-way. Reject Hedge, conditional/algo, Portfolio Margin, Spot writes and strategies before send.
- Command filters must retain LOT_SIZE/MARKET_LOT_SIZE min/max/step with exact decimals. Official research reports `(quantity-minQty) % stepSize == 0`. Reject unsupported full size rather than clip/chunk; preserve reduce-only minimum-notional exemption.
- Ledger currently assumes target index 0. Close-all needs bounded multi-target state, individual pre-send markers, IDs, proof and aggregation. Existing schema supports indexed targets; no migration currently indicated.
- Closing proof needs the submitted order's terminal evidence plus fresh same-scope position evidence. Cancel racing fills preserves executed quantity/exposure. Keep owner/session/version, confirmation, idempotency, live lease/fence and stale callback protections.
- API `connections.assert_action_supported` currently denies Binance after checking owner. Keeping it permits fixture-only code without changing connections.py. An environment trading flag alone is not a launch barrier.
- Generic Binance identity proof stays read-only. Demo authoritative UID/key-permission proof is unavailable; fixtures must not invent venue evidence.

## Coordinator proposals still requiring final synthesis

1. Retain default public Binance action denial even with trading enabled. Positive tests require an explicit fixture-only ledger policy plus injected fake transport; real native writes remain denied. No activation environment setting.
2. Reuse ledger infrastructure with explicit Binance branches and unchanged OKX contracts. Proposed actions: `close_position`, `partial_close`, `cancel_order`, `close_all`, product USD_M. Finalize exact identity schemas.
3. Proposed close-all cap: 20 nonzero positions sorted by symbol; reject unsupported enumeration before persistence. Mark only actually attempted targets. Stop after uncertain/failed sends; untouched tail retains null pre-send marker. Finalize aggregate statuses and final account-position proof.
4. Bind semantic identity, permissions/mode, native quantity/sign and raw filters/versions; exclude volatile quotes/PnL/time. Reject changes before send. Finalize partial-close quantities and allowed regular cancellation types.
5. Command-specific filters and safe error categories stay within task surfaces; add `test_binance_reads.py` to allowed tests if needed. Do not alter Spot parser or connection admission without a scope amendment.

## Resume sequence

1. Read T113, D-007, approved P04/spec and this checkpoint; load binding workflow rules as required.
2. Finalize `docs/agents/validation/2026-10-11-t113-preflight.md`, adopting both R2 reports with exact schemas, gates, multi-target state/proof, scope and Definition of Ready. Update task/plan/telemetry.
3. Inspect agent inventory, then dispatch new bounded E2 executor `gpt-6-luna/max`, `fork_turns=none`, explicit route; do not reuse E1 for E2.
4. Require before-change failure, formal negative RED before positive GREEN, focused V3 regressions, fresh backend compile and independent explicit R3 `gpt-6.1-sol/high` audit. Record source/runtime/venue verdicts separately.
5. Complete authorized source work while keeping unavailable VPS/demo evidence pending. Do not start T114 or perform new Git writes without authorization.

## Workspace preservation

Uncommitted coordinator changes: decision log D-007, main plan continuation, T113 task staging, 2026-10-11 telemetry and this checkpoint. User-owned `docs/agents/telemetry/events/2026-10-06.jsonl` was already modified: do not read its content/diff, mutate or stage it. No protected content or secrets were accessed to save this checkpoint.
