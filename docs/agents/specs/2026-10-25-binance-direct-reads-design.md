# Design Specification: Binance direct reads and combined views

Status: IMPLEMENTED
Date: 2026-10-25
Tier: L
Decision Ledger: `docs/agents/decisions/2026-10-25-binance-direct-reads-decisions.md`

## 1. Objective and Decisions
Add direct Binance Spot and USDT-M Futures reads beside OKX on existing screens, identifying every source with its icon and accessible name. D-001..007 fix the revised scope. Revision: 2. No open material clarification. Revision 2 execution explicitly approved by the user on 2026-10-25.

## 2. Current State
| ID | Non-protected source | Observation |
|---|---|---|
| OBS-001 | `lib/core/network/okx_data_client.dart`, `okx_read_scope.dart` | GET-only fixed-origin transport; local credential generations; independent of backend login. |
| OBS-002 | `lib/features/portfolio/data/portfolio_repository.dart`, `lib/features/orders/data/order_repository.dart` | One exchange's balance, positions, pending and recent first-page history. |
| OBS-003 | `lib/features/market/presentation/providers/market_provider.dart`, `lib/core/network/okx_websocket_service.dart` | REST quote polling; bare-coin keys cannot distinguish sources. |
| OBS-004 | `lib/features/market/presentation/market_screen.dart` | USDT Spot, volume >5M, Top 50; percentage baseline is UTC-day open. |
| OBS-005 | `lib/features/fractal_tracker/presentation/providers/fractal_provider.dart`, `lib/features/support_resistance/data/market_repository.dart` | Spot Fractal; Spot/perpetual support/resistance with closed UTC candles. |
| OBS-006 | `lib/features/support_resistance/data/watchlist_store.dart` | v1 bare OKX IDs; ten selections per mode. |
| OBS-007 | `lib/features/orders/presentation/widgets/order_cancellation_control.dart` | Displayed OKX orders can enter backend cancellation. |
| OBS-008 | `lib/features/strategy/domain/strategy_selection.dart` | OKX instrument IDs flow into backend Strategy contracts. |
| OBS-009 | `lib/core/security/secure_storage_helper.dart`, `lib/main.dart` | Native/web credential implementations need independent Binance state. |

Source inspection only; no current-run build/test/live-key result. Initial unrelated untracked `.wrangler/` and `wrangler.jsonc` remain excluded. Protected content was not inspected.

## 3. Scope
In scope: independent Binance credentials/transport/adapters, source-aware display identity/quotes, combined portfolio/orders, account-valuation quotes, progress/error UX and focused regression tests.

Excluded: Binance Market/Fractal/support-resistance/Strategy integration, analytical or watchlist changes, Binance writes, backend changes, COIN-M/Margin/Options/Funding/Earn wallets, visual redesign, new dependencies/configuration, Git mutations/deploy. USDT-settled perpetual and dated contracts map by catalog metadata; no Binance Margin data is synthesized.

## 4. Requirements
### REQ-001 — Independent secure direct reads
Public reads need no credentials/backend login. Signed reads use separate Binance HMAC API Key/Secret, native/web generation fencing and fixed HTTPS origins. GET-only allowlisted routes; no redirects, cookies, backend bearer or OKX headers. Verify destination, method, encoded query and signature at the final adapter. Never log private bodies, credential headers or signed URLs; sanitize errors before scheduler retention. No proxy fallback.

Missing/partially saved/rotating/unreadable keys fail before send. Save/clear start and completion invalidate only that exchange's private reads. Rotation/disposal/cancellation prevent stale publication. Authentication failure does not expire backend login or affect OKX credentials.

Binance persistence uses one versioned bundle value (`BINANCE_CREDENTIAL_BUNDLE_V1`) containing both key and secret, rather than separate writes. Serialize save/clear mutations; validate version and both nonempty strings on every load. Publish a usable generation only after the native write completes or the web write returns true. A native exception/web false result disables private reads in the current session until a successful save/clear, with a sanitized recoverable error. After reload, only a structurally complete persisted bundle is usable; old/new fields can never be combined. Test failure before/after a single storage operation, malformed stored bundle, reload, and concurrent mutations. Existing OKX persistence is preserved rather than opportunistically redesigned.

### REQ-002 — Neutral records and product mapping
Handwritten source-aware display records retain exact decimal text, currency/unit and native identity; preserve original OKX/backend DTOs. Binance must not masquerade as OKX. Read Spot holdings/orders and USDT-M equity, nonzero positions and ordinary/conditional orders. Holdings do not become synthetic leveraged positions. Catalog mapping: Spot -> SPOT, perpetual -> SWAP, dated -> FUTURES; MARGIN remains OKX-only. Hedge identity includes side; net direction uses signed amount. Use symbol-configuration reads for leverage/margin mode absent from position responses. Unknown values remain unavailable rather than fabricated zero. Ordinary/conditional IDs use separate namespaces; linked executions must not double count.

### REQ-003 — All-pair recent history
Snapshot every Spot-enabled symbol returned by exchangeInfo, without a USDT-only/current-balance/open-order shortcut. Union symbols already known in the current in-memory credential generation. Query every captured symbol sequentially using its native recent first page (`limit=500`, no start/end filter). This preserves recent-history scope rather than introducing a lifetime archive. The scan exposes completed/total/failed counts, rows, cooldown and coverage limitations. Publish incremental rows with an incomplete indicator; an empty-history message is authoritative only when all symbols succeeded.

Invalid/delisted symbols remain explicit failures. Deterministic ordering and deduplication use exchange/product/order-kind/symbol/orderId; merged results sort by newest timestamp then those identity fields. Cancel on navigation or key rotation. Resume unfinished symbols only within the same in-memory credential generation. Refresh creates a new scan and rejects obsolete callbacks. Start on History-tab entry/manual refresh, never every render or fast polling. No persisted account-history cache. Catalog omissions and native retention/first-page limits remain visible in history coverage copy; do not promise discoverability of every delisted historical symbol.

Futures recent ordinary/conditional histories are scanned over the captured USDT-settled catalog with native first pages/retention. OKX's existing per-category recent first pages remain intact.

### REQ-004 — Combined account views and partial results
Show one portfolio headline with exchange/wallet details, separate source-labeled asset rows, merged positions/pending/history and existing filters/privacy/currency/timezone/refresh. Do not collapse same-asset rows across exchanges. Exchange/product states load independently; successful data remains visible when another fails or lacks credentials. Totals explicitly show incomplete/stale status whenever a required source or valuation is missing. Missing data never becomes success-looking zero.

Spot equity is free + locked valued by its own exchange's Spot quotes; retain the application's existing USD/USDT reporting convention and VND rate/fallback. Prefer native reported value where available. Missing direct USDT valuation remains unavailable; never borrow the other exchange's price. Futures equity uses native reported margin equity once, retaining its account-mode denomination (USDT versus USD). Do not add position PnL again or sum both an aggregate and its asset components. Preserve collateral detail; unsupported mode/denomination valuation marks the headline incomplete rather than guessing. PnL, ratios, position quantity and notional preserve explicit units.

### REQ-005 — Source-specific quotes for account valuation
Key account-valuation subscriptions/cache/in-flight identity by exchange/product/native instrument. Preserve positive finite values, 15-second freshness, bounded batch polling and inactive ownership cancellation. Binance batch Spot tickers provide its own account valuation prices. No per-position request fan-out or borrowing OKX prices for Binance assets.

These readers serve Portfolio/Orders only. Keep the existing OKX Market, Fractal, support/resistance and Strategy providers, quote facade, calculations, selections and UI unchanged. No merged Top 50, Binance candles, analytical selector or watchlist migration is included.

### REQ-006 — REMOVED
Removed by D-007 before execution approval. The prior Binance analytical parity/watchlist migration requirement is superseded. All analytical screens and watchlist persistence retain existing OKX behavior.

### REQ-007 — Credential UX and backend boundary
Add Binance key/secret editing through current manual/bundle paste, masked summary, edit/cancel/save/clear/error patterns; no passphrase. Keep original OKX storage keys and existing native/web mechanisms. Do not request credentials in chat.

Binance cards have no backend cancel/close/Strategy actions. Only OKX adapters can attach an original OKX DTO; both action entry and UI require explicit OKX provenance before calling existing action flows. Do not infer authority from symbol matching. Existing backend account controls/authoritative target selection and OKX Strategy payloads remain separate and unchanged.

### REQ-008 — Existing visual system
F1: reuse Flutter cards/settings/forms, palette, typography, responsive primitives and locale formatting. Add fixed-size local platform icons with exchange semantics/tooltip; use text when necessary for ambiguous rows/status. No color-only distinction, remote icon dependency or package. Dense history uses lazy construction; progress updates are throttled with accessible announcements. No navigation/hierarchy redesign.

## 5. Data and Cross-Layer Contract
| Value | Grain / unit | Missing semantics |
|---|---|---|
| Instrument | exchange + spot/perpetual/dated + native symbol, base/quote/settlement | Invalid metadata fails explicitly |
| Order | instrument + ordinary/conditional + native ID | Never deduplicate across sources |
| Position | instrument + side + margin mode | Zero amount is not open |
| Balance | exchange + wallet + asset, exact decimal and currency-bearing money | Unknown value is null with reason |
| Quote | instrument + exchange observation time | Remove after freshness deadline |
| Source result | exchange/product/generation + loading/partial/complete/error/cooldown | Empty differs from unavailable |
| History scan | captured symbols, generation, completed/failed/pending counts and rows | Failed/pending prevents completeness |

Worked fixture: OKX equity 100; Binance Spot 2 units at 10 USDT plus 30 USDT cash -> 50; Binance Futures margin equity 45 already includes 5 PnL. Combined equity is 195, not 200. Futures PnL remains 5 currency units rather than 5 multiplied by underlying price. Removing a Spot quote makes the headline incomplete. Identical order IDs on different exchanges yield two rows.

Flow: native exchange -> guarded transport -> native adapter -> neutral records -> source result -> combined providers -> existing rows. Account catalog/quote interfaces retain source identity. Methods accept cancellation; history exposes a cancelable progress session/stream. Aggregate independent states without fail-fast Future.wait. Existing analytical calculators/providers are untouched; native/backend DTOs do not acquire Binance semantics.

## 6. Transport and Scheduling
Spot origin `https://api.binance.com`; Futures origin `https://fapi.binance.com`. Allow only required time/catalog/ticker and signed account/position/order/symbol-configuration read routes. Server-offset timestamps, `recvWindow=5000`, exact encoded-query HMAC-SHA256 and X-MBX-APIKEY. Timestamp rejection allows one clock-resync retry; permission errors do not loop.

Reuse RequestCoordinator patterns in separate Binance scheduling domains. Public/private calls share a host-level weight/cooldown budget. Track catalog limits, endpoint weights, used-weight and Retry-After headers. Reserve interactive reads ahead of sequential scan steps; do not enqueue every symbol ahead of refresh. One history request in flight; at least existing 250ms spacing, slower when budget requires. 429 pauses that host; 418 prevents sends until its deadline. Never clear OKX/backend backoff. When browser headers are unavailable, apply conservative documented weights and spacing. No nested scheduling deadlock.

### Exact read-route registry
All routes below are GET-only, pinned to the named origin; no caller-selected origin or auth flag. Registry metadata owns whether signing is required. Endpoint weights are taken from the official references and recorded as explicit tested registry constants; their host budgets are read from exchangeInfo. User credentials and signed queries never form deduplication/log keys.

| Origin | Public routes | Signed routes |
|---|---|---|
| api.binance.com | `/api/v3/time`, `/api/v3/exchangeInfo`, `/api/v3/ticker/24hr` | `/api/v3/account`, `/api/v3/openOrders`, `/api/v3/allOrders` |
| fapi.binance.com | `/fapi/v1/time`, `/fapi/v1/exchangeInfo`, `/fapi/v1/ticker/24hr` | `/fapi/v3/account`, `/fapi/v3/positionRisk`, `/fapi/v1/symbolConfig`, `/fapi/v1/multiAssetsMargin`, `/fapi/v1/openOrders`, `/fapi/v1/openAlgoOrders`, `/fapi/v1/allOrders`, `/fapi/v1/allAlgoOrders` |

Account-mode read determines the denomination used with the reported account aggregate. Catalog metadata determines eligible USDT-settled contracts. Spot open orders may omit symbol; histories always retain the captured symbol scope even where a Futures route permits broader queries. No mutation, user-data-stream lifecycle, download-link or order-placement route is allowed. Native query limits and source-specific record normalization remain adapter responsibilities under this fixed contract. Candle and trading-day-statistics routes are excluded from the Binance allowlist.

### Verified request weights and query policy
Snapshot: official Binance documentation checked 2026-10-25. Route/auth/weight constants are implementation input, not an invitation for executor API redesign. Stop for coordinator validation if observed documentation/runtime semantics contradict this snapshot.

| Host / route suffix | Weight | Query policy |
|---|---:|---|
| Spot `time` | 1 | none |
| Spot `exchangeInfo` | 20 | unfiltered catalog |
| Spot `ticker/24hr` | 2 for 1..20 symbols; 40 for 21..100; 80 for >100 or all | use explicit batches <=20; one symbol costs 2 |
| Spot `account` | 20 | timestamp/recvWindow |
| Spot `openOrders` | 6 with symbol, 80 without | omit symbol for complete pending view |
| Spot `allOrders` | 20 | symbol, limit=500; omit time/order cursor for recent page |
| Futures `time`, `exchangeInfo` | 1 each | unfiltered catalog |
| Futures `ticker/24hr` | 1 with symbol, 40 without | shared all-symbol snapshot for batch quotes |
| Futures `account`, `positionRisk`, `symbolConfig` | 5 each | no symbol for positions/configuration snapshots |
| Futures `multiAssetsMargin` | 30 | mode, cached per credential generation |
| Futures `openOrders`, `openAlgoOrders` | 1 with symbol, 40 without | omit symbol for pending snapshots |
| Futures `allOrders`, `allAlgoOrders` | 5 each | explicit symbol, limit=500, recent page |

Sources: [Spot general](https://developers.binance.com/en/docs/catalog/core-trading-spot-trading/api/rest-api/general), Spot account/market and Futures account/trade references in section 10; [Futures market](https://developers.binance.com/en/docs/catalog/core-trading-derivatives-trading-usd-s-m-futures/api/rest-api/market-data). Some generated Spot ticker parameter prose contradicts its no-symbol weight row; explicit batches <=20 avoid that ambiguity. No unbounded symbols parameter is sent.

Budgets use every relevant REQUEST_WEIGHT/RAW_REQUEST interval from catalog metadata, reserve 20% for interactive work and cap agent-owned spending at 80% of each advertised interval. History uses the remaining 60%; re-evaluate before each step using response usage/deadlines. Missing/invalid budget metadata pauses the scan with an explicit error rather than an invented quota. Time/catalog bootstrap requests are serialized; charge them when the budget snapshot arrives. Other applications may consume the same IP quota; headers and 429/418 remain authoritative.

History time policy: native recent first page only, without time/cursor filters. Spot supplied time ranges (if added in a separately approved future change) cannot span >24h. Current Futures ordinary/conditional defaults cover recent seven days, and native retention excludes orders older than 90 days plus canceled/expired unfilled orders after three days; reflect these limitations in coverage copy. No Binance candle/history-candle pagination is implemented; existing OKX analytical reads remain unchanged.

Conditional linkage: preserve `algoId`, `actualOrderId`, symbol, `algoStatus` and ordinary `orderId` independently. When a positive actualOrderId matches an ordinary row on the same exchange/product/symbol, display the ordinary execution with its conditional-parent metadata; suppress the duplicate parent row's executable quantity/notional contribution. If the linked execution is absent, retain the conditional row without inventing execution/PnL. Equal numeric algoId/orderId alone never proves linkage. Sort conditional rows by createTime and ordinary rows by time; use updateTime only as status freshness, not creation identity.

## 7. Invariants and Failure Semantics
INV-001: Source/product/generation own credentials, requests, subscriptions and caches.
INV-002: Binance display data never establishes backend authority.
INV-003: Partial totals/history/empty states never conceal missing coverage.
INV-004: Account money, quantities and ratios retain their units.
INV-005: Existing OKX storage, analytical/Strategy contracts, watchlist schema and user selections remain unchanged.

Auth/missing keys -> local actionable error, no repeated private sends. Rate limit -> visible deadline/resumable scan. Invalid payload -> explicit source/item error. Source failure -> other data visible; any retained old value labeled stale. Rotation -> discard old-generation private rows/results. Unknown account valuation symbol -> unavailable value, no cross-source fallback. CORS/network denial -> surfaced source error, no implicit proxy.

## 8. RED / GREEN, Acceptance and Traceability
| AC | Requirement | RED before GREEN | GREEN expected result |
|---|---|---|---|
| AC-001 | REQ-001 | Missing/rotating keys; hostile origin/method/query; timestamp rejection; 429/418 | Fixed-origin signed GET and signed-out public reads; other sources unaffected |
| AC-002 | REQ-002 | Colliding IDs/sides, invalid currency/decimal/metadata | Distinct normalized ordinary/conditional and position records |
| AC-003 | REQ-003 | Symbol failure, cancel/rotation, exhausted budget, stale callback | All captured Spot pairs queried; correct progress and recent sorted rows |
| AC-004 | REQ-004 | Missing source/quote; duplicated futures PnL | Fixture total 195, clear partial state/source breakdown |
| AC-005 | REQ-005 | Different same-coin source prices; stale account quote | Separate fresh account-valuation quotes; existing OKX analytical consumers unchanged |
| AC-006 | REQ-006 | REMOVED by D-007 | No Binance analytical/watchlist change |
| AC-007 | REQ-007 | Binance active limit order enters backend cancellation; failed key save | No Binance backend mutation; independent credentials; preserved OKX actions |
| AC-008 | REQ-008 | Narrow screen/long source labels; keyboard/focus/icon semantics | Accessible labeled rows/forms with no overflow |

REQ-001 -> AC-001 -> P01/T116 -> RED-116/GREEN-116.
REQ-002,003,005 -> AC-002,003,005 -> P02/T117 -> RED-117/GREEN-117.
REQ-004,007,008 -> AC-004,007,008 -> P03/T118 -> RED-118/GREEN-118.
REQ-006 / AC-006 / P04 / T119: REMOVED by D-007. REQ-005 / AC-005 remain implemented by P02/T117 only.

## 9. Compatibility, Performance and Configuration
Additive source adapters first; consumer transitions remain buildable. Preserve an OKX quote facade for unchanged Strategy consumers. No generated native/backend DTO regeneration or watchlist data migration is planned. Synthetic clocks/adapters prove bounded scheduling, interactive priority and absence of render-triggered scans. No live scan-duration/latency claim.

Protected configuration/environment actions: none planned. Never inspect/modify manifests/locks/runtime/deployment files. API keys are user-entered application data. Web build consumes existing settings opaquely. Live authenticated browser/device evidence requires credentials retained on the user's device; report unavailable evidence honestly.

## 10. Official API Evidence
Verified 2026-10-25 without sending repository content:
- [Spot account](https://developers.binance.com/en/docs/catalog/core-trading-spot-trading/api/rest-api/account): symbol-scoped recent history and native limits.
- [Spot REST](https://developers.binance.com/en/docs/products/spot/rest-api): signing, timing and IP-weight/cooldown contracts.
- [Spot market](https://developers.binance.com/en/docs/catalog/core-trading-spot-trading/api/rest-api/market): batch tickers for account valuation; analytical endpoints are excluded from the revised implementation.
- [Futures account](https://developers.binance.com/en/docs/catalog/core-trading-derivatives-trading-usd-s-m-futures/api/rest-api/account): account-mode denominations and symbol configuration.
- [Futures trade](https://developers.binance.com/en/docs/catalog/core-trading-derivatives-trading-usd-s-m-futures/api/rest-api/trade): positions and separate ordinary/conditional readers.
- [Futures general](https://developers.binance.com/en/docs/products/derivatives-trading-usds-futures/general-info): fixed origin, HMAC and rate behavior.

## 11. Rollout, Rollback and Completion
Implement approved T116..T118 only; formal RED before GREEN, affected tests, fresh per-task/final web builds, independent source/action audit and pinned interface audit. T119/P04 is removed and must not be dispatched. No watchlist/schema change. Git release/rollback needs separate user authorization.

Completion requires every active AC (AC-001..005,007,008), buildable task boundaries, explained final diff, unchanged OKX analytical/watchlist behavior, no protected access, no unapproved Git changes and explicit live-verification limitations.

## 12. Revision 2
D-007 removes Binance analytical screens and watchlist migration. REQ-006/AC-006/P04/T119 remain reserved as removed IDs. REQ-005 is narrowed to account valuation quotes; Binance candle and trading-day-statistics endpoints, corresponding tests and migration/rollback work are removed. The user explicitly approved execution of the three remaining task contracts on 2026-10-25.
