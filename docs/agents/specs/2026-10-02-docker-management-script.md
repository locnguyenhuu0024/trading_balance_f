# Design Specification: Docker Management Script

Status: READY_FOR_PLAN
Date: 2026-10-02
Tier: L
Decision Ledger: `docs/agents/decisions/2026-10-02-docker-management-script.md`

## Objective and evidence

Provide one root-level Bash script that runs the documented Docker lifecycle for the trade API and strategy worker. The operator can build an image, start, stop, restart, rebuild/recreate, inspect status, and read logs from one entry point. D-001 sets the default scope to both containers, with API-only mode.

| ID | Non-protected evidence | Observation |
|---|---|---|
| OBS-001 | `docs/deployment/position-trade-api.md` | API and worker use one image; worker uses `--volumes-from` the API container. Rebuild order is worker removal, API replacement, then worker creation. |
| OBS-002 | `docs/deployment/position-trade-api.md` | Documented names, env-file paths, bind mount, loopback port, UID and hardening flags are available without inspecting protected files. |
| OBS-003 | Path existence only | `backend/Dockerfile` is missing in this checkout; it is a user-owned prerequisite on the Docker host. Docker and shellcheck executables are unavailable here. |
| OBS-004 | `release_build.sh` path existence only | An existing release script is present; its contents are protected and outside this change. |

## Scope and command contract

Create only `docker_manage.sh` at repository root. It is an operational script explicitly requested by the user. Do not inspect or edit `release_build.sh`, Dockerfile, env files, dependency/build manifests, Compose, CI, or deployment settings. Do not run real Docker lifecycle commands during implementation.

Syntax: `./docker_manage.sh [--api-only] <build|start|stop|restart|rebuild|status|logs|help> [api|worker]`. The optional `api|worker` target is accepted only for `logs` and defaults to `api`; `worker` is invalid in API-only mode. Other commands always act on the selected scope (both by default, API only with `--api-only`) and reject extra positional arguments before Docker mutation.

| Command | Required behavior |
|---|---|
| `build` | Build `trading-balance-trade-api` from repository root using `backend/Dockerfile`; leave containers untouched. |
| `start` | Use the existing image; create missing containers or start stopped ones, API before worker; leave running containers untouched. |
| `stop` | Stop worker then API when running; never remove containers or data. |
| `restart` | Require all selected containers to exist before mutation; restart API then worker without building or replacing. |
| `rebuild` | Validate prerequisites, build successfully before touching containers, stop/remove worker then API, recreate API then worker from the new image. |
| `status` | Report exact named containers as running, stopped, or missing without mutation. |
| `logs` | Show the last 100 lines from the selected existing container without following by default. |

The script locates the repository root from its own path. It calls `docker` directly; the operator supplies Docker permission (for example by invoking the script with `sudo`). For local mock verification, non-secret path variables may override the default Dockerfile, API env-file, worker env-file, and persistent-directory paths; container names, image name, mount target and API port remain fixed. All path arguments are quoted and never evaluated as shell code.

## Requirements and invariants

- REQ-001: Preserve the documented API run flags: one image, container name `trading-balance-trade-api`, UID/GID `10001:10001`, read-only root, tmpfs, dropped capabilities, no new privileges, PID limit, API env-file, `/var/lib/trading-balance` bind mount, and `127.0.0.1:8000:8000` port mapping.
- REQ-002: Preserve the documented worker flags and name `trading-balance-strategy-worker`, using the API image and `--volumes-from trading-balance-trade-api`; publish no worker port. Recreate the worker after the API on rebuild.
- REQ-003: Fail before mutation on missing required files/directories, unavailable Docker/image, invalid arguments, or an API-only mutation when a worker container exists. Never read env-file or Dockerfile contents itself. A missing `backend/Dockerfile` blocks `build`/`rebuild` with an actionable message.
- REQ-004: `rebuild` must not stop a container if image build fails. Never run `docker system prune`, remove volumes, delete the SQLite bind directory, or target containers other than the two documented names. On a later recreate failure, exit nonzero and report the stopped state; do not claim automatic rollback.
- INV-001: Existing SQLite files under the host bind mount survive every command.
- INV-002: API-only mode is allowed only when no worker container exists for mutating commands, preventing a worker from retaining a stale `--volumes-from` relationship.
- INV-003: The script never echoes secrets or env-file contents.

## Acceptance and verification

| ID | Scenario | Expected result |
|---|---|---|
| AC-001 / RED-001 | Fake Docker build fails during `rebuild` | Nonzero exit; no stop, rm, run, or data-directory operation. |
| AC-002 / RED-002 | Missing prerequisite or API-only command while worker exists | Nonzero exit before selected container mutation; clear safe message. |
| AC-003 / GREEN-001 | Fake Docker success for default `rebuild` | Build precedes stop/remove; worker stops/removes before API; API runs before worker with exact documented security, mount and port flags. |
| AC-004 / GREEN-002 | Fake Docker state for start/stop/restart/status/logs | Exact named containers and idempotent state handling; restart never rebuilds; status/logs are read-only. |

Run formal RED before GREEN with a temporary local fake Docker executable and temporary prerequisite paths; no real Docker daemon or protected file is needed. Run `bash -n docker_manage.sh` after the final edit and the focused fake-Docker harness. No actual deployment is part of this request.

## Rollout, rollback, and limits

The operator places the script in a host checkout with the user-owned `backend/Dockerfile`, API env file, worker env file and persistent SQLite directory described in the guide, then invokes a command with Docker permissions. The current checkout lacks the Dockerfile, so a real image build cannot be verified here. `rebuild` is not an atomic deployment; if recreation fails after replacement starts, fix the prerequisite and rerun `start` or restore the prior image through the operator's normal process. The script must not implement automatic exchange/order or database recovery.

No new configuration content is required by the script. The existing user-owned prerequisite paths are checked by existence only. Protected configuration contents are not an evidence source.
