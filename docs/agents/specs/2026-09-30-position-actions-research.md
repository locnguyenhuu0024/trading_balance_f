# Position actions research

Status: SUPERSEDED_BY_DESIGN_SPEC
Date: 2026-09-30
Scope: research and planning only; no live trade or account action executed.

## Repository evidence

- `lib/features/orders/data/order_repository.dart` currently reads positions and orders; it has no authenticated write operation for position actions.
- `lib/features/orders/data/okx_position_model.dart` includes `instId`, `posSide`, `pos`, and `mgnMode`, but not `instType`, `posId`, position/margin currency, or account mode. The ALL view therefore lacks fields needed to target every action safely.
- Position cards in `lib/features/orders/presentation/orders_screen.dart` display values only; there are no action buttons or confirmation flows.
- `test/features/orders/presentation/orders_screen_position_layout_test.dart` asserts the card ends shortly after the liquidation price; adding controls will require updating this layout contract.

## Official OKX API evidence

| Proposed action | Verified contract | Planning consequence |
|---|---|---|
| Add margin | [Increase/decrease margin](https://www.okx.com/docs-v5/en/#rest-api-account-increase-decrease-margin): `POST /api/v5/account/position/margin-balance`, `type=add`, isolated positions only; `ccy` conditional for isolated MARGIN. | Show only when eligibility and margin currency are known. Adding margin does not add position size. |
| DCA / increase position | [Place order](https://www.okx.com/docs-v5/en/#rest-api-trade-place-order): `POST /api/v5/trade/order` with trading mode, side, order type and size; position-side rules differ by mode. | Define input unit, order type, side, precision, and risk confirmation before implementation. DCA is an application workflow, not a distinct OKX endpoint. |
| Close part of a position | [Place order](https://www.okx.com/docs-v5/en/#rest-api-trade-place-order): opposite-side order with an explicit size; `reduceOnly` applicability depends on product and position mode. | Require precise position identity, available size, lot/min-size rules, and mode-aware validation. |
| Close a whole position | [Close positions](https://www.okx.com/docs-v5/en/#rest-api-trade-close-positions): `POST /api/v5/trade/close-position` sends a market close for one instrument/side, with conditional margin currency and optional pending-close-order cancellation. | Confirm target and pending-order behavior; verify final state after request. |
| Close all positions | No bulk close endpoint is established by the reviewed contracts. | If intended, plan a multi-position workflow that can finish partially and reports each outcome. |

The [positions API](https://www.okx.com/docs-v5/en/#rest-api-account-get-positions) includes position identity and mode fields not currently retained by the app model. Do not derive a target solely from the card label or `instId` when multiple sides/margin modes can exist.

## Candidate user flow

Place eligible actions on each position card or in its action menu. Each write flow reviews the current position, side, trading mode, amount/size, execution type, and estimated effect before a distinct final confirmation. Refresh the position immediately before sending; disable duplicate submission while pending; show partial fills, individual failures, and the confirmed post-action state. A page-level close-all flow, if requested, needs a separate confirmation and per-position outcome list.

## User decisions recorded after initial research

- Implement real OKX actions in the application. A full close on a card targets 100% of that selected position; add a separate account-wide close-all button independent of the display filter. Every action requires a confirmation popup.
- DCA is a market order with a size entered in the position's unit. Partial close uses a percentage (25%, 50%, 75%, or custom). The first release targets eligible MARGIN, SWAP, and FUTURES positions, not OPTION.
- Selected and account-wide full close must cancel pending closing orders first. Use the supported OKX cancellation behavior only after the user confirms the exact target list.
- Intended environment is production. The current API key has read-only permission, so a Trade-enabled key is a user-owned prerequisite for any live write verification.
- The user initially requested direct Flutter signing with encryption. In a browser, a decrypted signing key remains accessible to client-side code. The user approved a private Python server-side signing architecture under `backend/` in this repository. No server/API exists yet; code and deployment guidance are the current deliverable.
- The backend will use password plus TOTP login and a short-lived web session. The user will later create `/etc/trading-balance/trade-api.env` outside Git and pass the public API URL to Flutter through `--dart-define`.
- MARGIN DCA/partial-close cases that cannot express exact position-unit size or percentage under the documented market-order contract will be disabled in the first release.

## Remaining blockers

- Q-006: RESOLVED — Python backend under `backend/` in this repository, password and TOTP authentication, code and guide now; hosting is a later user-owned action.
- Q-007: RESOLVED — future server secrets in `/etc/trading-balance/trade-api.env` created by the user; public API URL via Flutter `--dart-define`.
- Q-008: Define exact eligibility rules for MARGIN partial close and DCA; disable cases where documented market-order units cannot express the requested amount exactly. Instrument-specific rounding and minimum trade size must be validated from OKX metadata at runtime.
- Q-009: Production live write verification cannot occur until the user provisions a Trade-enabled key and an authenticated HTTPS server without disclosing credentials to agents. The present deliverable is code, local tests, and deployment instructions.

## Planning workstreams

UI/interaction, API/trade semantics, and server security are independently material. The initial research had separate UI and API runs. After the user expanded the scope, explicitly bound R2 UI, R3 API, and R3 security runs were collected. Fan-out required: YES; required 3, actual 3 in the current cycle, compliance PASS. Coordinator owns cross-layer synthesis and final contract. No action implementation task is ready while Q-006..009 remain open.
