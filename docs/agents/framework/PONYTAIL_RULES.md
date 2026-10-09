# Ponytail Minimal Complete Change — OptCodex Adapter

> OptCodex-owned, policy-constrained adaptation of DietrichGebert/ponytail 5.1.0. This is an instruction adapter, **not** an installed plugin or executable hook. Load only for planning, implementation, or change review when a repository change is in scope.

## 1. Authority and operating boundaries

The applicable OptCodex baseline `AGENTS.md`, approved requirements/architecture/task, company or personal security boundary, protected-configuration restrictions, explicit model/effort binding, mandatory user approval, RED then GREEN, buildability and independent audit **always outrank** minimalism. Never treat "shorter" as permission to reduce correctness, security, privacy, error handling, accessibility, migrations, data integrity, or acceptance coverage.

Read only relevant, allowed source/test/documentation evidence. **Do not scan or inspect protected configuration** for reuse or dependency discovery. If the smallest solution requires a protected configuration edit or a new dependency-manifest change, report a user-owned external action or a blocker under the governing baseline; do not edit it.

## 2. Planning: minimal complete solution

1. Understand the user-approved goal and non-goals, existing behavior, callers, consumers, relevant tests, and invariants.
2. Ask in order:
   - Does the requested behavior already exist or is the proposed addition unnecessary?
   - Can an existing repository component/helper/pattern satisfy it?
   - Can the language standard library or native platform satisfy it?
   - Can an **already-approved and known** dependency satisfy it?
   - Is a readable local change enough?
   - Otherwise implement the smallest complete solution.
3. Reuse project conventions before proposing abstractions, wrappers, options, configuration, or dependencies.
4. Document the chosen reuse/minimal-change approach in the task contract, along with affected callers, tests, and edge cases; this is **not** permission to skip required S/M/L artifacts or split/merge tasks outside approved planning.
5. Include one focused regression check for non-trivial new logic; OptCodex RED/GREEN and mandatory compile/build/QA gates remain additional requirements.

Do not change business meaning, interfaces, architecture, or approved scope solely to reduce LOC. If the simplest option conflicts with requirements, raise the conflict for the coordinator/user instead of silently choosing.

## 3. Execution: bounded implementer

- Implement **only** the approved task, in its Allowed Write Surfaces. Never use Ponytail to expand scope or bypass the implementation executor.
- Prefer deletion of unnecessary code over addition where behavior stays equivalent; check all affected callers, tests, fixtures and exports within the permitted evidence boundary.
- No speculative "for later" infrastructure, duplicate helpers, incidental refactors or new dependencies.
- Never code-golf: clarity, maintainability, error handling and edge-case correctness beat raw line count.
- For an acknowledged limitation already within approved scope, document succinctly and report it; do not introduce an unapproved `shortcut:` marker or new behavior.
- Run the baseline's narrowest sufficient RED/GREEN verification and buildability checks. Do not replace them with Ponytail's optional test heuristic.

## 4. Audit: correct → safe → load → tested → fast → lean

Audit changed paths and their **permitted** callers (not only the diff). Report concrete reproducible findings, prioritized as Must fix / Should fix / Nice to have:
- functional regressions and broken integrations;
- security, access boundaries, validation and potential data loss;
- concurrency, scale and performance regressions at expected load;
- missing or weakened focused tests;
- unnecessary code, abstraction, duplication or dependency.

Every finding includes the triggering case, exact allowed source location, minimal safe correction and impact of skipping. Prioritize mandatory OptCodex contract/QA/RED-GREEN findings over aesthetic minimalism. Audit remains independent/read-only. The coordinator alone decides remediation and final verdict.

## 5. Loading, hook safety and telemetry

- This document is on-demand; do not inject it repeatedly into every subagent or append the upstream prompt to the baseline.
- Pass the **relevant compact excerpt** to executor subagents, not the entire framework.
- No Ponytail lifecycle hooks, codebase-map scanner, external plugin or automated file traversal is enabled by this adapter. If users later install a plugin, audit every hook against protected-file policy; disable automatic mapping (`PONYTAIL_MAP=0`) until separately approved.
- Measure accepted-task outcomes, rework, latency, and observed usage via existing OptCodex telemetry. Do not invent a Ponytail percentage saving or remove required checks to inflate efficiency.

Source: https://github.com/DietrichGebert/ponytail (MIT). This adapter is independently scoped to OptCodex policies and does not claim upstream endorsement.
