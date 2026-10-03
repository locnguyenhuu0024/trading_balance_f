# Small Change Plan: Docker rebuild and restart instructions

Status: COMPLETE
Date: 2026-10-02
Tier: S

## Objective

Add copyable rebuild/recreate and restart-only commands for the trade API container to the existing deployment guide.

## Evidence and Scope

- Current guide: `docs/deployment/position-trade-api.md` documents `docker build` and the initial `docker run`, but not how to replace a running container after rebuilding. It mentions `docker restart` only in a persistence check.
- The guide's baseline uses container name `trading-balance-trade-api`, host loopback port 8000, a user-owned environment file, and a persistent SQLite bind mount. `backend/Dockerfile` is absent from this local checkout; the commands apply on a host checkout where the user-owned Dockerfile exists.
- Allowed file: `docs/deployment/position-trade-api.md` only. Preserve the existing run flags, mount, environment-file path, and network binding. Do not inspect or edit Dockerfile, environment files, Nginx, or other protected configuration.
- Workstreams: deployment documentation is the single material workstream; fan-out required NO; fan-out compliance SKIPPED with `SINGLE_MATERIAL_WORKSTREAM`. No material clarification is open because the guide already establishes the Docker-run setup.

## Implementation Step — P01

Add a short section after the initial `docker run` example:

1. From the server repository root, rebuild the image using the guide's existing `docker build` command.
2. Gracefully stop and remove only `trading-balance-trade-api`, then recreate it with the same documented `docker run` flags, environment file, bind mount, and loopback port. State that `docker restart` alone does not load a newly built image.
3. Give `docker restart trading-balance-trade-api` as a separate restart-only command and include a read-only container-status check.

RED: the current guide lacks an end-to-end rebuild/recreate sequence; verify by inspecting the current bounded section. GREEN: inspect the edited section for the exact sequence, persistent mount and safe loopback binding, then run `git diff --check -- docs/deployment/position-trade-api.md` (exit 0). Verification ceiling V1; no Docker commands are executed.

Task buildability gate: N/A, documentation only. Affected canonical build unit: N/A. External verification: none. External configuration/environment action: none; the Dockerfile and env file remain user-owned prerequisites already documented in the guide.

Stop if the documentation must represent a Compose or custom production launch configuration instead of the existing guide's Docker-run baseline; do not inspect protected configuration to resolve this.

## Task and Approval Gate

T51 implemented P01. Executor class E0, explicitly bound `gpt-6-luna` / `high` route. User authorization was given after plan presentation. RED/GREEN and diff check passed; documentation buildability is N/A. The coordinator audited the new commands and found no protected configuration action.
