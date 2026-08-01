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
#   ./scripts/development-workflow/batch-merge.sh [--base <branch>] discover
#   ./scripts/development-workflow/batch-merge.sh [--base <branch>] discover --prs 101,102,103
#   ./scripts/development-workflow/batch-merge.sh [--base <branch>] discover --include-checkpointed --prs 101,102,103
#
#   # --- Per-PR merge mode ---
#   ./scripts/development-workflow/batch-merge.sh [--base <branch>] merge --pr 101
#
#   # --- Safe branch deletion (MERGED-state guard) ---
#   ./scripts/development-workflow/batch-merge.sh [--base <branch>] delete-branch --pr 101
#
#   --base defaults to 'develop'; override to merge into an epic integration branch.
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
#   PR_HAS_HUMAN_CHECKPOINT=true|false
#   PR_HAS_CHANGELOG=true|false
#   PR_CREATED_AT=<ISO-8601>
#   PR_ORDER=<1-based index in merge order>
#   ---
#
# Merge output:
#   MERGE_PR_NUMBER=<n>
#   MERGE_RESULT=clean|conflict|failed
#   CHANGELOG_DEDUPED=true|false          (only when MERGE_RESULT=clean; true when
#                                          duplicate ### headers were auto-consolidated)
#   CONFLICTED_FILES=<file1,file2,...>   (only when MERGE_RESULT=conflict)
#   ERROR_MESSAGE=<text>                  (only when MERGE_RESULT=failed)
#
# Note: cmd_merge pushes the merge commit to origin/<base> and calls
# `gh pr merge --merge` so GitHub records the PR as MERGED (not CLOSED).
# If `gh pr merge` fails and the PR is not yet MERGED, a warning is emitted
# to stderr; Protocol 94 Step 4.2's `gh pr view --json state` poll is the
# safety net that detects and reports any remaining non-MERGED state.
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

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./workflow-lib.sh
. "$SCRIPT_DIR/workflow-lib.sh"

cd_workflow_repo_root

# TARGET_BASE: base integration branch for merge and discover subcommands.
# Resolution order (highest priority first):
#   1. --base flag (parsed at entry point before subcommand dispatch)
#   2. TARGET_BASE environment variable
#   3. Default: "develop"
TARGET_BASE="${TARGET_BASE:-develop}"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

usage() {
  cat >&2 <<'EOF'
Usage:
  batch-merge.sh [--base <branch>] discover [--include-checkpointed] [--prs <num1,num2,...>]
  batch-merge.sh recheck-remaining --prs <num1,num2,...> --after-merged-pr <number> --base <branch>
  batch-merge.sh [--base <branch>] merge --pr <number>
  batch-merge.sh [--base <branch>] delete-branch --pr <number>

  --base  Target integration branch (default: develop).
          Override when merging PRs into an epic integration branch.

  --include-checkpointed
          Discovery only. Include PRs labeled human-checkpoint-required in the
          candidate output after protocol-level confirmation. Merge mode still
          refuses that label until checkpoint satisfaction evidence removes it.
EOF
  exit 2
}

is_nonnegative_integer() {
  case "${1:-}" in
    ''|*[!0-9]*) return 1 ;;
    *) return 0 ;;
  esac
}

run_with_timeout() {
  local seconds="$1"
  shift

  local output_file pid start now status
  output_file="$(mktemp)"
  "$@" >"$output_file" 2>/dev/null &
  pid=$!
  start="$(date +%s)"

  while kill -0 "$pid" 2>/dev/null; do
    now="$(date +%s)"
    if [ $((now - start)) -ge "$seconds" ]; then
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      rm -f "$output_file"
      return 124
    fi
    sleep 1
  done

  status=0
  wait "$pid" || status=$?
  cat "$output_file"
  rm -f "$output_file"
  return "$status"
}

emit_recheck_record() {
  jq -cn \
    --arg record_type "$1" \
    --arg pr "$2" \
    --arg original_index "$3" \
    --arg invalidating_sibling_pr "$4" \
    --arg base_ref "$5" \
    --arg head_ref "$6" \
    --arg merge_state "$7" \
    --arg checks_state "$8" \
    --arg classification "$9" \
    --arg retryable "${10}" \
    --arg attempts "${11}" \
    --arg deadline_seconds "${12}" \
    --arg outcome "${13}" \
    --arg reason "${14}" '
      def maybe_number:
        if . == "" or . == "null" then null
        elif test("^[0-9]+$") then tonumber
        else null end;
      def maybe_string:
        if . == "" or . == "null" then null else . end;
      {
        record_type: $record_type,
        pr: ($pr | maybe_number),
        original_index: ($original_index | maybe_number),
        invalidating_sibling_pr: ($invalidating_sibling_pr | maybe_number),
        base_ref: ($base_ref | maybe_string),
        head_ref: ($head_ref | maybe_string),
        merge_state: ($merge_state | maybe_string),
        checks_state: ($checks_state | maybe_string),
        classification: $classification,
        retryable: ($retryable == "true"),
        attempts: ($attempts | tonumber),
        deadline_seconds: ($deadline_seconds | maybe_number),
        outcome: $outcome,
        reason: $reason
      }'
}

emit_recheck_error() {
  emit_recheck_record \
    "error" \
    "null" \
    "null" \
    "${1:-null}" \
    "null" \
    "null" \
    "null" \
    "null" \
    "helper_failed" \
    "false" \
    "0" \
    "${2:-null}" \
    "error" \
    "$3"
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

  local number title branch base created_at labels_csv ready_label is_draft has_needs_fixes has_human_checkpoint

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
  if printf '%s' "$json" | jq -r '.labels[].name' | grep -q '^human-checkpoint-required$'; then
    has_human_checkpoint="true"
  else
    has_human_checkpoint="false"
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
  print_kv PR_HAS_HUMAN_CHECKPOINT "$has_human_checkpoint"
  print_kv PR_HAS_CHANGELOG  "$has_changelog"
  print_kv PR_CREATED_AT     "$created_at"
}

# ---------------------------------------------------------------------------
# Command: discover
# ---------------------------------------------------------------------------

cmd_discover() {
  local explicit_prs=""
  local include_checkpointed="false"

  while [ $# -gt 0 ]; do
    case "$1" in
      --include-checkpointed)
        include_checkpointed="true"
        shift
        ;;
      --prs)
        [ $# -ge 2 ] && [ -n "${2:-}" ] || die "--prs requires a comma-separated value (e.g. --prs 101,102)"
        explicit_prs="$2"
        shift 2
        ;;
      --base)
        # Per-subcommand --base overrides the global TARGET_BASE (and env var).
        [ $# -ge 2 ] && [ -n "${2:-}" ] || die "--base requires a branch name"
        TARGET_BASE="$2"
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
    # Auto-discover PRs labeled ready-for-human-review targeting TARGET_BASE.
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

    local base has_changelog is_draft has_needs_fixes has_human_checkpoint
    base="$(printf '%s\n' "$meta" | awk -F'=' '$1=="PR_BASE"{print $2}')"
    has_changelog="$(printf '%s\n' "$meta" | awk -F'=' '$1=="PR_HAS_CHANGELOG"{print $2}')"
    is_draft="$(printf '%s\n' "$meta" | awk -F'=' '$1=="PR_IS_DRAFT"{print $2}')"
    has_needs_fixes="$(printf '%s\n' "$meta" | awk -F'=' '$1=="PR_HAS_NEEDS_FIXES"{print $2}')"
    has_human_checkpoint="$(printf '%s\n' "$meta" | awk -F'=' '$1=="PR_HAS_HUMAN_CHECKPOINT"{print $2}')"

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

    # Filter: skip unsatisfied human checkpoints unless the caller has already
    # completed the protocol-level checkpoint confirmation path. Merge mode has
    # a second hard guard and will still refuse a stale checkpoint label.
    if [ "$has_human_checkpoint" = "true" ] && [ "$include_checkpointed" != "true" ]; then
      echo "WARNING: PR #${pr_num} is labeled human-checkpoint-required — skipping until the named checkpoint is satisfied or waived and labels are synced" >&2
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
# Command: recheck-remaining
# ---------------------------------------------------------------------------

normalize_checks_state() {
  local json="$1"
  printf '%s\n' "$json" | jq -r '
    def check_name: (.name // .context // .workflowName // "");
    def state:
      if .__typename == "StatusContext" then ((.state // "") | ascii_downcase)
      else
        (((.status // "") | ascii_downcase) + ":" + ((.conclusion // "") | ascii_downcase))
      end;
    (.statusCheckRollup // []) as $checks |
    ($checks | map(select((check_name | test("^E2E regression \\(placeholder\\)$") | not)))) as $required |
    if ($required | length) == 0 then "not_required"
    elif ($required | any(.[]; (state | test("failure|error|cancelled|timed_out|action_required|startup_failure")))) then "failure"
    elif ($required | any(.[]; (state | test("pending|queued|in_progress|waiting|requested|expected")))) then "pending"
    elif ($required | all(.[]; (state | test("success|completed:success|completed:skipped|completed:neutral")))) then "success"
    else "unknown" end
  ' 2>/dev/null
}

classify_recheck_json() {
  local json="$1"
  local bound_exhausted="$2"

  local state is_draft base_ref merge_state checks_state labels_type checks_type
  state="$(printf '%s\n' "$json" | jq -r '.state // ""' 2>/dev/null)" || return 1
  is_draft="$(printf '%s\n' "$json" | jq -r 'if has("isDraft") then (.isDraft | tostring) else "" end' 2>/dev/null)" || return 1
  base_ref="$(printf '%s\n' "$json" | jq -r '.baseRefName // ""' 2>/dev/null)" || return 1
  merge_state="$(printf '%s\n' "$json" | jq -r '.mergeStateStatus // ""' 2>/dev/null)" || return 1
  checks_state="$(normalize_checks_state "$json")" || return 1
  labels_type="$(printf '%s\n' "$json" | jq -r 'if has("labels") then (.labels | type) else "" end' 2>/dev/null)" || return 1
  checks_type="$(printf '%s\n' "$json" | jq -r 'if has("statusCheckRollup") then (.statusCheckRollup | type) else "" end' 2>/dev/null)" || return 1

  if [ -z "$state" ] || [ -z "$is_draft" ] || [ -z "$base_ref" ] ||
     [ "$labels_type" != "array" ] || [ "$checks_type" != "array" ]; then
    printf 'helper_failed|false|error|missing_required_field|%s|%s|%s\n' "$base_ref" "$merge_state" "$checks_state"
    return 0
  fi

  if [ "$state" != "OPEN" ]; then
    printf 'merge_blocked|false|hold|pr_not_open|%s|%s|%s\n' "$base_ref" "$merge_state" "$checks_state"
    return 0
  fi
  if [ "$is_draft" = "true" ]; then
    printf 'merge_blocked|false|hold|draft_pr|%s|%s|%s\n' "$base_ref" "$merge_state" "$checks_state"
    return 0
  fi
  if ! printf '%s\n' "$json" | jq -e '.labels[].name | select(. == "ready-for-human-review")' >/dev/null 2>&1; then
    printf 'merge_blocked|false|hold|label_gate_failed|%s|%s|%s\n' "$base_ref" "$merge_state" "$checks_state"
    return 0
  fi
  if printf '%s\n' "$json" | jq -e '.labels[].name | select(. == "needs-fixes" or . == "do-not-merge" or . == "human-checkpoint-required")' >/dev/null 2>&1; then
    printf 'merge_blocked|false|hold|label_gate_failed|%s|%s|%s\n' "$base_ref" "$merge_state" "$checks_state"
    return 0
  fi
  if [ "$base_ref" != "$TARGET_BASE" ]; then
    printf 'merge_blocked|false|hold|base_ref_mismatch|%s|%s|%s\n' "$base_ref" "$merge_state" "$checks_state"
    return 0
  fi
  case "$merge_state" in
    DIRTY|BLOCKED|BEHIND|UNSTABLE|HAS_HOOKS)
      printf 'merge_blocked|false|hold|merge_state_non_clean|%s|%s|%s\n' "$base_ref" "$merge_state" "$checks_state"
      return 0
      ;;
  esac
  if [ "$checks_state" = "failure" ]; then
    printf 'merge_blocked|false|hold|checks_failed|%s|%s|%s\n' "$base_ref" "$merge_state" "$checks_state"
    return 0
  fi
  if [ "$checks_state" = "pending" ] || [ "$checks_state" = "unknown" ]; then
    if [ -n "$bound_exhausted" ]; then
      printf 'merge_blocked|false|hold|%s|%s|%s|%s\n' "$bound_exhausted" "$base_ref" "$merge_state" "$checks_state"
    else
      printf 'retryable|true|hold|checks_not_settled|%s|%s|%s\n' "$base_ref" "$merge_state" "$checks_state"
    fi
    return 0
  fi

  case "$merge_state" in
    CLEAN)
      printf 'clean|false|continue|refreshed_clean|%s|%s|%s\n' "$base_ref" "$merge_state" "$checks_state"
      ;;
    ""|UNKNOWN)
      if [ -n "$bound_exhausted" ]; then
        printf 'merge_blocked|false|hold|%s|%s|%s|%s\n' "$bound_exhausted" "$base_ref" "$merge_state" "$checks_state"
      else
        printf 'retryable|true|hold|merge_state_unknown|%s|%s|%s\n' "$base_ref" "$merge_state" "$checks_state"
      fi
      ;;
    *)
      printf 'helper_failed|false|error|unclassified_state|%s|%s|%s\n' "$base_ref" "$merge_state" "$checks_state"
      ;;
  esac
}

cmd_recheck_remaining() {
  local explicit_prs=""
  local after_merged_pr=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --prs)
        [ $# -ge 2 ] && [ -n "${2:-}" ] || {
          emit_recheck_error "null" "null" "invalid_pr_list"
          exit 2
        }
        explicit_prs="$2"
        shift 2
        ;;
      --after-merged-pr)
        [ $# -ge 2 ] && [ -n "${2:-}" ] || {
          emit_recheck_error "null" "null" "missing_after_merged_pr"
          exit 2
        }
        after_merged_pr="$2"
        shift 2
        ;;
      --base)
        [ $# -ge 2 ] && [ -n "${2:-}" ] || {
          emit_recheck_error "${after_merged_pr:-null}" "null" "missing_base"
          exit 2
        }
        TARGET_BASE="$2"
        shift 2
        ;;
      *)
        emit_recheck_error "${after_merged_pr:-null}" "null" "invalid_argument"
        exit 2
        ;;
    esac
  done

  local attempts_limit sleep_seconds deadline_seconds
  attempts_limit="${BATCH_MERGE_RECHECK_ATTEMPTS:-3}"
  sleep_seconds="${BATCH_MERGE_RECHECK_SLEEP_SECONDS:-10}"
  deadline_seconds="${BATCH_MERGE_RECHECK_DEADLINE_SECONDS:-60}"
  if ! is_nonnegative_integer "$attempts_limit" || [ "$attempts_limit" -lt 1 ] ||
     ! is_nonnegative_integer "$sleep_seconds" ||
     ! is_nonnegative_integer "$deadline_seconds"; then
    emit_recheck_error "${after_merged_pr:-null}" "${deadline_seconds:-null}" "invalid_retry_config"
    exit 2
  fi

  case "$after_merged_pr" in
    ''|*[!0-9]*)
      emit_recheck_error "null" "$deadline_seconds" "missing_after_merged_pr"
      exit 2
      ;;
  esac
  if [ -z "$explicit_prs" ]; then
    emit_recheck_error "$after_merged_pr" "$deadline_seconds" "invalid_pr_list"
    exit 2
  fi
  case "$explicit_prs" in
    ,*|*,|*,,*)
      emit_recheck_error "$after_merged_pr" "$deadline_seconds" "invalid_pr_list"
      exit 2
      ;;
  esac

  require_gh

  local pr_file seen_file
  pr_file="$(mktemp)"
  seen_file="$(mktemp)"
  # shellcheck disable=SC2064
  trap "rm -f '$pr_file' '$seen_file'" EXIT INT TERM

  local raw pr_id index=0
  IFS=',' read -r -a _recheck_tokens <<< "$explicit_prs"
  for raw in "${_recheck_tokens[@]}"; do
    pr_id="${raw#\#}"
    case "$pr_id" in
      ''|*[!0-9]*)
        emit_recheck_error "$after_merged_pr" "$deadline_seconds" "invalid_pr_list"
        exit 2
        ;;
    esac
    if grep -qx "$pr_id" "$seen_file"; then
      emit_recheck_error "$after_merged_pr" "$deadline_seconds" "invalid_pr_list"
      exit 2
    fi
    printf '%s\n' "$pr_id" >> "$seen_file"
    printf '%s\t%s\n' "$index" "$pr_id" >> "$pr_file"
    index=$((index + 1))
  done

  if ! grep -qx "$after_merged_pr" "$seen_file"; then
    emit_recheck_error "$after_merged_pr" "$deadline_seconds" "after_merged_pr_not_in_frozen_list"
    exit 2
  fi

  while IFS="$(printf '\t')" read -r original_index pr_num; do
    [ "$pr_num" = "$after_merged_pr" ] && continue

    local start_ts attempt json fetch_status classification_line bound_exhausted emitted
    start_ts="$(date +%s)"
    attempt=0
    classification_line=""
    emitted=""

    while [ "$attempt" -lt "$attempts_limit" ]; do
      local now elapsed remaining
      now="$(date +%s)"
      elapsed=$((now - start_ts))
      remaining=$((deadline_seconds - elapsed))
      if [ "$deadline_seconds" -gt 0 ] && [ "$remaining" -le 0 ]; then
        bound_exhausted="retry_deadline_exhausted"
        break
      fi
      [ "$deadline_seconds" -eq 0 ] && remaining=30

      attempt=$((attempt + 1))
      json=""
      fetch_status=0
      json="$(run_with_timeout "$remaining" gh pr view "$pr_num" --json number,state,isDraft,labels,baseRefName,headRefName,mergeStateStatus,statusCheckRollup)" || fetch_status=$?
      if [ "$fetch_status" -eq 124 ]; then
        bound_exhausted="retry_deadline_exhausted"
        break
      fi
      if [ "$fetch_status" -ne 0 ] || [ -z "$json" ]; then
        emit_recheck_record "error" "$pr_num" "$original_index" "$after_merged_pr" "null" "null" "null" "null" "helper_failed" "false" "$attempt" "$deadline_seconds" "error" "github_query_failed"
        exit 2
      fi
      if [ "$(printf '%s\n' "$json" | jq -r '.state // ""' 2>/dev/null || true)" = "MERGED" ]; then
        local merged_base_ref merged_head_ref merged_merge_state merged_checks_state
        merged_base_ref="$(printf '%s\n' "$json" | jq -r '.baseRefName // "null"' 2>/dev/null)" || merged_base_ref="null"
        merged_head_ref="$(printf '%s\n' "$json" | jq -r '.headRefName // "null"' 2>/dev/null)" || merged_head_ref="null"
        merged_merge_state="$(printf '%s\n' "$json" | jq -r '.mergeStateStatus // "UNKNOWN"' 2>/dev/null)" || merged_merge_state="UNKNOWN"
        merged_checks_state="$(normalize_checks_state "$json")" || merged_checks_state="unknown"
        emit_recheck_record "remaining_pr" "$pr_num" "$original_index" "$after_merged_pr" "$merged_base_ref" "$merged_head_ref" "$merged_merge_state" "$merged_checks_state" "merge_blocked" "false" "$attempt" "$deadline_seconds" "hold" "already_merged"
        emitted="true"
        break
      fi

      if [ "$attempt" -ge "$attempts_limit" ]; then
        bound_exhausted="retry_attempts_exhausted"
      else
        bound_exhausted=""
      fi
      classification_line="$(classify_recheck_json "$json" "$bound_exhausted")" || {
        emit_recheck_record "error" "$pr_num" "$original_index" "$after_merged_pr" "null" "null" "null" "null" "helper_failed" "false" "$attempt" "$deadline_seconds" "error" "malformed_response"
        exit 2
      }

      local classification retryable outcome reason base_ref head_ref merge_state checks_state
      IFS='|' read -r classification retryable outcome reason base_ref merge_state checks_state <<< "$classification_line"
      head_ref="$(printf '%s\n' "$json" | jq -r '.headRefName // ""' 2>/dev/null)" || head_ref=""
      if [ "$classification" != "retryable" ]; then
        emit_recheck_record "remaining_pr" "$pr_num" "$original_index" "$after_merged_pr" "$base_ref" "$head_ref" "$merge_state" "$checks_state" "$classification" "$retryable" "$attempt" "$deadline_seconds" "$outcome" "$reason"
        emitted="true"
        if [ "$classification" = "helper_failed" ]; then
          exit 2
        fi
        break
      fi

      if [ "$attempt" -ge "$attempts_limit" ]; then
        emit_recheck_record "remaining_pr" "$pr_num" "$original_index" "$after_merged_pr" "$base_ref" "$head_ref" "$merge_state" "$checks_state" "merge_blocked" "false" "$attempt" "$deadline_seconds" "hold" "retry_attempts_exhausted"
        emitted="true"
        break
      fi

      now="$(date +%s)"
      elapsed=$((now - start_ts))
      remaining=$((deadline_seconds - elapsed))
      if [ "$deadline_seconds" -gt 0 ] && [ "$remaining" -le 0 ]; then
        emit_recheck_record "remaining_pr" "$pr_num" "$original_index" "$after_merged_pr" "$base_ref" "$head_ref" "$merge_state" "$checks_state" "merge_blocked" "false" "$attempt" "$deadline_seconds" "hold" "retry_deadline_exhausted"
        emitted="true"
        break
      fi
      if [ "$sleep_seconds" -gt 0 ]; then
        local sleep_for="$sleep_seconds"
        if [ "$deadline_seconds" -gt 0 ] && [ "$sleep_for" -gt "$remaining" ]; then
          sleep_for="$remaining"
        fi
        [ "$sleep_for" -gt 0 ] && sleep "$sleep_for"
      fi
    done

    if [ -z "$emitted" ]; then
      emit_recheck_record "remaining_pr" "$pr_num" "$original_index" "$after_merged_pr" "null" "null" "UNKNOWN" "unknown" "merge_blocked" "false" "$attempt" "$deadline_seconds" "hold" "${bound_exhausted:-retry_deadline_exhausted}"
    fi
  done < "$pr_file"

  local observation_json observation_status observation_timeout
  observation_timeout="$deadline_seconds"
  [ "$observation_timeout" -eq 0 ] && observation_timeout=30
  observation_status=0
  observation_json="$(run_with_timeout "$observation_timeout" gh pr list --base "$TARGET_BASE" --state open --json number,headRefName,baseRefName,mergeStateStatus,statusCheckRollup 2>/dev/null)" || observation_status=$?
  if [ "$observation_status" -ne 0 ]; then
    emit_recheck_error "$after_merged_pr" "$deadline_seconds" "github_query_failed"
    exit 2
  fi
  if [ -z "$observation_json" ]; then
    emit_recheck_error "$after_merged_pr" "$deadline_seconds" "malformed_response"
    exit 2
  fi
  if ! printf '%s\n' "$observation_json" | jq -e 'type == "array"' >/dev/null 2>&1; then
    emit_recheck_error "$after_merged_pr" "$deadline_seconds" "malformed_response"
    exit 2
  fi

  local observation_lines
  observation_lines="$(printf '%s\n' "$observation_json" | jq -c '.[]' 2>/dev/null)" || {
    emit_recheck_error "$after_merged_pr" "$deadline_seconds" "malformed_response"
    exit 2
  }

  local observation_lines_file
  observation_lines_file="$(mktemp)"
  printf '%s\n' "$observation_lines" > "$observation_lines_file"
  while IFS= read -r item; do
    [ -z "$item" ] && continue
    local observed_pr observed_base observed_head observed_merge observed_checks
    if ! printf '%s\n' "$item" | jq -e 'type == "object" and (.number | type == "number")' >/dev/null 2>&1; then
      rm -f "$observation_lines_file"
      emit_recheck_error "$after_merged_pr" "$deadline_seconds" "malformed_response"
      exit 2
    fi
    observed_pr="$(printf '%s\n' "$item" | jq -r '.number // ""')"
    [ -z "$observed_pr" ] && continue
    grep -qx "$observed_pr" "$seen_file" && continue
    observed_base="$(printf '%s\n' "$item" | jq -r '.baseRefName // "null"')"
    observed_head="$(printf '%s\n' "$item" | jq -r '.headRefName // "null"')"
    observed_merge="$(printf '%s\n' "$item" | jq -r '.mergeStateStatus // "null"')"
    observed_checks="$(normalize_checks_state "$item")" || observed_checks="unknown"
    emit_recheck_record "out_of_scope_observation" "$observed_pr" "null" "$after_merged_pr" "$observed_base" "$observed_head" "$observed_merge" "$observed_checks" "out_of_scope_observation" "false" "1" "$deadline_seconds" "observe" "not_in_frozen_scope"
  done < "$observation_lines_file"
  rm -f "$observation_lines_file"
}

# ---------------------------------------------------------------------------
# CHANGELOG deduplication helper
# ---------------------------------------------------------------------------
#
# consolidate_changelog_duplicates FILE
#
# Rewrites FILE in-place so that each ### sub-header (Added, Changed, etc.)
# appears at most once within any ## section.  When duplicates are detected,
# their bullet lists are merged under the first occurrence of that header,
# preserving the original section order.  Sections without duplicates pass
# through verbatim to guarantee idempotency on already-clean input.
#
# Returns 0 always (idempotent on already-clean input).

consolidate_changelog_duplicates() {
  local file="$1"
  [ -f "$file" ] || return 0

  # Run the deduplication via Python3 to avoid awk quoting complexity with
  # multi-line state.  Python3 is available on macOS (system) and all common
  # Linux distributions.
  #
  # Strategy: parse each ## section, collect ### sub-sections in order.
  # When a duplicate ### header is found, append its bullets to the first
  # occurrence and drop the duplicate header.  The original section order is
  # preserved (no reordering) — only sections with actual duplicates are
  # reconstructed; clean sections pass through verbatim.
  python3 - "$file" <<'PYEOF'
import sys, re, os, tempfile

filepath = sys.argv[1]
with open(filepath, "r") as fh:
    lines = fh.readlines()

result = []
i = 0
while i < len(lines):
    line = lines[i]
    # Detect ## section boundary
    if re.match(r'^## ', line):
        # Collect the full ## section (up to next ## or EOF)
        section_lines = [line]
        i += 1
        while i < len(lines) and not re.match(r'^## ', lines[i]):
            section_lines.append(lines[i])
            i += 1

        # Check whether this section has duplicate ### headers; pass through
        # verbatim if clean (idempotency guarantee for already-clean input).
        seen_check = {}
        has_dup = False
        for sl in section_lines[1:]:
            if re.match(r'^### ', sl):
                hdr = sl[4:].strip()
                if hdr in seen_check:
                    has_dup = True
                    break
                seen_check[hdr] = True
        if not has_dup:
            result.extend(section_lines)
            continue

        # Duplicates found — reconstruct this section merging duplicate bodies.
        # Each entry: (header_text, [body lines], original_header_line)
        subsections = []   # in first-appearance order
        seen_idx = {}      # header_text -> index in subsections
        preamble = []      # lines before the first ### in this ## block

        j = 1  # skip the ## header line itself
        while j < len(section_lines):
            sl = section_lines[j]
            if re.match(r'^### ', sl):
                hdr = sl[4:].strip()
                body = []
                j += 1
                while (j < len(section_lines) and
                       not re.match(r'^### ', section_lines[j]) and
                       not re.match(r'^## ', section_lines[j])):
                    body.append(section_lines[j])
                    j += 1
                if hdr in seen_idx:
                    # Merge into the first occurrence: append bullets, strip
                    # surrounding blank lines so output is clean.
                    idx = seen_idx[hdr]
                    existing = subsections[idx][1]
                    while existing and existing[-1].strip() == "":
                        existing.pop()
                    stripped = list(body)
                    while stripped and stripped[0].strip() == "":
                        stripped.pop(0)
                    while stripped and stripped[-1].strip() == "":
                        stripped.pop()
                    if stripped:
                        existing.extend(stripped)
                    subsections[idx] = (hdr, existing, subsections[idx][2])
                else:
                    seen_idx[hdr] = len(subsections)
                    subsections.append((hdr, body, sl))
            else:
                if not subsections:
                    preamble.append(sl)
                elif (sl.strip() == "" and
                      j + 1 < len(section_lines) and
                      re.match(r'^### ', section_lines[j + 1])):
                    # Blank line immediately before an upcoming ###: drop it;
                    # a consistent blank separator is added during output.
                    pass
                else:
                    if subsections:
                        subsections[-1][1].append(sl)
                    else:
                        preamble.append(sl)
                j += 1

        # Reconstruct: ## header, preamble, then sub-sections in original order
        result.append(section_lines[0])
        result.extend(preamble)
        for k, (hdr, body, orig_hdr_line) in enumerate(subsections):
            result.append(orig_hdr_line)
            while body and body[-1].strip() == "":
                body.pop()
            result.extend(body)
            # Blank line after each sub-section (separator before next ### or ##)
            result.append("\n")
    else:
        result.append(line)
        i += 1

# Write atomically via a uniquely named temp file in the same directory.
# This avoids collisions and ensures we never replace the target with a
# partially written file if an exception occurs mid-write.
tmp_dir = os.path.dirname(filepath) or "."
fd = None
tmp = None
try:
    fd, tmp = tempfile.mkstemp(prefix=".dedup.", suffix=".tmp", dir=tmp_dir)
    with os.fdopen(fd, "w") as fh:
        fd = None
        fh.writelines(result)
        fh.flush()
        os.fsync(fh.fileno())
    os.replace(tmp, filepath)
    tmp = None
finally:
    if fd is not None:
        os.close(fd)
    if tmp is not None and os.path.exists(tmp):
        os.unlink(tmp)
PYEOF
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
      --base)
        # Per-subcommand --base overrides the global TARGET_BASE (and env var).
        [ $# -ge 2 ] && [ -n "${2:-}" ] || die "--base requires a branch name"
        TARGET_BASE="$2"
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

  if printf '%s' "$pr_json" | jq -e '.labels[].name | select(. == "human-checkpoint-required")' >/dev/null 2>&1; then
    merge_die "PR #${pr_num} is labeled human-checkpoint-required — satisfy or waive the checkpoint, record audit evidence, and sync labels before merging"
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

  # Ensure local TARGET_BASE is current
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
    # Post-merge CHANGELOG deduplication guard.
    # A clean git merge can still produce structural CHANGELOG violations when the
    # incoming PR placed its entries under a category header (e.g. ### Fixed) that
    # already exists earlier in the [Unreleased] block on develop.  Git has no
    # conflict to report — both sides simply have a ### Fixed section — but the
    # result is two ### Fixed blocks in the same ## [Unreleased] section, which
    # violates Keep a Changelog conventions and fails the duplicate-header lint.
    #
    # Strategy: run check-changelog-duplicate-headers.sh immediately after the
    # merge commit; if duplicates are detected, consolidate them in-place and
    # amend the merge commit before pushing so the remote branch stays clean.
    local changelog_deduped="false"
    local lint_script="$SCRIPT_DIR/../lint/check-changelog-duplicate-headers.sh"
    if [ -f "CHANGELOG.md" ] && [ -f "$lint_script" ]; then
      if ! bash "$lint_script" CHANGELOG.md >/dev/null 2>&1; then
        echo "INFO: CHANGELOG duplicate section headers detected after clean merge of PR #${pr_num} — auto-consolidating..." >&2
        # Do not abort merge flow if consolidation tooling is unavailable, but
        # emit an explicit warning so this does not fail silently.
        if ! consolidate_changelog_duplicates CHANGELOG.md; then
          echo "WARNING: CHANGELOG deduplication helper failed (for example, missing python3); continuing without auto-fix." >&2
        fi
        # Verify the fix resolved all duplicates before amending.
        if bash "$lint_script" CHANGELOG.md >/dev/null 2>&1; then
          git add CHANGELOG.md
          # Only amend when CHANGELOG.md actually changed (idempotency guard).
          if ! git diff --cached --quiet; then
            git commit --amend --no-edit >/dev/null 2>&1 || \
              merge_die "CHANGELOG deduplication succeeded but amending the merge commit failed"
            changelog_deduped="true"
            echo "INFO: CHANGELOG duplicate headers consolidated and merge commit amended." >&2
          fi
        else
          # Consolidation could not fully resolve all duplicates — warn but
          # do not block the merge; the lint will catch it in CI.
          echo "WARNING: CHANGELOG deduplication after PR #${pr_num} merge left residual duplicates — manual fix may be required." >&2
        fi
      fi
    fi

    # Push the merge commit so GitHub can process the merge event.
    git push origin "$TARGET_BASE" >/dev/null 2>&1 || \
      merge_die "Merge succeeded locally but push to origin/${TARGET_BASE} failed"

    # Tell GitHub to record this PR as MERGED.  `gh pr merge --merge` detects
    # that the commits are already on the base branch and marks the PR merged
    # without creating a duplicate commit.
    # If the call fails (e.g. already-MERGED idempotent case, API error, or
    # auth issue), check the actual PR state.  Only warn when the PR is still
    # not MERGED — the caller's Step 4.2 MERGED-state poll is the safety net.
    if ! gh pr merge "$pr_num" --merge 2>/dev/null; then
      local post_state
      post_state="$(gh pr view "$pr_num" --json state --jq '.state' 2>/dev/null)" || post_state=""
      if [ "$post_state" != "MERGED" ]; then
        echo "WARNING: gh pr merge failed for PR #${pr_num} and PR is in state '${post_state:-unknown}' — caller should verify MERGED state via 'gh pr view ${pr_num} --json state'" >&2
      fi
    fi

    print_kv MERGE_RESULT "clean"
    print_kv CHANGELOG_DEDUPED "$changelog_deduped"
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
  error_msg="$(printf '%s' "$merge_output" | head -n 5 | tr '\n' ' ')"
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

# Parse global flags before the subcommand name.
while [ $# -gt 0 ]; do
  case "$1" in
    --base)
      [ $# -ge 2 ] && [ -n "${2:-}" ] || die "--base requires a branch name"
      TARGET_BASE="$2"
      shift 2
      ;;
    --) shift; break ;;
    -*) break ;;  # Unknown flag — let the subcommand handle or reject it.
    *)  break ;;
  esac
done

if [ $# -lt 1 ]; then
  usage
fi

COMMAND="$1"
shift

case "$COMMAND" in
  discover)       cmd_discover       "$@" ;;
  recheck-remaining) cmd_recheck_remaining "$@" ;;
  merge)          cmd_merge          "$@" ;;
  delete-branch)  cmd_delete_branch  "$@" ;;
  *) die "Unknown command: ${COMMAND}" ;;
esac
