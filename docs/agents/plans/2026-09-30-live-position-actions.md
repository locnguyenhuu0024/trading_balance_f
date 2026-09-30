# Implementation Plan: Live OKX position actions

Status: APPROVED_FOR_IMPLEMENTATION
Date: 2026-09-30
Tier: L
Specification: `docs/agents/specs/2026-09-30-position-actions-design.md`
Decision Ledger: `docs/agents/decisions/2026-09-30-position-actions-live-decisions.md`

## 1. Objective and preconditions

Implement REQ-001..010 / AC-001..010 as code and deployment guidance, without executing production trades. T33 default-ALL work is an existing uncommitted change and must be preserved. The user will later supply a private HTTPS server, Trade-enabled OKX credentials, and the public backend URL; none exists now. The current read-only OKX key must not be given Trade permission in the Flutter client.

## 2. Repository impact and protected boundaries

| Area | Planned files | Change |
|---|---|---|
| Python backend | `backend/*.py`, `backend/tests/*.py` | New standard-library WSGI API, authentication, OKX adapter, operation journal, local fake-transport tests, user-run credential-generation helper. |
| Flutter client | `lib/features/orders/data/okx_position_model.dart`, its generated companions, `lib/features/orders/presentation/orders_screen.dart`, new client/controller/widgets under `lib/features/orders/`, focused `test/features/orders/` | Complete identity, server interaction, action input/confirmation/results, responsive layout. |
| Deployment guide | `docs/deployment/position-trade-api.md` | Exact user-owned setup, secret placeholders, startup, rollback, and production verification sequence. |

No agent may read or write a dependency manifest, `.env`, Dockerfile/Compose file, build/deploy config, existing credential store, or other protected configuration/environment file. The backend uses Python standard-library application dependencies only; the user-owned Docker image adds a production WSGI server. The future Ubuntu 24.04 LTS host supplies Docker and a TLS reverse proxy. No new package manifest is planned. An ambiguous source file whose primary purpose may be configuration is excluded from inspection.

## 3. External configuration and environment actions

The user creates `/etc/trading-balance/trade-api.env` on the future server, outside Git, with literal Docker `KEY=VALUE` entries (no shell interpolation or sourcing), root ownership, and restrictive permissions. Required keys and exact non-secret structure:

```text
OKX_API_KEY=<SET_BY_USER>
OKX_API_SECRET=<SET_BY_USER>
OKX_API_PASSPHRASE=<SET_BY_USER>
ADMIN_PASSWORD_HASH=<SET_BY_USER>
TOTP_SECRET=<SET_BY_USER>
SESSION_SIGNING_KEY=<SET_BY_USER>
ALLOWED_WEB_ORIGIN=https://tradingbalancef.vercel.app
OPERATION_DB_PATH=/var/lib/trading-balance/trade-api.sqlite3
```

The user-owned `backend/Dockerfile` (new protected build file, created by the user only) is placed at the repository's `backend/` root. T34's guide must present this non-secret baseline recipe, adjusted only if implementation proves a concrete runtime incompatibility and the plan is revalidated:

```dockerfile
FROM python:3.12-slim
WORKDIR /app
RUN python -m pip install --no-cache-dir gunicorn
COPY backend /app/backend
USER 10001:10001
CMD ["gunicorn", "--workers", "1", "--bind", "0.0.0.0:8000", "backend.app:application"]
```

The host owner builds from repository root with `docker build -f backend/Dockerfile -t trading-balance-trade-api .`, creates `/var/lib/trading-balance` and makes it writable by container UID 10001, including SQLite side files, then applies this exact baseline container run command from the guide:

```sh
docker run -d --name trading-balance-trade-api --restart unless-stopped \
  --read-only --tmpfs /tmp:rw,noexec,nosuid,size=64m \
  --cap-drop=ALL --security-opt=no-new-privileges --pids-limit=128 \
  --user 10001:10001 --env-file /etc/trading-balance/trade-api.env \
  --mount type=bind,source=/var/lib/trading-balance,target=/var/lib/trading-balance \
  -p 127.0.0.1:8000:8000 trading-balance-trade-api
```

The user-owned HTTPS reverse proxy routes `https://<USER_API_HOST>/v1/*` to `127.0.0.1:8000`; `ALLOWED_WEB_ORIGIN` is the distinct Flutter site origin, `https://tradingbalancef.vercel.app`. The backend exposes `GET /v1/health` with no account/secret data for startup checks. The guide must verify the mounted journal and TOTP replay state survive `docker restart`, that the allowed web origin passes CORS and a different origin fails, and that an unknown operation can be retrieved after restart. Exact reverse-proxy file path/domain and image/package digest pins are deployment-time user choices because no server exists yet; the baseline recipe must be pinned and reviewed before production activation. They do not enter executable repository code or local verification.

The user supplies a Trade-enabled production OKX key without Withdraw permission; preferably restrict it to the server's stable egress IP. On the Ubuntu 24.04 LTS host, the user creates the persistent operation database directory and applies the deployment guide's Dockerfile at `backend/Dockerfile` and container run command. That Dockerfile is a protected user-owned file: T34 writes the exact non-secret recipe into the guide, but no agent creates or edits the Dockerfile itself. The container uses a Python runtime with a production WSGI server, one worker, a read-only application filesystem where feasible, a persistent journal mount, no secrets baked into the image, and loopback-only port exposure to a user-owned HTTPS reverse proxy. The build command for the web app receives `--dart-define=TRADE_API_BASE_URL=https://<USER_API_HOST>`; this URL is public, not secret. No secret value is sent to the agent. These actions block live production verification but do not block code and fake-transport tests.

## 4. Planning workstream coverage

| Workstream | Material | Independent | Requested route | Logical run | Adoption |
|---|---|---|---|---|---|
| Frontend/UI | YES | YES | R2 `gpt-6-sol` / `medium` | R2-034-UI | COMPLETE / USED |
| OKX API/trade | YES | YES | R3 `gpt-6-sol` / `high` | R3-034-API | COMPLETE / USED |
| Client/server security | YES | YES | R3 `gpt-6-sol` / `high` | R3-034-SEC | COMPLETE / PARTIAL |
| Docker/Ubuntu runtime | YES | YES | R2 `gpt-6-sol` / `medium` | R2-034-INFRA | COMPLETE / USED |

Fan-out Required: YES. Required Reasoning Agents: 4. Actual Reasoning Agents: 4. Fan-out Compliance: PASS. Skip Reason: N/A. Coordinator reconciliation: the server owns all Trade signing and action validation; Flutter only displays prepared operations and sends a one-use confirmation token. The Docker container keeps SQLite on a host mount and binds only to loopback behind HTTPS; the web and API origins are distinct. A security-agent observation about ambiguous local source was excluded from canonical evidence. Independent R3 specification and R2 infrastructure critiques were collected and their fail-closed findings incorporated.

## 5. Dependency graph and steps

```text
P01 / T34 (backend contract, fake transport, guide)
       -> P02 / T35 (Flutter client, models, controls)
       -> P03 (integration/security audit and final build)
```

### P01 — Private Python trade API

Implement a Python standard-library WSGI application under `backend/`, exporting `backend.app:application`. Keep it dependency-free so it can be syntax-compiled and locally tested without protected dependency files or external package installation. The user-owned Docker deployment on Ubuntu 24.04 LTS supplies a production WSGI server; do not add Docker or dependency configuration to the executor write surface. Define the stable JSON contract: `GET /v1/health` (static status only), `POST /v1/login`, `POST /v1/logout`, `GET /v1/positions`, `POST /v1/actions/prepare`, `POST /v1/actions/execute`, and `GET /v1/actions/result/<operation-id>`. Login follows the specification's scrypt/TOTP rules with durable replay prevention; issue a 10-minute random bearer token, store only its hash, and enforce exact configured Origin on browser requests. Return a safe user-facing session expiry and masked account identifier. Cap body size and rate-limit login/action calls. Never return secrets or raw OKX authentication material.

Prepare fetches fresh OKX positions and instrument metadata, determines eligibility using the specification's product/action matrix and exact Decimal-normalized amount/size, and persists an expiring operation record. Close-all prepare ignores the UI filter and gathers the complete MARGIN/SWAP/FUTURES target list; any ineligible supported position blocks the whole batch. Execute consumes the token once under a database transaction, rechecks the complete target set before the first close-all write, and persists `ATTEMPT_STARTED` before each per-target network call. A repeated execute returns stored status without another write. Support `margin-balance type=add`, market `trade/order`, and `trade/close-position autoCxl=true` according to the official contracts. For full close, verify the target closed; for placed orders, check top-level/item-level codes, query order details, and refresh the position. Unknown/timeouts remain UNKNOWN pending reconciliation through the status endpoint; do not resend blindly, including after process restart. Close-all records individual outcomes and never collapses partial success into full success. Use one worker per deployment until journal/locking semantics are independently proven across workers.

RED: invalid login/TOTP replay, missing session, stale position, duplicate execute, unsupported MARGIN size, and partial close-all failure cause zero extra write attempts and honest status. GREEN: a valid prepared eligible action makes exactly one correct fake OKX request and reconciles the expected result. Tests use a fake HTTP transport, test secrets, temporary SQLite database, and `unittest`; they never call OKX live. Buildability command: `python3 -m compileall -q backend` after final backend edit; behavior command: `python3 -m unittest discover -s backend/tests -v`. Stop if the stdlib server cannot meet the authentication/idempotency contract without a new protected dependency/configuration requirement; return for coordinator replanning.

Validation update VAL-001..003 for P01: interpret MARGIN long/short only from verified `posCcy` versus instrument base/quote currency; never infer MARGIN direction from signed `pos` or a missing `posCcy`. Keep MARGIN DCA/partial close disabled in this release because exact trade capacity and currency-consistent debt checks remain unproven. Retain isolated MARGIN add-margin and full close when identity and mode are complete. For any future MARGIN order, `ccy` must be the confirmed margin currency. On result lookup after a process restart, an `IN_PROGRESS` operation's `PENDING` targets are known unattempted and become conflicted without a network write; `ATTEMPT_STARTED` targets remain UNKNOWN. Add realistic positive-`pos` MARGIN short, missing `posCcy`, and interrupted `IN_PROGRESS`/`PENDING` restart tests. The local host requires `python3.12` for behavior tests because its `python3` is Python 3.9 without `hashlib.scrypt`; the exact whole-backend compile command remains the T34 build gate after protected-path cleanup.

### P02 — Flutter action interface and API client

Extend the position model with stable identity, product type, signed size, margin and position currency as needed. Regenerate only the model's application-code companions with the repository-native generator, without editing package/build configuration. Add an authenticated backend client using the public `TRADE_API_BASE_URL` compile-time value. Keep the bearer token in memory; do not persist it in browser storage. Once logged in, obtain actionable cards from the backend account's positions endpoint and show its masked account identifier; cards from the read-only client alone never gain enabled Trade actions. Build per-card actions and a separate page-level close-all action. Inputs lead to server prepare and then a mandatory confirmation popup rendering the server-returned target/amount/list. Cancel/dismiss sends no execute request; duplicate taps cannot resend. Show disabled eligibility reasons, stale conflicts, unknown/partial results, and a read-only setup state when no backend URL exists. Coordinate auto-refresh with pending dialogs/results; update affected card-layout tests.

RED: cancel and unsupported identity emit no execute, selected full close targets only its card, close-all ignores filter, and double tap does not duplicate. GREEN: each eligible prepared action presents the exact summary and executes once only after explicit confirmation, then refreshes visible positions. V1 focused widget/unit tests, V2 affected orders test group; V3 only if shared provider/navigation regressions appear. Buildability command: `flutter build web --no-pub` after final Flutter executable change. Stop if backend contract differs from the approved interface or generated code cannot be updated without protected configuration writes.

### P03 — Final audit

Independently inspect changed non-protected paths and run focused backend/client tests, `git diff --check`, and the final `flutter build web --no-pub` after all executable changes. Audit the client/server secret boundary and one-use operation journal with a read-only security reviewer. Do not perform a production OKX write. Report live verification as pending user setup, with the exact guide path and no claim that production trading was exercised.

P03 audit remediation: reject non-HTTPS client URLs before authentication traffic; bind every prepared operation and reconciliation snapshot to the full server-side OKX account UID through a keyed fingerprint; capture a tapped card's identity before awaiting input; retain UNKNOWN/PARTIAL operation IDs in the authenticated UI with a later status lookup; and reconcile close-all aggregate UNKNOWN rows after a transient final-account-query failure. Add focused regressions for each before final V2 suites and builds. These fixes preserve the approved backend-owned trade architecture and do not require a new protected configuration file.

## 6. Verification, risks, and rollback

Formal order per task: RED first, then GREEN after implementation stabilizes. T34 ceiling V2 backend test suite; T35 ceiling V2 affected orders tests, with V3 escalation on an observed shared regression. Final integration includes both units and the mandatory web build; no full Flutter suite without a concrete broad-risk finding. Backend tests must use fake OKX responses covering top-level success with per-item failure, stale position, signed net side, rounding/minimum, MARGIN disabled cases, 401/429, timeout, and partial close-all. Flutter tests cover all confirmation popups, cancel/no-call, filter-independent close-all, in-memory session expiry, and mobile overflow.

Risks: irreversible market orders; stale target; wrong MARGIN unit; duplicated call after timeout; partial close-all; Trade-key exposure; missing server; lost SQLite journal after container replacement. Mitigations: server prepare/execute, Decimal and instrument metadata, explicit mode eligibility, operation journal and reconciliation, per-target outcomes, server-only Trade key, persistent host mount, and read-only fallback. Rollback first records/reconciles UNKNOWN operation IDs when feasible, then disables the backend URL/stops the container/revokes the server Trade key. In a key-compromise emergency revoke first and reconcile manually in OKX. Already executed trades require normal exchange-side management.

## 7. Tasks and buildability

| Task | Steps | Depends on | Route | Allowed write surface | Buildability |
|---|---|---|---|---|---|
| T34 | P01 | none | E2 `gpt-6-luna` / `max` | `backend/*.py`, `backend/tests/*.py`, `docs/deployment/position-trade-api.md` (Dockerfile recipe in guide only) | Python compileall and backend tests |
| T35 | P02 | T34 PASS | E1 `gpt-6-luna` / `xhigh` | specific orders source/generated files and `test/features/orders/` | Flutter web build and focused tests |

Handoff review: backend auth/OKX/journal are compile- and behavior-coupled and stay in one auditable task. Flutter consumes the stable P01 API and is a separate auditable task. The guide ships with backend because its environment and operation contract are inseparable from server implementation. No concurrent writer wave: T35 depends on T34's completed API contract. Coordinator owns tasks, telemetry, and audit. All child dispatches must bind role, model, and effort explicitly; no parent route inheritance.

## 8. Completion gate

- [x] Material planning workstreams dispatched and reconciled.
- [x] Independent spec critique reconciled.
- [x] Plan and T34/T35 presented, then explicitly approved by the user.
- [x] T34 and T35 each pass RED/GREEN and their affected-unit build gate.
- [x] Final repository web build and security/integration audit pass; the final T35 post-fix source audit was coordinator-owned after a redundant child audit hit a runtime usage limit.
- [x] User-owned configuration actions are documented; no protected file content was read, and the only protected-file changes were deletion of the two exact paths explicitly authorized by the user.
- [x] Live production verification is explicitly pending until the user supplies a server and Trade key.
