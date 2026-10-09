# Frontend Design Brief — <Topic>

Status: DRAFT | READY_FOR_APPROVAL | APPROVED | BLOCKED
Frontend Level: F2 | F3
Specification: <path | N/A>
Plan: <path | pending>

## 1. Product grounding

Product / subject:
Primary audience:
Primary user job:
Target surfaces:
Representative content:
Existing design/brand system:
Explicit user preferences:
Explicit anti-preferences:

## 2. Required states

- default:
- loading:
- empty:
- success:
- error:
- disabled:
- permission/role:
- long-content / dense-content:
- other:

## 3. Constraints

Accessibility/compliance:
Responsive/browser/device:
Performance:
Motion:
Localization/content:
Existing component/token constraints:
Out of scope:

## 4. Skill activation

| Guidance | Required | Why |
| --- | --- | --- |
| Anthropic frontend-design | YES | F2/F3 visual direction |
| Vercel web-design-guidelines | YES | final interface audit |
| Vercel react-best-practices | YES/NO | <reason> |
| Vercel composition-patterns | YES/NO | <reason> |
| Vercel react-view-transitions | YES/NO | <reason> |

## 5. Visual token plan

### Color

Use 4–6 core named colors unless the existing design system already defines the palette.

| Token | Hex / existing token | Role |
| --- | --- | --- |
| <name> | <value> | <role> |

### Typography

Primary family:
Secondary family (if justified):
Body treatment:
Display/headline treatment:
Type scale:
Line-length target:

### Layout

Alignment strategy:
Grid/container:
Spacing rhythm:
Responsive transformation:

ASCII wireframe:

```text
<wireframe>
```

### Shape / surface

Radius:
Borders:
Shadows:
Iconography/illustration:
Other:

### Motion

Primary motion idea:
User-triggered feedback:
Non-user-triggered motion:
Reduced-motion behavior:

### Copy/content

Vocabulary:
CTA naming:
Error/empty-state voice:

## 6. Distinctive idea

One memorable element:
Why it belongs to this product:
What stays deliberately quiet around it:

## 7. Anti-generic review

Potential generic/default choices found:
- <finding>

Revisions made:
- <change + why>

Generic-looking choices intentionally retained because the brief/system requires them:
- <choice + evidence>

## 8. Accessibility and engineering review plan

Keyboard/focus:
Semantic structure:
Contrast/status redundancy:
Forms:
Responsive/overflow:
Images/media:
Loading/hydration:
Performance risks:
React/Next-specific checks:

## 9. Approval gate

- [ ] brief grounded in real product/audience/job
- [ ] required states covered
- [ ] design-system reuse/replacement decision explicit
- [ ] anti-generic review completed
- [ ] accessibility/performance constraints captured
- [ ] open product/design decisions resolved
- [ ] user/baseline approval obtained where required
