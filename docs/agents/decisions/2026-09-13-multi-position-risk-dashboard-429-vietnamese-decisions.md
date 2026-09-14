# Decisions: Multi-position Risk Dashboard, 429 resilience, and Vietnamese UI

Status: ACTIVE
Specification: `docs/agents/specs/2026-09-13-multi-position-risk-dashboard-429-vietnamese-design.md`
Plan: `docs/agents/plans/2026-09-13-multi-position-risk-dashboard-429-vietnamese.md`

## Clarification Questions

### Q-001 — Position coverage model
Status: ANSWERED
Question: Should the dashboard inspect only one selected eligible position, monitor every eligible isolated-margin position simultaneously, or include all wallet coins?
Why it matters: simultaneous monitoring changes repository batching, monitor state, persistence/event ownership, API load, and UI structure.
Repository evidence: `RiskRepository.loadPosition`, `RiskPositionSelection.candidates`, `RiskMonitor._positionSelection`, `RiskMonitorViewState`
Possible interpretations:
- A: one selected eligible position at a time; smallest change but alerts remain selection-scoped.
- B: all open eligible isolated-margin positions are monitored and alerted simultaneously.
- C: all wallet coins, including spot balances without position-risk inputs.

### Q-002 — Compact presentation
Status: ANSWERED
Question: How should simultaneous position detail remain compact?
Why it matters: rendering all full dashboards at once is dense and expensive.
Repository evidence: `risk_dashboard_screen.dart` currently renders one complete position dashboard.
Possible interpretations:
- A: one collapsible section per open isolated-margin position.
- B: one global selector showing only one position detail.

### Q-003 — Localization order and scope
Status: ANSWERED
Question: When and how broadly should Risk Dashboard text be translated?
Why it matters: dashboard widgets, dynamic reasons, history, validation, accessibility, and notifications currently expose English from multiple layers.
Repository evidence: Risk presentation widgets plus domain/application error/event text.
Possible interpretations:
- A: translate headings only.
- B: after 429 and multi-position behavior pass, translate every user-visible Risk Dashboard surface while preserving technical identifiers and user-authored text.

### Q-004 — Supported isolated-margin directions and currencies
Status: OPEN
Question: Does “all open isolated-margin positions” mean only positions supported by the current risk formulas (long isolated MARGIN with USDT quote/debt), or must short and other-quote isolated positions also receive full risk evaluation and alerts?
Why it matters: short/other-quote positions require new accounting, liquidation, leverage, stress, debt, and alert semantics rather than a monitoring/UI-only extension.
Repository evidence: `docs/agents/specs/2026-09-10-isolated-margin-risk-dashboard-design.md` §3/§6.1; `RiskPosition.isEligible`; `RiskRepository.loadPosition`
Possible interpretations:
- A: monitor all currently supported long isolated MARGIN/USDT positions; unsupported rows stay outside active evaluation.
- B: add full short and/or non-USDT isolated-margin financial semantics in this workflow.

## User Decisions

### D-001 — Monitor all eligible open isolated-margin positions
Source question: Q-001
Decision: Simultaneously evaluate, persist, and alert every currently open isolated-margin position within the eligibility breadth resolved by Q-004; spot-only wallet coins remain out of scope.
Impacts: REQ-001, REQ-002, REQ-003, AC-001 through AC-006, P01, P02, T24, T25

### D-002 — Collapsible per-position sections
Source question: Q-002
Decision: Display each open eligible isolated-margin position as a compact collapsible section that expands on user action.
Impacts: REQ-004, AC-007 through AC-009, P03, T26

### D-003 — Complete Vietnamese Risk Dashboard after functional work
Source question: Q-003
Decision: After the 429 and multi-position changes pass, translate all rendered user-visible Risk Dashboard text, including sheets, dialogs, validation, dynamic states/reasons, history, and accessibility. Preserve coin/instrument names, units, protocol/storage identifiers, source names, and user-authored content. OS notification localization is not included without a separate request.
Impacts: REQ-005, AC-010 through AC-012, P04, T27

## User-Authorized Assumptions

N/A.

## Change Log

| Revision | Change | Reason |
|---|---|---|
| 1 | Recorded simultaneous monitoring, collapsible presentation, and post-functional Vietnamese localization. | User clarification on 2026-09-13. |
