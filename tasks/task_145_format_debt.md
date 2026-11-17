# Task 145 — Apply `dart format` to the 13 unformatted files

Status: APPROVED
Approval: "Duyệt A, commit, làm" (user, chat, 2026-11-17, on this revision; Option A coordinator tool-run override for T145; includes commit on PASS)
Agent Role: coordinator (tool run, task-specific override — Option A of D-028); implementation_executor only if Option B is chosen
Executor Class: E0 (deterministic tool output)
Target Route: Option A — none (SDK formatter run by coordinator); Option B — gpt-6.1-terra / low (E1)
Routing Policy: EXECUTOR_ROUTING_POLICY.json v2 (OptCodex v1.4.0)
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Plan: `docs/agents/plans/2026-11-17-format-debt.md`
Plan Steps: §6
Decisions: D-028, D-029

## 1. Objective

Make `dart format --output=none --set-exit-if-changed lib test` exit 0 without semantic change.

## 2. Preconditions

Predecessors: T144 = PASS (`6f01085`). Clean checkout.

## 3. Allowed Scope

The 13 files in plan §2 OBS-301, and nothing else.

## 4. Forbidden Scope

Every other file; `analysis_options.yaml`; protected configuration; `backend/`; manual edits of any line (Option A: only the formatter writes); Git history.

## 5. Procedure (Option A)

1. RED: `dart format --output=none --set-exit-if-changed lib test` → exit 1, the 13 files.
2. Apply: `dart format` with the 13 explicit paths (not `lib test`, so no other file can change).
3. GREEN: step 1 command → exit 0.
4. `git diff --name-only` → exactly the 13 files.
5. Review `git diff -w --ignore-blank-lines`: only line-break and trailing-comma changes.
6. `flutter analyze --no-pub` → `No issues found!`; `flutter test --no-pub` → 691/691; `flutter build web --no-pub` → built.
7. Commit `style: dart format 13 files (T145)`.

## 6. Tests

No new test; V4 is the behavior check.

## 7. Task Buildability Gate

Required: YES
Command: `dart format --output=none --set-exit-if-changed lib test && flutter analyze --no-pub && flutter build web --no-pub`
Expected: exit 0, `No issues found!`, web built.

## 8. Stop Conditions

Stop if the formatter changes any file outside the 13, cannot parse a file, or if analyze/V4/build fail.

## 9. Execution Ledger

- Option A, coordinator tool run (work id `T145-format-run`): `dart format` on the 13 explicit paths → "Formatted 13 files (13 changed)". No manual edit. No Codex dispatch.

## 10. Coordinator Audit

Verdict: PASS (2026-11-17).

- RED: `dart format --output=none --set-exit-if-changed lib test` → exit 1, 219 files (13 changed).
- GREEN: same → exit 0, 219 files (0 changed).
- Scope: `git diff --name-only` = exactly the 13 files; 663 insertions, 256 deletions.
- No semantic change: for each of the 13 files, HEAD and new content are identical after removing whitespace and commas (13/13 token-equal).
- `flutter analyze --no-pub` → `No issues found!`; V4 691/691 pass; full gate `dart format … && flutter analyze --no-pub && flutter build web --no-pub` → built.
- D-029 in effect from here: every task's buildability gate includes the repo-wide format check.
