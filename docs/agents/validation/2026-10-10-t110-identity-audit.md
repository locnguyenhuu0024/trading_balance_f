# T110 identity/store audit — 2026-10-10

Status: PASS — independent source audit and operator-provided real-runtime evidence accepted.
Independent advisory route: auditor R3 / gpt-6.1-sol / high, explicitly dispatched; effective model/effort unavailable. Coordinator owns final verdict. Writer E2 / gpt-6-luna / max; explicit binding, no inheritance. Runtime has no child close/release primitive; final audit follow-up is planned for the same reviewer.

## Preliminary findings sent to executor

- AUD-110-01: Serialize enrollment/recovery transitions per user. Recheck persisted session authority inside mutations; require user status/generation CAS rowcount one. Concurrent enrollment must not overwrite accepted MFA/recovery material after session revocation, or commit stale mutations across recovery.
- AUD-110-02: Translate AES-GCM `InvalidTag` to the safe crypto error; real fabricated tamper/AAD tests remain required on the installed runtime.
- AUD-110-03: Atomically reserve auth attempts across processes before expensive verification; successful login must not clear shared source abuse history.
- AUD-110-04: Mode-compatible user status must participate in session validation; disabled users are denied independently of an accidental missing generation bump.
- Coordinator additional checks: insert the pending user before consuming the invite FK, rollback losing invite CAS; debounce/session and step-up generation/revocation/idle races; database-backed enrollment/step-up guessing limits; UTC response timestamps; v2-only bootstrap without singleton exchange credentials; v2 tokens cannot authorize legacy exchange routes.

These findings arose from an evolving source review and are remediation targets, not a final snapshot verdict. No tests were run by the preliminary reviewer against the in-flight writer.

## Required final evidence

Baseline-failing new-behavior regression; formal RED before GREEN; focused auth/store/legacy regression V3; final backend compileall after executable changes; source/diff review of every allowed changed path. Local injected test cipher/SQLite fixtures do not establish actual AES-GCM or PostgreSQL multi-process behavior. Runtime integration remains pending on operator-run Ubuntu 24.04 VPS verification.

## First final checkpoint

Coordinator reproduced formal RED replay/recovery tests (2 pass), then independent-users GREEN (1 pass). Coordinator broadened the previously sandbox-blocked V3 via a local-only escalated loopback invocation: `python3.12 -m unittest backend.tests.test_multiuser_auth backend.tests.test_multiuser_store backend.tests.test_trade_api -q`: 68 tests, OK, skipped=4, exit 0. Effective 64 executed passes; four crypto/PG checks remain pending. Independent final source verdict REWORK: AUD-110-07 per-GET CSRF rotation/write; AUD-110-08 PG race test rejects completion-first serialization. Bounded correction dispatched as T117, E1/gpt-6-luna/xhigh. Prior source fixes are verified in the independent advisory review.

## Final checkpoint after T117

AUD-110-07/08 corrected and independently reviewed: stable purpose-separated per-session CSRF, read-only authority revalidation and transaction-free concurrent restores within debounce; tagged PostgreSQL race accepts exactly either safe serialization and validates winning MFA/recovery material. R3 advisory source audit PASS, no remaining actionable findings. Auditor ran no tests.

Executor observed baseline failure before correction, then formal negative CSRF contract before positive activation/restore/enrollment (one passing test each). Final auth/store suite: 19 total, 15 passes/four skips; coordinator independently reproduced exit 0 and final `python3.12 -m compileall -q backend` exit 0. Prior unaffected legacy V3 evidence is reused. Four skips require actual AES-GCM and PostgreSQL runtime verification; the operator-run Ubuntu 24.04 commands are in `docs/agents/runbooks/2026-10-10-ubuntu-24-04-multiuser-setup.md`.

Coordinator verdict: source remediation accepted; full T110 BLOCKED_EXTERNAL_VERIFICATION, T111–T116 awaiting predecessor PASS. Requested child routes remained explicitly bound; effective routes UNVERIFIABLE. No protected content or configuration touched; no Mac install, VPS action or Git write. No child close/release primitive is available.

## Accepted external verification — 2026-10-10

User supplied Ubuntu VPS test output after commit e167220. Formal negative pair passed first (2 tests), then independent-user GREEN passed (1). Genuine AES-GCM owner-AAD/tamper and all three dedicated PostgreSQL process/connection tests passed (4 tests, no skips). Focused related auth/store/trade regression passed (69 tests, no skips). Exact commands match the Ubuntu runbook. Operator compileall returned without diagnostics; no explicit numeric exit code was supplied. The coordinator independently observed build exit 0 on the same unchanged executable source state.

Evidence provenance: user-provided terminal output; no agent VPS access, protected-input inspection or re-execution. The required runtime blocker is cleared. Coordinator verdict T110 PASS, T117 remediation accepted. T111 predecessor gate is now satisfied; its own verification remains required. These synthetic tests do not authorize or establish production deployment or exchange trading. Earlier blocked checkpoints above are historical.
