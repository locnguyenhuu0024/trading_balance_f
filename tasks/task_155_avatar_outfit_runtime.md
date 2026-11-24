# Task 155 — Avatar runtime: outfit mixing (Donut-Chan items on Pixiv Sample)

Status: READY
Agent Role: implementation_executor
Executor Class: E4
Target Model: gpt-6.2-sol
Target Effort: high
Target Route: gpt-6.2-sol / high
Routing Policy: EXECUTOR_ROUTING_POLICY.json v3 (OptCodex v1.5.1)
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Specification: `docs/agents/specs/2026-11-22-pnl-avatar-3d-design.md` (Revision 4)
Plan: `docs/agents/plans/2026-11-22-pnl-avatar-3d.md` (Revision 4, PLAN-20261124-pnl-avatar-3d-r4)
Requirements: REQ-229, REQ-230
Acceptance Criteria: AC-231 (automated), AC-232 (coordinator visual)
Decisions: D-045, CD-15, CD-16, CD-17, CD-18

## 1. Dispatch Compliance

The CCB dispatcher passes `--model gpt-6.2-sol` and `model_reasoning_effort=high`. `UNVERIFIABLE` is a valid state.

## 2. Objective

The page can dress the target model in borrowed Donut-Chan items via `setOutfit`, with donor bytes from Flutter (native) or fetched (web).

## 3. Preconditions

T153 PASS. Offline deps: `DEPS=/private/tmp/claude-501/-Users-locnguyen-projects-trading-balance-f/581c8564-b131-4cc5-b169-666a1740764c/scratchpad/avatar-deps`. Reference spike (read-only, proven fit, but it binds with the current world matrix by accident — do NOT copy that): `/private/tmp/claude-501/-Users-locnguyen-projects-trading-balance-f/02dda968-4471-429d-89b5-19ee52747604/scratchpad/spike/src/mix.js`.

## 4. Allowed Scope (exact files)

New: `tools/avatar/src/items.js`, `tools/avatar/src/rebind.js`, `tools/avatar/src/chunks.js`, `tools/avatar/test/items.test.js`, `tools/avatar/test/rebind.test.js`, `tools/avatar/test/chunks.test.js`.
Modify: `tools/avatar/src/protocol.js`, `tools/avatar/src/main.js`, `tools/avatar/test/protocol.test.js`, `tools/avatar/README.md`, `assets/avatar/avatar.bundle.js`.

## 5. Forbidden Scope

Protected files, Dart, other assets, network.

## 6. Executor Contract

1. `items.js` (pure): `ITEMS` frozen —
   - `donut-chan:outfit`: donor `donut-chan`, material prefixes `N00_002_03_Tops_01_CLOTH_01`, `_02`, `_03`, `N00_007_01_Tops_01_CLOTH_01`, `_02`; hide `{'pixiv-sample': /^(Tops_01|Bottoms_01)_CLOTH/}`
   - `donut-chan:shoes`: prefixes `N00_008_01_Shoes_01_CLOTH_01`, `_02`; hide `{'pixiv-sample': /^Shoes_01_CLOTH/}`
   - `donut-chan:plasters`: prefix `N00_010_01_Onepiece_00_CLOTH_03`; hide `{}`
   - `DONORS = ['donut-chan']`; `itemForMaterial(name)` (startsWith); `resolveOutfit(items, targetId)` → `{show:Set, hide:RegExp[]}` (unknown target → empty).
2. `rebind.js` (pure, three `Matrix4`/`Quaternion`/`Vector3` only): `flipFor(donorMetaVersion, targetMetaVersion)` (RotY(π) when different, else identity); `boneKey(name)` (`J_Bip*` → name, else `donor:` + name); `flipLocal(position, quaternion, flip)` (position·flip; quaternion conjugated as (−x, y, −z, w) when flipping); `rebindInverse(flip, inverse)` = flip·inverse; `planChain(bone, hasKey)` → donor bones to clone from the nearest mapped ancestor down.
3. `chunks.js` (pure): `createAssembler()` → `add(i, n, b64)` returns `Uint8Array` when complete; decodes each chunk separately; inconsistent `n` → error; duplicates ignored; out-of-order OK. Use it for both `loadModelChunk` and `loadDonorChunk`.
4. `protocol.js`: `setOutfit` (`items` array ≤ 3, strings, own keys of `ITEMS`, unique; fieldCount 1); `loadDonorChunk` (`model` ∈ `DONORS`; i/n/b64 same rules as `loadModelChunk`; fieldCount 4).
5. `main.js`:
   - state `outfit = []`, donor state `none|receiving|parsing|ready|failed`; buffer donor chunks until the target model is ready.
   - web: on the first non-empty outfit after the target loads, `fetch` the donor via `MODELS['donut-chan']` (`{redirect:'error'}`); native: wait for `loadDonorChunk`.
   - on donor parsed: `VRMUtils.removeUnnecessaryVertices(donor.scene)`; do NOT add the donor scene; `updateMatrixWorld(true)` on both; for every item in `ITEMS` (one pass, shared bone map), clone matching donor `SkinnedMesh`es (material from `[].concat(material)[0].name`) into `new SkinnedMesh(geometry, material)`, build bones with `boneKey`/`planChain`/`flipLocal` (clone each donor-only bone once, name it `donor:<name>`), inverses with `rebindInverse`, `mesh.bind(new Skeleton(bones, inverses), new Matrix4())` (identity bind matrix), `frustumCulled = false`; put each item's meshes in a hidden `Group` under `vrm.scene`; then dispose donor geometries/materials/textures not used by kept meshes (close ImageBitmap sources) and drop donor references.
   - apply outfit: `resolveOutfit(outfit, currentModelId)`; show/hide item groups; for target meshes, `visible = !hide.some(r => r.test(materialName))`; then reset `appliedColors = {}` and `applyColors()` (CD-18).
   - current model id: web from `resolveModel` id; native: derive from the loaded model (`vrm.meta` title/name equals `VRM1_Constraint_Twist_Sample` → `pixiv-sample`, `Donut-Chan` → `donut-chan`); unknown → no items.
   - any donor fetch/parse/transfer failure → `send({v:1,type:'error',code:'outfit',message})`, state `failed`, base avatar keeps rendering (do NOT call `fail`).
6. Tests:
   - `items.test.js`: frozen ids; `resolveOutfit` for each item, all three, duplicates, unknown target; GLB check — every prefix matches ≥ 1 donut-chan material, every hide regex matches ≥ 1 pixiv-sample material and none of the borrowed materials.
   - `rebind.test.js`: flip identity when versions equal; conjugation round-trip; synthetic D (donor bone world), T = F·D·F⁻¹ ⇒ T·rebindInverse(F, D⁻¹)·v ≈ F·v (1e-6); `planChain` on a mock hierarchy; a helper that returns the bind matrix used is identity.
   - `chunks.test.js`: complete in order/out of order, duplicate, inconsistent n, padded chunks.
   - `protocol.test.js`: setOutfit accepts `[]`, one, all three; rejects unknown, duplicate, non-array, > 3, extra field; loadDonorChunk accepts valid, rejects bad model/base64/i ≥ n; existing cases unchanged.
7. Rebuild bundle; document messages in `tools/avatar/README.md`.

## 9. Mandatory Verification

### RED — RED-155
Before implementing: `node --test tools/avatar/test/` fails (modules missing; setOutfit/loadDonorChunk rejected). Record.

### GREEN — GREEN-155
`node --test tools/avatar/test/` all pass; `python3 -I -B tools/avatar/build.py --deps "$DEPS"` exits 0.

### Task Buildability Gate
Command: `python3 -I -B tools/avatar/build.py --deps "$DEPS" && node --test tools/avatar/test/`
Result: PENDING

## 10. Stop Conditions

A three r187 / three-vrm 3.5.5 API in §6 missing → BLOCKED with evidence. Visual correctness is audited by the coordinator; do not tune geometry beyond §6.

## 12. Coordinator Audit

Verdict: PENDING (browser check AC-232)
