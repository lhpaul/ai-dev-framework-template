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
# Opt-in filter for graduation closeout GitHub-provider paths only. One
# line-by-line state machine (fence state has absolute precedence), then the
# shared strip_fenced_pr_body_blocks filter for blockquotes/inline (and any
# residual top-level fences). Prefer keeping prose over stripping.
#
# Supported CommonMark subset (closeout-only; not a full parser):
# - Tab expansion (first): every line's leading whitespace, and whitespace
#   immediately after a list marker, is expanded to spaces with tab stops of 4
#   before any other parsing, so indentation/list/fence logic sees only spaces.
# - Fences (``` / ~~~, length ≥3, same char; closer length ≥ opener, trailing
#   whitespace only): while inside a fence, only look for the matching closer
#   (indent 0–3 relative to the fence's container indent) and drop every other
#   line — never interpret list markers, headings, thematic breaks, or
#   indentation inside a fence. Openers: top-level at absolute indent 0–3;
#   list-relative at content_indent+0..3; or on a list-marker line remainder.
#   Content inside fences never changes list context. Closing a top-level fence
#   restores the list context saved when it opened. Unclosed → EOF.
# - List stack: each list item is a container with content_indent. Document is
#   the root (content_indent 0). On each non-blank line, pop containers whose
#   content_indent > line indent when the line exits the item (dedent restores
#   the parent). Lazy paragraph continuation is the exception: a non-blank line
#   with indent < content_indent that directly follows a paragraph line (no
#   blank) and is not a list marker, ATX heading, thematic break, or fence
#   opener does NOT pop — it stays in the current item. Pop after a blank when
#   indent < content_indent, or on a marker/heading/thematic/fence that exits.
#   A list marker at indent in [parent_content_indent, parent_content_indent+3]
#   pushes a new item (dedent makes siblings replace the top). content_indent =
#   marker indent + marker width + following spaces (1–4; if more than 4,
#   padding is 1 and content_indent = marker_end + 1). When the marker is
#   followed by ≥5 spaces, the remainder begins ≥4 columns past content_indent
#   and is an indented code block inside the item (do not emit it); further
#   lines at ≥ content_indent+4 stay code. An ATX heading on the marker-line
#   remainder is the item's first block (block boundary), so a following line
#   at ≥ content_indent+4 starts indented code.
# - Headings / thematic / setext / fences / indented code are evaluated relative
#   to the current container's content_indent. A heading inside an item does not
#   clear the stack — only a block boundary within that container. Indented code
#   is cols ≥ content_indent+4 after a blank (or continuing code), even if the
#   line looks like a list marker. Paragraph continuation (no blank) at ≥
#   content_indent+4 stays prose.
#
# Do not use this from post-merge cleanup or validate-closing-keyword-scope —
# those consumers keep strip_fenced_pr_body_blocks / closing_keyword_live_refs.
strip_markdown_code_for_closeout() {
  local staged
  if ! staged="$(python3 -c '
import re, sys

THEMATIC_BREAK_RE = re.compile(r"^([-*_])(?:[ \t]*\1){2,}[ \t]*$")
LIST_MARKER_ONLY_RE = re.compile(r"^([-*+]|\d+[.)])")
LIST_MARKER_RE = re.compile(r"^([-*+]|\d+[.)])( +|$)")
ATX_HEADING_RE = re.compile(r"^#{1,6}(?:[ \t]+|$)")
SETEXT_RE = re.compile(r"^(?:=+|-+)[ \t]*$")
FENCE_MARKER_RE = re.compile(r"^(`{3,}|~{3,})(.*)$")

def expand_tabs_closeout(line):
    """Expand tabs in leading whitespace and list-marker padding (tab stop 4)."""
    out = []
    col = 0
    i = 0
    n = len(line)

    def emit_ws_run():
        nonlocal col, i
        while i < n and line[i] in " \t":
            if line[i] == " ":
                out.append(" ")
                col += 1
            else:
                add = 4 - (col % 4)
                out.append(" " * add)
                col += add
            i += 1

    emit_ws_run()
    if i >= n:
        return "".join(out)
    m = LIST_MARKER_ONLY_RE.match(line[i:])
    if not m:
        out.append(line[i:])
        return "".join(out)
    marker = m.group(1)
    out.append(marker)
    col += len(marker)
    i += len(marker)
    emit_ws_run()
    out.append(line[i:])
    return "".join(out)

def leading_indent_columns(line):
    # Tabs already expanded; count leading spaces only.
    i = 0
    while i < len(line) and line[i] == " ":
        i += 1
    return i, i

def list_marker_parts(line):
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
        content_start = 0
    elif spaces <= 4:
        padding = spaces
        content_start = spaces
    else:
        padding = 1
        content_start = 1
    return cols + len(marker) + padding, rest[content_start:]

def fence_info_from_content(text):
    m = FENCE_MARKER_RE.match(text)
    if not m:
        return None
    marker = m.group(1)
    return marker[0], len(marker), m.group(2)

def fence_at_container(line, container_indent):
    cols, start = leading_indent_columns(line)
    rel = cols - container_indent
    if rel < 0 or rel > 3:
        return None
    return fence_info_from_content(line[start:])

def is_thematic_break_body(body):
    return THEMATIC_BREAK_RE.match(body) is not None

def is_setext_underline_body(body):
    return SETEXT_RE.match(body) is not None

def is_atx_heading_body(body):
    return ATX_HEADING_RE.match(body) is not None

lines = [expand_tabs_closeout(line) for line in sys.stdin.read().split("\n")]
out = []
# Stack of list-item content_indents; document root is implicit (0).
stack = []
in_indented_code = False
at_block_start = True
prev_was_paragraph = False
in_fence = False
fence_kind = None  # "top" | "list"
fence_char = None
fence_len = 0
fence_container_indent = 0
fence_saved_stack = None

def current_ci():
    return stack[-1] if stack else 0

def open_fence(kind, char, length, container_indent):
    global in_fence, fence_kind, fence_char, fence_len, fence_container_indent
    global fence_saved_stack, in_indented_code, at_block_start, prev_was_paragraph
    if kind == "top":
        fence_saved_stack = list(stack)
    in_fence = True
    fence_kind = kind
    fence_char = char
    fence_len = length
    fence_container_indent = container_indent
    in_indented_code = False
    at_block_start = False
    prev_was_paragraph = False

def rel_in_container(cols, ci):
    rel = cols - ci
    return 0 <= rel <= 3

def is_structural_exit_body(body):
    """True when the line body starts a block that exits lazy continuation."""
    if LIST_MARKER_RE.match(body) is not None:
        return True
    if is_atx_heading_body(body):
        return True
    if is_thematic_break_body(body):
        return True
    if fence_info_from_content(body) is not None:
        return True
    return False

for line in lines:
    # (1) Inside a fence: only matching closer; never interpret structure.
    if in_fence:
        info = fence_at_container(line, fence_container_indent)
        if (info is not None
                and info[0] == fence_char
                and info[1] >= fence_len
                and info[2].strip() == ""):
            if fence_kind == "top" and fence_saved_stack is not None:
                stack[:] = fence_saved_stack
                fence_saved_stack = None
            in_fence = False
            fence_kind = None
            fence_char = None
            fence_len = 0
            fence_container_indent = 0
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

    # Dedent: pop when the line exits the item. Lazy paragraph continuation
    # (follows a paragraph with no blank, indent < content_indent, not a
    # marker/heading/thematic/fence) keeps the current container.
    ci = current_ci()
    if stack and cols < ci:
        lazy = prev_was_paragraph and not is_structural_exit_body(body)
        if not lazy:
            while stack and stack[-1] > cols:
                stack.pop()
            ci = current_ci()
    # else: stay at current ci (including lazy continuation)

    # Block boundaries relative to the current container (do not clear stack).
    if prev_was_paragraph and rel_in_container(cols, ci) and is_setext_underline_body(body):
        in_indented_code = False
        at_block_start = True
        prev_was_paragraph = False
        out.append(line)
        continue

    if rel_in_container(cols, ci) and is_thematic_break_body(body):
        in_indented_code = False
        at_block_start = True
        prev_was_paragraph = False
        out.append(line)
        continue

    if rel_in_container(cols, ci) and is_atx_heading_body(body):
        in_indented_code = False
        at_block_start = True
        prev_was_paragraph = False
        out.append(line)
        continue

    # (2) Fence openers relative to current container.
    fence = fence_at_container(line, ci)
    if fence is not None:
        kind = "list" if stack else "top"
        open_fence(kind, fence[0], fence[1], ci)
        continue

    # List marker in [parent_ci, parent_ci+3] pushes a new item.
    parts = list_marker_parts(line)
    if parts is not None and ci <= cols <= ci + 3:
        new_ci, remainder = parts
        stack.append(new_ci)
        in_indented_code = False
        at_block_start = False
        fence = fence_info_from_content(remainder)
        if fence is not None:
            open_fence("list", fence[0], fence[1], new_ci)
            continue
        # ≥5 spaces after marker → remainder starts at content_indent+4: code.
        rem_lead = 0
        while rem_lead < len(remainder) and remainder[rem_lead] == " ":
            rem_lead += 1
        if rem_lead >= 4:
            in_indented_code = True
            at_block_start = False
            prev_was_paragraph = False
            continue
        # ATX heading as first block → block boundary (next ≥ci+4 is code).
        if is_atx_heading_body(remainder):
            in_indented_code = False
            at_block_start = True
            prev_was_paragraph = False
            out.append(line)
            continue
        if is_thematic_break_body(remainder):
            in_indented_code = False
            at_block_start = True
            prev_was_paragraph = False
            out.append(line)
            continue
        prev_was_paragraph = True
        out.append(line)
        continue

    # Document-level fence when still at root (ci==0) and absolute indent 0–3
    # was already handled via fence_at_container(line, 0). Nothing more here.

    # (3) Indented code relative to current container, else prose.
    code_threshold = ci + 4
    if cols >= code_threshold and (at_block_start or in_indented_code):
        in_indented_code = True
        at_block_start = False
        prev_was_paragraph = False
        continue

    out.append(line)
    at_block_start = False
    in_indented_code = False
    prev_was_paragraph = True
sys.stdout.write("\n".join(out))
')"; then
    return 1
  fi
  # Blockquotes + inline code spans (shared); fences already handled above.
  printf '%s' "$staged" | strip_fenced_pr_body_blocks
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
