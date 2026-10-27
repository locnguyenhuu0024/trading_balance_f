#!/usr/bin/env python3
"""Local CCB task/event ledger. Metadata only, independent of OptCodex canonical telemetry.

No raw source, prompts, session IDs, shell logs, protected config, tokens or
cost estimates. Every event is append-only; reports count unique tasks vs attempts.
"""
from __future__ import annotations

import argparse
import csv
from contextlib import contextmanager
import datetime as dt
import hashlib
import io
import json
import os
from pathlib import Path
import re
import sys
import time
import uuid

ID_PATTERN = re.compile(r"[A-Za-z0-9_-]{1,80}\Z")
EVENTS = {"TASK_PLANNED", "ATTEMPT_STARTED", "ATTEMPT_FINISHED", "AUDIT_COMPLETED",
          "PLANNING_ATTEMPT_STARTED", "PLANNING_ATTEMPT_FINISHED",
          "CLAUDE_WORK_STARTED", "CLAUDE_WORK_FINISHED"}
OUTCOMES = {"PASS", "REWORK", "BLOCKED", "FAILED", "UNKNOWN"}
ROLES = {"coordinator", "reasoning", "auditor"}
MAX_LINE = 8192


class LedgerError(Exception):
    pass


def valid_id(value: str) -> str:
    if not isinstance(value, str) or not ID_PATTERN.fullmatch(value):
        raise LedgerError("IDs must be nonempty, alphanumeric/hyphen/underscore, max 80 characters")
    return value


def project_id(root: Path) -> str:
    if not root.is_dir() or root.is_symlink():
        raise LedgerError("Project path must be an existing non-symlink directory")
    return hashlib.sha256(str(root.resolve(strict=True)).casefold().encode("utf-8")).hexdigest()[:20]


def ledger_path(project: Path) -> Path:
    configured = os.environ.get("CCB_TASK_LEDGER_PATH")
    path = (Path(configured).expanduser() if configured
            else Path.home() / ".ccb" / "task-ledger" / "events.jsonl")
    if not path.is_absolute():
        raise LedgerError("CCB_TASK_LEDGER_PATH must be absolute")
    path = path.resolve(strict=False)
    if path.is_relative_to(project.resolve(strict=True)):
        raise LedgerError("Ledger must live OUTSIDE project/git checkout")
    if path.is_symlink() or any(p.is_symlink() for p in path.parents):
        raise LedgerError("Symlink ledger path is not allowed")
    return path


@contextmanager
def locked(path: Path):
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    lockfile = path.with_name(path.name + ".lock")
    deadline = time.monotonic() + 5
    while True:
        try:
            fd = os.open(lockfile, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
            os.close(fd)
            break
        except FileExistsError:
            if time.monotonic() > deadline:
                raise LedgerError("Ledger lock is busy/stale; investigate before manual recovery")
            time.sleep(0.025)
    try:
        yield
    finally:
        lockfile.unlink(missing_ok=True)


def read_events(path: Path) -> list[dict]:
    if not path.exists():
        return []
    events = []
    with path.open("r", encoding="utf-8") as reader:
        for number, line in enumerate(reader, 1):
            if len(line) > MAX_LINE:
                raise LedgerError("Oversized ledger line " + str(number))
            try:
                obj = json.loads(line)
            except ValueError as exc:
                raise LedgerError("Malformed ledger line " + str(number)) from exc
            if not isinstance(obj, dict) or obj.get("schema_version") != 1:
                raise LedgerError("Unsupported ledger event")
            events.append(obj)
    return events


def write_event(project: Path, plan_id: str, task_id: str, event: str, *,
                event_id: str | None = None, **metadata) -> dict:
    if event not in EVENTS:
        raise LedgerError("Unknown event")
    valid_id(plan_id); valid_id(task_id)
    allowed = {"attempt_id", "role", "work_id", "status", "model", "effort", "domain",
               "experiment_id", "duration_seconds"}
    if set(metadata) - allowed:
        raise LedgerError("Unexpected telemetry fields")
    for field in ("attempt_id", "work_id", "experiment_id"):
        if metadata.get(field) is not None:
            valid_id(metadata[field])
    if metadata.get("status") is not None and metadata["status"] not in (
            OUTCOMES | {"REVIEW_REQUIRED", "DRY_RUN_READY", "RUNNING", "PROPOSAL_READY"}):
        raise LedgerError("Invalid status")
    if metadata.get("role") is not None and metadata["role"] not in ROLES:
        raise LedgerError("Invalid role")
    if metadata.get("domain") is not None and metadata["domain"] not in ("web", "mobile", "backend", "unspecified"):
        raise LedgerError("Invalid domain")
    if metadata.get("duration_seconds") is not None and (type(metadata["duration_seconds"]) not in (int, float)
       or not 0 <= metadata["duration_seconds"] <= 1e8):
        raise LedgerError("Invalid duration")
    path = ledger_path(project)
    event_id = event_id or uuid.uuid4().hex
    valid_id(event_id)
    obj = {"schema_version": 1, "event_id": event_id,
           "ts": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds"),
           "project_id": project_id(project), "approved_plan_id": plan_id,
           "task_id": task_id, "event": event, **{k: v for k, v in metadata.items() if v is not None}}
    raw = json.dumps(obj, separators=(",", ":"), ensure_ascii=True) + "\n"
    if len(raw) > MAX_LINE:
        raise LedgerError("Oversized event")
    with locked(path):
        existing = read_events(path)
        if any(row.get("event_id") == event_id for row in existing):
            return obj   # repeat safe; e.g. Claude retries plan recording
        fd = os.open(path, os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o600)
        with os.fdopen(fd, "a", encoding="utf-8") as writer:
            writer.write(raw)
            writer.flush()
            os.fsync(writer.fileno())
    return obj


def record_planned_task(project: Path, plan_id: str, task_id: str,
                        domain: str | None = None):
    """Idempotent planner record, also invoked as dispatch fallback for missed calls."""
    identity = project_id(project) + ":" + valid_id(plan_id) + ":" + valid_id(task_id)
    event_id = hashlib.sha256(identity.encode()).hexdigest()[:32]
    return write_event(project, plan_id, task_id, "TASK_PLANNED",
                       event_id=event_id, domain=domain)


def record_attempt_event(project: Path, manifest: dict, kind: str, attempt_id: str,
                         *, status: str | None = None, duration_seconds: float | None = None):
    if kind not in ("ATTEMPT_STARTED", "ATTEMPT_FINISHED"):
        raise LedgerError("Invalid implementation attempt transition")
    trial = manifest.get("terra_trial")
    if kind == "ATTEMPT_STARTED":
        record_planned_task(project, manifest["approved_plan_id"], manifest["task_id"],
                            domain=manifest.get("domain", "unspecified"))
    return write_event(project, manifest["approved_plan_id"], manifest["task_id"], kind,
                       attempt_id=attempt_id, status=status, duration_seconds=duration_seconds,
                       model=manifest["model"], effort=manifest["effort"],
                       domain=manifest.get("domain", "unspecified"),
                       experiment_id=trial["experiment_id"] if trial else None)


def summarize(events: list[dict]) -> dict:
    tasks = set()
    planned = set()
    attempted = set()
    attempts = {}
    audits = {}
    claude_work = set()
    by_model = {}
    planning_attempts = {}
    for ev in events:
        key = (ev["project_id"], ev["approved_plan_id"], ev["task_id"])
        kind = ev["event"]
        if kind == "PLANNING_ATTEMPT_STARTED":
            aid = ev["attempt_id"]
            if aid not in planning_attempts:
                planning_attempts[aid] = {"model": ev.get("model"), "effort": ev.get("effort"),
                                          "finished": False, "status": None, "duration": None}
        if kind == "PLANNING_ATTEMPT_FINISHED" and ev.get("attempt_id") in planning_attempts:
            current = planning_attempts[ev["attempt_id"]]
            current["finished"] = True
            current["status"] = ev.get("status")
            current["duration"] = ev.get("duration_seconds")
        if ev.get("task_id") == "__planning__":
            continue
        tasks.add(key)
        if kind == "TASK_PLANNED":
            planned.add(key)
        if kind == "CLAUDE_WORK_STARTED":
            claude_work.add((key, ev.get("work_id")))
        if kind == "ATTEMPT_STARTED":
            attempted.add(key)
            attempt_id = ev["attempt_id"]
            if attempt_id not in attempts:
                attempts[attempt_id] = {"key": key, "model": ev["model"],
                                        "effort": ev["effort"], "finished": False,
                                        "duration": None}
        if kind == "ATTEMPT_FINISHED" and ev.get("attempt_id") in attempts:
            attempt = attempts[ev["attempt_id"]]
            attempt["finished"] = True
            attempt["duration"] = ev.get("duration_seconds")
        if kind == "AUDIT_COMPLETED":
            audits[key] = ev
    for x in attempts.values():
        label = x["model"] + "/" + x["effort"]
        rec = by_model.setdefault(label, {"attempts": 0, "finished": 0,
                                           "observed_duration_seconds": 0.0})
        rec["attempts"] += 1
        if x["finished"]:
            rec["finished"] += 1
            if x["duration"] is not None:
                rec["observed_duration_seconds"] += x["duration"]
    by_planning_model = {}
    for current in planning_attempts.values():
        label = str(current["model"]) + "/" + str(current["effort"])
        rec = by_planning_model.setdefault(label, {"attempts": 0, "finished": 0,
                                                    "proposals_ready": 0,
                                                    "observed_duration_seconds": 0.0})
        rec["attempts"] += 1
        if current["finished"]:
            rec["finished"] += 1
            rec["proposals_ready"] += (current["status"] == "PROPOSAL_READY")
            if current["duration"] is not None:
                rec["observed_duration_seconds"] += current["duration"]
    latest = {v: sum(a["status"] == v for a in audits.values()) for v in OUTCOMES}
    first_pass = 0
    for key, audit in audits.items():
        if audit["status"] == "PASS":
            atts = [aid for aid, a in attempts.items() if a["key"] == key]
            if len(atts) == 1 and audit.get("attempt_id") == atts[0]:
                first_pass += 1
    return {"distinct_tasks_seen": len(tasks), "planned_tasks": len(planned),
            "attempted_tasks": len(attempted), "attempts_started": len(attempts),
            "attempts_finished": sum(x["finished"] for x in attempts.values()),
            "attempts_incomplete": sum(not x["finished"] for x in attempts.values()),
            "claude_work_runs_started": len(claude_work),
            "audited_tasks": len(audits), "latest_audit_status": latest,
            "first_attempt_audit_pass": first_pass, "by_requested_model_effort": by_model,
            "planning_attempts_started": len(planning_attempts),
            "planning_attempts_finished": sum(a["finished"] for a in planning_attempts.values()),
            "by_planning_model_effort": by_planning_model,
            "usage_input_tokens": None, "usage_output_tokens": None, "quota_used": None}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="cmd", required=True)
    for cmd in ("plan", "audit", "work", "report"):
        p = sub.add_parser(cmd)
        p.add_argument("--project", required=True, type=Path, help="Planning project root (not worker checkout)")
        if cmd != "report":
            p.add_argument("--plan-id", required=True)
            p.add_argument("--task-id", required=True)
        if cmd == "audit":
            p.add_argument("--verdict", required=True, choices=("PASS", "REWORK", "BLOCKED", "FAILED", "UNKNOWN"))
            p.add_argument("--attempt-id")
        if cmd == "plan":
            p.add_argument("--domain", choices=("backend", "web", "mobile"))
        if cmd == "work":
            p.add_argument("--role", required=True, choices=tuple(ROLES))
            p.add_argument("--work-id", required=True)
            p.add_argument("--state", required=True, choices=("STARTED", "FINISHED"))
            p.add_argument("--model")
        if cmd == "report":
            p.add_argument("--since", help="Inclusive UTC YYYY-MM-DD")
            p.add_argument("--until", help="Inclusive UTC YYYY-MM-DD")
            p.add_argument("--format", choices=("json", "csv"), default="json")
    a = parser.parse_args(argv)
    try:
        if a.cmd == "report":
            values = read_events(ledger_path(a.project))
            pid = project_id(a.project)
            values = [e for e in values if e.get("project_id") == pid]
            for field in ("since", "until"):
                val = getattr(a, field)
                if val:
                    dt.date.fromisoformat(val)
            if a.since: values = [e for e in values if e["ts"][:10] >= a.since]
            if a.until: values = [e for e in values if e["ts"][:10] <= a.until]
            result = {"project_id": pid, "since_utc": a.since, "until_utc": a.until,
                      "period_interpretation": "events in UTC window; tasks spanning windows may be partial",
                      **summarize(values)}
            if a.format == "csv":
                buf = io.StringIO(); writer = csv.writer(buf)
                writer.writerow(["model_effort", "attempts", "finished", "duration_seconds"])
                for model, row in sorted(result["by_requested_model_effort"].items()):
                    writer.writerow([model, row["attempts"], row["finished"], row["observed_duration_seconds"]])
                print(buf.getvalue(), end="")
            else:
                print(json.dumps(result, indent=2))
        elif a.cmd == "plan":
            record_planned_task(a.project, a.plan_id, a.task_id, domain=a.domain)
            print(json.dumps({"status": "RECORDED", "task_id": a.task_id, "event": "TASK_PLANNED"}))
        elif a.cmd == "audit":
            write_event(a.project, a.plan_id, a.task_id, "AUDIT_COMPLETED",
                        status=a.verdict, attempt_id=a.attempt_id)
            print(json.dumps({"status": "RECORDED", "task_id": a.task_id, "audit": a.verdict}))
        else:
            kind = "CLAUDE_WORK_" + a.state
            write_event(a.project, a.plan_id, a.task_id, kind, role=a.role, work_id=a.work_id,
                        model=a.model)
            print(json.dumps({"status": "RECORDED", "event": kind, "work_id": a.work_id}))
        return 0
    except (LedgerError, OSError, ValueError, KeyError) as exc:
        print(json.dumps({"status": "BLOCKED", "reason": str(exc)}))
        return 2


if __name__ == "__main__":
    sys.exit(main())
