# Decisions: App simplification

Status: ACTIVE
Date: 2026-10-09

D-001: User explicitly authorized autonomous proposed choices, implementation immediately after planning, new branch, commit and push. This overrides the local requirement to ask again after presenting the plan. No deployment or exchange write is authorized.
D-002: Remove the Risk product feature and background owner; preserve shared scheduling and unrelated strategy risk scoring/trade safeguards.
D-003: Remember password only with explicit opt-in after successful login in FlutterSecureStorage, endpoint scoped; never remember OTP. Opt-out deletes immediately, logout retains opt-in. Password errors are generic and never echo input.
D-004: Refresh covers seven remaining destinations plus two detail/settings pages. Preserve current form/draft/selection state and reuse existing read flows. Settings refreshes exchange rate, not saved preference assignments.

Authority for D-002..004: user's explicit instruction to propose and execute choices autonomously, reconciled with inspected source. No open question. All choices are bounded to requested features.
