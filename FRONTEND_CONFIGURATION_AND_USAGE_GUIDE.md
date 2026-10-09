# OptCodex + Ponytail frontend-personal v1.1.0 — Hướng dẫn cấu hình và sử dụng

## 1. Mục đích

Variant này dành cho **web frontend dự án cá nhân**. Nó kế thừa `OptCodex-Personal-v1.2.1`, giữ RTK + Headroom, Ponytail, rồi bổ sung Anthropic frontend-design và các Vercel frontend skills đã pin.

```text
Personal baseline
   ↓
RTK / Headroom
   ↓
Ponytail rules on demand
   ↓
Frontend design + engineering rules
```

## 2. Cài vào repository

Copy toàn bộ nội dung của:

`variants/frontend-personal`

vào root repository cá nhân.

Phải copy cả:
- `AGENTS.md`;
- personal baseline files;
- `docs/agents/framework/profiles/CONTEXT_OPTIMIZATION.md`;
- frontend framework/templates;
- `scripts/`;
- `third_party/`.

## 3. Runtime

Ponytail: chỉ dùng local Markdown rules, không cần API key hoặc plugin.

RTK/Headroom:
- cấu hình theo personal baseline hiện tại.

Anthropic/Vercel vendored skills:
- không cần API key/plugin riêng;
- dùng local Markdown snapshot;
- không tự fetch latest trong product workflow.

## 4. Frontend level

- F0: functional-only.
- F1: design-system extension.
- F2: new/materially reshaped experience.
- F3: brand/design-system/high-visibility.

F2/F3 bắt buộc design brief; visual review dùng rendered evidence khi available.

## 5. Context optimization

RTK/Headroom vẫn là lớp tối ưu context của personal variant.

- shell output đủ điều kiện → RTK trước;
- large non-shell output đủ điều kiện → Headroom trước;
- raw/direct output chỉ fallback theo profile;
- third-party compiled `AGENTS.md` lớn chỉ load khi thực sự cần;
- không đưa dữ liệu bảo vệ qua công cụ tối ưu.

Security/correctness luôn cao hơn token savings.

## 6. Skill activation

| Skill | Khi dùng |
| --- | --- |
| Anthropic frontend-design | F2/F3; F1 khi còn visual choices mở |
| Vercel web-design-guidelines | UI/a11y/interaction audit |
| Vercel react-best-practices | React/Next.js performance/render/data/bundle |
| Vercel composition-patterns | reusable component/API architecture |
| Vercel react-view-transitions | approved transition/motion requirement |

Không load tất cả cùng lúc.

## 7. Workflow

```text
Task
 ↓
Personal baseline
 ↓
RTK/Headroom
 ↓
S/M/L + F0/F1/F2/F3
 ↓
Design brief nếu F2/F3
 ↓
Applicable skills
 ↓
Implementation
 ↓
Verification
 ↓
Pinned UI audit
 ↓
Visual review nếu required/available
 ↓
Independent OptCodex audit
```

## 8. Upstream pins

- Anthropic skills: `41bbe19d1a1a7eaab5e7bb9050a417e5c6cffc8f`;
- Vercel agent-skills: `063bee94c3f4df8453406c830b0a7df0f2860278`;
- Vercel web-interface-guidelines: `434b7f91364665f2f733b310ec54809bf8f37937`.

## 9. Security

Không gửi ra external service:
- source code/diff;
- raw logs;
- screenshots/private assets;
- protected config;
- credentials;
- private project data.

Live upstream refresh chỉ inbound-only.

## 10. Source of truth

Chỉ GitHub `OptCodexRules` là source of truth. Không sync sang Google Drive.
