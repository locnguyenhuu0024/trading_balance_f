# Implementation Plan: Multi-platform view-only restructure

Status: APPROVED revision 2 (user, chat, 2026-11-07: "Duyệt, chạy T122"; includes PRE-4); EXECUTING
Date: 2026-11-07
Tier: L
Plan ID: PLAN-20261107-multi-platform-view-only
Specification: `docs/agents/specs/2026-11-07-multi-platform-view-only-design.md`
Decision Ledger: `docs/agents/decisions/2026-11-07-multi-platform-view-only-decisions.md`

## 1. Objective

Implements: REQ-001..REQ-012
Acceptance: AC-001..AC-012

## 2. Preconditions

Decisions: D-001..D-011. Proposals P-001..P-005 are accepted only by approval of this plan.

Before the first dispatch, each needing specific user approval:
- PRE-1 Git: commit `designs/` and these planning artifacts so the writer checkout is clean (`scripts/ccb/dispatch.py` rejects dirty trees, including untracked files), then create branch `codex/multi-platform-view-only` from main.
- PRE-2 CCB: `scripts/ccb/dispatch.py` `ALLOWED_EXTENSIONS` on main has no `.dart`, so every task here would be refused. Re-add that one entry in a separate commit.
- PRE-3 Git: commit each task after its audit PASS.
- PRE-4 Git (revision 2): commit the OptCodex v1.4.0 and CCB v0.7 upgrade in the checkout, re-add `.dart` to `ALLOWED_EXTENSIONS` in a separate commit since the upgrade removed it again, and commit the T116 attempt as work in progress so T122 can run on a clean checkout.

## 3. Repository Impact

| Area | File | Symbol | Change Type |
|---|---|---|---|
| Gate | `lib/core/backend_features.dart` | `backendFeaturesEnabledProvider` | ADD |
| Gate | `trade_session_provider.dart`, `strategy_api_client.dart` | `tradeApiProvider`, `strategyApiProvider` | MODIFY |
| Orders | `orders_screen.dart` | parent gating, neutral data, scope | MODIFY |
| Settings | `settings_screen.dart`, `settings_trade_access_page.dart` | nav tiles and dialogs removed, backend section gated, form extraction | MODIFY |
| Navigation | `main_navigation_shell.dart`, `navigation_destination_data.dart`, `navigation_presentation_host.dart`, `trading_navigation_bar.dart`, `main.dart`, `secure_storage_helper.dart` | fixed bar | MODIFY |
| Navigation | `floating_navigation_buttons.dart`, `navigation_preferences.dart`, `navigation_preferences_provider.dart` | customization | DELETE |
| Tools | `lib/features/tools/tools_screen.dart` | `ToolsScreen` | ADD |
| Exchange core | `lib/core/exchange/*` | contract, registry, scope, scoped read | ADD |
| OKX | `lib/exchanges/okx/okx_adapter.dart`, `okx_read_scope.dart` | adapter, wrapper | ADD/MODIFY |
| Binance | `lib/exchanges/binance/*`, `secure_storage_helper.dart` | client, signer, readers, market, credentials | ADD/MODIFY |
| Analysis | market, fractal_tracker, support_resistance | adapter reads, per-exchange watchlist | MODIFY |
| Connections | `lib/features/connections/*`, `lib/core/widgets/scope_bar.dart` | bar, picker, gate, management, forms | ADD |
| Portfolio | `portfolio_screen.dart`, provider | neutral data, design layout | MODIFY |

Explicitly not modified: `backend/`, Strategy feature code, `TradeApiClient`, position and cancellation flow providers, all protected configuration and manifests, the two earlier branches.

## 4. External Configuration / Environment Actions

Required actions: none.

## Planning Workstream Decomposition

| Workstream | Material | Independently Analyzable | Reasoning Route | Agent Run | Status / Adoption |
|---|---|---|---|---|---|
| Mobile UI, IA, navigation, hide-backend | YES | YES | R2 / Claude Sonnet / medium, explicit; effective route unverifiable | R2-A | COMPLETE, USED with corrections |
| Exchange integration, contract, scope, concurrency | YES | YES | R2 / Claude Sonnet / medium, explicit; effective route unverifiable | R2-B | COMPLETE, USED with corrections |
| Backend/API | NO | N/A | N/A | N/A | D-003 removes it from scope |

Fan-out Required: YES
Required Reasoning Agents: 2
Actual Reasoning Agents: 2
Fan-out Compliance: EXCEPTION — user declined the external `gpt-6.1-sol/medium` route (D-011) and chose Claude subagents, so counts are met on a user-directed substitute route, not the baseline route.
Skip Reason: N/A
Cross-workstream synthesis: Scope mechanism combines B's scope-keyed family providers with A's keyed subtree. R2-A's `capture id and compare` is replaced by the structural mechanism. R2-B's Binance facts were unverified, so the coordinator checked routes and CORS by curl and read docs (spec OBS-010..012), correcting `/fapi/v3/positionRisk` as sole source of leverage. Both task lists merged: nav goes with the gate because they edit the same shell.

Coordinator runtime: the app reports Claude Opus 5.5, while the CCB rules describe Sonnet 5.5 High as the user's selection. Effort is not observable.

## 5. Dependency Graph

```text
PRE-1, PRE-2 -> T116 -> T122 -> T117 -> T118 -> G1 -> T119 -> T120 -> T121 -> final audit -> user live check
```

All serial: CCB allows one writer per checkout, and these tasks share screens and providers.

G1 (coordinator, read-only, before T119): resolve HYP-001 and HYP-002 from Binance documentation. If `positionRisk` fields differ, update the T119 mapping within the spec's rule that unavailable fields render `—`. Any material change returns here for approval.

## 6. Ordered Implementation Steps

Task files hold the exact contracts.

### P01 — View-only mode and fixed navigation (T116)
Implements REQ-001..003. This ships a usable view-only app on OKX first. Verification: RED-116 then GREEN-116.

### P02 — Exchange core and OKX behind it (T117)
Implements REQ-004, 005, 012 for portfolio and orders. Behavior for users is unchanged. A fake second adapter proves switching.

### P03 — Analysis screens and Binance public market (T118)
Implements REQ-008. Binance public reads and the per-exchange watchlist; swallowed candle errors are surfaced.

### P04 — Binance private reads (T119)
Implements REQ-006, 007. Adapter only, using fake transports.

### P05 — Connection experience (T120)
Implements REQ-009, 010 and registers Binance so a person can select it.

### P06 — Design shell and states (T121)
Implements REQ-011. Visual layer with rendered review.

## 7. Test and Verification Plan

| Test | Proves | Level | Command/Method |
|---|---|---|---|
| RED-116, GREEN-116 | AC-001..003 | widget | `rtk flutter test --no-pub <file> --plain-name '<name>'` |
| RED-117a/b/c, GREEN-117 | AC-004, 005, 012 | provider, widget | same |
| RED-118a/b, GREEN-118 | AC-008 | unit, widget | same |
| RED-119a/b/c/d, GREEN-119 | AC-006, 007 | unit with fake transport | same |
| RED-120a/b, GREEN-120 | AC-009, 010 | widget | same |
| RED-121, GREEN-121 | AC-010, 011 | widget, rendered review | same, plus browser review of web build |

Inner-loop diagnostics: narrowest test. Formal checkpoint: RED then GREEN once when ready. Later changes invalidate only affected evidence.
Task verification ceiling: V3.
Final integration ceiling: V4 once; no CI is recorded as authoritative here.
Escalate when: a shared provider or fixture used outside the task's test set changes.

### External verification constraints

User-executed verification required: YES, after final audit.
1. Native build, because agents may not regenerate native project files: `flutter build ios --simulator --no-codesign`
2. Live read with the user's own read-only keys on a device or simulator: OKX and Binance assets, positions, pending orders, history, Margin, switching both ways, reopen.

Proves: AC-006, AC-007 and AC-009 on real data.
Evidence required back: pass or fail per item, and any non-secret message shown.
Completion blocked until evidence supplied: YES for claiming live Binance works; NO for code audit PASS.
Full-suite ownership: CODEX_ONCE, run by the final executor pass and re-observed by the coordinator.

Regression coverage: all existing OKX read tests; gate-true backend screen tests.
Other checks: `flutter analyze --no-pub`; `flutter build web --no-pub`.

## 8. Migration / Data Plan

N/A — no stored data is migrated. New keys only: `SELECTED_CONNECTION_ID`, Binance credentials, per-exchange watchlist key for Binance.

## 9. Performance Verification

N/A — no numeric target; weights handled by lanes and the 10-symbol cap.

## 10. Risks

| Risk ID | Risk | Impact | Detection | Mitigation |
|---|---|---|---|---|
| RISK-001 | While view-only, the user cannot close positions or stop strategies in the app | Must act on the exchange's own app | Known by design | Stated in approval summary; backend and its worker are untouched by this plan |
| RISK-002 | `orders_screen.dart` and `portfolio_screen.dart` move to neutral data while large tests bind OKX types | Largest regression risk | Existing tests | Adapter maps field by field; T117 is E2; backend widgets keep OKX types |
| RISK-003 | Hidden code rots | Harder re-enable | Gate-true tests stay in the suite | Retain tests under the override |
| RISK-004 | Binance fixtures may not match live shapes | Wrong or missing values | User live check | Doc-derived fixtures; unavailable shows `—`; never claim live PASS without evidence |
| RISK-005 | Binance total is approximate; multi-asset and Earn assets may be partial | User reads total as exact | Partial label | Explicit partial copy, P-005 |
| RISK-006 | A rules upgrade overwrites the `.dart` allowlist again | Dispatch blocked | Dry-run before dispatch | PRE-2 |

## 11. Rollout / Rollback

Sequence: feature branch, task by task, final audit, user live check, then a user decision on merge.
Rollback trigger: wrong scoping or OKX regression.
Rollback steps: leave unmerged or revert. No data cleanup is needed.

## 12. Decision/Assumption Dependency Registry

| Decision/Assumption | Used By | Evidence/Authorization | Invalidated By |
|---|---|---|---|
| D-003 | T116, RISK-001 | Chat, 2026-11-07 | User re-enables backend |
| D-009 | T119, T120 | Chat, OBS-010 | Change in Binance CORS or product scope |
| D-010 | T119, T120 | Chat, OBS-012 | User wants wider history |
| D-005 | T118 | Chat | — |

## 13. Task Decomposition

Six tasks exceed the Tier L target of 2 to 5. Reason: T118 and T119 use different hosts, credentials and verification; T121 needs rendered review; merging them would make one executor hold too many independent failure modes. Nav and gate were merged because they share one surface.

| Task | Plan Steps | Requirements/AC | Depends On | Executor Class | Route | Allowed Write Surface |
|---|---|---|---|---|---|---|
| T116 | P01 | REQ-001..003 / AC-001..003 | PRE-1, PRE-2 | legacy E1 | gpt-6-luna / xhigh, kept per user | REWORK |
| T122 (T116 R01) | P01 | REQ-002, 012 / AC-002 | T116 WIP commit | E1 | gpt-6.1-terra / low | see task |
| T117 | P02 | REQ-004, 005, 012 / AC-004, 005, 012 | T116 PASS | E4 | gpt-6.1-terra / xhigh | see task |
| T118 | P03 | REQ-008 / AC-008 | T117 | E3 | gpt-6.1-terra / high | see task |
| T119 | P04 | REQ-006, 007 / AC-006, 007 | T117, G1 | E3 | gpt-6.1-terra / high | see task |
| T120 | P05 | REQ-009, 010 / AC-009, 010 | T118, T119 | E3 | gpt-6.1-terra / high | see task |
| T121 | P06 | REQ-011 / AC-011 | T120 | E2 | gpt-6.1-terra / medium | see task |

Routing follows `docs/agents/framework/EXECUTOR_ROUTING_POLICY.json` v2. Classes come from implementation entropy; rationale is in each task. No E5 and no route override is proposed. Escalation happens only on observed evidence.

### Task Buildability Plan

| Task | Required | Affected Canonical Build Unit | Exact Secret-Free Build Command | Boundary Strategy |
|---|---|---|---|---|
| T116..T121 | YES | Flutter app `lib/` plus `test/` | `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings && flutter build web --no-pub` | Compatibility-staged: `runOkxPrivateRead` kept as wrapper; screens move only in the task that owns them; new code is additive until wired |

## 14. Completion Gate

- [x] planning workstream coverage gate has a permitted `EXCEPTION` recorded
- [ ] every task PASS
- [ ] every code-producing task had a `PASS` task buildability gate at its final task-local executable state
- [ ] compile-coupled changes were merged or compatibility-staged
- [ ] every affected AC has implementation/verification evidence
- [ ] RED precedes GREEN for every task
- [ ] relevant repository checks observed
- [ ] final diff matches approved scope
- [ ] final integration audit PASS
- [ ] no protected configuration/environment file was read or modified by an agent
- [x] every external configuration/environment action is reported or N/A

## 15. Change Log

| Revision | Change | Reason |
|---|---|---|
| 2 | T117..T121 reclassified to E0-E5 routes; T122 added as T116 remediation; analyzer gate no longer fails on pre-existing infos | User request after upgrade to OptCodex v1.4.0 and CCB v0.7; rules require re-approval of pre-v1.4 task routes; T116 audit |
