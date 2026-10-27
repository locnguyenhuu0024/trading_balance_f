# Binance direct reads — Independent re-audit

Date: 2026-10-27
Verdict: REWORK (bounded; remediation planned as T120, T121)
Supersedes for follow-up only: `2026-10-25-binance-direct-reads-integration.md` (its evidence remains valid for what it observed)
Auditor: Claude coordinator (user-selected Sonnet 5.5 High; effective route not programmatically verifiable). No child agents were used.

## Evidence reviewed

- Git: branch `codex/binance-direct-reads`, working tree clean; changed paths vs `origin/main` are only `lib/`, `test/`, `docs/`, `tasks/`. No protected configuration/environment path changed or read.
- Fresh observations in current state: `rtk flutter test --no-pub` exit 0, 664 passed; `rtk flutter build web --no-pub` exit 0 (built `build/web`, warning-only Wasm/Cupertino notices). `rtk flutter analyze --no-pub lib`: 49 issues, of which the findings below are branch-introduced.
- Source reviewed in full: `binance_data_client.dart`, `binance_read_routes.dart`, `binance_request_coordinator.dart`, `binance_exchange_reader.dart`, `exchange_readers.dart`, `binance_history_scan.dart`, `exchange_quote_service.dart`, `binance_credential_bundle.dart`, Binance parts of `secure_storage_helper.dart` and `main.dart`, action-boundary diffs. Reviewed selectively: `exchange_account_providers.dart`, `exchange_models.dart`, `orders_screen.dart`, `portfolio_screen.dart`, `settings_trade_access_page.dart`.
- Confirmed sound: fixed-origin GET-only transport with final-adapter validation; signing after scheduling; sanitized errors; single-bundle credential persistence with generation fencing; weight/budget constants match the specification; backend action authority requires explicit OKX source plus original OKX DTO.

## Findings

| ID | Severity | Requirement | Evidence | Expected vs observed |
|---|---|---|---|---|
| AUD-001 | Should fix (High) | REQ-005 bounded polling, INV-003 | `exchange_account_providers.dart:461` calls `getSpotCatalog` on every evaluation; `binance_exchange_reader.dart:76-82` always sends `/api/v3/exchangeInfo`; `portfolio_screen.dart:49` and `portfolio_details_screen.dart:42` invalidate the Spot source every 5 s (`exchange_account_providers.dart:1098`). No test counts exchangeInfo requests. | Expected: catalog read once per credential generation (bounded refresh). Observed: one full Spot catalog (weight 20, multi-MB payload, parsed on the UI isolate) per refresh, about 12 per minute. |
| AUD-002 | Should fix | REQ-002 unknown stays unavailable | `binance_exchange_reader.dart:1053` accepts any parsable `price`; `orders_screen.dart:1012` prints it. Binance Spot returns `"0.00000000"` for MARKET orders (Futures path already handles this in `_futuresOrderPrice`). No Spot MARKET fixture. | Expected: unavailable (`--`). Observed: "Price 0.00000000 USDT". Binance API behavior is from reviewer knowledge, not a live capture. |
| AUD-003 | Should fix (needs live confirmation) | REQ-004 usable combined view | `binance_exchange_reader.dart:318-360` keeps every balance row; the registry forbids `omitZeroBalances` (`binance_read_routes.dart:78`); Portfolio renders all rows (`portfolio_screen.dart:166-260`). | Expected: only meaningful Binance assets. Observed (predicted): Spot account response lists zero-balance assets, so many zero rows. Not verified with a real account. |
| AUD-004 | Nice to have | Ponytail minimal change | Analyzer warnings introduced by the migration: unused imports (`binance_exchange_reader.dart:8`, `exchange_quote_service.dart:9`, `portfolio_screen.dart:18`, `portfolio_details_screen.dart:19`), unused local (`binance_data_client.dart:345`, `portfolio_details_screen.dart:354`), unreferenced `_buildPortfolioData`, `_buildErrorState`, `_DetailsContent`, `_buildEmptyState`. | Expected: no dead code left by the migration. |

Residual risks (not findings): Futures weight headroom is thin when several screens poll together (about 1,600–1,800 of a 1,920 ceiling per minute); web credentials sit in `SharedPreferences` like the existing OKX ones; no live private-account, device or CORS evidence exists.

## Not done

No `task_ledger.py audit` verdict was recorded: the ledger has no records for T116–T118 (no attempt IDs). Coordinator telemetry for this audit was not appended pending approval of the remediation plan. Existing T116–T118 statuses are unchanged; remediation uses new tasks.
