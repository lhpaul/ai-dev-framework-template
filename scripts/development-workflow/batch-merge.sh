#!/usr/bin/env bash
#
# batch-merge.sh — Deterministic merge pipeline for parallel batch PRs.
#
# Handles PR discovery (auto or explicit), metadata collection, merge ordering,
# and single-PR merge execution with structured key-value output.  The agent
# protocol (94-batch-merge-protocol.md) drives the human-interaction loop and
# calls this script once per PR in the approved merge order.
#
# Usage:
#   # --- Discovery mode ---
#   ./scripts/development-workflow/batch-merge.sh discover
#   ./scripts/development-workflow/batch-merge.sh discover --prs 101,102,103
#
#   # --- Per-PR merge mode ---
#   ./scripts/development-workflow/batch-merge.sh merge --pr 101
#
# Discovery output (one block per candidate PR):
#   DISCOVERY_RESULT=found|none
#   PR_NUMBER=<n>
#   PR_TITLE=<title>
#   PR_BRANCH=<branch>
#   PR_BASE=<base-branch>
#   PR_LABELS=<label1,label2,...>
#   PR_READY_LABEL=true|false
#   PR_HAS_CHANGELOG=true|false
#   PR_CREATED_AT=<ISO-8601>
#   PR_ORDER=<1-based index in merge order>
#   ---
#
# Merge output:
#   MERGE_PR_NUMBER=<n>
#   MERGE_RESULT=clean|conflict|failed
#   CONFLICTED_FILES=<file1,file2,...>   (only when MERGE_RESULT=conflict)
#   ERROR_MESSAGE=<text>                  (only when MERGE_RESULT=failed)
#
# Exit codes:
#   0  — operation succeeded (clean merge or discovery complete)
#   1  — conflict detected (caller must classify and resolve)
#   2  — fatal error (invalid usage, git failure, etc.)
#

set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./workflow-lib.sh
. "$SCRIPT_DIR/workflow-lib.sh"

cd_workflow_repo_root

TARGET_BASE="develop"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

usage() {
  cat >&2 <<'EOF'
Usage:
  batch-merge.sh discover [--prs <num1,num2,...>]
  batch-merge.sh merge --pr <number>
EOF
  exit 2
}

die() {
  echo "ERROR: $*" >&2
  exit 2
}

# Fetch PR metadata from GitHub for a given PR number.
# Prints key=value lines (prefixed with "PR_") to stdout.
fetch_pr_meta() {
  local pr_num="$1"

  local json
  json="$(gh pr view "$pr_num" \
    --json number,title,headRefName,baseRefName,labels,createdAt \
    2>/dev/null)" || {
    echo "FETCH_ERROR=could not fetch PR #${pr_num}" >&2
    return 1
  }

  local number title branch base created_at labels_csv ready_label

  number="$(printf '%s' "$json" | jq -r '.number')"
  title="$(printf '%s' "$json" | jq -r '.title')"
  branch="$(printf '%s' "$json" | jq -r '.headRefName')"
  base="$(printf '%s' "$json" | jq -r '.baseRefName')"
  created_at="$(printf '%s' "$json" | jq -r '.createdAt')"
  labels_csv="$(printf '%s' "$json" | jq -r '[.labels[].name] | join(",")')"
  if printf '%s' "$json" | jq -r '.labels[].name' | grep -q '^ready-for-human-review$'; then
    ready_label="true"
  else
    ready_label="false"
  fi

  # Check whether the PR diff touches CHANGELOG.md
  local has_changelog="false"
  if gh pr diff --name-only "$pr_num" 2>/dev/null | grep -q '^CHANGELOG\.md$'; then
    has_changelog="true"
  fi

  print_kv PR_NUMBER       "$number"
  print_kv_escaped PR_TITLE "$title"
  print_kv PR_BRANCH       "$branch"
  print_kv PR_BASE         "$base"
  print_kv PR_LABELS       "$labels_csv"
  print_kv PR_READY_LABEL  "$ready_label"
  print_kv PR_HAS_CHANGELOG "$has_changelog"
  print_kv PR_CREATED_AT   "$created_at"
}

# ---------------------------------------------------------------------------
# Command: discover
# ---------------------------------------------------------------------------

cmd_discover() {
  local explicit_prs=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --prs)
        explicit_prs="${2:-}"
        shift 2
        ;;
      *)
        die "Unknown option: $1"
        ;;
    esac
  done

  require_gh

  # Build newline-separated list of PR numbers (stored in temp files for
  # bash 3 compatibility — no mapfile/readarray available).
  local pr_list_file no_changelog_file changelog_file
  pr_list_file="$(mktemp)"
  no_changelog_file="$(mktemp)"
  changelog_file="$(mktemp)"
  # Set a single trap for all temp files at once to avoid fragile overwrites.
  # shellcheck disable=SC2064
  trap "rm -f '$pr_list_file' '$no_changelog_file' '$changelog_file'" EXIT INT TERM

  if [ -n "$explicit_prs" ]; then
    # Parse comma-separated list; strip leading '#' if provided
    local IFS=','
    for raw in $explicit_prs; do
      printf '%s\n' "${raw#\#}" >> "$pr_list_file"
    done
  else
    # Auto-discover PRs labeled ready-for-human-review targeting develop
    gh pr list \
      --base "$TARGET_BASE" \
      --label "ready-for-human-review" \
      --state open \
      --json number \
      --jq '.[].number' \
      2>/dev/null > "$pr_list_file" || true
  fi

  if [ ! -s "$pr_list_file" ]; then
    print_kv DISCOVERY_RESULT "none"
    return 0
  fi

  # Collect metadata for each PR, separating into two groups by CHANGELOG flag.
  # Defer DISCOVERY_RESULT until after filtering so that a non-empty initial
  # list that is entirely filtered out (e.g. all PRs target main) still results
  # in DISCOVERY_RESULT=none rather than a misleading =found with no PR blocks.
  while IFS= read -r pr_num; do
    [ -z "$pr_num" ] && continue

    local meta
    if ! meta="$(fetch_pr_meta "$pr_num" 2>&1)"; then
      echo "WARNING: skipping PR #${pr_num} — could not fetch metadata" >&2
      continue
    fi

    local base has_changelog
    base="$(printf '%s\n' "$meta" | awk -F'=' '$1=="PR_BASE"{print $2}')"
    has_changelog="$(printf '%s\n' "$meta" | awk -F'=' '$1=="PR_HAS_CHANGELOG"{print $2}')"

    # Filter: only target develop (explicit mode may include any PR numbers)
    if [ "$base" != "$TARGET_BASE" ]; then
      echo "WARNING: PR #${pr_num} targets '${base}', not '${TARGET_BASE}' — skipping" >&2
      continue
    fi

    if [ "$has_changelog" = "true" ]; then
      printf '%s\n' "$pr_num" >> "$changelog_file"
    else
      printf '%s\n' "$pr_num" >> "$no_changelog_file"
    fi
  done < "$pr_list_file"

  # If every PR was filtered out, report none.
  if [ ! -s "$no_changelog_file" ] && [ ! -s "$changelog_file" ]; then
    print_kv DISCOVERY_RESULT "none"
    return 0
  fi

  print_kv DISCOVERY_RESULT "found"

  # Emit ordered output: non-CHANGELOG PRs first (sorted numerically),
  # then CHANGELOG PRs (sorted numerically).
  local order=0

  for group_file in "$no_changelog_file" "$changelog_file"; do
    [ -s "$group_file" ] || continue
    while IFS= read -r pr_num; do
      [ -z "$pr_num" ] && continue
      order=$((order + 1))
      local meta
      meta="$(fetch_pr_meta "$pr_num")"
      printf '%s\n' "$meta"
      print_kv PR_ORDER "$order"
      echo "---"
    done < <(sort -n "$group_file")
  done
}

# ---------------------------------------------------------------------------
# Command: merge
# ---------------------------------------------------------------------------

cmd_merge() {
  local pr_num=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --pr)
        pr_num="${2:-}"
        shift 2
        ;;
      *)
        die "Unknown option: $1"
        ;;
    esac
  done

  [ -z "$pr_num" ] && usage

  require_gh

  print_kv MERGE_PR_NUMBER "$pr_num"

  # Fetch branch name for this PR
  local branch
  branch="$(gh pr view "$pr_num" --json headRefName --jq '.headRefName' 2>/dev/null)" || \
    die "Could not fetch branch for PR #${pr_num}"

  # Ensure local develop is current
  git checkout "$TARGET_BASE" >/dev/null 2>&1 || \
    die "Could not check out '${TARGET_BASE}' — ensure the working tree is clean and the branch exists locally"
  git pull --ff-only origin "$TARGET_BASE" >/dev/null 2>&1 || \
    die "Could not fast-forward local '${TARGET_BASE}' from origin — resolve divergence manually"

  # Fetch the PR's head branch
  git fetch origin "$branch" >/dev/null 2>&1 || \
    die "Could not fetch origin/${branch}"

  # Attempt the merge (capture output; the 'if' absorbs the non-zero exit code
  # so set -e does not fire on a failed merge).
  local merge_output
  if merge_output="$(git merge --no-ff --no-edit "origin/${branch}" 2>&1)"; then
    print_kv MERGE_RESULT "clean"
    return 0
  fi

  # Merge failed — check for conflicts
  local conflicted_files
  conflicted_files="$(git diff --name-only --diff-filter=U 2>/dev/null | tr '\n' ',' | sed 's/,$//')"

  if [ -n "$conflicted_files" ]; then
    print_kv MERGE_RESULT     "conflict"
    print_kv CONFLICTED_FILES "$conflicted_files"
    # Exit 1 signals "conflict detected" — do NOT abort the merge here;
    # the caller (agent protocol) classifies and resolves or aborts.
    exit 1
  fi

  # Non-conflict failure: abort and report.
  git merge --abort 2>/dev/null || true
  local error_msg
  error_msg="$(printf '%s' "$merge_output" | head -5 | tr '\n' ' ')"
  print_kv MERGE_RESULT "failed"
  print_kv_escaped ERROR_MESSAGE "$error_msg"
  exit 2
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if [ $# -lt 1 ]; then
  usage
fi

COMMAND="$1"
shift

case "$COMMAND" in
  discover) cmd_discover "$@" ;;
  merge)    cmd_merge    "$@" ;;
  *) die "Unknown command: ${COMMAND}" ;;
esac
