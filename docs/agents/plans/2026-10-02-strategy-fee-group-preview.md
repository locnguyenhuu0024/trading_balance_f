# Implementation Plan: OKX Fee Group Strategy Preview

Status: COMPLETE
Date: 2026-10-02
Tier: L
Specification: `docs/agents/specs/2026-10-02-strategy-fee-group-preview.md`
Decision Ledger: N/A

## 1. Objective and Preconditions

Implement REQ-001–003 / AC-001–003 in one bounded backend task. Production root cause remains unconfirmed; the documented-format fee 502 is reproduced offline. Current branch is `feature/position-strategy`; worktree was clean before this planning change. No external configuration action is required.

## 2. Repository Impact

| Area | File | Symbol | Change |
|---|---|---|---|
| OKX client | `backend/okx.py` | `trade_fee` | Validate exactly one fee data row. |
| Strategy | `backend/strategy.py` | `_load_market_inputs` | Select exact instrument fee group and normalize signed rates. |
| Tests | `backend/tests/test_strategy_api.py` | fake responses and focused preview tests | Exercise current OKX fee format, calculations, and malformed branches. |

No frontend, database, migration, protected configuration, build manifest, Docker, proxy, or deployment files may be edited. No live OKX order operation.

## 3. Planning Workstreams

| Workstream | Material | Independent | Route | Logical agent run | Result |
|---|---|---|---|---|---|
| OKX external fee contract | YES | YES | R3 / gpt-6-sol / high, explicit | R3-FEE-CONTRACT-001 | COMPLETE; USED: feeGroup matching, signed rates, no family echo. |
| Backend API/preview semantics | YES | YES | R2 / gpt-6-sol / medium, explicit | R2-FEE-BACKEND-001 | COMPLETE; USED: current failure branch, test gap, no trade write. |
| Frontend | NO | N/A | N/A | N/A | No API/UI shape change. |

Fan-out Required: YES. Required Reasoning Agents: 2. Actual Reasoning Agents: 2. Fan-out Compliance: PASS. Skip Reason: N/A. Coordinator synthesis: select by the live instrument's group ID, normalize OKX signed rates to nonnegative cost, and retain the existing API/error and no-write contract.

## 4. Dependency Graph and Steps

```text
Approval -> T52 (P01 -> P02 -> P03) -> coordinator audit -> optional user-authorized rollout
```

### P01 — RED fixture and regression

Add a focused preview fixture with documented `feeGroup`, negative signed rates, no echoed `instFamily`, and instrument `groupId`. Capture current structured 502 before implementation. Add independently calculated fee expectation and no-write assertion. Add malformed/ambiguous variants.

### P02 — Fee-group implementation

Make `trade_fee` reject zero/multiple fee data rows. In `_load_market_inputs`, require valid instrument group ID, validate SWAP and optional echoed family, match exactly one fee group, parse bounded finite signed rates, and convert with `max(0, -rate)`. Preserve stale quote 409, no trade writes, API shape, and all unrelated preview math. Never fall back to top-level fee fields.

### P03 — GREEN and integration

Run focused tests; confirm valid documented response and rebate case, malformed branches, no order writes, and unchanged API semantics. Compile backend after final edit and run only the necessary final repository build checks. Audit the diff and test evidence before marking T52 PASS.

## 5. Verification

| ID | Proves | Method |
|---|---|---|
| TEST-001 | RED-001, GREEN-001, AC-001 | `python3.12 -m unittest backend.tests.test_strategy_api -v` with documented response fixture; observe RED before P02 and GREEN after. |
| TEST-002 | GREEN-002/003, AC-002/003 | Same focused suite with wrong/missing/duplicate groups, row count, conflicting family, malformed rates, rebate, no-write assertions. |
| TEST-003 | Task buildability | `python3.12 -m compileall -q backend` after last code/test change. |
| TEST-004 | Final integration | Existing repository backend and web build commands from prior approved strategy plan, only where relevant and available without protected-config inspection. |

Inner-loop: narrow focused tests. Formal checkpoint: RED then GREEN. Task ceiling V2; final integration ceiling V3. Escalate only for a concrete related regression or build failure. Full suite ownership: NOT_REQUIRED unless related failures appear. No external verification is needed for offline acceptance. Production confirmation is a later rollout check and is not assumed from tests.

## 6. Risks, Compatibility, and Rollout

| Risk | Detection | Mitigation |
|---|---|---|
| Existing previews were computed with old fee semantics | Existing stale-preview hash check | Require refreshed preview; do not bypass hash or silently apply old estimate. |
| Exchange adds another fee group or returns ambiguous data | Exact `groupId` and row-count tests | Fail closed with structured 502. |
| Production 502 has another cause | 502 remains after rollout | Collect safe response metadata/error category; do not assume this fix resolves proxy or clock behavior. |

No data migration, performance-sensitive change, or configuration action. Deployment, commit, and push are outside T52 and require the user's specific authorization.

## 7. Task Decomposition and Buildability

| Task | Steps | Requirements/AC | Executor route | Allowed write surface |
|---|---|---|---|---|
| T52 | P01–P03 | REQ-001–003 / AC-001–003 | E1 / gpt-6-luna / xhigh, explicit | `backend/okx.py`, `backend/strategy.py`, `backend/tests/test_strategy_api.py` |

One task is appropriate because response validation, fee selection, and tests share one preview contract and RED/GREEN path. Task buildability: YES; affected unit is Python backend, exact command `python3.12 -m compileall -q backend` after final edit. Task may not pass with a broken intermediate backend.

Completion requires approved scope, T52 PASS, formal RED-before-GREEN, buildability PASS, coordinator diff audit, no protected configuration access/write, and no trade writes.

## 8. Completion Audit

T52 PASS. The executor observed RED-001 before the implementation edit: the documented fee-group regression returned structured 502 (focused test exit 1). GREEN: `rtk test python3.12 -m unittest backend.tests.test_strategy_api -v` passed 31 tests. Task buildability: `python3.12 -m compileall -q backend` passed after the final edit. Coordinator audited the complete three-file product/test diff and confirmed exact group selection, signed fee normalization, malformed-data failure, no trade writes, and no protected-path changes. Final post-edit repository build gates passed: backend compileall and `rtk flutter build web --release`; `git diff --check` passed. The first Flutter build attempt was blocked before compilation by SDK cache permissions; a single approved elevated retry completed successfully. No external configuration action. Production behavior remains unverified until separately authorized deployment and retry.
