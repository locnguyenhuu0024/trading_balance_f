# Design Specification: Strategy preview failure diagnostics

Status: APPROVED (T45 implemented and audited 2026-10-02)
Date: 2026-10-02
Tier: M
Decision Ledger: N/A — this is a diagnostic change with no new trading decision.

## Objective and evidence

The iPhone strategy wizard fails immediately after Step 2 submits a SOL-USDT-SWAP/H6 preview. The screenshot displays `The authenticated strategy request could not be completed.` The user confirmed that Trade Management still loads positions, and that unauthenticated `POST /v1/strategies/preview` returns `401 application/json` both at the Docker container's localhost port and through the public HTTPS API. Docker logs did not show the request; the application source does not itself record access logs. The HTTP outcome of the authenticated browser request remains unknown.

| ID | Source | Observation |
| --- | --- | --- |
| OBS-001 | `lib/features/strategy/data/strategy_api_client.dart` `_request` | The screenshot text is the fallback for a Dio failure without a nonempty parsed JSON `message`; the code discards failure type and status from the visible message. |
| OBS-002 | `lib/features/strategy/presentation/strategy_wizard_dialog.dart` `_requestPreview` | Step 2 sends a bearer-authenticated preview and displays `StrategyApiException.message`; a 401 expires the session. |
| OBS-003 | `backend/app.py`, `backend/strategy.py` | Backend API errors, including ordinary validation, OKX input failures, and unexpected exceptions, produce JSON with a nonempty message when their response reaches the client. |
| OBS-004 | Local fake-exchange probe | A two-sided 200 USDT, 5x, 50/50 preview returns HTTP 200 and two orders; this does not prove the user's selected SOL levels will pass. |

The screenshot does not establish whether the authenticated request failed at the browser, proxy, or backend. No production credentials, body, or response content are available for inspection.

## Scope and requirements

### REQ-001 / AC-001 — Actionable safe preview failure

When a strategy API call fails without a structured JSON message, classify it by Dio failure type and safe HTTP status. Show a short Vietnamese message with an actionable next step and a stable diagnostic marker such as `HTTP 404`, `HTTP 502`, `TIMEOUT`, or `CONNECTION`. Never display raw response bodies, request payloads, bearer tokens, URLs with credentials, or exception internals. For a server response with a nonempty structured `message`, preserve that message and the existing error code/details contract. HTTP 401 continues to expire the session.

### REQ-002 / AC-002 — Preview retry and successful behavior

After a failed preview, Step 2 remains usable and `Xem lại lệnh` may be pressed again without losing selections or financial inputs. Successful preview still requires a valid `previewHash` and nonempty order list, then advances to Step 3. The client must not retry automatically or submit/save/place an order because an error occurred.

## Interface, invariants, and failure matrix

No backend API, database, auth, trading, or configuration contract changes. `StrategyApiException` retains status/code/details. Its user-visible fallback message is determined by: response status if present; otherwise connection/timeout/cancel/unknown Dio type. Do not infer a precise root cause from `connectionError`, which can include browser CORS rejection.

| Failure | Expected visible fallback |
| --- | --- |
| No response, timeout | Vietnamese timeout and retry advice; `TIMEOUT` marker |
| No response, connection/browser failure | Vietnamese connection or browser-blocked advice; `CONNECTION` marker |
| Unstructured HTTP 404 | Vietnamese endpoint/routing advice; `HTTP 404` marker |
| Unstructured HTTP 429 | Vietnamese rate-limit advice; `HTTP 429` marker |
| Other unstructured HTTP 4xx/5xx | Vietnamese safe server response advice; exact `HTTP nnn` marker |
| Structured backend error | Preserve backend message, status, code, and details |
| HTTP 401 | Preserve session-expiry behavior |

## Verification contract

RED-001: A Dio 404 HTML/empty response or a no-response connection failure currently yields the same generic English message; the changed client must distinguish them without exposing response data.

GREEN-001: A structured backend 422 message remains intact, and a successful preview still reaches Step 3 with existing selection and budget. A retry after a failure sends only one new preview request.

Unit tests use an in-memory Dio adapter/fake and no live exchange, credentials, or external service. Final affected build unit is Flutter web. No protected configuration action is required.

## Limit and next evidence

This change reveals the failure category on the user's next attempt; it does not claim to repair an unknown production proxy/backend fault. The reported marker, together with SOL/H6, will determine whether a separate backend/proxy remediation plan is required. Deployment and a user retry require separate authorization.
