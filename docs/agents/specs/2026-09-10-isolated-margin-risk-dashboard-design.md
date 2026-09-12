# Design Specification: Isolated Margin Risk Dashboard

Status: READY_FOR_PLAN
Date: 2026-09-10
Tier: L
Decision Ledger: `docs/agents/decisions/2026-09-10-isolated-margin-risk-dashboard-decisions.md`

## 1. Objective

Replace the Portfolio Home with a risk-first dashboard implementing all 36 sections of the user brief. Within 5–10 seconds, expose current overall state, liquidation buffer, effective leverage, the -10% scenario, True Exit Price, trend, and predefined action status. PnL is hidden by default. The application monitors and explains; it never trades or invents the user's action plan.

## 2. Current State

| ID | Source | Observation |
|---|---|---|
| OBS-001 | `lib/features/portfolio/presentation/portfolio_screen.dart` | Home polls balance every 2 seconds; account equity/PnL precede a coin list. |
| OBS-002 | `lib/features/orders/data/okx_position_model.dart` | Position DTO lacks identity, currency, debt, interest, margin, ratio, and timestamps needed here. |
| OBS-003 | `lib/features/orders/data/order_repository.dart` | Authenticated GET positions already exists; retain Orders contracts. |
| OBS-004 | `lib/features/market/presentation/providers/market_provider.dart` | Spot last-price ticker stream has no risk analytics. Do not use it as a mark-price substitute. |
| OBS-005 | `lib/core/services/background_service.dart` | Existing 1-second balance polling updates a foreground notification with equity/PnL. Replace this behavior. |
| OBS-006 | `lib/main.dart`, `lib/core/timezone/app_time_zone.dart`, `pubspec.yaml` | Riverpod, Dio, crypto, SharedPreferences, local notifications, background service, timezone and Flutter tests already exist. |
| OBS-007 | `test/features/portfolio/portfolio_dual_currency_screen_test.dart` | Existing Home summary assertions must move to the opt-in details view; keep currency behavior. |
| OBS-008 | read-only Git status at planning | Existing edits to AGENTS/framework/templates and deletions of older plans/specs are user changes. Preserve them. |

Inspection is static; no running app, authenticated account, or device notification was inspected during planning. No hypothesis is used as an API guarantee.

### Official evidence (consulted 2026-09-10)

- [OKX API v5](https://www.okx.com/docs-v5/en/): positions/configuration, instruments, fee rates, hourly borrowing rate, accrued interest, candles, funding and open interest endpoint contracts.
- [OKX isolated margin explanation](https://www.okx.com/en-sg/help/vii-introduction-to-the-isolated-mode-of-single-multi-currency-portfolio-margin): old/new asset accounting, collateral currencies and liquidation mechanics. Position assets can exclude margin in new mode and include it in old mode. Ratio declines toward liquidation. This page's liability description and separate-interest formulas are not fully consistent; use the reconciliation contract below rather than blindly adding interest twice.

Thresholds, estimators, market labels, projections and lifecycle rules below are APPLICATION HEURISTICS proposed under A-001, not OKX ratings or recommendations.

## 3. Scope

In scope: all requested metrics and cards; independent Position/Market/Recovery states; hard rules; explanations; volatility; stress and price map; local plan/zone CRUD; event notifications and deduplication; history; since-last-check; daily snapshots; trend/velocity; responsive light/dark Home; data quality and empty/error states; integration with current navigation/currency/timezone.

V1 analyzes one selected long isolated MARGIN position at a time, with USDT as quote/debt currency (the supplied scope). Selector handles multiple eligible positions and remembers the chosen identity. It does not combine their risks. Other quotes/directions/products are listed as unsupported, not silently interpreted. No hard-coded SUI values outside test fixtures.

Out of scope: order placement, repayment, borrowing, automatic deleveraging, server/cloud sync, new external data vendors, deployment, commit/push. Closed-app continuous iOS/Web monitoring cannot be promised by a local-only Flutter app; see §15.

## 4. Decisions

D-001 through D-005 and A-001 in the decision ledger apply. No open product question remains for planning. Exact proposed defaults in this specification become approved only with execution approval of the linked plan. Technical data uncertainty has explicit unavailable behavior, not an executor-selected default.

## 5. Requirements

| ID | Requirement | Failure behavior |
|---|---|---|
| REQ-001 | Select and normalize one actual Long Isolated MARGIN position with coherent timestamps, currencies and old/new accounting. | Empty is distinct from failed fetch or unsupported/incomplete position. |
| REQ-002 | Compute buffer, effective leverage, exposure, debt, equity, maintenance requirement/ratio, sensitivity, True Exit and holding costs. | Missing/unverified inputs produce `-`, never zero or a demo number. |
| REQ-003 | Configurable Position Risk and hard floors; transparent reasons and units. | Partial evidence cannot assert safety or reduce a known adverse floor. |
| REQ-004 | BTC/asset structure, funding, OI/price relationship, volatility and volume pressure produce explainable Market Risk. | Missing market components remain `-`; no bullish substitute. |
| REQ-005 | Recovery Risk and overall aggregation preserve position/hard floors; explain escalation/improvement. | Incomplete states display a partial lower bound, not an unqualified final rating. |
| REQ-006 | Current/-5/-10/-15/-20%, custom levels, liquidation scenario and sorted Survival Price Map. | Nonpositive equity never yields finite positive leverage; liquidation rows are modeled boundaries. |
| REQ-007 | User-authored rules and zones, persistence, edits/deletes, active counts and reminders. | Missing operand is unevaluated, distinct from false; no default trading instructions. |
| REQ-008 | Local snapshots/history, previous check, daily summary, trend and velocity with causes. | No fabricated history across gaps, account changes or position episodes. |
| REQ-009 | Event-only risk alerts, improvements included, persistent anti-spam; replace PnL notification. | Permission/OS/storage failures retain visible in-app events and explicit monitoring status. |
| REQ-010 | Risk-first responsive Home, PnL opt-in details, seven answers near top, neutral accessible language. | Clear loading, stale, partial, empty, offline and unauthenticated states. |
| REQ-011 | Shared engine/policy, single monitoring owner, bounded GET polling, scoped local storage and existing app compatibility. | No duplicated polling/notifications or leakage between accounts. |

## 6. Data Contract

### 6.1 Types, identity and quality

Use independent handwritten immutable risk DTOs under `lib/features/portfolio/data/risk/` and pure domain types under `lib/features/portfolio/domain/risk/`. Do not expand legacy generated Orders DTOs for this feature.

Every numeric observation is nullable, finite, unit-tagged and timestamped, with a source and quality reason. Empty string, malformed text, NaN and infinity become absent. Zero is retained only where meaningful (e.g. interest/rate); zero price/quantity is not a divisor. An explicit zero equity is valid adverse evidence.

Account namespace = SHA-256 of environment + current OKX uid; never API secret or raw API key. Resolve uid from GET account/config. Until resolved, show ephemeral observations but do not load/write another namespace. On credential change clear in-memory state and pending requests immediately; resolve fresh account/config before resuming. Position episode key = account namespace + posId + cTime; require identity for persistence. Same-pair reopened positions never inherit active action rules without user copying them. Persist selected identity; fallback to first eligible instId/posId in lexical order only if selection vanished, visibly announcing the change.

| Field | API / type / unit | Normalization |
|---|---|---|
| mode | config.mgnIsoMode | `auto_transfers_ccy` = new; `automatic` = old; quick/unknown = partial unsupported accounting. |
| identity | positions.posId/cTime/instId/instType/mgnMode/posSide/posCcy/ccy/liabCcy | Eligible: MARGIN, isolated, base posCcy, quote USDT, debt USDT, positive pos; explicit short disqualifies. `net` alone does not prove direction. |
| Qraw | positions.pos, base units | New mode: traded quantity Q=Qraw. Old base-collateral mode: Q=Qraw-margin. Reject Q<=0 from trade calculations. |
| M | positions.margin, ccy units | Base or USDT only. Missing currency blocks conversion. |
| P,A,L | markPx, avgPx, liqPx, USDT/base | P/A/L positive; liquidation L is OKX's supplied estimate, not recomputed from our thresholds. |
| U | positions.upl, collateral currency | Keep reported value with source label; E=(margin+upl) converted using P for base collateral or 1 for USDT. Do not subtract interest again. |
| B,C | total base collateral exposure and quote collateral | New/base: B=Qraw+M,C=0; new/quote: B=Qraw,C=M; old/base: B=Qraw,C=0. Other cases unavailable. |
| reported debt / interest | liab / interest, liability currency | Display magnitudes independently; preserve signs in parser evidence. See reconciliation below. |
| ratio / maintenance | mgnRatio / mmr | Ratio raw 1.5 displays 150%; never multiply before comparisons. Show mmr in returned collateral currency; convert only with explicit ccy. |
| hourlyRate | account/interest-rate matching liabCcy | Nonnegative hourly fraction, not annual/daily. |
| fee | account/trade-fee for MARGIN + exact instId | Select applicable feeGroup/instrument group; legacy taker only when unambiguous. Negative fee -> positive expense; positive rebate -> zero estimated expense with rebate excluded note. |
| settled interest | account/interest-accrued | Attribute only exact isolated instId/currency/episode time range; fully paginate. Missing pages or shared attribution => unknown. |
| market | confirmed candles / public funding / public OI | Each source carries venue, instrument, timestamp, sample window and freshness. Funding/OI use the asset-USDT-SWAP proxy, not the margin instrument. |

Debt reconciliation: `D_implied=B*P+C-E`. Compare with `abs(liab)` and `abs(liab)+abs(interest)` using tolerance max(0.01 USDT, 0.1% of implied debt). If exactly one matches, select it as total outstanding debt D; if both match because interest is below tolerance use D_implied and record precision limitation. Borrow principal `D-I` requires I<=D. If neither matches, display reported debt with reconciliation warning; computed D/principal/holding projections are `-`. Do not infer equity from Q*P-debt alone or from whole-account balances. E from isolated M+U is authoritative only for supported mode/currency with finite values. Keep technical reconciliation detail in metric drill-down.

### 6.2 Metrics and formulas (fractions internally)

- Buffer b = (P-L)/P, display percent. Negative b retained; progress bar clamps 0..100% visually only.
- Trade notional N=Q*P (USDT); effective leverage=N/E for E>0. E<=0 gives unbounded/not meaningful leverage (`∞` with explanation) and CRITICAL. Also show gross asset exposure B*P separately if B differs from Q.
- Trade PnL sensitivity: Q*0.01 USDT per 0.01 USDT price move; Q*P*0.01 per 1% move. Label sign as symmetric +/−; USDT is not silently relabeled USD.
- Equity sensitivity includes base collateral: B*0.01 and B*P*0.01. Show when B!=Q so the stress model does not hide collateral risk.
- Distance to entry=(A/P)-1; distance to true exit=(T/P)-1. Preserve negative values when above a target.
- Current holding projection Hday=principal*hourlyRate*24, H7=7*Hday, H30=30*Hday. Show additional future cost separately from accrued interest. Simple, constant-rate/constant-principal estimate, not guaranteed exchange billing or compounding.
- Holding cost today sums attributable actual interest records within configured timezone's current day; do not present a projected day as paid cost. Partial day coverage displays `-` plus known subtotal in details.

### 6.3 True Exit Price: cost completeness, not false precision

`T=(Q*A + I_lifetime + C_known + F_entry_est)/(Q*(1-f_exit))`, where Q>0 and 0<=f_exit<1. `F_entry_est=Q*A*f_entry` uses current applicable taker rate as an explicitly estimated entry-cost allowance; f_exit is current taker expense rate. Do not call this an exchange guaranteed breakeven or an executable fill price.

I_lifetime is verified settled interest attributed to the remaining position plus unbilled I. Reconcile a billing rollover so it is not counted twice: use interest ledger entries up to position response's server observation, then current unbilled I for that same cutoff; if timestamps do not establish non-overlap the sum is unavailable. C_known is attributable additional actual cost from local verified observations/API; unknown expenses are not zero. Fee allowance is an estimated round-trip allowance; actual opening fees are not added again. Explain this cost model and its limitations in Recovery details.

Completeness: if lifetime attribution is incomplete (position predates available history, changed size before monitoring, ambiguous settled cost ownership, or source failure), full True Exit displays `-`. A secondary `Known-cost exit estimate` may use available I and fee estimates but must not be substituted into T-dependent rules or called True Exit. On newly opened positions with complete ledger coverage and unchanged size, empty confirmed ledger = zero settled interest; additional costs scope is exchange borrowing/trading costs only, no invented external costs. A size increase/reduction invalidates lifetime allocation and T until complete remaining-cost attribution can be established; v1 does not guess allocation. This deliberately favors the user's missing-data rule over fictitious precision.

Between coherent fetches, show an explicitly projected T with additional interest `principal*hourlyRate*elapsedHours`, at most until freshness expires; do not persist that as actual paid interest. Actual T is recalculated from each coherent cost snapshot. Notification materiality uses verified interest-driven changes, not this interpolated display.

### 6.4 Independent synthetic examples

These are test data, not live defaults:

- F1: new mode, quote collateral, Q=100, P=10, A=11, L=6, M=700, U=-200, E=500, reconciled total debt=1200 (reported 1198 plus unbilled interest 2), ratio=4, hourly rate=0.00001, round-trip fee allowance 0.001 each, settled/other verified cost=0. Buffer=40%, N=1000, leverage=2, sensitivity=1 per 0.01 and 10 per 1%, Hday=0.28752. True Exit=(1100+2+1.1)/99.9=11.042042042; distance=10.42042042%.
- F1 at -10%: P'=9, U trade delta=-100, E'=400, N'=900, leverage=2.25, buffer=1/3; position WATCH. -20%: P'=8,E'=300, leverage=2.6666667, buffer=25%, position HIGH. At L=6: buffer=0, CRITICAL; no claim that this model predicts exchange fills.
- F2: same trade with new base margin M=50, U=-20 base at P=10: E=300, B=150. At P'=9, E'=150, N'=900, leverage=6 => CRITICAL. Trade sensitivity=1 per 0.01, equity sensitivity=1.5. This proves collateral is included.
- User reference quantity 5277.5681 yields sensitivity 52.775681 per 0.01. Supplied entry/debt/liquidation alone cannot determine equity or leverage; omit those results unless complete independent inputs are supplied.

## 7. Cross-Layer Mapping

```text
OKX authenticated/public GET adapters
  -> nullable source DTOs + timestamps + account/episode identity
  -> normalized position / market observations
  -> pure RiskEngine + MarketRiskEngine + configurable RiskPolicy
  -> pure ActionPlanEvaluator / RiskEventReducer / History projection
  -> single-owner RiskMonitor + scoped RiskLocalStore
  -> Riverpod view model / Home widgets / platform notification sink
```

No UI widget computes financial formulas. Time and storage are injected. Platform adapters do not duplicate risk algorithms. Snapshots carry policyVersion and source quality so a historical state is not recomputed under today's thresholds.

## 8. Proposed Design and Deterministic Policy

### 8.1 Position Risk and hard floors

All values configurable through an in-app `Risk settings` sheet with validated ordering, units, reset-to-default and local persistence. Position state is maximum of applicable rows; keep all triggered reasons.

| Factor | NORMAL | WATCH | HIGH | CRITICAL |
|---|---|---|---|---|
| Buffer | >45% | [30%,45%] | [20%,30%) | <20% |
| Effective leverage | <3x | [3x,4x) | [4x,6x) | >=6x or E<=0 |
| OKX margin ratio | >300% | (150%,300%] | (110%,150%] | <=110% |
| Buffer / daily vol | >=4 | [3,4) | <3 | no independent critical override |

P<=L overrides to CRITICAL. Unavailable metrics contribute no numeric score. If buffer/leverage/ratio is absent, mark Position partial even if another metric supplies a known lower bound. Missing volatility marks volatility unavailable, not all position metrics absent. CRITICAL remains CRITICAL regardless of missing market data. User edits may tune alert thresholds but never disable E<=0 or P<=L hard critical rules. Rule changes re-evaluate with a `Policy changed` history reason; do not label them market movement.

### 8.2 Volatility and structure

Fetch spot candles for asset-USDT and BTC-USDT. For BTC position reuse the same series without double counting. Confirmed candles only (`confirm=1`), ascending unique timestamp; reject gaps in the required consecutive window.

Daily volatility: sample standard deviation of the last 24 consecutive closed 1H log returns multiplied by sqrt(24). Require 25 closes; zero volatility => multiple `-`, not infinity. Low <3%, Normal [3%,6%), High >=6%. This is a trailing realized estimator, not the 24h high-low range or a probability of liquidation.

Structure: latest closed 4H close C0 vs EMA20 and EMA50. Initialize EMA with SMA of first period, then alpha=2/(period+1); require 100 consecutive closed 4H candles. Support=min(low of prior 20 candles, excluding latest), resistance=max(high of same 20). Breakdown if C0<support*0.995. Recovery if prior close was below its own prior support and C0>=that broken support*1.005. Otherwise Weak/Bearish if C0<EMA20<EMA50, Stable/Neutral otherwise; show Bullish in details if C0>EMA20>EMA50. BTC label uses Weak; asset uses Bearish. A direction is heuristic and names its 4H timeframe.

Volume pressure: latest 4H volume / mean prior 20 volumes >=1.5 plus close<open => Elevated down-volume; close>open => Elevated up-volume; else Balanced. This is a candle proxy, not measured buyer/seller order flow. No volume score if history missing/mean zero.

### 8.3 Funding + OI

Use the matching USDT perpetual only; caption `OKX perpetual context`. If instrument absent, funding/OI are `-`. No substitute instrument or other exchange. Funding never adds holding costs to this MARGIN position.

Use funding normalized to 8 hours: reported fraction*8/actual settlement interval hours (require valid fundingTime/nextFundingTime). Neutral |f8|<=0.0001; Positive (0.0001,0.0005); Strong positive >=0.0005; Negative <-0.0001. Display raw funding interval/rate in details; no solo bullish/bearish classification.

OI change uses oiCcy at now versus nearest sample at or before now-4h within 15 minutes; use corresponding spot closes at these samples (within 5 minutes). Do not use oiUsd change because price mechanically changes it. Before sufficient local history, delta/relationship show `-` even when current OI is available. Price neutral band ±0.5%; OI neutral band ±2%, endpoints included. Otherwise:

| Price / OI | Label | Market points |
|---|---|---:|
| up / up | New leverage entering; squeeze exposure may rise | 1 |
| up / down | Possible covering/deleveraging recovery | 0 |
| down / down | Leverage being flushed; stabilization not confirmed | 0 |
| down / up | New positioning during decline; volatility exposure | 2 |
| either neutral | Mixed/limited change | 0 |

Funding conjunction: strong positive funding adds 1; positive funding + rising OI + price neutral/down adds 1 crowded-long point. Cap combined funding contribution at 1 to avoid counting the same condition twice. Negative funding after >=5% 24H decline is explanatory only (`Short positioning may be increasing`), never a standalone recovery rating.

### 8.4 Market state

Points: asset Breakdown=2, Bearish=1, others=0; High volatility=1; down-volume=1; OI/funding per above. Non-BTC subtotal 0=NORMAL,1=WATCH,>=2=HIGH. BTC Weak/Breakdown increases this by one level capped HIGH; BTC Stable/Recovery/Bullish adds none. For BTC positions classify own structure once and skip extra BTC escalation. Market never produces CRITICAL independently. On missing components keep observed lower bound plus `Partial`; do not assign NORMAL unless required structure/volatility/funding/OI windows are complete (absent swap context remains disclosed unavailable, not neutral).

### 8.5 Recovery and overall

Recovery distance r=max(0,T/P-1): <=10% NORMAL, (10%,20%] WATCH, >20% HIGH. Holding burden = projected additional 30-day interest / E: <1% NORMAL, [1%,3%) WATCH, >=3% HIGH. Recovery=max(available factors), never independent CRITICAL. Missing factors mark partial. Nearby user zones/support/resistance are displayed as context, not app-generated actions.

Overall=max(Position,Market,Recovery,hard floors), using ordinal NORMAL=0,WATCH=1,HIGH=2,CRITICAL=3. These are maximum severity constraints, not an arithmetic score average. Position is the minimum final floor and sole authority for CRITICAL. Bullish observations can remove prior market contributions, reducing Overall only as far as Position/Recovery floors.

If any required component incomplete, header shows the available state plus `Partial assessment` / `at least` qualifier and missing reasons; if none available display `- / Insufficient data`. Never report `Position is stable` from absent data. Show top 3 reasons ordered hard rule, buffer, leverage/ratio, market, recovery, with full evidence in details. Improvements cite cleared factors and before/after values; do not imply unknown means improved.

### 8.6 Stress and price map

Instantaneous frozen-debt, frozen-cost scenarios: P'=P*(1+s), s=0,-.05,-.10,-.15,-.20 plus user custom positive prices, L, entry, T and action-zone boundaries. Deduplicate numerically; current and percentage scenarios stay pinned in order. Custom defaults are proportional scenarios, never SUI-specific price constants.

For each price: estimated trade PnL = current verified quote PnL + Q*(P'-P); if current U is collateral-valued convert U using current P first and label exchange-PnL basis. Equity E'=E+B*(P'-P), not E+Q*delta when base collateral exists. Leverage=Q*P'/E'; buffer=(P'-L)/P'. Recompute buffer/leverage/volatility Position factors. Do not invent future OKX margin ratio; show `-` and retain any current margin-ratio hard floor. Market frozen with explicit label, Recovery recomputed with fixed costs/T. Each scenario shows estimated overall lower bound plus Position detail; scenario is partial when a required input/future ratio is unknown. At/below L show CRITICAL and `At/beyond current liquidation estimate; hypothetical only`.

Survival Map is a vertically sorted list of labeled prices, not a candlestick chart. Include T, entry, current, support/resistance, user zones, stress prices, liquidation and derived buffer boundaries P=L/(1-b) at b=.30 and .20. Label derived boundaries `Buffer 30% / 20%` rather than asserting a whole-risk rating. Coalesce identical levels with multiple labels. Near levels may share a visual row without losing values. Do not clamp the real ordering for aesthetics.

### 8.7 Action plans and zones

A rule has id, episodeKey, enabled, metric, comparison, threshold(s), note, createdAt/updatedAt. Metrics: mark price, buffer, effective leverage, total debt, daily holding cost, price vs True Exit. Operators: <,<=,>,>=, inclusive between; dynamic True Exit supports above/below. Validate finite positive price/debt/cost thresholds, buffer 0..100%, positive leverage, ordered ranges, trimmed label 1..80 and note 1..300 characters. Max 50 rules per episode. No arbitrary executable expressions.

Zones are price rules with user-provided title and optional note; enter/exit uses mark price. CRUD and enabled switches persist. Example templates may prefill neutral review wording but remain disabled drafts until explicitly saved by the user; never activate supplied sample SUI thresholds. No rules => `No plan defined` with Create action, not `No threshold triggered`. Enabled unknown rules => count pending evaluation separately. Active rules => show exact user note as `Your predefined plan` with triggers and metrics. Editing a rule re-evaluates it as a configuration event, not a market crossing.

## 9. Persistence, Monitoring and Event Contracts

### 9.1 Interfaces

- `RiskRepository`: read account context/positions and position-specific rates/costs through existing authenticated infrastructure; GET only.
- `RiskMarketRepository`: candles + funding + OI with explicit instrument mapping and timestamps.
- `RiskEngine.evaluate(position, policy, market, clock)`: immutable evaluation with metrics, component floors, overall, reasons and quality.
- `ActionPlanEvaluator.evaluate(rules, evaluation)`: active/inactive/unknown by id, no I/O.
- `RiskEventReducer.reduce(previous, current, latches, policy, clock)`: events and next latches; no OS calls.
- `RiskLocalStore`: versioned per-account records; read/write error results; never default corrupted data to a fresh silently writable record.
- `RiskMonitor`: serialized capture -> evaluate -> persist event/latches -> publish snapshot -> optional notification; idempotent start/stop.
- `RiskMonitorBridge`: same view-model/command protocol for local foreground owner and Android service owner.
- `RiskNotificationSink`: capability/permission status and delivery; web uses in-app sink only.

### 9.2 Storage/lifecycle

Use existing SharedPreferences for local risk JSON, no new dependency. Native storage is app-local; web uses origin-local storage, not server sync. Do not store credentials, full API payloads or logs in risk records. Account namespace protects accidental cross-account display, not a cryptographic boundary.

Single owner writes evaluation/history/events/latches; action/settings commands go through that same owner. UI reads cached view state and sends typed commands. Android service is owner while available (foreground or background UI); UI never starts a second monitor because a heartbeat is late. If service cannot start, confirm `isRunning=false` before foreground fallback; show background unavailable. Other platforms use the foreground owner; stop sampling on pause. Dispose outstanding timers/subscriptions and invalidate late responses using an owner/account generation token. On Android service/UI reconnect request current state and command acknowledgments; never replay pending mutations blindly. Every command has unique id; duplicate ids return original outcome. Local store writes are serialized.

Storage keys: `risk.v1.<accountHash>.settings`, `.episode.<episodeHash>`; episode record contains rules, levels, current sample, last-check baseline, sampled history, events, summaries and alert latches. Atomic setString per episode record; settings separately versioned. Decode validates schema, finite numbers, units and identity. Corrupt/future schema => read-only error and explicit user Reset local risk data action (with confirmation); do not overwrite. Save failure shows unsaved state and blocks OS delivery until dedupe state persisted; retain prior durable data.

Retention defaults: 15-minute samples for 30 days (max 2880/episode); 1-minute OI samples for 25 hours (max 1500, coalesced); risk events max 1000 and 90 days; daily summaries 90 days; closed episode records 90 days; max 20 recent episodes, oldest closed removed first. Active selected episode cannot be evicted. Persist OI batches once per 5 minutes, immediate flush on controlled stop; no fabricated missing samples. Prune at write, not every render. Expose history clear per episode and policy retention/timing settings.

### 9.3 Previous check, trend and velocity

A check starts on Home entry/resume after >=60 seconds away. Compare first valid current snapshot to the last saved session baseline of the same episode. Freeze baseline for that visit; live refresh does not move it. Save latest valid observed state on departure/pause, not before showing differences. First visit has `No previous check`. Compare buffer in percentage points, leverage, debt, T, structure, funding class, OI delta and Overall; unknown transitions are data-quality changes, not improvements.

Trend baseline = most recent valid sample at/before now-1h within 15 minutes. Deteriorating when Overall rises, buffer drops >=2 percentage points or leverage rises >=0.25x. Improving when Overall falls or buffer rises >=2pp or leverage falls >=0.25x, provided no deterioration criterion holds. Otherwise Stable; deterioration wins conflicts. Need comparable complete positional inputs; absent baseline => `- / Collecting history`.

Velocity = (current buffer%-baseline buffer%)/elapsedHours, baseline at/before now-6h within 30 minutes; use actual elapsed duration. <=-1pp/hour => `Deteriorating fast`, >=1 => `Improving fast`, else trend label from 1h. Require same episode and unchanged position quantity/margin/debt within 0.1%; otherwise label `Position changed`, no price-driven velocity claim. History records the change and resets comparison windows for those trend metrics. Never interpolate through >30-minute sample gaps.

### 9.4 Daily summary

One snapshot per episode/local calendar date at first valid observation at/after 08:00 in app timezone. Show actual capture time; if app opens at 14:00 it is a 14:00 capture, not an invented 08:00 snapshot. No backfill for missed dates. Include three component states, overall, buffer, leverage, today's accrued cost/coverage, major actual change, action count/unknowns, quality. Changing timezone affects future grouping/display; summary identity includes date+timezone and no additional daily OS notification by default.

### 9.5 Events and anti-spam

Every fresh valid transition can create an in-app event/history entry; OS delivery only after durable latch update and permission. Initial observation establishes a baseline without market-crossing notification; currently triggered plan remains visible. One aggregated event per observation can contain multiple new factors.

Events: component/overall state change; buffer boundaries; leverage boundaries; margin boundaries; zone/rule entry and rearm; newly confirmed structure/funding/OI factor; interest-only T rise; explicit user debt/holding-cost rule crossing. Recovery improvements are events too. PnL changes never create events.

State worsening is immediate. State improvement requires 2 fresh consecutive samples >=30 seconds apart. Raw live rating still shows current computed state; only alert confirmation is delayed. In/out threshold oscillations use latches: buffer rearm >=boundary+1pp; leverage rearm <=boundary-0.2x; ratio rearm >=boundary+10pp; price zones rearm after exit by >=0.5% of nearest boundary; debt/cost rearm by 1% on safe side. Other user comparison rules use equivalent units, inclusive boundary rules, and mirrored margins for upward/downward operators. Rearm requires two fresh samples >=30 seconds apart. New more-severe distinct thresholds notify immediately even during rearm of an older one.

Interest-only T event: >=0.25% increase since last notified verified T, same quantity/entry/fee/policy and reconciled attribution, minimum 24h between such events. Price-only changes do not trigger it. Market factor identities include instrument,timeframe,type and confirmed candle time; repeated refresh of same factor produces no event. Factor must clear on a fresh observation before reentry becomes a new occurrence. Reconnection after >5 minutes gap creates one `Risk changed since last observation` event if risk/active rules actually differ; do not assert when during the gap it crossed or replay every intermediate boundary. Same unchanged state after restart produces no notification. No event from a sample older than the last accepted observation, stale source, policy edit or unknown->known recovery alone.

## 10. Invariants

- INV-001: Overall >= Position and every hard floor. CRITICAL cannot be diluted by bullish market.
- INV-002: Missing/stale/unsupported data never becomes zero, NORMAL, Stable or no-action by default.
- INV-003: Margin-risk calculations never use aggregate account equity or futures contract quantity formulas.
- INV-004: No order/borrow/repay API write; action copy belongs to the user.
- INV-005: PnL hidden on each new Home visit/session and absent from notifications; global privacy preference also masks all amounts/quantities without hiding state labels.
- INV-006: One monitor owner and one persisted alert latch writer per active account; no history crossing episodes.
- INV-007: Every reason has factor id, observed value, threshold/window, time and source; snapshots preserve policy version.

## 11. Edge Cases

- EDGE-001: P/L missing, bad strings, zero Q, E<=0, unsupported collateral/mode, posSide net/short, pos=0 funded record => preserve valid raw fields and partial/empty semantics.
- EDGE-002: Mark/position, cost and market ages differ => independent freshness, not a falsely synchronous snapshot.
- EDGE-003: Account switch, selected position closes/reopens, size or debt changes => invalidate old responses/cost attribution and reset incompatible history comparisons.
- EDGE-004: No swap, insufficient candles/OI, duplicate/out-of-order timestamps, zero volatility => unavailable context only.
- EDGE-005: No plan, invalid rule, unknown T, boundary equality, overlapping zones => deterministic validation and active/unknown counts.
- EDGE-006: API 401/429/offline; store corruption/write failure; denied notification; Android service loss => explicit capability/quality state, no fake continuity.
- EDGE-007: Small viewport, large text, dual currency, hidden values, light/dark, floating navigation => readable scrollable layout without clipped controls.

## 12. Failure and Freshness Semantics

Position refresh 15s while Home visible; 60s when Android monitoring without Home. Each completion schedules next, no overlapping requests. Freshness uses successful fetch time and source server timestamp when meaningful; unchanged position.uTime alone does not make a newly fetched position stale. Position/mark stale after 120s without successful refresh. Market refresh 60s; stale after 5min failed refresh; candle completeness uses expected last closed interval. Rates/fees/config refresh 1h; stale after 2h (account identity refresh immediately on credential change). Cost ledger refresh 5min, stale after 10min. Cached values can be shown with age; exclude stale factors from new events, preserve last known risk as visibly stale, and never announce risk improved because inputs disappeared.

API code errors preserve last good state; 401 stops authenticated polling until credentials change/manual retry, 429/network use 30/60/120/300s capped backoff (respect longer Retry-After). Success resets backoff. All new requests have 15s timeouts and cancellation/generation guards. Pull-to-refresh joins/coalesces in-flight work; it does not multiply polls. No stale source emits alert; no logging of authenticated headers/payloads by new adapters.

## 13. RED / GREEN Behavioral Contract

| Pair | RED (execute first; expected negative/boundary behavior) | GREEN (execute second; expected success) |
|---|---|---|
| RED/GREEN-001 | Invalid mark => buffer `-`; E=0 => CRITICAL; missing/ambiguous debt never coerced; new base margin F2 proves stress includes collateral. | F1 exact metrics/T/holding and -10/-20 scenarios; old/new mode and signed debt fixtures reconcile independently. |
| RED/GREEN-002 | Bullish market cannot reduce CRITICAL; absent OI/zero-vol/incomplete candles cannot be NORMAL; funding alone cannot say Bullish. | Four price/OI quadrants; 4H break and recovery; configured factor points; WATCH position + HIGH market => HIGH with traceable reasons. |
| RED/GREEN-003 | Repeat identical/restart/threshold jitter => no duplicate; failed storage => no OS intent; unknown rule is not inactive; account/episode isolation. | Save/reload rules, threshold entry, stable rearm, improvement, 1h/6h trend, last-check freeze, late daily capture and retention under injected clock. |
| RED/GREEN-004 | Empty/error/stale/partial view, hidden PnL semantics, no plan, malformed rules and 320px at 200% text => no false safety or overflow. | F1 Home shows seven answers, -10 card, working drill-downs/editors/map/history/details, dual currency and navigation preserved. |
| RED/GREEN-005 | Denied capability, service crash/restart, duplicate owners/commands, 401/429 and out-of-order account response => no PnL alert or duplicate writer; failed latch write => no delivery. | Serialized GET monitoring -> persisted event -> one fake OS delivery; Android bridge/foreground owner parity; final integrated fresh transition and improvement. |

Formal RED means a negative/boundary scenario with the specified expected result; it is not a claim that an arbitrary test suite must fail. Restart RED then GREEN after implementation/test-support changes per governing user instructions.

## 14. Performance Contract

Fake-clock tests prove bounded poll counts and no overlap over 5 minutes with slow responses; one cadence per owner, independent caches, no 1/2-second loops added. Domain evaluation is linear in <=50 rules and bounded snapshots; render only latest snapshot and lazily build history lists. API history retrieval is paginated with a maximum 100 pages per initial attribution attempt; if limit or 1-year endpoint boundary prevents complete coverage, show `-` and incomplete costs rather than claim completeness. No full-history query per ticker. Persist samples at cadence/events, not widget builds.

## 15. Compatibility and Platform Matrix

Preserve Orders/Market/Fractal functionality, navigation modes/positioning, app text scale, light/dark, timezone and USDT/VND/dual currency. Risk prices/rates keep USDT/native units; optional VND conversion is presentational and never enters formulas. Preserve legacy account balances inside explicit `Portfolio details`; remove top-level summary assertions only by relocating and testing them there. Retain `hideBalanceProvider` / `isDarkModeProvider` import compatibility.

| Platform | Monitoring | Notification |
|---|---|---|
| Android | existing foreground service becomes risk owner, including while UI visible | persistent generic service status (no PnL), separate risk events when permission allows; OS may suspend/stop service, show last update/gap on resume |
| iOS | foreground/resumed app monitoring; no claim of continuous closed-app polling | native local events while executing, permission-dependent; suspended gaps explicit |
| Web | active foreground page only; stop on pause | in-app event center; no background push/server and no permission workaround |
| Desktop | foreground owner | in-app events as baseline; no new background service expectation |

Do not add native entitlements, backend or packages to imply guaranteed background execution. Runtime device testing is separate from mocked Dart capability tests and must be reported honestly.

## 16. Security and Permissions

Use existing credential helper/interceptor with a dedicated risk Dio instance without verbose LogInterceptor. Public context requests do not attach private auth headers. No new external service, repository upload or telemetry. Tests use synthetic fixtures/fake adapters only. No actual credential reads or private API calls needed for implementation verification. User action text is rendered as text, never executed. Notification payload includes only account/episode/event hashes, not credentials. Hide numeric amounts in OS alerts when existing privacy setting enabled; always exclude PnL.

## 17. Rollout / Rollback

After approval implement five serial audited tasks, then integrate. No install/deploy/publish/Git mutation implicit. New risk keys are versioned and isolated from existing preferences; no destructive migration of balances/settings. Rollback, if explicitly authorized, restores previous Home/service implementation while retaining risk keys for a later compatible version. Trigger: wrong accounting, duplicated alert ownership, privacy violation or incompatible navigation. Never delete user edits as rollback.

## 18. Acceptance Criteria

- AC-001: Eligible long selection/empty/error/unsupported/account isolation use actual DTOs with unit/freshness evidence (REQ-001,011).
- AC-002: F1/F2, raw reference sensitivity, invalid inputs and fee/interest completeness prove all mandatory metrics and missing-data behavior (REQ-002).
- AC-003: Exact 20/30/45% boundaries, leverage/margin overrides and configurable validation; CRITICAL floor always wins (REQ-003).
- AC-004: Market sources/proxy labels, volatility estimator, BTC modifier, four OI quadrants and funding conjunctions deterministic (REQ-004).
- AC-005: Recovery burden/distance and max aggregation with partial qualification/reason changes (REQ-005).
- AC-006: Default/custom stress rows and map ordering; base collateral sensitivity and E<=0 behavior; -10 summary accessible on Home (REQ-006).
- AC-007: Rule/zone CRUD, local reload, unknown/active counts, neutral copy and no trading APIs (REQ-007).
- AC-008: Last check/trend/velocity/history/daily summary and pruning under controlled time, with explicit gaps (REQ-008).
- AC-009: Fresh worsening/new threshold/improvement create one durable event; repeated refresh/restart does not spam; no PnL notifications (REQ-009).
- AC-010: At 390x844 with normal text, selected pair, overall/position qualifier, trend, buffer, leverage, debt, T, -10 status and plan status are visible within the first viewport or one short continuation; at 320px/200% scale readable via scroll with zero overflow. Details intentionally lower priority (REQ-010).
- AC-011: Single monitor, bounded requests, stale/offline and capabilities accurate; affected existing tests pass (REQ-011).

## 19. Traceability to the Entire User Brief

| User sections | Requirement / acceptance | Plan / task | Verification |
|---|---|---|---|
| 1,10–13,18,30–36 | REQ-010 / AC-010 | P04/T21 | RED/GREEN-004 |
| 2,4 | REQ-001,002 / AC-001,002 | P01/T18 | RED/GREEN-001 |
| 3,5–9 | REQ-003,004,005 / AC-003,004,005 | P01/T18,P02/T19 | RED/GREEN-001,002 |
| 14,15 | REQ-006 / AC-006 | P01/T18,P04/T21 | RED/GREEN-001,004 |
| 16,17 | REQ-007 / AC-007 | P03/T20,P04/T21 | RED/GREEN-003,004 |
| 19,20 | REQ-009,011 / AC-009,011 | P03/T20,P05/T22 | RED/GREEN-003,005 |
| 21,26–29,34 | REQ-008 / AC-008 | P03/T20,P04/T21 | RED/GREEN-003,004 |
| 22–25 | REQ-004 / AC-004 | P02/T19,P04/T21 | RED/GREEN-002,004 |

## 20. Completion Gate

- [x] Material proposal authority recorded; no open product question for planning.
- [x] Configurable defaults, missing data and financial semantics documented.
- [x] Failure, ownership, platform and rollout limits explicit.
- [x] RED/GREEN independent fixtures and all 36-section coverage defined.
- [ ] User approves canonical plan/checklist before code changes.
- [ ] All five tasks audited PASS and integrated checks observed.
- [ ] Screenshots/device limitations and final diff audited; no unexplained changes.

## 21. Visual Layout Contract

Retain native Flutter and current neutral light/dark surfaces, system typography, existing currency formatters and Material icons. Use 16px compact padding, 12px gaps/radii and bordered low-elevation cards; neutral surfaces, colored state label/icon/border only (NORMAL green, WATCH amber, HIGH orange, CRITICAL red with contrast-appropriate text). No decorative hero art or new font dependency.

Mobile order: compact pair/selector + ISOLATED LONG; Overall badge/trend + explicit Position/Market/Recovery chips; buffer hero (40px figure, current/liquidation, small segmented bar, volatility multiple); 2x2 metric grid (leverage, debt, T, -10 scenario summary); active-plan strip; top reasons; since-last-check; Market; full Stress; Exposure/Recovery/cost; Survival Map; plan editor/list; history/daily; collapsed Portfolio Details with masked PnL and deliberate Show control. Above-fold blocks prioritize concise labels and accessible tap targets; details use bottom sheets. Header risk includes partial/stale text where needed even if it adds height.

At >=900px max content width 1280, use 2 columns: risk/metrics/stress left (3 parts), market/action/recovery right (2 parts), history/map below. Under 900px single column with responsive grids; stress table becomes stacked selectable scenario cards on small widths. Preserve global NavigationContentFrame; add scroll trailing clearance for floating navigation without changing navigation layout policy. User-authored rules/settings are native sheets; no additional top-level navigation destinations.

PnL Show affects only the explicit details session, resets on next Home visit, and cannot bypass global hidden-balance setting. Screen-reader semantics must not contain the hidden numbers. Use explicit +/- pp for buffer change, x for leverage, timestamp for source freshness. No BUY/SELL/DCA/CLOSE suggestion is generated.
