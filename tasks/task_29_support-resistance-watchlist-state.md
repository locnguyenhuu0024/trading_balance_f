# Task 29 — Persisted support/resistance watchlist state

Status: PASS
Agent Role: implementation_executor
Executor Class: E1
Target Model: gpt-6-luna
Target Effort: xhigh
Target Route: gpt-6-luna / xhigh
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Dispatch Route Status: UNVERIFIABLE (explicit model/effort bound; effective route unavailable)
Specification: `docs/agents/specs/2026-09-29-support-resistance-watchlist-design.md`
Plan: `docs/agents/plans/2026-09-29-support-resistance-watchlist.md`
Plan Steps: P02
Requirements: REQ-001, REQ-002
Acceptance Criteria: AC-001

## Objective and dependency

Persist separate ordered Spot/Perpetual watchlists, active mode, and timeframe. Predecessor: T28 PASS; run serially to avoid shared Flutter build-state collision. User authorized T29 on 2026-09-30. T30 remains on hold.

## Allowed write surface

- `lib/features/support_resistance/data/watchlist_store.dart`
- `lib/features/support_resistance/presentation/providers/watchlist_provider.dart`
- `test/features/support_resistance/watchlist_provider_test.dart`

No protected configuration/environment access or changes; no dependency, BMAG, Risk, or navigation changes. Do not accept an eleventh coin, duplicate, invalid mode/timeframe, or non-USDT pair. If validating active instruments requires a contract outside T28, return BLOCKED for coordinator resolution.

## Contract

Use the existing SharedPreferences dependency for one versioned nonsensitive snapshot, with an injectable storage boundary for deterministic failure tests. Fresh install defaults to Spot/H6 with two empty lists. Maintain separate lists of up to 10 valid selected instrument IDs, preserving order. Restore the last mode and timeframe. Sanitize corrupt/unknown/duplicate/over-limit stored records and invalid enum values. Additions require an exact active instrument from the selected mode's T28 catalog; a syntactically valid delisted saved coin remains visible as unavailable for removal per EDGE-001. Serialize writes so a failed persistence operation preserves the last confirmed snapshot and exposes a recoverable error.

## RED then GREEN

- RED-29: corrupt persisted selection, duplicate/eleventh addition, and failed write. Expected: safe sanitized/rolled-back state and visible save error.
- GREEN-29: save separate Spot/Perpetual lists and D1, recreate controller, recover both ordered lists and last mode/timeframe.
- Tests: `flutter test --no-pub test/features/support_resistance/watchlist_provider_test.dart`.

Verification ceiling V2. Buildability gate after final executable change: `flutter build web --no-pub`, canonical Flutter app/web unit; required PASS. Report SDK cache permission failure as `BLOCKED_ENVIRONMENT`, without protected-config diagnostics.

## Audit ledger

- [x] Explicit child role/model/effort dispatch recorded; effective route UNVERIFIABLE.
- [x] RED observed before GREEN: 3 RED tests, then 2 GREEN tests passed.
- [x] Focused tests and canonical build observed after final change: 5 focused tests and Flutter web build passed.
- [x] No protected configuration content accessed or modified.
- [x] Coordinator verdict: PASS.

Audit: `docs/agents/audits/2026-09-30-task-29-support-resistance-watchlist-state.md`.
