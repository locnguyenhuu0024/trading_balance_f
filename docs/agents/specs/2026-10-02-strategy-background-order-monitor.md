# Design Specification: Background Strategy Order Monitor

Status: READY_FOR_PLAN
Date: 2026-10-02
Tier: L
Decision Ledger: N/A — user decisions are recorded below.

## 1. Objective

Keep the existing exchange-side strategy orders: application submits every selected Long/Short limit order to OKX once. Add a separately running backend worker that checks whether those orders have filled while the browser is closed. The worker never places, amends, or cancels an order. For an applied strategy dashboard, the browser obtains current quotes and account metrics only through the authenticated backend; the strategy creation wizard keeps its existing market-data path.

Success: a filled or partially filled order becomes visible in durable strategy state without a browser request; restart/duplicate workers do not issue trades or corrupt order state; the browser shows each order's fill state and uses no direct OKX request for applied-strategy quotes.

## 2. Current State and Evidence

| ID | Source | Observation |
|---|---|---|
| OBS-001 | `backend/strategy.py`, `_execute`/`_okx_order` | Apply sends a batch of limit orders to OKX once; ACK decides APPLIED/PARTIAL/UNKNOWN. |
| OBS-002 | `backend/strategy.py`, `_result_for`/`_reconcile_orders`/`_list` | GET result/list performs order-detail reconciliation and reads positions/PnL. No requests means no further local sync. Reconciliation already checks instrument, client ID, size, fill amount, and states. |
| OBS-003 | `backend/store.py` | SQLite persists strategy/results and apply lease, but no monitor lease or last successful scan. |
| OBS-004 | `backend/app.py` | WSGI service initializes lazily per process; a per-worker daemon thread would not provide a reliable single background owner. |
| OBS-005 | `lib/features/strategy/presentation/providers/strategy_dashboard_provider.dart` | The visible dashboard directly polls OKX ticker each second and calls backend list every 20 seconds; both timers stop when page/app is hidden. |
| OBS-006 | `lib/features/strategy/presentation/strategy_screen.dart` | Running cards show aggregate metrics but no per-order fill count/status. |

Official OKX API reference: [order details and rate limits](https://app.okx.com/docs-v5/en/#rest-api-trade-get-order-details), [positions](https://www.okx.com/docs-v5/en/#rest-api-account-get-positions). The design uses read-only exchange endpoints and conservatively limits request volume.

## 3. Scope and User Decisions

In scope: applied strategy order-state monitoring, durable freshness/error metadata, completion detection, authenticated backend quote forwarding for the applied dashboard, per-order fill display, and worker startup instructions. Out of scope: changing upfront batch placement, sequential trigger orders, TP/SL, auto cancellation, notifications, changing the wizard's OKX market-data calls, or other app screens.

- D-001: Keep all selected limit orders on OKX immediately after Apply. Worker only reads already submitted orders.
- D-002: Target one order-state scan per eligible strategy every 5 seconds. Back off on exchange errors/rate limits; show freshness honestly instead of promising a fixed latency.
- D-003: Partial fill counts as activated and displays filled quantity separately.
- D-004: Stop scanning a strategy and mark it COMPLETED after every submitted order is terminal and OKX has no position for that instrument. Querying position only for this completion decision is permitted; continuous background price/PnL sampling is not.
- D-005: For applied strategies only, browser quote requests go to backend. Backend reads OKX when the page is visible; PnL/position are obtained via existing backend list/result reads. The wizard remains unchanged. Preserve the existing one-second visible quote refresh and stale-price display.
- D-006: Run one separately supervised Docker worker using the existing backend image and shared SQLite data. The user provides the worker env values privately on the server. The original `/home/deploy/trading_balance_f/trade-api-worker.env` location was superseded after `sudoedit` refused to edit a file under that writable directory; use the root-owned `/etc/trading-balance/trade-api-worker.env` location instead.

## 4. Requirements

### REQ-001 — Read-only durable order synchronization

The worker MUST select already attempted, noncompleted strategies for the active OKX account and reconcile each nonterminal submitted order by its stored client order ID. It MUST reuse the existing identity/size/fill validation and preserve the last known state when OKX data is absent, malformed, or unavailable. It MUST persist `lastOrderScanAt`, last scan outcome, order status, filled contracts, and average fill price. A partial fill is an active fill. The worker MUST NOT invoke an exchange write endpoint.

### REQ-002 — Single owner, restart, and rate safety

At most one worker owns active scanning of the shared SQLite database at a time. Use an atomic, expiring lease/fence; never hold a database transaction during a network request. Fenced writes and existing per-strategy compare-and-swap MUST prevent stale/duplicate workers and concurrent API GET reconciliation from overwriting newer state. On restart or lease loss, resume safely without repeating order placement. Target a 5-second healthy scan cycle; bound exchange calls and apply retry/backoff under errors or throttling.

### REQ-003 — Completion and API visibility

When all strategy order rows are terminal (`filled`, `canceled`, `mmp_canceled`, `rejected`, or `not_submitted`) and a fresh OKX positions read confirms no open position for the instrument, persist immutable `COMPLETED` and stop scanning it. Never complete on an unavailable positions read or unknown order. Existing and new applied strategies are eligible. Authenticated list/result responses MUST include order-state freshness and keep existing actual position/PnL behavior when requested.

### REQ-004 — Backend-fed visible quote

Add an authenticated strategy quote read for an applied strategy ID. Validate ownership, active status, OKX instrument identity, positive exact Decimal last price, and exchange timestamp/freshness. Return instrument ID, exact last price, and observed time without credentials. The browser dashboard calls only this backend endpoint for applied-strategy quotes at the existing visible one-second cadence; no quote polling runs when hidden. The wizard's instruments/candles/ticker path remains unchanged.

### REQ-005 — Per-order dashboard status

For each submitted order, show side, entry/DCA role, limit price, planned contracts, current exchange-derived status, filled contracts, and average fill price when available. Distinguish partial from full fill; show scan age/error when stale. Show `COMPLETED` distinctly while retaining the strategy record and its order outcomes. Existing draft and confirmation flows remain intact.

### REQ-006 — Preserve upfront OKX limit placement

After the user's final confirmation, Apply MUST still submit every selected Long and/or Short entry and DCA row as `ordType=limit` through the existing OKX batch endpoint, with the reviewed prices and contract counts. The worker MUST NOT defer these orders until price reaches a level or submit them again. Preserve existing partial/unknown batch ACK and reconciliation safeguards.

## 5. Data and Interface Contract

| Field | Type | Source | Meaning/absence |
|---|---|---|---|
| `orders[].status` | enum string | OKX detail or existing ACK | `accepted`, `live`, `partially_filled`, `filled`, `canceled`, `mmp_canceled`, `rejected`, `unknown`, `not_submitted`. Missing/unknown is never treated as filled. |
| `orders[].filledContracts` | exact decimal string/null | OKX `accFillSz` | Quantity already matched; `0 < filled < planned` is partial activation. |
| `orders[].averageFillPrice` | exact decimal string/null | OKX `avgPx` | Present when exchange supplies it. |
| `lastOrderScanAt` | UTC timestamp/null | worker/API fallback | Time of last successful full order-state scan, distinct from strategy edit time. |
| `orderSyncState` | `fresh`/`stale`/`error` | backend | Last attempt quality; retain last known order data on failure. |
| `quote.instrumentId` | string | backend-validated OKX ticker | Must equal owned strategy instrument. |
| `quote.lastPrice` | exact positive decimal string | OKX ticker | No floating-point rewriting. |
| `quote.observedAt` | UTC exchange timestamp | OKX ticker | Reject future or older-than-15-second quote. |

New status `COMPLETED` is immutable and not draft-deletable. Quote API shape: `GET /v1/strategies/{id}/quote` -> `{instrumentId,lastPrice,observedAt}`. Existing list/result paths remain authenticated and retain previous fields. No public unauthenticated market proxy is introduced.

## 6. Invariants and Failure Semantics

- INV-001: Apply is the only strategy path allowed to place orders; worker and quote endpoint are read-only against OKX.
- INV-002: Never attribute another account/instrument/client ID/size to a strategy. Check account fingerprint before worker processing.
- INV-003: A stale worker cannot write after lease loss; a failed OKX read cannot mark a fill or completion.
- INV-004: Browser closure affects only visible quote/metrics reads, not already placed orders or worker scanning.
- INV-005: The user-owned worker env and any protected runtime/Docker configuration are never read or written by agents.

Failure cases: OKX timeout/429/invalid details => retain data, mark stale/error and back off; worker crash => lease expires and replacement resumes; account mismatch => do not scan or mutate that account's orders; unknown placement outcome => reconcile only by existing client IDs; positions unavailable => no COMPLETED transition. Frontend quote failure => retain last quote with its original timestamp and mark stale, never present it as current.

## 7. RED / GREEN and Acceptance

- RED-001 / GREEN-001 / AC-001: Without any browser request, fake OKX changes a submitted order from live to partial to filled; worker persists each validated state/filled quantity, with zero OKX write calls.
- RED-002 / GREEN-002 / AC-002: Two workers race, one loses lease or crashes during an OKX read; only current owner persists, restart resumes, and no placement repeats.
- RED-003 / GREEN-003 / AC-003: All orders terminal plus zero position => COMPLETED; unavailable positions, unknown order, or remaining position => not completed.
- RED-004 / GREEN-004 / AC-004: Applied dashboard quote previously reaches public OKX directly; after change its request goes only to authenticated backend once per second while visible, with freshness/out-of-order guards. Wizard market calls remain unchanged.
- RED-005 / GREEN-005 / AC-005: Running card shows individual partial/full/canceled states and filled quantity; stale scan is visible and not mislabeled current.
- GREEN-006 / AC-006: Apply submits the reviewed Long/Short entry and DCA rows as OKX limit orders in one batch; the worker performs zero exchange writes on every scan/restart path.

Formal RED precedes GREEN for each implementation task. Offline fake OKX verifies no exchange writes. Python backend compile and Flutter web build are mandatory task/final gates. Live worker deployment and production confirmation are user-owned after code approval.

## 8. Security, Performance, Rollout

Only the backend accesses credentials. The worker env file must contain `OKX_API_KEY`, `OKX_API_SECRET`, `OKX_API_PASSPHRASE`, `SESSION_SIGNING_KEY`, and `OPERATION_DB_PATH`; values must match the API account/key and shared mounted database. The worker does not need admin password, TOTP, or web origin. The user creates the file at the approved path and restricts its permissions. Agents never inspect its contents.

Bound work to nonterminal orders; at most 20 selected orders per strategy. Space requests within the documented OKX limits; if the backlog cannot fit a 5-second cycle, delay fairly and expose actual scan age. No network call inside a SQLite transaction. Retain existing applied strategy rows across deployment and include them in the first scan. Rollback stops the worker and returns to request-triggered reconciliation; do not cancel OKX orders or delete strategy data. Production validation is blocked until the user supplies the worker env and runs the separate container.

Traceability: REQ-001 -> AC-001/005; REQ-002 -> AC-002; REQ-003 -> AC-003; REQ-004 -> AC-004; REQ-005 -> AC-005; REQ-006 -> AC-006.
