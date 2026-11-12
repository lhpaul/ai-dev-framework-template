#!/usr/bin/env bash
# outcome-record-revision-check.sh
#
# Read-only check of whether a plan pull request's per-rule outcome record
# names a current revision, per the "When the outcome record's stated revision
# is current" section of
# docs/workflow/development-workflow/plan-authoring-rigor-rules.md (#1820).
#
# The stated revision is current when it is the head itself, or when the head
# is a non-merge commit whose only parent is the stated revision and nothing
# changed between the two except the record's own `Plan revision:` SHA (or
# nothing at all). Every other case is not current.
#
# This helper is a convenience: it applies the canonical condition with git
# alone and never fetches, writes refs, or touches the work tree. Callers must
# make both revisions available locally (for example, fetch the PR head) first.
#
# Output: stable key=value lines (RESULT=, REASON=, STATED=, HEAD=, PARENT=).
# Exit codes: 0 current, 1 not current, 2 usage or tooling error.

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: outcome-record-revision-check.sh --stated <sha> --head <rev> [--repo-root <path>]

  --stated <sha>      Revision the per-rule outcome record names (7-40 hex chars)
  --head <rev>        The plan pull request's current head (commit or ref)
  --repo-root <path>  Repository to inspect (default: current directory)
  --help              Show this help

RESULT=current      REASON=same_head | stamp_lag_no_change | stamp_lag_stamp_only
RESULT=not_current  REASON=missing | malformed | unresolved | not_on_branch |
                           merge_head | more_than_one_push | structural_change |
                           substantive_change
USAGE
}

require_value() {
  if [ "$#" -lt 2 ] || [ -z "${2:-}" ]; then
    printf 'ERROR: missing value for %s\n' "${1:-<unknown>}" >&2
    usage >&2
    exit 2
  fi
}

stated=""
stated_given="false"
head_rev=""
repo_root="."

while [ "$#" -gt 0 ]; do
  case "$1" in
    --stated)
      # An empty stated revision is a missing record marker, which is an
      # outcome (not current), not a usage error.
      if [ "$#" -lt 2 ]; then
        printf 'ERROR: missing value for --stated\n' >&2
        usage >&2
        exit 2
      fi
      stated="$2"
      stated_given="true"
      shift 2
      ;;
    --head)
      require_value "$@"
      head_rev="$2"
      shift 2
      ;;
    --repo-root)
      require_value "$@"
      repo_root="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      printf 'ERROR: unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [ "$stated_given" != "true" ] || [ -z "$head_rev" ]; then
  printf 'ERROR: --stated and --head are required\n' >&2
  usage >&2
  exit 2
fi

if ! git -C "$repo_root" rev-parse --git-dir >/dev/null 2>&1; then
  printf 'ERROR: not a git repository: %s\n' "$repo_root" >&2
  exit 2
fi

head_sha="$(git -C "$repo_root" rev-parse --verify --quiet "${head_rev}^{commit}" 2>/dev/null)" || head_sha=""
if [ -z "$head_sha" ]; then
  printf 'ERROR: head revision does not resolve to a local commit: %s\n' "$head_rev" >&2
  exit 2
fi

emit() {
  # emit <result> <reason> <stated_sha> <parent_sha>
  printf 'RESULT=%s\n' "$1"
  printf 'REASON=%s\n' "$2"
  printf 'STATED=%s\n' "$3"
  printf 'HEAD=%s\n' "$head_sha"
  printf 'PARENT=%s\n' "$4"
}

not_current() {
  emit "not_current" "$1" "${2:-}" "${3:-}"
  exit 1
}

# Strip surrounding whitespace and Markdown code-span backticks a reader may
# have copied along with the SHA.
stated_clean="$(printf '%s' "$stated" | tr -d '`[:space:]')"

if [ -z "$stated_clean" ]; then
  not_current "missing"
fi

if ! printf '%s\n' "$stated_clean" | grep -Eq '^[0-9a-fA-F]{7,40}$'; then
  not_current "malformed"
fi

stated_sha="$(git -C "$repo_root" rev-parse --verify --quiet "${stated_clean}^{commit}" 2>/dev/null)" || stated_sha=""
if [ -z "$stated_sha" ]; then
  not_current "unresolved"
fi

if [ "$stated_sha" = "$head_sha" ]; then
  emit "current" "same_head" "$stated_sha" ""
  exit 0
fi

if ! git -C "$repo_root" merge-base --is-ancestor "$stated_sha" "$head_sha" 2>/dev/null; then
  not_current "not_on_branch" "$stated_sha"
fi

# `rev-list --parents -n 1 <head>` prints the head followed by its parents.
parent_line="$(git -C "$repo_root" rev-list --parents -n 1 "$head_sha")"
# shellcheck disable=SC2086 # deliberate word split of SHA list
set -- $parent_line
parent_count=$(($# - 1))
if [ "$parent_count" -gt 1 ]; then
  not_current "merge_head" "$stated_sha"
fi
parent_sha="${2:-}"
if [ "$parent_sha" != "$stated_sha" ]; then
  not_current "more_than_one_push" "$stated_sha" "$parent_sha"
fi

# Added, deleted, renamed, copied, mode-changed, or binary files are never a
# stamp-only change.
summary="$(git -C "$repo_root" diff --no-ext-diff --summary "$stated_sha" "$head_sha")"
if [ -n "$summary" ]; then
  not_current "structural_change" "$stated_sha" "$parent_sha"
fi
if git -C "$repo_root" diff --no-ext-diff --numstat "$stated_sha" "$head_sha" | grep -q '^-'; then
  not_current "structural_change" "$stated_sha" "$parent_sha"
fi

if git -C "$repo_root" diff --no-ext-diff --quiet "$stated_sha" "$head_sha"; then
  emit "current" "stamp_lag_no_change" "$stated_sha" "$parent_sha"
  exit 0
fi

# Every changed line must be a `Plan revision:` line, and the removed and added
# lines of each file must be identical once hex SHA tokens are normalized, so
# that only the SHA itself changed.
diff_text="$(git -C "$repo_root" diff --no-ext-diff --no-color --no-textconv -U0 "$stated_sha" "$head_sha")"
verdict="$(printf '%s\n' "$diff_text" | awk '
  function norm(s) {
    # Seven or more hex characters; spelled out because mawk lacks {m,n}.
    gsub(/[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]+/, "<sha>", s)
    return s
  }
  /^diff --git / { next }
  /^index / { next }
  /^--- / { next }
  /^\+\+\+ / { file = substr($0, 5); next }
  /^@@/ { next }
  /^[+-]/ {
    sign = substr($0, 1, 1)
    body = substr($0, 2)
    if (body !~ /^[ \t]*(\*\*)?Plan revision:(\*\*)?[ \t]/) { bad = 1; exit }
    key = file "\034" norm(body)
    if (sign == "-") { removed[key]++ } else { added[key]++ }
    changed = 1
    next
  }
  END {
    if (bad) { print "substantive"; exit }
    if (!changed) { print "substantive"; exit }
    for (k in removed) { if (removed[k] != added[k]) { print "substantive"; exit } }
    for (k in added) { if (added[k] != removed[k]) { print "substantive"; exit } }
    print "stamp_only"
  }
')"

if [ "$verdict" = "stamp_only" ]; then
  emit "current" "stamp_lag_stamp_only" "$stated_sha" "$parent_sha"
  exit 0
fi

not_current "substantive_change" "$stated_sha" "$parent_sha"
