# Task 118 — Combined account views and credential UX

Status: PASS
Agent Role: implementation_executor
Executor Class: E1
Target Model: gpt-6-luna
Target Effort: xhigh
Target Route: gpt-6-luna / xhigh
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Specification: `docs/agents/specs/2026-10-25-binance-direct-reads-design.md`
Plan: `docs/agents/plans/2026-10-25-binance-direct-reads.md`
Plan Steps: P03
Requirements / Acceptance: REQ-004,007,008 / AC-004,007,008
Frontend Level: F1
Frontend Design Brief: N/A — no material redesign

## 1. Dispatch / Definition of Ready
Explicit user approval of the presented plan and predecessors T117 = PASS are required. No unresolved product decision may be delegated. Spawn with the exact model AND effort above, role implementation_executor, no inherited route. Requested route: gpt-6-luna / xhigh (E1-T118-001); effective route: unavailable; dispatch status: UNVERIFIABLE. Record MATCH or UNVERIFIABLE only from actual dispatch evidence. Mismatch stops mutation; unavailable binding is BLOCKED_ROUTE. Follow repository baseline, Ponytail minimal-complete rules and RTK-first/context profile. No nested agents.

## 2. Objective and Contract
Revision: 2 — account views only (D-007).
Implement P03 with neutral source results rather than fail-fast aggregation. Keep asset rows separate per exchange/wallet. Only explicit OKX provenance plus original OKX DTO permits existing backend entry; guard both UI and entry. Reuse existing card/form primitives. No Binance write controls or backend payload changes. Expose incomplete/history coverage and cancellation status accessibly; use lazy lists and no render-triggered rescan.

Done when referenced AC and all verification/build gates pass; related production consumers remain buildable. Preserve specification INV-001..005 and approved D-001..007.

## 3. Allowed Write Surface
Source files only:
- `lib/core/exchange/exchange_account_providers.dart (new)`
- `lib/core/widgets/exchange_icon.dart (new local vector/painter widget)`
- `lib/features/portfolio/data/portfolio_repository.dart (neutral aggregation seam, retain native reader)`
- `lib/features/portfolio/presentation/providers/portfolio_provider.dart`
- `lib/features/portfolio/presentation/portfolio_screen.dart`
- `lib/features/portfolio/presentation/portfolio_details_screen.dart`
- `lib/features/portfolio/presentation/widgets/portfolio_currency_amount.dart`
- `lib/features/orders/data/order_repository.dart (neutral aggregation seam, retain native reader)`
- `lib/features/orders/presentation/providers/order_provider.dart`
- `lib/features/orders/presentation/orders_screen.dart`
- `lib/features/orders/presentation/widgets/order_cancellation_control.dart`
- `lib/features/orders/presentation/providers/order_cancellation_flow_provider.dart (source entry guard only)`
- `lib/features/orders/presentation/widgets/order_notional.dart`
- `lib/features/orders/presentation/widgets/order_filter_controls.dart (source-aware category semantics only)`
- `lib/features/orders/presentation/widgets/trade_account_controls.dart (explicit backend scope label and compatibility invalidation of affected OKX display providers only)`
- `lib/features/orders/presentation/providers/position_action_flow_provider.dart (existing successful-action display invalidation callback only; no backend authority/session/API behavior change)`
- `lib/features/settings/presentation/settings_trade_access_page.dart`
- `lib/features/settings/presentation/settings_screen.dart (exchange credential labels only)`

Test files only:
- `test/features/portfolio/combined_exchange_portfolio_test.dart`
- `test/features/orders/combined_exchange_orders_test.dart`
- `test/features/orders/combined_exchange_test_fixtures.dart (new deterministic neutral-source fixture/override helper for affected existing Orders widget tests; no product logic)`
- `test/features/settings/binance_credentials_page_test.dart`
- `test/features/portfolio/*.dart (affected existing tests only)`
- `test/features/orders/**/*.dart (affected existing tests only)`
- `test/features/settings/*.dart (affected existing tests only)`

Test globs mean non-configuration Dart behavioral tests only. New required support files outside this explicit surface require coordinator scope review before writes.

## 4. Forbidden Scope
Market, Fractal, support/resistance, Strategy and watchlist behavior remain OKX-only; no source/quote/persistence migration for those features.
Never inspect/read/search/diff protected repository configuration/environment files or change them. No dependency/lock/build/CI/runtime settings changes, credential retrieval, backend/Strategy behavior changes, native generated DTO regeneration, unrelated refactors, Git state/history mutation, external code/log upload or deployment. Do not change canonical plans/tasks/status or append telemetry; coordinator owns those. Return BLOCKED if required change exceeds this contract or reveals missing semantics.

## 5. External Configuration
None planned. Existing build settings are opaque inputs. Keys are user-entered through application UX. If a new protected setting becomes necessary, stop and report the exact non-secret target/location/semantics needed; never inspect it.

## 6. RED then GREEN
Meaningful negative verification, named `RED-118` cases:
Fail/unconfigure/rotate one source while another succeeds, remove a valuation quote, collide source order IDs, fail credential save and try backend cancellation from a Binance active-limit row. Require explicit partial totals and zero Binance backend calls.

Primary success verification, named `GREEN-118` cases:
Combined equity is 195 for the independent spec fixture. Both sources render/refresh with icon/wallet identity; scan progress/cancel/resume is coherent; independent Binance credential editing works. Preserve privacy/currency/timezone and existing OKX backend actions/session checks. Test narrow/desktop layout and source semantics.

During diagnostics use the narrowest check. Once implementation is ready, formal RED precedes GREEN. Expected values derive from the spec/independent fixtures, never the implementation's output. Named prefixes must cover the relevant test files so commands exercise the entire scenario set.

RED command: `rtk flutter test --no-pub test/features/portfolio/combined_exchange_portfolio_test.dart test/features/orders/combined_exchange_orders_test.dart test/features/settings/binance_credentials_page_test.dart --plain-name RED-118`
GREEN command: `rtk flutter test --no-pub test/features/portfolio/combined_exchange_portfolio_test.dart test/features/orders/combined_exchange_orders_test.dart test/features/settings/binance_credentials_page_test.dart --plain-name GREEN-118`
Then run complete relevant files/groups from plan section 7. Ceiling: V3, never full suite per task. Escalate only for demonstrated shared-surface regression/missing contract evidence. Later edits invalidate only affected evidence; repeat both if their shared basis changes. Capture concise actual command/result/counts and RED-before-GREEN order.

## 7. Buildability Gate
Required: YES. Affected canonical build unit: full Flutter application.
Exact command: `rtk flutter build web --no-pub`.
Run after the last task-local executable/test change; report exact target and exit/status. Focused test compilation is insufficient. Additive/backward-compatible boundary is required; no later task may repair this task's build. Changed-source build error -> REWORK; genuine pre-build toolchain failure -> BLOCKED_ENVIRONMENT. No dependency installation or protected-file diagnosis.

## 8. Frontend / Audit Handoff
Reuse existing AppPalette, typography, forms, cards and locale formatting. Pinned local web-interface checklist, source/icon semantics, keyboard/focus, narrow/desktop overflow and loading/partial/error states are mandatory; rendered visual status must be honest. No React/aesthetic skill or F2 redesign.
Return changed source/test paths, AC mapping, formal RED/GREEN evidence, relevant regression results, fresh build evidence, limitations and sanitized telemetry envelope. Do not claim live private API or device/CORS verification from mocks/web compilation.

## 9. Checklist
- [x] Approval and predecessor PASS confirmed by coordinator
- [x] Explicit role/model/effort dispatch; no inherited route
- [x] Bounded source/test implementation and relevant regression tests
- [x] Formal RED observed before GREEN
- [x] Relevant file/group checks within planned ceiling
- [x] Fresh task-local full Flutter web build PASS
- [x] No protected content accessed/changed; no unapproved external/Git action
- [x] Compact evidence report returned to coordinator

## 10. Coordinator Audit
Scope / AC / minimality / units / source isolation / action authority: PENDING.
RED-before-GREEN / tests / buildability / route compliance: PENDING.
External configuration and live verification limitations: PENDING.
Verdict: PENDING (PASS | REWORK | BLOCKED).

## 11. Early coordinator / independent review checkpoints
Read-only R2-T118-AUDIT-001 (explicit gpt-6.1-sol/medium, effective unavailable UNVERIFIABLE) plus coordinator ground-truth review fed existing-contract corrections into the active inner loop:
- Independent source/product AsyncValues and synchronous composition for Portfolio, Positions, Pending and OKX History. Held/failed/rotating one source cannot suppress successful unaffected data. Discard obsolete rows only for changed generation.
- Healthy-source quote refresh/15-second expiry must continue during partial/auth-terminal sources; account latency cannot freeze price freshness. Skip automatic retries for auth-terminal sources; explicit manual refresh remains recovery.
- Native Futures collateral row uses reportedTotal wallet balance; aggregate native margin equity remains counted once.
- Reader position issue sink propagates into partial rows/coverage warnings.
- Reuse native OKX cards and resolveOrderNotional with explicit source plus original DTO, preserving liquidation/PnL ratio/leverage/type/detail and contract units. No invented derivative price*contract notional.
- Both UI and controller action entry prove OKX source and original native DTO; actual Binance collision attempt test proves zero backend calls.
- History UI exposes completed/failed/pending, actionable reason/cooldown deadline, native recent-page/retention/catalog coverage, accessible throttled live announcements and stop/resume. Merged ordering includes deterministic source/product/kind/symbol/ID tie-breaker.
- Mobile/desktop rendered synthetic-fixture evidence requested within existing allowed tests, no new dependency/configuration or live credentials.
All are approved REQ004/007/008 compatibility/verification requirements; no scope expansion. Independent final verdict waits final code/test/build state. No runtime child close/release primitive is exposed.

## 12. Bounded caller-surface amendment (coordinator-reviewed)
Existing approved OKX action compatibility requires display invalidation after the neutral consumer migration. Source evidence: position_action_flow_provider.dart existing refresh callback and trade_account_controls.dart existing action/session invalidation points still target legacy display providers. Add only current OKX source-provider invalidation at those same points. Allowed surface amended above; backend/session/permission/action payload logic remains untouched. This is a required caller/wiring consequence of REQ004/007, not a product/architecture/security change or external action. Add focused regression/asserted invalidation in existing allowed Orders tests; no new execution approval required within current authorization.

## 13. Bounded final audit remediation R1
Agent Role: implementation_executor; Executor Class: E1; Target Model: gpt-6-luna; Target Effort: xhigh; Route Binding EXPLICIT; Parent Route Inheritance FORBIDDEN. Reuse current explicitly bound executor (logical E1-T118-R1-001); existing approved scope.
- AUD-118-001 (independent R2 audit REWORK): global any-source-loading timer/manual gates stop healthy Orders refresh when another source is held. Remove global gate; per-source helpers skip loading and terminal sources individually, refresh eligible healthy sources without restarting held requests. Deterministic >16-second held Binance test proves OKX refresh plus single-flight held source.
- AUD-118-002 (coordinator source proof): valuation providers use account AsyncValue.valueOrNull during refresh and _portfolioSourceFromAsync/_expireStalePortfolioQuotes preserve prior result flags unchanged. Retained account balances/native equity can remain complete/fresh-looking while private refresh is held. Preserve same-generation rows and fresh quotes but explicitly mark retained account state updating/stale/partial; test first success then held refresh, visible warning/partial total and unaffected exchange retained.
- Existing V3 fixtures overriding legacy display providers must migrate only provider seams to neutral source fixtures while preserving original behavioral expectations; no test weakening.
After affected fixes/tests, repeat invalidated named RED-118 before GREEN-118, complete relevant V3, fresh full Flutter web build. Later test-only changes invalidate only dependent evidence. No protected configuration/action authority/backend payload changes.

## 14. Bounded test support surface approval
Coordinator reviewed executor request: allow new test/features/orders/combined_exchange_test_fixtures.dart to centralize native OKX-to-neutral deterministic fixture results and explicit inert Binance overrides for the affected existing widget tests. Preserve native DTO provenance, original assertions and all source failure semantics; no production behavior, configuration, external requests or broad test rewrites. Existing test globs remain affected tests only. This reduces duplicate fixtures while retaining verification contracts.
Preserve existing Portfolio account-poll cadence at five seconds; source-specific quote freshness/cache remains fifteen seconds, host budget still authoritative. Do not change old timing assertions to match an unsolicited cadence change.

## 15. Final parity/test-quality remediation R2
Agent Role implementation_executor; E1 gpt-6-luna/xhigh EXPLICIT, same bound writer; logical E1-T118-R2-001.
AUD-118-003 (independent audit): existing Portfolio capital/unrealized PnL/ratio/currency/color behavior was removed and tests changed to findsNothing or moved to Details. This is unapproved behavior loss/test weakening. Restore equivalent source-labeled native OKX capital/PnL/ratio on PortfolioScreen, original main-screen privacy, signed dual currency and near-zero coloring expectations. Reuse native DTO/formatters, own-exchange quotes and explicit units. Do not invent Binance Spot cost basis/PnL or convert Futures USDT PnL through an underlying price; combined equity remains195 fixture. Restore original selected-currency heading semantics where applicable. Source-scoped native metric display is acceptable alongside combined headline.

Coordinator reconciliation for refresh tests: account and currency-rate reads may start concurrently so an unrelated pending rate cannot block manual account refresh (previously authorized inner-loop fix). Preserve safety assertions explicitly: initial read1, one toolbar manual read2, concurrent pull causes no third read; after disposal completing pending rate cannot start any further account read. Rename/restate affected test only to make this same safety contract explicit; changing counts alone is insufficient. Preserve independent original5s automatic cadence proof. This does not authorize other assertion removals.
Repeat affected RED->GREEN and full planned V3, then fresh web build after final changes. Independent audit must reject weakened prior behavior rather than accepting test-only deletion.

## 16. Final Coordinator Audit — PASS
AC-004/007/008 satisfied by per-source account/order providers, source icons and credential editor, independent partial/stale/loading results, native-unit valuation and guarded actions. Independent R2-T118-AUDIT-003 confirms AUD-118-001..003 and prior compatibility issues resolved; coordinator inspected current provider/caller/test diffs and rendered fixtures. Original native OKX cards and main-screen capital/PnL/ratio/currency/privacy/near-zero semantics restored; native contract notional retained; backend payload/session/authority unchanged. Narrow source/test amendments in sections12/14 are accounted for, not unexplained scope.

Formal final evidence reused: exact section6 commands (absoluteRTK, expanded reporter) RED-118 6passed then GREEN-118 14passed. Relevant V3 `rtk flutter test --no-pub test/features/portfolio test/features/orders test/features/settings test/core/widgets/app_startup_test.dart` 224passed. Fresh task-local `rtk flutter build web --no-pub` exit0 after last executable change. Orders group33 and Portfolio parity10 focused passes support regression diagnosis. Final code unchanged after task build. Explicit E1 route requested; effective unavailable UNVERIFIABLE, no inherited route.

Coordinator final integration observed `rtk flutter test --no-pub` exit0,664passed; then fresh `rtk flutter build web --no-pub` exit0, built build/web in24.4s. Both after last executable/test change. Tracked and new Dart whitespace checks clean. No analytical/watchlist changed paths, protected content access or protected-file writes, Git mutation/deploy or external code transmission. No external configuration action required.

Pinned Flutter-equivalent interface audit PASS for scoped semantics, labels/focus/forms, source/status redundancy, responsive/lazy content, locale/timezone and critical loading/error/partial states. Six mobile/desktop PNGs in /private/tmp reviewed for geometry; full visual typography status UNAVAILABLE because test engine renders Ahem block glyphs. This is not a typography/real-device visual PASS. Live private Binance/device/CORS evidence unavailable and not claimed. Build warning-only Wasm secure-storage/Cupertino font diagnostics remain; JS web build PASS. Terminal child results collected; no close/release API available.
Verdict: PASS. Task buildability: PASS. Final repository build: PASS. Test-quality remediation complete.
