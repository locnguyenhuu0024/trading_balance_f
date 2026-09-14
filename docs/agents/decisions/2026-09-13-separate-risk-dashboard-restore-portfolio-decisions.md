# Decisions: Separate Risk Dashboard and Restore Portfolio

Status: ACTIVE
Specification: `docs/agents/specs/2026-09-13-separate-risk-dashboard-restore-portfolio-design.md`
Plan: `docs/agents/plans/2026-09-13-separate-risk-dashboard-restore-portfolio.md`

## Clarification Questions

### Q-001 — Primary destination ownership

Status: ANSWERED
Question: Should Risk Dashboard become the sixth primary navigation destination while destination zero restores the Portfolio screen that existed immediately before commit `cdf01ff`?
Why it matters: This determines navigation ordering, the screen split boundary, and which behavior owns the application home.
Repository evidence: `lib/core/navigation/main_navigation_shell.dart`, `lib/core/navigation/navigation_destination_data.dart`, `lib/features/portfolio/presentation/portfolio_screen.dart`, commit `a028c632f3d7b4d0802af4d3566d7a731112eabb`
Possible interpretations:
- A: Keep Risk Dashboard as destination zero and expose Portfolio elsewhere.
- B: Restore Portfolio as destination zero and add Risk Dashboard as destination five (the sixth item).

## User Decisions

### D-001 — Restore Portfolio home and add sixth Risk destination

Source question: Q-001
Decision: The user selected interpretation B. Destination zero is the pre-`cdf01ff` Portfolio screen, and Risk Dashboard is a separate sixth primary navigation destination.
Impacts: REQ-001, REQ-002, REQ-003, AC-001 through AC-005, P01 through P03, T23

## Authorized Assumptions

N/A — no material assumption is left to implementation.

## Change Log

| Revision | Change | Reason |
|---|---|---|
| 1 | Recorded D-001. | User answered Q-001 on 2026-09-13. |
