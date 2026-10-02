# Task 51 — Document Docker rebuild and restart

Status: PASS
Plan: `docs/agents/plans/2026-10-02-docker-rebuild-guide.md` P01
Agent Role: implementation_executor
Executor Class: E0
Target Model: gpt-6-luna
Target Effort: high
Target Route: gpt-6-luna / high
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Dispatch Route Status: UNVERIFIABLE (explicitly bound; effective route unavailable)

## Objective and scope

Update only `docs/deployment/position-trade-api.md` with rebuild/recreate and restart-only commands matching its existing Docker-run baseline. Preserve the current container name, `--env-file`, persistent mount, security flags, and `127.0.0.1:8000:8000` binding. Do not read/write protected Docker, environment, Nginx, or other configuration files. Do not run Docker, deploy, commit, or push.

RED: bounded current section has build and initial run but no replacement sequence. GREEN: edited guide has exact build, graceful stop, remove, same-flags run, separate restart-only command, and read-only status check. Inspect text and run `git diff --check -- docs/deployment/position-trade-api.md`; verification ceiling V1. Task buildability: N/A (documentation only). External configuration and verification actions: none.

Stop and return BLOCKED if documenting the user’s actual container requires protected configuration details or a launch method contradicting the guide. Coordinator audits command safety, persistence, scope, and diff.

## Completion and coordinator audit

Verdict: PASS. RED was the absence of a replacement sequence in the existing guide. GREEN: the edited guide gives build, stop, remove, same-flags run, separate restart-only, and read-only status commands; `git diff --check -- docs/deployment/position-trade-api.md` exited 0. Coordinator inspected the diff and confirmed the environment-file path, persistent bind mount, security flags, and loopback port match the original run example. Documentation-only buildability N/A. No Docker command was executed and no protected configuration file was read or changed. Effective child route was not exposed after explicit `gpt-6-luna` / `high` binding.
