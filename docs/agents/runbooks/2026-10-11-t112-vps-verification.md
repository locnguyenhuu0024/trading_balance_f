# T112 Ubuntu 24.04 verification

Status: READY_AFTER_SOURCE_DELIVERY — source audit PASS; operator execution pending
Task: T112 / P03. Existing dedicated multi-user test runtime is reused. No new dependency or configuration action is required. This runbook is not permission to activate production, contact Binance/OKX, or run trades.

## Runtime verification after source delivery

From the repository checkout on VPS, use the existing operator-managed test environment and isolated test database. Do not paste credentials, connection strings, key material, or environment contents into chat.

```bash
set -a
source backend/.env.multiuser.test
set +a
backend/.venv-multiuser/bin/python -m unittest \
  backend.tests.test_exchange_contracts \
  backend.tests.test_binance_reads \
  backend.tests.test_exchange_read_routes \
  backend.tests.test_data_gateway \
  backend.tests.test_positions_read_pressure \
  backend.tests.test_multiuser_ownership \
  backend.tests.test_credential_vault -q
```

```bash
backend/.venv-multiuser/bin/python -m unittest \
  backend.tests.test_strategy_list_reads \
  backend.tests.test_strategy_scope \
  backend.tests.test_trade_api -q
```

```bash
backend/.venv-multiuser/bin/python -m compileall -q backend
printf 'compileall exit=%s\n' "$?"
```

Return only the final test summary, skip summary if any, sanitized failure traceback, and compileall exit. Expected: all scoped tests pass; actual AES-GCM cases execute without skips; compileall exit0. Expected suite counts after T120:123 and92, both OK without skips when existing crypto/PostgreSQL runtime is ready. Local Mac results:119/5skips and92/1skip; source audit PASS and compileall0. These commands use fixture transports, including local HTTP test servers, and make no real venue requests. Never substitute a production database for MULTIUSER_TEST_DATABASE_URL.

## Venue verification is a separate gate

These tests use fabricated credentials and fixture transports. They do not establish venue integration or authorize live reads/orders. Binance demo activation remains closed until authoritative API-key permission and identity binding are documented and verified. Standard USD-M accountAlias is not a canonical UID. No operator should enable trade flags merely to run this source test suite. Binance actions/strategies are not enabled by T112.

## T120 slow-projection regression

The first119-case operator run failed one local projection with data_stale on slower hardware; the other92 cases and compileall passed without skips. Pull the T120 revision on the same branch, then run:

```bash
backend/.venv-multiuser/bin/python -m unittest -v \
  backend.tests.test_exchange_read_routes.ExchangeReadRouteTests.test_slow_owned_strategy_projection_freezes_stale_rows_with_truthful_timestamps \
  backend.tests.test_exchange_read_routes.ExchangeReadRouteTests.test_owned_strategy_projection_uses_bound_sql_and_frozen_pages_without_upstream
```

Expected2 tests OK. Then rerun the first full group above (now123 cases) and compileall; the unchanged92-case operator result is retained. The fix permits only persisted strategy snapshots to report stale=true and keeps original timestamps, owner/session/generation guards and venue freshness unchanged. No new configuration/install or real venue call is needed.
