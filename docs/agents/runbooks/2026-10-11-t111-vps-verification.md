# T111 verification on Ubuntu 24.04

Status: READY FOR OPERATOR VERIFICATION — source audit and local related regression pass. Pull the reviewed T111 revision from `codex/multi-user-okx-binance-plan` onto the VPS before running these commands. This runbook is not release approval.

## Focused rerun after T118 fixture correction

The operator's307-test run had one failure: the PostgreSQL API fixture omitted selectedLevels and was rejected before lease contention. T118 supplies a valid shared fixture and local coverage, preserving the production validators and exact PostgreSQL race assertions. After pulling the correction and loading the existing test environment as below, rerun only the affected scope:

```bash
backend/.venv-multiuser/bin/python -m unittest \
  backend.tests.test_strategy_scope \
  backend.tests.test_strategy_worker -q
backend/.venv-multiuser/bin/python -m compileall -q backend
printf 'compileall exit=%s\n' "$?"
```

Required: all affected tests pass with no PostgreSQL skip; compileall exit0. Send the concise test summary and build exit status. The earlier unaffected results can be reused; a full regression rerun is unnecessary for this fixture-only correction.

Reuse the existing Python environment and dedicated test database from [T110 setup](2026-10-10-ubuntu-24-04-multiuser-setup.md). No additional packages or Mac installation are required. The operator owns `backend/.env.multiuser.test`; its exported `MULTIUSER_TEST_DATABASE_URL` must target only the dedicated disposable test database. Do not disclose its contents. These tests create and remove isolated random schemas, use fabricated exchange responses, and do not trade on an exchange. Keep feature flags disabled.

From the repository root on the VPS, load the existing test environment without displaying values:

```bash
set -a
source backend/.env.multiuser.test
set +a
```

Run negative owner/authority/send-boundary cases before the intended-success cases:

```bash
backend/.venv-multiuser/bin/python -m unittest -v \
  backend.tests.test_multiuser_ownership.MultiuserOwnershipBaselineTests.test_connection_id_guess_is_owner_first_uniform_404_without_upstream \
  backend.tests.test_multiuser_ownership.MultiuserOwnershipBaselineTests.test_revoke_same_account_relink_keeps_id_and_unknown_barrier \
  backend.tests.test_command_claims.CommandExecutionBoundaryTests.test_generation_change_after_prepare_cancels_without_send \
  backend.tests.test_command_claims.CommandExecutionBoundaryTests.test_send_timeout_persists_unknown_and_same_key_replay_does_not_resend
```

```bash
backend/.venv-multiuser/bin/python -m unittest -v \
  backend.tests.test_multiuser_ownership.MultiuserOwnershipBaselineTests.test_authenticated_owner_can_list_owned_connections \
  backend.tests.test_command_claims.CommandExecutionBoundaryTests.test_supported_close_polls_marker_during_send_and_same_key_returns_proven_result \
  backend.tests.test_strategy_scope.OwnedStrategyLookupTests.test_owned_worker_queue_persists_markers_and_ack_with_advancing_transport \
  backend.tests.test_strategy_scope.OwnedStrategyLookupTests.test_owned_worker_persists_readonly_same_owner_recovery_without_resending
```

Run real AES-GCM and PostgreSQL checks for the changed T111 scope plus the affected T110 identity foundation:

```bash
backend/.venv-multiuser/bin/python -m unittest -v \
  backend.tests.test_credential_vault.CredentialVaultAesGcmTests \
  backend.tests.test_multiuser_ownership.PostgresOwnedConnectionIntegrationTests \
  backend.tests.test_command_claims.PostgresCommandClaimIntegrationTests \
  backend.tests.test_strategy_scope.PostgresOwnedStrategyIntegrationTests \
  backend.tests.test_multiuser_auth.MultiuserAuthTests.test_aes_gcm_owner_aad_and_tamper_fail_closed_when_available \
  backend.tests.test_multiuser_store.PostgresIdentityStoreIntegrationTests
```

Required result: ten tests pass, zero skips. Missing crypto runtime or explicit test URL is a verification blocker. Do not substitute a production database. These tests cover real encryption/AAD, concurrent v1 schema upgrade with preserved rows, command claims/revoke/expired fences, and API/worker shared connection fences, alongside identity replay/recovery races.

Run the related V3 regression scope and final package build:

```bash
backend/.venv-multiuser/bin/python -m unittest \
  backend.tests.test_multiuser_auth \
  backend.tests.test_multiuser_store \
  backend.tests.test_multiuser_ownership \
  backend.tests.test_credential_vault \
  backend.tests.test_command_claims \
  backend.tests.test_trade_api \
  backend.tests.test_strategy_scope \
  backend.tests.test_strategy_api \
  backend.tests.test_strategy_automatic \
  backend.tests.test_strategy_queue \
  backend.tests.test_strategy_worker -q
```

```bash
backend/.venv-multiuser/bin/python -m compileall -q backend
printf 'compileall exit=%s\n' "$?"
```

Report only counts, exit status, skip count, and concise non-sensitive failures. No environment contents, DSN, passwords, keys, credentials or activation tokens. Successful synthetic verification does not authorize production migration, feature activation or deployment.
