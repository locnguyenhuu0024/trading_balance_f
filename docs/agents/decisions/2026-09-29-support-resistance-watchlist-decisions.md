# Support and resistance watchlist decisions

Date: 2026-09-29
Status: RESOLVED

| ID | Decision | Source |
|---|---|---|
| D-001 | Add a dedicated primary navigation destination. | User clarification |
| D-002 | One screen-wide market mode, Spot or Perpetual; keep a separate persisted coin list for each. Start with an empty list and a selection prompt. | User clarification |
| D-003 | Select from all currently trading USDT pairs in the active market. Allow at most 10 coins per mode. | User clarification |
| D-004 | Offer H1, H4, H6, D1 and W1 using UTC-aligned closed candles. Persist the last market mode and timeframe. | User clarification |
| D-005 | Use the latest 300 closed candles. A swing extremum must be strictly above/below its two preceding and two following candles. Merge nearby extrema within 0.5% into one representative level. | User clarification; deterministic grouping details in design §6 |
| D-006 | Classify merged levels by their position relative to current price, including after a crossing. Show up to five nearest supports and five nearest resistances. | User clarification |
| D-007 | Refresh every minute while the screen is open, with a manual refresh control. | User clarification |

No product decision remains open. Implementation choices such as deterministic cluster ordering, failure handling, and exact UTC bar mapping are specified in the design and are part of the approval request.
