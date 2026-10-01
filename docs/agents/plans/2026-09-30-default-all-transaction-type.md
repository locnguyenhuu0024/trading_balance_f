# Small Change Plan: Default transaction type ALL

Status: IMPLEMENTED_AND_AUDITED
Date: 2026-09-30
Tier: S

## Objective

Opening a fresh Transaction Management screen selects `ALL` as the transaction type while retaining the current Positions status default.

## Evidence and scope

- OBS-001: `orderFilterProvider` in `lib/features/orders/presentation/providers/order_provider.dart` initializes to `MARGIN`.
- OBS-002: The selector already offers `ALL`; the repository already aggregates ALL results for Positions, Pending, and History.
- Allowed product/test surface: `order_provider.dart` and a focused provider/widget test under `test/features/orders/`.
- Preserve explicit user-selected types during the current provider lifetime, the Positions status default, ALL aggregation, and the current refresh timing.
- Out of scope: position action buttons, trade API writes, model changes, protected configuration, generated code.

## Implementation step — P01

REQ-001 / AC-001: A newly created provider scope starts with transaction type `ALL`.

1. Change only the `orderFilterProvider` initial state from `MARGIN` to `ALL`; correct its nearby comment if needed.
2. Add a focused test that checks a fresh provider scope starts at `ALL` and that an explicit selection such as `SWAP` stays selected on subsequent reads/rebuilds.

Formal RED first: set `SWAP` explicitly and observe it remains `SWAP` after a provider read/rebuild; this protects user selection from an accidental reset. Formal GREEN second: start a fresh provider scope and observe `ALL`, with the Positions tab still selected. The expected results follow the stated state contract, independent of implementation output.

Inner loop: narrow diagnostics; formal RED then GREEN once when implementation is ready. V2 ceiling: the focused test file and directly related filter tests; escalate only on a concrete provider/UI regression. Task buildability gate: YES, Flutter web application, `flutter build web --no-pub` after final code change. No external verification or configuration action.

Stop if repository evidence contradicts the single-state default contract. Protected configuration contents remain unreadable and files non-writable.

## Task and approval gate

T33 implements P01, E0 / `gpt-6-luna` / `high`, explicitly bound. Planning workstreams: provider/default selection is one atomic material workstream; fan-out not required (`SINGLE_MATERIAL_WORKSTREAM`). The separate position-action research has UI and API workstreams and its own fan-out.

- [x] No material ambiguity for the default selection
- [x] Scope and RED/GREEN defined
- [x] Buildability command defined
- [x] Explicit execution authorization after this plan is presented (user: "Thực hiện tasks")
