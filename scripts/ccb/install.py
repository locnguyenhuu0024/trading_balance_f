#!/usr/bin/env python3
"""Install pinned OptCodexRules + CCB overlay for backend, web or mobile.

Read-only preview is the default. Never delete existing project files.
Private GitHub source requires an already authenticated local git credential helper.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import sys
import tempfile

from compat import CompatibilityError, load_lock, verify_compatibility

DOMAINS = ("backend", "web", "mobile")
SCOPES = ("company", "personal")
UPSTREAM_URL = "https://github.com/locnguyenhuu0024/OptCodexRules.git"
COMMON = (
    "CLAUDE.md",
    "optcodex.lock.json",
    "model-routing.json",
    ".claude/rules/ccb-control.md",
    ".claude/rules/ccb-safety.md",
    ".claude/skills/ccb-plan/SKILL.md",
    ".claude/skills/ccb-dispatch/SKILL.md",
    ".claude/skills/ccb-audit/SKILL.md",
    ".claude/skills/ccb-status/SKILL.md",
    ".claude/skills/ccb-install/SKILL.md",
    ".claude/skills/ccb-report/SKILL.md",
    ".claude/skills/ccb-sol-plan/SKILL.md",
    "docs/agents/framework/CCB_PROTOCOL.md",
    "docs/agents/templates/CCB_JOB_TEMPLATE.json",
    "scripts/ccb/compat.py",
    "scripts/ccb/dispatch.py",
    "scripts/ccb/install.py",
    "scripts/ccb/task_ledger.py",
    "scripts/ccb/sol_plan.py",
    "schemas/ccb_sol_plan.schema.json",
    "schemas/ccb_executor_report.schema.json",
)
DOMAIN_OVERLAY = {
    "backend": ".claude/rules/ccb-domain-backend.md",
    "web": ".claude/rules/ccb-domain-web.md",
    "mobile": ".claude/rules/ccb-domain-mobile.md",
}


class InstallError(Exception):
    pass


def variant_for(domain: str, scope: str) -> str:
    if domain not in DOMAINS or scope not in SCOPES:
        raise InstallError("Unknown domain/scope")
    return ("frontend-" if domain == "web" else "") + scope


def guarded_path(root: Path, relative: str, *, existing: bool) -> Path:
    if not isinstance(relative, str) or "\\" in relative or "\x00" in relative:
        raise InstallError("Invalid path: " + repr(relative))
    pp = PurePosixPath(relative)
    if pp.is_absolute() or not relative or any(x in ("", ".", "..") for x in relative.split("/")):
        raise InstallError("Non-canonical path: " + repr(relative))
    if ".git" in pp.parts or ".ccb-backups" in pp.parts:
        raise InstallError("Reserved path: " + relative)
    out = root
    for part in pp.parts:
        out = out / part
        if out.is_symlink():
            raise InstallError("Symlink path forbidden: " + relative)
    if not out.resolve(strict=False).is_relative_to(root.resolve()):
        raise InstallError("Path escape: " + relative)
    if existing and not out.is_file():
        raise InstallError("Missing source file: " + relative)
    if not existing and out.exists() and not out.is_file():
        raise InstallError("Target is not a regular file: " + relative)
    return out


def prepare_sources(ccb: Path, upstream: Path, lock: dict, domain: str, scope: str):
    variant = variant_for(domain, scope)
    spec = lock.get("variants", {}).get(variant)
    if not isinstance(spec, dict) or not isinstance(spec.get("required_paths"), list):
        raise InstallError("Missing pinned OptCodex variant")
    variant_root = upstream / "variants" / variant
    if not variant_root.is_dir() or variant_root.is_symlink():
        raise InstallError("OptCodex source variant directory missing/unsafe")
    try:
        verify_compatibility(variant_root, variant, lock)
    except (CompatibilityError, OSError) as exc:
        raise InstallError(str(exc)) from exc
    result = {}
    for rel in spec["required_paths"]:
        if rel in result:
            raise InstallError("Duplicate upstream path")
        result[rel] = guarded_path(variant_root, rel, existing=True)
    for rel in (*COMMON, DOMAIN_OVERLAY[domain]):
        if rel in result:
            raise InstallError("OptCodex/CCB path collision: " + rel)
        result[rel] = guarded_path(ccb, rel, existing=True)
    return variant, result


def plan_copy(project: Path, source_files: dict):
    plan = []
    for rel, source in sorted(source_files.items()):
        target = guarded_path(project, rel, existing=False)
        # Read only files that are in the managed, explicit OptCodex/CCB inventory.
        contents = source.read_bytes()
        state = "identical" if target.is_file() and target.read_bytes() == contents else (
            "conflict" if target.exists() else "create"
        )
        plan.append((rel, source, target, state))
    return plan


def apply_copy(project: Path, plan, replace_existing: bool, backup_root: Path):
    conflicts = [rel for rel, _, _, state in plan if state == "conflict"]
    if conflicts and not replace_existing:
        raise InstallError(
            str(len(conflicts)) + " existing managed files differ; review preview and "
            "use --replace-existing only with explicit user authorization"
        )
    if conflicts and backup_root.exists():
        raise InstallError("Backup destination already exists")
    # Reject a backup within the project to prevent accidental source-control addition.
    if backup_root.resolve(strict=False).is_relative_to(project):
        raise InstallError("Backup directory must be outside the project")
    changed = []
    created = []
    backups = []
    try:
        for rel, source, target, state in plan:
            if state == "identical":
                continue
            guarded_path(project, rel, existing=False)
            target.parent.mkdir(parents=True, exist_ok=True)
            if state == "conflict":
                backup = guarded_path(backup_root, rel, existing=False)
                backup.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(target, backup)
                backups.append((target, backup))
            # Same-directory temporary file + replace: per-file atomic update.
            fd, tmp_name = tempfile.mkstemp(prefix=".ccb-copy-", dir=target.parent)
            try:
                with os.fdopen(fd, "wb") as dest, source.open("rb") as src:
                    shutil.copyfileobj(src, dest)
                os.replace(tmp_name, target)
            finally:
                if os.path.exists(tmp_name):
                    os.unlink(tmp_name)
            changed.append(rel)
            if state == "create":
                created.append(target)
    except Exception:
        for dest, backup in reversed(backups):
            if backup.exists():
                shutil.copy2(backup, dest)
        for dest in reversed(created):
            if dest.exists():
                dest.unlink()
        raise
    return changed, len(backups)


def main(argv=None):
    parser = argparse.ArgumentParser(description="Install pinned OptCodex + CCB into a project")
    parser.add_argument("--project", required=True, type=Path, help="Existing target project directory")
    parser.add_argument("--domain", required=True, choices=DOMAINS, help="backend, web or mobile")
    parser.add_argument("--scope", required=True, choices=SCOPES, help="company or personal")
    parser.add_argument("--optcodex-source", type=Path, help="Local OptCodexRules checkout (recommended)")
    parser.add_argument("--ccb-source", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--apply", action="store_true", help="Write files only after user review")
    parser.add_argument("--replace-existing", action="store_true", help="Back up and replace conflicting managed files")
    parser.add_argument("--backup-dir", type=Path, help="Explicit backup location outside the project")
    args = parser.parse_args(argv)
    try:
        if args.replace_existing and not args.apply:
            raise InstallError("--replace-existing requires --apply")
        if args.project.is_symlink() or not args.project.is_dir():
            raise InstallError("Target project must be an existing non-symlink directory")
        if args.ccb_source.is_symlink() or not args.ccb_source.is_dir():
            raise InstallError("CCB source must be an existing non-symlink directory")
        project = args.project.resolve(strict=True)
        ccb = args.ccb_source.resolve(strict=True)
        if project == ccb:
            raise InstallError("Install into a separate product project, not the CCB source repository")
        lock = load_lock(ccb / "optcodex.lock.json")
        with tempfile.TemporaryDirectory(prefix="ccb-optcodex-") as tmp:
            if args.optcodex_source:
                if args.optcodex_source.is_symlink() or not args.optcodex_source.is_dir():
                    raise InstallError("Invalid OptCodex source path")
                upstream = args.optcodex_source.resolve(strict=True)
            else:
                upstream = Path(tmp) / "OptCodexRules"
                env = dict(os.environ)
                env["GIT_TERMINAL_PROMPT"] = "0"
                command = ["git", "clone", "--quiet", "--depth", "1", UPSTREAM_URL, str(upstream)]
                result = subprocess.run(command, env=env, stdout=subprocess.DEVNULL,
                                        stderr=subprocess.PIPE, text=True, timeout=120, check=False)
                if result.returncode:
                    raise InstallError("Cannot clone private OptCodexRules; authenticate GitHub git "
                                       "or provide --optcodex-source (details intentionally suppressed)")
                tree = subprocess.check_output(["git", "-C", str(upstream), "rev-parse",
                                                "HEAD^{tree}"], text=True).strip()
                if tree != lock["source_revision"]:
                    raise InstallError("Upstream OptCodexRules changed; pinned snapshot review required")
            variant, source_files = prepare_sources(ccb, upstream, lock, args.domain, args.scope)
            plan = plan_copy(project, source_files)
            stale = []
            for other_domain, other_rel in DOMAIN_OVERLAY.items():
                if other_domain == args.domain:
                    continue
                old_file = guarded_path(project, other_rel, existing=False)
                if old_file.exists():
                    stale.append(other_rel)
            counts = {s: sum(item[3] == s for item in plan) for s in ("create", "identical", "conflict")}
            preview = {
                "status": "PREVIEW" if not args.apply else "PREFLIGHT",
                "project": str(project),
                "domain": args.domain,
                "scope": args.scope,
                "optcodex_variant": variant,
                "upstream_tree": lock["source_revision"],
                "counts": counts,
                "conflicts": [p[0] for p in plan if p[3] == "conflict"],
                "changes": [p[0] for p in plan if p[3] != "identical"],
                "deletes": [],
                "stale_domain_overlays": stale,
            }
            if not args.apply:
                print(json.dumps(preview, ensure_ascii=False, indent=2))
                return 0
            if stale:
                raise InstallError("Old domain rules still present: " + ", ".join(stale) +
                                   "; archive/remove manually after reviewing them (no auto-delete)")
            stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
            backup = args.backup_dir or project.parent / ("." + project.name + "-ccb-backups") / stamp
            backup = backup.resolve(strict=False)
            changes, backup_count = apply_copy(project, plan, args.replace_existing, backup)
            # Ensure the installed policy pins still match before claiming completion.
            verify_compatibility(project, variant, lock)
            print(json.dumps({
                "status": "INSTALLED",
                "optcodex_variant": variant, "domain": args.domain,
                "created_or_replaced": len(changes),
                "backed_up_existing": backup_count,
                "backup_dir": str(backup) if backup_count else None,
                "no_files_deleted": True,
            }, ensure_ascii=False, indent=2))
            return 0
    except (InstallError, CompatibilityError, OSError, subprocess.TimeoutExpired) as exc:
        print(json.dumps({"status": "BLOCKED", "reason": str(exc)}, ensure_ascii=False))
        return 2


if __name__ == "__main__":
    sys.exit(main())
