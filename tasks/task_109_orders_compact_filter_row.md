# Task109 — Compact Orders filter row

Status: PASS
Plan: docs/agents/plans/2026-10-09-orders-compact-filter-row.md#P01
Frontend Level: F1
Required Frontend Guidance: pinned web-design-guidelines
Visual Review Required: YES
Agent Role: implementation_executor
Executor Class: E1
Target Model: gpt-6-luna
Target Effort: xhigh
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Dispatch Route Status: UNVERIFIABLE

## Contract
Implement P01 exactly: one compact row, select pair capped286px, each <=140px,6pxgap,13pxtext/18pxicon,40pxvisibleborder; close-all36pxvisibleborder/18pxicon; all controls retain48pxhitheight. Flex narrower at320px. Labels accessible, ellipsized selected text has full accessible value, menu labels intact, native focus retained. Only presentation changes.
Allowed product paths: lib/features/orders/presentation/widgets/order_filter_controls.dart and trade_account_controls.dart; orders_screen.dart only if caller adjustment is needed. Allowed tests: test/features/orders/order_filter_controls_test.dart, orders_screen_refresh_test.dart, position_actions_test.dart. Use ignored build previews/logs. No task/doc/telemetry edits by executor.
Forbidden: protected configuration read/write/contentdiff, unrelated source/refactors/backend/dependencies, Git mutations/commit/push, executor-created agents.

## Verification
Formal RED first: boundary test with320px/1.6 and longest selections or signed-out disabled controls, expected no overflow/action. GREEN second: focused callback/compact actual Orders geometry tests then relevant group. Existing tests expecting stacked filters must change to user's new single-row contract, preserving callback, safety and48pxhit assertions.
Canonical build command: `C:\Users\Loc\develop\flutter\bin\flutter.bat build web --no-pub`. Required after last executable change; coordinator may run final build after your report, so return build gate PENDING if delegated to coordinator.
Return exact commands/results/order, preview paths, changed paths, protected-content confirmation, external configuration actions none, compact telemetry (logical runE1-T109-001, usage/effective route unavailable).

## Ledger and audit
- [x] Implementation
- [x] RED before GREEN
- [x] Relevant tests
- [x] Fresh canonical build
- [x] Visual/interface review
- [x] Protected boundaries
Coordinator Verdict: PASS

## Review checkpoints
- Initial regression RED: revised Orders same-row assertion failed against original source (selector top124 versus64), proving existing stacking. This is pre-implementation reproduction; final formal negative/boundary checkpoint is still required after remediation.
- Initial scoped group:57 passing tests. Later vertical-alignment edits invalidate affected filter/Orders test and screenshot evidence.
- AUD-109-01: coordinator viewed real320px/1.6 and1280px screenshots; labels/chevrons sat near the top of their40px faces. Executor must center content, add actual rendered geometry assertions, regenerate previews and rerun invalidated checks before build.
- Native focus border restored and opaque face moved behind native control during implementation review; no unresolved overlay finding.
- Effective child model/effort unavailable; requested explicit Luna/xhigh recorded. Runtime has no close/release primitive; terminal lifecycle limitation will be recorded without claiming release.

## Final audit evidence
AUD-109-01 resolved with native InputDecoration verticalpadding12px. Actual selected value and chevron center within2px of40pxface in allfiveviewport scenarios. Coordinator reopened320px/1.6 and1280px PNGs and accepted centered, legible one-row results. Enlarged320px FUTURES ellipsizes; actual SemanticsData exposes full label/value. Native outline focus remains visible; nativedropdowns/tooltips, confirmations, conditionalvisibility, disabledstates and themecolors remain intact. No backend logic changes.

Final source/test state:
- `C:\Users\Loc\develop\flutter\bin\flutter.bat test test/features/orders/order_filter_controls_test.dart test/features/orders/orders_screen_refresh_test.dart test/features/orders/position_actions_test.dart --no-pub`:57/57 PASS, exit0.
- `dart format --output=none --set-exit-if-changed` on fiveallowedpaths:0 changed, exit0 (executor).
- Additional coordinator formal checkpoint corrects missing final negative-before-success evidence: first `C:\Users\Loc\develop\flutter\bin\flutter.bat test test/features/orders/orders_screen_refresh_test.dart --no-pub --reporter expanded --plain-name 'RED-102 signed-out orders keeps refresh visible and disabled'`:1PASS exit0; then samecommand with `--plain-name 'positions filters stay compact beside close-all without overflow'`:1PASS exit0. No executable files changed afterward.
- RTK initially lost quoting around the spaced plain-name argument, causing test-loader failures for splitwords; this was tool forwarding failure, not product failure. Direct narrowly scoped rerun used for exact argument fidelity.
- Fresh canonical/final build: `C:\Users\Loc\develop\flutter\bin\flutter.bat build web --no-pub`, exit0,117.6seconds, Builtbuild/web. Output retained in ignored `build/orders-compact-final-web-build.log`; existingsecurestorageWasm-dry-run andCupertinoIcons warnings remain. StandardwebJSbuild verified, noWasm/native/deviceQAclaim.
- Unchanged backend `python3.12 -m compileall -q backend`:exit0.
- `git diff --check`:exit0; status/name-only then allfiveallowedcontentdiffs inspected. Only2product/3testfiles pluscoordinatorownedplan/task/telemetry changed. Protected configuration content neither read nor modified; external configuration actions none.
- Pinned web-interface audit:PASS for changed native controls, readable fonts, focus, full semantics,48pxhitheight, overflow, theme and preserved trade safety. NoReact-specific guidance applies.

Visual artifacts (ignored): `build/forms-preview/orders-filters-mobile-320.png`, `orders-filters-mobile-320-scale-1.6.png`, `orders-filters-mobile-390.png`, `orders-filters-mobile-390-scale-1.6.png`, `orders-filters-desktop-1280.png`. Generated from realFlutter widget render withRoboto/MaterialIcons; actualOS/browser/liveexchangeQA not performed.
