#!/usr/bin/env python3
"""
Markdown heuristic lint checks for spec, plan, and CHANGELOG documents.

Two checks are implemented:

  GLOB001 — Suspicious non-recursive glob
      Detects a non-recursive glob pattern (e.g., *.sh) inside a fenced code
      block when the surrounding document prose (within a configurable window)
      uses recursive-language cues (e.g., "subdirectories", "recursively").

  COUNT001 — Within-document count disagreement
      Detects a narrative count phrase (e.g., "4 acceptance criteria") that
      disagrees with the count of list items in the section immediately
      following (within 30 lines).

Both checks support inline suppression via:
    <!-- markdown-heuristic-disable GLOB001 -->
    <!-- markdown-heuristic-disable COUNT001 -->
placed on the same line or the line immediately preceding the finding.

Usage:
    python3 scripts/lint/markdown-heuristic-lint.py <file> [<file> ...]

Exit codes:
    0 — no violations found
    1 — one or more violations found
"""

import re
import sys
from typing import List, Optional

# ---------------------------------------------------------------------------
# GLOB001 configuration
# Extend this list to add new recursive-language cues without changing the
# detection logic.
# ---------------------------------------------------------------------------
RECURSIVE_CUES: List[str] = [
    "subdirectories",
    "subdirectory",
    "recursively",
    "recursive",
    "under the tree",
    "all files in",
    "in all subdirectories",
    "in all sub-directories",
    "throughout the repository",
    "throughout the repo",
    "under the directory",
    "in the directory tree",
    "nested",
    "across all directories",
]

# Window (in lines) around a code block to search for recursive cues.
GLOB001_WINDOW = 10

# Regex: non-recursive glob patterns inside code blocks.
# Matches patterns like *.sh, *.md, *.smoke-test.md but not **/*.sh or ./**/*.sh
# The extension group allows dots and hyphens so multi-part extensions
# (e.g., *.smoke-test.md, *.spec.ts) are captured in full.
# A lookahead on word/punctuation boundary prevents matching mid-token.
_GLOB_PATTERN = re.compile(
    r'(?<!\*\*/)(?<!\*/)(?<!\.\*\*)(?<!\./\*\*)(?<!\w)'
    r'(\*\.[A-Za-z0-9_][A-Za-z0-9_.-]*)'
    r'(?=$|[\s"\'`),;: ])'
)

# ---------------------------------------------------------------------------
# COUNT001 configuration
# ---------------------------------------------------------------------------
# Window (in lines) after the narrative phrase to search for the list.
COUNT001_WINDOW = 30

# Written-out numerals 0–20.
_WORD_TO_NUM = {
    "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4,
    "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
    "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14,
    "fifteen": 15, "sixteen": 16, "seventeen": 17, "eighteen": 18,
    "nineteen": 19, "twenty": 20,
}

# Count-phrase keywords that signal a list count.
_COUNT_KEYWORDS = [
    r"acceptance criteria",
    r"acceptance criterion",
    r"use cases?",
    r"steps?",
    r"checks?",
    r"tasks?",
    r"rules?",
    r"requirements?",
    r"changes?",
    r"scenarios?",
    r"conditions?",
]

_NUM_PATTERN = r"(?P<n>\d+|" + "|".join(_WORD_TO_NUM.keys()) + r")"
_KEYWORD_PATTERN = "(?P<label>" + "|".join(_COUNT_KEYWORDS) + ")"
# Negative lookahead: exclude "N step(s)" when "step" is immediately followed by another
# number (e.g., "Protocol 90 Step 2.5" → "90 Step 2" is a section reference, not a count).
# Also exclude when preceded by "Protocol" (common in workflow doc prose).
_COUNT_PHRASE_RE = re.compile(
    r"(?<!Protocol\s)\b" + _NUM_PATTERN + r"\b\s+" + _KEYWORD_PATTERN + r"\b(?!\s*\d)",
    re.IGNORECASE,
)

# Markdown list item (ordered or unordered).
_LIST_ITEM_RE = re.compile(r"^\s{0,3}(?:[-*+]|\d+[.)]) ")

# Fenced code block opening pattern — matches 3 or more backticks/tildes.
# Capturing the full marker length (e.g., ```` for 4-backtick fences) is
# required so the closing fence is matched correctly.
_FENCE_RE = re.compile(r"^(?P<fence>`{3,}|~{3,})")

# Markdown heading
_HEADING_RE = re.compile(r"^#{1,6}\s")

# Suppression comment pattern
_SUPPRESS_RE = re.compile(
    r"<!--\s*markdown-heuristic-disable\s+(GLOB001|COUNT001)\s*-->"
)


def _is_suppressed(lines: List[str], line_index: int, rule: str) -> bool:
    """Return True if the given line (0-indexed) has a suppression comment for rule.

    Uses finditer so that a line with multiple directives (e.g.,
    <!-- markdown-heuristic-disable GLOB001 --> <!-- markdown-heuristic-disable COUNT001 -->)
    is handled correctly regardless of directive order.
    """
    for idx in (line_index, line_index - 1):
        if 0 <= idx < len(lines):
            for m in _SUPPRESS_RE.finditer(lines[idx]):
                if m.group(1) == rule:
                    return True
    return False


def _parse_number(text: str) -> Optional[int]:
    """Parse a digit string or written numeral to int."""
    if text.isdigit():
        return int(text)
    return _WORD_TO_NUM.get(text.lower())


def check_glob001(path: str, lines: List[str]) -> List[str]:
    """Check for suspicious non-recursive globs (GLOB001)."""
    findings: List[str] = []

    # Scan each code block line for non-recursive globs.
    # Use line.strip() for fence detection to handle indented fences correctly.
    # Store the full fence marker (3+ chars) so 4-backtick blocks are closed
    # by a 4-backtick fence and not accidentally by an inner 3-backtick line.
    in_code_block = False
    fence_marker: Optional[str] = None
    current_block_start = 0

    for i, line in enumerate(lines):
        lstripped = line.strip()
        stripped = line.rstrip()
        if not in_code_block:
            fence_match = _FENCE_RE.match(lstripped)
            if fence_match:
                in_code_block = True
                fence_marker = fence_match.group("fence")
                current_block_start = i
        else:
            if fence_marker and lstripped.startswith(fence_marker):
                in_code_block = False
                continue
            # Look for non-recursive glob patterns
            for m in _GLOB_PATTERN.finditer(stripped):
                glob_pattern = m.group(1)
                # Skip if it's preceded by ** (already recursive) — belt-and-suspenders
                start_pos = m.start(1)
                before = stripped[:start_pos]
                if before.endswith("**/") or before.endswith("*/"):
                    continue
                # Skip if it's a find -name argument: `find ... -name "*.ext"` or
                # `-name '*.ext'` — find itself handles recursion; the glob is a
                # filename-only pattern, not a path glob.
                if re.search(r"-name\s+[\"']?" + re.escape(glob_pattern) + r"[\"']?", stripped):
                    continue

                # Search for recursive cues in the surrounding prose.
                # Backward context: lines before the code block fence.
                # Forward context: lines after the code block's closing fence
                # (to avoid treating code-internal comments as "prose").
                window_start = max(0, current_block_start - GLOB001_WINDOW)
                backward_context = lines[window_start:current_block_start]

                # Find the closing fence to determine where forward prose starts.
                closing_fence_line = len(lines)  # default: end of file
                for k in range(i + 1, len(lines)):
                    if fence_marker and lines[k].strip().startswith(fence_marker):
                        closing_fence_line = k + 1  # prose starts after closing fence
                        break
                forward_end = min(len(lines), closing_fence_line + GLOB001_WINDOW)
                forward_context = lines[closing_fence_line:forward_end]

                context_lines = backward_context + forward_context
                context_text = " ".join(cl.lower() for cl in context_lines)

                triggered_cue: Optional[str] = None
                for cue in RECURSIVE_CUES:
                    if cue in context_text:
                        triggered_cue = cue
                        break

                if triggered_cue is not None:
                    if not _is_suppressed(lines, i, "GLOB001"):
                        line_no = i + 1  # 1-indexed
                        findings.append(
                            f"{path}:{line_no}: GLOB001 Suspicious non-recursive glob "
                            f"'{glob_pattern}' — surrounding prose suggests recursion "
                            f"('{triggered_cue}'); use '**/{glob_pattern}' or suppress inline"
                        )

    return findings


def check_count001(path: str, lines: List[str]) -> List[str]:
    """Check for within-document count disagreements (COUNT001)."""
    findings: List[str] = []

    # Skip lines inside code blocks.
    # Use line.strip() for fence detection to handle indented fences correctly.
    # Store the full fence marker (3+ chars) so 4-backtick blocks are closed
    # by a 4-backtick fence and not accidentally by an inner 3-backtick line.
    in_code_block = False
    fence_marker_c: Optional[str] = None
    code_block_lines: set = set()

    for i, line in enumerate(lines):
        lstripped = line.strip()
        if not in_code_block:
            fence_match = _FENCE_RE.match(lstripped)
            if fence_match:
                in_code_block = True
                fence_marker_c = fence_match.group("fence")
                code_block_lines.add(i)
        else:
            code_block_lines.add(i)
            if fence_marker_c and lstripped.startswith(fence_marker_c):
                in_code_block = False

    for i, line in enumerate(lines):
        if i in code_block_lines:
            continue

        m = _COUNT_PHRASE_RE.search(line)
        if not m:
            continue

        stated_n = _parse_number(m.group("n"))
        if stated_n is None:
            continue

        label = m.group("label")

        # Count top-level list items immediately following this line.
        # Rules:
        # - Only the IMMEDIATELY following list is counted: stop if any non-blank,
        #   non-code, non-heading line appears BEFORE the first list item is found.
        # - Once a top-level list starts (base_indent established), only top-level
        #   items (indent == base_indent) are counted; nested/indented lines are
        #   treated as continuation content and are skipped without stopping.
        # - Blank lines between list items do not stop the count.
        # - A heading or unindented non-list line after the list has started stops it.
        actual_count = 0
        found_list = False
        base_indent: Optional[int] = None
        for j in range(i + 1, min(len(lines), i + 1 + COUNT001_WINDOW)):
            if j in code_block_lines:
                continue
            jline = lines[j]
            # Stop counting if we hit a heading (new section)
            if _HEADING_RE.match(jline):
                break
            list_match = _LIST_ITEM_RE.match(jline)
            if list_match:
                indent = len(jline) - len(jline.lstrip(" \t"))
                if base_indent is None:
                    # First list item — establish the top-level indent
                    base_indent = indent
                if indent == base_indent:
                    actual_count += 1
                    found_list = True
                # else: nested bullet — skip without stopping
            elif not found_list and jline.strip():
                # Non-blank, non-list line before any list item found — stop;
                # the list (if any) is not immediately following the count phrase.
                break
            elif found_list and jline.strip() == "":
                # Blank line after list items — could be list continuation, keep going
                pass
            elif found_list and jline.strip() and not list_match:
                # Non-blank, non-list line after the list has started.
                # Indented lines are continuation content; unindented lines end the list.
                if jline[0] in (" ", "\t"):
                    pass  # list-item continuation line — keep going
                else:
                    break

        if not found_list:
            # No list found following the count phrase — skip
            continue

        if actual_count != stated_n:
            if not _is_suppressed(lines, i, "COUNT001"):
                line_no = i + 1  # 1-indexed
                findings.append(
                    f"{path}:{line_no}: COUNT001 Count disagreement — stated "
                    f"'{m.group('n')} {label}' but found {actual_count} items; "
                    f"update the narrative or the list, or suppress inline"
                )

    return findings


def lint_file(path: str) -> List[str]:
    """Run all heuristic checks on one file and return findings."""
    try:
        with open(path, encoding="utf-8") as fh:
            lines = fh.readlines()
    except OSError as exc:
        return [f"{path}:0: ERROR Cannot read file: {exc}"]

    findings: List[str] = []
    findings.extend(check_glob001(path, lines))
    findings.extend(check_count001(path, lines))
    return findings


def main() -> int:
    if len(sys.argv) < 2:
        print("Usage: markdown-heuristic-lint.py <file> [<file> ...]", file=sys.stderr)
        return 1

    all_findings: List[str] = []
    for path in sys.argv[1:]:
        all_findings.extend(lint_file(path))

    for finding in all_findings:
        print(finding)

    if all_findings:
        print(f"\n{len(all_findings)} heuristic finding(s) found.", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
