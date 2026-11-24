# Final Integration Audit — PnL-reactive 3D avatar

Date: 2026-11-24
Branch: `feature/pnl-avatar-3d` (base `main` @ 4eac0f2)
Plans: PLAN-20261122-pnl-avatar-3d (rev 1.x) and PLAN-20261122-pnl-avatar-3d-r2
Verdict: PASS (exception: macOS signing, user-owned)

## Tasks
| Task | Verdict | Attempts |
|---|---|---|
| T146 page runtime + assets | PASS | 3 (REWORK, REWORK — coordinator contract sign error, PASS) |
| T147 mood + setting + licenses | PASS | 2 |
| T148 home host (native WebView / web iframe) | PASS | 2 (BLOCKED on contract, PASS) |
| T149 VRM 0.x, framing, quality, Donut-Chan | PASS | 1 |
| T150 catalog + picker + switching | PASS | 2 |

## Integration evidence (after the last code change, b27e521)
- `flutter test --no-pub`: 722/722 pass.
- `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings`: No issues found.
- `node --test tools/avatar/test/`: 18/18 pass.
- Builds: web ✓, Android debug APK ✓, iOS simulator ✓; macOS BLOCKED_ENVIRONMENT (signing).
- Assets reproducible byte-for-byte from `tools/avatar` with the pinned offline deps.
- Devices: iOS Simulator (coordinator) — render, drag, background/resume, picker, switch, persistence; Android device (user) — PASS.

## Requirement coverage
REQ-210..REQ-220 implemented and evidenced in the task audits (T146..T150).

## Scope and safety
- Final diff limited to approved surfaces plus user-authorized changes: `pubspec.yaml` (user commits + coordinator asset entry D-036), generated `pubspec.lock` / `GeneratedPluginRegistrant.swift`, `scripts/ccb/dispatch.py` allowlist (.dart, .vrm, .png — user approved), README rewrite (user request).
- Protected-config exceptions disclosed: pre-baseline read of `pubspec.yaml`; D-036 edit on explicit user instruction.
- Licenses: three.js (MIT), @pixiv/three-vrm (MIT), VRM1_Constraint_Twist_Sample (VRM Public License 1.0, © pixiv), Donut-Chan (Public Domain, Kana Fuyuko) — shipped in `assets/avatar/LICENSES.md` and Flutter LicenseRegistry.

## Open items (not blocking)
- macOS signing (user): select a Team in `macos/Runner.xcworkspace`.
- Nits: "Chọn nhân vật" row lacks a leading icon (alignment); head hit area small at 160×220; `Object.hasOwn` in web-only model resolution.

## Addendum — revisions 3–4 (T151–T156, PLAN-20261124-pnl-avatar-3d-r3 / -r4)

| Task | Verdict | Attempts |
|---|---|---|
| T151 avatar_recolor_runtime | PASS | 1 |
| T152 avatar_customize_page | PASS | 1 |
| T153 avatar_part_rules | PASS | 1 |
| T154 avatar_parts_swatches | PASS | 2 (R01: test semantics handle) |
| T155 avatar_outfit_runtime | PASS | 2 (R01: `Object.hasOwn` off the native path) |
| T156 avatar_outfit_tab | PASS | 2 (R01: test assertions) |

Integration evidence after the last code change (318a8b6): `flutter analyze` No issues; `flutter test --no-pub` 761/761; `node --test tools/avatar/test/` 65/65 with a byte-identical bundle rebuild; `flutter build web` ✓, `flutter build apk --debug` ✓, `flutter build ios --simulator --debug` ✓. macOS unchanged (signing BLOCKED_ENVIRONMENT, user-owned).
Device evidence: iOS Simulator full outfit flow (equip, recolour borrowed dress, save, relaunch → home shows it); local Chromium outfit/failure checks (T155). Android physical-device check of outfit mixing: pending user.
Open (not blocking): Donut-Chan ears/tail as borrowable items (deferred by user); shoes/plasters are outside the upper-body framing so only GLB-mapping tests cover them visually; picker Semantics label includes HueRingPicker's "Hex".
