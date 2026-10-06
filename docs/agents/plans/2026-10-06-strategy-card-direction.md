# Small Change Plan: Strategy Card Direction Labels
Status: COMPLETE
Date: 2026-10-06
Tier: S

## Objective and evidence
Show each strategy card's persisted direction: Long, Short, or Long + Short. strategy_screen.dart _StrategyCard currently shows coin/status without direction. Backend _basic_result exposes sides; candidate drafts omit executable sides and contain immutable recommendations. Frontend preserves individual strategy IDs.
Allowed: lib/features/strategy/presentation/strategy_screen.dart, test/features/strategy/strategy_screen_test.dart. No backend/API/config/dependency/generation changes. Current branch fix/independent-long-short-strategies retained. Existing six unrelated telemetry lines stay untouched. No commit/push authorization assumed for this follow-up.

## Planning workstreams and authorization
Frontend card display is the single material workstream; backend only supplies the already-established sides contract (non-material). Independent fan-out required NO; actual planning reasoning agents 0; Fan-out Compliance EXCEPTION; skip SINGLE_MATERIAL_WORKSTREAM. Coordinator C1 preferred, current runtime retained. User requests this as continuation of Long/Short distinction and prior explicit instruction to implement immediately after planning remains applicable. Plan presented before execution, no new product ambiguity.

## P01 / T87
1. Add a small display-only label resolver. Valid nonempty sides list is authoritative (long/short exact values, deduplicate), map long->Long, short->Short, both->Long + Short. Malformed/nonempty unknown values -> Chưa rõ chiều. If sides absent/null on older ordinary records, derive union from nonempty order rows only if every row has a valid long/short side; otherwise Chưa rõ chiều. Never infer direction from buy/sell, status or coin.
2. Candidate drafts use already validated StrategyDraftEntries: any long/short recommendations -> Đề xuất: Long / Đề xuất: Short / Đề xuất: Long + Short; no recommendations -> Chưa chọn chiều. Recommendations remain editable proposal semantics; no default selection added.
3. Put direction Chip alongside existing status Chip in a Wrap with spacing/runSpacing, stable key strategy-direction-<id>. Keep card/header/actions/metrics/status colors and semantics intact; show label in accessibility description when useful.
4. Widget coverage for Long/Short/Both distinct cards, unknown/malformed and legacy-order fallback, candidate draft semantics, and 320px viewport with enlarged text without overflow. Extend existing fake API fixtures narrowly; do not weaken existing expectations.

RED: Missing/malformed side evidence renders Chưa rõ chiều and candidate without recommendations Chưa chọn chiều, no incorrect Long/Short default. Observe a new main-display regression failing on baseline if practical.
GREEN: Three persisted side combinations display correct per-card label; mobile layout and existing card actions/status remain intact. Formal RED negative test before GREEN positive test in final state; exact commands/results in report. Focused strategy_screen_test.dart then affected strategy group only if necessary (V2 default).
Task Buildability Gate YES: affected Flutter app; flutter build web --no-pub --release after final executable edits. Final canonical repository build gates: python3.12 -m compileall -q backend, flutter build web --no-pub --release, flutter build macos --no-pub --release. Same documented commands as previous audit; opaque manifest consumption only. No release_build.sh/deployment. No full backend regression needed for this display-only change.
External configuration/environment actions none. Live-service calls not authorized/required. DAG approved contract -> T87(E0) -> audit/final builds. One executor task; no overlapping writers.

## Completion
T87 PASS. 25 screen widget tests and final Python/web/macOS builds pass. Exact diff/audit confirms source scope and meaningful negative/positive display evidence. No protected configuration mutation; no commit/push/deploy for this follow-up.
