# Design Specification: ALL transaction filter and mobile filter row

Status: READY_FOR_PLAN
Date: 2026-09-30
Tier: M
Decision Ledger: N/A — the user clarified the only material product choice in conversation.

## Objective and scope

REQ-001: The transaction type selector offers `ALL` for Positions, Pending, and History. `ALL` shows the complete result across supported transaction types for the selected status.

REQ-002: At mobile widths, the Status and Transaction Type selectors occupy one row and remain usable without overflow. Desktop behavior remains a two-column row.

In scope: the orders screen, its filter widget, providers/repository, and focused tests. Out of scope: other screens, backend/API contracts, dependencies, protected configuration, pagination changes, and unrelated visual redesign.

## Evidence

- OBS-001: `OrderFilterControls` lists `SPOT`, `MARGIN`, `SWAP`, `FUTURES` and uses a `Column` below 600 px.
- OBS-002: `orderFilterProvider` defaults to `MARGIN`; `ordersFutureProvider` and `positionsFutureProvider` forward its value unchanged.
- OBS-003: `OrderRepository` sends `instType` in each request; SPOT positions return an empty list locally.
- OBS-004: `OrdersScreen` refreshes the active provider once per second and has a SPOT-only positions message.
- D-001: The user confirmed `ALL` applies to all three statuses.

## Behavior and data contract

- Positions with `ALL` query `MARGIN`, `SWAP`, and `FUTURES`; SPOT has no open-position result. Pending and History with `ALL` query `SPOT`, `MARGIN`, `SWAP`, and `FUTURES`.
- The repository sends only concrete supported `instType` values. Merge all successful results; any failed request fails the entire ALL load so a partial result is never presented as complete.
- Pending and History merged results sort by numeric `cTime` descending. Missing or invalid timestamps follow valid timestamps; equal timestamps retain input order. Each single-type path retains its existing behavior and the default remains `MARGIN`.
- The existing SPOT positions explanation applies only to SPOT, not ALL. Existing cards and manual pull-to-refresh remain usable.
- To limit request volume from the fan-out, automatic refresh for ALL is every 5 seconds; single-type refresh remains every 1 second. A refresh cycle must not intentionally launch another cycle while its current request is unresolved.
- Both selectors are peers in a `Row` at mobile and desktop widths. Their expanded fields fit a 390 px viewport without clipping or render overflow; preserve readable labels and selected values.

## Invariants and failures

- INV-001: The ALL literal is never sent as `instType` to the API.
- INV-002: Single-type requests, SPOT positions behavior, default selection, and error handling remain intact.
- EDGE-001: An empty ALL result uses the existing status-specific empty state.
- EDGE-002: One failed subtype request shows the existing error state rather than partial data.
- EDGE-003: Unknown `cTime` values sort after numeric timestamps without throwing.

## RED / GREEN and acceptance

- RED-001: With ALL selected and one subtype failing, the provider reports an error and no partial list; SPOT positions remain empty.
- GREEN-001: With ALL selected, mixed fixtures from all relevant subtypes appear for each status, and pending/history are globally newest first. No request contains `instType=ALL`.
- GREEN-002: At 390 px, the two selector rectangles have the same top coordinate, do not overlap, and produce no Flutter overflow exception; choosing ALL emits `ALL`.
- AC-001: Selecting ALL on Positions shows open positions from MARGIN, SWAP, and FUTURES together.
- AC-002: Selecting ALL on Pending or History shows orders from all four supported types together, newest first.
- AC-003: At mobile width, Status and Transaction Type appear on one row with both selections accessible.
- AC-004: A subtype failure in ALL shows an error; single-type and SPOT behavior still work.

No configuration/environment action, schema migration, or rollout step is required. Protected configuration contents are not an evidence source.
