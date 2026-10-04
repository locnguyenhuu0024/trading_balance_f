# Small Change Plan: Trade action label and strategy display rounding

Status: COMPLETE
Date: 2026-10-04
Tier: S

## Objective and evidence
P01: make close-all discoverable and strategy numbers readable without changing trading values.
The close-all control in `trade_account_controls.dart` is an icon-only button. Strategy cards, metrics, order rows and financial summaries interpolate raw numbers. The existing adaptive formatter supplies grouped 2 decimals for magnitudes >=1000, up to 4 for >=1, up to 8 below 1.

## Contract
- AC01: visible label `Đóng tất cả vị thế`, warning icon, tooltip, 48px minimum target; preserve authentication/visibility/disabled predicates and confirmation flow. Wrap gracefully at mobile widths.
- AC02: apply magnitude-based adaptive rounding to displayed strategy prices, margins, fees, PnL and contract amounts in screen/wizard/retry summaries. Handle negative values by absolute magnitude, restoring sign. Preserve nonzero values below display precision using compact significant-digit notation. Missing/non-finite values use the existing contextual placeholder. Percent display uses two decimal places. Counts, leverage, IDs, statuses, times and editable input values remain untouched.
- AC03: rounding is presentation-only: models, exact decimals, calculations, selected level identity, requests and submitted prices/sizes remain unchanged. Do not alter the shared formatter's behavior for other screens.

## Scope / task
T76 implements P01 as one E1 executor task (`gpt-6-luna` / `xhigh`, EXPLICIT, parent inheritance FORBIDDEN). Allowed: trade account controls; strategy screen/wizard/retry presentation; a strategy presentation formatter; focused corresponding tests. Coordinator owns plan/task/telemetry. No protected configuration reads/writes, dependencies, backend, deployment or live trades.
Workstreams: frontend presentation material; backend/data non-material (no contract changes). Independence: one material workstream. Fan-out Required: NO; required/actual reasoning agents 0/0; compliance EXCEPTION; skip SINGLE_MATERIAL_WORKSTREAM. Coordinator C1, current fixed runtime retained; no main-route change claimed.
One task avoids extra handoffs for a bounded presentation contract. DAG: T76 -> coordinator audit. User explicitly authorized autonomous decisions and execution after planning in this request; no renewed approval required.

## Verification
RED before GREEN: focused regressions demonstrate absent label/raw long decimals before product edits; GREEN proves visible labeled action and rounded display, including negatives/tiny values and unchanged request data. Preserve existing unavailable/disabled/cancel behavior. V2 ceiling: corresponding orders actions + strategy screen/wizard/retry test files and formatter tests. Escalate only for a concrete related failure. Re-run only invalidated evidence.
Task/final buildability: Flutter web application; `flutter build web --no-pub` after the last executable change, using RTK first. Existing documented canonical route. Other unchanged top-level backend build: `python3.12 -m compileall -q backend`. No config generation or dependency installation.
External configuration/verification actions: none.

## Completion
T76 PASS. RED before source changes observed two intended widget failures for missing label/raw PnL. Final GREEN: 69 tests passed across orders position actions and strategy formatter/screen/wizard/retry tests. Final `rtk proxy flutter build web --no-pub` exited 0 and produced build/web; non-blocking wasm/Cupertino font diagnostics. Unchanged backend top-level `rtk test python3.12 -m compileall -q backend` exited 0. Coordinator reviewed all product/test diffs and new formatter/tests, confirmed unchanged action safety predicates and no request/domain changes; precise wizard input and retry values remain exact. `git diff --check` exited 0. No protected configuration paths changed. Final audit PASS. No further test execution needed: final executor evidence covers approved V2 and build gate. One interim review finding (negative margin validation) was fixed by the executor before final verification. Runtime exposes no child close/release primitive; collected terminal child is not scheduled for reuse.
