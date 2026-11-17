# Final integration audit: multi-platform view-only restructure

Date: 2026-11-07
Plan: `docs/agents/plans/2026-11-07-multi-platform-view-only.md` revision 2
Branch: `codex/multi-platform-view-only`, based on `main` at 544de3c. Not pushed, not merged.
Verdict: PASS for code and fixture-level verification. External live verification pending (below).

## Coordinator-observed evidence

| Check | Result |
|---|---|
| Full test suite, V4 | 597 passed |
| `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings` | 0 errors, 129 warnings and infos (78 before this work) |
| `flutter build web --no-pub` | Pass |
| Web build in a real browser | Loads, no console errors, no backend requests, no-key state renders |
| Binance public market through the real client, live | Spot and USD-M tickers, instruments, levels, prices and candles returned |
| Rendered review, light and dark | Assets, Orders, Market, Tools, picker, connections, form reviewed against handoff images |
| Changed files outside `lib`, `test`, `tasks`, `docs/agents`, `designs` | Only the user-installed rules upgrade and the `.dart` allowlist entry |
| Protected files and `backend/` | Unchanged |
| Write routes in `lib/exchanges` | None |

## Acceptance

| AC | Evidence | Status |
|---|---|---|
| AC-001, AC-002 | `test/core/backend_features_test.dart`, browser network list | PASS |
| AC-003 | `main_navigation_shell_test`, `tools_screen_test`, `widget_test` | PASS |
| AC-004, AC-005 | `exchange_scope_test`, `portfolio_scope_test`, `orders_scope_test` | PASS |
| AC-006, AC-007 | `binance_reader_test`, `binance_history_test`, fixtures only | PASS on fixtures; live pending |
| AC-008 | `binance_market_test`, `fractal_provider_test`, `watchlist_provider_test`; public reads live | PASS |
| AC-009, AC-010 | `scope_switch_test`, `connections_screen_test`, `account_state_test` | PASS on fixtures; live pending |
| AC-011 | `design_layout_test`, rendered review | PASS; device check pending |
| AC-012 | Existing OKX tests retained | PASS on fixtures; live pending |

## Deviations from the normal flow

- VAL-005: the executor sandbox cannot run `flutter test`, so RED then GREEN ran on the host, by the coordinator, after implementation. RED is a negative scenario executed before GREEN; it was not observed failing before implementation, except where an executor reported it (T116, T122).
- Long executor runs ended early, so T117, T118, T119, T120 and T121 ran in stages, with `wip` commits between stages to keep the checkout clean, beyond the commits named in PRE-3 and PRE-4. The user asked to run all tasks and review at the end.
- Fan-out used Claude subagents on user direction (D-011).
- Rules were upgraded during T116, whose route stays the legacy Luna route by user decision.
- The dispatch path gate refuses names containing `credential`, so `BinanceKeyBundle` lives in `binance_private_client.dart`.

## Open items

1. Live private reads on Binance and OKX with read-only keys; response shapes for USD-M `positionRisk` are not doc-verified.
2. Native iOS and Android build and run.
3. `USDⓈ-M` glyph on real devices; the test font cannot draw it.
4. PnL stays green and red as in the existing app, while the design is close to monochrome.
5. A first launch with no keys says `Cần kiểm tra lại kết nối`, which is accurate but not tailored to a new user.
6. 129 analyzer warnings and infos, mostly style in new code.
