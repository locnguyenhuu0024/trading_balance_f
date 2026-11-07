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

## Not verified

- U1: the VPS ping result was not reported. It must return 200 before U2.
- The nginx location has not been syntax-checked or run.
- Live Spot and Margin reads with real keys through the proxy.
- Native iOS and Android builds, still pending from the parent plan.

## User-owned steps

Follow `docs/deployment/binance-read-proxy.md`: VPS ping, add the location, `nginx -t`, verification requests, build with the define, deploy, and check live with a read-only key.

## Known limits

- The API key and signature pass through Cloudflare and the VPS. The secret stays on the device.
- The Origin check is not authentication. Others can use the route with their own keys and share the VPS IP weight limit.
- Binance order history coverage is unchanged (D-010).
