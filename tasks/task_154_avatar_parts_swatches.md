# Task 154 — Avatar customize: Donut-Chan parts and original-colour swatches

Status: PASS
Agent Role: implementation_executor
Executor Class: E2
Target Model: gpt-6.2-sol
Target Effort: low
Target Route: gpt-6.2-sol / low
Routing Policy: EXECUTOR_ROUTING_POLICY.json v3 (OptCodex v1.5.1)
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Specification: `docs/agents/specs/2026-11-22-pnl-avatar-3d-design.md` (Revision 3.1)
Plan: `docs/agents/plans/2026-11-22-pnl-avatar-3d.md` (Revision 4, PLAN-20261124-pnl-avatar-3d-r4)
Requirements: REQ-227, REQ-228
Acceptance Criteria: AC-229, AC-230
Decisions: D-043, D-044, CD-14

## 1. Dispatch Compliance

The CCB dispatcher passes `--model gpt-6.2-sol` and `model_reasoning_effort=low`. `UNVERIFIABLE` is a valid state.

## 2. Objective

Donut-Chan's customize page lists its real outfit parts, and every unset part starts from its original colour instead of black.

## 3. Preconditions

T153 PASS. Executor sandbox cannot run Flutter: write complete code, report RED/GREEN `NOT_RUN`, buildability `BLOCKED` with that reason.

## 4. Allowed Scope (exact files)

`lib/features/avatar/domain/avatar_colors.dart`, `lib/features/avatar/domain/avatar_model.dart`, `lib/features/settings/presentation/settings_avatar_customize_page.dart`, `test/features/avatar/avatar_colors_test.dart`, `test/features/avatar/avatar_model_test.dart`, `test/features/settings/settings_avatar_customize_page_test.dart`.

## 5. Forbidden Scope

Protected files; renderers, storage, home, other pages; `assets/**`, `tools/**`.

## 6. Executor Contract

1. `AvatarPart`: add `dress` (label `Váy`), `bows` (`Nơ & huy hiệu`), `socks` (`Tất`), `plasters` (`Miếng dán`); `wireName` = enum name; JSON decode accepts the new names.
2. `AvatarModel`: add `final Map<AvatarPart, Color> originalColors` (const). pixiv-sample parts unchanged with originals hair `#6d4b3a`, eyes `#0f0904`, top `#f8f6f6`, bottom `#050505`, shoes `#929aab`. donut-chan parts in order [hair, eyes, dress, bows, socks, shoes, plasters, accessory] with originals hair `#c4b68b`, eyes `#415130`, dress `#f7bdc0`, bows `#f8a5b0`, socks `#f5b4bd`, shoes `#f0bec4`, plasters `#d6cac6`, accessory `#e5d9b6`.
3. Customize page: for an unset part, the chip swatch shows `model.originalColors[part]` and its Semantics value says `Mặc định`; the `HueRingPicker` `pickerColor` for an unset part is that original colour (so the first touch starts near the original); behaviour otherwise unchanged (draft, throttle, save, reset).
4. Stale data: `restrictTo(model.parts)` already drops parts not in the model — keep it applied wherever colours are read for a model (verify; no new code if already the case).
5. Tests (`RED-153`/`GREEN-153` naming is reserved for T153 — use `RED-154` / `GREEN-154`):
   - avatar_model_test: donut-chan parts equal the ordered list; every part of every model has an original colour; pixiv unchanged.
   - avatar_colors_test: JSON with `dress`/`bows`/`socks`/`plasters` decodes; `restrictTo(donut parts)` drops `top`/`bottom`.
   - customize_page_test: donut-chan shows 8 chips in order (`Tóc, Mắt, Váy, Nơ & huy hiệu, Tất, Giày, Miếng dán, Phụ kiện`); unset chip swatch equals the original colour; the picker's initial colour for an unset part equals the original (not black).

## 9. Mandatory Verification (host, coordinator)

### RED — RED-154
`flutter test --no-pub test/features/avatar/avatar_model_test.dart test/features/avatar/avatar_colors_test.dart test/features/settings/settings_avatar_customize_page_test.dart --plain-name "RED-154"`: stale donut `top`/`bottom` dropped; unset part picker colour is not black.

### GREEN — GREEN-154
Same files `--plain-name "GREEN-154"`: ordered donut chips; original swatches; new parts JSON round-trip.

### Task Buildability Gate
Command: `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings && flutter build web --no-pub`
Result: PASS (coordinator, host)

## 12. Coordinator Audit

Attempts `f7a16849…` (REWORK, AUD-154-1) and R01 `5f60dc78…`. Scope: exact allowlist both times.
Review: four parts appended to `AvatarPart` (wire names = enum names, so JSON decode picks them up); `originalColors` const maps match §6 exactly; donut parts ordered per contract; chip swatch and picker fall back to `originalColors`; Semantics split into label `Màu <part>` + value (hex or `Mặc định`). `restrictTo(model.parts)` already applied at home and in the page (§6.4, no new code).
Host evidence after R01: analyze No issues; RED-154 2/2; GREEN-154 3/3; V4 `flutter test --no-pub` 743/743; `flutter build web --no-pub` ✓.
AC-230 visual (original-colour start on device) is folded into the T156 simulator walkthrough.
Dispatch route: UNVERIFIABLE (explicit gpt-6.2-sol / low). Buildability: PASS.
Verdict: PASS

## 13. Remediation R01 (coordinator audit attempt 1 → REWORK)

Attempt `f7a16849…` committed as the starting point (7131067). Host evidence: analyze clean; RED-154 2/2 pass; GREEN-154 2 pass / 1 fail; V4 742 pass / 1 fail.
AUD-154-1 (Must; test defect): "GREEN-154 Donut-Chan shows ordered parts and original swatches" fails with "A SemanticsHandle was active at the end of the test" — `addTearDown(semantics.dispose)` runs after Flutter's end-of-test handle check. Remove the `addTearDown(semantics.dispose);` line and call `semantics.dispose();` as the last statement of that test body. Nothing else.
Allowed write files (exact): `test/features/settings/settings_avatar_customize_page_test.dart`.
RED-154-R01: record `grep -n "addTearDown(semantics.dispose)" test/features/settings/settings_avatar_customize_page_test.dart` (matches) before editing.
GREEN-154-R01: grep no longer matches and `semantics.dispose();` is present; coordinator reruns GREEN-154 and V4 on host.
