# Trading Balance F — Multi Platform design handoff

Date: 2026-11-07  
Status: Design reference; implementation has not been authorized by this handoff.  
Audience: Claude or another engineer working in this repository.  
Language: English specification; Vietnamese product UI.

## 1. Read this first

Design a mobile trading portfolio application for multiple exchanges, initially illustrated with **OKX and Binance**. The user explicitly chose **one exchange and one account at a time**. There is no combined portfolio or cross-exchange trading operation in this design.

This handoff describes the saved FigCraft design. It does not establish that the Flutter application supports Binance, that exchange capabilities are equivalent, or that the illustrated connections and trading operations are functional. All balances, accounts, prices, positions, credentials placeholders and permission states are illustrative.

Only design artifacts were created for this work. Flutter code and repository configuration were not changed. The earlier single-exchange mobile design was preserved.

Before repository implementation, read the governing `AGENTS.md` and `BASELINE_AGENTS_OptCodex-Personal-v1.2.2.md` in full. Follow their planning, approval, protected-configuration, executor-routing and verification rules. This document is not permission to bypass them.

## 2. Reference package

Paths below are relative to the repository root:

| Reference | Path | Purpose |
| --- | --- | --- |
| Main editable design | `designs/Trading Balance F - Multi Platform.figcraft` | Authoritative visual reference for this handoff |
| Connection flow overview | `designs/Trading Balance F - Multi Platform - Preview.png` | Two picker states, connection management and exchange catalog |
| Earlier mobile design | `designs/Trading Balance F - Mobile.figcraft` | Previous version; retain as a comparison |
| Screen exports | `designs/handoff-assets/` | Eight PNG references for tools that cannot read FigCraft |

The native file contains **49 mobile frames across five screen pages**, plus a sixth page with the design brief and component specimens. Many frames deliberately repeat a layout for different account contexts; they are not 49 separate product features. Four Dark frames are representative examples, not a complete second set of every screen.

Use these image exports alongside this document:

| Image | Contents |
| --- | --- |
| `handoff-assets/01-okx-assets.png` | OKX asset screen and application shell |
| `handoff-assets/02-binance-assets.png` | Same shell with Binance account and different balances |
| `handoff-assets/03-binance-orders.png` | Scoped position list, filters and cards |
| `handoff-assets/04-binance-strategy-setup.png` | Strategy inputs with locked account context |
| `handoff-assets/05-binance-review.png` | Exchange-specific review before submission |
| `handoff-assets/06-binance-confirm-close.png` | Exchange-specific position close confirmation |
| `handoff-assets/07-dark-binance-assets.png` | Representative Dark appearance |
| `handoff-assets/08-account-switch-loading.png` | Clean loading boundary while switching accounts |

The image paths in this table are relative to `designs/`.

## 3. Confirmed product direction

1. Support an extensible exchange/account selection model in the design, using OKX and Binance as the initial examples.
2. Show a single selected exchange/account throughout portfolio, positions, orders, strategies and market analysis.
3. Keep the existing monochrome visual direction and Vietnamese UI.
4. Make the current scope visible before a user acts on trading data.
5. Fix the scope during a strategy draft or trade confirmation. The user backs out of the flow before changing accounts.
6. Show expired connections and read-only permissions as account-specific states.
7. Keep other exchanges as an extension placeholder. The design does not promise support for any named additional exchange.

Illustrated accounts:

| Exchange | Account label | Product label | Example native instrument |
| --- | --- | --- | --- |
| OKX | `Chính` | `USDT Perpetual` | `BTC-USDT-SWAP` |
| Binance | `Futures 01` | `USDⓈ-M Futures` | `BTCUSDT` |

These product labels and symbols belong to the visual examples. Confirm real product catalogs, instrument identity and API compatibility before integration. The display label `BTC / USDT` must not be treated as an exchange-independent execution identifier.

## 4. Information architecture

The fixed bottom navigation has five visible items:

| Label | Destination |
| --- | --- |
| `Tài sản` | Selected account portfolio |
| `Lệnh` | Selected account positions, pending orders and history |
| `Chiến thuật` | Selected account strategies and drafts |
| `Thị trường` | Market data from the selected exchange/product |
| `Thêm` | `Công cụ`: BMAG, support/resistance, connections and settings |

The `Công cụ` screen exposes `BMAG`, `Hỗ trợ / kháng cự`, `Sàn & tài khoản`, and `Cài đặt`. It keeps analytical tools available without squeezing all destinations into the bottom bar.

The existing project's configurable navigation behavior must be inspected before coding. Replacing the displayed navigation does not automatically authorize removing stored navigation preferences.

## 5. Visual system and geometry

### Palette

| Semantic token | Light | Dark |
| --- | --- | --- |
| `bg` | `#FFFFFF` | `#101010` |
| `surface` | `#F7F7F7` | `#1A1A1A` |
| `ink` | `#151515` | `#F4F4F4` |
| `muted` | `#595959` | `#B8B8B8` |
| `border` | `#D6D6D6` | `#414141` |
| `strong` | `#151515` | `#F4F4F4` |
| `onStrong` | `#FFFFFF` | `#101010` |

Use quiet neutral surfaces, thin borders, restrained radii and almost no decorative elevation. Main actions use `strong` with `onStrong`. Signs, Long/Short labels and textual order states carry meaning without depending on color. Exchange and coin badges in the prototype are simple letters, not production brand assets.

### Typography

The FigCraft frames use **Helvetica Neue**, Regular and Bold, approximately 140% line height and tabular figures. Named text styles are Title 24, Section 18, Body 14, Label 12 and Balance 37. Cards also use intermediate sizes such as 15–17 and 23–25.

Some dense prototype labels are 10–11 px, including bottom navigation labels. The design brief's readability and touch-target goals are not proof that every individual layer already meets an accessibility standard. Reconcile compact labels with readable platform text, scaling and measured contrast during implementation. Reuse the application's existing/system font where appropriate; the design does not require adding a font dependency.

### Reference shell

All coordinates are logical design units on a **390 × 844** reference frame:

| Element | Geometry |
| --- | --- |
| Horizontal content inset | 24 on each side; usable width 342 |
| Main page title | Usually x=24, y=62, size 24 Bold |
| Back control on secondary pages | x=12, y=53, 48 × 48; title starts x=68 |
| Exchange/account selector | x=24, y=111, 342 × 54, radius 12 |
| Selector badge | 34 × 34; radius 8; left of two-line account label |
| Main content start | Approximately y=190 |
| Bottom navigation surface | y=744, width 390, height 100 |
| Individual navigation item | 72 × 61, radius 12, spaced across five slots |
| Main buttons | Usually 342 × 48, radius 12 |
| Text input surface | Usually 342 × 52, radius 12, 1-unit border |
| Cards | Radius 12 or 16; neutral surface; optional 1-unit border |

Spacing follows 4/8/12/16/24/32. There are no fixed-height requirements for real dynamic content. Implement safe areas and scrolling rather than copying y coordinates as hardcoded runtime layout. Primary touch targets should be at least 48 logical pixels; small visual chips may need larger hit areas.

The prototype navigation uses a 140 ms dissolve. Production motion must respect reduced-motion settings and existing platform back-navigation conventions.

## 6. Shared account selector

The selector contains a letter badge, exchange name, account label and product label. A chevron indicates it can open `Chọn sàn & tài khoản`.

On a normal data screen, selecting another account leads to a clean loading state and then that account's asset screen. The destination account must be visible during loading; the previous account's balances and orders must not be shown under the new label.

There are separate picker examples for OKX-selected and Binance-selected states. The active row has a stronger border and `Đang xem`; the other row says `Chuyển sang tài khoản này`. `Quản lý kết nối` opens connection management.

In position detail, strategy setup/review, confirmations and scoped trade success, the account bar uses a lock icon and has no account-switch interaction. It remains visible so the user can verify where the action applies.

Filter persistence, last-used screen restoration, saved default account, selection persistence across launches and switching to a non-home destination are not specified by the prototype. Resolve those behaviors before implementation instead of inferring them from static frames.

## 7. Screen specifications

### Assets — `Tài sản`

Show a large account-only balance card: `Tổng tài sản tài khoản`, dominant amount, USDT unit, visibility icon and `PnL chưa thực hiện`. Follow with account scope and display currency rows, then `Tài sản chi tiết`.

Asset rows use a 40-unit coin badge, symbol/name on the left and right-aligned valuation/quantity. For the reference frame, the balance card is 342 × 193 at y=191; asset rows begin around y=549. Long lists must scroll clear of the bottom navigation.

OKX and Binance examples contain different mock balances. Neither is a combined balance. The eye icon communicates a visibility affordance; its complete behavior is not simulated. Reuse the existing application's masking and currency behavior rather than introducing new financial calculations from the mock values.

### Positions — `Lệnh`

Show tabs `Vị thế`, `Chờ khớp`, `Lịch sử`; below them, compact product/filter chips and an account-scoped list label.

Each position card contains instrument, Long/Short, leverage, exchange/account, margin mode, large signed unrealized PnL and a detail affordance. BTC demonstrates the connected detail flow; not every sample instrument card has a separate prototype destination. Tab counts and visible example cards are illustrative.

### Pending orders — `Lệnh chờ khớp`

Retain the same scope bar and order tabs. Cards include instrument, MUA/BÁN, LIMIT, exchange/account, order price, quantity, notional and status. The reference version does not provide a complete per-order cancellation flow; do not infer a trading API contract from these cards.

### Order history — `Lịch sử lệnh`

Use the same scoped shell with compact cards containing instrument, side, terminal status, exchange/account and timestamp. Both exchange examples have their own history frames.

### Position detail — `Chi tiết vị thế`

Keep the account locked and visible. Show Long, margin mode/leverage, signed PnL, native instrument, entry price, current price, liquidation price, quantity and position value. The primary action is `Đóng vị thế`; the secondary action returns to the list.

### Close confirmation — `Xác nhận đóng vị thế`

Repeat the locked account context, prominently show `Chỉ đóng trên OKX` or `Chỉ đóng trên Binance`, and list the native instrument, side and quantity. The main button names the target exchange: `Xác nhận đóng trên …`.

The success destination retains the same exchange/account. This represents a confirmation/result UI, not a new execution method, guaranteed fill, or existing Binance integration. Reconcile pending, rejected, uncertain and expired-confirmation results with real trading contracts before implementation.

### Strategy list — `Chiến thuật`

Show `+ Tạo chiến thuật`, status filters and account-scoped strategy cards. Cards contain instrument, status, exchange/account, direction, signed PnL and order counts, or a draft message such as `Chưa gửi lệnh lên sàn`.

### Strategy setup — `Tạo chiến thuật`

Keep the scope locked. The illustrated two-stage flow has native instrument, Long/Short/Long & Short choices, margin in USDT and leverage, followed by `Xem lại chiến thuật`.

This is a simplified design example, not authorization to remove the existing wizard's price levels, validation, settings or other business rules. The earlier single-platform prototype used a three-stage flow. Resolve the actual wizard contract with the user and repository evidence before replacing it.

### Strategy review — `Xem lại chiến thuật`

Show `Gửi tới …`, account/product, native instrument, direction/leverage, margin and planned order count. The primary button says `Xác nhận gửi trên …`. Switching accounts requires leaving the draft flow. Exchange-specific supported order types, precision, leverage, margin modes and submission mechanisms remain integration questions.

### Market — `Thị trường`

Scope the search and product chips to the selected exchange. Explicitly label `Nguồn giá: …`. Market rows show instrument, price and signed 24-hour change. Do not silently substitute one exchange's quote for another's.

### BMAG

Use account context, instrument/timeframe chips, a dominant price, a simple monochrome candle/fractal chart and upper/lower fractal values. Candle bodies use filled/hollow distinctions. The chart in FigCraft is illustrative geometry; existing BMAG logic and market-source compatibility must be verified separately.

### Support / resistance — `Hỗ trợ / kháng cự`

Show the exchange source, a 3/10 watchlist example and instrument cards with clearly labeled support/resistance columns. The design direction is exchange-scoped market analysis; persistence and identity of watchlists across exchanges/accounts need an implementation decision.

### Tools and settings

`Công cụ` contains four destination cards. `Cài đặt` contains appearance, display currency, time zone, text size and balance visibility. The design does not decide which settings are global versus per-account. Preserve existing settings until that decision is made.

### Connection management

`Sàn & tài khoản` lists connections independently, with exchange/account/product and connection state. Reading data and permission to trade are distinct concerns. The footer action is `+ Thêm kết nối`.

`Thêm kết nối` offers OKX and Binance examples plus a nonfunctional `Sàn khác` extension placeholder. Exchange-specific connection forms show account name, generic connection information, permission summary, `Kiểm tra kết nối` and `Hủy`.

The connection field is intentionally abstract. It is not a specification for an API-key/secret/passphrase schema or credential storage. Confirm the exact authentication model, permission checks and secure storage separately. Forms contain no real secrets; their success screens are simulated.

## 8. Main prototype flows

```text
OKX assets -> OKX account picker -> Binance selection
  -> clean Binance loading state -> Binance assets

Binance assets -> Binance account picker -> OKX selection
  -> clean OKX loading state -> OKX assets

Selected account -> Lệnh -> BTC position detail
  -> exchange-specific close confirmation -> same-account result

Selected account -> Chiến thuật -> Tạo chiến thuật
  -> exchange-specific review -> same-account result

Công cụ -> Sàn & tài khoản -> Thêm kết nối
  -> OKX / Binance form -> exchange-specific connection result
```

The saved file contains 245 routed prototype hotspots. Inputs, filters, search, all direction choices, every sample row, storage and asynchronous behavior are not fully simulated. A click-through prototype is not evidence of live behavior.

## 9. State and boundary requirements

| State | Expected user experience |
| --- | --- |
| Account switch loading | Show target account; clear the former account's sensitive data; display loading |
| Connection expired | Identify affected account and offer connection repair; keep other accounts selectable |
| Read-only account | Permit available read views; make unavailable trading actions understandable |
| No positions | Explain the selected account has no open positions; do not display another account's positions |
| Draft / confirmation | Keep scope immutable and visible until the user exits the flow |
| Trade result | Retain the source exchange/account context |

These are design expectations, not a prescribed cache/store architecture. Late responses from a former account must not appear under a newly selected account. Decide and test the technical mechanism during implementation planning.

Generic read failure/retry, expired draft, duplicate submit, partial/uncertain trade result, permission changes during a flow and keyboard/error focus need to be resolved using existing product contracts. The exported state frames do not exhaust those cases.

## 10. Native file map

| Page | Contents |
| --- | --- |
| `00 · Start here / Multi-platform contract` | Design brief and component specimens |
| `01 · OKX / Selected account` | 15 OKX-scoped mobile frames |
| `02 · Binance / Selected account` | 15 Binance-scoped mobile frames |
| `03 · Exchange switcher & connections` | 10 picker, connection and result specimens |
| `04 · Dark / Account context` | 4 representative Dark frames |
| `05 · States / Account boundaries` | 5 loading, expired, read-only and empty specimens |

Each exchange screen page includes `home`, `orders`, `strategy`, `market`, `more`, `support`, `bmag`, `settings`, `position`, `wizard`, `review`, `confirm`, `pending`, `success`, and `history`, prefixed by `okx_` or `binance_`.

Useful source node IDs in this saved version:

| Example | Node ID |
| --- | ---: |
| OKX home | 2 |
| Binance home | 552 |
| Binance positions | 608 |
| Binance wizard | 1010 |
| Binance review | 1042 |
| Binance close confirmation | 1069 |
| OKX picker / Binance picker | 1199 / 1222 |
| Connection management / catalog | 1245 / 1266 |
| OKX / Binance connection forms | 1283 / 1305 |
| Scoped connection results, OKX / Binance | 1783 / 1796 |
| Dark Binance home | 1415 |
| Binance / OKX switch loading | 1573 / 1809 |

Node IDs identify design layers in this file, not application routes or business identifiers. The shared specimens page contains older generic result specimens with duplicate-looking names (including 1327 and 1339). Prefer the scoped result frames reached by the wired flows; do not implement duplicate screens merely because every specimen exists.

## 11. Implementation boundaries and open decisions

The following are not resolved by this design and need repository inspection and, where material, user clarification:

- Actual Binance backend/client support and exchange-specific API contracts.
- Supported account/product types and instrument catalogs per exchange.
- Credential format, storage, authentication, connection testing and permission verification.
- Account selection persistence, removal/reconnection behavior and account identity.
- Global versus exchange/account-specific settings, filters and watchlists.
- Exact strategy wizard steps and preservation of existing strategy business rules.
- Pending, rejected, partial and uncertain exchange mutations; retry/reconciliation policy.
- Which existing presentation/navigation preferences must remain compatible.

Do not infer business formulas or exchange permissions from mock labels and numbers. Do not treat the one-account scope as permission to drop existing precision, privacy, currency, time-zone, authentication or confirmation behavior.

## 12. Suggested acceptance checklist for a future implementation plan

- [ ] Match the reference mobile shell and both palette modes.
- [ ] Expose all seven product areas through the five-item navigation and Tools.
- [ ] Keep one exchange/account context per data view.
- [ ] Test OKX -> Binance and Binance -> OKX, including late responses and loading boundaries.
- [ ] Preserve full instrument identity, signs, money formatting and masking.
- [ ] Keep exchange/account visible and immutable during drafts and confirmations.
- [ ] Confirm only the selected account's operation; preserve its context in the result.
- [ ] Represent expired, read-only and empty states independently per account.
- [ ] Verify scrolling at narrow widths, long labels, text scaling and with keyboard open.
- [ ] Enlarge chip hit areas where necessary; check semantics, contrast and reduced motion.
- [ ] Preserve relevant existing OKX behavior and tests.
- [ ] Keep mock illustrations separate from verified runtime capabilities.

This is a candidate checklist for the plan, not a claim that implementation or these checks have already passed.

## 13. Prompt to give Claude

Copy the following text into Claude and attach this handoff plus the PNG references. Provide repository access if you expect code analysis. A `.figcraft` file alone may not be readable in Claude's environment.

```text
Help me prepare implementation of the Trading Balance F Multi Platform mobile design.

Read designs/CLAUDE_DESIGN_HANDOFF.md and the supplied PNG references first.
The editable reference is designs/Trading Balance F - Multi Platform.figcraft.

The confirmed product decision is ONE exchange and ONE account at a time.
Use OKX and Binance examples with an extensible exchange selector. Do not add
an all-exchanges aggregate portfolio or cross-exchange trading operation.

Follow the monochrome mobile layout, account scope bar, five-item navigation,
locked account context in trading flows, and account-specific states described
in the handoff. Retain Vietnamese UI labels.

Treat every account, quote, credential placeholder, permission and result in
the prototype as illustrative. Do not assume Binance integration exists or
that OKX and Binance share authentication, instrument or execution contracts.

Before any repository work, read AGENTS.md and the full binding baseline it
references. Respect protected configuration boundaries and the required
planning/approval/executor/verification workflow.

First inspect the relevant allowed repository sources. Present a grounded
implementation plan that separates reusable existing UI from missing exchange
integration contracts. Identify material ambiguities, especially strategy
wizard preservation and account/permission semantics. Ask only questions that
repository evidence cannot resolve. Do not implement until the current plan
has received the explicit authorization required by the repository rules.

Use the handoff as a visual/product reference, not as a backend API spec.
Preserve existing OKX behavior, precision, privacy, authentication, currency,
time zone and explicit trade-confirmation safety unless a change is approved.
```
