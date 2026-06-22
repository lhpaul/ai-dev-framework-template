#!/usr/bin/env python3
"""Resolve shared and local workflow repository context.

This script intentionally uses only the Python standard library. It supports the
small YAML subset used by `.ai-dev-workflow.yaml` and
`.ai-dev-workflow.local.yaml`: nested mappings, lists, and scalar values.
Unsupported or malformed structures fail closed with a file-specific error.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shlex
import sys
from pathlib import Path
from typing import Any


VALID_MODES = {"single_repo", "workflow_hub", "product_repo"}
LOCAL_ONLY_KEYS = {
    "local_path",
    "checkout_path",
    "checkout_root",
    "private_key_path",
    "private_key",
    "secret",
    "secrets",
    "secret_ref",
    "tool_overrides",
    "local_overrides",
}


class ConfigError(Exception):
    """Configuration problem with a human-readable message."""


def strip_inline_comment(line: str) -> str:
    in_single = False
    in_double = False
    escaped = False
    result: list[str] = []
    for char in line:
        if escaped:
            result.append(char)
            escaped = False
            continue
        if char == "\\" and in_double:
            result.append(char)
            escaped = True
            continue
        if char == "'" and not in_double:
            in_single = not in_single
            result.append(char)
            continue
        if char == '"' and not in_single:
            in_double = not in_double
            result.append(char)
            continue
        if char == "#" and not in_single and not in_double:
            break
        result.append(char)
    return "".join(result).rstrip()


def preprocess_yaml(path: Path) -> list[tuple[int, str, int]]:
    try:
        raw_lines = path.read_text(encoding="utf-8").splitlines()
    except OSError as exc:
        raise ConfigError(f"{path}: could not read config: {exc}") from exc

    lines: list[tuple[int, str, int]] = []
    for line_no, raw in enumerate(raw_lines, start=1):
        if "\t" in raw[: len(raw) - len(raw.lstrip(" \t"))]:
            raise ConfigError(f"{path}:{line_no}: tabs are not supported for indentation")
        stripped_comment = strip_inline_comment(raw)
        if not stripped_comment.strip():
            continue
        indent = len(stripped_comment) - len(stripped_comment.lstrip(" "))
        if indent % 2 != 0:
            raise ConfigError(f"{path}:{line_no}: indentation must use multiples of two spaces")
        lines.append((indent, stripped_comment.strip(), line_no))
    return lines


def split_key_value(content: str, path: Path, line_no: int) -> tuple[str, str | None]:
    if ":" not in content:
        raise ConfigError(f"{path}:{line_no}: expected '<key>: <value>'")
    key, value = content.split(":", 1)
    key = key.strip()
    if not re.match(r"^[A-Za-z0-9_.-]+$", key):
        raise ConfigError(f"{path}:{line_no}: unsupported key '{key}'")
    value = value.strip()
    return key, value if value != "" else None


def parse_scalar(value: str) -> Any:
    if value.startswith("[") and value.endswith("]"):
        inner = value[1:-1].strip()
        if not inner:
            return []
        return [parse_scalar(item.strip()) for item in split_inline_list(inner) if item.strip()]
    if value in {"''", '""'}:
        return ""
    if (value.startswith("'") and value.endswith("'")) or (
        value.startswith('"') and value.endswith('"')
    ):
        return value[1:-1]
    if value == "[]":
        return []
    if value == "{}":
        return {}
    if value.lower() == "true":
        return True
    if value.lower() == "false":
        return False
    if value.lower() in {"null", "~"}:
        return None
    return value


def split_inline_list(value: str) -> list[str]:
    items: list[str] = []
    current: list[str] = []
    in_single = False
    in_double = False
    escaped = False

    for char in value:
        if escaped:
            current.append(char)
            escaped = False
            continue
        if char == "\\" and in_double:
            current.append(char)
            escaped = True
            continue
        if char == "'" and not in_double:
            in_single = not in_single
            current.append(char)
            continue
        if char == '"' and not in_single:
            in_double = not in_double
            current.append(char)
            continue
        if char == "," and not in_single and not in_double:
            items.append("".join(current))
            current = []
            continue
        current.append(char)

    items.append("".join(current))
    return items


def parse_mapping(
    lines: list[tuple[int, str, int]], index: int, indent: int, path: Path
) -> tuple[dict[str, Any], int]:
    result: dict[str, Any] = {}
    while index < len(lines):
        line_indent, content, line_no = lines[index]
        if line_indent < indent:
            break
        if line_indent > indent:
            raise ConfigError(f"{path}:{line_no}: unexpected indentation")
        if content.startswith("- "):
            raise ConfigError(f"{path}:{line_no}: list item is not valid in this mapping")
        key, value = split_key_value(content, path, line_no)
        index += 1
        if value is not None:
            result[key] = parse_scalar(value)
            continue
        if index >= len(lines) or lines[index][0] <= indent:
            result[key] = {}
            continue
        child_indent, child_content, _ = lines[index]
        if child_indent != indent + 2:
            raise ConfigError(f"{path}:{lines[index][2]}: expected child indentation of {indent + 2}")
        if child_content.startswith("- "):
            child, index = parse_list(lines, index, child_indent, path)
        else:
            child, index = parse_mapping(lines, index, child_indent, path)
        result[key] = child
    return result, index


def parse_list(
    lines: list[tuple[int, str, int]], index: int, indent: int, path: Path
) -> tuple[list[Any], int]:
    result: list[Any] = []
    while index < len(lines):
        line_indent, content, line_no = lines[index]
        if line_indent < indent:
            break
        if line_indent > indent:
            raise ConfigError(f"{path}:{line_no}: unexpected indentation")
        if not content.startswith("- "):
            break
        item = content[2:].strip()
        index += 1
        if not item:
            if index >= len(lines) or lines[index][0] <= indent:
                result.append({})
                continue
            child_indent, child_content, _ = lines[index]
            if child_indent != indent + 2:
                raise ConfigError(f"{path}:{lines[index][2]}: expected child indentation of {indent + 2}")
            if child_content.startswith("- "):
                child, index = parse_list(lines, index, child_indent, path)
            else:
                child, index = parse_mapping(lines, index, child_indent, path)
            result.append(child)
            continue
        if ":" in item:
            key, value = split_key_value(item, path, line_no)
            if value is None and index < len(lines) and lines[index][0] > indent:
                # For `- key:` items, the following indented block is the value
                # of `key`; it must not be merged into the list-item root.
                child_indent = lines[index][0]
                child_content = lines[index][1]
                if child_content.startswith("- "):
                    child, index = parse_list(lines, index, child_indent, path)
                else:
                    child, index = parse_mapping(lines, index, child_indent, path)
                item_map = {key: child}
            else:
                item_map = {key: parse_scalar(value) if value is not None else {}}
            if value is not None and index < len(lines) and lines[index][0] == indent + 2:
                continuation, index = parse_mapping(lines, index, indent + 2, path)
                for continuation_key, continuation_value in continuation.items():
                    item_map[continuation_key] = continuation_value
            result.append(item_map)
        else:
            result.append(parse_scalar(item))
    return result, index


def parse_yaml_subset(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}
    lines = preprocess_yaml(path)
    if not lines:
        return {}
    if lines[0][0] != 0:
        raise ConfigError(f"{path}:{lines[0][2]}: top-level keys must not be indented")
    data, index = parse_mapping(lines, 0, lines[0][0], path)
    if index != len(lines):
        _, _, line_no = lines[index]
        raise ConfigError(f"{path}:{line_no}: could not parse remaining YAML")
    return data


def repo_root_from_args(value: str | None) -> Path:
    if value:
        return Path(value).resolve()
    return Path.cwd().resolve()


def as_mapping(value: Any, path: Path, field: str) -> dict[str, Any]:
    if value is None:
        return {}
    if not isinstance(value, dict):
        raise ConfigError(f"{path}: field '{field}' must be a mapping")
    return value


def as_list(value: Any, path: Path, field: str) -> list[Any]:
    if value is None:
        return []
    if not isinstance(value, list):
        raise ConfigError(f"{path}: field '{field}' must be a list")
    return value


def load_configs(repo_root: Path) -> tuple[dict[str, Any], dict[str, Any], Path, Path]:
    shared_path = repo_root / ".ai-dev-workflow.yaml"
    local_path = repo_root / ".ai-dev-workflow.local.yaml"
    shared = parse_yaml_subset(shared_path)
    local = parse_yaml_subset(local_path)
    return shared, local, shared_path, local_path


def mode_from_shared(shared: dict[str, Any], shared_path: Path) -> str:
    raw_mode = shared.get("mode", "single_repo")
    if raw_mode in {None, ""}:
        raw_mode = "single_repo"
    if not isinstance(raw_mode, str):
        raise ConfigError(f"{shared_path}: field 'mode' must be a string")
    if raw_mode not in VALID_MODES:
        raise ConfigError(
            f"{shared_path}: field 'mode' must be one of {', '.join(sorted(VALID_MODES))}"
        )
    return raw_mode


def product_repos(shared: dict[str, Any], shared_path: Path) -> list[dict[str, Any]]:
    workflow_hub = as_mapping(shared.get("workflow_hub"), shared_path, "workflow_hub")
    repos = as_list(workflow_hub.get("product_repos"), shared_path, "workflow_hub.product_repos")
    normalized: list[dict[str, Any]] = []
    seen: set[str] = set()
    for index, raw in enumerate(repos, start=1):
        if not isinstance(raw, dict):
            raise ConfigError(f"{shared_path}: workflow_hub.product_repos[{index}] must be a mapping")
        forbidden = sorted(find_local_only_keys(raw))
        if forbidden:
            raise ConfigError(
                f"{shared_path}: workflow_hub.product_repos[{index}] contains local-only field(s): {', '.join(forbidden)}"
            )
        name = raw.get("name")
        if not isinstance(name, str) or not name:
            raise ConfigError(f"{shared_path}: workflow_hub.product_repos[{index}].name is required")
        if name in seen:
            raise ConfigError(
                f"{shared_path}: duplicate workflow_hub.product_repos name '{name}'"
            )
        seen.add(name)
        github_repo = raw.get("github_repo") or ""
        git_url = raw.get("git_url") or ""
        if not github_repo and not git_url:
            raise ConfigError(
                f"{shared_path}: workflow_hub.product_repos[{index}] '{name}' must define github_repo or git_url"
            )
        repo = dict(raw)
        repo["default_branch"] = repo.get("default_branch") or "main"
        normalized.append(repo)
    return normalized


def find_local_only_keys(value: Any, prefix: str = "") -> set[str]:
    if isinstance(value, dict):
        found: set[str] = set()
        for key, child in value.items():
            key_path = f"{prefix}.{key}" if prefix else str(key)
            if key in LOCAL_ONLY_KEYS:
                found.add(key_path)
            found.update(find_local_only_keys(child, key_path))
        return found
    if isinstance(value, list):
        found = set()
        for index, child in enumerate(value, start=1):
            item_path = f"{prefix}[{index}]" if prefix else f"[{index}]"
            found.update(find_local_only_keys(child, item_path))
        return found
    return set()


def select_product_repo(repos: list[dict[str, Any]], target: str | None, shared_path: Path) -> dict[str, Any]:
    if target:
        for repo in repos:
            if repo.get("name") == target:
                return repo
        raise ConfigError(f"{shared_path}: no workflow_hub.product_repos entry named '{target}'")
    if not repos:
        raise ConfigError(f"{shared_path}: workflow_hub.product_repos is required for workflow_hub mode")
    if len(repos) > 1:
        names = ", ".join(str(repo.get("name")) for repo in repos)
        raise ConfigError(
            f"{shared_path}: product repository selection is ambiguous; pass --repo. Available: {names}"
        )
    return repos[0]


def local_product_repo(local: dict[str, Any], local_path: Path, name: str) -> dict[str, Any]:
    repos = as_list(local.get("product_repos"), local_path, "product_repos")
    for index, raw in enumerate(repos, start=1):
        if not isinstance(raw, dict):
            raise ConfigError(f"{local_path}: product_repos[{index}] must be a mapping")
        if raw.get("name") == name:
            return raw
    return {}


def resolve_local_path(
    repo_root: Path,
    local: dict[str, Any],
    local_path: Path,
    name: str,
    require_local: bool,
) -> tuple[str, str]:
    local_entry = local_product_repo(local, local_path, name)
    explicit = local_entry.get("local_path") or local_entry.get("checkout_path")
    if explicit:
        return str((repo_root / str(explicit)).resolve()) if not os.path.isabs(str(explicit)) else str(explicit), "local_override"
    checkout_root = local.get("checkout_root")
    if checkout_root:
        base = Path(str(checkout_root))
        if not base.is_absolute():
            base = (repo_root / base).resolve()
        return str(base / name), "checkout_root"
    if require_local:
        raise ConfigError(
            f"{local_path}: local path for product repo '{name}' is required; set product_repos[].local_path or checkout_root"
        )
    return "", ""


def relative_or_absolute_path(repo_root: Path, value: str) -> str:
    path = Path(value)
    if path.is_absolute():
        try:
            return os.path.relpath(path, repo_root)
        except ValueError:
            return str(path)
    return value


def quote_yaml_scalar(value: Any) -> str:
    text = str(value)
    if text == "":
        return '""'
    yaml_token = text.lower()
    if (
        yaml_token in {"true", "false", "yes", "no", "on", "off", "null", "~"}
        or re.match(r"^[+-]?[0-9]+(?:\.[0-9]+)?$", text)
    ):
        must_quote = True
    else:
        must_quote = not re.match(r"^[A-Za-z0-9_./:@~+-]+$", text)
    if not must_quote:
        return text
    escaped = text.replace("\\", "\\\\").replace("\n", "\\n").replace('"', '\\"')
    return '"' + escaped + '"'


def dump_yaml_subset(value: Any, indent: int = 0) -> list[str]:
    prefix = " " * indent
    lines: list[str] = []
    if isinstance(value, dict):
        for key, child in value.items():
            if isinstance(child, (dict, list)):
                lines.append(f"{prefix}{key}:")
                lines.extend(dump_yaml_subset(child, indent + 2))
            else:
                lines.append(f"{prefix}{key}: {quote_yaml_scalar(child)}")
        return lines
    if isinstance(value, list):
        for item in value:
            if isinstance(item, dict):
                if not item:
                    lines.append(f"{prefix}- {{}}")
                    continue
                first = True
                for key, child in item.items():
                    if first:
                        if isinstance(child, (dict, list)):
                            lines.append(f"{prefix}- {key}:")
                            lines.extend(dump_yaml_subset(child, indent + 4))
                        else:
                            lines.append(f"{prefix}- {key}: {quote_yaml_scalar(child)}")
                        first = False
                    else:
                        if isinstance(child, (dict, list)):
                            lines.append(f"{prefix}  {key}:")
                            lines.extend(dump_yaml_subset(child, indent + 4))
                        else:
                            lines.append(f"{prefix}  {key}: {quote_yaml_scalar(child)}")
            else:
                lines.append(f"{prefix}- {quote_yaml_scalar(item)}")
        return lines
    lines.append(f"{prefix}{quote_yaml_scalar(value)}")
    return lines


def set_local_product_repo_path(repo_root: Path, repo_name: str, local_path_value: str) -> Path:
    _, local, _, local_path = load_configs(repo_root)
    repos = as_list(local.get("product_repos"), local_path, "product_repos")
    updated = False
    match_count = 0
    normalized_path = relative_or_absolute_path(repo_root, local_path_value)

    new_repos: list[dict[str, Any]] = []
    for index, raw in enumerate(repos, start=1):
        if not isinstance(raw, dict):
            raise ConfigError(f"{local_path}: product_repos[{index}] must be a mapping")
        repo = dict(raw)
        if repo.get("name") == repo_name:
            match_count += 1
            repo["local_path"] = normalized_path
            updated = True
        new_repos.append(repo)

    if match_count > 1:
        raise ConfigError(
            f"{local_path}: duplicate product_repos entries named '{repo_name}' cannot be updated safely"
        )

    if not updated:
        new_repos.append({"name": repo_name, "local_path": normalized_path})
    local["product_repos"] = new_repos

    local_path.write_text("\n".join(dump_yaml_subset(local)) + "\n", encoding="utf-8")
    return local_path


def flatten_tracker_hints(repo: dict[str, Any]) -> str:
    tracker = repo.get("tracker")
    if not isinstance(tracker, dict):
        return ""
    parts = []
    for key in sorted(tracker):
        value = tracker[key]
        if value not in {None, ""}:
            parts.append(f"{key}:{value}")
    return ",".join(parts)


def github_repo_from_url(value: str) -> str:
    match = re.match(
        r"^(?:git@github\.com:|https://github\.com/|ssh://git@github\.com/)([^/\s]+/[^/\s]+?)(?:\.git)?/?$",
        value,
    )
    if not match:
        return ""
    return match.group(1)


def parse_remote_slug(repo_root: Path) -> str:
    git_config = repo_root / ".git" / "config"
    if not git_config.exists():
        return ""
    try:
        text = git_config.read_text(encoding="utf-8", errors="ignore")
    except OSError:
        return ""
    match = re.search(
        r"^\s*url = (?:git@github\.com:|https://github\.com/|ssh://git@github\.com/)([^/\s]+/[^/\s]+)\s*$",
        text,
        re.M,
    )
    if not match:
        return ""
    slug = match.group(1)
    return slug[:-4] if slug.endswith(".git") else slug


def nested_mapping(value: dict[str, Any], key: str) -> dict[str, Any]:
    raw = value.get(key)
    return raw if isinstance(raw, dict) else {}


def first_present(*values: Any) -> str:
    for value in values:
        if value is not None and value != "":
            return str(value)
    return ""


def resolve_auth_context(args: argparse.Namespace) -> dict[str, str]:
    repo_root = repo_root_from_args(args.repo_root)
    shared, local, shared_path, local_path = load_configs(repo_root)
    mode = mode_from_shared(shared, shared_path)
    if mode != "workflow_hub":
        return {
            "WORKFLOW_MODE": mode,
            "AUTH_STATUS": "not_required",
            "AUTH_REQUIRES_PRODUCT_REPO": "false",
            "AUTH_MESSAGE": "GitHub App product-repo auth is only required in workflow_hub mode",
        }

    repo = select_product_repo(product_repos(shared, shared_path), args.repo, shared_path)
    local_repo = local_product_repo(local, local_path, str(repo["name"]))
    shared_app = nested_mapping(repo, "github_app")
    local_app = nested_mapping(local_repo, "github_app")

    github_repo = str(repo.get("github_repo") or "")
    if not github_repo and repo.get("git_url"):
        github_repo = github_repo_from_url(str(repo.get("git_url")))

    app_id = first_present(local_app.get("app_id"), local_repo.get("app_id"), shared_app.get("app_id"))
    installation_id = first_present(
        local_app.get("installation_id"),
        local_repo.get("installation_id"),
        shared_app.get("installation_id"),
    )
    private_key_path = first_present(
        local_app.get("private_key_path"), local_repo.get("private_key_path")
    )
    secret_ref = first_present(local_app.get("secret_ref"), local_repo.get("secret_ref"))

    status = "auth_configured"
    if not app_id:
        status = "missing_app_id"
    elif not private_key_path and not secret_ref:
        status = "missing_private_key"
    elif not installation_id:
        status = "missing_installation"

    context = {
        "WORKFLOW_MODE": mode,
        "TARGET_REPO_NAME": str(repo.get("name") or ""),
        "TARGET_GITHUB_REPO": github_repo,
        "TARGET_GIT_URL": str(repo.get("git_url") or ""),
        "AUTH_STATUS": status,
        "AUTH_REQUIRES_PRODUCT_REPO": "true",
        "AUTH_APP_ID_PRESENT": "true" if app_id else "false",
        "AUTH_INSTALLATION_ID_PRESENT": "true" if installation_id else "false",
        "AUTH_PRIVATE_KEY_REF_PRESENT": "true" if (private_key_path or secret_ref) else "false",
        "AUTH_SECRET_SOURCE": (
            "private_key_path" if private_key_path else ("secret_ref" if secret_ref else "")
        ),
    }
    if args.include_local_secrets:
        context.update(
            {
                "AUTH_APP_ID": app_id,
                "AUTH_INSTALLATION_ID": installation_id,
                "AUTH_PRIVATE_KEY_PATH": private_key_path,
                "AUTH_SECRET_REF": secret_ref,
            }
        )
    return context


def resolve_context(args: argparse.Namespace) -> dict[str, str]:
    repo_root = repo_root_from_args(args.repo_root)
    shared, local, shared_path, local_path = load_configs(repo_root)
    mode = mode_from_shared(shared, shared_path)
    context: dict[str, str] = {
        "WORKFLOW_MODE": mode,
        "TARGET_REPO_NAME": "",
        "TARGET_GITHUB_REPO": "",
        "TARGET_GIT_URL": "",
        "TARGET_DEFAULT_BRANCH": "",
        "TARGET_LOCAL_PATH": "",
        "TARGET_LOCAL_PATH_SOURCE": "",
        "TARGET_TRACKER_HINTS": "",
        "WORKFLOW_HUB_GITHUB_REPO": "",
        "WORKFLOW_HUB_GIT_URL": "",
    }

    if mode == "single_repo":
        context["TARGET_REPO_NAME"] = repo_root.name
        context["TARGET_GITHUB_REPO"] = parse_remote_slug(repo_root)
        context["TARGET_DEFAULT_BRANCH"] = str(shared.get("default_branch") or "main")
        context["TARGET_LOCAL_PATH"] = str(repo_root)
        context["TARGET_LOCAL_PATH_SOURCE"] = "current_repo"
        return context

    if mode == "workflow_hub":
        repo = select_product_repo(product_repos(shared, shared_path), args.repo, shared_path)
        local_value, local_source = resolve_local_path(
            repo_root, local, local_path, str(repo["name"]), bool(args.require_local)
        )
        context.update(
            {
                "TARGET_REPO_NAME": str(repo.get("name") or ""),
                "TARGET_GITHUB_REPO": str(repo.get("github_repo") or ""),
                "TARGET_GIT_URL": str(repo.get("git_url") or ""),
                "TARGET_DEFAULT_BRANCH": str(repo.get("default_branch") or "main"),
                "TARGET_LOCAL_PATH": local_value,
                "TARGET_LOCAL_PATH_SOURCE": local_source,
                "TARGET_TRACKER_HINTS": flatten_tracker_hints(repo),
            }
        )
        return context

    product_repo = as_mapping(shared.get("product_repo"), shared_path, "product_repo")
    hub = as_mapping(product_repo.get("workflow_hub"), shared_path, "product_repo.workflow_hub")
    context.update(
        {
            "TARGET_REPO_NAME": repo_root.name,
            "TARGET_GITHUB_REPO": parse_remote_slug(repo_root),
            "TARGET_DEFAULT_BRANCH": str(product_repo.get("default_branch") or "main"),
            "TARGET_LOCAL_PATH": str(repo_root),
            "TARGET_LOCAL_PATH_SOURCE": "current_repo",
            "WORKFLOW_HUB_GITHUB_REPO": str(hub.get("github_repo") or ""),
            "WORKFLOW_HUB_GIT_URL": str(hub.get("git_url") or ""),
        }
    )
    if not context["WORKFLOW_HUB_GITHUB_REPO"] and not context["WORKFLOW_HUB_GIT_URL"]:
        raise ConfigError(
            f"{shared_path}: product_repo.workflow_hub must define github_repo or git_url in product_repo mode"
        )
    return context


def list_from_path(data: dict[str, Any], path: list[str]) -> list[str]:
    value: Any = data
    for key in path:
        if not isinstance(value, dict):
            return []
        value = value.get(key)
    if isinstance(value, list):
        return [str(item) for item in value]
    return []


def scalar_from_path(data: dict[str, Any], path: list[str]) -> str:
    value: Any = data
    for key in path:
        if not isinstance(value, dict):
            return ""
        value = value.get(key)
    return str(value) if value not in {None, ""} else ""


def resolve_review_overrides(args: argparse.Namespace) -> dict[str, str]:
    repo_root = repo_root_from_args(args.repo_root)
    _, local, _, _ = load_configs(repo_root)

    local_runner = list_from_path(local, ["review", "on_draft", "runner"])
    runner = local_runner
    runner_source = ".ai-dev-workflow.local.yaml" if local_runner else ""

    local_policy = scalar_from_path(local, ["review", "internal_reviewers_unavailable_policy"])
    policy = local_policy
    policy_source = ".ai-dev-workflow.local.yaml" if local_policy else ""

    sources = []
    if runner_source:
        sources.append(f"runner:{runner_source}")
    if policy_source:
        sources.append(f"policy:{policy_source}")

    return {
        "REVIEW_ON_DRAFT_RUNNER": ",".join(runner),
        "REVIEW_ON_DRAFT_RUNNER_SOURCE": runner_source,
        "INTERNAL_REVIEWERS_UNAVAILABLE_POLICY": policy,
        "INTERNAL_REVIEWERS_UNAVAILABLE_POLICY_SOURCE": policy_source,
        "LOCAL_OVERRIDE_SOURCE": ",".join(sources),
    }


def print_shell_context(values: dict[str, str]) -> None:
    for key in sorted(values):
        value = values[key]
        if value == "":
            print(f"{key}=")
        else:
            print(f"{key}={shlex.quote(str(value))}")


def print_context(args: argparse.Namespace, values: dict[str, str]) -> None:
    if getattr(args, "json", False):
        print(json.dumps(values, sort_keys=True))
    else:
        print_shell_context(values)


def cmd_mode(args: argparse.Namespace) -> int:
    repo_root = repo_root_from_args(args.repo_root)
    shared, _, shared_path, _ = load_configs(repo_root)
    print_context(args, {"WORKFLOW_MODE": mode_from_shared(shared, shared_path)})
    return 0


def cmd_resolve(args: argparse.Namespace) -> int:
    print_context(args, resolve_context(args))
    return 0


def cmd_list_product_repos(args: argparse.Namespace) -> int:
    repo_root = repo_root_from_args(args.repo_root)
    shared, _, shared_path, _ = load_configs(repo_root)
    mode = mode_from_shared(shared, shared_path)
    if mode != "workflow_hub":
        raise ConfigError(f"{shared_path}: workflow_hub mode is required to list product repositories")
    names = [str(repo.get("name")) for repo in product_repos(shared, shared_path)]
    if args.json:
        print(json.dumps(names))
    else:
        for name in names:
            print(name)
    return 0


def cmd_set_local_path(args: argparse.Namespace) -> int:
    repo_root = repo_root_from_args(args.repo_root)
    shared, _, shared_path, _ = load_configs(repo_root)
    mode = mode_from_shared(shared, shared_path)
    if mode != "workflow_hub":
        raise ConfigError(f"{shared_path}: workflow_hub mode is required to write product repository local paths")
    select_product_repo(product_repos(shared, shared_path), args.repo, shared_path)
    written = set_local_product_repo_path(repo_root, args.repo, args.local_path)
    print_context(args, {"LOCAL_CONFIG_PATH": str(written)})
    return 0


def cmd_auth(args: argparse.Namespace) -> int:
    print_context(args, resolve_auth_context(args))
    return 0


def cmd_review_overrides(args: argparse.Namespace) -> int:
    print_context(args, resolve_review_overrides(args))
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Resolve AI workflow repository context")
    subcommands = parser.add_subparsers(dest="command", required=True)

    mode = subcommands.add_parser("mode", help="print the effective workflow mode")
    mode.add_argument("--repo-root")
    mode.add_argument("--json", action="store_true", help="print JSON instead of shell KEY=value")
    mode.set_defaults(func=cmd_mode)

    for name in ("resolve", "validate"):
        command = subcommands.add_parser(name, help=f"{name} repository context")
        command.add_argument("--repo-root")
        command.add_argument("--repo", help="stable product repository name")
        command.add_argument(
            "--require-local",
            action="store_true",
            help="require a resolved local product checkout path",
        )
        command.add_argument("--json", action="store_true", help="print JSON instead of shell KEY=value")
        command.set_defaults(func=cmd_resolve)

    list_product_repos = subcommands.add_parser(
        "list-product-repos", help="list configured workflow_hub product repository names"
    )
    list_product_repos.add_argument("--repo-root")
    list_product_repos.add_argument("--json", action="store_true", help="print JSON instead of one name per line")
    list_product_repos.set_defaults(func=cmd_list_product_repos)

    set_local_path = subcommands.add_parser(
        "set-local-path", help="write one product repository local path to local config"
    )
    set_local_path.add_argument("--repo-root")
    set_local_path.add_argument("--repo", required=True, help="stable product repository name")
    set_local_path.add_argument("--local-path", required=True, help="local checkout path to write")
    set_local_path.add_argument("--json", action="store_true", help="print JSON instead of shell KEY=value")
    set_local_path.set_defaults(func=cmd_set_local_path)

    auth = subcommands.add_parser("auth", help="print product repository auth metadata")
    auth.add_argument("--repo-root")
    auth.add_argument("--repo", help="stable product repository name")
    auth.add_argument(
        "--include-local-secrets",
        action="store_true",
        help="include local secret references for machine callers; do not use for normal logs",
    )
    auth.add_argument("--json", action="store_true", help="print JSON instead of shell KEY=value")
    auth.set_defaults(func=cmd_auth)

    overrides = subcommands.add_parser("review-overrides", help="print local review override values")
    overrides.add_argument("--repo-root")
    overrides.add_argument("--json", action="store_true", help="print JSON instead of shell KEY=value")
    overrides.set_defaults(func=cmd_review_overrides)
    return parser


def main(argv: list[str]) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        return int(args.func(args))
    except ConfigError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
