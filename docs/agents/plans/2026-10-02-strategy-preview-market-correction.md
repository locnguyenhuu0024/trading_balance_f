# Implementation Plan: Strategy preview market correction

Status: IMPLEMENTED_AUDITED
Date: 2026-10-02
Tier: L
Specification: `docs/agents/specs/2026-10-02-strategy-preview-market-correction.md`
Decision Ledger: `docs/agents/decisions/2026-10-02-strategy-preview-market-correction.md`

## Objective and boundary

Resolve the evidenced SOL strategy preview 502, exact tick prices, separate equal-price orders, Both-side enforcement, and quote request lifecycle. This plan authorizes no implementation by itself. Product/test mutation begins only after explicit user approval under repository `AGENTS.md`; commit, push, release and deployment remain separate decisions.

## Planning workstreams and synthesis

| Workstream | Material / independent | Explicit requested route | Logical run | Result |
| --- | --- | --- | --- | --- |
| Backend preview, tiers, persisted order compatibility | YES / YES | R2 `gpt-6-sol` / `medium` | R2-001 | COMPLETE / USED |
| Flutter analysis, selection, wizard and polling | YES / YES | R2 `gpt-6-sol` / `medium` | R2-002 | COMPLETE / USED |
| Exact decimal/tick algorithm and artifact risk | YES / YES | R3 `gpt-6-sol` / `high` | R3-001 | COMPLETE / USED |
| Duplicate-price identity and compatibility | YES / YES | R3 `gpt-6-sol` / `high` | R3-002 | COMPLETE / USED |
| Transport/error behavior | YES / YES | R2 `gpt-6-sol` / `medium` | R2-003 | COMPLETE / PARTIAL |

Fan-out Required: YES. Required reasoning agents: 2 (frontend and backend). Actual reasoning agents: 5. Fan-out Compliance: PASS. Skip reason: N/A. Child requests explicitly bound model and effort; effective routes were not exposed. The coordinator reconciled the backend 502 evidence with the separate price precision defect, selected additive IDs to preserve old drafts, and retained fresh server preflight while removing UI timers.

## Dependency graph and bounded tasks

| Step / task | Outcome | Predecessor | Executor contract | Build unit |
| --- | --- | --- | --- | --- |
| P01 / T46 | Accept valid OKX isolated tier rows with omitted duplicated type/mode fields; reject explicit conflicts. | none | `implementation_executor`, E0, `gpt-6-luna` / `high`, EXPLICIT, no parent inheritance | `python3.12 -m compileall -q backend` |
| P02 / T47 | Add v2 level IDs/direction, distinct equal-price orders, grouped liquidation, old-draft/hash compatibility. | T46 PASS | `implementation_executor`, E2, `gpt-6-luna` / `max`, EXPLICIT, no parent inheritance | `python3.12 -m compileall -q backend` |
| P03 / T48 | Preserve exact market decimals, quantize displayed/requested levels, enforce Both, remove wizard timers/freshness gates. | T47 PASS | `implementation_executor`, E2, `gpt-6-luna` / `max`, EXPLICIT, no parent inheritance | `rtk flutter build web --release` |
| P04 / T49 | Poll quotes only for visible, started strategies; retain backoff/visibility/status refresh. | T48 PASS | `implementation_executor`, E1, `gpt-6-luna` / `xhigh`, EXPLICIT, no parent inheritance | `rtk flutter build web --release` |

Each executor receives only its task write surface and fixed contract. Any discovered API, business, or compatibility ambiguity returns to coordinator planning. No task may alter protected configuration/environment files or read their contents.

## Verification and integration

Each task records meaningful formal RED before GREEN; use focused fake OKX/client tests and no live order submission. T46/T47: `python3.12 -m unittest backend.tests.test_strategy_api -v`, then Python compileall after the last backend edit. T48/T49: focused strategy Flutter tests through RTK, then `rtk flutter build web --release` after the last Flutter edit. At integration, rerun affected backend and Flutter strategy tests, RTK Flutter analyze, backend compileall, Flutter web build, and `git diff --check`. Broaden only for a concrete shared regression.

Audit API compatibility (legacy no-ID drafts/hash, new ID order persistence/retry), two-ended Hedge-mode batch payload, equal-price group liquidation label, <=20 rows, reference quote call count, server preflight, and dashboard DRAFT/PREPARED no-poll behavior. No configuration, database migration, or external action is required. Because the public domain is not locally deployable by this plan, the original production 502 is finally verified only after a separately authorized backend deployment and a safe user retry; local fake tests/builds are the implementation gate.

Rollback: revert the coordinated backend/frontend application changes before deployment if contract audit fails; after deployment, revert both versions together if the new ID contract fails in production. Do not rewrite or replay already attempted strategies.

## Requirement traceability

| Requirement | Acceptance | Task |
| --- | --- | --- |
| REQ-001 | AC-001 | T46 |
| REQ-002 | AC-002 | T47, T48 |
| REQ-003 | AC-003 | T47, T48 |
| REQ-004 | AC-004 | T48, T49 |

Execution and audit: user authorized T46/T47, then T48/T49. T46–T49 passed their task audits; final audit remediation T50 removed introduced analyzer warnings and passed. Backend strategy tests (28), Flutter strategy tests (52), backend compileall, targeted strategy analyzer (no warnings/errors), final Flutter web release build, and diff whitespace checks passed. Repository-wide analyzer still reports unrelated existing warnings and informational lints. No protected configuration action was required. Production recovery of the original 502 remains unverified until a separately authorized deployment and safe retry; commit, push, release, and deployment remain separate decisions.
