# Decisions: Multi-platform view-only restructure

Status: ACTIVE
Specification: `docs/agents/specs/2026-11-07-multi-platform-view-only-design.md`
Plan: `docs/agents/plans/2026-11-07-multi-platform-view-only.md`

All D-* entries are explicit user answers in chat on 2026-11-07. Quoted text is the user's own wording where the user typed free text.

## User Decisions

### D-001 — One exchange and one account at a time
Source: `designs/CLAUDE_DESIGN_HANDOFF.md` section 3, confirmed product direction; request to follow the design.
Decision: Every data view shows one exchange/connection. No aggregate portfolio across exchanges.
Impacts: REQ-005, REQ-009.

### D-002 — Start from main; disregard earlier branches
Decision: "từ main, không cần bận tâm những nhánh khác đã làm trước đó. tôi muốn làm lại từ đầu."
Consequence: `codex/binance-direct-reads` and `codex/multi-user-okx-binance-plan` are not merged, cherry-picked or used as design sources. They stay untouched. Decisions recorded only on those branches (including its D-007 on OKX-only analysis) do not bind this plan.
Impacts: all tasks.

### D-003 — View-only application; backend disconnected
Decision: "Tạm thời ngắt kết nối đến backend đi, các chức năng liên quan cũng ẩn đi. App hiện tại sẽ quay về mục đích chỉ xem. Toàn bộ kết nối đều trực tiếp đi thẳng tới các sàn."
Consequence: No client request reaches the private backend. Trade login, position actions, order cancellation, close-all and Strategy are hidden. "Tạm thời" means code is retained and gated.
Supersedes the earlier answer "Binance read-only" by making read-only true for every exchange, and makes the question of matching the device OKX key with the backend trading account moot while the backend is disconnected.
Impacts: REQ-001, REQ-002, REQ-003, T116.

### D-004 — One connection per exchange
Decision: One connection per exchange now, identified by a stable connectionId so that a later expansion does not redesign the scope model. Existing OKX storage keys stay; no secure-storage migration.
Impacts: REQ-004, REQ-009.

### D-005 — Analysis screens follow the selected exchange
Decision: Market, BMAG and Support/Resistance use the selected exchange and show the price source. Watchlists are per exchange; the existing one belongs to OKX.
Impacts: REQ-008, T118.

### D-006 — Existing strategy wizard preserved
Decision: Keep existing business rules; do not rebuild it as the design's two-step flow. While D-003 holds, Strategy is unreachable and its code is unchanged.
Impacts: REQ-002 preserved behavior.

### D-007 — Fixed navigation; customization removed
Decision: Fixed navigation replaces reorder, hide and floating options. Customization UI and code are removed. The stored value is ignored and its storage key is not touched.
Impacts: REQ-003, T116.

### D-008 — Remember selection; reset filters
Decision: The selected exchange persists across launches. Filters reset when switching. Appearance, currency, time zone and text size are global.
Impacts: REQ-005, REQ-009.

### D-009 — Binance products
Decision: USDⓈ-M, Spot and Margin (cross and isolated). On web only USDⓈ-M private data is available, and the screen says that Spot and Margin are app-only.
Evidence: curl CORS preflight with `x-mbx-apikey`, 2026-11-07, see OBS-010.
Impacts: REQ-006, T119, T120.

### D-010 — Binance order history coverage
Decision: Automatically load at most 10 symbols taken from held assets, open positions and the Binance watchlist; the screen states this scope. Orders for symbols no longer held do not appear.
Impacts: REQ-007, T119, T120.

### D-011 — No external planning service
Decision: Curated packets are not sent to GPT-6.1 Sol. Independent workstreams use Claude subagents, and the plan records that the Sol route was not used.
Impacts: plan fan-out record.

### D-012 — Reclassify tasks under new executor rules
Decision: "Ngoại trừ task đang chạy, hãy lập lại task theo bộ rules cho executor mới."
Consequence: T116 keeps its dispatched route. Later tasks use `EXECUTOR_ROUTING_POLICY.json` v2. Route changes need fresh approval, per the v1.4.0 rule.
Impacts: T117..T121, T122.

### D-013 — Web Spot and Margin through a proxy
Decision: "Làm proxy cho web", after the trade-offs were presented. This is a stated exception to D-003 and narrows D-009's web limit, for Binance Spot and Margin reads on web only. The API key and signature pass through the proxy.
Impacts: `docs/agents/plans/2026-11-07-binance-web-proxy.md`.

### D-014 — Proxy host and allowed origin
Decision: nginx on the VPS; web origin `https://app.tradingbalancef.com`.

### D-015 — Estimated profit is planned
Decision: "Sửa nhãn, lập kế hoạch PnL". Labels and percentage are T127. Profit from trade history is `docs/agents/plans/2026-11-07-binance-estimated-pnl.md`.

## Coordinator Proposals For Approval

### P-007 — Estimated profit method (accepted by plan approval, "Duyệt, làm đi")
Moving average cost, USDT pairs only, unrealized only, fees in other assets ignored, unpaid interest only. Figures stay separate from USDⓈ-M.

### P-006 — Reuse `api.tradingbalancef.com`
The location goes in the existing server block under `/binance-proxy/`, so no new DNS or certificate is needed.


These follow from the decisions above. Accepted by plan approval on 2026-11-07 ("Duyệt, bắt đầu T116").

### P-001 — Four navigation items
Strategy is backend-only, so hiding it leaves `Tài sản`, `Lệnh`, `Thị trường`, `Thêm`. With the gate on, the design's fifth item returns.

### P-002 — Gate mechanism
`backendFeaturesEnabledProvider` (`Provider<bool>`, default `false`), not a build define, so no build configuration changes and tests can flip it. Turning the backend back on is a one-line source change. There is no user-visible toggle.

### P-003 — No locked scope bar
The design's locked state exists for drafts and trade confirmations, all of which are hidden. It is not built now. `Chi tiết vị thế` remains read-only with the normal bar and no close action.

### P-004 — Stored backend data untouched
The remembered trade password and backend endpoint values in secure storage are neither read nor deleted. The backend server, its worker and its OKX account are not changed by this plan.

### P-005 — Binance total valuation
The account total is the sum of signed per-asset values described in spec section 6. It is an approximate display value, marked partial if any row cannot be priced or any wallet fails.

## User-Authorized Assumptions

None.

## Change Log

| Revision | Change | Reason |
|---|---|---|
| 1 | Initial record | Planning cycle 2026-11-07 |
| 2 | D-012 added | Executor rules upgraded to OptCodex v1.4.0 |
