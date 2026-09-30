#!/usr/bin/env python3
"""Lint `gh api graphql` query literals under scripts/ for balanced delimiters.

#1828 shipped a `gh api graphql` query in `apply-readiness-labels.sh` with one
extra closing brace. The test suite mocks `gh`, so a syntactically invalid
query stayed green until it hit GitHub live and every `codex-github` readiness
run escalated `codex-occupancy-timeline-fetch-failed`. That fix
(`test-apply-readiness-labels.sh`) proved the tokenizer approach but scoped it
to one file. This script generalizes the same check repo-wide across
`scripts/`, so the next unbalanced query literal in any script is caught
before merge regardless of which file it lands in.

The check tokenizes each query as a GraphQL lexer would: `"..."` strings (with
backslash escapes), `\"\"\"...\"\"\"` block strings, and `#` comments to end of
line are skipped, so delimiters inside them are neither counted nor able to
hide real ones. Nesting order is checked, not just totals — `query{a}}{` has
equal counts of `{` and `}` but is not valid.
"""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path

# Shell shape: `query='` must begin a shell word — a flag argument such as
# `-f query='` or an assignment to a variable whose name ends in `query`
# (`query=`, `graphql_query=`, `local _gql_items_query=`). Text such as
# `obj.query='`, or `query='` in the middle of a word, is not a query literal.
# `gh api graphql` itself is not required on the same command: real call
# sites go through wrappers (`gh "${gh_args[@]}"`,
# `workflow_run_gh_capture_stderr api graphql`) or pass the variable to a
# helper function.
QUERY_ASSIGNMENT_START = re.compile(r"(?<![^\s;(])(?:[A-Za-z_][A-Za-z0-9_]*)?query='")
# GraphQL content: the literal must open (after whitespace and # comments)
# with an operation keyword or an anonymous `{` selection set. This keeps
# shell prose or non-GraphQL strings that happen to use a `*query='` shape out
# of scope.
GRAPHQL_OPENING = re.compile(
    r"\A(?:\s|#[^\r\n]*)*(?:query|mutation|subscription|fragment)\b|\A(?:\s|#[^\r\n]*)*\{"
)
# Files that never mention GraphQL cannot hold a `gh api graphql` literal.
GRAPHQL_FILE_MARKER = "graphql"
PAIRS = {"}": "{", ")": "(", "]": "["}
OPENERS = set(PAIRS.values())

# Paths under any `tests/` directory are excluded from the scan: fixtures in
# this repo's own checker tests deliberately construct malformed query
# literals (and, in test-protocol-91-readiness-checklist.sh, embed a Python
# regex string that merely *looks* like `query='...'`) to prove the tokenizer
# catches them. Those are not production `gh api graphql` calls.
EXCLUDED_PATH_SEGMENT = "/tests/"


def extract_concatenated_query(text: str, quote_pos: int) -> tuple[str, int] | None:
    """Join adjacent quoted bash segments starting at an opening `'`.

    Some queries are built via bash string concatenation, e.g.
    `graphql_query='query{...'"$pr_fields"'more{...}}'` — adjacent quoted
    segments with no operator between them are one logical string. Bash
    single-quoted segments cannot contain an escaped quote (a `'` always
    terminates them), so segment boundaries are unambiguous. Double-quoted
    segments (typically a `"$variable"` interpolation) contribute unknown
    content at compose time, so they are skipped rather than guessed at;
    contiguous-quote parsing itself is not sensitive to shell metacharacters
    since it only ever needs to find the next `'` or handle a `\"`-escaped
    `"` inside a double-quoted run.

    Returns (joined_query_text, end_index) or None if a segment is
    unterminated.
    """
    parts: list[str] = []
    pos = quote_pos
    n = len(text)
    while pos < n and text[pos] == "'":
        end = text.find("'", pos + 1)
        if end == -1:
            return None
        parts.append(text[pos + 1 : end])
        pos = end + 1
        if pos < n and text[pos] == '"':
            j = pos + 1
            while j < n and text[j] != '"':
                j += 2 if text[j] == "\\" and j + 1 < n else 1
            if j >= n:
                return None
            pos = j + 1
    return "".join(parts), pos


@dataclass
class Finding:
    path: str
    line: int
    query: str


def well_nested(query: str) -> bool:
    """Return True if a GraphQL query's delimiters are correctly nested.

    Skips GraphQL string values (`"..."` and `\"\"\"...\"\"\"`, both with
    backslash escapes) and `#` comments to end of line, since delimiters
    inside them are data or prose, not syntax.
    """
    stack: list[str] = []
    i, n = 0, len(query)
    while i < n:
        if query.startswith('"""', i):
            j = i + 3
            while j < n and not query.startswith('"""', j):
                j += 4 if query.startswith('\\"""', j) else 1
            if j >= n:
                return False
            i = j + 3
            continue
        char = query[i]
        if char == '"':
            j = i + 1
            while j < n and query[j] not in '"\r\n':
                j += 2 if query[j] == '\\' and j + 1 < n and query[j + 1] not in '\r\n' else 1
            if j >= n or query[j] != '"':
                return False
            i = j + 1
            continue
        if char == '#':
            while i < n and query[i] not in '\r\n':
                i += 1
            continue
        if char in OPENERS:
            stack.append(char)
        elif char in PAIRS:
            if not stack or stack.pop() != PAIRS[char]:
                return False
        i += 1
    return not stack


WORD_BOUNDARY_BEFORE = " \t\r\n;&|()"
CASE_KEYWORD = re.compile(r"(case|esac)(?=[\s;&|()]|\Z)")
HEREDOC_OPERATOR = re.compile(r"<<(-?)[ \t]*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\2")


def _skip_heredoc_bodies(text: str, pos: int, pending: list[tuple[str, bool]]) -> int:
    """Skip heredoc bodies that start at `pos` (just after a newline)."""
    n = len(text)
    for word, strip_tabs in pending:
        while pos < n:
            end = text.find("\n", pos)
            line = text[pos : end if end != -1 else n]
            pos = end + 1 if end != -1 else n
            if (line.lstrip("\t") if strip_tabs else line) == word:
                break
    return pos


def executed_query_starts(text: str) -> list[tuple[int, int]]:
    """Return (match_start, quote_pos) for `*query='` in executed shell code.

    A small shell-context lexer: text inside double quotes, `#` comments
    (whole-line or trailing), other single-quoted strings, `$'...'` strings,
    and heredoc bodies is data, not code, so a `query='` there is never a
    literal passed to `gh api graphql`. Command substitutions (`$( ... )`)
    are code again even inside double quotes — most real call sites have the
    shape `var="$(gh api graphql -f query='...')"`.
    """
    starts: list[tuple[int, int]] = []
    # Each frame: ["code", paren_depth, case_depth] or ["dq", 0, 0]. The
    # bottom frame is code. case_depth tracks open `case ... esac` blocks so a
    # pattern terminator `)` is never mistaken for the `$(` closer.
    stack: list[list] = [["code", 0, 0]]
    pending_heredocs: list[tuple[str, bool]] = []
    i, n = 0, len(text)
    while i < n:
        frame = stack[-1]
        c = text[i]
        if frame[0] == "dq":
            if c == "\\":
                i += 2
            elif c == '"':
                stack.pop()
                i += 1
            elif text.startswith("$(", i):
                stack.append(["code", 0, 0])
                i += 2
            else:
                i += 1
            continue

        at_word_start = i == 0 or text[i - 1] in WORD_BOUNDARY_BEFORE
        if at_word_start:
            match = QUERY_ASSIGNMENT_START.match(text, i)
            if match:
                quote_pos = match.end() - 1
                starts.append((i, quote_pos))
                extracted = extract_concatenated_query(text, quote_pos)
                if extracted is None:
                    break  # unterminated: the rest of the file is swallowed
                i = extracted[1]
                continue
            if c == "#":
                end = text.find("\n", i)
                i = end if end != -1 else n
                continue
            keyword = CASE_KEYWORD.match(text, i)
            if keyword:
                if keyword.group(1) == "case":
                    frame[2] += 1
                elif frame[2] > 0:
                    frame[2] -= 1
                i = keyword.end()
                continue
        if c == "\\":
            i += 2
        elif c == "\n":
            i += 1
            if pending_heredocs:
                i = _skip_heredoc_bodies(text, i, pending_heredocs)
                pending_heredocs = []
        elif text.startswith("$'", i):
            j = i + 2
            while j < n and text[j] != "'":
                j += 2 if text[j] == "\\" else 1
            i = j + 1
        elif c == "'":
            end = text.find("'", i + 1)
            i = end + 1 if end != -1 else n
        elif c == '"':
            stack.append(["dq", 0, 0])
            i += 1
        elif text.startswith("$(", i):
            stack.append(["code", 0, 0])
            i += 2
        elif c == "(":
            frame[1] += 1
            i += 1
        elif c == ")":
            if frame[1] > 0:
                frame[1] -= 1
            elif frame[2] > 0:
                pass  # a `case` pattern terminator, not the `$(` closer
            elif len(stack) > 1:
                stack.pop()
            i += 1
        elif text.startswith("<<<", i):
            # Here-string: the operand is an ordinary word, lexed normally.
            i += 3
        elif text.startswith("<<", i):
            heredoc = HEREDOC_OPERATOR.match(text, i)
            if heredoc:
                pending_heredocs.append((heredoc.group(3), heredoc.group(1) == "-"))
                i = heredoc.end()
            else:
                i += 2
        else:
            i += 1
    return starts


def graphql_literals(text: str) -> list[tuple[int, str | None]]:
    """Return (line, joined_query_or_None_if_unterminated) per GraphQL literal."""
    if GRAPHQL_FILE_MARKER not in text:
        return []
    literals: list[tuple[int, str | None]] = []
    for match_start, quote_pos in executed_query_starts(text):
        extracted = extract_concatenated_query(text, quote_pos)
        body = extracted[0] if extracted is not None else text[quote_pos + 1 :]
        if not GRAPHQL_OPENING.match(body):
            continue
        line = text.count("\n", 0, match_start) + 1
        literals.append((line, extracted[0] if extracted is not None else None))
    return literals


def find_unbalanced_in_text(path: str, text: str) -> list[Finding]:
    findings: list[Finding] = []
    for line, query in graphql_literals(text):
        if query is None:
            findings.append(Finding(path=path, line=line, query="<unterminated literal>"))
        elif not well_nested(query):
            findings.append(Finding(path=path, line=line, query=query))
    return findings


def count_query_literals(text: str) -> int:
    return len(graphql_literals(text))


def is_excluded(relative: Path) -> bool:
    # Evaluated on the path relative to the scan root, so a checkout that
    # itself lives under a directory named `tests` is not wholly excluded.
    return EXCLUDED_PATH_SEGMENT in f"/{relative.as_posix()}"


def discover_shell_files(root: Path) -> list[Path]:
    # An explicitly named file is always scanned: the caller asked for it.
    if root.is_file():
        return [root]
    return sorted(
        p for p in root.rglob("*.sh") if not is_excluded(p.relative_to(root))
    )


def format_findings(findings: list[Finding]) -> str:
    lines = [
        "lint-graphql-query-literals found unbalanced GraphQL query literals:",
        "",
    ]
    for finding in findings:
        lines.append(f"{finding.path}:{finding.line}: unbalanced or misnested delimiters")
        lines.append(f"  query='{finding.query}'")
    lines.append("")
    lines.append(
        "Braces, brackets, and parens must nest correctly (order, not just "
        "totals). Delimiters inside GraphQL string values and # comments are "
        "ignored. See scripts/lint/README.md."
    )
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Lint every `gh api graphql` query='...' literal under a scripts/ "
            "tree for balanced, correctly nested delimiters."
        )
    )
    parser.add_argument(
        "paths",
        nargs="*",
        default=["scripts"],
        help="files or directories to scan (default: scripts)",
    )
    args = parser.parse_args()

    files: list[Path] = []
    for raw_path in args.paths:
        target = Path(raw_path)
        if not target.exists():
            print(f"ERROR: path not found: {target}", file=sys.stderr)
            return 2
        files.extend(discover_shell_files(target))

    findings: list[Finding] = []
    total_queries = 0
    examined = 0
    for file_path in files:
        text = file_path.read_text(encoding="utf-8", errors="surrogateescape")
        examined += 1
        total_queries += count_query_literals(text)
        findings.extend(find_unbalanced_in_text(str(file_path), text))

    print(
        f"lint-graphql-query-literals: examined={examined} files, "
        f"queries={total_queries}, findings={len(findings)}",
        file=sys.stderr,
    )

    if findings:
        print(format_findings(findings), file=sys.stderr)
        return 1

    if examined == 0:
        # A run that examined nothing proves nothing; refuse to read as a pass.
        print(
            "ERROR: no shell files examined; check the scan path(s).",
            file=sys.stderr,
        )
        return 2

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
