# Decisions: Strategy preflight
Status: COMPLETE
D-001: User explicitly authorizes autonomous decisions and execution after planning. No new approval needed for bounded fixes/remediation.
D-002: Preserve existing availBal semantics; no repository evidence supports account-mode availEq substitution. Missing data is an availability error, never proof of insufficient money.
D-003: Use explicit operation-local identity propagation. Independent requests, execution phases and post-leverage checks remain fresh. No global/TTL identity cache.
D-004: Return explicit upstream HTTP 429 with conservative application retry guidance; do not retry trade writes or add automatic retries.
Open questions: none for bounded source fix. Gunicorn configuration remediation is excluded.
