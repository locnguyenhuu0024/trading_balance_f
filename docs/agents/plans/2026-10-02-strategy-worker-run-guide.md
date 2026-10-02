# Small Change Plan: Strategy worker run guide

Status: COMPLETE
Date: 2026-10-02
Tier: S — documentation only
Related implementation: T53/T54 and `docs/agents/plans/2026-10-02-strategy-background-order-monitor.md`

## Objective and Scope

The approved worker launch command exists in the implementation plan, but `docs/deployment/position-trade-api.md` omits the worker. Add copyable instructions to that guide for the user-owned worker env file, first launch, image replacement, restart, status check, and production scan validation. Preserve the guide's existing API Docker baseline and the approved worker env path, five keys, image, mounts, and module command. The guide is the only allowed product-documentation write.

Workstreams: deployment documentation is the single material workstream; fan-out required NO (`SINGLE_MATERIAL_WORKSTREAM`). No product behavior, API, Dockerfile, environment file, or dependency change is planned. The user's follow-up about missing run instructions authorizes completing this omitted T53/T54 documentation outcome.

## P01 / T55

Place a worker section after the API rebuild/restart commands. Document creation of `/etc/trading-balance/trade-api-worker.env` by the user with restrictive permissions and the five approved placeholder entries; do not read or write its contents. This supersedes the original home-directory target after the user observed `sudoedit` reject its writable parent. Provide a first-launch command using the rebuilt API image, shared persistent mount, UID 10001, and the API container's hardening flags without publishing a port. On later image changes, stop/remove the worker, rebuild/recreate the API, then recreate the worker. Separate restart-only from image replacement. Include a read-only container status command and an applied-strategy UI check after 5–10 seconds; note that health/status alone does not prove exchange synchronization.

RED: the deployment guide has no `strategy_worker` or worker env instructions. GREEN: the guide contains the exact approved command, safe lifecycle order, all five key names, and validation. Inspect the bounded diff and run `git diff --check -- docs/deployment/position-trade-api.md`. Verification ceiling V1. Buildability N/A (documentation only). Do not execute Docker or access protected configuration.

T55 passed after two bounded audit corrections: prevent overwriting an existing env file, and make the UI check apply only to eligible noncompleted strategies. See `docs/agents/audits/2026-10-02-task-55-strategy-worker-run-guide.md`.

User-reported deployment RED after T55: `sudoedit` refused the original home-directory env file because its parent was writable. Rework the guide and all active rollout instructions to use the existing root-owned `/etc/trading-balance` directory, then rerun the documentation GREEN checks. No protected file is inspected or edited by agents.

Rework result: the deployment guide and active T53 rollout contract now use `/etc/trading-balance/trade-api-worker.env`; the worker's first-create guard and Docker `--env-file` agree. `git diff --check` passed after the correction. Server-side `sudoedit` success remains for the user to confirm.

Follow-up documentation RED: the guide has separate API and worker run blocks, but its copyable image-replacement block stops only the API. The worker replacement text requires manually combining multiple sections, so the full API-then-worker update sequence previously given to the user is not present as one executable block. Add a complete combined update block: build image, stop/remove worker if present, stop/remove API, recreate API with its existing flags, then recreate worker with its existing flags and the corrected env path. Add first-deployment ordering and read-only status checks for both containers. Preserve the API-only procedure for deployments without a worker and label its applicability. Documentation-only V1 verification; no Docker execution.

Latest user instruction: prefix the operational Docker commands in this guide with `sudo`, including build, run, stop/remove, restart, and status checks for both API and worker. Keep `sudo` out of code/Dockerfile content and preserve all command flags.

Rework result: the guide gives first-deployment order, one copyable combined API/worker image-replacement sequence, and both status checks. Operational Docker commands use `sudo docker`; the API-only block is labeled for deployments without a worker. The API launch is explicitly identified as one WSGI worker. Scoped diff check passed; no Docker command was executed.
