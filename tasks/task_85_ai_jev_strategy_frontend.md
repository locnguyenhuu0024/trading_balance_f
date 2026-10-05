# Task 85 — Automatic Strategy UI and Saved AI Review

Status: PASS
Agent Role: implementation_executor
Executor Class: E1
Target Model: gpt-6-luna
Target Effort: xhigh
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Dispatch Route Status: UNVERIFIABLE
Specification: docs/agents/specs/2026-10-05-ai-jev-auto-strategy.md
Plan: docs/agents/plans/2026-10-05-ai-jev-auto-strategy.md
Plan Steps: P02
Requirements/Acceptance: REQ-001,003–006 / AC-001,003–006
Predecessor: canonical API/JSON specification READY; T84 implementation is independent with disjoint write surfaces

Allowed writes: lib/features/strategy/** permitted Dart business source except configuration/settings files; test/features/strategy/** permitted Dart tests except settings/config files. No unrelated changes, manifests/config/generated runtime artifacts, telemetry/tasks, commits/push/deploy/live SDK calls.

Implement icon+visible title action Dựng chiến thuật tự động responsively. Select coin and H6/D1/W1, then call backend automatic-drafts using stable requestId on retry. Parse immutable persisted aiGeneration, open manual review, reopen from dashboard after closing. Use constructor initial candidate Draft input, avoid original auto-first-instrument regeneration; show all ranked supports/resistances with assessment status/quality/suitability/failure risk, no selections by default. Allow normal selection/direction/margin/leverage/split/allocation and existing preview/save using candidateDraftId, retaining same ID; then unchanged approval. Candidate cards have Review and no Apply or retry/replace bypass; legacy cards unchanged. Session changes/stale responses must not resurrect draft data. Separate optional API interface/capability avoids forcing new methods into existing StrategyApi fake implementations. Keep manual calculator/selection/order cap unchanged.

RED-085: disabled/failed enrichment retains all candidates and no preselection; stale session response ignored; candidate cannot Apply; more than ten selected still rejected. GREEN-085: action/selectors/backend review; saved reopen no regeneration; ranking displayed independent per side; explicit review inputs save same Draft through current preview then human confirmation. API payload/auth tests.

Formal focused RED before GREEN, followed by flutter test --no-pub test/features/strategy. dart format only changed allowed Dart files. Analyze strategy source. Buildability YES: flutter build web --no-pub --release after last executable change. No dependency resolution/config changes. Return exact evidence, safe limitations, telemetry envelope logical agent_run_id=E1-JEV-T85-001. Do not update task.

## Completion evidence

RED: the new mobile automatic-create action test failed before implementation because its key was absent. GREEN: final strategy directory passed 123 tests after the last source/test mutation; targeted API/session/reopen/empty/malformed/zero-price/materialization guards passed. Web release build succeeded. Targeted analyzer has one warning at an untouched provider catch variable and twelve infos; no new automatic-dialog/API diagnostics. Changed-path diff check passed. Independent R2-JEV-FE-AUDIT-001 adopted PASS. Final macOS release build succeeded. Full Flutter suite: 481 passed, four navigation/settings failures attributed to unchanged HEAD source/test mismatches by independent review; no clean HEAD runtime claim. No protected configuration changes or live external calls.
