# Task 156 — Avatar customize: "Phối đồ" tab, outfit storage and renderer wiring

Status: PASS
Agent Role: implementation_executor
Executor Class: E3
Target Model: gpt-6.2-sol
Target Effort: medium
Target Route: gpt-6.2-sol / medium
Routing Policy: EXECUTOR_ROUTING_POLICY.json v3 (OptCodex v1.5.1)
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Specification: `docs/agents/specs/2026-11-22-pnl-avatar-3d-design.md` (Revision 4)
Plan: `docs/agents/plans/2026-11-22-pnl-avatar-3d.md` (Revision 4, PLAN-20261124-pnl-avatar-3d-r4)
Requirements: REQ-231, REQ-232, REQ-233
Acceptance Criteria: AC-233, AC-234
Decisions: D-045, D-046, CD-16, CD-17, CD-19

## 1. Dispatch Compliance

The CCB dispatcher passes `--model gpt-6.2-sol` and `model_reasoning_effort=medium`. `UNVERIFIABLE` is a valid state.

## 2. Objective

Users pick borrowed items per slot for Pixiv Sample in a "Phối đồ" tab; choices persist, recolour, and appear on the home avatar.

## 3. Preconditions

T154 and T155 PASS. Executor sandbox cannot run Flutter: write complete code, report RED/GREEN `NOT_RUN`, buildability `BLOCKED` with that reason.

## 4. Allowed Scope (exact files)

New: `lib/features/avatar/domain/avatar_outfit.dart`, `test/features/avatar/avatar_outfit_test.dart`.
Modify: `lib/features/avatar/presentation/avatar_renderer.dart`, `lib/features/avatar/presentation/avatar_renderer_native.dart`, `lib/features/avatar/presentation/avatar_renderer_web.dart`, `lib/features/avatar/presentation/avatar_view.dart`, `lib/features/avatar/presentation/floating_avatar.dart`, `lib/features/settings/presentation/settings_avatar_customize_page.dart`, `lib/core/security/secure_storage_helper.dart`, `lib/main.dart`, `lib/features/portfolio/presentation/portfolio_screen.dart`, `test/features/avatar/floating_avatar_test.dart`, `test/features/settings/settings_avatar_customize_page_test.dart`, `test/features/settings/settings_avatar_model_picker_test.dart`, `test/features/portfolio/portfolio_avatar_test.dart`, `test/core/widgets/app_startup_test.dart`.

## 5. Forbidden Scope

Protected files; `assets/**`, `tools/**`; PnL math; unrelated settings.

## 6. Executor Contract

1. `avatar_outfit.dart`: `enum AvatarSlot {outfit('Trang phục'), shoes('Giày'), plasters('Miếng dán')}`; const `AvatarItem {id, donorModelId, slot, label, parts, replacesParts}`:
   - `donut-chan:outfit` (slot outfit, label `Váy Donut-Chan`, parts [dress, bows], replaces [top, bottom])
   - `donut-chan:shoes` (slot shoes, label `Giày Donut-Chan`, parts [shoes], replaces [shoes])
   - `donut-chan:plasters` (slot plasters, label `Miếng dán Donut-Chan`, parts [plasters], replaces [])
   - `itemsForModel(modelId)` → all three for `pixiv-sample`, empty otherwise.
   - `effectiveParts(model, itemIds)`: walk `model.parts`; a replaced part is substituted (once) by the parts of the item replacing it; finally append parts of additive items not yet present.
   - `originalColorFor(model, itemIds, part)`: donor `originalColors[part]` when an equipped item provides the part, else the model's.
   - codec: `decodeAvatarOutfits(String?)` → `Map<String, List<String>>` (never throws; known models; ids in `itemsForModel`; one per slot, first wins; dedupe), `encodeAvatarOutfits` (drop empty lists); `avatarOutfitsProvider = StateProvider<Map<String, List<String>>>((ref) => const {})`.
2. Storage: key `AVATAR_OUTFITS`, `getAvatarOutfitsJson`/`saveAvatarOutfitsJson` (native) + `WebStorageHelper` overrides (`StateError` on failed save); `AppStartupData.avatarOutfits` preload in its own try/catch; provider override.
3. Renderer: `void setOutfit(List<String> itemIds)`. Web: store + send `{'type':'setOutfit','items':ids}`, replay on ready. Native: store, send with the initial messages; after `AvatarModelLoaded` (and on later changes), if any equipped item's donor has not been streamed by this renderer, stream `assets/avatar/<donor file>` as `loadDonorChunk {model, i, n, b64}` (reuse the chunking used for the main model; 512 KiB raw slices; serialize streams; never re-send).
4. `AvatarView`/`FloatingAvatar`: `outfit` parameter; send on init and only on change (`listEquals`). `AvatarError` with code `outfit` must NOT hide the view (other codes still hide).
5. Home: pass `avatarOutfitsProvider[model.id]` filtered by `itemsForModel`; colours restricted to `effectiveParts`.
6. Customize page: when `itemsForModel(model)` is non-empty show a `TabBar` (`Màu sắc`, `Phối đồ`) under the preview (use an index-switched body, not `TabBarView`, inside the existing scroll view); Phối đồ: per slot a choice (`Đồ gốc` or the item label; 48 dp; Semantics `<slot>: <choice>`) and `Bỏ phối đồ` (confirm); outfit draft applies to the preview immediately; colour chips use `effectiveParts` and `originalColorFor`; if the selected part disappears select the first; `_dirty` covers colours and outfit; `Lưu` saves outfits then colours (restrict colours to `effectiveParts`), optimistic providers, roll back both + SnackBar on any failure; `Khôi phục mặc định` resets colours only. Models without items keep today's UI (no tabs).
7. Tests (`RED-156` / `GREEN-156`): effectiveParts for none/outfit/shoes/plasters/all (exact ordered lists); originalColorFor donor swatches; codec (malformed JSON, unknown model/item, two items one slot, dedupe, round trip, empty dropped); startup restore native/web; AvatarView sends setOutfit on init and only on change; `outfit` error keeps the view; customize page: tabs only for pixiv, equipping the outfit swaps Áo/Quần-Váy for Váy/Nơ & huy hiệu, preview receives setOutfit, one Lưu saves both, failure rolls back both, outfit-only change triggers the discard dialog, reset touches colours only; home receives saved outfit (stale ids filtered).

## 9. Mandatory Verification (host, coordinator)

### RED — RED-156
`flutter test --no-pub test/features/avatar/avatar_outfit_test.dart test/features/settings/settings_avatar_customize_page_test.dart test/core/widgets/app_startup_test.dart test/features/avatar/floating_avatar_test.dart --plain-name "RED-156"`.

### GREEN — GREEN-156
Same files plus `test/features/portfolio/portfolio_avatar_test.dart`, `test/features/settings/settings_avatar_model_picker_test.dart`, `--plain-name "GREEN-156"`.

### Task Buildability Gate
Command: `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings && flutter build web --no-pub`
Result: PASS (coordinator, host)

## 12. Coordinator Audit

Attempts `ca14dca8…` (REWORK, AUD-156-1, test only) and R01 `b1d555e0…`. Scope: exact allowlist both times.
Review: `avatar_outfit.dart` per §6.1 (one item per slot via `equippedItems`, first wins); executor-added `decodeAvatarColorsWithOutfits` is required so borrowed-part colours (e.g. `dress` on Pixiv) survive restart — accepted. Native renderer streams each donor once after `AvatarModelLoaded`, serialized, reusing the 512 KiB chunker; `outfit` errors never hide the view (renderer + `AvatarView`). Home restricts outfit to `itemsForModel` and colours to `effectiveParts`. Customize page: tabs only for models with items, index-switched body, selection falls back to the first part, one `Lưu` writes outfits then colours with two-provider rollback (and re-saves the previous outfit if colours fail), reset touches colours only.
Host evidence after R01: analyze No issues; RED-156 7/7; GREEN-156 11/11; V4 `flutter test --no-pub` 761/761; builds web ✓, apk debug ✓, iOS simulator ✓.
iOS Simulator (coordinator, iPhone 16): Pixiv customize page shows tabs "Màu sắc"/"Phối đồ" with original swatches and the picker starting at the original hair colour (AC-230); equipping "Váy Donut-Chan" + "Giày Donut-Chan" streams the donor natively and dresses the preview; colour chips become Tóc/Mắt/Váy/Nơ & huy hiệu/Giày with Donut swatches; recolouring Váy green updates the preview live; "Lưu" then app relaunch → home avatar is Pixiv in the green Donut dress.
Note (pre-existing, not this task): the picker's Semantics label merges HueRingPicker's "Hex" text.
Dispatch route: UNVERIFIABLE (explicit gpt-6.2-sol / medium). Buildability: PASS.
Verdict: PASS

## 13. Remediation R01 (coordinator audit attempt 1 → REWORK)

Attempt `ca14dca8…` committed as the starting point (7fc5d20). Host evidence: analyze clean; RED-156 7/7; GREEN-156 1 fail; V4 760 pass / 1 fail. Product code reviewed and accepted (selection reset, save order, two-provider rollback, outfit error non-fatal, donor streaming once, `decodeAvatarColorsWithOutfits` keeps borrowed-part colours across restart).
AUD-156-1 (Must; test defect) in "GREEN-156 equipping a dress changes the preview and colour parts":
- `find.bySemanticsLabel('Chọn màu Tóc')` finds nothing because the picker node merges HueRingPicker's own text (actual label `Chọn màu Tóc\nHex`). Assert the reset selection instead by the `ChoiceChip` whose label text is `Tóc` having `selected == true` (or `find.bySemanticsLabel(RegExp(r'^Chọn màu Tóc'))`).
- `addTearDown(semantics.dispose)` runs after Flutter's end-of-test handle check (same as AUD-154-1): remove it and call `semantics.dispose();` as the last statement of the test body.
- The initial `tester.tap(find.text('Áo'))` warns that it misses the hit test; use the file's existing `_tapText` helper (or `ensureVisible` first).
Nothing else.
Allowed write files (exact): `test/features/settings/settings_avatar_customize_page_test.dart`.
RED-156-R01: record `grep -n "Chọn màu Tóc'\|addTearDown(semantics.dispose)" test/features/settings/settings_avatar_customize_page_test.dart` (matches) before editing.
GREEN-156-R01: coordinator reruns GREEN-156 and V4 on host.
