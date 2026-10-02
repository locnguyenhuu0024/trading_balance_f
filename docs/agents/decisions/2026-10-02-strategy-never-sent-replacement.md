# Decisions: Never-Sent Strategy Replacement

Status: ACTIVE
Specification: `docs/agents/specs/2026-10-02-strategy-never-sent-replacement.md`
Plan: `docs/agents/plans/2026-10-02-strategy-never-sent-replacement.md`

## User decisions

| ID | Decision | Affected requirements |
|---|---|---|
| D-001 | Delete only when the server can prove no order batch was sent. | REQ-001, REQ-004 |
| D-002 | Replacement requires a fresh order-list review and manual confirmation. | REQ-003 |
| D-003 | Fetch current candles and let the user choose new Long/Short levels. | REQ-003 |
| D-004 | Delete the old strategy automatically only after OKX accepts every new order. | REQ-004 |

Source: user answers in the 2026-10-02 production incident conversation. No configuration values or credentials were requested.

## Coordinator interface resolution

| ID | Decision | Affected requirements |
|---|---|---|
| D-005 | Project eligible legacy `COMPLETED` as public `PARTIAL` with `leverage_rejected` or `never_sent` reason; expose `replacementCleanupConflict` for the accepted-batch cleanup warning. | REQ-002, REQ-004 |
