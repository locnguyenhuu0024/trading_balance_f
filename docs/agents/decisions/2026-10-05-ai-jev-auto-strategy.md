# Jev Integration Decisions

User authorized the coordinator to propose and answer questions and execute tasks after planning, for this session only.

- D-001: Interpret khung giờ as candle timeframe H6/D1/W1. Preserve the existing manual 12H option separately.
- D-002: Introduce candidate-stage DRAFT in the existing table, because coin/timeframe cannot safely imply margin/leverage/orders. Materialize the same record only after manual selection and valid preview; avoid replacement lineage semantics.
- D-003: Use the Strategy calculator contract (500 candles, exact decimals), not the watchlist calculator (300 candles, truncated lists). Acquire selected interval and H6/D1/W1 context without adding external feeds.
- D-004: Persist every raw generated level; success-first independent ranking with deterministic tie-breaks; no default selection or recommendation.
- D-005: Use sync official SDK matching WSGI, lazy imports, bounded workers/timeouts/deadline, no live test calls. Deadline misses explicitly fail enrichment only.
- D-006: Keep configuration external and user-owned. Document process-environment setup rather than invent/edit protected file locations. New adapter may consume environment as normal runtime input; agents do not inspect actual values.
- D-007: Create feat/ai-jev-auto-strategy; no commit, push, deploy or live Jev call authorized by this implementation task.

Planning frontend/backend results adopted and reconciled: R2-JEV-FE-001, R2-JEV-BE-001. Model/effort explicitly requested; effective routes unavailable. Runtime has no child close/release primitive, so terminal reports are collected and no guessed cleanup operation is used.

- D-008: Independent audit requires session revalidation after enrichment, stage-aware idempotent replay, guarded deletion of candidate-stage drafts, and rejection of late provider successes. The 12-second budget bounds admission/acceptance; workers must drain and close, so SDK timeout/cleanup scheduling can extend response wall time. No abandoned background provider calls.
- Inspection deviation: one coordinator search over mixed backend/service.py included a protected configuration region. The diagnostic branch stopped immediately; that content was not used or propagated. Subsequent inspection is restricted to explicitly identified business dispatch/session methods. No protected file mutation occurred.
