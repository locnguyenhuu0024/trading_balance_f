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

Task 87 PASS after bounded documentation correction: offline command uses the repository stdlib unittest module, hidden zsh input preserves raw key characters, and UI status is distinguished from exact saved assessment JSON paths. Reviewed against business adapter source and official SDK references; markdown diff check passed. No runtime/source/test/configuration change, package installation, secret access or live provider call occurred. Existing successful code/test/build evidence remains valid; documentation-only work does not require rebuilding. Executor terminal reports collected; runtime lacks child release primitive. Documentation was committed/pushed as eae0b4f under explicit session authorization.

## Docker follow-up task 88

Status: PASS
Workflow: WF-20261005-JEV-DOCKER-DOC-004
Authorization: User explicitly requested adding Docker instructions, then committing and pushing.
Workstream: Single material documentation workstream; Fan-out Required NO; required/actual reasoning agents 0/0; compliance EXCEPTION; skip SINGLE_MATERIAL_WORKSTREAM.
Executor: implementation_executor E0, gpt-6-luna/high, existing explicitly bound route reused; parent inheritance forbidden; effective route unavailable/UNVERIFIABLE. Logical run E0-JEV-DOCKER-DOC-T88-001.
Allowed Writes: docs/development/ai-jev-strategy.md only. No runtime/configuration changes, installations, Docker execution, secret access or external calls.

Append concrete English Docker guidance from the existing deployment guide: user-owned backend/Dockerfile SDK RUN instruction before USER; user edits /etc/trading-balance/trade-api.env with five exact settings preserving existing entries; build trading-balance-trade-api image; recreate container using documented API-only procedure preserving SQLite mount, read-only/hardening/env-file/loopback port, or coordinated API+worker procedure when worker deployed. Do not suggest restart loads new image/env-file or install into running read-only container. Include Python metadata/import check inside API container and manual new-Draft success verification. Link existing docs/deployment/position-trade-api.md with correct relative link and Docker official reference. Update general restart/rollback wording to distinguish Docker environment changes requiring recreation. No need duplicate full multi-service deployment recipes. Audit explicit doc diff and markdown consistency; tests/builds not invalidated by docs-only changes. Coordinator owns statuses/telemetry/authorized commit and push.

Task 88 audit PASS: concrete image installation, user-owned five-setting environment change, recreate semantics, persistent/hardened deployment references and offline container import check verified. Relative deployment links/anchors match existing headings. Corrected env-file terminology (option, not mount). Guide diff check passes. No Docker commands, configuration inspection/mutation, installation or live provider calls performed; docs-only scope preserves prior test/build evidence. User explicitly authorized committing/pushing this update.
