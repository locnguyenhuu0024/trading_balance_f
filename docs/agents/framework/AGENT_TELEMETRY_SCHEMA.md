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
  "planning_workstream_count": 2,
  "material_workstream_count": 2,
  "fanout_required": true,
  "required_reasoning_agents": 2,
  "actual_reasoning_agents": 2,
  "fanout_compliance": "PASS",
  "fanout_skip_reason": null,
  "configured_model": "gpt-6.1-sol",
  "configured_effort": "medium",
  "requested_model": "gpt-6.1-sol",
  "requested_effort": "medium",
  "route_binding_mode": "EXPLICIT",
  "parent_route_inherited": false,
  "dispatch_route_status": "UNVERIFIABLE",
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
  } ,
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
- `planning_workstreams_classified`, `planning_fanout_violation`
- `subagent_dispatched`, `subagent_completed`
- `executor_dispatched`, `executor_completed`
- `route_escalated`
- `route_mismatch`, `route_unavailable`
- `verification_completed`, `audit_completed`
- `external_verification_required`, `external_verification_received`
- `environment_blocker`
- `orchestration_transport_error`
- `telemetry_degraded`
- `frontend_design_classified`, `frontend_design_brief_ready`, `frontend_guidelines_audited`, `frontend_visual_review_completed`

Do not create a telemetry event for every shell command, file read, or internal thought.

## 4. Outcome and assessment enums

```text
outcome:
PASS | REWORK | BLOCKED | FAILED | UNKNOWN | N/A

result_use:
USED | PARTIAL | DISCARDED | N/A

route_assessment:
FIT | UNDERPOWERED | OVERPOWERED | UNKNOWN | N/A

route_binding_mode:
EXPLICIT | INHERITED | UNAVAILABLE | N/A

dispatch_route_status:
MATCH | MISMATCH | UNVERIFIABLE | ROUTE_UNAVAILABLE | N/A

fanout_compliance:
PASS | EXCEPTION | UNAVAILABLE | VIOLATION | PENDING | N/A

fanout_skip_reason:
null | SINGLE_MATERIAL_WORKSTREAM | NOT_INDEPENDENT_ATOMIC_CONTRACT | RUNTIME_CHILD_DISPATCH_UNAVAILABLE | N/A

error_category:
null | environment | transport | verification | contract | route_mismatch | route_unavailable | security | toolchain | other
```

Route-binding semantics:
- `configured_model` / `configured_effort`: canonical route selected by policy/task artifact.
- `requested_model` / `requested_effort`: exact values actually submitted to the child spawn/dispatch operation; never fill these from the configured route unless they were truly sent.
- `EXPLICIT`: both requested model and effort were supplied to the runtime.
- `INHERITED`: model and/or effort came from parent/default behavior; for an `E*` implementation task this is a routing-policy violation.
- `UNAVAILABLE`: the runtime cannot express the requested binding.
- `MATCH`: runtime reports effective role/model/effort matching the configured route.
- `UNVERIFIABLE`: explicit binding succeeded but the runtime does not expose effective route afterward.

Planning-fan-out semantics:
- `planning_workstream_count`: all identified technical planning workstreams, including non-material ones when useful for traceability.
- `material_workstream_count`: workstreams whose analysis can materially affect the plan contract.
- `fanout_required`: `true` when at least two material workstreams are independently analyzable. Material frontend + material backend is an automatic `true` case.
- `required_reasoning_agents`: minimum separate planning reasoning runs required by the workstream gate. For material frontend + backend this is at least `2`.
- `actual_reasoning_agents`: distinct planning reasoning runs actually dispatched for the required workstreams.
- `PASS`: required fan-out was completed and reconciled.
- `EXCEPTION`: fan-out was not required because an allowed structural exception applies (`SINGLE_MATERIAL_WORKSTREAM` or `NOT_INDEPENDENT_ATOMIC_CONTRACT`).
- `UNAVAILABLE`: fan-out was required but child dispatch was unavailable; planning may continue coordinator-owned with the limitation recorded.
- `VIOLATION`: fan-out was required and available, but fewer than the required reasoning workstreams were dispatched/collected before finalization.
- Handoff cost, token saving, coordinator speed, or "only two domains" must never be encoded as a skip reason.
- `MISMATCH`: runtime reports a different role/model/effort; do not treat a stronger route as compliant.
- `ROUTE_UNAVAILABLE`: required explicit child route cannot be expressed; implementation must not silently fall back to inherited/default execution.

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
- planning fan-out compliance rate; required-vs-actual reasoning-agent counts; `VIOLATION`/`UNAVAILABLE`/allowed-exception counts; material frontend+backend plans finalized without the required two-workstream fan-out;
- route distribution by `C*`, `R*`, `E*`, model, and effort;
- explicit-binding compliance rate and counts of `INHERITED`, `MISMATCH`, `UNVERIFIABLE`, and `ROUTE_UNAVAILABLE`;
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
- frontend F0/F1/F2/F3 distribution; design-brief compliance; web-guidelines finding rate; visual-review PASS/REWORK/UNAVAILABLE distribution when applicable.

Interpret cost/performance only after separating model failures from environment, transport, security-boundary, and contract/design failures.
