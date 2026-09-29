# Coordinator Audit — T28

Task: `tasks/task_28_support-resistance-market-levels.md`
Verdict: PASS

## Evidence reviewed

- Requirements: REQ-002..004; relevant data/calculation portions of AC-002..004.
- Executor route: E2 `gpt-6-luna` / `max`, explicitly bound; effective route unavailable, dispatch status UNVERIFIABLE. The bounded pagination/validation and clustering implementation justified E2.
- Name-only Git status showed the five allowed task 28 product/test paths and the coordinator's untracked planning artifacts. `git diff --name-only` showed no tracked changes. No protected configuration path changed.
- Reviewed all five new non-protected files, including the post-remediation instrument parser and focused fixtures.
- Executor verification evidence was reused: exact commands and results were reported, no later executable/test change was observed, and fixtures independently assert prices, order, market keys, 300 confirmed candles, and UTC bar mapping.
- Verification level: V2. No external configuration or external verification action is required. Live OKX service compatibility was not tested; the task contract uses mocked transport and prohibits unapproved live calls.

## Contract mapping

| Contract | Implementation evidence | Verification evidence | Result |
| --- | --- | --- | --- |
| REQ-002 / AC-002 | `SupportResistanceTimeframe` maps H1/H4/H6/D1/W1 to explicit UTC bars and validates alignment. | UTC bar mapping test; spot/perpetual 300-candle test. | PASS |
| REQ-003 / AC-004 data portion | Repository discovers live USDT instruments, validates exact ticker and confirmed candles, paginates to 300, and returns typed failures including 429. | RED open-candle/pagination case; instrument, wrong-key and 429 tests; AUD-28-01 regression. | PASS |
| REQ-004 / AC-003 | Pure calculator uses strict ±2 swings, bounded 0.5% median clusters, current-price classification, nearest-first top five. | RED tied/open/crossed-level tests; GREEN 300-candle exact-value tests; cluster-span test. | PASS |

## RED / GREEN and build

- RED ran before GREEN after the remediation: `rtk test flutter test --no-pub test/features/support_resistance/level_calculator_test.dart test/features/support_resistance/market_repository_test.dart --plain-name 'RED-28'` — PASS, 2 tests.
- GREEN: same command with `--plain-name 'GREEN-28'` — PASS, 5 tests.
- Focused V2 suite: `rtk test flutter test --no-pub test/features/support_resistance/level_calculator_test.dart test/features/support_resistance/market_repository_test.dart` — PASS, 10 tests.
- Task buildability gate: YES, canonical Flutter web app; `rtk flutter build web --no-pub` — PASS, output confirmed `Built build/web` after the final source/test change. Wasm dry-run and Cupertino icon font warnings were non-blocking. Executor had an initial SDK-cache sandbox failure before test discovery; an escalated invocation completed verification. No environment blocker remains.
- Final whole-feature integration audit is pending T29 and T30 by user instruction. This task's buildability gate has passed.

## Scope and findings

- Allowed write surface: PASS. Existing Risk/BMAG code and protected configuration were unchanged; no protected contents were accessed per executor report and coordinator inspection.
- Test quality: PASS. Expected support/resistance values and order follow the approved algorithm rather than the implementation's output.
- AUD-28-01, resolved: a valid live USDT SWAP with blank `baseCcy` originally failed instrument discovery. Executor filtered eligible USDT rows first, derived the missing base from the exact SWAP instrument ID, added a regression test, and reran affected checks and build.
- No remaining blocking finding. Route assessment: FIT; one audit remediation was a domain integration edge case, with no route escalation.

## Verdict

PASS for Task 28 only. Tasks 29 and 30 remain unstarted, so the requested screen is not yet present.
