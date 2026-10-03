# Decisions: Ten Orders Per Strategy

Date: 2026-10-03
Status: ACTIVE

| ID | Decision/question | Evidence/status |
|---|---|---|
| D-001 | Maximum10 total buy+sell limit orders per strategy, both batch and sequential. | Explicit user choice in this chat. |
| Q-001 | Oversized historical DRAFT/PREPARED policy. | ANSWERED: block new apply; recreate with at most10. Explicit user choice on2026-10-03. |
| Q-002 | Preexisting active queues11–20 policy. | ANSWERED: finish the confirmed tail. Explicit user choice on2026-10-03. |

Preserve existing submitted orders and history; no cancellation/resend/truncation from the cap. User subsequently requested selective limit-order resubmission and authorized coordinator decisions. A combined revised plan is being prepared; no implementation under the revised scope has started. T61 is already implemented, audited, committed and pushed separately.
