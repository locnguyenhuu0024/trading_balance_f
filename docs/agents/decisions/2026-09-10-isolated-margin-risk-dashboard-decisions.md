# Decisions: Isolated Margin Risk Dashboard

Status: ACTIVE
Specification: Pending clarification
Plan: Pending clarification

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
Status: OPEN
Question: May the coordinator define and present configurable v1 defaults for leverage/margin hard rules, market/recovery classifications, volatility estimator, trend/velocity windows, event materiality/anti-spam, history retention, and daily-summary timing, for approval with the implementation plan?
Why it matters: The brief supplies conceptual examples rather than a complete deterministic algorithm. D-003 approves buffer thresholds but does not uniquely define the other algorithms. Executors must not invent financial/product semantics.
Repository evidence: Existing portfolio consumes account balance; existing position DTO omits position debt, interest, margin ratio, and equity fields. Market provider supplies ticker prices only. Background service currently polls account balances.
Proposed approach: Treat these classifications as transparent configurable application heuristics, not exchange-provided ratings. Preserve "-" for missing inputs and disclose partial/stale analysis; never fabricate NORMAL from absent data. Keep position/hard rules as the final-state floor. Present exact defaults and verification examples in the canonical specification before implementation approval.

## Execution Authorization

No implementation plan/checklist has yet been presented. Implementation remains unauthorized under repository AGENTS.md section 6. Current user response resolves scope/data decisions; it does not bypass that gate.
