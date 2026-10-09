# Task 103 — Preserve manual login when secure storage is unavailable

Status: PASS
Agent Role: implementation_executor
Executor Class: E1
Target Model: gpt-6-luna
Target Effort: xhigh
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Dispatch Route Status: UNVERIFIABLE
Dispatch: same original explicitly bound E1 gpt-6-luna/xhigh executor reused after T102 PASS; no parent/default substitution.
Specification: docs/agents/specs/2026-10-09-app-simplification-design.md
Plan: docs/agents/plans/2026-10-09-app-simplification.md
Finding: AUD-101-001
Requirements/Acceptance: REQ-002/003 / AC-002/003
Frontend Level: F1
Predecessor: T102 terminal and audited PASS (serialization only)

## Contract

Independent R2 audit found initial read+delete failure blocks manual auth despite specified failed-read fallback. Distinguish unavailable or pending storage (remembering unavailable, no explicit opt-out) from a deliberate checkbox opt-out after successful load. For failed/pending initial read, manually entered valid password/OTP must authenticate without save/delete; remember checkbox stays unavailable until a usable load and a late load must not overwrite user input/choice. State truthful saved-state unknown/unchanged message, never claim deletion. A successful read with unchecked login still deletes saved scope before auth; explicit checked-to-unchecked deletion failure still blocks button AND keyboard auth and retains truthful record state. Preserve all endpoint/session/stale cleanup/OTP/auth-error invariants.

Allowed: trade_account_controls.dart private login dialog/caller only; position_actions_test.dart additive/corrected failure expectations. No secure helper change unless exact compile consumer contract demands it; no other page/source/refactor, protected config/env/manifests/locks/dependencies, tasks/telemetry/Git mutation or subagents.

RED-004: combined initial read+delete unavailable store, valid manually typed credentials => one auth call, zero delete/save calls, remembering unavailable, no false deletion claim. Pending read must not delay manual auth or overwrite input after completion. Failed explicit opt-out remains blocked via Enter and button.
GREEN-004: normal checked successful auth still saves; reopened saved password masked and fresh empty OTP; healthy unchecked login removes saved password. Run exact failure negative filters before primary remember-success positive. V2 relevant auth group plus secure-store tests reused if unchanged; escalate only demonstrated missing evidence. Task buildability YES `flutter build web --no-pub` after final edit; known working elevated RTK Flutter path. Report exact commands/results/order/freshness and safe limitations. No external configuration action.

- [x] implement bounded remediation
- [x] formal RED then GREEN
- [x] affected evidence and fresh build
- [x] independent coordinator audit PASS

Audit: PASS. Coordinator and independent R2 source auditor confirmed pending/failed initial storage permits manual auth with no save/delete; typed credentials and post-submit choice resist late prefill. Healthy unchecked and explicit opt-out deletion/error behavior preserved. Initial RED-103 two failures observed, same filter then2/2; negative opt-out/read failure cases before remember-success positive passed. Endpoint, OTP and stale-session checks passed. Two-file formatter0 changes. Fresh RTK Flutter build web --no-pub exit0 after final edit. Same explicitly bound E1 Luna/xhigh reused, effective UNVERIFIABLE. No protected/external changes; final integration full tests/build remain separate.
