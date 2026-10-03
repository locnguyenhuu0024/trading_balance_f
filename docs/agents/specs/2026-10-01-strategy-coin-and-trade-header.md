# Design Specification: Strategy contract catalog and trade header

Status: APPROVED (execution authorized 2026-10-01)
Date: 2026-10-01
Tier: M
Decision Ledger: N/A — the requested behavior and repository evidence resolve the contract.

## Objective

- REQ-001: The strategy wizard lists live linear USDT perpetual contracts when OKX omits or empties `baseCcy` for SWAP instruments.
- REQ-002: On Trade Management, the close-all area displays only a compact close-all button, while a simple authentication status icon sits on the same AppBar title line.

## Evidence and diagnosis

| ID | Source | Observation |
| --- | --- | --- |
| OBS-001 | `lib/features/strategy/data/strategy_market_repository.dart` `getInstruments` | Every otherwise valid SWAP is skipped when `baseCcy` is absent or blank. |
| OBS-002 | `lib/features/strategy/presentation/strategy_wizard_dialog.dart` `_loadInstruments` and `_buildSelectionStep` | The dropdown uses that filtered list directly. |
| OBS-003 | `lib/features/support_resistance/data/market_repository.dart` `getInstruments` | The existing market catalog derives base currency from a strict instrument ID when `baseCcy` is empty. |
| OBS-004 | `lib/features/orders/presentation/orders_screen.dart` | The AppBar has a standalone title and watches the trade session elsewhere. |
| OBS-005 | `lib/features/orders/presentation/widgets/trade_account_controls.dart` | A full-width Card combines account status, explanatory copy, close-all action, and operation recovery. |

HYP-001: Blank or absent SWAP `baseCcy` causes the empty strategy list. This is strongly supported by code and a parallel repository implementation; it has not been verified against live OKX in this planning cycle.

## Contract

### REQ-001 / AC-001

Given a live linear USDT SWAP row with a valid `BASE-USDT-SWAP` ID, empty or absent `baseCcy` must use the base parsed from that ID. A nonempty but conflicting `baseCcy` must still be rejected. Keep existing filters for market type, state, settlement, contract type, malformed IDs, and duplicates. The wizard must offer accepted instruments for selection and continue loading levels on selection. An empty valid result or request failure continues to show its existing error path.

### REQ-002 / AC-002

The title remains `Quản lý Giao dịch`. An adjacent, compact icon reflects `tradeSessionProvider.isAuthenticated` and has accessible Vietnamese status text for signed-in and signed-out states. When authenticated, the close-all area contains the compact action button only; it is not stretched to the full card width. When unauthenticated, no empty close-all container appears. Existing confirmation, disable conditions, pending-operation recovery, API/session errors, progress, and result feedback stay accessible outside the compact button area. The separate Settings login/logout controls remain intact.

## Design and invariants

- Strategy catalog: match `^([A-Z0-9]+)-USDT-SWAP$`, use capture group as the canonical base, and compare nonblank metadata only when present. Retain sorting and immutable return value.
- Trade title: use a compact row containing the existing title and a status icon with Tooltip/Semantics. The icon is informational and must fit narrow widths.
- Trade controls: render the close-all button without header/account prose in its own compact area. Render actionable pending-operation diagnostics and error/progress/result feedback separately when present.
- INV-001: No order execution, auth, or session semantics change.
- INV-002: Pending-operation lookup remains available and continues to block conflicting close-all actions.
- INV-003: No protected configuration file is read or changed.

## RED / GREEN and acceptance

| ID | Scenario | Independently expected result |
| --- | --- | --- |
| RED-001 | Valid SWAP with blank/missing `baseCcy`; conflicting nonblank metadata | Valid IDs appear; conflict is excluded. Current code fails the first expectation. |
| GREEN-001 | Existing and new strategy catalog cases | Valid live linear USDT SWAPs are listed; all existing exclusions remain. |
| RED-002 | Authenticated and signed-out Trade Management layouts | AppBar status icon follows session state; compact close-all area contains only the action button. Current layout fails. |
| GREEN-002 | Close-all and pending-operation flows | Existing action/confirmation/recovery tests pass with the new layout. |

No public API, persistence, permission, or environment contract changes. No external configuration action is required. No deployment/migration action is part of this change.
