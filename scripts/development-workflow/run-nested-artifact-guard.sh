#!/usr/bin/env bash
# run-nested-artifact-guard.sh - prevent silent duplicate nested workflow paths.

set -euo pipefail

MODE=""
ISSUE_NUMBER=""
EXPECTED_BRANCH=""
EXPECTED_WORKTREE=""
APPROVED_BASE=""
ALLOW_SPLIT=false
REPO_ROOT="$(pwd)"

usage() {
  cat <<'USAGE'
Usage:
  run-nested-artifact-guard.sh --mode <pre-create|pre-pr|audit> --issue <number> --expected-branch <branch> [--approved-base <branch>] [--expected-worktree <path>] [--allow-split true|false] [--repo-root <path>]

Checks issue-scoped worktrees, branches, remote branches, and open PRs before a
nested or spawned agent creates workflow artifacts. The guard is read-only.
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

is_positive_int() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
    0*) return 1 ;;
    *) return 0 ;;
  esac
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --mode)
      require_value "$@"
      MODE="$2"
      shift 2
      ;;
    --issue)
      require_value "$@"
      ISSUE_NUMBER="$2"
      shift 2
      ;;
    --expected-branch)
      require_value "$@"
      EXPECTED_BRANCH="$2"
      shift 2
      ;;
    --expected-worktree)
      require_value "$@"
      EXPECTED_WORKTREE="$2"
      shift 2
      ;;
    --approved-base)
      require_value "$@"
      APPROVED_BASE="$2"
      shift 2
      ;;
    --allow-split)
      require_value "$@"
      ALLOW_SPLIT="$2"
      shift 2
      ;;
    --repo-root)
      require_value "$@"
      REPO_ROOT="$2"
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

case "$MODE" in
  pre-create|pre-pr|audit) ;;
  *) die_usage "--mode must be one of pre-create, pre-pr, or audit" ;;
esac
if ! is_positive_int "$ISSUE_NUMBER"; then
  die_usage "--issue must be a positive integer"
fi
[ -n "$EXPECTED_BRANCH" ] || die_usage "--expected-branch is required"
case "$ALLOW_SPLIT" in
  true|false) ;;
  *) die_usage "--allow-split must be true or false" ;;
esac
if [ "$MODE" != "audit" ] && [ -z "$APPROVED_BASE" ]; then
  printf 'RESULT=missing_base\n'
  printf 'ISSUE=%s\n' "$ISSUE_NUMBER"
  printf 'MODE=%s\n' "$MODE"
  printf 'EXPECTED_BRANCH=%s\n' "$EXPECTED_BRANCH"
  printf 'APPROVED_BASE=\n'
  printf 'REQUIRED_ACTION=Parent runner must re-dispatch with explicit approved base branch before branch or PR creation.\n'
  exit 1
fi
if [ ! -d "$REPO_ROOT" ]; then
  die_usage "--repo-root must be an existing directory"
fi

ARTIFACTS_FILE="$(mktemp)"
CANONICAL_FILE="$(mktemp)"
cleanup() {
  rm -f "$ARTIFACTS_FILE" "$CANONICAL_FILE"
}
trap cleanup EXIT

branch_matches_issue() {
  local branch="$1"
  [[ "$branch" =~ ^(feature|fix|refactor|hotfix|spec|implementation-plan|backport/hotfix)/([A-Z][A-Z0-9]{1,7}-)?${ISSUE_NUMBER}($|-) ]]
}

is_canonical_artifact() {
  local kind="$1"
  local branch="$2"
  local path_or_number="$3"

  if [ "$branch" = "$EXPECTED_BRANCH" ]; then
    return 0
  fi
  if [ "$kind" = "worktree" ] && [ -n "$EXPECTED_WORKTREE" ] && [ "$path_or_number" = "$EXPECTED_WORKTREE" ]; then
    return 0
  fi
  return 1
}

add_artifact() {
  local kind="$1"
  local branch="$2"
  local location="$3"
  local base="$4"
  local state="$5"
  local canonical="false"

  branch_matches_issue "$branch" || return 0
  if is_canonical_artifact "$kind" "$branch" "$location"; then
    canonical="true"
    printf '%s\t%s\t%s\t%s\t%s\n' "$kind" "$branch" "$location" "$base" "$state" >> "$CANONICAL_FILE"
    return 0
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$kind" "$branch" "$location" "$base" "$state" "$canonical" >> "$ARTIFACTS_FILE"
}

scan_worktrees() {
  local output current_path current_branch line
  if ! output="$(git -C "$REPO_ROOT" worktree list --porcelain 2>/dev/null)"; then
    printf 'RESULT=scan_failed\n'
    printf 'SCAN=worktrees\n'
    printf 'REQUIRED_ACTION=Retry git worktree scan before nested artifact creation.\n'
    exit 1
  fi
  current_path=""
  current_branch=""
  while IFS= read -r line; do
    case "$line" in
      worktree\ *) current_path="${line#worktree }" ;;
      branch\ refs/heads/*)
        current_branch="${line#branch refs/heads/}"
        add_artifact "worktree" "$current_branch" "$current_path" "" "local"
        ;;
      "") current_path=""; current_branch="" ;;
    esac
  done <<EOF
$output
EOF
}

scan_local_branches() {
  local output branch
  if ! output="$(git -C "$REPO_ROOT" for-each-ref --format='%(refname:short)' refs/heads 2>/dev/null)"; then
    printf 'RESULT=scan_failed\n'
    printf 'SCAN=local_branches\n'
    printf 'REQUIRED_ACTION=Retry git branch scan before nested artifact creation.\n'
    exit 1
  fi
  while IFS= read -r branch; do
    [ -n "$branch" ] || continue
    add_artifact "local_branch" "$branch" "$branch" "" "local"
  done <<EOF
$output
EOF
}

scan_remote_branches() {
  local output ref branch
  if ! output="$(git -C "$REPO_ROOT" ls-remote --heads origin 2>/dev/null)"; then
    printf 'RESULT=scan_failed\n'
    printf 'SCAN=remote_branches\n'
    printf 'REQUIRED_ACTION=Retry remote branch scan before nested artifact creation.\n'
    exit 1
  fi
  while IFS= read -r ref; do
    [ -n "$ref" ] || continue
    branch="${ref##*refs/heads/}"
    [ "$branch" != "$ref" ] || continue
    add_artifact "remote_branch" "$branch" "$branch" "" "remote"
  done <<EOF
$output
EOF
}

scan_open_prs() {
  local output parsed
  if ! command -v gh >/dev/null 2>&1; then
    return 0
  fi
  if ! output="$(gh pr list --state open --search "$ISSUE_NUMBER" --json number,headRefName,baseRefName,title 2>/dev/null)"; then
    printf 'RESULT=scan_failed\n'
    printf 'SCAN=open_prs\n'
    printf 'REQUIRED_ACTION=Retry gh PR scan before nested artifact creation.\n'
    exit 1
  fi
  if ! parsed="$(printf '%s' "$output" | python3 -c '
import json, sys
try:
    prs = json.load(sys.stdin)
except Exception:
    sys.exit(1)
for pr in prs or []:
    print("{}\t{}\t{}\t{}".format(
        pr.get("number") or "",
        pr.get("headRefName") or "",
        pr.get("baseRefName") or "",
        (pr.get("title") or "").replace("\t", " "),
    ))
')"; then
    printf 'RESULT=scan_failed\n'
    printf 'SCAN=open_prs_json\n'
    printf 'REQUIRED_ACTION=Retry gh PR scan before nested artifact creation.\n'
    exit 1
  fi
  while IFS="$(printf '\t')" read -r number head base title; do
    [ -n "$head" ] || continue
    add_artifact "open_pr" "$head" "$number" "$base" "$title"
  done <<EOF
$parsed
EOF
}

scan_worktrees
scan_local_branches
scan_remote_branches
scan_open_prs

wrong_base_count=0
duplicate_count=0
if [ -s "$ARTIFACTS_FILE" ]; then
  while IFS="$(printf '\t')" read -r kind branch location base state canonical; do
    [ -n "$kind" ] || continue
    if [ "$kind" = "open_pr" ] && [ -n "$APPROVED_BASE" ] && [ "$base" != "$APPROVED_BASE" ]; then
      wrong_base_count=$((wrong_base_count + 1))
    else
      duplicate_count=$((duplicate_count + 1))
    fi
  done < "$ARTIFACTS_FILE"
fi

if [ "$wrong_base_count" -gt 0 ]; then
  result="wrong_base"
elif [ "$ALLOW_SPLIT" = "true" ] && [ -n "$APPROVED_BASE" ]; then
  result="clean"
elif [ "$duplicate_count" -gt 0 ]; then
  if [ "$MODE" = "audit" ]; then
    result="unexpected_fork"
  else
    result="blocked_duplicate"
  fi
else
  result="clean"
fi

printf 'RESULT=%s\n' "$result"
printf 'MODE=%s\n' "$MODE"
printf 'ISSUE=%s\n' "$ISSUE_NUMBER"
printf 'EXPECTED_BRANCH=%s\n' "$EXPECTED_BRANCH"
printf 'EXPECTED_WORKTREE=%s\n' "$EXPECTED_WORKTREE"
printf 'APPROVED_BASE=%s\n' "$APPROVED_BASE"
printf 'ALLOW_SPLIT=%s\n' "$ALLOW_SPLIT"
printf 'CANONICAL_COUNT=%s\n' "$(wc -l < "$CANONICAL_FILE" | tr -d ' ')"
printf 'UNEXPECTED_COUNT=%s\n' "$(wc -l < "$ARTIFACTS_FILE" | tr -d ' ')"
if [ -s "$CANONICAL_FILE" ]; then
  awk -F '\t' '{printf "CANONICAL_ARTIFACT kind=%s branch=%s location=%s base=%s state=%s\n",$1,$2,$3,$4,$5}' "$CANONICAL_FILE"
fi
if [ -s "$ARTIFACTS_FILE" ]; then
  awk -F '\t' '{printf "UNEXPECTED_ARTIFACT kind=%s branch=%s location=%s base=%s state=%s\n",$1,$2,$3,$4,$5}' "$ARTIFACTS_FILE"
fi

case "$result" in
  clean)
    if [ "$ALLOW_SPLIT" = "true" ] && [ -s "$ARTIFACTS_FILE" ]; then
      printf 'REQUIRED_ACTION=Continue with explicit split approval and approved base recorded in the parent summary.\n'
    else
      printf 'REQUIRED_ACTION=Continue; no unexpected issue-scoped artifacts found.\n'
    fi
    ;;
  wrong_base)
    printf 'REQUIRED_ACTION=Stop before PR readiness or creation; close or retarget wrong-base PRs and re-run with approved base.\n'
    exit 1
    ;;
  blocked_duplicate)
    printf 'REQUIRED_ACTION=Stop before creating duplicate work; parent runner must resume canonical path or approve an explicit split.\n'
    exit 1
    ;;
  unexpected_fork)
    printf 'REQUIRED_ACTION=Parent runner must surface unexpected forks in the run summary and resolve before terminal readiness.\n'
    exit 1
    ;;
esac
