# Jev Backend Setup Guide Expansion

Status: COMPLETE
Workflow: WF-20261005-JEV-DOC-003
Authorization: User requested setup guidance and immediate execution after planning. Existing session authorization permits commit/push on completion.
Scope: Expand docs/development/ai-jev-strategy.md only; no provider activation, installation, secret access or protected configuration changes.

One material documentation workstream; fan-out not required. Required/actual reasoning agents: 0/0; Fan-out Compliance: EXCEPTION; Skip Reason: SINGLE_MATERIAL_WORKSTREAM. Coordinator resolves all runtime semantics from backend/strategy_jev.py and strategy_automatic.py and official SDK documentation. E0 implementation_executor, gpt-6-luna/high, EXPLICIT; parent inheritance forbidden; effective route unexposed is UNVERIFIABLE.

## Task 87

Status: PASS
Allowed Writes: docs/development/ai-jev-strategy.md only. Write English repository documentation; user summary in Vietnamese.

Add requirements, backend-interpreter installation command pinned to integration contract typesafe-sdk==0.7.2, metadata/import check without a provider call; five exact environment settings with defaults/ranges; API key acquisition official console link; safe local zsh hidden-input example, no secrets in files/history/output; restart existing backend launcher with inherited variables and pre-existing runtime settings, no invented launch/deployment command. Explain host environment versus container/service process environment; existing environment files are not automatically consumed by this adapter and exact deployment configuration stays user-owned.

Describe manual validation through Strategy action, explicit coin/timeframe, new Draft and per-candidate success/disabled/failed status, quality0..5 and probabilities0..1, saved modelRequested/modelUsed/evaluatedAt/errorCode/contextHash, supports/resistances paths. Existing Drafts are immutable; settings changes require a new generation request. Empty candidate lists do not verify SDK. Explain endpoint requestId idempotency, timeout3s clamped0.05..10, concurrency4 clamped1..8,12s admission/acceptance budget and drain cleanup, no retries/auto orders. Troubleshooting uses exact fixed codes disabled/key_missing/sdk_unavailable/settings_invalid/provider_unavailable/provider_error/timeout/deadline_exceeded/invalid_model/invalid_response; provider_error does not prove a specific HTTP status. Include offline test command and rollback JEV_ENABLED=false. Official source links https://docs.typesafe.ai/sdk/python and /sdk/python/api/clients/sync verified by coordinator. No full config recipes, debug-body logging or live connectivity commands executed.

Verification: source/document contract audit and markdown diff check; no test/build rerun for docs-only changes. Terminal result: changed path, safe verification, no further writes, telemetry logical run E0-JEV-DOC-T87-001. Coordinator owns plan/status/telemetry and authorized Git integration.

## Audit outcome

PASS after bounded documentation correction: offline command uses the repository stdlib unittest module, hidden zsh input preserves raw key characters, and UI status is distinguished from exact saved assessment JSON paths. Reviewed against business adapter source and official SDK references; markdown diff check passed. No runtime/source/test/configuration change, package installation, secret access or live provider call occurred. Existing successful code/test/build evidence remains valid; documentation-only work does not require rebuilding. Executor terminal reports collected; runtime lacks child release primitive. Documentation will be committed/pushed using the existing explicit session authorization.
