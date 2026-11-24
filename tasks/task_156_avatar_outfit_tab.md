# Task 156 — Avatar customize: "Phối đồ" tab, outfit storage and renderer wiring

Status: READY
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
Result: PENDING

## 12. Coordinator Audit

Verdict: PENDING
