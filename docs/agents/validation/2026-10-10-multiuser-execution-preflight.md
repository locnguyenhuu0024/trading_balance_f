# Multi-user execution preflight — 2026-10-10

Verdict: BLOCKED_ENVIRONMENT (T110 Definition of Ready)
Plan revision: 1, execution authorized by the user on 2026-10-10.

## Observed evidence

- `command -v python3.12`: `/opt/homebrew/bin/python3.12`.
- `python3.12 -c 'import importlib.util, sys; print("Python", sys.version.split()[0]); print({name: importlib.util.find_spec(name) is not None for name in ("psycopg", "cryptography")})'`: Python 3.12.13; both modules absent; exit 0.
- `command -v psql` / `command -v postgres`: no executable on PATH. This does not prove a remote/test DB is unavailable.
- Dedicated test DB and vault readiness: UNCONFIRMED. No protected file or environment value inspected.
- Initial Git status: pre-existing modification only in `docs/agents/telemetry/events/2026-10-06.jsonl`; preserved.
- Executor dispatch, RED/GREEN, tests/build, independent implementation audit: NOT_RUN. No product implementation occurred.

## Operator-owned setup

The T110 STOP-for-missing-setup contract prevents dispatch. Spec section 12 assigns installation/configuration to the operator. These actions are required before runtime verification; implementation authorization is already recorded.

1. Proposed new `backend/requirements-multiuser.txt`, top-level dependency pins: `psycopg[binary]==3.3.6` and `cryptography==50.0.2`. Both releases declare Python 3.12 support. Official sources: [psycopg](https://pypi.org/project/psycopg/3.3.6/), [psycopg-binary](https://pypi.org/project/psycopg-binary/3.3.6/), [cryptography](https://pypi.org/project/cryptography/50.0.2/). These are a direct dependency pin proposal; transitive/hash locking and installed compatibility have not been verified. Operator pins/installs into the backend Python 3.12 runtime, then verifies imports/version and AESGCM/psycopg availability. No agent creates or modifies this manifest.
2. Proposed new `backend/.env.multiuser.test`, key `MULTIUSER_TEST_DATABASE_URL=<SET_BY_USER_ISOLATED_TEST_DB>`; use a dedicated PostgreSQL DB with no production data. Operator may inject the equivalent process variable. Loader does not exist yet; merely creating a file is not evidence that it is loaded. Only this explicit test input authorizes test schema reset. Validate isolated connection/readiness without printing DSN; run the focused PostgreSQL race tests once implemented.
3. Proposed new `backend/.env.multiuser`, one key per line: `MULTIUSER_DATABASE_URL=<SET_BY_USER>`, `CREDENTIAL_VAULT_KEY=<SET_BY_USER_32_BYTE_BASE64>`, `CREDENTIAL_VAULT_KEY_ID=v1`, `REMOTE_IDENTITY_KEY=<SET_BY_USER_32_BYTE_BASE64>`, `SESSION_SIGNING_KEY=<SET_BY_USER>`, `MULTIUSER_ENABLED=false`, `MULTIUSER_TRADE_ENABLED=false`. Equivalent operator-injected process inputs are permitted. Keep key material distinct, outside DB backups; no production activation. Validate vault round-trip/tamper fixtures and DB readiness through the implemented tests, then restart only the isolated runtime as needed.

Confirm the Python/runtime path and test DB/vault readiness using non-sensitive facts only. Never send secret values or complete configuration files. An alternative installed runtime can satisfy the preflight without modifying the current runtime. Subsequent task gates remain unchanged; T111–T116 cannot start before their predecessors PASS.
