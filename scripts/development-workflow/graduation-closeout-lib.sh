#!/usr/bin/env bash
#
# graduation-closeout-lib.sh — closeout-only tracker provider helpers.
#
# Kept out of workflow-lib.sh so shared provider resolution stays identical to
# develop for all other callers. Requires workflow-lib.sh to be sourced first
# (workflow_config_provider, workflow_normalize_issue_tracker_provider,
# workflow_repo_root).
#
# Sourced by:
#   - scripts/development-workflow/graduation-closeout.sh
#   - scripts/development-workflow/graduation-closeout-from-merged-pr.sh
#
# This file defines functions only and runs nothing on source.

# graduation_closeout_issue_tracker_provider_in_file <config_file>
# Read issue_tracker.provider under a section header that may carry a trailing
# comment (`issue_tracker: # ...`). Does not change workflow_config_provider.
graduation_closeout_issue_tracker_provider_in_file() {
  local config_file="$1"
  [ -f "$config_file" ] || return 0
  awk '
    function trim(value) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      gsub(/^["'"'"']|["'"'"']$/, "", value)
      return value
    }
    /^issue_tracker:[[:space:]]*(#.*)?$/ { in_section = 1; next }
    in_section && /^[^[:space:]#]/ { exit }
    in_section && /^[[:space:]][[:space:]]provider:[[:space:]]*/ {
      line = $0
      sub(/^[[:space:]]*provider:[[:space:]]*/, "", line)
      sub(/[[:space:]]+#.*$/, "", line)
      print trim(line)
      exit
    }
  ' "$config_file"
}

# graduation_closeout_tracker_provider_raw [repo_root]
# Resolve issue_tracker.provider for graduation closeout.
# - Prefer shared .ai-dev-workflow.yaml via workflow_config_provider (same as
#   post-merge-cleanup; no .ai-dev-workflow.local.yaml).
# - If that is empty, a closeout-local comment-tolerant read may recover
#   provider: linear so Linear safety still applies under commented headers
#   (callers then fail closed when the shared bridge cannot read linear).
# - Non-Linear (github_*, none, other, undeclared) always returns the legacy
#   workflow_config_provider result — never exit 64 — so GitHub closeout stays
#   byte-identical to develop.
graduation_closeout_tracker_provider_raw() {
  local repo_root="${1:-$(workflow_repo_root)}"
  local shared="$repo_root/.ai-dev-workflow.yaml"
  local legacy="" local_raw="" local_norm=""

  [ -f "$shared" ] || return 0

  legacy="$(workflow_config_provider issue_tracker "$shared")"
  if [ -n "$legacy" ]; then
    printf '%s' "$legacy"
    return 0
  fi

  local_raw="$(graduation_closeout_issue_tracker_provider_in_file "$shared")"
  local_norm="$(workflow_normalize_issue_tracker_provider "$local_raw")"
  if [ "$local_norm" = "linear" ]; then
    printf '%s' "$local_raw"
    return 0
  fi

  printf '%s' "$legacy"
  return 0
}

# Compatibility aliases used by existing closeout call sites / docs.
workflow_graduation_closeout_issue_tracker_provider_in_file() {
  graduation_closeout_issue_tracker_provider_in_file "$@"
}

workflow_graduation_closeout_tracker_provider_raw() {
  graduation_closeout_tracker_provider_raw "$@"
}

# ---------------------------------------------------------------------------
# GitHub-provider closeout: GFM render → visible text → shared live refs
#
# Requires closing-keyword-lib.sh (CLOSING_KEYWORD_REGEX, closing_keyword_live_refs)
# and `gh` with markdown API access. Fail closed on render/extract errors —
# callers must not fall back to raw PR text.
# ---------------------------------------------------------------------------

# graduation_closeout_raw_has_closing_keyword_candidate
# stdin: raw markdown. Exit 0 if CLOSING_KEYWORD_REGEX matches (cheap prefilter;
# may hit code examples — still render via GFM before trusting refs).
graduation_closeout_raw_has_closing_keyword_candidate() {
  local raw
  raw="$(cat)"
  [ -n "$raw" ] || return 1
  # Do not use grep -q: under pipefail a quiet early exit SIGPIPEs printf
  # (exit 141) on large bodies and drops a real prose keyword. Consume all
  # input; discard match text.
  printf '%s' "$raw" | grep -iE "$CLOSING_KEYWORD_REGEX" >/dev/null
}

# graduation_closeout_raw_has_epic_or_parent_ref
# stdin: raw markdown. Exit 0 if Epic/Parent #N appears (cheap prefilter).
graduation_closeout_raw_has_epic_or_parent_ref() {
  local raw
  raw="$(cat)"
  [ -n "$raw" ] || return 1
  # Same no-grep -q rule as the closing-keyword prefilter (pipefail / SIGPIPE).
  printf '%s' "$raw" | grep -iE '(^|[^[:alnum:]_])(epic|parent)[[:space:]]*#[0-9]+' >/dev/null
}

# graduation_closeout_html_visible_text
# stdin: HTML from GitHub's markdown API. stdout: visible text outside
# <pre> and <code> (stdlib html.parser). Excluded code/pre runs are replaced
# with a spaced non-matching placeholder so adjacent prose cannot fuse into a
# closing keyword (e.g. Closes <code>other/repo</code>#326). Block boundaries
# become newlines.
graduation_closeout_html_visible_text() {
  python3 -c '
import sys
from html.parser import HTMLParser

class VisibleTextExtractor(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self._parts = []
        self._skip = 0
        self._block = {
            "p", "div", "li", "tr", "ul", "ol", "blockquote",
            "h1", "h2", "h3", "h4", "h5", "h6", "pre", "br",
        }

    def handle_starttag(self, tag, attrs):
        name = tag.lower()
        if name in ("pre", "code"):
            # One placeholder per outermost excluded run — never delete without
            # a boundary (that can join "Closes " to a following "#N").
            if self._skip == 0:
                self._parts.append(" [code] ")
            self._skip += 1
            return
        if self._skip:
            return
        if name == "br" or name in self._block:
            self._parts.append("\n")

    def handle_endtag(self, tag):
        name = tag.lower()
        if name in ("pre", "code"):
            if self._skip:
                self._skip -= 1
            if name == "pre" and self._skip == 0:
                self._parts.append("\n")
            return
        if self._skip:
            return
        if name in self._block and name != "br":
            self._parts.append("\n")

    def handle_data(self, data):
        if self._skip:
            return
        self._parts.append(data)

parser = VisibleTextExtractor()
try:
    parser.feed(sys.stdin.read())
    parser.close()
except Exception:
    sys.exit(1)
sys.stdout.write("".join(parser._parts))
'
}

# graduation_closeout_render_gfm <owner/repo>
# stdin: markdown. stdout: HTML from `gh api markdown` (mode=gfm). Return 1
# when the API call fails or returns empty output.
graduation_closeout_render_gfm() {
  local context="${1:?graduation_closeout_render_gfm requires owner/repo context}"
  local payload html
  local text
  text="$(cat)"
  if ! payload="$(printf '%s' "$text" | python3 -c '
import json, sys
print(json.dumps({"text": sys.stdin.read(), "mode": "gfm", "context": sys.argv[1]}))
' "$context")"; then
    return 1
  fi
  # Capture API failure via if-assignment only — never toggle set -e/+e
  # (that would leak into the caller's shell options).
  if html="$(printf '%s' "$payload" | gh api markdown --input - 2>/dev/null)" \
    && [ -n "$html" ]; then
    printf '%s' "$html"
    return 0
  fi
  return 1
}

# graduation_closeout_github_live_refs_from_markdown <owner/repo>
# stdin: raw PR title or body markdown. Render via GFM, drop <pre>/<code>
# text, then run shared closing_keyword_live_refs. Return 1 on any failure
# (never fall back to scanning raw markdown).
graduation_closeout_github_live_refs_from_markdown() {
  local context="${1:?graduation_closeout_github_live_refs_from_markdown requires owner/repo context}"
  local raw html visible
  raw="$(cat)"
  if ! html="$(printf '%s' "$raw" | graduation_closeout_render_gfm "$context")"; then
    return 1
  fi
  if ! visible="$(printf '%s' "$html" | graduation_closeout_html_visible_text)"; then
    return 1
  fi
  printf '%s' "$visible" | closing_keyword_live_refs
}

# graduation_closeout_github_visible_text_from_markdown <owner/repo>
# Like the live-refs helper but returns the visible text (for epic/parent
# scans). Return 1 on render/extract failure.
graduation_closeout_github_visible_text_from_markdown() {
  local context="${1:?graduation_closeout_github_visible_text_from_markdown requires owner/repo context}"
  local raw html visible
  raw="$(cat)"
  if ! html="$(printf '%s' "$raw" | graduation_closeout_render_gfm "$context")"; then
    return 1
  fi
  if ! visible="$(printf '%s' "$html" | graduation_closeout_html_visible_text)"; then
    return 1
  fi
  printf '%s' "$visible"
  return 0
}
