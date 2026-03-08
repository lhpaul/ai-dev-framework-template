#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=scripts/development-workflow/workflow-lib.sh
source "$SCRIPT_DIR/workflow-lib.sh"

usage() {
  cat <<'EOF'
Usage: ./scripts/development-workflow/pr-review-loop.sh <pr-number> [--branch name] [--platform greptile] [--poll-interval seconds] [--max-wait seconds]

Triggers an automated PR review, polls for completion, classifies findings, and reports a stable result.
Outputs stable key=value lines and exits with:
  0 -> clean or skipped
  1 -> blocking findings present
  2 -> timeout / escalation
EOF
}

if [ "$#" -lt 1 ]; then
  usage >&2
  exit 64
fi

pr_number=""
branch_name=""
platform="greptile"
poll_interval=120
max_wait=1200
bot_login="greptile-apps[bot]"
trigger_comment="@greptile review"
trigger_author_login="${PR_REVIEW_TRIGGER_AUTHOR_LOGIN:-}"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --branch)
      branch_name="$2"
      shift 2
      ;;
    --platform)
      platform="$2"
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

if [ "$platform" != "greptile" ]; then
  print_kv RESULT skipped
  print_kv REASON "unsupported-platform"
  print_kv PR_NUMBER "$pr_number"
  print_kv PLATFORM "$platform"
  exit 0
fi

require_gh
cd_workflow_repo_root

repo="$(repo_slug)"

if [ -z "$branch_name" ]; then
  branch_name="$(gh pr view "$pr_number" --json headRefName --jq '.headRefName')"
fi

review_comment_id=""
review_window_start=""
if [ -n "$trigger_author_login" ]; then
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
else
  recent_trigger_comment="$(
    gh api "repos/$repo/issues/$pr_number/comments" --paginate \
      | jq --arg trigger "$trigger_comment" \
          --argjson max_wait "$max_wait" \
          '
            .[]
            | select(
                .body == $trigger and
                ((now - (.created_at | fromdateiso8601)) <= $max_wait)
              )
            | {id, created_at}
          ' \
      | jq -s 'sort_by(.created_at) | last // empty'
  )"
fi

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
  review_window_start="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  review_comment_url="$(gh pr comment "$pr_number" --body "$trigger_comment")"
  review_comment_id="$(printf '%s\n' "$review_comment_url" | grep -oE '[0-9]+$')"
fi

if [ -z "$review_comment_id" ]; then
  echo "Failed to determine review comment ID for PR #$pr_number." >&2
  exit 65
fi

blocking_lines_file="$(mktemp)"
trap 'rm -f "$blocking_lines_file"' EXIT

elapsed=0

while :; do
  thumbs_up="$(
    gh api "repos/$repo/issues/comments/$review_comment_id/reactions" \
      | jq --arg bot "$bot_login" '[.[] | select(.content == "+1" and .user.login == $bot)] | length'
  )"

  if [ "$thumbs_up" -gt 0 ]; then
    break
  fi

  if [ "$elapsed" -ge "$max_wait" ]; then
    print_kv RESULT escalate
    print_kv REASON timeout
    print_kv PLATFORM "$platform"
    print_kv PR_NUMBER "$pr_number"
    print_kv BRANCH "$branch_name"
    print_kv REVIEW_COMMENT_ID "$review_comment_id"
    print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
    exit 2
  fi

  sleep "$poll_interval"
  elapsed=$((elapsed + poll_interval))
done

comments="$(
  gh api "repos/$repo/pulls/$pr_number/comments" --paginate \
    | jq --arg bot "$bot_login" --arg since "$review_window_start" '
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
    | jq --arg bot "$bot_login" --arg since "$review_window_start" '
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

blocking_count=0
suggestion_count=0
comment_count=0

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
  index=1
  while IFS= read -r blocking_json; do
    [ -z "${blocking_json:-}" ] && continue
    print_kv "BLOCKING_${index}_PATH" "$(printf '%s\n' "$blocking_json" | jq -r '.path')"
    print_kv "BLOCKING_${index}_LINE" "$(printf '%s\n' "$blocking_json" | jq -r '.line')"
    print_kv_escaped "BLOCKING_${index}_BODY" "$(printf '%s\n' "$blocking_json" | jq -r '.body')"
    index=$((index + 1))
  done < "$blocking_lines_file"
  exit 1
fi

print_kv RESULT clean
print_kv PLATFORM "$platform"
print_kv PR_NUMBER "$pr_number"
print_kv BRANCH "$branch_name"
print_kv REVIEW_COMMENT_ID "$review_comment_id"
print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
print_kv COMMENT_COUNT "$comment_count"
print_kv BLOCKING_COUNT 0
print_kv SUGGESTION_COUNT "$suggestion_count"
exit 0
