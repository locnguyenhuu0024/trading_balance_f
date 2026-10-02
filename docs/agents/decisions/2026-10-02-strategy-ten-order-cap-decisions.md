# Decisions: Ten Orders Per Strategy

Date: 2026-10-02
Status: BLOCKED_ON_CLARIFICATION

| ID | Decision/question | Evidence/status |
|---|---|---|
| D-001 | Maximum10 total buy+sell limit orders per strategy, both batch and sequential. | Explicit user choice in this chat. |
| Q-001 | Oversized historical DRAFT/PREPARED: block new apply and recreate <=10, or allow grandfathered apply? | Asked; pending. |
| Q-002 | Preexisting active queues11–20: finish confirmed tail or stop unsent tail? | Asked; pending. |

Recommended answers are proposals, not authorization. Preserve all existing submitted orders and history; no cancellation/resend/truncation. T61 logging was not cancelled or approved by this policy choice.
