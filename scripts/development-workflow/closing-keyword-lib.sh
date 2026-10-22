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
