# Task 97 — Deterministic verification fixture compatibility

Status: PASS
Agent Role: implementation_executor
Executor Class: E0
Target Model: gpt-6-luna
Target Effort: high
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Predecessors: T93,T94,T96 PASS for backend fixture work; T95 terminal before Flutter checks/build
Findings: AUD-INT-1, AUD-INT-2, AUD-INT-3, AUD-INT-4, AUD-INT-5
Scope: final verification harness only; no runtime/product behavior change

## Evidence and bounded contract

The unchanged Settings navigation fixture intentionally returns an unresolved getOkxApiKey future to avoid native secure-storage reads. The test calls pumpAndSettle after opening the access page, whose progress animation remains active while that future is pending. Isolated baseline reproduced timeout at line127. The VND provider is overridden, so no external currency request is involved. This is a deterministic verification-harness mismatch, not a credential/runtime requirement change.

Allowed writes ONLY test/features/settings/settings_navigation_preferences_test.dart; backend/tests/test_order_cancellation.py; backend/tests/test_strategy_scope.py; backend/tests/test_strategy_diagnostics.py; test/core/navigation/main_navigation_shell_test.dart; test/features/strategy/strategy_retry_dialog_test.dart; test/features/strategy/strategy_wizard_dialog_test.dart.

Final aggregate extension AUD-INT-4/5: Flutter full run exited1 with553 passes and3 failures. Navigation fixture fakes every data source except Risk, so navigating Risk instantiates the production backend factory without a configured HTTPS URL. Inject an in-memory Risk owner/bridge as an explicit offline navigation fixture, preserving every navigation/assertion and deterministic cleanup. Do not modify production providers/transport, supply operational URL/configuration, or weaken HTTPS/session guards. Two Strategy dialog fixtures still construct StrategyMarketRepository with Dio although the approved consumer now accepts BackendDataClient; mechanically adapt their fake constructors/imports with the same offline BackendDataClient seam used in the accepted Strategy screen test. Preserve fake method overrides, financial/dialog/action/no-replay assertions and no external requests.

Run the three affected test files after edits. Formal negative boundary assertions must precede independent GREEN navigation/dialog success selectors; exact names selected from existing tests. Run native-only Flutter commands, then webbuild after final edits. Coordinator reruns final aggregate because these required fixture edits invalidate the earlier full run.

Settings: cover two distinct states. Preserve the intentional pending read in a separate negative navigation/loading test with explicit bounded route-transition pumping; loading remains visible and credential editor fields remain absent. Preserve every original content assertion in the GREEN ready-state navigation test: explicitly fake successful null results for all three credential reads (no platform access), then tap the existing manual-entry toggle before asserting API Key/Secret Key/Passphrase and private trade controls. Source evidence establishes that editor fields are absent while loading and hidden until manual mode is selected. Do not weaken timeouts, skip assertions/tests, complete the pending negative merely to hide loading, modify credential UI/settings/product source, or touch configuration/manifests.

Backend final discovery `python3.12 -m unittest discover -s backend/tests -t . -q` failed:329 tests,147.111s,17 errors and1 assertion failure. Errors are Windows SQLite cleanup handles from unchanged direct fixture connections in order_cancellation (lines79,552) and strategy_scope (line214). Apply the already-proven contextlib.closing plus connection transaction context to these three sites, preserving commit/rollback behavior and all cancellation/migration assertions. Do not modify application store/transaction/migration/cancellation source.

Diagnostics compatibility: test_strategy_diagnostics.py Response fake at line370 lacks HTTPResponse.getheader, newly needed for sanitized Retry-After metadata. The 503 category test therefore sees generic transport_failure instead of http_rejected503. Add a minimal getheader stub returningNone, preserving all expected category/content-free/no-replay assertions. No production transport/logger changes.

This test-only fixture correction is necessary for the approved final full-suite verification; no additional product scope is authorized. Coordinator owns this contract. Executor must not alter it, Git, canonical docs, telemetry or spawn children. Read only explicitly selected non-protected source/test evidence; no operational configuration content or external service.

## Verification

Reuse observed failing baselines; no need to repeat unchanged10-minute-settle behavior. Backend formal RED negative first: rollback/cancel ambiguous outcome assertions unchanged and resourcesclose; then GREEN diagnostics categories/cancellation verifiedsuccess. Run entire three affected backend test modules, compileall after final backend edit. Final backend discovery will be rerun by coordinator due these required changes.

Settings formal RED negative: pending credential read leaves loading active and never pretends credentials completed, yet navigation is rendered. GREEN: ready-state access-page navigation/content and visible-page control work with all platform reads faked. Run exact named tests in that order, then entire Settings navigation test file. Record exact commands/exits/counts. Do not run Flutter tests/format/build while T95 owns that runtime; prepare source correction and wait for coordinator release. Buildability YES: backend compileall and Flutter web --no-pub after final edits. Final integration still runs fresh aggregate build/tests. Use authorized native routes for known sandbox stalls. Return no external configuration action, safe telemetry and changed paths; coordinator audits status.
