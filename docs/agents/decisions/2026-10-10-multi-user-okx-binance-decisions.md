# Decisions: Multi-user OKX and Binance expansion

Status: ACTIVE — proposed defaults for plan approval, not execution approval
Date: 2026-10-10
Specification: `docs/agents/specs/2026-10-10-multi-user-okx-binance-design.md`
Plan: `docs/agents/plans/2026-10-10-multi-user-okx-binance.md`

## User decisions

- D-001: Research expansion to multiple users, focusing on OKX and Binance; prioritize UX/UI and processing speed. Create/check out a new branch and produce a detailed plan. Do not implement tasks yet.
- D-002: The user explicitly delegates suitable proposals for unresolved choices: "Nếu có thắc mắc thì bạn tự đề xuất sao cho phù hợp với hệ thống nhất." Defaults below are visible proposals under that delegation, not claims about existing deployment or approval to activate external services.
- D-003: Branch `codex/multi-user-okx-binance-plan` starts from local `main`, commit `a31553ca82e0d4a3648df8197173c66e955c9266`; verified by `git merge-base main HEAD` and `git log -1` after checkout. Working tree was clean before checkout. No fetch was performed; remote currency is unverified.

## Authorized planning assumptions

| ID | Proposed choice | Reason | Dependencies / invalidation |
|---|---|---|---|
| A-001 | One app user owns multiple exchange connections; each connection belongs to exactly one user. No organizations, shared access, or delegated trading in v1. | Smallest secure extension of personal account workflows. | REQ-001/002/004; replan for shared ownership. |
| A-002 | Invitation-only beta. Username/password, per-user TOTP and single-use recovery codes; reuse local scrypt/TOTP helpers. An operator creates/revokes invites through an offline administrative command. Public registration, email delivery, social login and external IdP are later decisions. | Avoid activating a new external identity service and reuse existing security helpers without retaining singleton login. | REQ-001; replan before public signup. |
| A-003 | PostgreSQL is the production multi-user store; SQLite remains an isolated legacy/dev path and offline migration input. One Python modular backend plus bounded worker processes initially; no microservice rewrite. | Sessions and singleton SQLite write transactions are a concurrency boundary. | REQ-002/006/007; infrastructure application is user-owned. |
| A-004 | Credential material is encrypted on the backend using vetted AES-GCM with a separate, versioned runtime encryption key; no agent-generated cryptography. API permissions should be read-only first, optional trading, no withdrawal. Browser retains no exchange secrets. | Enables background strategies and cross-device use while containing disclosure. | REQ-002; production dependency/key provisioning remains external. |
| A-005 | Preserve current OKX-supported behavior. Add Binance Spot balances/open orders/market reads and standard USDⓈ-M Futures positions/orders/market reads first; then controlled USD-M position actions/cancellation. Enable Binance strategies only after their supported modes pass adapter and demo gates. | Existing strategies are SWAP-centric. Equivalent feature names do not imply equivalent exchange semantics. | REQ-003/004; COIN-M, options, margin loans, Portfolio Margin, withdrawals and transfers excluded. |
| A-006 | Trades always target one explicit connection, product and position/order identity. Combined overview is read-only; no cross-account close-all. A remote account has one canonical connection identity/owner, including revoked tombstones; same-owner relink reactivates that identity and retains unresolved-command barriers. No owner transfer in v1. Duplicates are rejected without revealing another owner. | Prevent duplicate schedulers and revoke/relink bypass of uncertain commands. | REQ-004/005; legitimate ownership transfer requires separate design. |
| A-007 | Beta sizing: 100 concurrently active users, 1,000 linked connections, at most 200 actively refreshed accounts, 20 accounts with running strategies. Admit at most two foreground accounts per user, one executing mutation per connection. Stress at 500 users to measure degradation, not promise support. | Establishes an explicit benchmark instead of an unlimited scalability claim. | REQ-006; replan admission/resource budgets if sizing changes. |
| A-008 | Optimize existing gateway/coalescing/pooling first with adaptive foreground polling. Plan server-owned exchange streams and client push as a gated second stage; do not couple beta to a new ASGI/runtime deployment. Public data is shared, private data isolated. | Fits existing WSGI runtime and prior gateway architecture; measures benefit before runtime expansion. | REQ-006; event push becomes a separate approved implementation plan. |
| A-009 | Preserve Flutter, Riverpod, current monochrome tokens and native controls. Build F2 onboarding/connection management and explicit account context; keep Vietnamese UI and existing USDT/VND presentation semantics. | Reuse beats a frontend rewrite. | REQ-005; branding/localization expansion is separate. |
| A-010 | Define new user-owned setup inputs in `backend/.env.multiuser` and `backend/requirements-multiuser.txt` without reading or creating them. Proposed values and operator actions are documented in the spec. | Makes infrastructure dependencies reviewable without claiming current configuration. | REQ-007; exact package release pin/runtime availability must be verified before setup. |

## Open questions and future gates

No unanswered product question blocks this research plan: D-002 authorizes the proposals above. Actual deployment topology, installed dependencies, region/eligibility, production hardware, exchange permissions and credential-vault provisioning are unverified. They are explicit execution/launch preflight gates, not inferred facts. No production connection, secret retrieval, order, commit, push or deployment is authorized by this plan.

For approval, accept or amend A-001–A-010. A materially different market scope, account ownership rule, authentication service or capacity target requires a revised contract before affected implementation.
