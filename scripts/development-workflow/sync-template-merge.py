#!/usr/bin/env python3
"""Preserve consumer patches using committed, per-path template baselines.

Preview is read-only for both checkouts. Private plans contain prepared bytes;
stdout contains only dispositions, counts and an independently approvable digest.
"""
from __future__ import annotations

import argparse
import base64
from collections import Counter
import hashlib
import importlib.util
import json
import os
from pathlib import Path, PurePosixPath
import posixpath
import re
import stat
import subprocess
import sys
import tempfile

STATE_PATH = ".ai-dev-workflow.sync-state.json"
LOCK_PATH = ".ai-dev-workflow.sync-lock"
MODES = {"100644", "100755", "120000"}
BLOCKING = {"conflict", "baseline_unavailable", "blocked"}


class SyncError(Exception):
    """A named failure which cannot authorize a write."""


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def encoded(data: bytes) -> str:
    return base64.b64encode(data).decode("ascii")


def decoded(value: str) -> bytes:
    return base64.b64decode(value, validate=True)


def json_bytes(value) -> bytes:
    return (json.dumps(value, sort_keys=True, indent=2, ensure_ascii=True) + "\n").encode()


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise SyncError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def read_json(data: bytes):
    try:
        return json.loads(data, object_pairs_hook=unique_object)
    except (ValueError, UnicodeError) as exc:
        raise SyncError(f"invalid JSON: {exc}") from exc


def git(repo: Path, *args: str) -> bytes:
    proc = subprocess.run(["git", "-C", str(repo), *args], capture_output=True)
    if proc.returncode:
        # Git diagnostics can contain remote URLs; do not reproduce them.
        raise SyncError(f"Git object read failed ({args[0]}); verify the pinned commit is available")
    return proc.stdout


def commit(repo: Path, revision: str) -> str:
    if not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", revision):
        raise SyncError("baseline/incoming commit must be an exact full lowercase SHA")
    result = git(repo, "rev-parse", "--verify", revision + "^{commit}").decode().strip()
    if result != revision:
        raise SyncError("commit does not resolve to the recorded SHA")
    return result


def valid_path(path: str) -> str:
    if not isinstance(path, str) or not path or "\0" in path or "\\" in path:
        raise SyncError("invalid relative path")
    parts = path.split("/")
    if any(part in {"", ".", "..", ".git"} for part in parts) or PurePosixPath(path).is_absolute():
        raise SyncError(f"unsafe path: {path}")
    return path


def load_module(name: str, filename: str):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(filename))
    if spec is None or spec.loader is None:
        raise SyncError(f"missing helper dependency: {filename}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


SELECTOR = load_module("sync_merge_selector", "select-sync-manifest-entries.py")
COVERAGE = load_module("sync_merge_coverage", "check-sync-manifest-coverage.py")


class Objects:
    def __init__(self):
        self.trees = {}

    def tree(self, repo: Path, sha: str):
        key = (str(repo), sha)
        if key not in self.trees:
            commit(repo, sha)
            result = {}
            for row in git(repo, "ls-tree", "-r", "-z", sha).split(b"\0"):
                if not row:
                    continue
                info, raw_path = row.split(b"\t", 1)
                mode, kind, blob = info.decode("ascii").split()
                path = valid_path(raw_path.decode("utf-8"))
                result[path] = {"mode": mode, "blob": blob, "kind": kind}
            self.trees[key] = result
        return self.trees[key]

    def snapshot(self, repo: Path, sha: str, path: str):
        entry = self.tree(repo, sha).get(path)
        if entry is None:
            return None
        if entry["mode"] not in MODES or entry["kind"] != "blob":
            raise SyncError(f"unsupported Git kind/mode at {path}")
        return {"mode": entry["mode"], "data": encoded(git(repo, "cat-file", "blob", entry["blob"]))}


def safe_ancestors(root: Path, path: str) -> dict:
    result = {}
    for parent in reversed(PurePosixPath(path).parents):
        if str(parent) == ".":
            continue
        target = root / str(parent)
        try:
            info = target.lstat()
        except FileNotFoundError:
            result[str(parent)] = None
            continue
        if not stat.S_ISDIR(info.st_mode):
            raise SyncError(f"unsafe non-directory/symlink ancestor: {parent}")
        result[str(parent)] = stat.S_IMODE(info.st_mode)
    return result


def local_snapshot(root: Path, path: str):
    safe_ancestors(root, path)
    target = root / path
    try:
        info = target.lstat()
    except FileNotFoundError:
        return None
    if stat.S_ISLNK(info.st_mode):
        return {"mode": "120000", "data": encoded(os.fsencode(os.readlink(target)))}
    if not stat.S_ISREG(info.st_mode):
        raise SyncError(f"unsupported consumer kind at {path}")
    # Do not follow a leaf replaced with a symlink between lstat and open.
    fd = os.open(target, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(fd, "rb") as stream:
        opened = os.fstat(stream.fileno())
        if not stat.S_ISREG(opened.st_mode):
            raise SyncError(f"consumer kind changed while reading: {path}")
        return {"mode": "100755" if opened.st_mode & 0o111 else "100644",
                "data": encoded(stream.read()), "permissions": stat.S_IMODE(opened.st_mode)}


def same(left, right) -> bool:
    if left is None or right is None:
        return left is right
    return (left["mode"], left["data"]) == (right["mode"], right["data"])


def merged_permissions(output, ours):
    if output is None or output["mode"] == "120000":
        return output
    output = dict(output)
    perms = ours.get("permissions", 0o644) if ours and ours["mode"] != "120000" else 0o644
    executable = output["mode"] == "100755"
    if not executable:
        perms &= ~0o111
    elif not perms & 0o111:
        perms |= 0o111
    output["permissions"] = perms
    return output


def classify(ours, base, incoming, known: bool):
    def outcome(name, output, reason=""):
        return name, merged_permissions(output, ours), reason
    if same(ours, incoming):
        return outcome("no_change", ours)
    if not known:
        return outcome("baseline_unavailable", ours, "verify an exact prior-sync/bootstrap base or decline and re-preview")
    if base is None and ours is None:
        return outcome("add", incoming)
    if base is not None and ours is None:
        if same(base, incoming):
            return outcome("local_deletion", None)
        return outcome("conflict", None, "consumer deletion conflicts with upstream change")
    if incoming is None:
        return outcome("conflict", ours, "upstream removal requires explicit manual resolution or decline, then fresh preview")
    if same(ours, base):
        return outcome("direct_update", incoming)
    if same(incoming, base):
        return outcome("local_retained", ours)
    if base is None or any(s["mode"] == "120000" for s in (ours, base, incoming)):
        return outcome("conflict", ours, "incompatible additions, types or link targets")
    blobs = [decoded(s["data"]) for s in (ours, base, incoming)]
    try:
        for data in blobs:
            if b"\0" in data:
                raise UnicodeError()
            data.decode("utf-8")
    except UnicodeError:
        return outcome("conflict", ours, "both sides changed non-text content")
    with tempfile.TemporaryDirectory(prefix="sync-merge-text-") as directory:
        files = [Path(directory) / name for name in ("ours", "base", "incoming")]
        for target, data in zip(files, blobs):
            target.write_bytes(data)
        proc = subprocess.run(["git", "merge-file", "-p", "-L", "consumer", "-L", "baseline", "-L", "upstream", *map(str, files)], capture_output=True)
    if proc.returncode:
        return outcome("conflict", ours, "three-way text merge is not clean; resolve before re-preview")
    mode = incoming["mode"] if ours["mode"] == base["mode"] else ours["mode"]
    return outcome("clean_merge", {"mode": mode, "data": encoded(proc.stdout)})


def validate_state(snapshot, identity: str):
    if snapshot is None:
        return None
    if snapshot["mode"] == "120000":
        raise SyncError(f"{STATE_PATH}: state cannot be a symlink")
    state = read_json(decoded(snapshot["data"]))
    if not isinstance(state, dict) or set(state) != {"schema_version", "template_id", "files"}:
        raise SyncError(f"{STATE_PATH}: invalid state shape")
    if type(state["schema_version"]) is not int or state["schema_version"] != 1:
        raise SyncError(f"{STATE_PATH}: unsupported schema version")
    if state["template_id"] != identity or not isinstance(state["files"], dict):
        raise SyncError(f"{STATE_PATH}: template identity or files mismatch")
    for path, entry in state["files"].items():
        valid_path(path)
        if not isinstance(entry, dict) or set(entry) != {"commit", "source", "blob", "mode"}:
            raise SyncError(f"{STATE_PATH}: invalid entry for {path}")
        if entry["source"] not in {"template", "consumer"} or not isinstance(entry["commit"], str) or not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", entry["commit"]):
            raise SyncError(f"{STATE_PATH}: invalid provenance for {path}")
        if entry["mode"] is None and entry["blob"] is None:
            continue
        if entry["mode"] not in MODES or not isinstance(entry["blob"], str) or not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", entry["blob"]):
            raise SyncError(f"{STATE_PATH}: invalid object metadata for {path}")
    return state


def selection(inputs, objects: Objects):
    root, sha = Path(inputs["template_root"]), inputs["template_ref"]
    manifest = objects.snapshot(root, sha, "sync-manifest.yaml")
    if manifest is not None:
        if manifest["mode"] == "120000":
            raise SyncError("sync-manifest.yaml: committed manifest cannot be a symlink")
        with tempfile.TemporaryDirectory(prefix="sync-merge-manifest-") as directory:
            path = Path(directory) / "sync-manifest.yaml"
            path.write_bytes(decoded(manifest["data"]))
            _, entries = SELECTOR.parse_manifest(path)
        scopes = SELECTOR.ROLE_SCOPE_SELECTION[inputs["role"]]
        selected = [e for e in entries if e.category == "always_sync" and e.mode_scope in scopes]
        owned = {e.path for e in entries if e.category == "project_specific" and not e.glob}
        matches = lambda path: any(COVERAGE.entry_matches(e, path) for e in selected)
        evidence = manifest
    else:
        filename = inputs.get("selection_file")
        if not filename:
            raise SyncError("sync-manifest.yaml: absent; provide explicit protocol fallback --selection-file")
        raw = Path(filename).read_bytes()
        fallback = read_json(raw)
        if not isinstance(fallback, dict) or set(fallback) != {"role", "paths", "project_specific"} or fallback["role"] != inputs["role"]:
            raise SyncError("fallback selection must bind role, paths and project_specific")
        if not all(isinstance(fallback[k], list) for k in ("paths", "project_specific")):
            raise SyncError("fallback paths/project_specific must be lists")
        chosen = {valid_path(p) for p in fallback["paths"]}
        owned = {valid_path(p) for p in fallback["project_specific"]}
        matches = lambda path: path in chosen
        evidence = {"fallback_digest": digest(raw)}
    owned |= {STATE_PATH, LOCK_PATH, ".ai-dev-workflow.local.yaml", ".ai-dev-workflow.local.env", ".ai-dev-workflow.yaml"}
    return matches, owned, evidence


def link_graph(root: Path, rows: list[dict]):
    """Validate each selected final link without writing or following OS links."""
    planned = {r["path"]: r["output"] for r in rows}
    directories = {str(p) for path, value in planned.items() if value is not None for p in PurePosixPath(path).parents if str(p) != "."}
    observed = {}

    def node(path):
        if path in planned:
            value = planned[path]
            return "missing" if value is None else value
        if path in directories:
            return "directory"
        target = root / path
        try:
            info = target.lstat()
        except FileNotFoundError:
            observed[path] = None
            return "missing"
        if stat.S_ISLNK(info.st_mode):
            value = {"mode": "120000", "data": encoded(os.fsencode(os.readlink(target)))}
            observed[path] = value
            return value
        value = "directory" if stat.S_ISDIR(info.st_mode) else "file"
        observed[path] = {"kind": value, "permissions": stat.S_IMODE(info.st_mode)}
        return value

    def resolve(path, seen):
        if path == ".":
            return "directory"
        parts = path.split("/")
        for index in range(len(parts)):
            prefix = "/".join(parts[:index + 1])
            value = node(prefix)
            if isinstance(value, dict) and value.get("mode") == "120000":
                if prefix in seen:
                    raise SyncError(f"symlink cycle at {prefix}")
                target = os.fsdecode(decoded(value["data"]))
                if not target or target.startswith("/") or "\0" in target:
                    raise SyncError(f"unsafe symlink target at {prefix}")
                combined = posixpath.normpath(posixpath.join(posixpath.dirname(prefix), target, *parts[index + 1:]))
                if combined == ".." or combined.startswith("../") or ".git" in combined.split("/"):
                    raise SyncError(f"symlink escapes consumer root at {prefix}")
                return resolve(combined, seen | {prefix})
            if value == "missing":
                raise SyncError(f"dangling symlink target: {prefix}")
            if index < len(parts) - 1 and value != "directory":
                raise SyncError(f"non-directory symlink target ancestor: {prefix}")
        return value

    for row in rows:
        if row["disposition"] in BLOCKING:
            continue
        output = row["output"]
        if output and output["mode"] == "120000":
            try:
                resolve(row["path"], set())
            except (SyncError, UnicodeError, ValueError) as exc:
                row.update(disposition="blocked", reason=str(exc))
    return observed


def build_preview(inputs: dict, lock_owned: bool = False):
    root, source = Path(inputs["consumer_root"]), Path(inputs["template_root"])
    objects = Objects()
    incoming_tree = objects.tree(source, inputs["template_ref"])
    source_head = git(source, "rev-parse", "HEAD").decode().strip()
    matches, owned, selection_evidence = selection(inputs, objects)
    state_snapshot = local_snapshot(root, STATE_PATH)
    error = ""
    try:
        state = validate_state(state_snapshot, inputs["template_id"])
    except SyncError as exc:
        state, error = None, str(exc)
    if not lock_owned and os.path.lexists(root / LOCK_PATH):
        error = f"{LOCK_PATH}: active or interrupted transaction; inspect recovery material before retrying"
    candidates = set(incoming_tree) | (set(state["files"]) if state else set())
    paths = sorted(p for p in candidates if p not in owned and matches(p))
    declines = set(inputs["decline"])
    if not declines.issubset(paths):
        raise SyncError("declined path is outside selected always-sync scope")
    rows, ancestors = [], {}
    for path in paths:
        if path in declines:
            continue
        ours = incoming = base = None
        known, reason, disposition = False, error, "blocked"
        try:
            ancestors.update(safe_ancestors(root, path))
            ours = local_snapshot(root, path)
            incoming = objects.snapshot(source, inputs["template_ref"], path)
            if error:
                raise SyncError(error)
            entry = state["files"].get(path) if state else None
            if entry:
                base_root = source if entry["source"] == "template" else root
                base = objects.snapshot(base_root, entry["commit"], path)
                tree_entry = objects.tree(base_root, entry["commit"]).get(path)
                if (tree_entry["mode"] if tree_entry else None, tree_entry["blob"] if tree_entry else None) != (entry["mode"], entry["blob"]):
                    raise SyncError("baseline commit disagrees with stored object metadata")
                known = True
            elif inputs.get("base_ref"):
                base_root = source if inputs["base_source"] == "template" else root
                base = objects.snapshot(base_root, inputs["base_ref"], path)
                known = True
            disposition, output, reason = classify(ours, base, incoming, known)
        except (SyncError, OSError, UnicodeError, ValueError, SELECTOR.ManifestError) as exc:
            output, reason = ours, str(exc)
        rows.append({"path": path, "disposition": disposition, "reason": reason,
                     "ours": ours, "incoming": incoming, "output": output,
                     "baseline_known": known})
    link_evidence = link_graph(root, rows)
    counts = dict(sorted(Counter(r["disposition"] for r in rows).items()))
    return {"schema_version": 1, "inputs": inputs, "source_head": source_head,
            "selection_evidence": selection_evidence, "state_before": state_snapshot,
            "state": state, "config_before": local_snapshot(root, ".ai-dev-workflow.yaml"),
            "ancestors": ancestors, "link_evidence": link_evidence, "declined": sorted(declines),
            "rows": rows, "counts": counts, "selected_count": len(rows),
            "result": "blocked" if error or any(r["disposition"] in BLOCKING for r in rows) else "ready",
            "error": error}


def show(preview, approved_digest: str = ""):
    print("RESULT=" + preview["result"])
    print("SELECTED_COUNT=" + str(preview["selected_count"]))
    print("COUNTS=" + json.dumps(preview["counts"], sort_keys=True))
    print("Locally modified template files")
    for row in preview["rows"]:
        print(f"{row['disposition']}\t{row['path']}" + (f"\t{row['reason']}" if row["reason"] else ""))
    for path in preview["declined"]:
        print("declined\t" + path)
    if preview["error"]:
        print("ERROR=" + preview["error"])
    if approved_digest:
        print("PREVIEW_DIGEST=" + approved_digest)


def write_private_plan(path: Path, data: bytes, roots):
    resolved = path.resolve()
    if any(resolved == root or root in resolved.parents for root in roots):
        raise SyncError("preview plan must be private scratch outside both checkouts")
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, "wb") as stream:
        os.fchmod(stream.fileno(), 0o600)
        stream.write(data)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    preview = sub.add_parser("preview")
    preview.add_argument("--template-root", required=True)
    preview.add_argument("--consumer-root", required=True)
    preview.add_argument("--template-ref", required=True)
    preview.add_argument("--template-id", required=True)
    preview.add_argument("--role", choices=sorted(SELECTOR.VALID_ROLES), required=True)
    preview.add_argument("--base-ref")
    preview.add_argument("--base-source", choices=("template", "consumer"))
    preview.add_argument("--selection-file")
    preview.add_argument("--decline", action="append", default=[])
    preview.add_argument("--plan", required=True)
    args = parser.parse_args(argv)
    try:
        if bool(args.base_ref) != bool(args.base_source):
            raise SyncError("verified --base-ref and --base-source must be supplied together")
        if not re.fullmatch(r"[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)+", args.template_id):
            raise SyncError("template identity must be a normalized repository name, without credentials or URLs")
        inputs = {k: getattr(args, k) for k in ("template_ref", "template_id", "role", "base_ref", "base_source", "selection_file", "decline")}
        inputs.update(template_root=str(Path(args.template_root).resolve()), consumer_root=str(Path(args.consumer_root).resolve()))
        inputs["decline"] = sorted({valid_path(p) for p in args.decline})
        if inputs["selection_file"]:
            inputs["selection_file"] = str(Path(inputs["selection_file"]).resolve())
        plan_path = Path(args.plan)
        # Refuse an unsafe output before reading/preparing any data.
        if any(root == plan_path.resolve() or root in plan_path.resolve().parents for root in (Path(inputs["template_root"]), Path(inputs["consumer_root"]))):
            raise SyncError("preview plan must be private scratch outside both checkouts")
        result = build_preview(inputs)
        raw = json_bytes(result)
        write_private_plan(plan_path, raw, (Path(inputs["template_root"]), Path(inputs["consumer_root"])))
        show(result, digest(raw))
        return 0 if result["result"] == "ready" else 1
    except (SyncError, OSError, ValueError, UnicodeError, SELECTOR.ManifestError) as exc:
        print(f"RESULT=blocked\nERROR={exc}\nACTION=Resolve the named input and generate a fresh preview.", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
