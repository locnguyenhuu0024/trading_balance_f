# Implementation Plan: PnL-reactive 3D avatar

Plan ID: PLAN-20261122-pnl-avatar-3d
Status: APPROVED
Revision: 1
Date: 2026-11-22
Tier: L
Specification: `docs/agents/specs/2026-11-22-pnl-avatar-3d-design.md`
Decision Ledger: `docs/agents/decisions/2026-11-22-pnl-avatar-3d-decisions.md`

## 1. Objective

Implements: REQ-210..REQ-215
Acceptance: AC-210..AC-217

## 2. Preconditions

Decisions: D-030..D-034, CD-1..CD-4.
Repository: clean `main` at `4eac0f2`; OptCodex personal 1.5.1 / baseline 1.2.3 lock verified.
Network: T146 downloads pinned npm packages (three 0.187.0, @pixiv/three-vrm 3.5.5, esbuild 0.25.10) and the sample VRM model (D-035: `VRM1_Constraint_Twist_Sample`) from `raw.githubusercontent.com/vrm-c/vrm-specification`. Approval of this plan is the explicit permission for these downloads.

## 3. Repository Impact

| Area | File | Symbol | Change |
|---|---|---|---|
| Runtime src | `tools/avatar/src/{bridge,protocol,mood,gesture,hit,main,entry}.js` | page runtime | ADD |
| Runtime build | `tools/avatar/build.py`, `tools/avatar/optimize_vrm.py`, `tools/avatar/README.md` | build/optimize | ADD |
| Runtime tests | `tools/avatar/test/*.test.js` | node --test | ADD |
| Assets | `assets/avatar/{index.html,avatar.bundle.js,avatar.vrm,LICENSES.md}` | bundled | ADD (generated/committed) |
| Domain | `lib/features/avatar/domain/avatar_mood.dart` | `AvatarMood`, `avatarMoodFor` | ADD |
| Settings | `lib/core/security/secure_storage_helper.dart` | `_avatarEnabled`, `getAvatarEnabled`, `saveAvatarEnabled` | MODIFY |
| Startup | `lib/main.dart` | `AppStartupData.avatarEnabled`, `initializeAppStartup`, `buildInitializedApp`, `WebStorageHelper` | MODIFY |
| Settings UI | `lib/features/settings/presentation/settings_screen.dart` | `avatarEnabledProvider`, switch + credit | MODIFY |
| Licenses | `lib/features/avatar/avatar_licenses.dart` | `registerAvatarLicenses()` called from `main()` | ADD / MODIFY main |
| Host | `lib/features/avatar/presentation/{avatar_renderer.dart,avatar_renderer_native.dart,avatar_renderer_web.dart,floating_avatar.dart}` | renderer + overlay | ADD |
| Home | `lib/features/portfolio/presentation/portfolio_screen.dart` | extract `_headline`, Stack overlay | MODIFY |
| Tests | `test/features/avatar/*`, `test/features/settings/settings_avatar_toggle_test.dart`, `test/features/portfolio/portfolio_avatar_test.dart`, `test/core/widgets/app_startup_test.dart` | | ADD/MODIFY |

Explicitly not modified: `pubspec.yaml`, `pubspec.lock`, all `ios/`, `android/`, `macos/`, `web/` platform/config files, `analysis_options.yaml`, any `package.json`, CI, Docker, `.env*`, governance files.

## 4. External Configuration / Environment Actions

User-owned (spec §17): (1) add `webview_flutter: ^4.14.1` and `web: ^0.5.1` to `pubspec.yaml` `dependencies:`; (2) add `- assets/avatar/` under `flutter:` → `assets:`; (3) `flutter pub get` (and `pod install` in `ios/`/`macos/` if not automatic). Must be applied **after T146 PASS and before T148 dispatch**. Blocks T148: YES.

## Planning Workstream Decomposition

| Workstream | Material | Independently Analyzable | Reasoning Route | Agent Run | Status / Adoption |
|---|---|---|---|---|---|
| Flutter host (UI, settings, lifecycle, platform embedding) | YES | YES | R2 / claude-opus (Agent tool; effort not bindable) | RSN-001 | COMPLETE / USED |
| 3D web runtime (three-vrm, assets, gestures, bridge, perf) | YES | YES | R2 / claude-opus (Agent tool; effort not bindable) | RSN-002 | COMPLETE / PARTIAL |
| Backend/API | NO | — | N/A | N/A | N/A |

Fan-out Required: YES
Required Reasoning Agents: 2
Actual Reasoning Agents: 2
Fan-out Compliance: PASS (route effort UNVERIFIABLE — runtime child selector exposes model only)
Skip Reason: N/A
Cross-workstream synthesis: gesture ownership reconciled to Flutter-owned input + page-side classification (CD-1; RSN-002 proposed WebView-owned taps, RSN-001 proposed IgnorePointer). Bridge contract unified in spec §7 (`pointer` message added). npm build kept outside repo manifests (CD-3). Model bytes: native chunked transfer, web relative fetch.

## 5. Dependency Graph

```text
T146 ──┐
       ├─► [USER: pubspec actions] ─► T148 ─► final integration + user device check
T147 ──┘
```
Writers serialized (one Codex writer per checkout): wave 1 T146, wave 2 T147, user action, wave 3 T148.

## 6. Ordered Implementation Steps

### P01 — Page runtime and assets (T146)
Implements REQ-213 (page side), REQ-214, REQ-215 (LICENSES.md); AC-215 (auto part), AC-217.
1. Pure ES modules `protocol.js`, `mood.js`, `gesture.js` (no three import) + `node --test` suites.
2. `hit.js` (bone projection regions), `bridge.js` (AvatarChannel / postMessage adapter), `main.js` (renderer, loader, idle, moods, reactions, pause, chunks), `entry.js`.
3. `build.py`: temp dir (or `--deps` cache) → `npm install --no-save --ignore-scripts three@0.187.0 @pixiv/three-vrm@3.5.5 esbuild@0.25.10` → esbuild IIFE → `assets/avatar/avatar.bundle.js`.
4. `optimize_vrm.py` (stdlib only + macOS `sips`): parse GLB, downscale PNG images > 512² to 512² (keep image/texture indices and the thumbnail), rewrite buffer/bufferViews, assert `VRMC_*` extension JSON unchanged → `assets/avatar/avatar.vrm`.
5. `index.html`, `LICENSES.md`, `README.md` (how to rebuild, pinned versions, source URL + license).
RED/GREEN: RED-146 / GREEN-146 (spec §13).

### P02 — Mood + setting + licenses (T147)
Implements REQ-210, REQ-211, REQ-215; AC-210..AC-212, AC-216.
1. `avatar_mood.dart` pure mapping.
2. Storage key/getter/saver (native) + `WebStorageHelper` overrides; `AppStartupData.avatarEnabled` loaded in its own try/catch; provider override.
3. `avatarEnabledProvider` + `SwitchListTile` + credit line in Settings section "BẢO MẬT & TRẢI NGHIỆM"; revert on save failure.
4. `registerAvatarLicenses()` via `LicenseRegistry.addLicense`, called in `main()`.
RED/GREEN: RED-147 / GREEN-147.

### P03 — Home host (T148)
Implements REQ-212, REQ-213 (Flutter side); AC-213..AC-215.
1. `AvatarRenderer` interface + factory provider; conditional import native/web.
2. Native: `WebViewController` (JS unrestricted, transparent bg guarded, `AvatarChannel`), `loadFlutterAsset('assets/avatar/index.html')`, on `ready` send `setReducedMotion`, `setMood`, then model chunks (`rootBundle.load('assets/avatar/avatar.vrm')`, base64, 512 KB chunks).
3. Web: `ui_web.platformViewRegistry` iframe (`assets/assets/avatar/index.html`, `pointer-events:none`, transparent, no border), `window.onMessage` origin-checked.
4. `FloatingAvatar`: Stack-positioned, long-press drag + clamp, pointer forwarding (throttle 30 Hz), lifecycle observer, haptics, Semantics, hide on `error`, fade-in on `modelLoaded`.
5. PortfolioScreen: extract headline computation to a private helper (no math change), compute `avatarMoodFor`, wrap Column in Stack, add overlay when enabled.
RED/GREEN: RED-148 / GREEN-148.

## 7. Test and Verification Plan

| Test | Proves | Level | Command |
|---|---|---|---|
| TEST-146 | RED/GREEN-146 | unit (node) | `node --test tools/avatar/test/` |
| TEST-146b | bundle + VRM build | script | `python3 -I -B tools/avatar/build.py && python3 -I tools/avatar/optimize_vrm.py check assets/avatar/avatar.vrm` |
| TEST-147 | RED/GREEN-147 | unit/widget | `flutter test --no-pub test/features/avatar/avatar_mood_test.dart test/features/settings/settings_avatar_toggle_test.dart test/core/widgets/app_startup_test.dart` |
| TEST-148 | RED/GREEN-148 | widget (fake renderer) | `flutter test --no-pub test/features/portfolio/portfolio_avatar_test.dart test/features/avatar/floating_avatar_test.dart` |
| MAN-148 | AC-214, AC-215 | manual, user-run | run on iOS sim, Android device, macOS, Chrome; checklist in T148 |

Executor sandbox cannot run Flutter (prior evidence T141): executors write code and report RED/GREEN `NOT_RUN`; coordinator runs formal RED → GREEN and buildability on host.
Task verification ceiling: V2. Final integration ceiling: V4 (`flutter test --no-pub` full suite).
External verification: YES — MAN-148 device checklist, user-run; completion of AC-214/AC-215(manual) blocked until returned.

## 8. Migration / Data Plan

N/A — new bool key only, absent ⇒ false.

## 9. Performance Verification

Automated: asset sizes (AC-217). Manual: low-end Android fps/thermal 2 min observation, part of MAN-148.

## 10. Risks

| ID | Risk | Impact | Detection | Mitigation |
|---|---|---|---|---|
| RISK-210 | Executor sandbox lacks network for npm/GitHub | T146 blocked | build.py failure | `BLOCKED_ENVIRONMENT`; user runs `python3 -I -B tools/avatar/build.py` and optimizer once locally |
| RISK-211 | macOS WKWebView transparency/asset loading differs | macOS visual | MAN-148 | guarded `setBackgroundColor`; report as REWORK finding |
| RISK-212 | Android hybrid-composition cost / WebGL context loss | jank, blank | MAN-148 | 30 fps cap, pause, `webglcontextlost` → error → hide |
| RISK-213 | VRM-unaware optimization corrupts model | broken render | `--check` + manual | stdlib GLB rewrite, extension equality assert |
| RISK-214 | App size +~6.5 MB (assets) | install size | asset size check | texture downscale; feature default off (assets still shipped) |
| RISK-215 | Pointer forwarding latency via `runJavaScript` | sluggish petting | MAN-148 | 30 Hz throttle; page interpolates |

## 11. Rollout / Rollback

Default off. Rollback: revert feature files; user removes pubspec entries.

## 12. Decision/Assumption Dependency Registry

| Decision | Used By | Authorization | Invalidated By |
|---|---|---|---|
| D-030 | P03, T148 | user 2026-11-22 | platform scope change |
| D-031/D-032 | P02, P03 | user 2026-11-22 | metric/threshold change |
| D-033 | P01, P03 | user 2026-11-22 | placement/delivery change |
| D-034 | P01 | user 2026-11-22 | model change |
| CD-1..CD-4 | P01, P03 | this plan's approval | user veto at approval |

## 13. Task Decomposition

| Task | Steps | REQ/AC | Depends On | Class | Route | Allowed Write Surface |
|---|---|---|---|---|---|---|
| T146 | P01 | REQ-213/214/215; AC-215/217 | — | E3 | gpt-6.2-sol / medium | `tools/avatar/**`, `assets/avatar/**` |
| T147 | P02 | REQ-210/211/215; AC-210..212, AC-216 | — | E2 | gpt-6.2-sol / low | `lib/features/avatar/domain/avatar_mood.dart`, `lib/features/avatar/avatar_licenses.dart`, `lib/core/security/secure_storage_helper.dart`, `lib/main.dart`, `lib/features/settings/presentation/settings_screen.dart`, `test/features/avatar/avatar_mood_test.dart`, `test/features/settings/settings_avatar_toggle_test.dart`, `test/core/widgets/app_startup_test.dart` |
| T148 | P03 | REQ-212/213; AC-213..215 | T146, T147, user pubspec actions | E3 | gpt-6.2-sol / medium | `lib/features/avatar/presentation/**`, `lib/features/portfolio/presentation/portfolio_screen.dart`, `test/features/avatar/floating_avatar_test.dart`, `test/features/portfolio/portfolio_avatar_test.dart` |

3 tasks (Tier L target 2–5). T146 separate: different toolchain (node/python), no Dart compile coupling. T147 separate from T148: buildable without new dependencies, so it can PASS before the user pubspec action.

### Task Buildability Plan

| Task | Required | Build Unit | Command | Strategy |
|---|---|---|---|---|
| T146 | YES (JS bundle) | `tools/avatar` | `python3 -I -B tools/avatar/build.py && node --test tools/avatar/test/` | self-contained |
| T147 | YES | Flutter app | `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings && flutter build web --no-pub` | self-contained (no new deps) |
| T148 | YES | Flutter app (native + web) | `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings && flutter build web --no-pub && flutter build apk --debug --no-pub && flutter build macos --debug --no-pub && flutter build ios --simulator --debug --no-pub` | requires user pubspec actions first |

## 14. Completion Gate

- [x] planning workstream coverage PASS
- [ ] every task PASS
- [ ] buildability PASS per task
- [ ] no compile-coupled task passed on a broken boundary
- [ ] every AC evidenced (AC-214/215 manual via MAN-148)
- [ ] RED before GREEN per task
- [ ] V4 full suite at final integration
- [ ] final diff matches scope
- [ ] final integration audit PASS
- [ ] no protected file modified by an agent (pre-baseline read of `pubspec.yaml` disclosed)
- [ ] external configuration actions reported

## 15. Change Log

| Revision | Change | Reason |
|---|---|---|
| 1.1 | Executor-facing file names aligned to dispatcher allowlist; `web: ^0.5.1`; offline deps cache pre-staged by coordinator for T146 (downloads authorized by plan approval) | Execution-time constraints; no scope/requirement change. Approved revision 1 remains the governing plan. |
| 4.0 | Revision 4 added (outfit mixing; supersedes 3.1 plan) — READY_FOR_APPROVAL | User request 2026-11-24 |
| 3.1 | Revision 3.1 added (Donut part mapping, initial colours) — READY_FOR_APPROVAL | T152 device findings |
| 3.0 | Revision 3 added (colour customization) — READY_FOR_APPROVAL | User request 2026-11-24 |
| 2.0 | Revision 2 added (model picker, Donut-Chan, quality) — READY_FOR_APPROVAL | User request 2026-11-22 |
| 1.2 | D-035 model switch; T146 remediation R01 (arm rest pose, per-chunk base64, CSP `file:`, live swipe yaw, model swap) | T146 audit REWORK + user decision |

## Revision 2 — model picker, Donut-Chan, render quality (2026-11-22)

Plan ID: PLAN-20261122-pnl-avatar-3d-r2
Status: APPROVED (user, 2026-11-22)
Implements: REQ-216..REQ-220; AC-218..AC-222. Decisions D-037..D-039, CD-5..CD-8.
T148 remains VERIFYING (MAN-148: iOS simulator PASS; Android device runs — quality finding addressed here).

### Planning workstreams
| Workstream | Material | Independent | Route | Run | Adoption |
|---|---|---|---|---|---|
| Avatar runtime (VRM0, framing, quality, optimizer, assets) | YES | YES | R2 / claude-opus (effort not bindable) | RSN-003 | USED |
| Flutter catalog + picker + host | YES | YES | R2 / claude-opus (effort not bindable) | RSN-004 | USED |

Fan-out Required: YES · Required 2 · Actual 2 · Compliance: PASS (effort UNVERIFIABLE).
Synthesis: model ids/files unified (CD-5); pubspec needs no change (directory entry); thumbnails need `.png` in the dispatcher allowlist (CD-8).

### Preconditions
- User approves this revision **and** the one-line allowlist change adding `.png` to `scripts/ccb/dispatch.py` (separate commit).
- Coordinator stages the Donut-Chan source into the offline deps cache (`$DEPS/Donut-Chan.vrm`, copied from `~/Downloads/Donut-Chan/`), sha256 recorded in T149.

### Steps and tasks
| Task | Step | REQ/AC | Depends | Class | Route | Allowed writes |
|---|---|---|---|---|---|---|
| T149 | P04 runtime + assets | REQ-216/217/218/220; AC-218..220 | — | E3 | gpt-6.2-sol / medium | `tools/avatar/src/{main,framing,models,pose}.js`, `tools/avatar/test/{framing,models,pose}.test.js`, `tools/avatar/optimize_vrm.py`, `tools/avatar/README.md`, `assets/avatar/{index.html,avatar.bundle.js,LICENSES.md,pixiv-sample.vrm,donut-chan.vrm,pixiv-sample.png,donut-chan.png,avatar.vrm(delete)}` |
| T150 | P05 Flutter catalog + picker | REQ-219, REQ-218 (Flutter side); AC-221, AC-222 | T149 | E3 | gpt-6.2-sol / medium | `lib/features/avatar/domain/avatar_model.dart`, `lib/features/avatar/avatar_licenses.dart`, `lib/features/avatar/presentation/{avatar_renderer,avatar_renderer_native,avatar_renderer_web,floating_avatar}.dart`, `lib/features/settings/presentation/{settings_screen,settings_avatar_model_page}.dart`, `lib/features/portfolio/presentation/portfolio_screen.dart`, `lib/core/security/secure_storage_helper.dart`, `lib/main.dart`, tests listed in T150 |

Serial (one writer per checkout): T149 → T150 → final integration (V4, analyze, web/apk/ios builds) → user device check.

### Verification
- T149: `node --test tools/avatar/test/`; `python3 -I -B tools/avatar/build.py --deps "$DEPS"`; `optimize_vrm.py check` for both models; coordinator browser render of both models (AC-218).
- T150: focused RED/GREEN widget tests on host, analyze, `flutter build web --no-pub`; final V4 `flutter test --no-pub`, apk/ios builds; iOS simulator check of switching.

### Risks
| ID | Risk | Mitigation |
|---|---|---|
| RISK-216 | Sparse re-encoding corrupts morphs | decode round-trip equality in `check`; visual expression check |
| RISK-217 | App size +~9 MB (Donut) and +1.6 MB (pixiv at 1024) | sparse morphs; thumbnail shrink |
| RISK-218 | MSAA + DPR 3 cost on low-end Android | small canvas, 30 fps cap, pause; user device check |
| RISK-219 | Donut-Chan 109 morph targets per face primitive heavier on GPU | observe on device; fall back to pixiv default |

## Revision 3 — per-part colour customization (2026-11-24)

Plan ID: PLAN-20261124-pnl-avatar-3d-r3
Status: APPROVED (user, 2026-11-24)
Implements: REQ-221..REQ-225; AC-223..AC-226. Decisions D-040..D-042, CD-9..CD-12.

### Planning workstreams
| Workstream | Material | Independent | Route | Run | Adoption |
|---|---|---|---|---|---|
| Runtime recolor + bridge | YES | YES | R2 / claude-opus (effort not bindable) | RSN-005 | USED |
| Flutter domain, storage, customize page | YES | YES | R2 / claude-opus (effort not bindable) | RSN-006 | PARTIAL (its "JS material tint" note superseded by texture colorize CD-9) |

Fan-out Required: YES · Required 2 · Actual 2 · Compliance: PASS (effort UNVERIFIABLE).

### Tasks (serial)
| Task | REQ/AC | Depends | Class | Route | Allowed writes |
|---|---|---|---|---|---|
| T151 runtime recolor | REQ-221, REQ-222; AC-223, AC-224 | — | E3 | gpt-6.2-sol / medium | `tools/avatar/src/{recolor,protocol,main}.js`, `tools/avatar/test/{recolor,protocol,models}.test.js`, `assets/avatar/avatar.bundle.js`, `tools/avatar/README.md` |
| T152 Flutter customize | REQ-223..REQ-225; AC-225, AC-226 | T151 + user pubspec action | E3 | gpt-6.2-sol / medium | listed in T152 |

### User action before T152
Add `flutter_colorpicker: ^1.1.0` under `dependencies:` in `pubspec.yaml`, run `flutter pub get`, commit (pubspec.lock / plugin registrants as generated).

### Verification
T151: node tests, bundle build, coordinator browser recolor check of both models. T152: RED/GREEN on host, analyze, web/apk/ios builds, V4, iOS simulator customize flow; user Android check.

### Risks
| ID | Risk | Mitigation |
|---|---|---|
| RISK-221 | Recolor jank on low-end Android while dragging (Donut top 5.2 Mpx) | cached luminance, changed parts only, 100 ms coalescing both sides |
| RISK-222 | Extra memory for caches (~15–20 MB worst case) | lazy per part; freed on teardown |
| RISK-223 | Hair highlights (emissive) keep original hue | accepted for now; revisit after visual check |

## Revision 3.1 — Donut-Chan part mapping and initial colours (2026-11-24)

Plan ID: PLAN-20261124-pnl-avatar-3d-r3b
Status: SUPERSEDED by revision 4 (never approved; T153/T154 carried over)
Implements: REQ-226..REQ-228; AC-227..AC-230. Decisions D-043, D-044, CD-13, CD-14.
Planning workstreams: remediation of revision 3 contracts; evidence gathered by coordinator probe (OBS-235..243); fan-out record of revision 3 (RSN-005/006, PASS) applies.

| Task | REQ/AC | Depends | Class | Route | Allowed writes |
|---|---|---|---|---|---|
| T153 runtime part rules | REQ-226; AC-227, AC-228 | T151, T152 PASS | E2 | gpt-6.2-sol / low | `tools/avatar/src/recolor.js`, `tools/avatar/test/recolor.test.js`, `tools/avatar/test/protocol.test.js`, `tools/avatar/test/models.test.js`, `tools/avatar/README.md`, `assets/avatar/avatar.bundle.js` |
| T154 Flutter parts + swatches | REQ-227, REQ-228; AC-229, AC-230 | T153 PASS | E2 | gpt-6.2-sol / low | `lib/features/avatar/domain/avatar_colors.dart`, `lib/features/avatar/domain/avatar_model.dart`, `lib/features/settings/presentation/settings_avatar_customize_page.dart`, `test/features/avatar/avatar_colors_test.dart`, `test/features/avatar/avatar_model_test.dart`, `test/features/settings/settings_avatar_customize_page_test.dart` |

Verification: T153 node tests + bundle rebuild + browser part check; T154 RED/GREEN on host, analyze, web build, V4, iOS simulator.

## Revision 4 — Donut-Chan part fix + outfit mixing (2026-11-24)

Plan ID: PLAN-20261124-pnl-avatar-3d-r4
Status: APPROVED (user, 2026-11-24)
Implements: REQ-226..REQ-233; AC-227..AC-234. Decisions D-043..D-046, CD-13..CD-19.

### Planning workstreams
| Workstream | Material | Independent | Route | Run | Adoption |
|---|---|---|---|---|---|
| Runtime outfit mixing | YES | YES | R2 / claude-opus (effort not bindable) | RSN-007 | USED |
| Flutter outfit tab + storage | YES | YES | R2 / claude-opus (effort not bindable) | RSN-008 | USED |
Fan-out Required: YES · Required 2 · Actual 2 · Compliance: PASS (effort UNVERIFIABLE). Synthesis: non-fatal `outfit` error code (runtime) ↔ Flutter must not hide on it; donor streamed after `modelLoaded`.

### Tasks (serial, one writer per checkout)
| Task | REQ/AC | Depends | Class | Route |
|---|---|---|---|---|
| T153 runtime part rules | REQ-226; AC-227, AC-228 | T151, T152 | E2 | gpt-6.2-sol / low |
| T154 Flutter parts + swatches | REQ-227, REQ-228; AC-229, AC-230 | T153 | E2 | gpt-6.2-sol / low |
| T155 runtime outfit mixing | REQ-229, REQ-230; AC-231, AC-232 | T153 | E4 | gpt-6.2-sol / high |
| T156 Flutter outfit tab | REQ-231..REQ-233; AC-233, AC-234 | T154, T155 | E3 | gpt-6.2-sol / medium |

T155 is E4 (high): interdependent skinning invariants (bind matrix, flip, bone policy), async donor state machine and disposal.

### Verification
Each task: RED then GREEN; T153/T155 node tests + bundle + coordinator browser checks; T154/T156 host Flutter tests, analyze, web build; final V4 + apk/ios builds + iOS simulator flow; user Android check.
