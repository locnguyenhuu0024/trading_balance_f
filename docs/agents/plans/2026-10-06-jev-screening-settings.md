# Implementation Plan: Account JEV Screening Settings
Status: COMPLETE
Date: 2026-10-06
Tier: L
Specification: docs/agents/specs/2026-10-06-jev-screening-settings-design.md
Decision Ledger: docs/agents/decisions/2026-10-06-jev-screening-settings-decisions.md

## Objective and preconditions
Implements REQ-001..004 and AC-001..004. D-001/A-001/A-002 resolved; user preauthorizes immediate execution after planning. Branch codex/jev-screening-settings starts at pushed a64547c. Six preexisting unrelated telemetry lines preserved. Coordinator current fixed runtime retained, preferred C1 Sol medium, no claim of exposed main route.

## Planning Workstream Decomposition
| Workstream | Material | Independent | Explicit route | Logical run | Adoption |
|---|---|---|---|---|---|
| Backend/API/data migration/generation | YES | YES | R2 gpt-6.1-sol medium | R2-JEV-BE-001 | COMPLETE USED |
| Frontend/UI/API state/snapshot consumers | YES | YES | R2 gpt-6.1-sol medium | R2-JEV-FE-001 | COMPLETE USED |
Fan-out Required YES; Required Reasoning Agents2; Actual2; Compliance PASS; Skip N/A. Cross-layer synthesis coordinator-owned: full settings additive API, optional capability for legacy fakes, decimal percent UI, snapshot range validation, no current-settings re-filter. Both child routes explicitly bound; effective routes unavailable UNVERIFIABLE. Existing terminal children collected; runtime has no close/release primitive.

## P01 / T88 — Persist and freeze thresholds
Add three preference columns and transactional idempotent migration in backend/store.py. Extend strategy.py settings validation/full return/partial transactional groups; retain isolated mode reader. Automatic _create reads thresholds after replay detection and passes copied values to _generation_snapshot/_recommendation (optional default argument for direct legacy helper tests). Preserve rankings/cap/provider/records. Test backend settings/migration and generation boundaries/replay/provider-time setting change. Allowed source: backend/store.py, backend/strategy.py, backend/strategy_automatic.py. Allowed tests: backend/tests/test_strategy_automatic.py, backend/tests/test_strategy_queue.py, new backend/tests/test_strategy_settings.py if useful. New product helper files prohibited unless coordinator approves exact surface.
RED-001 then GREEN-001 formal checkpoint; V2 affected test modules. Build python3.12 -m compileall -q backend. E1 Luna xhigh: normal bounded SQL additive migration/API wiring, no unresolved design.

## P02 / T89 — Settings UI and immutable snapshot compatibility
New typed lib/features/strategy/domain/strategy_settings.dart; optional StrategySettingsApi capability and full typed GET/save in existing client while preserving old mode methods. Controller state/guards and settings dialog draft/inputs/validation/reset/help. Domain and wizard accept recorded valid thresholds without live settings. Extend focused tests and only necessary settings fakes. Explicit surfaces in task. RED-002 then GREEN-002 formal checkpoint; V2/V3 focused strategy settings/API/controller/domain/wizard tests. Build flutter build web --no-pub --release. E1 Luna xhigh: resolved normal frontend/API state work.

## DAG, waves and buildability
approved contract -> [T88 || T89] -> coordinator diff/integration audit -> final builds.
Disjoint backend/frontend writes; tests offline, isolated temp DB. Only T89 invokes Flutter while tasks run, avoiding shared Flutter caches. Typed capability keeps T89 compile self-contained without changing every legacy fake; additive backend leaves old frontend mode API valid. T88 canonical backend compile, T89 canonical web app build, no broken intermediate boundary allowed.

Coordinator-owned non-runtime documentation: update docs/development/ai-jev-strategy.md recommendation section to describe defaults, account Settings, frozen generation and fixed cap. This does not change provider setup.

## Verification and migration
Tasks execute narrow baseline regression if practical and formal negative RED then positive GREEN after final edits. Preserve mode preparation freezing, session safety, wizard selection and max10 orders. Final backend unittest discover once (V4 justified by schema/public settings contract); frontend focused settings/API/controller/domain/wizard/screen group (V3); final Python compileall, Flutter release web and macOS builds after all changes. Reuse fresh executor task evidence; rerun only missing/invalidated behavior checks. Full suite owner CODEX_ONCE for backend. No live financial/provider calls. Build/tests may consume manifests as opaque input only. Known SDK cache/loopback permissions may require escalation; no user external verification needed.
Migration: initialize under transaction rechecks missing columns, add defaults, preserves row values/time and mode. Verify legacy schema repeated/concurrent initialization. Rollout backend API restart before frontend; rollback old backend ignores columns, older frontend cannot consume custom snapshots reliably. External configuration actions none. Runtime settings files/manifests/locks/deployment paths forbidden.

## Traceability and completion
REQ-001 -> AC-001 -> P01 -> T88 -> RED-001/GREEN-001.
REQ-002 -> AC-002 -> P01 -> T88 -> RED-001/GREEN-001.
REQ-003 -> AC-003 -> P02 -> T89 -> RED-002/GREEN-002.
REQ-004 -> AC-004 -> P02 -> T89 -> RED-002/GREEN-002.
Risks: partial writes/data loss mitigated transaction and migration tests; stale state mitigated session/operation guards; old custom snapshot rejection addressed both readers; rounding mitigated finite decimal percent conversion. Final PASS only after all AC, audited non-protected diffs, fresh final builds, no unexplained protected changes. Commit/push is authorized by the user earlier in this session; no deployment.

## Completion evidence
T88 and T89 PASS; all AC-001..004 covered. Backend282 tests pass; seven-file focused Flutter group passes (exact total unavailable). Formal RED precedes GREEN and independently reviewed negative/positive expectations. Fresh final compileall/web/macOS canonical builds exit0; no executable changes afterwards. Final audit docs/agents/audits/2026-10-06-jev-screening-settings.md PASS. Protected config untouched; external actions none. Changes on codex/jev-screening-settings are ready for the previously authorized commit/push; deployment has not been run.
