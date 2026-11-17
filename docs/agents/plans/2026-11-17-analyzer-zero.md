# Implementation Plan: Zero analyzer issues

Status: COMPLETE
Approval: "Duyệt, commit, làm" (user, chat, 2026-11-17, on this revision; includes commit on PASS)
Date: 2026-11-17
Tier: M
Plan ID: PLAN-20261117-analyzer-zero
Spec: `docs/agents/specs/2026-11-17-analyzer-zero-design.md`
Domain: mobile (Flutter)
Branch: `codex/multi-platform-view-only` (current branch)

## 1. Objective

`flutter analyze --no-pub` → `No issues found!` (155 → 0) by fixing code, with no behavior change (REQ-201..206, D-026, D-027).

## 2. Preconditions

- Clean checkout at `a78ef9c` (motion polish COMPLETE).
- OptCodex personal 1.4.0 lock verified by the dispatcher on every run (2026-11-17).

## 3. Repository Impact

| Task | Files | Issues |
|---|---|---|
| T142 mechanical `lib/` | 21 `lib/` files (list in task) | 60 |
| T143 behavior-sensitive | `binance_adapter.dart`, `binance_trade_history.dart`, `order_cancellation_flow_provider.dart`, `strategy_wizard_dialog.dart`, `test/features/strategy/strategy_wizard_dialog_test.dart` | 24 |
| T144 tests | 23 `test/` files (list in task) | 71 |

60 + 24 + 71 = 155. Each file belongs to exactly one task.

## 4. External Configuration / Environment Actions

None. No `pubspec.yaml`, no `analysis_options.yaml`, no dependency change.

## Planning Workstream Decomposition

- Workstreams: mobile code quality (material). Backend: none.
- Fan-out Required: NO. Skip Reason: `SINGLE_MATERIAL_WORKSTREAM`.
- Sol planning advisor: not used — no data-sharing authorization for this plan; coordinator planned directly from the host analyzer output.

## 5. Dependency Graph

```
T142 (lib mechanical) ──► T143 (behavior-sensitive lib + its test) ──► T144 (tests, final zero gate)
```
Serial: one writer per checkout. File sets are disjoint; order puts the riskiest change in the middle so T144 closes the gate.

## 6. Ordered Implementation Steps

### P01 — T142 mechanical `lib/` cleanup
Braces, `const`, unnecessary/unused imports, `@override`, function declarations, `toList` in spread, unused `catch` variable, `withOpacity` → `withValues(alpha:)`.

### P02 — T143 behavior-sensitive cleanup
Public getter on `BinanceCostController`; analyzer-visible `mounted` check and `!` removal in the cancellation flow; `DropdownButtonFormField.initialValue`; `RadioGroup` for the wizard entry radio (+ test accessor update); remaining mechanical issues in those files.

### P03 — T144 test cleanup and final gate
All test-file issues incl. `Color.r/g/b` and `SemanticsData.flagsCollection`. Gate: whole-repo `No issues found!`.

## 7. Test and Verification Plan

| Level | Command |
|---|---|
| RED (each task) | `flutter analyze --no-pub <task files>` reports the task's issue count |
| GREEN (each task) | same command: `No issues found!`; then V4 `flutter test --no-pub` all pass |
| Buildability | `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings && flutter build web --no-pub`; 0 errors and total count ≤ 95 after T142, ≤ 71 after T143, 0 after T144 |
| Format | `dart format --set-exit-if-changed <touched files>` |
| Suppression check | `git diff <base>..HEAD` contains no added `ignore:` and no `analysis_options.yaml` |

The executor sandbox cannot run Flutter; the coordinator runs RED, GREEN and the build on the host.

## 8. Migration / Data Plan
N/A.

## 9. Performance Verification
N/A (no runtime path change beyond `const` canonicalization).

## 10. Risks
- RISK-201: `DropdownButtonFormField.initialValue` might not follow later state changes. Mitigation: EDGE-201; wizard tests in V4.
- RISK-202: `RadioGroup` migration changes the semantics tree or disabled behavior. Mitigation: EDGE-202; wizard tests; `enabled:` preserved.
- RISK-203: adding `const` or braces changes nothing at runtime, but a wrong `const` on a widget holding mutable state would; analyzer only suggests `const` where valid.
- RISK-204: Flutter SDK upgrade later may add new deprecations; out of scope (D-027 makes them visible immediately).

## 11. Rollout / Rollback
One commit per task on PASS, after approval. Revert per task.

## 12. Decision/Assumption Dependency Registry
D-026 → P01, P02, P03; D-027 → P03 and all later plans.

## 13. Task Decomposition

| Task | Steps | Class | Route |
|---|---|---|---|
| T142 `tasks/task_142_analyzer_lib_mechanical.md` | P01 | E2 | gpt-6.1-terra / medium |
| T143 `tasks/task_143_analyzer_behavior_sensitive.md` | P02 | E3 | gpt-6.1-terra / high |
| T144 `tasks/task_144_analyzer_tests_zero.md` | P03 | E2 | gpt-6.1-terra / medium |

3 tasks (Tier M target 1–3). Split reason: mechanical vs. API-migration risk, and `lib` vs `test` verification.

### Task Buildability Plan
Each task ends with analyze (0 errors, count reduced by its share) and `flutter build web --no-pub`. No cross-task compile coupling (T143 adds a getter used only inside its own files).

## 14. Completion Gate
- [x] T142, T143, T144 PASS (`52f60bd`, `fe1b124`, final commit of T144)
- [x] `flutter analyze --no-pub` → `No issues found!`
- [x] V4 + web build green (691/691)
- [x] no `ignore:` added, `analysis_options.yaml` untouched
- [x] no protected file read or changed

## 15. Change Log
- 2026-11-17: created.
- 2026-11-17: approved by user.
- 2026-11-17: COMPLETE. 155 → 0. T142 4 attempts, T143 2, T144 2. From now on the buildability gate is strict: `flutter analyze --no-pub` must print `No issues found!` (D-027). Repo-wide `dart format` debt (13 pre-existing files) is not an analyzer issue and is out of scope.
