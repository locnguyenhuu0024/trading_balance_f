# Design Specification: Multi-position Risk Dashboard, 429 resilience, and Vietnamese UI

Status: BLOCKED_ON_CLARIFICATION
Date: 2026-09-13
Tier: L
Decision Ledger: `docs/agents/decisions/2026-09-13-multi-position-risk-dashboard-429-vietnamese-decisions.md`

## 1. Objective

Requested outcome:
- Remove the persistent HTTP 429 failure shown beside the active Risk monitor by bounding and coordinating requests.
- Simultaneously monitor and alert every open eligible isolated-margin position.
- Present every position as a compact collapsible section.
- After the functional work passes, translate the complete Risk Dashboard experience into Vietnamese.

Success conditions:
- One monitoring owner fetches the account position list once per capture batch and fairly updates every eligible position without an unbounded request burst.
- A 429 activates shared backoff, honors a longer `Retry-After`, preserves last-known data, and cannot be bypassed by timer or manual refresh.
- Every active position has isolated evaluation, plan, history, event latches, persistence, freshness, and notification behavior.
- Every active position remains visible regardless of NORMAL/WATCH/HIGH/CRITICAL state and can be expanded independently.
- Risk Dashboard user-visible copy is Vietnamese after the functional acceptance criteria pass.

## 2. Current State

### Observed Facts

| ID | Source | Symbol/Location | Observation |
|---|---|---|---|
| OBS-001 | `lib/features/portfolio/data/risk/risk_repository.dart` | `loadPosition`, `_fetchInterestLedger` | One eligible position is selected and enriched; interest-ledger pagination may run synchronously through as many as 100 pages. |
| OBS-002 | `lib/features/portfolio/application/risk_monitor.dart` | `_capture`, `_registerFailure` | The monitor is single-flight and has 30/60/120/300-second backoff, but state and episode context are singular. |
| OBS-003 | `lib/features/portfolio/domain/risk/risk_models.dart` | `RiskPositionSelection.candidates` | The repository already identifies every eligible position, but candidates do not reach the view state. |
| OBS-004 | `lib/features/portfolio/application/risk_monitor.dart` | `_selectedPositionId` | A selected-position field is read but has no command that assigns it; only the first eligible position is effectively monitored. |
| OBS-005 | `lib/features/portfolio/application/risk_monitor_bridge.dart` | `RiskMonitorViewState` and wire codec | The public/runtime state carries one evaluation, one episode, one plan, and one history set. |
| OBS-006 | `lib/features/portfolio/presentation/risk_dashboard_screen.dart` | `_DashboardBody`, `_MonitorStatus`, `_PositionContext` | The UI renders one full evaluation; the monitor-status block displays upstream `lastError`, including HTTP 429. |
| OBS-007 | Risk presentation widgets and risk domain/application sources | user-visible literals and generated messages | English copy is distributed across dashboard widgets, validators, dynamic reasons/errors/events, history, and notifications. |
| OBS-008 | `docs/agents/specs/2026-09-10-isolated-margin-risk-dashboard-design.md` | V1 scope and invariants | The original design intentionally selected one position; account/episode isolation, no false safety, single ownership, and bounded GET polling remain governing invariants. |

### Reproduced Behavior

| ID | Method/Command | Observed Result |
|---|---|---|
| REP-001 | Targeted static call-path inspection | Dashboard start triggers one monitor; account enrichment may surface `Risk enrichment request failed (HTTP 429)` while `isRunning` remains true. |
| REP-002 | Targeted state/UI inspection | Eligible candidates remain private to the repository/monitor, so only one position evaluation can render or alert. |

### Hypotheses

| ID | Hypothesis | Evidence | Status |
|---|---|---|---|
| HYP-001 | Tight, restart-from-page-one interest-ledger pagination is a material 429 amplifier. | Up to 100 sequential authenticated page requests have no pacing or resumable partial cache. This code-level amplifier is confirmed; the exact live endpoint that returned the user's 429 remains unconfirmed because UI state discards it. | CONFIRMED amplifier / live endpoint unconfirmed |

## 3. Scope

### In Scope

- Aggregate monitoring for all currently open positions that satisfy the existing long isolated MARGIN/USDT eligibility contract.
- One shared position discovery request per capture batch; fair, bounded per-position enrichment and market refresh.
- Shared single-flight request coordination, request spacing, endpoint-class backoff, `Retry-After`, resumable bounded ledger pagination, and last-good-state preservation.
- Per-episode runtime context, persistence, history, plans, latches, events, and notifications under one owner.
- Backward-compatible bridge/service wire transport for aggregate position state.
- Collapsible per-position summaries and lazily built expanded detail surfaces.
- Vietnamese copy for all rendered Risk Dashboard surfaces after functional tasks pass.

### Out of Scope

- Spot-only wallet coins, closed positions in the active dashboard, short/cross-margin/futures positions, unsupported quote/debt currencies, or changed financial formulas.
- Trading, borrowing, repayment, or automatic risk actions.
- New packages, external data services, server sync, deployment, or protected configuration changes.
- Translating Portfolio Details or other application destinations outside Risk Dashboard.
- Translating coin/instrument/source names, `USDT`, `OI`, `%`, `pp`, `x`, protocol/storage keys, or user-authored rule/zone text.

## 4. Clarifications and Decisions

Open questions: none
Resolved decisions: D-001, D-002, D-003, D-004
Authorized assumptions: N/A

## 5. Requirements

### REQ-001 — Bounded shared position discovery and enrichment

The system MUST fetch the active MARGIN position set once per capture batch and enrich eligible positions through one shared request coordinator.

Inputs: authenticated account/config/positions and existing enrichment endpoints.
Outputs: deterministic ordered eligible-position snapshots with per-source quality/freshness.
Required behavior: authenticated requests are single-flight by request key, serialized with at least 250 ms spacing, cached by existing stable/ledger TTL semantics, and fairly scheduled across positions. Interest-ledger work is resumable and limited to two pages total across the monitor per capture batch; completed pages are not replayed unless invalidated, and pagination stops once a trustworthy page crosses the episode start boundary.
Failure behavior: 429 immediately closes the affected authenticated/public request lane, skips later work in that lane, and starts shared endpoint-class backoff using 30/60/120/300 seconds and any longer valid `Retry-After`; timer and manual refresh issue zero blocked requests. Partial ledger coverage keeps True Exit unavailable under the existing contract.
Permission behavior: existing read-only authenticated GET boundary remains unchanged.
Preserved behavior: credential invalidation, generation fencing, no authenticated payload/header logging, and current eligibility formulas.

### REQ-002 — Simultaneous per-position monitoring

The system MUST evaluate every currently open eligible isolated-margin position during one owner-controlled monitoring lifecycle.

Inputs: ordered position snapshots, cached/per-position market snapshots, account settings, per-episode records.
Outputs: immutable ordered `RiskPositionMonitorViewState` entries plus aggregate owner/request status.
Required behavior: each entry owns its episode identity, evaluation, plan evaluation, plan, market state, history, summaries, previous check, trend, velocity, events, quality, freshness, unsaved flag, and last error. Scheduling is round-robin so a large first position cannot starve later positions.
Failure behavior: one position/source failure does not erase or stop unrelated position states; global credential failure still fences the account.
Permission behavior: N/A.
Preserved behavior: risk formulas, missing-data semantics, freshness rules, and single monitor owner.

### REQ-003 — Isolated alerts and persistence for every active episode

The system MUST persist and notify state transitions independently for every active position episode.

Inputs: fresh per-position evaluations and existing account/episode storage.
Outputs: independently deduplicated events, histories, plans, summaries, and privacy-safe notifications.
Required behavior: one position's event/latch/plan/history never mutates another position's context; a newly opened episode starts clean; a closed position is removed from the active list after pending writes flush while retained history follows existing retention.
Failure behavior: a failed episode write blocks OS delivery for that episode only and marks it unsaved; other episodes continue.
Permission behavior: existing notification capability rules.
Preserved behavior: no PnL notification, durable-before-delivery ordering, account namespace isolation.

### REQ-004 — Collapsible all-position dashboard

The system MUST render one compact collapsible section for every active eligible position, including positions with no active warning.

Inputs: aggregate monitor view state.
Outputs: ordered collapsed summaries and on-demand full detail.
Required behavior: all sections start collapsed on a new dashboard visit; each summary shows coin/instrument, eligibility context, overall state, buffer, leverage, quality/freshness, and alert/error indicator subject to privacy. Tapping a section expands its existing full dashboard content; sections expand/collapse independently and details are built lazily.
Failure behavior: empty/error/global-backoff states remain actionable; a failed position remains visible with last-known values when valid.
Permission behavior: N/A.
Preserved behavior: light/dark theme, privacy semantics, 320 px/200% text accessibility, and existing drill-down/editor behavior.

### REQ-005 — Complete Vietnamese Risk Dashboard

The system MUST display Vietnamese for every user-visible Risk Dashboard string after REQ-001 through REQ-004 pass.

Inputs: typed risk states, reasons, validations, events, and legacy persisted messages.
Outputs: Vietnamese dashboard, sheets, dialogs, snackbars, empty/error/stale/partial states, in-dashboard history, tooltips, and semantics.
Required behavior: use a centralized Vietnamese formatter/catalog; translate typed labels and known legacy generated messages at presentation boundaries. User-authored text and approved technical tokens remain unchanged. Unknown upstream errors render a safe Vietnamese generic explanation plus non-linguistic status/source metadata rather than raw English.
Failure behavior: missing translation fails the source-audit/allowlist test; wire/storage enum values and persisted identifiers never change for translation.
Permission behavior: N/A.
Preserved behavior: persistence decode compatibility, privacy redaction, source attribution, units, and user content.

## 6. Data Contract

| Field | Type | Required | Meaning | Null/Zero/Absent Semantics |
|---|---|---:|---|---|
| `positions` | immutable list of `RiskPositionMonitorViewState` | yes | All active eligible positions ordered by the existing comparator. | Empty means no eligible open position; never means request failure. |
| `positionId` / `episodeKey` | string | yes per active entry | Stable position/episode identity. | Missing identity makes the row unsupported and excludes evaluation/persistence. |
| `requestStatus` | typed aggregate status | yes | Ready, refreshing, backing off, auth blocked, or partial. | Must not infer success from `isRunning` alone. |
| `retryAt` / endpoint class | datetime / enum | optional | Safe non-secret retry diagnostic. | Absent when no scheduled retry is active. |
| `expanded` | UI-local boolean | yes | Presentation-only expansion state. | Starts false per dashboard visit; never persisted. |

Grain: one aggregate view snapshot contains one entry per active eligible position; one persisted episode record remains one account-position episode.
Source tables/fields: existing OKX adapter fields and local risk records; no new remote source.
Date boundary/timezone: unchanged from existing settings and history semantics.
Formula: unchanged; each position is evaluated independently by the existing engines.
Independent worked example: positions BTC (NORMAL), ETH (WATCH), and SUI (HIGH) produce three ordered entries and three collapsed headers; expanding ETH shows only ETH plan/history, while a SUI event produces no ETH latch/history mutation.

## 7. Cross-Layer Mapping

| Semantic Field | Persistence/Query | DTO | API | Frontend Normalization | Component | Export |
|---|---|---|---|---|---|---|
| Active positions | existing account positions fetch | existing position DTO | one `account/positions` request per batch | eligible ordered list | aggregate dashboard | bridge state |
| Episode state | existing per-account/per-episode keys | existing risk records | N/A | map keyed by episode | one expansion section | `RiskPositionMonitorViewState` |
| Request pressure | resumable ledger cursor/cache | internal coordinator state | existing GET endpoints | typed backoff/quality | monitor status + row error | aggregate bridge state |
| Vietnamese copy | no persistence schema change | stable typed values | N/A | Vietnamese formatter/catalog | all Risk widgets/sheets/history | dashboard formatter |

## 8. Proposed Design

Architecture/control flow:

```text
single RiskMonitor owner/timer
  -> one shared account/config + positions discovery
  -> eligible positions ordered once
  -> fair request coordinator with authenticated/public lanes
       (single-flight, pacing, cache, immediate 429 stop, backoff)
       -> bounded resumable enrichment per episode
       -> cached/staggered market refresh per instrument; shared BTC candles
  -> Map<episodeKey, RiskEpisodeMonitorContext>
       -> evaluate / reduce events / persist / notify independently
  -> aggregate RiskMonitorViewState.positions
  -> collapsible per-position sections
  -> Vietnamese formatter after functional tasks PASS
```

State transitions/side effects:
- A new eligible episode creates a clean context and joins the round-robin queue.
- A continuing episode reuses caches and persisted state.
- A closed/disappeared episode flushes pending OI/history, leaves the active list, and remains retained by existing policy.
- A 429 blocks the affected request lane globally until retry time and cancels later queued work for that lane; cached position cards remain visible and explicitly stale/partial.
- Successful requests clear only the matching failure/backoff state.

## 9. Interfaces and Contracts

Public API: extend `RiskMonitorViewState` with immutable per-position entries and typed request status while retaining a temporary legacy single-position projection through T25 so the application remains buildable before T26.
Internal interface: replace singular monitor episode fields with a context map and introduce a repository/request-coordinator batch contract. Wire codec must round-trip every per-position field.
Database/schema: no required storage-key/schema migration; reuse existing episode records. If implementation evidence disproves this, stop for plan validation rather than silently migrating.
External configuration/environment requirement: N/A.
Authorization: existing authenticated GET and notification permissions only.

## 10. Invariants

- INV-001: Financial formulas and severity aggregation remain unchanged and operate independently per position.
- INV-002: One owner performs discovery, evaluation, persistence, and notification; per-position monitoring does not create duplicate owners or timers.
- INV-003: One capture batch performs at most one uncached account-position discovery request.
- INV-004: 429/backoff cannot be bypassed by timer, UI refresh, expansion, or another position.
- INV-005: No position can starve indefinitely; request scheduling is deterministic round-robin.
- INV-006: Episode history, plans, latches, samples, and notifications never cross positions/accounts.
- INV-007: Missing/stale/partial data never becomes NORMAL or suppresses a known adverse floor.
- INV-008: Collapsing/expanding is presentation-only and causes no HTTP request or monitor mutation.
- INV-009: Translation never changes wire/storage identifiers, formulas, sources, units, or user-authored text.
- INV-010: Protected configuration/environment contents remain unread and unmodified.

## 11. Edge Cases

### EDGE-001 — Large active-position set
Condition: more positions exist than can finish all due enrichment in one capture.
Expected behavior: publish every known position, process work fairly over later batches, and mark pending/partial freshness; never burst or starve.
Expected side effects: delayed completeness only.

### EDGE-002 — One position receives 429
Condition: any authenticated/public request returns 429.
Expected behavior: shared class backoff starts, longer `Retry-After` wins, no blocked request occurs, and unaffected cached entries remain visible.
Expected side effects: position/global status records retry metadata without sensitive content.

### EDGE-003 — Position opens, closes, or reopens
Condition: the active set changes between batches.
Expected behavior: new episode starts isolated; closed episode flushes/removes; reopened same coin uses a new episode and no stale plan/latch.
Expected side effects: retained closed history follows current limits.

### EDGE-004 — Multiple states and failures
Condition: NORMAL, WATCH, HIGH, stale, and failed positions coexist.
Expected behavior: all appear in deterministic order; one error does not hide normal positions or replace aggregate content.
Expected side effects: none.

### EDGE-005 — Compact and accessible expansion
Condition: 320 px width, 200% text, hidden amounts, keyboard/screen reader use.
Expected behavior: headers wrap/scroll without overflow, expansion remains reachable, and hidden numeric semantics are absent.
Expected side effects: none.

### EDGE-006 — Legacy English history
Condition: stored events contain known English messages from earlier versions.
Expected behavior: formatter renders Vietnamese without rewriting stored identifiers or user-authored text.
Expected side effects: none.

## 12. Failure Semantics

| Failure | Expected Response/Error/Status | Allowed Side Effects | Forbidden Side Effects |
|---|---|---|---|
| HTTP 429 | backing-off status with retry time/category; preserve last good data | retry scheduling | immediate retry, request storm, false recovery alert |
| Per-position enrichment/market failure | that entry becomes partial/stale/error | continued monitoring of other entries | removing unrelated positions |
| Account credential rejection | account-wide auth block | user-visible Vietnamese status | continuing authenticated polling |
| Episode persistence failure | affected entry `unsaved`; no OS delivery for its unpersisted event | in-app error/event | cross-episode block or unsafe notification |
| Wire decode incompatibility | typed unavailable state and ownership recovery | diagnostics | silently dropping positions |
| Missing translation | test failure / REWORK | allowlisted technical token | mixed English UI or mutated identifiers |

## 13. RED / GREEN Behavioral Contract

### RED-001
Scenario: ten eligible positions and a multi-page ledger are captured while a 429 with `Retry-After` occurs.
Input/setup: fake repository/clock with ten positions, at least five ledger pages, and a deterministic 429.
Expected result: one positions discovery per batch, no more than two ledger pages total in that batch, no overlap, no later request in a lane after its 429, and zero repository requests before retry time.
Expected side effects: typed backoff state only.

### GREEN-001
Scenario: request batching completes across multiple capture cycles without a rate-limit failure.
Input/setup: ten eligible positions, shared currencies/BTC context, and resumable ledger pages.
Expected result: keyed caches are reused, BTC context is fetched once when due, ledger cursors advance fairly without replay, and all due work completes within the declared bounds.
Expected side effects: bounded cache/cursor updates only.

### RED-002
Scenario: the current singular monitor receives three eligible positions and one per-position failure.
Input/setup: BTC NORMAL, ETH WATCH, SUI HIGH with independent episode records and a retry cooldown.
Expected result: pre-change state cannot represent all entries; after the contract is implemented, manual/timer refresh during cooldown issues no request and last-good unrelated/per-position entries remain intact.
Expected side effects: typed aggregate/per-position status only.

### GREEN-002
Scenario: three eligible positions with different risk states are monitored through open/change/close cycles.
Input/setup: BTC NORMAL, ETH WATCH, SUI HIGH with independent episode records and events.
Expected result: all three publish and alert independently; updates are fair; ETH history/plan/latches never contain SUI data; a closed then reopened SUI starts a new episode.
Expected side effects: existing per-episode persistence and one notification per durable event.

### RED-003
Scenario: dashboard receives multiple positions at 320 px/200% text with hidden amounts and one stale/error row.
Input/setup: aggregate synthetic state with collapsed sections.
Expected result: no overflow/privacy leak, all positions remain reachable, and expanding one row triggers zero HTTP/monitor commands.
Expected side effects: UI-local expansion state only.

### GREEN-003
Scenario: user expands ETH while BTC and SUI remain collapsed.
Input/setup: three aggregate entries.
Expected result: all three summary headers stay visible; ETH full existing detail renders with ETH-only editors/history and can collapse again independently.
Expected side effects: none outside widget state.

### RED-004
Scenario: all Risk Dashboard surfaces are audited after functional tasks pass.
Input/setup: fresh/partial/stale/error/429/empty states, editor validation, in-dashboard history, semantics, and legacy stored messages.
Expected result: no unapproved user-visible English literal appears; protocol values, source labels, units, and user-authored text remain unchanged.
Expected side effects: none.

### GREEN-004
Scenario: a Vietnamese user opens, expands, edits, refreshes, and reads Risk Dashboard history.
Input/setup: synthetic multi-position state and dashboard surfaces.
Expected result: every application-generated phrase is Vietnamese and privacy masking still removes protected numbers.
Expected side effects: unchanged functional state transitions.

Verification order for each task is RED then GREEN.

## 14. Performance Contract

Baseline: current monitor has one serialized owner but may issue up to 100 unpaced ledger pages and represents one position.
Measurement: fake clock/recording adapters assert request count, ordering, concurrency, backoff, cache reuse, and round-robin fairness for 1, 3, and 10 positions.
Targets:
- account positions: at most one uncached request per capture batch;
- authenticated request concurrency: one, with at least 250 ms scheduler spacing;
- ledger progress: at most two pages total across the monitor per batch, resumable without replay and stopped at the episode boundary;
- expansion/collapse: zero network/monitor commands;
- rendering: expanded details are lazy; collapsed list remains scrollable at 10 positions.
Semantic parity: every fresh position uses the same engine/policy and event rules as the current single-position monitor.
Unavailable evidence response: do not claim live OKX capacity; deterministic adapter evidence proves app-side bounds, while live endpoint limits remain server-owned.

## 15. Compatibility

Existing repository formulas, storage keys/records, risk settings, notification privacy, navigation, Portfolio screen, and supported platform ownership remain compatible. T25 keeps a legacy primary-position projection until T26 consumes aggregate state, preventing a broken intermediate build. Existing stored English messages remain decodable and are localized only when rendered.

## 16. Security and Permissions

No new credentials, permissions, endpoints, or write APIs. Request diagnostics expose endpoint category/status/retry time only—never headers, payloads, raw credentials, or configuration. Tests use fake adapters/data.

## 17. Protected Configuration / Environment Actions

Required external actions: none.

## 18. Rollout / Rollback

Rollout sequence: T24 rate-safe data foundation -> T25 aggregate monitor -> T26 collapsible UI -> T27 Vietnamese UI -> integrated audit.
Rollback trigger: duplicated owner/alerts, cross-episode data, unbounded request count, privacy regression, or wire incompatibility.
Rollback procedure/data implications: revert only the new aggregate/UI/localization source and test surfaces; existing per-episode records remain valid and no destructive migration occurs.

## 19. Acceptance Criteria

### AC-001
Given 1, 3, or 10 active eligible positions, when a capture batch runs, then account positions are fetched once and enrichment is single-flight, paced, cached, and fairly scheduled.

### AC-002
Given paginated interest history, when capture cycles continue, then at most two ledger pages total are fetched per batch and fair progress resumes without replay until complete, the episode boundary is crossed, or the existing hard limit is reached.

### AC-003
Given a 429 with or without `Retry-After`, when repository work is attempted before the permitted retry, then no request is issued and typed retry metadata remains available.

### AC-004
Given multiple eligible episodes, when evaluations and events occur, then each position retains independent plans/history/latches/notifications, last-good state survives cooldown, and a failure in one does not erase another.

### AC-005
Given an open/close/reopen lifecycle, when the active set changes, then active cards update, pending state flushes safely, and the reopened episode inherits no prior episode state.

### AC-006
Given foreground/service ownership and a populated aggregate snapshot, when state crosses the bridge, then all entries round-trip without duplicate polling or field loss.

### AC-007
Given NORMAL, WATCH, HIGH, and failed eligible positions, when the dashboard renders, then every position has a collapsed summary regardless of warning state.

### AC-008
Given a collapsed position, when the user expands it, then that position's existing full detail/edit/history surfaces render lazily and no network/monitor command is sent.

### AC-009
Given mobile, desktop, 320 px/200% text, dark/light, and hidden values, when sections expand/collapse, then there is no overflow, inaccessible position, or semantic privacy leak.

### AC-010
Given every Risk Dashboard route/sheet/dialog/state, when rendered after T24-T26 pass, then all application-generated user-visible text is Vietnamese except approved tokens.

### AC-011
Given dynamic reasons, validation, in-dashboard history, and legacy known messages, when displayed, then the centralized formatter produces Vietnamese without changing wire/storage values or user-authored text.

### AC-012
Given future source changes, when Risk presentation tests run, then an allowlist-based source audit fails for newly introduced unapproved English user-visible literals.

## 20. Requirement Traceability

| Requirement | Acceptance Criteria | Design/Contract | RED/GREEN |
|---|---|---|---|
| REQ-001 | AC-001, AC-002, AC-003 | §8, §9, §14 | RED-001 / GREEN-001 |
| REQ-002 | AC-001, AC-004, AC-005, AC-006 | §6-§10 | RED-002 / GREEN-002 |
| REQ-003 | AC-004, AC-005 | §8-§12 | RED-002 / GREEN-002 |
| REQ-004 | AC-007, AC-008, AC-009 | §8, §10, §14 | RED-003 / GREEN-003 |
| REQ-005 | AC-010, AC-011, AC-012 | §8-§12 | RED-004 / GREEN-004 |

## 21. Completion Gate

- [x] no unresolved material question — Q-004 resolved by D-004
- [x] no silent assumption
- [x] requirements/contracts are unambiguous
- [x] edge/failure semantics defined
- [x] RED/GREEN expected outcomes independently derived
- [x] acceptance criteria complete
- [x] traceability complete for affected requirements
- [x] protected configuration/environment contents were not read
- [x] required external configuration/environment actions are N/A

## 22. Change Log

| Revision | Change | Reason |
|---|---|---|
| 1 | Initial ready specification for rate-safe multi-position monitoring, collapsible UI, and Vietnamese localization. | D-001 through D-003. |
