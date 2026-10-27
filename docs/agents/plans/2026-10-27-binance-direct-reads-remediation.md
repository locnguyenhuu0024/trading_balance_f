# Remediation Plan: Binance direct reads re-audit findings

Status: COMPLETE (T120 PASS, T121 PASS, final integration audit PASS, 2026-10-27)
Date: 2026-10-27
Tier: M (client-only corrections; no new architecture or contracts)
Parent specification: `docs/agents/specs/2026-10-25-binance-direct-reads-design.md` (revision 2, unchanged)
Parent plan: `docs/agents/plans/2026-10-25-binance-direct-reads.md` (COMPLETE)
Audit: `docs/agents/audits/2026-10-27-binance-direct-reads-reaudit.md`
Decision Ledger: `docs/agents/decisions/2026-10-25-binance-direct-reads-decisions.md` (D-008..D-010 APPROVED)

## 1. Objective
Fix AUD-001..004 so Binance Spot refresh is bounded, unknown prices stay unavailable, zero-balance Binance rows are not shown, and the migration leaves no dead code. No change to OKX behavior, backend actions, the route registry, scheduling or credentials.

## 2. Planning workstreams and route
One material workstream (Flutter client data/presentation). Fan-out Required: NO. Skip reason: `SINGLE_MATERIAL_WORKSTREAM`. Coordinator: Claude Sonnet 5.5 High (user-selected; effective route not claimed). Executors: T120 E1 `gpt-6-luna`/`xhigh`; T121 E0 `gpt-6-luna`/`high`; explicit model and effort at spawn, inheritance forbidden, no Terra trial requested.

## 3. Decisions requiring user approval (proposed by coordinator)
- D-008: hide Binance asset rows (Spot and Futures) whose total is available and exactly zero. Rows with unavailable amounts stay visible. OKX rows unchanged. Hidden rows add nothing to totals, so equity and completeness are unchanged.
- D-009: a Binance Spot order price that is absent or not positive is `unavailable` (shows `--`). No average price is derived from executed quote and quantity.
- D-010: reuse of the Spot catalog is per credential generation with a 60-minute lifetime on the reader clock. Credential change, disposal or expiry forces a fresh read. The history scan keeps its own fresh catalog read.

## 4. Scope
Allowed source: `lib/core/exchange/binance_exchange_reader.dart`, `lib/core/exchange/exchange_account_providers.dart` (T120); plus `lib/core/exchange/exchange_quote_service.dart`, `lib/core/network/binance_data_client.dart`, `lib/features/portfolio/presentation/portfolio_screen.dart`, `lib/features/portfolio/presentation/portfolio_details_screen.dart`, `lib/features/orders/presentation/orders_screen.dart` (T121). Tests: `test/core/exchange/exchange_readers_test.dart`, `test/features/portfolio/combined_exchange_portfolio_test.dart` (T120 only).
Out of scope: protected configuration, dependencies, route registry or weights, scheduling, history scan behavior, backend/Strategy/OKX behavior, Git actions, pre-existing analyzer findings (for example the `!` warnings in `order_cancellation_flow_provider.dart` and the catch clause in `strategy_dashboard_provider.dart`), test-file lint cleanup.

## 5. DAG and decomposition
`T120/P01 -> T121/P02 -> independent audit -> final V4 once + fresh build`. Serial because both touch `binance_exchange_reader.dart`. Two tasks (handoff target 1–3): T120 groups three findings that share a write surface and test path; T121 differs in class (E0) and evidence (static analysis).

| Task | Findings | Acceptance | Route | Build unit |
|---|---|---|---|---|
| T120 | AUD-001, AUD-002, AUD-003 | RAC-001, RAC-002, RAC-003 | E1 gpt-6-luna xhigh | full Flutter app |
| T121 | AUD-004 | RAC-004 | E0 gpt-6-luna high | full Flutter app |

## 6. Steps and verification
### P01 / T120
1. Reader keeps the last successful Spot catalog with its generation and timestamp. New optional `getSpotCatalog` parameter (default off) lets the portfolio source reuse it under D-010. Every successful fetch refreshes the stored catalog; generation change and disposal clear it.
2. `binanceSpotPortfolioSourceProvider` requests the catalog with reuse enabled.
3. `_spotOrder` price is available only when the parsed native price is positive (D-009).
4. `_portfolioRows` omits Binance rows per D-008.

RED-120: before the change, two consecutive Spot portfolio refreshes in one generation send two exchangeInfo requests (expected one); a Spot MARKET row with price `0.00000000` reports an available price (expected unavailable); a Binance Spot and Futures zero row is listed (expected hidden).
GREEN-120: one exchangeInfo request across refreshes within lifetime; a new request after 60 minutes and after a credential generation change; the history scan still reads its own catalog; positive limit prices unchanged; zero Binance rows hidden while an unavailable-amount row and a zero OKX row remain; fixture combined equity 195 unchanged.
Ceiling V3: `rtk flutter test --no-pub test/core/exchange test/features/portfolio test/features/orders`. Build: `rtk flutter build web --no-pub` (full app).

### P02 / T121
Remove only the analyzer-reported items listed in T121, and anything those removals orphan in the same files. RED = recorded analyzer baseline listing exactly those 10 findings; GREEN = none of them remain. Regression: `rtk flutter test --no-pub test/core/exchange test/core/network/binance_data_client_test.dart test/features/portfolio test/features/orders`. Build as above.

Task buildability: YES for both, after the last executable change, no deferral to a later task.
Stop if: a removal target is still referenced, or scope must exceed section 4.

## 7. External verification / configuration
None. Live private-account, device and CORS checks stay unavailable and unclaimed; AUD-002 and AUD-003 rest on documented Binance behavior until the user checks with a real account.

## 8. Approval gate
- [x] scope bounded, write surfaces explicit and serial
- [x] RED then GREEN defined, build unit and exact command defined
- [x] no protected configuration content needed
- [x] user approves D-008, D-009, D-010 and this plan (chat, 2026-10-27)
- [ ] `task_ledger.py plan` for T120 and T121 recorded after approval
