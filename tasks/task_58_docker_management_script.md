# Task 58 — Docker Management Script

Status: PASS
Agent Role: implementation_executor
Executor Class: E1
Target Model: gpt-6-luna
Target Effort: xhigh
Target Route: gpt-6-luna / xhigh
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Dispatch Route Status: UNVERIFIABLE
Observed Effective Model: unavailable
Observed Effective Effort: unavailable
Specification: `docs/agents/specs/2026-10-02-docker-management-script.md`
Plan: `docs/agents/plans/2026-10-02-docker-management-script.md`
Plan Steps: P01
Requirements: REQ-001, REQ-002, REQ-003, REQ-004
Acceptance Criteria: AC-001, AC-002, AC-003, AC-004

## Objective and boundaries

Create the one root-level `docker_manage.sh` CLI from P01. Allowed write surface: `docker_manage.sh` only, under the user's direct script-creation request and post-plan execution authorization. Do not inspect or edit `release_build.sh`, Dockerfile, env files, Compose, manifests or other operational configuration. Do not run real Docker lifecycle commands, deploy, commit or push.

## RED / GREEN

- RED-001: fake Docker build failure during `rebuild` leaves both containers untouched.
- RED-002: missing prerequisite and API-only mode with an existing worker fail before mutation.
- GREEN-001: successful fake Docker `rebuild` builds first, removes worker before API, then creates API before worker with exact documented flags.
- GREEN-002: start/stop/restart/status/logs target only the named containers with idempotent and read-only behavior where specified.

Execute the focused formal RED cases before GREEN after implementation. Use a temporary fake Docker harness outside the repo; never require real Docker or protected file contents. Task buildability: `bash -n docker_manage.sh` after the final edit. Verification ceiling V2. Report exact commands, outcomes, and the unverified real-host prerequisite. Stop for coordinator decision if the documented Docker-run contract cannot be honored without reading or editing protected configuration.
