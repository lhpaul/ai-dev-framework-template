#!/usr/bin/env python3
"""Read project-owned path-risk rules and match normalized classifier evidence.

No classification, authority or remote writes live here. The shell classifier
owns built-in categories and independently enforces protected-path floors.
"""

from __future__ import annotations

import argparse
import importlib.util
import json
from pathlib import Path
import re
import sys
import subprocess
from typing import Any


class RiskPathError(ValueError):
    """A diagnostic that contains field locations, never configuration values."""


MISSING = object()
RANK = {"low": 1, "medium": 2, "high": 3}


def has_line_or_control(value: str) -> bool:
    return any(ord(c) < 32 or ord(c) == 127 or c in "\x85\u2028\u2029" for c in value)


def config_reader() -> Any:
    path = Path(__file__).with_name("workflow-config-resolver.py")
    spec = importlib.util.spec_from_file_location("workflow_risk_config", path)
    if spec is None or spec.loader is None:
        raise RiskPathError("workflow configuration reader is unavailable")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def map_node(data: dict[str, Any], location: str) -> Any:
    if "guardrails" not in data:
        return MISSING
    guardrails = data["guardrails"]
    if not isinstance(guardrails, dict):
        raise RiskPathError(f"{location}.guardrails must be a mapping")
    return guardrails.get("risk_paths", MISSING)


def select_map(reader: Any, shared: dict[str, Any], path: Path, root: Path,
               evidence: dict[str, Any], product: str) -> tuple[Any, str]:
    location = "guardrails.risk_paths"
    own_map = map_node(shared, "configuration")
    mode = reader.mode_from_shared(shared, path)
    if mode != "workflow_hub":
        return own_map, location
    hub = shared.get("workflow_hub", {})
    if not isinstance(hub, dict):
        raise RiskPathError("workflow_hub must be a mapping")
    raw_products = hub.get("product_repos", [])
    if not isinstance(raw_products, list) or any(not isinstance(p, dict) for p in raw_products):
        raise RiskPathError("workflow_hub.product_repos must be a list of mappings")
    product_maps = [map_node(p, f"workflow_hub.product_repos[{i}]")
                    for i, p in enumerate(raw_products)]
    if own_map is MISSING and all(node is MISSING for node in product_maps):
        # Preserve no-map consumers that classify remotely without a checkout
        # or target selector. No project policy can be confused in this case.
        return MISSING, location
    product_evidence = evidence.get("productRepo", {})
    if not isinstance(product_evidence, dict):
        raise RiskPathError("evidence.productRepo must be a mapping")
    selected = product or product_evidence.get("name", "") or evidence.get("productRepoName", "")
    slug = evidence.get("github_repo", "")
    if not isinstance(selected, str) or not isinstance(slug, str):
        raise RiskPathError("project identity must use strings")
    repos = reader.product_repos(shared, path)

    def repo_slug(repo: dict[str, Any]) -> str:
        return repo.get("github_repo") or reader.github_repo_from_url(str(repo.get("git_url", "")))

    if selected:
        candidates = [repo for repo in repos if repo["name"] == selected]
    elif slug:
        # Git resolves the common repository config for linked worktrees.
        try:
            remote = subprocess.run(
                ["git", "-C", str(root), "remote", "get-url", "origin"],
                check=True, capture_output=True, text=True, timeout=10,
            ).stdout.strip()
        except (OSError, subprocess.SubprocessError):
            remote = ""
        if slug == reader.github_repo_from_url(remote):
            return own_map, location
        candidates = [repo for repo in repos if repo_slug(repo) == slug]
    elif all(node is MISSING for node in product_maps):
        return own_map, location
    else:
        raise RiskPathError("project risk map requires an unambiguous project identity")
    if len(candidates) != 1:
        raise RiskPathError("project risk map target is unknown or ambiguous")
    selected_repo = candidates[0]
    if slug and repo_slug(selected_repo) != slug:
        raise RiskPathError("project risk map selector and evidence repository disagree")
    location = "workflow_hub.product_repos[].guardrails.risk_paths"
    return map_node(selected_repo, "selected product"), location


def relative_path(value: Any, location: str, *, pattern: bool = False) -> str:
    if not isinstance(value, str) or not value.strip():
        raise RiskPathError(f"{location} must be a nonblank relative path")
    if ("\\" in value or has_line_or_control(value)
            or any(segment in {"", ".", ".."} for segment in value.split("/"))):
        raise RiskPathError(f"{location} must use relative POSIX paths without dot or empty segments")
    if pattern and any(c in value for c in "[]{}"):
        raise RiskPathError(f"{location} supports literals, *, ** and ? only")
    return value


def compile_glob(value: str) -> re.Pattern[str]:
    parts = []
    index = 0
    while index < len(value):
        if value[index:index + 2] == "**":
            parts.append(".*")
            index += 2
        elif value[index] == "*":
            parts.append("[^/]*")
            index += 1
        elif value[index] == "?":
            parts.append("[^/]")
            index += 1
        else:
            parts.append(re.escape(value[index]))
            index += 1
    return re.compile("".join(parts))


def rules_from_node(node: Any, location: str) -> list[tuple[dict[str, str], re.Pattern[str]]]:
    if node is MISSING:
        return []
    if not isinstance(node, list):
        raise RiskPathError(f"{location} must be a list (use [] for an empty map)")
    rules = []
    for index, rule in enumerate(node):
        field = f"{location}[{index}]"
        if not isinstance(rule, dict) or set(rule) != {"glob", "risk", "reason"}:
            raise RiskPathError(f"{field} must contain exactly glob, risk and reason")
        for key in ("glob", "risk", "reason"):
            if not isinstance(rule[key], str) or not rule[key].strip() or has_line_or_control(rule[key]):
                raise RiskPathError(f"{field}.{key} must be a nonblank single-line string")
        if rule["risk"] not in RANK:
            raise RiskPathError(f"{field}.risk must be low, medium or high")
        glob = relative_path(rule["glob"], f"{field}.glob", pattern=True)
        rules.append((rule, compile_glob(glob)))
    return rules


def evaluate(root: Path, product: str, evidence: Any) -> dict[str, Any]:
    if not isinstance(evidence, dict):
        raise RiskPathError("classifier evidence must be a JSON object")
    reader = config_reader()
    path = root / ".ai-dev-workflow.yaml"
    try:
        shared = reader.parse_review_yaml(path) if path.exists() else {}
    except reader.ConfigError as exc:
        if "requires PyYAML" in str(exc):
            raise RiskPathError("PyYAML is required; install the workflow tooling dependencies") from exc
        # The underlying parser diagnostic can include a source snippet. Keep
        # its line locator, but never echo raw YAML or invalid scalar values.
        line = re.search(r":([0-9]+):", str(exc))
        locator = f":{line[1]}" if line else ""
        raise RiskPathError(f".ai-dev-workflow.yaml{locator}: invalid or unsupported YAML") from exc
    try:
        node, location = select_map(reader, shared, path, root, evidence, product)
    except reader.ConfigError as exc:
        raise RiskPathError("project workflow configuration or identity is invalid") from exc
    rules = rules_from_node(node, location)
    files = evidence.get("changed_files", [])
    if files is None:
        files = []  # Existing missing-file evidence compatibility.
    if not isinstance(files, list):
        raise RiskPathError("evidence.changed_files must be a list")
    matches = {}
    for index, path_value in enumerate(files):
        file = relative_path(path_value, f"evidence.changed_files[{index}]")
        matched = [rule for rule, regex in rules if regex.fullmatch(file)]
        if matched:
            matches[file] = {
                "risk": max((rule["risk"] for rule in matched), key=RANK.__getitem__),
                "reasons": [f"project risk path rule {rule['glob']}: {rule['reason']}: {file}"
                            for rule in matched],
            }
    return {"matches": matches}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", required=True)
    parser.add_argument("--product-repo", default="")
    args = parser.parse_args()
    try:
        evidence = json.load(sys.stdin)
        result = evaluate(Path(args.repo_root).resolve(), args.product_repo, evidence)
    except (RiskPathError, OSError, ValueError, TypeError, KeyError, RecursionError) as exc:
        if isinstance(exc, RiskPathError):
            print(f"ERROR: {exc}", file=sys.stderr)
        else:
            print("ERROR: unreadable project configuration or classifier evidence", file=sys.stderr)
        return 2
    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
