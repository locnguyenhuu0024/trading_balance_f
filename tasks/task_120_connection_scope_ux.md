# Task 120 — Connection experience and account states

Status: PASS
Agent Role: implementation_executor
Executor Class: E3
Target Model: gpt-6.1-terra
Target Effort: high
Target Route: gpt-6.1-terra / high
Routing Policy: EXECUTOR_ROUTING_POLICY.json v2 (OptCodex v1.4.0)
Route Rationale: Multi-file frontend integration with explicit invariants, on contracts delivered by T117 to T119.
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Specification: `docs/agents/specs/2026-11-07-multi-platform-view-only-design.md`
Plan: `docs/agents/plans/2026-11-07-multi-platform-view-only.md`
Plan Steps: P05
Requirements: REQ-009, REQ-010
Acceptance Criteria: AC-009, AC-010

## 1. Dispatch Compliance

Before this task may enter `EXECUTING`, the coordinator must spawn an `implementation_executor` with both Target Model and Target Effort explicitly supplied. Omitting either or inheriting a route is prohibited. The coordinator has done this: the dispatcher passes `--model` and `model_reasoning_effort` on your command line, and your prompt states the route. You cannot observe more than that from inside the run, and `UNVERIFIABLE` is a valid state. Do not stop for it; start the task.

Dispatch Route Status: UNVERIFIABLE (explicitly bound by `scripts/ccb/dispatch.py`, runtime does not expose the effective route)
Requested Model: gpt-6.1-terra
Requested Effort: high
Observed Effective Model: unavailable
Observed Effective Effort: unavailable

## Stage instruction (current)

Stage C2 is committed. **Current stage C2b, test-only:** in `test/features/portfolio/portfolio_loading_test.dart`, the test `completed error stays visible until a pending retry begins` asserts raw exception text, which REQ-010 now forbids on screen. Change it to expect `Không thể tải dữ liệu` while the error is shown, its absence while the retry is pending with the progress indicator, and the same message after the retry fails. Also assert `balance failed` and `retry failed` never appear. Keep the `loadCalls` assertions. Change nothing else. Finish by returning the structured report.

## 2. Objective

A user can connect Binance, switch between connections, manage them, and see correct state for each.

Done when: OKX and Binance are both registered and selectable, and switching follows the design with fake transports.

Complete the work in this run; a long run is normal. Ending without file changes is a failed attempt.

## 3. Preconditions

Predecessors: T118 and T119 = PASS. Decisions: D-001, D-004, D-008, D-009, D-010, P-003.
Required state: clean checkout on branch `codex/multi-platform-view-only`. Plan revision 2 approved.

## 4. Allowed Scope

Each stage below gives the exact write list. New files use exactly those names. Read access covers all non-protected source and tests.

## 5. Forbidden Scope

Do not:
- read, search, parse, summarize or content-diff protected configuration, including `pubspec.yaml`, `pubspec.lock`, `analysis_options.yaml` and native project configuration;
- create, modify, regenerate or delete protected files, or add or remove dependencies;
- touch `backend/` or any git history, staging or branches;
- add any Binance or OKX write route;
- make opportunistic refactors or exceed the surface above.

If required work exceeds Allowed Scope, return `BLOCKED`.

## 6. Executor Contract

Design is fixed; mechanism details are yours if they satisfy the invariants and tests. Report what you chose. Stop only for a conflict about product behavior.

Stage A, selection:
1. Register Binance in `exchangeRegistryProvider` with connectionId `binance-default`. Labels: OKX account `Chính`, product line `Tài khoản giao dịch`; Binance account `Chính`, product line `USDⓈ-M · Spot · Margin`, on web `USDⓈ-M`. The illustrative `Futures 01` and `USDT Perpetual` are not used.
2. `configuredConnectionsProvider`: profiles whose keys exist in storage, in registry order. If the selected connection has no keys, the scope falls back to the other configured connection, else OKX's existing no-key state (EDGE-002).
3. `ScopeBar`: 54 high, radius 12, badge 34 with exchange initial, two-line label, chevron; hit area at least 48; button semantics naming exchange and account. Tapping opens `ScopePicker`.
4. `ScopePicker`: heading `Chọn sàn & tài khoản`, rows with `Đang xem` or `Chuyển sang tài khoản này`, the active row with a stronger border, and `Quản lý kết nối`.
5. `ScopeSwitchGate` in the shell: on selection pop pushed routes, go to `Tài sản`, key the subtree by connectionId and epoch, and show `Đang tải <exchange> / <account>` with the bar until the account read settles. The text sits in a live region; the spinner is static under reduced motion.
6. Add `ScopeBar` at the top of Tài sản, Lệnh, Thị trường, Công cụ, BMAG, Hỗ trợ / kháng cự and Cài đặt, using existing layouts.

Stage B, management:
7. `ConnectionsScreen` (`Sàn & tài khoản`): one card per configured connection with exchange, account, product line and state, reachable from Tools and the picker; footer `+ Thêm kết nối`.
8. `ConnectionCatalogScreen` (`Thêm kết nối`): OKX, Binance, disabled `Sàn khác`. One connection per exchange, so an existing one opens its form to repair.
9. OKX opens the existing `SettingsTradeAccessPage`, unchanged. `BinanceConnectionForm`: key and secret, obscured secret, guidance to use a read-only key, `Kiểm tra kết nối`, `Lưu`, and `Xóa kết nối` with confirmation. A test succeeds if any platform-available wallet read succeeds. Saving goes through `trackBinanceCredentialMutation`. Secrets never appear in errors or state.

Stage C, states:
10. Show instruments from `InstrumentKey.base` and `quote` when present, falling back to the existing OKX split only for OKX. Never split a Binance id.
11. Filter chips from `capabilities`: Binance shows `Tất cả`, `USDⓈ-M` (value `SWAP`), `Spot`, `Margin`; OKX unchanged. On web Binance shows `Tất cả` and `USDⓈ-M`.
12. Margin section on the Lệnh positions tab from `AccountSnapshot.marginRows`: cross and isolated cards showing net, borrowed, interest, margin level, and for isolated liquidation and index price. Absent values show `—`. No close action.
13. Non-OKX absent amounts show `—`, not `0.00`. Partial total shows `Chưa đầy đủ` with reasons; unpriced rows say `Chưa định giá`. Map wallet issues to Vietnamese from `walletResults`; do not show the English issue text.
14. States per spec section 12 through `adapter.classify`: expired shows `Cần kiểm tra lại kết nối` with `Kiểm tra kết nối` opening the form, and other connections stay selectable; empty per design; web shows `Chỉ có trên ứng dụng` for Spot and Margin; generic failure shows a retry card replacing raw `Lỗi: $error` in Orders and `Lỗi kết nối: $errorMessage` in Portfolio. Keep OKX retry behavior. Automatic refresh stops on terminal failures for every exchange through `classify`.
15. Binance history shows which symbols are covered, from `binanceHistorySymbolsProvider`.

Required invariants and edges: INV-001, INV-003, INV-004; EDGE-002, EDGE-004, EDGE-005, EDGE-010.
Apply reuse-first, minimal complete changes. Do not invent product semantics. If the contract is insufficient, return `BLOCKED`.

## 7. External Configuration / Environment Actions

Planned action: none.
Blocks verification until user applies: NO

## 8. Tests

- TEST-120-1: persistence across restart.
- TEST-120-2: fallback when keys are removed.
- TEST-120-3: state rendering.
- TEST-120-4: OKX settings keys intact.

## 9. Mandatory Verification

### RED — RED-120a/b
Scenario: (a) Picker opened with Binance keys removed while selected. (b) Binance expired on Tài sản. Also: a raw exception string from the read.
Command/method: `rtk flutter test --no-pub <file> --plain-name '<name>'`
Expected: (a) Fallback to OKX with no crash. (b) `Cần kiểm tra lại kết nối`, OKX remains selectable, and no raw error text anywhere.
Actual: PENDING
Status: PENDING

### GREEN — GREEN-120
Scenario: Fake transports: OKX to Binance to OKX; restart with Binance selected; web platform Binance.
Command/method: `rtk flutter test --no-pub <file> --plain-name '<name>'`
Expected: Target loading shown; no former data; lands on Tài sản; Binance restored after restart; web shows USD-M plus `Chỉ có trên ứng dụng`.
Actual: PENDING
Status: PENDING

Run RED before GREEN. Verification ceiling: V3: `test/features/connections`, `test/features/settings`, `test/features/portfolio`, `test/features/orders`.
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

Attempt: 9f94cb21b0ea48b0b181447eec1f86c4
Dispatch route compliance: UNVERIFIABLE (requested gpt-6.1-terra/high, explicit).
Parent route inheritance: NO
RED and GREEN executed by the coordinator on the host, RED first (VAL-005): removed keys fallback, expired Binance keeps OKX selectable, raw error hidden; then full suite
Regression and buildability, coordinator-observed: Full test directories passed; analyzer 0 errors; web build pass. Delivered over stages A, A2, A3, B, C1, C2, C2b. AUD-120-01 to 04 found by coordinator and fixed, including a saved secret loaded into the form.
Task buildability gate: PASS
Verdict: PASS
