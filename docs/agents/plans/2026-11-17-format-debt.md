# Implementation Plan: Clear `dart format` debt

Status: COMPLETE
Approval: "Duyệt A, commit, làm" (user, chat, 2026-11-17, on this revision; Option A coordinator tool-run override for T145; includes commit on PASS)
Date: 2026-11-17
Tier: S
Plan ID: PLAN-20261117-format-debt
Domain: mobile (Flutter)
Branch: `codex/multi-platform-view-only` (current branch)
Request: "Lên plan format" (user, 2026-11-17), follow-up of PLAN-20261117-analyzer-zero.

## 1. Objective

`dart format --output=none --set-exit-if-changed lib test` exits 0 (13 files → 0), with no semantic change. Afterwards the format check becomes part of every task's buildability gate.

## 2. Observations (host, HEAD `6f01085`)

- OBS-301: 13 files are not `dart format`-clean; diff size (changed lines, before/after):

| File | Lines |
|---|---|
| `lib/core/services/background_service.dart` | 87 |
| `lib/core/widgets/scope_bar.dart` | 329 |
| `lib/exchanges/binance/binance_estimated_pnl.dart` | 27 |
| `lib/features/market/data/okx_ticker_model.dart` | 39 |
| `lib/features/orders/presentation/widgets/margin_account_card.dart` | 247 |
| `lib/features/portfolio/data/okx_balance_model.dart` | 107 |
| `test/core/network/ticker_polling_service_test.dart` | 902 |
| `test/core/services/background_service_retirement_test.dart` | 173 |
| `test/exchanges/binance/binance_estimated_pnl_test.dart` | 642 |
| `test/features/connections/account_state_test.dart` | 529 |
| `test/features/connections/scope_bar_test.dart` | 7 |
| `test/features/orders/presentation/orders_screen_position_layout_test.dart` | 74 |
| `test/features/portfolio/portfolio_scope_test.dart` | 1501 |

  Total ≈ 4,660 changed lines. All other 206 Dart files in `lib/` and `test/` are clean.
- OBS-302: The Codex sandbox cannot run Dart (T142 attempt af43dec9: "dart --version did not complete"). Hand-formatting ≈ 4,660 lines to the exact `dart format` output is error-prone and would need several host round trips.
- OBS-303: `dart format` is the SDK's deterministic formatter. Its changes are whitespace, line breaks and trailing commas only; it refuses to write a file it cannot parse.

## 3. Decision required — D-028 (who writes)

- **Option A (recommended): coordinator runs the formatter as a tool.** Claude runs `dart format <13 files>` on the host once, then audits. This is a task-specific coordinator override of "Claude does not write implementation code": Claude does not hand-edit any line; the SDK tool produces every change. Needs your explicit approval.
- Option B: Codex hand-formats (E1 Terra/low, 13 files). Not recommended: no formatter in the sandbox (OBS-302); expect multiple REWORK rounds on ≈ 4,660 lines.

D-029: after this plan, every task's buildability gate also requires `dart format --output=none --set-exit-if-changed lib test` to exit 0.

## 4. Planning Workstream Decomposition

- Workstreams: mobile code style (single). Fan-out Required: NO. Skip Reason: `SINGLE_MATERIAL_WORKSTREAM`. Sol not used.

## 5. Task Decomposition

| Task | Class | Route | Writer |
|---|---|---|---|
| T145 `tasks/task_145_format_debt.md` | E0 (no reasoning; tool output) | n/a under Option A — coordinator tool run; Terra/low E1 under Option B | Option A: coordinator (override) |

Single task: one deterministic command; splitting adds nothing.

## 6. Verification

| Step | Command | Expected |
|---|---|---|
| RED | `dart format --output=none --set-exit-if-changed lib test` | exit 1, 13 files listed |
| Apply (Option A) | `dart format <the 13 files>` | "Formatted 13 files (13 changed)" |
| GREEN | same as RED | exit 0, `Formatted 219 files (0 changed)` |
| Scope | `git diff --name-only` | exactly the 13 files |
| No semantic change | `git diff -w --ignore-blank-lines` reviewed: only line breaks / trailing commas; analyzer and tests below | — |
| Analyzer | `flutter analyze --no-pub` | `No issues found!` |
| V4 | `flutter test --no-pub` | 691/691 pass |
| Build | `flutter build web --no-pub` | built |

## 7. Risks

- RISK-301: Large diff hides an unintended change. Mitigation: only the formatter writes; scope check; analyzer + V4 + build.
- RISK-302: `git blame` noise on 13 files. Accepted; single commit `style: dart format …` so it can be added to `.git-blame-ignore-revs` later if wanted (not part of this plan).

## 8. External Configuration / Environment Actions

None. No `analysis_options.yaml`, no `pubspec.yaml`.

## 9. Rollout / Rollback

One commit on PASS (approved together with this plan). Revert = revert that commit.

## 10. Completion Gate

- [x] RED observed, GREEN exit 0
- [x] only the 13 files changed (token-equal ignoring whitespace/commas)
- [x] analyze `No issues found!`, V4 691/691, web build OK
- [x] committed

## 11. Change Log

- 2026-11-17: created.
- 2026-11-17: approved (Option A). COMPLETE.
