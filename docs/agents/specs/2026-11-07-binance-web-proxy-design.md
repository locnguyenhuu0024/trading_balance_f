# Design Specification: Binance Spot and Margin on web through a read proxy

Status: READY_FOR_PLAN
Date: 2026-11-07
Tier: M
Decision Ledger: `docs/agents/decisions/2026-11-07-multi-platform-view-only-decisions.md` (D-013, D-014, P-006)

## 1. Objective

The web build at `https://app.tradingbalancef.com` shows Binance Spot and Margin, which browsers block today (OBS-010), through a read-only nginx location on the VPS. Native builds keep calling Binance directly.

## 2. Observed Facts

| ID | Source | Observation |
|---|---|---|
| OBS-101 | `curl` 2026-11-07 | `https://api.tradingbalancef.com/v1/health` answers 200, behind Cloudflare |
| OBS-102 | `docs/deployment/position-trade-api.md` | That host is the VPS API on Ubuntu 24.04 with nginx |
| OBS-103 | `binance_reader.dart`, `account_state_view.dart`, `scope_bar.dart`, filter chips | Spot and Margin are gated by `isWeb` in about ten places |
| OBS-104 | `binance_adapter.dart` | `readPositions` ignores `orderFilterProvider`, so the Margin chip also lists USD-M positions |

## 3. Requirements

- REQ-101: With `BINANCE_PROXY_URL` set on web, private `/api/v3/*` and `/sapi/*` reads go to `<proxy><path>?<signed query>` with the `X-MBX-APIKEY` header. `/fapi/*`, public market and time reads stay direct. Native ignores the proxy.
- REQ-102: With it unset or invalid (not `https`, or carrying a query or fragment), behavior is exactly today's: no request, and the app-only notice.
- REQ-103: The secret never leaves the device. It is used only for signing.
- REQ-104: A proxy failure, including `451` and `403`, marks only the Spot and Margin wallets unavailable; USD-M keeps working and the total is partial.
- REQ-105: Product line, filter chips and notices follow availability instead of `isWeb`.
- REQ-106: On Binance `Lệnh` → `Vị thế`: `Tất cả` and `USDⓈ-M` list USD-M positions; `Margin` lists margin cards only. `Tất cả` also keeps margin cards.

## 4. Security

The API key and signature pass through Cloudflare and the VPS. The signature is query-bound and expires with `recvWindow`, and the secret does not travel. The location allows GET on six fixed paths, one Origin, no access log, no cache. An Origin check is not authentication, so anyone could use the proxy with their own key on those read routes; the exposure is bounded because it adds no credential and allows no writes, and the VPS IP shares its Binance weight limit.

## 5. Acceptance Criteria

- AC-101: On web with the proxy, a Spot read goes to the proxy host with a correct signature, and no request contains the secret.
- AC-102: On web without the proxy, zero Spot or Margin requests occur and the notice shows.
- AC-103: Native ignores a configured proxy.
- AC-104: A `451` on Spot leaves USD-M rendered and the total partial.
- AC-105: Chips and product line show Spot and Margin on web with the proxy, and hide them without it.
- AC-106: REQ-106 holds with fixture data.
- AC-107: User-run: nginx checks in `docs/deployment/binance-read-proxy.md` pass, and the deployed site shows real Spot and Margin.

## 6. Protected Configuration / Environment Actions

- Target: the nginx `server` block for `api.tradingbalancef.com`.
- Content: the location in `docs/deployment/binance-read-proxy.md`.
- Scope: production VPS. Reason: REQ-101. Validation: `nginx -t`, reload, section 3 checks.
- Build flag: `--dart-define=BINANCE_PROXY_URL=https://api.tradingbalancef.com/binance-proxy`.
- Verification of AC-107 is blocked until applied: YES. AC-101..106 are not blocked.
