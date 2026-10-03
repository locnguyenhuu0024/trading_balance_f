# Decisions: Limit Cap and Explicit Resubmission

Status: ACTIVE
Date: 2026-10-03
Specification: docs/agents/specs/2026-10-03-strategy-limit-cap-resubmission-design.md
Plan: docs/agents/plans/2026-10-03-strategy-limit-cap-resubmission.md

## User decisions

- D-001: Maximum10 total buy+sell orders for any new strategy submission, both batch and sequential. Previously explicitly selected.
- D-002: Historical DRAFT/PREPARED with more than10 orders cannot newly apply; recreate a compliant strategy. Explicit response on2026-10-03.
- D-003: Already APPLYING legacy queues may finish their confirmed11–20 row list. Explicit instruction and response on2026-10-03.
- D-004: Add explicit resubmission of truly not-submitted and definitely rejected orders only, following fresh review and confirmation. Accepted or uncertain outcomes are excluded. Explicit response on2026-10-03.

## Authorized coordinator decisions

A-001: User said the coordinator should decide implementation/product choices. Adopted contract: new linked strategy attempt, exact source price/quantity/leverage, fresh child client IDs, preserve source history, current account preference frozen at prepare, explicit subset1..10, no automatic retry/cancellation. Existing positions/pending/reservation preflight remains authoritative; live siblings can block resubmission until the instrument safely admits another strategy.

A-002: Duplicate prevention uses idempotent child-draft creation and durable direct-source consumption after a child claim. Claimed retry children and referenced sources cannot be deleted/replaced through never-sent cleanup. Another retry originates from the newest child. An unclaimed retry draft can be explicitly deleted through existing safe eligibility to release selection locks.

Repository evidence and independently analyzed tradeoffs support these coordinator choices; they are not executor decisions. Open material questions: NONE. Execution authorization after presentation of this revised plan: PENDING under AGENTS.md §6.

## Planning synthesis

R3 backend analysis established fixed-order math, JSON lineage and atomic guards; R2 frontend analysis established server-owned eligibility, two-step selection/review and session/once-only boundaries. A focused R3 follow-up verified claimed-child permanence and identified ordinary replacement races; the contract blocks sources with any persisted ordinary replacement child and applies symmetric source dependency guards to replacement creation/claim/cleanup.
