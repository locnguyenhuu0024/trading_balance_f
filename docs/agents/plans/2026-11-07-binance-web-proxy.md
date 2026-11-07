# Implementation Plan: Binance Spot and Margin on web through a read proxy

Status: COMPLETE (code); U1 and U2 pending
Approval: "Duyệt, làm đi." (user, chat, 2026-11-07)
Date: 2026-11-07
Tier: M
Plan ID: PLAN-20261107-binance-web-proxy
Specification: `docs/agents/specs/2026-11-07-binance-web-proxy-design.md`

## Preconditions

- U1, user-run first: the VPS ping in `docs/deployment/binance-read-proxy.md` section 1 returns 200. If it returns 451 or 403, this plan stops before any code.
- U1 result was not reported when the user approved. T125 and T126 proceed because the code stays inert without the build define; U1 remains a gate before U2.
- Commit these planning files, and each task on PASS, on `codex/multi-platform-view-only`.

## Planning Workstream Decomposition

Fan-out Required: NO. Skip Reason: SINGLE_MATERIAL_WORKSTREAM. The client is the only code workstream; the nginx location is a user-owned configuration action, written by the coordinator as documentation. Backend application: not touched.

## Tasks

`U1 -> T125 -> T126 -> final audit -> U2 (user applies nginx, builds, checks live)`

| Task | Content | Class | Route |
|---|---|---|---|
| T125 | Client routes Spot and Margin through the proxy, availability gate in reader | E3 | gpt-6.1-terra / high |
| T126 | UI follows availability; Margin chip filter defect | E2 | gpt-6.1-terra / medium |

Executors write code and tests; the coordinator runs RED then GREEN on the host (VAL-005 of the parent plan).

Verification: V3 per task; V4, analyzer, web build at the end. No new dependency.

## Risks

| Risk | Mitigation |
|---|---|
| Binance blocks the VPS location | U1 before any code |
| nginx snippet not syntax-checked here | `nginx -t` before reload; rollback documented |
| Key and signature pass through Cloudflare and the VPS | Read-only key guidance, no access log, secret stays on the device |
| Shared IP weight limit if others use the open route | Origin check; per-exchange lane backs off on 429 |

## Rollback

Remove the nginx location or build without the define. USD-M on web is unaffected.
