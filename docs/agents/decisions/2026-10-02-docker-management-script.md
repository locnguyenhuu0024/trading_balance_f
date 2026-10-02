# Decisions: Docker Management Script

Status: ACTIVE
Specification: `docs/agents/specs/2026-10-02-docker-management-script.md`
Plan: `docs/agents/plans/2026-10-02-docker-management-script.md`

| ID | Decision | Source |
|---|---|---|
| D-001 | One shell script manages both the trade API and strategy worker by default and offers an API-only mode. | User reply on 2026-10-02. |

The direct user request authorizes creating the single operational shell script identified in the plan. Existing Dockerfile, env files, and host configuration remain user-owned and are neither read nor modified by agents.
