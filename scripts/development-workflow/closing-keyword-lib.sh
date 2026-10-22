#!/usr/bin/env bash
#
# closing-keyword-lib.sh — the canonical closing-keyword reading, in one place.
#
# `strip_fenced_pr_body_blocks` was moved here verbatim from
# post-merge-cleanup.sh, which now sources this file. It is a move, not a
# rewrite: post-merge cleanup decides what actually gets closed, and any
# divergence between that decision and a validation of it would make the
# validation worse than useless. Two copies would drift; one cannot.
#
# Sourced by:
#   - scripts/development-workflow/post-merge-cleanup.sh
#   - scripts/development-workflow/validate-closing-keyword-scope.sh
#
# This file defines functions only and runs nothing on source.

# strip_fenced_pr_body_blocks
# Removes quoted/example PR body text from stdin before it is scanned for
# closing keywords, so an example like "Closes #999" inside a code sample,
# inline code span, or blockquote is not treated as a live closing reference.
# Handles both backtick (```) and tilde (~~~) fence styles, and treats an
# unclosed opening fence as extending to end of input (rather than leaving the
# rest of the body unfiltered). Matches GitHub-Flavored Markdown's
# fence-matching rule: a closing fence must use the same character as the
# opening fence, be at least as long, and have nothing but trailing whitespace
# after the fence marker — a shorter, differently-charactered, or
# content-suffixed line (e.g. a nested example fence, or "``` end of block") is
# treated as still being inside the fence rather than closing it. A fence
# delimiter may be indented up to 3 spaces per GFM; 4+ spaces of leading
# whitespace makes it indented code instead, so the raw line (not a fully
# whitespace-stripped line) is matched to preserve that boundary — otherwise a
# 4-space-indented "```" could be mistaken for a real fence and hide a live
# closing reference.
strip_fenced_pr_body_blocks() {
  python3 -c '
import re, sys

def strip_inline_code_spans(line):
    out = []
    i = 0
    while i < len(line):
        if line[i] != "`":
            out.append(line[i])
            i += 1
            continue
        j = i
        while j < len(line) and line[j] == "`":
            j += 1
        ticks = line[i:j]
        closing = line.find(ticks, j)
        if closing == -1:
            out.append(line[i])
            i += 1
            continue
        i = closing + len(ticks)
    return "".join(out)

def strip_inline_code_spans_by_paragraph(lines):
    out_lines = []
    paragraph = []
    for line in lines:
        if line.strip() == "":
            if paragraph:
                out_lines.extend(strip_inline_code_spans("\n".join(paragraph)).split("\n"))
                paragraph = []
            out_lines.append(line)
        else:
            paragraph.append(line)
    if paragraph:
        out_lines.extend(strip_inline_code_spans("\n".join(paragraph)).split("\n"))
    return "\n".join(out_lines)

lines = sys.stdin.read().split("\n")
out = []
fence_char = None
fence_len = 0
fence_re = re.compile(r"^ {0,3}(`{3,}|~{3,})(.*)$")
for line in lines:
    match = fence_re.match(line)
    if fence_char is None:
        if match:
            fence_char = match.group(1)[0]
            fence_len = len(match.group(1))
            continue
        if re.match(r"^\s*>", line):
            continue
        out.append(line)
    else:
        if (match and match.group(1)[0] == fence_char
                and len(match.group(1)) >= fence_len
                and match.group(2).strip() == ""):
            fence_char = None
            fence_len = 0
        continue
sys.stdout.write(strip_inline_code_spans_by_paragraph(out))
'
}

# The canonical closing-keyword pattern, in one place.
#
# This is the literal that lived inline in fetch_pr_closing_issues; that
# function now uses this constant, so the validator and the cleanup cannot
# disagree about what a closing reference is. Changing this changes what gets
# closed, which is why it has a name.
#
# A non-word character is required before the keyword (start of string counts),
# so "disclose #12" and "hotfix #12" are not closing references while
# "(Fixes #12)" is.
CLOSING_KEYWORD_REGEX='(^|[^[:alnum:]_])(close[sd]?|fix(es|ed)?|resolve[sd]?)[[:space:]]+(issue[[:space:]]+)?#[0-9]+'

# Identity of this feature's report comment. The trailing space is part of the
# prefix and is what terminates the version: without it the prefix also matches
# "<!-- closing-keyword-scope:v10 ...", and a future v10 report would be
# adopted, updated, or deleted as a v1 duplicate.
# shellcheck disable=SC2034  # consumed by validate-closing-keyword-scope.sh
CLOSING_KEYWORD_SCOPE_MARKER_PREFIX='<!-- closing-keyword-scope:v1 '

# Fixed identity of this feature's check run.
# shellcheck disable=SC2034  # consumed by validate-closing-keyword-scope.sh
CLOSING_KEYWORD_SCOPE_CHECK_NAME='Closing-keyword scope'
# shellcheck disable=SC2034  # consumed by validate-closing-keyword-scope.sh
CLOSING_KEYWORD_SCOPE_CHECK_EXTERNAL_ID='closing-keyword-scope:v1'

# closing_keyword_scope_started_at
# The ordering stamp's time component: this run's own clock, read once at
# start. Not GITHUB_RUN_ID, which GitHub documents as unique and not
# chronological, and not a workflow context field — none supplies a
# millisecond timestamp.
#
# python3 rather than `date`: macOS `date` has no sub-second format, and
# python3 is already a hard dependency of this file. Fixed width, so string
# comparison is chronological comparison.
#
# It is a function so tests can redefine it after sourcing, which is how the
# equal-timestamp cases are made deterministic.
closing_keyword_scope_started_at() {
  python3 -c 'import datetime; print(datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z")'
}

# closing_keyword_live_refs
# Reads text on stdin, filters it with the canonical filter, and echoes the
# issue numbers of every live closing reference — one per line, in order,
# NOT deduplicated.
#
# The multiset matters. fetch_pr_closing_issues ends in `sort -un` because it
# only needs to know *which* issues to close; attribution needs to know how
# many references survived, so that an issue named live in both the title and
# the description can be told apart from one named only in the title.
#
# Returns 1 without echoing if the filter or a scan stage failed, so a failure
# is never read as "no closing keywords". A scan that simply found nothing
# returns 0 with empty output. Each grep stage is run separately and its status
# captured directly: under `pipefail` a two-stage pipeline reports only the
# rightmost non-zero exit, so a real error in the first grep can be masked by
# the second grep's ordinary "no match" on its now-empty input.
closing_keyword_live_refs() {
  local raw filtered keyword_lines refs stage_status
  raw="$(cat)"
  if ! filtered="$(printf '%s' "$raw" | strip_fenced_pr_body_blocks)"; then
    echo "ERROR: could not strip fenced blocks while reading closing references." >&2
    return 1
  fi
  set +e
  keyword_lines="$(printf '%s' "$filtered" | grep -ioE "$CLOSING_KEYWORD_REGEX")"
  stage_status=$?
  set -e
  if [ "$stage_status" -gt 1 ]; then
    echo "ERROR: failed to scan text for closing keywords (grep exit ${stage_status})." >&2
    return 1
  fi
  if [ "$stage_status" -eq 1 ] || [ -z "$keyword_lines" ]; then
    return 0
  fi
  set +e
  refs="$(printf '%s' "$keyword_lines" | grep -oE '[0-9]+$')"
  stage_status=$?
  set -e
  if [ "$stage_status" -gt 1 ]; then
    echo "ERROR: failed to extract issue numbers from closing-keyword matches (grep exit ${stage_status})." >&2
    return 1
  fi
  if [ "$stage_status" -eq 1 ] || [ -z "$refs" ]; then
    return 0
  fi
  printf '%s\n' "$refs"
  return 0
}

# strip_markdown_code_for_closeout
# Opt-in filter for graduation closeout GitHub-provider paths only. Applies the
# shared strip_fenced_pr_body_blocks filter, then drops CommonMark-style indented
# code blocks without removing list/paragraph prose. Prefer keeping prose.
#
# Supported CommonMark subset (closeout-only; not a full parser):
# - Top-level fences: strip_fenced_pr_body_blocks first (indent 0–3 absolute).
# - In-list fences: opener/closer (``` or ~~~, length ≥3, same char; closer
#   length ≥ opener, trailing whitespace only) whose indent relative to the
#   current list item's content_indent is 0–3 columns; strip until matching
#   closer or EOF (unclosed). Shared filter ignores these (absolute indent ≥4).
# - Indented code (tab stops of 4): outside lists, a run with indent ≥4 that
#   starts after a blank / document start / ATX heading / setext underline /
#   thematic break (or continues a prior code line).
# - Lists: marker indent 0–3 starts list context. content_indent = marker indent
#   + marker width + following spaces (1–4; if more than 4, padding is 1).
#   Inside a list item, indent ≥ content_indent+4 after a blank (or continuing
#   code) is indented code; indent < content_indent+4 stays prose. Nested list
#   markers (indent < content_indent+4) update content_indent. List ends on an
#   indent-0 non-marker after a blank, or on thematic / ATX / setext.
# - ATX headings (#{1,6} + space/end, indent 0–3) and setext underlines
#   (=== / --- under a paragraph line) are block boundaries: the next ≥4-indent
#   line may start indented code without a blank. After a paragraph, --- is
#   setext (not a thematic break); thematic breaks still match - - - / *** / etc.
#
# Do not use this from post-merge cleanup or validate-closing-keyword-scope —
# those consumers keep strip_fenced_pr_body_blocks / closing_keyword_live_refs.
strip_markdown_code_for_closeout() {
  local staged
  if ! staged="$(strip_fenced_pr_body_blocks)"; then
    return 1
  fi
  printf '%s' "$staged" | python3 -c '
import re, sys

def leading_indent_columns(line):
    col = 0
    i = 0
    while i < len(line):
        ch = line[i]
        if ch == " ":
            col += 1
            i += 1
        elif ch == "\t":
            col = (col // 4 + 1) * 4
            i += 1
        else:
            break
    return col, i

THEMATIC_BREAK_RE = re.compile(r"^([-*_])(?:[ \t]*\1){2,}[ \t]*$")
LIST_MARKER_RE = re.compile(r"^([-*+]|\d+[.)])([ \t]+|$)")
ATX_HEADING_RE = re.compile(r"^#{1,6}(?:[ \t]+|$)")
SETEXT_RE = re.compile(r"^(?:=+|-+)[ \t]*$")
FENCE_MARKER_RE = re.compile(r"^(`{3,}|~{3,})(.*)$")

def list_item_content_indent(line):
    """Return content_indent for a list-marker line, or None."""
    cols, start = leading_indent_columns(line)
    m = LIST_MARKER_RE.match(line[start:])
    if not m:
        return None
    marker = m.group(1)
    rest = line[start + len(marker):]
    spaces = 0
    for ch in rest:
        if ch == " ":
            spaces += 1
        else:
            break
    if spaces == 0:
        padding = 1
    elif spaces <= 4:
        padding = spaces
    else:
        padding = 1
    return cols + len(marker) + padding

def is_thematic_break_body(body):
    return THEMATIC_BREAK_RE.match(body) is not None

def is_setext_underline_body(body):
    return SETEXT_RE.match(body) is not None

def is_atx_heading_body(body):
    return ATX_HEADING_RE.match(body) is not None

def list_relative_fence(line, content_indent):
    """Fence opener/closer info if indent is content_indent..content_indent+3."""
    cols, start = leading_indent_columns(line)
    rel = cols - content_indent
    if rel < 0 or rel > 3:
        return None
    m = FENCE_MARKER_RE.match(line[start:])
    if not m:
        return None
    marker = m.group(1)
    return marker[0], len(marker), m.group(2)

lines = sys.stdin.read().split("\n")
out = []
in_list = False
content_indent = 0
in_indented_code = False
at_block_start = True
prev_was_paragraph = False
in_list_fence = False
list_fence_char = None
list_fence_len = 0
for line in lines:
    if in_list_fence:
        info = list_relative_fence(line, content_indent) if in_list else None
        if (info is not None
                and info[0] == list_fence_char
                and info[1] >= list_fence_len
                and info[2].strip() == ""):
            in_list_fence = False
            list_fence_char = None
            list_fence_len = 0
            in_indented_code = False
            at_block_start = True
            prev_was_paragraph = False
        continue

    if line.strip() == "":
        out.append(line)
        at_block_start = True
        in_indented_code = False
        prev_was_paragraph = False
        continue

    cols, start = leading_indent_columns(line)
    body = line[start:]

    # Setext underline ends the preceding paragraph (--- after prose ≠ thematic).
    if prev_was_paragraph and cols < 4 and is_setext_underline_body(body):
        in_list = False
        content_indent = 0
        in_indented_code = False
        at_block_start = True
        prev_was_paragraph = False
        out.append(line)
        continue

    if cols < 4 and is_thematic_break_body(body):
        in_list = False
        content_indent = 0
        in_indented_code = False
        at_block_start = True
        prev_was_paragraph = False
        out.append(line)
        continue

    if cols < 4 and is_atx_heading_body(body):
        in_list = False
        content_indent = 0
        in_indented_code = False
        at_block_start = True
        prev_was_paragraph = False
        out.append(line)
        continue

    if in_list:
        fence = list_relative_fence(line, content_indent)
        if fence is not None:
            in_list_fence = True
            list_fence_char, list_fence_len = fence[0], fence[1]
            in_indented_code = False
            at_block_start = False
            prev_was_paragraph = False
            continue
        code_threshold = content_indent + 4
        marker_ci = list_item_content_indent(line)
        if marker_ci is not None and cols < code_threshold:
            content_indent = marker_ci
            in_indented_code = False
            at_block_start = False
            prev_was_paragraph = True
            out.append(line)
            continue
        if cols >= code_threshold and (at_block_start or in_indented_code):
            in_indented_code = True
            at_block_start = False
            prev_was_paragraph = False
            continue
        if cols == 0 and at_block_start:
            in_list = False
            content_indent = 0
            # fall through — reclassify as outside-list line
        else:
            out.append(line)
            at_block_start = False
            in_indented_code = False
            prev_was_paragraph = True
            continue

    marker_ci = list_item_content_indent(line)
    if marker_ci is not None and cols < 4:
        in_list = True
        content_indent = marker_ci
        in_indented_code = False
        at_block_start = False
        prev_was_paragraph = True
        out.append(line)
        continue

    if cols >= 4 and (at_block_start or in_indented_code):
        in_indented_code = True
        at_block_start = False
        prev_was_paragraph = False
        continue

    out.append(line)
    at_block_start = False
    in_indented_code = False
    prev_was_paragraph = True
sys.stdout.write("\n".join(out))
'
}

# closing_keyword_live_refs_for_closeout
# Same contract as closing_keyword_live_refs, but uses
# strip_markdown_code_for_closeout. Graduation closeout GitHub providers only.
closing_keyword_live_refs_for_closeout() {
  local raw filtered keyword_lines refs stage_status
  raw="$(cat)"
  if ! filtered="$(printf '%s' "$raw" | strip_markdown_code_for_closeout)"; then
    echo "ERROR: could not strip markdown code while reading closing references." >&2
    return 1
  fi
  set +e
  keyword_lines="$(printf '%s' "$filtered" | grep -ioE "$CLOSING_KEYWORD_REGEX")"
  stage_status=$?
  set -e
  if [ "$stage_status" -gt 1 ]; then
    echo "ERROR: failed to scan text for closing keywords (grep exit ${stage_status})." >&2
    return 1
  fi
  if [ "$stage_status" -eq 1 ] || [ -z "$keyword_lines" ]; then
    return 0
  fi
  set +e
  refs="$(printf '%s' "$keyword_lines" | grep -oE '[0-9]+$')"
  stage_status=$?
  set -e
  if [ "$stage_status" -gt 1 ]; then
    echo "ERROR: failed to extract issue numbers from closing-keyword matches (grep exit ${stage_status})." >&2
    return 1
  fi
  if [ "$stage_status" -eq 1 ] || [ -z "$refs" ]; then
    return 0
  fi
  printf '%s\n' "$refs"
  return 0
}

# closing_keyword_mangle
# Reads text on stdin and echoes it with the first letter of every
# closing-keyword token replaced by "Z": Closes -> Zloses, fixes -> Zixes,
# resolved -> Zesolved. None of those is a keyword, and the substitution is
# length-preserving, so every byte offset, fence delimiter and inline-code span
# in the surrounding text is unchanged — which is the whole point. The filter
# must make byte-for-byte identical suppression decisions on the mangled text,
# or the difference between the two runs would not mean what attribution needs
# it to mean.
#
# Only the keyword itself is touched; the "#NNN" is left alone so the reference
# stays visible to a human reading a debug dump.
closing_keyword_mangle() {
  python3 -c '
import re, sys

# The canonical pattern, transliterated: POSIX [[:alnum:]_] and [[:space:]]
# written out, so this matches exactly what the grep stage matches.
PATTERN = re.compile(
    r"(^|[^A-Za-z0-9_])(close[sd]?|fix(?:es|ed)?|resolve[sd]?)([ \t\n\r\f\v]+)((?:issue[ \t\n\r\f\v]+)?#[0-9]+)",
    re.IGNORECASE,
)

def mangle(match):
    keyword = match.group(2)
    return match.group(1) + "Z" + keyword[1:] + match.group(3) + match.group(4)

sys.stdout.write(PATTERN.sub(mangle, sys.stdin.read()))
'
}
