# Task 35 — Flutter position actions

Status: PASS
Agent Role: implementation_executor
Executor Class: E1
Target Model: gpt-6-luna
Target Effort: xhigh
Target Route: gpt-6-luna / xhigh
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Dispatch Route Status: UNVERIFIABLE
Specification: `docs/agents/specs/2026-09-30-position-actions-design.md`
Plan: `docs/agents/plans/2026-09-30-live-position-actions.md`
Plan Steps: P02
Requirements: REQ-001..010
Acceptance Criteria: AC-001..010 (client portions)

## Objective

Implement the Flutter backend client, position identity/model projection, action controls, input and confirmation popups, and result states against the completed T34 API contract. Preserve existing ALL/default and order filter behavior.

Predecessor: T34 PASS. Governing user decisions: D-001..015. Allowed writes: `lib/features/orders/data/okx_position_model.dart`, its two generated application-code companions, new `lib/features/orders/data/trade_api_client.dart`, new `lib/features/orders/presentation/providers/trade_session_provider.dart`, new files under `lib/features/orders/presentation/widgets/` for position actions, `lib/features/orders/presentation/orders_screen.dart`, and focused files under `test/features/orders/`. If the exact client contract requires another source path, return BLOCKED for coordinator scope review. No protected configuration/environment contents may be read or files written; do not write package/build config, backend files, or existing credential code. Do not perform live trades, commit, push, or deploy.

## Contract

Validation VAL-001..003: backend eligibility disables MARGIN DCA and partial close in this release. Render the returned reason and never enable those actions locally. MARGIN direction is determined by backend `posCcy` interpretation, not the sign of `pos`.

1. Use compile-time public `TRADE_API_BASE_URL` with an unconfigured read-only fallback. Keep session bearer only in memory; login uses password plus TOTP, then actionable cards come only from backend-owned positions and show a masked account identifier. The existing display path may remain while logged out, with actions unavailable.
2. Add per-card Add margin, DCA, Partial close, and Close 100% actions, plus a separate account-wide Close all positions control. Follow the backend eligibility and prepare responses; do not infer unsupported MARGIN sizing client-side. Each input path leads to a distinct confirmation popup showing the backend-authoritative target and normalized amount/list. Dismiss/cancel sends no execute; duplicate taps send one; stale/unknown/partial outcomes remain visible and trigger appropriate refresh/status lookup.
3. Preserve mobile usability and update the existing position-card layout test to account for action controls. Keep the existing ALL aggregation and selected filter behavior.

## Verification

Formal RED-002: cancel/dismiss, unsupported identity, stale confirmation, and repeat-tap do not send an execute request; selected full close has one target; close-all ignores display filter. Formal GREEN-002: every eligible action opens a popup with server-prepared details, confirmation sends one execute, and result/position state refreshes. Run RED then GREEN after implementation stabilizes; narrow diagnostics may precede the checkpoint. V2 ceiling: new action tests and directly related orders tests; V3 only on an observed shared-state/layout regression.

- Focused `flutter test --no-pub` for the newly added action tests and affected position-layout/provider tests. Report exact paths, scenarios, and exit/status.
- Task buildability gate: `flutter build web --no-pub` after the final executable/generated-code change. Record exact exit/status.

External configuration: user passes the public API URL using `--dart-define=TRADE_API_BASE_URL=https://<USER_API_HOST>` when building for production; no value is needed for local fake-client tests. User-owned backend secret file and hosting are documented in T34's guide. Local implementation may PASS without live production verification, which remains pending user setup. Stop and report BLOCKED for a backend interface contradiction, unknown material action semantics, or required protected configuration write.

## Coordinator audit

Scope: PASS — backend-owned position identity, HTTPS client, in-memory session and unresolved-operation lookup, confirmation popups, account-wide close-all, and identity-scoped action progress are limited to the allowed Flutter source/test files. Acceptance: PASS for local fake-client behavior; production activation is pending user-owned server setup. RED-before-GREEN: PASS — the initial T35 RED 10/GREEN 9 checkpoint and focused failing regressions for target refresh, unresolved lookup, unsafe URLs/redirects, and card-state attribution were observed before remediation. Affected Orders V2 suite: 37 PASS after the final card-flow edit; URL suite: 4 PASS after the redirect edit. Buildability: PASS — Flutter web build exited 0 after both final Flutter edits, with a nonblocking existing `package:js` WASM warning. The coordinator's redundant final test rerun could not start because this session lacks permission to write the Flutter SDK cache; executor evidence remains the post-edit result. Route compliance: UNVERIFIABLE after explicit E1/E2/E0 bindings. Verdict: PASS. Independent audit found the refresh, unresolved-status, HTTPS, redirect, and card-state issues and each was remediated; a redundant post-fix auditor run failed to start when runtime usage limits were reached, so the coordinator completed the final source/test audit.

## Final audit remediation

- AUD-035-001: Snapshot the tapped position before any await and compare the prepared target to that immutable identity.
- AUD-035-002: Keep UNKNOWN and unresolved PARTIAL operation IDs in the active in-memory session, expose later status lookup, and block new actions until resolution.
- AUD-035-003: Reject non-HTTPS trade API URLs and redirects before credentials or bearer tokens can be forwarded.
- AUD-035-004: Keep action progress/status keyed by complete account and position identity in a page-scoped controller, with dialogs launched from a stable Navigator context. Recheck session and unresolved-operation state immediately before execute.
