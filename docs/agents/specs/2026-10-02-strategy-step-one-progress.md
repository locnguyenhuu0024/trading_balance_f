# Design Specification: Strategy step-one progress and contract continuity

Status: APPROVED (execution authorized 2026-10-02)
Date: 2026-10-02
Tier: L
Decision Ledger: N/A — use the existing backend 15-second quote policy and strict market metadata invariants.

## Objective and observed state

The user checked a price level in step 1 but cannot press `Tiếp theo`; no error is visible. The wizard currently disables that button when selection validation fails or the public ticker is older than four seconds. It suppresses selection-validation details. A ticker update can also move a selected support/resistance across the current price while leaving the now invisible selection in state.

| ID | Safe code evidence | Observation |
| --- | --- | --- |
| OBS-001 | `strategy_wizard_dialog.dart` `_buildFooter`, `_selectionOrNull`, `_refreshTicker` | Navigation combines selection and four-second freshness checks without a specific disabled reason. |
| OBS-002 | `strategy_market_repository.dart` `getTicker`; `strategy_models.dart` `isFreshAt` | Frontend ticker gate is four seconds. |
| OBS-003 | `backend/strategy.py` `_QUOTE_MAX_AGE_MS` and `_load_market_inputs` | Backend independently fetches a quote and permits up to 15 seconds for preview. |
| OBS-004 | `strategy_market_repository.dart` `getInstruments`; `backend/strategy.py` `_load_market_inputs` | T40 permits blank/missing SWAP `baseCcy`, while backend preview currently rejects it and blank `quoteCcy`. |
| OBS-005 | `strategy_calculator.dart` | Updated market price can move a previously chosen level to the other side of price. |

The user's exact coin/timeframe and quote age are unavailable, so the particular blocking predicate on their device is unconfirmed. The code-level failures above are independently verifiable and define the correction.

## Requirements

### REQ-001 / AC-001 — Explain and unblock step-one navigation

With at least one currently valid selected level and nearest entry per selected side, step 1 can advance to the budget step even if the visible public quote has expired. Advancing does not preview, save, or place orders. If selection is absent/invalid, `Tiếp theo` stays disabled and a visible Vietnamese reason tells the user what to do. A stale public quote has a visible status and retry guidance. Preview, save, and apply continue to require a fresh quote and backend approval. Do not silently treat an invalid entry as valid.

### REQ-002 / AC-002 — Reconcile selections and quote age

When a new ticker changes a level's side or removes it from the current analysis, remove only that no-longer-valid selected level, recalculate the nearest entry for the retained levels, invalidate preview, and show a visible notice asking for selection review. Retained valid choices remain checked. The wizard and strategy market repository use a maximum public ticker age of 15 seconds, matching the existing backend preview gate; the default four-second freshness policy used by other features remains unchanged. Quotes older than 15 seconds, future/out-of-order timestamps, failed refreshes, and unavailable levels still fail closed before preview/save/apply.

### REQ-003 / AC-003 — Preview accepts catalog-valid blank SWAP metadata

For a strict `BASE-USDT-SWAP` ID, the backend derives canonical base from the ID and verifies the live linear USDT SWAP family, settlement, base-denominated contract value, and positive tick/lot/size/value metadata. Missing/blank `baseCcy` and `quoteCcy` are permitted; nonblank values must match the canonical base and `USDT`. Inverse contracts, conflicting metadata, malformed IDs, missing required valuation metadata, or non-live contracts are rejected before draft persistence or any trade write. Existing account, fee, tier, and quote checks remain intact.

## Data and cross-layer contract

| Semantic | Flutter catalog | Flutter wizard | Backend preview |
| --- | --- | --- | --- |
| Instrument identity | Strict `BASE-USDT-SWAP` ID, live linear USDT settlement | Selected ID retained until user changes it | Strict ID/family and current instrument metadata verified independently |
| Optional base/quote metadata | Base may be blank/missing; nonblank conflict rejected | No inference from UI text | Blank/missing allowed, nonblank conflict rejected; `ctValCcy` must equal ID base |
| Public quote age | Up to 15 seconds in strategy repository | Navigation allowed on stale snapshot; preview requires <=15 seconds | Fresh quote fetched independently, <=15 seconds |

No API shape or storage schema change. No authentication, order execution, or batch placement change.

## Invariants and failure semantics

- INV-001: The backend remains authoritative before preview and any live order; navigation alone cannot bypass preview validation.
- INV-002: No selected level is silently reinterpreted as an opposite-side order after a price crossing.
- INV-003: Other app features retaining a four-second quote policy are not changed by the wizard-specific age choice.
- INV-004: No protected configuration/environment file is read or modified.
- Failure to fetch a new acceptable quote shows a reason and prevents preview/save/apply; it does not create or apply a strategy.
- An instrument failing strict backend metadata checks returns the existing unavailable response with zero trade writes.

## RED / GREEN and acceptance

| ID | Scenario | Independently expected result |
| --- | --- | --- |
| RED-001 | Selected valid level, then public quote becomes older than 15 seconds | Step 1 remains navigable; preview refuses the stale quote. Current Step 1 is disabled. A separate 5–15-second case proves the aligned freshness threshold. |
| RED-002 | Selected level crosses the live price on a later ticker | Invalid level is removed or clearly actionable; reason is visible, valid other levels remain. Current hidden selection remains. |
| RED-003 | Preview with blank/missing base/quote metadata from a catalog-valid linear USDT SWAP | Preview succeeds if all other metadata is valid; conflicting nonblank/inverse rows reject with zero trade writes. Current backend rejects blank fields. |
| GREEN-001 | Wizard selection, stale, crossed-level, and no-selection flows | AC-001/002 pass with explanatory UI and retained safety gates. |
| GREEN-002 | Backend preview metadata matrix and existing strategy API tests | AC-003 passes; all existing quote/account/order guards remain. |

## Rollout and limits

Code-only change, no migration or protected configuration action. No production OKX request or live order is part of verification. The exact device-specific predicate remains unproven without the user's selected coin and quote timestamp; the new UI exposes that reason directly if it recurs.
