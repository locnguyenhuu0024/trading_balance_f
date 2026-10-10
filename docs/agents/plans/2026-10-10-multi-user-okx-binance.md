# Implementation plan: Multi-user OKX and Binance

Status: READY_FOR_APPROVAL — planning complete; execution NOT AUTHORIZED
Date: 2026-10-10
Revision: 1
Tier: L
Specification: `docs/agents/specs/2026-10-10-multi-user-okx-binance-design.md`
Decision Ledger: `docs/agents/decisions/2026-10-10-multi-user-okx-binance-decisions.md`
Frontend Brief: `docs/agents/specs/2026-10-10-multi-user-okx-binance-frontend-brief.md`
Branch: `codex/multi-user-okx-binance-plan`
Base: local `main` at `a31553ca82e0d4a3648df8197173c66e955c9266` (merge-base/log verified; no remote refresh)

## 1. Recommendation and alternatives

Retain Flutter and the Python backend; evolve them into a modular application with explicit user/connection scopes, PostgreSQL, a vetted credential vault, bounded gateway resources and durable execution claims. Start Binance read-only, then enable a deliberately limited USD-M trading capability after demo verification. This gives the current personal workflows a safe growth path without a rewrite.

| Option | Benefit | Cost / risk | Decision |
|---|---|---|---|
| One personal backend per user | Small initial code delta | Repeated resources/deployment, weak unified UX, singleton operations and no scalable ownership model | Reject as product architecture; isolated local legacy mode only |
| Modular backend + exchange adapters + PostgreSQL | Reuses transport/cache/UI, explicit isolation, affordable staged rollout | Requires auth/store/ledger migration and disciplined budgets | Choose |
| Immediate microservices/Redis/Kafka/full realtime | More scaling knobs | Distributed failures and operating cost before measured demand | Defer; justify individual components from measurements |
| Keep exchange secrets/trades on client | Avoid backend vault | Breaks server worker/cross-device use; browser secret and inconsistent lifecycle risks | Reject |
| Force OKX feature parity on Binance | Uniform labels | Wrong sizing/mode/algo assumptions and unsafe trades | Reject; capability-driven rollout |

Estimated effort: 30–50 engineering days for this staged beta, roughly 6–10 weeks for one dedicated engineer with review/operator support. This is a planning estimate, not observed duration or a delivery commitment. Missing infrastructure, exchange contract surprises and device verification can extend it. Real-money activation is a separate launch decision.

## 2. Preconditions and scope

Implements REQ-001–007 / AC-001–007 under D-001–003 and A-001–010. All tasks remain PENDING. Before starting a task: approval of this revision and brief, predecessor PASS, exact protected setup required by that task provisioned by the operator, explicit executor role/model/effort binding and independent audit owner.

Before runtime tasks, verify the chosen PostgreSQL/cryptography package versions and Python compatibility without reading dependency manifests. Have the operator pin/install compatible releases and supply an isolated test DB/vault keys. No production configuration discovery is needed for source-only development; actual setup and launch remain gated.

The roadmap is fully planned but intentionally staged. Beta does not promise Binance Hedge, TP/SL/algo, Spot writes, or strategy parity. These require separate endpoint-specific execution plans once the first beta is measured. The gateway remains the sole Flutter exchange-data boundary.

## 3. Planning workstream decomposition and synthesis

| Workstream | Material / independent | Requested reasoning route | Logical run | Result/adoption |
|---|---|---|---|---|
| Backend/auth/data/security/migration/concurrency (one tightly connected backend contract) | YES / YES relative to UI and official integration research | R3 / gpt-6.1-sol / high | backend-plan-01 | COMPLETE / USED |
| Flutter/UI/session/state/performance | YES / YES | R2 / gpt-6.1-sol / medium | frontend-plan-01 | COMPLETE / USED |
| External exchange contracts/capability research | YES / YES | R2 / gpt-6.1-sol / medium | exchange-plan-01 | COMPLETE / USED |

Fan-out Required: YES. Required Reasoning Agents: 3. Actual Reasoning Agents: 3. Fan-out Compliance: PASS. Skip Reason: N/A. All requests explicitly supplied model and effort; generic child roles were read-only reasoning, parent inheritance forbidden. Runtime did not expose effective routes: UNVERIFIABLE, not inferred.

Coordinator routing preference: C2, gpt-6.1-sol/high for difficult architecture with a small advisory wave; main runtime route is fixed/not independently verified. Coordinator owns decisions and canonical artifacts. Child-close/release primitive is not exposed in this runtime; terminal results were collected, with no additional agent dispatch planned.

Reconciled findings: existing account fingerprint is not a tenant ID; session signing-key rotation must not change ownership. The worker performs exchange writes and needs durable fencing. Frontend generation protection extends to user/connection/product/permission generation. Public cache sharing must distinguish exchange/product; private sharing is prohibited. Binance conditional/algo lifecycle is deferred instead of being coerced into ordinary position-close code. Combined overview remains read-only; selected account is authoritative for actions.

Frontend gate: F2, brief READY_FOR_APPROVAL; pinned Anthropic frontend-design and local Vercel interface guidance loaded, React-specific guidance N/A. Rendered mobile/desktop review and native device checks required after implementation. Visual PASS NOT_RUN. No UI implementation or screenshot claim this turn.

## 4. Repository impact and setup ownership

| Area | Existing source to adapt | Proposed additions |
|---|---|---|
| Identity/storage | `backend/security.py`, `store.py`, `service.py`, `app.py` | `backend/auth.py`, `principal.py`, `store_contract.py`, `postgres_store.py`, `schema_multiuser.py` |
| Connections/vault | service/gateway account construction | `backend/connections.py`, `credential_vault.py`, `account_context.py` |
| Durable commands | `service.py`, `strategy.py`, `strategy_queue.py`, `strategy_scope.py`, `strategy_worker.py` | `backend/command_ledger.py`, `worker_scheduler.py` |
| Exchange abstraction | `backend/okx.py`, `data_gateway.py`, strategy/read consumers | `backend/exchanges/contracts.py`, `okx_adapter.py`, `binance_transport.py`, `binance_spot.py`, `binance_usdm.py` |
| Client contracts/UI | existing data/session clients, affected market/order/portfolio/strategy repositories/providers, settings flow, navigation shell | `lib/core/session/user_session.dart`, `connection_scope.dart`; `lib/features/connections/domain/`, `data/`, `presentation/` Dart sources |
| Migration/benchmark | existing affected test fixtures | `backend/migrate_multiuser.py`, `backend/benchmarks/multiuser_load.py`, focused new Python/Dart tests and deployment documentation |

Exact task-owned source/test surfaces are in T110–T116. Framework docs/telemetry are coordinator-owned. Protected runtime/build/dependency/deployment files, unrelated features, generated artifacts and existing completed task files are outside writer scope. New manifests/config files are user-owned actions described in spec §12. Agents do not read, create or modify them. Existing manifests may be consumed opaquely by canonical tools.

New setup proposals: operator-owned `backend/.env.multiuser`, `backend/.env.multiuser.test`, `backend/requirements-multiuser.txt`; exact variable semantics/placeholders and required validation are in spec §12. Dependency version pinning is an execution preflight gate. Deployment host/origin/TLS/egress facts and exact protected paths must be supplied for a separate launch runbook before deployment; no path/value inferred from current settings.

## 5. Dependency DAG and execution waves

```text
T110 (identity + production storage contract)
  -> T111 (owned OKX contexts + vault + safe command ledger)
     -> T112 (normalized OKX/Binance read adapters)
        -> T113 (gated USD-M One-way writes)
        -> T114 (new client/UI flow)
     -> T115 (fair workers + bounded runtime)
T113 + T114 + T115 -> T116 (migration, load, recovery and launch evidence)
```

Run T110 → T111 → T112 serially for contract stability. After T112, T113 and T114 may run together only if backend/Flutter/test-support surfaces and runtime ports are disjoint; T114 uses the fixed mocked DTO contract while T113 changes only server execution capabilities. T115 touches shared backend lifecycle files, so run it after T113 and without another backend writer. T116 follows all predecessors. Independent advisory audit can run read-only; mutable build/shared DB fixtures are serialized. Never spawn multiple writers against the same store/worker/test support file.

Seven tasks exceed the L handoff target of five because identity/storage, safe command integration, exchange reads, exchange writes, UI, worker scheduling and offline recovery/load have materially different failure or verification paths. Splitting by individual file is avoided. Interfaces are introduced additively with compatibility adapters so every intermediate task builds; no task relies on its successor to repair imports/schema references.

## 6. Ordered implementation steps

### P01 / T110 — User identity and production storage foundation (4–7 days)

Create scoped storage/principal/auth contracts; implement PostgreSQL user/session/MFA/invite schema and SQLite compatibility for existing isolated tests. Reuse scrypt/TOTP, add atomic replay/recovery consumption and independent auth admission. Recovery requires username+password+code and grants only MFA reenrollment until fresh ordinary login. Introduce v2 identity routes without changing legacy exchange commands yet. Retain existing password minimum. Add authenticated owner predicates and composite key constraints to the new schema from the start. Provisioning of packages/DB/keys is user-owned.

REQ/AC: 001, foundations for 002/007. RED/GREEN-001. Focused auth/storage tests, PostgreSQL races; V3 ceiling. Build backend after final changes. Stop if infrastructure is missing, an identity decision changes or schema contract cannot maintain staged compatibility.

### P02 / T111 — Owned connections, vault and durable OKX commands (6–9 days)

Replace global-current-account assumptions with immutable scoped AccountContext; create/verify/rotate/revoke connections; stable remote identity dedup independent of session keys. Preserve canonical connection identity through revocation/relink, inherit UNKNOWN barriers and reject owner transfer; digest-key rotation cannot bypass uniqueness. Apply owner-first queries to every private action/result/strategy/preference/reservation/conflict path. Persist command CAS claims/fences/leases and attempt markers before sending, reuse strategy safeguards, protect result polling during active execution. Never retry an unresolved send solely because its lease expired. Add v2 OKX paths, leaving old code only in isolated legacy mode.

REQ/AC: 002/004; INV-001–006. RED/GREEN-002 and 004 against OKX mocks/multiprocess DB races. V3. Include connection revocation, same-symbol distinct-account conflicts, vault tamper, CSRF/native bearer and owner scoping. Build backend; no real exchange writes. Logout revokes UI authority but does not silently cancel previously accepted confirmed worker jobs; disable/revoke is the explicit stop mechanism.

### P03 / T112 — Neutral exchange data and Binance read-only (4–6 days)

Define typed decimal/native-unit DTOs and capability contract; wrap existing OKX client without changing its native semantics. Add Binance signers/transports for supported Spot and standard USD-M read endpoints. Correct product-aware market keys and gateway allowlist; resource sharing distinguishes public vs private scope. Replace synchronous strategy-list reconciliation with persisted paginated reads and explicit bounded refresh queue hooks. Add fixture parity and identity metadata verification; no fallback identity from key/balance.

REQ/AC: 003 and read side of 006. RED/GREEN-003; unsupported capability, quantity step/contract conversion and same coin/exchange/product fixture. V3. Demo reads are operator-authorized separate checks; initial synthetic fixtures are sufficient for source checkpoint but not venue integration PASS. Build backend.

### P04 / T113 — Binance USD-M One-way regular-order actions (4–6 days)

Support mode-aware standard USD-M position close/reduce and regular-order cancel using the durable ledger. Fresh metadata/position/mode/permission preflight; no automatic position-mode/leverage changes during close. One-way only initially. Hedge/algo/Portfolio Margin/strategy/Spot writes return capability unsupported. Map -1007/503 variants and native IDs to reconciliation, preserve partial-fill/cancel races. Close-all enumerates supported targets and individually proves outcomes.

REQ/AC: 003/004. RED/GREEN-003/004 with Binance fixture + demo evidence, not live trades. V3. Demo activation requires explicit operator-provisioned test credentials/endpoint approval. Build backend. No real-money enablement before task audit and launch gate.

### P05 / T114 — Multi-user connection UX and client contracts (5–8 days)

Implement approved F2 brief with existing Flutter/Material/Riverpod tokens. Replace singleton credential setup with server connection manager, username/MFA onboarding, context strip and capability states. Scope providers/caches/pending operations by user/connection/exchange/product/generation; private rows clear before switch and late responses are ignored. Migrate exchange-shaped clients behind normalized v2 without introducing direct Binance calls. Provide read-only combined overview with completeness/valuation semantics from spec. Explicit user action re-enters legacy keys and clears local saved keys only after successful connection verification and user consent; never silently uploads existing credentials.

REQ/AC: 005 and client 001–004. RED/GREEN-005, typed DTO widget/provider tests, 360/768/1440px rendered states, 200% text, dark/light, keyboard/semantics and secret-paste checks. V3. Build Flutter web; Android build/device acceptance is a launch gate if local tooling unavailable. Keep generated model files untouched by using hand-written DTOs unless separately planned.

### P06 / T115 — Fair workers, global budgets and responsiveness (4–7 days)

Replace singleton monitor lease with per-connection/job claims, database time and monotonic fences. Account-fair due scheduling, finite queues, dead-letter/manual reconciliation state and budget reservation for safety work. Shared bounded executors/context LRU; no pool per linked account. DB-coordinated account/IP rate budgets across processes; observed upstream feedback; safe read retry/backoff only. Public cache-miss coalescing uses deployment-owned DB lease/latest snapshot; private single-flight is one per process with a declared four-process maximum amplification. Enforce active-account admission and existing strategy order density limits; disconnect UI polling from background strategy execution.

REQ/AC: 004/006. RED/GREEN-004/006, lost-fence/crash/noisy-neighbor/full-queue tests, 15-minute soak and process count scaling. V3. Build backend. Start with polling; realtime remains phase-next. Stops if throughput budget cannot satisfy declared freshness without overload; reduce admission or revise accepted capacity, never bypass venue limits.

### P07 / T116 — Offline migration, recovery, benchmark and release evidence (3–7 days)

Add explicit ownership-mapping importer with dry-run first, quarantine output and no exchange mutation capability. Preserve legacy order IDs/statuses/intents; revoke sessions/confirmations; reconcile uncertain rows before execution resumes. Compare SQL counts/decimal values/status histograms and restore/decryption readiness. Run baseline/new load profile from spec §11; report actual p50/p95/p99, fairness, cache coalescing, upstream weight, threads/sockets/RSS/queue bounds and UI frame results. Produce operator launch runbook only from supplied safe runtime facts. Independent final integration/a11y/security/trade-safety review.

REQ/AC: 006/007, integration 001–005. RED/GREEN-007 then 006 integration. Task V3; one final V4 backend+Flutter regression justified by auth/storage/DTO/global runtime changes. Build backend + Flutter at final executable state. Synthetic/demo evidence cannot claim live performance or profitability. This task writes code/docs and verifies local fixtures; production migration/deploy/trade activation still need separate authorization.

## 7. Verification and buildability

Planned proposed new suites (not created or run): `test_multiuser_auth`, `test_multiuser_ownership`, `test_credential_vault`, `test_command_claims`, `test_exchange_contracts`, `test_binance_reads`, `test_binance_commands`, `test_worker_scheduler`, `test_multiuser_migration`; frontend `test/multiuser/`. Existing trade/gateway/strategy queue/worker and frontend session/filter/refresh tests remain relevant regressions.

| Tasks | Formal RED → GREEN | Relevant regression / build |
|---|---|---|
| T110 | per-user MFA/recovery/session races → successful independent sessions | auth/storage suites; `python3.12 -m compileall -q backend` |
| T111 | IDOR/vault tamper/duplicate execute → owned secure OKX flow | trade_api/strategy_scope/strategy_queue/data_gateway and PostgreSQL process races; backend compileall |
| T112 | unit/mode/capability/key collision → normalized OKX/Binance reads | exchange/gateway/read-pressure fixtures; backend compileall |
| T113 | unknown timeout/hedge denial/cancel-fill → One-way proven result | command fixtures + operator-authorized demo smoke; backend compileall |
| T114 | delayed response/401/scope switch → accessible correct-account UI | `flutter test test/multiuser`; `flutter analyze`; `flutter build web --no-pub` |
| T115 | noisy neighbor/fence loss/full queue → fair bounded workers | scheduler/strategy_worker/strategy_queue races; backend compileall |
| T116 | ambiguous import/unsafe resume → validated mapped migration | migration/load/recovery suites; backend compileall + Flutter web build |

Focused unit commands use `python3.12 -m unittest <approved relevant modules> -q`. PostgreSQL integration tests must explicitly use the isolated `MULTIUSER_TEST_DATABASE_URL`; absence is BLOCKED, never a silent SQLite substitute. Canonical backend build unit is the backend Python package; compileall plus actual import/runtime test coverage validates it. A fake transport fixture is not DB multiprocess evidence. Flutter build consumes manifests opaquely.

Inner loop: narrow diagnostics only. Formal checkpoint: independently defined RED observed before GREEN; baseline-failing new test when applicable; then task build after last source/test edit. Later changes invalidate only affected evidence. V1→V2→V3; broader tests only for shared-surface uncertainty or failures. V4 once at integration: `python3.12 -m unittest discover -s backend/tests -q`, `flutter test`; required because auth/store/DTO/runtime cut across existing paths. Prefer RTK first for eligible output; exact failures/raw native Flutter named-test commands when quoting/evidence requires it.

Independent coordinator audit returns PASS/REWORK/BLOCKED for each task; each product writer is an explicitly bound executor, not a planning agent. Focus audit on ownership, attempt markers/fences, unknown lifecycle, decimals, current OKX behavior, resource bounds and native UX. No implementation check has run in this planning turn.

## 8. Migration, sizing and launch gates

Migration/rollback procedure is canonical in spec §10. Neither user count nor registered accounts directly determines exchange traffic. At 200 accounts refreshed every 5s, there are 40 account refresh cycles/s before endpoint fan-out; 20 strategy accounts ×20 order queries every 5s adds 80 queries/s. These are sizing arithmetic, not approved venue capacity. Limit active strategy density initially to existing safe bounds; measure weighted budgets and reduce active admission/frequency where required. Do not advertise 200-account freshness if measured venue budget cannot sustain it.

Launch requires: mapped owner migration; external config applied and readiness proven; read-only and write kill switches; secure sessions/vault restore; source isolation audit; multiprocess no-duplicate proof; demo adapter proof; SLOs/bounded degradation; rendered/mobile device review; no unexplained diff; operator-reviewed release runbook. Geography/account eligibility and API permissions must be validated per connection; broker/OAuth/partner programs are not assumed authorized.

Roll out owner-only OKX → invited read-only users → gated USD-M One-way → measured beta. Separate authorization required for live SQL/migration, deployment and real-money capabilities; commit and push are also separate. Avoid rolling back to a pre-write ledger after new exchange writes.

## 9. Risks and response

| Risk | Detection | Mitigation |
|---|---|---|
| Missing ownership path/IDOR | foreign-ID/cursor/replacement/action tests and query audit | Mandatory principal/scope, composite constraints, uniform 404 |
| Race/lease expiry causes duplicate write | multiprocess/crash/send-marker tests | CAS ledger, no new writer while unresolved intent exists |
| Vault or browser secret exposure | redaction/AAD/migration/restore tests | Vetted encryption, isolated keys, user-triggered local removal |
| Product metadata/mode mismatch | endpoint fixtures + demo reads/writes | Decimal/native units, explicit capability gates, no forced parity |
| Shared Binance egress saturates | response budget + synthetic weight model + live-read canary | deployment-wide limiter, public reuse, fair admission, phase-next WS |
| In-flight revoke makes order proof unavailable | revoke-after-send exercise | Preserve UNKNOWN, stop tail, manual exchange recovery route |
| Migration drops command history | restore/count/unknown-state dry run | Offline freeze, quarantine, no dual writers, forward-fix after new trades |
| UI compactness hides account/actions | render/context-switch/semantics checks | Context strip, repeated confirmation scope, 48px targets |
| New package/runtime unavailable | explicit preflight | Operator-owned pinned setup; BLOCKED runtime check, no fallback production claim |

## 10. Task contracts and completion

| Task artifact | Steps / AC | Predecessor | Executor binding |
|---|---|---|---|
| `tasks/task_110_multiuser_identity_store.md` | P01 / AC-001 | — | E2 / gpt-6-luna / max |
| `tasks/task_111_owned_connections_ledger.md` | P02 / AC-002/004 | T110 | E2 / gpt-6-luna / max |
| `tasks/task_112_exchange_read_contracts.md` | P03 / AC-003 | T111 | E1 / gpt-6-luna / xhigh |
| `tasks/task_113_binance_usdm_commands.md` | P04 / AC-003/004 | T112 | E2 / gpt-6-luna / max |
| `tasks/task_114_multiuser_connection_ui.md` | P05 / AC-005 | T112 | E1 / gpt-6-luna / xhigh |
| `tasks/task_115_account_worker_budgets.md` | P06 / AC-004/006 | T113 | E2 / gpt-6-luna / max |
| `tasks/task_116_multiuser_migration_release.md` | P07 / AC-006/007 | T113/T114/T115 | E2 / gpt-6-luna / max |

E2 is used for transaction/lease/state-machine/migration complexity, not task size or importance. The adapter-read and approved UI contracts are bounded E1. Every dispatch requires `agent_role=implementation_executor`, explicit model+effort and no parent inheritance; effective route unavailable is recorded, a mismatch stops work. No executor has been dispatched.

- [x] Material advisory workstreams collected and reconciled.
- [x] Canonical spec/decision/brief/plan and seven pending tasks created.
- [x] Protected files excluded; no product behavior changed.
- [ ] User approves revision 1 and authorizes execution.
- [ ] Operator provisions required task-specific setup.
- [ ] T110–T116 each has formal RED/GREEN, build and independent PASS.
- [ ] Final regression, isolation, demo, performance, recovery and visual evidence pass.
- [ ] Separate launch/migration/deployment authorization and runbook are present.

Approval gate source: repository baseline §6 requires explicit execution authorization after presenting the current plan. This turn stops at the user's requested planning scope; no immediate approval response is required.

## 11. Subsequent expansion milestones

These are planned gates beyond the seven-task beta, not currently dispatch-ready implementation tasks. Each milestone needs its own endpoint-specific contract, bounded tasks and explicit execution approval. The adapter/ownership foundation should allow them without changing the tenant model.

| Milestone | Entry gate | Concrete work and UX | Required evidence | Planning estimate |
|---|---|---|---|---|
| Binance strategy support | Beta ledger/metadata/worker PASS; per-strategy capability review | Map only strategies whose sizing, fees, leverage/tier/risk and execution rules are proven; show unsupported reasons in wizard; preserve FIFO/reservations/UNKNOWN behavior | Known independent sizing/risk fixtures, demo queue/timeout/replacement tests, no accidental Spot use of SWAP formula | 5–10 engineering days depending on strategy coverage |
| Binance Hedge and conditional orders | One-way canary proven; separate algo/native IDs/state contract approved | Correct LONG/SHORT ownership; explicit conditional TP/SL/trailing controls; regular/algo lists and lifecycle distinct; no automatic mode change with open positions/orders | Both-leg reduce/close, conditional trigger, partial fill, cancel race, restart and reconciliation demos | 4–8 days |
| Binance Spot trading | Spot read filters/permissions proven; explicit trade UX approved | Buy/sell and cancel with available/locked balance, fee asset, market/limit/notional filters; no leverage/position-close labels; separate strategy semantics | Insufficient funds, lot/notional, fee asset, partial fill and unknown submit demos | 3–6 days |
| Server market/private streams and client push | Polling budget/latency measurements show benefit; operator confirms approved stream-capable runtime | Shared public WS; product-specific private subscriptions/renewal; snapshot/replay/gap reconciliation; user-scoped SSE/WS push and reconnect/offline status | Sequence gaps, 24h reconnect/renewal where applicable, dropped packets, finite buffers, no cross-user delivery, before/after budgets/latency | 4–8 days |
| Broader public access | Beta isolation/security/load/recovery and operating runbooks proven | Revisit public enrollment, account recovery and mature identity-provider options; define support and abuse limits before opening registration | Threat/abuse/recovery review and sustainable exchange/API capacity; any IdP/email service separately approved | Estimate after operating evidence |

Prioritize a milestone by actual user demand and measured bottleneck. Public-market streams may precede advanced trading if shared IP pressure is the dominant limit. Redis or service separation is considered only when current process/cache/scheduler measurements identify a concrete need.
