# Design Specification: PnL-reactive 3D avatar on the home screen

Status: READY_FOR_PLAN
Date: 2026-11-22
Tier: L
Decision Ledger: `docs/agents/decisions/2026-11-22-pnl-avatar-3d-decisions.md`

## 1. Objective

Requested outcome:
- An optional female anime 3D character floats on the home screen (PortfolioScreen), shows happy/sad expressions according to the account's headline PnL percentage, and reacts to touch (pat, petting stroke, poke, swipe-to-rotate).
- A Settings switch turns the character on/off (default off).

Success conditions:
- Mood follows D-032 thresholds, is neutral when data is unavailable or balance is hidden.
- Runs offline on iOS, Android, macOS and web with the bundled model.
- License credit for the model and libraries is visible in the app.

## 2. Current State

> Protected configuration (pubspec.yaml, lockfiles, platform plists/manifests/gradle, web/index.html) is not evidence. The coordinator read `pubspec.yaml` once during exploratory research before loading the baseline; that content is excluded from this specification.

### Observed Facts

| ID | Source | Symbol/Location | Observation |
|---|---|---|---|
| OBS-210 | `lib/features/portfolio/presentation/portfolio_screen.dart` | `_buildPortfolioData` ~L340-402 | `headlineRatio` is a local computed from live prices, cost view and `_costFinished`; only reachable in the `data:` branch of `portfolioAsyncValue.when` (~L290-312). |
| OBS-211 | same | L28, ~L224, ~L254-256 | `hideBalanceProvider` (`StateProvider<bool>`) is the live hidden state. |
| OBS-212 | same | ~L69-72 | 5 s `Timer.periodic` triggers rebuilds. |
| OBS-213 | same | ~L226-236 | `Scaffold > SafeArea > NavigationContentFrame > Column`. |
| OBS-214 | `lib/core/navigation/main_navigation_shell.dart` | ~L45-54, ~L96-104 | Only the selected tab is built (switch + `KeyedSubtree`); switching tabs disposes PortfolioScreen. |
| OBS-215 | `lib/core/navigation/navigation_content_frame.dart` | ~L28-49 | Bottom padding reserves the floating navigation bar height. |
| OBS-216 | `lib/core/security/secure_storage_helper.dart` | keys ~L171-177, getters ~L302-311, `saveAppTextScale` ~L342 | Bool settings persisted as `'true'/'false'` strings. |
| OBS-217 | `lib/main.dart` | `AppStartupData` L27, `initializeAppStartup` L49, `WebStorageHelper` L379 | Startup preloads settings into provider overrides; web overrides every storage getter/setter with SharedPreferences. |
| OBS-218 | `lib/features/settings/presentation/settings_screen.dart` | providers L24-27, `_loadSavedPreferences` ~L73-102, hide-balance `SwitchListTile` ~L596-631 | Pattern to copy for the new switch. Strings are hardcoded Vietnamese. |
| OBS-219 | `lib/features/strategy/presentation/strategy_screen.dart` | ~L30-47 | Existing `WidgetsBindingObserver` lifecycle pattern. |
| OBS-220 | `lib/core/network/backend_data_client.dart` L6 | conditional import | Repository uses `if (dart.library.html)` conditional imports. No file in `lib/` imports `dart:html` or `package:web`. |
| OBS-221 | SUPERSEDED by D-035 — Seed-san VRM meta (vrm-c/vrm-specification) | `VRMC_vrm.meta` | Female anime model; commercial use by corporation, redistribution and modification allowed; `creditNotation: required`; VRM Public License 1.0. Presets include happy, sad, angry, relaxed, surprised, neutral, blink, lookAt; has VRMC_springBone (28 joints). 10.9 MB; 15 PNG textures (11 × 1024²); ~45k triangles. |
| OBS-225 | `VRM1_Constraint_Twist_Sample.vrm` meta (vrm-c/vrm-specification, sha256 12c2b97e…31a2) | `VRMC_vrm.meta` | Female, long brown hair, anime style (visually verified in browser render 2026-11-22). (c) 2022 pixiv Inc.; VRM Public License 1.0; commercialUsage corporation; redistribution and modification allowed; creditNotation unnecessary. Presets happy, sad, angry, relaxed, surprised, neutral, blink, lookAt; VRMC_springBone, VRMC_node_constraint. 10.8 MB source; 19 PNG; optimized to ~3.9 MB. |
| OBS-222 | npm registry 2026-11-22 | — | three 0.187.0; @pixiv/three-vrm 3.5.5 (peer three ≥0.137). IIFE bundle with GLTFLoader + VRMLoaderPlugin ≈ 943 KB min / 239 KB gzip. |
| OBS-223 | pub.dev 2026-11-22 | webview_flutter 4.14.1 | Supports android, ios, macos; no web implementation. |
| OBS-224 | local toolchain | — | node v26.8.2, npm 12.2.1, macOS `sips` available; Python Pillow not installed. Flutter 3.47.5. |

## 3. Scope

### In Scope
- Bundled web runtime (HTML + one IIFE bundle + optimized VRM + license file) and its build/optimize tooling and pure-module tests.
- Mood derivation, settings persistence (native + web), Settings switch + credit, license registry entries.
- Floating draggable host on PortfolioScreen; native WebView host and web iframe host; lifecycle pause; pointer forwarding; haptics.

### Out of Scope
- Persisting drag position (CD-2); multiple characters / model picker; sound/voice; `.vrma` animation clips; Windows/Linux; changing PnL math.

## 4. Clarifications and Decisions

Open questions: N/A
Resolved decisions: D-030, D-031, D-032, D-033, D-034 (+ coordinator design decisions CD-1..CD-4)
Authorized assumptions: N/A

## 5. Requirements

### REQ-210 — Mood derivation
The system MUST map the headline ratio (percent) to `AvatarMood { strongHappy, mildHappy, neutral, mildSad, strongSad }`:
- ratio null, NaN or infinite → neutral; hidden == true → neutral;
- |r| ≤ 1 → neutral; 1 < r < 5 → mildHappy; r ≥ 5 → strongHappy; −5 < r < −1 → mildSad; r ≤ −5 → strongSad.
Inputs: `double? ratioPercent`, `bool hidden`. Output: `AvatarMood`. Pure function, no side effects.

### REQ-211 — Setting
The system MUST provide a persisted bool `AVATAR_ENABLED` (default false) loaded at startup into `avatarEnabledProvider`, saved on toggle, on native (secure storage) and web (`WebStorageHelper`, SharedPreferences). Read failure → false. Save failure → switch reverts and a SnackBar shows "Không lưu được cài đặt".
Settings shows a `SwitchListTile` "Nhân vật 3D" / subtitle "Hiển thị nhân vật biểu cảm theo lãi/lỗ" in the "BẢO MẬT & TRẢI NGHIỆM" card, followed by the credit line "Nhân vật 3D: VRM1_Constraint_Twist_Sample © 2022 pixiv Inc. (VRM Public License 1.0)".

### REQ-212 — Home host
When the setting is on, PortfolioScreen MUST show a floating avatar of 160×220 logical px (scaled ×0.8 when screen width < 360), default anchored bottom-right with 16 px margin inside the `NavigationContentFrame`, draggable by long-press-drag and clamped inside the frame. When off, no WebView/iframe is created. On iOS/Android/macOS it uses `webview_flutter`; on web an iframe via `HtmlElementView`.
Mood input: headline ratio from the existing computation (extracted to a private helper without changing its math) when data is present; neutral during loading/error/no credentials; neutral whenever `hideBalanceProvider` is true. Only the mood enum crosses the bridge, never amounts or ratios.
The host MUST be created once per screen lifetime (periodic refresh must not recreate it), send `setMood` only on change, send `setPaused(true)` on app lifecycle paused/inactive/hidden and `setPaused(false)` on resumed, send `setReducedMotion` from `MediaQuery.disableAnimations`.
Until `modelLoaded` the area is transparent; on `error` the overlay hides (CD-4).
Semantics label "Nhân vật 3D"; hit target ≥ 48 dp.

### REQ-213 — Interaction
Flutter MUST forward pointer samples over the avatar (down/move/up/cancel, CSS px relative to the view, timestamp ms; moves throttled to ≤ 30 Hz) to the page (CD-1). Long-press-drag moves the widget and is not forwarded. The page classifies (thresholds in §9) and responds:
- pat (tap in head region) → happy + eyes closed + head tilt ~1.2 s;
- stroke on head (petting) → relaxed/happy blend + head sway while active, ends 600 ms after last stroke;
- poke (tap in body region) → surprised ~0.8 s;
- swipe (outside head) → yaw rotation by dx·0.01 rad, damped back to 0;
- look-at follows pointer while down.
After the reaction the PnL mood resumes. The page emits `interaction{kind}` (debounced ≥150 ms); Flutter calls `HapticFeedback.lightImpact()` (no-op where unsupported).

### REQ-214 — Runtime and assets
`assets/avatar/` MUST contain `index.html` (classic `<script src="avatar.bundle.js">`, CSP `default-src 'self' file:; script-src 'self' file:; img-src 'self' file: blob: data:; connect-src 'self' file: blob: data:` (`file:` because native pages load from file URLs), transparent background), `avatar.bundle.js` (IIFE of three 0.187.0 + GLTFLoader + @pixiv/three-vrm 3.5.5 + app runtime), `avatar.vrm` (all images downscaled to ≤512², image/texture indices unchanged, all `VRMC_*` JSON extensions identical to the source), `LICENSES.md`. No network access at runtime. Renderer: alpha, no antialias, pixelRatio ≤ 2, 30 fps cap, render loop stopped while paused or document hidden, delta clamped ≤ 1/15 s. Procedural idle: breathing, gentle sway, auto blink. Moods crossfade (exponential approach). Strong moods add motion: strongHappy small bounce; strongSad head down.
Model delivery: web page fetches `avatar.vrm` relatively; native pages receive bytes from Flutter in base64 chunks (`loadModelChunk`).

### REQ-215 — Licenses
`LicenseRegistry` MUST include three.js (MIT), @pixiv/three-vrm (MIT) and VRM1_Constraint_Twist_Sample (VRM Public License 1.0, © 2022 pixiv Inc.) so they appear in Flutter's license page; `LICENSES.md` ships the same texts.

## 6. Data Contract

N/A — no persisted data except the bool `AVATAR_ENABLED` (absent → false).

## 7. Cross-Layer Mapping (Flutter ⇄ page bridge, envelope `{"v":1,"type":...}`)

| Dir | type | fields |
|---|---|---|
| F→P | `setMood` | `mood`: `strongHappy`\|`mildHappy`\|`neutral`\|`mildSad`\|`strongSad` |
| F→P | `setPaused` | `paused`: bool |
| F→P | `setReducedMotion` | `on`: bool |
| F→P | `pointer` | `phase`: `down`\|`move`\|`up`\|`cancel`, `x`, `y` (CSS px), `t` (ms) |
| F→P | `loadModelChunk` | `i`, `n`, `b64` (native only) |
| P→F | `ready` | `version` |
| P→F | `modelLoaded` | — |
| P→F | `error` | `code`, `message` |
| P→F | `interaction` | `kind`: `pat`\|`pettingStart`\|`pettingEnd`\|`poke`\|`swipe` |

Transport: native F→P `runJavaScript("window.avatar.receive(<json-string>)")`, P→F JavaScriptChannel `AvatarChannel`. Web: `postMessage` both ways with `origin === location.origin` and source checks. Unknown `v`/`type` or malformed → page emits `error{code:"protocol"}` and ignores; Flutter ignores unknown messages. No `eval`.

## 8. Proposed Design

```text
PortfolioScreen.build
  ├─ existing content (unchanged)
  └─ if avatarEnabled: FloatingAvatar(mood)            (Stack inside NavigationContentFrame)
        └─ AvatarRenderer (provider-injected factory)
             ├─ native: WebViewController.loadFlutterAsset('assets/avatar/index.html')
             └─ web:    iframe src 'assets/assets/avatar/index.html'
page: bridge.js ⇄ main.js (three + three-vrm) ← mood.js / gesture.js / protocol.js (pure)
```

Dart files: `lib/features/avatar/domain/avatar_mood.dart`, `lib/features/avatar/presentation/{avatar_renderer.dart, avatar_renderer_native.dart, avatar_renderer_web.dart, floating_avatar.dart}`.

## 9. Interfaces and Contracts

Gesture thresholds (CSS px, page side, pure `gesture.js`): tap < 250 ms and travel < 10 px; stroke = start in head region, ≥ 2 horizontal reversals with legs ≥ 12 px within 1.5 s; swipe = start outside head, |dx| > 24 and |dx| > 1.5·|dy|. Head region: circle around projected head bone (radius = 0.11 m projected); body region: capsule chest→hips.

Mood → expression targets (pure `mood.js`): strongHappy {happy:1.0}; mildHappy {happy:0.5}; neutral {relaxed:0.15}; mildSad {sad:0.5}; strongSad {sad:1.0}. Reactions temporarily override.

Dart: `AvatarMood avatarMoodFor(double? ratioPercent, {required bool hidden})`; `abstract class AvatarRenderer` with `Widget build`, `setMood`, `setPaused`, `setReducedMotion`, `sendPointer`, `Stream<AvatarEvent> events`, `dispose`; `avatarRendererFactoryProvider` overridable in tests.

External configuration requirement: see §17.

## 10. Invariants

- INV-210: PnL/headline math and displayed values are unchanged.
- INV-211: No ratio/amount leaves Dart; only the mood enum.
- INV-212: Setting off ⇒ zero WebView/iframe instances.
- INV-213: No runtime network access by the page.
- INV-214: Existing settings (hide balance, biometrics, text scale, timezone) unaffected.

## 11. Edge Cases

- EDGE-210: ratio exactly ±1 → neutral; exactly ±5 → strong.
- EDGE-211: balance hidden toggled while mood strong → neutral immediately.
- EDGE-212: scope/account switch → screen re-keyed, avatar recreated neutral until data.
- EDGE-213: tab switch → host disposed; returning recreates it.
- EDGE-214: app backgrounded → paused; resumed → continues, springs not exploding.
- EDGE-215: WebGL unavailable / context lost / model parse error → overlay hidden (CD-4).
- EDGE-216: narrow screen < 360 → ×0.8 size; drag clamped above the nav bar.
- EDGE-217: reduced motion → no bounce/sway; expressions still change.
- EDGE-218: `setBackgroundColor` unsupported on a platform → caught, continue.
- EDGE-219: periodic 5 s refresh → host not recreated, no duplicate `setMood`.

## 12. Failure Semantics

| Failure | Response | Allowed | Forbidden |
|---|---|---|---|
| Setting read fails | treat as off | log | crash |
| Setting save fails | revert switch + SnackBar | — | silent desync |
| Page/model load error | hide overlay | debug log | retry loop, crash |
| Malformed bridge message | ignore (+ page `error{protocol}`) | — | eval |

## 13. RED / GREEN Behavioral Contract

- RED-146: page pure modules: `protocol.parse` rejects `{v:2}` / unknown type / non-JSON; gesture classifier returns no `pat` for a 300 ms hold or a 15 px drag; `mood.targets('bogus')` falls back to neutral.
- GREEN-146: `mood.targets` values per §9; tap 120 ms/3 px in head → `pat`; 3 reversals × 20 px in 900 ms from head → `pettingStart`; dx 60/dy 10 outside head → `swipe`; bundle builds; optimized VRM keeps VRMC extensions and all images ≤ 512².
- RED-147: `avatarMoodFor(6, hidden:true)` → neutral; `avatarMoodFor(null)` → neutral; `1.0` → neutral; NaN → neutral; startup read failure → avatarEnabled false; save failure reverts switch.
- GREEN-147: 1.0001 → mildHappy; 5 → strongHappy; −5 → strongSad; −4.99 → mildSad; toggle on persists `AVATAR_ENABLED=true` (native + web helper) and restores at startup; credit text present.
- RED-148: setting off → no renderer created; loading/error state → mood neutral; hidden → neutral; 5 s refresh does not recreate renderer (factory count 1); malformed/unknown page message ignored; `error` event hides overlay.
- GREEN-148: setting on with data yielding ratio 6% → renderer receives `setMood(strongHappy)` once; lifecycle paused → `setPaused(true)`; drag past edges stays clamped; `interaction` event → haptic call; pointer tap forwarded as down/up.

## 14. Performance Contract

Target: ≤ 30 fps cap, pixelRatio ≤ 2, rendering stopped when paused/hidden; VRM asset ≤ 6 MB after optimization; bundle ≤ 1.1 MB. Measurement: file sizes (automated); fps/thermal on a low-end Android device (manual, user-run). No automated fps gate.

## 15. Compatibility

Additive; setting defaults off so existing users see no change. Web build gains ~6–7 MB assets fetched only when the iframe loads.

## 16. Security and Permissions

Local assets only; CSP restricts scripts to self; postMessage origin-checked; no PnL values transmitted to the page. No new OS permissions.

## 17. Protected Configuration / Environment Actions

Required external actions (user-owned; agents do not edit):

1. Target: `pubspec.yaml` — section `dependencies:` — add
   ```yaml
   webview_flutter: ^4.14.1
   web: ^0.5.1
   ```
   Reason: REQ-212 native + web hosts. Validation: `flutter pub get`. Blocks T148 build/verification: YES.
2. Target: `pubspec.yaml` — section `flutter:` → `assets:` (create the `assets:` list if absent) — add
   ```yaml
       - assets/avatar/
   ```
   Reason: REQ-214. Validation: `flutter pub get`; app finds `assets/avatar/index.html`. Blocks T148 verification: YES.
3. iOS: `cd ios && pod install` after (1) if the Flutter tool does not run it automatically. macOS: same in `macos/`. No plist/entitlement change expected; if macOS build reports a sandbox/network error, stop and report (no change planned).

## 18. Rollout / Rollback

Rollout: ships default off. Rollback: users switch off; code rollback = revert the feature files and remove the two pubspec entries (user-owned).

## 19. Acceptance Criteria

- AC-210: Given ratios {null, NaN, 0.5, 1, 1.0001, 4.99, 5, 12, −1, −1.0001, −4.99, −5, −20}, mood equals the REQ-210 table.
- AC-211: Given balance hidden, mood is neutral for any ratio.
- AC-212: Given a fresh install, the switch is off and no avatar renders; toggling on persists and survives restart (native and web).
- AC-213: Given the switch on and data loaded, the home screen shows the avatar and the renderer receives the derived mood; loading/error → neutral; refresh does not recreate it.
- AC-214: Given iOS, Android, macOS and web builds, the avatar loads offline and reacts to mood changes (manual device check, user-run).
- AC-215: Pat/stroke/poke/swipe produce the REQ-213 reactions and a haptic on supported devices (manual) and the page classifier passes its automated cases.
- AC-216: Settings shows the credit line; Flutter license page lists three.js, three-vrm, VRM1_Constraint_Twist_Sample.
- AC-217: Optimized `avatar.vrm` ≤ 6 MB, all images ≤ 512², VRMC extensions preserved; bundle ≤ 1.1 MB.

## 20. Requirement Traceability

| Requirement | AC | Design | RED/GREEN |
|---|---|---|---|
| REQ-210 | AC-210, AC-211 | §5, §9 | RED-147 / GREEN-147 |
| REQ-211 | AC-212, AC-216 | §5 | RED-147 / GREEN-147 |
| REQ-212 | AC-213, AC-214 | §8, §9 | RED-148 / GREEN-148 |
| REQ-213 | AC-215 | §7, §9 | RED-146/148 / GREEN-146/148 |
| REQ-214 | AC-214, AC-217 | §5, §14 | RED-146 / GREEN-146 |
| REQ-215 | AC-216 | §5 | GREEN-147 |

## 21. Completion Gate

- [x] no unresolved material question
- [x] no silent assumption (CD-1..CD-4 presented for approval)
- [x] requirements/contracts are unambiguous
- [x] edge/failure semantics defined
- [x] RED/GREEN expected outcomes independently derived
- [x] acceptance criteria complete
- [x] traceability complete
- [ ] protected configuration/environment contents were not read — **exception**: `pubspec.yaml` was read once during pre-baseline research; excluded from evidence and disclosed to the user
- [x] required external configuration actions fully specified

## 22. Change Log

| Revision | Change | Reason |
|---|---|---|
| 1.2 | Model switched to pixiv `VRM1_Constraint_Twist_Sample` (D-035); asset renamed `avatar.vrm`; credit text updated | Visual audit of T146 showed Seed-san is not clearly female (D-034). |
| 1.1 | §17 `web` constraint `^1.1.0` → `^0.5.1`; `LICENSES.txt` → `LICENSES.md`; build script `build.sh` → `build.py`; JS tests `*.test.js` | `flutter pub get` failed: `web_socket_channel ^2.4.4` requires `web ^0.5.0` (user report); CCB dispatcher allowlist accepts only `.py/.js/.html/.md/.vrm/.dart` for these files. No requirement change. |

## Revision 2 — model picker, Donut-Chan, render quality (2026-11-22)

Status: READY_FOR_PLAN. Decisions D-037..D-039, CD-5..CD-8. Evidence: MAN-148 Android (user): APK runs, avatar works; blurry details and jagged silhouette edges (cause: 512 px textures — eyes/face sources are 1024 px — `antialias:false`, pixelRatio ≤ 2 on 2.75–3.5 DPR screens). Reasoning fan-out RSN-003 (runtime) and RSN-004 (Flutter) collected.

### Observed facts
| ID | Source | Observation |
|---|---|---|
| OBS-226 | `Donut-Chan.vrm` (27.3 MB) | VRM 0.x (`extensions.VRM`), 72 blendshape groups (joy/sorrow/fun/angry presets; custom `Surprised`), 24 spring groups, ~56.6k tris, 33 PNG (many 2048²), morph targets dense (110 of 218 morph accessors all-zero). |
| OBS-227 | three-vrm 3.5.5 | `VRMUtils.rotateVRM0` sets `vrm.scene.rotation.y = π` for metaVersion "0"; VRM0 normalized bones keep the model's local frame, so X/Z rotations must be negated for VRM0; expression presets joy→happy, sorrow→sad, fun→relaxed mapped by the loader; `lookAt.faceFront` handled. |
| OBS-228 | local test render (current bundle) | Donut-Chan faces away and arms point up; framing slightly different (head 1.368 m, hips 0.887 m vs pixiv 1.395/0.908). |
| OBS-229 | optimizer at 1024 (copy) | pixiv 10.78 → 5.48 MB; Donut-Chan 27.3 → 14.76 MB (≈9.8 MB non-image, mostly dense morph data; sparse estimate ≈ 8–8.5 MB total). |

### Requirements
- REQ-216 (quality): renderer `antialias:true`, pixelRatio `min(dpr,3)`; all bundled models re-optimized with `--max-side 1024`; embedded thumbnail image may be shrunk to 256 px.
- REQ-217 (multi-model runtime): the page supports VRM 0.x and 1.0. For metaVersion "0": base yaw π (combined with gesture yaw, not overwritten), sign `s=-1` applied to every procedural X/Z bone rotation (chest pitch, head pitch/tilt/sway, upper/lower arm rest pose); `surprised` falls back to a custom expression named `Surprised`. Camera framing computed after load from head (H) and hips (P) world Y: S=H−P, top=H+0.73·S, bottom=P−0.20·S, centre and half-height from these, width from aspect; `camera.updateMatrixWorld()`/`updateProjectionMatrix()` after changes. Pure modules `framing.js`, `models.js`, `pose.js` (rest-pose/sign) are unit-tested.
- REQ-218 (selection transport): web iframe URL `index.html?model=<id>`; the page maps `id` through an allowlist `{ 'pixiv-sample': 'pixiv-sample.vrm', 'donut-chan': 'donut-chan.vrm' }` (id must match `^[a-z0-9-]{1,32}$`); unknown/missing → `pixiv-sample`. Native: Flutter loads `assets/avatar/<file>` and sends chunks (unchanged protocol).
- REQ-219 (Flutter catalog + picker): `AvatarModel {id, name, file, thumbnail, credit, licenseText}` catalog with `avatarModelById(id)` → default for unknown; persisted `AVATAR_MODEL_ID` (native + web helper, startup override, read failure → default); Settings row "Chọn nhân vật" under the "Nhân vật 3D" switch (disabled while the avatar is off) showing current model name; the credit line follows the selected model; picker page lists every model with 48 px thumbnail (`errorBuilder` → icon), name, credit/license, check icon + `Semantics(selected)`, optimistic save with rollback + SnackBar "Không lưu được cài đặt"; LicenseRegistry entry per model; home host keyed by model id so switching recreates the renderer with the new model.
- REQ-220 (assets): `assets/avatar/` contains `pixiv-sample.vrm`, `donut-chan.vrm`, `pixiv-sample.png`, `donut-chan.png`, bundle, `index.html`, `LICENSES.md` (adds Donut-Chan, Public Domain, Kana Fuyuko); `avatar.vrm` removed. Size limits: pixiv ≤ 6 MB, Donut-Chan ≤ 10 MB.

### Acceptance criteria
- AC-218: browser render of each model faces the camera, arms down at rest, upper body framed with the head near the top (coordinator visual check) — both models.
- AC-219: page unit tests: framing reproduces pixiv frame (centre 1.28, half 0.47 ±1e-3) and keeps Donut-Chan head-top in view; model id validation rejects `../x`, `avatar.vrm`, upper case, empty, unknown → default; VRM0 rest pose has negated X/Z.
- AC-220: `optimize_vrm.py check` passes for both outputs against their sources (extensions preserved, images ≤ 1024, sparse morph decode equals source, size limits).
- AC-221: Settings: picker lists both models with credits; selecting Donut-Chan persists (native + web) and survives restart; unknown stored id → pixiv; credit line follows selection; license page lists both models.
- AC-222: home: changing the selected model disposes the old renderer and creates a new one with the new model file; Android/iOS device check (user) shows sharper edges.

### RED / GREEN
- RED-149: optimizer `check` on a Donut-Chan output fails today ("Required VRMC extensions are missing"); framing/models/pose tests fail before the modules exist.
- GREEN-149: node tests pass; both models optimized and checked; bundle rebuilt.
- RED-150: unknown stored model id / failed save / missing thumbnail cases (fallbacks asserted).
- GREEN-150: selection persists and recreates the host with the new file; picker semantics/check icon.

### Protected configuration
None — `pubspec.yaml` already declares the `assets/avatar/` directory, which covers the new files.

## Revision 3 — per-part colour customization (2026-11-24)

Status: READY_FOR_PLAN. Decisions D-040..D-042, CD-9..CD-12. Fan-out RSN-005 (runtime recolor) and RSN-006 (Flutter customize) collected.

### Observed facts
| ID | Source | Observation |
|---|---|---|
| OBS-230 | both VRMs, material names | VRoid naming: hair `_HAIR`, iris `EyeIris`, top `Tops_`, bottom `Bottoms_`/`Onepiece_`, shoes `Shoes_`, accessory `Accessory_` (Donut only); `EyeWhite`/`EyeHighlight` separate. |
| OBS-231 | `FaceMouth` texture (both) | Teeth, tongue, mouth interior — not lips. |
| OBS-232 | GLTFLoader / three r187 | map and shadeMultiplyTexture of a material are the same Texture object; outline clones share it; textures must be replaced via `orig.clone()` + new `Source(canvas)` (assigning `image` on a clone corrupts the shared source). Blob-URL images are origin-clean (`getImageData` allowed). |
| OBS-233 | texture counts | worst part Donut top 5 × 1024² (~5.2 Mpx); whole Donut ~11 Mpx. |
| OBS-234 | scratch spike | colorize result acceptable on both models. |

### Requirements
- REQ-221 (runtime recolor): pure `recolor.js` — `partForMaterial(name)`, `parseHex`, `luminance(pixels)` → `{lum, mean}` (mean over alpha > 8, fallback 128), `colorize(pixels, lum, mean, rgb)` (alpha unchanged, clamp 255). `main.js` keeps `colors` state; for each changed part, every original base texture of matching materials is recolored once (cache per original texture: canvas, imageData, lum, mean, recolored clone) and assigned to `map` and `shadeMultiplyTexture`; reset restores originals; applied after load before the first frame; updates coalesced ≤ 1 per 100 ms; parts without materials ignored; caches freed on teardown.
- REQ-222 (bridge): `setColors {colors}`; protocol accepts only keys hair/eyes/top/bottom/shoes/accessory with `^#[0-9a-fA-F]{6}$`, no extra fields; `{}` valid.
- REQ-223 (domain + storage): `AvatarPart` enum with labels Tóc/Mắt/Áo/Quần-Váy/Giày/Phụ kiện; `AvatarModel.parts` (pixiv: hair, eyes, top, bottom, shoes; donut-chan: + accessory); immutable `AvatarColors` with value equality and tolerant JSON; `AVATAR_COLORS` persisted native + web, preloaded at startup into `avatarColorsProvider` (`Map<String, AvatarColors>`); corrupt data → empty, startup continues.
- REQ-224 (renderer + home): `AvatarRenderer.setColors(AvatarColors)` (native/web keep latest and resend after ready); shared non-floating `AvatarView` extracted from `FloatingAvatar`; home passes the selected model's saved colours; `setColors` sent only when colours change.
- REQ-225 (customize page): button per model row in the picker (does not change selection) → `SettingsAvatarCustomizePage(modelId)`: live 3D preview (height clamp(240, 40% screen, 360)), part chips from `model.parts` with swatch + Semantics label, `HueRingPicker` (no alpha), draft colours sent to the preview throttled to 100 ms (trailing value), "Lưu" persists (rollback + SnackBar on failure), "Khôi phục mặc định" with confirm, back with unsaved changes confirms discard; scrollable for text scale.

### Acceptance criteria
- AC-223: node tests for recolor/protocol pass; GLB coverage test: every declared part matches ≥ 1 material, pixiv has no accessory.
- AC-224: coordinator browser check: setColors recolors hair/eyes/top/bottom/shoes on pixiv and + accessory on Donut; `{}` restores originals; whites/highlights of eyes unchanged.
- AC-225: Flutter tests: JSON tolerance, per-model isolation, save/rollback, reset, throttled preview calls, picker button navigation, startup restore native/web, home receives saved colours.
- AC-226: iOS simulator: customize Pixiv Sample and Donut-Chan, save, home shows the colours after restart (coordinator); Android device check (user).

### Protected configuration (user-owned)
`pubspec.yaml` → `dependencies:` add `flutter_colorpicker: ^1.1.0`; run `flutter pub get`. Blocks T152 build: YES.
