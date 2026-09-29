# Implementation Plan: Support and Resistance Watchlist

Status: BLOCKED_ON_CLARIFICATION
Execution: T28 PASS (authorized separately on 2026-09-29); T29 and T30 ON_HOLD by user instruction.
Date: 2026-09-29
Tier: L
Specification: `docs/agents/specs/2026-09-29-support-resistance-watchlist-design.md`
Decision Ledger: `docs/agents/decisions/2026-09-29-support-resistance-watchlist-decisions.md`

## 1. Objective and authorization

Implement REQ-001..006 and AC-001..005 from the specification. This is a planning artifact only. Product/test/runtime code changes begin only after the user explicitly approves this presented plan and task checklist.

The user separately authorized T28 while the first-launch default for later tasks remains open. T28 passed its independent audit; this does not authorize T29, T30, or final feature rollout.

## 2. Preconditions and repository impact

User decisions D-001..007 are resolved. The existing BMAG and Risk algorithms remain untouched. No dependency-manifest, configuration, environment, CI, deployment, or generated configuration files may be read or written by an agent. No user-owned external configuration action is required.

| Area | Planned files | Change |
|---|---|---|
| Domain/data | `lib/features/support_resistance/domain/{level_calculator,models}.dart`, `data/market_repository.dart` | Add validated public market data and pure level calculation. |
| State/persistence | `lib/features/support_resistance/data/watchlist_store.dart`, `presentation/providers/watchlist_provider.dart` | Add independent persisted lists and global mode/timeframe. |
| UI/integration | `lib/features/support_resistance/presentation/{support_resistance_screen.dart,providers/levels_provider.dart}`, `lib/core/navigation/{navigation_destination_data,main_navigation_shell}.dart` | Add seventh destination and screen. |
| Tests | `test/features/support_resistance/{level_calculator_test,market_repository_test,watchlist_provider_test,support_resistance_screen_test}.dart`, `test/core/navigation/main_navigation_shell_test.dart` | Focused behavior, state, and navigation coverage. |

The files above are planned exact write surfaces; an executor must stop for coordinator review if another file becomes necessary. Existing protected files remain name-only metadata.

## Planning Workstream Decomposition

| Workstream | Material | Independent | Reasoning route | Logical agent run | Result/adoption |
|---|---|---|---|---|---|
| Frontend/navigation/state | YES | YES | R2 / gpt-6-sol / medium, EXPLICIT | plan-frontend-01 | COMPLETE / USED |
| Market data/level semantics | YES | YES | R2 / gpt-6-sol / medium, EXPLICIT | plan-data-01 | COMPLETE / USED |
| Configuration | NO | N/A | N/A | N/A | No change permitted or required |

Fan-out Required: YES
Required Reasoning Agents: 2
Actual Reasoning Agents: 2
Fan-out Compliance: PASS
Skip Reason: N/A
Effective child routes: unavailable; both spawn requests explicitly bound model and effort, status UNVERIFIABLE.

Coordinator synthesis: use a separate watchlist state rather than BMAG's single-coin provider; use a separate read-only market adapter rather than change Risk's 1H/4H guard; connect per-coin loading to the seventh nav destination. Instrument, ticker and candle requests all use the same selected market/instrument key.

## 3. Dependency graph and tasks

```text
T28 market data + calculation -> T29 persisted selection -> T30 screen + navigation
```

The data and persistence implementations have distinct files but run serially because their Flutter build checks share mutable SDK/output state. T30 depends on both. Each executor is bound explicitly to its task route; no parent-route inheritance.

| Task | Steps | Requirements/AC | Route | Allowed write surface |
|---|---|---|---|---|
| T28 | P01 | REQ-002..004, AC-002..004 | E2 / gpt-6-luna / max | New domain/data and two corresponding tests |
| T29 | P02 | REQ-001..002, AC-001 | E1 / gpt-6-luna / xhigh | New store/provider and corresponding test |
| T30 | P03 | REQ-001..006, AC-001..005 | E1 / gpt-6-luna / xhigh | New screen/result provider, two nav files, screen/nav tests |

## 4. Ordered implementation steps

### P01 — Typed market adapter and deterministic levels (T28)

Create a public read-only adapter with injectable transport and public request coordination. Discover live USDT Spot/Perpetual instruments, fetch exact-market ticker and enough UTC candles to pass at most the newest 300 confirmed records to a pure calculator. Validate payloads, pagination, timestamp order and alignment. Reject mixed/invalid data; preserve typed error state and 429 backoff. Calculator applies the strict two-candle swing, 0.5%-span median clusters, current-price side, nearest-first and five-per-side rules of design §4. Do not change BMAG/Risk behavior.

RED: fixture with an unconfirmed extreme, tied neighboring highs, a 0.5%-chain wider than its endpoint span, and crossed level; verify excluded false swing and recategorized side.
GREEN: valid multi-swing 300-candle fixture plus mocked Spot/Perpetual responses yields exact ordered level prices and mode-specific request keys.
Stop: exchange response cannot establish the specified UTC interval, or integration needs a protected configuration change.

### P02 — Persisted selections (T29)

Create a nonsensitive SharedPreferences-backed store and controller for separate unique ordered Spot/Perpetual lists (10 each), last mode and timeframe, initial empty watchlists, search-result validation, and save-error rollback. Keep this state separate from BMAG and Risk.

RED: malformed stored entries and an eleventh/duplicate insert cannot leak into state; a failed write restores last confirmed selection.
GREEN: choose different lists in two modes and D1, recreate controller, recover both lists and D1.

### P03 — Screen, refresh and navigation (T30)

Add a searchable multi-select UI, mode/timeframe controls, per-coin cards with current price and levels, accessible loading/error/sparse/stale states, one-minute mounted refresh and manual refresh, plus nav integration in fixed/floating layouts. Use provider keys/generation to ignore obsolete responses. Update existing nav test and add focused screen test.

RED: switch mode/timeframe while an old request is pending; old result does not replace current state, and one coin's failure does not hide the other.
GREEN: add two coins, display ordered five-per-side data, switch timeframe/mode, refresh, and navigate through the seventh item on a narrow screen.

## 5. Verification

Formal order per task: focused RED, then focused GREEN after implementation is ready. Run only impacted tests while editing. After the last code/test change in each task, run the canonical affected build `flutter build web --no-pub`; this is a task buildability gate, not a substitute for behavioral tests. Run `flutter analyze --no-pub` and the focused feature/navigation test set at final integration. Suggested test command: `flutter test --no-pub test/features/support_resistance test/core/navigation/main_navigation_shell_test.dart`.

Verification ladder: V1 task-specific RED/GREEN; V2 impacted test group; V3 affected feature and navigation tests; final integration ceiling V3. Broaden only for a concrete cross-feature regression signal. Re-run only evidence invalidated by later changes; restart RED→GREEN if their shared calculation/fixture basis changes.

Environment note: planning probe `flutter --version` could not write to the Flutter SDK cache outside the workspace (`Operation not permitted`). Execution may require sandbox escalation for Flutter's SDK cache. This is a toolchain permission issue, not a reason to alter repository configuration. If access remains unavailable, report build/analyzer/test evidence as blocked; do not mark a code task PASS.

No direct external OKX live call is authorized as planning evidence. Contract behavior is verified with mocked transport; if live exchange compatibility is later requested, seek explicit service authorization and report results separately.

## 6. Risks, rollout and completion

| Risk | Detection | Response |
|---|---|---|
| UTC bar spelling/alignment differs from expected response | Adapter test/verified public response | Stop affected task and replan; do not silently change period boundaries. |
| API rate limit with up to 10 selected coins | Typed 429/backoff and per-coin errors | Serialize/dedupe requests, keep unaffected cards visible, label stale data. |
| Seventh nav item crowds narrow widths | Narrow fixed/floating widget tests | Adjust responsive nav within T30 scope without hiding destination semantics. |
| Flutter SDK cache is not writable in sandbox | Exact build/test command failure before compilation | Request the narrow permission needed; preserve source and report blocked evidence if denied. |

Rollout: ship the new destination after T28→T29→T30 and integration audit. Rollback: remove the new destination/feature code; existing BMAG/Risk behavior has no migration. Completion requires all three tasks PASS, ordered RED/GREEN and build evidence, all AC verified, final status/diff audit, and no protected configuration access/write.
