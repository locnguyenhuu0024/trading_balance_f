# Task 157 — Avatar runtime: full-body framing and `setFraming`

Status: PASS
Agent Role: implementation_executor
Executor Class: E2
Target Model: gpt-6.2-sol
Target Effort: low
Target Route: gpt-6.2-sol / low
Routing Policy: EXECUTOR_ROUTING_POLICY.json v3 (OptCodex v1.5.1)
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Specification: `docs/agents/specs/2026-11-22-pnl-avatar-3d-design.md` (Revision 5)
Plan: `docs/agents/plans/2026-11-22-pnl-avatar-3d.md` (Revision 5, PLAN-20261127-pnl-avatar-3d-r5)
Requirements: REQ-234, REQ-235
Acceptance Criteria: AC-235 (automated), AC-236 (coordinator visual)
Decisions: D-047, CD-21

## 1. Dispatch Compliance
The CCB dispatcher passes `--model gpt-6.2-sol` and `model_reasoning_effort=low`. `UNVERIFIABLE` is a valid state.

## 2. Objective
The runtime can frame the avatar full-body or half-body and switch at runtime on `setFraming`.

## 3. Preconditions
T155 PASS. Offline deps: `DEPS=/private/tmp/claude-501/-Users-locnguyen-projects-trading-balance-f/581c8564-b131-4cc5-b169-666a1740764c/scratchpad/avatar-deps`. No network.

## 4. Allowed Scope (exact files)
`tools/avatar/src/framing.js`, `tools/avatar/src/protocol.js`, `tools/avatar/src/main.js`, `tools/avatar/test/framing.test.js`, `tools/avatar/test/protocol.test.js`, `tools/avatar/README.md`, `assets/avatar/avatar.bundle.js`.

## 5. Forbidden Scope
Protected files, Dart, other assets, `hit.js`/`gesture.js`, network.

## 6. Executor Contract
1. `framing.js`: `export const FRAMING_MODES = Object.freeze(['half','full'])`; `frame({headY, hipsY, footY}, mode = 'half')`. `half`: today's code path, unchanged (footY ignored). `full`: S=headY−hipsY (same validation), requires `Number.isFinite(footY) && footY < hipsY` else `RangeError`; top=headY+0.60·S, bottom=footY−0.30·S; return `{centerY, halfHeight}` as today. Unknown mode → `RangeError`.
2. `protocol.js`: `setFraming` valid when `FRAMING_MODES.includes(msg.mode)`, exactly one field (same style as `setMood`).
3. `main.js`: `let framingMode = 'full'`, `let bounds`. At load, right after the existing `updateMatrixWorld(true)`, store `bounds = {headY, hipsY, footY: Math.min(leftFoot Y, rightFoot Y)}` (`vrm.humanoid` normalized bone nodes, same way as head/hips) and replace the inline framing with `applyFraming()`: no-op without `bounds`; else frame, set `camera.position.y`, `halfHeight`, `camera.top/bottom`, `resize()`, and render once when the renderer exists and a frame was already drawn. Message `setFraming` → `framingMode = msg.mode; applyFraming()`. Errors in framing go through the existing `fail('load', …)` path only at load.
4. README: document `setFraming`.
5. Rebuild the bundle with `python3 -I -B tools/avatar/build.py --deps "$DEPS"`.
6. Tests (`RED-157`/`GREEN-157` in test names):
   - framing: full pixiv `{1.395, 0.908, 0.100}` → centerY 0.82055, halfHeight 0.86665 (±1e-4); full donut `{1.368, 0.887, 0.116}` → top ≥ head+0.28, bottom ≤ foot−0.14; full rejects missing/NaN/≥hips footY; unknown mode throws; `FRAMING_MODES` frozen, exactly half/full; existing half tests unchanged and pass with and without footY.
   - protocol: accepts `setFraming` half/full (string and object); rejects `'FULL'`, `1`, missing mode, extra field.

## 9. Mandatory Verification
### RED — RED-157
Before editing, run the new tests → full-mode/protocol cases fail. Record.
### GREEN — GREEN-157
`node --test tools/avatar/test/` all pass; bundle rebuild exits 0 and is reproducible.
### Task Buildability Gate
Command: `python3 -I -B tools/avatar/build.py --deps "$DEPS" && node --test tools/avatar/test/`
Result: PASS (coordinator, host)

## 13. Remediation R01 (coordinator audit attempt 1 → REWORK)

Attempt `276671b1…` committed as the starting point. Executor BLOCKED only on a purged offline deps dir; coordinator re-staged the pinned deps (base rebuild byte-identical to the committed bundle), rebuilt (reproducible, sha e39e6fe9…) and ran `node --test` 73/73. Code review: half path numerically unchanged, protocol/main per contract.
AUD-157-1 (Must; AC-236): in the 1:2 full-body frame Donut-Chan's heart ahoge touches the top edge and the feet sit on the bottom edge (local Chromium). Per CD-21 widen the full margins: top = headY + 0.75·S, bottom = footY − 0.35·S. Update the full-body tests: pixiv `{1.395, 0.908, 0.100}` → centerY 0.8449, halfHeight 0.91535 (±1e-4); donut → top ≥ head + 0.36, bottom ≤ foot − 0.16. Rebuild the bundle. Nothing else.
Allowed write files (exact): `tools/avatar/src/framing.js`, `tools/avatar/test/framing.test.js`, `assets/avatar/avatar.bundle.js`.
Offline deps: `DEPS=/private/tmp/claude-501/-Users-locnguyen-projects-trading-balance-f/02dda968-4471-429d-89b5-19ee52747604/scratchpad/avatar-deps`.
RED-157-R01: run the updated tests before editing `framing.js` → the full-body value cases fail.
GREEN-157-R01: `node --test tools/avatar/test/` all pass; bundle rebuild exits 0.

## 14. Coordinator Audit

Attempts `276671b1…` (BLOCKED on purged deps; REWORK AUD-157-1) and R01 `6b393a4c…`. Scope: exact allowlist both times.
Review: `FRAMING_MODES` frozen; half path numerically unchanged; full uses required `leftFoot`/`rightFoot`, bounds cached at load; `setFraming` validated via `FRAMING_MODES`, applied live with a one-off render; R01 margins 0.75·S / 0.35·S.
GREEN (coordinator): `node --test tools/avatar/test/` 73/73; bundle rebuild reproducible (sha 616439c5…).
AC-236 (coordinator, local Chromium, 150×300 full / 160×220 half): pixiv, donut and pixiv wearing the Donut outfit + shoes show hair/ahoge and shoes with clearance; half frames unchanged; `setFraming` switches full↔half live without reload, no errors.
Dispatch route: UNVERIFIABLE (explicit gpt-6.2-sol / low). Buildability: PASS.
Verdict: PASS
