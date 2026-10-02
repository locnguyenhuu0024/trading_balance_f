# Design Specification: Never-Sent Strategy Replacement

Status: READY_FOR_PLAN
Date: 2026-10-02
Tier: L
Decision Ledger: `docs/agents/decisions/2026-10-02-strategy-never-sent-replacement.md`

## 1. Objective

Allow deletion of a strategy whose order batch was certainly never attempted, and allow a replacement built from newly fetched candles and newly selected levels. The replacement must show a fresh server-prepared order list and require explicit confirmation. Remove the old strategy only after OKX accepts every replacement order.

## 2. Evidence and diagnosis

| ID | Evidence | Observation |
|---|---|---|
| OBS-001 | User-provided read-only production query | Latest strategy: `COMPLETED`, `batch_attempted=0`, ten `not_submitted` orders, leverage `rejected`, no retained failure reason. |
| OBS-002 | `backend/strategy.py:_execute` | Leverage is set before `place_batch_orders`; rejected leverage exits before the batch marker is set. |
| OBS-003 | `backend/strategy_worker.py:_process_strategy` | `not_submitted` counts as terminal; zero position can overwrite the strategy with `COMPLETED` and clear its failure reason. |
| OBS-004 | `backend/strategy.py:_delete` | Only a never-attempted `DRAFT` can be deleted now. |
| OBS-005 | `lib/features/strategy/presentation/strategy_screen.dart` | The card hides `failureReason` and `leverageResults`; it labels `COMPLETED` as finished even with no submitted orders. |
| OBS-006 | `backend/okx.py:request` | A nonzero top-level exchange code becomes a generic error; leverage row `sCode` is also not retained. |

The exact OKX leverage rejection cause cannot be recovered from this record. The application supports at most 20 selected levels; that source limit does not establish OKX's current API limit. The observed attempt did not reach batch placement.

## 3. Scope and decisions

In scope: guarded deletion, never-sent status repair at the API boundary, worker completion fix, safe leverage error-code retention, replacement association, fresh wizard flow, automatic old-record deletion after full acceptance, and focused tests.

Out of scope: canceling or modifying OKX orders, automatically retrying an uncertain batch, changing credentials/environment files, and claiming a precise cause for the historical leverage rejection.

Decisions D-001 through D-004 are in the decision ledger. No material clarification remains open.

## 4. Requirements

### REQ-001 — Trustworthy never-sent eligibility

The API MUST expose `batchAttempted` and `canDelete` for each strategy. `canDelete` is true only when `batch_attempted=0`, all persisted order results are `not_submitted`, no execution is active, and the authenticated OKX account owns the strategy. The delete endpoint MUST recheck those conditions in one transaction and remove its reservation/sync rows. A batch-attempted or currently applying strategy MUST receive 409 without deletion.

### REQ-002 — Accurate state and diagnosis

The worker MUST NOT mark a never-batched strategy `COMPLETED` merely because all rows are `not_submitted` and the position is zero. The API MUST present legacy `COMPLETED`/never-batched/all-`not_submitted` rows as a never-sent failure, preserving or safely deriving the known `leverage_rejected` reason from persisted leverage results. The UI MUST say that no limit order was sent, show leverage rejection when known, and avoid an irrelevant stale-order-scan warning for that state. Future leverage rejections MUST retain a bounded non-secret OKX error code when the response provides one; raw exchange message bodies remain excluded.

### REQ-003 — Fresh replacement and explicit confirmation

The replacement action MUST open the existing wizard using newly fetched market candles, require the user to choose new levels, obtain a fresh server preview/prepare response, display that exact list, and call execute only after explicit confirmation. It MUST generate a new strategy and new client order IDs; it MUST NOT re-arm or resend the old strategy or reuse its confirmation token. No automatic retry occurs after an unknown exchange outcome.

### REQ-004 — Automatic cleanup after full acceptance

The new strategy MUST carry an internal reference to the old eligible never-sent strategy. When the replacement batch has a complete acknowledgment and every new order is accepted, the backend MUST delete the old strategy with the same guarded eligibility predicate as REQ-001. For partial, rejected, unknown, canceled-before-confirmation, or pre-batch failures, the old strategy remains. If the process is interrupted after batch placement, recovery MUST apply the same cleanup only after it independently establishes full acceptance; otherwise it leaves the old record. The new batch result remains authoritative even if guarded cleanup cannot proceed.

## 5. Data and interface contract

| Field | Meaning |
|---|---|
| `batchAttempted: bool` | Persisted marker set before any batch order request; absent in older clients means no eligibility inference. |
| `canDelete: bool` | Server-computed hint; endpoint revalidates it. |
| `replacementSourceId: string?` | Internal relation from a new draft to the never-sent source; account-scoped and persisted before execution. |
| `leverageResults[].errorCode: string?` | Bounded exchange numeric/code token, never raw `sMsg` or credentials. |

`POST /v1/strategies` may accept `replacementSourceId` only when the source satisfies REQ-001. Existing preview, prepare, execute and delete routes remain the flow. The server validates the source again before order placement and during cleanup. If stale, return a safe conflict before sending; if it changes after placement, preserve both records and report the cleanup conflict without changing the batch outcome.

## 6. Invariants and edge cases

- INV-001: `batch_attempted=0` is the only authoritative proof that the batch request was never initiated; UI labels and order statuses alone are insufficient.
- INV-002: Neither delete nor replacement can cancel OKX orders; any `batch_attempted=1` record is immutable under this feature.
- INV-003: Repeated taps or retries cannot cause a second execute call for the same confirmation token.
- EDGE-001: Legacy `COMPLETED` + zero batch + all `not_submitted` remains eligible and displays as never sent.
- EDGE-002: An active `APPLYING` strategy is ineligible even while its batch marker is zero.
- EDGE-003: If current market validation or leverage setup fails again, no batch is sent and the old strategy remains.
- EDGE-004: A lost response after batch attempt is unknown; no automatic second batch or old-record deletion.

## 7. RED / GREEN acceptance

| ID | RED failure/boundary | GREEN intended behavior |
|---|---|---|
| AC-001 | Legacy false `COMPLETED` never-batched row | API/UI says never sent; worker does not complete or erase cause. |
| AC-002 | Applying or batch-attempted row | Delete/replacement rejected with no DB deletion or exchange write. |
| AC-003 | New wizard canceled or stale preview | No execute call; old row remains. |
| AC-004 | Replacement acknowledged with all rows accepted | One batch call with new IDs; old eligible row and dependent rows removed. |
| AC-005 | Partial/unknown batch outcome | Old row remains; no automatic retry. |
| AC-006 | Leverage rejection with OKX code | No batch call; safe code retained and shown without raw message. |

## 8. Rollout and rollback

Deploy API and worker from the same updated image, then the web client. Existing false-completed rows are handled by the API compatibility projection and guarded eligibility, without a production-wide database rewrite. Keep the SQLite backup before deployment. Rollback by restoring the prior image/web build; do not use the new replacement action while versions differ. Existing exchange orders are unaffected by rollback or database deletion.
