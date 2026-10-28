# Plan: Binance read failure visibility

Status: APPROVED (user, chat, 2026-10-28: "Duyệt"); T122 PASS (commit 3ed75c5); T123 PASS (independent audit 2026-10-28, uncommitted); final integration audit PASS
Date: 2026-10-28
Tier: M (client-only; no new architecture, dependency or contract)
Parent plan: `docs/agents/plans/2026-10-27-binance-direct-reads-remediation.md` (COMPLETE)
Advisory input: Sol Medium proposal, planning attempt `fb8526b935e44749a1cb2865b8ed450d`, packet sha256 `0b12d55e2fb8fca5ae5b3a06112d5a8c860f590106c88550caec5b9e772ce80c`, approval `SOL-2026-10-28-001`. The proposal is untrusted and non-canonical; this plan reconciles it with the code.

## 1. Objective
When a Binance read fails, the user sees a distinct, safe, actionable message per failure type instead of the generic or verbatim client text. A failing Binance source never hides OKX or other Binance products, and the portfolio stays partial. No secrets, signatures, request URLs or raw response bodies appear in messages.

## 2. Verified facts (coordinator read of the code, 2026-10-28)
- `BinanceDataClient` already classifies: `binance_network_error`, `binance_ip_banned` (418), `binance_rate_limited` (429), `binance_authentication_failed` (-2014/-2015), `binance_timestamp_invalid` (-1021, one automatic retry), `binance_http_error`, `binance_api_error`, `binance_invalid_response`, `binance_host_paused` and `binance_budget_metadata_unavailable` (carry `retryAt`), plus credential and cancel codes.
- A Dio timeout without a response currently collapses into `binance_network_error` (`_safeTransportFailure` returns `_networkError()` when `response == null`). Distinct timeout copy therefore needs a new code in `binance_data_client.dart`.
- `BinanceExchangeReader._get` rewraps the exception as `ExchangeReadException(code, message, retryAt, statusCode)`; the `retryAfter` header string is not converted to `retryAt`, so a wait time exists only for the host-pause codes.
- `_safeReadError` in `exchange_account_providers.dart` returns `ExchangeReadException.message` verbatim. The result type `ExchangeAccountResult` carries only `error` (String) and `isTerminalFailure`.
- The error string reaches the UI as the `${label}: ${result.error}` warning (`exchange_account_providers.dart:852`) and `result.error`, rendered by `portfolio_screen.dart` (warnings, sources), `portfolio_details_screen.dart` and `orders_screen.dart`. Per-source isolation and the partial flag already exist.
- Not verified: whether those screens have a retry control or a route to credential settings, how browser-blocked requests surface in Dio on web, live Binance behavior.

## 3. Decisions requiring user approval (proposed by coordinator)
- D-011: map failures to curated copy inside `_safeReadError`, keyed by `ExchangeReadException.code`, and keep the `ExchangeAccountResult` shape unchanged. Sol proposed adding `errorCode` and `retryAt` fields; that is deferred (see section 7) because the current UI shows only a string, so the extra fields would be unused. Unknown codes fall back to safe generic copy.
- D-012: add a distinct `binance_timeout` code in `binance_data_client.dart` for Dio connect, send and receive timeouts. No change to synchronization, request coordination, signing or credential storage.
- D-013: on web, never state that CORS is the cause. An ambiguous no-response failure shows "Cannot reach Binance from this browser. Check your connection; browser or network restrictions may also block requests." A retry time is shown only when `retryAt` is present, as a clock time in the user's locale, and an elapsed `retryAt` shows no time.

## 4. Copy matrix (English, safe fallback for anything else)
| Code | Message |
|---|---|
| `binance_network_error` | Cannot reach Binance. Check your connection and retry. (web: the D-013 sentence) |
| `binance_timeout` | Binance did not respond in time. Retry in a moment. |
| `binance_rate_limited` | Binance rate limit reached. Retry shortly. |
| `binance_ip_banned` | Binance temporarily blocked reads from this network. Retry later. |
| `binance_host_paused`, `binance_budget_metadata_unavailable` | Binance reads are paused. Retry after HH:mm when a time is known, otherwise retry later. |
| `binance_authentication_failed` | Binance rejected the API key. Check the key, secret and permissions. |
| `binance_timestamp_invalid` | Binance rejected the request time. Check your device clock and retry. |
| `binance_http_error`, `binance_api_error`, `binance_invalid_response` | Binance could not complete the request. Retry later. |
| `binance_credentials_required`, `binance_credentials_unavailable` | existing text kept |
| `request_cancelled`, `credentials_changed` | existing behavior kept; not shown as an outage |

## 5. Scope
Allowed source: `lib/core/network/binance_data_client.dart`, `lib/core/exchange/exchange_account_providers.dart`. Tests: `test/core/network/binance_data_client_test.dart`, `test/features/portfolio/combined_exchange_portfolio_test.dart` (and `test/core/exchange/exchange_readers_test.dart` only if the mapping is exercised there).
Out of scope: protected configuration, dependencies, signing, credential storage, request coordinator, `ExchangeAccountResult` shape, widgets, OKX behavior, history scan, Git actions, live Binance checks.

## 6. DAG and tasks
`T122 -> T123 -> independent audit -> final V4 once + fresh build`. Serial: T123 uses the new timeout code.

| Task | Content | Route | Build unit |
|---|---|---|---|
| T122 | `binance_timeout` classification in the client | E0 `gpt-6-luna`/`high` | full Flutter app |
| T123 | curated mapping in `_safeReadError`, retry-time formatting (no clock injection; tests use times relative to now), source-isolation and sentinel tests | E1 `gpt-6-luna`/`xhigh` | full Flutter app |

RED-122: a Dio connect, send or receive timeout currently yields `binance_network_error`; expected `binance_timeout`; other transport failures unchanged. GREEN-122 exact classification, existing client tests green.
RED-123: current `_safeReadError` returns the client message verbatim; expected the section 4 copy for every code, a time only when `retryAt` is future, safe fallback for unknown codes, sentinel text (key, signature, URL, body) never present, a failed Binance source leaving OKX and another Binance product in the portfolio with `isPartial` true. GREEN-123 all pass.
Ceiling V3: `rtk flutter test --no-pub test/core/exchange test/core/network test/features/portfolio test/features/orders`. Build: `rtk flutter build web --no-pub` after `flutter pub get`.
Task buildability: YES for both, no deferral.
Stop if: scope must grow past section 5, or the screens cannot render the mapped string without a widget change.

## 7. Deferred, not approved
- Add `errorCode` and `retryAt` to `ExchangeAccountResult` plus widget actions (retry and "open credential settings"). Needs a prior read of the three screens to confirm existing controls; propose separately if wanted.
- Detecting browser-blocked requests on web: no defensible Dio signal is known.
- Live verification against a real account and the browser.

## 8. Approval gate
- [x] scope bounded, write surfaces explicit and serial
- [x] RED then GREEN defined, build unit and command defined
- [x] no protected configuration content needed
- [x] user approves D-011, D-012, D-013 and this plan (chat, 2026-10-28)
- [x] `task_ledger.py plan` for T122 and T123 recorded after approval
- [x] task files and manifests created after approval; worktree must be clean before dispatch (this plan file and `pubspec.lock` need a user-approved commit or revert)
