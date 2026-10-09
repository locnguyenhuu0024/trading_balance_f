# Task 106 — Complete responsive forms and automatic direction client

Status: PASS
Agent Role: implementation_executor
Executor Class: E1
Target Model: gpt-6-luna
Target Effort: xhigh
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Dispatch Route Status: UNVERIFIABLE
Requested Model: gpt-6-luna
Requested Effort: xhigh
Observed Effective Model/Effort: unavailable
Plan: docs/agents/plans/2026-10-09-forms-loading-direction.md
Specification: docs/agents/specs/2026-10-09-forms-loading-direction-design.md
Plan Steps: P02
Requirements/Acceptance: REQ-001/002/003/005 / AC-001/002/003/005
Frontend Level: F2
Frontend Design Brief: docs/agents/specs/2026-10-09-forms-loading-direction-frontend-brief.md
Predecessors: none; API contract fixed in specification

## Contract and scope

Implement all inventoried input forms and related dialogs in specification, reusable native form/loading helpers under lib/core/widgets, app_theme.dart presentation, strategy_api_client.dart direction optional field and all affected implementations/test fakes. Tests may change under test/core/theme, test/core/widgets and affected test/features; widget render harness allowed. No main.dart/navigation/web writes (T107 owns); no backend or protected config/dependency/generated source changes. Existing UI source named settings is allowed. Read approved brief/spec and pinned skills/checklist before implementation.

Use 14-16px input/body, supporting >=12px, 48px hit targets, mobile16/desktop24 padding, field gaps12, simple max560/complex max960. Preserve text scaling, tabular numbers, label/focus/paste/validation/session/confirmation. Reflow wide controls, wrap actions, scroll under keyboard insets. Report coverage for EVERY inventoried form (changed or already compliant with evidence). Avoid rewriting data/business logic. Shared helper APIs should remain small.

Async forms use consistent labeled feedback and guard duplicate submits, restore after error and preserve entered values/session fencing. Automatic form defaults both and shows Long/Short/Long&Short; optional API direction default both; direction changes reset requestId; selection locked while pending. Validate returned scope and enforce candidate-review single-side scope; update every fake compile consumer. Legacy missing scope is accepted for both, rejected for explicitly selected single side.

## Verification

RED-106 then GREEN-106: narrow+scaled+keyboard fields/actions usable; pending/error/session fencing and no duplicate submits; mismatched/opposite-side automatic result rejected; all side choices sent/reopened correctly. V3 ceiling affected form/theme/API/screen suites. Render real mobile/desktop light/dark and complex automatic/strategy state PNGs using existing monochrome_portfolio_preview_test.dart pattern, with non-sensitive fixtures. Return absolute PNG paths. Buildability: flutter build web --no-pub after final source/test edit. Do not run concurrent Flutter commands; Python sibling is independent. Native OS/device behavior not implied.

## Stop and report

No protected reads/writes, packages, docs/tasks/telemetry, agents or git writes. No product invention. Return BLOCKED for unresolved contract/scope/config dependency. RTK first eligible output; exact raw source allowed. Return complete coverage table, exact RED/GREEN commands/results/order, tests/build evidence, visual files, external actions and route metadata. Coordinator audit/interface/visual verdict PENDING.

Acceptance note: source/build/visual PASS; final formal negative-boundary RED then success GREEN evidence will be completed by coordinator during integration after T107 releases Flutter ownership. The initial diagnostic failure is not counted as final RED. See coordinator audit.
Final evidence gate closed: coordinator observed9 boundary RED tests PASS before4 success GREEN tests PASS on unchangedfinalsource. Full integration/build tracked in coordinator audit.
