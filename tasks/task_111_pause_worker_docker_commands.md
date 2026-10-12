# Task 111 — Align Docker lifecycle commands with worker pause

Status: PASS (source audit; runtime unverified)
Agent Role: implementation_executor
Executor Class: E1
Target Model: gpt-6-luna
Target Effort: xhigh
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN

## Plan and authorization

The user explicitly requested updating `docker_manage.sh` after the worker-pause implementation. This specific authorization permits reading/editing this deployment script; it does not permit access to other protected files. Existing commit/push authorization applies to this continuation. Work on `codex/pause-strategy-worker`.

## Contract

- Allowed write surface: `docker_manage.sh` only.
- Lifecycle start/restart/rebuild must stop an existing running worker and start/restart/recreate only the API. Stop handles worker then API. No path may create/start/restart a worker.
- Retain `--api-only` as a compatibility alias; it must accept an existing stopped/running worker and enforce the pause.
- Do not require worker env files or remove the old worker container. Keep status/log access for diagnosing retained worker state. Preserve API hardening, mount, port, image, API path checks and actionable failures.
- Update help text for paused-worker behavior and compatibility flag. Remove unreachable worker startup/guard code.
- A failed image build must leave API untouched; worker suspension is intentional and may already have happened. Abort before API mutation if worker stop fails.
- Do not inspect other protected files or run real Docker operations. Do not add/run tests (current developer constraint); coordinator performs source/diff review and reports unexecuted runtime verification.
- Do not commit/push or modify task/telemetry documents.

## Audit

Independent coordinator source audit PASS: only the named authorized script changed; no worker create/start/restart/remove path remains; start/restart/rebuild/stop stop running worker before API mutation; failed build preserves API; worker env not required; existing API hardening and persistence unchanged; status/logs retained. Runtime verification and shell validation were not requested and not performed. No real Docker operation occurred. Requested executor route remains explicitly bound Luna/xhigh; effective runtime route unavailable. Commit/push is the authorized integration step, with outcome reported to the user.
