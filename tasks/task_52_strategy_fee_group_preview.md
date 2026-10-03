# Task 52 — Read applicable OKX fee group in strategy preview

Status: PASS
Agent Role: implementation_executor
Executor Class: E1
Target Model: gpt-6-luna
Target Effort: xhigh
Target Route: gpt-6-luna / xhigh
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Dispatch Route Status: UNVERIFIABLE (model and effort explicitly bound; effective route not exposed)
Specification: `docs/agents/specs/2026-10-02-strategy-fee-group-preview.md`
Plan: `docs/agents/plans/2026-10-02-strategy-fee-group-preview.md`, P01–P03
Requirements: REQ-001–003; Acceptance: AC-001–003

## Objective and scope

Make preview accept the applicable documented OKX SWAP `feeGroup`, normalize signed commission/rebate rates, and fail closed on missing or ambiguous fee data. Allowed writes: `backend/okx.py`, `backend/strategy.py`, `backend/tests/test_strategy_api.py` only. Do not read or write protected configuration, change frontend/API schema/auth/order execution, place live orders, deploy, commit, or push.

Predecessor: current plan explicitly authorized. Bind `implementation_executor`, `gpt-6-luna`, and `xhigh` in the spawn call; inherited/default routing is forbidden. If effective route mismatches, stop mutation. If the current OKX response contract contradicts the approved spec or scope is insufficient, return BLOCKED for coordinator replanning.

## Executor contract

1. P01: add documented-format fee fixture and regression. Record the current RED result before production code changes.
2. P02: require exactly one fee data row, exact matching instrument/fee `groupId`, valid signed rates, and nonnegative cost via `max(0, -rate)`. Optional echoed family may be absent; explicit conflict fails. No legacy top-level fallback.
3. P03: run GREEN and focused malformed/rebate/no-write cases; preserve quote-stale 409 and existing preview API shape.

RED-001: documented feeGroup response currently returns 502; command `python3.12 -m unittest backend.tests.test_strategy_api -v` (or narrower single test). GREEN-001: same response previews with expected cost and no trade write. GREEN-002/003: malformed/ambiguous/conflicting fees fail closed, rebate is zero cost. Verification ceiling V2; widen only for concrete related regression.

Task buildability gate: YES; affected unit `backend`; execute `python3.12 -m compileall -q backend` after final source/test edit and record exit status. No external configuration or verification action. Return compact file/diff summary, RED/GREEN evidence, build result, route status, and any residual risk for coordinator audit.

## Coordinator audit

Scope: PASS — only the three allowed backend source/test files changed. Acceptance: PASS — applicable group selected, signed fees normalized, malformed/ambiguous responses fail closed. RED-before-GREEN: PASS — documented response first returned structured 502 (focused test exit 1), then the 31-test backend suite passed after the fix. No-write safety: PASS — preview regression assertions observe zero trade writes. Buildability: PASS — `python3.12 -m compileall -q backend` exit 0 after final task edit. Route compliance: UNVERIFIABLE — explicit E1 `gpt-6-luna` / `xhigh` binding; runtime exposed no effective route. Final integration: PASS — backend compileall, `rtk flutter build web --release`, and `git diff --check` exit 0. Protected configuration paths: unchanged. External configuration actions: none. Verdict: PASS. Production 502 recovery awaits deployment and safe retry.
