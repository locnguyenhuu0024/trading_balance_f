# Frontend Design Rules — OptCodex + Ponytail frontend-personal v1.1.0

> Progressive frontend design and engineering layer. Load for user-facing web UI work. This file integrates, constrains and routes the vendored Anthropic/Vercel guidance.

## 1. Purpose

Frontend quality has two independent axes:

1. **visual/product design quality** — intentional hierarchy, typography, layout, content, motion and identity;
2. **frontend engineering quality** — semantics, accessibility, responsive behavior, performance, component architecture and runtime correctness.

Do not optimize one by sacrificing the other.

## 2. Precedence and conflict resolution

Apply, in order:

1. explicit user instruction / approved product brief;
2. personal baseline safety/correctness and protected-config rules;
3. deterministic hard gates and the RTK/Headroom context-optimization profile;
4. repository-native design system, brand tokens, component conventions and established interaction vocabulary;
5. explicit accessibility/compliance standard and observable product behavior;
6. this integration file;
7. applicable vendored upstream skill;
9. generic design preference.

### Vercel-specific preferences are not universal

The pinned Vercel interface guidelines contain some Vercel brand/product preferences (for example Title Case conventions, `&` preference and Vercel-specific copy choices). Do **not** impose those on unrelated products.

Treat accessibility, semantic HTML, focus, forms, responsive layout, interaction, reduced motion, hydration safety, i18n and performance rules as cross-product quality guidance when applicable. Treat brand/copy conventions as advisory unless the repository/user explicitly adopts them.

When legal/compliance requirements specify WCAG or another standard, that requirement wins over an upstream preference such as APCA.

### Personal context-optimization interaction

Before repository inspection/verification that may produce shell output or large non-shell output, follow `docs/agents/framework/profiles/CONTEXT_OPTIMIZATION.md`.

- RTK remains first choice for eligible shell-output reduction.
- Headroom remains first choice for eligible large non-shell output reduction.
- Read each vendored `SKILL.md` first; load large compiled `AGENTS.md` only when detailed rules are required.
- Do not use RTK/Headroom as a route to protected content.
- Exact evidence outranks token savings.

## 3. Frontend levels

### F0 — functional-only

Examples:
- event/state/data-binding bug with established UI;
- type/build/test-only frontend change;
- accessibility defect whose desired visual treatment is already defined;
- API integration with no intended visual redesign.

Rules:
- preserve visual treatment unless explicitly in scope;
- do not load aesthetic guidance merely because files are TSX/CSS;
- load Vercel audit/performance guidance only when the changed behavior triggers it.

### F1 — bounded design-system extension

Examples:
- new field, card, table column, modal, settings panel or small screen using an established product system.

Rules:
- reuse repository tokens/components first;
- inspect only the minimum non-protected design-system evidence required;
- Anthropic frontend-design is optional unless material visual choices remain open;
- Vercel web-interface audit is required for changed UI before final acceptance.

### F2 — new/materially reshaped visual experience

Examples:
- new page or flow;
- substantial layout/hierarchy/typography change;
- new dashboard/landing/onboarding experience;
- material responsive or interaction redesign.

Rules:
- read the Anthropic frontend-design `SKILL.md`;
- create `FRONTEND_DESIGN_BRIEF_TEMPLATE.md`;
- perform design-plan anti-generic critique before code;
- identify applicable Vercel engineering skills;
- rendered visual review is required when screenshot/browser evidence is available.

### F3 — brand/design-system/high-visibility

Examples:
- new design system or product shell;
- brand-defining marketing surface;
- major navigation paradigm;
- motion-led flagship experience;
- high-visibility visual work where failure is reputationally material.

Rules:
- all F2 gates;
- design planning/critique uses at least an R3 reasoning route unless baseline requires stronger;
- visual-review artifact is mandatory;
- implementation executor must not invent unresolved tokens, interaction semantics or component-system decisions.

F-level and S/M/L planning tier are separate dimensions.

## 4. Skill activation matrix

| Source | Load when | Do not use as |
| --- | --- | --- |
| Anthropic `frontend-design` | F2/F3; F1 with material open visual choices | backend architecture, security policy, accessibility substitute |
| Vercel `web-design-guidelines` + pinned interface checklist | F1–F3 final UI audit; F0 when semantics/forms/a11y/interaction are touched | product brand voice authority |
| Vercel `react-best-practices` | React/Next.js work involving fetching, rendering, bundle, client/server boundaries, re-renders or performance | reason to add dependencies or refactor unrelated code |
| Vercel `composition-patterns` | reusable component APIs, boolean-prop proliferation, compound components, shared state architecture | mandatory pattern for simple local components |
| Vercel `react-view-transitions` | approved route/state/shared-element/list transition requirement | invitation to add decorative motion |

For Vercel skills, read `SKILL.md` first. Load compiled `AGENTS.md` only if the detailed rules are needed.

## 5. Brief grounding gate

Before F2/F3 design planning establish:

- product/subject and real domain;
- primary audience;
- primary user job;
- target surfaces and viewport expectations;
- existing brand/design-system constraints;
- representative real content;
- required loading/empty/success/error/disabled/permission states;
- interaction/motion constraints;
- accessibility/compliance requirements;
- explicit user preferences and anti-preferences.

If a material product/design semantic is unknown and cannot be derived from safe repository evidence, use the baseline clarification gate. Do not disguise missing requirements as creative freedom.

## 6. Two-pass design plan

For F2/F3, use the design brief template.

Pass 1:
- 4–6 named color tokens with hex values;
- typography families/roles/type scale;
- layout concept and alignment;
- compact ASCII wireframe(s);
- spacing/radius/border/shadow direction when material;
- motion intent;
- copy/content tone;
- one memorable visual idea and restraint around it.

Pass 2 — anti-generic critique:
- compare every free design axis against generic AI/SaaS defaults;
- remove decorative labels, cards, gradients, motion or numbering that carry no information;
- preserve any generic-looking treatment that is explicitly required by the brief/design system;
- record what changed and why.

Do not code F2/F3 before this pass is complete and the baseline approval requirements are satisfied.

## 7. Repository-native design systems

Existing systems outrank novelty.

Before introducing new tokens/components:
- locate existing color/type/spacing/radius/motion tokens using safe repository inspection;
- reuse established primitives when they satisfy the brief;
- avoid a second design system inside one product;
- do not add a font/icon/component/animation dependency solely because an upstream skill suggests a technique;
- dependency changes remain governed by the approved plan and baseline scope.

For an explicit redesign, document which existing conventions are intentionally replaced.

## 8. React/Next.js engineering gates

Only apply React-specific Vercel rules when the project is actually React/Next.js and the relevant runtime/version supports them.

Priorities:
1. avoid async waterfalls where architecture permits;
2. control bundle cost;
3. preserve server/client boundaries and serialization discipline;
4. avoid unnecessary re-render work;
5. keep hydration deterministic;
6. optimize only after correctness and scope.

Never introduce SWR, a cache library, a view-transition dependency, React canary, or another package just to satisfy upstream prose. Prefer the repository's existing stack. Any dependency/version change requires normal OptCodex approval.

Version-sensitive guidance such as React 19 APIs or ViewTransition support must be checked against the target project's actual package/runtime versions.

## 9. Web-interface audit gate

Use the pinned local checklist at:

`third_party/vercel-labs/web-interface-guidelines/command.md`

rather than silently fetching new rules.

Audit changed UI for applicable:
- semantic HTML and keyboard operation; native semantic controls count as keyboard-operable without redundant key handlers unless custom behavior actually requires them;
- visible unobscured focus;
- labels, form behavior, validation and paste;
- reduced motion and interruptible motion;
- responsive/overflow/safe-area behavior;
- image dimensions/loading/alt;
- loading/empty/error/dense states;
- locale-aware formatting;
- hydration safety;
- interaction/touch behavior;
- performance regressions introduced by the change.

Findings must be scoped to changed or materially affected UI. Do not opportunistically rewrite the whole application.

A live refresh of the Vercel checklist is maintenance work, not normal product work. Fetch inbound-only, diff against the pin, review conflicts, then version this ruleset before adopting changed rules.

## 10. Motion gate

Motion must communicate continuity, state change, hierarchy or deliberate emphasis.

- do not add motion only because a skill is available;
- honor `prefers-reduced-motion`;
- prefer transform/opacity and compositor-friendly techniques;
- motion must be interruptible where user input can change the state;
- route/list/shared-element transitions require a semantic reason;
- use the view-transition skill only when the actual React/runtime support is verified.

For F2/F3, spend boldness in one orchestrated motion idea rather than many unrelated animations.

## 11. Visual evidence gate

When rendering/screenshot tooling is available:

F2 minimum:
- one representative mobile viewport;
- one representative desktop viewport;
- critical state(s) affected by the task.

F3 minimum:
- mobile;
- desktop;
- wide desktop when the layout uses the width materially;
- all critical interactive/error/empty states affected.

Review screenshots against the approved brief, not against generic taste.

Check:
- visual hierarchy and reading order;
- type scale/line length/wrapping;
- alignment and spacing rhythm;
- clipping/overflow;
- long/short content resilience;
- contrast and status redundancy;
- focus visibility where capturable;
- responsive behavior;
- motion/reduced-motion behavior when material;
- anti-generic critique findings.

If visual evidence is not available, mark visual status `UNAVAILABLE` or `BLOCKED_EVIDENCE`. Do not claim visual PASS solely from code.

## 12. Copy and content

UI copy is part of product behavior.

- product vocabulary and user mental model outrank implementation terminology;
- action labels describe the result;
- the same action name remains consistent through the flow;
- errors state the problem and a recovery action when known;
- empty states give a useful next step;
- user/brand style guide wins over Anthropic/Vercel stylistic defaults.

Do not automatically apply Vercel Title Case or `&` preferences outside products that adopt them.



Allowed:
- existing `classify_task`, `route_executor`, `evaluate_result`, `score_context`;
- `score_context` may rank optional design/reference categories.

Not allowed:
- using a low context score to omit mandatory frontend rules/briefs/a11y constraints;

## 14. Frontend-safe telemetry

The frontend variant may record bounded fields:
- `frontend_level`: F0/F1/F2/F3;
- `frontend_skills_loaded`: identifiers only;
- `design_brief_status`: N/A/DRAFT/APPROVED;
- `web_guidelines_audit`: N/A/PASS/FINDINGS/BLOCKED;
- `visual_review_status`: N/A/PASS/REWORK/UNAVAILABLE/BLOCKED_EVIDENCE.

Never put screenshot pixels, source bodies, design assets, raw UI copy dumps or protected configuration into telemetry.

## 15. Completion gate

For applicable frontend work:
- baseline verification gates pass;
- design brief approved when required;
- unresolved visual/product decisions did not leak to executor;
- applicable Vercel engineering guidance was reviewed;
- web-interface audit has no unresolved blocking finding;
- responsive/a11y/state requirements are verified to available evidence;
- visual review PASS when required and evidence is available;
- unavailable visual evidence is reported honestly;
- no out-of-scope redesign or dependency expansion occurred.
