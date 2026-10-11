# T111 ownership/vault/command audit — 2026-10-10

Status: PASS — final independent source audit and operator real AES/PostgreSQL verification accepted.

## Accepted final operator evidence — 2026-10-11

Latest operator affected strategy_scope/strategy_worker command reports48 tests OK with no skipped summary; final compileall explicit exit0. Reviewed revision includes T118/T119 test-only corrections; the real PG API-versus-worker exact claim and persisted-state assertions now pass. This resolves AUD33/34 and the last outstanding runtime gate.

Evidence reuse: the earlier307-test runtime regression had only this PG test failing, with no skip summary. Other required AES, PG migration/command/T110 cases passed in that run and their executable source did not change during fixture/assertion corrections. Reuse those successful unaffected results plus the final48-test affected run. No fictitious full309-test successful run is asserted. Independent source audit, formal ordered local safety/success, relevant runtime and final build gates are satisfied. Coordinator final verdict T111 PASS; T118/T119 PASS; T112 predecessor ready. Synthetic/runtime PASS does not establish exchange demo/live integration or authorize production activation/deployment.

## Second operator rerun — T119 / AUD-111-34

Operator affected48-test run still fails one test, now at its persisted lease assertion: tuple(lease) gives column names rather than values. compileall explicitly exit0. The preceding exact API connection_busy/worker claimed fence5 assertion now passes, confirming T118 fixed admission to the actual race.

PostgresIdentityStore configures psycopg dict_row: iterating that mapping yields keys. SQLite-only row fixtures iterate values. Both tuple(lease) and tuple(worker_strategy) in the PG race test must use explicit named-column values; production row adapters must remain unchanged. Coordinator checked analogous tuples in other T111 PG suites: migration uses raw psycopg default tuple rows, so those expressions are valid. T119 E0/gpt-6-luna/high explicitly dispatched, no inheritance/effective route unavailable, only these two assertions plus necessary focused evidence. Existing tests must still reject wrong owner/fence/state and retain exact expected values. No real PostgreSQL assertion PASS is claimed until operator rerun.

AUD34 source correction PASS: executor changed only the two persisted-state actual expressions to named column access, retaining exact expected tuples. Actual AST-extracted assertions fail on correct mappings before fix; after fix accept mapping/SQLite representations and reject six wrong individual values. Coordinator independently inspected the complete diff and ran actual assertions in formal negative6-before-positive2 representation order, exit0. Fresh final backend compileall exit0 and diff whitespace exit0. No unrelated tests repeated. T119/T111 remain BLOCKED only on operator PG persisted-state rerun. Commit/push under existing user authorization; source-only harness never claimed as PostgreSQL evidence.

## Operator runtime result and T118 remediation — 2026-10-11

Operator reported307-test regression FAILED with one failure in PostgresOwnedStrategyIntegrationTests.test_pg_owner_api_claim_and_worker_claim_share_connection_fence: API returned invalid_strategy rather than connection_busy; worker result did not differ. No skip count appeared in the provided summary. Operator final compileall explicitly exit0. Runtime gate remains REWORK; no full T111 PASS.

AUD-111-33: coordinator source inspection finds the API prepared fixture persists contract_json containing only instrumentId. Production _claim_execution calls _ensure_new_order_cap before lease acquisition and requires nonempty selectedLevels. Thus the malformed synthetic contract fails validation before proving the intended connection-lease exclusion. Do not accept invalid_strategy as an alternative race outcome or bypass production validation. Bounded fixture-only T118 dispatched E1/gpt-6-luna/xhigh explicitly, no inheritance; effective route unavailable. Allowed write only test_strategy_scope.py, add local protection for the actual pre-claim fixture shape, preserve PostgreSQL processes/barrier/exact results/persisted-state checks. Existing pre-existing telemetry2026-10-06 stays excluded. No child close/release primitive exists; terminal previous results preserved, only this writer active.

T118 failing baseline observed by executor before fixture correction: `rtk proxy python3.12 -m unittest backend.tests.test_strategy_scope.OwnedStrategyLookupTests.test_owned_api_claim_race_fixture_reaches_busy_guard` ran1, exit1, invalid_strategy instead of independently expected connection_busy. Initial default Python3.9 cannot import the existing slots dataclass; using already available Python3.12 restores the correct task runtime, with no installation or source workaround.

AUD33 source correction PASS after independent coordinator inspection: valid API selectedLevels and related fabricated contract fields are seeded through one helper shared by local and PG tests. No production behavior, process/barrier/exact race or persisted state assertion changed. Local47 tests pass (PG class intentionally excluded). Coordinator final malformed-contract negative1 then valid-busy positive1 each passed; fresh backend compileall0 and selected diff whitespace0. Exact commands in T118 task. T111 remains BLOCKED_EXTERNAL_VERIFICATION pending affected PostgreSQL rerun from the updated VPS runbook. Changes are being committed/pushed under the existing T111 Git authorization; this record does not establish a real PG pass.

## Stable related-regression checkpoint — 2026-10-11

Executor terminal turn failed with a runtime usage-limit error before final report. Source preserved. Existing role/route-compatible writer received bounded remediation; existing R3 auditor received a final read-only review request. No route substitution or coordinator executable edit.

Coordinator observed `/opt/homebrew/bin/python3.12 -m unittest backend.tests.test_multiuser_auth backend.tests.test_multiuser_store backend.tests.test_strategy_api backend.tests.test_strategy_automatic backend.tests.test_strategy_queue backend.tests.test_strategy_worker -q`: exit1, 198 tests, one failure, 15 errors, three skipped PostgreSQL cases. AUD-111-30: auth fixtures fail at TradeService initialization because T111 now requires connection-vault settings. AUD-111-31: the legacy batch-marker refusal fixture has a two-argument replacement while the current call supplies orders; execute returns500 instead of the expected safe200. The remediation must preserve missing-production-vault rejection and meaningful refusal/no-network assertions. Related fixture-only surface amendments are recorded in T111.

Coordinator observed `/opt/homebrew/bin/python3.12 -m compileall -q backend`: exit0 after executor termination, before any remediation. This is current snapshot build evidence only; later executable edits invalidate it. Previously reported 57-test T111 core (six unavailable-runtime skips) and 50-test trade suite evidence are not a full task verdict. Required final audit and real AES/PostgreSQL evidence remain outstanding.

AUD-111-30/31 corrected and inspected: only fabricated key settings were added to the existing auth fixture; production missing-vault guard remains. Legacy batch marker uses its two-argument seam and returns persisted APPLYING when refused, with no batch write and marker0; owned mode passes targets and retains guarded unsent completion. Ordered negative marker-refusal then positive post-leverage recheck each passed. Executor final V3 checkpoint: related198 tests OK/skipped4; T111 core107 tests OK/skipped6; both exit0. Fresh executor and coordinator backend compileall exit0, selected diff whitespace check exit0. These results preceded AUD-111-32 remediation and are reused only where unaffected.

AUD-111-32: independent R3 review and coordinator source inspection found `OwnedStrategyOrderWorker._claim_job` rejects a historical strategy claim whenever its fence differs from the current connection-wide fence. Another completed strategy/action or read-only scan advances that fence without updating every historical claim, permanently preventing older APPLIED/PARTIAL monitoring. Bounded E2 remediation delegated to the same explicitly bound executor, only `backend/strategy_worker.py` and `backend/tests/test_strategy_scope.py`: take over an older inactive historical claim using its observed prior-fence CAS under the connection lease, retain exact fresh-fence guards on callbacks and active-lease exclusion. Deterministic multiple-strategy monitoring and stale-worker regressions required before final stable audit. Task remains IN_PROGRESS/REWORK; no successor dispatch or runtime PASS.

## Final source checkpoint — 2026-10-11

AUD32 corrected: inactive nonnegative historical claim fence may be at or below the connection fence, never above it; takeover CASes the observed old claim to the newly allocated connection fence under existing locks. Active connection/claim leases still exclude takeover and callbacks retain exact fresh-fence guards. Before fix, the two new tests ran with one failure (only the first of two historical jobs recovered); after fix both pass. Tests assert fences5/6, both persisted APPLIED, zero exchange mutations, active/future-fence denial and stale first-job callback refusal. Executor observed `rtk test python3.12 -m unittest backend.tests.test_strategy_scope backend.tests.test_strategy_worker -q`: 46 run, OK/skipped1, exit0. No unaffected broad suite repeated.

R3 final immutable source review PASS: AUD01–32 reconciled, AUD14 withdrawn, no remaining scoped finding. Coordinator inspected the worker guard/new regression, legacy marker split, production vault guard/fixture-only changes and related evidence. Six T111 AES/PG cases remain unexecuted locally. Prior exact17-test checkpoint cannot be reconstructed reliably from retained executor evidence, so it is not used as the final ordered command proof. Coordinator ran the following fresh checkpoint in this order on the final stable source, using `/Users/locnguyen/.local/bin/rtk test /opt/homebrew/bin/python3.12` as the command prefix:

```bash
-m unittest \
  backend.tests.test_multiuser_ownership.MultiuserOwnershipBaselineTests.test_connection_id_guess_is_owner_first_uniform_404_without_upstream \
  backend.tests.test_multiuser_ownership.MultiuserOwnershipBaselineTests.test_revoke_same_account_relink_keeps_id_and_unknown_barrier \
  backend.tests.test_command_claims.CommandExecutionBoundaryTests.test_generation_change_after_prepare_cancels_without_send \
  backend.tests.test_command_claims.CommandExecutionBoundaryTests.test_send_timeout_persists_unknown_and_same_key_replay_does_not_resend \
  backend.tests.test_command_claims.OwnedCommandClaimTests.test_active_result_poll_does_not_rewrite_send_marker \
  backend.tests.test_strategy_scope.OwnedStrategyLookupTests.test_owned_worker_historical_claim_takeover_requires_expired_valid_fences -q
```

Negative checkpoint: six run, OK, zero skips, exit0. Then:

```bash
-m unittest \
  backend.tests.test_multiuser_ownership.MultiuserOwnershipBaselineTests.test_authenticated_owner_can_list_owned_connections \
  backend.tests.test_command_claims.CommandExecutionBoundaryTests.test_supported_close_polls_marker_during_send_and_same_key_returns_proven_result \
  backend.tests.test_strategy_scope.OwnedStrategyLookupTests.test_owned_worker_queue_persists_markers_and_ack_with_advancing_transport \
  backend.tests.test_strategy_scope.OwnedStrategyLookupTests.test_owned_worker_persists_readonly_same_owner_recovery_without_resending \
  backend.tests.test_strategy_scope.OwnedStrategyLookupTests.test_owned_worker_reclaims_historical_readonly_jobs_after_connection_fence_advances -q
```

Intended-success checkpoint: five run, OK, zero skips, exit0. Coordinator fresh `/opt/homebrew/bin/python3.12 -m compileall -q backend`: exit0 after all executable changes. Production/configuration paths unchanged; no installs, live exchange/VPS calls, Git writes or deployment. Pre-existing telemetry2026-10-06 remains untouched.

Final task verdict BLOCKED: source and local verification gates pass, required real runtime gates do not. Operator runbook `docs/agents/runbooks/2026-10-11-t111-vps-verification.md` contains six syntax-checked Bash blocks and fourteen AST-validated named test references. It requests six new T111 and four affected T110 runtime cases, all ten passing with no skips, plus the relevant regression and build. Existing T110 setup remains sufficient; no production setting or restart is required for synthetic tests. T112 and later tasks stay gated on full T111 PASS. Changes remain local/uncommitted; no commit/push action inferred from continuation.
Predecessor T110 PASS from independent source audit and accepted operator-provided Ubuntu real AES/PostgreSQL evidence. User authorized continuation of the existing revision 1 plan. Writer E2: requested gpt-6-luna/max explicitly bound, fork none; advisory auditor R3: requested gpt-6.1-sol/high explicitly bound, fork none. Effective routes unavailable. No child close/release primitive exposed.

## Review contracts

AC-002: owner from validated ordinary server principal; ownership predicates before every private/context lookup, operation/result/strategy/preference/reservation/conflict/worker path; guessed ID receives uniform 404 with zero victim upstream calls. Restricted recovery cannot alter connections/trading. Cookie Origin/CSRF and native bearer retain T110 rules.

AC-004: prepare binds owner/connection/product/environment/version/metadata/mode/expiry; durable claim/fence/lease and per-target pre-send marker atomically gate each mutation. Active execution excludes result polling reconciliation. Lease expiry cannot make unresolved sent intent executable again. Revocation/rotation stops unsent tail; sent ambiguity survives restart/relink.

Identity/vault: authoritative OKX uid from existing account_config; no API-key/balance-derived identity. Typed credentials stored only as vetted AEAD, owner/connection/exchange/version AAD; keys separate from session and remote identity. Stable remote mapping remains reserved through revoked tombstones; same-owner relink retains connection_id/UNKNOWN barriers, no owner transfer or digest-key bypass.

Preliminary advisory checklist has been sent to the writer; it is not an audit of a stable implementation. Existing singleton strategy callers require complete v2 ownership integration or explicit fail-closed staging, not implicit access through v1.

## Evidence required

Baseline regression observed before implementation; formal negative RED before GREEN for owner isolation and duplicate/crash send cases; focused planned V3, unchanged legacy compatibility, final backend compileall. Independent stable-source review after writer completion. Real AES-GCM and PostgreSQL process/connection tests must run separately on the operator VPS; test doubles/SQLite do not establish this evidence. No production launch or live exchange write is authorized.

Official endpoint contract refreshed from https://app.okx.com/docs-v5/en/ and https://my.okx.com/docs-v5/en/: GET /api/v5/account/config supplies current account metadata (uid and current-key permission fields); the existing backend/okx.py transport is the reuse target. No repository content was sent in documentation queries.

## Baseline regression before implementation

Executor reported `python3.12 -m unittest backend.tests.test_multiuser_ownership.MultiuserOwnershipBaselineTests.test_authenticated_owner_can_list_owned_connections -q` exit 1: authenticated GET /v2/connections returned 404 because route is absent. Only the allowed new test file was added at that point. This is baseline-new-behavior evidence, separate from the formal negative RED then intended-success GREEN still required after implementation.

## Preliminary implementation findings

- AUD-111-01: existing account-context verification compares scalar permission strings, but official OKX config uses comma-separated permission sets. Parse a bounded unique allowlist; reject withdrawal anywhere, unknown/empty tokens fail closed. Add read+trade and mixed-withdrawal fixtures. Writer acknowledged; correction pending verification.
- AUD-111-02: schema check-then-ALTER needs a PostgreSQL migration-wide lock; per-instance initialization mutex does not serialize API/worker processes. Reject future schema version before mutations and test concurrent old-schema initialization with preserved rows. Sent to writer; correction pending verification.

Targeted preliminary vault review found coherent purpose-separated HKDF and owner/connection/exchange/version/environment/region/key-ID AAD; missing key ID fails closed. No stable-snapshot or actual AES/PG result claimed.

## Additional evolving-source findings (forwarded to writer)

- AUD-111-03: refresh time and persisted session/step-up/version/lease authority after the final potentially blocking lock; emit UTC ISO timestamps and bound upstream verification admission.
- AUD-111-04: account GET must be side-effect-free; guarded POST verify requires recent step-up before enabling permission/trading changes.
- AUD-111-05: crash-paused identity rotation must resume only with matching old/target fingerprints; wrong keys/new connection remain blocked.
- AUD-111-06: public command API must accept the approved typed close/cancel intents, not arbitrary new-order native payloads. Require fresh scoped metadata/mode/target preflight and bound one-use confirmation, 30s expiry, before execute.
- AUD-111-07: semantic idempotency hash excludes generated operation/client IDs; return existing same-key operation before new-command readiness/UNKNOWN barriers after owner/session validation; changed intent yields409.
- AUD-111-08: marker transition must allow a safe sequential second target under the same valid fence, never resume after uncertainty.
- AUD-111-09: accepted ACK is nonterminal; reconciliation must validate exact target identity and exchange-proven terminal close/cancel state. Never infer successful completion from an order ID or ACK.
- AUD-111-10: guarded EXPIRED/CANCELED/unsent-tail transitions must commit before safe rejection; raising inside transaction otherwise rolls them back. Tests must assert durable state, not just HTTP error.

These are confirmed preliminary source defects, not a final stable audit. No coordinator/reviewer tests were run while the executor was mutating source. Full T111 completion is not claimed.

## User pause

Writer interrupted at user request; source preserved, stable audit not performed. Additional recovery/eligibility findings AUD-111-11/12 and reported selected regression results are captured in `2026-10-10-t111-resume-checkpoint.md`. Last source corrections require review on resume; no T111 PASS claimed.

## Resumed evolving-source review

User resumed the interrupted E2 writer. R3 reviewed recovery bindings: sent operation digests are atomically reindexed during remote-key rotation; reconciliation alone may use current same-owner read credentials, submission keeps original generation checks. A rotation racing captured recovery payload can safely produce one UNKNOWN result before a later fresh recovery; runtime regression still required (AUD-111-13).

Strategy findings forwarded while source evolves:
- AUD-111-14 withdrawn for current snapshot: coordinator and writer independently counted six legacy columns/values, eight owned. No unnecessary SQL correction required; execution coverage still appropriate.
- AUD-111-15: owned strategy lookup must precede any upstream account call for guessed IDs.
- AUD-111-16: replace SQLite-only nullable `execution_id IS ?` on PostgreSQL-owned paths; handle IdentityStoreConflict safely.
- AUD-111-17: owner-scoped historical result reads remain available after credential rotation; generation restrictions apply to new mutations, not durable result projection.
- AUD-111-18: create indexes only after referenced additive columns; add strategy credential/permission version columns to the correct old-schema table. Test actual v1 schema upgrade, not a current schema with version flag changed.

No stable implementation verdict, full RED/GREEN, final build or real PostgreSQL/AES result is claimed for current T111. GUC/RLS substitution was considered by the writer and explicitly rejected; approved architecture retains portable explicit composite-owner predicates and normal scoped storage, with no new database-role/configuration requirement.

## Resumed focused executor evidence

- `python3.12 -m unittest backend.tests.test_strategy_scope.OwnedStrategyLookupTests -q`: four tests pass, exit0, after correcting the captured-clock fixture. Scenarios: owner-first missing-ID/no upstream, historical result after rotated generation, owned scan success/error upsert, legacy scan success/error upsert. This supports corrections15–17 and withdrawal14, not final task PASS.
- `python3.12 -m unittest backend.tests.test_multiuser_ownership.MultiuserOwnershipBaselineTests.test_t110_schema_upgrade_preserves_owner_and_connection_rows -q`: one test passes, with actual old-v1 strategy/reservation schema preservation and additive owner/version columns. Supports correction18; actual PostgreSQL upgrade/race evidence remains required.

Executor reports execution marker/finish and owned queue/worker integration still in progress; current snapshot is not stable for final audit.

## Owned execution/queue checkpoint (still in progress)

R3 findings19–21 were forwarded: leverage marker used side_order before assignment; post-send finish revalidated request authority; uncertain leverage could release reservation and become deletable as never-sent. Writer reports fixes and 12 passing `OwnedStrategyLookupTests`: unchanged owner/execution/fence can retain outcome after revoke/expiry, newer fence blocks stale overwrite, UNKNOWN leverage retains reservation and delete/replacement barriers. This evidence remains executor-reported inner-loop; stable audit and runtime races pending.

Affected existing `backend.tests.test_strategy_api.StrategyApiTests.test_green_batch_execute_rechecks_account_and_mode_after_leverage` initially failed500 in prepare: lock helper assumed legacy SQLiteStore had a dialect field. Corrected missing-dialect handling; exact legacy regression then passed,1test with both account-change and mode-change subtests. Subset py_compile passes are not final backend compileall evidence. Owned worker/caller integration still incomplete.

## Caller/route review findings after queue checkpoint

- AUD-111-22: expected authority-loss exceptions at pre-send guard must go through safe completion of prior leverage evidence. Writer tested an APIError path (three tests pass); actual owner guard raises ConnectionServiceError, which still needs normalization/test via real guard.
- AUD-111-23: strategy action suffix includes ID, so comparing whole suffix to bare prepare-apply/execute-apply incorrectly skips recent step-up and trade capability gates.
- AUD-111-24: persisted GET history/result/list/settings must use owner-scoped metadata without decrypting credentials or requiring an active connection; revoked credentials cannot hide durable outcomes.
- AUD-111-25: owned compatibility fingerprint must not derive from session-signing key, because key rotation cannot change ownership/history/preferences/reservations.

Writer confirmed23–25 in source and is integrating read-only scope and stable fingerprint. Worker remains incomplete. No final T111 verification/audit/PASS claimed.

## Route remediation focused evidence

Executor observed failures before correction for real nested prepare-apply step-up route (APIError not raised) and revoked historical result GET (connection_unavailable). Both exact tests subsequently passed. Stable owned compatibility fingerprint now derives from domain-separated user_id+connection_id rather than signing key. `test_owned_history_preferences_and_reservation_survive_signing_key_rotation` passed after actual fresh login under a new signing key, preserving UNKNOWN history, saved preference and overlap reservation. These are focused executor checks, not final audit.

At latest checkpoint the worker is still absent. Owned queue claim needs the shared connection lease/fence and strategy claim; API execution claim lock ordering is being corrected before identity-store worker selection/takeover. No required task has been declared complete.
