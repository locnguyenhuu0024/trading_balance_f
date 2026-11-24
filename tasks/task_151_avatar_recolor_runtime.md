# Task 151 — Avatar runtime: per-part recolor and `setColors` bridge

Status: READY
Agent Role: implementation_executor
Executor Class: E3
Target Model: gpt-6.2-sol
Target Effort: medium
Target Route: gpt-6.2-sol / medium
Routing Policy: EXECUTOR_ROUTING_POLICY.json v3 (OptCodex v1.5.1)
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Specification: `docs/agents/specs/2026-11-22-pnl-avatar-3d-design.md` (Revision 3)
Plan: `docs/agents/plans/2026-11-22-pnl-avatar-3d.md` (Revision 3, PLAN-20261124-pnl-avatar-3d-r3)
Requirements: REQ-221, REQ-222
Acceptance Criteria: AC-223 (automated), AC-224 (coordinator visual)
Decisions: D-042, CD-9, CD-10

## 1. Dispatch Compliance

The CCB dispatcher passes `--model gpt-6.2-sol` and `model_reasoning_effort=medium`. `UNVERIFIABLE` is a valid state.

## 2. Objective

The page recolors model parts on a `setColors` message, per spec Revision 3.

Done when: RED-151 then GREEN-151 pass and buildability passes.

## 3. Preconditions

T149 PASS. Offline deps (read-only): `DEPS=/private/tmp/claude-501/-Users-locnguyen-projects-trading-balance-f/581c8564-b131-4cc5-b169-666a1740764c/scratchpad/avatar-deps`. No network.

## 4. Allowed Scope (exact files)

`tools/avatar/src/recolor.js` (new), `tools/avatar/src/protocol.js`, `tools/avatar/src/main.js`, `tools/avatar/test/recolor.test.js` (new), `tools/avatar/test/protocol.test.js`, `tools/avatar/test/models.test.js`, `tools/avatar/README.md`, `assets/avatar/avatar.bundle.js`.

## 5. Forbidden Scope

Protected files, Dart files, other assets, network, repo `package.json`.

## 6. Executor Contract

1. `recolor.js` (pure, no three import):
   - `PARTS = ['hair','eyes','top','bottom','shoes','accessory']`.
   - `partForMaterial(name)`: hair `/_HAIR/`, eyes `/EyeIris/`, top `/Tops_/`, bottom `/(Bottoms_|Onepiece_)/`, shoes `/Shoes_/`, accessory `/^Accessory_/`; else `null` (names may carry `N00_…` prefixes, ` (Instance)` / ` (Outline)` suffixes; `EyeWhite`, `EyeHighlight`, `*_SKIN`, `FaceMouth` → null).
   - `parseHex('#rrggbb')` → `[r,g,b]` (case-insensitive).
   - `luminance(pixels)` → `{lum: Uint8Array, mean}`; L = 0.2126R+0.7152G+0.0722B; mean over pixels with alpha > 8; 128 when none.
   - `colorize(pixels, lum, mean, rgb)`: in place, k = min(1.6, L/mean), channel = min(255, round(target·k)); alpha bytes untouched.
2. `protocol.js`: `case 'setColors'`, `fieldCount = 1`; `colors` must be a non-null, non-array object whose own keys are all in `PARTS` with values matching `/^#[0-9a-f]{6}$/i` (`{}` valid; `__proto__` key rejected).
3. `main.js`:
   - state `colors = {}`; on `setColors` store and schedule an apply (≤ 1 apply per 100 ms, last value wins); no-op until the model is loaded.
   - after `scene.add(vrm.scene)` and before the first render: apply current colors.
   - apply: traverse materials; for materials with a part, take the original base texture (`map`; first time cache it per material); per original texture keep `{canvas, ctx, imageData, lum, mean, tex}` created lazily (`drawImage` of `orig.image`, `getImageData`, `luminance`), where `tex = orig.clone(); tex.source = new Source(canvas)` (import `Source` from three) — never assign `.image` on the clone; recolor only parts whose value changed (copy original pixels back from a cached copy, `colorize`, `putImageData`, `tex.needsUpdate = true`); assign `tex` (or the original when the part is cleared) to both `map` and `shadeMultiplyTexture` (only if the material had it) and set `material.needsUpdate = true` when the slot object changes.
   - each original texture recolored once even when shared by several materials (outline clones).
   - on `fail`/page teardown dispose recolored textures and drop caches.
4. Tests:
   - `recolor.test.js`: partForMaterial table (above), colorize (grey at mean → exact target; white → target·1.6 clamped; black stays black; alpha unchanged; transparent pixels excluded from mean; all-transparent → mean 128, no NaN), parseHex.
   - `protocol.test.js`: setColors valid partial and `{}`; rejects unknown key, `__proto__`, `#fff`, `red`, `#GGGGGG`, array, null, extra field, missing `colors`.
   - `models.test.js`: parse each GLB JSON chunk in `assets/avatar/*.vrm`; pixiv-sample has materials for hair, eyes, top, bottom, shoes and none for accessory; donut-chan has materials for all six.
5. Rebuild the bundle; document `setColors` in `tools/avatar/README.md`.

## 9. Mandatory Verification

### RED — RED-151
Before implementing: `node --test tools/avatar/test/` fails (missing `recolor.js`, `setColors` rejected as unknown type). Record.

### GREEN — GREEN-151
`node --test tools/avatar/test/` all pass; `python3 -I -B tools/avatar/build.py --deps "$DEPS"` exits 0.

Verification ceiling: V2.

### Task Buildability Gate
Command: `python3 -I -B tools/avatar/build.py --deps "$DEPS" && node --test tools/avatar/test/`
Result: PENDING

## 10. Stop Conditions

A three r187 API in §6 missing → BLOCKED with evidence.

## 12. Coordinator Audit

Verdict: PENDING (coordinator browser check AC-224)
