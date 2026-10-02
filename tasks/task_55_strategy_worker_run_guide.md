# Task 55 — Document strategy worker startup and replacement

Status: PASS
Plan: `docs/agents/plans/2026-10-02-strategy-worker-run-guide.md` P01
Agent Role: implementation_executor
Executor Class: E0
Target Model: gpt-6-luna
Target Effort: high
Target Route: gpt-6-luna / high
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Dispatch Route Status: UNVERIFIABLE (explicit model/effort bound; runtime effective route unavailable)

Allowed write: `docs/deployment/position-trade-api.md` only. Preserve existing API run/rebuild/restart instructions. Add the user-owned worker env setup, first launch, replacement/restart, and checks using the approved T53/T54 contract. Do not read/write config, env, Dockerfile, dependency, or other files; do not deploy, commit, or push.

RED: current deployment guide lacks worker instructions. GREEN: guide has approved env path/five keys, correct worker command and shared SQLite mount, safe image replacement sequence, and status/UI checks. Run focused `git diff --check`; no runtime build or Docker execution. Return a concise report for coordinator audit.

Verdict: PASS. The guide now includes the worker lifecycle and validation. An existing worker env file is not overwritten. The UI scan check identifies eligible noncompleted strategies. Scoped `git diff --check` exited 0. Documentation-only buildability is N/A. See `docs/agents/audits/2026-10-02-task-55-strategy-worker-run-guide.md`.

Reopened after user-run RED: `sudoedit` refused the home-directory env file because its parent was writable. Bounded remediation: in the allowed guide only, replace worker env creation/edit and Docker `--env-file` with `/etc/trading-balance/trade-api-worker.env`, preserving the five keys and root-only permissions. Explain why the original path was superseded; do not read/move/delete the existing user-owned home-directory env file. GREEN: guide has one consistent worker env target and safe first-create guard; `git diff --check` exits 0. No Docker execution.

Rework verdict: PASS for documentation. The guide's env creation/edit and Docker launch all use the root-owned `/etc/trading-balance/trade-api-worker.env` path; the existing-file guard remains. The user has not yet confirmed the new `sudoedit` command on the server.

Reopened after user asked whether the complete API/worker command sets were incorporated. RED: the guide lacks one copyable combined image-replacement sequence and only the API appears in its existing rebuild block. Remediation within the allowed guide: add first-deployment order, one full combined rebuild/recreate sequence with worker stop/remove before API and API start before worker, and read-only status checks for both. Preserve exact security flags, bind mount, loopback API port, worker env path, and no worker port. GREEN: inspect command order and `git diff --check`; documentation buildability N/A.

Latest user instruction: every operational Docker command in the guide must begin with `sudo docker`, including build, run, stop/remove, restart, status inspection, and inline command references. Do not change Dockerfile content.

Final rework verdict: PASS. First deployment and combined image replacement now appear in the guide with `sudo docker` commands, correct API-before-worker start and worker-before-API stop order, preserved runtime flags and env paths, and read-only checks for both containers. `git diff --check` exited 0; documentation buildability N/A. No Docker execution.
