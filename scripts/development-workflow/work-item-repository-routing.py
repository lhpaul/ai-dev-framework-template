#!/usr/bin/env python3
"""Classify work-item repository routing before implementation mutation."""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
from pathlib import Path
from typing import Any


OUTCOME_LABELS = {
    "product_owned": "Product owned",
    "hub_only": "Hub only",
    "missing_target": "Missing target",
    "ambiguous_target": "Ambiguous target",
    "multiple_targets": "Multiple targets",
    "single_repo": "Single-repository",
}


def load_json(path: str | None, label: str) -> dict[str, Any]:
    if not path:
        return {}
    try:
        with Path(path).open(encoding="utf-8") as handle:
            value = json.load(handle)
    except OSError as exc:
        raise ValueError(f"{label} could not be read: {exc}") from exc
    except json.JSONDecodeError as exc:
        raise ValueError(f"{label} is not valid JSON: {exc}") from exc
    if not isinstance(value, dict):
        raise ValueError(f"{label} must be a JSON object")
    return value


def configured_keys_from_config(config: dict[str, Any]) -> list[str]:
    if isinstance(config.get("configured_product_repo_keys"), list):
        return sorted(str(value) for value in config["configured_product_repo_keys"])
    repos = config.get("product_repos")
    if repos is None:
        repos = config.get("workflow_hub", {}).get("product_repos") if isinstance(config.get("workflow_hub"), dict) else None
    if repos is None:
        return []
    if not isinstance(repos, list):
        raise ValueError("product_repos must be an array")
    keys: list[str] = []
    for index, repo in enumerate(repos, start=1):
        if not isinstance(repo, dict) or not isinstance(repo.get("name"), str) or not repo["name"]:
            raise ValueError(f"product_repos[{index}].name is required")
        keys.append(repo["name"])
    return sorted(keys)


def configured_keys_from_repo_root(repo_root: str | None) -> tuple[str, list[str]]:
    if not repo_root:
        return "single_repo", []
    root = Path(repo_root)
    resolver = Path(__file__).with_name("workflow-config-resolver.py")
    try:
        mode = subprocess.run(
            [sys.executable, str(resolver), "mode", "--repo-root", str(root), "--json"],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=True,
        )
    except subprocess.CalledProcessError as exc:
        raise ValueError(exc.stderr.strip() or "failed to resolve repository mode") from exc
    mode_json = json.loads(mode.stdout)
    workflow_mode = str(mode_json.get("WORKFLOW_MODE") or mode_json.get("workflow_mode") or "single_repo")
    if workflow_mode != "workflow_hub":
        return workflow_mode, []
    try:
        repos = subprocess.run(
            [sys.executable, str(resolver), "list-product-repos", "--repo-root", str(root), "--json"],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=True,
        )
    except subprocess.CalledProcessError as exc:
        raise ValueError(exc.stderr.strip() or "failed to list product repositories") from exc
    keys = json.loads(repos.stdout)
    if not isinstance(keys, list):
        raise ValueError("list-product-repos returned non-array JSON")
    return workflow_mode, sorted(str(key) for key in keys)


def as_bool(value: Any) -> bool:
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        return value.lower() in {"1", "true", "yes", "on"}
    return bool(value)


def selected_keys(args: argparse.Namespace, fixture: dict[str, Any]) -> list[str]:
    values: list[str] = []
    raw = fixture.get("selected_product_repo_keys")
    if isinstance(raw, list):
        values.extend(str(value) for value in raw if str(value))
    elif isinstance(raw, str) and raw:
        values.append(raw)
    raw_single = fixture.get("selected_product_repo_key")
    if isinstance(raw_single, str) and raw_single:
        values.append(raw_single)
    values.extend(args.selected_product_repo_key or [])
    return sorted(dict.fromkeys(values))


def classify(
    repository_mode: str,
    stage: str,
    item_identifier: str,
    configured_keys: list[str],
    selected: list[str],
    hub_only: bool,
) -> dict[str, Any]:
    configured_set = set(configured_keys)
    outcome = "single_repo"
    artifact_owner = "current_repository"
    stop_reason: str | None = None
    required_human_action: str | None = None
    selected_key: str | None = None

    if repository_mode == "workflow_hub":
        if hub_only and selected:
            outcome = "ambiguous_target"
            artifact_owner = "none"
            stop_reason = "hub-only work cannot also select a product repository"
            required_human_action = "remove the product repository key or reclassify the item as product-owned"
        elif hub_only:
            outcome = "hub_only"
            artifact_owner = "hub_repository"
        elif len(selected) == 0:
            outcome = "missing_target"
            artifact_owner = "none"
            stop_reason = "product-owned work has no selected product repository key"
            required_human_action = "select exactly one configured product repository key"
        elif len(selected) > 1:
            outcome = "multiple_targets"
            artifact_owner = "none"
            stop_reason = "product-owned work selected multiple product repository keys"
            required_human_action = "split the request or narrow it to one product repository"
        elif selected[0] not in configured_set:
            outcome = "ambiguous_target"
            artifact_owner = "none"
            stop_reason = f"selected product repository key '{selected[0]}' is not configured"
            required_human_action = "select one configured product repository key"
        else:
            outcome = "product_owned"
            artifact_owner = "selected_product_repository"
            selected_key = selected[0]

    continue_allowed = outcome in {"single_repo", "hub_only", "product_owned"}
    schema_version = "work_item_repository_routing.v1"
    fingerprint_input = {
        "schema_version": schema_version,
        "item_identifier": item_identifier,
        "repository_mode": repository_mode,
        "stage": stage,
        "configured_product_repo_keys": sorted(configured_keys),
        "selected_product_repo_keys": sorted(selected),
        "hub_only": hub_only,
    }
    canonical = json.dumps(fingerprint_input, sort_keys=True, separators=(",", ":"))
    fingerprint = "sha256:" + hashlib.sha256(
        ("routing-fingerprint.v1\n" + canonical).encode("utf-8")
    ).hexdigest()
    return {
        "outcome_code": outcome,
        "display_label": OUTCOME_LABELS[outcome],
        "continue_allowed": continue_allowed,
        "selected_product_repo_key": selected_key,
        "artifact_owner": artifact_owner,
        "stop_reason": stop_reason,
        "required_human_action": required_human_action,
        "configured_product_repo_keys": sorted(configured_keys),
        "selected_product_repo_keys": sorted(selected),
        "fingerprint": fingerprint,
        "schema_version": schema_version,
    }


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Classify work-item repository routing")
    parser.add_argument("--config", help="JSON configuration fixture")
    parser.add_argument("--repo-root", help="repository root for production config resolution")
    parser.add_argument("--fixture", help="JSON item fixture")
    parser.add_argument("--repository-mode", choices=["single_repo", "workflow_hub", "product_repo"])
    parser.add_argument("--stage", default="implementation")
    parser.add_argument("--item-identifier", default="")
    parser.add_argument("--selected-product-repo-key", action="append")
    parser.add_argument("--hub-only", action="store_true")
    parser.add_argument("--json", action="store_true")
    return parser


def main(argv: list[str]) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        fixture = load_json(args.fixture, "fixture")
        config = load_json(args.config, "config")
        repo_mode, repo_keys = configured_keys_from_repo_root(args.repo_root)
        if config:
            repo_keys = configured_keys_from_config(config)
            repo_mode = str(config.get("repository_mode") or config.get("mode") or "workflow_hub")
        repository_mode = str(args.repository_mode or fixture.get("repository_mode") or repo_mode)
        stage = str(args.stage or fixture.get("stage") or "implementation")
        item_identifier = str(args.item_identifier or fixture.get("item_identifier") or "")
        hub_only = args.hub_only or as_bool(fixture.get("hub_only"))
        result = classify(
            repository_mode,
            stage,
            item_identifier,
            sorted(repo_keys),
            selected_keys(args, fixture),
            hub_only,
        )
    except ValueError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2

    if args.json:
        print(json.dumps(result, indent=2))
    else:
        for key, value in result.items():
            if isinstance(value, list):
                value = ",".join(value)
            elif value is None:
                value = ""
            print(f"{key.upper()}={value}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
