#!/usr/bin/env python3
"""CCB v0.4: gated single-writer Codex CLI adapter; not a security sandbox.

Reads only the approved task/manifest and Git path metadata. It never examines
repository configuration contents or product source files. Execution requires
an independently approved plan and a clean writer checkout.
"""

from __future__ import annotations

import argparse
from contextlib import contextmanager, nullcontext
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import tempfile

from compat import CompatibilityError, load_lock, require_route, verify_compatibility
from task_ledger import LedgerError, record_attempt_event


EFFORTS = {"low", "medium", "high", "xhigh", "max"}
ROUTES = {"E0", "E1", "E2"}
ALLOWED_EXTENSIONS = {
    ".py", ".ts", ".tsx", ".js", ".jsx", ".go", ".rs", ".java",
    ".kt", ".swift", ".cs", ".c", ".h", ".cpp", ".hpp",
    ".sql", ".html", ".css", ".scss", ".md",
}
BLOCKED_NAMES = {
    "agents.md", "claude.md", "package.json", "pyproject.toml", "cargo.toml",
    "go.mod", "go.sum", "dockerfile", "makefile", "conftest.py",
    "settings.py", "config.py", "tsconfig.json", "requirements.txt",
    "gradle.properties", "pom.xml", "build.gradle", "build.gradle.kts",
    "vite.config.ts", "jest.config.js", "vitest.config.ts",
}
BLOCKED_PARTS = {
    ".git", ".claude", ".codex", ".github", ".circleci", ".vscode",
    "secrets", "infrastructure", "infra", "terraform", "helm", "k8s",
    "deployment", "deploy", "ci", "cd", ".env",
}


class GateError(Exception):
    pass


def path_contract(value: str) -> str:
    """Normalize manifest path to exact portable POSIX-relative file name."""
    if not isinstance(value, str) or not value or "\\" in value:
        raise GateError("Path must be a nonempty POSIX-style relative path")
    if value.startswith("/") or re.match(r"^[A-Za-z]:", value):
        raise GateError("Absolute path forbidden")
    parts = value.split("/")
    if any(p in {"", ".", ".."} for p in parts):
        raise GateError("Path traversal or non-canonical path forbidden")
    return value


def allowed_source_path(value: str) -> bool:
    p = Path(path_contract(value))
    parts = {piece.lower() for piece in p.parts}
    name = p.name.lower()
    if parts & BLOCKED_PARTS or name in BLOCKED_NAMES:
        return False
    if name.startswith(".env") or name.endswith((".lock", ".secret", ".pem", ".key")):
        return False
    if any(k in name for k in (".config.", ".settings.", "credential", "secret")):
        return False
    return p.suffix.lower() in ALLOWED_EXTENSIONS


def git_run(repo: Path, *args: str) -> bytes:
    proc = subprocess.run(["git", "-C", str(repo), *args], capture_output=True, check=False)
    if proc.returncode:
        raise GateError("Git preflight failed; verify repo and worktree")
    return proc.stdout


def git_status_paths(repo: Path) -> tuple[set[str], bool]:
    """Read Git path/status metadata ONLY, not any file contents."""
    raw = git_run(repo, "status", "--porcelain=v1", "--untracked-files=all", "-z")
    records = raw.split(b"\0")
    paths: set[str] = set()
    staged = False
    i = 0
    while i < len(records):
        record = records[i]
        i += 1
        if not record:
            continue
        if len(record) < 4 or record[2:3] != b" ":
            raise GateError("Unexpected Git status format")
        state = record[:2].decode("ascii", errors="replace")
        if state[0] not in {" ", "?"}:
            staged = True
        path = record[3:].decode("utf-8", errors="surrogateescape")
        paths.add(path.replace("\\", "/"))
        # Porcelain v1 -z supplies the origin as a second NUL record for rename/copy.
        if "R" in state or "C" in state:
            if i >= len(records) or not records[i]:
                raise GateError("Malformed Git rename/copy metadata")
            origin = records[i].decode("utf-8", errors="surrogateescape")
            paths.add(origin.replace("\\", "/"))
            i += 1
    return paths, staged


def get_manifest(path: Path) -> dict:
    try:
        m = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        raise GateError("Cannot read job manifest as JSON") from exc
    required = {"task_id", "approved_plan_id", "task_file", "allowed_writes",
                "dependencies", "route_class", "timeout_seconds", "model", "effort",
                "optcodex_variant", "optcodex_version", "baseline_version",
                "optcodex_source_revision", "agent_role", "route_binding",
                "parent_route_inheritance", "planning_fanout"}
    if not isinstance(m, dict) or not required <= m.keys():
        raise GateError("Job manifest missing required fields")
    for k in ("task_id", "approved_plan_id", "task_file"):
        if not isinstance(m[k], str) or not m[k].strip():
            raise GateError("Invalid manifest: " + k)
    if not re.fullmatch(r"[A-Za-z0-9_-]{1,80}", m["task_id"]):
        raise GateError("task_id must be a short safe identifier")
    if m["route_class"] not in ROUTES:
        raise GateError("Invalid route class")
    if m["agent_role"] != "implementation_executor":
        raise GateError("Executor role must be explicitly bound")
    if m["route_binding"] != "EXPLICIT" or m["parent_route_inheritance"] != "FORBIDDEN":
        raise GateError("Explicit route binding is required")
    try:
        require_route(m["route_class"], m["model"], m["effort"], m.get("terra_trial"))
    except CompatibilityError as exc:
        raise GateError(str(exc)) from exc
    if not isinstance(m["optcodex_variant"], str):
        raise GateError("OptCodex variant missing")
    for key in ("optcodex_version", "baseline_version", "optcodex_source_revision"):
        if not isinstance(m[key], str) or not m[key]:
            raise GateError("Missing compatibility field: " + key)
    fanout = m["planning_fanout"]
    if not isinstance(fanout, dict) or set(fanout) != {
        "required", "status", "required_workstreams", "collected_workstreams", "reason"
    }:
        raise GateError("Missing complete planning fan-out gate")
    if type(fanout["required"]) is not bool or type(fanout["required_workstreams"]) is not int or (
        type(fanout["collected_workstreams"]) is not int
    ) or min(fanout["required_workstreams"], fanout["collected_workstreams"]) < 0:
        raise GateError("Invalid planning fan-out counts")
    if fanout["required"]:
        if fanout["required_workstreams"] < 2 or fanout["status"] not in {"PASS", "UNAVAILABLE"}:
            raise GateError("Required planning fan-out not reconciled")
        if fanout["status"] == "PASS" and fanout["collected_workstreams"] < fanout["required_workstreams"]:
            raise GateError("Missing required completed planning workstreams")
        if fanout["status"] == "UNAVAILABLE" and fanout["reason"] != "RUNTIME_CHILD_DISPATCH_UNAVAILABLE":
            raise GateError("Missing authorized fan-out-unavailable reason")
    else:
        if fanout["status"] != "EXCEPTION" or fanout["reason"] not in {
            "SINGLE_MATERIAL_WORKSTREAM", "NOT_INDEPENDENT_ATOMIC_CONTRACT"
        }:
            raise GateError("Invalid planning fan-out exception")
        if fanout["required_workstreams"] >= 2:
            raise GateError("Multiple material workstreams require fan-out")
    if not isinstance(m["allowed_writes"], list) or not m["allowed_writes"]:
        raise GateError("allowed_writes must be a nonempty exact-file list")
    if not all(isinstance(x, str) for x in m["allowed_writes"]):
        raise GateError("allowed_writes must contain exact strings")
    normalized = [path_contract(x) for x in m["allowed_writes"]]
    if len(set(x.casefold() for x in normalized)) != len(normalized):
        raise GateError("Duplicate or case-colliding allowed paths")
    if not all(allowed_source_path(x) for x in normalized):
        raise GateError("Manifest includes a protected or unsupported file path")
    if not isinstance(m["dependencies"], list) or not all(
        isinstance(x, dict) and set(x) == {"task_id", "status"}
        and isinstance(x["task_id"], str) and x["task_id"]
        and x["status"] == "PASS" for x in m["dependencies"]
    ):
        raise GateError("Dependencies must each have an observed PASS")
    if type(m["timeout_seconds"]) is not int or not 60 <= m["timeout_seconds"] <= 3600:
        raise GateError("timeout_seconds must be between 60 and 3600")
    task_relative = path_contract(m["task_file"])
    if not task_relative.startswith("tasks/") or not task_relative.endswith(".md"):
        raise GateError("Task contract must be a canonical tasks/*.md document")
    if not re.fullmatch(r"[A-Za-z0-9_-]+", Path(task_relative).stem):
        raise GateError("Invalid task filename")
    return m


def stop_tree(proc: subprocess.Popen) -> None:
    if proc.poll() is not None:
        return
    if os.name == "nt":
        subprocess.run(["taskkill", "/PID", str(proc.pid), "/T", "/F"],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    else:
        try:
            os.killpg(proc.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait()


def report_check(report: object, task_id: str) -> dict:
    if not isinstance(report, dict):
        raise GateError("Executor report must be a JSON object")
    required = {"task_id", "status", "summary", "files_changed", "red", "green", "buildability", "checks", "blockers"}
    if set(report) != required:
        raise GateError("Executor report fields do not match schema")
    if report["task_id"] != task_id or report["status"] not in {"COMPLETED", "BLOCKED", "FAILED"}:
        raise GateError("Unexpected task id or executor status")
    if not isinstance(report["summary"], str):
        raise GateError("Invalid summary")
    if not isinstance(report["files_changed"], list) or not all(isinstance(x, str) for x in report["files_changed"]):
        raise GateError("Invalid files_changed")
    if not isinstance(report["checks"], list) or not isinstance(report["blockers"], list):
        raise GateError("Invalid checks or blockers")
    if not all(isinstance(x, str) for x in report["blockers"]):
        raise GateError("Invalid blockers")
    def check(c: object) -> None:
        if not isinstance(c, dict) or set(c) != {"name", "result", "evidence"}:
            raise GateError("Invalid check structure")
        if any(not isinstance(c[k], str) for k in ("name", "result", "evidence")):
            raise GateError("Invalid check field")
        if c["result"] not in {"PASS", "FAIL", "NOT_RUN"}:
            raise GateError("Invalid check result")
    for item in [report["red"], report["green"], *report["checks"]]:
        check(item)
    b = report["buildability"]
    if not isinstance(b, dict) or set(b) != {"name", "result", "evidence"}:
        raise GateError("Invalid buildability structure")
    if not all(isinstance(b[k], str) for k in b):
        raise GateError("Invalid buildability fields")
    if b["result"] not in {"PASS", "BLOCKED", "N/A"}:
        raise GateError("Invalid buildability result")
    return report


@contextmanager
def writer_lock(repo: Path):
    """Atomic checkout-level writer lock. Stale locks require manual review."""
    digest = hashlib.sha256(str(repo).casefold().encode("utf-8")).hexdigest()[:24]
    lockfile = Path(tempfile.gettempdir()) / ("ccb-writer-" + digest + ".lock")
    try:
        fd = os.open(lockfile, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    except FileExistsError as exc:
        raise GateError("A CCB writer lock exists; verify state before manual lock recovery") from exc
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(str(os.getpid()))
        yield
    finally:
        lockfile.unlink(missing_ok=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--repo", required=True, type=Path, help="clean executor checkout")
    parser.add_argument("--plan-root", type=Path, help="root containing task files; defaults to repo")
    parser.add_argument("--execute", action="store_true", help="actually invoke Codex")
    parser.add_argument("--approved-plan-id", default="", help="explicit approved plan ID")
    parser.add_argument("--approved-experiment-id", default="", help="separately authorized Terra trial ID")
    opts = parser.parse_args()
    try:
        repo = opts.repo.resolve(strict=True)
        plan_root = (opts.plan_root or repo).resolve(strict=True)
        manifest_candidate = opts.manifest.absolute()
        if not manifest_candidate.is_relative_to(plan_root):
            raise GateError("Job manifest must be inside plan-root")
        job_relative = manifest_candidate.relative_to(plan_root).as_posix()
        if not (
            re.fullmatch(r"jobs/[A-Za-z0-9_-]+\.json", job_relative)
            or re.fullmatch(r"docs/agents/ccb/jobs/[A-Za-z0-9_-]+\.json", job_relative)
        ):
            raise GateError("Job manifest must be a jobs/<safe-name>.json file")
        if manifest_candidate.is_symlink() or manifest_candidate.resolve(strict=True) != manifest_candidate:
            raise GateError("Job manifest symlink or unsafe path rejected")
        manifest = get_manifest(manifest_candidate)
        lock = load_lock()
        compatible = verify_compatibility(repo, manifest["optcodex_variant"], lock)
        for manifest_field, actual_field in (
            ("optcodex_version", "variant_version"),
            ("baseline_version", "baseline_version"),
            ("optcodex_source_revision", "source_revision"),
        ):
            if manifest[manifest_field] != compatible[actual_field]:
                raise GateError("Incompatible OptCodex pin: " + manifest_field)
        task_candidate = plan_root / manifest["task_file"]
        if any(p.is_symlink() for p in (plan_root / Path(*Path(manifest["task_file"]).parts[:n])
                                        for n in range(1, len(Path(manifest["task_file"]).parts) + 1))):
            raise GateError("Task symlink rejected")
        taskfile = task_candidate.resolve(strict=True)
        if not taskfile.is_relative_to(plan_root) or not taskfile.is_file():
            raise GateError("Task file must be inside plan-root")
        for target in manifest["allowed_writes"]:
            rel = Path(target)
            if any(p.is_symlink() for p in (repo / Path(*rel.parts[:n])
                                            for n in range(1, len(rel.parts) + 1))):
                raise GateError("Allowed write path includes a symlink: " + target)
            resolved_target = (repo / rel).resolve()
            if not resolved_target.is_relative_to(repo):
                raise GateError("Allowed write path escapes checkout: " + target)
        root = Path(os.fsdecode(git_run(repo, "rev-parse", "--show-toplevel")).strip()).resolve()
        if repo != root:
            raise GateError("--repo must be Git worktree root")
        with (writer_lock(repo) if opts.execute else nullcontext()):
            paths, staged = git_status_paths(repo)
            if paths or staged:
                raise GateError("Writer worktree is dirty; create a clean isolated checkout")
            if not opts.execute:
                print(json.dumps({"status": "DRY_RUN_READY", "task_id": manifest["task_id"],
                                  "repo": str(repo), "plan_root": str(plan_root),
                                  "allowed_writes": manifest["allowed_writes"],
                                  "optcodex": compatible,
                                  "route": {"class": manifest["route_class"],
                                            "model": manifest["model"], "effort": manifest["effort"],
                                            "binding": "EXPLICIT"}}, ensure_ascii=False))
                return 0
            if manifest["approved_plan_id"] != opts.approved_plan_id:
                raise GateError("Missing/mismatched approval ID; verify user approved CURRENT presented plan")
            trial = manifest.get("terra_trial")
            if trial is not None:
                if opts.approved_experiment_id != trial["experiment_id"]:
                    raise GateError("BLOCKED_ROUTE: missing separately approved Terra experiment ID")
            elif opts.approved_experiment_id:
                raise GateError("Unexpected Terra approval argument on default route")
            if shutil.which("codex") is None:
                raise GateError("codex executable not found in PATH")
            task_content = taskfile.read_text(encoding="utf-8")
            schema_file = Path(__file__).resolve().parents[2] / "schemas" / "ccb_executor_report.schema.json"
            run_dir = Path(tempfile.mkdtemp(prefix="ccb-run-"))
            report_file = run_dir / "report.json"
            prompt = (
                f"You are the OptCodex {compatible['variant']} bounded implementation executor for task {manifest['task_id']}.\n"
                f"Route is explicitly bound: {manifest['model']} / {manifest['effort']}.\n"
                "Honor the installed OptCodex baseline, phase-specific execution/audit rules, Ponytail, "
                "and applicable frontend/QA/context profile requirements.\n"
                "Do not make requirements, product, security, or architecture decisions. "
                "Do not read or edit any protected configuration/environment file. "
                "Do not run git state-changing commands or alter Git history. "
                "Do not edit planning, skills, instructions or other tasks.\n"
                f"EXACT ALLOWED WRITE FILES: {json.dumps(manifest['allowed_writes'])}\n"
                "Stop rather than editing an unlisted file. Run RED before GREEN and return "
                "only the structured executor report required by the output schema.\n\n"
                "APPROVED TASK CONTRACT:\n" + task_content
            )
            command = ["codex", "exec", "--cd", str(repo), "--sandbox", "workspace-write",
                       "--output-schema", str(schema_file), "--output-last-message", str(report_file)]
            command += ["--model", manifest["model"],
                        "--config", f"model_reasoning_effort={manifest['effort']}"]
            command.append("-")
            # Do not persist stdout/stderr; raw traces may expose source or sensitive data.
            popen_kwargs = {"stdin": subprocess.PIPE, "stdout": subprocess.DEVNULL,
                            "stderr": subprocess.DEVNULL}
            if os.name == "nt":
                popen_kwargs["creationflags"] = subprocess.CREATE_NEW_PROCESS_GROUP
            else:
                popen_kwargs["start_new_session"] = True
            # Durable attempt-start event is recorded BEFORE starting the writer. Ledger errors
            # block the writer rather than silently losing task/attempt statistics.
            import uuid
            import time
            attempt_id = uuid.uuid4().hex
            started_at = time.monotonic()
            record_attempt_event(plan_root, manifest, "ATTEMPT_STARTED", attempt_id)
            proc = subprocess.Popen(command, **popen_kwargs)
            timed_out = False
            try:
                proc.communicate(prompt.encode("utf-8"), timeout=manifest["timeout_seconds"])
            except subprocess.TimeoutExpired:
                timed_out = True
                stop_tree(proc)
            changed, has_staged = git_status_paths(repo)
            allowed = set(manifest["allowed_writes"])
            unexpected = sorted(p for p in changed if p not in allowed)
            verdict = "BLOCKED"
            message = "unknown"
            report = None
            if unexpected or has_staged:
                message = "Out-of-scope or staged Git changes detected; preserve checkout for review"
            elif timed_out:
                message = "Codex process timed out; verify no child writer remains"
            elif proc.returncode != 0:
                message = "Codex exited with an error; output suppressed to protect data"
            else:
                try:
                    report = report_check(json.loads(report_file.read_text(encoding="utf-8")), manifest["task_id"])
                    report_paths = set(report["files_changed"])
                    if report_paths != changed:
                        message = "Executor report paths differ from observed Git status"
                    elif report["status"] != "COMPLETED":
                        message = "Executor reported non-completion; needs Claude review"
                    elif report["buildability"]["result"] != "PASS" and any(
                        Path(p).suffix.lower() != ".md" for p in allowed
                    ):
                        message = "Code task lacks successful buildability evidence"
                    else:
                        verdict = "REVIEW_REQUIRED"
                        message = "Executor returned; Claude must independently audit"
                except (OSError, ValueError, GateError):
                    message = "Missing/invalid structured executor report"
            record_attempt_event(plan_root, manifest, "ATTEMPT_FINISHED", attempt_id,
                                 status=verdict, duration_seconds=round(time.monotonic()-started_at, 3))
            print(json.dumps({"attempt_id": attempt_id, "status": verdict, "task_id": manifest["task_id"],
                              "message": message, "observed_changed_paths": sorted(changed),
                              "unexpected_paths": unexpected, "staged_changes": has_staged,
                              "run_dir": str(run_dir),
                              "route": {"requested_model": manifest["model"],
                                        "requested_effort": manifest["effort"],
                                        "binding": "EXPLICIT",
                                        "effective_route": "UNVERIFIABLE"},
                              "optcodex": compatible,
                              "report_path": str(report_file) if report is not None else None}, ensure_ascii=False))
            return 0 if verdict == "REVIEW_REQUIRED" else 2
    except (GateError, CompatibilityError, LedgerError, FileNotFoundError, OSError, UnicodeError) as exc:
        print(json.dumps({"status": "BLOCKED", "message": str(exc)}, ensure_ascii=False))
        return 2


if __name__ == "__main__":
    sys.exit(main())
