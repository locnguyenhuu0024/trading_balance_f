# Design Specification: OKX Fee Group Strategy Preview

Status: READY_FOR_PLAN
Date: 2026-10-02
Tier: L
Decision Ledger: N/A — the exchange schema and existing user-approved margin semantics determine the contract.

## 1. Objective

Make strategy preview use the applicable current OKX SWAP fee group. A valid fee response must not produce a 502, and preview must remain read-only. This corrects a reproduced 502 branch; it does not assert that the production 502 has the same cause until deployed evidence confirms it.

## 2. Current State and Evidence

| ID | Evidence | Observation |
|---|---|---|
| OBS-001 | `backend/strategy.py`, `_load_market_inputs` | Preview calls OKX account config, SWAP instruments, ticker, trade fee, and isolated position tiers. It requires deprecated top-level `maker`/`taker`, rejects negative `taker`, and requires `fee.instFamily`. |
| OBS-002 | `backend/okx.py`, `trade_fee` | The request pins `instType=SWAP` and `instFamily`, but the response handler takes the first data row without validating row count. |
| OBS-003 | `backend/tests/test_strategy_api.py` | Existing fake fee data only exercises legacy top-level positive rates and an echoed `instFamily`. |
| OBS-004 | Official OKX fee-rate and instrument documentation | Current fee groups have `groupId`, `maker`, and `taker`; signed negative rates are commission, positive rates are rebate. The fee response need not echo the requested family. |
| OBS-005 | User-run public OKX probes on the Docker host | SWAP instruments and SOL-USDT-SWAP ticker both returned HTTP 200. A separate public-time probe returned 403, which does not establish clock skew. |
| REP-001 | Offline fake OKX preview with a documented `feeGroup` and negative rates | Preview returned `502 preview_inputs_unavailable`, with zero trade writes. |

Sources: [OKX fee rates](https://app.okx.com/docs-v5/en/#rest-api-account-get-fee-rates), [OKX instruments](https://app.okx.com/docs-v5/en/#rest-api-account-get-instruments), [OKX fee guide](https://www.okx.com/en-us/help/how-to-calculate-the-contract-transaction-fee).

Hypothesis HYP-001: the production 502 is this fee-validation branch. Status: UNCONFIRMED; production response body was unavailable. The defect itself is confirmed by REP-001.

## 3. Scope and Decisions

In scope: backend fee response validation, the strategy fee-cost calculation, and offline tests. Out of scope: frontend, order execution, authentication, deployment, server clock/configuration, and proxy settings. No open product decision or external configuration action.

The existing user decision remains: entered USDT is real margin before leverage; fees are additional. A rebate may reduce exchange charges, but preview must not count a rebate as extra available margin.

## 4. Requirements

### REQ-001 — Select the applicable fee group

For the selected live SWAP instrument, require a nonempty instrument `groupId`. Validate one and only one OKX fee data row for the pinned SWAP/family request, then select exactly one `feeGroup` entry with matching `groupId`. Accept absent echoed `instFamily`; reject a present conflicting family. Reject absent, duplicate, malformed, or mismatched groups with the existing structured `502 preview_inputs_unavailable`. Do not silently use deprecated top-level rates or a different group.

### REQ-002 — Apply OKX signed-fee semantics

Parse the selected group's finite Decimal `maker` and `taker` rates with absolute value below 1. Convert each signed rate to a nonnegative cost rate as `max(0, -signed_rate)`. Continue to use taker cost for estimated opening/liquidation fees and keep the entered margin budget exclusive of fees. A positive rebate contributes zero cost, not extra margin.

### REQ-003 — Preserve safe preview behavior

The fee change must not alter wizard inputs, API success shape, authentication, live-order methods, or any trade writes. A malformed OKX fee response must fail closed with structured 502. Existing stale quote behavior remains 409.

## 5. Data Contract

| Field | Type | Meaning | Invalid behavior |
|---|---|---|---|
| Instrument `groupId` | nonempty string | Applicable fee group | Structured 502 |
| Fee `feeGroup[].groupId` | nonempty string | Exact group identity | Missing/duplicate match: structured 502 |
| Matching `maker`, `taker` | finite Decimal string | OKX signed rates | Missing/nonfinite/abs >= 1: structured 502 |
| Internal fee cost | Decimal | `max(0, -signed_rate)` | Never negative |

Example: instrument group `2`, matching taker `-0.0005` produces a 0.0005 taker cost; an unrelated group with taker `-0.001` must not be selected. A matching taker `0.0001` rebate produces zero estimated cost. Two matching group `2` rows fail as ambiguous.

## 6. Design, Invariants, and Failure Semantics

Flow: fetch existing OKX inputs -> locate selected instrument -> validate group identity -> validate exact fee row and matching group -> normalize signed rates -> run existing preview math -> return existing preview shape. No new external request, order write, persistence write, or API field.

- INV-001: Never infer a fee from a different instrument group or deprecated top-level fields.
- INV-002: Estimated fee cost is nonnegative and does not increase available margin.
- INV-003: Preview performs no trade write, including failure paths.
- EDGE-001: A response without echoed family is valid when the request is family-pinned; an explicit conflict fails.
- EDGE-002: Missing/duplicate groups, multiple fee data rows, and malformed signed rates fail closed.
- EDGE-003: Legacy stored preview hashes may differ after fee correction; applying such a draft must still use the existing stale-preview protection and require a refreshed preview.

## 7. RED / GREEN and Acceptance

- RED-001: Given a documented `feeGroup` with negative rates and no echoed family, the current code returns 502. This is the pre-change failure to capture in a regression test.
- GREEN-001 / AC-001: The same response previews successfully, selecting the instrument's group, computing expected fee costs, and writing no orders.
- GREEN-002 / AC-002: A different group, missing/duplicate matching group, multiple fee data rows, conflicting echoed family, or malformed rates returns structured 502 with no order writes.
- GREEN-003 / AC-003: A positive rebate contributes zero fee cost; margin and existing preview API behavior stay unchanged.

Verification: offline fake OKX client and focused backend API tests, then backend buildability and final repository integration gates. Deployment and production validation require separate authorization. If production 502 persists, collect only safe HTTP status/response-size/error category evidence before widening scope.

## 8. Rollout and Security

No migration or configuration change. Roll out by rebuilding/recreating the backend container under the user's deployment process after code approval and verification. Roll back the code change if preview calculations regress. No credentials, protected configuration, or live orders are needed to test.

Traceability: REQ-001 -> AC-001/002 -> RED-001/GREEN-001/002; REQ-002 -> AC-001/003 -> GREEN-001/003; REQ-003 -> AC-001/002/003 -> all scenarios.
