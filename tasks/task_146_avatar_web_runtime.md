# Task 146 — Avatar page runtime and bundled assets

Status: PASS
Agent Role: implementation_executor
Executor Class: E3
Target Model: gpt-6.2-sol
Target Effort: medium
Target Route: gpt-6.2-sol / medium
Routing Policy: EXECUTOR_ROUTING_POLICY.json v3 (OptCodex v1.5.1)
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Specification: `docs/agents/specs/2026-11-22-pnl-avatar-3d-design.md`
Plan: `docs/agents/plans/2026-11-22-pnl-avatar-3d.md`
Plan Steps: P01
Requirements: REQ-213 (page side), REQ-214, REQ-215 (LICENSES.md)
Acceptance Criteria: AC-215 (automated part), AC-217
Decisions: D-033, D-034, CD-1, CD-3, CD-4

## 1. Dispatch Compliance

The CCB dispatcher passes `--model gpt-6.2-sol` and `model_reasoning_effort=medium`. `UNVERIFIABLE` is a valid state.

Dispatch Route Status: PENDING
Requested Model: PENDING
Requested Effort: PENDING
Observed Effective Model: unavailable
Observed Effective Effort: unavailable

## 2. Objective

Create the self-contained local web page that renders the Seed-san VRM with three.js + @pixiv/three-vrm, reacts to the bridge messages in spec §7, and the reproducible tooling that produces the bundled assets.

Done when: RED-146 then GREEN-146 pass, `assets/avatar/` contains the four files, sizes meet AC-217.

## 3. Preconditions

Predecessors: none. Tools: node ≥ 20, npm, python3 (stdlib only), macOS `sips`.
Offline dependency cache (pre-staged by the coordinator, read-only for you): `DEPS=/private/tmp/claude-501/-Users-locnguyen-projects-trading-balance-f/581c8564-b131-4cc5-b169-666a1740764c/scratchpad/avatar-deps` contains `node_modules/` (three 0.187.0, @pixiv/three-vrm 3.5.5, esbuild 0.25.10 with darwin-arm64 binary) and `Seed-san.vrm` (sha256 `624d0d554bc205bbdc33e22a68a2c3c20edebb3e573011ead8878a65e5329b23`). Use `--deps "$DEPS"` / `--source "$DEPS/Seed-san.vrm"`; do not use the network.

File naming follows the CCB dispatcher allowlist (`.py .js .html .md .vrm` only): build script is Python, tests are `*.test.js` (ES module syntax; Node auto-detects), licenses file is Markdown.

## 4. Allowed Scope

- `tools/avatar/src/protocol.js` — `parse(raw) -> {ok, msg|error}` for spec §7 envelope v1; F→P types only; no eval.
- `tools/avatar/src/mood.js` — `MOODS`, `targets(mood)` per spec §9 (unknown → neutral), `step(current, target, dt, rate)` exponential approach clamped 0..1, `motion(mood)` → `{bounce, headPitch}` (strongHappy bounce > 0; strongSad headPitch < 0; others 0).
- `tools/avatar/src/gesture.js` — `createClassifier({now})` consuming `{phase,x,y,t,region}` samples and emitting `pat|pettingStart|pettingEnd|poke|swipe` with spec §9 thresholds; 150 ms debounce for emitted interactions; `pettingEnd` 600 ms after last stroke leg.
- `tools/avatar/src/hit.js` — region from projected head/chest/hips screen positions (head circle, chest→hips capsule).
- `tools/avatar/src/bridge.js` — `send(msg)` → `window.AvatarChannel.postMessage(JSON.stringify(msg))` if present else `parent.postMessage(msg, location.origin)`; `window.avatar.receive(json)` + `message` listener with `e.origin === location.origin && e.source === window.parent`.
- `tools/avatar/src/main.js` — WebGLRenderer `{alpha:true, antialias:false, powerPreference:'low-power'}`, `setPixelRatio(Math.min(devicePixelRatio,2))`, clear alpha 0; fixed camera framing upper body; 1 directional + 1 ambient light; GLTFLoader + VRMLoaderPlugin, `VRMUtils.removeUnnecessaryVertices`, `VRMUtils.combineSkeletons`, `frustumCulled=false`; model source: if `window.AvatarChannel` exists wait for `loadModelChunk` messages (reassemble base64 → Uint8Array → `parseAsync`), else `fetch('seed.vrm')`; procedural idle (breathing chest, gentle sway, auto blink every 3–6 s); mood crossfade via `mood.step`; reactions per REQ-213 overriding then releasing; look-at target from pointer while down; yaw from swipe damped to 0; petting = head bone sway; `setPaused` and `visibilitychange` stop/start rAF; 30 fps accumulator; delta ≤ 1/15 s; `springBoneManager.reset()` after resume; `webglcontextlost` / load failure → `send({v:1,type:'error',...})`; emits `ready{version:1}` on DOMContentLoaded and `modelLoaded` after first frame; `setReducedMotion` disables bounce/sway.
- `tools/avatar/src/entry.js` — imports main.
- `tools/avatar/build.py` — stdlib only. `python3 -I tools/avatar/build.py [--deps DIR]`: without `--deps`, create a temp dir and run `npm install --prefix TMP --no-save --ignore-scripts --no-audit --no-fund three@0.187.0 @pixiv/three-vrm@3.5.5 esbuild@0.25.10`; with `--deps`, use `DIR/node_modules`. Run the esbuild binary (`node DIR/node_modules/esbuild/bin/esbuild`) on `tools/avatar/src/entry.js` with `--bundle --format=iife --minify --target=es2019 --legal-comments=eof` and `NODE_PATH`/`--resolve-extensions` so imports resolve from the deps dir → `assets/avatar/avatar.bundle.js`; print byte size; non-zero exit on failure. Pinned versions are constants at the top of the file.
- `tools/avatar/optimize_vrm.py` — stdlib only. `optimize SRC DST`: parse GLB, for each PNG image with a side > 512 px write to temp, `sips -Z 512`, replace bytes, rebuild BIN chunk with 4-byte aligned bufferViews, update `buffers[0].byteLength`, keep all indices; `check DST [--source SRC]`: assert valid GLB, every image ≤ 512², and `extensions.VRMC_vrm`, `VRMC_springBone`, `VRMC_materials_mtoon` (materials) JSON equal to the source when `--source` is given. Without a local source, documented download URL: `https://raw.githubusercontent.com/vrm-c/vrm-specification/master/samples/Seed-san/vrm/Seed-san.vrm`.
- `tools/avatar/test/protocol.test.js`, `mood.test.js`, `gesture.test.js` (`node --test tools/avatar/test/`).
- `tools/avatar/README.md` — pinned versions, rebuild commands, model source URL, license.
- `assets/avatar/index.html` — transparent body/canvas, `<meta http-equiv="Content-Security-Policy" content="default-src 'self'; script-src 'self'; img-src 'self' blob: data:; connect-src 'self' blob: data:">`, `<script src="avatar.bundle.js"></script>` (classic).
- `assets/avatar/avatar.bundle.js`, `assets/avatar/seed.vrm` (generated), `assets/avatar/LICENSES.md` (three.js MIT full text, @pixiv/three-vrm MIT full text, "Seed-san © VirtualCast, Inc. — VRM Public License 1.0 — https://vrm.dev/licenses/1.0/").

## 5. Forbidden Scope

Do not read/modify protected files (pubspec.yaml, lockfiles, any package.json in the repo, platform configs, web/index.html). Do not create a `package.json` or `node_modules` inside the repository. No Dart changes. No runtime CDN URLs in assets. No other files.

## 6. Executor Contract

Implement §4 in order: pure modules + tests → hit/bridge/main/entry → build.py → optimize_vrm.py → index.html/LICENSES/README → run `python3 -I tools/avatar/build.py --deps "$DEPS"` and `python3 -I tools/avatar/optimize_vrm.py optimize "$DEPS/Seed-san.vrm" assets/avatar/seed.vrm`.

Exact allowed write files (manifest): `tools/avatar/src/protocol.js`, `tools/avatar/src/mood.js`, `tools/avatar/src/gesture.js`, `tools/avatar/src/hit.js`, `tools/avatar/src/bridge.js`, `tools/avatar/src/main.js`, `tools/avatar/src/entry.js`, `tools/avatar/build.py`, `tools/avatar/optimize_vrm.py`, `tools/avatar/test/protocol.test.js`, `tools/avatar/test/mood.test.js`, `tools/avatar/test/gesture.test.js`, `tools/avatar/README.md`, `assets/avatar/index.html`, `assets/avatar/avatar.bundle.js`, `assets/avatar/seed.vrm`, `assets/avatar/LICENSES.md`. Python bytecode caches must not be left behind (run with `-B` or `PYTHONDONTWRITEBYTECODE=1`).
Invariants: INV-211 (page never receives amounts), INV-213 (no runtime network).
Edges: EDGE-214, EDGE-215, EDGE-217.

## 7. External Configuration / Environment Actions

Planned: none. If the deps cache is unreadable from the sandbox, return `BLOCKED_ENVIRONMENT` with the exact commands for the user.

## 8. Tests

- TEST-146: node test suites for protocol, mood, gesture.
- TEST-146b: build + `check`.

## 9. Mandatory Verification

### RED — RED-146
Command: `node --test tools/avatar/test/` (run with only the RED cases present first, i.e. before implementing the GREEN behaviour paths, or report the observed RED-case output)
Expected: cases asserting rejection/no-event pass — `parse('{"v":2,"type":"setMood"}')` → not ok; unknown type → not ok; non-JSON → not ok; 300 ms hold in head → no `pat`; 15 px drag in head within 200 ms → no `pat`; `targets('bogus')` equals neutral targets.
Status: READY

### GREEN — GREEN-146
Command: `node --test tools/avatar/test/ && python3 -I -B tools/avatar/build.py --deps "$DEPS" && python3 -I -B tools/avatar/optimize_vrm.py check assets/avatar/seed.vrm --source "$DEPS/Seed-san.vrm"`
Expected: `targets` per spec §9; 120 ms / 3 px head → `pat`; 3 reversals × 20 px within 900 ms starting in head → `pettingStart` then `pettingEnd` 600 ms after; dx 60 / dy 10 outside head → `swipe`; bundle ≤ 1.1 MB; seed.vrm ≤ 6 MB, images ≤ 512², VRMC extensions identical.
Status: READY

Verification ceiling: V2.

### Task Buildability Gate
Required: YES
Affected build unit: `tools/avatar`
Command: `python3 -I -B tools/avatar/build.py --deps "$DEPS" && node --test tools/avatar/test/`
Result: PENDING

### External Verification
Required: NO (rendering checked in T148 MAN-148).

## 10. Stop Conditions

Version incompatibility between three 0.187.0 and three-vrm 3.5.5 at bundle time → retry with three@0.180.0 only (pre-approved fallback in spec OBS-222), else BLOCKED. VRMC extension mismatch after optimize → BLOCKED. Network unavailable → BLOCKED_ENVIRONMENT.

## 11. Execution Ledger

- [ ] route confirmed explicit
- [ ] modules + tests
- [ ] runtime
- [ ] build + optimize
- [ ] RED then GREEN
- [ ] buildability
- [ ] no protected file touched

## 12. Coordinator Audit

Scope: PASS — every attempt stayed inside its exact allowlist (dispatcher name-only check, no unexpected/staged paths).
Acceptance criteria: AC-217 PASS (bundle 778 089 B ≤ 1.1 MB; avatar.vrm 3 885 572 B ≤ 6 MB; 19 PNG ≤ 512²; VRMC extensions, image/texture indices and non-image bufferViews identical to source). AC-215 automated part PASS (node tests); browser check: pat/poke/swipe/pettingStart/pettingEnd emitted from bone regions; manual device part remains MAN-148.
Test quality: PASS — 12 node tests cover protocol rejection, mood targets/crossfade, gesture thresholds.
RED evidence: PASS (attempt 1 negative cases; R01 atob InvalidCharacterError; R02 wrong-sign grep).
GREEN evidence: PASS — coordinator re-ran `node --test` (12/12) and rebuilt bundle + model in an isolated copy: byte-identical to committed assets.
RED-before-GREEN: PASS (per executor reports; ordering not independently observable).
Evidence reused vs rerun: tests and build rerun by coordinator; visual render in local browser (Chromium) of host page with iframe mirroring the Flutter web setup: transparent background, model loads (`ready`, `modelLoaded`), strongHappy/strongSad expressions, arms at rest after R02, protocol errors on v2/non-JSON.
Architecture/contract conformance: PASS after R01/R02 (findings AUD-146-1..4, D-035).
Dispatch route compliance: UNVERIFIABLE (explicit gpt-6.2-sol / medium binding; effective route not exposed).
Parent route inheritance: NO
Task buildability gate: PASS (`python3 -I -B tools/avatar/build.py --deps "$DEPS" && node --test tools/avatar/test/`).
Not verified here: native WebView (file: URL, CSP with `file:`, chunked model transfer) — covered by T148 + MAN-148.
Verdict: PASS (attempts: 3 — b1d7a2b6 REWORK, f51c51eb REWORK, 6b1152e5 PASS). R02 REWORK cause was a coordinator contract error (arm rotation sign), not executor quality.

## 13. Remediation R01 (coordinator audit attempt 1 → REWORK)

Attempt 1 (`b1d7a2b6…`) is committed on the branch as the starting point. Keep everything not listed here unchanged.

Allowed write files for R01 (exact): `tools/avatar/src/main.js`, `tools/avatar/test/mood.test.js`, `tools/avatar/README.md`, `tools/avatar/optimize_vrm.py`, `assets/avatar/index.html`, `assets/avatar/avatar.bundle.js`, `assets/avatar/LICENSES.md`, `assets/avatar/avatar.vrm` (new), `assets/avatar/seed.vrm` (delete).

Model source (offline cache, sha256 `12c2b97e95e700783a6a550dc0eee2d7880aeedccef9ae67bc4c5a2f0f2631a2`): `$DEPS/Twist.vrm` = `VRM1_Constraint_Twist_Sample.vrm` from `https://raw.githubusercontent.com/vrm-c/vrm-specification/master/samples/VRM1_Constraint_Twist_Sample/vrm/VRM1_Constraint_Twist_Sample.vrm`.

Findings to fix:
- AUD-146-1 (Must): the model renders in T-pose. In `pose()`, set a relaxed rest pose on normalized bones every frame before `vrm.update`: `leftUpperArm.rotation.z = +1.2`, `rightUpperArm.rotation.z = -1.2`, `leftLowerArm.rotation.z = +0.15`, `rightLowerArm.rotation.z = -0.15` (VRM 1.0 normalized rig, +X = model's left). Guard for missing bones. Arms must hang down along the body in the browser render.
- AUD-146-2 (Must): `addChunk` joins base64 strings before `atob`; independently padded chunks (e.g. 512 KiB raw slices, 524288 mod 3 ≠ 0) contain `=` mid-string and fail. Decode each chunk separately into its own `Uint8Array`, then concatenate in index order.
- AUD-146-3 (Must): native pages load from `file:` URLs; `'self'` may not match there. CSP becomes `default-src 'self' file:; script-src 'self' file:; img-src 'self' file: blob: data:; connect-src 'self' file: blob: data:`.
- AUD-146-4 (Should): swipe rotation is applied only on pointer-up. While a non-head drag is active, set `yaw = (x - startX) * 0.01` live on each `move`; keep the damped return after release and keep the `swipe` interaction event on up.
- D-035 (Must): replace the model. Generate `assets/avatar/avatar.vrm` with `python3 -I -B tools/avatar/optimize_vrm.py optimize "$DEPS/Twist.vrm" assets/avatar/avatar.vrm`; delete `assets/avatar/seed.vrm`; `main.js` web path fetches `avatar.vrm`; `optimize_vrm.py` docstring/messages must not name Seed-san (its default size limit 6 000 000 stays); `README.md` and `LICENSES.md` name `VRM1_Constraint_Twist_Sample`, (c) 2022 pixiv Inc., VRM Public License 1.0, source URL; remove Seed-san/VirtualCast text.
- Add to `mood.test.js` nothing new unless needed; do not weaken existing tests.

RED-146-R01: before changing `main.js`, a Node check that base64-encodes a 1 000 001-byte buffer as two chunks of 524 288 and 475 713 raw bytes, joins them and calls `atob` → throws `InvalidCharacterError` (observed). Record the output.
GREEN-146-R01: `node --test tools/avatar/test/ && python3 -I -B tools/avatar/build.py --deps "$DEPS" && python3 -I -B tools/avatar/optimize_vrm.py check assets/avatar/avatar.vrm --source "$DEPS/Twist.vrm"` exits 0; `grep -c "file:" assets/avatar/index.html` ≥ 1; `assets/avatar/seed.vrm` absent; no `Seed-san` string in `tools/avatar` or `assets/avatar` (excluding the bundle's third-party legal comments).
Buildability: `python3 -I -B tools/avatar/build.py --deps "$DEPS" && node --test tools/avatar/test/`.

## 14. Remediation R02 (audit of R01 → REWORK)

R01 (`f51c51eb…`) fixed AUD-146-2/3/4 and D-035 (verified: reproducible build, browser render, pat/poke/protocol). AUD-146-1 remains: the coordinator's R01 contract gave the wrong signs — with +1.2 / −1.2 the arms point **up**. VRM 1.0 normalized rig faces +Z with the model's left arm along +X, so a positive Z rotation raises the left arm.

Allowed write files (exact): `tools/avatar/src/main.js`, `assets/avatar/avatar.bundle.js`.
Fix: `leftUpperArm.rotation.z = -1.2`, `rightUpperArm.rotation.z = 1.2`, `leftLowerArm.rotation.z = -0.15`, `rightLowerArm.rotation.z = 0.15`; rebuild the bundle. Nothing else.
RED-146-R02: before editing, `grep -n "leftUpperArm.rotation.z = 1.2" tools/avatar/src/main.js` finds the wrong sign (record output).
GREEN-146-R02: `grep -n "leftUpperArm.rotation.z = -1.2" tools/avatar/src/main.js` matches; `node --test tools/avatar/test/ && python3 -I -B tools/avatar/build.py --deps "$DEPS"` exits 0. Visual check (arms down) is done by the coordinator.
