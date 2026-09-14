# Decisions: Isolated Margin Risk Dashboard

Status: ACTIVE
Specification: `docs/agents/specs/2026-09-10-isolated-margin-risk-dashboard-design.md`
Plan: `docs/agents/plans/2026-09-10-isolated-margin-risk-dashboard.md`

## User Decisions

### D-001 — Full scope
Implement the complete 36-section user brief, including market analysis, local action plans/zones, stress tests, history, change detection, daily summaries, risk trend/velocity, and event-based notifications.

### D-002 — Data and service authorization
Use the existing OKX integration. The user explicitly permits consulting official OKX API documentation. Display "-" for unavailable API data; do not substitute demo values or zero. No other external service is authorized.

### D-003 — Buffer baseline
Accepted boundaries: NORMAL >45%; WATCH 30% through 45%; HIGH 20% up to 30%; CRITICAL <20%. Thresholds must remain configurable.

### D-004 — Overall state
Header displays Overall Risk. Position WATCH plus Market HIGH results in Overall HIGH; show component states separately. Favorable market conditions never lower position/hard-rule floors.

### D-005 — Empty state and local persistence
Display an empty state without eligible positions. Persist action plans and history locally on the device.

## Clarification Questions

### Q-001 — Authorization of remaining configurable heuristics
Status: ANSWERED
Question: May the coordinator define and present configurable v1 defaults for leverage/margin hard rules, market/recovery classifications, volatility estimator, trend/velocity windows, event materiality/anti-spam, history retention, and daily-summary timing, for approval with the implementation plan?
Why it matters: The brief supplies conceptual examples rather than a complete deterministic algorithm. D-003 approves buffer thresholds but does not uniquely define the other algorithms. Executors must not invent financial/product semantics.
Repository evidence: Existing portfolio consumes account balance; existing position DTO omits position debt, interest, margin ratio, and equity fields. Market provider supplies ticker prices only. Background service currently polls account balances.
Proposed approach: Treat these classifications as transparent configurable application heuristics, not exchange-provided ratings. Preserve "-" for missing inputs and disclose partial/stale analysis; never fabricate NORMAL from absent data. Keep position/hard rules as the final-state floor. Present exact defaults and verification examples in the canonical specification before implementation approval.

## User-Authorized Assumptions

### A-001 — Coordinator may propose the remaining defaults
Source: User replied "tôi đồng ý" to Q-001 on 2026-09-10.
Authorization: Define configurable v1 defaults for missing risk heuristics, event rules, storage retention and summary timing; present their exact contract for approval with the implementation plan.
Impacts: REQ-001 through REQ-011; P01 through P05; T18 through T22.
Proposal: Specification sections 6–16 and 21 are canonical. Defaults include leverage 3/4/6x, ratio 300/150/110%, 24 hourly-return realized volatility, confirmed 4H structure, 4H OI comparison, max-severity aggregation, 1h trend/6h velocity, hysteresis, 08:00 local summaries and bounded retention. Multiple-position selection remembers the last eligible episode. Platform monitoring limitations and strict unknown-cost behavior are stated explicitly for plan approval.
Important: Permission to propose these choices is not a claim that they are exchange-defined or clinically/statistically calibrated.

## Execution Authorization

The canonical plan and T18–T22 checklist are ready for presentation. Implementation remains unauthorized until the user explicitly approves execution after presentation, under repository AGENTS.md section 6. No product code, tests, dependencies or runtime configuration changed during planning.

### D-006 — Execution approval
User: "duyệt, bắt đầu đi" after plan/checklist presentation. All canonical P01–P05/T18–T22 defaults and scope approved. Execution authorized; Git mutations/deployment remain unauthorized.
