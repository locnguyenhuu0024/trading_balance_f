# Frontend Design Brief: Forms and motion

Status: APPROVED
Frontend Level: F2
Specification: docs/agents/specs/2026-10-09-forms-loading-direction-design.md
Plan: docs/agents/plans/2026-10-09-forms-loading-direction.md

## Grounding

Personal Flutter trading portfolio for market inspection and deliberately confirmed orders. Targets web/mobile/Windows/macOS; real content includes Vietnamese field labels, USDT SWAP instruments, credentials, margin, leverage, level selection and settings. Preserve established monochrome AppPalette, AppTokens, system font, tabular numbers and text-scale preference. User delegates design proposals and execution.

## States and constraints

Default, pending read, pending submit, empty options, success, actionable error, disabled, expired session and long/dense content. Keep input values during recoverable failure and move focus/announce errors where supported. Never block paste. Material focus/tap semantics, 48px targets, keyboard inset and safe area. No new packages/fonts/icons, decorative data or credentials in fixtures. Use disableAnimations/accessibleNavigation plus CSS prefers-reduced-motion.

## Two-pass visual plan

Core roles use existing values: background #FFFFFF/#101010, surface #F7F7F7/#1A1A1A, ink #151515/#F4F4F4, muted #595959/#B8B8B8, border #D6D6D6/#414141. Preserve profit/loss semantics already provided by app.

Use existing system Material family. Body/input 14-16px, heading 18-22px, supporting labels at least 12px; all scale with app/OS text preference. Form line lengths below roughly 80 characters. Left align labels and fields. Simple forms/dialogs max 560px; complex strategy review max 960px. Mobile padding16, desktop24, field gap12, section gap24; existing radii8/12/16 and restrained borders. Reflow side-by-side controls when width/text scale needs it. Do not turn every subsection into a card.

```text
Mobile                         Desktop
[title                  close] [        bounded form column        ]
[label + input               ] [label + input][related control     ]
[next label + input          ] [validation / pending feedback       ]
[inline error / busy         ] [                   cancel][action  ]
[cancel] [primary action     ]
```

One continuity idea: a quiet startup progress mark hands off to content; destination changes use 140/220ms opacity motion. Form submissions replace action content with labeled progress without changing button bounds. No staggered card animations or fake progress percentages. Reduced motion makes transitions immediate and loading static/labeled.

Vietnamese copy remains domain-specific; loading labels end in ellipsis. Long/Short/Long&Short wording follows the user.

Anti-generic critique: retain monochrome because it is established; reject new gradients, ornamental cards, headlines and font packages. Keep motion focused on actual asynchronous state and destination continuity. Layout changes follow form task relationships, not an arbitrary dashboard kit.

## Guidance and review

Loaded pinned Anthropic frontend-design and Vercel web-design-guidelines with local command.md; React skills are N/A for Flutter. Independent audit checks labels/focus, paste, error/loading, scrolling, long content, responsive layout, reduced motion and touch targets. Render representative mobile+desktop forms and critical loading/side states using existing Flutter PNG harness where available. Record unavailable native device/OS evidence honestly.

Approval: D-001/A-001; design choices grounded, anti-generic pass complete, no open decisions.

Accepted compatibility refinement D-003: preserve native Cupertino route transitions and back-swipe on iOS/macOS, using settled animations for reduced motion while retaining stable page identity. Other platform route fades are220ms forward/reverse; all destination fades140ms. Avoid remounts, duplicate reads, extra interaction clocks and delayed reverse fades.
