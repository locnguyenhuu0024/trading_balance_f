# Task 121 — Design shell and accessibility

Status: PENDING
Agent Role: implementation_executor
Executor Class: E2
Target Model: gpt-6.1-terra
Target Effort: medium
Target Route: gpt-6.1-terra / medium
Routing Policy: EXECUTOR_ROUTING_POLICY.json v2 (OptCodex v1.4.0)
Route Rationale: Routine presentation work with no logic or provider change and clear acceptance criteria.
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Specification: `docs/agents/specs/2026-11-07-multi-platform-view-only-design.md`
Plan: `docs/agents/plans/2026-11-07-multi-platform-view-only.md`
Plan Steps: P06
Requirements: REQ-011
Acceptance Criteria: AC-011

## 1. Dispatch Compliance

Before this task may enter `EXECUTING`, the coordinator must spawn an `implementation_executor` with both Target Model and Target Effort explicitly supplied. Omitting either or inheriting a route is prohibited. The coordinator has done this: the dispatcher passes `--model` and `model_reasoning_effort` on your command line, and your prompt states the route. You cannot observe more than that from inside the run, and `UNVERIFIABLE` is a valid state. Do not stop for it; start the task.

Dispatch Route Status: UNVERIFIABLE (explicitly bound by `scripts/ccb/dispatch.py`, runtime does not expose the effective route)
Requested Model: gpt-6.1-terra
Requested Effort: medium
Observed Effective Model: unavailable
Observed Effective Effort: unavailable

## 2. Objective

Retained screens match the design shell and pass accessibility checks.

Done when: Rendered light and dark review of retained frames passes with no behavior change.

## 3. Preconditions

Predecessors: T120 = PASS.
Required state: clean checkout on branch `codex/multi-platform-view-only`. Plan revision 2 approved.

## 4. Allowed Scope

- `lib/core/navigation/trading_navigation_bar.dart`
- `lib/core/theme/app_theme.dart` (text style additions only; palette unchanged)
- Presentation files for portfolio, orders, market, fractal_tracker, support_resistance, settings, tools, connections
- Related presentation tests

## 5. Forbidden Scope

Do not:
- read, search, parse, summarize or content-diff protected configuration, including `pubspec.yaml`, `pubspec.lock`, `analysis_options.yaml` and native project configuration;
- create, modify, regenerate or delete protected files, or add or remove dependencies;
- touch `backend/` or any git history, staging or branches;
- add any Binance or OKX write route;
- make opportunistic refactors or exceed the surface above.

If required work exceeds Allowed Scope, return `BLOCKED`.

## 6. Executor Contract

1. Apply the shell: 24 inset, 54 scope bar, radius 12 and 16, card layouts from handoff section 7, using existing system font and tabular figures.
2. Use the design copy: `Tổng tài sản tài khoản`, `Phạm vi dữ liệu`, `Tài sản chi tiết`, order tabs, `Công cụ`. Remove prototype-only copy such as `Dữ liệu minh họa`.
3. Keep Vietnamese, masking, currency and time zone logic unchanged.
4. Use safe areas and scrolling, not fixed coordinates. Keep bar labels readable; prefer not below 11 at default scale and scale with `textScaler`.

Required invariants and edges: No logic or provider changes. Numbers come from existing formatters.
Apply reuse-first, minimal complete changes. Do not invent product semantics. If the contract is insufficient, return `BLOCKED`.

## 7. External Configuration / Environment Actions

Planned action: none.
Blocks verification until user applies: NO

## 8. Tests

- TEST-121-1: narrow width and large text have no overflow.
- TEST-121-2: target sizes.
- TEST-121-3: reduced motion for switch loading.

## 9. Mandatory Verification

### RED — RED-121
Scenario: 320-wide viewport at the app maximum text scale with a long account label on each retained screen.
Command/method: `rtk flutter test --no-pub <file> --plain-name '<name>'`
Expected: No overflow exceptions; scope bar and nav remain operable; targets at least 48.
Actual: PENDING
Status: PENDING

### GREEN — GREEN-121
Scenario: Web build reviewed at 390 x 844 in light and dark against `designs/handoff-assets` 01, 02, 03, 07, 08.
Command/method: `rtk flutter test --no-pub <file> --plain-name '<name>'`
Expected: Layout, hierarchy and tokens match, excepting the fifth nav item, per P-001.
Actual: PENDING
Status: PENDING

Run RED before GREEN. Verification ceiling: V3: presentation tests; final V4 runs in the final integration audit, not here.
Escalate only if: a shared provider or fixture used outside this set changes.

### Verification environment

Confirmed by the coordinator: this sandbox cannot run `flutter test`, because the test runner cannot bind 127.0.0.1, and the default SDK cache is not writable. Do not spend time on this and do not stop for it.

- Write the complete code and tests. Do not run `flutter test`.
- For a compile check, use `env HOME=/private/tmp/claude-501/-Users-locnguyen--claude-spares-spare-1YiVQu/74faedd6-f84d-41fb-aa01-a0288d74204a/scratchpad/flutter-home PUB_CACHE=/Users/locnguyen/.pub-cache /private/tmp/claude-501/-Users-locnguyen--claude-spares-spare-1YiVQu/74faedd6-f84d-41fb-aa01-a0288d74204a/scratchpad/flutter-sdk/bin/flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings`, and `env HOME=/private/tmp/claude-501/-Users-locnguyen--claude-spares-spare-1YiVQu/74faedd6-f84d-41fb-aa01-a0288d74204a/scratchpad/flutter-home PUB_CACHE=/Users/locnguyen/.pub-cache /private/tmp/claude-501/-Users-locnguyen--claude-spares-spare-1YiVQu/74faedd6-f84d-41fb-aa01-a0288d74204a/scratchpad/flutter-sdk/bin/flutter build web --no-pub` for buildability.
- In your report set `red` and `green` to `NOT_RUN`, naming the exact tests and the order RED then GREEN. Set `status` to `COMPLETED`.
- The coordinator executes RED then GREEN on the host during audit and returns any failure as a bounded remediation.

### Conflict rule

If a sentence in this contract conflicts with how OKX behaves today, REQ-012 wins: keep the existing OKX behavior, implement the rest, and name the conflict in your summary. Stop only if the conflict affects something other than OKX preservation.

### Task Buildability Gate

Required: YES
Affected canonical build unit: Flutter app `lib/` and `test/`
Exact secret-free build command: `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings && flutter build web --no-pub`
Executed after the last task-local change: PENDING
Result: PENDING

### External Verification

Required: NO for this task. The program's user-run live check follows the final audit.

## 10. Stop Conditions

Return `BLOCKED` when repository evidence contradicts this contract, a design decision is missing, a dependency appears necessary, scope is exceeded, or verification is unavailable. Report evidence, affected IDs, and the coordinator decision needed.

## 11. Execution Ledger

- [ ] confirm route binding
- [ ] inspect referenced symbols
- [ ] implement assigned step
- [ ] add or update tests
- [ ] execute formal RED, then GREEN
- [ ] run buildability gate after last change
- [ ] return compact executor report
- [ ] confirm no protected content read or modified

## 12. Coordinator Audit

Verdict: PENDING
