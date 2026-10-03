# Decisions: Strategy lifecycle deletion and PnL
Status: COMPLETE
Specification: docs/agents/specs/2026-10-03-strategy-lifecycle-pnl.md
Plan: docs/agents/plans/2026-10-03-strategy-lifecycle-pnl.md

## Clarification Questions
None open; user delegated product choices and authorized execution after plan.

## User Decisions
D01: Execution after finalized plan is authorized for this follow-up. Existing planner/executor/auditor separation remains mandatory. Impacts T71/T72.

## User-Authorized Assumptions
A01: Strategy deletion is local cleanup only after verified terminal orders and no instrument exposure/active executor/lineage dependency. Existing never-sent replacement remains separate. Impacts REQ-003/005, T71/T72.
A02: Near-zero means abs(value)<0.005 before 2-decimal USDT/percentage formatting; exact boundary retains sign color. Dedicated PnL colors preserve the wider neutral theme and hidden-value privacy. Impacts REQ-004/T72.
A03: All-canceled summary can display Đã hủy without changing persisted execution status. Otherwise current Vietnamese status/never-sent labels apply. Impacts REQ-002/T72.
A04: Continue current feature branch; follow-up has no request to commit/push or deploy. No configuration changes required.
