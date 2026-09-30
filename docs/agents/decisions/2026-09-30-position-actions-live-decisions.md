# Decisions: Live OKX position actions

Status: ACTIVE
Specification: `docs/agents/specs/2026-09-30-position-actions-design.md`
Plan: N/A — clarification in progress

## Resolved user decisions

| ID | Decision | Source |
|---|---|---|
| D-001 | Implement real OKX position actions. | User reply to action scope. |
| D-002 | Per-card full close targets 100% of the selected position. | User reply to close scope. |
| D-003 | Add a separate page-level close-all action. It targets all supported open account positions regardless of the selected display filter. | User replies to action scope and filter scope. |
| D-004 | Every action requires a confirmation popup before a write request. | User instruction. |
| D-005 | DCA uses a market order with quantity entered in the position's unit. | User reply to DCA style. |
| D-006 | Full close cancels pending closing orders first. | User reply to pending-order policy. |
| D-007 | The first release may support eligible MARGIN, SWAP, and FUTURES positions; OPTION is excluded. | User replies to product scope. |
| D-008 | Partial close uses 25%, 50%, 75%, or a custom percentage. | User reply to partial-close input. |
| D-009 | The intended live environment is OKX production. The current API key has read-only permission. | User replies to environment and permission questions. |
| D-010 | Use a private Python backend to hold and use the Trade key; no server/API exists yet. | User replies to architecture and runtime questions. |
| D-011 | Disable MARGIN DCA/partial-close cases that cannot express the requested position-unit quantity or exact percentage under the documented OKX market-order contract. | User reply to MARGIN sizing restriction. |
| D-012 | Place the Python backend under `backend/` in this repository. Prepare code and deployment instructions now; no server/API exists yet. | User reply to code location and hosting question. |
| D-013 | Use password plus TOTP for single-user backend login with a short-lived Flutter web session. | User reply to authentication question. |
| D-014 | User-owned production secrets belong in `/etc/trading-balance/trade-api.env` on the future server; the public API URL is provided to Flutter through `--dart-define` at build time. | User reply to configuration-location proposal. |
| D-015 | The future server host runs Ubuntu 24.04 LTS; the Python API runs in a Docker container. This is the deployment target for T34, while the current deliverable remains code and deployment guidance. | User replies to Docker/Ubuntu clarification. |

## Open clarification questions

### Q-001 — Secret boundary and server architecture

Status: ANSWERED
Question: Will the user approve a private HTTPS API that stores the Trade key and signs OKX requests server-side?
Decision: D-010. A web client must use a decrypted signing secret to sign requests, so client-side encryption cannot keep a production Trade secret private from code running in the browser.

### Q-002 — Existing server capability and authentication

Status: ANSWERED
Question: Does the user already have a private HTTPS API and app authentication, and which runtime can it run?
Decision: D-010, D-012, D-013. No existing server/API; backend Python code is prepared now and deployed by the user later.

### Q-003 — Protected configuration action

Status: ANSWERED
Question: What exact user-owned protected path and key/section will hold the OKX Trade credential and client API URL after architecture selection?
Decision: D-014. The planned environment file lives outside Git on the future server; the Flutter URL is a build argument. Agents cannot inspect protected configuration contents or create/edit those files.

### Q-004 — MARGIN market sizing restriction

Status: ANSWERED
Question: May DCA/partial-close controls be disabled for MARGIN cases where the documented market-order size unit cannot express the user's position-unit quantity or exact percentage?
Decision: D-011. OKX documents MARGIN market buys in quote currency and sells in base currency; an estimated conversion is not exact and can change with market price.

## Evidence

- Read-only UI, API, and security planning workstreams were separately dispatched and reconciled. An independent specification critique found fail-closed cases that the coordinator incorporated.
- The [OKX place-order contract](https://www.okx.com/docs-v5/en/#rest-api-trade-place-order) supplies the product-specific market-size rules.
- The current application order repository reads positions and orders but has no trade write methods; the position model lacks fields required to identify all action targets.

No user-authorized assumption has been made for an open question.

## Deployment revision

D-015 supersedes any bare-host Python startup suggestion. It does not authorize agents to create or edit Dockerfiles, Compose files, reverse-proxy configuration, or environment files; those are protected user-owned configuration surfaces under `AGENTS.md`. T34's deployment guide must provide the exact non-secret user-applied container recipe and commands.
