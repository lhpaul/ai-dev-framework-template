#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=scripts/development-workflow/workflow-lib.sh
source "$SCRIPT_DIR/workflow-lib.sh"

usage() {
  cat <<'EOF'
Usage: ./scripts/development-workflow/pr-review-loop.sh <pr-number> [--branch name] [--platform greptile] [--platform greptile,devin] [--poll-interval seconds] [--max-wait seconds]

Runs the automated PR review loop for one or more platforms in sequence. Before
triggering a new review, each platform checks for existing blocking findings. If
any platform reports blocking findings, the script stops immediately and exits 1.
If a platform times out or escalates, the script exits 2. If all configured
platforms are clean or skipped, the script exits 0.

Platform selection (in priority order):
  1. --platform flag(s) passed on the command line
  2. review_platforms list in .ai-dev-workflow.yaml at the repo root
  3. Fallback: greptile (only when .ai-dev-workflow.yaml is absent)

Outputs stable key=value lines including:
  RESULT=clean|needs_fixes|escalate|skipped
  PLATFORM_<n>_NAME / PLATFORM_<n>_RESULT
EOF
}

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

append_platforms() {
  local raw="$1"
  local entry
  IFS=',' read -r -a entries <<< "$raw"
  for entry in "${entries[@]}"; do
    entry="$(trim "$entry")"
    [ -n "$entry" ] && platforms+=("$entry")
  done
}

kv_value() {
  local key="$1"
  local kv_output="$2"
  printf '%s\n' "$kv_output" | awk -F= -v key="$key" '$1 == key { sub(/^[^=]*=/, ""); print; exit }'
}

kv_value_default() {
  local key="$1"
  local kv_output="$2"
  local default_value="$3"
  local value
  value="$(kv_value "$key" "$kv_output")"
  if [ -n "$value" ]; then
    printf '%s' "$value"
  else
    printf '%s' "$default_value"
  fi
}

emit_prefixed_platform_output() {
  local index="$1"
  local kv_output="$2"
  local line
  local key
  local value

  while IFS= read -r line; do
    [ -z "${line:-}" ] && continue
    key="${line%%=*}"
    value="${line#*=}"
    case "$key" in
      RESULT|PR_NUMBER|BRANCH|FIX_AGENT|PLATFORM)
        continue
        ;;
    esac
    printf 'PLATFORM_%s_%s=%s\n' "$index" "$key" "$value"
  done <<< "$kv_output"
}

run_greptile_review() {
  local pr_number="$1"
  local branch_name="$2"
  local poll_interval="$3"
  local max_wait="$4"
  local platform="greptile"
  local bot_login="greptile-apps[bot]"
  local trigger_comment="@greptile review"
  local trigger_author_login="${PR_REVIEW_TRIGGER_AUTHOR_LOGIN:-}"
  local repo
  local review_comment_id=""
  local review_window_start=""
  local recent_trigger_comment
  local existing_thumbs_up
  local head_sha=""
  local since_iso=""
  local existing_comments=""
  local existing_reviews=""
  local existing_blocking_file=""
  local existing_blocking_count=0
  local existing_suggestion_count=0
  local comment_json=""
  local review_json=""
  local body=""
  local blocking_lines_file=""
  local elapsed=0
  local thumbs_up=0
  local comments=""
  local blocking_reviews=""
  local blocking_count=0
  local suggestion_count=0
  local comment_count=0
  local index=1
  local blocking_json=""

  trap 'rm -f "${existing_blocking_file:-}" "${blocking_lines_file:-}"' RETURN

  require_gh
  cd_workflow_repo_root
  repo="$(repo_slug)"

  if [ -z "$trigger_author_login" ]; then
    trigger_author_login="$(gh api user --jq '.login')"
  fi

  recent_trigger_comment="$(
    gh api "repos/$repo/issues/$pr_number/comments" --paginate \
      | jq --arg author "$trigger_author_login" \
          --arg trigger "$trigger_comment" \
          --argjson max_wait "$max_wait" \
          '
            .[]
            | select(
                .user.login == $author and
                .body == $trigger and
                ((now - (.created_at | fromdateiso8601)) <= $max_wait)
              )
            | {id, created_at}
          ' \
      | jq -s 'sort_by(.created_at) | last // empty'
  )"

  if [ -n "$recent_trigger_comment" ]; then
    review_comment_id="$(printf '%s\n' "$recent_trigger_comment" | jq -r '.id')"
    review_window_start="$(printf '%s\n' "$recent_trigger_comment" | jq -r '.created_at')"
    existing_thumbs_up="$(
      gh api "repos/$repo/issues/comments/$review_comment_id/reactions" \
        | jq --arg bot "$bot_login" '[.[] | select(.content == "+1" and .user.login == $bot)] | length'
    )"
    if [ "$existing_thumbs_up" -gt 0 ]; then
      review_comment_id=""
      review_window_start=""
    fi
  fi

  if [ -z "$review_comment_id" ]; then
    head_sha="$(gh api "repos/$repo/pulls/$pr_number" --jq '.head.sha')"
    if [ -n "$head_sha" ]; then
      since_iso="$(gh api "repos/$repo/commits/$head_sha" --jq '.commit.committer.date // empty')"
    fi
    if [ -z "$since_iso" ]; then
      since_iso="$(date -u -v-24H +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -d '24 hours ago' +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo '1970-01-01T00:00:00Z')"
    fi

    existing_comments="$(
      gh api "repos/$repo/pulls/$pr_number/comments" --paginate \
        | jq -r --arg bot "$bot_login" --arg since "$since_iso" '
            .[]
            | select(.user.login == $bot and .created_at > $since)
            | { path, line: (.line // .original_line // 0), body: (.body // "") }
            | @json
          '
    )"
    existing_reviews="$(
      gh api "repos/$repo/pulls/$pr_number/reviews" --paginate \
        | jq -r --arg bot "$bot_login" --arg since "$since_iso" '
            .[]
            | select(
                .user.login == $bot and
                .submitted_at > $since and
                .state == "CHANGES_REQUESTED"
              )
            | { path: "", line: 0, body: (.body // "CHANGES_REQUESTED review without body") }
            | @json
          '
    )"

    existing_blocking_file="$(mktemp)"
    while IFS= read -r comment_json; do
      [ -z "${comment_json:-}" ] && continue
      body="$(printf '%s\n' "$comment_json" | jq -r '.body')"
      [ -z "$body" ] && continue
      if is_soft_suggestion "$body"; then
        existing_suggestion_count=$((existing_suggestion_count + 1))
        continue
      fi
      existing_blocking_count=$((existing_blocking_count + 1))
      printf '%s\n' "$comment_json" >> "$existing_blocking_file"
    done <<< "$existing_comments"

    while IFS= read -r review_json; do
      [ -z "${review_json:-}" ] && continue
      body="$(printf '%s\n' "$review_json" | jq -r '.body')"
      [ -z "$body" ] && continue
      existing_blocking_count=$((existing_blocking_count + 1))
      printf '%s\n' "$review_json" >> "$existing_blocking_file"
    done <<< "$existing_reviews"

    if [ "$existing_blocking_count" -gt 0 ]; then
      print_kv RESULT needs_fixes
      print_kv PLATFORM "$platform"
      print_kv PR_NUMBER "$pr_number"
      print_kv BRANCH "$branch_name"
      print_kv REVIEW_COMMENT_ID ""
      print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
      print_kv REASON existing_findings
      print_kv COMMENT_COUNT "$((existing_blocking_count + existing_suggestion_count))"
      print_kv BLOCKING_COUNT "$existing_blocking_count"
      print_kv SUGGESTION_COUNT "$existing_suggestion_count"
      while IFS= read -r blocking_json; do
        [ -z "${blocking_json:-}" ] && continue
        print_kv "BLOCKING_${index}_PATH" "$(printf '%s\n' "$blocking_json" | jq -r '.path')"
        print_kv "BLOCKING_${index}_LINE" "$(printf '%s\n' "$blocking_json" | jq -r '.line')"
        print_kv_escaped "BLOCKING_${index}_BODY" "$(printf '%s\n' "$blocking_json" | jq -r '.body')"
        index=$((index + 1))
      done < "$existing_blocking_file"
      rm -f "$existing_blocking_file"
      return 1
    fi

    rm -f "$existing_blocking_file"
    review_window_start="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    review_comment_id="$(gh api "repos/$repo/issues/$pr_number/comments" --method POST --raw-field body="$trigger_comment" --jq '.id')"
  fi

  if [ -z "$review_comment_id" ]; then
    echo "Failed to determine review comment ID for PR #$pr_number." >&2
    return 2
  fi

  blocking_lines_file="$(mktemp)"

  while :; do
    thumbs_up="$(
      gh api "repos/$repo/issues/comments/$review_comment_id/reactions" \
        | jq --arg bot "$bot_login" '[.[] | select(.content == "+1" and .user.login == $bot)] | length'
    )"

    if [ "$thumbs_up" -gt 0 ]; then
      break
    fi

    if [ "$elapsed" -ge "$max_wait" ]; then
      rm -f "$blocking_lines_file"
      print_kv RESULT escalate
      print_kv REASON timeout
      print_kv PLATFORM "$platform"
      print_kv PR_NUMBER "$pr_number"
      print_kv BRANCH "$branch_name"
      print_kv REVIEW_COMMENT_ID "$review_comment_id"
      print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
      return 2
    fi

    sleep "$poll_interval"
    elapsed=$((elapsed + poll_interval))
  done

  comments="$(
    gh api "repos/$repo/pulls/$pr_number/comments" --paginate \
      | jq -r --arg bot "$bot_login" --arg since "$review_window_start" '
        .[]
        | select(.user.login == $bot and .created_at > $since)
        | {
            path,
            line: (.line // .original_line // 0),
            body: (.body // "")
          }
        | @json
      '
  )"

  blocking_reviews="$(
    gh api "repos/$repo/pulls/$pr_number/reviews" --paginate \
      | jq -r --arg bot "$bot_login" --arg since "$review_window_start" '
        .[]
        | select(
            .user.login == $bot and
            .submitted_at > $since and
            .state == "CHANGES_REQUESTED"
          )
        | {
            path: "",
            line: 0,
            body: (.body // "CHANGES_REQUESTED review without body")
          }
        | @json
      '
  )"

  while IFS= read -r comment_json; do
    [ -z "${comment_json:-}" ] && continue
    body="$(printf '%s\n' "$comment_json" | jq -r '.body')"
    [ -z "$body" ] && continue
    comment_count=$((comment_count + 1))
    if is_soft_suggestion "$body"; then
      suggestion_count=$((suggestion_count + 1))
      continue
    fi
    blocking_count=$((blocking_count + 1))
    printf '%s\n' "$comment_json" >> "$blocking_lines_file"
  done <<< "$comments"

  while IFS= read -r review_json; do
    [ -z "${review_json:-}" ] && continue
    body="$(printf '%s\n' "$review_json" | jq -r '.body')"
    [ -z "$body" ] && continue
    comment_count=$((comment_count + 1))
    blocking_count=$((blocking_count + 1))
    printf '%s\n' "$review_json" >> "$blocking_lines_file"
  done <<< "$blocking_reviews"

  if [ "$blocking_count" -gt 0 ]; then
    print_kv RESULT needs_fixes
    print_kv PLATFORM "$platform"
    print_kv PR_NUMBER "$pr_number"
    print_kv BRANCH "$branch_name"
    print_kv REVIEW_COMMENT_ID "$review_comment_id"
    print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
    print_kv COMMENT_COUNT "$comment_count"
    print_kv BLOCKING_COUNT "$blocking_count"
    print_kv SUGGESTION_COUNT "$suggestion_count"
    while IFS= read -r blocking_json; do
      [ -z "${blocking_json:-}" ] && continue
      print_kv "BLOCKING_${index}_PATH" "$(printf '%s\n' "$blocking_json" | jq -r '.path')"
      print_kv "BLOCKING_${index}_LINE" "$(printf '%s\n' "$blocking_json" | jq -r '.line')"
      print_kv_escaped "BLOCKING_${index}_BODY" "$(printf '%s\n' "$blocking_json" | jq -r '.body')"
      index=$((index + 1))
    done < "$blocking_lines_file"
    rm -f "$blocking_lines_file"
    return 1
  fi

  rm -f "$blocking_lines_file"
  print_kv RESULT clean
  print_kv PLATFORM "$platform"
  print_kv PR_NUMBER "$pr_number"
  print_kv BRANCH "$branch_name"
  print_kv REVIEW_COMMENT_ID "$review_comment_id"
  print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
  print_kv COMMENT_COUNT "$comment_count"
  print_kv BLOCKING_COUNT 0
  print_kv SUGGESTION_COUNT "$suggestion_count"
  return 0
}

run_devin_review() {
  local pr_number="$1"
  local branch_name="$2"
  local poll_interval="$3"
  local max_wait="$4"
  local platform="devin"
  local bot_login="devin-ai-integration[bot]"
  local repo
  local head_sha=""
  local since_iso=""
  local existing_comments=""
  local existing_reviews=""
  local existing_blocking_file=""
  local existing_blocking_count=0
  local comment_json=""
  local review_json=""
  local body=""
  local blocking_lines_file=""
  local elapsed=0
  local check_completed=0
  local comments=""
  local blocking_reviews=""
  local blocking_count=0
  local comment_count=0
  local index=1
  local blocking_json=""

  trap 'rm -f "${existing_blocking_file:-}" "${blocking_lines_file:-}"' RETURN

  require_gh
  cd_workflow_repo_root
  repo="$(repo_slug)"

  head_sha="$(gh api "repos/$repo/pulls/$pr_number" --jq '.head.sha')"
  if [ -z "$head_sha" ]; then
    print_kv RESULT escalate
    print_kv REASON "head-sha-unavailable"
    print_kv PLATFORM "$platform"
    print_kv PR_NUMBER "$pr_number"
    print_kv BRANCH "$branch_name"
    print_kv REVIEW_COMMENT_ID ""
    print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
    return 2
  fi
  since_iso="$(gh api "repos/$repo/commits/$head_sha" --jq '.commit.committer.date // empty')"
  if [ -z "$since_iso" ]; then
    since_iso="$(date -u -v-24H +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -d '24 hours ago' +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo '1970-01-01T00:00:00Z')"
  fi

  # --- Phase 1: Check for existing blocking findings ---
  # Devin posts findings as inline comments, sometimes with replies containing
  # details. Filter out reply comments (in_reply_to_id != null) to avoid
  # double-counting a finding and its reply as separate blocking items.
  existing_comments="$(
    gh api "repos/$repo/pulls/$pr_number/comments" --paginate \
      | jq -r --arg bot "$bot_login" --arg since "$since_iso" '
          .[]
          | select(.user.login == $bot and .created_at > $since and .in_reply_to_id == null)
          | { path, line: (.line // .original_line // 0), body: (.body // "") }
          | @json
        '
  )"
  existing_reviews="$(
    gh api "repos/$repo/pulls/$pr_number/reviews" --paginate \
      | jq -r --arg bot "$bot_login" --arg since "$since_iso" '
          .[]
          | select(
              .user.login == $bot and
              .submitted_at > $since and
              (
                .state == "CHANGES_REQUESTED" or
                (
                  .state == "COMMENTED" and
                  (.body // "" | test("^\\*\\*Devin Review\\*\\*"; "i"))
                )
              )
            )
          | { path: "", line: 0, body: (.body // "review without body") }
          | @json
        '
  )"

  existing_blocking_file="$(mktemp)"
  while IFS= read -r comment_json; do
    [ -z "${comment_json:-}" ] && continue
    body="$(printf '%s\n' "$comment_json" | jq -r '.body')"
    [ -z "$body" ] && continue
    # Skip Devin's "No Issues Found" summary comments
    if printf '%s\n' "$body" | grep -qi "No Issues Found"; then
      continue
    fi
    existing_blocking_count=$((existing_blocking_count + 1))
    printf '%s\n' "$comment_json" >> "$existing_blocking_file"
  done <<< "$existing_comments"

  while IFS= read -r review_json; do
    [ -z "${review_json:-}" ] && continue
    body="$(printf '%s\n' "$review_json" | jq -r '.body')"
    [ -z "$body" ] && continue
    if printf '%s\n' "$body" | grep -qi "No Issues Found"; then
      continue
    fi
    existing_blocking_count=$((existing_blocking_count + 1))
    printf '%s\n' "$review_json" >> "$existing_blocking_file"
  done <<< "$existing_reviews"

  if [ "$existing_blocking_count" -gt 0 ]; then
    print_kv RESULT needs_fixes
    print_kv PLATFORM "$platform"
    print_kv PR_NUMBER "$pr_number"
    print_kv BRANCH "$branch_name"
    print_kv REVIEW_COMMENT_ID ""
    print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
    print_kv REASON existing_findings
    print_kv COMMENT_COUNT "$existing_blocking_count"
    print_kv BLOCKING_COUNT "$existing_blocking_count"
    print_kv SUGGESTION_COUNT 0
    while IFS= read -r blocking_json; do
      [ -z "${blocking_json:-}" ] && continue
      print_kv "BLOCKING_${index}_PATH" "$(printf '%s\n' "$blocking_json" | jq -r '.path')"
      print_kv "BLOCKING_${index}_LINE" "$(printf '%s\n' "$blocking_json" | jq -r '.line')"
      print_kv_escaped "BLOCKING_${index}_BODY" "$(printf '%s\n' "$blocking_json" | jq -r '.body')"
      index=$((index + 1))
    done < "$existing_blocking_file"
    rm -f "$existing_blocking_file"
    return 1
  fi

  rm -f "$existing_blocking_file"

  # --- Phase 2: Poll for Devin review completion ---
  # Devin signals completion by either:
  # 1. A summary review (body contains "**Devin Review**" or "Devin Review has completed"), or
  # 2. A "No Issues Found" review when it finds nothing to report (often no check run in that case), or
  # 3. Check run completed plus a grace period (for inline-only or no summary).
  # We check for (1) and (2) every iteration so we notice as soon as Devin posts.
  #
  # Early-exit: if Devin has no check run at all for the HEAD commit (queued, in_progress, or
  # completed), it is not going to review this push — treat as skipped. Devin only triggers a check
  # run when it intends to review (e.g. on PR open or when tagged); subsequent pushes to an already-
  # reviewed PR often have no check run. Since Phase 1 already confirmed zero existing blocking
  # findings, skipping is safe.
  local devin_any_check_count=0
  devin_any_check_count="$(
    gh api "repos/$repo/commits/$head_sha/check-runs" --paginate \
      | jq -s '
          [.[].check_runs[] | select(
            (.app.slug == "devin-ai-integration") or
            (.name | test("devin"; "i"))
          )] | length
        '
  )"
  devin_any_check_count="${devin_any_check_count:-0}"
  if [ "$devin_any_check_count" -eq 0 ]; then
    print_kv RESULT skipped
    print_kv REASON no_check_run
    print_kv PLATFORM "$platform"
    print_kv PR_NUMBER "$pr_number"
    print_kv BRANCH "$branch_name"
    print_kv REVIEW_COMMENT_ID ""
    print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
    print_kv COMMENT_COUNT 0
    print_kv BLOCKING_COUNT 0
    print_kv SUGGESTION_COUNT 0
    return 0
  fi

  local check_completed_at=-1   # -1 = not yet seen; record first-seen time
  local devin_post_check_grace=120  # seconds to wait after check completes
  local devin_summary_count=0
  local since_check_completed=0

  while :; do
    # Check for any Devin completion review every iteration (so "No Issues Found" is detected)
    devin_summary_count="$(
      gh api "repos/$repo/pulls/$pr_number/reviews" --paginate \
        | jq --arg bot "$bot_login" --arg since "$since_iso" '
            [.[]
             | select(
                 .user.login == $bot and
                 .submitted_at > $since and
                 (.body // "" | test("\\*\\*Devin Review\\*\\*|Devin Review has completed|No Issues Found"; "i"))
               )
            ] | length
          '
    )"
    devin_summary_count="${devin_summary_count:-0}"
    if [ "$devin_summary_count" -gt 0 ]; then
      # Summary or "No Issues Found" review — Devin is done
      break
    fi

    check_completed="$(
      gh api "repos/$repo/commits/$head_sha/check-runs" --paginate \
        | jq -s '
            [.[].check_runs[] | select(
              (.app.slug == "devin-ai-integration") or
              (.name | test("devin"; "i"))
            )] | map(select(.status == "completed")) | length
          '
    )"
    check_completed="${check_completed:-0}"

    if [ "$check_completed" -gt 0 ]; then
      if [ "$check_completed_at" -eq -1 ]; then
        check_completed_at="$elapsed"
      fi
      since_check_completed=$(( elapsed - check_completed_at ))
      if [ "$since_check_completed" -ge "$devin_post_check_grace" ]; then
        break
      fi
    fi

    if [ "$elapsed" -ge "$max_wait" ]; then
      print_kv RESULT escalate
      print_kv REASON timeout
      print_kv PLATFORM "$platform"
      print_kv PR_NUMBER "$pr_number"
      print_kv BRANCH "$branch_name"
      print_kv REVIEW_COMMENT_ID ""
      print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
      return 2
    fi

    sleep "$poll_interval"
    elapsed=$((elapsed + poll_interval))
  done

  # --- Phase 3: Collect results after completion ---
  # Use since_iso (commit timestamp) not review_window_start (current time)
  # to avoid a race where Devin posts findings between Phase 1's API snapshot
  # and Phase 2's timestamp. Phase 1 already confirmed zero blocking findings
  # from since_iso, so re-querying from the same timestamp won't double-count.
  blocking_lines_file="$(mktemp)"

  comments="$(
    gh api "repos/$repo/pulls/$pr_number/comments" --paginate \
      | jq -r --arg bot "$bot_login" --arg since "$since_iso" '
        .[]
        | select(.user.login == $bot and .created_at > $since and .in_reply_to_id == null)
        | {
            path,
            line: (.line // .original_line // 0),
            body: (.body // "")
          }
        | @json
      '
  )"

  blocking_reviews="$(
    gh api "repos/$repo/pulls/$pr_number/reviews" --paginate \
      | jq -r --arg bot "$bot_login" --arg since "$since_iso" '
        .[]
        | select(
            .user.login == $bot and
            .submitted_at > $since and
            (
              .state == "CHANGES_REQUESTED" or
              (
                .state == "COMMENTED" and
                (.body // "" | test("^\\*\\*Devin Review\\*\\*"; "i"))
              )
            )
          )
        | {
            path: "",
            line: 0,
            body: (.body // "review without body")
          }
        | @json
      '
  )"

  while IFS= read -r comment_json; do
    [ -z "${comment_json:-}" ] && continue
    body="$(printf '%s\n' "$comment_json" | jq -r '.body')"
    [ -z "$body" ] && continue
    # Skip Devin's "No Issues Found" summary comments
    if printf '%s\n' "$body" | grep -qi "No Issues Found"; then
      continue
    fi
    comment_count=$((comment_count + 1))
    blocking_count=$((blocking_count + 1))
    printf '%s\n' "$comment_json" >> "$blocking_lines_file"
  done <<< "$comments"

  while IFS= read -r review_json; do
    [ -z "${review_json:-}" ] && continue
    body="$(printf '%s\n' "$review_json" | jq -r '.body')"
    [ -z "$body" ] && continue
    if printf '%s\n' "$body" | grep -qi "No Issues Found"; then
      continue
    fi
    comment_count=$((comment_count + 1))
    blocking_count=$((blocking_count + 1))
    printf '%s\n' "$review_json" >> "$blocking_lines_file"
  done <<< "$blocking_reviews"

  if [ "$blocking_count" -gt 0 ]; then
    print_kv RESULT needs_fixes
    print_kv PLATFORM "$platform"
    print_kv PR_NUMBER "$pr_number"
    print_kv BRANCH "$branch_name"
    print_kv REVIEW_COMMENT_ID ""
    print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
    print_kv COMMENT_COUNT "$comment_count"
    print_kv BLOCKING_COUNT "$blocking_count"
    print_kv SUGGESTION_COUNT 0
    while IFS= read -r blocking_json; do
      [ -z "${blocking_json:-}" ] && continue
      print_kv "BLOCKING_${index}_PATH" "$(printf '%s\n' "$blocking_json" | jq -r '.path')"
      print_kv "BLOCKING_${index}_LINE" "$(printf '%s\n' "$blocking_json" | jq -r '.line')"
      print_kv_escaped "BLOCKING_${index}_BODY" "$(printf '%s\n' "$blocking_json" | jq -r '.body')"
      index=$((index + 1))
    done < "$blocking_lines_file"
    rm -f "$blocking_lines_file"
    return 1
  fi

  rm -f "$blocking_lines_file"
  print_kv RESULT clean
  print_kv PLATFORM "$platform"
  print_kv PR_NUMBER "$pr_number"
  print_kv BRANCH "$branch_name"
  print_kv REVIEW_COMMENT_ID ""
  print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
  print_kv COMMENT_COUNT "$comment_count"
  print_kv BLOCKING_COUNT 0
  print_kv SUGGESTION_COUNT 0
  return 0
}

run_platform_review() {
  local platform="$1"
  local pr_number="$2"
  local branch_name="$3"
  local poll_interval="$4"
  local max_wait="$5"

  case "$platform" in
    greptile)
      run_greptile_review "$pr_number" "$branch_name" "$poll_interval" "$max_wait"
      ;;
    devin)
      run_devin_review "$pr_number" "$branch_name" "$poll_interval" "$max_wait"
      ;;
    *)
      print_kv RESULT skipped
      print_kv PLATFORM "$platform"
      print_kv PR_NUMBER "$pr_number"
      print_kv BRANCH "$branch_name"
      print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
      print_kv REASON unsupported-platform
      print_kv COMMENT_COUNT 0
      print_kv BLOCKING_COUNT 0
      print_kv SUGGESTION_COUNT 0
      return 0
      ;;
  esac
}

if [ "$#" -lt 1 ]; then
  usage >&2
  exit 64
fi

pr_number=""
branch_name=""
poll_interval=120
max_wait=1200
declare -a platforms=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --branch)
      branch_name="$2"
      shift 2
      ;;
    --platform)
      append_platforms "$2"
      shift 2
      ;;
    --poll-interval)
      poll_interval="$2"
      shift 2
      ;;
    --max-wait)
      max_wait="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "Unknown option: $1" >&2
      exit 64
      ;;
    *)
      if [ -n "$pr_number" ]; then
        echo "Only one PR number may be provided." >&2
        exit 64
      fi
      pr_number="$1"
      shift
      ;;
  esac
done

if [ -z "$pr_number" ]; then
  usage >&2
  exit 64
fi

if [ "${#platforms[@]}" -eq 0 ]; then
  config_file="$(cd_workflow_repo_root && pwd)/.ai-dev-workflow.yaml"
  if [ -f "$config_file" ]; then
    while IFS= read -r line; do
      line="$(trim "$line")"
      [ -n "$line" ] && platforms+=("$line")
    done < <(sed -n '/^review_platforms:/,/^[^[:space:]-]/{/^[[:space:]]*-/{s/^[[:space:]]*-[[:space:]]*//;p;};}' "$config_file")
  fi
  # Only fall back to greptile when config file is absent. If the file exists but
  # we parsed zero platforms (empty list or parse issue), do not use greptile.
  if [ "${#platforms[@]}" -eq 0 ]; then
    if [ ! -f "${config_file:-}" ]; then
      platforms=("greptile")
    fi
  fi
fi

require_gh
cd_workflow_repo_root

if [ -z "$branch_name" ]; then
  branch_name="$(gh pr view "$pr_number" --json headRefName --jq '.headRefName')"
fi

aggregate_result="skipped"
aggregate_reason=""
last_platform=""
aggregate_output=""
aggregate_status=0
total_comment_count=0
total_blocking_count=0
total_suggestion_count=0

print_kv PR_NUMBER "$pr_number"
print_kv BRANCH "$branch_name"
print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
print_kv PLATFORM_COUNT "${#platforms[@]}"
# So callers can verify config was respected (e.g. no greptile when only devin is in .ai-dev-workflow.yaml)
print_kv PLATFORM_LIST "$(IFS=,; printf '%s' "${platforms[*]}")"

for index in "${!platforms[@]}"; do
  platform_index=$((index + 1))
  platform_name="${platforms[$index]}"

  set +e
  platform_output="$(run_platform_review "$platform_name" "$pr_number" "$branch_name" "$poll_interval" "$max_wait")"
  platform_status=$?
  set -e

  platform_result="$(kv_value_default RESULT "$platform_output" skipped)"
  platform_comment_count="$(kv_value_default COMMENT_COUNT "$platform_output" 0)"
  platform_blocking_count="$(kv_value_default BLOCKING_COUNT "$platform_output" 0)"
  platform_suggestion_count="$(kv_value_default SUGGESTION_COUNT "$platform_output" 0)"

  total_comment_count=$((total_comment_count + platform_comment_count))
  total_blocking_count=$((total_blocking_count + platform_blocking_count))
  total_suggestion_count=$((total_suggestion_count + platform_suggestion_count))
  last_platform="$platform_name"

  print_kv "PLATFORM_${platform_index}_NAME" "$platform_name"
  print_kv "PLATFORM_${platform_index}_RESULT" "$platform_result"
  emit_prefixed_platform_output "$platform_index" "$platform_output"

  case "$platform_result" in
    clean)
      aggregate_result="clean"
      aggregate_output="$platform_output"
      aggregate_status=$platform_status
      ;;
    skipped)
      # Per pr-review-platform.md: aggregate is "clean" when every reviewer is clean or skipped
      # Only overwrite aggregate_output when we haven't seen a clean platform (preserve REVIEW_COMMENT_ID)
      if [ "$aggregate_result" = "skipped" ]; then
        aggregate_output="$platform_output"
        aggregate_status=$platform_status
      fi
      aggregate_result="clean"
      ;;
    needs_fixes|escalate)
      aggregate_result="$platform_result"
      aggregate_reason="$(kv_value_default REASON "$platform_output" "")"
      aggregate_output="$platform_output"
      aggregate_status=$platform_status
      break
      ;;
    *)
      aggregate_result="escalate"
      aggregate_reason="unknown-platform-result"
      aggregate_output="$platform_output"
      aggregate_status=2
      break
      ;;
  esac
done

if [ -z "$last_platform" ]; then
  print_kv RESULT skipped
  print_kv REASON not_configured
  print_kv PLATFORM ""
  print_kv COMMENT_COUNT 0
  print_kv BLOCKING_COUNT 0
  print_kv SUGGESTION_COUNT 0
  exit 0
fi

print_kv RESULT "$aggregate_result"
print_kv PLATFORM "$last_platform"
[ -n "$aggregate_reason" ] && print_kv REASON "$aggregate_reason"
print_kv COMMENT_COUNT "$total_comment_count"
print_kv BLOCKING_COUNT "$total_blocking_count"
print_kv SUGGESTION_COUNT "$total_suggestion_count"

if [ -n "$aggregate_output" ]; then
  review_comment_id="$(kv_value REVIEW_COMMENT_ID "$aggregate_output")"
  [ -n "$review_comment_id" ] && print_kv REVIEW_COMMENT_ID "$review_comment_id"
fi

case "$aggregate_result" in
  clean|skipped)
    exit 0
    ;;
  needs_fixes)
    exit 1
    ;;
  escalate)
    exit 2
    ;;
  *)
    exit "${aggregate_status:-2}"
    ;;
esac
