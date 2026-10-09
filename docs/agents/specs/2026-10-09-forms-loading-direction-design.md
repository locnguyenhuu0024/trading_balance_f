# Design Specification: Forms, motion and automatic strategy direction

Status: READY_FOR_PLAN
Date: 2026-10-09
Tier: L
Decision Ledger: docs/agents/decisions/2026-10-09-forms-loading-direction-decisions.md

## Objective and current evidence

Improve every existing input form, make asynchronous state visible, provide startup/navigation continuity and enforce automatic strategy direction across client/server.

| ID | Source | Observation |
|---|---|---|
| OBS-001 | lib/core/theme/app_theme.dart | Existing monochrome AppPalette, spacing 4/8/12/16/24/32, 48px touch targets, 140/220ms motion |
| OBS-002 | lib/main.dart | Storage/preferences awaited before runApp; initialization is invisible |
| OBS-003 | lib/core/navigation/main_navigation_shell.dart | Selected destination replaces body directly |
| OBS-004 | backend/strategy_automatic.py | Automatic request has three fields; both candidate groups generated; direction not persisted |
| OBS-005 | backend/strategy.py; backend/strategy_scope.py | Materialized direction, side budgets, net/hedge gates and side-specific execution already supported |

Scope: all input forms and their confirmation/loading surfaces, startup and route transitions, automatic-generation direction contract. Exclusions: dependencies, protected configuration/environment, OS launch packaging, trading/risk algorithm redesign, deployment and live exchange actions.

## Requirements and acceptance

| Requirement | Acceptance criterion | Task | Verification |
|---|---|---|---|
| REQ-001: Consistent responsive forms | AC-001: Inputs and actions remain readable/reachable at 360px mobile, 1280px desktop and enlarged text; no overflow; labels, focus, scroll and validation preserved | T106 | RED-106/GREEN-106; responsive renders |
| REQ-002: Honest asynchronous loading | AC-002: Loading visible during form reads/submits; duplicate submissions disabled; failures clear busy state and retain safe inputs; stale responses cannot authorize work | T106 | pending/error/session tests |
| REQ-003: Automatic direction | AC-003: Long/Short/Long&Short choice sent, persisted, reopened and enforced; opposite-side tampering and request-ID changes rejected; legacy omission remains both | T105/T106 | RED-105/GREEN-105; side UI/API tests |
| REQ-004: Startup and page continuity | AC-004: Loading first Flutter frame before preferences finish, error/retry if initialization fails, then exactly one initialized app; web loading covers bootstrap and disappears at first frame; destination/route changes transition without duplicate interaction or late old-page reads | T107 | RED-107/GREEN-107; navigation/startup tests |
| REQ-005: Accessible bounded motion | AC-005: Reduced-motion uses immediate/static feedback; 48px targets, focus, text scaling and monochrome semantic status retained | T106/T107 | motion/a11y boundary tests and pinned audit |

## Design and interfaces

Design brief: docs/agents/specs/2026-10-09-forms-loading-direction-frontend-brief.md. Reuse native Material widgets and existing tokens; no dependencies.

Form inventory: settings_screen.dart, settings_trade_access_page.dart, support_resistance_screen.dart, fractal_screen.dart, order_filter_controls.dart, position_action_controls.dart, trade_account_controls.dart, strategy_automatic_draft_dialog.dart, strategy_retry_dialog.dart, strategy_settings_dialog.dart, strategy_wizard_dialog.dart. Also align related strategy_screen.dart dialogs, trade_action_confirmation_dialog.dart and order_cancellation_flow_provider.dart. Inventory review must explicitly report every surface covered or already compliant.

Automatic POST /v1/strategies/automatic-drafts accepts existing keys plus optional direction string in {long, short, both}. Null/invalid fails 422 before generation. Normalize absence to both. Filter before provider assessment. Persist direction in aiGeneration and candidate contract, include it in digest and both replay/transactional duplicate comparisons. Return 409 for reuse of a requestId with another direction. Saved generation missing direction means legacy both; malformed stored direction fails closed. Materialization must reject a contract/selection outside saved scope. For both, actual selected direction may be long, short or both.

Client API uses an optional named direction defaulting to both; update every implementation/test fake. UI defaults Long&Short, disables selection during request and rotates requestId on direction change. Validate server direction for new responses while accepting old missing direction only for both. Candidate review cannot broaden a saved single-side scope. Changing parameters invalidates existing preview/selection under existing guards.

Control flow: selected direction -> automatic request -> filtered candidates -> persisted scope -> review/sizing -> existing preview/save/prepare/explicit confirmation/execute. Generation never trades.

## Invariants and edges

- INV-001: Session fencing, confirmation, account ownership, stale-result rejection and server lifecycle evidence remain authoritative.
- INV-002: Single actual side retains 100% total margin; both uses existing split. Long maps to buy and Short to sell; only actual sides receive leverage writes. Two-sided hedge gate remains intact.
- INV-003: No protected file is read, content-diffed or modified. Native tools consume manifests only as opaque input; no package changes.
- INV-004: Loading describes pending work, does not imply success or block recovery. Do not log secrets or values.
- EDGE-001: Empty candidates/instruments, rejected validation, timeout, storage failure, session expiry and cancellation preserve safe recovery and do not place orders.
- EDGE-002: Large text, narrow dialog, keyboard inset and long instrument labels scroll/wrap with reachable actions.
- EDGE-003: Rapid navigation interrupts animation; old subtree cannot remain interactive or initiate late reads; navigation presentation preference changes preserve selected subtree state.

## RED then GREEN contracts

- RED-105: invalid/null side, same requestId changed side and opposite-side materialization fail without generation/order writes. GREEN-105: long/short allowed candidates and execution only; both/legacy remain compatible.
- RED-106: pending/error/session-expired forms cannot submit twice or accept opposite-side response; enlarged narrow forms do not overflow. GREEN-106: all choices reach API, reopen in correct scope and form controls remain usable with visible state.
- RED-107: delayed/failing initialization and rapid navigation/reduced motion cannot expose uninitialized app, duplicate interactions or indefinite decorative animation. GREEN-107: startup loads then hands off, retry recovers, navigation changes show bounded continuity.

## Compatibility, security and rollout

No database migration: existing JSON snapshot is persistence boundary. No new dependencies or external configuration actions. Test exchanges/providers are stubs; preserve permissions and trading confirmation. Code rollout requires normal frontend/backend deployment by owner, not part of this task. Roll back by reverting the feature commit; JSON extra fields are additive and old readers retain existing behavior. No latency/performance benchmark or native-device validation is implied by local tests/web build.

Traceability: requirements table above maps REQ -> AC -> T -> RED/GREEN; the canonical plan maps T to P.
Compatibility refinement D-003: Apple Navigator routes preserve native Cupertino transition/back-gesture; reduced motion settles animations through stable wrappers. Other route fades use exact220ms forward/reverse durations, destinations140ms; all state/interaction invariants remain binding.
