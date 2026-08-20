#!/usr/bin/env bash
#
# Manage hub-owned delivery bundle manifests.

set -euo pipefail

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR_CODE=missing_python3 message='python3 is required'" >&2
  exit 2
fi

python3 - "$@" <<'PY'
import argparse
import copy
import datetime as dt
import json
import os
import re
import shutil
import sys
import tempfile

SCHEMA = "delivery_bundle_manifest.v1"
EVIDENCE_SCHEMA = "component_release_evidence.v1"
KEY_RE = re.compile(r"^[A-Za-z0-9._-]+$")
MISSING_BLOCKERS = [
    "routing_evidence_missing",
    "release_evidence_missing",
    "ci_evidence_missing",
    "deployment_evidence_missing",
    "cleanup_evidence_missing",
    "hub_tracker_reconciliation_missing",
    "child_release_state_missing",
]


class Parser(argparse.ArgumentParser):
    def error(self, message):
        fail("invalid_arguments", message, 2)


def fail(code, message, exit_code=1):
    safe = str(message).replace("'", "'\\''")
    print(f"ERROR_CODE={code} message='{safe}'", file=sys.stderr)
    raise SystemExit(exit_code)


def now():
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def validate_bundle_key(bundle_key):
    if not bundle_key:
        fail("missing_bundle_key", "--bundle-key is required", 2)
    if not KEY_RE.match(bundle_key):
        fail("invalid_bundle_key", "--bundle-key must contain only letters, numbers, '.', '_' or '-'", 2)


def load_json_file(path, label, required=True):
    if not path:
        fail("invalid_arguments", f"{label} path is required", 2)
    if not os.path.exists(path):
        if required:
            fail(f"{label}_not_found", f"{label} file not found: {path}")
        return None
    try:
        with open(path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
    except json.JSONDecodeError as exc:
        fail("invalid_json", f"{label} file is not valid JSON: {exc}")
    if not isinstance(data, dict):
        fail("invalid_json", f"{label} file must contain a JSON object")
    return data


def validate_manifest(data, bundle_key):
    if data.get("schema_version") != SCHEMA:
        fail("invalid_manifest_schema", f"manifest must use schema_version {SCHEMA}")
    if data.get("bundle_key") != bundle_key:
        fail("bundle_key_mismatch", "manifest bundle_key does not match --bundle-key")
    if not isinstance(data.get("revision"), int) or data["revision"] < 1:
        fail("invalid_manifest_revision", "manifest revision must be a positive integer")
    return data


def atomic_write(path, data):
    parent = os.path.dirname(os.path.abspath(path)) or "."
    os.makedirs(parent, exist_ok=True)
    base = os.path.basename(path)
    fd = None
    tmp_path = None
    try:
        fd, tmp_path = tempfile.mkstemp(prefix=f".{base}.", suffix=".tmp", dir=parent)
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fd = None
            json.dump(data, fh, indent=2, sort_keys=True)
            fh.write("\n")
        load_json_file(tmp_path, "staged_manifest")
        os.replace(tmp_path, path)
    except OSError as exc:
        fail("manifest_write_failed", f"failed to write manifest atomically: {exc}")
    finally:
        if fd is not None:
            os.close(fd)
        if tmp_path and os.path.exists(tmp_path):
            os.unlink(tmp_path)


def with_lock(path, bundle_key, mutate):
    lock_dir = f"{path}.lock"
    parent = os.path.dirname(os.path.abspath(path)) or "."
    try:
        os.makedirs(parent, exist_ok=True)
    except OSError as exc:
        fail("manifest_write_failed", f"failed to create manifest directory: {exc}")
    try:
        os.mkdir(lock_dir)
    except FileExistsError:
        fail("lock_unavailable", f"manifest lock is already held: {lock_dir}")
    except OSError as exc:
        fail("lock_unavailable", f"failed to acquire manifest lock: {exc}")
    owner_path = os.path.join(lock_dir, "owner.json")
    try:
        atomic_write(owner_path, {"pid": os.getpid(), "acquired_at": now()})
    except SystemExit:
        shutil.rmtree(lock_dir, ignore_errors=True)
        raise
    try:
        current = load_json_file(path, "manifest", required=False)
        if current is not None:
            validate_manifest(current, bundle_key)
        new_manifest, changed, result = mutate(current)
        if changed:
            atomic_write(path, new_manifest)
        return result
    finally:
        shutil.rmtree(lock_dir, ignore_errors=True)


def check_expected_revision(manifest, expected):
    if expected is None:
        fail("missing_expected_revision", "--expected-revision is required", 2)
    if int(manifest["revision"]) != int(expected):
        fail("stale_manifest_revision", "manifest revision does not match --expected-revision")


def audit_event(event, revision, **extra):
    payload = {"event": event, "revision": revision, "created_at": now()}
    payload.update({k: v for k, v in extra.items() if v is not None and v != ""})
    return payload


def blocker_for_component(component):
    if component.get("component_tag") in (None, ""):
        return "missing_component_tag"
    state = component.get("evidence_state")
    if state == "conflicting":
        return "conflicting_component_evidence"
    if state == "stale":
        return "stale_readiness"
    if state in ("missing", "partial"):
        return "missing_component_evidence"
    if component.get("evidence_schema_version") != EVIDENCE_SCHEMA:
        return "missing_component_evidence"
    if component.get("routing_outcome") != "component_release_routed":
        return "missing_component_evidence"
    release = component.get("release_outcome")
    if release in (None, ""):
        return "missing_component_evidence"
    if release == "pending":
        return "pending_component_outcome"
    if release in ("failed", "blocked"):
        return "blocked_component_outcome"
    if release != "completed":
        return "blocked_component_outcome"
    for field in ("ci_outcome", "deployment_outcome"):
        value = component.get(field)
        if value in (None, ""):
            return "missing_component_evidence"
        if value == "pending":
            return "pending_component_outcome"
        if value in ("failed", "blocked"):
            return "blocked_component_outcome"
    if component.get("ci_outcome") not in ("passed", "not_applicable", "skipped"):
        return "blocked_component_outcome"
    if component.get("deployment_outcome") not in ("recorded", "not_applicable"):
        return "blocked_component_outcome"
    cleanup = component.get("cleanup_outcome")
    if cleanup in (None, ""):
        return "missing_component_evidence"
    if cleanup in ("not_started", "partial", "pending"):
        return "pending_component_outcome"
    if cleanup != "complete":
        return "blocked_component_outcome"
    hub = component.get("hub_tracker_reconciliation_outcome")
    if hub in (None, ""):
        return "missing_component_evidence"
    if hub == "pending":
        return "pending_component_outcome"
    if hub not in ("complete", "deferred"):
        return "blocked_component_outcome"
    child = component.get("child_release_state")
    if child in (None, ""):
        return "missing_component_evidence"
    if child == "pending":
        return "pending_component_outcome"
    if child not in ("released", "merged"):
        return "blocked_component_outcome"
    return None


def component_view(component):
    result = copy.deepcopy(component)
    blocker = blocker_for_component(component)
    if blocker is None:
        result["evidence_state"] = "verified"
        result["blockers"] = []
    elif component.get("evidence_schema_version") != EVIDENCE_SCHEMA:
        result["evidence_state"] = "missing"
        result["blockers"] = list(MISSING_BLOCKERS)
    else:
        result["evidence_state"] = "conflicting" if blocker == "conflicting_component_evidence" else "partial"
        result["blockers"] = [blocker]
    return result


def inspect_manifest(manifest):
    components = [component_view(c) for c in manifest.get("components", [])]
    blockers = []
    for comp in components:
        for blocker in comp.get("blockers", []):
            blockers.append({"component_key": comp.get("component_key"), "blocker": blocker})
    ready = len(components) > 0 and not blockers
    status = "ready_to_finalize" if ready else "blocked"
    result = copy.deepcopy(manifest)
    result["status"] = "finalized" if manifest.get("status") == "finalized" else status
    result["components"] = components
    result["readiness"] = {
        "revision": manifest.get("revision"),
        "ready": ready,
        "status": result["status"],
        "blockers": blockers,
    }
    return result


def new_manifest(args):
    return {
        "schema_version": SCHEMA,
        "bundle_key": args.bundle_key,
        "title": args.title,
        "purpose": args.purpose,
        "parent_ref": args.parent_ref,
        "child_items": args.child_item or [],
        "finalization_owner": args.finalization_owner,
        "rollout_notes": args.rollout_notes or "",
        "status": "open",
        "revision": 1,
        "components": [
            {
                "component_key": key,
                "evidence_state": "missing",
                "blockers": list(MISSING_BLOCKERS),
            }
            for key in (args.component or [])
        ],
        "removed_components": [],
        "readiness": None,
        "finalization": None,
        "audit_events": [audit_event("bundle_created", 1)],
    }


def stable_value(evidence, field):
    if field in evidence:
        return evidence[field]
    binding = evidence.get("target_binding")
    if isinstance(binding, dict):
        return binding.get(field)
    return None


def evidence_hash(evidence):
    encoded = json.dumps(evidence, sort_keys=True, separators=(",", ":")).encode("utf-8")
    import hashlib
    return "sha256:" + hashlib.sha256(encoded).hexdigest()


def component_from_evidence(args):
    evidence = load_json_file(args.evidence_file, "evidence")
    if evidence.get("schema_version") != EVIDENCE_SCHEMA:
        fail("invalid_evidence_schema", f"evidence must use schema_version {EVIDENCE_SCHEMA}")
    if not args.component_tag:
        fail("missing_component_tag", "--component-tag is required", 2)
    component = {
        "component_key": args.component_key,
        "evidence_state": "verified",
        "evidence_schema_version": EVIDENCE_SCHEMA,
        "evidence_hash": evidence_hash(evidence),
        "selected_product_repo_key": stable_value(evidence, "selected_product_repo_key"),
        "canonical_repository_identity": stable_value(evidence, "canonical_repository_identity"),
        "release_correlation_key": stable_value(evidence, "release_correlation_key"),
        "contract_revision": stable_value(evidence, "contract_revision"),
        "component_tag": args.component_tag,
        "component_version": args.component_version,
        "source_pr": str(args.source_pr),
        "release_pr": str(args.release_pr),
        "routing_outcome": evidence.get("routing_outcome"),
        "release_outcome": evidence.get("release_outcome"),
        "ci_outcome": evidence.get("ci_outcome"),
        "deployment_outcome": evidence.get("deployment_outcome"),
        "cleanup_outcome": evidence.get("cleanup_outcome"),
        "hub_tracker_ref": evidence.get("hub_tracker_ref"),
        "hub_tracker_reconciliation_outcome": args.hub_tracker_reconciliation_outcome,
        "child_item": args.child_item,
        "child_release_state": args.child_release_state,
    }
    missing = [
        field
        for field in (
            "selected_product_repo_key",
            "canonical_repository_identity",
            "release_correlation_key",
            "contract_revision",
        )
        if not component.get(field)
    ]
    if missing:
        fail("invalid_evidence_identity", "evidence is missing stable identity fields: " + ", ".join(missing))
    if component["selected_product_repo_key"] != args.component_key:
        fail(
            "component_key_repo_mismatch",
            "--component-key '"
            + str(args.component_key)
            + "' does not match evidence selected_product_repo_key '"
            + str(component["selected_product_repo_key"])
            + "'",
        )
    return component_view(component)


def find_component(components, key):
    for idx, component in enumerate(components):
        if component.get("component_key") == key:
            return idx, component
    return None, None


def invalidate_readiness(manifest):
    if manifest.get("status") == "ready_to_finalize":
        manifest["status"] = "open"
    manifest["readiness"] = None


def output(data, json_output):
    if json_output:
        print(json.dumps(data, indent=2, sort_keys=True))
    else:
        for key, value in data.items():
            if isinstance(value, (dict, list)):
                value = json.dumps(value, sort_keys=True)
            print(f"{str(key).upper()}={value}")


def cmd_create(args):
    validate_bundle_key(args.bundle_key)
    if not args.component:
        fail("missing_component", "at least one --component is required", 2)
    def mutate(current):
        if current is not None:
            fail("manifest_already_exists", "manifest already exists")
        manifest = new_manifest(args)
        return manifest, True, {"result": "created", "manifest": manifest}
    output(with_lock(args.manifest, args.bundle_key, mutate), args.json)


def cmd_add_component(args):
    validate_bundle_key(args.bundle_key)
    def mutate(current):
        if current is None:
            fail("manifest_not_found", "manifest file not found")
        check_expected_revision(current, args.expected_revision)
        if current.get("status") == "finalized":
            fail("bundle_finalized", "finalized bundles cannot be changed")
        manifest = copy.deepcopy(current)
        idx, existing = find_component(manifest.get("components", []), args.component_key)
        if existing is not None:
            return manifest, False, {"result": "idempotent", "manifest": manifest}
        manifest.setdefault("components", []).append({
            "component_key": args.component_key,
            "evidence_state": "missing",
            "blockers": list(MISSING_BLOCKERS),
        })
        manifest["revision"] += 1
        invalidate_readiness(manifest)
        manifest.setdefault("audit_events", []).append(
            audit_event("component_added", manifest["revision"], component_key=args.component_key)
        )
        return manifest, True, {"result": "updated", "manifest": manifest}
    output(with_lock(args.manifest, args.bundle_key, mutate), args.json)


def cmd_update_component(args):
    validate_bundle_key(args.bundle_key)
    incoming = component_from_evidence(args)
    stable_fields = (
        "selected_product_repo_key",
        "canonical_repository_identity",
        "release_correlation_key",
        "contract_revision",
    )
    def mutate(current):
        if current is None:
            fail("manifest_not_found", "manifest file not found")
        check_expected_revision(current, args.expected_revision)
        if current.get("status") == "finalized":
            fail("bundle_finalized", "finalized bundles cannot be changed")
        manifest = copy.deepcopy(current)
        idx, existing = find_component(manifest.get("components", []), args.component_key)
        if existing is not None and existing.get("evidence_schema_version") == EVIDENCE_SCHEMA:
            for field in stable_fields:
                if existing.get(field) != incoming.get(field):
                    fail("conflicting_component_evidence", f"component evidence conflicts on {field}")
            # component_tag/component_version are allowed to change across an
            # actual new release (a different release_pr is the authoritative
            # signal that a new release happened -- see the documented re-tag
            # flow in docs/testing/workflow/1357-delivery-bundle-issue-manifest-workflow.smoke-test.md).
            # But a version claim for the *same* release_pr must stay stable:
            # a different component_tag/component_version under an unchanged
            # release_pr is the conflicting "version state" acceptance
            # criterion 6 describes, not a legitimate re-tag, and must be
            # rejected instead of silently overwriting the accepted release
            # composition.
            if existing.get("release_pr") == incoming.get("release_pr"):
                for field in ("component_tag", "component_version"):
                    if existing.get(field) != incoming.get(field):
                        fail("conflicting_component_evidence", f"component evidence conflicts on {field}")
            if {k: existing.get(k) for k in incoming.keys()} == incoming:
                return manifest, False, {"result": "idempotent", "manifest": manifest}
        if idx is None:
            manifest.setdefault("components", []).append(incoming)
        else:
            manifest["components"][idx] = incoming
        manifest["revision"] += 1
        invalidate_readiness(manifest)
        manifest.setdefault("audit_events", []).append(
            audit_event("component_updated", manifest["revision"], component_key=args.component_key)
        )
        return manifest, True, {"result": "updated", "manifest": manifest}
    output(with_lock(args.manifest, args.bundle_key, mutate), args.json)


def cmd_remove_component(args):
    validate_bundle_key(args.bundle_key)
    if not args.reason:
        fail("missing_removal_reason", "--reason is required", 2)
    def mutate(current):
        if current is None:
            fail("manifest_not_found", "manifest file not found")
        check_expected_revision(current, args.expected_revision)
        if current.get("status") == "finalized":
            fail("bundle_finalized", "finalized bundles cannot be changed")
        manifest = copy.deepcopy(current)
        idx, existing = find_component(manifest.get("components", []), args.component_key)
        if existing is None:
            return manifest, False, {"result": "idempotent", "manifest": manifest}
        removed = manifest["components"].pop(idx)
        manifest["revision"] += 1
        removed["removed_revision"] = manifest["revision"]
        removed["reason"] = args.reason
        manifest.setdefault("removed_components", []).append(removed)
        invalidate_readiness(manifest)
        manifest.setdefault("audit_events", []).append(
            audit_event("component_removed", manifest["revision"], component_key=args.component_key, reason=args.reason)
        )
        return manifest, True, {"result": "updated", "manifest": manifest}
    output(with_lock(args.manifest, args.bundle_key, mutate), args.json)


def cmd_inspect(args):
    validate_bundle_key(args.bundle_key)
    manifest = validate_manifest(load_json_file(args.manifest, "manifest"), args.bundle_key)
    output(inspect_manifest(manifest), args.json)


def cmd_finalize(args):
    validate_bundle_key(args.bundle_key)
    def mutate(current):
        if current is None:
            fail("manifest_not_found", "manifest file not found")
        check_expected_revision(current, args.expected_revision)
        if current.get("status") == "finalized":
            return current, False, {"result": "idempotent", "manifest": current}
        readiness = current.get("readiness")
        if isinstance(readiness, dict) and readiness.get("revision") != current.get("revision"):
            fail("stale_readiness", "readiness was computed for an older manifest revision")
        view = inspect_manifest(current)
        blockers = view["readiness"]["blockers"]
        if blockers:
            fail(blockers[0]["blocker"], f"finalization blocked for {blockers[0]['component_key']}")
        manifest = copy.deepcopy(current)
        manifest["revision"] += 1
        manifest["status"] = "finalized"
        manifest["readiness"] = {
            "revision": manifest["revision"],
            "ready": True,
            "status": "finalized",
            "blockers": [],
        }
        manifest["finalization"] = {"revision": manifest["revision"], "finalized_at": now()}
        manifest.setdefault("audit_events", []).append(
            audit_event("bundle_finalized", manifest["revision"])
        )
        return manifest, True, {"result": "finalized", "manifest": manifest}
    output(with_lock(args.manifest, args.bundle_key, mutate), args.json)


def add_common(parser, expected=False):
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--bundle-key", required=True, dest="bundle_key")
    if expected:
        parser.add_argument("--expected-revision", required=True, type=int, dest="expected_revision")
    parser.add_argument("--json", action="store_true")


def main():
    parser = Parser(prog="delivery-bundle-manifest.sh")
    sub = parser.add_subparsers(dest="command", required=True, parser_class=Parser)

    create = sub.add_parser("create")
    add_common(create)
    create.add_argument("--title", required=True)
    create.add_argument("--purpose", required=True)
    create.add_argument("--parent-ref", required=True, dest="parent_ref")
    create.add_argument("--component", action="append", default=[])
    create.add_argument("--child-item", action="append", default=[], dest="child_item")
    create.add_argument("--finalization-owner", required=True, dest="finalization_owner")
    create.add_argument("--rollout-notes", default="", dest="rollout_notes")
    create.set_defaults(func=cmd_create)

    add_component = sub.add_parser("add-component")
    add_common(add_component, expected=True)
    add_component.add_argument("--component-key", required=True, dest="component_key")
    add_component.set_defaults(func=cmd_add_component)

    update = sub.add_parser("update-component")
    add_common(update, expected=True)
    update.add_argument("--component-key", required=True, dest="component_key")
    update.add_argument("--evidence-file", required=True, dest="evidence_file")
    update.add_argument("--component-tag", required=True, dest="component_tag")
    update.add_argument("--component-version", default=None, dest="component_version")
    update.add_argument("--source-pr", required=True, dest="source_pr")
    update.add_argument("--release-pr", required=True, dest="release_pr")
    update.add_argument("--child-item", required=True, dest="child_item")
    update.add_argument("--child-release-state", required=True, dest="child_release_state")
    update.add_argument(
        "--hub-tracker-reconciliation-outcome",
        default="pending",
        dest="hub_tracker_reconciliation_outcome",
    )
    update.set_defaults(func=cmd_update_component)

    remove = sub.add_parser("remove-component")
    add_common(remove, expected=True)
    remove.add_argument("--component-key", required=True, dest="component_key")
    remove.add_argument("--reason", required=True)
    remove.set_defaults(func=cmd_remove_component)

    inspect = sub.add_parser("inspect")
    add_common(inspect)
    inspect.set_defaults(func=cmd_inspect)

    finalize = sub.add_parser("finalize")
    add_common(finalize, expected=True)
    finalize.set_defaults(func=cmd_finalize)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
PY
