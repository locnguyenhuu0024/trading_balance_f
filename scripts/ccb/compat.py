#!/usr/bin/env python3
"""Fail-closed OptCodexRules variant/version/integrity preflight.

Hashes only explicitly pinned governance files, never operational configuration,
source contents, or secrets. This is an exact upstream compatibility lock.
"""
from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path

ROUTES = {
    "E0": ("gpt-6-luna", "xhigh"),
    "E1": ("gpt-6.1-terra", "low"),
    "E2": ("gpt-6.1-terra", "medium"),
    "E3": ("gpt-6.1-terra", "high"),
    "E4": ("gpt-6.1-terra", "xhigh"),
    "E5": ("gpt-6.1-terra", "max"),
}
ALLOWED_ROUTES = {
    "E0": {("gpt-6-luna", "xhigh")},
    "E1": {("gpt-6.1-terra", "low"), ("gpt-6-luna", "xhigh")},
    "E2": {("gpt-6.1-terra", "medium"), ("gpt-6.1-terra", "low")},
    "E3": {("gpt-6.1-terra", "high"), ("gpt-6.1-terra", "medium")},
    "E4": {("gpt-6.1-terra", "xhigh"), ("gpt-6.1-terra", "high")},
    "E5": {("gpt-6.1-terra", "max"), ("gpt-6.1-terra", "xhigh")},
}
POLICY_PATH = "docs/agents/framework/EXECUTOR_ROUTING_POLICY.json"
SUPPORTED_VARIANTS = ("company", "personal", "frontend-company", "frontend-personal")
LOCK_PATH = Path(__file__).resolve().parents[2] / "optcodex.lock.json"


class CompatibilityError(Exception):
    pass


def git_blob_sha(data: bytes) -> str:
    return hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()


def load_lock(path: Path = LOCK_PATH) -> dict:
    try:
        lock = json.loads(path.read_text(encoding="utf-8"))
    except (ValueError, OSError) as exc:
        raise CompatibilityError("Cannot load CCB compatibility lock") from exc
    if not isinstance(lock, dict) or lock.get("schema_version") != 1:
        raise CompatibilityError("Unsupported compatibility lock")
    if lock.get("source_repository") != "locnguyenhuu0024/OptCodexRules":
        raise CompatibilityError("Unknown OptCodexRules source repository")
    return lock


def _safe_governance_path(root: Path, relative: str) -> Path:
    """Read only fixed non-symlink OptCodex policy paths, never general repo files."""
    if not isinstance(relative, str) or "\\" in relative:
        raise CompatibilityError("Invalid governance path")
    parts = relative.split("/")
    if any(x in ("", ".", "..") for x in parts):
        raise CompatibilityError("Invalid governance path")
    if not (
        relative in {"AGENTS.md", "VERSION", "BASELINE_VERSION"}
        or relative.startswith("BASELINE_AGENTS_") and relative.endswith(".md") and "/" not in relative
        or relative.startswith("docs/agents/framework/") and relative.endswith(".md")
    ):
        raise CompatibilityError("Non-governance path in lock")
    p = root
    for part in parts:
        p = p / part
        if p.is_symlink():
            raise CompatibilityError("Symlink governance path rejected: " + relative)
    if not p.is_file() or not p.resolve().is_relative_to(root.resolve()):
        raise CompatibilityError("Missing OptCodex governance file: " + relative)
    return p


def _required_path(root: Path, relative: str) -> Path:
    """Check tracked variant completeness by *file name/existence only*."""
    if not isinstance(relative, str) or "\\\\" in relative or not relative:
        raise CompatibilityError("Invalid required variant path")
    parts = relative.split("/")
    if any(part in {"", ".", ".."} for part in parts):
        raise CompatibilityError("Invalid required variant path")
    p = root
    for part in parts:
        p = p / part
        if p.is_symlink():
            raise CompatibilityError("Required variant path is a symlink: " + relative)
    if not p.is_file() or not p.resolve().is_relative_to(root.resolve()):
        raise CompatibilityError("Incomplete OptCodex variant: missing " + relative)
    return p


def verify_compatibility(root: Path, variant: str, lock: dict | None = None) -> dict:
    """Verify installed variant's pinned governance source without reading app files."""
    lock = lock if lock is not None else load_lock()
    if variant not in SUPPORTED_VARIANTS:
        raise CompatibilityError("Unknown OptCodex variant")
    spec = lock.get("variants", {}).get(variant)
    if not isinstance(spec, dict) or not spec.get("pinned_files"):
        raise CompatibilityError("Variant missing in OptCodex compatibility lock")
    expected = spec["pinned_files"]
    required_paths = spec.get("required_paths")
    if not isinstance(expected, dict) or not expected:
        raise CompatibilityError("Invalid pinned file mapping")
    if not isinstance(required_paths, list) or not required_paths or any(
        not isinstance(p, str) for p in required_paths
    ) or not set(expected).issubset(set(required_paths)) or len(required_paths) != len(set(required_paths)):
        raise CompatibilityError("Invalid complete-variant file inventory")
    root = root.resolve(strict=True)
    # Check the full tracked OptCodex variant inventory without opening any
    # operational config, source code, third-party assets, or secrets.
    for relative in required_paths:
        _required_path(root, relative)
    for relative, sha in expected.items():
        if not isinstance(sha, str) or len(sha) != 40 or any(x not in "0123456789abcdef" for x in sha):
            raise CompatibilityError("Malformed expected Git blob SHA")
        contents = _safe_governance_path(root, relative).read_bytes()
        actual = git_blob_sha(contents)
        if actual != sha:
            # Git core.autocrlf can materialize canonical LF blobs as CRLF
            # on Windows. The lock pins canonical Git bytes, not the checkout.
            # Accept ONLY a matching canonical hash after EOL conversion.
            normalized = contents.replace(b"\r\n", b"\n")
            if normalized == contents or git_blob_sha(normalized) != sha:
                raise CompatibilityError(
                    "OptCodex governance drift: " + relative +
                    " (STOP; review/update lock; non-EOL change)"
                )
    load_route_policy(root)
    return {
        "variant": variant,
        "variant_version": spec["variant_version"],
        "baseline_version": spec["baseline_version"],
        "source_revision": lock["source_revision"],
        "checked_governance_files": len(expected),
        "checked_variant_paths": len(required_paths),
    }


TERRA_REASONS = {"UI_VISUAL", "HARD_DEBUG", "LUNA_REWORK", "E2_COMPLEX"}
OVERRIDE_REASONS = {"MODEL_AVAILABILITY", "LATENCY", "COST", "A_B_TEST", "REWORK", "USER_REQUEST"}


def load_route_policy(root: Path) -> dict:
    """Load runtime defaults, never arbitrary routes. Governance pins are separate."""
    path = _required_path(root.resolve(strict=True), POLICY_PATH)
    if path.stat().st_size > 4096:
        raise CompatibilityError("Oversized executor routing policy")
    try:
        obj = json.loads(path.read_text(encoding="utf-8"))
    except (ValueError, OSError) as exc:
        raise CompatibilityError("Invalid executor routing policy JSON") from exc
    if (not isinstance(obj, dict)
            or set(obj) != {"schema_version", "governance_contract", "defaults"}
            or obj["schema_version"] != 2
            or obj["governance_contract"] != "optcodex-executor-routing-v2"):
        raise CompatibilityError("Invalid routing policy contract")
    defaults = obj["defaults"]
    if not isinstance(defaults, dict) or set(defaults) != set(ALLOWED_ROUTES):
        raise CompatibilityError("Missing executor class in routing defaults")
    for cls, choices in ALLOWED_ROUTES.items():
        entry = defaults[cls]
        if not isinstance(entry, dict) or set(entry) != {"model", "effort"}:
            raise CompatibilityError("Invalid default route entry: " + cls)
        try:
            pair = (entry["model"], entry["effort"])
            if pair not in choices:
                raise CompatibilityError("Default route outside allowlist: " + cls)
        except TypeError as exc:
            raise CompatibilityError("Unhashable route fields") from exc
    return obj


def require_route(route: str, model: object, effort: object, trial: object = None,
                  *, policy: dict | None = None, override: object = None) -> None:
    """Enforce allowlisted explicit model+effort; nondefault route needs authorization."""
    if route not in ALLOWED_ROUTES:
        raise CompatibilityError("Unknown executor class")
    try:
        valid = (model, effort) in ALLOWED_ROUTES[route]
    except TypeError:
        valid = False
    if not valid:
        raise CompatibilityError("ROUTE_MISMATCH: unsupported executor route")
    defaults = (policy or {"defaults": {
        key: {"model": m, "effort": e} for key, (m, e) in ROUTES.items()
    }})["defaults"]
    selected_default = (defaults[route]["model"], defaults[route]["effort"])
    if trial is not None and override is not None:
        raise CompatibilityError("BLOCKED_ROUTE: conflicting approval objects")
    if trial is not None:
        if not isinstance(trial, dict) or set(trial) != {"experiment_id", "reason", "user_approved"}:
            raise CompatibilityError("BLOCKED_ROUTE: malformed legacy Terra experiment")
        if (model != "gpt-6.1-terra" or not isinstance(trial["experiment_id"], str)
                or not re.fullmatch(r"[A-Za-z0-9_-]{1,80}", trial["experiment_id"])
                or trial["reason"] not in TERRA_REASONS or trial["user_approved"] is not True):
            raise CompatibilityError("BLOCKED_ROUTE: invalid Terra experiment authorization")
        return
    if (model, effort) == selected_default:
        if override is not None:
            raise CompatibilityError("BLOCKED_ROUTE: override on default route")
        return
    if not isinstance(override, dict) or set(override) != {"approval_id", "reason", "user_approved"}:
        raise CompatibilityError("BLOCKED_ROUTE: explicit non-default override required")
    if (not isinstance(override["approval_id"], str)
            or not re.fullmatch(r"[A-Za-z0-9_-]{1,80}", override["approval_id"])
            or override["reason"] not in OVERRIDE_REASONS
            or override["user_approved"] is not True):
        raise CompatibilityError("BLOCKED_ROUTE: invalid non-default approval")
