# Jev Best Five per Side

Status: COMPLETE
Workflow: WF-20261005-JEV-BEST-006
Authorization: User explicitly authorized autonomous decisions and execution; existing session commit/push authorization applies.

## Canonical contract

This supersedes the no-recommendation/no-preselection requirements of the initial Jev specification. Keep generation, exact calculator, candidate identities, immutable provenance, provider budget, session/account guards and execution boundaries unchanged.

Select at most five LONG supports and five SHORT resistances independently, never transferring quotas or filling with ineligible candidates. Eligible means positive exact price and a successful valid assessment with structuralQuality >= 4, entrySuitabilityProbability >= 0.6 and failureRiskProbability <= 0.4. These are explicit initial screening thresholds on model scores, not calibrated probabilities or a profitability claim. Use existing per-side ranking: suitability descending, quality descending, risk ascending, generation order ascending. Preserve all candidates, including unselected and failed ones.

Add immutable aiGeneration.recommendation with version `ai-jev-selection-v1`, maxPerSide:5, minStructuralQuality:4, minEntrySuitabilityProbability:0.6, maxFailureRiskProbability:0.4, longLevelIds and shortLevelIds ordered by saved rank. Existing endpoint inputs stay unchanged. Replay returns saved recommendations without reevaluation. Old snapshots lacking metadata start unselected. Preserve metadata through same-row materialization.

Generation automatically saves the candidate-stage Draft, refreshes the list and shows counts without opening review. Empty recommendations still save a reviewable Draft, explaining that no levels met the filter. Reopening seeds exact recommended IDs only, derives actual Long/Short/Both direction, and chooses the nearest selected entry on each selected side. Empty selection displays Both. Malformed recommendations must atomically select nothing and remain manually reviewable with a safe notice. Validate supported version, list types, unique known IDs, correct side, <=5 per side, positive prices and successful assessments. Do not recompute model thresholds or rankings on the client. Manual review may edit choices under the existing ten-total limit; five-per-side applies to automatic recommendation only.

No sizing, leverage changes, preparation, reservations, exchange submissions or execution occurs during generation. Margin remains user input. Candidate-stage Apply/Retry/Replace remains blocked. No configuration/dependency/container files may be read or modified; all tests offline.

## Planning workstream gate

Backend selection/persistence and frontend deferred-review/preselection are material independent workstreams. Fan-out Required: YES. Required/Actual reasoning agents: 2/2. Fan-out Compliance: PASS. Skip reason: null.
R2-JEV-BEST-BE-PLAN-001 and R2-JEV-BEST-FE-PLAN-001: reasoning, R2, gpt-6.1-sol/medium, explicit existing bound routes, parent inheritance FORBIDDEN, effective routes unavailable/UNVERIFIABLE; completed/adopted. Coordinator reconciled shared schema and selected stricter 4/0.6/0.4 policy instead of provisional 3/0.5/0.5. No direction selector or new request field required. Coordinator route is runtime-fixed; no fabricated effective route. Runtime lacks child close/release; collected terminal children retained by runtime, no cleanup primitive fabricated.

## Bounded execution

T90 backend: implementation_executor E1 gpt-6-luna/xhigh EXPLICIT, parent inheritance FORBIDDEN. Allowed writes only backend/strategy_automatic.py, backend/tests/test_strategy_automatic.py, docs/development/ai-jev-strategy.md. Add deterministic recommendation construction and document policy, deferred review, empty/provider-failure behavior. Meaningful RED before source change, then GREEN: 8+8 ->5+5, 0+8 ->0+5, 2+8 ->2+5, all weak/failed/disabled ->0, threshold boundaries, invalid scores/nonpositive prices, ties, preserved candidates, replay and materialization provenance, no OKX writes. Do not alter calculator/provider/settings.

T91 frontend: implementation_executor E1 gpt-6-luna/xhigh EXPLICIT, parent inheritance FORBIDDEN. Allowed writes only lib/features/strategy/presentation/strategy_screen.dart, strategy_automatic_draft_dialog.dart and strategy_wizard_dialog.dart in the same directory; test/features/strategy/strategy_screen_test.dart and strategy_wizard_dialog_test.dart. Implement canonical UI contract. RED before source edits; GREEN deferred review/reopen with exact IDs and nearest selected entries, 5+5 and one/empty-side counts, old/malformed metadata fallback, session guards, same-ID materialization. No API contract changes or configuration edits.

Coordinator audits explicit allowlisted diffs, gathers independent R2 reviews, runs appropriate final full backend/Flutter verification and release web build after final changes, then commits and pushes existing feature branch. Live SDK/VPS deployment remains external user-owned verification; no deployment authorized here.

## Completion evidence

T90 PASS: E1-JEV-BEST-T90-001 explicitly dispatched gpt-6-luna/xhigh, effective route unavailable/UNVERIFIABLE. Formal recommendation RED before implementation; focused 27 tests pass. T91 PASS: E1-JEV-BEST-T91-001 reused the explicitly bound E1 gpt-6-luna/xhigh executor, effective route unavailable/UNVERIFIABLE. Formal RED exposed absent preselection and immediate review; focused GREEN and full strategy directory 126 tests pass. Targeted presentation analysis has 11 existing informational diagnostics and no warnings/errors. Final copy correction has focused GREEN. No source/test mutations after executor terminal checkpoint.

R2-JEV-BEST-BE-AUDIT-001 and R2-JEV-BEST-FE-AUDIT-001: independent read-only PASS, adopted. Frontend auditor noted stale automatic-dialog copy, corrected by executor and checked in final coordinator diff. Coordinator explicit allowlisted diff/check PASS. Final full backend 256 tests pass in 40.778 seconds; full Flutter 488 tests pass; Python compileall and web release build pass after final changes. Existing web Wasm compatibility/font notices are nonfatal; no configuration changes were made. Calculator/provider and manual execution contract unchanged.

No live Jev/OKX or VPS deployment was performed. The optional SDK and backend process settings remain user-owned prerequisites documented in docs/development/ai-jev-strategy.md; disabled/unavailable scoring saves an empty recommendation without synthetic fill. Deployment needs both updated backend and frontend build. Existing authorized Git integration uses feat/ai-jev-auto-strategy.
