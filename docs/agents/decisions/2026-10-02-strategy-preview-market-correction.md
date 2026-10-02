# Decision Ledger: Strategy preview market correction

Date: 2026-10-02
Status: RESOLVED

| ID | Decision | Authority |
| --- | --- | --- |
| D-001 | Round a computed Long limit price down and a Short limit price up to the current OKX tick before showing or sending it. | User reply on 2026-10-02. |
| D-002 | Keep two separately chosen levels as two separate limit orders even if rounding gives them the same price. | User reply on 2026-10-02. |
| D-003 | For same-side equal-price orders, estimate liquidation after the whole equal-price group is filled and warn that fill order is not guaranteed. | User reply on 2026-10-02. |
| D-004 | Both means at least one Long and one Short limit order, with one nearest entry level on each side. | User's feature specification and correction. |
| D-005 | During wizard setup fetch the public ticker once when opening a coin, without a periodic ticker request; the server retains its fresh quote checks on preview and order actions. | User replies on 2026-10-02. |
| D-006 | Poll live prices only while viewing already-started strategies; do not poll drafts. | User's latest instruction. |
| D-007 | New selected-level IDs and explicit direction are additive to preserve old persisted drafts and preview hashes. | Coordinator compatibility design based on repository behavior. |

Open material decisions: none. No user authorization to execute code, commit, push, or deploy is inferred from these decisions.
