# Design Specification: Account JEV Screening Settings
Status: READY_FOR_PLAN
Date: 2026-10-06
Tier: L
Decision Ledger: docs/agents/decisions/2026-10-06-jev-screening-settings-decisions.md

## Objective and observed evidence
Make JEV recommendation screening adjustable in the Strategy page Settings. Current strategy.py settings persist only submission mode in account preferences; strategy_automatic.py uses fixed 4/.6/.4 thresholds. Settings UI/controller/API are mode-only; strategy_draft_entries.dart and wizard reject custom recorded thresholds. Two independent read-only planning workstreams have completed and been reconciled. Protected configuration was not accessed.

## Scope, decisions and requirements
D-001 authorizes planning followed immediately by implementation, with coordinator-selected details. A-001 chooses account scope, defaults4/60%/40%, inclusive bounds, only new generations affected. No open questions.
REQ-001: Authenticated account settings persist submission mode plus three JEV thresholds, with backward-compatible partial group writes and atomic validation/persistence.
REQ-002: Every new automatic generation captures account thresholds once after saved request replay detection, before market/provider work. Recommendation records effective values and uses them inclusively. Existing replay/materialization preserves saved snapshots.
REQ-003: Strategy Settings exposes quality0..5 and two percentage inputs0..100, defaults4/60/40, local reset, validated atomic Save, load/error/retry/cancel and session safety.
REQ-004: Frontend saved recommendation readers accept valid custom recorded thresholds, retain recorded IDs/order, and never consult current settings.

## Data and API contract
GET /v1/strategies/settings and successful POST return the complete effective object:
```
{"limitOrderSubmissionMode":"sequential","jevScreeningThresholds":{"minStructuralQuality":4,"minEntrySuitabilityProbability":0.6,"maxFailureRiskProbability":0.4}}
```
POST supplies mode, threshold group, or both. Missing group preserves existing/default values. Supplied threshold object requires exactly the three keys. Quality is a JSON integer0..5 excluding bool; probabilities JSON finite numbers0..1 excluding bool/strings. Null/partial/extra-key threshold objects and no-recognized-field requests reject. Unknown top-level keys reject with invalid_strategy_settings. Invalid explicit mode preserves invalid_submission_mode; invalid thresholds use invalid_jev_screening_thresholds. Validate whole request before account write; return400 for invalid requests. Corrupt stored settings return500 strategy_settings_unavailable, never assumed defaults. Defaults apply only missing preference rows/newly migrated columns.
Grain: one preference per authenticated account fingerprint. Add source-owned SQL columns jev_min_structural_quality INTEGER NOT NULL DEFAULT4, jev_min_entry_suitability_probability REAL NOT NULL DEFAULT0.6, jev_max_failure_risk_probability REAL NOT NULL DEFAULT0.4. Existing table upgrades add missing columns transactionally after BEGIN IMMEDIATE and re-reading metadata, preserving mode/account/time. Repeated/concurrent initialization safe. No external configuration actions.
Mode-only GET/save client methods remain available and send only mode on POST. Full typed capability uses existing endpoint and verifies complete exact save acknowledgement. Optional separate StrategySettingsApi avoids forcing legacy StrategyApi consumers to implement full settings; legacy capability remains mode-only, JEV unavailable and disabled rather than falsely persisted. Realclient full GET requires complete validated settings.

## Control flow and invariants
INV-001: account fingerprint comes from authenticated service identity; no client account override. Account switch results ignored before adoption.
INV-002: submitted groups read/merged/upserted within one BEGIN IMMEDIATE transaction; mode-only calls cannot reset JEV and threshold-only calls cannot reset mode. Submission execution continues reading mode alone, so corrupt JEV does not alter order execution semantics.
INV-003: max5 recommendations per side, ranking, positive price, valid ID/rank, success-only assessments and all raw candidates remain unchanged. Model/provider/prompts/enabling remain unchanged.
INV-004: capture preferences after idempotency lookup; current in-flight snapshot uses captured copy even if settings change; next request uses new values. Duplicate persistence replay returns saved snapshot.
INV-005: controller retains load coalescing, duplicate-save prevention and session checks. Avoid GET/save overlap: no new GET while save active, no save while GET pending; a generation/version guard rejects stale same-session load completions. Existing mode wrappers preserve compatibility.
INV-006: UI drafts do not overwrite dirty local edits on notification/retry; initialize only successful authoritative load. Failed save and ACK mismatch preserve drafts; Cancel never writes. Full Save requires loaded/valid settings and no outstanding operation. Legacy mode-only save remains supported. Reset edits only local JEV values.
INV-007: snapshots validate threshold numeric finite range, quality integer-valued0..5 (legacy4.0 acceptable); version v1 and max5 remain. Saved IDs/order remain authoritative; no re-filter/re-rank or added selection defaults. Invalid recommendations reject atomically.

## UX and edge/failure semantics
Add expanded JEV section in scrollable Settings; Vietnamese labels for minimum structural quality, minimum entry suitability (%) and maximum failure risk (%). Quality dropdown0..5; decimal percentages allowed including comma decimal separator; finite0..100, no empty/nonnumeric/negative/>100. Typed domain holds probability values, converts only at UI/wire boundaries without integer rounding. Explain changes apply to newly generated drafts, fixed maximum5 per side and successful assessment prerequisite. Reset-to-defaults button marks local draft dirty, no network. Disable input during load/save/account mismatch. Load failure offers Retry without assumed JEV defaults. Signed-out message covers Strategy settings. 320px/enlarged text must scroll without overflow. Save acknowledgement must match all submitted fields, not only mode.
Failure table: invalid payload->400 no writes; persistence error->existing safe API error no partial writes; corrupt preference->500 no new generation; failed provider->existing unselected candidate behavior; stale session->no state adoption; failed frontend save->no success acknowledgement and edits retained.
Worked selection: quality3, suitability.55,risk.45 qualifies with3/.5/.5 but not4/.6/.4; equality qualifies. Non-success never qualifies even0/0/1. Five cap still holds. Preferences affect selection, not provider scoring.

## Compatibility, security, rollout and rollback
Additive response fields keep legacy mode callers compatible. Legacy SQL inserts use defaults. Old snapshot defaults and missing-recommendation legacy handling remain valid; custom snapshots use recorded values. No credentials/provider configuration access, dependency changes or external service calls. Deploy backend API first then frontend; restart backend against existing SQLite to apply additive migration. Rollback previous code ignores extra SQL fields, saved custom thresholds require new frontend reader; avoid rolling frontend back while such drafts remain visible. Commit/push uses the prior explicit user authorization for this repository; deployment is outside this request.

## Acceptance and traceability
AC-001 / REQ-001 / P01 / T88: defaults, custom and boundary roundtrip, account isolation, old mode-only POST preservation, threshold-only preservation, invalid combined write atomicity, corrupt values refusal, additive repeat/concurrent migration retains original row data.
AC-002 / REQ-002 / P01 / T88: independent worked selection, inclusive bounds, max5, failed exclusion, captured settings during provider change, saved replay/materialization immutability.
AC-003 / REQ-003 / P02 / T89: visible default/custom fields, percentage conversion/validation, reset/cancel/reopen, load and save failure, exact ACK, duplicate/save/load/account race protection, narrow enlarged layout.
AC-004 / REQ-004 / P02 / T89: valid custom thresholds accepted in domain and wizard, invalid threshold metadata rejected, legacy snapshots preserved, IDs/order unchanged.
RED-001: malformed/partial/boolean/out-of-range combined preference request cannot change either group. GREEN-001: custom prefs filter new generation and remain frozen across changes/replays.
RED-002: invalid UI values cannot send save; failed or mismatched save never shows success and retains edits. GREEN-002: save custom settings, reopen/load exact values and open custom immutable draft.
Baseline regression failure is desirable before implementation; formal final checkpoint runs defined negative RED scenario first, then positive GREEN. No performance-sensitive behavior beyond one account preference read/new generation.
Completion requires all AC, audited diff, formal RED before GREEN, task buildability and successful final Python/web/macOS builds. External configuration/environment actions: none.

## Completion evidence
REQ-001..004 and AC-001..004 complete; task and final canonical build gates PASS. See final audit for exact verification evidence and rollout.
