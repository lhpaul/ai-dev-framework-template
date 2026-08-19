#!/usr/bin/env bash
#
# Reconcile workflow-hub component milestones and parent release status.

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
import subprocess
import sys
import tempfile
from typing import Any, NoReturn

SCHEMA = "component_milestone_reconciliation.v1"
EVIDENCE_SCHEMA = "component_release_evidence.v1"
BUNDLE_SCHEMA = "delivery_bundle_manifest.v1"
VALID_TARGET_KINDS = {"component_child", "parent_epic", "delivery_bundle"}
VALID_MODES = {"workflow_hub", "single_repo"}
KEY_RE = re.compile(r"^[A-Za-z0-9._-]+$")
TAG_RE = re.compile(r"^[A-Za-z0-9._-]+$")
VERSION_RE = re.compile(r"^v\d+\.\d+\.\d+(?:[-+][A-Za-z0-9._-]+)?$")


class Parser(argparse.ArgumentParser):
    def error(self, message: str) -> NoReturn:
        fail("invalid_arguments", message, 2)


class GhCommandError(RuntimeError):
    pass


def fail(code: str, message: str, exit_code: int = 1, payload: dict[str, Any] | None = None) -> NoReturn:
    if payload is not None:
        print(json.dumps(payload, indent=2, sort_keys=True))
    safe = str(message).replace("'", "'\\''")
    print(f"ERROR_CODE={code} message='{safe}'", file=sys.stderr)
    raise SystemExit(exit_code)


def now() -> str:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def load_json_file(path: str | None, label: str, required: bool = True) -> dict[str, Any] | None:
    if not path:
        if required:
            fail("invalid_arguments", f"{label} path is required", 2)
        return None
    if not os.path.exists(path):
        if required:
            fail(f"{label}_not_found", f"{label} file not found: {path}")
        return None
    try:
        with open(path, "r", encoding="utf-8") as handle:
            data = json.load(handle)
    except json.JSONDecodeError as exc:
        fail("invalid_json", f"{label} file is not valid JSON: {exc}")
    if not isinstance(data, dict):
        fail("invalid_json", f"{label} file must contain a JSON object")
    return data


def output(data: dict[str, Any], json_output: bool) -> None:
    if json_output:
        print(json.dumps(data, indent=2, sort_keys=True))
        return
    for key, value in data.items():
        if isinstance(value, (dict, list)):
            value = json.dumps(value, sort_keys=True)
        print(f"{key.upper()}={value}")


def validate_issue(value: int | None, label: str = "issue") -> int:
    if value is None or value <= 0:
        fail("invalid_arguments", f"--{label} must be a positive integer", 2)
    return value


def validate_target_kind(target_kind: str) -> None:
    if target_kind not in VALID_TARGET_KINDS:
        fail("invalid_target_kind", f"--target-kind must be one of {', '.join(sorted(VALID_TARGET_KINDS))}", 2)


def validate_mode(mode: str) -> None:
    if mode not in VALID_MODES:
        fail("invalid_mode", f"--mode must be one of {', '.join(sorted(VALID_MODES))}", 2)


def validate_product_repo(product_repo: str | None) -> str | None:
    if not product_repo:
        return None
    if not KEY_RE.match(product_repo):
        return None
    return product_repo


def validate_component_tag(component_tag: str | None) -> str | None:
    if not component_tag:
        return None
    if not TAG_RE.match(component_tag):
        return None
    return component_tag


def stable_value(evidence: dict[str, Any], field: str) -> Any:
    if field in evidence:
        return evidence[field]
    binding = evidence.get("target_binding")
    if isinstance(binding, dict):
        return binding.get(field)
    return None


def base_component_result(args: argparse.Namespace) -> dict[str, Any]:
    return {
        "schema_version": SCHEMA,
        "mode": args.mode,
        "target_issue": args.issue,
        "target_kind": args.target_kind,
        "selected_product_repo_key": args.product_repo,
        "component_tag": args.component_tag,
        "reconciliation_outcome": "component_release_not_ready",
        "child_release_state": "pending",
        "parent_release_state": "not_released",
        "milestone_title": None,
        "requires_delivery_bundle": args.mode != "single_repo",
        "mutation_allowed": False,
        "required_next_action": "complete component release evidence before milestone reconciliation",
        "blockers": [],
        "milestone_assignment": {
            "target_issue": args.issue,
            "action": "none",
            "parent_epic_stamped": False,
            "delivery_bundle_stamped": False,
        },
    }


def non_hub_result(args: argparse.Namespace) -> dict[str, Any]:
    result = base_component_result(args)
    if not args.version:
        result.update(
            reconciliation_outcome="component_release_not_ready",
            required_next_action="provide --version for non-hub release milestone stamping",
            blockers=["missing_version"],
        )
        return result
    if not VERSION_RE.match(args.version):
        result.update(
            reconciliation_outcome="component_release_not_ready",
            required_next_action="provide a semantic release tag like v1.2.3 before milestone stamping",
            blockers=["invalid_version"],
        )
        return result
    result.update(
        reconciliation_outcome="single_repo_milestone",
        child_release_state="released",
        parent_release_state="not_applicable",
        milestone_title=args.version,
        requires_delivery_bundle=False,
        mutation_allowed=args.target_kind == "component_child",
        required_next_action="stamp the existing single-repository release milestone",
        blockers=[],
    )
    return result


def evidence_state(evidence: dict[str, Any]) -> str:
    raw = evidence.get("evidence_state")
    if isinstance(raw, str) and raw:
        return raw
    return ""


def classify_component(args: argparse.Namespace) -> dict[str, Any]:
    validate_mode(args.mode)
    validate_issue(args.issue)
    validate_target_kind(args.target_kind)

    if args.mode == "single_repo":
        return non_hub_result(args)

    result = base_component_result(args)
    product_repo = validate_product_repo(args.product_repo)
    component_tag = validate_component_tag(args.component_tag)

    if args.target_kind != "component_child":
        result.update(
            reconciliation_outcome="milestone_target_not_allowed",
            required_next_action="component milestones may only be applied to component child issues",
            blockers=["milestone_target_not_allowed"],
        )
        return result
    if args.product_repo and not product_repo:
        result.update(
            reconciliation_outcome="component_release_not_ready",
            required_next_action="provide a product repository key using letters, numbers, dot, underscore, or hyphen",
            blockers=["invalid_product_repository"],
        )
        return result
    if not product_repo:
        result.update(
            reconciliation_outcome="missing_product_selection",
            required_next_action="select exactly one product repository before component milestone reconciliation",
            blockers=["missing_product_selection"],
        )
        return result
    if args.component_tag and not component_tag:
        result.update(
            reconciliation_outcome="component_release_not_ready",
            required_next_action="provide a component tag using letters, numbers, dot, underscore, or hyphen",
            blockers=["invalid_component_tag"],
        )
        return result
    if not component_tag:
        result.update(
            reconciliation_outcome="component_tag_missing",
            required_next_action="provide the released component tag before milestone reconciliation",
            blockers=["component_tag_missing"],
        )
        return result
    result["milestone_title"] = f"{product_repo}@{component_tag}"

    evidence = load_json_file(args.evidence_file, "evidence", required=False)
    if evidence is None:
        result.update(
            reconciliation_outcome="component_release_pending",
            child_release_state="pending",
            required_next_action="attach component_release_evidence.v1 before milestone reconciliation",
            blockers=["component_release_evidence_missing"],
        )
        return result
    if evidence.get("schema_version") != EVIDENCE_SCHEMA:
        result.update(
            reconciliation_outcome="component_release_not_ready",
            child_release_state="blocked",
            required_next_action=f"provide evidence with schema_version {EVIDENCE_SCHEMA}",
            blockers=["invalid_evidence_schema"],
        )
        return result

    evidence_product = stable_value(evidence, "selected_product_repo_key")
    if evidence_product != product_repo:
        result.update(
            reconciliation_outcome="component_target_mismatch",
            child_release_state="blocked",
            required_next_action="correct the selected child or component release evidence before mutation",
            blockers=["product_repository_mismatch"],
        )
        return result

    evidence_tag = evidence.get("component_tag")
    if evidence_tag not in (None, "", component_tag):
        result.update(
            reconciliation_outcome="component_target_mismatch",
            child_release_state="blocked",
            required_next_action="correct the component tag or evidence before mutation",
            blockers=["component_tag_mismatch"],
        )
        return result

    required_identity = (
        "canonical_repository_identity",
        "release_correlation_key",
        "contract_revision",
        "hub_tracker_ref",
    )
    missing = [field for field in required_identity if not stable_value(evidence, field)]
    if missing:
        result.update(
            reconciliation_outcome="component_release_not_ready",
            child_release_state="blocked",
            required_next_action="repair incomplete component release evidence before mutation",
            blockers=[f"missing_{field}" for field in missing],
        )
        return result

    release = evidence.get("release_outcome")
    ci = evidence.get("ci_outcome")
    deployment = evidence.get("deployment_outcome")
    cleanup = evidence.get("cleanup_outcome")
    hub_reconciliation = evidence.get("hub_tracker_reconciliation_outcome") or evidence.get("hub_tracker_reconciliation")
    child_state = evidence.get("child_release_state")
    state = evidence_state(evidence)

    blockers: list[str] = []
    if not state:
        blockers.append("evidence_state_missing")
    if state in {"stale", "conflicting"}:
        blockers.append(f"{state}_component_evidence")
    if release != "completed":
        blockers.append(f"release_outcome_{release or 'missing'}")
    if ci not in {"passed", "skipped", "not_applicable"}:
        blockers.append(f"ci_outcome_{ci or 'missing'}")
    if deployment not in {"recorded", "not_applicable"}:
        blockers.append(f"deployment_outcome_{deployment or 'missing'}")
    if cleanup != "complete":
        blockers.append(f"cleanup_outcome_{cleanup or 'missing'}")
    if hub_reconciliation not in {"complete", "deferred"}:
        blockers.append(f"hub_tracker_reconciliation_{hub_reconciliation or 'missing'}")
    if not child_state:
        blockers.append("child_release_state_missing")
    elif child_state not in {"released", "merged"}:
        blockers.append(f"child_release_state_{child_state or 'missing'}")

    if blockers:
        if release == "failed" or child_state == "failed":
            child_release_state = "failed"
        elif release == "blocked" or state in {"stale", "conflicting"}:
            child_release_state = "blocked"
        else:
            child_release_state = "pending"
        result.update(
            reconciliation_outcome="component_release_not_ready",
            child_release_state=child_release_state,
            required_next_action="repair or retry component release evidence before milestone mutation",
            blockers=blockers,
        )
        return result

    result.update(
        reconciliation_outcome="component_released",
        child_release_state="released",
        parent_release_state="not_released",
        mutation_allowed=True,
        required_next_action="create or reuse the namespaced component milestone and assign it only to the component child",
        blockers=[],
    )
    return result


def repo_slug() -> str:
    env_slug = os.environ.get("GITHUB_REPOSITORY")
    if env_slug and "/" in env_slug:
        return env_slug
    try:
        remote = subprocess.check_output(["git", "config", "--get", "remote.origin.url"], text=True).strip()
    except FileNotFoundError:
        fail("missing_git", "git is required to resolve the GitHub repository", 2)
    except subprocess.CalledProcessError:
        fail("repo_unresolvable", "could not resolve GitHub repository from git remote")
    if remote.endswith(".git"):
        remote = remote[:-4]
    if remote.startswith("git@github.com:"):
        return remote.split(":", 1)[1]
    if "github.com/" in remote:
        return remote.split("github.com/", 1)[1]
    fail("repo_unresolvable", "could not resolve GitHub repository from git remote")


def run_gh(args: list[str], label: str, fail_on_error: bool = True) -> Any:
    try:
        completed = subprocess.run(["gh", *args], text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)
    except FileNotFoundError:
        fail("missing_gh", "gh is required for apply mode", 2)
    except subprocess.CalledProcessError as exc:
        message = exc.stderr.strip() or exc.stdout.strip() or f"gh {label} failed"
        if not fail_on_error:
            raise GhCommandError(message) from exc
        fail(f"gh_{label}_failed", message)
    if completed.stdout.strip() == "":
        return None
    try:
        return json.loads(completed.stdout)
    except json.JSONDecodeError:
        return completed.stdout.strip()


def flatten_pages(value: Any) -> list[dict[str, Any]]:
    if isinstance(value, dict):
        return [value]
    if not isinstance(value, list):
        return []
    if all(isinstance(item, dict) for item in value):
        return [item for item in value if isinstance(item, dict)]
    items: list[dict[str, Any]] = []
    for page in value:
        if isinstance(page, list):
            items.extend(item for item in page if isinstance(item, dict))
    return items


def milestone_number_from_pages(pages: Any, title: str) -> int | None:
    for milestone in flatten_pages(pages):
        if milestone.get("title") == title and milestone.get("number") is not None:
            return int(milestone["number"])
    return None


def list_milestones(repo: str) -> Any:
    return run_gh(["api", "--paginate", "--slurp", f"repos/{repo}/milestones?state=all&per_page=100"], "milestone_list")


def ensure_milestone(title: str) -> int:
    repo = repo_slug()
    existing = milestone_number_from_pages(list_milestones(repo), title)
    if existing is not None:
        return existing
    create_error = None
    try:
        created = run_gh(
            ["api", "-X", "POST", f"repos/{repo}/milestones", "-f", f"title={title}", "-f", f"description=Release {title}"],
            "milestone_create",
            fail_on_error=False,
        )
        if not isinstance(created, dict) or created.get("number") is None:
            create_error = f"GitHub milestone create response did not include a number for {title}"
        else:
            return int(created["number"])
    except GhCommandError as exc:
        create_error = str(exc)
    except (TypeError, ValueError) as exc:
        create_error = str(exc)

    raced = milestone_number_from_pages(list_milestones(repo), title)
    if raced is not None:
        return raced
    fail("milestone_create_failed", create_error or f"failed to create milestone {title}")


def issue_milestone_number(issue: int) -> int | None:
    repo = repo_slug()
    data = run_gh(["api", f"repos/{repo}/issues/{issue}"], "issue_read")
    if not isinstance(data, dict):
        return None
    milestone = data.get("milestone")
    if isinstance(milestone, dict) and milestone.get("number") is not None:
        return int(milestone["number"])
    return None


def assign_milestone(issue: int, milestone_number: int) -> str:
    existing_milestone = issue_milestone_number(issue)
    if existing_milestone == milestone_number:
        return "reused"
    if existing_milestone is not None:
        fail(
            "milestone_conflict",
            f"issue {issue} already has milestone {existing_milestone}; refusing to replace with {milestone_number}",
        )
    repo = repo_slug()
    run_gh(["api", "-X", "PATCH", f"repos/{repo}/issues/{issue}", "-F", f"milestone={milestone_number}"], "milestone_assign")
    return "assigned"


def cmd_inspect_component(args: argparse.Namespace) -> None:
    output(classify_component(args), args.json)


def cmd_apply_component(args: argparse.Namespace) -> None:
    result = classify_component(args)
    if result.get("mutation_allowed") is not True:
        fail(str(result["blockers"][0] if result["blockers"] else "mutation_not_allowed"), result["required_next_action"], 1, result)
    title = str(result["milestone_title"])
    milestone_number = ensure_milestone(title)
    action = assign_milestone(int(args.issue), milestone_number)
    result["milestone_assignment"].update(
        action=action,
        milestone_number=milestone_number,
        target_issue=int(args.issue),
        parent_epic_stamped=False,
        delivery_bundle_stamped=False,
    )
    if action == "reused":
        result["idempotent"] = True
    output(result, args.json)


def component_is_released(component: dict[str, Any]) -> bool:
    return (
        component.get("evidence_state") in {"verified", "released"}
        and component.get("release_outcome") == "completed"
        and component.get("ci_outcome") in {"passed", "skipped", "not_applicable"}
        and component.get("deployment_outcome") in {"recorded", "not_applicable"}
        and component.get("cleanup_outcome") == "complete"
        and component.get("hub_tracker_reconciliation_outcome") in {"complete", "deferred"}
        and component.get("child_release_state") in {"released", "merged"}
    )


def component_blocker(component: dict[str, Any]) -> str | None:
    blockers = component.get("blockers")
    if isinstance(blockers, list) and blockers:
        return str(blockers[0])
    if component.get("evidence_state") in {"stale", "conflicting"}:
        return f"{component.get('evidence_state')}_component_evidence"
    if component.get("release_outcome") in {"failed", "blocked"}:
        return "blocked_component_outcome"
    if component.get("ci_outcome") in {"failed", "blocked"}:
        return "blocked_component_outcome"
    if component.get("deployment_outcome") in {"failed", "blocked"}:
        return "blocked_component_outcome"
    if component.get("cleanup_outcome") in {"failed", "blocked"}:
        return "blocked_component_outcome"
    if component.get("child_release_state") in {"failed", "blocked"}:
        return "blocked_component_outcome"
    return None


def load_delivery_manifest(path: str) -> dict[str, Any]:
    manifest = load_json_file(path, "delivery_manifest")
    if manifest is None:
        fail("delivery_manifest_not_found", "delivery manifest file not found")
    if manifest.get("schema_version") != BUNDLE_SCHEMA:
        fail("invalid_manifest_schema", f"delivery manifest must use schema_version {BUNDLE_SCHEMA}")
    return manifest


def inspect_parent_state_from_manifest(args: argparse.Namespace, manifest: dict[str, Any]) -> dict[str, Any]:
    parent_issue = validate_issue(args.parent_issue, "parent-issue")
    components = [c for c in manifest.get("components", []) if isinstance(c, dict)]
    blockers: list[dict[str, Any]] = []
    released = 0
    unreleased = 0
    for component in components:
        blocker = component_blocker(component)
        if blocker:
            blockers.append({"component_key": component.get("component_key"), "blocker": blocker})
        if component_is_released(component):
            released += 1
        else:
            unreleased += 1
    finalized = manifest.get("status") == "finalized"
    readiness = manifest.get("readiness")
    if isinstance(readiness, dict) and isinstance(readiness.get("blockers"), list):
        for blocker in readiness["blockers"]:
            if isinstance(blocker, dict):
                blockers.append(blocker)
    if args.require_finalized and not finalized:
        blockers.append({"component_key": None, "blocker": "bundle_not_finalized"})

    if blockers:
        outcome = "parent_blocked"
        state = "blocked"
        mutation_allowed = False
        next_action = "correct delivery bundle evidence before parent release status mutation"
    elif finalized and released > 0 and unreleased == 0:
        outcome = "parent_released"
        state = "released"
        mutation_allowed = True
        next_action = "record parent release status in the delivery bundle manifest"
    elif finalized and unreleased > 0:
        outcome = "parent_blocked"
        state = "blocked"
        mutation_allowed = False
        next_action = "finish or remove unreleased component children before final bundle release"
        blockers.append({"component_key": None, "blocker": "finalized_bundle_has_unreleased_components"})
    elif released > 0 and unreleased > 0:
        outcome = "parent_partially_released"
        state = "partially_released"
        mutation_allowed = False
        next_action = "continue reconciling unreleased component children before final bundle release"
    else:
        outcome = "parent_not_released"
        state = "not_released"
        mutation_allowed = False
        next_action = "complete component release evidence before parent release"
    return {
        "schema_version": SCHEMA,
        "delivery_manifest_schema_version": manifest.get("schema_version"),
        "parent_issue": parent_issue,
        "reconciliation_outcome": outcome,
        "parent_release_state": state,
        "released_component_count": released,
        "unreleased_component_count": unreleased,
        "mutation_allowed": mutation_allowed,
        "required_next_action": next_action,
        "blockers": blockers,
        "milestone_assignment": {
            "parent_epic_stamped": False,
            "delivery_bundle_stamped": False,
            "action": "none",
        },
    }


def inspect_parent_state(args: argparse.Namespace) -> dict[str, Any]:
    return inspect_parent_state_from_manifest(args, load_delivery_manifest(args.delivery_manifest))


def cmd_inspect_parent(args: argparse.Namespace) -> None:
    output(inspect_parent_state(args), args.json)


def atomic_json_write(path: str, data: dict[str, Any]) -> None:
    parent = os.path.dirname(os.path.abspath(path)) or "."
    base = os.path.basename(path)
    fd = None
    tmp_path = None
    try:
        os.makedirs(parent, exist_ok=True)
        fd, tmp_path = tempfile.mkstemp(prefix=f".{base}.", suffix=".tmp", dir=parent)
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            fd = None
            json.dump(data, handle, indent=2, sort_keys=True)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        load_json_file(tmp_path, "staged_json")
        os.replace(tmp_path, path)
        dir_flags = getattr(os, "O_DIRECTORY", 0)
        try:
            dir_fd = os.open(parent, dir_flags)
            try:
                os.fsync(dir_fd)
            finally:
                os.close(dir_fd)
        except OSError:
            pass
    except OSError as exc:
        fail("status_write_failed", f"failed to write JSON atomically: {exc}")
    finally:
        if fd is not None:
            os.close(fd)
        if tmp_path and os.path.exists(tmp_path):
            os.unlink(tmp_path)


def cmd_apply_parent(args: argparse.Namespace) -> None:
    manifest = load_delivery_manifest(args.delivery_manifest)
    result = inspect_parent_state_from_manifest(args, manifest)
    if result.get("mutation_allowed") is not True:
        fail(str(result["blockers"][0]["blocker"] if result["blockers"] else "parent_not_released"), result["required_next_action"], 1, result)
    release_status = {
        "parent_issue": int(args.parent_issue),
        "state": "released",
        "reconciliation_outcome": "parent_released",
        "updated_at": now(),
    }
    current_status = manifest.get("release_status")
    if isinstance(current_status, dict) and current_status.get("parent_issue") == int(args.parent_issue) and current_status.get("state") == "released":
        result["idempotent"] = True
        release_status = copy.deepcopy(current_status)
        release_status_action = "unchanged"
    else:
        new_manifest = copy.deepcopy(manifest)
        release_status_action = "updated"
        new_manifest["release_status"] = release_status
        new_manifest.setdefault("audit_events", []).append(
            {
                "event": "parent_release_status_updated",
                "revision": new_manifest.get("revision"),
                "created_at": now(),
                "parent_issue": int(args.parent_issue),
                "state": "released",
            }
        )
        if args.status_output:
            atomic_json_write(
                args.status_output,
                {"release_status": release_status, "release_status_action": release_status_action},
            )
        atomic_json_write(args.delivery_manifest, new_manifest)
    if args.status_output and release_status_action == "unchanged":
        atomic_json_write(
            args.status_output,
            {"release_status": release_status, "release_status_action": release_status_action},
        )
    result["release_status"] = release_status
    result["release_status_action"] = release_status_action
    output(result, args.json)


def add_component_common(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--mode", default="workflow_hub")
    parser.add_argument("--issue", required=True, type=int)
    parser.add_argument("--target-kind", required=True, dest="target_kind")
    parser.add_argument("--product-repo", dest="product_repo")
    parser.add_argument("--component-tag", dest="component_tag")
    parser.add_argument("--evidence-file", dest="evidence_file")
    parser.add_argument("--version")
    parser.add_argument("--json", action="store_true")


def add_parent_common(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--parent-issue", required=True, type=int, dest="parent_issue")
    parser.add_argument("--delivery-manifest", required=True, dest="delivery_manifest")
    parser.add_argument("--require-finalized", action="store_true", dest="require_finalized")
    parser.add_argument("--json", action="store_true")


def main(argv: list[str]) -> int:
    parser = Parser(prog="component-milestone-reconciliation.sh")
    sub = parser.add_subparsers(dest="command", required=True, parser_class=Parser)

    inspect_component = sub.add_parser("inspect-component")
    add_component_common(inspect_component)
    inspect_component.set_defaults(func=cmd_inspect_component)

    apply_component = sub.add_parser("apply-component")
    add_component_common(apply_component)
    apply_component.set_defaults(func=cmd_apply_component)

    inspect_parent = sub.add_parser("inspect-parent")
    add_parent_common(inspect_parent)
    inspect_parent.set_defaults(func=cmd_inspect_parent)

    apply_parent = sub.add_parser("apply-parent")
    add_parent_common(apply_parent)
    apply_parent.add_argument("--status-output", dest="status_output")
    apply_parent.set_defaults(func=cmd_apply_parent)

    args = parser.parse_args(argv)
    args.func(args)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
PY
