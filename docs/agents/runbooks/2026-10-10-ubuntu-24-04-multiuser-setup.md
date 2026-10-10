# Ubuntu 24.04 — Multi-user backend setup and T110 verification

Scope: operator-run installation and isolated T110 verification. No production migration, deployment, exchange credentials or trade activation. Run only on the Ubuntu VPS, in a checkout containing the implemented changes. Current Mac implementation does not install packages or access the VPS. Replace `<VPS_PROJECT_DIRECTORY>` with the existing VPS checkout path; do not copy the Mac absolute path.

## 1. System dependencies

```bash
sudo apt update
sudo apt install -y python3.12 python3.12-venv postgresql postgresql-client
sudo systemctl start postgresql
```

Sources: [Ubuntu PostgreSQL installation](https://documentation.ubuntu.com/server/how-to/databases/install-postgresql/), [Ubuntu 24.04 Python venv package](https://packages.ubuntu.com/noble/python3.12-venv). This uses Ubuntu packages rather than adding a third-party repository. Do not upgrade the OS or edit existing database/server configuration to perform this task.

## 2. Separate Python environment

```bash
cd '<VPS_PROJECT_DIRECTORY>'
python3.12 -m venv backend/.venv-multiuser
backend/.venv-multiuser/bin/python -m pip install \
  'psycopg[binary]==3.3.6' \
  'cryptography==50.0.2'

backend/.venv-multiuser/bin/python -c \
'import psycopg, cryptography; from cryptography.hazmat.primitives.ciphers.aead import AESGCM; print("Dependency imports OK", psycopg.__version__, cryptography.__version__)'
```

Direct dependency pins: [psycopg 3.3.6](https://pypi.org/project/psycopg/3.3.6/), [cryptography 50.0.2](https://pypi.org/project/cryptography/50.0.2/). These are not a transitive/hash lock. If the operator maintains the new `backend/requirements-multiuser.txt`, add these two exact lines there; agents do not create/read/edit that protected manifest. Existing server process environments remain untouched.

## 3. Dedicated test role and database

Run once. `createuser` asks for a new local test DB password interactively; do not put it in a command argument, chat, source file or shell history. Keep it available for the next step.

```bash
sudo -u postgres createuser --pwprompt \
  --no-superuser --no-createdb --no-createrole \
  trading_balance_multiuser_test

sudo -u postgres createdb \
  --owner=trading_balance_multiuser_test \
  trading_balance_multiuser_test
```

If either name already exists, stop and confirm it belongs exclusively to this test environment; do not drop or overwrite it. This role owns only the new test database. Tests may create/delete synthetic rows/schema in this dedicated database; never substitute the production database URL. No PostgreSQL network port needs to be opened externally.

## 4. Local test input and separate test keys

From the checkout root, run this operator-owned setup. It prompts for the test DB password and writes a new restrictive-permission file without printing secrets. It refuses to replace an existing file. The file is for synthetic verification only and must not be committed.

```bash
backend/.venv-multiuser/bin/python - <<'PY'
from pathlib import Path
from getpass import getpass
from urllib.parse import quote
import base64
import os
import secrets

path = Path('backend/.env.multiuser.test')
if path.exists():
    raise SystemExit('Test input already exists; do not overwrite it.')
password = getpass('Dedicated PostgreSQL test role password: ')
if not password:
    raise SystemExit('A non-empty test password is required.')

def key():
    return base64.b64encode(secrets.token_bytes(32)).decode('ascii')

url = ('postgresql://trading_balance_multiuser_test:'
       + quote(password, safe='')
       + '@127.0.0.1:5432/trading_balance_multiuser_test')
# Quote each value for Bash sourcing; no values are printed.
import shlex
values = {
    'MULTIUSER_TEST_DATABASE_URL': url,
    'CREDENTIAL_VAULT_KEY': key(),
    'CREDENTIAL_VAULT_KEY_ID': 'v1',
    'REMOTE_IDENTITY_KEY': key(),
    'SESSION_SIGNING_KEY': secrets.token_hex(32),
    'MULTIUSER_ENABLED': 'false',
    'MULTIUSER_TRADE_ENABLED': 'false',
}
fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
with os.fdopen(fd, 'w') as file:
    for name, value in values.items():
        file.write(name + '=' + shlex.quote(value) + '\n')
print('Dedicated test inputs created.')
PY
```

Operator loads this trusted, locally generated file into the current verification shell; neither the existing API nor worker is restarted:

```bash
set -a
source backend/.env.multiuser.test
set +a

backend/.venv-multiuser/bin/python - <<'PY'
import os
import psycopg
with psycopg.connect(os.environ['MULTIUSER_TEST_DATABASE_URL']) as connection:
    assert connection.execute('SELECT 1').fetchone()[0] == 1
print('Dedicated PostgreSQL connection OK')
PY
```

No production DSN fallback is allowed. If bootstrap fails, report only the concise non-sensitive failure class; never send the input file or password.

## 5. Runtime verification

With the dedicated inputs loaded from step 4, initialize only the dedicated test database:

```bash
MULTIUSER_DATABASE_URL="$MULTIUSER_TEST_DATABASE_URL" \
  backend/.venv-multiuser/bin/python -m backend.auth init-schema
```

Run the negative/replay scenarios before the success path:

```bash
backend/.venv-multiuser/bin/python -m unittest -v \
  backend.tests.test_multiuser_auth.MultiuserAuthTests.test_replayed_totp_is_atomically_rejected \
  backend.tests.test_multiuser_auth.MultiuserAuthTests.test_recovery_requires_password_then_revokes_sessions_and_reenrolls

backend/.venv-multiuser/bin/python -m unittest -v \
  backend.tests.test_multiuser_auth.MultiuserAuthTests.test_two_users_have_independent_identity_and_mfa_state
```

Run real AES-GCM and PostgreSQL multi-process verification explicitly:

```bash
backend/.venv-multiuser/bin/python -m unittest -v \
  backend.tests.test_multiuser_auth.MultiuserAuthTests.test_aes_gcm_owner_aad_and_tamper_fail_closed_when_available \
  backend.tests.test_multiuser_store.PostgresIdentityStoreIntegrationTests
```

Required outcome: all four runtime integration tests run and pass, with no `skipped` results. The PostgreSQL cases use separate processes/connections for TOTP replay, recovery-code consumption/revocation, and enrollment/recovery serialization. Missing the explicit dedicated test URL blocks this evidence; do not set it to a production URL to bypass the gate.

Then run the focused related regression and build:

```bash
backend/.venv-multiuser/bin/python -m unittest \
  backend.tests.test_multiuser_auth \
  backend.tests.test_multiuser_store \
  backend.tests.test_trade_api -q

backend/.venv-multiuser/bin/python -m compileall -q backend
```

Send only exit codes, test counts, skip counts and concise non-sensitive failures. Do not send the environment file, password, keys, DSN or invite tokens. These tests fabricate exchange payloads and perform no real exchange trade.

Source-only tests do not establish real PostgreSQL concurrency or AES-GCM evidence. Keep both feature flags false until the remaining multi-user tasks and release audit pass. T110 is the identity foundation; it does not enable a multi-user exchange deployment by itself. The offline `init-schema`, `create-invite`, and `revoke-invite <invite_id>` commands use `MULTIUSER_DATABASE_URL` and the associated `SESSION_SIGNING_KEY`. Invite creation intentionally prints a private one-time activation token for the operator; do not paste or log it. Creating/revoking invites is unnecessary for running synthetic tests.

The implemented web transport uses Secure, HttpOnly, SameSite=Strict session cookies; browser ingress must be same-site or proxied through the frontend site. The trusted `ALLOWED_WEB_ORIGIN` and HTTPS/proxy topology are operator-confirmed launch settings. Cross-site Vercel-to-unrelated-VPS cookie operation is not verified by these tests. Native transport uses `X-Session-Transport: bearer`, with an ordinary Authorization bearer on authenticated requests; initial login/activation requires no existing bearer.

## 6. Later production actions

Production requires a separate `MULTIUSER_DATABASE_URL`, distinct vault/session/remote-identity keys, TLS/trusted origin, actual service-manager paths and ownership, and release approval. These are not inferred from the existing VPS. The operator supplies non-sensitive topology/path facts for the final launch runbook. Do not reuse synthetic keys or test DB for production.
