# Private position trade API deployment

This guide is for the user-owned production setup. The repository contains the Python WSGI application and offline fake-transport tests; it does not contain production credentials, a Dockerfile, or host/reverse-proxy configuration. Automated tests never contact OKX.

## Runtime contract

The API is `backend.app:application`, uses Python's standard library, and is intended to run behind one production WSGI worker. Its health route returns only `{"status":"ok"}` and does not prove that credentials, OKX access, or the database mount are ready.

| Method and route | Authentication | Purpose |
| --- | --- | --- |
| `GET /v1/health` | None | Static health status |
| `POST /v1/login` | None | Password and TOTP login |
| `POST /v1/logout` | Bearer session | Revoke the current session |
| `GET /v1/positions` | Bearer session | Read positions owned by the backend Trade account |
| `POST /v1/actions/prepare` | Bearer session | Fetch current account state and create an expiring confirmation |
| `POST /v1/actions/execute` | Bearer session | Consume a prepared confirmation once |
| `GET /v1/actions/result/<operation-id>` | Bearer session | Read and reconcile a recorded operation |
| `GET /v1/strategies/settings` | Bearer session | Read the current account's limit-order submission preference |
| `POST /v1/strategies/settings` | Bearer session | Save the current account's limit-order submission preference |
| `GET /v1/strategies/<source-id>/retry-candidates` | Bearer session | Read source-scoped retry eligibility and linked attempts |
| `POST /v1/strategies/<source-id>/retry-preview` | Bearer session | Review an exact selected source-order subset with fresh market inputs |
| `POST /v1/strategies/<source-id>/retry-drafts` | Bearer session | Create or replay one linked retry draft |

Requests and responses use JSON. The body limit is 64 KiB. Browser requests carrying an `Origin` must match `ALLOWED_WEB_ORIGIN` exactly. No `Origin` header is accepted for non-browser clients, but every account or action route still requires a bearer session where listed above. A successful login returns a random bearer token that expires after ten minutes; the API stores only its keyed hash. Keep that token in application memory and discard it on logout or expiry.

### Request shapes

Login:

```json
{"password":"<ADMIN_PASSWORD>","totp":"<6_DIGIT_CODE>"}
```

The response contains `token`, `expiresAt`, and a masked `accountIdentifier`. A TOTP counter can be accepted only once, including across restarts. Five failed login attempts from one source within 15 minutes are rate-limited.

`GET /v1/positions` returns `accountIdentifier` and `positions`. Each position includes its stable `identity`, raw `signedSize`, absolute `size`, `direction`, `marginMode`, `marginCurrency`, `positionCurrency`, available size/debt fields when OKX supplies them, and `eligibleActions`. Unknown or incomplete metadata disables the affected action.

Prepare one position action with one of these bodies:

```json
{"action":"add_margin","targetIdentity":{"instrumentType":"SWAP","instrumentId":"BTC-USDT-SWAP","positionId":"<ID>","positionSide":"net","marginMode":"isolated"},"amount":"5"}
```

```json
{"action":"dca","targetIdentity":{"instrumentType":"SWAP","instrumentId":"BTC-USDT-SWAP","positionId":"<ID>","positionSide":"net","marginMode":"isolated"},"size":"1"}
```

```json
{"action":"partial_close","targetIdentity":{"instrumentType":"SWAP","instrumentId":"BTC-USDT-SWAP","positionId":"<ID>","positionSide":"net","marginMode":"isolated"},"percentage":"50"}
```

```json
{"action":"close_position","targetIdentity":{"instrumentType":"SWAP","instrumentId":"BTC-USDT-SWAP","positionId":"<ID>","positionSide":"net","marginMode":"isolated"}}
```

For `MARGIN`, the identity also includes `marginCurrency`. In this release, MARGIN `dca` and `partial_close` are disabled. Eligible isolated MARGIN positions may use `add_margin` and a 100% `close_position`. For derivatives, `dca.size` is in contracts and `partial_close.percentage` must be greater than zero and less than 100. The server rounds down to the instrument lot size and rejects an amount below its minimum or outside verified available size.

Prepare close-all with:

```json
{"action":"close_all"}
```

Any display filter sent by a caller is ignored. The server prepares the complete supported MARGIN/SWAP/FUTURES account set and refuses the batch if any open supported target is ineligible. A prepare response contains `operationId`, `confirmationToken`, `expiresAt`, and the authoritative `summary.targets` list. Show that summary for confirmation before executing.

Execute exactly once with:

```json
{"operationId":"<OPERATION_ID>","confirmationToken":"<ONE_USE_TOKEN>"}
```

The response reports `SUCCEEDED`, `PARTIAL`, `FAILED`, `UNKNOWN`, or `CONFLICT` with an outcome for each target. Repeating the request returns journaled state without another OKX write. A stale target returns `CONFLICT`. If a network timeout leaves an outcome `UNKNOWN`, use the result route to reconcile it; never prepare a replacement action or blindly repeat the write while that target remains unresolved.

The server checks both top-level and item-level OKX response codes. Market orders are verified through order details and a refreshed position. Full closes are successful only after a fresh position query confirms that the target is gone. Close-all reports each target separately and does not report batch success while any position remains open or unknown.

### Strategy limit-order queue

The strategy settings endpoints use `limitOrderSubmissionMode`, with `sequential` and `batch` as the supported values. The default is `sequential`, and the preference is scoped to the authenticated OKX account. A prepared strategy freezes the selected mode; later preference changes apply only to strategies prepared afterward. Existing prepared records without a saved mode retain the legacy `batch` path.

In sequential mode, `POST /v1/strategies/<id>/execute-apply` consumes the confirmation and durably queues the reviewed orders. The API response reports `submissionMode`, `queueStatus`, `queueProgress`, and `applyOutcome: "queued"`; the separate strategy worker performs the exchange writes. The worker sends the frozen limit-order payloads in reviewed order, spaces placements by at least 250 ms, and makes no more than 20 placement attempts per worker pass. A queue stops at its 120-second deadline or on a rejected, malformed, or ambiguous write result. It records each write marker and ACK before advancing the cursor. After a restart, it revalidates the account, mode, preview hash, and deadline before continuing an accepted prefix. An ambiguous write remains unknown and is never resent; the untouched tail stays unsent.

With `batch`, the API keeps the existing batch submission path. Both modes use the same reservation and order-reconciliation records in the SQLite database.

### Selective strategy order resubmission

Retry candidates are available only for an attempted strategy owned by the authenticated account. The candidate response includes every source order with a fixed prior outcome, an `eligible` flag, and a bounded reason. Only a definitely `not_submitted` order or an order rejected with a validated numeric OKX error code can be selected. Accepted, canceled-after-acceptance, unknown, malformed, or in-flight rows remain excluded. Current position mode, zero positions, no pending orders, no other instrument reservation, and sufficient available USDT are required.

Send the returned `sourceRevision` and one through ten eligible `sourceClientOrderIds` to `retry-preview`. The server preserves each selected order's side, role, limit price, contract count, leverage, and optional level ID. It recalculates costs, cumulative entry and liquidation estimates, and current tier checks without reallocating quantity. The response contains a review `previewHash`; a changed fee, tier, contract rule, account mode, or source selection requires a fresh review. Quote time and price are checked for freshness on each review and preflight.

Create the child with the same ordered selection and revision, the preview hash, and a random `retryRequestId` containing 16–64 letters, digits, underscores, or hyphens. Repeating an identical request ID and payload returns the existing child without creating another draft or confirmation token. Reusing that ID with a different selection or review is rejected. The child has fresh client order IDs and a public `resubmission` history link to its direct source. The prepare acknowledgement returns the child ID, exact frozen child orders, current submission mode, and the public source strategy ID and ordered source client order IDs. Prepare it normally to freeze the current account submission preference, then confirm once through the existing batch or sequential path.

An unclaimed, never-sent retry draft can be deleted to release its selected rows. Once its token is claimed, the source selection is permanently consumed and both the child and its source history are protected, including when leverage fails before any order placement. A rejected retry child can be selected as a new direct source; the original ancestor does not become available again. Source, selection, retry-request, preview, position, pending-order, balance, and reservation blockers return safe errors; the server never retries an uncertain order automatically.

### Strategy submission diagnostics

The API and strategy worker emit best-effort, bounded JSON lines to their container stderr. Read the recent logs with:

```sh
sudo docker logs --since 10m trading-balance-trade-api
sudo docker logs --since 10m trading-balance-strategy-worker
```

Each event uses fixed stage, outcome, endpoint, and reason labels. `strategy_ref` (`s_…`) and `order_ref` (`o_…`) are separate SHA-256 references; match the same reference across the API and worker logs. Events never include request bodies, credentials, account identifiers, raw exchange IDs, prices, sizes, or exception text. `top_code` and `item_code` appear only when they pass numeric validation.

For a sequential queue, `enqueue_result` with `persisted: true` means the API durably queued the frozen strategy. Worker `worker_startup`, `heartbeat`, `selection`, and `preflight` events show whether a worker pass is running, whether due strategies match its current account, and where selection stopped. For example, no `worker_startup` or heartbeat in the selected log window means those logs contain no evidence of a worker pass; it does not establish why. A `selection` event with `outcome: "no_due"`, `eligible_count: 4`, and `matching_eligible_count: 0` means four due rows were visible, but none matched this worker's active account. The counts are bounded diagnostics and may be absent if the read-only count query fails.

`write_attempt` follows a committed write marker. `ack_observed` records the exchange response separately from the following `commit`: only `commit` with `persisted: true` confirms the outcome was stored. If an ACK is observed with `persisted: false`, followed by a commit with `persisted: false` and `reason: "fence_or_cas_loss"`, the ACK was not durably applied to strategy state. Preserve the unresolved in-flight marker and do not resend; this refusal does not prove that a later conservative stop has already been persisted. A later worker pass that acquires the lease will inspect the durable marker and apply interrupted-attempt recovery; until that recovery event appears, its persistence is unconfirmed. Batch logs use the same distinction and include a bounded `batch_summary`.

Fictional references below are illustrative. If an enqueue has no `worker_startup` or heartbeat in the selected time window, there is no worker-pass evidence in that window. A no-due event can still show that due rows belong to another account. An incomplete ACK remains unknown until reconciled:

```jsonl
{"event":"enqueue_result","component":"api","stage":"enqueue","outcome":"queued","persisted":true,"strategy_ref":"s_0123456789abcdef","submission_mode":"sequential"}
{"event":"worker_startup","component":"worker","stage":"startup","outcome":"success"}
{"event":"selection","component":"worker","stage":"selection","outcome":"no_due","reason":"no_due","eligible_count":4,"matching_eligible_count":0,"selected_count":0,"pass_count":1}
{"event":"ack_observed","component":"worker","stage":"order","outcome":"unknown","reason":"ack_unknown","ack_shape":"missing_order_id","persisted":false,"order_ref":"o_fedcba9876543210"}
{"event":"commit","component":"worker","stage":"commit","outcome":"refused","reason":"fence_or_cas_loss","persisted":false,"order_ref":"o_fedcba9876543210"}
```

An incomplete ACK such as `missing_order_id` is evidence that the response did not meet the expected shape, not evidence that the exchange did or did not place the order. Reconcile an unknown result before any new submission. The sink is local and nonblocking. A full queue, a stalled stderr reader, or a sink error can drop diagnostic events, so missing log lines do not prove that no exchange write occurred. Logs provide evidence for investigation; they do not establish that an order filled, identify a production root cause, or prove that a production failure was resolved.

## User-owned credentials

On a trusted local machine, run the helper from the repository root:

```sh
python3 -m backend.credential_helper
```

It prompts for the admin password without echoing it, requires at least 16 characters, and prints an encoded scrypt hash, a new TOTP seed, and a random 32-byte session signing key. Save those values securely. Tests use fixed disposable credentials and never invoke the helper.

On the Ubuntu host, create `/etc/trading-balance/trade-api.env` outside the repository, owned by root and readable only by root. Use literal Docker `KEY=VALUE` entries; do not source the file in a shell and do not commit it:

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

Use a Trade-enabled OKX API key with **no Withdraw permission**. Restrict it to the server's stable egress IP when available. Never put credentials in a Dockerfile, image layer, build argument, Flutter bundle, log, or API response.

## Ubuntu 24.04 LTS container

Install and maintain Docker on the Ubuntu 24.04 LTS host using the host owner's approved process. Create the persistent SQLite directory and allow container UID 10001 to write it, including SQLite journal side files:

For a first deployment, create the API env file and persistent directory below, then create the user-owned Dockerfile, build and start the API container. After the API is running, create the worker env file and start the worker using the instructions in the strategy worker section.

```sh
sudo install -d -o root -g root -m 0700 /etc/trading-balance
sudo install -d -o 10001 -g 10001 -m 0750 /var/lib/trading-balance
sudo install -o root -g root -m 0600 /dev/null /etc/trading-balance/trade-api.env
sudoedit /etc/trading-balance/trade-api.env
```

The user creates `backend/Dockerfile` from this baseline. This is user-owned protected configuration; agents do not create or edit it:

```dockerfile
FROM python:3.12-slim
WORKDIR /app
RUN python -m pip install --no-cache-dir gunicorn
COPY backend /app/backend
USER 10001:10001
CMD ["gunicorn", "--workers", "1", "--bind", "0.0.0.0:8000", "backend.app:application"]
```

Build from the repository root:

```sh
sudo docker build -f backend/Dockerfile -t trading-balance-trade-api .
```

Run the API with one WSGI worker, a read-only application filesystem, a writable temporary directory, dropped capabilities, and the persistent operation journal:

```sh
sudo docker run -d --name trading-balance-trade-api --restart unless-stopped \
  --read-only --tmpfs /tmp:rw,noexec,nosuid,size=64m \
  --cap-drop=ALL --security-opt=no-new-privileges --pids-limit=128 \
  --user 10001:10001 --env-file /etc/trading-balance/trade-api.env \
  --mount type=bind,source=/var/lib/trading-balance,target=/var/lib/trading-balance \
  -p 127.0.0.1:8000:8000 trading-balance-trade-api
```

### Rebuild and recreate after an application change

For deployments without the strategy worker, run these API-only commands from the repository root. Rebuilding the image does not update a running container; stop and remove the existing container, then create it again from the rebuilt image. The bind-mounted operation journal remains in `/var/lib/trading-balance` across container replacement.

```sh
sudo docker build -f backend/Dockerfile -t trading-balance-trade-api .
sudo docker stop trading-balance-trade-api
sudo docker rm trading-balance-trade-api
sudo docker run -d --name trading-balance-trade-api --restart unless-stopped \
  --read-only --tmpfs /tmp:rw,noexec,nosuid,size=64m \
  --cap-drop=ALL --security-opt=no-new-privileges --pids-limit=128 \
  --user 10001:10001 --env-file /etc/trading-balance/trade-api.env \
  --mount type=bind,source=/var/lib/trading-balance,target=/var/lib/trading-balance \
  -p 127.0.0.1:8000:8000 trading-balance-trade-api
```

To restart the existing API container without rebuilding or replacing it, run:

```sh
sudo docker restart trading-balance-trade-api
```

### Strategy order-monitor worker

The strategy worker runs as a separate container from the same API image. It submits durable sequential limit-order queues and monitors submitted orders through OKX order details and positions. Store its env file under the root-owned `/etc/trading-balance` directory because the `/home/deploy/trading_balance_f` parent is writable and causes `sudoedit` to reject that path. Use the same OKX account and session signing key as the API, and set `OPERATION_DB_PATH` to the API's absolute container path for the SQLite database on its persistent mount:

```sh
if ! sudo test -e /etc/trading-balance/trade-api-worker.env && ! sudo test -L /etc/trading-balance/trade-api-worker.env; then
  sudo install -o root -g root -m 0600 /dev/null /etc/trading-balance/trade-api-worker.env
fi
sudoedit /etc/trading-balance/trade-api-worker.env
```

For a release containing sequential queues, stop both the old API and worker, then back up the application SQLite database using the normal operator procedure. Install the same new image for the API and worker, start both services with the persistent database mounted, and verify both containers are running before releasing a compatible frontend that exposes the preference. The API and worker must share the same SQLite file so the lease fence, queue cursor, ACKs, and reservation state remain coordinated.

For rollback, first roll back the frontend, then stop both the API and worker while preserving the SQLite database and all queue markers. After sequential queues have finished or stopped and ambiguous placements are resolved, prefer `batch` for new preparations. Do not erase markers or start older binaries while any sequential queue is `APPLYING` or has an unresolved placement. Let the matching API and worker reconcile those rows, or leave both services stopped and preserve the database for review. Once queue state is resolved, roll the API and worker back together to the same prior image. The additive database migration is retained across an application rollback.

Add these five entries, replacing each placeholder privately on the host:

```dotenv
OKX_API_KEY=<SET_BY_USER_SAME_AS_API>
OKX_API_SECRET=<SET_BY_USER_SAME_AS_API>
OKX_API_PASSPHRASE=<SET_BY_USER_SAME_AS_API>
SESSION_SIGNING_KEY=<SET_BY_USER_SAME_AS_API>
OPERATION_DB_PATH=<SET_BY_USER_SAME_ABSOLUTE_CONTAINER_PATH_AS_API>
```

After the updated API container is running, start the worker from the Docker host. It uses the rebuilt API image, shares the API container's persistent volumes, runs as UID 10001 with a read-only filesystem and the same container hardening, and publishes no port:

```sh
sudo docker run --detach --name trading-balance-strategy-worker --restart unless-stopped \
  --read-only --tmpfs /tmp:rw,noexec,nosuid,size=64m \
  --cap-drop=ALL --security-opt=no-new-privileges --pids-limit=128 \
  --user 10001:10001 --env-file /etc/trading-balance/trade-api-worker.env \
  --volumes-from trading-balance-trade-api --entrypoint python3 \
  trading-balance-trade-api -m backend.strategy_worker
```

To restart the worker without changing its image, run:

```sh
sudo docker restart trading-balance-strategy-worker
```

To replace the API and worker images together, run this sequence from the repository root. It conditionally removes an existing worker, rebuilds the image, then recreates the API before the worker so the worker shares the API container's volumes:

```sh
sudo docker build -f backend/Dockerfile -t trading-balance-trade-api .
if sudo docker inspect trading-balance-strategy-worker >/dev/null 2>&1; then
  sudo docker stop trading-balance-strategy-worker
  sudo docker rm trading-balance-strategy-worker
fi
sudo docker stop trading-balance-trade-api
sudo docker rm trading-balance-trade-api
sudo docker run -d --name trading-balance-trade-api --restart unless-stopped \
  --read-only --tmpfs /tmp:rw,noexec,nosuid,size=64m \
  --cap-drop=ALL --security-opt=no-new-privileges --pids-limit=128 \
  --user 10001:10001 --env-file /etc/trading-balance/trade-api.env \
  --mount type=bind,source=/var/lib/trading-balance,target=/var/lib/trading-balance \
  -p 127.0.0.1:8000:8000 trading-balance-trade-api
sudo docker run --detach --name trading-balance-strategy-worker --restart unless-stopped \
  --read-only --tmpfs /tmp:rw,noexec,nosuid,size=64m \
  --cap-drop=ALL --security-opt=no-new-privileges --pids-limit=128 \
  --user 10001:10001 --env-file /etc/trading-balance/trade-api-worker.env \
  --volumes-from trading-balance-trade-api --entrypoint python3 \
  trading-balance-trade-api -m backend.strategy_worker
```

Check that Docker reports both containers running with these read-only commands:

```sh
sudo docker inspect --format '{{.State.Running}}' trading-balance-trade-api
sudo docker inspect --format '{{.State.Running}}' trading-balance-strategy-worker
```

After 5–10 seconds, open an applied, noncompleted strategy with outstanding submitted orders in the UI and confirm its order status and last successful scan freshness update, since draft or completed strategies receive no new worker scans. Container status and `/v1/health` only show process/API health; they do not prove that the worker synchronized with OKX.

Check container status and its published loopback port with this read-only command:

```sh
sudo docker ps --filter name=trading-balance-trade-api --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
```

Keep one WSGI worker until journal and write-lock behavior has been independently proven safe across workers. The container listens inside on port 8000; Docker publishes it only on host loopback. Configure the user's HTTPS reverse proxy to route `https://<USER_API_HOST>/v1/*` to `http://127.0.0.1:8000/v1/*`, preserve the browser `Origin` header, overwrite `X-Forwarded-For` with the connecting client address, and expose no plaintext public port. The API trusts that header only on loopback requests, so the proxy must not append a client-supplied value. The Flutter web origin remains `https://tradingbalancef.vercel.app`; the API host is a separate origin.

The public production API base URL is `https://api.tradingbalancef.com`. Build the release web client with it:

```sh
flutter build web --no-pub --release --dart-define=TRADE_API_BASE_URL=https://api.tradingbalancef.com
```

This URL is public. It is not a credential.

## Startup, persistence, and first-use checks

1. Check `GET https://<USER_API_HOST>/v1/health` returns `{"status":"ok"}`. This confirms only the static health route.
2. Send a browser-style request with `Origin: https://tradingbalancef.vercel.app`; it should receive the matching `Access-Control-Allow-Origin`. Repeat with a different origin; the API should return `403` and no allow-origin header.
3. Log in with the generated password and current authenticator code. Confirm that the response contains only a masked account identifier, then call `GET /v1/positions` and confirm that the positions belong to the Trade-key account.
4. Prepare an eligible action but do not execute it. Record its operation ID, restart the container with `sudo docker restart trading-balance-trade-api`, then retrieve `GET /v1/actions/result/<operation-id>` using the same session if still valid. The prepared journal entry should remain available on the mounted database.
5. Within the same 30-second TOTP window, retry login with the same code after the restart. It must be rejected as a replay. Wait for the next authenticator code before logging in again.
6. Before any trade, verify the API host, account identifier, product, position side, margin mode, amount/size unit, and target list. For a first live action, choose the smallest eligible amount supported by the instrument, prepare it, review the exact server-returned summary, and explicitly confirm once. Check the returned result and refreshed positions in OKX before regular use. Do not use close-all as the first live verification.

The automated suite uses only fake responses; these production checks and any real first trade are user-owned actions. No production OKX request is part of local verification.

## Rollback

If behavior is uncertain, first record and reconcile every `UNKNOWN` operation ID where possible. Stop the container and remove the public Flutter API URL to return the web app to read-only mode. Revoke the Trade key immediately if compromise is suspected; otherwise reconcile outstanding operations before revocation when safe. Already placed market orders require normal exchange-side management and cannot be undone by deploying older code.

Before production activation, the host owner must select and review image/package digest pins and the HTTPS reverse-proxy configuration for the actual host and domain.
