# Weekly OptCodex Agent Efficiency Review

Period: `<start>` -> `<end>`
Telemetry schema: `1`
Repositories/workflows included: <...>
Data quality: COMPLETE | PARTIAL — <missing fields/events>

## 1. Executive Summary

- workflows: <total / complete / blocked>
- tasks: <total / PASS / REWORK / BLOCKED>
- agent runs: <main / reasoning / executor / auditor>
- first-pass executor success: <...%>
- model/effort escalations: <count / rate>
- environment/toolchain/transport incidents: <count>
- runtime-reported cost/tokens coverage: <...% of runs>

## 2. Routing Effectiveness

| Route | Runs | PASS/useful | REWORK/BLOCKED | Escalated | FIT | UNDERPOWERED | OVERPOWERED | Avg duration* | Avg cost* |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| C1 Sol Medium | | | | | | | | | |
| C2 Sol High | | | | | | | | | |
| C3 Astra Low | | | | | | | | | |
| R0 | | | | | | | | | |
| R1 | | | | | | | | | |
| R2 Sol Medium | | | | | | | | | |
| R3 Sol High | | | | | | | | | |
| E0 Luna High | | | | | | | | | |
| E1 Luna XHigh | | | | | | | | | |
| E2 Luna Max | | | | | | | | | |

`*` only from runtime-observed values; do not impute missing values into the observed averages.

## 3. Fan-out / Handoff Efficiency

- average subagents per workflow: <...>
- average executor handoffs per workflow: <...>
- reasoning results USED / PARTIAL / DISCARDED: <...>
- duplicated/low-value fan-out observed: <...>
- workflows where coordination overhead exceeded benefit: <...>

## 4. Planning Quality

- clarification rounds per workflow: <...>
- spec revisions before approval: <...>
- plan revisions before approval: <...>
- executor blockers caused by unresolved product/design ambiguity: <count>
- acceptance-criterion misses found only during audit: <count>

## 5. Verification / Reliability

- V1/V2/V3/V4 distribution: <...>
- audit findings per task: <...>
- external verification rate: <...>
- environment/toolchain blockers: <...>
- orchestration transport errors: <...>
- SSPI constraint activations / self-clears: <...>

## 6. P/P Findings

Keep / increase usage:
- <route + evidence>

Reduce / downgrade candidates:
- <route + evidence>

Escalation threshold changes:
- <proposal + evidence>

Decomposition / fan-out changes:
- <proposal + evidence>

## 7. Next Optimization Decisions

| Decision | Evidence | Expected benefit | Risk | Action |
|---|---|---|---|---|
| <...> | <metric/events> | <...> | <...> | KEEP / CHANGE / EXPERIMENT |

Do not optimize solely for lower model cost. Prefer **cost per accepted, correctly verified outcome** and separate model-capability issues from contract, environment, transport, and tooling failures.
