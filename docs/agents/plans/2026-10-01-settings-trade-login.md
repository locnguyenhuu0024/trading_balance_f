# Implementation plan: Settings trade login

Status: READY_FOR_IMPLEMENTATION
Specification: `docs/agents/specs/2026-10-01-settings-trade-login.md`

1. T1 backend: extend the existing session service with eight-hour absolute expiry, secure cookie issuance/clearing, read-only cookie restore endpoint, and credentialed CORS. Keep bearer-only trading writes. Add focused session/expiry/CORS tests. RED before GREEN; verification ceiling: backend trade API test file.
2. T2 frontend: move the existing read-only key form to a Settings subpage, put trade login/logout/status there, remove auth buttons from Positions, and add web session restoration through credentialed requests. Keep all position action safety controls. Add focused widget and client/provider tests. RED before GREEN; verification ceiling: affected Flutter test files.
3. Coordinator integrates, independently audits changed source/tests and source-level security invariants, runs focused verification and `git diff --check`. Escalate to broader tests only for shared-surface failures.

Implementation route: T1 and T2 are E1 implementation_executor, `gpt-6-luna` / `xhigh`, explicit model and effort; parent route inheritance forbidden. Executors may write only assigned source/tests, not protected configuration. Coordinator owns docs, decisions, Git integration, and audit.

External user-owned action: after code delivery, rebuild/recreate the production backend container and deploy the web build. No configuration value change is required if `ALLOWED_WEB_ORIGIN` already names the live web origin. Verification of that condition belongs to the server owner without sharing its value or environment file contents.
