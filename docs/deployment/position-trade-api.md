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

The strategy worker runs as a separate container from the same API image. It only reads OKX order details and positions; order placement remains in the API. Store its env file under the root-owned `/etc/trading-balance` directory because the `/home/deploy/trading_balance_f` parent is writable and causes `sudoedit` to reject that path. Use the same OKX account and session signing key as the API, and set `OPERATION_DB_PATH` to the API's absolute container path for the SQLite database on its persistent mount:

```sh
if ! sudo test -e /etc/trading-balance/trade-api-worker.env && ! sudo test -L /etc/trading-balance/trade-api-worker.env; then
  sudo install -o root -g root -m 0600 /dev/null /etc/trading-balance/trade-api-worker.env
fi
sudoedit /etc/trading-balance/trade-api-worker.env
```

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

Build the web client with the public API base URL:

```sh
flutter build web --no-pub --dart-define=TRADE_API_BASE_URL=https://<USER_API_HOST>
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
