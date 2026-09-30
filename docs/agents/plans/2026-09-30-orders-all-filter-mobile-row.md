# Implementation Plan: ALL transaction filter and mobile filter row

Status: COMPLETE
Date: 2026-09-30
Tier: M
Specification: `docs/agents/specs/2026-09-30-orders-all-filter-mobile-row.md`
Decision Ledger: N/A

## Objective and readiness

Implements REQ-001/002 and AC-001..004. User decision D-001 confirms ALL for all three statuses. The user authorized Task 32 after plan presentation and requested an origin/main pull first. The pull fast-forwarded to `580f300` and changed only `README.md`. No protected configuration content is needed or writable.

## Planning workstreams

| Workstream | Material | Independent | Requested route | Logical run | Result |
|---|---|---|---|---|---|
| Flutter UI/layout | Yes | Yes | R2, gpt-6-sol / medium, explicit | R2-001 | Complete, used |
| Provider/repository data behavior | Yes | Yes | R2, gpt-6-sol / medium, explicit | R2-002 | Complete, used |

Fan-out Required: YES. Required Reasoning Agents: 2. Actual Reasoning Agents: 2. Fan-out Compliance: PASS. Skip Reason: N/A. Effective routes were not exposed by the runtime; explicit requested routes are recorded as UNVERIFIABLE. Coordinator synthesis: UI sends one stable `ALL` selection; repository expands it to concrete types. Existing positions SPOT guard remains only for SPOT. ALL polling is slowed to 5 seconds to bound fan-out load.

## Repository impact and task DAG

One bounded compile-coupled task, T32 / P01; no predecessor or parallel writer.

Allowed product/test surfaces:
- `lib/features/orders/presentation/widgets/order_filter_controls.dart`
- `lib/features/orders/presentation/orders_screen.dart`
- `lib/features/orders/presentation/providers/order_provider.dart` if needed for the approved ALL flow
- `lib/features/orders/data/order_repository.dart`
- focused new or existing tests under `test/features/orders/`

No dependency manifests, build/toolchain files, other configuration, generated model files, or unrelated screens may change. External configuration/environment actions: none.

### P01 — Implement ALL and responsive row

1. Add ALL to the selector; make both dropdowns share a row at mobile widths, with constraints that fit narrow viewports.
2. Expand ALL in repository into the specified type requests, merge atomically, and sort combined order results by numeric `cTime` descending with stable tie/invalid handling. Preserve single-type paths.
3. Keep SPOT positions special case; throttle ALL automatic refresh to 5 seconds while preserving manual refresh and existing single-type interval. Avoid overlapping automatic cycles.
4. Add focused tests for repository aggregation/failure and mobile layout/selection.

Stop if an API contract or missing product choice makes this plan invalid; do not infer protected configuration values.

## Verification

Formal RED before GREEN after implementation is ready:
- RED-001: focused ALL partial-failure and SPOT-position tests. Expected error rather than a partial merged list, and zero SPOT positions requests.
- GREEN-001: focused repository/provider tests with fake responses for each concrete type. Expected 3 position types, 4 order types, global order by numeric time, and no `instType=ALL`.
- GREEN-002: focused widget test at 390 px. Expected same-row dropdowns, ALL selection callback, and no overflow.

Use `flutter test --no-pub <focused test file>` for V1; V2 ceiling is the new focused files and directly affected existing orders tests. Escalate to V3 only for a discovered shared behavior regression. Buildability gate after the final code edit: `flutter build web --no-pub` for the Flutter web application. Run a focused `flutter analyze` on changed source/test paths if test/build diagnostics warrant it. Full suite is not required for this bounded change.

## Risk and completion

ALL fans out to 3 or 4 requests per load. The 5-second interval bounds routine volume; any subtype error surfaces as error. The coordinator audits the final source/test diff, RED-before-GREEN evidence, build status, and single-type preservation. Task reaches PASS only after the build and acceptance evidence pass. No commit or push is authorized.

Completion evidence: T32 PASS. Executor observed RED before source edits, then focused GREEN and directly related existing tests passed. The final `rtk proxy flutter build web --no-pub` exited 0. Coordinator independently ran the three new focused test files (8 tests passed) and `git diff --check` (exit 0). Final changed paths stayed within the approved implementation, planning, and telemetry surfaces.
