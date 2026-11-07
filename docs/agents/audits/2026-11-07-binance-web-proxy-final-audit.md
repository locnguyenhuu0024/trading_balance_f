# Final audit: Binance Spot and Margin on web through a proxy

Plan: `PLAN-20261107-binance-web-proxy`
Date: 2026-11-07
Verdict: PASS for code. Live behavior is pending the user-owned steps below.

## Coordinator-observed results

- Full suite: 626 tests pass.
- Analyzer: 0 errors.
- `flutter build web --release` passes with and without `BINANCE_PROXY_URL`. The proxy URL appears in `main.dart.js` only with the define.
- `GET https://api.binance.com/api/v3/time` with the web origin returns `Access-Control-Allow-Origin: *`, so the direct time route works in browsers.
- RED by mutation: T125 nine mutations, T126 twelve; each failed the suite.

## Tasks

| Task | Attempts | Verdict | Notes |
|---|---|---|---|
| T125 | 1 | PASS | Connection test provider has no injectable transport; verified by inspection |
| T126 | 3 | PASS | Two remediation rounds; two test-only coordinator corrections recorded in the task |

T126 audit found a defect that predates this plan: reading `.value` of a failed account read threw during build of `OrdersScreen`. Fixed.

## Live proxy checks

The user applied the nginx location. Coordinator-observed on the live host with a dummy key, no real credentials:

| Request | Result |
|---|---|
| Margin account, allowed origin | 400, Binance `-2008`, `access-control-allow-origin` set, `cache-control: no-store` |
| Spot account, allowed origin | Binance `-1102`, so the request reached Binance |
| Other origin, no origin | 403 |
| `api/v3/order`, outside the list | 404 |
| Preflight for `X-MBX-APIKEY` | 204 with CORS headers |
| POST | 405 |
| `/v1/health` | 200 |

## Not verified

- U1: the user reported that the VPS ping returned 200; the coordinator did not observe it.
- Live Spot and Margin reads with real keys through the proxy.
- Native iOS and Android builds, still pending from the parent plan.

## User-owned steps

Remaining from `docs/deployment/binance-read-proxy.md`: build with the define, deploy, and check live with a read-only key.

## Known limits

- The API key and signature pass through Cloudflare and the VPS. The secret stays on the device.
- The Origin check is not authentication. Others can use the route with their own keys and share the VPS IP weight limit.
- Binance order history coverage is unchanged (D-010).
