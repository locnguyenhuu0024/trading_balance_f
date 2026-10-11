# Task 114 — Multi-user connection experience and scoped Flutter data

Status: PASS — SOURCE_FIXTURE checkpoint under D-008; real venue/demo, Android-device and launch acceptance pending
Agent Role: implementation_executor
Executor Class: E1
Target Model: gpt-6-luna
Target Effort: xhigh
Target Route: gpt-6-luna / xhigh
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Dispatch Route Status: UNVERIFIABLE (runtime does not expose effective route after explicit binding)
Requested Model / Effort: gpt-6-luna / xhigh (explicit E1-T114-001 spawn)
Observed Effective Model / Effort: unavailable
Specification: `docs/agents/specs/2026-10-10-multi-user-okx-binance-design.md`
Plan: `docs/agents/plans/2026-10-10-multi-user-okx-binance.md`
Plan Steps: P05
Requirements: REQ-005, REQ-001, REQ-002, REQ-003, REQ-004
Acceptance Criteria: AC-005
Frontend Level: F2
Frontend Design Brief: docs/agents/specs/2026-10-10-multi-user-okx-binance-frontend-brief.md
Visual Review Required: YES

## 1. Objective and preconditions

Implement P05 exactly as defined in the canonical plan. Done when the referenced behavioral contracts, relevant regression, final task build and independent audit pass.
Predecessors/readiness: T112 = PASS; approved F2 brief; T113 capability can be mocked without changing contract. A-001–010 and INV-001–006 are binding. No product/architecture invention by the executor.
Source-development readiness follows D-008: T112 source/runtime PASS suffices for fixture-first implementation; venue verification and activation remain blocked. Binding consumer/API refinement: `docs/agents/validation/2026-10-11-t114-preflight.md`.
Runtime/setup: Use mocked fixed v2 endpoints for widget/provider tests; installed Flutter deps consumed opaquely. Android SDK/device is external verification if unavailable.
Provisioning/installation is operator-owned and is not part of the executor write scope.

## 2. Allowed write surface

- `lib/core/session/ (new hand-written Dart source)`
- `lib/features/connections/ (new domain/data/presentation Dart source)`
- `lib/core/network/backend_data_client.dart`
- `lib/core/network/backend_data_session.dart`
- `lib/core/network/okx_websocket_service.dart`
- `lib/core/security/secure_storage_helper.dart`
- `lib/core/navigation/main_navigation_shell.dart`
- `lib/features/market/presentation/market_screen.dart` (existing public consumer: owned venue/product routing, foreground polling and approved quote freshness only)
- `lib/features/orders/data/trade_api_client.dart`
- `lib/features/orders/data/order_repository.dart`
- `lib/features/orders/presentation/providers/ (affected session/action/order providers)`
- `lib/features/orders/presentation/widgets/trade_action_confirmation_dialog.dart`
- `lib/features/orders/presentation/widgets/trade_account_controls.dart`
- `lib/features/orders/presentation/orders_screen.dart`
- `lib/features/orders/presentation/widgets/position_action_controls.dart`
- `lib/features/orders/presentation/widgets/order_cancellation_control.dart`
- `lib/features/orders/presentation/widgets/responsive_order_grid.dart` (only if necessary for lazy normalized rows)
- `lib/features/portfolio/data/portfolio_repository.dart`
- `lib/features/portfolio/presentation/providers/portfolio_provider.dart`
- `lib/features/portfolio/presentation/portfolio_screen.dart`
- `lib/features/market/presentation/providers/market_provider.dart`
- `lib/features/strategy/data/strategy_api_client.dart`
- `lib/features/strategy/data/strategy_market_repository.dart`
- `lib/features/strategy/presentation/providers/strategy_dashboard_provider.dart`
- `lib/features/strategy/presentation/strategy_screen.dart` (necessary owned-scope consumer; preserve supported native strategy flows)
- `lib/features/strategy/presentation/strategy_wizard_dialog.dart` and `lib/features/strategy/presentation/strategy_automatic_draft_dialog.dart` (necessary existing owned-scope callers; preserve supported dialogs)
- `lib/features/strategy/presentation/strategy_retry_dialog.dart` and `lib/features/strategy/presentation/strategy_settings_dialog.dart` (necessary existing supported retry/settings callers; owned-scope compatibility/fences only)
- `lib/features/support_resistance/data/market_repository.dart`
- `lib/features/settings/presentation/settings_trade_access_page.dart`
- `lib/features/settings/presentation/settings_screen.dart` (necessary settings navigation entry to the owned connection page only)
- `lib/main.dart`
- `test/multiuser/ (new Dart tests)`
- `test/ (explicitly affected existing session/navigation/refresh/confirmation fixtures only)`
- `backend/exchanges/contracts.py` (optional additive safe target fields only)
- `backend/exchanges/okx_adapter.py` (populate those fields from native values only)
- `backend/tests/test_exchange_contracts.py` and `backend/tests/test_exchange_read_routes.py` (affected additive serialization/target fixtures only)

Read only the source/tests/docs needed for the listed contracts. New interfaces stage compatibility with existing consumers; leave the affected canonical unit buildable. Directory surfaces are restricted to the described hand-written source/test roles, not arbitrary settings or generated files.

## 3. Forbidden scope and reuse

All protected environment/runtime/dependency/build/CI/deployment/workspace files: content access and writes forbidden. No root recursive content search without explicit non-protected allowlist. No new dependency installation/manifest edits, source upload, secret retrieval, live account operations, migration of production data, commit/push or deployment. No unrelated feature redesign.
Reuse existing gateway/session fences/security helpers/OKX transport/native controls as applicable. If scope expands or a contract is insufficient, return BLOCKED to coordinator.

## 4. Executor contract

1. Implement invitation/login/MFA and backend-managed exchange connection flow from approved brief, with masked explicit paste and no browser exchange-key persistence.
   Actual POST /v2/connections verifies and persists atomically; label the explicit operation accordingly and show its safe summary after success. Do not invent a separate unsaved verify/save API. Existing approved re-entry migration takes precedence over reading/prefilling legacy secrets.
2. Introduce immutable UserSession/ConnectionScope, scope generation and typed v2 DTOs; migrate relevant repositories through existing single backend boundary.
3. Add account context strip/picker/product/capability states, read-only combined overview with partial/conversion completeness.
4. Clear A private data/actions synchronously on B selection; ignore delayed A response/401; preserve pending results on original account.
5. Use existing native tokens/navigation/forms/confirmation; user-triggered legacy credential migration only, consent before local removal; no automatic secret upload.
6. Use selective Riverpod row subscriptions/lazy lists, foreground read leases and adaptive coalesced polling; preserve existing quote age ≤15s.

Follow P05; preserve the single backend boundary, owner filtering, decimal units, server-proven lifecycle and bounded resources. Expected unsafe-path behavior is defined by spec §8, not implementation convenience.

## 5. Tests and formal RED → GREEN

Behavioral pairs: RED/GREEN-005.
RED scenario and independently expected result: Delayed A payload/401 arrives after B selection; denied capability/expired confirmation/failed verification and malformed paste cannot publish wrong private rows or authorize trading. Web secrets remain absent after confirmed migration.
GREEN scenario and independently expected result: User logs in, connects read-only and trade-capable accounts, switches OKX/Binance with correct DTOs and context, completes supported prepared mock action once, and logs out clearing private state.

Method: `flutter test test/multiuser`; name/select focused negative then success cases explicitly and record order, setup, outcome and exit. Proposed suites do not exist yet; these are implementation deliverables, not currently passing tests. Add a failing-baseline regression where new behavior is absent. Use only fabricated keys/account payloads.

Inner-loop diagnostics are narrow/non-authoritative. At readiness run formal RED before GREEN, then relevant regression and final build. Later edits rerun affected evidence only; restart pair if shared verification basis changes.
Verification ceiling: V3 (focused related tests). Full V4 belongs to T116 final integration only, justified by global auth/storage/DTO changes.
Escalation trigger: shared consumers changed, related regression failure, or task proof lacks required concurrency/runtime evidence; document reason before widening.

## 6. Task buildability and frontend evidence

Required: YES
Canonical build unit: Flutter application
Exact secret-free build command: `flutter build web --no-pub`
Run after the final executable/test change. Result/exit: PASS / 0 after final source/test changes; exact evidence in docs/agents/validation/2026-10-11-t114-final-verification.md. Buildable compatibility staging required; no PASS while awaiting a successor repair.
Backend compileall is paired with import/runtime tests; mocks cannot substitute PostgreSQL multi-process checks.

Frontend: approved F2 brief required; native theme/form/controls reused. Pinned interface audit and mobile/desktop rendered review required; React guidance N/A. Check 360/768/1440px, 200% text, dark/light, keyboard/semantics, 48px targets, critical loading/error/permission/confirmation states. Run flutter analyze and canonical web build. Device/runtime evidence unavailable must be marked BLOCKED_EVIDENCE, never visual PASS from source alone.

## 7. External actions, stop conditions and audit

External configuration/actions are spec §12 and the setup prerequisite above, all user-owned. No agent reads/creates protected files. Integration needing unapplied inputs is BLOCKED; report exact safe target/key/placeholder and validation step already specified in the spec. Unknown production topology/paths block launch, not synthetic checks.

STOP for missing approval/predecessor/setup, observable route mismatch, missing owner/capability contract, scope expansion, secret-bearing output, unavailable required verification or broken task build. Unknown exchange outcome is retained and reconciled; never resolve it by repeating a write.

Coordinator owns canonical status/audit/telemetry. Writer returns exact safe commands, scenario results, changed path names, build exit, limits and external-action list. Audit checks scope, AC, test quality, RED order, architecture, route binding, buildability, protected-file compliance and independently observed source. Verdict: PENDING.

## 8. Pending checklist

- [x] User execution approval and source-development predecessor ready under D-008; venue gates remain pending.
- [x] Explicit implementation_executor gpt-6-luna/xhigh dispatch; no inheritance, effective route unavailable/UNVERIFIABLE.
- [x] Fixture setup uses installed Flutter3.47.5/Dart3.13.4 and existing dependencies opaquely; no protected values read or provisioning performed.
- [x] Listed contract implemented with buildable staged consumers.
- [x] Formal RED observed before GREEN; regression ceiling respected.
- [x] Final canonical task build recorded.
- [x] Applicable visual/device/runtime evidence recorded honestly.
- [x] No protected-content access, external secret transmission or unapproved live action.
- [x] Independent coordinator audit PASS.

## 9. Resume execution — 2026-10-11

User explicitly requested continuation from the pause checkpoint. The previous writer/auditor are unavailable in this chat runtime (only coordinator listed); no prior writer is running here. Sole replacement serial writer E1-T114-RESUME-001 explicitly dispatched gpt-6-luna/xhigh, fork none; effective route unavailable/UNVERIFIABLE. Existing implementation and valid evidence are preserved. Scope, requirements and pending audit findings are unchanged; no new planning cycle or approval is required. Final independent audit follows the completed buildable unit. No close/release primitive is exposed; lifecycle cleanup limitation remains recorded. No Git mutation or venue action is authorized.

Coordinator caller-surface refinement: retry/settings dialog files are required to preserve already approved native strategy workflows under the v2 owned session. Their reviewed changes are session guards/callback compatibility only; no new feature/architecture/admission or redesign is authorized. Literal allowlist omission was identified after initial edits and corrected explicitly; future outside-surface edits require coordinator review before writing.

Coordinator public-consumer refinement: market_screen.dart is necessary for approved venue/product routing and foreground quote freshness. Existing affected market refresh fixtures are included. Its initial consumer edit preceded literal inclusion, a second ordering deviation; no additional redesign or quote semantics are authorized. All further outside-surface changes must be reported before writing.

## 10. Bounded E2 completion handover

E1-T114-RESUME-001 completed its atomic AUD-035 edit and explicitly confirmed frozen source/tests, no running command and terminal handover. Its diagnostic checkpoint passed25/25 private-data/market cases, plus the corrected owned-v2 stale-list case1/1. These are not final task acceptance. E2-T114-R01-001 is now the sole serial writer, explicitly dispatched gpt-6-luna/max with fork none, effective route UNVERIFIABLE. Contract: tasks/task_114_r01_lifecycle_confirmation_completion.md. Classification follows concrete asynchronous authority/confirmation/lifecycle reworks, not elapsed time. Remaining formal pair, V3 regressions, final application build, refreshed visual evidence and independent R3 audit remain pending.

## 11. Final source/fixture acceptance — 2026-10-11

Authoritative coordinator and independent R3 PASS at SOURCE_FIXTURE; AUD001–039 closed. Final completion executor E2 gpt-6-luna/max (initial E1 route retained above as dispatch history); all child requests explicitly bound, effective runtime UNVERIFIABLE. Latest multiuser73/73, strategy171/171, cross-area106/106; unaffected core/order/backend evidence retained; post-last-edit canonical webbuild0/diff0. Analyzer exit1 remains125 advisory warning/info, zeroerrors, not globally clean. Actual font-backed rendered review PASS, Android-device and real venue/demo acceptance remain separate pending launch gates; production Binance remains locked.

Final audit: docs/agents/validation/2026-10-11-t114-source-audit.md. Exact commands/order/freshness/render evidence: docs/agents/validation/2026-10-11-t114-final-verification.md. Source/tests frozen, all agents terminal, no running command. No commit/push/deployment, dependency/configuration change or live venue action. T115/T116 are not started.
