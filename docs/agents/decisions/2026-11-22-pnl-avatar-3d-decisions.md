# Decisions: PnL-reactive 3D avatar

Status: ACTIVE
Specification: `docs/agents/specs/2026-11-22-pnl-avatar-3d-design.md`
Plan: `docs/agents/plans/2026-11-22-pnl-avatar-3d.md`

## Clarification Questions

### Q-030 — Platforms
Status: ANSWERED
Question: Which platforms render the avatar in the first release?
Why it matters: web needs a separate iframe host and an extra dependency.

### Q-031 — Mood driver
Status: ANSWERED
Question: Which PnL percentage drives the mood?

### Q-032 — Thresholds
Status: ANSWERED
Question: Which thresholds switch the mood?

### Q-033 — Placement and model delivery
Status: ANSWERED
Question: Where does the avatar sit on the home screen, and is the model bundled or downloaded?

## User Decisions

### D-030 — All platforms
Source question: Q-030
Decision: iOS, Android, macOS and web (all platforms present in the repository).
Impacts: REQ-212, AC-214, P03, T148

### D-031 — Headline ratio
Source question: Q-031
Decision: Use the headline PnL percentage shown on the home screen (`headlineRatio`, which is the combined ratio when the combined view is active).
Impacts: REQ-210, AC-210, P02, P03, T147, T148

### D-032 — Thresholds ±1% / ±5%
Source question: Q-032
Decision: |r| ≤ 1% neutral; 1% < |r| < 5% mild happy/sad; |r| ≥ 5% strong happy/sad.
Impacts: REQ-210, AC-210, AC-211, P02, T147

### D-033 — Floating corner, bundled model
Source question: Q-033
Decision: Floating, draggable widget in a screen corner over the home content; the model ships inside the app (offline).
Impacts: REQ-212, REQ-214, AC-215, P01, P03, T146, T148

### D-034 — Female character
Source: user message on 2026-11-22 ("tôi muốn nhân vật nữ nhé")
Decision: The character must be female. Seed-san (female, anime style) satisfies this; any replacement model must also be female.
Impacts: REQ-214, P01, T146

## Coordinator design decisions (inside approved scope, presented for plan approval)

- CD-1: Flutter owns all pointer input over the avatar and forwards normalized pointer samples to the page; the page classifies gestures using projected bone regions. Reason: identical behavior on WebView and iframe, no platform-view gesture arena conflicts. (WS2 proposed WebView-owned short gestures; overridden.)
- CD-2: Avatar drag position is in-memory only and resets to bottom-right when the home screen is rebuilt (tab or scope switch). Persisting position is out of scope.
- CD-3: The JS bundle is built from a committed build script that installs pinned npm packages into a temporary directory; no `package.json` is added to the repository (protected manifest).
- CD-4: On any runtime `error` (WebGL unavailable, context lost, model parse failure) the overlay hides itself for the life of the screen; the setting is unchanged.

### D-035 — Switch model to the pixiv female sample
Source: T146 audit (2026-11-22). Rendering showed Seed-san with short hair and an androgynous look; the coordinator's earlier claim that Seed-san was a long-haired female was wrong (not visually verified at the time).
Decision (user, 2026-11-22): use `VRM1_Constraint_Twist_Sample` from `vrm-c/vrm-specification/samples` — female, long brown hair, anime style; (c) 2022 pixiv Inc.; VRM Public License 1.0 with commercialUsage `corporation`, allowRedistribution `true`, modification `allowModificationRedistribution`, creditNotation `unnecessary`. The app still credits pixiv. Bundled file renamed `assets/avatar/avatar.vrm`.
Supersedes: Seed-san choice in OBS-221 / REQ-214 / REQ-215.
Impacts: REQ-211, REQ-214, REQ-215, AC-216, AC-217, T146 (R01), T147, T148

### D-036 — Coordinator edits pubspec.yaml assets (user instruction)
Source: user message 2026-11-22 ("Bạn tự thêm đi") after being asked to add the asset entry.
Decision: one-off exception to the protected-configuration boundary, authorized by direct user instruction (baseline priority 1). The coordinator read only the `flutter:` section (lines 71–82) and inserted `assets: - assets/avatar/`. No other protected file read or changed. Not a standing permission.
Impacts: T148 precondition (spec §17 item 2)

## Revision 2 (2026-11-22) — model picker, Donut-Chan, render quality

### D-037 — Render quality
Source: user report (Android APK works; character blurry, jagged edges) + question.
Decision: textures capped at 1024 px (was 512), MSAA antialias on, pixelRatio `min(devicePixelRatio, 3)`.
Impacts: REQ-216, T149

### D-038 — Model picker UI
Decision: a Settings sub-page listing bundled models with a small thumbnail, name and credit/license; selection persists and the home avatar switches.
Impacts: REQ-218, REQ-219, T150

### D-039 — Add Donut-Chan
Source: user selected it from the candidate list and supplied the download (`~/Downloads/Donut-Chan/Donut-Chan.vrm`).
Evidence: VRM 0.x meta `commercialUssageName: Allow`, `allowedUserName: Everyone`, license "Public Domain" (author Kana Fuyuko); bundled `Thank You.txt`: "she is under Public Domain". Booth page titled CC0, "you don't have to credit". Visual check: blonde hair, cat ears, heart-shaped ahoge, pink dress (female) — rendered in the coordinator's local browser test.
Impacts: REQ-217, T149, T150

### Coordinator design decisions (presented with revision 2 for approval)
- CD-5: Model ids and files: `pixiv-sample` → `assets/avatar/pixiv-sample.vrm` (replaces `avatar.vrm`), `donut-chan` → `assets/avatar/donut-chan.vrm`; thumbnails `assets/avatar/<id>.png` (256 px, extracted from each VRM's embedded thumbnail). Default model `pixiv-sample`.
- CD-6: Switching model recreates the host (widget keyed by model id); no new bridge message. Web passes `?model=<id>` validated by an allowlist in the page; native sends the chosen asset's bytes.
- CD-7: Donut-Chan morph targets re-encoded as glTF sparse accessors (lossless; three.js decodes natively) to cut ~6 MB; verified by a decode round-trip equality check. Blendshape groups are not pruned.
- CD-8: The CCB dispatcher allowlist must accept `.png` for the thumbnails (needs explicit user approval; same pattern as the `.vrm` addition).
