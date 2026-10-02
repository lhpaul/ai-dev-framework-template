#!/usr/bin/env python3
"""Check that synced tests only depend on files the sync manifest ships (#1874).

A downstream project receives the template's workflow test suites through
``sync-manifest.yaml``. When one of those suites reads a repository file the
manifest does not ship, the consumer runs a new test against a stale or missing
file and the failure looks like a regression in the consumer's own tree.

Coverage mode (default) reads the manifest and the synced test files from a
template checkout, extracts every tracked repository path each test reads, and
classifies it:

* ``COVERED``        - an ``always_sync`` or ``special_handling`` entry selected
                       for the role ships the file.
* ``PROJECT_OWNED``  - a ``project_specific`` entry owns the file. Sync never
                       overwrites it; a synced test that asserts on template
                       wording there must be gated to the template
                       (``workflow_template_is_template``) or backed by a
                       ``required_additions`` entry. Reported, not a gap.
* ``EXEMPT``         - listed in the manifest's ``sync_coverage_exemptions``
                       with a reason (the test only names the path as data).
* ``UNCOVERED``      - nothing selected for the role covers the file: a gap.

Extraction is deliberately conservative: a path counts when it appears as a
token in a test line, resolving ``VAR="$REPO_ROOT/dir"`` assignments and
Python ``ROOT / "a" / "b"`` joins. Comment lines (other than ``# covers:``
declarations) and JSON key values such as ``{"path": "..."}`` or the first
element of ``"files": ["..."]`` are skipped because they name a path without
reading it.

Consumer mode (``--consumer-root``) evaluates the manifest's
``required_additions`` against a downstream checkout and reports each additive
update a project-owned file still needs, so the pre-flight diagnostic can name
it before synced tests fail on it.

Exit codes: 0 clean, 1 gaps or missing required additions, 2 usage or input
error.
"""

from __future__ import annotations

import argparse
import fnmatch
import importlib.util
import re
import subprocess
import sys
from pathlib import Path

DEFAULT_TEST_DIR = "scripts/development-workflow/tests"
TEST_SUFFIXES = (".sh", ".py")

TOKEN_RE = re.compile(r"[A-Za-z0-9_.@+-]+(?:/[A-Za-z0-9_.@+-]+)*")
ASSIGN_RE = re.compile(
    r"""^\s*(?:local\s+|readonly\s+|export\s+|declare\s+(?:-[a-zA-Z]+\s+)?)?"""
    r"""([A-Za-z_][A-Za-z0-9_]*)=["']?\$\{?(?:REPO_ROOT|ROOT_DIR|ROOT)\}?/([^"'\s;)]+)"""
)
VAR_USE_RE = re.compile(r"\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?/([A-Za-z0-9_.@+/-]+)")
COVERS_RE = re.compile(r"^\s*#\s*covers:\s*(\S+)")
# A quoted path that is the value of a JSON key ("path": "x") or the first
# element of a JSON array value ("changed_files": ["x"]) is fixture data, not a
# file read. Later list elements are deliberately not skipped: a plain list of
# paths is as likely to be a list of files a test reads.
JSON_LITERAL_RE = re.compile(r""""[A-Za-z_][A-Za-z0-9_]*"\s*:\s*\[?\s*\\?"([^"\\]+)\\?\"""")
# Python joins path segments with "/" between quoted strings:
# REPO_ROOT / "scripts" / "x.py" reads scripts/x.py.
PY_JOIN_RE = re.compile(r"""["']\s*/\s*["']""")


class InputError(Exception):
    """Input failure with a human-readable message."""


def load_selector(repo_root: Path):
    selector_path = repo_root / "scripts/development-workflow/select-sync-manifest-entries.py"
    spec = importlib.util.spec_from_file_location("select_sync_manifest_entries", selector_path)
    if spec is None or spec.loader is None:
        raise InputError(f"cannot load manifest selector at {selector_path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def parse_section_list(manifest: Path, section: str, strip_comment) -> list[dict[str, str]]:
    """Parse a top-level list of flat mappings (``section:`` / ``  - key: v``)."""
    entries: list[dict[str, str]] = []
    current: dict[str, str] | None = None
    in_section = False
    block_indent: int | None = None
    block_key = ""
    block_lines: list[str] = []

    def close_block() -> None:
        nonlocal block_indent, block_key, block_lines
        if current is not None and block_key:
            current[block_key] = " ".join(part.strip() for part in block_lines if part.strip())
        block_indent, block_key, block_lines = None, "", []

    for raw in manifest.read_text(encoding="utf-8").splitlines():
        if block_indent is not None:
            indent = len(raw) - len(raw.lstrip(" "))
            if raw.strip() == "" or indent > block_indent:
                block_lines.append(raw)
                continue
            close_block()
        line = strip_comment(raw)
        if not line.strip():
            continue
        indent = len(line) - len(line.lstrip(" "))
        content = line.strip()
        if indent == 0:
            in_section = content == f"{section}:"
            continue
        if not in_section:
            continue
        if content.startswith("- "):
            current = {}
            entries.append(current)
            content = content[2:].strip()
            indent += 2
        if current is None or ":" not in content:
            continue
        key, value = content.split(":", 1)
        value = value.strip()
        if value in {">", "|", ">-", "|-", ">+", "|+"}:
            block_indent, block_key, block_lines = indent, key.strip(), []
            continue
        if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
            value = value[1:-1]
        current[key.strip()] = value
    close_block()
    return entries


def tracked_files(repo_root: Path) -> set[str]:
    try:
        output = subprocess.run(
            ["git", "-C", str(repo_root), "ls-files", "-z"],
            check=True,
            capture_output=True,
        ).stdout
    except (OSError, subprocess.CalledProcessError) as exc:
        raise InputError(f"cannot list tracked files in {repo_root}: {exc}") from exc
    return {item for item in output.decode("utf-8", "replace").split("\0") if item}


def entry_matches(entry, rel_path: str) -> bool:
    base = entry.path
    if not entry.glob:
        if base.endswith("/"):
            return rel_path.startswith(base)
        return rel_path == base
    prefix = base if base.endswith("/") else base + "/"
    if not rel_path.startswith(prefix):
        return False
    remainder = rel_path[len(prefix):]
    if entry.glob == "**/*":
        return True
    if entry.glob.startswith("**/"):
        return fnmatch.fnmatch(remainder.rsplit("/", 1)[-1], entry.glob[3:])
    return "/" not in remainder and fnmatch.fnmatch(remainder, entry.glob)


def classify(entries, rel_path: str, owned_entries=None) -> tuple[str, str]:
    """Return (classification, matching entry path).

    ``entries`` are the role-selected entries. ``owned_entries`` (default: the same
    list) supplies project_specific entries; callers pass every scope there because
    sync never ships a project-owned file in any role, so its scope does not decide
    whether the file is project-owned.
    """
    owned = [entry for entry in (entries if owned_entries is None else owned_entries) if entry.category == "project_specific"]
    # Exact project_specific paths take precedence over directory globs
    # (sync-manifest.yaml "Precedence" note).
    for entry in owned:
        if not entry.glob and entry.path == rel_path:
            return "project_owned", entry.path
    for entry in entries:
        if entry.category in {"always_sync", "special_handling"} and entry_matches(entry, rel_path):
            return "covered", entry.path
    for entry in owned:
        if entry_matches(entry, rel_path):
            return "project_owned", entry.path
    return "uncovered", ""


def referenced_paths(text: str, tracked: set[str]) -> set[str]:
    found: set[str] = set()

    def consider(candidate: str) -> None:
        candidate = candidate.rstrip(".,:")
        parts = candidate.split("/")
        # Try the token and every suffix after a "/" so "REPO_ROOT/x/y" finds "x/y".
        for index in range(len(parts)):
            suffix = "/".join(parts[index:])
            if suffix in tracked:
                found.add(suffix)
                return

    variables: dict[str, str] = {}
    for line in text.splitlines():
        match = ASSIGN_RE.match(line)
        if match:
            variables[match.group(1)] = match.group(2).rstrip("/")
    for value in variables.values():
        consider(value)

    for line in text.splitlines():
        covers = COVERS_RE.match(line)
        if covers:
            consider(covers.group(1))
            continue
        if line.lstrip().startswith("#"):
            continue
        line = PY_JOIN_RE.sub("/", line)
        data_spans = [match.span(1) for match in JSON_LITERAL_RE.finditer(line)]
        for match in VAR_USE_RE.finditer(line):
            base = variables.get(match.group(1))
            if base is not None:
                consider(f"{base}/{match.group(2)}")
        for match in TOKEN_RE.finditer(line):
            start, end = match.span()
            if any(span_start <= start and end <= span_end for span_start, span_end in data_spans):
                continue
            consider(match.group(0))
    return found


def check_required_additions(additions: list[dict[str, str]], consumer_root: Path) -> tuple[list[str], int]:
    lines: list[str] = []
    missing = 0
    for addition in additions:
        path = addition.get("path", "")
        must_contain = addition.get("must_contain", "")
        when_pattern = addition.get("when_pattern", "")
        if not path or not must_contain:
            raise InputError("required_additions entry needs path and must_contain")
        target = consumer_root / path
        label = f"path={path} must_contain={must_contain} introduced_in={addition.get('introduced_in', '')}"
        if not target.is_file():
            lines.append(f"REQUIRED_ADDITION_NOT_APPLICABLE {label} reason=file_absent")
            continue
        text = target.read_text(encoding="utf-8", errors="replace")
        try:
            applies = not when_pattern or re.search(when_pattern, text, re.MULTILINE) is not None
        except re.error as exc:
            raise InputError(f"required_additions entry for {path} has an invalid when_pattern: {exc}") from exc
        if not applies:
            lines.append(f"REQUIRED_ADDITION_NOT_APPLICABLE {label} reason=when_pattern_absent")
            continue
        if must_contain in text:
            lines.append(f"REQUIRED_ADDITION_PRESENT {label}")
            continue
        missing += 1
        reader = addition.get("read_by", "")
        lines.append(f"REQUIRED_ADDITION_MISSING {label} read_by={reader}")
    return lines, missing


def run(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--repo-root", default=".", help="template checkout to inspect (default: .)")
    parser.add_argument("--manifest", help="manifest path (default: <repo-root>/sync-manifest.yaml)")
    parser.add_argument(
        "--role",
        default="single_repo",
        choices=["single_repo", "workflow_hub", "product_repo"],
        help="repository role whose manifest selection is checked (default: single_repo)",
    )
    parser.add_argument("--test-dir", default=DEFAULT_TEST_DIR, help=f"synced test directory (default: {DEFAULT_TEST_DIR})")
    parser.add_argument("--consumer-root", help="downstream checkout: also evaluate required_additions against it")
    parser.add_argument("--show-covered", action="store_true", help="also print covered references")
    args = parser.parse_args(argv)

    repo_root = Path(args.repo_root).resolve()
    manifest = Path(args.manifest).resolve() if args.manifest else repo_root / "sync-manifest.yaml"
    selector = load_selector(repo_root)
    try:
        _, all_entries = selector.parse_manifest(manifest)
    except selector.ManifestError as exc:
        raise InputError(str(exc)) from exc
    scopes = selector.ROLE_SCOPE_SELECTION[args.role]
    entries = [entry for entry in all_entries if entry.mode_scope in scopes]
    exemptions = {
        item["path"]: item.get("reason", "")
        for item in parse_section_list(manifest, "sync_coverage_exemptions", selector.strip_inline_comment)
        if item.get("path")
    }
    additions = parse_section_list(manifest, "required_additions", selector.strip_inline_comment)

    tracked = tracked_files(repo_root)
    test_dir = args.test_dir.strip("/")
    tests = sorted(
        path
        for path in tracked
        if path.startswith(test_dir + "/") and path.endswith(TEST_SUFFIXES) and "/fixtures/" not in path
    )
    # Only suites the role actually receives can break downstream.
    synced_tests = [path for path in tests if classify(entries, path)[0] == "covered"]

    readers: dict[str, set[str]] = {}
    for test in synced_tests:
        text = (repo_root / test).read_text(encoding="utf-8", errors="replace")
        for ref in referenced_paths(text, tracked):
            if ref != test:
                readers.setdefault(ref, set()).add(test)

    counts = {"covered": 0, "project_owned": 0, "exempt": 0, "uncovered": 0}
    lines: list[str] = []
    for ref in sorted(readers):
        classification, owner = classify(entries, ref, all_entries)
        if classification == "uncovered" and ref in exemptions:
            classification = "exempt"
        counts[classification] += 1
        if classification == "covered" and not args.show_covered:
            continue
        read_by = ",".join(sorted(Path(test).name for test in readers[ref]))
        detail = f" entry={owner}" if owner else ""
        if classification == "exempt":
            detail = " reason=sync_coverage_exemptions"
        lines.append(f"{classification.upper()} path={ref}{detail} read_by={read_by}")

    print(f"ROLE={args.role}")
    print(f"MANIFEST={manifest}")
    print(f"SYNCED_TEST_COUNT={len(synced_tests)}")
    print(f"REFERENCED_PATH_COUNT={len(readers)}")
    print(f"COVERED_COUNT={counts['covered']}")
    print(f"PROJECT_OWNED_COUNT={counts['project_owned']}")
    print(f"EXEMPT_COUNT={counts['exempt']}")
    print(f"UNCOVERED_COUNT={counts['uncovered']}")
    for line in lines:
        print(line)

    missing_additions = 0
    if args.consumer_root:
        addition_lines, missing_additions = check_required_additions(additions, Path(args.consumer_root).resolve())
        print(f"REQUIRED_ADDITION_COUNT={len(additions)}")
        print(f"REQUIRED_ADDITION_MISSING_COUNT={missing_additions}")
        for line in addition_lines:
            print(line)

    failed = counts["uncovered"] or missing_additions
    print(f"RESULT={'gaps_found' if failed else 'clean'}")
    return 1 if failed else 0


def main() -> None:
    try:
        raise SystemExit(run(sys.argv[1:]))
    except InputError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(2)


if __name__ == "__main__":
    main()
