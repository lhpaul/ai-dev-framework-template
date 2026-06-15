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
SUPPRESSION_DIRECTIVE = re.compile(
    r"\bworkflow-shell-guard:\s*allow\s+(SH\d{3})\b"
)
CRITICAL_COMMANDS = re.compile(r"\b(?:gh|git|curl|haystack)\b")
ASSIGNMENT_MASKING = re.compile(
    r"^\s*(?:local|declare|export)\s+[A-Za-z_][A-Za-z0-9_]*=\$\("
)
GREP_PREFIXES = ("fix/", "feature/", "refactor/", "hotfix/")


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

    for line in logical_lines(lines):
        stripped = line.content.strip()
        if not stripped or stripped.startswith("#"):
            continue
        findings.extend(lint_logical_line(line))

    return findings


def has_suppression(line: AddedLine, rule: str) -> bool:
    return any(
        match == rule
        for match in SUPPRESSION_DIRECTIVE.findall(line.content)
    )


def lint_logical_line(line: AddedLine) -> list[Finding]:
    findings: list[Finding] = []
    content = line.content

    if not has_suppression(line, "SH001") and CRITICAL_COMMANDS.search(content) and "|| true" in content:
        findings.append(
            Finding(
                rule="SH001",
                path=line.path,
                line=line.line,
                message=(
                    "critical command failure is suppressed with `|| true`; "
                    "handle the expected failure explicitly or add an inline "
                    "`# workflow-shell-guard: allow SH001 - <reason>` suppression"
                ),
                content=content,
            )
        )

    if not has_suppression(line, "SH002") and ASSIGNMENT_MASKING.search(content):
        findings.append(
            Finding(
                rule="SH002",
                path=line.path,
                line=line.line,
                message=(
                    "command substitution inside local/declare/export can mask "
                    "failures; split the declaration and assignment"
                ),
                content=content,
            )
        )

    if not has_suppression(line, "SH003") and is_unguarded_jq_r_assignment(content):
        findings.append(
            Finding(
                rule="SH003",
                path=line.path,
                line=line.line,
                message=(
                    "`jq -r` feeds control flow without `-e` or an explicit "
                    "exit-code guard; add `-e` or check the assignment result"
                ),
                content=content,
            )
        )

    if not has_suppression(line, "SH004") and has_unanchored_branch_prefix_grep(content):
        findings.append(
            Finding(
                rule="SH004",
                path=line.path,
                line=line.line,
                message=(
                    "unanchored branch-prefix grep can match substrings such "
                    "as `hotfix/`; anchor the prefix or use a case statement"
                ),
                content=content,
            )
        )

    if not has_suppression(line, "SH005") and re.search(r"^\s*(?:local|declare)\s+-A\b", content):
        findings.append(
            Finding(
                rule="SH005",
                path=line.path,
                line=line.line,
                message=(
                    "bash 4 associative arrays are unsupported here; use "
                    "parallel indexed arrays instead"
                ),
                content=content,
            )
        )

    return findings


def is_unguarded_jq_r_assignment(content: str) -> bool:
    if not re.search(
        r"^\s*(?:local|declare|export\s+)?[A-Za-z_][A-Za-z0-9_]*=\$\(",
        content,
    ):
        return False
    if "jq" not in content or "-r" not in content:
        return False

    jq_segment = content[content.index("jq") :]
    shell_level_segment = re.sub(r"'[^']*'|\"[^\"]*\"", "", jq_segment)
    if "-e" in shell_level_segment or "||" in shell_level_segment:
        return False

    return True


def has_unanchored_branch_prefix_grep(content: str) -> bool:
    if "grep" not in content:
        return False

    # Inspect the first grep pattern token after the command. This avoids
    # treating anchors that appear earlier in the same regex as missing just
    # because they are separated from the branch prefix by more than a few
    # characters.
    match = re.search(
        r"\bgrep\b(?:\s+-\S+)*\s+(?P<pattern>'[^']*'|\"[^\"]*\"|[^\s#]+)",
        content,
    )
    if not match:
        return False

    pattern = match.group("pattern").strip("'\"")
    for prefix in GREP_PREFIXES:
        idx = pattern.find(prefix)
        if idx == -1:
            continue
        if "^" not in pattern[:idx]:
            return True
    return False


def logical_lines(lines: Iterable[AddedLine]) -> list[AddedLine]:
    combined: list[AddedLine] = []
    pending: AddedLine | None = None
    pending_end_line = 0

    for line in lines:
        if pending is None:
            pending = line
            pending_end_line = line.line
        else:
            previous_continues = pending.content.rstrip().endswith("\\")
            same_file = pending.path == line.path
            consecutive = line.line == pending_end_line + 1
            if previous_continues and same_file and consecutive:
                pending = AddedLine(
                    pending.path,
                    pending.line,
                    f"{pending.content.rstrip()[:-1]} {line.content.strip()}",
                )
                pending_end_line = line.line
            else:
                combined.append(pending)
                pending = line
                pending_end_line = line.line

        if pending.content.rstrip().endswith("\\"):
            continue

        combined.append(pending)
        pending = None
        pending_end_line = 0

    if pending is not None:
        combined.append(pending)

    return combined


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
