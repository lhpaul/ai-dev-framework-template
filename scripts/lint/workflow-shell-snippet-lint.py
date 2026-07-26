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
FENCE = re.compile(r"^\s*```(?P<lang>bash|sh|shell|zsh)?\s*$", re.I)
CONTRACT = re.compile(r"^\s*<!--\s*workflow-shell-contract:\s*(bash|bash-zsh)\s*-->\s*$")
SHELL_SIGNAL = re.compile(r"(?:^|\s)(?:git|gh|bash|zsh|for|while|set|if|cd|export|source)\b")
PORTABLE_FOR = re.compile(r"\bfor\s+\w+\s+in\s+\$[A-Za-z_][A-Za-z0-9_]*\b")
PORTABLE_SET = re.compile(r"\bset\s+--\s+\$[A-Za-z_][A-Za-z0-9_]*\b")
BASH_ONLY = re.compile(r"BASH_SOURCE|<\(|\[\[|\$\{|\b(?:readarray|mapfile)\b|\w+=\(")
BASH4 = re.compile(r"\b(?:declare|local)\s+-A\b|\b(?:readarray|mapfile)\b")


@dataclass
class Finding:
    rule: str
    path: str
    line: int
    message: str


def in_scope(path: str) -> bool:
    return path == "AGENTS.md" or path.startswith(ROOTS[1:])


def diff_text(base_ref: str | None, input_file: str | None) -> str:
    if input_file:
        return Path(input_file).read_text(encoding="utf-8")
    result = subprocess.run(["git", "diff", "--unified=0", f"{base_ref}...HEAD"], text=True, capture_output=True)
    if result.returncode:
        raise RuntimeError(result.stderr.strip())
    return result.stdout


def changed_lines(diff: str) -> dict[str, set[int]]:
    found: dict[str, set[int]] = {}
    path = ""
    number = 0
    for row in diff.splitlines():
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


def lint(path: str, changed: set[int]) -> list[Finding]:
    file_path = Path(path)
    if not file_path.exists():
        return []
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
        changed_here = any(index < number <= closer + 1 for number in changed)
        language = (opener.group("lang") or "").lower()
        content = "\n".join(fence_lines)
        executable = language in {"bash", "sh", "shell", "zsh"} or bool(SHELL_SIGNAL.search(content))
        if changed_here and executable:
            contract = contract_before(lines, index)
            line = index + 1
            if contract is None:
                findings.append(Finding("WS001", path, line, "missing adjacent workflow-shell-contract marker (bash or bash-zsh)"))
            elif contract == "bash":
                first = next((row.strip() for row in fence_lines if row.strip() and not row.lstrip().startswith("#")), "")
                if not (first.startswith("#!/") and "bash" in first or first.startswith("bash ") or first.startswith("bash<<") or first.startswith("bash <<")):
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
    return findings


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-ref", default="origin/develop")
    parser.add_argument("--input", "--diff-file", dest="input_file")
    parser.add_argument("--all", action="store_true")
    args = parser.parse_args()
    try:
        changed = changed_lines(diff_text(args.base_ref, args.input_file))
    except (OSError, RuntimeError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 2
    if args.all:
        changed = {str(path): set(range(1, len(path.read_text(encoding="utf-8").splitlines()) + 1)) for root in ROOTS for path in Path(root).rglob("*.md") if path.is_file()}
    findings = [finding for path, lines in changed.items() for finding in lint(path, lines)]
    for finding in findings:
        print(f"{finding.path}:{finding.line}: {finding.rule}: {finding.message}")
    return 1 if findings else 0


if __name__ == "__main__":
    raise SystemExit(main())
