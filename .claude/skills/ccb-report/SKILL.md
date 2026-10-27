---
name: ccb-report
description: Export CCB local task and attempt stats by time window; no unobserved token/quota guesses.
disable-model-invocation: true
argument-hint: "[planning-root] [since YYYY-MM-DD] [until YYYY-MM-DD]"
---
# CCB task report
Use `python3 scripts/ccb/task_ledger.py report --project "<planning-root>" --since YYYY-MM-DD --until YYYY-MM-DD --format json` from the installed project. Dates use UTC; omit dates to include all history. For per-model CSV use `--format csv` and redirect to a user-approved output path outside the writer checkout. This is separate from canonical OptCodex telemetry. Show unique tasks vs attempts, Claude work runs, final audit status and observed durations. Do not claim executor result REVIEW_REQUIRED equals audited PASS or invent quota/token figures. A task spanning period boundaries can appear partially.

For the Sol pilot show planning attempts/ready proposals by model separately from implementation task IDs, executor attempts and independently audited outcomes; no implied quota or token figures.
