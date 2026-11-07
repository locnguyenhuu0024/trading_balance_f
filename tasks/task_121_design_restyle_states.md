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

## Stage instruction (current)

This task runs in stages. Stage 2 is committed as work in progress and reviewed from rendered screenshots. The layout is close to the design.

**Current stage 2b, do exactly this:**

1. `orders_screen.dart` shows the order tabs twice: the new tab row and the old `Vị thế` dropdown. Keep only the tab row. Give each tab semantics as a selected button and a 48 target. Keep the old dropdown's `Key` on the tab row container if tests look it up, and update tests that opened the dropdown to tap the tab instead, with the same behavioral assertions.
2. `order_filter_controls.dart`: use chips for OKX too, with labels `Tất cả`, `Spot`, `Margin`, `Perpetual`, `Futures` and the same values. Chips scroll horizontally rather than overflow, with hit areas at least 48.
3. Binance position and order cards show `USDⓈ-M` instead of `SWAP` in their product badge and detail line.
4. `portfolio_screen.dart`: the `Tài sản chi tiết` heading and divider use the same 24 inset as the other sections.
5. Coordinator-observed failures to fix:
   - `orders_screen_position_layout_test: shows an accessible signed-out status` expects one `Tooltip` in the title row, but the refresh button now adds another. Find the status with `find.byTooltip('Chưa đăng nhập')`, keeping the semantics assertion.
   - `orders_screen_refresh_test: positions filters stay compact beside close-all` measures the removed dropdown (expected 146, actual 170). Assert instead that the chips row and close-all do not overflow at the same widths.
   - `backend_position_actions_dialog_test: loads only explicit backend targets` finds no `BTCUSDT` text, because the fuller title area pushes the card below its small test viewport. Make the Orders body scrollable as one list if it is not, so the card can be reached, and scroll to it in the test. Keep the test's assertions.

Finish by returning the structured report.

## 2. Objective

Retained screens match the design shell and pass accessibility checks.

Done when: Rendered light and dark review of retained frames passes with no behavior change.

Complete the work in this run; a long run is normal. Ending without file changes is a failed attempt.

## 3. Preconditions

Predecessors: T120 = PASS.
Required state: clean checkout on branch `codex/multi-platform-view-only`. Plan revision 2 approved.

## 4. Allowed Scope

Each stage gives the exact write list. Read access covers all non-protected source and tests, and the images in `designs/handoff-assets/`.

## 5. Forbidden Scope

Do not:
- read, search, parse, summarize or content-diff protected configuration, including `pubspec.yaml`, `pubspec.lock`, `analysis_options.yaml` and native project configuration;
- create, modify, regenerate or delete protected files, or add or remove dependencies;
- touch `backend/` or any git history, staging or branches;
- add any Binance or OKX write route;
- make opportunistic refactors or exceed the surface above.

If required work exceeds Allowed Scope, return `BLOCKED`.

## 6. Executor Contract

Visual layer only: no logic, provider or data change. Design reference is `designs/CLAUDE_DESIGN_HANDOFF.md` sections 5 and 7 and `designs/handoff-assets/`. Use `AppPalette` tokens; `strong` is `ink`, and `onStrong` exists. Treat coordinates as guidance only: use safe areas and scrolling. Keep every existing `Key`.

Common rules: horizontal inset 24; page title Bold 24 in the body, not a centered AppBar title, with a 48 back control on pushed screens; radius 12 for controls and 16 for large cards; thin `border` lines, no elevation; spacing 4/8/12/16/24/32; primary buttons 48 high in `ink` with `onStrong`; tabular figures for amounts; system font. Positive and negative keep their sign and do not rely on color. Use `Tài sản`, `Lệnh`, `Thị trường`, `Thêm`, `Công cụ` copy from the design. Remove nothing functional. Do not add prototype-only text such as `Dữ liệu minh họa`.

Direct OKX reads leave `OkxPosition.size` empty, so the position card shows nothing after the direction today. Show `pos` when `size` is empty, through the existing neutral `size` mapping in `okx_adapter.dart` only if a stage lists that file.

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
