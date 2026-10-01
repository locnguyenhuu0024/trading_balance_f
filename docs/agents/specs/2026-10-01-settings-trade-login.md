# Settings trade login and eight-hour session

Status: READY_FOR_IMPLEMENTATION

## Decisions and contract

- REQ-1: The main Settings screen has one entry opening a dedicated API and trading access page. Move the existing read-only OKX API key form there without changing its storage semantics. The same page owns trade API sign-in, sign-out, and session status.
- REQ-2: Remove sign-in and sign-out controls from the Positions screen. Keep its account status, close-all action, unresolved-operation lookup, and all action confirmations. Signed-out guidance points to Settings.
- REQ-3: A trade session expires exactly eight hours after successful password and TOTP login. It does not slide or renew through activity. The server database expiry is authoritative. Existing sessions retain their stored expiry.
- REQ-4: Web reload restores an unexpired session using a host-only `__Host-trade_session` cookie on the API host (`Secure; HttpOnly; SameSite=Strict; Path=/; Max-Age=28800`). The bearer remains in client memory and existing authenticated trade requests continue to require the bearer header. No bearer, password, or TOTP enters local or session storage.
- REQ-5: `GET /v1/session` validates the cookie against the server session table and returns `token`, `expiresAt`, and `accountIdentifier` using the login response shape. This endpoint is read-only. Login sets the cookie; bearer-authenticated logout revokes the server session and clears the cookie. The cookie never authorizes trade write endpoints, so the existing bearer and confirmation-token gates remain in force.
- REQ-6: Credentialed browser requests are allowed only for the exact configured web origin, with `Access-Control-Allow-Credentials: true` on approved-origin responses and preflight. The existing production origin setting remains user-owned and is not changed in this task.
- REQ-7: If restoration fails or expires, show signed-out state and disable trading actions. Network failures may be retried from Settings; no action is submitted during restoration. A new login or logout invalidates the cached authenticated position list.

## Acceptance criteria

- AC-1: Settings entry opens a subpage containing both the original key form and trading login/session controls; the key form still saves through existing local secure storage.
- AC-2: Positions has no login/logout button, while close-all, individual actions, confirmation dialogs, and pending lookup remain available when authenticated.
- AC-3: Login expires at `login_time + 28800`; a request at that boundary is denied without an OKX write.
- AC-4: Browser reload restores before allowing actions. Cookie attributes, CORS credentials, logout revocation/clearing, and expired-cookie rejection are tested.
- AC-5: Unsupported or absent web API URL preserves read-only behavior. No credential or token is persisted by Flutter.

## Planning workstreams

| Workstream | Material | Independent | Route | Result |
| --- | --- | --- | --- | --- |
| Frontend/UI and session bootstrap | Yes | Yes | R2 gpt-6-sol/medium, explicit | Collected; Settings extraction and Orders safety retained |
| Backend/session and CORS | Yes | Yes | R2 gpt-6-sol/medium, explicit | Collected; fixed expiry, cookie restore, exact origin |

Fan-out Required: YES. Fan-out Compliance: PASS. Required/actual agents: 2/2. Cross-layer contract synthesized by coordinator. Effective child route unavailable after explicit binding.

## Risk and rollout

Deploy backend before web. The old web client remains compatible with bearer login and actions. After the new backend is running, deploy the new web client. The production container must be rebuilt and recreated by the server owner; restarting the old image will not apply this code. Roll back the web client first if needed; the backend retains existing bearer endpoints.
