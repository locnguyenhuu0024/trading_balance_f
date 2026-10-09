# Backend data gateway decisions

Date: 2026-10-07

- D1 USER: Exactly one existing backend OKX account. All private displays require the existing backend login; exchange keys saved locally are not used by migrated data clients.
- D2 USER: Shared polling, cache and connection reuse now; realtime push deferred.
- D3 USER: Create branch from main, write plan then execute immediately. Explicit task-specific workflow authorization overrides the normal second approval gate. Commit/push/deployment remain unauthorized.
- D4 COORDINATOR: Explicit GET-only compatibility gateway preserves existing financial DTOs and calculators, bounded single-flight and cache; no dependencies/configuration changes.
- D5 COORDINATOR: Android session handoff is memory-only, acknowledged before owner activation, with generation/expiry fencing. No new bearer persistence.
- D6 COORDINATOR: Strategy list uses a fresh post-reconciliation shared snapshot, separate from display TTL caching. Existing write and terminal-proof paths retain authoritative checks.
- D7 COORDINATOR: Existing HTTPS backend compile definition is reused; no new setting required. Production frontend/backend deployment and native device checks remain user-owned.
- D8 USER: Include existing CoinGecko VND rate in backend-owned data. T93/T94 extended within existing ownership; fixed upstream, no dependency/configuration addition, existing fallback preserved.
