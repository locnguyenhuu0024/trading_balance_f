# Task 22 — Risk monitoring notifications and integration

Status: PASS
Executor: implementation executor (configured target gpt-5.6-luna / max; verify effective routing)
Specification: `docs/agents/specs/2026-09-10-isolated-margin-risk-dashboard-design.md`
Plan: `docs/agents/plans/2026-09-10-isolated-margin-risk-dashboard.md`
Plan Steps: P05
Requirements: REQ-009, REQ-011
Acceptance Criteria: AC-009, AC-011; integration of all ACs

## 1. Objective

Complete the single auditable outcome in canonical plan §5 P05. Done when the referenced ACs and required negative/success scenarios are observed, scope is audited and coordinator verdict is PASS. Do not substitute a summary for repository evidence.

## 2. Preconditions

Predecessors: T21 = PASS.
Required decisions: D-001–005, A-001. Explicit execution approval of the presented plan is mandatory before dispatch. Coordinator confirms Definition of Ready and reads execution/audit rules. Inspect applicable AGENTS and context optimization profile; preserve existing user changes. Read only relevant specification sections and P05, not all framework/templates.

## 3. Allowed Scope

- `lib/features/portfolio/application/risk_monitor.dart`
- `lib/features/portfolio/application/risk_monitor_runtime.dart`
- `lib/features/portfolio/application/risk_notification_sink.dart`
- `lib/core/services/background_service.dart`
- `lib/main.dart (risk bootstrap and WebStorageHelper credential invalidation only)`
- `lib/core/security/secure_storage_helper.dart (credential invalidation only)`
- `lib/features/portfolio/presentation/providers/risk_dashboard_provider.dart (runtime bridge wiring only)`
- `lib/features/portfolio/data/risk/risk_repository.dart` (remediation only: preserve typed HTTP/retry failure metadata for monitor classification and cache-aware orchestration; no endpoint or financial-semantic changes)
- `lib/features/portfolio/application/risk_monitor_bridge.dart` (remediation only: typed service command/state transport required for the approved Android owner; no UI/product-semantic changes)
- `test/widget_test.dart (fake runtime injection only)`
- `test/features/portfolio/risk/risk_monitor_test.dart`
- `test/features/portfolio/risk/risk_runtime_test.dart`
- `test/features/portfolio/risk/risk_notification_test.dart`

Synthetic fixtures may be created under `test/features/portfolio/risk/fixtures/`. No real account payloads. Executor reports evidence to coordinator; coordinator owns planning/audit metadata and task allocation.

Coordinator escalation note: the first T22 audit proved two upstream contracts insufficient for the already-approved P05 behavior: `RiskRepository.loadPosition` erased HTTP status/retry metadata, and the typed bridge lacked Android service transport. The task permits escalation for evidenced shared-surface regressions. These narrow additions preserve the approved endpoint/formula/UI semantics and do not expand product scope.

## 4. Forbidden Scope

No unrelated refactors, generated Orders DTO changes, trading API writes, dependency changes, deployment, Git mutations, real credential reads or private API calls. No external services beyond explicitly authorized official OKX documentation. No product-semantic decisions outside the specification. Return BLOCKED if required work exceeds the write surface.

## 5. Executor Contract

Follow canonical P05 in order. Use specification formulas/defaults and missing-data behavior exactly. Domain functions are pure and platform code must reuse them. Honor all applicable INV/EDGE entries called out by P05. Incomplete API data uses specified quality states; do not invent neutral or zero values. User-authored plan text remains text, never a trading command.

Before handoff inspect the diff, scope, changed symbols and test evidence. Do not claim runtime/native verification from mocks. If effective executor model is explicitly reported different from configured target, report BLOCKED.

## 6. Tests

Test files above implement RED-005/GREEN-005 prefixes and independently derived expectations below. Use injected time, storage, HTTP and platform interfaces. Narrow diagnostics first; do not run broad suites during each edit. Existing compatibility checks are listed in the canonical plan.

## 7. Mandatory Verification

### RED — RED-005

Scenario and expected outcome: Permission denial, native unavailable, service disconnect/restart, duplicated command, 401/429 and late prior-account response cause no PnL event, no extra owner and no wrong-account write. Failed durable latch write causes zero OS notifications. Stale/unchanged reconnect does not spam.

Command: `flutter test test/features/portfolio/risk/risk_monitor_test.dart test/features/portfolio/risk/risk_runtime_test.dart test/features/portfolio/risk/risk_notification_test.dart --plain-name RED-005 --reporter compact`
Actual: PASS — 9 tests passed after the final implementation/test-support change.
Status: PASS

### GREEN — GREEN-005

Scenario and expected outcome: Fake HTTP/clock/storage/sink pipeline persists one event before one delivery; restart reuses latch. Worsening and confirmed improvement both deliver once. Cadences stay bounded/no overlap. Native bridge and foreground owner publish equivalent state. Run final integration checks only after scoped verification is PASS.

Command: `flutter test test/features/portfolio/risk/risk_monitor_test.dart test/features/portfolio/risk/risk_runtime_test.dart test/features/portfolio/risk/risk_notification_test.dart --plain-name GREEN-005 --reporter compact`
Actual: PASS — 31 tests passed after RED-005 and after the final implementation/test-support change.
Status: PASS

Execute RED before GREEN at the formal checkpoint. After implementation/test-support changes restart the pair under the governing direct-user AGENTS instruction. Verification ceiling: V3. Escalation only for an evidenced shared-surface regression or missing AC evidence. Final full-suite ownership belongs to coordinator integration, not each task.

## 8. Stop Conditions

Return BLOCKED for missing material contract, incompatible API semantics beyond explicit unavailable handling, scope expansion, failed prerequisite, unavailable necessary verification or an explicit model mismatch. Include evidence, affected IDs and needed coordinator decision. Do not silently reduce full scope.

## 9. Execution Ledger

- [x] Definition of Ready and authorization confirmed
- [x] Referenced symbols inspected
- [x] Assigned P05 implemented within allowed scope
- [x] Required tests/fixtures added or updated
- [x] Formal RED executed and observed
- [x] Formal GREEN executed and observed afterward
- [x] Verification ceiling respected
- [x] Compact report: changed files, behavior, commands/results, unresolved limits

## 10. Coordinator Audit

Scope: PASS — final diff matches P05 plus documented R22-001 through R22-005 escalations; no dependency, generated, credential, trading-write or Git-history changes.
Acceptance criteria: PASS — AC-009 and AC-011 plus final integration of all ACs are covered by the single-owner runtime, durable event ordering, local notifications, lifecycle, retry and cache behavior.
Test quality: PASS — formal negative/success selectors include remediation regressions; unfiltered focused T22/repository suite passed 92/92.
RED evidence: PASS — coordinator observed RED-005 9/9 after the final change.
GREEN evidence: PASS — coordinator observed GREEN-005 31/31 after RED-005 and after the final change.
RED-before-GREEN: PASS
Architecture/contract conformance: PASS — independent auditor final verdict PASS; Android service owns monitoring exclusively, web/other platforms use foreground ownership, and OS payloads remain privacy-safe.
Evidence reuse vs rerun: PASS — coordinator reran formal checkpoints, focused checks, full 197-test suite, analyzer, web build and Android debug build.
Verdict: PASS

### Remediation R22-001

First independent audit verdict: REWORK. Required remediation IDs:

- AUD-T22-001: implement an actual Android service owner/typed command-state bridge, ownership acquisition, acknowledgments, reconnect and service-loss behavior; a generic status-only service is insufficient;
- AUD-T22-002: wire the installed native notification plugin as the production sink, preserve permission/capability state and retain in-app events when denied; web remains in-app only;
- AUD-T22-003: preserve repository HTTP status/retry metadata so only 401 blocks credentials; 429/network failures use bounded retry/backoff and `Retry-After` when longer;
- AUD-T22-004: serialize timer captures and every mutation/store write in one queue with generation checks; prove no lost plan/history/latches during deferred races;
- AUD-T22-005: implement foreground pause/resume/departure baseline behavior and dispose active/unused owners correctly;
- AUD-T22-006: restore/persist OI history, combine it into market evaluation, batch writes/flush on stop, and cache stable position metadata/rates with the approved cadences;
- AUD-T22-007: sample risk history at the approved 15-minute cadence rather than every poll while preserving fresh current state;
- AUD-T22-008: pass previous/current plans to the reducer and apply reconnect gap semantics only after more than five minutes;
- AUD-T22-009: replace vacuous tests with real adapter orchestration and exact durable ordering; cover native wiring, denial, restart, lifecycle, credential bus, 401/429/network, service loss, cadence/backoff, storage races, reload, OI and reconnect cases.

All formal RED/GREEN evidence is invalidated by the production/runtime and test-support changes and must restart from RED-005.

### Remediation R22-002

Second independent audit verdict: REWORK. Required remediation IDs:

- AUD-T22-010: make the Android wire codec round-trip the complete dashboard state (evaluation, quality, plan/settings, market, history/summaries, comparison/trend/velocity, events and capability), and prove populated foreground/service parity;
- AUD-T22-011: add an explicit service-isolate credential-invalidation command that immediately fences prior generations, clears repository caches and restarts the last requested identity only after invalidation; protect foreground caches from late pre-invalidation fetches repopulating them;
- AUD-T22-012: separate candle and non-candle fetch cadences so candles refresh every five minutes during continuous monitoring without one-minute fetches resetting their age or discarding new candles;
- AUD-T22-013: keep the latest accepted event sample independently from the downsampled persisted history so an OI-only flush cannot regress event comparison state;
- AUD-T22-014: resume live foreground monitoring immediately while using the away duration only for comparison-session semantics; cancel pending resume work on every later pause; preserve UI departure/resume checks while Android service ownership continues;
- AUD-T22-015: treat command acknowledgement timeout/service silence as ownership loss, clean up timers, publish unavailable/reacquire through the runtime, and test a silent service whose streams remain open;
- AUD-T22-016: allow an explicit manual refresh to retry after a 401, propagate enrichment 401/429/network metadata, make ledger caching reusable across moving episode end times, and parse both delta-seconds and RFC HTTP-date Retry-After values;
- AUD-T22-017: invalidate the native notification capability cache when lifecycle/permission state may change;
- AUD-T22-018: add non-vacuous tests for all cases above plus the full 30/60/120/300-second capped backoff sequence and continuous polling across the five-minute OI boundary.

All R22-001 verification evidence is invalidated by these runtime, repository, codec and test-support changes. Restart the formal RED-005 then GREEN-005 checkpoint after remediation.

### Remediation R22-003

Third independent audit verdict: REWORK. Required remediation IDs:

- AUD-T22-019: separate handshake timeout, liveness timeout and command completion. A slow healthy command may exceed five seconds while typed heartbeats continue and must not tear down ownership; test a slow acknowledged capture with uninterrupted heartbeats;
- AUD-T22-020: restore the latest accepted event baseline from the persisted latch rather than sparse history after restart, including the OI-only flush case, so unchanged risk cannot emit a false reconnect/change event;
- AUD-T22-021: track Android UI check departure/resume independently while the service monitor continues polling. Persist/freeze the UI departure baseline and start the next comparison after more than 60 seconds without stopping the service owner;
- AUD-T22-022: include every remediation regression in the formal RED-005/GREEN-005 selectors, then run the complete focused files. Test evidence that omits `R22-002` scenarios is insufficient.

All prior formal RED/GREEN evidence is invalidated by these runtime/state/test-support changes. Restart RED-005 then GREEN-005 after remediation and follow with the unfiltered focused T22/repository suite.

### Remediation R22-004

Fourth independent audit verdict: REWORK. Required remediation:

- AUD-T22-023: service-owned Android UI resume must invalidate and recheck the cached native notification capability before capture/delivery. Add a formal controller/proxy lifecycle test that changes permission while paused and verifies refreshed capability and delivery after resume.

This notification/lifecycle change invalidates the formal checkpoint. Restart RED-005 then GREEN-005 and the unfiltered focused suite after remediation.

### Integration Remediation R22-005

Final V4 full-suite evidence exposed one cross-task regression: `crypto_icon_url_test.dart` requires every asset screen to use the shared `CryptoIcon`, while the redesigned Risk Home position context shows the pair without it. Narrowly permit `lib/features/portfolio/presentation/portfolio_screen.dart` for adding the shared base-asset icon and `test/features/crypto_icon_urls/crypto_icon_url_test.dart` only if its assertion needs a semantic update. Preserve privacy masking and responsive layout. Run the failing test as RED before the change, then rerun it as GREEN plus T21 dashboard tests and T22 formal/focused checks.
