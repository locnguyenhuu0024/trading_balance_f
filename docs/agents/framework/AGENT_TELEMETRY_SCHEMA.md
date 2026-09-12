# Agent Telemetry Schema

> Operational evaluation data for OptCodex. This records observable workflow metadata and outcomes only; it never records private chain-of-thought.

## 1. Canonical storage

```text
docs/agents/telemetry/events/YYYY-MM-DD.jsonl
docs/agents/telemetry/reports/YYYY-MM-DD-weekly.md
```

The coordinator is the single writer. Each line in the daily event file is one valid JSON object. Use schema version `1`.

Logical correlation IDs are coordinator-generated and repository-local:
- `workflow_id`: e.g. `WF-20260912-001-normalized-log`
- `agent_run_id`: e.g. `MAIN-001`, `R2-003`, `E1-T07-001`

Do not store runtime session/thread/subagent IDs for routine correlation.

## 2. Base event schema

Recommended shape:

```json
{
  "schema_version": 1,
  "ts": "2026-09-12T10:30:00+07:00",
  "workflow_id": "WF-20260912-001-topic",
  "event": "subagent_completed",
  "agent_run_id": "R2-001",
  "role": "reasoning",
  "route_class": "R2",
  "work_type": "plan_validation",
  "task_ids": ["T07"],
  "configured_model": "gpt-5.6-sol",
  "configured_effort": "medium",
  "effective_model": null,
  "effective_effort": null,
  "duration_ms": null,
  "outcome": "PASS",
  "retry_count": 0,
  "escalation_from": null,
  "escalation_to": null,
  "verification_level": null,
  "result_use": "USED",
  "route_assessment": "FIT",
  "error_category": null,
  "usage": {
    "input_tokens": null,
    "output_tokens": null,
    "reasoning_tokens": null,
    "cached_tokens": null,
    "cost": null,
    "currency": null
  },
  "summary": "Plan validation found no blocking mismatch."
}
```

Unknown/unexposed runtime fields are `null`; never estimate them and present the estimate as observed telemetry.

## 3. Event vocabulary

Use the smallest useful set:
- `workflow_started`, `workflow_completed`
- `coordinator_route_selected`
- `clarification_round`
- `spec_ready`, `plan_ready`, `approval_requested`, `approval_received`
- `subagent_dispatched`, `subagent_completed`
- `executor_dispatched`, `executor_completed`
- `route_escalated`
- `verification_completed`, `audit_completed`
- `external_verification_required`, `external_verification_received`
- `environment_blocker`
- `orchestration_transport_error`
- `telemetry_degraded`

Do not create a telemetry event for every shell command, file read, or internal thought.

## 4. Outcome and assessment enums

```text
outcome:
PASS | REWORK | BLOCKED | FAILED | UNKNOWN | N/A

result_use:
USED | PARTIAL | DISCARDED | N/A

route_assessment:
FIT | UNDERPOWERED | OVERPOWERED | UNKNOWN | N/A

error_category:
null | environment | transport | verification | contract | security | toolchain | other
```

`route_assessment` is a post-hoc coordinator/auditor judgment:
- `FIT`: route was sufficient without unnecessary escalation/rework attributable to capability;
- `UNDERPOWERED`: capability was a material cause of avoidable retry/escalation or unusable output;
- `OVERPOWERED`: evidence indicates a materially cheaper configured route would likely have been sufficient; use conservatively;
- `UNKNOWN`: evidence is insufficient to judge.

## 5. Security and privacy boundary

Never log:
- chain-of-thought or hidden reasoning;
- full user prompts or full subagent prompts;
- source-code bodies, diffs, raw logs, or raw command output;
- secrets, credentials, tokens, certificates, connection strings;
- protected configuration/environment contents;
- customer/business payloads or other sensitive data not required for evaluation.

Prefer stable IDs, counts, enums, timestamps, observed usage, and one-sentence summaries. Safe path names may be logged only when materially useful.

## 6. Weekly evaluation metrics

At minimum compute:
- workflows completed / blocked;
- clarification rounds per workflow; spec/plan revision counts;
- subagents and executor handoffs per workflow;
- route distribution by `C*`, `R*`, `E*`, model, and effort;
- first-pass executor success rate;
- REWORK/BLOCKED rates by route;
- escalation rate and escalation path by `R*`/`E*`;
- subagent adoption rate (`USED`, `PARTIAL`, `DISCARDED`);
- route-fit distribution (`FIT`, `UNDERPOWERED`, `OVERPOWERED`, `UNKNOWN`);
- audit findings per task and verification-level distribution;
- environment/toolchain/transport error rate;
- external-verification rate;
- unresolved-design leakage to executors (contract/ambiguity blockers);
- duration and runtime-reported token/cost per accepted task/workflow when available.

Interpret cost/performance only after separating model failures from environment, transport, security-boundary, and contract/design failures.
