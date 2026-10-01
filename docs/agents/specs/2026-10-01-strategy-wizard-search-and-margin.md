# Design Specification: Strategy wizard search and margin input

Status: APPROVED (execution authorized 2026-10-01)
Date: 2026-10-01
Tier: M
Decision Ledger: `docs/agents/decisions/2026-10-01-strategy-wizard-input-decisions.md`

## Objective

- REQ-001: Search the loaded USDT SWAP contract list while choosing a strategy instrument.
- REQ-002: Accept positive dot or comma decimal margin input from the wizard and send precise decimal strings for every financial value in preview/save requests.

## Evidence

| ID | Safe source | Observation |
| --- | --- | --- |
| OBS-001 | `strategy_wizard_dialog.dart` `_buildSelectionStep` | The contract control is a full-list dropdown with no search. |
| OBS-002 | `strategy_wizard_dialog.dart` `_validateBudget` | `double.tryParse` rejects the user's iPhone input `100,0`; the failure is reported on Review Orders. |
| OBS-003 | `strategy_selection.dart` `StrategySelectedLevel.toJson` and `toRequestJson` | Selected prices and entries are sent as Dart doubles. |
| OBS-004 | `backend/strategy.py` `_decimal` and `_normalize_contract` | The backend deliberately rejects floats; its selected-level error matches the user's first report. |
| OBS-005 | `backend/tests/test_strategy_api.py` | Existing valid strategy fixtures use decimal strings for selected levels and entries. |

The literal ASCII value `100.0` passes current local budget validation; the user clarified that the failing iPhone value was `100,0`. D-001 resolves the input contract.

## Contract

### REQ-001 / AC-001

The instrument control displays the selected contract and opens a searchable picker. Search is case-insensitive after trimming whitespace and matches either base coin or complete instrument ID. Empty query shows the already loaded list. No match shows an empty-result message. Query edits and dismissal do not change the selected instrument, levels, budget, or preview. Selecting a different instrument closes the picker and calls the existing `_loadLevels` path once, preserving its dependent-state invalidation and stale-response guard. Disable selection while the existing loading/saving states prohibit it. The loaded catalog and its empty/error/retry behavior remain unchanged.

### REQ-002 / AC-002

`100`, `100.0`, and `100,0` in Total Margin all represent a positive 100 USDT margin budget and reach preview with a dot-decimal string. A single decimal comma is accepted for the Long percentage field for the same mobile keyboard behavior. Reject zero, negative, non-finite, mixed separators, grouping separators, multiple separators, suffixes, and malformed input with a local field-appropriate error; no request is sent. Preview and subsequent save use the same normalized margin and percent values. Every selected-level and entry price is serialized as a decimal string, with identical numeric meaning for a matching entry and selected level. Backend float rejection and its financial validation remain intact.

## Design and invariants

- Add a local searchable contract picker patterned after the existing support/resistance picker; filter the in-memory `_instruments` list, without a second OKX catalog request.
- Normalize user-entered comma decimals to dot decimals at the request boundary. Validation uses the normalized value, and preview/save use the same value. Do not interpret comma as a thousands separator.
- Serialize `StrategySelectedLevel.price` and `entryBySide` prices as strings at `StrategySelection.toRequestJson`; do not loosen backend decimal parsing.
- INV-001: No backend, order execution, authentication, leverage, market-data, or stored-strategy semantics change.
- INV-002: Choosing a new coin still resets dependent levels/entry/preview; searching alone does not.
- INV-003: No protected configuration file is read or modified.

## RED / GREEN acceptance

| ID | Scenario | Independent expected outcome |
| --- | --- | --- |
| RED-001 | Open instrument picker, search lowercase base/full ID, then dismiss/select | Matching contracts only; dismiss preserves state; selection loads new levels exactly once. Current picker lacks search. |
| GREEN-001 | Search and choose from loaded catalog | AC-001 passes for empty/matching/no-match query and loading-disabled states. |
| RED-002 | Submit valid selection with margin `100`, `100.0`, or `100,0` | Preview receives valid dot-decimal margin and string prices. Current code rejects comma locally and sends float prices for dot/integer inputs. |
| GREEN-002 | Preview and save request serialization | AC-002 passes, malformed inputs remain local errors, and backend string-decimal fixtures remain valid. |

No public API, schema, dependency, protected configuration, or deployment change is required. No live order request is needed for verification.
