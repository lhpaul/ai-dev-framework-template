#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=scripts/development-workflow/workflow-lib.sh
source "$SCRIPT_DIR/workflow-lib.sh"

usage() {
  cat <<'EOF'
Usage: ./scripts/development-workflow/pr-review-loop.sh <pr-number> [--branch name] [--platform greptile] [--platform greptile,devin,coderabbit] [--poll-interval seconds] [--max-wait seconds]

Runs the automated PR review loop for one or more platforms in sequence. Before
triggering a new review, each platform checks for existing blocking findings. If
any platform reports blocking findings, the script stops immediately and exits 1.
If a platform times out or escalates, the script exits 2. If all configured
platforms are clean or skipped, the script exits 0.

Platform selection (in priority order):
  1. --platform flag(s) passed on the command line
  2. review.platforms list in .ai-dev-workflow.yaml at the repo root

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
  local stale_file=""

  trap 'rm -f "${existing_blocking_file:-}" "${blocking_lines_file:-}" "${stale_file:-}"' RETURN

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

  # --- Phase 1: Check for existing blocking findings on the current HEAD ---
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
    if printf '%s\n' "$body" | grep -qi "No Issues Found"; then continue; fi
    if printf '%s\n' "$body" | grep -q "^✅"; then continue; fi
    existing_blocking_count=$((existing_blocking_count + 1))
    printf '%s\n' "$comment_json" >> "$existing_blocking_file"
  done <<< "$existing_comments"

  while IFS= read -r review_json; do
    [ -z "${review_json:-}" ] && continue
    body="$(printf '%s\n' "$review_json" | jq -r '.body')"
    [ -z "$body" ] && continue
    if printf '%s\n' "$body" | grep -qi "No Issues Found"; then continue; fi
    if printf '%s\n' "$body" | grep -q "^✅"; then continue; fi
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
  local devin_any_check_count=0
  local check_completed_at=-1   # -1 = not yet seen; record first-seen time
  local devin_post_check_grace=120  # seconds to wait after check completes
  local devin_summary_count=0
  local since_check_completed=0
  local devin_status_count=0
  local devin_completed_status_count=0

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

    read -r devin_any_check_count check_completed < <(
      gh api "repos/$repo/commits/$head_sha/check-runs" --paginate \
        | jq -s -r '
            [.[].check_runs[] | select(
              (.app.slug == "devin-ai-integration") or
              (.name | test("devin"; "i"))
            )] as $runs
            | ($runs | length),
              ($runs | map(select(.status == "completed")) | length)
            | tostring
          ' | tr '\n' ' '; echo
    )
    devin_any_check_count="${devin_any_check_count:-0}"
    check_completed="${check_completed:-0}"

    # Also count Devin status contexts (Devin sometimes signals via a GitHub Status
    # Context on the commit rather than a Check Run — both mean Devin has completed).
    # devin_status_count: any Devin status context (including pending) — used for
    #   devin_any_check_count so we know Devin is configured and active.
    # devin_completed_status_count: only terminal states (success/failure/error) — used
    #   for check_completed so a pending status never starts the grace timer prematurely.
    # Deduplicate by context (keep latest entry per context) to avoid double-counting
    # when the same context transitions through multiple states (e.g. pending → success).
    read -r devin_status_count devin_completed_status_count < <(
      gh api "repos/$repo/commits/$head_sha/statuses" --paginate \
        | jq -s -r '
            ( [.[].[] | select(.context | test("devin"; "i"))]
              | group_by(.context) | map(max_by(.updated_at)) | length ),
            ( [.[].[] | select(.context | test("devin"; "i"))]
              | group_by(.context) | map(max_by(.updated_at))
              | map(select(.state == "success" or .state == "failure" or .state == "error"))
              | length )
            | tostring
          ' | tr '\n' ' '; echo
    )
    devin_status_count="${devin_status_count:-0}"
    devin_completed_status_count="${devin_completed_status_count:-0}"
    if [ "$devin_status_count" -gt 0 ]; then
      devin_any_check_count=$(( devin_any_check_count + devin_status_count ))
    fi

    # Only count status contexts in terminal states toward check_completed.
    if [ "$devin_completed_status_count" -gt 0 ]; then
      check_completed=$(( check_completed + devin_completed_status_count ))
    fi

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
      if [ "$devin_any_check_count" -eq 0 ]; then
        # Devin didn't review this HEAD (common after merging the base branch
        # when the diff didn't change). Before reporting "skipped", scan the
        # full PR history for unresolved Devin findings from prior reviews.
        local stale_count=0
        local stale_comments
        # Only consider unresolved inline comments here. Historical review-level
        # summaries (e.g., CHANGES_REQUESTED/COMMENTED) may have been superseded
        # by later clean runs and can cause false stale blockers.
        stale_comments="$(
          gh api "repos/$repo/pulls/$pr_number/comments" --paginate \
            | jq -s -r --arg bot "$bot_login" '
                (
                  [
                    .[][]
                    | select(
                        .user.login == $bot and
                        .in_reply_to_id != null and
                        ((.body // "") | test("^✅"))
                      )
                    | .in_reply_to_id
                  ]
                ) as $resolved_ids
                | .[][]
                | select(
                    .user.login == $bot and
                    .in_reply_to_id == null and
                    ((.body // "") | test("^✅") | not) and
                    ((.body // "") | test("✅ Addressed") | not) and
                    ((.body // "") | test("No Issues Found"; "i") | not) and
                    (.id as $comment_id | ($resolved_ids | index($comment_id) | not))
                  )
                | { path, line: (.line // .original_line // 0), body: (.body // "") }
                | @json
              '
        )"
        stale_file="$(mktemp)"
        while IFS= read -r comment_json; do
          [ -z "${comment_json:-}" ] && continue
          stale_count=$((stale_count + 1))
          printf '%s\n' "$comment_json" >> "$stale_file"
        done <<< "$stale_comments"

        if [ "$stale_count" -gt 0 ]; then
          print_kv RESULT needs_fixes
          print_kv PLATFORM "$platform"
          print_kv PR_NUMBER "$pr_number"
          print_kv BRANCH "$branch_name"
          print_kv REVIEW_COMMENT_ID ""
          print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
          print_kv REASON stale_findings
          print_kv COMMENT_COUNT "$stale_count"
          print_kv BLOCKING_COUNT "$stale_count"
          print_kv SUGGESTION_COUNT 0
          while IFS= read -r blocking_json; do
            [ -z "${blocking_json:-}" ] && continue
            print_kv "BLOCKING_${index}_PATH" "$(printf '%s\n' "$blocking_json" | jq -r '.path')"
            print_kv "BLOCKING_${index}_LINE" "$(printf '%s\n' "$blocking_json" | jq -r '.line')"
            print_kv_escaped "BLOCKING_${index}_BODY" "$(printf '%s\n' "$blocking_json" | jq -r '.body')"
            index=$((index + 1))
          done < "$stale_file"
          rm -f "$stale_file"
          return 1
        fi
        rm -f "$stale_file"

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
    if printf '%s\n' "$body" | grep -qi "No Issues Found"; then continue; fi
    if printf '%s\n' "$body" | grep -q "^✅"; then continue; fi
    comment_count=$((comment_count + 1))
    blocking_count=$((blocking_count + 1))
    printf '%s\n' "$comment_json" >> "$blocking_lines_file"
  done <<< "$comments"

  while IFS= read -r review_json; do
    [ -z "${review_json:-}" ] && continue
    body="$(printf '%s\n' "$review_json" | jq -r '.body')"
    [ -z "$body" ] && continue
    if printf '%s\n' "$body" | grep -qi "No Issues Found"; then continue; fi
    if printf '%s\n' "$body" | grep -q "^✅"; then continue; fi
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

is_coderabbit_blocking() {
  # Returns 0 (true) if the comment body contains a blocking severity marker.
  # Critical (🔴) and Major (🟠) are blocking; Minor (🟡) and Low (🟢) are not.
  # However, CodeRabbit appends "✅ Addressed in commit ..." at the end of the
  # comment body when the finding has been fixed in a subsequent commit. These
  # resolved findings are NOT blocking even if they still contain 🔴/🟠 markers.
  local body="$1"
  if printf '%s\n' "$body" | grep -q "✅ Addressed"; then return 1; fi
  if printf '%s\n' "$body" | grep -q "🔴"; then return 0; fi
  if printf '%s\n' "$body" | grep -q "🟠"; then return 0; fi
  return 1
}

run_coderabbit_review() {
  local pr_number="$1"
  local branch_name="$2"
  local poll_interval="$3"
  local max_wait="$4"
  local platform="coderabbit"
  local bot_login="coderabbitai[bot]"
  local repo
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
  local comments=""
  local blocking_reviews=""
  local blocking_count=0
  local suggestion_count=0
  local comment_count=0
  local index=1
  local blocking_json=""
  local stale_file=""

  trap 'rm -f "${existing_blocking_file:-}" "${blocking_lines_file:-}" "${stale_file:-}"' RETURN

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

  # --- Phase 1: Check for existing blocking findings on the current HEAD ---
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
    if is_coderabbit_blocking "$body"; then
      existing_blocking_count=$((existing_blocking_count + 1))
      printf '%s\n' "$comment_json" >> "$existing_blocking_file"
    else
      existing_suggestion_count=$((existing_suggestion_count + 1))
    fi
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

  # --- Phase 2: Poll for CodeRabbit review completion ---
  # CodeRabbit signals completion by posting a COMMENTED review after the HEAD commit.
  # Unlike Devin, there are no check runs to monitor — we rely solely on the review.
  #
  local coderabbit_review_count=0
  local coderabbit_any_activity=0
  local coderabbit_retrigger_attempted=0
  local coderabbit_rate_limit_retries=0
  local coderabbit_rate_limit_max_retries="${CODERABBIT_RATE_LIMIT_MAX_RETRIES:-2}"
  local coderabbit_rate_limit_wait="${CODERABBIT_RATE_LIMIT_WAIT:-180}"
  if ! [[ "$coderabbit_rate_limit_max_retries" =~ ^[0-9]+$ ]]; then
    echo "WARN: CODERABBIT_RATE_LIMIT_MAX_RETRIES must be a non-negative integer; defaulting to 2" >&2
    coderabbit_rate_limit_max_retries=2
  fi
  if ! [[ "$coderabbit_rate_limit_wait" =~ ^[0-9]+$ ]] || [ "$coderabbit_rate_limit_wait" -le 0 ]; then
    echo "WARN: CODERABBIT_RATE_LIMIT_WAIT must be a positive integer; defaulting to 180" >&2
    coderabbit_rate_limit_wait=180
  fi

  while :; do
    # Check for any CodeRabbit review submitted after the HEAD commit
    coderabbit_review_count="$(
      gh api "repos/$repo/pulls/$pr_number/reviews" --paginate \
        | jq --arg bot "$bot_login" --arg since "$since_iso" '
            [.[]
             | select(
                 .user.login == $bot and
                 .submitted_at > $since
               )
            ] | length
          '
    )"
    coderabbit_review_count="${coderabbit_review_count:-0}"

    if [ "$coderabbit_review_count" -gt 0 ]; then
      coderabbit_any_activity=1
      break
    fi

    # Also check for CodeRabbit issue comments (summary comment) as activity signal.
    # Filter by since_iso so historical comments from prior pushes do not incorrectly
    # mark this HEAD cycle as having activity (which would suppress stale-findings recovery).
    # Exclude "Reviews paused" comments (pause marker) and "rate limit" comments (rate-limit
    # marker) — neither represents a completed review and must not suppress rate-limit handling.
    if [ "$coderabbit_any_activity" -eq 0 ]; then
      local activity_count
      activity_count="$(
        gh api "repos/$repo/issues/$pr_number/comments" --paginate \
          | jq --arg bot "$bot_login" --arg since "$since_iso" '
              [.[] | select(
                  .user.login == $bot and
                  .created_at > $since and
                  ((.body // "") | test("Reviews paused|review paused"; "i") | not) and
                  ((.body // "") | test("rate.?limit"; "i") | not)
              )] | length
            '
      )"
      if [ "${activity_count:-0}" -gt 0 ]; then
        coderabbit_any_activity=1
      fi
    fi

    # --- Auto-retrigger: detect CodeRabbit "reviews paused" state ---
    # CodeRabbit auto-pauses reviews after many commits. When this happens, no
    # review is posted for the current HEAD, causing the loop to time out. Detect
    # the pause by checking for a "Reviews paused" issue comment and post
    # "@coderabbitai review" to trigger a fresh review. Only attempt once.
    if [ "$coderabbit_any_activity" -eq 0 ] && [ "$coderabbit_retrigger_attempted" -eq 0 ] && [ "$elapsed" -ge "$((max_wait / 2))" ]; then
      # Check if the most recent CodeRabbit bot comment created after since_iso contains
      # a "Reviews paused" marker. Use since_iso filter to avoid false positives from
      # historical pause banners from prior HEAD commits.
      local paused_count
      paused_count="$(
        gh api "repos/$repo/issues/$pr_number/comments" --paginate \
          | jq --arg bot "$bot_login" --arg since "$since_iso" '
              [.[] | select(
                  .user.login == $bot and
                  .created_at > $since and
                  ((.body // "") | test("Reviews paused|review paused"; "i"))
              )] | length
            '
      )"
      if [ "${paused_count:-0}" -gt 0 ]; then
        echo "INFO: CodeRabbit reviews are paused — posting @coderabbitai review to trigger a fresh review" >&2
        if gh pr comment "$pr_number" --body "@coderabbitai review" >/dev/null 2>&1; then
          coderabbit_retrigger_attempted=1
          # Reset the elapsed timer to give the retrigger time to complete.
          elapsed=0
        else
          echo "WARN: failed to post retrigger comment — will not reset timer" >&2
          coderabbit_retrigger_attempted=1
        fi
        sleep "$poll_interval"
        elapsed=$((elapsed + poll_interval))
        continue
      fi
    fi

    # --- Rate-limit detection: CodeRabbit posts a comment when it cannot review yet ---
    # When CodeRabbit is rate-limited it posts an issue comment containing "rate limit"
    # text. Detect this, wait, and retry up to coderabbit_rate_limit_max_retries times.
    if [ "$coderabbit_any_activity" -eq 0 ] && [ "$coderabbit_rate_limit_retries" -lt "$coderabbit_rate_limit_max_retries" ]; then
      local rate_limit_comment_count
      rate_limit_comment_count="$(
        gh api "repos/$repo/issues/$pr_number/comments" --paginate \
          | jq --arg bot "$bot_login" --arg since "$since_iso" '
              [.[] | select(
                  .user.login == $bot and
                  .created_at > $since and
                  ((.body // "") | test("rate.?limit"; "i"))
              )] | length
            '
      )"
      if [ "${rate_limit_comment_count:-0}" -gt 0 ]; then
        coderabbit_rate_limit_retries=$((coderabbit_rate_limit_retries + 1))
        echo "INFO: CodeRabbit rate limit detected (retry $coderabbit_rate_limit_retries/$coderabbit_rate_limit_max_retries) — waiting ${coderabbit_rate_limit_wait}s before re-triggering" >&2
        sleep "$coderabbit_rate_limit_wait"
        # Do NOT reset since_iso — keep the original HEAD-commit timestamp so any review
        # posted by CodeRabbit during or after the wait is still within the detection window.
        elapsed=0
        if gh pr comment "$pr_number" --body "@coderabbitai review" >/dev/null 2>&1; then
          echo "INFO: posted @coderabbitai review trigger after rate-limit wait" >&2
        else
          echo "WARN: failed to post @coderabbitai review trigger after rate-limit wait" >&2
        fi
        sleep "$poll_interval"
        elapsed=$((elapsed + poll_interval))
        continue
      fi
    fi

    if [ "$elapsed" -ge "$max_wait" ]; then
      if [ "$coderabbit_any_activity" -eq 0 ]; then
        # --- SUCCESS commit-status fallback ---
        # Before running stale-findings recovery or escalating, check whether CodeRabbit
        # already posted a SUCCESS commit-status context for the current HEAD SHA. This
        # happens during rate-limit windows on parallel batches: CodeRabbit signals the
        # result via a commit status rather than an inline review comment. If found, treat
        # the PR as clean and return immediately without scanning for stale findings.
        # Context name is matched case-insensitively to guard against future renames.
        local coderabbit_success_status_count
        # Deduplicate by context (keep latest entry per context) before checking state,
        # so a superseded status (e.g., an old success followed by a failure on the same
        # context) is not counted. This matches the deduplication pattern used by the
        # Devin adapter above.
        coderabbit_success_status_count="$(
          gh api "repos/$repo/commits/$head_sha/statuses" --paginate \
            | jq -s '[.[].[] | select(
                    (.context // "" | ascii_downcase | test("coderabbit"))
                  )]
                  | group_by(.context) | map(max_by(.updated_at))
                  | map(select(.state == "success"))
                  | length'
        )"
        if [ "${coderabbit_success_status_count:-0}" -gt 0 ]; then
          echo "INFO: CodeRabbit SUCCESS commit-status found for HEAD $head_sha — treating PR as clean (coderabbit_status_success_fallback)" >&2
          print_kv RESULT clean
          print_kv REASON coderabbit_status_success_fallback
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

        # CodeRabbit didn't review this HEAD. Check for stale findings before skipping.
        # Only consider unresolved inline comments here. Exclude resolved findings
        # (replies starting with ✅ resolve their parent comment) — same pattern as Devin.
        local stale_count=0
        local stale_blocking_count=0
        local stale_comments
        stale_comments="$(
          gh api "repos/$repo/pulls/$pr_number/comments" --paginate \
            | jq -s -r --arg bot "$bot_login" '
                (
                  [
                    .[][]
                    | select(
                        .user.login == $bot and
                        .in_reply_to_id != null and
                        ((.body // "") | test("^✅"))
                      )
                    | .in_reply_to_id
                  ]
                ) as $resolved_ids
                | .[][]
                | select(
                    .user.login == $bot and
                    .in_reply_to_id == null and
                    ((.body // "") | test("^✅") | not) and
                    ((.body // "") | test("✅ Addressed") | not) and
                    (.id as $comment_id | ($resolved_ids | index($comment_id) | not))
                  )
                | { path, line: (.line // .original_line // 0), body: (.body // "") }
                | @json
              '
        )"
        stale_file="$(mktemp)"
        while IFS= read -r comment_json; do
          [ -z "${comment_json:-}" ] && continue
          body="$(printf '%s\n' "$comment_json" | jq -r '.body')"
          [ -z "$body" ] && continue
          if is_coderabbit_blocking "$body"; then
            stale_blocking_count=$((stale_blocking_count + 1))
            printf '%s\n' "$comment_json" >> "$stale_file"
          fi
          stale_count=$((stale_count + 1))
        done <<< "$stale_comments"

        if [ "$stale_blocking_count" -gt 0 ]; then
          print_kv RESULT needs_fixes
          print_kv PLATFORM "$platform"
          print_kv PR_NUMBER "$pr_number"
          print_kv BRANCH "$branch_name"
          print_kv REVIEW_COMMENT_ID ""
          print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
          print_kv REASON stale_findings
          print_kv COMMENT_COUNT "$stale_count"
          print_kv BLOCKING_COUNT "$stale_blocking_count"
          print_kv SUGGESTION_COUNT "$((stale_count - stale_blocking_count))"
          while IFS= read -r blocking_json; do
            [ -z "${blocking_json:-}" ] && continue
            print_kv "BLOCKING_${index}_PATH" "$(printf '%s\n' "$blocking_json" | jq -r '.path')"
            print_kv "BLOCKING_${index}_LINE" "$(printf '%s\n' "$blocking_json" | jq -r '.line')"
            print_kv_escaped "BLOCKING_${index}_BODY" "$(printf '%s\n' "$blocking_json" | jq -r '.body')"
            index=$((index + 1))
          done < "$stale_file"
          rm -f "$stale_file"
          return 1
        fi
        rm -f "$stale_file"

        print_kv RESULT skipped
        print_kv REASON no_review
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
    if is_coderabbit_blocking "$body"; then
      blocking_count=$((blocking_count + 1))
      printf '%s\n' "$comment_json" >> "$blocking_lines_file"
    else
      suggestion_count=$((suggestion_count + 1))
    fi
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
    print_kv REVIEW_COMMENT_ID ""
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
  print_kv REVIEW_COMMENT_ID ""
  print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
  print_kv COMMENT_COUNT "$comment_count"
  print_kv BLOCKING_COUNT 0
  print_kv SUGGESTION_COUNT "$suggestion_count"
  return 0
}

bot_login_for_platform() {
  # Returns the GitHub bot login for a given review platform name.
  # Used to filter reviewThreads by bot-authored comments only.
  case "$1" in
    coderabbit) printf 'coderabbitai[bot]\n' ;;
    devin)      printf 'devin-ai-integration[bot]\n' ;;
    greptile)   printf 'greptile-apps[bot]\n' ;;
    *)          printf '\n' ;;
  esac
}

check_unresolved_threads() {
  # Enumerate all reviewThreads on a PR via the GitHub GraphQL API (cursor-based
  # pagination), filter to bot-authored threads, and return the count of unresolved
  # threads on stdout as a plain integer.
  #
  # A thread is considered resolved when:
  #   - isResolved=true (GitHub resolved it via the Resolve button / mutation), OR
  #   - the first comment body contains "✅ Addressed" (bot self-marked it resolved)
  #
  # Only threads whose first comment was authored by a configured bot login are counted.
  # Human-authored threads are ignored.
  #
  # Arguments:
  #   $1 pr_number  - PR number (integer)
  #   $2 bot_logins - space-separated list of bot login strings to check
  #   $3 repo       - "owner/repo" slug
  #
  # Re-enable errexit within this function. When called from a command substitution
  # with set +e active in the parent (as in the thread gate), the subshell inherits
  # set +e. Without this explicit re-enablement, gh api graphql failures inside this
  # function would be silently ignored and the function would always return exit 0,
  # making the caller's error-handling code unreachable.
  set -e
  local pr_number="$1"
  local bot_logins="$2"
  local repo="$3"

  local owner repo_name
  owner="$(printf '%s\n' "$repo" | cut -d/ -f1)"
  repo_name="$(printf '%s\n' "$repo" | cut -d/ -f2)"

  local unresolved_count=0
  local cursor=""
  local has_next_page="true"
  local page=0
  local max_pages=10

  # GraphQL query: paginate reviewThreads 100 at a time, fetch first comment per thread.
  # Using inline query string to avoid heredoc quoting issues in subshells.
  local graphql_query
  graphql_query='query($owner:String!,$repo:String!,$pr:Int!,$cursor:String){repository(owner:$owner,name:$repo){pullRequest(number:$pr){reviewThreads(first:100,after:$cursor){pageInfo{hasNextPage endCursor}nodes{id isResolved comments(first:1){nodes{author{login}body}}}}}}}'

  while [ "$has_next_page" = "true" ]; do
    page=$((page + 1))
    if [ "$page" -gt "$max_pages" ]; then
      echo "WARN: check_unresolved_threads: exceeded $max_pages pages for PR #$pr_number — some threads may not have been checked" >&2
      break
    fi

    local result
    if [ -n "$cursor" ]; then
      result="$(gh api graphql \
        -f query="$graphql_query" \
        -f owner="$owner" -f repo="$repo_name" -F pr="$pr_number" -f cursor="$cursor" \
        --jq '.data.repository.pullRequest.reviewThreads')"
    else
      result="$(gh api graphql \
        -f query="$graphql_query" \
        -f owner="$owner" -f repo="$repo_name" -F pr="$pr_number" \
        --jq '.data.repository.pullRequest.reviewThreads')"
    fi

    has_next_page="$(printf '%s\n' "$result" | jq -r '.pageInfo.hasNextPage')"
    cursor="$(printf '%s\n' "$result" | jq -r '.pageInfo.endCursor // empty')"

    local thread_json
    while IFS= read -r thread_json; do
      [ -z "${thread_json:-}" ] && continue

      local is_resolved author body
      is_resolved="$(printf '%s\n' "$thread_json" | jq -r '.isResolved')"
      author="$(printf '%s\n' "$thread_json" | jq -r '.comments.nodes[0].author.login // ""')"
      body="$(printf '%s\n' "$thread_json" | jq -r '.comments.nodes[0].body // ""')"

      # Only count threads authored by configured bot logins
      local is_bot=0
      local bot_login
      for bot_login in $bot_logins; do
        if [ "$author" = "$bot_login" ]; then is_bot=1; break; fi
      done
      [ "$is_bot" -eq 0 ] && continue

      # Thread is resolved if isResolved=true (GitHub resolved) or body contains "✅ Addressed"
      if [ "$is_resolved" = "true" ]; then continue; fi
      if printf '%s\n' "$body" | grep -q "✅ Addressed"; then continue; fi

      unresolved_count=$((unresolved_count + 1))
    done < <(printf '%s\n' "$result" | jq -c '.nodes[]')
  done

  printf '%d\n' "$unresolved_count"
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
    coderabbit)
      run_coderabbit_review "$pr_number" "$branch_name" "$poll_interval" "$max_wait"
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
  config_file="$(workflow_config_file)"
  if workflow_config_exists; then
    while IFS= read -r line; do
      line="$(trim "$line")"
      [ -n "$line" ] && platforms+=("$line")
    done < <(workflow_config_review_platforms "$config_file")
  fi
fi

if [ "${#platforms[@]}" -gt 0 ]; then
  require_gh
  cd_workflow_repo_root

  if [ -z "$branch_name" ]; then
    branch_name="$(gh pr view "$pr_number" --json headRefName --jq '.headRefName')"
  fi
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
  print_kv UNRESOLVED_THREAD_COUNT 0
  exit 0
fi

# --- Unresolved review thread gate ---
# When all platforms returned clean or skipped, check whether any bot-authored
# review threads remain unresolved before declaring the aggregate result clean.
# This catches Nitpick/Trivial/Minor severity threads that individual platform
# handlers do not classify as blocking but that still need explicit resolution.
if [ "$aggregate_result" = "clean" ] || [ "$aggregate_result" = "skipped" ]; then
  # Derive the space-separated list of bot logins from the configured platforms.
  unresolved_bot_logins=""
  for _platform in "${platforms[@]}"; do
    _login="$(bot_login_for_platform "$_platform")"
    [ -n "$_login" ] && unresolved_bot_logins="$unresolved_bot_logins $_login"
  done
  # Trim leading/trailing whitespace
  unresolved_bot_logins="$(printf '%s\n' "$unresolved_bot_logins" | xargs 2>/dev/null || printf '%s\n' "$unresolved_bot_logins")"

  unresolved_thread_count=0
  if [ -n "$unresolved_bot_logins" ]; then
    # Wrap with set +e so a transient GraphQL API failure does not crash the script
    # (all platform reviews have already succeeded; we degrade gracefully on thread-check failure).
    # Do NOT use 2>&1 — stderr (WARN messages) must remain on stderr so that only the
    # integer count appears on stdout for clean capture into unresolved_thread_count.
    thread_check_output=""
    thread_check_status=0
    set +e
    thread_check_output="$(check_unresolved_threads "$pr_number" "$unresolved_bot_logins" "$(repo_slug)")"
    thread_check_status=$?
    set -e
    if [ "$thread_check_status" -ne 0 ]; then
      echo "WARN: check_unresolved_threads failed (exit $thread_check_status) — skipping thread gate, treating as 0 unresolved" >&2
      unresolved_thread_count=0
    else
      unresolved_thread_count="$thread_check_output"
    fi
  fi
  print_kv UNRESOLVED_THREAD_COUNT "$unresolved_thread_count"

  if [ "$unresolved_thread_count" -gt 0 ]; then
    aggregate_result="needs_fixes"
    aggregate_reason="unresolved_review_threads"
    # Increment total_blocking_count so BLOCKING_COUNT reflects the unresolved threads.
    # No BLOCKING_N_* entries are emitted for thread findings — callers must use
    # REASON=unresolved_review_threads and UNRESOLVED_THREAD_COUNT to handle this case.
    total_blocking_count=$((total_blocking_count + unresolved_thread_count))
  fi
else
  print_kv UNRESOLVED_THREAD_COUNT 0
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
