# Task 149 — Avatar runtime: VRM 0.x support, auto-framing, quality, Donut-Chan assets

Status: PENDING
Agent Role: implementation_executor
Executor Class: E3
Target Model: gpt-6.2-sol
Target Effort: medium
Target Route: gpt-6.2-sol / medium
Routing Policy: EXECUTOR_ROUTING_POLICY.json v3 (OptCodex v1.5.1)
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Specification: `docs/agents/specs/2026-11-22-pnl-avatar-3d-design.md` (Revision 2)
Plan: `docs/agents/plans/2026-11-22-pnl-avatar-3d.md` (Revision 2, PLAN-20261122-pnl-avatar-3d-r2)
Plan Steps: P04
Requirements: REQ-216, REQ-217, REQ-218 (page side), REQ-220
Acceptance Criteria: AC-218 (coordinator visual), AC-219, AC-220
Decisions: D-037, D-039, CD-5, CD-6, CD-7

## 1. Dispatch Compliance

The CCB dispatcher passes `--model gpt-6.2-sol` and `model_reasoning_effort=medium`. `UNVERIFIABLE` is a valid state.

Dispatch Route Status: PENDING
Requested Model: PENDING
Requested Effort: PENDING

## 2. Objective

Make the page runtime render both bundled models correctly and sharply, and produce the optimized model and thumbnail assets.

Done when: RED-149 then GREEN-149 pass and buildability passes.

## 3. Preconditions

Predecessors: T146 PASS. Offline deps cache (read-only): `DEPS=/private/tmp/claude-501/-Users-locnguyen-projects-trading-balance-f/581c8564-b131-4cc5-b169-666a1740764c/scratchpad/avatar-deps` with `node_modules/` (three 0.187.0, @pixiv/three-vrm 3.5.5, esbuild 0.25.10), `Twist.vrm` (pixiv source, sha256 `12c2b97e95e700783a6a550dc0eee2d7880aeedccef9ae67bc4c5a2f0f2631a2`) and `Donut-Chan.vrm` (sha256 recorded by the coordinator in §13). No network.

## 4. Allowed Scope (exact files)

`tools/avatar/src/main.js`, `tools/avatar/src/framing.js` (new), `tools/avatar/src/models.js` (new), `tools/avatar/src/pose.js` (new), `tools/avatar/test/framing.test.js` (new), `tools/avatar/test/models.test.js` (new), `tools/avatar/test/pose.test.js` (new), `tools/avatar/optimize_vrm.py`, `tools/avatar/README.md`, `assets/avatar/index.html`, `assets/avatar/avatar.bundle.js`, `assets/avatar/LICENSES.md`, `assets/avatar/pixiv-sample.vrm` (new), `assets/avatar/donut-chan.vrm` (new), `assets/avatar/pixiv-sample.png` (new), `assets/avatar/donut-chan.png` (new), `assets/avatar/avatar.vrm` (delete).

## 5. Forbidden Scope

Protected files; any Dart file; network; `package.json`/`node_modules` in the repo; changes to `bridge.js`, `protocol.js`, `gesture.js`, `hit.js`, `mood.js` (unless a one-line import is required — then report it).

## 6. Executor Contract

1. `framing.js` (pure, no three import): `frame({headY, hipsY})` → `{centerY, halfHeight}` with S=headY−hipsY, top=headY+0.73·S, bottom=hipsY−0.20·S; throws on non-finite or S ≤ 0.
2. `models.js` (pure): `MODELS = {'pixiv-sample':'pixiv-sample.vrm','donut-chan':'donut-chan.vrm'}`, `DEFAULT_MODEL='pixiv-sample'`, `resolveModel(search)` → file name; id must match `/^[a-z0-9-]{1,32}$/` and be a key of MODELS, else default.
3. `pose.js` (pure): `restPose(isVrm0)` → `{leftUpperArmZ, rightUpperArmZ, leftLowerArmZ, rightLowerArmZ}` = (−1.2, 1.2, −0.15, 0.15) for VRM1 and the negated values for VRM0; `axisSign(isVrm0)` → 1 or −1.
4. `main.js`:
   - renderer `antialias: true`; `setPixelRatio(Math.min(devicePixelRatio, 3))`.
   - web path: `fetch(resolveModel(location.search), {redirect:'error'})`.
   - after load: `isVrm0 = vrm.meta?.metaVersion === '0'`; `baseYaw = isVrm0 ? Math.PI : 0`; each frame `vrm.scene.rotation.y = baseYaw + yaw`; multiply chest.x, head.x, head.z (tilt + sway) by `axisSign`; arms from `restPose(isVrm0)`.
   - expression for poke: use `surprised`, or `Surprised` when `surprised` is absent (`vrm.expressionManager.getExpression`).
   - framing: after `scene.add`, `vrm.scene.updateMatrixWorld(true)`, read head/hips world Y, apply `frame()` to camera position Y and top/bottom; `resize()` uses the computed half height; call `camera.updateProjectionMatrix()` and `camera.updateMatrixWorld()`.
5. `optimize_vrm.py`:
   - `optimize SRC DST [--max-side 1024] [--thumbnail-side 256] [--thumbnail-out PNG]`: images resized to `--max-side`; the meta thumbnail image (VRM1 `meta.thumbnailImage`, VRM0 `extensions.VRM.meta.texture` → texture → image) resized to `--thumbnail-side` inside the VRM; `--thumbnail-out` writes that thumbnail as a PNG file; dense morph-target accessors re-encoded as sparse accessors (indices of non-zero elements, `UNSIGNED_INT` or `UNSIGNED_SHORT`) when that is smaller; all indices of images/textures/accessors preserved.
   - `check DST --source SRC [--max-side 1024] [--max-bytes N]`: accept VRM1 (`VRMC_vrm`, `VRMC_springBone`, MToon materials) or VRM0 (`extensions.VRM` with `materialProperties`, `secondaryAnimation`); the VRMC subtree or `extensions.VRM` equal to the source except the thumbnail image bytes; images ≤ max-side; every accessor decodes (sparse applied) to the same values as the source; size ≤ max-bytes.
6. Generate: `optimize "$DEPS/Twist.vrm" assets/avatar/pixiv-sample.vrm --thumbnail-out assets/avatar/pixiv-sample.png`; `optimize "$DEPS/Donut-Chan.vrm" assets/avatar/donut-chan.vrm --thumbnail-out assets/avatar/donut-chan.png`; delete `assets/avatar/avatar.vrm`; rebuild the bundle.
7. `LICENSES.md` and `README.md`: add Donut-Chan (Kana Fuyuko, Public Domain, Booth item 5975245); rename the pixiv entry's file; document the commands above.

## 7. External Configuration

None (`pubspec.yaml` already declares the `assets/avatar/` directory).

## 8. Tests

framing/models/pose node tests; optimizer `check` for both models.

## 9. Mandatory Verification

### RED — RED-149
Before implementing: `python3 -I -B tools/avatar/optimize_vrm.py check <a 1024 optimize of Donut-Chan made with the current script into a temp dir> --source "$DEPS/Donut-Chan.vrm"` fails with "Required VRMC extensions are missing"; new node tests fail (modules missing). Record output.

### GREEN — GREEN-149
`node --test tools/avatar/test/` passes (incl. framing (1.28, 0.47 ±1e-3 for head 1.395/hips 0.908), id validation `../x`, `avatar.vrm`, `DONUT-CHAN`, empty, unknown → default, VRM0 negated rest pose); `python3 -I -B tools/avatar/build.py --deps "$DEPS"` exits 0; `check` passes for `pixiv-sample.vrm` (`--max-bytes 6000000`) and `donut-chan.vrm` (`--max-bytes 10000000`); both PNGs exist and are ≤ 256 px.

Verification ceiling: V2.

### Task Buildability Gate
Command: `python3 -I -B tools/avatar/build.py --deps "$DEPS" && node --test tools/avatar/test/`
Result: PENDING

## 10. Stop Conditions

Sparse encoding cannot pass the round-trip check → keep dense for that accessor and report; Donut-Chan still above 10 MB after sparse → report the measured size (BLOCKED for coordinator decision, do not prune blendshapes).

## 11. Coordinator Audit

Verdict: PENDING (coordinator renders both models in a local browser for AC-218)

## 13. Coordinator staging

Donut-Chan source sha256: PENDING (filled before dispatch).
