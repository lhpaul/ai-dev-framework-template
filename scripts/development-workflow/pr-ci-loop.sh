#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=scripts/development-workflow/workflow-lib.sh
source "$SCRIPT_DIR/workflow-lib.sh"

usage() {
  cat <<'EOF'
Usage: ./scripts/development-workflow/pr-ci-loop.sh <pr-number> [--poll-interval seconds] [--max-wait seconds]

Polls GitHub required status checks for a PR until they are green, failing, or timed out.
Outputs stable key=value lines and exits with:
  0 -> green
  1 -> red
  2 -> timeout
EOF
}

if [ "$#" -lt 1 ]; then
  usage >&2
  exit 64
fi

pr_number=""
poll_interval=60
max_wait=1800

while [ "$#" -gt 0 ]; do
  case "$1" in
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

require_gh
cd_workflow_repo_root

elapsed=0
repo="$(repo_slug)"
min_no_checks_wait=$((poll_interval * 2))

# is_devin_status_stale <pr_number> <repo>
#
# Returns 0 (stale — safe to skip) when:
#   - The PR HEAD has no blocking Devin inline comments (no bot-authored inline
#     comments posted after the HEAD commit that are not prefixed with ✅), AND
#   - The PR has no Devin CHANGES_REQUESTED or blocking COMMENTED review from
#     the Devin bot for the current HEAD.
#
# Returns 1 (not stale — findings still exist) otherwise.
#
# This mirrors the Phase 1 pre-check in pr-review-loop.sh::run_devin_review()
# and is used to bypass a stale `error` Devin commit status that has not been
# refreshed since all findings were resolved (see issue #404).
is_devin_status_stale() {
  local pr_num="$1"
  local repo_slug="$2"
  local bot_login="devin-ai-integration[bot]"
  local head_sha=""
  local since_iso=""
  local blocking_count=0
  local inline_count=0
  local comment_json=""
  local review_json=""
  local body=""
  local review_state=""

  head_sha="$(gh api "repos/$repo_slug/pulls/$pr_num" --jq '.head.sha' 2>/dev/null || true)"
  if [ -z "$head_sha" ]; then
    # Cannot determine HEAD — treat as not stale (conservative).
    return 1
  fi

  since_iso="$(gh api "repos/$repo_slug/commits/$head_sha" --jq '.commit.committer.date // empty' 2>/dev/null || true)"
  if [ -z "$since_iso" ]; then
    since_iso="1970-01-01T00:00:00Z"
  fi

  # Check for blocking inline comments from Devin on the current HEAD.
  # Emit each comment body as a compact JSON object (one per line) to survive multi-line bodies.
  # Capture output first so API failures return 1 (not stale / conservative) rather than
  # silently feeding an empty string to the while loop and returning 0 (stale).
  local raw_comments=""
  raw_comments="$(
    gh api "repos/$repo_slug/pulls/$pr_num/comments" --paginate 2>/dev/null \
      | jq -r --arg bot "$bot_login" --arg since "$since_iso" '
          .[]
          | select(.user.login == $bot and .created_at > $since and .in_reply_to_id == null)
          | {body: (.body // "")} | @json
        '
  )" || return 1  # API or jq failure — treat as not stale (conservative)

  while IFS= read -r comment_json; do
    [ -z "${comment_json:-}" ] && continue
    body="$(printf '%s\n' "$comment_json" | jq -r '.body')"
    [ -z "$body" ] && continue
    if printf '%s\n' "$body" | grep -qi "No Issues Found"; then continue; fi
    if printf '%s\n' "$body" | grep -q "^✅"; then continue; fi
    inline_count=$((inline_count + 1))
    blocking_count=$((blocking_count + 1))
  done <<< "$raw_comments"

  # Check for blocking review-level findings from Devin on the current HEAD.
  # Use "review without body" fallback (matching pr-review-loop.sh) so that
  # CHANGES_REQUESTED reviews with null bodies are never silently skipped.
  local raw_reviews=""
  raw_reviews="$(
    gh api "repos/$repo_slug/pulls/$pr_num/reviews" --paginate 2>/dev/null \
      | jq -r --arg bot "$bot_login" --arg since "$since_iso" '
          .[]
          | select(
              .user.login == $bot and
              .submitted_at > $since and
              (.state == "CHANGES_REQUESTED" or .state == "COMMENTED")
            )
          | {body: (.body // "review without body"), state: .state}
          | @json
        '
  )" || return 1  # API or jq failure — treat as not stale (conservative)

  while IFS= read -r review_json; do
    [ -z "${review_json:-}" ] && continue
    body="$(printf '%s\n' "$review_json" | jq -r '.body // ""')"
    review_state="$(printf '%s\n' "$review_json" | jq -r '.state // ""')"
    [ -z "$body" ] && continue
    if printf '%s\n' "$body" | grep -qi "No Issues Found"; then continue; fi
    if printf '%s\n' "$body" | grep -q "^✅"; then continue; fi
    # COMMENTED reviews are only blocking when the body starts with "**Devin Review**"
    # OR when there are unresolved inline comments (mirrors pr-review-loop.sh logic).
    if [ "$review_state" = "COMMENTED" ]; then
      if printf '%s\n' "$body" | grep -qi "^\\*\\*Devin Review\\*\\*"; then
        : # blocking
      elif [ "$inline_count" -gt 0 ]; then
        : # COMMENTED review with inline findings — blocking
      else
        continue  # COMMENTED review with no inline comments — not blocking
      fi
    fi
    blocking_count=$((blocking_count + 1))
  done <<< "$raw_reviews"

  if [ "$blocking_count" -gt 0 ]; then
    return 1  # still has findings — not stale
  fi
  return 0  # no findings — stale error status, safe to skip
}

while :; do
  checks_json="$(gh pr view "$pr_number" --json statusCheckRollup)"
  # statusCheckRollup can include historical duplicates for the same check.
  # Keep only the latest entry per check name to avoid stale conclusions.
  normalized_checks_json="$(
    printf '%s\n' "$checks_json" | jq '
      (.statusCheckRollup // [])
      | map(
          . + {
            __check_key: (
              if (.context // "") != "" then
                "status:" + .context
              elif (.workflowName // "") != "" and (.name // "") != "" then
                "check:" + .workflowName + "/" + .name
              elif (.name // "") != "" then
                "check:" + .name
              else
                "unknown"
              end
            ),
            __check_ts: (.startedAt // .completedAt // .createdAt // "")
          }
        )
      | sort_by(.__check_key, .__check_ts)
      | group_by(.__check_key)
      | map(last | del(.__check_key, .__check_ts))
    '
  )"
  total_check_count="$(
    printf '%s\n' "$normalized_checks_json" | jq 'length'
  )"
  pending_count="$(
    printf '%s\n' "$normalized_checks_json" | jq '
      .
      | map(select(
          ((.status // "") != "" and (.status != "COMPLETED"))
          or (.state == "EXPECTED")
          or (.state == "PENDING")
          or (.state == "IN_PROGRESS")
          or (.state == "QUEUED")
        ))
      | length
    '
  )"
  pending_list="$(
    printf '%s\n' "$normalized_checks_json" | jq -r '
      .
      | map(select(
          ((.status // "") != "" and (.status != "COMPLETED"))
          or (.state == "EXPECTED")
          or (.state == "PENDING")
          or (.state == "IN_PROGRESS")
          or (.state == "QUEUED")
        ))
      | map(.name // .context // .workflowName // "unknown")
      | join(",")
    '
  )"
  failing_count="$(
    printf '%s\n' "$normalized_checks_json" | jq '
      .
      | map(select(
          (.conclusion == "FAILURE")
          or (.conclusion == "CANCELLED")
          or (.conclusion == "TIMED_OUT")
          or (.conclusion == "ACTION_REQUIRED")
          or (.conclusion == "STARTUP_FAILURE")
          or (.state == "FAILURE")
          or (.state == "ERROR")
        ))
      | length
    '
  )"
  failing_list="$(
    printf '%s\n' "$normalized_checks_json" | jq -r '
      .
      | map(select(
          (.conclusion == "FAILURE")
          or (.conclusion == "CANCELLED")
          or (.conclusion == "TIMED_OUT")
          or (.conclusion == "ACTION_REQUIRED")
          or (.conclusion == "STARTUP_FAILURE")
          or (.state == "FAILURE")
          or (.state == "ERROR")
        ))
      | map(.name // .context // .workflowName // "unknown")
      | join(",")
    '
  )"

  # --- Stale Devin error status bypass ---
  # When all failing checks are Devin commit-status contexts in state=ERROR,
  # and no blocking Devin review findings exist for the current PR HEAD, the
  # `error` status is stale (Devin has not re-run since findings were resolved).
  # In that case, treat Devin's error as green so the CI loop is not blocked
  # waiting for a manual re-trigger. A diagnostic line is emitted instead.
  #
  # Only activates when every failing check is a Devin-pattern status context.
  # Any non-Devin failure still causes the loop to report red as usual.
  if [ "$failing_count" -gt 0 ]; then
    devin_error_count="$(
      printf '%s\n' "$normalized_checks_json" | jq '
        .
        | map(select(
            .state == "ERROR" and
            ((.context // "") | test("devin"; "i"))
          ))
        | length
      '
    )"
    if [ "$devin_error_count" -gt 0 ] && [ "$devin_error_count" -eq "$failing_count" ]; then
      # All failures are Devin error contexts. Check whether the error is stale.
      if is_devin_status_stale "$pr_number" "$repo"; then
        echo "INFO: Devin commit status is ERROR but no blocking Devin review findings exist for the current HEAD. Treating as stale — bypassing Devin error check." >&2
        failing_count=0
        failing_list=""
      fi
    fi
  fi

  if [ "$failing_count" -gt 0 ]; then
    print_kv RESULT red
    print_kv PR_NUMBER "$pr_number"
    print_kv REPO "$repo"
    print_kv TOTAL_CHECK_COUNT "$total_check_count"
    print_kv FAILING_CHECK_COUNT "$failing_count"
    print_kv FAILING_CHECKS "$failing_list"
    print_kv PENDING_CHECK_COUNT "$pending_count"
    print_kv PENDING_CHECKS "$pending_list"
    exit 1
  fi

  if [ "$pending_count" -eq 0 ]; then
    if [ "$total_check_count" -eq 0 ] && [ "$elapsed" -lt "$min_no_checks_wait" ]; then
      sleep "$poll_interval"
      elapsed=$((elapsed + poll_interval))
      continue
    fi

    print_kv RESULT green
    print_kv PR_NUMBER "$pr_number"
    print_kv REPO "$repo"
    print_kv TOTAL_CHECK_COUNT "$total_check_count"
    print_kv FAILING_CHECK_COUNT 0
    print_kv FAILING_CHECKS ""
    print_kv PENDING_CHECK_COUNT 0
    print_kv PENDING_CHECKS ""
    exit 0
  fi

  if [ "$elapsed" -ge "$max_wait" ]; then
    print_kv RESULT timeout
    print_kv PR_NUMBER "$pr_number"
    print_kv REPO "$repo"
    print_kv TOTAL_CHECK_COUNT "$total_check_count"
    print_kv FAILING_CHECK_COUNT "$failing_count"
    print_kv FAILING_CHECKS "$failing_list"
    print_kv PENDING_CHECK_COUNT "$pending_count"
    print_kv PENDING_CHECKS "$pending_list"
    exit 2
  fi

  sleep "$poll_interval"
  elapsed=$((elapsed + poll_interval))
done
