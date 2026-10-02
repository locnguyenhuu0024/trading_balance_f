# Decisions: Strategy Limit Order Submission

Status: ACTIVE
Specification: `docs/agents/specs/2026-10-02-strategy-limit-order-queue-design.md`
Plan: `docs/agents/plans/2026-10-02-strategy-limit-order-queue.md`

## Authorization and decisions

The user requested a sequential queue alternative to OKX batch placement and a top strategy Settings modal whose first item selects the limit submission mechanism. The subsequent instruction authorized the coordinator to decide the details. This authorizes the assumptions below; execution approval remains subject to AGENTS.md section 6 after the current plan is presented.

| ID | Authorized assumption / resolved decision | Impacts |
|---|---|---|
| D-001 | Provide sequential and batch choices; default new account preferences to sequential. Persist this user-facing preference in the account-bound application database. | REQ-001, REQ-002 |
| A-001 | Freeze the selected mechanism at preparation and display it in final confirmation. Subsequent preference changes affect future preparations only. | REQ-003 |
| A-002 | Use the existing supervised backend worker and SQLite durability. Submit every reviewed row sequentially after acknowledgments, independently of fills and browser lifetime. | REQ-004 |
| A-003 | Stop the unsent tail on the first rejection, ambiguity, expired deadline, or failed safety validation. Never automatically retry an uncertain attempted write or resume a stopped tail. | REQ-005, REQ-006 |
| A-004 | Set an enqueue-relative 120-second placement deadline and a minimum 250ms interval between placement requests. Preserve reviewed row ordering, prices, contract sizes, and client IDs. | REQ-004, REQ-006 |
| A-005 | Preserve legacy batch attempts, monitoring, deletion/replacement safety, and zero-position completion. Update API and worker together before creating sequential queues. | REQ-007 |
| A-006 | Use a responsive modal with expandable settings sections, currently one meaningful section, explicit Save/Cancel, safe failure states, and account/session isolation. | REQ-001, REQ-008 |

Open material questions: none. Batch failure is a user-reported hypothesis, not a locally reproduced diagnosis. No live OKX orders are part of local verification.
