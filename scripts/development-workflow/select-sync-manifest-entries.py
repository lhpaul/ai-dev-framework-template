#!/usr/bin/env python3
"""Select sync-manifest entries for a repository mode.

The sync manifest uses a deliberately small YAML shape: top-level
`mode_scopes`, then `categories` with list entries that include `path`,
optional `glob`, and `mode_scope`. This parser is intentionally scoped to that
shape so the helper can run without third-party YAML dependencies.
"""

from __future__ import annotations

import argparse
import sys
from dataclasses import dataclass
from pathlib import Path


VALID_ROLES = {"single_repo", "workflow_hub", "product_repo"}
VALID_MODE_SCOPES = {"shared", "hub_only", "product_repo_injection"}
CATEGORY_NAMES = {"always_sync", "special_handling", "project_specific"}
ROLE_SCOPE_SELECTION = {
    "single_repo": VALID_MODE_SCOPES,
    "workflow_hub": {"shared", "hub_only"},
    "product_repo": {"shared", "product_repo_injection"},
}


class ManifestError(Exception):
    """Manifest selection failure with a human-readable message."""


@dataclass(frozen=True)
class ManifestEntry:
    category: str
    path: str
    glob: str
    mode_scope: str
    mixed_content: str
    annotation_scheme: str
    line_no: int


def strip_inline_comment(line: str) -> str:
    in_single = False
    in_double = False
    triple_quote: str | None = None
    escaped = False
    result: list[str] = []
    index = 0
    while index < len(line):
        char = line[index]
        if escaped:
            result.append(char)
            escaped = False
            index += 1
            continue
        if triple_quote is not None:
            if line.startswith(triple_quote, index):
                result.append(line[index : index + 3])
                index += 3
                triple_quote = None
                continue
            result.append(char)
            index += 1
            continue
        if not in_single and not in_double and line.startswith('"""', index):
            result.append('"""')
            index += 3
            triple_quote = '"""'
            continue
        if not in_single and not in_double and line.startswith("'''", index):
            result.append("'''")
            index += 3
            triple_quote = "'''"
            continue
        if char == "\\" and in_double:
            result.append(char)
            escaped = True
            index += 1
            continue
        if char == "'" and not in_double:
            in_single = not in_single
            result.append(char)
            index += 1
            continue
        if char == '"' and not in_single:
            in_double = not in_double
            result.append(char)
            index += 1
            continue
        if char == "#" and not in_single and not in_double:
            break
        result.append(char)
        index += 1
    return "".join(result).rstrip()


def parse_scalar(value: str) -> str:
    value = value.strip()
    if (value.startswith('"""') and value.endswith('"""')) or (
        value.startswith("'''") and value.endswith("'''")
    ):
        return value[3:-3]
    if (value.startswith('"') and value.endswith('"')) or (
        value.startswith("'") and value.endswith("'")
    ):
        return value[1:-1]
    return value


def parse_key_value(content: str) -> tuple[str, str] | None:
    if ":" not in content:
        return None
    key, value = content.split(":", 1)
    return key.strip(), parse_scalar(value.strip())


def parse_manifest(path: Path) -> tuple[set[str], list[ManifestEntry]]:
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError as exc:
        raise ManifestError(f"could not read manifest {path}: {exc}") from exc

    mode_scopes: set[str] = set()
    entries: list[ManifestEntry] = []
    section: str | None = None
    current_category: str | None = None
    current: dict[str, str] | None = None
    current_line = 0
    block_scalar_indent: int | None = None

    def flush_current() -> None:
        nonlocal current, current_line
        if current is None:
            return
        entry_path = current.get("path", "")
        mode_scope = current.get("mode_scope", "")
        if not entry_path:
            raise ManifestError(f"line {current_line}: category entry is missing path")
        if not mode_scope:
            raise ManifestError(f"line {current_line}: entry {entry_path} is missing mode_scope")
        if mode_scope not in VALID_MODE_SCOPES:
            raise ManifestError(
                f"line {current_line}: entry {entry_path} has unknown mode_scope '{mode_scope}'"
            )
        if current_category is None:
            raise ManifestError(f"line {current_line}: entry {entry_path} has no category")
        entries.append(
            ManifestEntry(
                category=current_category,
                path=entry_path,
                glob=current.get("glob", ""),
                mode_scope=mode_scope,
                mixed_content=current.get("mixed_content", ""),
                annotation_scheme=current.get("annotation_scheme", ""),
                line_no=current_line,
            )
        )
        current = None
        current_line = 0

    for line_no, raw_line in enumerate(lines, start=1):
        if "\t" in raw_line[: len(raw_line) - len(raw_line.lstrip(" \t"))]:
            raise ManifestError(f"line {line_no}: tabs are not supported for indentation")
        line = strip_inline_comment(raw_line)
        if not line.strip():
            continue
        indent = len(line) - len(line.lstrip(" "))
        content = line.strip()

        if block_scalar_indent is not None:
            if indent > block_scalar_indent:
                continue
            block_scalar_indent = None

        if indent == 0:
            flush_current()
            current_category = None
            if content == "mode_scopes:":
                section = "mode_scopes"
            elif content == "categories:":
                section = "categories"
            else:
                section = None
            continue

        if section == "mode_scopes":
            if indent == 2 and content.endswith(":"):
                mode_scopes.add(content[:-1])
            continue

        if section != "categories":
            continue

        if indent == 2 and content.endswith(":"):
            flush_current()
            category = content[:-1]
            if category not in CATEGORY_NAMES:
                raise ManifestError(f"line {line_no}: unknown category '{category}'")
            current_category = category
            continue

        if indent == 4 and content.startswith("- "):
            flush_current()
            if current_category is None:
                raise ManifestError(f"line {line_no}: category entry appears before category name")
            current = {}
            current_line = line_no
            inline = content[2:].strip()
            parsed = parse_key_value(inline)
            if parsed is not None:
                key, value = parsed
                current[key] = value
            continue

        if indent >= 6 and current is not None:
            parsed = parse_key_value(content)
            if parsed is not None:
                key, value = parsed
                if value in {">", "|", ">-", "|-", ">+", "|+"}:
                    block_scalar_indent = indent
                current[key] = value

    flush_current()

    if not mode_scopes:
        raise ManifestError("manifest is missing mode_scopes")
    unknown_declared_scopes = mode_scopes - VALID_MODE_SCOPES
    if unknown_declared_scopes:
        joined = ", ".join(sorted(unknown_declared_scopes))
        raise ManifestError(f"manifest declares unknown mode_scope values: {joined}")
    missing_declared_scopes = VALID_MODE_SCOPES - mode_scopes
    if missing_declared_scopes:
        joined = ", ".join(sorted(missing_declared_scopes))
        raise ManifestError(f"manifest is missing required mode_scope declarations: {joined}")
    if not entries:
        raise ManifestError("manifest has no sync category entries")

    return mode_scopes, entries


def format_record(prefix: str, entry: ManifestEntry, reason: str = "") -> str:
    parts = [
        prefix,
        f"category={entry.category}",
        f"mode_scope={entry.mode_scope}",
        f"path={entry.path}",
        f"glob={entry.glob}",
        f"mixed_content={entry.mixed_content}",
        f"annotation_scheme={entry.annotation_scheme}",
    ]
    if reason:
        parts.append(f"reason={reason}")
    return " ".join(parts)


def run(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", required=True, help="Path to sync-manifest.yaml")
    parser.add_argument(
        "--role",
        required=True,
        choices=sorted(VALID_ROLES),
        help="Repository role to select for",
    )
    args = parser.parse_args(argv)

    manifest = Path(args.manifest).resolve()
    _, entries = parse_manifest(manifest)
    selected_scopes = ROLE_SCOPE_SELECTION[args.role]
    selected = [entry for entry in entries if entry.mode_scope in selected_scopes]
    skipped = [entry for entry in entries if entry.mode_scope not in selected_scopes]

    print(f"ROLE={args.role}")
    print(f"MANIFEST={manifest}")
    print(f"SELECTED_COUNT={len(selected)}")
    print(f"SKIPPED_COUNT={len(skipped)}")
    for entry in selected:
        print(format_record("SELECTED", entry))
    for entry in skipped:
        print(format_record("SKIPPED", entry, "scope_not_applicable"))
    return 0


def main() -> None:
    try:
        raise SystemExit(run(sys.argv[1:]))
    except ManifestError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)


if __name__ == "__main__":
    main()
