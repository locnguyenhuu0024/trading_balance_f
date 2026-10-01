# Design Specification: Live OKX position actions

Status: APPROVED_FOR_IMPLEMENTATION
Date: 2026-09-30
Tier: L
Decision Ledger: `docs/agents/decisions/2026-09-30-position-actions-live-decisions.md`

## 1. Objective and delivery boundary

Prepare real, production-capable position actions for the Transaction Management screen: add isolated margin, market DCA, partial close, close the selected position completely, and close all supported account positions. Every action requires a confirmation popup. The deliverable is repository code, local tests, and deployment instructions. Production activation and live-write verification remain user-owned follow-up because no server or Trade-enabled API key exists yet (D-009, D-012).

## 2. Current state and evidence

| ID | Source | Observation |
|---|---|---|
| OBS-001 | `lib/features/orders/data/order_repository.dart` | The repository reads positions and orders; it has no trade write methods. ALL aggregates MARGIN, SWAP, and FUTURES positions. |
| OBS-002 | `lib/features/orders/data/okx_position_model.dart` | The model lacks instrument type, position ID, and margin/position currency fields needed for action targeting. |
| OBS-003 | `lib/features/orders/presentation/orders_screen.dart` | Position cards are display-only, and the screen refreshes every one or five seconds. |
| OBS-004 | `test/features/orders/presentation/orders_screen_position_layout_test.dart` | The current layout test assumes there are no controls below the liquidation-price row. |
| OBS-005 | User-provided fact | The current OKX key is read-only; no private server/API exists. |

Official contracts: [positions](https://www.okx.com/docs-v5/en/#rest-api-account-get-positions), [increase margin](https://www.okx.com/docs-v5/en/#rest-api-account-increase-decrease-margin), [place order](https://www.okx.com/docs-v5/en/#rest-api-trade-place-order), [close position](https://www.okx.com/docs-v5/en/#rest-api-trade-close-positions), [order details](https://www.okx.com/docs-v5/en/#rest-api-trade-get-order-details).

## 3. Scope and decisions

In scope: MARGIN, SWAP, and FUTURES positions with complete identity and verified action eligibility. OPTION, SPOT positions, automatic credential provisioning, deployment, and live production trades are outside the present deliverable. D-001..D-015 in the ledger govern action semantics, account-wide scope, production target, backend location, authentication, user-owned configuration, and Docker on Ubuntu 24.04 LTS. No material product question remains open for code preparation.

The app must never route a production Trade key through Flutter web. HTTPS protects both network legs; the Python server alone holds and uses the key. Client-side encryption cannot make a signing key private from the browser runtime that signs with it. The existing read-only path may remain for display only.

## 4. Requirements and acceptance criteria

| ID | Requirement | Acceptance |
|---|---|---|
| REQ-001 | Preserve a complete target identity and reject zero-size, ambiguous, or unsupported positions. | AC-001: The card shows eligibility; no write request is sent when identity, side, mode, currency, or sizing metadata is insufficient. |
| REQ-002 | Add margin only to an eligible isolated position using the displayed margin currency and a positive validated amount. | AC-002: A confirmed eligible add sends one server command; cross/unknown modes cannot submit. |
| REQ-003 | DCA places a market order sized in the position unit only where OKX documents that unit exactly. | AC-003: Eligible derivative and MARGIN cases send the correct increasing side/mode/size; inexact MARGIN market-buy cases stay disabled with a reason. |
| REQ-004 | Partial close uses 25/50/75 or a custom percentage strictly between 0 and 100; size is rounded to valid instrument increments without exceeding the requested portion. | AC-004: Eligible cases submit one reducing market order; zero-after-rounding, below-minimum, inexact MARGIN, and position-change cases submit none. |
| REQ-005 | A card-level full close affects only the selected position and automatically cancels its pending closing orders under the supported OKX close-position contract. | AC-005: Confirmation identifies one target; success is reported only after a fresh position query confirms it closed. |
| REQ-006 | Page-level close-all fetches a fresh unfiltered set of all supported account positions and shows the exact target count/list before confirmation. If any supported open target is ineligible, preparation blocks the whole close-all action and lists the reasons. | AC-006: It ignores the display filter, rejects a changed target set before the first write, then submits per-position closes and reports success/failure/unknown per target; it never claims total success while any supported position remains open. |
| REQ-007 | Every mutation requires a distinct confirmation popup after input collection and current-position review. | AC-007: Cancel/dismiss/back sends zero writes; changed target invalidates confirmation; repeated confirm creates at most one operation. |
| REQ-008 | Only an authenticated user may call the private Python trade API; the Trade key remains server-only. | AC-008: Password+TOTP login produces a short-lived bearer session kept only in Flutter memory; missing/expired auth, wrong origin, replay, and duplicate operation are rejected. |
| REQ-009 | Server write outcomes are reconciled against OKX before the UI claims completion. | AC-009: Top-level and item-level OKX codes are checked; order IDs are queried when provided; a timeout becomes UNKNOWN and is not blindly retried. |
| REQ-010 | The app works in read-only mode before the user supplies a private API URL and backend credentials. | AC-010: Position data remains viewable; action controls explain their unavailable state without attempting a trade through the read-only client path. |

## 5. Data and cross-layer contract

Identity grain: one OKX position, keyed by instrument type, instrument ID, position ID when supplied, position side, margin mode, and margin/position currency where applicable. Store the raw signed position size and derive direction by documented product/mode rules; do not infer net direction from the displayed `NET` badge. Zero size is not open. A list snapshot has a server-generated short-lived confirmation token; the server re-fetches and compares material identity/size before submitting a write. After login, actionable position cards must come from the backend account's own `/v1/positions` response, with a masked account identifier shown in the UI; do not apply a server Trade action to a card sourced solely from a separate read-only client account.

Derivative market-order `sz` is in contracts. For MARGIN, OKX reports positive `pos` for both directions: `posCcy` equal to instrument base currency means long, and equal to quote currency means short. Missing or unrecognized `posCcy` disables all MARGIN actions that require direction. MARGIN market buy `sz` is in quote currency; market sell `sz` is in base currency. The available MARGIN fields do not establish exact additional trade capacity or currency-consistent debt limits for the first release, so MARGIN DCA and partial close are disabled with a reason. Eligible isolated MARGIN positions retain add-margin and 100% close. Margin-order `ccy` denotes the confirmed margin currency; margin-add `amt` is in that currency. Instrument minimum/lot size must come from OKX metadata, not a global decimal constant.

The client communicates with the Python backend through a narrow HTTPS JSON API: login, logout, backend-owned positions, prepare action, execute prepared action, and operation status. A loopback/proxy health route returns only a static healthy/unhealthy signal without secrets or account data. The prepare response contains the authoritative current target summary, eligibility, normalized size/amount, and an opaque short-lived operation token; Flutter renders that exact summary in the popup. Execute consumes the token once. Close-all prepare always reads the complete MARGIN/SWAP/FUTURES set, irrespective of the screen filter. It rejects a nonempty ineligible set rather than silently executing a partial target list. Execute re-queries the complete account set and rejects additions/removals/material changes before its first write. Any drift during execution is reported per target, and a final account-wide query determines whether the all-position objective was achieved. The backend serializes overlapping writes per position and records per-step state for duplicate suppression and timeout reconciliation.

The Flutter client rejects a public trade API URL unless it uses HTTPS and refuses redirects for private requests. The server binds a prepared operation to a keyed fingerprint of the full OKX account UID and verifies that binding before each write and before using an account snapshot to reconcile an uncertain result. A missing UID or missing legacy journal binding fails closed. Neither the raw UID nor its fingerprint is returned to the browser. Position controls snapshot the tapped target before awaiting input, and active flow state is keyed by full position identity so background refresh cannot redirect or misattribute the action. UNKNOWN and PARTIAL operation IDs remain accessible within the authenticated client session with an explicit later status lookup; lookup never resends execute. A close-all final-account uncertainty must be reconcilable after a later successful account query, including synthetic aggregate result rows.

Eligibility matrix for the first release:

| Action | SWAP/FUTURES | MARGIN |
|---|---|---|
| Add margin | Isolated only; known margin currency and positive amount | Isolated only; known margin currency and positive amount |
| DCA market | Exact contract size, valid net/hedge direction and lot/minimum | Disabled in this release because exact additional trade capacity cannot be proven from the available fields |
| Partial close market | Exact contract size, valid reduce-only/hedge rules and lot/minimum | Disabled in this release because exact base-size/debt/available limits cannot be proven together |
| Full selected / close-all | Complete identity, side, mode, and cancellation eligibility | Complete identity, mode, currency, and cancellation eligibility |

Any missing metadata or uncertain account/position mode disables that action. In particular, a MARGIN market buy denominated in quote currency must not be used to implement an exact base-unit DCA or percentage close.

## 6. Interaction and server state

```text
select action -> collect input -> server prepare/current snapshot -> confirmation popup
cancel -> no mutation
confirm -> authenticated execute once -> OKX acknowledgement -> reconcile -> result + refresh
```

The page-level close-all popup lists every eligible target, identifies ineligible/skipped targets, and shows a count. The destructive confirmation button states the account-wide scope. Auto-refresh must not overwrite a pending confirmation or conceal final per-position outcomes. A material target change returns a conflict and requires a new prepare/confirmation. The UI must not show a market price as guaranteed.

Server login uses an encoded scrypt password hash and TOTP seed supplied through server-only environment variables; passwords/OTP/Trade keys are never logged. Require at least 16 password characters in the user-run hash generator. TOTP uses 30-second steps with a one-step clock window; the last accepted counter is persisted and cannot be reused, including after restart. Persist a limit of five failed login attempts per source within 15 minutes. Sessions are random 256-bit bearer tokens held only in Flutter memory; store only token hashes, expire them after 10 minutes, and revoke them on logout. Verify secrets in constant time. The backend accepts only the configured web origin, enforces a bounded JSON body size and action rate limits, and requires the bearer token for every positions/prepare/execute/status call. CORS is browser isolation, not authorization. The operation journal stores non-secret IDs/state only and deduplicates execute requests. No trade command is sent on an authentication, stale-snapshot, precision, or eligibility failure.

## 7. Invariants, edges, and failure semantics

- INV-001: No Trade credential or OKX signing secret enters the Flutter bundle, local storage, logs, or API response.
- INV-002: Each prepared per-position step can initiate at most one OKX mutation attempt. Persist `ATTEMPT_STARTED` before the network call; repeated execute returns the recorded operation state and never sends another call. An unknown outcome is reconciled before any manual retry or new operation. OKX `autoCxl=true` is the documented close-position option that cancels pending closing orders within that per-target close request.
- INV-003: No page filter can narrow the close-all account target set.
- INV-004: A popup cancellation sends no mutation.
- EDGE-001: A position changes/disappears after preparation: execute rejects with a stale-target result; the user must review a fresh popup.
- EDGE-002: Percentage rounds below instrument minimum or to zero: reject before placing an order.
- EDGE-003: OKX returns top-level success with item-level error: report error, not success.
- EDGE-004: Close-all partly succeeds or times out: preserve and display each target outcome; no automatic repeat of unknown calls.
- EDGE-007: A new supported position appears between close-all prepare and execute: reject the entire unstarted batch for renewed confirmation. If it appears after execution starts, report the batch incomplete; do not close a target the user did not confirm.
- EDGE-005: Server URL is absent or login expires: display read-only positions and require login/setup before actions.
- EDGE-006: Supported type is present but unsupported mode/currency/size metadata is missing: disable that specific action with an explanation.
- EDGE-008: A process stops after an operation becomes `IN_PROGRESS` but before a target reaches `ATTEMPT_STARTED`: result lookup marks that `PENDING` target unattempted/conflicted without sending a write; a fresh confirmation is required. An `ATTEMPT_STARTED` target stays UNKNOWN until reconciliation.

## 8. RED / GREEN and verification

- RED-001: Missing/ambiguous position identity or unsupported MARGIN size unit yields no mutation. GREEN-001: An eligible derivative action produces the documented normalized request after confirmation.
- RED-002: Cancel, stale token, duplicate confirm, and expired auth produce no new OKX write. GREEN-002: A valid prepared operation is consumed once and reconciled.
- RED-003: Filtered screen plus account-wide close-all still prepares all supported positions; any ineligible target or pre-execution target drift blocks the entire batch, and a partial result cannot be marked complete. GREEN-003: Each confirmed eligible target is attempted once and has a verified individual outcome.
- RED-004: Invalid password/TOTP/replay/origin is rejected without a session. GREEN-004: Valid login yields a short-lived in-memory session and protected API access.

Use fake OKX HTTP transport and a locally launched WSGI test server with temporary test secrets and SQLite storage; no real OKX write in automated tests. Exact Python commands are `python3 -m compileall -q backend` and `python3 -m unittest discover -s backend/tests -v`, with no production environment file or external dependency. Flutter widget tests cover every popup's cancel/confirm, filter independence, disabled states, duplicate taps, and mobile layout. Build `flutter build web --no-pub` after executable changes. Production live-write verification is explicitly deferred until the user provisions the server and Trade key.

## 9. Security, configuration, and rollout

User-owned future server file: `/etc/trading-balance/trade-api.env`, environment assignments for `OKX_API_KEY=<SET_BY_USER>`, `OKX_API_SECRET=<SET_BY_USER>`, `OKX_API_PASSPHRASE=<SET_BY_USER>`, `ADMIN_PASSWORD_HASH=<SET_BY_USER>`, `TOTP_SECRET=<SET_BY_USER>`, `SESSION_SIGNING_KEY=<SET_BY_USER>`, `ALLOWED_WEB_ORIGIN=https://tradingbalancef.vercel.app`, and `OPERATION_DB_PATH=/var/lib/trading-balance/trade-api.sqlite3`. The user creates it outside Git with restrictive permissions. The user passes the public API URL with `--dart-define=TRADE_API_BASE_URL=https://<USER_API_HOST>` when building Flutter. No agent reads or edits protected configuration, and no agent requests secret values. Runtime code may consume those variables as opaque input.

Deployment target: an Ubuntu 24.04 LTS host runs the Python backend in a Docker container. The container image uses a Python runtime and a production WSGI server with one worker; it does not need an Ubuntu base image. The host keeps `/etc/trading-balance/trade-api.env` outside Git and a persistent operation-journal volume, including SQLite journal side files. The API container listens on an internal port exposed only at `127.0.0.1:8000` on the host. A user-owned HTTPS reverse proxy routes `https://<USER_API_HOST>/v1/*` to that loopback port. `ALLOWED_WEB_ORIGIN` is the separate Flutter website origin, `https://tradingbalancef.vercel.app`, not the API host. The user owns the Dockerfile, container run configuration, TLS/reverse-proxy configuration, environment file, and host provisioning; agents supply exact non-secret instructions in the deployment guide but do not create or modify those protected configuration files. Keep secrets out of the image and build arguments.

Rollout: local fake-transport verification -> user provisions an Ubuntu 24.04 LTS host with Docker, HTTPS, and a Trade-enabled OKX key with no Withdraw permission -> user creates the server environment and persistent journal directory -> user builds/runs the container and builds Flutter with the public API URL -> user verifies health, login, backend-owned positions, CORS origin rejection, and persistence of operation/TOTP replay state after a container restart -> user performs one deliberately small first trade and reconciles its result -> enable routine use. Prefer an OKX key restricted to the server's fixed egress IP if available. Rollback: record and reconcile UNKNOWN operation IDs before stopping the API or revoking the key when possible; in a key-compromise emergency revoke first and reconcile manually in OKX. Remove the Flutter API URL/redeploy read-only web. Already placed market orders cannot be rolled back by code deployment.

Completion for this repository delivery requires tests, affected-unit builds, final integration build, guide with exact user-owned setup/verification steps, and an audit of the client/server secret boundary. It does not claim a live production order was executed.

Revision: D-015 fixes the deployment target to Docker on an Ubuntu 24.04 LTS host. The container recipe remains user-owned protected configuration; the plan and guide provide it as copyable non-secret text. The image/package digest pins and HTTPS reverse-proxy path are selected when a real host/domain exists, before production activation.

## 10. Planning workstreams

Material independent workstreams: UI R2 `gpt-6-sol`/`medium` (R2-034-UI), OKX API R3 `gpt-6-sol`/`high` (R3-034-API), security/server R3 `gpt-6-sol`/`high` (R3-034-SEC), and Docker/Ubuntu runtime R2 `gpt-6-sol`/`medium` (R2-034-INFRA). Required 4, actual 4, fan-out PASS. The coordinator adopted UI/API/infrastructure results and the non-protected security conclusions, excluding an ambiguous local-source observation. Cross-layer synthesis and final contract are coordinator-owned.
