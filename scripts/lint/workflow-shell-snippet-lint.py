#!/usr/bin/env python3
"""Lint changed executable shell fences on framework-owned guidance surfaces."""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

ROOTS = ("AGENTS.md", "docs/workflow/", "docs/best-practices/", ".agents/skills/", ".codex/skills/", ".claude/commands/", ".claude/agents/", ".cursor/commands/", ".cursor/agents/", "scripts/development-workflow/")
FENCE = re.compile(r"^\s*```(?P<lang>[A-Za-z0-9_-]+)?\s*$", re.I)
CONTRACT = re.compile(r"^\s*<!--\s*workflow-shell-contract:\s*(bash|bash-zsh)\s*-->\s*$")
SHELL_SIGNAL = re.compile(r"(?m)^\s*(?:git|gh|bash|zsh|for|while|set|if|cd|export|source)\b")
SHELL_LANGS = {"bash", "sh", "shell", "zsh"}
PORTABLE_FOR = re.compile(r"\bfor\s+\w+\s+in\s+\$[A-Za-z_][A-Za-z0-9_]*\b")
PORTABLE_SET = re.compile(r"\bset\s+--\s+\$[A-Za-z_][A-Za-z0-9_]*\b")
BASH_ONLY = re.compile(r"BASH_SOURCE|<\(|\[\[|\$\{![^}]+\}|\b(?:readarray|mapfile)\b|\w+=\(")
BASH4 = re.compile(r"\b(?:declare|local)\s+-A\b|\b(?:readarray|mapfile)\b")


@dataclass
class Finding:
    rule: str
    path: str
    line: int
    message: str


def in_scope(path: str) -> bool:
    return any(
        path == root.rstrip("/") or path.startswith(f"{root.rstrip('/')}/")
        for root in ROOTS
    )


def markdown_paths(root: str) -> list[Path]:
    candidate = Path(root)
    if candidate.is_file():
        return [candidate] if candidate.suffix == ".md" else []
    return list(candidate.rglob("*.md")) if candidate.is_dir() else []


def diff_text(base_ref: str | None, input_file: str | None) -> str:
    if input_file:
        return Path(input_file).read_text(encoding="utf-8")
    result = subprocess.run(["git", "diff", "--unified=0", f"{base_ref}...HEAD"], text=True, capture_output=True)
    # `git diff --exit-code` uses 1 to report differences. The normal command
    # above does not request that behavior, but accepting it keeps this helper
    # correct if the invocation is ever extended with that option.
    if result.returncode not in (0, 1):
        raise RuntimeError(result.stderr.strip())
    return result.stdout


# Structure this parser can actually consume. changed_lines() reads exactly two
# things: `+++ b/<path>` file headers and well-formed `@@ -a,b +c,d @@` hunk
# headers. `+++ /dev/null` is a deletion, which is a real header with nothing
# to examine behind it.
# A complete `diff --git` header names two paths. Requiring the second one keeps
# a prose line that merely starts with "diff --git " from standing in as
# evidence of a Git record. Paths are matched loosely on purpose: git does not
# quote a path containing spaces in this header, so "diff --git a/a b.txt
# b/a b.txt" is valid output and must not be rejected.
DIFF_GIT_HEADER = re.compile(r"(?m)^diff --git \S+ \S[^\n]*$")
DIFF_HUNK_HEADER = re.compile(r"(?m)^@@ -\d+(?:,\d+)? \+\d+(?:,\d+)? @@")
DIFF_TARGET_HEADER = re.compile(r"(?m)^\+\+\+ (?:b/\S|/dev/null\s*$)")


def split_diff_records(diff: str) -> list[str]:
    """Split a diff into records at each complete `diff --git` header.

    Any non-blank text before the first header is returned as its own leading
    record. changed_lines() processes those bytes, so the shape check must cover
    them too: validation and parsing have to see exactly the same input, or the
    unvalidated remainder is a hole.

    Returns an empty list when the text carries no `diff --git` header at all,
    which the caller treats as a single implicit record.
    """
    starts = [match.start() for match in DIFF_GIT_HEADER.finditer(diff)]
    if not starts:
        return []
    records: list[str] = []
    preamble = diff[: starts[0]]
    if preamble.strip():
        records.append(preamble)
    bounds = starts + [len(diff)]
    records.extend(diff[bounds[index] : bounds[index + 1]] for index in range(len(starts)))
    return records


def diff_shape(diff: str) -> str:
    """Classify what `diff` actually is, before trying to parse it.

    A path list, a file listing, or any other non-diff text parses as a diff
    with no hunks and yields an empty changed map, which reads exactly like a
    clean run (issue #1658, observed on PR #1646 where a real WS002 survived an
    `--input <path list>` invocation that exited 0).

    The markers are matched against the syntax this parser consumes, not against
    a prefix: a stray `@@ some prose` line or a Markdown `---` rule is not a
    diff. The classification then turns on whether the input carries changed
    lines this parser is failing to read, which is the only case worth refusing:

    * A hunk header means there ARE changed lines. Without a `+++` target header
      they cannot be attributed to a path, so the input is unreadable — a
      `git diff --no-prefix` output, for instance.
    * A `+++` target header with no hunk is a fragment either way: in real
      output a target header exists precisely to introduce a hunk, so a path
      with no lines behind it is malformed even when a `diff --git` line frames
      it. This case is checked before the metadata-only one.
    * No hunk header, no target header, and a `diff --git` line means a genuine
      Git record with no textual changes at all: a mode-only change, a binary
      file, a pure rename. There is nothing to attribute, so zero examined is
      the correct answer and the run passes. Refusing these would fail CI on any
      pull request that contains one.

    The check is **per record**, not global. A diff with several file records
    would otherwise pass on the strength of one well-formed record while another
    carried a hunk this parser cannot attribute: the markers would all be
    present *somewhere*, and changed_lines() would credit the unreadable
    record's lines to the previous record's path.

    Returns "empty", "not_a_diff", "unparseable", or "diff".
    """
    if not diff.strip():
        return "empty"
    records = split_diff_records(diff)
    if not records:
        records = [diff]
    shape = "diff"
    for record in records:
        framed = bool(DIFF_GIT_HEADER.match(record))
        has_hunk = bool(DIFF_HUNK_HEADER.search(record))
        has_target = bool(DIFF_TARGET_HEADER.search(record))
        if framed:
            # A Git record may legitimately carry neither: a mode-only change, a
            # binary file, a pure rename. It may not carry only one.
            if has_hunk != has_target:
                return "unparseable"
            continue
        # An unframed record — the text before the first `diff --git` header, or
        # the whole input when there is none — has no header vouching for it, so
        # only the full `+++` plus hunk pair makes it a diff. Carrying neither is
        # not a metadata-only record; it is prose.
        if has_hunk and has_target:
            continue
        if has_hunk or has_target:
            return "unparseable"
        shape = "not_a_diff"
    return shape


def changed_lines(diff: str) -> dict[str, set[int]]:
    found: dict[str, set[int]] = {}
    path = ""
    number = 0
    for row in diff.splitlines():
        # Each file record starts fresh: without this reset, a record whose
        # `+++ b/<path>` header this parser cannot read would have its lines
        # credited to the previous record's path.
        if DIFF_GIT_HEADER.match(row):
            path = ""
            continue
        if row.startswith("+++ b/"):
            path = row[6:]
            continue
        match = re.match(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@", row)
        if match:
            number = int(match.group(1)) - 1
            continue
        if row.startswith("+") and not row.startswith("+++"):
            number += 1
            if path and in_scope(path):
                found.setdefault(path, set()).add(number)
        elif row.startswith(" "):
            number += 1
    return found


def contract_before(lines: list[str], opener: int) -> str | None:
    cursor = opener - 1
    while cursor >= 0 and not lines[cursor].strip():
        cursor -= 1
    if cursor >= 0:
        match = CONTRACT.match(lines[cursor])
        return match.group(1) if match else None
    return None


def lint(path: str, changed: set[int]) -> tuple[list[Finding], int]:
    """Return this file's findings and the number of fences the rules evaluated.

    The count is the evidence that the run examined anything: a rule can only
    fire on a fence that is both changed and executable, so `evaluated == 0`
    means no WS rule ran on this file no matter what the exit status says.
    """
    file_path = Path(path)
    evaluated = 0
    if not file_path.exists():
        return [], evaluated
    lines = file_path.read_text(encoding="utf-8").splitlines()
    findings: list[Finding] = []
    index = 0
    while index < len(lines):
        opener = FENCE.match(lines[index])
        if not opener:
            index += 1
            continue
        closer = index + 1
        while closer < len(lines) and not lines[closer].lstrip().startswith("```"):
            closer += 1
        fence_lines = lines[index + 1 : closer]
        # A changed contract marker immediately above the opener (whose
        # 1-based line number equals the opener's 0-based index) must also
        # validate the fence it declares.
        changed_here = any(index <= number < closer + 1 for number in changed)
        language = (opener.group("lang") or "").lower()
        content = "\n".join(fence_lines)
        # A fence with an explicit language tag is authoritative: an explicit
        # shell tag (bash/sh/shell/zsh) is always executable, and any other
        # explicit tag (ts, typescript, python, json, ...) is never executable
        # shell, regardless of whether its content happens to contain a line
        # that starts with a SHELL_SIGNAL keyword (e.g. idiomatic TypeScript
        # `export`/`if` statements). Only an untagged fence is genuinely
        # ambiguous and falls back to the content heuristic.
        if language:
            executable = language in SHELL_LANGS
        else:
            executable = bool(SHELL_SIGNAL.search(content))
        if changed_here and executable:
            evaluated += 1
            contract = contract_before(lines, index)
            line = index + 1
            if contract is None:
                findings.append(Finding("WS001", path, line, "missing adjacent workflow-shell-contract marker (bash or bash-zsh)"))
            elif contract == "bash":
                first = next((row.strip() for row in fence_lines if row.strip()), "")
                launches_bash = any(re.match(r"^\s*bash(?:\s|$)", row) for row in fence_lines)
                if not (first.startswith("#!/") and "bash" in first or launches_bash):
                    findings.append(Finding("WS002", path, line, "bash contract must visibly launch Bash or start a complete Bash-shebang script"))
                if BASH4.search(content):
                    findings.append(Finding("WS006", path, line, "bash contract uses Bash 4+ syntax; repository supports Bash 3.2"))
            elif contract == "bash-zsh":
                if PORTABLE_FOR.search(content):
                    findings.append(Finding("WS003", path, line, "portable snippet uses implicit word splitting in a for loop"))
                if PORTABLE_SET.search(content):
                    findings.append(Finding("WS004", path, line, "portable snippet uses implicit positional-parameter splitting"))
                if BASH_ONLY.search(content):
                    findings.append(Finding("WS005", path, line, "portable snippet uses a Bash-only feature"))
        index = closer + 1
    return findings, evaluated


def emit_summary(files: int, fences: int, changed_line_count: int, source: str, findings: int) -> None:
    """Print the run summary. Called before EVERY exit, refusals included.

    A refusal that printed only an error would still leave a run with no
    machine-readable statement of how much it examined, which is the shape of
    evidence issue #1658 exists to remove.
    """
    print(
        f"examined={files} files, {fences} fences, {changed_line_count} changed-lines "
        f"(source: {source}); findings={findings}"
    )


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Lint changed executable shell fences on framework-owned guidance surfaces.",
    )
    parser.add_argument("--base-ref", default="origin/develop")
    parser.add_argument(
        "--input",
        "--diff-file",
        dest="input_file",
        help="Read a UNIFIED DIFF from this file instead of running git diff. This is not a path list.",
    )
    parser.add_argument("--all", action="store_true")
    parser.add_argument(
        "--allow-empty",
        action="store_true",
        help="Exit 0 when the diff under examination is empty instead of failing closed.",
    )
    args = parser.parse_args()
    if args.all:
        source = "all"
        changed = {str(path): set(range(1, len(path.read_text(encoding="utf-8").splitlines()) + 1)) for root in ROOTS for path in markdown_paths(root)}
    else:
        source = "input" if args.input_file else f"base-ref {args.base_ref}"
        try:
            diff = diff_text(args.base_ref, args.input_file)
        except (OSError, RuntimeError) as error:
            emit_summary(0, 0, 0, source, 0)
            print(f"ERROR: {error}", file=sys.stderr)
            return 2
        # Issue #1658: a run that examined nothing must never be mistaken for a
        # clean run. Classify the input before parsing it — a path list, a
        # malformed diff, and an empty diff all parse to an empty changed map,
        # but they are different failures and only one of them is ever
        # legitimate.
        shape = diff_shape(diff)
        if shape == "not_a_diff":
            emit_summary(0, 0, 0, source, 0)
            print(
                f"ERROR: --input/--diff-file expects a unified diff; {args.input_file!r} contains "
                "text that is not one — either the whole file, or the lines before its first "
                "`diff --git` header, carry no hunk and no `+++` target header. Produce it with "
                "`git diff --unified=0 <base>...HEAD`, or use --base-ref to let this script run "
                "git diff itself.",
                file=sys.stderr,
            )
            return 2
        if shape == "unparseable":
            emit_summary(0, 0, 0, source, 0)
            print(
                f"ERROR: the diff under examination (source: {source}) carries changed lines this "
                "parser cannot read: a hunk header with no `+++ b/<path>` target header to attribute "
                "it to, or a target header with no hunk behind it. Produce it with "
                "`git diff --unified=0 <base>...HEAD` and keep the default a/ and b/ prefixes.",
                file=sys.stderr,
            )
            return 2
        if shape == "empty" and not args.allow_empty:
            emit_summary(0, 0, 0, source, 0)
            print(
                f"ERROR: the diff under examination is empty (source: {source}); nothing was examined, "
                "so this run is not evidence that WS rules pass.",
                file=sys.stderr,
            )
            if not args.input_file:
                print(
                    f"HINT: --base-ref diffs committed history ({args.base_ref}...HEAD), so uncommitted "
                    "work is invisible to it. Commit first, or check that the base ref exists and is "
                    "fetched.",
                    file=sys.stderr,
                )
            else:
                print(
                    f"HINT: {args.input_file!r} produced no diff content.",
                    file=sys.stderr,
                )
            print("Pass --allow-empty if an empty diff is genuinely expected here.", file=sys.stderr)
            return 2
        changed = changed_lines(diff)
    findings: list[Finding] = []
    fences = 0
    for path, lines in sorted(changed.items()):
        path_findings, path_fences = lint(path, lines)
        findings.extend(path_findings)
        fences += path_fences
    for finding in findings:
        print(f"{finding.path}:{finding.line}: {finding.rule}: {finding.message}")
    emit_summary(
        len(changed),
        fences,
        sum(len(lines) for lines in changed.values()),
        source,
        len(findings),
    )
    if not changed:
        print(
            "NOTE: no in-scope guidance file changed in this diff, so no WS rule ran. "
            "Exit 0 here means 'nothing to check', not 'checks passed'.",
            file=sys.stderr,
        )
    return 1 if findings else 0


if __name__ == "__main__":
    raise SystemExit(main())
