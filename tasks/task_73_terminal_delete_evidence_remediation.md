# Task 73 — Strict terminal deletion exchange evidence
Status: PASS
Agent Role: implementation_executor
Executor Class: E1
Target Model: gpt-6-luna
Target Effort: xhigh
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Specification: docs/agents/specs/2026-10-03-strategy-lifecycle-pnl.md
Plan: docs/agents/plans/2026-10-03-strategy-lifecycle-pnl.md
Requirements: REQ-003/005; AC-003/005
Findings: AUD-001, AUD-002, AUD-003
Dispatch Route Status: PENDING

## Preconditions / objective
T71 CLI must be TERMINAL before dispatch; no concurrent writer on backend. Revalidate current source findings first because T71 is still completing. Correct approved fail-closed contract; no architecture invention.

## Findings and concrete remediation
AUD-001: Existing okx.positions filters nondict rows and missing data, so strategy.py hint/delete cannot prove zero exposure using it. Add narrow strategy-only raw helper via existing okx.request GET /api/v5/account/positions params instType SWAP, require dict response with success code and explicit list data, validate every item (instId nonempty string, valid posSide, finite numeric pos). Empty explicit list is valid zero; missing/null/scalar/nonobject/mixed rows are invalid. Use strict helper for terminal hint and actual DELETE. Preserve safe display fallback positionStatus unavailable; never produce terminal canDelete on malformed raw data. Do not modify shared okx client/default consumers.
AUD-002: Terminal submitted batch path accepts not_submitted rows, which are allowed only safely stopped sequential queues in spec. Reject any not_submitted in terminal batch path; preserve original never-sent deletion predicate.
AUD-003: Legacy order_details returns first row from ambiguous multi-row raw data. Add narrow strict terminal-order read using existing okx.request GET /api/v5/trade/order params instId and clOrdId. Require success response, explicit exactly-one dict data row, then existing terminal identity/size/side/fill validation. Missing/null/nonobject/multiple rows must block; no exchange mutation.
If T71 already fixed any finding, retain it without reimplementation; only change remaining defects.

## Allowed Write Surface
- backend/strategy.py
- backend/tests/test_strategy_api.py
Read-only permitted source/test/doc allowlists. No product writes outside these files. No docs/tasks/telemetry/Git writes, no config content or mutation, no external plugins/services or children, no generators/dependencies. RTK first; narrow exact evidence proxy allowed. Return BLOCKED if bounded contract cannot be implemented safely.

## Verification
Formal RED before GREEN after final code: new missing/null/scalar/nonobject/mixed raw positions, ambiguous order responses, submitted batch unsent guard all reject without deletion or exchange writes; hint false/position unavailable where applicable. Existing negative account/revision/live-position guards remain.
Formal GREEN: explicit empty valid positions + exactly-one matching terminal canceled order allows local deletion and dependent cleanup, keeps canReplace false; valid stopped sequential unsent remains supported; original draft/no-placement behavior preserved.
Commands: /opt/homebrew/bin/python3.12 -m unittest backend.tests.test_strategy_api -k <stable new RED/GREEN name>, then full backend.tests.test_strategy_api and relevant existing queue/worker/retry group V3; no full repository suite.
Task Buildability Required: YES
Canonical build: PYTHONPYCACHEPREFIX=/private/tmp/strategy-lifecycle-pycache python3 -m compileall -q backend after last executable change, exit0 required. Native configs opaque only.
Configuration/environment actions: none. External/live verification: none.
Return compact terminal report including exact ordered commands/counts/status, no protected-path mutations, requested/effective route and telemetry envelope. Coordinator owns audit/verdict.

Precondition observed: T71 CLI terminal exit0; no backend writer remains. Awaiting route-compatible E1 child after T72 terminal; no duplicate writer.

Dispatch: existing implementation_executor E1 gpt-6-luna/xhigh explicitly bound; effective unavailable UNVERIFIABLE. Dispatched after T71 terminal, then interrupted on user pause. Implementation/verification UNKNOWN; inspect partial permitted diff before resuming. No PASS.

Resume 2026-10-03: user requested all remaining implementation via executor sub-agent. Fresh native E1 gpt-6-luna/xhigh explicitly dispatched; prior children absent from runtime listing; effective route unavailable UNVERIFIABLE. No duplicate writer.

## Final acceptance
PASS after T73: AUD-001/002/003 resolved; final RED3 then GREEN1+1 PASS, API76 and related44 PASS, compileall exit0 after last code changes. Independent source audit plus coordinator final error-mapping/scope review PASS. See docs/agents/plans/2026-10-03-strategy-lifecycle-pnl-audit.md. Historical pause/interim findings above are superseded by this final result.
