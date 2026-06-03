#!/usr/bin/env python3
"""Lint risky shell patterns in newly added workflow script lines.

The checker intentionally operates on added diff lines by default. It prevents
new risky patterns without turning existing historical debt into an immediate
repository-wide failure.
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


CHECKED_PATH = re.compile(r"^scripts/development-workflow/.*\.sh$")
CRITICAL_SUPPRESSION = re.compile(
    r"\b(?:gh|git|curl|haystack)\b.*\|\|\s*true\b"
)
SUPPRESSION = "workflow-shell-guard: allow SH001"


@dataclass
class AddedLine:
    path: str
    line: int
    content: str


@dataclass
class Finding:
    rule: str
    path: str
    line: int
    message: str
    content: str


def run_git_diff(base_ref: str) -> str:
    result = subprocess.run(
        [
            "git",
            "diff",
            "--unified=0",
            f"{base_ref}...HEAD",
            "--",
            "scripts/development-workflow",
        ],
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if result.returncode != 0:
        sys.stderr.write(result.stderr)
        raise SystemExit(result.returncode)
    return result.stdout


def parse_added_lines(diff_text: str) -> list[AddedLine]:
    added: list[AddedLine] = []
    current_path = ""
    new_line = 0

    for raw_line in diff_text.splitlines():
        if raw_line.startswith("+++ b/"):
            current_path = raw_line[6:]
            continue

        hunk = re.match(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@", raw_line)
        if hunk:
            new_line = int(hunk.group(1)) - 1
            continue

        if raw_line.startswith("+") and not raw_line.startswith("+++"):
            new_line += 1
            if current_path and CHECKED_PATH.match(current_path):
                added.append(AddedLine(current_path, new_line, raw_line[1:]))
            continue

        if raw_line.startswith(" ") or raw_line == "":
            new_line += 1

    return added


def lint_added_lines(lines: Iterable[AddedLine]) -> list[Finding]:
    findings: list[Finding] = []

    for line in lines:
        stripped = line.content.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if SUPPRESSION in line.content:
            continue
        if CRITICAL_SUPPRESSION.search(line.content):
            findings.append(
                Finding(
                    rule="SH001",
                    path=line.path,
                    line=line.line,
                    message=(
                        "critical command failure is suppressed with `|| true`; "
                        "handle the expected failure explicitly or add an inline "
                        f"`# {SUPPRESSION} - <reason>` suppression"
                    ),
                    content=line.content,
                )
            )

    return findings


def format_findings(findings: list[Finding]) -> str:
    output = [
        "workflow-shell-guard-lint found risky added shell lines:",
        "",
    ]
    for finding in findings:
        output.append(f"{finding.path}:{finding.line}: {finding.rule}: {finding.message}")
        output.append(f"  {finding.content.strip()}")
    output.append("")
    output.append("See scripts/lint/README.md for suppression guidance.")
    return "\n".join(output)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Lint risky added shell lines in workflow scripts."
    )
    parser.add_argument(
        "--base-ref",
        default="origin/develop",
        help="base ref used for git diff mode (default: origin/develop)",
    )
    parser.add_argument(
        "--diff-file",
        help="read a unified diff from this file instead of invoking git diff",
    )
    args = parser.parse_args()

    if args.diff_file:
        diff_text = Path(args.diff_file).read_text(encoding="utf-8")
    else:
        diff_text = run_git_diff(args.base_ref)

    findings = lint_added_lines(parse_added_lines(diff_text))
    if findings:
        print(format_findings(findings), file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
