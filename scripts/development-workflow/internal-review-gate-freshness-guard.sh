#!/usr/bin/env bash
# internal-review-gate-freshness-guard.sh - refuse PR readiness when the
# internal review gate's (Step 7a) approved commit is stale against HEAD.
#
# The internal review gate's verdict binds to the commit it reviewed, not to
# the branch. A later non-mechanical commit invalidates that verdict even if
# the automated reviewer loop (Step 7) reports clean at the new HEAD — the
# reviewer loop validates the PR branch, it does not replace the pre-PR
# review gate (see REVIEW.md). This guard is the mechanical check: it
# compares the gate-evidence commit SHA (recorded in the Step 7a summary
# comment) against the current HEAD SHA and refuses readiness on any
# mismatch unless the delta is explicitly classified mechanical.

set -euo pipefail

GATE_SHA=""
HEAD_SHA=""
REPO_ROOT="$(pwd)"
MAX_MECHANICAL_LINES=10

usage() {
  cat <<'USAGE'
Usage:
  internal-review-gate-freshness-guard.sh --gate-sha <sha> --head-sha <sha> [--repo-root <path>] [--max-mechanical-lines <n>]

Compares the internal review gate's evidence commit SHA (the commit Step 7a
last approved, from the "Step 7a Internal Review Gate Summary" PR comment)
against the current PR HEAD SHA.

Refuses readiness on any mismatch unless BOTH:
  1. Every commit in the gate_sha..head_sha range carries the literal marker
     `MECHANICAL_DELTA:` in its commit message.
  2. The cumulative diff (insertions + deletions) between gate_sha and
     head_sha is at or below --max-mechanical-lines (default 10).

This mirrors the Trivial-fix skip rule's non-structural / <=10-line bound
(91-orchestrate-work-protocol.md) so both checks apply the same bar for what
counts as mechanical.

Prints stable key=value lines:
  RESULT=pass|refused
  REASON=fresh|mechanical_delta_verified|stale_gate_evidence|gate_sha_not_ancestor|invalid_input|git_error
  GATE_SHA=<resolved sha, or as-supplied on invalid_input>
  HEAD_SHA=<resolved sha, or as-supplied on invalid_input>
  LINES_CHANGED=<n, blank when not computed>
  MARKER_PRESENT=true|false
  HUMAN_ACTION=<guidance>

Exit codes: 0 = pass, 1 = refused, 64 = invalid input, 2 = git/internal error.
USAGE
}

die_usage() {
  printf 'ERROR: %s\n' "$*" >&2
  usage >&2
  exit 64
}

require_value() {
  if [ "$#" -lt 2 ] || [ -z "${2:-}" ] || [ "${2#--}" != "$2" ]; then
    die_usage "$1 requires a value"
  fi
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --gate-sha)
      require_value "$@"
      GATE_SHA="$2"
      shift 2
      ;;
    --head-sha)
      require_value "$@"
      HEAD_SHA="$2"
      shift 2
      ;;
    --repo-root)
      require_value "$@"
      REPO_ROOT="$2"
      shift 2
      ;;
    --max-mechanical-lines)
      require_value "$@"
      MAX_MECHANICAL_LINES="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die_usage "unknown argument: $1"
      ;;
  esac
done

[ -n "$GATE_SHA" ] || die_usage "--gate-sha is required"
[ -n "$HEAD_SHA" ] || die_usage "--head-sha is required"
case "$MAX_MECHANICAL_LINES" in
  ''|*[!0-9]*) die_usage "--max-mechanical-lines must be a non-negative integer" ;;
esac

emit_invalid_input() {
  local reason="$1"
  printf 'RESULT=refused\nREASON=invalid_input\nGATE_SHA=%s\nHEAD_SHA=%s\nLINES_CHANGED=\nMARKER_PRESENT=false\nHUMAN_ACTION=%s\n' \
    "$GATE_SHA" "$HEAD_SHA" "$reason"
}

if ! cd "$REPO_ROOT" 2>/dev/null; then
  emit_invalid_input "--repo-root $REPO_ROOT is not accessible"
  exit 64
fi

resolved_gate_sha=""
if ! resolved_gate_sha="$(git rev-parse --verify "${GATE_SHA}^{commit}" 2>/dev/null)"; then
  emit_invalid_input "gate SHA $GATE_SHA could not be resolved in this repository; confirm the Step 7a summary comment cites a real commit"
  exit 64
fi

resolved_head_sha=""
if ! resolved_head_sha="$(git rev-parse --verify "${HEAD_SHA}^{commit}" 2>/dev/null)"; then
  emit_invalid_input "HEAD SHA $HEAD_SHA could not be resolved in this repository"
  exit 64
fi

if [ "$resolved_gate_sha" = "$resolved_head_sha" ]; then
  printf 'RESULT=pass\nREASON=fresh\nGATE_SHA=%s\nHEAD_SHA=%s\nLINES_CHANGED=0\nMARKER_PRESENT=false\nHUMAN_ACTION=none\n' \
    "$resolved_gate_sha" "$resolved_head_sha"
  exit 0
fi

if ! git merge-base --is-ancestor "$resolved_gate_sha" "$resolved_head_sha" 2>/dev/null; then
  printf 'RESULT=refused\nREASON=gate_sha_not_ancestor\nGATE_SHA=%s\nHEAD_SHA=%s\nLINES_CHANGED=\nMARKER_PRESENT=false\nHUMAN_ACTION=gate SHA %s is not an ancestor of HEAD %s; the gate evidence does not describe this branch history. Re-run the internal review gate (Step 7a) at the current HEAD.\n' \
    "$resolved_gate_sha" "$resolved_head_sha" "$resolved_gate_sha" "$resolved_head_sha"
  exit 1
fi

shortstat=""
if ! shortstat="$(git diff --shortstat "${resolved_gate_sha}..${resolved_head_sha}" -- . 2>/dev/null)"; then
  printf 'RESULT=refused\nREASON=git_error\nGATE_SHA=%s\nHEAD_SHA=%s\nLINES_CHANGED=\nMARKER_PRESENT=false\nHUMAN_ACTION=could not compute diff stat between %s and %s.\n' \
    "$resolved_gate_sha" "$resolved_head_sha" "$resolved_gate_sha" "$resolved_head_sha"
  exit 2
fi
lines_changed="$(printf '%s\n' "$shortstat" | grep -Eo '[0-9]+ (insertion|deletion)' | grep -Eo '^[0-9]+' | awk '{s+=$1} END {print s+0}')"
lines_changed="${lines_changed:-0}"

marker_present="true"
commit_list=""
if ! commit_list="$(git rev-list "${resolved_gate_sha}..${resolved_head_sha}" 2>/dev/null)"; then
  printf 'RESULT=refused\nREASON=git_error\nGATE_SHA=%s\nHEAD_SHA=%s\nLINES_CHANGED=%s\nMARKER_PRESENT=false\nHUMAN_ACTION=could not list commits between %s and %s.\n' \
    "$resolved_gate_sha" "$resolved_head_sha" "$lines_changed" "$resolved_gate_sha" "$resolved_head_sha"
  exit 2
fi
while IFS= read -r commit_sha; do
  [ -n "$commit_sha" ] || continue
  commit_message="$(git log -1 --format=%B "$commit_sha" 2>/dev/null || true)"
  if ! grep -Fq 'MECHANICAL_DELTA:' <<< "$commit_message"; then
    marker_present="false"
    break
  fi
done <<< "$commit_list"

if [ "$marker_present" = "true" ] && [ "$lines_changed" -le "$MAX_MECHANICAL_LINES" ]; then
  printf 'RESULT=pass\nREASON=mechanical_delta_verified\nGATE_SHA=%s\nHEAD_SHA=%s\nLINES_CHANGED=%s\nMARKER_PRESENT=true\nHUMAN_ACTION=none\n' \
    "$resolved_gate_sha" "$resolved_head_sha" "$lines_changed"
  exit 0
fi

printf 'RESULT=refused\nREASON=stale_gate_evidence\nGATE_SHA=%s\nHEAD_SHA=%s\nLINES_CHANGED=%s\nMARKER_PRESENT=%s\nHUMAN_ACTION=the internal review gate last approved commit %s but HEAD is now %s; this delta is not classified mechanical (requires a MECHANICAL_DELTA: marker on every commit in range and <= %s changed lines, found %s changed with marker_present=%s). Re-run the internal review gate (Step 7a) at the current HEAD before readiness.\n' \
  "$resolved_gate_sha" "$resolved_head_sha" "$lines_changed" "$marker_present" \
  "$resolved_gate_sha" "$resolved_head_sha" "$MAX_MECHANICAL_LINES" "$lines_changed" "$marker_present"
exit 1
