# Implementation Plan: Binance direct reads and combined views

Status: COMPLETE
Date: 2026-10-25
Revision: 2
Tier: L
Specification: `docs/agents/specs/2026-10-25-binance-direct-reads-design.md`
Decision Ledger: `docs/agents/decisions/2026-10-25-binance-direct-reads-decisions.md`

## 1. Objective / Preconditions
Implement active REQ/AC-001..005,007,008 under D-001..007. REQ-006/AC-006/P04/T119 are removed by D-007. User explicitly authorized execution of revision 2 with “thực hiện tasks” on 2026-10-25. No protected content required. Preserve unrelated initial `.wrangler/` and `wrangler.jsonc`.

## 2. Planning Workstreams and Route
| Workstream | Material / Independent | Explicit requested route | Logical run | Result |
|---|---|---|---|---|
| Combined frontend/source identity/settings | YES / YES | R2 gpt-6.1-sol medium | R2-BINANCE-UI-001 | COMPLETE / USED |
| Direct integration/units/scheduling/isolation | YES / YES | R2 gpt-6.1-sol medium | R2-BINANCE-INTEGRATION-001 | COMPLETE / USED |
| Backend implementation | NO / N/A | N/A | N/A | Excluded |

Fan-out Required: YES. Required/actual reasoning agents: 2/2. Compliance: PASS. Exact model and effort were submitted, inheritance forbidden; effective routes unavailable, UNVERIFIABLE. Terminal results collected; runtime offers no close/release primitive, so none is fabricated.

Coordinator workload: reasoning HARD, orchestration LOW; preferred C2 gpt-6.1-sol/high. Runtime does not expose changing the current main route; current coordinator retains ownership and does not claim an effective route. No extra main session is created.

Synthesis: source-aware records/units are mandatory before aggregation; shared bare-coin prices and lane-wide invalidation cannot represent Binance safely. Native display rows cannot authorize backend actions. D-007 keeps Market, Fractal, support/resistance, Strategy and watchlists entirely on existing OKX behavior. D-004 selects all-pair scans; D-005 selects partial results. Native coverage/retention limitations are disclosed, not hidden.

## 3. Frontend Gate
F1 for bounded platform icons, credential section, existing account cards and source/progress/error states. F0 for transport. Reuse AppPalette, existing typography, responsive forms, number/time formatting and card layouts. No design brief or React skills. Required final audit: pinned `third_party/vercel-labs/web-interface-guidelines/command.md`, applied to Flutter equivalents. Existing repository rules override upstream fetch/brand preferences. Review mobile/desktop and changed critical states with rendered evidence when available; widget semantics/overflow coverage is mandatory. Do not claim visual PASS without rendering. Material layout/navigation redesign returns to planning/F2.

## 4. Scope and External Actions
Exact active source/test write surfaces are in T116..T118; analytical/watchlist source changes are excluded; configuration/manifests/locks/generated native DTOs/backend sources/Strategy behavior are excluded. No external protected configuration action or new dependency planned. Binance keys are entered using application settings, not repository environment files or chat. API permission/real-network checks are user-device verification if credentials are unavailable to test locally; no live secrets are retrieved by agents.

## 5. DAG and Task Decomposition
`T116/P01 -> T117/P02 -> T118/P03 -> independent integration audit -> fresh final build`. T119/P04 is REMOVED and must not be dispatched.

Three serial writers: native transport security, stateful history/data adapters and account/action UI have distinct failure evidence. Separating the first two isolates request authorization from the scanner's state machine. Shared app build/cache state and predecessor interfaces require serialization. Every task is additive or compatibility-staged and must compile before PASS; no later task repairs an earlier broken build.

| Task | Objective | Requirements / AC | Route | Canonical build boundary |
|---|---|---|---|---|
| T116 | Independent Binance transport and native/web credential lifecycle | REQ-001 / AC-001 | E1 gpt-6-luna xhigh | Additive client; original app unchanged |
| T117 | Neutral adapters, source quotes, weight-aware resumable history | REQ-002,003,005 / AC-002,003,005 | E2 gpt-6-luna max | Additive readers; existing consumers retained |
| T118 | Combined portfolio/orders, credential UX and backend action guards | REQ-004,007,008 / AC-004,007,008 | E1 gpt-6-luna xhigh | Migrate all compile-coupled account consumers together |

T117 is E2 because token-budget scheduling, cancellation/generation fencing and resumable incremental scans interact; this is coding/state-machine entropy, not unresolved product design. All children require role implementation_executor and explicit model AND effort. Effective unavailable is recorded UNVERIFIABLE; mismatch stops mutations. Auditors use explicit R2 gpt-6.1-sol/medium and stay read-only.

## 6. Ordered Steps
### P01 / T116 — Transport and credential foundation
Add Binance HMAC signed read client, final-adapter origin/method/query guards, sanitized exceptions, server-clock offset, bounded timestamp recovery and host cooldown support. Add independent Binance storage keys/generation/rotation/disposal and web overrides without changing OKX keys. Reuse existing crypto/HTTP/storage dependencies opaquely. RED-116 denies hostile/missing/rotating requests and stale publication; GREEN-116 proves exact signed GET, public signed-out reads and independent credential save/clear. Existing OKX security regressions required.

Persist one strict Binance credential bundle, serialize mutations, and treat native exceptions/web false as unusable until recovery. T116 owns failed-save/reload tests; T118 only consumes the storage contract. The spec's exact endpoint/weight/query inventory is binding implementation input.

### P02 / T117 — Neutral readers, quotes and scan engine
Add neutral models/read interfaces and adapters retaining native OKX/backend DTOs. Implement native Binance balances/positions/ordinary and conditional orders, product metadata, typed optional monetary fields, source-specific batch quote polling for account valuation only. Preserve all-pair Spot universe beyond USDT and holdings. Expose snapshot denominator/progress/errors, one-in-flight scan, host weight/cooldown handling, interaction priority and generation-scoped resume; native recent first pages are explicitly limited to 500 per symbol and do not promise lifetime history. Futures readers obey documented endpoint scope/retention and conditional-order separation. RED-117 proves collision/units/budget/cancel/partial-scan boundaries; GREEN-117 proves deterministic complete synthetic scans and validated account data/quotes. Existing production consumers remain untouched/buildable.

### P03 / T118 — Account presentation and action boundary
Wire independent source results into portfolio/order providers/screens; partial sources do not fail all results. Combined headline/rows follow the 195-equity fixture. Render icon/source/wallet/coverage and scan progress/cancel/resume/refresh states. Add Binance credential form/bundle parser using existing settings UX. Require original OKX provenance at cancellation/action entry as well as UI. Keep backend account controls visibly separate; no Binance payload enters TradeApi/StrategyApi. RED-118 tests source failure, rotation, unknown valuation and Binance active-limit action attempt; GREEN-118 covers combined refresh, credentials/privacy/currency/timezone and unchanged OKX backend actions.

### P04 / T119 — REMOVED
D-007 removes Binance analytics and watchlist migration. Preserve existing OKX Market, Fractal, support/resistance, Strategy, public providers/quote facade and persistence. No corresponding implementation or new analytical tests are authorized.

## 7. Verification Budget and Buildability
Each task executes its independently derived formal RED scenario set before its primary GREEN set after narrow implementation diagnostics. Use synthetic credentials, clocks and HTTP adapters; no test invokes actual exchange writes. Later edits invalidate only affected scenarios; restart the pair when its shared basis changes.

| Gate | Exact command / method | Scope |
|---|---|---|
| T116 focused | `rtk flutter test --no-pub test/core/network/binance_data_client_test.dart test/core/security/binance_credential_generation_test.dart test/core/network/okx_data_client_test.dart test/core/security/okx_credential_generation_test.dart` | V2 |
| T117 focused | `rtk flutter test --no-pub test/core/exchange` | V2/V3; named RED/GREEN cases in task |
| T118 focused | `rtk flutter test --no-pub test/features/portfolio test/features/orders test/features/settings test/core/widgets/app_startup_test.dart` | V3 |
| Each code task + final | `rtk flutter build web --no-pub` | Full Flutter app; after final task-local executable change |
| Final regression | `rtk flutter test --no-pub` | V4 once, justified by shared storage/providers/quote contracts across app |
| Final scope | Name-only Git status; content diffs only explicitly allowed source/test/doc files; `git diff --check -- <explicit allowed files>` | Never inspect protected diffs |

Focused RED/GREEN runs use `--plain-name` selecting RED-NNN / GREEN-NNN named tests in the respective task test files. Test filenames and exact commands are finalized below in task contracts. If RTK obscures evidence, rerun the narrow failing command through raw/proxy. No per-task V4. Escalate only for unexpected shared-provider/consumer regressions outside V3 or concrete missing evidence. Analyzer checks, if needed, target changed Dart sources only; no repository-wide cleanup.

Affected canonical build unit is the Flutter application for every task. Record exact build command, target, final-change ordering and exit/status; test compilation alone cannot pass buildability. Existing config is opaque build input. No dependency install/config remediation is authorized. Build errors caused by changes are REWORK; genuine pre-build toolchain failure is BLOCKED_ENVIRONMENT.

## 8. Migration, Performance and Risks
Migration: none. Watchlist schema/storage and all analytical selections remain unchanged. No history cache migration. No secrets/history persisted to telemetry.

Performance evidence is synthetic: one history request in flight, >=250ms spacing plus actual weight budget, no repeated full scan on rebuild, lazy history rendering, shared batch quotes and prompt interactive reads. Do not state a fixed live scan duration.

| Risk | Mitigation / detection |
|---|---|
| Browser CORS/region/IP denial | Surface source state; no implicit proxy; live device verification reported separately |
| All-pair scan duration / IP limits | Progress, stop/resume, serial steps, host-wide weight budgets and 429/418 cooldown |
| Delisted/unavailable historic symbols | Display captured-universe/first-page/native-retention coverage, never promise lifetime completeness |
| Double equity/PnL conversion | Exact currency-bearing model and independent 195 fixture |
| Binance row invokes backend | Dual entry/UI source guard plus collision/action tests |
| Quote or credential cross-contamination | Source/product/generation keys and independently injected clocks/adapters |

## 9. Rollout / Rollback
All three active tasks and independent audit must PASS before release consideration. Run final V4 once and fresh web build after final executable changes. No branch creation/commit/push/deploy is implied. Release and Git rollback need explicit authorization. If rollback is later authorized, recover prior code; no application-data migration or watchlist recovery is required by this change.

## 10. Completion Checklist
- [x] D-001..007 resolved and official API references checked
- [x] Separate planning workstreams collected/reconciled, fan-out PASS
- [x] Spec, canonical plan and three active bounded task checklists revised; T119 marked removed
- [x] Explicit post-presentation execution approval (2026-10-25)
- [x] T116 PASS: transport/credential RED -> GREEN + build
- [x] T117 PASS: adapters/scan RED -> GREEN + build
- [x] T118 PASS: account/action UI RED -> GREEN + build
- [x] Independent read-only integration/action/units audit PASS
- [x] Pinned interface audit and available mobile/desktop visual evidence
- [x] Final regression, fresh build, explained final scope/status
- [x] Report real-key/browser/device limitations and user-owned configuration actions (currently none)
- [x] Confirm no protected-content access, unapproved Git mutation or external code transmission

## 11. Independent Planning Validation (Revision 1)
R2-BINANCE-VALIDATION-001 (explicit gpt-6.1-sol/medium, read-only) requested two corrections: assign partial/failed credential persistence to T116, and fix exact endpoint/auth/parameter-dependent weights before dispatch. Coordinator completed both in spec section 6, REQ-001 and T116/T117. R2-BINANCE-VALIDATION-002 confirmed both resolved, with no further blocker in the bounded recheck. Effective route was unavailable; no product/test mutation or live API verification occurred. This is readiness evidence, not execution approval or implementation PASS.

## 12. Revision 2 — Account views only
User decision D-007 removes P04/T119 and Binance analytical parity. Three active tasks remain. T117 no longer implements candle readers, merged Market rankings or analytical quote consumers. REQ-005/AC-005 cover account valuation quotes only; REQ-006/AC-006 are reserved as removed IDs. Existing Market/Fractal/support-resistance/Strategy/watchlist sources remain outside all write surfaces. The revision-1 validation above remains relevant to unchanged credential safety, native request weights, scan mechanics and backend action isolation; analytical/migration validation is obsolete. Coordinator scope/references/endpoint review applies to this revision. Execution of revision2 was explicitly approved and completed on 2026-10-25.

## 13. Final Outcome
T116/T117/T118 PASS; T119 remains REMOVED. Independent read-only audits and coordinator source/caller/test reconciliation complete. Final full regression664passed and fresh Flutter web build exit0. No code/test changes after final verification. See docs/agents/audits/2026-10-25-binance-direct-reads-integration.md for evidence and limitations. No commit/push/deployment performed.
