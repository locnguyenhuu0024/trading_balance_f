# Coordinator Audit — T55

Task: `tasks/task_55_strategy_worker_run_guide.md`
Verdict: PASS

- RED: the existing deployment guide had no worker env, `backend.strategy_worker`, or worker replacement instructions.
- GREEN: `docs/deployment/position-trade-api.md` now documents the approved five-key user-owned env file, first worker launch with shared API volume and no published port, restart versus image replacement, read-only container status, and an eligible-strategy scan check.
- Audit correction AUD-T55-01: initial file-creation command could truncate an existing env file. The final command creates it only when neither a file nor symlink exists. A second correction limits the UI freshness check to noncompleted applied strategies with outstanding submitted orders.
- Scope: only the approved deployment guide changed as product documentation. The coordinator's plan/task/audit/telemetry are framework artifacts. Protected configuration contents were not inspected or edited. No Docker command, deployment, commit, or push occurred.
- Route: E0 `gpt-6-luna` / `high` explicitly bound; effective child route unavailable. `git diff --check -- docs/deployment/position-trade-api.md` exited 0 after the final edit. Buildability N/A for documentation only.

## User-reported deployment correction

- RED: the user ran the original home-directory `sudoedit` command and received `editing files in a writable directory is not permitted`. No secret or env-file content was requested or inspected.
- The active guide, worker env create/edit commands, and Docker `--env-file` now use `/etc/trading-balance/trade-api-worker.env`, under the root-owned directory already specified for the API. The first-create guard remains and does not overwrite an existing env file or symlink.
- GREEN documentation audit: no old worker env path remains in the deployment guide; `git diff --check -- docs/deployment/position-trade-api.md` exited 0. Actual server-side success and worker operation are pending user verification. Verdict remains PASS for the documentation change.

## Complete API and worker commands

- Follow-up RED: the guide's API-only image-replacement block did not include the strategy worker, and the full sequence required manual assembly from separate sections.
- GREEN: the guide now states first-deployment order and gives one copyable combined replacement block: build image; conditionally stop/remove worker; stop/remove API; start API with its original flags; start worker with the corrected root-owned env file and shared volume. It includes status checks for both containers.
- The user's `sudo` preference is reflected in every operational Docker command, including inline restart examples. The API run text identifies its one WSGI worker to avoid confusion with the strategy monitor. Scoped `git diff --check` exited 0 after the final edit. No Docker command was executed; actual server behavior remains user-owned verification.
