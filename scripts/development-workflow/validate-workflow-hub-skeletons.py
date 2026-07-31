#!/usr/bin/env python3
"""Validate workflow-hub and product-repo skeleton manifests."""

from __future__ import annotations

import argparse
import importlib.util
import sys
from pathlib import Path
from typing import Any


ALLOWED_SCOPES = {"shared", "hub_only", "product_repo_injection"}
SKELETON_MANIFESTS = (
    "template/workflow-hub/skeleton-manifest.yaml",
    "template/product-repo-injection/skeleton-manifest.yaml",
)
PRODUCT_RELEASE_RUNTIME_PATHS = {
    "scripts/development-workflow/workflow-config-resolver.py",
    "scripts/development-workflow/validate-workflow-config.sh",
    "scripts/development-workflow/workflow-lib.sh",
    "scripts/development-workflow/pr-review-loop.sh",
    "scripts/development-workflow/pr-ci-loop.sh",
    "scripts/development-workflow/post-merge-cleanup.sh",
}


class ValidationError(Exception):
    """Validation problem with a human-readable message."""


def load_workflow_parser(repo_root: Path) -> Any:
    sys.dont_write_bytecode = True
    resolver_path = repo_root / "scripts/development-workflow/workflow-config-resolver.py"
    spec = importlib.util.spec_from_file_location("workflow_config_resolver", resolver_path)
    if spec is None or spec.loader is None:
        raise ValidationError(f"{resolver_path}: could not load workflow config parser")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def validate_skeleton_manifest(manifest_path: Path, repo_root: Path, parser: Any) -> None:
    if not manifest_path.read_text(encoding="utf-8").strip():
        raise ValidationError(f"{manifest_path}: manifest is empty")

    data = parser.parse_yaml_subset(manifest_path)
    if not isinstance(data, dict):
        raise ValidationError(f"{manifest_path}: manifest root must be a mapping")

    role = data.get("skeleton_role")
    if role not in {"workflow_hub", "product_repo"}:
        raise ValidationError(f"{manifest_path}: unknown skeleton_role '{role}'")

    entries = data.get("entries")
    if not isinstance(entries, list) or not entries:
        raise ValidationError(f"{manifest_path}: entries must be a non-empty list")

    product_required_runtime: set[str] = set()
    for index, entry in enumerate(entries, start=1):
        if not isinstance(entry, dict):
            raise ValidationError(f"{manifest_path}: entry {index} must be a mapping")
        path = entry.get("path")
        if not isinstance(path, str) or not path.strip():
            raise ValidationError(f"{manifest_path}: entry {index} has no path")
        scope = entry.get("mode_scope")
        if scope not in ALLOWED_SCOPES:
            raise ValidationError(f"{manifest_path}: entry {path} has unknown mode_scope '{scope}'")

        generated = entry.get("generated_example") is True or entry.get("example_only") is True
        if not generated and not (repo_root / path).exists():
            raise ValidationError(f"{manifest_path}: entry {path} points to a missing source path")

        if role == "product_repo":
            required = entry.get("required_for_product_repo") is True
            if path in PRODUCT_RELEASE_RUNTIME_PATHS and required:
                product_required_runtime.add(path)
            forbidden = (
                path.startswith("docs/specs/")
                or "implementation-plan" in path
                or path.startswith("docs/testing/workflow/")
            )
            if forbidden and not required:
                raise ValidationError(
                    f"{manifest_path}: product repository injection includes hub-owned artifact {path}"
                )
        elif entry.get("required_for_product_repo") is True:
            raise ValidationError(
                f"{manifest_path}: required_for_product_repo is only valid for product_repo manifests"
            )

    if role == "product_repo" and data.get("enforce_release_runtime") is True:
        missing_runtime = PRODUCT_RELEASE_RUNTIME_PATHS - product_required_runtime
        if missing_runtime:
            raise ValidationError(
                f"{manifest_path}: missing required product release runtime entries: {', '.join(sorted(missing_runtime))}"
            )


def validate_sync_manifest(sync_manifest: Path) -> None:
    lines = sync_manifest.read_text(encoding="utf-8").splitlines()
    if not lines:
        raise ValidationError(f"{sync_manifest}: manifest is empty")

    mode_scope_keys: set[str] = set()
    category_keys: set[str] = set()
    paths: set[str] = set()
    mode_scope_values: set[str] = set()
    in_mode_scopes = False
    in_categories = False

    for raw in lines:
        stripped = raw.strip()
        if not stripped or stripped.startswith("#"):
            continue
        indent = len(raw) - len(raw.lstrip(" "))

        if indent == 0:
            in_mode_scopes = stripped == "mode_scopes:"
            in_categories = stripped == "categories:"
            continue

        if in_mode_scopes and indent == 2 and stripped.endswith(":"):
            mode_scope_keys.add(stripped[:-1])
            continue

        if in_categories and indent == 2 and stripped.endswith(":"):
            category_keys.add(stripped[:-1])
            continue

        if stripped.startswith("- path: "):
            paths.add(stripped.removeprefix("- path: ").strip().strip("'\""))
            continue

        if stripped.startswith("path: "):
            paths.add(stripped.removeprefix("path: ").strip().strip("'\""))
            continue

        if stripped.startswith("mode_scope: "):
            mode_scope_values.add(stripped.removeprefix("mode_scope: ").strip().strip("'\""))

    missing_scopes = ALLOWED_SCOPES - mode_scope_keys
    if missing_scopes:
        raise ValidationError(
            f"{sync_manifest}: missing mode_scopes entries: {', '.join(sorted(missing_scopes))}"
        )

    unknown_scopes = mode_scope_values - ALLOWED_SCOPES
    if unknown_scopes:
        raise ValidationError(
            f"{sync_manifest}: unknown mode_scope values: {', '.join(sorted(unknown_scopes))}"
        )

    required_categories = {"always_sync", "special_handling", "project_specific"}
    missing_categories = required_categories - category_keys
    if missing_categories:
        raise ValidationError(
            f"{sync_manifest}: missing categories: {', '.join(sorted(missing_categories))}"
        )

    required_paths = {"template/workflow-hub/", "template/product-repo-injection/"}
    missing_paths = required_paths - paths
    if missing_paths:
        raise ValidationError(
            f"{sync_manifest}: missing skeleton paths: {', '.join(sorted(missing_paths))}"
        )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", default=".", help="repository root for source-path checks")
    parser.add_argument(
        "--parser-root",
        default=None,
        help="repository root that contains workflow-config-resolver.py; defaults to this script's repo",
    )
    parser.add_argument(
        "--skeleton-manifest",
        action="append",
        default=[],
        help="skeleton manifest to validate; defaults to both template skeleton manifests",
    )
    parser.add_argument(
        "--sync-manifest",
        default=None,
        help="sync manifest to validate; defaults to <repo-root>/sync-manifest.yaml",
    )
    parser.add_argument(
        "--skip-sync-manifest",
        action="store_true",
        help="skip sync-manifest.yaml validation",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    repo_root = Path(args.repo_root).resolve()
    parser_root = Path(args.parser_root).resolve() if args.parser_root else Path(__file__).resolve().parents[2]
    parser = load_workflow_parser(parser_root)

    manifests = args.skeleton_manifest or [str(repo_root / item) for item in SKELETON_MANIFESTS]
    for manifest in manifests:
        validate_skeleton_manifest(Path(manifest), repo_root, parser)

    if not args.skip_sync_manifest:
        sync_manifest = Path(args.sync_manifest) if args.sync_manifest else repo_root / "sync-manifest.yaml"
        validate_sync_manifest(sync_manifest)

    print("VALID")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ValidationError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
