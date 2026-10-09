# Task108 — Orders filter reflow integration

Status: PASS
Agent Role: implementation_executor
Executor Class: E1
Target Model: gpt-6-luna
Target Effort: xhigh
Route Binding: EXPLICIT
Parent Route Inheritance: FORBIDDEN
Dispatch Route Status: UNVERIFIABLE
Plan: docs/agents/plans/2026-10-09-forms-loading-direction.md
Specification: docs/agents/specs/2026-10-09-forms-loading-direction-design.md
Frontend Design Brief: docs/agents/specs/2026-10-09-forms-loading-direction-frontend-brief.md
Frontend Level: F2
Requirements/Acceptance: REQ-001/005 / AC-001/005
Plan Step: P04 — observed integration remediation

Observed full Flutter regression:529 passed,1 failed outof530. Focused reproduction positions filters and close-all stay aligned without overflow fails because old test assumes same-row filters at320px; new intentional responsive form puts fields at y64/124. Preserve reflow instead of restoring squeezed fields.

Allowed writes: lib/features/orders/presentation/widgets/order_filter_controls.dart; lib/features/orders/presentation/orders_screen.dart only minimal filter/closeAll parent alignment if actual render confirms need; test/features/orders/orders_screen_refresh_test.dart; existing order_filter_controls_test.dart/orders_screen_mobile_layout_test.dart and focused actual render harness if needed. No other product/tests/config/docs/git/telemetry/agents.

Body/input labels14–16; minimum48px actions; readable narrow/large text fields. Actual parent view must keep closeAll/refresh visible, inbounds, nonoverlapping and aligned with appropriate row of stacked filters. Test contract may accept stack atnarrowwidth but must retain geometry/action/input behavior; no broad assertion deletion. Existing session, active-provider refresh, confirmation and trading action semantics unchanged.

Formal RED: actual narrow/enlarged OrdersScreen has no overflow/overlap, cannot submit disabled closeAll/refresh, reflow follows availablewidth. Then GREEN: filter/tab selection and manual refresh preserve correct callbacks/providers; action targets48px. Relevant V3 filter/refresh/mobilelayout tests only. Root owns final fullsuite and fresh webbuild, serving taskbuild too. Render actual mobile320/390 scaled and desktop; no fake mockup.

Return exact command/result/order and allowedsource/render paths. Route effective unavailable. Audit PENDING.

Additional bounded typography gap FE108002: independent R2 audit classified settings_screen.dart explicit13px styles at251(timezone),403(theme),496(currency),619(textscale) as primary selectable form inputs, below approved14–16px. Allowed correction adds this file for four14px style changes plus minimal actual narrow/scaled layout correction only if observed, and existing settings timezone/currency/navigation tests or actual SettingsScreen geometry/render tests. Supporting12px text and chartannotations unchanged. Verify real narrow/scaled settings input layout, not source-string checks. Requirement unchanged; no config/dependencies/providers/business rewrites.
Actual caller correction: owning filter/closeAll Row is in lib/features/orders/presentation/widgets/trade_account_controls.dart. This file is now allowed only for minimal crossAxisAlignment.end alignment and associated focused tests. OrdersScreen itself need not change if delegation is sufficient. Preserve48px actions, confirmations/session/data boundaries; no unrelated control rewrite.
Final confirmed typography roles FE108003: fractal_screen.dart coinpreset selectable value at1012 is12px, allowedexact14px correction preserving48px target/selection; trade_account_controls.dart lookupaction label at192 allowed14px/inheritnativebuttonfont. Include existing fractal priceformat/presetinteraction and affected order/session/cancellation tests as needed. Independent auditor classified every remaining explicit12px as supporting/chart/status/error; no further font sweep.


Observed FE108004 actualSettings320/1.6 trailing dropdown overflow and dense textscale33.6px target: move affected selectors tofullwidthsubtitles oncompact breakpoint, remove dense override; preservelabels/currentvalues/storagecallbacks. FE108005 theme-native selectedtypography: derive six dropdownstyles fromTheme.textTheme.bodyMedium.copyWith(fontSize14, existingcolor/weight) insteadbareTextStyle toretainnativefontinheritance. CaptureharnessloadsSDKRoboto/MaterialIcons; no manualPNG edits.

Finalsource/visualPASS; boundary2 thenGREEN95PASS. Finalwebbuild taskgate shared with coordinator finalbuild, pending. Exactevidence incoordinatoraudit.

Final shared webbuildexit0 afterlastcode/tests closes taskbuildgate; finalauditPASS and532FluttertestsPASS. Exactevidence coordinatoraudit.
