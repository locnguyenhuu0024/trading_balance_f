# Design Specification: Strategy preview market correction

Status: IMPLEMENTED_AUDITED
Date: 2026-10-02
Tier: L
Decision Ledger: `docs/agents/decisions/2026-10-02-strategy-preview-market-correction.md`

## 1. Objective

Make SOL-USDT-SWAP/H6 and other valid strategy previews complete with current OKX data, preserve every selected limit order (including two orders at one rounded price), and keep two-sided strategies genuinely two-sided. Fetch a public quote once when a coin is opened in the wizard; poll only visible, running strategies. The server remains authoritative when previewing, saving, preparing, and applying.

## 2. Current State and Evidence

| ID | Source | Observation |
| --- | --- | --- |
| OBS-001 | User's browser Network capture | Authenticated `POST /v1/strategies/preview` for SOL-USDT-SWAP/H6 returned 502 after about 983 ms. Nginx access log showed OPTIONS 204 then POST 502. |
| OBS-002 | Public OKX `position-tiers` response for SOL-USDT isolated SWAP, read-only | Returned valid tier rows without per-row `instType` and `tdMode`. The request itself pins those parameters. |
| OBS-003 | `backend/strategy.py`, `_load_market_inputs` | Rejects every tier row without both per-row fields, raising `preview_inputs_unavailable` 502. |
| OBS-004 | User payload and `strategy_calculator.dart` / `strategy_models.dart` | A selected price serializes as `115.63499999999999`; SOL's observed public `tickSz` is `0.01`. Backend separately rejects off-tick prices with 422. |
| OBS-005 | `strategy_wizard_dialog.dart` | Starts a one-second ticker timer, invalidates previews after a 15-second UI quote age, and allows Both with only one selected side. |
| OBS-006 | `strategy_dashboard_provider.dart` | Polls quote once per second for every listed strategy, including drafts, while the page is visible. |
| OBS-007 | `backend/strategy.py` and Flutter selection model | Same-side, same-price selected levels are rejected or merged by price identity. |

The tier mismatch is the evidenced cause of the reported backend 502. The floating-point price is a separate failure that would surface after that correction. The missing CORS header on the observed 502 obscured the server error in Flutter; this specification does not assume an unverified Nginx fault.

## 3. Scope and Decisions

In scope: tier parsing, exact level price normalization, stable level identity, grouped same-price liquidation estimates, mandatory two-sided selection, wizard quote lifecycle, and running-strategy quote filtering. Out of scope: Nginx/Cloudflare/container changes, auth changes, order type or margin mode changes, automatic trading without final confirmation, and unrelated market screens.

Resolved decisions: Long prices round down and Short prices round up to current OKX tick; keep separately selected levels as separate orders even when rounded prices match; model liquidation after the whole same-price group with a clear fill-order caveat; Both requires at least one Long and one Short selected limit order and one nearest entry on each side; the wizard fetches a public ticker exactly once on opening a coin, with no timer; the server still refreshes and validates market data for preview and order actions; live quote polling is for visible, started strategies only. Open material questions: none. Authorized assumptions: none.

## 4. Requirements and Contracts

### REQ-001 — Live OKX isolated tiers

Accept absent, null, or blank per-row `instType`/`tdMode` when the already pinned `position-tiers` request succeeds. Reject a present conflicting or malformed value. Continue requiring exact `instFamily`, valid positive sizes/leverage and `0 <= mmr < 1`, a nonempty tier set, and unique matching tier. Return a structured backend error for invalid data. Never submit an order from invalid market metadata.

### REQ-002 — Exact prices and distinct level identity

Retain candle OHLC and ticker decimal text and OKX tick text through level calculation. Perform median and tick quantization in decimal integer units, before display or request serialization. Long uses floor; Short uses ceiling. Render and send the same canonical decimal price, with no binary-float artifact. Assign each source level a stable, unique, bounded `levelId` for this analysis snapshot before quantization. Selection and entry radios use IDs; exactly one entry ID per selected side; nearest-price entry is mandatory, with an explicit ID resolving equal-price ties. Limit the selected *rows/orders* to 20.

The new API request adds `direction` (`long`/`short`/`both`), `levelId` to each selected level, and `entryLevelIdBySide`. ID mode is all-or-none; IDs are unique ASCII strings matching `^[A-Za-z0-9_-]{1,128}$`, each entry ID belongs to its side, and `direction` must equal the submitted side set. If legacy `entryBySide` is also provided, its price must match the chosen ID. Preview, stored orders and execution results carry `levelId`. Deterministic sorting is Long then Short, numeric price then ID; preview sequence is Long descending and Short ascending, with ID tie-break. Persisted client order IDs are mapped and reused by level ID in the new mode, including retries/reconciliation; raw ID text is never used as an OKX client order ID. Legacy requests and persisted drafts without IDs retain their prior price-based normalization and preview hash so they remain usable; they continue to reject duplicate side/price pairs.

### REQ-003 — Two-sided execution and grouped estimates

The Both wizard option cannot advance unless Long and Short each have a selected order and nearest entry. Backend ID mode validates exactly the submitted sides and cannot silently reduce a requested two-sided contract to one side. Hedge-mode preflight remains mandatory. When two same-side orders have the same limit price, calculate and display liquidation after the entire same-price group is assumed filled; rows in the group share that group estimate and receive an additive `liquidationEstimateNote` explaining the group assumption and that OKX fill order is not guaranteed. Keep the two separate limit orders in the batch, with distinct client IDs, and retain the 20-order cap. Existing isolated, separate Long/Short leverage and final confirmation rules remain.

### REQ-004 — Quote lifecycle

`loadLevels` takes one public ticker snapshot when a coin/timeframe analysis opens. The wizard has no periodic public ticker or freshness timer, no automatic extra ticker call on Step 1/2/3, and no 15-second UI gate that disables preview/save/apply. Show the initial quote as a timestamped *reference*; show the backend preview quote as authoritative for order review. Server preview/save/prepare/apply continue their existing fresh-quote, account, balance and position checks; stale/changed data yields a visible structured retry/review error, not silent acceptance. A user-initiated coin/timeframe reload begins a new analysis and may fetch its own single quote. The visible dashboard polls every second only for strategies whose application has started (`APPLIED`, `PARTIAL`, `UNKNOWN`); drafts and prepared-only strategies receive no periodic public ticker calls. Existing visibility and backoff behavior remain.

## 5. Cross-Layer Mapping and Invariants

| Semantic | Source / backend | API / persistence | Flutter |
| --- | --- | --- | --- |
| Price | Exact OKX decimal strings, server `Decimal` | Canonical tick-aligned decimal text | BigInt decimal calculation; one canonical text for card/selection/request |
| Level identity | Bounded unique opaque ID | `levelId` in selected rows, preview, stored and result orders | Stable per analysis snapshot; map and radio keyed by ID |
| Entry | Nearest selected level per side | `entryLevelIdBySide` in v2; `entryBySide` in legacy | One radio per required side |
| Quote | Fresh server ticker at each protected operation | Preview timestamp/price | One initial public quote for analysis; backend quote shown on review |
| Active status | Application attempt status | `APPLIED`/`PARTIAL`/`UNKNOWN` | One-second visible-page quote polling only for these statuses |

INV-001: Previewed and submitted orders use exactly the displayed quantized prices and quantities. INV-002: In Both mode, accepted preview and batch each contain at least one Long and one Short. INV-003: A unique selected ID maps to one order and one stable client order ID, even at an equal price. INV-004: No backend market validation is weakened by removing frontend polling. INV-005: Existing no-ID drafts remain loadable and prepareable with their original hash.

## 6. Edge and Failure Semantics

| Case | Expected result |
| --- | --- |
| Tier row omits optional duplicated request fields | Valid row accepted after all other checks. |
| Tier row explicitly conflicts with SWAP/isolated/family or numeric guards | Structured 502; no order action. |
| Exact median lies between ticks | Long floor, Short ceiling; canonical displayed/request price. |
| Two source levels round to same side/price | Two distinct rows/orders; group liquidation estimate; explicit fill-order caveat. |
| Invalid/duplicate/missing `levelId`, mismatched entry ID/price, >20 orders | Structured validation failure before side effects. |
| Both selected with only one side | Step 1 cannot advance; explanatory UI message. Backend v2 also rejects malformed two-sided contract. |
| Initial reference quote ages while user fills Step 2 | Wizard remains usable; server obtains its own fresh quote for preview. |
| Backend quote or preview changes at save/prepare/apply | Existing stale/conflict flow requires renewed review; no silent order submission. |
| Draft-only dashboard | No periodic ticker calls. |

## 7. Verification Contract

RED-001: Existing backend tier test rejects a valid missing-field OKX tier response; GREEN-001: preview succeeds for that response and still rejects conflicting/malformed fields.

RED-002: Existing calculator/selection path emits an off-tick floating artifact or merges equal rounded prices; GREEN-002: exact-source decimal test yields correct directional rounding, canonical text, two IDs and two distinct orders.

RED-003: Both mode with one side can advance and dashboard polls a draft; GREEN-003: Both cannot advance, backend v2 cannot silently infer one side, and only started strategies poll while visible.

RED-004: Wizard makes an additional ticker call after initial load or disables preview after 15 seconds; GREEN-004: no timed wizard calls, reference quote may age, backend preview still checks a fresh quote and save/apply retain server preflight.

Test legacy draft/hash compatibility, reordered request determinism, 21st-order rejection, same-price entry selection, separate Long/Short order payloads, retry/reconciliation ID stability, and authenticated error handling. Unit/fake tests must not submit live orders.

## 8. Performance, Compatibility, Security, and Rollout

Wizard public ticker requests: one per coin/timeframe load, zero timed calls. Visible dashboard: up to one public ticker request per unique instrument per second for started strategies, preserving existing overlap/backoff guards; zero for drafts. Numeric calculation must remain bounded by the existing <=500 candles and <=20 selected orders.

No database migration or protected configuration action is planned. New fields are additive; legacy draft JSON and hash behavior are preserved. Auth/session and preflight remain unchanged. Deploy backend compatibility first, then Flutter; verify focused tests and canonical backend/web builds before requesting separate commit/push/deploy authorization. Roll back application code together if new ID compatibility or order identity verification fails; never rewrite an in-flight strategy.

## 9. Acceptance and Traceability

| Requirement | Acceptance criterion | RED/GREEN |
| --- | --- | --- |
| REQ-001 | AC-001: Valid live SOL tiers without row type/mode produce preview; explicit conflicts still fail safely. | 001 |
| REQ-002 | AC-002: Tick-aligned canonical prices, two equal-price levels remain two orders, old drafts preserve hashes. | 002 |
| REQ-003 | AC-003: Both mode requires and submits separate Long/Short orders; grouped estimates are labeled. | 003 |
| REQ-004 | AC-004: Wizard makes one initial public ticker call and no timed calls; drafts are not polled; backend still checks fresh data. | 004 |

Completion: all material questions were resolved and frontend/backend workstreams reconciled. The user authorized T46–T49 in two execution phases; each task passed local audit, with one T49 display remediation and one final analyzer cleanup. No protected configuration content was used and no external configuration action was required. Production verification awaits a separately authorized deployment and safe retry.
