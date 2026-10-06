# Decisions: Account JEV Screening Settings
Status: COMPLETE
Specification: docs/agents/specs/2026-10-06-jev-screening-settings-design.md
Plan: docs/agents/plans/2026-10-06-jev-screening-settings.md

D-001: User requests adjustable JEV conditions inside Strategy Settings, authorizes coordinator to propose/resolve choices and execute tasks after planning. Applies REQ-001..004, P01/P02, T88/T89.
A-001: Under D-001, coordinator selects account-scoped defaults4/.6/.4, quality integer0..5, finite probability0..1 with decimal percentage UI, only newly generated recommendations affected, fixed5 per side. Existing saved recommendations remain immutable. No unresolved material questions.
A-002: Additive full settings API with omitted groups preserved, optional typed frontend capability for existing mode-only integrations. Backend-first deployment, no provider operational config changes. Prior explicit user commit/push authorization remains applicable to the completed repository changes; deployment is outside this task.
