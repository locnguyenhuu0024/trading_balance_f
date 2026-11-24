# Task 153 — Avatar runtime: Donut-Chan part rules

Status: PENDING
Agent Role: implementation_executor
Executor Class: E2
Target Model: gpt-6.2-sol
Target Effort: low
Target Route: gpt-6.2-sol / low
Routing Policy: EXECUTOR_ROUTING_POLICY.json v3 (OptCodex v1.5.1)
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Specification: `docs/agents/specs/2026-11-22-pnl-avatar-3d-design.md` (Revision 3.1)
Plan: `docs/agents/plans/2026-11-22-pnl-avatar-3d.md` (Revision 3.1, PLAN-20261124-pnl-avatar-3d-r3b)
Requirements: REQ-226
Acceptance Criteria: AC-227 (automated), AC-228 (coordinator visual)
Decisions: D-043, CD-13

## 1. Dispatch Compliance

The CCB dispatcher passes `--model gpt-6.2-sol` and `model_reasoning_effort=low`. `UNVERIFIABLE` is a valid state.

## 2. Objective

`partForMaterial` maps Donut-Chan materials to the parts users actually see; the protocol accepts the new part ids.

## 3. Preconditions

T151, T152 PASS. Offline deps: `DEPS=/private/tmp/claude-501/-Users-locnguyen-projects-trading-balance-f/581c8564-b131-4cc5-b169-666a1740764c/scratchpad/avatar-deps`. No network.

## 4. Allowed Scope (exact files)

`tools/avatar/src/recolor.js`, `tools/avatar/test/recolor.test.js`, `tools/avatar/test/protocol.test.js`, `tools/avatar/test/models.test.js`, `tools/avatar/README.md`, `assets/avatar/avatar.bundle.js`.

## 5. Forbidden Scope

Protected files, Dart, `main.js`/`protocol.js` (protocol already validates against `PARTS` from `recolor.js`), other assets, network.

## 6. Executor Contract

1. `recolor.js`: `PARTS = ['hair','eyes','top','bottom','shoes','accessory','dress','bows','socks','plasters']`. Before the generic patterns, check an ordered list of material-name prefixes:
   - `N00_002_03_Tops_01_CLOTH_02`, `N00_002_03_Tops_01_CLOTH_03` → `dress`
   - `N00_002_03_Tops_01_CLOTH_01`, `N00_007_01_Tops_01_CLOTH_01`, `N00_007_01_Tops_01_CLOTH_02` → `bows`
   - `N00_010_01_Onepiece_00_CLOTH_01`, `N00_010_01_Onepiece_00_CLOTH_02` → `socks`
   - `N00_010_01_Onepiece_00_CLOTH_03` → `plasters`
   (`name.startsWith(prefix)` so ` (Instance)` / ` (Outline)` suffixes match.) Generic patterns unchanged.
2. Tests:
   - `recolor.test.js`: each prefix above (with ` (Instance)` and ` (Outline)` suffixes) → its part; pixiv names unchanged (`Tops_01_CLOTH` → top, `Bottoms_01_CLOTH` → bottom, `Shoes_01_CLOTH` → shoes, hair/eyes); `N00_008_01_Shoes_01_CLOTH_01` → shoes; `Accessory_FoxTail_01_CLOTH (Instance)` → accessory.
   - `protocol.test.js`: setColors accepts `dress`, `bows`, `socks`, `plasters`; still rejects unknown keys.
   - `models.test.js`: per model expected parts — pixiv-sample {hair, eyes, top, bottom, shoes}; donut-chan {hair, eyes, dress, bows, socks, shoes, plasters, accessory} — each matches ≥ 1 material; donut-chan has no material mapped to `top` or `bottom`.
3. Rebuild the bundle; update the README part list.

## 9. Mandatory Verification

### RED — RED-153
Before editing: run the new/updated tests → Donut-Chan prefix cases fail (current mapping returns `top`/`bottom`). Record.

### GREEN — GREEN-153
`node --test tools/avatar/test/` all pass; `python3 -I -B tools/avatar/build.py --deps "$DEPS"` exits 0.

### Task Buildability Gate
Command: `python3 -I -B tools/avatar/build.py --deps "$DEPS" && node --test tools/avatar/test/`
Result: PENDING

## 12. Coordinator Audit

Verdict: PENDING (coordinator browser part check AC-228)
