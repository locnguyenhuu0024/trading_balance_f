# Frontend design brief: Multi-user and exchange connections

Status: READY_FOR_APPROVAL
Date: 2026-10-10
Frontend Level: F2
Specification: `docs/agents/specs/2026-10-10-multi-user-okx-binance-design.md`
Plan: `docs/agents/plans/2026-10-10-multi-user-okx-binance.md`

## 1. Product grounding

Audience: invited individual traders monitoring personal OKX/Binance accounts on Flutter web and Android. Primary job: quickly identify the selected account, inspect fresh balances/positions/orders, and perform a deliberate action on that account. Connection setup is secondary to this daily workflow.

Representative content: `OKX · Tài khoản chính`, `Binance · Futures`, `BTC-USDT-SWAP`, `BTCUSDT`, independent long/short legs, USDT/VND values, partially filled orders, expired API permissions and a disconnected exchange. Names may be 1–80 characters. Show exchange symbol and market instead of assuming identical instrument naming.

Reuse `lib/core/theme/app_theme.dart`, `lib/core/typography/app_text_scale.dart`, navigation shell/preferences, `responsive_form_content.dart`, `manual_refresh_button.dart`, current trade confirmation and account controls. No new font/icon/UI dependency or React rewrite. User preferences: compact, readable, responsive, fast and safe.

## 2. Required states and flows

1. Invitation activation → username/password → TOTP enrollment → recovery-code acknowledgment → signed-in empty account list. Existing users log in with username/password/TOTP; local biometric unlock cannot replace server authentication.
2. Empty account list: “Kết nối tài khoản” → select OKX/Binance → choose live/demo → show only required credential fields → test permissions/account identity → connection summary → save. OKX requires API key, secret and passphrase; Binance key and secret. Never auto-read clipboard; paste only on explicit action, mask secrets, allow manual input and clear secret form state on success/cancel.
3. Permission summary distinguishes “Chỉ xem” from “Cho phép giao dịch”. Trading requires a recent TOTP step-up; no withdrawal/transfer controls. If permission is unverifiable, trading stays disabled with a recovery action.
4. Account selector shows exchange, nickname, product and live/demo context. Switching immediately clears old private rows, resets account-specific actions/filters as appropriate and shows a skeleton for the new context. Retain unrelated app presentation preferences.
5. Combined overview is explicitly read-only and reports partial/unavailable accounts. Never turn a missing/stale balance into zero. USDT aggregation requires a common valuation timestamp and complete conversion coverage; otherwise show partial totals and unavailable entries.
6. Trading screens always show one selected connection; confirmation repeats account, exchange, market, instrument, side, size and consequence. “Đóng tất cả” applies to supported positions of that connection only; unsupported positions are enumerated before confirmation and remain untouched.
7. A queued/executing operation remains bound to its original account even if the user changes selection. Confirmation is canceled when context changes. Running server strategies continue independently of UI selection and are visible on their owning connection.
8. Lost connection: distinguish saved credentials, validating, syncing, read-only, trade-ready, degraded, reconnect-needed and revoked. Show “Đang kiểm tra trạng thái lệnh…” for UNKNOWN, never a success animation from request acceptance alone. Provide refresh/reconnect only when meaningful; do not suggest repeating an unknown trade.

Loading: localized skeletons with stable geometry; no whole-page blocking spinner for background refresh. Empty: one useful next action. Error: inline problem plus recovery. Disabled: visible reason. Dense content: virtualized rows, stable keys, adaptive number formatting and preserved native disclosure.

## 3. Visual plan — pass 1

Use existing palette roles; no exchange-colored theme duplication.

| Role | Light | Dark | Use |
|---|---|---|---|
| background | `#FFFFFF` | `#101010` | Page |
| surface | `#F7F7F7` | `#1A1A1A` | Sections/forms |
| raised | `#FFFFFF` | `#242424` | Dialogs/selectors |
| ink | `#151515` | `#F4F4F4` | Primary text/action |
| muted | `#595959` | `#B8B8B8` | Secondary text |
| border | `#D6D6D6` | `#414141` | Structure |

Retain existing PnL/danger semantic components; never communicate order side, errors or connectivity solely by color. Typography inherits AppTheme/AppTextScale; proposed screen title 20, section 16, body 14, supporting text 12 logical pixels, numeric tabular figures. Verify 200% text scaling before acceptance. Data aligned by column, labels left-aligned, monetary values right-aligned.

Spacing: existing 4/8/12/16/24/32 scale. Reuse 8/12/16 radii by existing component role. Minimum hit target 48×48 even with a 36–40px visual selector. No decorative shadows, illustrations or gradients. Onboarding content max width 560px; account drawer max 420px; desktop data uses available content width.

```text
Mobile: 360–430px                     Desktop: 1280–1440px
[OKX | Chính v] [Live] [sync]          [Account selector] [Market] [sync] [profile]
[Tài sản] [Vị thế] [Lệnh]             [Existing navigation] [Account data area]
[Search] [market filter]              [Filters] [Refresh] [Scoped actions]
[Instrument / side]                  [Instrument | side | size | price | action]
[Size / price / PnL / action]         [Virtualized rows, inline status]
[Existing native navigation]         [Existing desktop navigation behavior]
```

Distinctive idea: a persistent account context strip, reused in confirmation, makes trade ownership obvious at every consequential step. The data remains visually quiet around it.

Motion: existing 140/220ms only for user-triggered continuity; account selection clears old data synchronously before any animation. Reduced motion removes transitions. No per-price tick animation or status flicker.

Copy: consistent Vietnamese result labels such as “Kết nối tài khoản”, “Kiểm tra kết nối”, “Chuyển tài khoản”, “Chỉ xem”, “Cần kết nối lại”. Technical implementation terms remain in diagnostics, not the normal user flow.

## 4. Anti-generic review — pass 2

- Replace proposed dashboard cards for every account metric with the existing dense data layout; cards only where the mobile component already needs them.
- Replace exchange-brand background washes with textual exchange/live-demo identification and the account strip.
- Remove a repeated welcome hero and decorative numbered steps; steps remain only in actual invitation/connection sequences.
- Keep monochrome palette and native navigation because the repository defines them, even though they are common defaults.
- Do not hide disabled capabilities to make the screen look cleaner: a short reason helps users distinguish platform limits from connection failures.

## 5. Engineering, accessibility and performance gates

Guidance loaded: pinned `third_party/anthropic/frontend-design/SKILL.md`, pinned `third_party/vercel-labs/agent-skills/web-design-guidelines/SKILL.md` and local `third_party/vercel-labs/web-interface-guidelines/command.md`. Local policy overrides upstream live-fetch instructions. React-specific skills are N/A for Flutter. Flutter semantics, focus traversal and native Material controls satisfy equivalent accessibility intent; do not apply HTML syntax literally.

Keyboard: focus returns to account selector after dismissing drawer/dialog; first invalid field receives focus; Enter submits only the active form. Expose account/product/status and disabled reasons in Semantics. Masked secret inputs allow paste; secrets never appear in validation messages or diagnostics. Confirmations require explicit action and are not auto-focused on the destructive button.

Check 360px mobile, 768px tablet, 1440px desktop; long names, 200% text, dark/light, 50–500 rows, partial data, token expiry, capability denial, switch-during-request and UNKNOWN trades. No horizontal clipping of primary controls; preserve safe areas and scroll behavior. Target text contrast ≥4.5:1, large text ≥3:1, and visible focus/control contrast ≥3:1. Audit actual rendered colors.

Performance targets (proposed, not measured): selector acknowledges input ≤100ms p95; correct cached account data ≤300ms p95 and fresh data ≤2s p95 under the spec's network profile; 60Hz frame work ≤16.7ms p95 during 500-row scroll; no offscreen per-account poller. Use Riverpod selective subscriptions, virtualized lists and latest-generation cancellation. Preserve existing refresh behavior and failure messages.

Rendered review is required after implementation: representative mobile/desktop and critical connection/switch/error/confirmation states; Android device check is a launch gate. Status now: NOT_RUN — planning only. Code checks cannot claim visual PASS.

## 6. Approval gate

- [x] Product, audience, job and representative content grounded.
- [x] Required states, design reuse and anti-generic critique documented.
- [x] Accessibility/performance targets and evidence requirements specified.
- [ ] User approves this brief as part of the canonical plan.
- [ ] Implementation and rendered design audit pass.
