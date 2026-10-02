# Design Specification: Strategy Limit Order Queue

Status: READY_FOR_PLAN
Date: 2026-10-02
Tier: L
Decision Ledger: `docs/agents/decisions/2026-10-02-strategy-limit-order-queue-decisions.md`

## 1. Objective

Offer an account-scoped choice between durable sequential limit submission and the existing batch mechanism. Add a top strategy Settings action opening a modal whose first item selects that mechanism. Sequential mode sends each reviewed order through the OKX single-order endpoint and records its result before advancing.

## 2. Current evidence

| ID | Non-protected source | Observation |
|---|---|---|
| OBS-001 | `backend/strategy.py`, `_prepare`, `_execute`, `_okx_order` | Confirmation consumes a token once, reserves account/instrument, sets isolated leverage, and places one batch of reviewed limit rows. |
| OBS-002 | `backend/okx.py`, `place_order` | Single-order endpoint support already exists. |
| OBS-003 | `backend/store.py`, `backend/strategy_worker.py` | SQLite transactions, additive schema changes, and a fenced singleton worker lease already exist; the worker currently monitors only. |
| OBS-004 | `lib/features/strategy/presentation/strategy_screen.dart` | Top AppBar currently has refresh; both saved-draft and wizard paths have final order confirmation. |
| OBS-005 | `strategy_dashboard_provider.dart` | Apply executes once and never retries an uncertain write; provider lifecycle is bearer-scoped. |
| HYP-001 | User report | Batch placement may be failing in production. Unconfirmed locally; this change provides another mechanism without claiming to diagnose that failure. |

Planning evidence was independently collected by LQ-BE-PLAN (R3) and LQ-FE-PLAN (R2), then reconciled by the coordinator. No live placement was performed.

## 3. Scope and decisions

Implement preference, modal, confirmation snapshot, durable queue, worker placement, per-order visibility, additive data migration, and compatibility tests. Existing sizing, tick rounding, isolated leverage, hedge-mode rules, twenty-order cap, and exact reviewed payloads remain governing contracts. Automatic cancellation, order amendment, stops, take profit, real-account trading tests, and operational configuration changes are outside scope.

D-001 and A-001 through A-006 in the decision ledger resolve material choices. No open questions remain.

## 4. Requirements

### REQ-001 — Strategy settings modal

Add a top AppBar Settings button with a Vietnamese tooltip. It opens a responsive, scrollable modal titled `Cài đặt chiến thuật`, structured as an extensible list of sections. Its first expandable item is `Cơ chế gửi lệnh limit`, offering `Hàng đợi tuần tự` and `Gửi theo lô`. Explain that sequential advances after acknowledgment, not fill. Provide explicit `Lưu` and `Hủy`; show loading and errors, keep edited selection after save failure, and acknowledge saving only after server confirmation. Signed-out users may open the modal but receive a login explanation and cannot save.

### REQ-002 — Account-scoped preference

Authenticated `GET /v1/strategies/settings` returns `{limitOrderSubmissionMode: sequential|batch}`. Authenticated `POST` on that path validates and persists the same field and returns the acknowledged preference. Reuse session, origin, rate-limit, and active account protections. Missing preference defaults to sequential; invalid values return 400 without a write. Store the preference by account fingerprint in application data, never in env/config files. Errors must not silently masquerade as a saved default.

### REQ-003 — Immutable confirmation mode

New preparation reads the current account preference, freezes `submissionMode` with exact prepared orders, and binds it to the existing single-use confirmation. Both confirmation paths display that mode and its behavior. Execute remains token-only and never re-reads the preference to choose a mode. Legacy prepared records without a mode execute as batch; historical batch records are reported as batch. New frontend rejects a missing/invalid prepared mode before execute. An old backend therefore cannot silently substitute batch for the selected queue mode.

### REQ-004 — Durable sequential submission

Sequential execute atomically consumes confirmation, sets APPLYING, creates the durable queue, and acquires the account/instrument reservation. Return the queued record immediately; the worker owns all sequential exchange writes. Send frozen prepared rows in their existing FIFO order: Long nearest-to-farthest, then Short nearest-to-farthest, retaining equal-price rows and distinct IDs. Only one sequential placement may be in flight across the worker. At most 20 placements per worker pass; at least 250ms between placement request starts. All rows remain `ordType=limit`, `tdMode=isolated`, `ccy=USDT`, with reviewed `px`, `sz`, `side`, `posSide`, and `clOrdId`. Browser closure has no effect on durable work.

### REQ-005 — Persist-before-send and ambiguity safety

Before every leverage or placement write, renew/check ownership, atomically record its in-flight marker under the current worker fence, and commit. No network call runs inside a DB transaction. After the response, persist the validated outcome, clear the marker, and advance the cursor in one fenced transaction. A placement acknowledgment requires exactly one matching `clOrdId`, successful codes, and a nonempty exchange order ID. Explicit rejection stops the queue and marks untouched rows not_submitted. Transport uncertainty, malformed acknowledgment, or an interrupted in-flight marker stops the queue with UNKNOWN and preserves the attempted row as unknown. Neither execute replay, reads, worker restart, nor later reconciliation may resend that row or restart its stopped tail. Exchange not-found does not prove it was never attempted.

### REQ-006 — Deadline and restart validation

Persist a placement deadline of atomic enqueue time +120 seconds, separate from the consumed confirmation token expiry. Check it before each external write. Expiry stops the untouched tail with `queue_expired` while preserving prefix outcomes and uncertainty.

Before initial queue side effects, repeat full existing account/position/pending-order/balance preflight and compare the prepared preview hash. Persist successful per-side leverage results, then repeat full preflight before the first order. Verify unchanged position mode as well as fingerprint/hash. Renew/check the worker lease before every external read and write, including reads within preflight.

Restart with a committed acknowledged prefix and no in-flight marker can resume only within deadline after fresh account/mode validation and `_preview_contract` hash equality. Omit initial zero-position/no-pending/full-budget guards on this resume because the queue's own orders/fills may satisfy them; retain the reservation. Never regenerate payloads or repeat successful leverage writes. Metadata/marketability changes stop untouched rows; interrupted leverage writes stop conservatively. A stopped queue is permanent even if later reads resolve the uncertainty.

### REQ-007 — Legacy and monitor compatibility

Retain the existing batch path and `batchAttempted` meaning. Generalize actual placement evidence as `orderPlacementAttempted = batchAttempted OR sequential attempt marker` for recovery eligibility, deletion, reservation release, and T56 replacement cleanup. An active queue must bypass API interrupted-batch recovery and monitor aggregation. Never query order details for queued, sending, or intentionally not_submitted rows. Reconcile attempted accepted/unknown rows after submission ends, preserve historical placement acceptance while exchange fill status evolves, and aggregate resolved prefix plus stopped tail as PARTIAL. Preserve fresh-zero-position completion and existing batch restart/fencing tests. A strategy with any attempted placement must never acquire a never-sent deletion/replacement permission.

### REQ-008 — Honest client state and session boundaries

Show the frozen mode, queue phase/progress, and per-row states during APPLYING and afterward. Distinguish queued, sending, accepted, filled, rejected, unknown, and not_submitted. Durable enqueue success is a `queued` apply outcome; HTTP success or accepted orders do not prove fills. Continue existing read-only visibility-based polling. Guard controller disposal/session ownership after each prepare/confirmation/settings await; logout/account switch disables or closes owned modal/confirmation routes and prevents stale callbacks from executing or presenting settings success for another session.

## 5. Data and interface contract

| Field | Type / values | Meaning |
|---|---|---|
| limitOrderSubmissionMode | sequential / batch | Account preference; default sequential when no application preference exists. |
| submissionMode | sequential / batch / null | Frozen preparation/attempt mechanism; null for a draft not yet prepared. Legacy prepared/attempted rows are batch. |
| orderPlacementAttempted | boolean | At least one placement reached its durable pre-send marker; includes legacy batch evidence. |
| queueStatus | null / pending / sending / stopped / submitted | Null for batch. Submitted means all placement acknowledgments succeeded, independently of fills. |
| queueProgress | nullable object | totalCount, attemptedCount, acceptedCount, pendingCount, notSubmittedCount; nonnegative integers bounded by totalCount. |
| order.status | queued / sending plus existing statuses | Queue rows expose progress without inferring exchange fill state. Stopped untouched tail becomes not_submitted. |
| order.placementState | pending / sending / accepted / rejected / unknown / not_submitted | Sequential submission provenance retained when status later becomes live/filled/canceled. Legacy rows may omit it. |

Add an account preference table keyed by account fingerprint, and additive strategy columns `submission_mode` (legacy default batch), `order_placement_attempted` (default 0), and nullable `queue_json`. Queue JSON stores phase, cursor, enqueue/deadline, in-flight kind/index/side, and bounded safe stop reason. Existing frozen prepared rows and results remain payload/outcome sources. Derived progress uses durable attempt and placement provenance, never fill assumptions.

All externally displayed times use existing UTC serialization. Client uses the existing bearer transport. No credentials or raw exchange response messages are added to payloads/logs.

## 6. Control flow and invariants

```text
Settings GET/POST -> account preference
prepare -> frozen mode + exact reviewed orders -> explicit confirmation
execute(token) -> batch path OR atomic durable queue
worker lease -> fresh validation -> persisted leverage -> repeated validation
-> marker -> single-order request -> validated durable ACK -> next row
-> submitted/APPLIED OR stopped/PARTIAL|UNKNOWN
-> existing read-only fill/position reconciliation
```

- INV-001: Every attempted row has its original reviewed client ID, price, and contracts.
- INV-002: An uncertain attempt is never automatically repeated; a stopped tail is never resumed.
- INV-003: Every side effect and outcome commit is ownership checked; an old fence cannot advance queue state.
- INV-004: No transaction holds a network call, and no API read drains a queue.
- INV-005: Preferences never alter prepared/active historical attempts.
- INV-006: Accepted means acknowledged placement, not filled; completion still requires terminal rows and a fresh zero position.
- INV-007: Account-bound application data never crosses identities, and placement evidence prevents false never-sent eligibility.

## 7. Failure and edge cases

| Condition | Required result |
|---|---|
| Worker unavailable / delayed | Show pending truthfully; expire on worker resumption if deadline passed, with zero late placements. |
| Order 2 rejected in 3-row queue | Preserve row 1 accepted, row 2 rejected, row 3 not_submitted; PARTIAL; no third request. |
| Timeout or crash after row 2 marker | Preserve row 1, row 2 unknown, row 3 not_submitted; UNKNOWN; no retry across restarts. |
| Crash after row 1 ACK committed | Resume only untouched rows after fresh resume validation within deadline. |
| Lost fence | No new placement or state advance; surviving in-flight evidence is handled conservatively by successor. |
| Preference changes while confirmation open | Execute original snapshot; next preparation uses new preference. |
| Account switch during modal/confirmation | Discard stale results, disable owned actions; zero execute for disposed session. |
| Changed quote/metadata/mode or expired deadline | Stop untouched tail, preserve prior outcomes; report bounded reason. |
| Active/stopped queue result read | No batch recovery; no lookup for unsent client IDs; no write retries. |
| Old prepared/batch history | Preserve batch execution and monitor/replacement behavior. |

## 8. Acceptance and RED/GREEN contracts

| AC | Requirements | Independently specified evidence |
|---|---|---|
| AC-001 | REQ-001/002/008 | Account preference persists, default sequential, invalid/write-failure/session paths do not claim success; mobile/desktop modal works. |
| AC-002 | REQ-003 | Both confirmations display and freeze mode; later preference changes cannot affect execute; malformed prepared mode causes zero execute. |
| AC-003 | REQ-004 | Three reviewed rows enqueue durably, produce three ordered single requests with exact payloads and no batch call, minimum spacing, and browser independence. |
| AC-004 | REQ-005 | Reject/timeout/crash marker halts tail; restart/read/replayed execute never resend attempted rows. |
| AC-005 | REQ-006 | Valid ACK-prefix restart resumes safely; deadline, mode/account/hash changes and lost fence prevent further writes. |
| AC-006 | REQ-007 | Legacy batches, attempted-only monitoring, reservations, completion, never-sent replacement/deletion and migrations remain safe. |
| AC-007 | REQ-008 | APPLYING shows frozen mode and individual progress; queued success differs from unknown; accepted differs from filled. |

RED-BE: Simulated three-row queue times out on row 2. Assert exactly two placement calls, row 3 unsent, and no replay after worker restart, result reads, reconciliation, or duplicate execute. Execute this negative scenario before GREEN-BE.

GREEN-BE: Simulated three-row queue returns matching success ACKs. Assert durable atomic enqueue, three exact FIFO single requests with >=250ms spacing, no batch call, and APPLIED/submitted with acceptedCount=3. Separately test valid prefix restart and old batch migration.

RED-FE: Logout while confirmation is pending and fail a settings save. Assert zero execute, no stale account success, retained draft/error, and no false save claim. Execute before GREEN-FE.

GREEN-FE: Open modal at mobile/desktop sizes, choose/save/reload a preference, prepare a frozen mode, display it on both confirmation paths, and show queued results progressing through read-only refresh.

## 9. Rollout, rollback, performance and completion

No new env, dependency, Docker, deployment, or toolchain configuration is required. Runtime SQLite application migrations are additive and performed by the bounded executor code. Document API+worker coordinated upgrade: stop old API/worker, back up application DB through normal operator procedures, deploy the same new image to both, start worker/API, then publish the compatible client. Do not expose sequential queues to an old read-only worker. Production rollout and live trading are separate explicit actions.

Rollback preference to batch for future preparations after existing queues finish or stop. Stopped tails remain untouched; queued uncertain attempts retain durable evidence. Do not erase queue/attempt markers or run old binaries against pending sequential work. Report actual scan age and queue status; no promise of placement before deadline under arbitrary backlog.

Completion requires T59 and T60 PASS, ordered RED/GREEN evidence, affected backend tests and canonical web build, final integration audit, and no unexplained or protected configuration changes.
