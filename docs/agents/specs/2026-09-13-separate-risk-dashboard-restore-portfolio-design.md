# Design Specification: Separate Risk Dashboard and Restore Portfolio

Status: IMPLEMENTED
Date: 2026-09-13
Tier: M
Decision Ledger: `docs/agents/decisions/2026-09-13-separate-risk-dashboard-restore-portfolio-decisions.md`

## 1. Objective

Requested outcome:
- Restore the pre-risk Portfolio screen as the application home.
- Preserve the complete current Risk Dashboard as a separate sixth primary destination.

Success conditions:
- Destination zero renders the Portfolio UI from immediately before commit `cdf01ff`.
- Destination five renders Risk Dashboard without losing its current working-tree behavior.
- Fixed and floating navigation expose all six destinations without clipping, inaccessible controls, or index regressions.

## 2. Current State

### Observed Facts

| ID | Source | Symbol/Location | Observation |
|---|---|---|---|
| OBS-001 | `lib/core/navigation/main_navigation_shell.dart` | `_buildSelectedScreen` | Index zero currently renders `PortfolioScreen`; indices one through four render BMAG, Orders, Market, and Settings. |
| OBS-002 | `lib/core/navigation/navigation_destination_data.dart` | `navigationItems` | Primary navigation currently contains five items and has no Risk destination. |
| OBS-003 | `lib/features/portfolio/presentation/portfolio_screen.dart` | `PortfolioScreen` | The class currently owns the Risk Dashboard and its monitor lifecycle. |
| OBS-004 | commit `a028c632f3d7b4d0802af4d3566d7a731112eabb` | `portfolio_screen.dart` | The immediate pre-`cdf01ff` Portfolio home owns balance refresh, WebSocket price subscription, total/base/PnL summary, privacy masking, dual-currency rendering, dust filtering, and asset rows. |
| OBS-005 | commit `79f2f04bb8b7116cd3d3857c9d6c9bdb5497f4ec` | `portfolio_screen.dart` | The latest Risk Dashboard presentation, including the position-context icon/spacing refinements observed earlier in the working tree, is now committed and must be relocated rather than replaced by the older `cdf01ff` snapshot. |
| OBS-006 | `lib/core/navigation/trading_navigation_bar.dart`, `floating_navigation_buttons.dart` | dynamic item loops/layout | Both navigation presentations derive their controls from `navigationItems`; tests contain hard-coded five-item expectations. |
| OBS-007 | `test/features/portfolio/risk/*`, `portfolio_dual_currency_screen_test.dart` | screen harnesses | Risk tests instantiate `PortfolioScreen`, while Portfolio tests currently enter a separate details screen from Risk Home. |

### Reproduced Behavior

| ID | Method/Command | Observed Result |
|---|---|---|
| REP-001 | Targeted source and Git-history inspection | Risk Dashboard replaced the former Portfolio implementation in commit `cdf01ff`; the former behavior remains recoverable from its parent `a028c632...`, and the latest Risk presentation is at current HEAD `79f2f04...`. |

### Hypotheses

N/A — current behavior and the requested target are established by source, history, and D-001.

## 3. Scope

### In Scope

- Add `RiskDashboardScreen` by relocating the current working-tree Risk Dashboard implementation.
- Restore `PortfolioScreen` from its immediate pre-`cdf01ff` behavior at `a028c632...`, including its shared provider exports.
- Add a sixth primary navigation item at index five with label `Risk` and shield-style iconography.
- Update affected Portfolio, Risk Dashboard, root navigation, fixed navigation, floating navigation, and shared-icon tests.

### Out of Scope

- Risk calculation, repository, monitoring, storage, notification, or policy changes.
- Portfolio API/data semantics or currency formulas.
- Navigation preference persistence or presentation redesign.
- Dependency, build, CI, deployment, or protected configuration changes.
- Deleting `PortfolioDetailsScreen`; it remains available to the preserved Risk Dashboard.

## 4. Clarifications and Decisions

Open questions: N/A
Resolved decisions: D-001
Authorized assumptions: N/A

## 5. Requirements

### REQ-001 — Restore the former Portfolio home

The system MUST render the pre-`cdf01ff` Portfolio experience at primary destination zero.

Inputs: existing Portfolio provider data, live prices, currency mode, exchange rate, theme, and balance privacy state.
Outputs: the former total assets, base capital, unrealized PnL, and asset list presentation.
Required behavior: preserve periodic refresh, pull-to-refresh, WebSocket ticker subscription, dust filtering, responsive layout, dual currency, theme, and privacy masking from commit `a028c632...`.
Failure behavior: preserve the former loading and connection-error states.
Permission behavior: N/A.
Preserved behavior: `hideBalanceProvider` and `isDarkModeProvider` remain import-compatible for existing consumers.

### REQ-002 — Separate and preserve Risk Dashboard

The system MUST expose the current Risk Dashboard as `RiskDashboardScreen` without changing its domain behavior or monitor ownership.

Inputs: the same bridge, optional plan/settings/market/history test seams, and providers currently accepted by `PortfolioScreen`.
Outputs: the same Risk Home UI, drill-downs, editors, settings, Portfolio Details action, refresh behavior, state quality, and privacy behavior.
Required behavior: relocate the exact presentation from current HEAD `79f2f04...` plus any later user-owned working-tree refinements present at execution time, and rename only the public screen ownership.
Failure behavior: preserve current unavailable/error/partial/stale semantics.
Permission behavior: N/A.
Preserved behavior: no Risk engine, repository, runtime, notification, persistence, or event contract changes.

### REQ-003 — Add a sixth primary destination

The system MUST append Risk Dashboard at navigation index five while preserving indices zero through four.

Inputs: fixed or floating navigation mode and destination selection index.
Outputs: six reachable controls ordered Portfolio, BMAG, Orders, Market, Settings, Risk.
Required behavior: label the sixth item `Risk`, use shield-style selected/unselected icons, and route index five to `RiskDashboardScreen`.
Failure behavior: constrained horizontal or vertical floating layouts remain scrollable; no destination becomes unreachable.
Permission behavior: N/A.
Preserved behavior: selection animation, hit testing, semantics, button scale/opacity, saved navigation preferences, and existing destination indices.

### REQ-004 — Keep tests aligned with screen ownership

The system MUST verify Portfolio and Risk Dashboard independently and verify both navigation presentations with six destinations.

Inputs: existing synthetic widget-test fixtures.
Outputs: deterministic focused test evidence.
Required behavior: Risk tests instantiate `RiskDashboardScreen`; Portfolio tests directly exercise restored `PortfolioScreen`; navigation tests assert index five and six-item accessibility.
Failure behavior: tests fail if either screen is swapped, a destination is missing, or constrained navigation overflows.
Permission behavior: N/A.
Preserved behavior: no live credentials or external services are used.

## 6. Data Contract

N/A — no data model, persistence, API, or formula contract changes.

## 7. Cross-Layer Mapping

| Semantic Field | Persistence/Query | DTO | API | Frontend Normalization | Component | Export |
|---|---|---|---|---|---|---|
| Primary Portfolio | unchanged | unchanged | unchanged | existing providers | `PortfolioScreen` | existing class/provider exports |
| Risk Dashboard | unchanged | unchanged | unchanged | existing risk view state | `RiskDashboardScreen` | new screen class |
| Destination index 5 | N/A | N/A | N/A | `navigationItems` | `MainNavigationShell` | existing navigation list |

## 8. Proposed Design

Architecture/control flow:

```text
navigation index 0 -> PortfolioScreen -> portfolio/live-price providers
navigation index 5 -> RiskDashboardScreen -> risk monitor bridge/providers
navigationItems ----> fixed bar and floating buttons (six controls)
```

State transitions/side effects:
- Entering Portfolio starts its existing periodic refresh/subscription lifecycle.
- Entering Risk starts its existing monitor lifecycle.
- Switching destinations disposes the previous screen under the existing shell behavior; no new cross-screen state owner is introduced.

## 9. Interfaces and Contracts

Public API: add `const RiskDashboardScreen(...)` with the constructor contract currently exposed by Risk-owned `PortfolioScreen`; restore `const PortfolioScreen({super.key})`.
Internal interface: `MainNavigationShell` maps index five to `RiskDashboardScreen`.
Database/schema: N/A.
External configuration/environment requirement: N/A.
Authorization: N/A.

## 10. Invariants

- INV-001: Navigation indices zero through four retain their existing meaning.
- INV-002: Current working-tree Risk Dashboard changes are preserved during relocation.
- INV-003: Risk domain/runtime/storage/notification contracts are unchanged.
- INV-004: Shared privacy and theme providers remain available at their current import path.
- INV-005: Agents neither read nor modify protected configuration/environment files.

## 11. Edge Cases

### EDGE-001 — Compact six-item fixed navigation
Condition: a narrow viewport with six destinations and enlarged button scale/text.
Expected behavior: every control remains rendered and tappable without exceptions; selected labels scale/ellipsize as currently designed.
Expected side effects: none.

### EDGE-002 — Constrained floating navigation
Condition: six controls do not fit horizontally or vertically.
Expected behavior: the existing bounded scrolling fallback makes index five reachable.
Expected side effects: none.

### EDGE-003 — Concurrent uncommitted Risk UI work
Condition: the source Risk Dashboard contains committed refinements and may contain later user-owned working-tree edits at execution time.
Expected behavior: relocation copies the current version, including any such edits, before `PortfolioScreen` is restored.
Expected side effects: no unrelated dirty file is reverted.

### EDGE-004 — Screen-specific injected test data
Condition: Risk widget tests inject a bridge/plan/settings/market/history.
Expected behavior: the same constructor seams remain available on `RiskDashboardScreen`.
Expected side effects: none.

## 12. Failure Semantics

| Failure | Expected Response/Error/Status | Allowed Side Effects | Forbidden Side Effects |
|---|---|---|---|
| Relocation would lose dirty Risk changes | Stop and return `BLOCKED` | planning/audit notes | overwriting or reverting user work |
| Six-item layout overflows or hides index five | Test failure / `REWORK` | test diagnostics | shipping unreachable navigation |
| Restored Portfolio differs from the pre-`cdf01ff` `a028c632...` behavior | Test failure / `REWORK` | targeted correction | replacing it with Portfolio Details semantics |
| Build/test needs protected config inspection | `BLOCKED` and ask for minimum non-sensitive fact | none | reading or changing protected config |

## 13. RED / GREEN Behavioral Contract

### RED-001
Scenario: The present application does not provide independent Portfolio and Risk primary destinations.
Input/setup: root shell with six-destination expectations and synthetic Portfolio/Risk providers.
Expected result: before implementation, index zero shows Risk Home, index five is absent, and restored Portfolio assertions fail.
Expected side effects: none.

### GREEN-001
Scenario: Portfolio and Risk Dashboard are independently reachable after the split.
Input/setup: root shell and existing synthetic widget fixtures.
Expected result: index zero shows the former Portfolio summary/list, index five shows `Risk Home`, all six fixed/floating controls are reachable, and existing Risk behavior tests pass against `RiskDashboardScreen`.
Expected side effects: only existing screen lifecycle effects.

Verification order is RED then GREEN.

## 14. Performance Contract

N/A — no new data computation or background cadence is introduced.

## 15. Compatibility

Existing destination indices, provider import paths, Portfolio formatting, Risk monitor interfaces, and navigation preferences remain compatible. The intentional UI change is one appended destination and restoration of Portfolio at index zero.

## 16. Security and Permissions

No authentication, authorization, credential, or sensitive-data contract changes. Existing balance masking and Risk privacy behavior are preserved.

## 17. Protected Configuration / Environment Actions

Required external actions: none.

## 18. Rollout / Rollback

N/A — local presentation split with no data migration or deployment action in scope. A rollback would revert only the approved source/test split while preserving unrelated dirty work.

## 19. Acceptance Criteria

### AC-001
Given application startup, when destination zero is selected, then the pre-`cdf01ff` Portfolio summary and asset list are displayed rather than Risk Home.

### AC-002
Given either navigation presentation, when controls are rendered, then exactly six primary destinations exist in the order defined by REQ-003 and index five is labeled `Risk`.

### AC-003
Given index five is selected, when the destination renders, then the current Risk Dashboard starts and displays `Risk Home` with its existing drill-down/editor behavior.

### AC-004
Given compact, large-text, fixed, or floating layouts, when six destinations render, then every index remains reachable without overflow exceptions.

### AC-005
Given existing imports and privacy/theme settings, when Portfolio, Orders, Market, Settings, and Risk render, then `hideBalanceProvider` and `isDarkModeProvider` remain compatible and current masking/theme behavior remains intact.

## 20. Requirement Traceability

| Requirement | Acceptance Criteria | Design/Contract | RED/GREEN |
|---|---|---|---|
| REQ-001 | AC-001, AC-005 | §8-§10 | RED-001 / GREEN-001 |
| REQ-002 | AC-003, AC-005 | §8-§10 | RED-001 / GREEN-001 |
| REQ-003 | AC-002, AC-004 | §8-§11 | RED-001 / GREEN-001 |
| REQ-004 | AC-001-AC-005 | §13 | RED-001 / GREEN-001 |

## 21. Completion Gate

- [x] no unresolved material question
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
| 1 | Initial ready specification. | D-001 resolved destination ownership. |
