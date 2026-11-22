# Task 146 — Avatar page runtime and bundled assets

Status: READY
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

Verdict: PENDING
