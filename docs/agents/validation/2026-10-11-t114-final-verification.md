# T114 frozen verification evidence — 2026-10-11

Status: ACCEPTED — SOURCE_FIXTURE; final independent whole-unit and targeted R3 PASS collected. This records executor evidence; coordinator verdict is in the source audit. Source/fixture only under D-008; venue/device gates remain pending. No source/test edit after final web build. Effective child routes unavailable/UNVERIFIABLE; E2 gpt-6-luna/max explicitly bound, R3 gpt-6.1-sol/high explicitly bound.

## Ordered formal contract checks

Each selected command uses `/Users/locnguyen/.local/bin/rtk flutter test --no-pub --reporter expanded <file> --plain-name '<selector>'`. Each selected case below passed1/1 exit0. Unsafe-path assertions are the final RED contract checks, separate from observed failing missing-behavior baselines. All ten negatives preceded the nine positives; directly affected negatives were rerun after companion fixture additions. No unlisted global V4.

| Order | File | RED selector |
|---|---|---|
|1|test/multiuser/connections_page_authority_test.dart|pending step-up cannot submit after another owner replaces A|
|2|test/multiuser/private_data_contract_test.dart|delayed accepted receipt is discarded when another login replaces its owner|
|3|test/multiuser/private_data_contract_test.dart|UNKNOWN action lookup keeps one send attempt and records proof without resubmission|
|4|test/multiuser/private_data_contract_test.dart|pause cancels an in-flight private read and resume starts one fresh snapshot|
|5|test/multiuser/private_data_contract_test.dart|paused transient failure backoff sends no background retry and resumes once|
|6|test/multiuser/multi_user_api_client_test.dart|owned strategy list rejects stale, incomplete and expired snapshots|
|7|test/features/strategy/strategy_screen_test.dart|owned prepared strategy confirmation caps at 30 seconds and rejects changed authority before execute|
|8|test/multiuser/connections_page_authority_test.dart|standalone root step-up clears entered credentials and closes on owner replacement|
|9|test/multiuser/private_data_contract_test.dart|secondary account late 401 cannot clear replacement session or scope|
|10|test/multiuser/private_data_contract_test.dart|stale metadata blocks position preparation|

| Order | File | GREEN selector |
|---|---|---|
|1|test/multiuser/private_data_contract_test.dart|accepted delayed action survives route disposal and same-owner authority changes only on original scope|
|2|test/multiuser/multi_user_api_client_test.dart|owned strategy list accepts a fresh complete snapshot|
|3|test/features/strategy/strategy_screen_test.dart|owned StrategyScreen opens the root step-up dialog and clears credentials when it closes|
|4|test/multiuser/connections_page_authority_test.dart|saved connection step-up enables a supported action without creating a connection|
|5|test/multiuser/private_data_contract_test.dart|net short signed contracts allow close without optional posCcy|
|6|test/multiuser/private_data_contract_test.dart|initially paused portfolio starts no reads and resumes one coalesced snapshot|
|7|test/multiuser/private_data_contract_test.dart|isolated overview reader passes real v2 scope guards without selection mutation|
|8|test/features/strategy/strategy_screen_test.dart|GREEN-001 summary icon action preserves frozen confirmation|
|9|test/features/strategy/strategy_dashboard_controller_test.dart|stale list response keeps known rows and marks recovery state|

Later AUD037 boundary baseline: selected `raw Dio fetch with a valid session cannot use a foreign destination` failed exit1 before configured-origin/base-path repair (foreign fabricated adapter returned code0). After repair the following negatives passed1/1 each in order, before complete boundary suites15/15 and13/13:
1. test/core/network/backend_data_client_test.dart / raw Dio fetch with a valid session cannot use a foreign destination
2. same / a later interceptor cannot change the final backend destination
3. test/multiuser/backend_v2_client_test.dart / an earlier interceptor cannot redirect v2 to a foreign destination
4. same / a later interceptor cannot append an unregistered URI query

Preserved other missing-behavior baselines are documented in source audit/checkpoints. Intermediate fixture errors (missing fabricated OKX passphrase, invalid v2 query, fake-clock zero-delay deadlock intentionally terminated exit130) were corrected; they are not passing evidence. AUD036 actual double-pop baseline observed before single-shot route guard.

## Final affected regressions and freshness

All commands below start `/Users/locnguyen/.local/bin/rtk flutter test --no-pub --reporter expanded`.

| Scope argument | Result | Freshness |
|---|---|---|
|test/core|137/137 exit0|after boundary/navigation correction; affected backend test15/15 again after import cleanup|
|test/multiuser|71/71 exit0|after last relevant import/QA/boundary change|
|test/features/settings|43/43 exit0|after owned-page/no legacy reads assertion and import cleanup|
|test/features/market/market_screen_test.dart|5/5 exit0|no later relevant source/test change|
|test/features/orders/orders_screen_refresh_test.dart|8/8 exit0|no later relevant source/test change|
|test/features/strategy|169/169 exit0|unaffected UI evidence retained; boundary consumer subset refreshed below|
|test/features/strategy/strategy_api_client_test.dart|15/15 exit0|after shared boundary repair|
|test/core/network/backend_data_client_test.dart|15/15 exit0|after final redundant import cleanup|
|test/multiuser/backend_v2_client_test.dart|13/13 exit0|boundary ordered pair; included in final multiuser71|

No count is an additive total: subsets overlap. Android device and live exchange acceptance were not run.

## Backend paired compile/runtime

`PYTHONPYCACHEPREFIX=/private/tmp/t114-r01-pycache /Users/locnguyen/.local/bin/rtk python3 -m compileall -q backend/exchanges/contracts.py backend/exchanges/okx_adapter.py` — exit0.

`PYTHONPYCACHEPREFIX=/private/tmp/t114-r01-pycache /Users/locnguyen/.local/bin/rtk /Users/locnguyen/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 -m unittest -v backend.tests.test_exchange_contracts backend.tests.test_exchange_read_routes` — exit0,31/31, Python3.12.14. System Python3.9 cannot run dataclass slots; no installation, pytest absent, standard-library unittest used. No repository pycache.

## Analyzer, final canonical application build and diff

`/Users/locnguyen/.local/bin/rtk flutter analyze --no-pub` — exit1,125 diagnostics (31 warning/94 info), zero error severity. Full safe report `/private/tmp/t114-r01-analyze-final.txt`. Introduced redundant/unused imports removed and affected suites rerun; global cleanup not authorized. Remaining diagnostics include existing style/deprecation/non-null items and broader T114 source/test lint items; independent classification pending, do not claim clean analyzer.

`/Users/locnguyen/.local/bin/rtk flutter build web --no-pub` — exit0, Built build/web,24.4s. This is the canonical Flutter application, not harness-only evidence; no source/test changes after it. Dry-run WebAssembly notices involve flutter_secure_storage_web dart:html/js_util/js; CupertinoIcons font-not-found notice observed, but canonical web compilation succeeded. No installation/configuration change.

`/Users/locnguyen/.local/bin/rtk git diff --check -- lib test` — exit0. `/Users/locnguyen/.local/bin/rtk rg -n '[[:blank:]]+$' lib/core/session lib/features/connections test/multiuser` — no matches, expected rg exit1.

## Physical rendered review

Actual installed Flutter SDK Roboto and MaterialIcons font assets; no downloads. Directory `/private/tmp/t114-resume-qa`. Coordinator inspected the final corrected units/overview plus matrix/critical images; independent review pending. Initial overview Ahem glyph failure corrected and rerendered; no visual PASS from that failed image.

- portfolio-{360,768,1440}-{light,dark}-text-{1.0x,2.0x}.png (12)
- account-context-portfolio-360-light-text-2.0x.png; account-context-portfolio-1440-light-text-1.0x.png
- portfolio-360-light-text-2.0x-scrolled-balance.png
- action-confirmation-360.png; pending-target-proof-768-dark.png; stale-metadata-360-dark.png; binance-unavailable-360-dark.png
- auth-{login,enrollment,loading,error}-360-light-text-2.0x.png
- connection-{create-form,empty,loading,error}-360.png; connection-long-name-360-text-2.0x.png
- overview-mixed-partial-800-light.png

Confirmed readable native5contracts/filled2contracts, captured account/exchange/product/environment/region/consequence; UNKNOWN target proof without repeat write; persistent context and whole numeric rows at360/200%; connection empty/loading/error/manual masked entry; overview native USDT/BNB/missing SPOT/stale incomplete USD_M/first page, no invented conversion or zero. Long names and 48px/keyboard/focus/lazy500 evidence are also runtime test contracts, not screenshot-only assertions.

## Boundaries and remaining gates

Executor reports no protected-content reads/edits, Git mutation, installs, secret retrieval, live/external service calls or activation. SDK-cache focused escalations were approved. Preexisting T113/doc changes and telemetry2026-10-06 remain untouched. Scoped status uses names only for protected paths. Source/tests frozen. Final independent audit and coordinator reconciliation required before T114 checkpoint PASS. Real venue/demo, Android device and later T115/T116 integration/launch remain pending; Binance production writes stay locked.

## Post-independent-audit bounded correction — latest frozen evidence

The preceding frozen snapshot received REWORK for008/029/036/038; requested actual production-wrapper regression also exposed scoped provider AUD039. Same explicitly bound E2 corrected five defects, no feature expansion. Source/tests frozen after fresh final build; targeted same R3 recheck PENDING.

All following selected commands use the exact common prefix `/Users/locnguyen/.local/bin/rtk flutter test --no-pub --reporter expanded`, followed by file and `--plain-name '<selector>'`. Each passing final selector1/1 exit0; actual failing baselines separately observed before corresponding correction; unsafe-path guards preceded supported positive suite runs.

| File | Exact selector | Observed missing-behavior baseline | Final result |
|---|---|---|---|
|test/multiuser/public_panel_scope_test.dart|real MarketScreen key changes preserve root stores and next private read|root scope null after actual MarketScreen key disposal|1/1 exit0|
|test/multiuser/session_authority_test.dart|malformed nonempty TOTP focuses the proof field and sends no login|focus stays username for12x, login0|1/1 exit0|
|test/features/strategy/strategy_screen_test.dart|cancelled native confirmation ignores batched authority changes during reverse animation|precise observer records both dialog and underlying MaterialPageRoute popped; preliminary missing-button assertion superseded as ambiguous|1/1 exit0, only dialog pop/execute0|
|test/features/strategy/strategy_screen_test.dart|production strategy wrapper replacement fences retained root wizard callbacks|initial real wrapper Riverpod scoped-provider assertion(AUD039); with dependency fixed but mounted guard removed: StateError ref afterdispose(AUD038)|1/1 exit0,no exception/adapterwrite|

Latest affected full regressions: `rtk flutter test --no-pub --reporter expanded test/multiuser`73/73 exit0; `... test/features/strategy`171/171 exit0. Cross-area command `rtk flutter test --no-pub --reporter expanded test/core/widgets/app_startup_test.dart test/core/widgets/app_startup_preview_test.dart test/core/services/background_service_retirement_test.dart test/core/security/time_zone_storage_test.dart test/core/security/remembered_trade_password_test.dart test/features/settings test/core/navigation test/features/market`106/106 exit0. Counts overlap preceding suites, never add as unique total.

After final test-only unused-local/super-parameter cleanup, public_panel_scope_test.dart3/3 and production-wrapper replacement selector1/1 rerun exit0. Unchanged backendcompile/runtime31, unaffected core137 and orderrefresh8 retained. Initial post-fix multiuser72/73 failure was QA fixture-owned session timer left alive now parent ownership preserved; explicit fixture teardown corrected and73/73 rerun, no production ownership workaround.

Latest analyze `rtk flutter analyze --no-pub` exit1,125 diagnostics31warning94info0errors; `/private/tmp/t114-r01-analyze-final-r3.txt`. New two cleanup diagnostics removed; same advisory baseline relative prior audit, not all preexisting relative originalHEAD. Latest canonical `rtk flutter build web --no-pub` exit0 produced build/web after ALL edits; existing Wasm/optional Cupertino font notices persist. Latest `rtk git diff --check -- lib test`exit0. No source/test changes or active command after build.

Source fixes: parent ownership preserved by keyed public subtree; shared login validation/focus; native shared one-shot captured-route close across all exits; origin mounted guard before WidgetRef reads; owned dashboard declares scoped strategyApi dependency. No legacy family expansion. Affected actual runtime tests and source/caller recheck pending R3. Existing font-backed static images retained; coordinator and prior independent review physically inspected them. Device/real venue gates unchanged.

## Final evidence acceptance

Independent R3 compared latest analyzer reports normalized for line numbers: identical125 advisory diagnostics, no new relative prior review. Rechecked008/029/036/038/039 and direct affected callers/provider scope; no remaining concrete blocker. Physical static evidence from prior full review remains valid. Coordinator adopts SOURCE_FIXTURE PASS; authoritative complete finding closure/scope/build/frontend/gates report is2026-10-11-t114-source-audit.md. Historical pending statements above represent their original frozen snapshots and are superseded by this final acceptance. Source/tests unchanged after latest build.
