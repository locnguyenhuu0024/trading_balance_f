# Jev Automatic Strategy Integration Audit

Branch: feat/ai-jev-auto-strategy
Workflow: WF-20261005-JEV-001
Status: PASS_WITH_EXTERNAL_ACTIVATION_PENDING

## Delivered behavior and architecture

The Strategy page has an icon and visible Vietnamese title for automatic generation. Users explicitly choose a USDT SWAP instrument and H6/D1/W1. The authenticated backend generates every candidate with the existing Strategy algorithm, evaluates each through the optional official SDK, ranks support and resistance independently, and saves an immutable candidate-stage Draft. Closing and reopening consumes that saved snapshot without regeneration or preselection.

Review retains the existing manual selection, direction, margin, leverage, allocation, preview and frozen confirmation steps. `candidateDraftId` materializes the same record while retaining all AI provenance. Candidate-stage records cannot prepare, execute, retry or replace orders. Provider errors never remove candidates. Jev receives public market context only; account/session data and exchange credentials stay outside the adapter.

Backend boundaries: `strategy_levels.py` exact-decimal algorithm; `strategy_jev.py` optional SDK adapter; `strategy_automatic.py` orchestration/persistence; existing strategy lifecycle and narrow service dispatch/session wiring. Frontend boundaries: optional API capability, automatic selectors, saved review wizard and dashboard guards. No dependency/environment/deployment file changes, database migration, commit, push or deployment.

## Verification evidence

- Backend initial RED: five automatic API tests failed with missing route before implementation. Twenty final new tests cover data validation, SDK calls/cleanup/errors, retention/ranking, persistence, identity/materialization, account/session changes, deletion and deadline behavior. Audit remediation checks were added after fixes and are not represented as pre-fix RED.
- Final full backend discovery passed 249 tests in 40.689 seconds, with fake localhost server access authorized. The preceding run's retry snapshot regression was fixed by attaching the candidate guard to the existing account context; the final run supersedes that failed evidence.
- Independent actual Dart/Python calculator comparison passed 45 seeded fixtures over H6/D1/W1, 5–520 inputs and several tick sizes. Final calculator SHA-256 remains `13d5fcab832485e76b447857bb5f75658aa6886d93dfe0f7f5f70db5e3e3dcfa`; evidence was not invalidated.
- Frontend RED: new mobile button key absent before implementation. Final Strategy tests: 123 passed, including session cancellation, authenticated payload, saved reopen, no regeneration/default selection, empty snapshot, malformed assessment, equal/zero prices and same-record save.
- Full Flutter suite: 481 passed, four navigation/settings failures. Independent review attributes them to unchanged HEAD source/test mismatches (six/seven destinations expected versus eight canonical destinations; width clamp; lazily built Settings row). This is source-based attribution, not a clean HEAD test run.
- Follow-up WF-20261005-NAV-002: user authorized repairing those four tests. Both affected files reproduced RED, then passed 16 focused tests; full Flutter suite now passes all 485 tests. Targeted analysis is clean, final web/macOS builds pass. This supersedes the earlier four-failure result; production navigation behavior remains unchanged.
- Web release and macOS release builds succeeded after final frontend changes. Backend compileall succeeded after executable changes. Targeted Dart analyzer: one warning in an untouched provider catch variable and twelve infos; no diagnostics in the new automatic dialog/API. Python lint/type tools were unavailable locally.
- Changed permitted source/test/doc diff checks passed. Protected mixed `service.py` was inspected only at its explicitly identified dispatch business section for final review; no whole-file content diff.

## Audit findings and resolution

Independent backend audit initially required four fixes: session revocation during enrichment, stale candidate response after concurrent materialization, advertised but rejected candidate deletion, and late provider success. Executor added session revalidation before persistence/response, stage-aware replay, narrow transactional safe deletion, and late-result downgrade. Independent bounded re-audit passed all four. Independent frontend audit passed without remediation.

The coordinator owns planning/audit/documents; explicitly routed E2 Luna/max and E1 Luna/xhigh executors own backend/frontend code. Two independent R2 Sol/medium planning workstreams satisfied the mandatory gate. Effective child routes are unexposed and recorded UNVERIFIABLE. The runtime provides no child close/release primitive.

One coordinator search over mixed `service.py` accidentally included a protected configuration region. The diagnostic branch stopped; that content was neither used nor propagated. No protected file mutation occurred. The workflow therefore does not claim zero protected-content exposure.

## External activation and practical limits

Live Jev verification remains pending user-owned SDK installation and process environment setup in [the developer guide](../../development/ai-jev-strategy.md). The local Python environment did not have the optional SDK installed. All verification used mocked provider/exchange transports; no live Jev or OKX mutation was performed.

The 12-second AI budget bounds admission/acceptance; outstanding calls drain and clients close before return, so SDK timeout/cleanup scheduling may extend wall-clock duration. Missing evidence stays nullable; scoring is advisory and has no calibration/backtesting guarantee. Disabling Jev keeps saved/manual review available.
