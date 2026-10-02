# Implementation Plan: Docker Management Script

Status: COMPLETE
Date: 2026-10-02
Tier: L
Specification: `docs/agents/specs/2026-10-02-docker-management-script.md`
Decision Ledger: `docs/agents/decisions/2026-10-02-docker-management-script.md`

## Objective and preconditions

Implement REQ-001 through REQ-004 and AC-001 through AC-004 in one root-level `docker_manage.sh`. User decision D-001 selects API plus worker by default. The script is the only operational file directly requested and authorized for creation; `release_build.sh`, Dockerfile, env files, Compose and other protected configuration remain outside scope. Actual Docker host operation is not authorized by this script-writing request.

## Planning workstreams

| Workstream | Material | Independent | Route | Logical run | Result |
|---|---|---|---|---|---|
| Docker lifecycle and host safety | YES | N/A, sole workstream | N/A | N/A | Coordinator-owned |
| Application API/worker code | NO, launch contract derived from documented flags | N/A | N/A | N/A | No product-code change |

Fan-out Required: NO
Required Reasoning Agents: 0
Actual Reasoning Agents: 0
Fan-out Compliance: EXCEPTION
Skip Reason: SINGLE_MATERIAL_WORKSTREAM

## Impact, dependency, and task routing

```text
T58 Docker script -> coordinator audit -> final integration verification
```

One task is appropriate despite Tier L because the script is one atomic lifecycle contract and one fake-Docker verification path. Executor class E1 (`gpt-6-luna` / `xhigh`) reflects bounded but non-mechanical shell state handling. Allowed write surface: `docker_manage.sh` only. The user has directly requested this one operational script, which is the task-specific exception to the general protected operational-file write rule; no other configuration path is writable.

## P01 — Implement the command dispatcher and lifecycle

1. Parse the exact CLI contract and reject invalid input before mutation. Resolve repository root independently of caller working directory.
2. Check only path existence for user-owned Dockerfile/env files/data directory. Use documented paths by default and safe non-secret path overrides for fake-Docker verification. Never read those file contents.
3. Implement build/start/stop/restart/rebuild/status/logs with exact container names, ordering, API loopback port, persistent mount, security flags, and API-only guard in the specification.
4. Keep Docker invocations as argument arrays or safely quoted positional arguments; no `eval`, secret echo, broad Docker cleanup, or automatic rollback claim.

RED: use a temporary fake Docker command to show failed build cannot trigger stop/rm/run, and missing prerequisite/API-only conflict fails before mutation. GREEN: use the same harness to observe successful command order and exact run arguments, plus idempotent lifecycle/read-only commands. Execute RED before GREEN at the formal checkpoint. `bash -n docker_manage.sh` is the task buildability gate after the final executable edit.

## Verification and limits

| Test | Contract | Method |
|---|---|---|
| TEST-001 | AC-001, AC-002 | Temporary fake-Docker RED harness; record exact command and call log summary. |
| TEST-002 | AC-003, AC-004 | Temporary fake-Docker GREEN harness; assert ordering, flags, named targets and no volume/data deletion. |
| TEST-003 | Script syntax/buildability | `bash -n docker_manage.sh` after last edit. |

Verification ceiling V2; broaden only if a concrete shell portability or state-transition failure remains. A real `docker build` is unavailable because Docker and the user-owned Dockerfile are absent in this checkout. Final repository build gate follows `EXECUTION_AUDIT_RULES.md` after implementation. The script must be auditable without actual deployment.

No migration, schema or product API change. The existing host prerequisites are documented in `docs/deployment/position-trade-api.md`; the script checks their presence but does not create or modify them. On failure after replacement begins, keep the persistent mount and return an actionable nonzero error. Rollback remains an operator action.

## Approval gate

This plan and `tasks/task_58_docker_management_script.md` must be presented to the user. `docker_manage.sh` is not created until explicit execution authorization follows this presentation.
