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
#   # --- Safe branch deletion (MERGED-state guard) ---
#   ./scripts/development-workflow/batch-merge.sh delete-branch --pr 101
#
# Discovery output (one block per candidate PR):
#   DISCOVERY_RESULT=found|none
#   PR_NUMBER=<n>
#   PR_TITLE=<title>
#   PR_BRANCH=<branch>
#   PR_BASE=<base-branch>
#   PR_LABELS=<label1,label2,...>
#   PR_READY_LABEL=true|false
#   PR_IS_DRAFT=true|false
#   PR_HAS_NEEDS_FIXES=true|false
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
# Note: cmd_merge pushes the merge commit to origin/<base> and calls
# `gh pr merge --merge` so GitHub records the PR as MERGED (not CLOSED).
# Protocol 94 Step 4.2's separate push is idempotent (no-op for same commits)
# and the subsequent `gh pr view --json state` check will return MERGED.
#
# Delete-branch output:
#   DELETE_PR_NUMBER=<n>
#   DELETE_RESULT=deleted|skipped|not_found
#   DELETE_BRANCH=<branch-name>          (absent when metadata fetch fails before branch is known)
#   DELETE_PR_STATE=<state>              (only when DELETE_RESULT=skipped due to non-MERGED state)
#   ERROR_MESSAGE=<text>                 (when DELETE_RESULT=skipped; covers non-MERGED state and push failures)
#
# Exit codes:
#   0  — operation succeeded (clean merge, discovery complete, branch deleted/not_found, or branch deletion safely skipped — e.g. PR not yet MERGED)
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
  batch-merge.sh delete-branch --pr <number>
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
    --json number,title,headRefName,baseRefName,labels,createdAt,isDraft \
    2>/dev/null)" || {
    echo "FETCH_ERROR=could not fetch PR #${pr_num}" >&2
    return 1
  }

  local number title branch base created_at labels_csv ready_label is_draft has_needs_fixes

  number="$(printf '%s' "$json" | jq -r '.number')"
  title="$(printf '%s' "$json" | jq -r '.title')"
  branch="$(printf '%s' "$json" | jq -r '.headRefName')"
  base="$(printf '%s' "$json" | jq -r '.baseRefName')"
  created_at="$(printf '%s' "$json" | jq -r '.createdAt')"
  labels_csv="$(printf '%s' "$json" | jq -r '[.labels[].name] | join(",")')"
  is_draft="$(printf '%s' "$json" | jq -r '.isDraft')"
  if printf '%s' "$json" | jq -r '.labels[].name' | grep -q '^ready-for-human-review$'; then
    ready_label="true"
  else
    ready_label="false"
  fi
  if printf '%s' "$json" | jq -r '.labels[].name' | grep -q '^needs-fixes$'; then
    has_needs_fixes="true"
  else
    has_needs_fixes="false"
  fi

  # Check whether the PR diff touches CHANGELOG.md
  local has_changelog="false"
  if gh pr diff --name-only "$pr_num" 2>/dev/null | grep -q '^CHANGELOG\.md$'; then
    has_changelog="true"
  fi

  print_kv PR_NUMBER         "$number"
  print_kv_escaped PR_TITLE  "$title"
  print_kv PR_BRANCH         "$branch"
  print_kv PR_BASE           "$base"
  print_kv PR_LABELS         "$labels_csv"
  print_kv PR_READY_LABEL    "$ready_label"
  print_kv PR_IS_DRAFT       "$is_draft"
  print_kv PR_HAS_NEEDS_FIXES "$has_needs_fixes"
  print_kv PR_HAS_CHANGELOG  "$has_changelog"
  print_kv PR_CREATED_AT     "$created_at"
}

# ---------------------------------------------------------------------------
# Command: discover
# ---------------------------------------------------------------------------

cmd_discover() {
  local explicit_prs=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --prs)
        [ $# -ge 2 ] && [ -n "${2:-}" ] || die "--prs requires a comma-separated value (e.g. --prs 101,102)"
        explicit_prs="$2"
        shift 2
        ;;
      *)
        die "Unknown option: $1"
        ;;
    esac
  done

  require_gh

  # Temp files for bash 3 compatibility (no mapfile/readarray available).
  # Each PR's metadata is cached from the single fetch call so the output loop
  # reads from the cache instead of re-fetching — avoids double API calls and
  # ensures DISCOVERY_RESULT=found is never emitted before all output is ready.
  local pr_list_file no_changelog_file changelog_file meta_cache_dir
  pr_list_file="$(mktemp)"
  no_changelog_file="$(mktemp)"
  changelog_file="$(mktemp)"
  meta_cache_dir="$(mktemp -d)"
  # Single trap covers all temp files/dirs.
  # shellcheck disable=SC2064
  trap "rm -rf '$pr_list_file' '$no_changelog_file' '$changelog_file' '$meta_cache_dir'" EXIT INT TERM

  if [ -n "$explicit_prs" ]; then
    # Parse comma-separated list; strip leading '#' and validate numeric.
    local -a _pr_tokens
    IFS=',' read -r -a _pr_tokens <<< "$explicit_prs"
    for raw in "${_pr_tokens[@]}"; do
      local pr_id="${raw#\#}"
      # Reject non-numeric tokens to prevent path traversal via cache file names.
      case "$pr_id" in
        ''|*[!0-9]*) die "Invalid PR number '${pr_id}' — must be a positive integer" ;;
      esac
      printf '%s\n' "$pr_id" >> "$pr_list_file"
    done
  else
    # Auto-discover PRs labeled ready-for-human-review targeting develop.
    # Distinguish a real API failure (exit non-zero + no output) from an
    # empty result (exit 0 + no output) so API errors are not silently
    # treated as DISCOVERY_RESULT=none.
    local gh_exit=0
    gh pr list \
      --base "$TARGET_BASE" \
      --label "ready-for-human-review" \
      --state open \
      --json number \
      --jq '.[].number' \
      2>/dev/null > "$pr_list_file" || gh_exit=$?
    if [ "$gh_exit" -ne 0 ] && [ ! -s "$pr_list_file" ]; then
      die "gh pr list failed (exit ${gh_exit}) — check gh authentication and network connectivity"
    fi
  fi

  if [ ! -s "$pr_list_file" ]; then
    print_kv DISCOVERY_RESULT "none"
    return 0
  fi

  # Fetch metadata once per PR.  Cache the result so the output loop can reuse
  # it without a second API call.  Defer DISCOVERY_RESULT until after filtering
  # so a list that is entirely filtered out emits =none, not a misleading =found
  # with zero PR blocks.
  while IFS= read -r pr_num; do
    [ -z "$pr_num" ] && continue

    local meta
    if ! meta="$(fetch_pr_meta "$pr_num" 2>&1)"; then
      echo "WARNING: skipping PR #${pr_num} — could not fetch metadata" >&2
      continue
    fi

    local base has_changelog is_draft has_needs_fixes
    base="$(printf '%s\n' "$meta" | awk -F'=' '$1=="PR_BASE"{print $2}')"
    has_changelog="$(printf '%s\n' "$meta" | awk -F'=' '$1=="PR_HAS_CHANGELOG"{print $2}')"
    is_draft="$(printf '%s\n' "$meta" | awk -F'=' '$1=="PR_IS_DRAFT"{print $2}')"
    has_needs_fixes="$(printf '%s\n' "$meta" | awk -F'=' '$1=="PR_HAS_NEEDS_FIXES"{print $2}')"

    # Filter: only target develop (explicit mode may include any PR numbers)
    if [ "$base" != "$TARGET_BASE" ]; then
      echo "WARNING: PR #${pr_num} targets '${base}', not '${TARGET_BASE}' — skipping" >&2
      continue
    fi

    # Filter: skip draft PRs (not ready for merge regardless of label)
    if [ "$is_draft" = "true" ]; then
      echo "WARNING: PR #${pr_num} is a draft — skipping" >&2
      continue
    fi

    # Filter: skip PRs labeled needs-fixes (review cycle not complete)
    if [ "$has_needs_fixes" = "true" ]; then
      echo "WARNING: PR #${pr_num} is labeled needs-fixes — skipping" >&2
      continue
    fi

    # Cache metadata to avoid a second API call during output.
    printf '%s\n' "$meta" > "${meta_cache_dir}/${pr_num}.meta"

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
  # then CHANGELOG PRs (sorted numerically).  Read from cache — no re-fetch.
  local order=0

  for group_file in "$no_changelog_file" "$changelog_file"; do
    [ -s "$group_file" ] || continue
    while IFS= read -r pr_num; do
      [ -z "$pr_num" ] && continue
      local cache_file="${meta_cache_dir}/${pr_num}.meta"
      if [ ! -f "$cache_file" ]; then
        echo "WARNING: no cached metadata for PR #${pr_num} — skipping output" >&2
        continue
      fi
      order=$((order + 1))
      cat "$cache_file"
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
        [ $# -ge 2 ] && [ -n "${2:-}" ] || die "--pr requires a PR number value"
        pr_num="$2"
        shift 2
        ;;
      *)
        die "Unknown option: $1"
        ;;
    esac
  done

  [ -z "$pr_num" ] && usage

  # Validate numeric (same guard as cmd_discover to prevent cache path issues).
  case "$pr_num" in
    ''|*[!0-9]*) die "Invalid PR number '${pr_num}' — must be a positive integer" ;;
  esac

  require_gh

  print_kv MERGE_PR_NUMBER "$pr_num"

  # merge_die: emit structured failure output before exiting so the agent
  # protocol always receives MERGE_RESULT=failed + ERROR_MESSAGE, not just
  # MERGE_PR_NUMBER with no MERGE_RESULT (which would violate the output contract).
  merge_die() {
    print_kv MERGE_RESULT "failed"
    print_kv_escaped ERROR_MESSAGE "$*"
    echo "ERROR: $*" >&2
    exit 2
  }

  # Revalidate the PR immediately before merging. A PR may have been
  # retargeted, closed, or labeled needs-fixes since discovery.
  local pr_json branch base state is_draft
  pr_json="$(gh pr view "$pr_num" --json headRefName,baseRefName,state,labels,isDraft 2>/dev/null)" || \
    merge_die "Could not fetch metadata for PR #${pr_num}"

  branch="$(printf '%s' "$pr_json" | jq -r '.headRefName')"
  base="$(printf '%s' "$pr_json" | jq -r '.baseRefName')"
  state="$(printf '%s' "$pr_json" | jq -r '.state')"
  is_draft="$(printf '%s' "$pr_json" | jq -r '.isDraft')"

  [ "$base" = "$TARGET_BASE" ] || \
    merge_die "PR #${pr_num} targets '${base}', not '${TARGET_BASE}'"
  [ "$state" = "OPEN" ] || \
    merge_die "PR #${pr_num} is not open (state: ${state})"
  [ "$is_draft" = "false" ] || \
    merge_die "PR #${pr_num} is a draft"

  if printf '%s' "$pr_json" | jq -e '.labels[].name | select(. == "needs-fixes")' >/dev/null 2>&1; then
    merge_die "PR #${pr_num} is labeled needs-fixes"
  fi

  # Guard: refuse to proceed if the working tree has unresolved conflict markers.
  # This prevents a previous merge's conflict state from contaminating this PR's
  # merge (e.g., when the caller accidentally batches multiple merge calls in a
  # single shell loop instead of handling each MERGE_RESULT individually).
  local conflict_state
  conflict_state="$(git status --porcelain 2>/dev/null | grep -E '^(UU|AA|DD|AU|UA|DU|UD)' || true)"
  if [ -n "$conflict_state" ]; then
    merge_die "Working tree has unresolved conflicts from a previous merge — resolve or abort the in-progress merge before calling merge --pr again. Conflicting paths: $(printf '%s' "$conflict_state" | awk '{print $2}' | tr '\n' ' ')"
  fi

  # Ensure local develop is current
  git checkout "$TARGET_BASE" >/dev/null 2>&1 || \
    merge_die "Could not check out '${TARGET_BASE}' — ensure the working tree is clean and the branch exists locally"
  if ! git pull --ff-only origin "$TARGET_BASE" >/dev/null 2>&1; then
    echo "ff-pull failed on first attempt; retrying after 2s (transient stale-ref recovery)..." >&2
    sleep 2
    git fetch origin "$TARGET_BASE" >/dev/null 2>&1 || \
      merge_die "Could not refresh '${TARGET_BASE}' from origin before retry — check network/auth and retry"
    git pull --ff-only origin "$TARGET_BASE" >/dev/null 2>&1 || \
      merge_die "Could not fast-forward local '${TARGET_BASE}' from origin — resolve divergence manually"
  fi

  # Fetch via the pull-request ref (works for both same-repo and fork PRs;
  # `refs/pull/<N>/head` is always available via `origin` on GitHub regardless
  # of whether the head branch belongs to the same repo or a fork).
  local pr_head_ref="refs/pull/${pr_num}/head"
  local merge_ref="FETCH_HEAD"
  git fetch origin "$pr_head_ref" >/dev/null 2>&1 || \
    merge_die "Could not fetch ${pr_head_ref} from origin"

  # Attempt the merge (capture output; the 'if' absorbs the non-zero exit code
  # so set -e does not fire on a failed merge).
  local merge_output
  if merge_output="$(git merge --no-ff --no-edit -m "Merge PR #${pr_num} (${branch})" "$merge_ref" 2>&1)"; then
    # Push the merge commit so GitHub can process the merge event.
    git push origin "$TARGET_BASE" >/dev/null 2>&1 || \
      merge_die "Merge succeeded locally but push to origin/${TARGET_BASE} failed"

    # Tell GitHub to record this PR as MERGED.  `gh pr merge --merge` detects
    # that the commits are already on the base branch and marks the PR merged
    # without creating a duplicate commit.  The `|| true` guard prevents the
    # script from failing if the PR is already in MERGED state (idempotent).
    gh pr merge "$pr_num" --merge 2>/dev/null || true

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
# Command: delete-branch
# ---------------------------------------------------------------------------
#
# Safely deletes the remote branch for a PR — but ONLY after confirming that
# GitHub has recorded the PR as MERGED.  Deleting the branch before the merge
# push is reflected by GitHub causes the PR to transition to CLOSED (not
# MERGED), losing the merge attribution.  This guard prevents that failure mode.

cmd_delete_branch() {
  local pr_num=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --pr)
        [ $# -ge 2 ] && [ -n "${2:-}" ] || die "--pr requires a PR number value"
        pr_num="$2"
        shift 2
        ;;
      *)
        die "Unknown option: $1"
        ;;
    esac
  done

  [ -z "$pr_num" ] && usage

  # Validate numeric.
  case "$pr_num" in
    ''|*[!0-9]*) die "Invalid PR number '${pr_num}' — must be a positive integer" ;;
  esac

  require_gh

  print_kv DELETE_PR_NUMBER "$pr_num"

  # delete_die: emit structured failure output before exiting so the caller
  # always receives DELETE_PR_NUMBER + DELETE_RESULT + ERROR_MESSAGE, not a
  # partial tuple that violates the output contract.  Mirrors merge_die in
  # cmd_merge for the same reason.
  delete_die() {
    print_kv DELETE_RESULT "skipped"
    print_kv_escaped ERROR_MESSAGE "$*"
    echo "ERROR: $*" >&2
    exit 2
  }

  # Fetch the current PR state and branch name.
  local pr_json branch state
  pr_json="$(gh pr view "$pr_num" --json headRefName,state 2>/dev/null)" || \
    delete_die "Could not fetch metadata for PR #${pr_num}"

  branch="$(printf '%s' "$pr_json" | jq -r '.headRefName')"
  state="$(printf '%s' "$pr_json" | jq -r '.state')"

  print_kv DELETE_BRANCH "$branch"

  # Guard: only delete the remote branch when GitHub confirms MERGED state.
  # If the PR is CLOSED (not MERGED) it means the merge push has not been
  # reflected yet (or failed) — deleting now would permanently lose merge
  # attribution on the PR.
  if [ "$state" != "MERGED" ]; then
    echo "WARNING: PR #${pr_num} is in state '${state}' (not MERGED) — skipping branch deletion to prevent data loss." >&2
    print_kv DELETE_RESULT   "skipped"
    print_kv DELETE_PR_STATE "$state"
    print_kv_escaped ERROR_MESSAGE "PR #${pr_num} is in state '${state}' (not MERGED) — branch '${branch}' was NOT deleted. Verify the merge push completed and GitHub has updated the PR state before retrying."
    return 0
  fi

  # Delete the remote branch.  Distinguish "branch already gone" (expected
  # when auto-delete-on-merge is enabled or a prior run already deleted it)
  # from genuine errors (network failure, auth, permission denied) — the latter
  # must be surfaced to the caller rather than silently reported as not_found.
  local push_err push_exit
  push_err="$(git push origin --delete "$branch" 2>&1)" && {
    print_kv DELETE_RESULT "deleted"
    return 0
  }
  push_exit=$?

  if printf '%s' "$push_err" | grep -qi 'remote ref does not exist'; then
    # Branch was already gone — expected after auto-delete or a prior run.
    print_kv DELETE_RESULT "not_found"
  else
    # Genuine push failure (network, auth, permissions, etc.) — report it and
    # exit 2 to signal a fatal error per the script's exit-code contract.
    print_kv DELETE_RESULT "skipped"
    print_kv_escaped ERROR_MESSAGE "Failed to delete remote branch '${branch}' (exit ${push_exit}): ${push_err}"
    echo "ERROR: failed to delete remote branch '${branch}': ${push_err}" >&2
    exit 2
  fi
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
  discover)       cmd_discover       "$@" ;;
  merge)          cmd_merge          "$@" ;;
  delete-branch)  cmd_delete_branch  "$@" ;;
  *) die "Unknown command: ${COMMAND}" ;;
esac
