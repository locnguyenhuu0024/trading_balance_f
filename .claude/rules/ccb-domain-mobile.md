# CCB Domain — Frontend Mobile (native / cross-platform)

**Applicability:** Select ONLY for mobile-app projects via the CCB installer --domain mobile. This is a scoped supplement to the pinned OptCodex `company` or `personal` baseline. It never substitutes for the OptCodex binding AGENTS.md and does not modify E0/E1/E2 model routing.

## Mobile-specific planning

- Classify the platform before making design decisions: iOS SwiftUI/UIKit, Android Jetpack Compose/Views, Flutter, React Native/Expo or hybrid. Do not assume a web DOM, Vite, Next.js or Vercel environment.
- Check project-owned design system, OS conventions, accessibility (VoiceOver/TalkBack, dynamic type, contrast and touch targets), localization, safe areas, keyboard handling, dark mode and motion-reduction requirements.
- Include navigation/back-stack, lifecycle/background states, permission prompts, push/deeplink flow, offline/cache/retry states, release channel and OS version support whenever affected.
- Keep platform behavior, API boundaries, persistence, error semantics and device-specific acceptance cases explicit before approval.
- Scope mobile testing to native build unit and relevant unit/UI/device/simulator checks. For iOS, prefer Xcode scheme build/tests; for Android, Gradle task(s); for Flutter, Flutter test/build; for React Native, native build plus JS tests as applicable.
- If the feature also alters a backend service, follow OptCodex mandatory independent planning-workstream fan-out. Coordinate cross-repository API contracts before implementation.

## Executor and audit

- Executor defaults follow v3: E0 Terra/low; E1 Terra/medium; E2 Sol/low; E3 Sol/medium; E4 Sol/high; E5 Sol/xhigh. A different allowlisted route requires explicit task approval; there is no automatic fallback. Preserve native mobile lifecycle/build/UI testing.
- Preserve strict approval, protected-config restrictions, RED→GREEN, task buildability and final repository build, independent audit and company QA handoff where applicable.
- Do not apply web-specific F0–F3 or pinned React/Vercel rules to native-only UI unless the project explicitly uses the relevant web technologies.
