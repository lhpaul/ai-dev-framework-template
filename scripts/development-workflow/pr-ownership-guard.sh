#!/usr/bin/env bash
# pr-ownership-guard.sh - refuse a PR mutation by number unless the PR belongs
# to the expected branch (issue #1444).
#
# `gh pr edit <n>`, `gh pr comment <n>`, `gh pr ready <n>`, and label changes by
# number accept any PR number. Under parallel waves a transposed digit, or a
# body file a sibling agent overwrote, silently mutates a sibling's PR. Run
# this guard immediately before every PR mutation that addresses the PR by
# number; proceed only on exit 0.
#
# The guard is read-only: it performs one `gh pr view` and never mutates the
# PR, the checkout, or the tracker.

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: pr-ownership-guard.sh --pr <number> [--expected-branch <branch>] \
  [--repo <owner/name>] [--repo-root <path>]

Resolves the PR's headRefName and exits 0 only when it equals the expected
branch. Run it before any `gh pr edit|comment|ready|close` or label change that
addresses a PR by number.

Options:
  --pr <number>              PR number about to be mutated (required)
  --expected-branch <branch> Branch the PR must belong to. Default: the branch
                             currently checked out in --repo-root.
  --repo <owner/name>        Passed through to `gh pr view --repo`.
  --repo-root <path>         Checkout whose branch is the default expectation.
                             Default: the current directory.
  -h, --help                 Show this help.

Environment:
  PR_OWNERSHIP_GUARD_TIMEOUT_SECONDS  Deadline for the gh lookup (default 30).

Output (stdout, key=value): RESULT, PR, EXPECTED_BRANCH,
EXPECTED_BRANCH_SOURCE, PR_HEAD_BRANCH, and REQUIRED_ACTION on refusal.

Exit codes:
  0  RESULT=owned          PR head branch equals the expected branch; proceed.
  1  RESULT=not_owned      PR belongs to another branch; do not mutate it.
  2  usage error.
  3  RESULT=pr_unresolved  gh missing, failed, timed out, or returned no
                           head branch; fail closed.
  4  RESULT=branch_unknown No --expected-branch and the checkout is detached
                           or its branch cannot be read; fail closed.
USAGE
}

die_usage() {
  printf 'ERROR: %s\n' "$*" >&2
  usage >&2
  exit 2
}

require_value() {
  if [ "$#" -lt 2 ] || [ -z "${2:-}" ] || [ "${2#--}" != "$2" ]; then
    die_usage "$1 requires a value"
  fi
}

PR_NUMBER=""
EXPECTED_BRANCH=""
REPO_SLUG=""
REPO_ROOT="$(pwd)"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --pr)
      require_value "$@"
      PR_NUMBER="$2"
      shift 2
      ;;
    --expected-branch)
      require_value "$@"
      EXPECTED_BRANCH="$2"
      shift 2
      ;;
    --repo)
      require_value "$@"
      REPO_SLUG="$2"
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

case "$PR_NUMBER" in
  ''|*[!0-9]*|0*) die_usage "--pr must be a positive integer" ;;
esac
case "$EXPECTED_BRANCH" in
  *[[:space:]]*) die_usage "--expected-branch must not contain whitespace" ;;
esac
case "$REPO_SLUG" in
  ''|*/*) ;;
  *) die_usage "--repo must be in owner/name form" ;;
esac
[ -d "$REPO_ROOT" ] || die_usage "--repo-root must be an existing directory"

TIMEOUT_SECONDS="${PR_OWNERSHIP_GUARD_TIMEOUT_SECONDS:-30}"
case "$TIMEOUT_SECONDS" in
  ''|*[!0-9]*|0*) die_usage "PR_OWNERSHIP_GUARD_TIMEOUT_SECONDS must be a positive integer" ;;
esac
[ "${#TIMEOUT_SECONDS}" -le 5 ] \
  || die_usage "PR_OWNERSHIP_GUARD_TIMEOUT_SECONDS must be at most 99999"

refuse() {
  # refuse <exit-code> <result> <message> <required-action>
  local code="$1" result="$2" message="$3" action="$4"
  printf 'RESULT=%s\n' "$result"
  printf 'PR=%s\n' "$PR_NUMBER"
  printf 'EXPECTED_BRANCH=%s\n' "$EXPECTED_BRANCH"
  printf 'EXPECTED_BRANCH_SOURCE=%s\n' "$EXPECTED_SOURCE"
  printf 'PR_HEAD_BRANCH=%s\n' "${PR_HEAD_BRANCH:-}"
  printf 'REQUIRED_ACTION=%s\n' "$action"
  printf 'REFUSED: PR #%s mutation blocked: %s\n' "$PR_NUMBER" "$message" >&2
  exit "$code"
}

EXPECTED_SOURCE="argument"
PR_HEAD_BRANCH=""
if [ -z "$EXPECTED_BRANCH" ]; then
  EXPECTED_SOURCE="current_branch"
  if ! EXPECTED_BRANCH="$(git -C "$REPO_ROOT" symbolic-ref --quiet --short HEAD 2>/dev/null)" \
      || [ -z "$EXPECTED_BRANCH" ]; then
    EXPECTED_BRANCH=""
    refuse 4 branch_unknown \
      "no --expected-branch was given and $REPO_ROOT is detached or not a git checkout" \
      "Pass --expected-branch <item-branch> or run from the item worktree on its branch."
  fi
fi

if ! command -v gh >/dev/null 2>&1; then
  refuse 3 pr_unresolved "gh CLI is not available" \
    "Install or expose gh CLI, then re-run the guard before mutating the PR."
fi

# A bare failure here would exit 1 under `set -e`, which reads as not_owned.
SCRATCH_DIR="$(mktemp -d "${TMPDIR:-/tmp}/pr-ownership-guard.XXXXXX")" \
  || refuse 3 pr_unresolved "could not create a private scratch directory" \
    "Check TMPDIR permissions, then re-run the guard before mutating the PR."
cleanup() {
  rm -rf "$SCRATCH_DIR"
}
trap cleanup EXIT

GH_ARGS=(pr view "$PR_NUMBER")
if [ -n "$REPO_SLUG" ]; then
  GH_ARGS+=(--repo "$REPO_SLUG")
fi
GH_ARGS+=(--json headRefName --jq .headRefName)

# Background-wait deadline instead of GNU `timeout`, which macOS lacks.
gh "${GH_ARGS[@]}" >"$SCRATCH_DIR/stdout" 2>"$SCRATCH_DIR/stderr" &
GH_PID=$!
# Poll in tenths of a second so a fast lookup is not padded to a whole second.
DEADLINE_TENTHS=$((TIMEOUT_SECONDS * 10))
ELAPSED_TENTHS=0
while kill -0 "$GH_PID" 2>/dev/null; do
  if [ "$ELAPSED_TENTHS" -ge "$DEADLINE_TENTHS" ]; then
    kill "$GH_PID" 2>/dev/null || true
    wait "$GH_PID" 2>/dev/null || true
    refuse 3 pr_unresolved "gh pr view timed out after ${TIMEOUT_SECONDS}s" \
      "Retry the guard; do not mutate the PR until its head branch is resolved."
  fi
  sleep 0.1
  ELAPSED_TENTHS=$((ELAPSED_TENTHS + 1))
done
GH_STATUS=0
wait "$GH_PID" || GH_STATUS=$?

if [ "$GH_STATUS" -ne 0 ]; then
  refuse 3 pr_unresolved "gh pr view exited $GH_STATUS: $(head -n 1 "$SCRATCH_DIR/stderr" 2>/dev/null || true)" \
    "Confirm the PR number and repository, then re-run the guard before mutating the PR."
fi

PR_HEAD_BRANCH="$(head -n 1 "$SCRATCH_DIR/stdout")"
if [ -z "$PR_HEAD_BRANCH" ] || [ "$PR_HEAD_BRANCH" = "null" ]; then
  PR_HEAD_BRANCH=""
  refuse 3 pr_unresolved "gh pr view returned no head branch" \
    "Confirm the PR number and repository, then re-run the guard before mutating the PR."
fi

if [ "$PR_HEAD_BRANCH" != "$EXPECTED_BRANCH" ]; then
  refuse 1 not_owned \
    "it belongs to branch '$PR_HEAD_BRANCH', not '$EXPECTED_BRANCH'" \
    "Re-resolve this item's own PR number (gh pr view --json number on the item branch); never mutate a sibling PR."
fi

printf 'RESULT=owned\n'
printf 'PR=%s\n' "$PR_NUMBER"
printf 'EXPECTED_BRANCH=%s\n' "$EXPECTED_BRANCH"
printf 'EXPECTED_BRANCH_SOURCE=%s\n' "$EXPECTED_SOURCE"
printf 'PR_HEAD_BRANCH=%s\n' "$PR_HEAD_BRANCH"
