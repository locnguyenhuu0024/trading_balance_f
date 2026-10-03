# Design Specification: Strategy Submission Diagnostics

Status: READY_FOR_PLAN
Date: 2026-10-02
Tier: M
Decision Ledger: N/A — diagnostic instrumentation; no trading semantics change

## 1. Objective and evidence

Give operators a safe local diagnostic trail for failed OKX limit submissions in both API and worker containers.

| ID | Source | Observation |
|---|---|---|
| OBS-001 | `backend/strategy.py`, `_execute` | Sequential execute durably enqueues; the API does not send those orders. |
| OBS-002 | `backend/strategy_worker.py`, `run_once` | Account-read failure, invalid identity, lease contention/loss and empty selection can return silently. |
| OBS-003 | `backend/okx.py`, `request`, `_network_transport` | Errors intentionally suppress raw response/exception text; numeric exchange codes are bounded. |
| OBS-004 | `backend/app.py`, `__call__` | Origin/auth/body and unexpected errors can occur before strategy dispatch, without diagnostic events. |
| OBS-005 | `backend/strategy.py`, `_parse_batch_ack` | Stored batch item codes must be independently sanitized for logging. |

Production failure: user reports orders still cannot be submitted; no screenshot, safe runtime log, or production reproduction is available. Absent worker, incompatible deployment, different stores/accounts, preflight failure, exchange rejection, expired queue and uncertain acknowledgement are UNCONFIRMED hypotheses. Logging does not constitute a root-cause fix or proof of live submission.

## 2. Scope and requirements

- REQ-001: Trace prepare/execute requests, frozen mode, enqueue/no-op, preflight, leverage, batch/individual placement, and committed/refused outcomes.
- REQ-002: Explain worker availability with startup, shutdown, fatal category and throttled heartbeat. Report lease/account-read outcome, selected and attempted counts, and eligible/matching-eligible counts without account identifiers.
- REQ-003: Explain OKX reads used by submission preflight and the three submission writes using fixed endpoint labels, duration, safe HTTP status, numeric top/item codes and fixed response-shape hints.
- REQ-004: Emit bounded JSON lines to local stderr, available through Docker logs. Use standard library only; no new configuration, dependencies, storage/schema, public endpoint or UI.
- REQ-005: Logging is best effort and isolated from trading: no exchange retries, extra exchange requests, changes to payloads, API response contracts, confirmation consumption, markers, leases, deadlines, pacing, reservations, cursor/state or reconciliation.

The reported production failure remains unverified. This task supplies evidence for a later diagnosis. Runtime deployment and real financial orders are outside this change.

## 3. Architecture and data contract

Add `backend/diagnostics.py`: central static schema validation -> nonblocking bounded queue -> daemon sink -> JSON stderr lines. Maximum queue length 256; drop on full or invalid record; no synchronous sink on request/worker paths. Start lazily once per process, after fork; process-aware initialization prevents inherited dead threads. No logging within DB transactions. Never wait for the sink during order processing; optional bounded shutdown drain at most 250 ms outside processing. A stalled sink can lose logs but cannot block lease/deadline work. Emit a bounded dropped-event count when the sink next progresses.

Schema version 1. Allowed fields only:

| Field | Contract |
|---|---|
| timestamp | UTC timestamp generated locally |
| event, component, stage, outcome, reason, endpoint, method, submission_mode, side, status, ack_shape | Fixed internal enums, never arbitrary text |
| strategy_ref, order_ref | First 16 hexadecimal SHA-256 characters with separate namespace prefixes; derive only from strategy ID and prepared client ID, never from tokens/account identity |
| order_index | Integer 0..19 |
| order_count, attempted_count, accepted_count, pending_count, not_submitted_count | Integer 0..20; booleans invalid |
| eligible_count, matching_eligible_count, selected_count, pass_count, dropped_count | Nonnegative integers capped at 1,000,000 |
| http_status | Integer 100..599 |
| top_code, item_code | Existing `bounded_error_code` semantics; revalidate independently |
| api_code | Static allowlist of existing codes relevant to these routes; unknown maps to `other` |
| elapsed_ms | Finite nonnegative integer, capped at 600,000 |
| data_count | Integer capped at 21 |
| persisted | Boolean: observed ACK is distinct from committed ledger outcome |

Omit unavailable fields. Records at most 4 KiB; no recursive traversal or copying payload dictionaries. Hash refs allow API/worker correlation while avoiding raw caller/exchange identifiers. Prepare/execute boundary events classify routes with existing route grammar, never log raw URL, query or origin. Unauthenticated failure may carry the hashed route strategy reference but no bearer/body. Other routes remain unaffected.

Safe events cover request start/end/failure, preparation success, enqueue/no-op, worker startup/shutdown/fatal, heartbeat, selection, preflight result, leverage/order write attempt, observed outcome, transition commit/refusal, queue stop and batch summary. Attempts are logged only after existing write markers commit; an event is not itself a marker. Logging must not imply accepted means filled. Use context-local submission correlations for synchronous OKX preflight/write events; do not share mutable request context across threads.

Transport errors may gain optional content-free diagnostic category and HTTP status while preserving type/message/error-code contracts. Categories distinguish HTTP rejection, oversize, malformed JSON, nonobject response, malformed data and transport failure. Use fixed shape hints for invalid/missing codes, cardinality, row type, client identity mismatch, missing order ID, leverage identity mismatch and top-level conflict. Never use raw ACK strings to derive log text.

Worker heartbeat is emitted at most once per 60 seconds per process, with a first-pass event. Read-only eligible counts use the same existing eligibility semantics and current account; they explain selection context, not prove deployment correctness. No database path, UID, fingerprint or account hash is emitted. Fatal logging re-raises existing failures; it does not turn a failed worker into a successful pass.

## 4. Safety, invariants and edge behavior

- INV-001: Exchange calls, exact payloads, durable state and no-resend behavior match the existing implementation with diagnostics disabled, working or failing.
- INV-002: Never emit headers, credentials, signatures, confirmation/session tokens, bodies, raw responses/messages, exception text/stack traces, database/env paths, account data, price/size/margin/leverage amounts, or arbitrary extra fields.
- INV-003: An ACK observation followed by fence/CAS loss is explicitly unpersisted; no success event may claim a failed commit.
- INV-004: Logging enqueue/sink failure cannot propagate or cause retry; slow sinks cannot hold transactions or order execution.
- INV-005: Existing unknown/rejected/stopped semantics remain conservative; no guessed production fix.

Hostile ACK strings/codes/IDs are omitted or mapped to fixed hints. Oversized/full/stalled/raising sinks drop events safely. Concurrent request contexts remain isolated. Startup events do not include environment values. Heartbeats prevent idle-pass log floods.

## 5. RED / GREEN and acceptance

RED-001: Inject credential canaries, newlines/ANSI, nested/large fields and transport exception text; force rejected/unknown ACK, fence refusal and full/stalled/raising sink. Logs contain no canaries/raw text; tail stays unsent, write counts/state match baseline, and producer completes while sink remains blocked.

GREEN-001: Fake successful sequential flow emits prepare/enqueue -> worker selection/preflight -> leverage -> FIFO order attempts/ACK -> committed outcomes with stable refs. Batch mixed results produce bounded numeric codes/counts. Fake HTTP/JSON failures produce distinct content-free categories. No live OKX request.

| AC | Requirement | Observable proof |
|---|---|---|
| AC-001 | REQ-001, REQ-003 | Each failed stage is identifiable; observed versus persisted outcomes distinguish fence loss. |
| AC-002 | REQ-002 | First pass and throttled heartbeat explain no-due/account/lease branches without identity data. |
| AC-003 | REQ-004 | Valid bounded JSON lines and documented API/worker Docker log commands; no configuration requirement. |
| AC-004 | REQ-005 | RED privacy/sink/no-resend tests and GREEN call/state parity; existing affected regressions pass. |

## 6. Compatibility, rollout and completion

API/data/schema compatibility unchanged; only optional internal safe error metadata and diagnostics are added. No protected configuration file access/write or external service upload. Update the existing deployment guide with commands and interpretation, including missing worker, no eligible row and incomplete acknowledgement examples using fictional refs/codes.

Operators deploy the same code image to API and worker using their existing process; no automatic deployment in this task. Existing container log retention is operator-owned and unchanged. Rollback uses prior matching binaries while preserving all queue markers and current data safety rules. Dropped diagnostics and missing logs cannot establish that no exchange request occurred.

Completion requires T61 PASS, RED before GREEN, relevant offline tests, backend compile and final integration audit. Real production resolution remains pending runtime evidence.
