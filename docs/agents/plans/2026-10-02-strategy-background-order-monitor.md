# Implementation Plan: Background Strategy Order Monitor

Status: READY_FOR_APPROVAL
Date: 2026-10-02
Tier: L
Specification: `docs/agents/specs/2026-10-02-strategy-background-order-monitor.md`
Decision Ledger: N/A

## 1. Objective and Preconditions

Implement REQ-001–006 / AC-001–006. Existing strategy application remains one exchange-side batch of reviewed limit orders; the new worker only reads order details and completion positions. User decisions D-001–006 in the specification are resolved. The new user-owned worker env path is approved; its contents and current API runtime configuration are not inspected.

## 2. Repository Impact

| Area | File | Planned change |
|---|---|---|
| Backend state | `backend/store.py` | Add durable monitor lease/fence and per-strategy scan freshness/error metadata; initialize old DB safely. |
| Backend strategy | `backend/strategy.py` | Share validated order reconciliation, fence worker writes, COMPLETE transition, expose sync metadata, add authenticated quote read. |
| Backend worker | `backend/strategy_worker.py` (new) | Minimal five-variable settings, isolated read-only OKX scan loop, signal handling/backoff/rate budget. |
| Backend tests | `backend/tests/test_strategy_api.py`, `backend/tests/test_strategy_worker.py` (new) | RED/GREEN and concurrency/no-trade tests. |
| Flutter client/controller | `lib/features/strategy/data/strategy_api_client.dart`, `lib/features/strategy/presentation/providers/strategy_dashboard_provider.dart` | Applied-strategy ticker uses authenticated backend quote endpoint. |
| Flutter UI/tests | `lib/features/strategy/presentation/strategy_screen.dart`, `test/features/strategy/strategy_api_client_test.dart`, `test/features/strategy/strategy_dashboard_controller_test.dart`, `test/features/strategy/strategy_screen_test.dart`, `test/features/strategy/strategy_wizard_dialog_test.dart` | Per-order states/partial fill and COMPLETE/stale views; authenticated quote request routing and fake-interface compatibility tests. |

Exact allowed writer paths are repeated in task files. No protected env/Docker/dependency/build/proxy configuration file is readable or writable by agents. Wizard and other feature source files are excluded.

## 3. User-owned External Configuration Action

Target file: `/home/deploy/trading_balance_f/trade-api-worker.env` (new, on Docker host). Location: five top-level `KEY=value` entries, exactly:

```dotenv
OKX_API_KEY=<SET_BY_USER_SAME_AS_API>
OKX_API_SECRET=<SET_BY_USER_SAME_AS_API>
OKX_API_PASSPHRASE=<SET_BY_USER_SAME_AS_API>
SESSION_SIGNING_KEY=<SET_BY_USER_SAME_AS_API>
OPERATION_DB_PATH=<SET_BY_USER_SAME_ABSOLUTE_CONTAINER_PATH_AS_API>
```

Scope: production worker container only. The user creates the file privately with restrictive permissions and confirms `OPERATION_DB_PATH` is on the API's persistent mounted database directory. No secret values are requested or stored in repository artifacts. The worker image is the rebuilt `trading-balance-trade-api`, with API container mounts shared via `--volumes-from trading-balance-trade-api` and a separate process command `python3 -m backend.strategy_worker`. Example host launch, after the updated API container is running:

```sh
docker run --detach --name trading-balance-strategy-worker --restart unless-stopped --env-file /home/deploy/trading_balance_f/trade-api-worker.env --volumes-from trading-balance-trade-api --entrypoint python3 trading-balance-trade-api -m backend.strategy_worker
```

The user owns file creation and Docker launch/recreation; agents do not run deployment. Validate with `docker inspect --format '{{.State.Running}}' trading-balance-strategy-worker` plus a safe UI status check after 5–10 seconds. Stop/recreate the worker when replacing its image. Production verification is blocked until the user applies this action; offline code/task verification is not blocked.

## 4. Planning Workstreams and Fan-out

| Workstream | Material | Independent | Route | Logical run | Status/adoption |
|---|---|---|---|---|---|
| Worker/runtime and concurrency | YES | YES | R3 / gpt-6-sol / high, explicit | R3-WORKER-001 | COMPLETE; USED: separate process, lease/fence, no transaction across network. |
| Data/reconciliation/API | YES | YES | R2 / gpt-6-sol / medium, explicit | R2-SYNC-001 | COMPLETE; USED: existing validated order reconciliation and persistence gap. |
| Frontend/dashboard | YES | YES | R2 / gpt-6-sol / medium, explicit | R2-DASHBOARD-001 | COMPLETE; USED: quote timer, API boundary, per-order presentation. |

Fan-out Required: YES. Required Reasoning Agents: 3. Actual Reasoning Agents: 3. Fan-out Compliance: PASS. Skip Reason: N/A. Coordinator synthesis: backend worker owns durable order scan; visible dashboard still requests current quote and actual PnL, now through authenticated backend; wizard direct market path remains unchanged.

## 5. Dependency Graph and Ordered Steps

```text
Plan approval -> T53 backend worker/state -> T54 quote API/dashboard -> final audit -> user-owned Docker rollout
```

### P01 / T53 — Durable read-only order monitor

Add two SQLite-owned structures: an atomic singleton monitor lease with owner/fence/expiry and a per-strategy sync record (`last_attempt_at`, `last_success_at`, safe error category, `next_scan_at`). The worker loads only the five approved env keys, verifies active OKX UID fingerprint, acquires/renews lease, and scans attempted APPLIED/PARTIAL/UNKNOWN strategies and expired APPLYING recovery. Reuse validated order-detail state parsing and CAS writes; require a valid lease fence for worker persistence, with no DB transaction held across OKX I/O. Query positions only when order rows are terminal and while a terminal-order strategy still has an open position; mark COMPLETED only on fresh zero-position proof. Keep pre-existing rows eligible. Target 5 seconds when healthy, cap/schedule calls below OKX endpoint limits and back off on failure/rate limit. Preserve API GET reconciliation as a stale-worker fallback without needless duplicate detail calls during a recent successful scan. Never call OKX write methods.

Retain the existing Apply path: after confirmation it submits every selected entry/DCA row for both selected sides to `/api/v5/trade/batch-orders` with `ordType=limit`, reviewed price/size, and current partial/unknown ACK safeguards. Add an explicit regression assertion; do not move placement to the worker.

RED: fake OKX fills an order while no GET occurs; existing state stays unchanged. GREEN: worker persists validated partial/full fill and scan timestamp; duplicate/expired lease, crash/restart, errors, account mismatch, and completion conditions behave as specified, with zero trade writes.

### P02 / T54 — Backend quote boundary and dashboard presentation

Add authenticated `GET /v1/strategies/{id}/quote` for an owned applied strategy. Revalidate the current OKX account fingerprint and strategy ownership on every request; do not cache identity across requests. Validate ticker instrument, exact positive decimal, exchange timestamp within 15 seconds, and no future quote. Reuse existing auth and error envelope; coalesce/cache the public ticker response for one second per instrument only after the identity check. Flutter dashboard retains its visible one-second timer and stale/out-of-order logic but calls `StrategyApi.getQuote`, not `StrategyMarketRepository.getTicker`; the wizard keeps its repository. Show each order state and filled/planned contracts, scan freshness, and COMPLETED label. Existing 20-second metrics request remains backend-only when visible.

RED: applied dashboard uses direct OKX quote, and running card omits per-order status. GREEN: fake Strategy API receives quote call while direct market repository receives none; order UI displays partial/full/canceled outcomes and stale scan; hidden dashboard sends no quote calls; wizard tests still pass.

## 6. Tests and Verification

| ID | Proves | Method |
|---|---|---|
| TEST-001 | AC-001/002/003; RED/GREEN worker | New `backend.tests.test_strategy_worker` with fake OKX/clock, two worker instances, crash, restart, account mismatch, and no-write assertions. |
| TEST-002 | API compatibility and status | `python3.12 -m unittest backend.tests.test_strategy_api -v`. |
| TEST-002A | AC-006 upfront placement | Existing/focused fake OKX Apply test asserts one batch containing all selected Long/Short entry/DCA rows, each `ordType=limit`, and no later worker trade write. |
| TEST-003 | AC-004/005; RED/GREEN UI | Focused strategy dashboard/screen Flutter tests with fake authenticated API and forbidden direct ticker stub. |
| TEST-004 | T53/T54 backend buildability | `python3.12 -m compileall -q backend` after each backend task's last edit. |
| TEST-005 | T54 Flutter buildability/final repo build | `rtk flutter build web --release` after final frontend edit. |
| TEST-006 | Whitespace/scope | `git status --short`, name-only diff first, then `git diff --check` and audited nonprotected diffs. |

Formal RED precedes GREEN per task. Inner loops use one focused test. T53 ceiling V2; T54 ceiling V2/V3 due cross-layer contract; final integration ceiling V3. Escalate only for a concrete shared regression. Reuse executor evidence when exact and fresh. Final repository build gate requires backend compileall plus Flutter web release build after all code changes. No live orders or production OKX calls in tests.

## 7. Risks, Migration, and Rollout

| Risk | Detection | Mitigation |
|---|---|---|
| Two worker instances or worker/API race | Lease/concurrency tests | Lease fence and per-strategy CAS; no network I/O in DB transaction. |
| Exchange outage/rate limit | Stale timestamp/error metadata | Preserve last known state, bounded backoff, never assume fill/completion. |
| 5-second target under many active instruments | Actual scan age exceeds target | Fair bounded queue; display actual freshness rather than claiming a guarantee. |
| Existing applied rows after deploy | Upgrade fixture | New sync table initializes without changing plans/orders; first worker scan includes them. |
| Worker env/database mismatch | Startup validation and no scan | Fail closed; user checks shared mount, account and file path locally. |
| Backend quote load | Focused rate/coalescing tests | Authenticate, validate ownership, cache/coalesce visible requests; no arbitrary public proxy. |

Rollout: code/tests/build first; user rebuilds/recreates backend API image/container using existing procedure; user creates worker env and starts separate worker; validate scan timestamp and known order status without placing a new order. Rollback: stop worker and revert code while leaving OKX orders and persisted strategies intact. A running strategy is not deleted or amended by rollback.

## 8. Task Decomposition and Buildability

| Task | Steps/AC | Route | Allowed write surface | Build unit |
|---|---|---|---|---|
| T53 | P01 / AC-001–003, AC-006 | E2 / gpt-6-luna / max, explicit | `backend/store.py`, `backend/strategy.py`, `backend/strategy_worker.py`, `backend/tests/test_strategy_api.py`, `backend/tests/test_strategy_worker.py` | Python backend: `python3.12 -m compileall -q backend`. |
| T54 | P02 / AC-004–005 | E1 / gpt-6-luna / xhigh, explicit | `backend/strategy.py`, `backend/tests/test_strategy_api.py`, `lib/features/strategy/data/strategy_api_client.dart`, `lib/features/strategy/presentation/providers/strategy_dashboard_provider.dart`, `lib/features/strategy/presentation/strategy_screen.dart`, `test/features/strategy/strategy_api_client_test.dart`, `test/features/strategy/strategy_dashboard_controller_test.dart`, `test/features/strategy/strategy_screen_test.dart`, `test/features/strategy/strategy_wizard_dialog_test.dart` | Python backend compileall and Flutter web release build. |

T53 precedes T54 because both change `backend/strategy.py` and T54 consumes the completed-state contract. Two tasks have distinct RED/GREEN paths and independently buildable boundaries. No executor may edit task/plan/spec/telemetry or protected configuration.

## 9. Completion Gate

- [ ] User explicitly authorizes this current plan after presentation.
- [ ] T53 and T54 have exact model/effort bound at dispatch, formal RED-before-GREEN, and task buildability PASS.
- [ ] Every AC has independently audited implementation and test evidence; no worker exchange writes.
- [ ] No protected configuration file content read or modified; user-owned env action reported and production verification status explicit.
- [ ] Final backend and Flutter builds PASS after last change; final audit PASS.

Commit/push and deployment are separate user decisions. Code completion cannot claim production worker operation until the user performs the external env/container action.
