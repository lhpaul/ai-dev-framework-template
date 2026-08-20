#!/usr/bin/env bash
#
# Validate workflow-hub multi-repository release adoption fixtures.

set -euo pipefail

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR_CODE=missing_python3 message='python3 is required'" >&2
  exit 2
fi

python3 - "$@" <<'PY'
import argparse
import hashlib
import json
import os
import re
import sys
from typing import Any, NoReturn

SCHEMA = "multi_repo_release_assurance.v1"
VALID_OUTCOMES = {"pass", "fail", "blocked", "skipped", "retryable"}
CANONICAL_SCENARIOS = [
    "component_routing",
    "configuration_validation",
    "namespaced_component_milestones",
    "bundle_finalization",
    "partial_failures",
    "reruns",
    "migration_no_rewrite",
    "single_repo_compatibility",
]
REQUIRED_EVIDENCE = {
    "component_routing": ["selected_product_repo_key", "canonical_repository_identity", "release_contract"],
    "configuration_validation": ["hub_config", "product_config"],
    "namespaced_component_milestones": ["component_evidence", "milestone_reconciliation"],
    "bundle_finalization": ["delivery_bundle_manifest", "component_evidence"],
    "reruns": ["run_id", "step_id", "supersedes", "idempotency_guard"],
}

# A missing-evidence gate that only checks non-emptiness accepts arbitrary
# strings such as "garbage" as valid evidence for any field. These shape
# checks apply where this codebase already establishes an objective,
# unambiguous format or constant for the referenced artifact (a schema
# version string, a contract-revision digest prefix, a product repository
# key charset, a GitHub owner/repo slug, or the documented
# <product-repo>@<component-tag> milestone title format) -- catching
# evidence that could not possibly be the artifact it claims to be, without
# loading or re-verifying the referenced artifact itself (the assurance
# summary remains self-review evidence, not a replacement for the release
# helpers it checks).
_KEY_RE = re.compile(r"^[A-Za-z0-9._-]+$")
_OWNER_RE = re.compile(r"^[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?$")
_REPO_NAME_RE = re.compile(r"^[A-Za-z0-9._-]+$")


def _is_valid_repo_slug(value: str) -> bool:
    if value.count("/") != 1:
        return False
    owner, repo_name = value.split("/", 1)
    if repo_name in ("", ".", ".."):
        return False
    return bool(_OWNER_RE.match(owner)) and bool(_REPO_NAME_RE.match(repo_name))


def _is_valid_milestone_title(value: str) -> bool:
    if value.count("@") != 1:
        return False
    repo_key, tag = value.split("@", 1)
    return bool(_KEY_RE.match(repo_key)) and bool(_KEY_RE.match(tag))


EVIDENCE_SHAPE_VALIDATORS = {
    "selected_product_repo_key": lambda value: isinstance(value, str) and bool(_KEY_RE.match(value)),
    "canonical_repository_identity": lambda value: isinstance(value, str) and _is_valid_repo_slug(value),
    "release_contract": lambda value: isinstance(value, str) and value.startswith("sha256:") and len(value) > len("sha256:"),
    "component_evidence": lambda value: value == "component_release_evidence.v1",
    "delivery_bundle_manifest": lambda value: value == "delivery_bundle_manifest.v1",
    "milestone_reconciliation": lambda value: isinstance(value, str) and _is_valid_milestone_title(value),
}


class Parser(argparse.ArgumentParser):
    def error(self, message: str) -> NoReturn:
        fail("invalid_arguments", message, 2)


def fail(code: str, message: str, exit_code: int = 1) -> NoReturn:
    safe = str(message).replace("'", "'\\''")
    print(f"ERROR_CODE={code} message='{safe}'", file=sys.stderr)
    raise SystemExit(exit_code)


def load_json(path: str, label: str) -> dict[str, Any]:
    if not os.path.exists(path):
        fail(f"{label}_not_found", f"{label} file not found: {path}")
    try:
        with open(path, "r", encoding="utf-8") as handle:
            data = json.load(handle)
    except json.JSONDecodeError as exc:
        fail("invalid_json", f"{label} is not valid JSON: {exc}")
    if not isinstance(data, dict):
        fail("invalid_json", f"{label} must be a JSON object")
    return data


def file_digest(path: str) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(65536), b""):
            digest.update(chunk)
    return f"sha256:{digest.hexdigest()}"


def baseline_files(root: str) -> list[str]:
    files: list[str] = []
    if not os.path.isdir(root):
        fail("baseline_not_found", f"baseline directory not found: {root}")
    for current, _, names in os.walk(root):
        for name in sorted(names):
            path = os.path.join(current, name)
            if os.path.isfile(path):
                files.append(os.path.relpath(path, root))
    return sorted(files)


def compare_baseline(before: str, after: str, owner: str) -> dict[str, Any]:
    before_files = baseline_files(before)
    after_files = baseline_files(after)
    changed: list[str] = []
    if before_files != after_files:
        changed.extend(sorted(set(before_files).symmetric_difference(after_files)))
    for relpath in before_files:
        before_path = os.path.join(before, relpath)
        after_path = os.path.join(after, relpath)
        if os.path.exists(after_path) and file_digest(before_path) != file_digest(after_path):
            changed.append(relpath)
    return {
        "owner": owner,
        "unchanged": len(changed) == 0,
        "changed_files": sorted(set(changed)),
        "file_count": len(before_files),
    }


def normalize_scenario(raw: Any) -> dict[str, Any]:
    if not isinstance(raw, dict):
        fail("invalid_scenario", "scenario entries must be JSON objects")
    name = str(raw.get("name") or "")
    if not name:
        fail("invalid_scenario", "scenario name is required")
    outcome = str(raw.get("outcome") or "")
    if outcome not in VALID_OUTCOMES:
        fail("invalid_outcome", f"scenario {name} has invalid outcome: {outcome}")
    approved_skipped_raw = raw.get("approved_skipped", False)
    if not isinstance(approved_skipped_raw, bool):
        fail("invalid_scenario", f"scenario {name} approved_skipped must be a boolean")
    approved_skipped = approved_skipped_raw
    if outcome == "skipped" and not approved_skipped:
        raw = {**raw, "required_next_action": raw.get("required_next_action") or "record skipped rationale before validation"}
    if raw.get("stale_attempt") is True and outcome != "retryable":
        fail("invalid_scenario", f"scenario {name} marks stale_attempt outside retryable outcome")
    if raw.get("side_effect_repeated") is True:
        raw = {
            **raw,
            "outcome": "fail",
            "approved_skipped": False,
            "required_next_action": "fix idempotency or completion guard before adoption",
        }
        approved_skipped = False
    missing_evidence = []
    invalid_evidence = []
    if raw.get("required", True) is not False and raw.get("outcome") == "pass":
        for key in REQUIRED_EVIDENCE.get(name, []):
            value = raw.get(key)
            if value in (None, "", [], {}):
                missing_evidence.append(key)
                continue
            validator = EVIDENCE_SHAPE_VALIDATORS.get(key)
            if validator is not None and not validator(value):
                invalid_evidence.append(key)
        if missing_evidence or invalid_evidence:
            reasons = []
            if missing_evidence:
                reasons.append("provide required evidence before adoption: " + ", ".join(missing_evidence))
            if invalid_evidence:
                reasons.append("evidence does not match the expected artifact format: " + ", ".join(invalid_evidence))
            raw = {
                **raw,
                "outcome": "fail",
                "required_next_action": "; ".join(reasons),
            }
    return {
        "name": name,
        "owner": raw.get("owner") or "hub",
        "required": raw.get("required", True) is not False,
        "outcome": raw.get("outcome"),
        "approved_skipped": approved_skipped,
        "rationale": raw.get("rationale") or "",
        "required_next_action": raw.get("required_next_action") or "",
        "run_id": raw.get("run_id") or "",
        "step_id": raw.get("step_id") or "",
        "supersedes": raw.get("supersedes") or "",
        "idempotency_guard": raw.get("idempotency_guard") or "",
        "missing_evidence": missing_evidence,
        "invalid_evidence": invalid_evidence,
    }


def validate_scenario_set(raw_scenarios: Any) -> list[Any]:
    if not isinstance(raw_scenarios, list) or not raw_scenarios:
        fail("missing_scenarios", "assurance fixture must include scenarios")
    names: list[str] = []
    for item in raw_scenarios:
        if not isinstance(item, dict):
            fail("invalid_scenario", "scenario entries must be JSON objects")
        names.append(str(item.get("name") or ""))
    canonical = set(CANONICAL_SCENARIOS)
    unknown = sorted(name for name in names if name not in canonical)
    duplicate = sorted({name for name in names if names.count(name) > 1})
    missing = sorted(canonical.difference(names))
    if unknown or duplicate or missing:
        parts = []
        if unknown:
            parts.append("unknown: " + ", ".join(unknown))
        if duplicate:
            parts.append("duplicate: " + ", ".join(duplicate))
        if missing:
            parts.append("missing: " + ", ".join(missing))
        fail("invalid_scenario_set", "; ".join(parts))
    return raw_scenarios


def adoption_status(scenarios: list[dict[str, Any]], historical: list[dict[str, Any]]) -> str:
    if any(not item["unchanged"] for item in historical):
        return "blocked"
    for scenario in scenarios:
        if not scenario["required"]:
            continue
        outcome = scenario["outcome"]
        if outcome == "pass":
            continue
        if outcome == "skipped" and scenario["approved_skipped"] and scenario["rationale"].strip():
            continue
        return "blocked"
    return "validated"


def main(argv: list[str]) -> int:
    parser = Parser(prog="multi-repo-release-assurance.sh")
    parser.add_argument("--fixture-dir", required=True)
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args(argv)

    fixture_dir = os.path.abspath(args.fixture_dir)
    manifest = load_json(os.path.join(fixture_dir, "assurance.json"), "assurance")
    scenarios = [normalize_scenario(item) for item in validate_scenario_set(manifest.get("scenarios", []))]

    historical = [
        compare_baseline(os.path.join(fixture_dir, "historical", "hub-before"), os.path.join(fixture_dir, "historical", "hub-after"), "hub"),
        compare_baseline(
            os.path.join(fixture_dir, "historical", "product-before"),
            os.path.join(fixture_dir, "historical", "product-after"),
            "product",
        ),
    ]
    status = adoption_status(scenarios, historical)
    owner_actions = [
        {
            "owner": scenario["owner"],
            "scenario": scenario["name"],
            "required_next_action": scenario["required_next_action"],
        }
        for scenario in scenarios
        if scenario["required_next_action"]
    ]
    for baseline in historical:
        if not baseline["unchanged"]:
            owner_actions.append(
                {
                    "owner": baseline["owner"],
                    "scenario": "migration_no_rewrite",
                    "required_next_action": "restore historical baseline before adoption",
                }
            )

    result = {
        "schema_version": SCHEMA,
        "adoption_status": status,
        "scenario_results": scenarios,
        "historical_no_rewrite": historical,
        "owner_actions": owner_actions,
        "required_next_action": "record adoption evidence" if status == "validated" else "resolve blocked assurance scenarios before adoption",
    }

    if args.json:
        print(json.dumps(result, indent=2, sort_keys=True))
    else:
        print(f"SCHEMA_VERSION={SCHEMA}")
        print(f"ADOPTION_STATUS={status}")
        print(f"SCENARIO_COUNT={len(scenarios)}")
        print(f"HISTORICAL_NO_REWRITE={all(item['unchanged'] for item in historical)}")
        print(f"REQUIRED_NEXT_ACTION={result['required_next_action']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
PY
