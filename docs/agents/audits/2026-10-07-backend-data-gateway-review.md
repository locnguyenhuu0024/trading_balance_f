# Backend data gateway review and remediation

Status: PASS
Tasks: T93,T94,T95,T96,T97
Specification: docs/agents/specs/2026-10-07-backend-data-gateway.md
Plan: docs/agents/plans/2026-10-07-backend-data-gateway.md

## Provisional independent findings

Read-only R2 reviewers explicitly bound to gpt-6.1-sol/medium inspected current non-protected sources while T93/T94 verification was active. Coordinator adopted the following findings and issued bounded corrections to the original E2 gpt-6-luna/max executors. These are within the approved requirements; no coordinator product edits or new authorization.

| ID | Task / Requirement | Finding | Required proof | Status |
|---|---|---|---|---|
| AUD93-1 | T93 / REQ-002,004 | ALL/normalized position assembly can return child data whose TTL expired during sibling/identity work | Fake monotonic delayed sibling; bounded refresh or 503, never stale success | CLOSED |
| AUD93-2 | T93 / REQ-004,005 | Normalized display executor admission leaves an unbounded job queue | Saturation returns bounded503 before submission; slots released in finally | CLOSED |
| AUD93-3 | T93 / REQ-002 | Fan-out collector converts child session401 to502 | Mid-flight revocation remains401, no aggregate data | CLOSED |
| AUD93-4 | T93 / REQ-003 | Identity upstream rate limit loses429/Retry-After | Fake identity429/50011/50040 retains sanitized429/header; cache invalidated | CLOSED |
| AUD94-1 | T94 / REQ-007 | Failed first quote batch can send another after disconnect; no request cancellation | >100 ids + delayed failure/disconnect produces no second batch | CLOSED |
| AUD94-2 | T94 / REQ-007 | Old live prices remain current while the next poll hangs | Independent 15-second source-timestamp expiry and invalid-ts rejection | CLOSED |
| AUD94-3 | T94 / REQ-006 | Raw Dio.fetch or later interceptor may redirect an otherwise allowed private request | Final send-boundary guard; no foreign-host request/bearer leakage | CLOSED |
| AUD93-5 | T93 / REQ-002,003 | Private observation TTL/fetchedAt starts after slow identity verification, hiding elapsed data age | Capture acquisition clocks before verification; fake slow postcheck cannot publish old data as freshly fetched | CLOSED |
| AUD93-6 | T93 / REQ-004 | Nested cache/aggregate/display freshness retries multiply child refresh attempts | No internal freshness retry or shared per-request budget; deterministic combined delays never exceed one refresh per child | CLOSED |

## Resume review evidence

The user resumed the saved checkpoint on 2026-10-07. Original explicitly bound writers continued. Backend native77-test run identified nine errors, all TemporaryDirectory cleanup WinError32 on operations.sqlite3, matching nine pre-existing direct SQLite fixture contexts without close. Executor is applying test-only closing plus transaction context; no action/store semantics change. The earlier3-second timeout did not recur in this run; final regression remains required.

Read-only backend review accepted the drafted AUD93-1..4 source corrections, but identified missing bounded-cache/inflight/network/admission/failure-waiter behavioral evidence. Coordinator requested deterministic fake coverage. A separate bounded freshness review identified AUD93-5; coordinator adopted acquisition-time TTL semantics and delegated correction.

Coordinator frontend inspection caught legitimate owner Bearer being rejected by the final guard and inadequate foreign-destination negative fixtures. Original executor corrected exact owner auth validation and added isolated destination/header/auth mutation, active-session raw fetch, and delayed-interceptor logout coverage. Reported ordered negative scenarios followed by privateBearer/ALL/public successes pass; focused suite/build and independent final source review remain pending.

Backend candidate completed86 focused tests and compileall exit0. Acquisition-time TTL and required bounds coverage are present. Coordinator final inspection identified nested freshness loops that can multiply refresh attempts (AUD93-6); original E2 executor receives bounded remediation. The candidate evidence is retained but affected final acceptance/build must be rerun.

## T93 final task audit — PASS

Coordinator inspected selected source/test diffs and new gateway/currency/pool/fake concurrency paths; read-only R2 reports were adopted and reconciled. Acquisition clocks precede identity verification; one acquisition per cache miss prevents multiplying freshness retries. Combined-delay regression bounds balance reads to2 and fails503 when the refreshed result expires. Cache256 eviction,32-flight admission,4 display reads, reserved action connection, failed waiter release and display admission reclamation are covered. No protected path changes or external configuration actions.

Final observed order after last executable edit:
1. RED negative: `& 'D:\CodexData\rtk\bin\rtk.exe' python3.12 -m unittest backend.tests.test_trade_api.TradeApiTests.test_red_expired_session_cannot_read_cached_private_gateway_data -q` — exit0,1 test.
2. GREEN intended success: `& 'D:\CodexData\rtk\bin\rtk.exe' python3.12 -m unittest backend.tests.test_data_gateway.DataGatewayTests.test_balance_keeps_all_currencies_cache_hits_and_returns_deep_copies -q` — exit0,1 test.
3. `python3.12 -m unittest backend.tests.test_data_gateway backend.tests.test_okx_pool backend.tests.test_trade_api -q` — exit0,87 tests in49.652s.
4. `python3.12 -m compileall -q backend` — exit0; backend task buildability PASS.

Earlier native9 cleanup errors were causally resolved by closing pre-existing test-only SQLite connections; subsequent77 and87 suites passed. No action/store changes were used to bypass failures. Task T93 PASS enables T96. Final whole-repository acceptance still requires remaining tasks and fresh final builds.

## T94 final task audit — PASS

Coordinator reviewed explicit changed source/test diffs and new transport/session/polling paths; R2 independent review was adopted. Final adapter uses immutable captured session for send, success and error fencing; exact owner Bearer is permitted while caller/substituted/duplicate auth and exchange headers are rejected. Raw-fetch destination test now uses the legacy allowlisted path with an active session. Ticker prices expire independently by upstream timestamp; subscription cancellation and batching are fenced. Financial and candle assertions remain.

Final observed formal sequence (all commands exit0):
1. `flutter test --no-pub --plain-name "a quote expires while the next backend poll remains pending" test/core/network/ticker_polling_service_test.dart`
2. `flutter test --no-pub --plain-name "raw Dio fetch with a valid session cannot use a foreign destination" test/core/network/backend_data_client_test.dart`
3. `flutter test --no-pub --plain-name "logout during a delayed later interceptor stops the final send" test/core/network/backend_data_client_test.dart`
4. `flutter test --no-pub --plain-name "clearing mutable request extras cannot bypass response session fencing" test/core/network/backend_data_client_test.dart`
5. `flutter test --no-pub --plain-name "logout during an in-flight success rejects the response" test/core/network/backend_data_client_test.dart`
6. `flutter test --no-pub --plain-name "a late 401 from an old generation cannot expire the new session" test/core/network/backend_data_client_test.dart`
7. GREEN `flutter test --no-pub --plain-name "private route uses only the shared backend bearer header" test/core/network/backend_data_client_test.dart`
8. GREEN `flutter test --no-pub --plain-name "loads ALL positions through one backend aggregate request" test/features/orders/order_repository_all_test.dart`
9. GREEN `flutter test --no-pub --plain-name "public reads need no login and preserve a backend base path" test/core/network/backend_data_client_test.dart`

Additional isolated destination/header/bearer mutation negatives also passed before GREEN. Final focused command: `flutter test --no-pub test/core/network/backend_data_client_test.dart test/core/network/backend_data_session_test.dart test/core/network/ticker_polling_service_test.dart test/features/orders/order_repository_all_test.dart test/features/strategy/strategy_market_repository_test.dart test/features/support_resistance/market_repository_test.dart test/features/settings/vnd_exchange_rate_provider_test.dart` — exit0,44 tests. Consumer run observed105 passes before a migrated Strategy fake compile failure; corrected strategy_screen_test.dart then passed25/25. Watchlist/SupportResistance screen targeted regression passed12 tests. Build after final edits: `flutter build web --no-pub` — exit0,109.3s; wasm compatibility dry-run and CupertinoIcons asset warnings, not warning-free. Task buildability PASS.

Separate final-integration issue AUD-INT-1: unchanged Settings navigation test intentionally keeps getOkxApiKey pending while calling pumpAndSettle after opening an access page with an ongoing progress animation. VND is overridden in this fixture. Isolated failure reproduced at test line127. No credential UI edits were made; required final full-suite acceptance must account for this fixture defect. T94 scope-related checks and build pass; T95 may proceed. External configuration/environment actions: none.

## T96 final task audit — PASS

Coordinator inspected backend/strategy.py diff and new list tests; R2 independent review accepted source. Existing cleanup/recovery/reconciliation order and active/corrupt sequential queue exception remain. Surviving selected records are reread after all refreshes, followed by fresh account, one uncached SWAP observation, account postcheck and scoped projection. Final surviving-ID filter handles concurrent deletion and replacement source removal. Basic result, deletion eligibility/execution, placement/lease guards and worker sources are untouched. Individual result remains fresh. No protected paths or external action.

Observed pre-edit baseline: three stable records produced4 account and3 SWAP reads; account changing after positions returned200 instead of409. Post-edit same stable scenario produces3 account reads and1 SWAP read. These are offline request-count measurements, not production latency timings.

Final ordered commands (all exit0):
1. RED negatives,5 cases: `python3.12 -m unittest backend.tests.test_strategy_list_reads.StrategyListReadTests.test_red_list_rejects_account_change_after_shared_position_observation backend.tests.test_strategy_list_reads.StrategyListReadTests.test_red_malformed_shared_positions_make_every_terminal_delete_hint_unavailable backend.tests.test_strategy_list_reads.StrategyListReadTests.test_red_stale_or_error_order_scan_blocks_shared_terminal_delete_hints backend.tests.test_strategy_list_reads.StrategyListReadTests.test_red_active_and_corrupt_sequential_queues_are_not_recovered_by_list backend.tests.test_strategy_list_reads.StrategyListReadTests.test_red_list_filters_a_record_deleted_during_shared_observation -q`
2. GREEN,4 cases: `python3.12 -m unittest backend.tests.test_strategy_list_reads.StrategyListReadTests.test_red_list_shares_one_terminal_position_observation_across_records backend.tests.test_strategy_list_reads.StrategyListReadTests.test_green_list_finishes_all_order_scans_before_shared_position_read backend.tests.test_strategy_list_reads.StrategyListReadTests.test_green_list_cleans_fully_accepted_replacement_source backend.tests.test_strategy_list_reads.StrategyListReadTests.test_green_empty_and_candidate_only_lists_do_not_read_positions -q`
3. `python3.12 -m unittest backend.tests.test_strategy_list_reads backend.tests.test_strategy_api backend.tests.test_strategy_queue backend.tests.test_strategy_retry backend.tests.test_strategy_automatic -q` —167 tests,46.599s.
4. `python3.12 -m compileall -q backend` — task buildability PASS, no later source/test edit.

Existing baseline failures and unaffected evidence remain recorded; fixes invalidate affected formal negative/success and build checks. Re-run affected explicit RED negative before GREEN success, focused regressions, and task build after last executable edit. Final integration will require fresh whole-app/backend builds after all remaining tasks.

External configuration/environment actions: none identified. Runtime route visibility: explicitly bound requests, effective routes unavailable/UNVERIFIABLE. No protected operational content was used as review evidence.

## Final backend discovery fixture remediation — pending

Native discovery ran329 tests in147.111s, exit1:17 SQLite TemporaryDirectory cleanup errors and1 diagnostics assertion failure. AUD-INT-2 identifies three unchanged direct SQLite fixture connections in test_order_cancellation.py and test_strategy_scope.py that do not close their handles on Windows. AUD-INT-3 identifies a fake HTTPResponse missing getheader, causing the503 category case to exercise generic AttributeError handling. T97 E0 owns only the four explicitly allowed test files, preserves transaction/category/cancellation assertions, and adds no production behavior. Full discovery must rerun after correction. AUD-INT-1 pending Settings navigation fixture remains part of T97. Risk baseline55 tests passed; T95 implementation continues.

T97 contract clarification from direct page-source evidence: editor fields cannot appear while credential reads are pending and default editor uses bundle mode. Separate pending-loading negative from successful-null fake-read GREEN navigation; select existing manual entry before preserving all original field assertions. No UI/runtime source changes. Three backend fixture modules now pass54 tests and compileall after corrections; exact formal report/final integration remain pending. Independent final backend R2 source integration accepted with no new findings; final runtime acceptance remains pending.

## Final backend verification — PASS

After T97 fixture corrections, final native `python3.12 -m unittest discover -s backend/tests -t . -q` exited0:329 tests in112.407s. Fresh `python3.12 -m compileall -q backend` exited0. No backend source/test edits afterward. Earlier17 cleanup errors and1 fake-transport assertion failure are resolved by fixture-only changes; no production cancellation/migration/assertion weakening.

T97 backend formal final order after edits: negative `python3.12 -m unittest backend.tests.test_order_cancellation.OrderCancellationTests.test_red_recovery_of_durable_attempt_started_is_read_only backend.tests.test_strategy_scope.StrategyReservationMigrationTests.test_failed_migration_rolls_back_legacy_table_and_rows -v` exit0,2; then GREEN `python3.12 -m unittest backend.tests.test_order_cancellation.OrderCancellationTests.test_green_confirmed_spot_cancel_uses_exact_body_and_is_idempotent backend.tests.test_strategy_diagnostics.StrategyDiagnosticsTests.test_green_okx_failure_categories_are_content_free_and_distinct -v` exit0,2. Related three-module suite exit0,54 tests in8.298s. Pre-edit same2negative tests exit1 with cleanup errors; source audit accepted exactclosing/transaction contexts and getheaderfake compatibility. AUD-INT-2/3 CLOSED; Settings portion T97 pending.

## T95 provisional session audit

AUD95-1 OPEN: service command admission validates session only when command arrives; a queued Start can execute after an immediate newer handoff fence before post-dispatch rejection. Require captured session context plus successfully acknowledged current authority immediately before owner.dispatch, retaining post-await fence. Regression blocks queue, admits Start under acknowledgedA, replaces/clears session while queued, then releases queue and proves no authorized owner dispatch/sample. Original E2 writer owns correction under REQ-008; no architecture/scope change.

AUD95-2 OPEN: provisional runtime draft extracts handshake session watermark in waitForHandshake using an undefined payload, instead of _onHandshake(payload). Move extraction to the handshake handler and prove a recreated proxy allocates above the surviving service watermark. Original E2 writer owns correction; source compile and behavioral regression are both required.

AUD95-3 OPEN: runtime service-owner UI state is not fenced synchronously on foreground session change; old private positions remain and queued service states can repopulate the UI before handoff acknowledgement. Publish existing typed sanitized stopped/unavailable state immediately, suppress service states until current session acknowledgement, and prove delayed-channel logout plus late-old-state rejection. Preserve financial monitor semantics and token-free state.

AUD95-4 OPEN: RiskMonitor owner state stream is asynchronous; an emitted old-state callback can execute after synchronous handoff and be stamped with the new service generation. Managed-session wire publication must serialize current owner.currentState or reject a noncurrent event value. Prove queued old owner event followed by synchronous handoff never publishes old private positions with the new generation. This is a publication fence, not financial logic change.

AUD95-1..4 source corrections were confirmed by final R2 inspection; runtime acceptance remains pending. First native Risk candidate run exit1 after38 passes: nullable owner callback compile failure and current-session401 diagnostic lost after synchronous cache-generation change. Original writer owns bounded fixes and reruns.

AUD95-5 OPEN: native expiry callback discards service generation and unconditionally expires foreground controller. During delayed ownership acquisition, foreground rotates before a new proxy generation is allocated; old service expiry can clear newer foreground session. Associate handoff generation with captured shared-session generation and TradeSession; require matches before foreground expiry. Regression rotates while acquisition awaits, delivers old expiry, and proves new session survives. Memory-only association and token-free outputs remain mandatory.

T95 independent source acceptance: AUD95-1..5 corrections confirmed by R2, including handoff foreground generation plus expected TradeSession before native expiry callback. StaleA expiry after foregroundB regression passes. Native full focused89 tests passed before an additional auth-gate widget fixture was added; final formal sequence/build remains required after that test edit. No further source finding; no financial engine or protected configuration change.

Additional auth-gate widget fixture resolved causally: assertions already completed, but disposing actors constructed in WidgetTester FakeAsync from runAsync stalled at monitor.dispose. Read-only R2 diagnosed unawaited owner attachment/work-tail continuations retaining fake zone. Actors now constructed in runAsync with real microtask before pumping; widget unmounted, actors disposed in runAsync. Isolated native auth-gate widget test exits0,1/1; temporary diagnostic prints removed. No production lifecycle semantics were changed to bypass fixture. Final formal sequence/focused90 suite/build follows last edits.

## T95 final task audit — PASS

Coordinator selected source/test inspection and independent R2 source acceptance reconciled AUD95-1..5, now CLOSED with regressions. Production Risk/native factories use shared backend transport and memory-only session handoff. Captured acknowledged authority gates queued dispatch and post-await publication. State envelopes carry non-secret generation; current owner snapshot prevents asynchronous old events being relabeled. Proxy and runtime reject old state before/after ack, clear UI immediately, and associate expiry with captured foreground identity. Cache entrypoints synchronously check expiry;401 stays typed invalid rather than empty. Stable provider ownership, Vietnamese visible disabled controls and original risk calculations/history remain. No shared T94 client/session or financial monitor engine changes.

Final observed native order after last diagnostic/fixture edit (all exit0):
1. `flutter test --no-pub --reporter expanded test/features/portfolio/risk/backend_session_handoff_test.dart --plain-name "cannot"` —3 tests.
2. Same path/flags `--plain-name "logout"` —3 tests.
3. `flutter test --no-pub --reporter expanded test/features/portfolio/risk/backend_session_handoff_test.dart test/features/portfolio/risk/risk_backend_session_repository_test.dart --plain-name "prior-generation"` —1 test.
4. `flutter test --no-pub --reporter expanded test/features/portfolio/risk/risk_backend_session_repository_test.dart --plain-name "expired session"` —1 test.
5. Same repository path/flags `--plain-name "private 401"` —1 test.
6. GREEN `flutter test --no-pub --reporter expanded test/features/portfolio/risk/backend_session_handoff_test.dart --plain-name "Start waits for an acknowledged active session handoff"` —1 test.
7. GREEN `flutter test --no-pub --reporter expanded test/features/portfolio/risk/risk_repository_test.dart test/features/portfolio/risk/risk_monitor_test.dart` —30 tests.
8. `flutter test --no-pub --reporter expanded test/features/portfolio/risk/backend_session_handoff_test.dart test/features/portfolio/risk/risk_backend_session_repository_test.dart test/features/portfolio/risk/risk_runtime_test.dart test/features/portfolio/risk/risk_repository_test.dart test/features/portfolio/risk/risk_market_repository_test.dart test/features/portfolio/risk/risk_monitor_test.dart test/features/portfolio/risk/risk_dashboard_test.dart` —90 tests.
9. `flutter build web --no-pub` —exit0,95.1s. Existing wasm dry-run secure-storage compatibility and CupertinoIcons font warnings; standard web build succeeded.

Optional `flutter build apk --debug --no-pub` exit1: no Android SDK installed. Android source/device execution is UNVERIFIED; no SDK/configuration installation or modification performed. Fake service lifecycle tests do not prove actual-device background behavior. User-owned external configuration actions: none for approved code/local web verification. No real exchange action or external request. T97 owns final fixture checks, followed by whole Flutter suite/fresh builds.

## T97 final task audit — PASS

Coordinator accepted exact four-file fixture diff; no product or configuration changes. All original content assertions remain in ready/manual-entry navigation. Pending-read negative independently checks navigation/loading without pretending credential read completed. SQLite connections close while transaction commit/rollback remains unchanged; minimal HTTPResponse fake getheader matches production interface. AUD-INT-1..3 CLOSED.

Final native Flutter order:
1. `flutter test --no-pub --plain-name "opens the API and trade access subpage from Settings" test/features/settings/settings_navigation_preferences_test.dart` —exit0,1 pending/loading negative.
2. `flutter test --no-pub --plain-name "opens the ready API and trade access subpage" test/features/settings/settings_navigation_preferences_test.dart` —exit0,1 ready/content GREEN.
3. `flutter test --no-pub test/features/settings/settings_navigation_preferences_test.dart` —exit0,12 tests.
4. `flutter build web --no-pub` —exit0,69.2s; wasm dry-run warnings, standard build succeeded. No edits afterward.

Final backend ordered2negative/2GREEN,54 module tests and compileall passed, followed by coordinator329 full discovery PASS recorded above. Task97PASS enables final aggregate Flutter verification and fresh final builds. Explicit E0gpt-6-luna/high request; effective route unavailable/UNVERIFIABLE. No external configuration action.

## Final Flutter aggregate fixture remediation — pending

`flutter test --no-pub --reporter expanded` native exited1 at01:24 with553 passes/3 failures. AUD-INT-4 navigation fixture fakes other data consumers but not Risk; opening Risk instantiates production backend transport without HTTPS configuration. Add explicit in-memory Risk navigation fixture preserving all navigation assertions; production transport/session/HTTPS guards stay unchanged. AUD-INT-5 two unchanged Strategy dialog fake subclasses use old Dio constructor at retryline645/wizardline1495; adapt fake constructors/imports to approved BackendDataClient interface without weakening action/financial assertions. Reopen T97 E0 bounded seven-test-file surface. Final runtime aggregate/build must rerun after fixture corrections; no protected configuration action or product redesign.

T97 final aggregate extension PASS: coordinator accepted exact three additional test-only diffs; production APIs/configuration unchanged and all assertions retained. AUD-INT-4/5 CLOSED. Native ordered negatives each1/1: `flutter test --no-pub --plain-name "filters hidden pages and maps visible slots in both modes" test/core/navigation/main_navigation_shell_test.dart`; `flutter test --no-pub --plain-name "T65 cancel during pending create cannot repeat or advance" test/features/strategy/strategy_retry_dialog_test.dart`; `flutter test --no-pub --plain-name "malformed recommendation clears both sides atomically" test/features/strategy/strategy_wizard_dialog_test.dart`. Then GREEN each1/1: same file commands with names `shows all primary destinations and switches selected content`; `T65 narrow dialog follows fixed preview, linked draft, prepare, one execute`; `wizard accepts saved IDs with valid custom thresholds` respectively. Entire three-file command `flutter test --no-pub test/core/navigation/main_navigation_shell_test.dart test/features/strategy/strategy_retry_dialog_test.dart test/features/strategy/strategy_wizard_dialog_test.dart` exited0,33 tests. `flutter build web --no-pub` exited0,61.2s; known wasm dry-run warnings. No later source/test edit. Final aggregate rerun follows; backend unchanged329PASS remains valid.

## Final integration verdict — PASS

All T93..T97 tasks are PASS. AUD93-1..6, AUD94-1..3, AUD95-1..5 and AUD-INT-1..5 are CLOSED. Coordinator reconciled explicit source/test diffs, independent R2 review and observed verification; no product/testing writer role bypass. Routes explicitly bound, effective routes unavailable/UNVERIFIABLE. No child close/release primitive exists; all terminal results collected without fabricated lifecycle operations.

Final commands and evidence:
- Native `python3.12 -m unittest discover -s backend/tests -t . -q` —exit0,329 tests in112.407s. Backend unchanged afterward; whole-run evidence retained.
- Native `flutter test --no-pub --reporter expanded` —exit0,582 tests at01:51 after all source/test remediation.
- Fresh `python3.12 -m compileall -q backend` after all final fixture edits —exit0.
- Fresh native `flutter build web --no-pub` after final full Flutter suite —exit0,74.2s, built build/web. Known secure-storage wasm dry-run warnings; standard web build succeeds.

Source checks found no direct OKX/CoinGecko destinations or OKX signing interceptor in migrated production consumers, and selected source/test whitespace check passes. Protected operational files do not appear in final name-only Git changes. Existing initial telemetry modifications and all task edits retained; no commit/push/deployment, live exchange action, production read or source transmission.

Latency evidence is bounded offline behavior: frontend ALL positions uses one backend request; three stable strategies share one fresh SWAP read rather than three. Cache reuse, connection exclusivity/reserve, shared polling, deadlines and session fences are behaviorally tested. No production millisecond claim. Realtime push remains deferred by user choice. Deploy backend first, then frontend using the existing HTTPS backend definition; deployment is not performed.

Android debug build remains UNVERIFIED because Android SDK is absent. Fake channel/lifecycle tests do not establish actual-device background behavior. These are verification limits, not hidden completed rollout actions. No protected configuration changes are required for the approved code/local web verification.
