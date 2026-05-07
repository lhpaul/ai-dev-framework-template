#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=scripts/development-workflow/workflow-lib.sh
source "$SCRIPT_DIR/workflow-lib.sh"

# --- Single-instance guard ---
# Prevent two simultaneous invocations for the same PR. Uses an atomic mkdir
# lock directory (POSIX-guaranteed atomic) so two concurrent callers cannot
# both acquire the lock. The lock dir name includes the PR number so parallel
# runs for different PRs do not interfere with each other.
#
# Layout:
#   /tmp/pr-review-loop-<pr>.lockdir/   — lock directory (atomic creation)
#   /tmp/pr-review-loop-<pr>.lockdir/pid — PID of the owner process
#   /tmp/pr-review-loop-<pr>.lockdir/cmd — basename of script ($0) for verification
_PR_ARG=""
_skip_next=0
for _arg in "$@"; do
  if [ "$_skip_next" -eq 1 ]; then _skip_next=0; continue; fi
  case "$_arg" in
    --branch|--platform|--poll-interval|--max-wait) _skip_next=1 ;;
    [0-9]*) _PR_ARG="$_arg"; break ;;
  esac
done
unset _skip_next
_LOCK_DIR="/tmp/pr-review-loop-${_PR_ARG:-unknown}.lockdir"
_OWN_LOCK=0

if mkdir "$_LOCK_DIR" 2>/dev/null; then
  # We created the lock dir atomically — we own the lock.
  printf '%d\n' "$$"           > "$_LOCK_DIR/pid"
  printf '%s\n' "$(basename "$0")" > "$_LOCK_DIR/cmd"
  _OWN_LOCK=1
else
  # Lock dir already exists — check whether the recorded owner is still alive
  # and actually belongs to this script (guards against stale locks from crashes).
  _LOCK_PID="$(cat "$_LOCK_DIR/pid" 2>/dev/null || true)"
  _LOCK_CMD="$(cat "$_LOCK_DIR/cmd" 2>/dev/null || true)"
  if [ -n "$_LOCK_PID" ] && kill -0 "$_LOCK_PID" 2>/dev/null && [ "$_LOCK_CMD" = "$(basename "$0")" ]; then
    echo "ERROR: pr-review-loop.sh is already running for PR #${_PR_ARG:-unknown} (PID $_LOCK_PID). Exiting to prevent parallel execution." >&2
    print_kv RESULT escalate
    print_kv REASON lock_contention
    print_kv PR_NUMBER "${_PR_ARG:-}"
    exit 75  # EX_TEMPFAIL — lock contention; not a normal review result (0/1/2)
  fi
  # Stale lock (process gone or belongs to a different script) — reclaim atomically.
  # Use mv (atomic rename) to move the stale dir out of the way, then mkdir.
  # If two callers reach this point simultaneously, only one mv succeeds (rename
  # is atomic on POSIX); the loser's mv fails because the source is gone. Then
  # both try mkdir; only one succeeds and the other exits via the else branch.
  mv "$_LOCK_DIR" "${_LOCK_DIR}.stale.$$" 2>/dev/null || true
  rm -rf "${_LOCK_DIR}.stale.$$" 2>/dev/null || true
  if mkdir "$_LOCK_DIR" 2>/dev/null; then
    printf '%d\n' "$$"           > "$_LOCK_DIR/pid"
    printf '%s\n' "$(basename "$0")" > "$_LOCK_DIR/cmd"
    _OWN_LOCK=1
  else
    echo "ERROR: pr-review-loop.sh is already running for PR #${_PR_ARG:-unknown} (concurrent startup race). Exiting to prevent parallel execution." >&2
    print_kv RESULT escalate
    print_kv REASON lock_contention
    print_kv PR_NUMBER "${_PR_ARG:-}"
    exit 75
  fi
fi
trap '[ "$_OWN_LOCK" -eq 1 ] && rm -rf "$_LOCK_DIR"' EXIT

usage() {
  cat <<'EOF'
Usage: ./scripts/development-workflow/pr-review-loop.sh <pr-number> [--branch name] [--platform greptile] [--platform greptile,pr-agent,coderabbit,codex-github] [--poll-interval seconds] [--max-wait seconds]

Runs the automated PR review loop for one or more platforms in sequence. Before
triggering a new review, each platform checks for existing blocking findings. If
any platform reports blocking findings, the script stops immediately and exits 1.
If a platform times out or escalates, the script exits 2. If all configured
platforms are clean or skipped, the script exits 0. If a second instance is
detected for the same PR number, the script emits RESULT=escalate with
REASON=lock_contention and exits 75 (EX_TEMPFAIL).

Platform selection (in priority order):
  1. --platform flag(s) passed on the command line
  2. review.platforms list in .ai-dev-workflow.yaml at the repo root

Branch-type-aware default timeout:
  On spec/* and implementation-plan/* branches, Devin has no trigger condition and
  exits immediately with REASON=no_check_run. To avoid wasting the full 20-minute
  default wait budget on these branches, the script automatically reduces --max-wait
  to 60 s and --poll-interval to 30 s when the branch matches spec/* or
  implementation-plan/* and the caller did not pass the respective flag explicitly.
  poll_interval is also reduced so it stays below max_wait — the per-loop timeout
  check requires elapsed >= max_wait, which can only fire after at least one
  poll_interval has elapsed. Pass --max-wait and/or --poll-interval explicitly to
  override either value.

Outputs stable key=value lines including:
  RESULT=clean|needs_fixes|escalate|skipped
  PLATFORM_<n>_NAME / PLATFORM_<n>_RESULT
  REASON=lock_contention (when exit code is 75)
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

run_codex_github_review() {
  local pr_number="$1"
  local branch_name="$2"
  local poll_interval="$3"
  local max_wait="$4"
  local platform="codex-github"
  local bot_login="${CODEX_GITHUB_BOT_LOGIN:-codex-ai[bot]}"
  # GraphQL author.login returns the login WITHOUT the "[bot]" suffix that the
  # REST API uses. Strip it here so check_unresolved_threads comparisons work.
  local graphql_bot_login="${bot_login%\[bot\]}"
  local repo
  local reviewer_script
  local script_exit=0
  local thread_check_output=""
  local thread_check_status=0
  local unresolved_count=0

  require_gh
  cd_workflow_repo_root
  repo="$(repo_slug)"

  # Phase 1: Check for existing unresolved review threads from the codex bot
  set +e
  thread_check_output="$(check_unresolved_threads "$pr_number" "$repo" "$graphql_bot_login")"
  thread_check_status=$?
  set -e
  if [ "$thread_check_status" -eq 0 ]; then
    unresolved_count="$thread_check_output"
  fi

  if [ "$unresolved_count" -gt 0 ]; then
    print_kv RESULT needs_fixes
    print_kv PLATFORM "$platform"
    print_kv PR_NUMBER "$pr_number"
    print_kv BRANCH "$branch_name"
    print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
    print_kv REASON existing_findings
    print_kv COMMENT_COUNT "$unresolved_count"
    print_kv BLOCKING_COUNT "$unresolved_count"
    print_kv SUGGESTION_COUNT 0
    return 1
  fi

  # Phase 2: Trigger the codex-github review and wait for response
  reviewer_script="$(workflow_repo_root)/scripts/development-workflow/codex-github-reviewer.sh"

  local owner repo_name
  owner="$(printf '%s\n' "$repo" | cut -d/ -f1)"
  repo_name="$(printf '%s\n' "$repo" | cut -d/ -f2)"
  local max_retriggers
  max_retriggers="${CODEX_GITHUB_MAX_RETRIGGERS:-1}"
  case "$max_retriggers" in
    ''|*[!0-9]*) max_retriggers=1 ;;
  esac

  # Keep polling interval bounded by the wait budget to avoid zero-poll attempts
  # when a caller provides poll_interval > max_wait.
  local effective_poll_interval
  effective_poll_interval="$poll_interval"
  if [ "$effective_poll_interval" -gt "$max_wait" ]; then
    effective_poll_interval="$max_wait"
  fi
  set +e
  "$reviewer_script" "$pr_number" "$owner" "$repo_name" \
    --bot-login "$bot_login" \
    --poll-interval "$effective_poll_interval" \
    --max-wait "$max_wait" \
    --max-retriggers "$max_retriggers" >/dev/null 2>&1
  script_exit=$?
  set -e

  case "$script_exit" in
    0)
      print_kv RESULT clean
      print_kv PLATFORM "$platform"
      print_kv PR_NUMBER "$pr_number"
      print_kv BRANCH "$branch_name"
      print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
      print_kv COMMENT_COUNT 0
      print_kv BLOCKING_COUNT 0
      print_kv SUGGESTION_COUNT 0
      return 0
      ;;
    1)
      unresolved_count=0
      set +e
      thread_check_output="$(check_unresolved_threads "$pr_number" "$repo" "$graphql_bot_login")"
      thread_check_status=$?
      set -e
      if [ "$thread_check_status" -eq 0 ]; then
        unresolved_count="$thread_check_output"
      fi
      [ "$unresolved_count" -eq 0 ] && unresolved_count=1

      print_kv RESULT needs_fixes
      print_kv PLATFORM "$platform"
      print_kv PR_NUMBER "$pr_number"
      print_kv BRANCH "$branch_name"
      print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
      print_kv REASON unresolved_review_threads
      print_kv COMMENT_COUNT "$unresolved_count"
      print_kv BLOCKING_COUNT "$unresolved_count"
      print_kv SUGGESTION_COUNT 0
      return 1
      ;;
    *)
      print_kv RESULT escalate
      print_kv REASON timeout
      print_kv PLATFORM "$platform"
      print_kv PR_NUMBER "$pr_number"
      print_kv BRANCH "$branch_name"
      print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
      return 2
      ;;
  esac
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
  local existing_inline_blocking_count=0
  local inline_comment_count=0
  local review_state=""
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
                .state == "COMMENTED"
              )
            )
          | { path: "", line: 0, body: (.body // "review without body"), state: .state }
          | @json
        '
  )"
  existing_blocking_file="$(mktemp)"
  # Process inline comments first so existing_blocking_count reflects inline findings
  # before we evaluate COMMENTED reviews (used for the inline-findings gate below).
  while IFS= read -r comment_json; do
    [ -z "${comment_json:-}" ] && continue
    body="$(printf '%s\n' "$comment_json" | jq -r '.body')"
    [ -z "$body" ] && continue
    if printf '%s\n' "$body" | grep -qi "No Issues Found"; then continue; fi
    if printf '%s\n' "$body" | grep -q "^✅"; then continue; fi
    existing_blocking_count=$((existing_blocking_count + 1))
    printf '%s\n' "$comment_json" >> "$existing_blocking_file"
  done <<< "$existing_comments"
  # Snapshot the inline blocking count before processing reviews (used below).
  existing_inline_blocking_count="$existing_blocking_count"

  while IFS= read -r review_json; do
    [ -z "${review_json:-}" ] && continue
    body="$(printf '%s\n' "$review_json" | jq -r '.body')"
    review_state="$(printf '%s\n' "$review_json" | jq -r '.state // ""')"
    [ -z "$body" ] && continue
    if printf '%s\n' "$body" | grep -qi "No Issues Found"; then continue; fi
    if printf '%s\n' "$body" | grep -q "^✅"; then continue; fi
    # For COMMENTED reviews, only treat as blocking when:
    # (a) the body starts with "**Devin Review**" (Devin uses COMMENTED instead of
    #     CHANGES_REQUESTED regardless of finding severity), OR
    # (b) there are blocking inline comments from Devin (the COMMENTED review is the
    #     umbrella review object that accompanies those inline findings).
    # COMMENTED reviews with no inline findings are informational and not blocking.
    if [ "$review_state" = "COMMENTED" ]; then
      if printf '%s\n' "$body" | grep -qi "^\\*\\*Devin Review\\*\\*"; then
        : # falls through to blocking logic below
      elif [ "$existing_inline_blocking_count" -gt 0 ]; then
        : # COMMENTED review with inline findings — treat as blocking
      else
        continue  # COMMENTED review with no inline findings — not blocking
      fi
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
              .state == "COMMENTED"
            )
          )
        | {
            path: "",
            line: 0,
            body: (.body // "review without body"),
            state: .state
          }
        | @json
      '
  )"

  # Count blocking inline comments from this HEAD for the COMMENTED-with-findings check.
  inline_comment_count=0
  while IFS= read -r comment_json; do
    [ -z "${comment_json:-}" ] && continue
    body="$(printf '%s\n' "$comment_json" | jq -r '.body')"
    [ -z "$body" ] && continue
    if printf '%s\n' "$body" | grep -qi "No Issues Found"; then continue; fi
    if printf '%s\n' "$body" | grep -q "^✅"; then continue; fi
    comment_count=$((comment_count + 1))
    blocking_count=$((blocking_count + 1))
    inline_comment_count=$((inline_comment_count + 1))
    printf '%s\n' "$comment_json" >> "$blocking_lines_file"
  done <<< "$comments"

  while IFS= read -r review_json; do
    [ -z "${review_json:-}" ] && continue
    body="$(printf '%s\n' "$review_json" | jq -r '.body')"
    review_state="$(printf '%s\n' "$review_json" | jq -r '.state // ""')"
    [ -z "$body" ] && continue
    if printf '%s\n' "$body" | grep -qi "No Issues Found"; then continue; fi
    if printf '%s\n' "$body" | grep -q "^✅"; then continue; fi
    # For COMMENTED reviews, only treat as blocking when:
    # (a) the body starts with "**Devin Review**" (Devin uses COMMENTED instead of
    #     CHANGES_REQUESTED regardless of finding severity), OR
    # (b) there are blocking inline comments from Devin (the COMMENTED review is the
    #     umbrella review object that accompanies those inline findings).
    # Non-matching COMMENTED reviews with no inline comments are informational and
    # not blocking.
    if [ "$review_state" = "COMMENTED" ]; then
      if printf '%s\n' "$body" | grep -qi "^\\*\\*Devin Review\\*\\*"; then
        : # falls through to blocking logic below
      elif [ "$inline_comment_count" -gt 0 ]; then
        : # COMMENTED review with inline findings — treat as blocking
      else
        continue  # COMMENTED review with no inline comments — not blocking
      fi
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

run_pr_agent_review() {
  # PR-Agent posts all review output as plain PR issue comments — it does NOT submit
  # formal GitHub PR reviews (APPROVED/CHANGES_REQUESTED/COMMENTED). The summary
  # comment always contains "PR Reviewer Guide" in its body. Two stable body markers
  # distinguish clean from has-issues:
  #   "No major issues detected"                                → clean
  #   "Recommended focus areas for review" → may or may not be blocking (see below)
  #
  # PR-Agent always emits "Recommended focus areas for review" when it finds any
  # suggestion — including purely advisory ones. The bold labels inside that
  # section determine the verdict:
  #   Hard-blocker / security / compatibility labels → needs_fixes:
  #     Critical, Must Fix, Breaking Change, Security Concern,
  #     API Change, Backward Compatibility
  #   Explicitly-known advisory-only labels (non-blocking) → clean:
  #     Possible Issue, Edge Case, Logic Gap, Documentation Inconsistency
  #   Any other unrecognized label, or no labels parsed → needs_fixes (conservative)
  # Only return clean when every label found is in the explicit advisory list.
  #
  # Bot login is "github-actions[bot]" when using GITHUB_TOKEN. Override with
  # PR_AGENT_BOT_LOGIN when using a GitHub App token (e.g. for fork PR support).
  local pr_number="$1"
  local branch_name="$2"
  local poll_interval="$3"
  local max_wait="$4"
  local platform="pr-agent"
  local bot_login="${PR_AGENT_BOT_LOGIN:-github-actions[bot]}"
  local repo
  local head_sha=""
  local since_iso=""
  local elapsed=0
  local comment_body=""

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
  # Use the HEAD commit's push timestamp to scope comments to this review cycle.
  since_iso="$(gh api "repos/$repo/commits/$head_sha" --jq '.commit.committer.date // empty')"
  if [ -z "$since_iso" ]; then
    since_iso="$(date -u -v-24H +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -d '24 hours ago' +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo '1970-01-01T00:00:00Z')"
  fi

  _pr_agent_latest_comment() {
    local match_mode="${1:-strict_sha}"
    gh api "repos/$repo/issues/$pr_number/comments" --paginate \
      | jq -rs --arg bot "$bot_login" --arg sha "$head_sha" --arg since "$since_iso" --arg mode "$match_mode" '
          add // []
          | [.[]
             | select(
                 .user.login == $bot and
                 (
                   ($mode == "strict_sha" and ((.body // "") | contains($sha))) or
                   ($mode == "recent_or_sha" and (((.body // "") | contains($sha)) or .updated_at > $since))
                 ) and
                 ((.body // "") | test("PR Reviewer Guide"; "i"))
               )
            ]
          | sort_by(.updated_at)
          | last
          | .body // ""
        '
  }

  _pr_agent_classify() {
    local body="$1"
    local found_unknown label labels
    if [ -z "$body" ]; then
      printf 'none'
    elif printf '%s\n' "$body" | grep -q "No major issues detected"; then
      printf 'clean'
    elif printf '%s\n' "$body" | grep -q "Recommended focus areas for review"; then
      # Inspect every bold label in the section to classify conservatively:
      #   - Hard-blocker / security / compatibility label → needs_fixes immediately
      #     (Critical, Must Fix, Breaking Change, Security Concern,
      #      API Change, Backward Compatibility)
      #   - Explicitly-known advisory-only labels → skip (non-blocking)
      #     (Possible Issue, Edge Case, Logic Gap, Documentation Inconsistency)
      #   - Any other unrecognized label → needs_fixes (conservative)
      # If no labels are parsed at all, default to needs_fixes (unreadable format).
      found_unknown=0
      # Scope extraction to the "Recommended focus areas for review" section only.
      # PR-Agent comments may include other <details><summary><strong>…</strong>
      # blocks elsewhere (e.g. ticket/compliance metadata). Scanning the full body
      # would pick up those labels, and any unrecognized text would set found_unknown=1,
      # recreating the false-loop bug this classifier is meant to fix.
      # Strategy: use awk to collect all lines between the section marker and the
      # next section boundary (**bold header, </td>, <tr>, or ---), then extract
      # every <strong>…</strong> token from that window.
      # Parsing the whole section (not just <details> lines) ensures labels are
      # found even when PR-Agent formats a finding over multiple lines — for example
      # <details><summary><a ...> on one line and <strong>Possible Issue</strong>
      # on the next; anchoring to ^<details> would miss those labels and fall back
      # to needs_fixes for advisory-only reviews.
      labels="$(printf '%s\n' "$body" \
        | awk '/Recommended focus areas for review/{found=1; next}
               found && /^[[:space:]]*(\*\*|<\/td>|<tr>)|^---$/{found=0}
               found{print}' \
        | grep -oE '<strong>[^<]+</strong>' \
        | sed 's|<strong>||g;s|</strong>||g;s|^[[:space:]]*||;s|[[:space:]]*$||' \
        || true)"
      if [ -z "$labels" ]; then
        # No finding-label tokens found — treat as unknown/unreadable, be conservative.
        printf 'needs_fixes'
        return
      fi
      while IFS= read -r label; do
        [ -z "$label" ] && continue
        case "$label" in
          Critical|"Must Fix"|"Breaking Change"|"Security Concern"|"API Change"|"Backward Compatibility")
            # Hard-blocker or security/compatibility concern — block immediately.
            printf 'needs_fixes'
            return
            ;;
          "Possible Issue"|"Edge Case"|"Logic Gap"|"Documentation Inconsistency")
            # Explicitly-known advisory-only labels — non-blocking, keep scanning.
            ;;
          *)
            # Unrecognized label — treat conservatively as blocking.
            found_unknown=1
            ;;
        esac
      done <<EOF
$labels
EOF
      if [ "$found_unknown" -eq 1 ]; then
        printf 'needs_fixes'
      else
        printf 'clean'
      fi
    else
      printf 'escalate'
    fi
  }

  # --- Phase 1: Check for an existing PR-Agent summary comment on this HEAD ---
  comment_body="$(_pr_agent_latest_comment strict_sha)"
  local verdict
  verdict="$(_pr_agent_classify "$comment_body")"

  case "$verdict" in
    clean)
      print_kv RESULT clean
      print_kv PLATFORM "$platform"
      print_kv PR_NUMBER "$pr_number"
      print_kv BRANCH "$branch_name"
      print_kv REVIEW_COMMENT_ID ""
      print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
      print_kv COMMENT_COUNT 0
      print_kv BLOCKING_COUNT 0
      print_kv SUGGESTION_COUNT 0
      return 0
      ;;
    needs_fixes)
      print_kv RESULT needs_fixes
      print_kv PLATFORM "$platform"
      print_kv PR_NUMBER "$pr_number"
      print_kv BRANCH "$branch_name"
      print_kv REVIEW_COMMENT_ID ""
      print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
      print_kv REASON existing_findings
      print_kv COMMENT_COUNT 1
      print_kv BLOCKING_COUNT 1
      print_kv SUGGESTION_COUNT 0
      return 1
      ;;
    escalate)
      print_kv RESULT escalate
      print_kv REASON pr_agent_ambiguous_review
      print_kv PLATFORM "$platform"
      print_kv PR_NUMBER "$pr_number"
      print_kv BRANCH "$branch_name"
      print_kv REVIEW_COMMENT_ID ""
      print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
      print_kv COMMENT_COUNT 0
      print_kv BLOCKING_COUNT 0
      print_kv SUGGESTION_COUNT 0
      return 2
      ;;
  esac

  # --- Phase 2: Poll until PR-Agent posts its summary comment ---
  while :; do
    comment_body="$(_pr_agent_latest_comment recent_or_sha)"
    verdict="$(_pr_agent_classify "$comment_body")"

    if [ "$verdict" != "none" ]; then
      break
    fi

    if [ "$elapsed" -ge "$max_wait" ]; then
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

    sleep "$poll_interval"
    elapsed=$((elapsed + poll_interval))
  done

  # --- Phase 3: Classify the comment body ---
  case "$verdict" in
    clean)
      print_kv RESULT clean
      print_kv PLATFORM "$platform"
      print_kv PR_NUMBER "$pr_number"
      print_kv BRANCH "$branch_name"
      print_kv REVIEW_COMMENT_ID ""
      print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
      print_kv COMMENT_COUNT 0
      print_kv BLOCKING_COUNT 0
      print_kv SUGGESTION_COUNT 0
      return 0
      ;;
    needs_fixes)
      print_kv RESULT needs_fixes
      print_kv PLATFORM "$platform"
      print_kv PR_NUMBER "$pr_number"
      print_kv BRANCH "$branch_name"
      print_kv REVIEW_COMMENT_ID ""
      print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
      print_kv REASON existing_findings
      print_kv COMMENT_COUNT 1
      print_kv BLOCKING_COUNT 1
      print_kv SUGGESTION_COUNT 0
      return 1
      ;;
    *)
      print_kv RESULT escalate
      print_kv REASON pr_agent_ambiguous_review
      print_kv PLATFORM "$platform"
      print_kv PR_NUMBER "$pr_number"
      print_kv BRANCH "$branch_name"
      print_kv REVIEW_COMMENT_ID ""
      print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
      print_kv COMMENT_COUNT 0
      print_kv BLOCKING_COUNT 0
      print_kv SUGGESTION_COUNT 0
      return 2
      ;;
  esac
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

# Returns the validated THREAD_AUDIT_MAX_RETRIES value (a positive integer).
# If the environment variable is unset, empty, non-integer, or non-positive,
# emits a WARN on stderr and returns the default (3).
thread_audit_max_retries_value() {
  local value="${THREAD_AUDIT_MAX_RETRIES:-3}"
  if ! printf '%s' "$value" | grep -qE '^[0-9]+$' || [ "$value" -le 0 ] 2>/dev/null; then
    echo "WARN: THREAD_AUDIT_MAX_RETRIES must be a positive integer; defaulting to 3" >&2
    value=3
  fi
  printf '%s\n' "$value"
}

# Returns 0 when CodeRabbit may treat the PR as thread-clean for this pass.
# Returns 1 after emitting RESULT=needs_fixes (unresolved GraphQL threads).
# Returns 2 after emitting RESULT=escalate (thread page cap exceeded or
#   GraphQL failure after all retries exhausted).
# On transient GraphQL failure (exit 3 from check_unresolved_threads), retries
# up to THREAD_AUDIT_MAX_RETRIES times before escalating. Never returns 0 when
# the thread audit could not be completed — RESULT=clean is only emitted by the
# caller once this function returns 0 with a confirmed zero unresolved count.
coderabbit_thread_gate_clean() {
  local pr_number="$1" repo="$2" bot_login="$3" branch_name="$4"
  local platform="coderabbit"
  local out st
  local thread_audit_max_retries
  thread_audit_max_retries="$(thread_audit_max_retries_value)"
  local thread_audit_attempt=0
  # GraphQL author.login returns the login WITHOUT the "[bot]" suffix that the
  # REST API uses. Strip it here so check_unresolved_threads comparisons work.
  local graphql_bot_login="${bot_login%\[bot\]}"

  # check_unresolved_threads re-enables errexit internally; capture and restore
  # shellopts so set -e does not leak into run_coderabbit_review (dead rc capture).
  local prev_errexit
  prev_errexit="$(set +o | grep errexit)"

  while true; do
    thread_audit_attempt=$((thread_audit_attempt + 1))
    set +e
    out="$(check_unresolved_threads "$pr_number" "$repo" "$graphql_bot_login")"
    st=$?
    eval "$prev_errexit"

    if [ "$st" -eq 2 ]; then
      echo "WARN: check_unresolved_threads exceeded page cap for PR #$pr_number (CodeRabbit pass)" >&2
      print_kv RESULT escalate
      print_kv REASON unresolved_thread_check_incomplete
      print_kv PLATFORM "$platform"
      print_kv PR_NUMBER "$pr_number"
      print_kv BRANCH "$branch_name"
      print_kv REVIEW_COMMENT_ID ""
      print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
      print_kv COMMENT_COUNT 0
      print_kv BLOCKING_COUNT 0
      print_kv SUGGESTION_COUNT 0
      return 2
    fi

    if [ "$st" -eq 3 ]; then
      if [ "$thread_audit_attempt" -le "$thread_audit_max_retries" ]; then
        echo "WARN: check_unresolved_threads GraphQL failure for PR #$pr_number (CodeRabbit pass, attempt $thread_audit_attempt/$thread_audit_max_retries) — retrying" >&2
        sleep 5
        continue
      fi
      echo "ERROR: check_unresolved_threads GraphQL failure for PR #$pr_number (CodeRabbit pass) — all $thread_audit_attempt attempts ($thread_audit_max_retries retries) failed; escalating" >&2
      print_kv RESULT escalate
      print_kv REASON review_thread_audit_failed
      print_kv PLATFORM "$platform"
      print_kv PR_NUMBER "$pr_number"
      print_kv BRANCH "$branch_name"
      print_kv REVIEW_COMMENT_ID ""
      print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
      print_kv COMMENT_COUNT 0
      print_kv BLOCKING_COUNT 0
      print_kv SUGGESTION_COUNT 0
      return 2
    fi

    if [ "$st" -ne 0 ]; then
      echo "ERROR: check_unresolved_threads unexpected exit $st for PR #$pr_number (CodeRabbit pass) — escalating" >&2
      print_kv RESULT escalate
      print_kv REASON review_thread_audit_failed
      print_kv PLATFORM "$platform"
      print_kv PR_NUMBER "$pr_number"
      print_kv BRANCH "$branch_name"
      print_kv REVIEW_COMMENT_ID ""
      print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
      print_kv COMMENT_COUNT 0
      print_kv BLOCKING_COUNT 0
      print_kv SUGGESTION_COUNT 0
      return 2
    fi

    break
  done

  if [ "${out:-0}" -gt 0 ]; then
    print_kv RESULT needs_fixes
    print_kv REASON coderabbit_unresolved_review_threads
    print_kv PLATFORM "$platform"
    print_kv PR_NUMBER "$pr_number"
    print_kv BRANCH "$branch_name"
    print_kv REVIEW_COMMENT_ID ""
    print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
    print_kv COMMENT_COUNT "$out"
    print_kv BLOCKING_COUNT "$out"
    print_kv SUGGESTION_COUNT 0
    print_kv UNRESOLVED_THREAD_COUNT "$out"
    return 1
  fi
  return 0
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
        # Issue-comment activity means CodeRabbit finished this HEAD cycle, but unlike
        # a formal PR review it does not hit the `break` above — continue to Phase 3.
        break
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
        echo "INFO: CodeRabbit rate limit detected (retry $coderabbit_rate_limit_retries/$coderabbit_rate_limit_max_retries) — checking for SUCCESS commit status before waiting" >&2
        # --- Early SUCCESS check before retry wait ---
        # Check whether CodeRabbit already posted a SUCCESS commit status for the current
        # HEAD SHA. This happens when CodeRabbit signals the result via a commit status
        # during a rate-limit window on a parallel batch. If found, skip the retry wait
        # entirely and treat the PR as clean via coderabbit_status_success_fallback.
        local coderabbit_early_success_count
        coderabbit_early_success_count="$(
          gh api "repos/$repo/commits/$head_sha/statuses" --paginate \
            | jq -s '[.[].[] | select(
                    (.context // "" | ascii_downcase | test("coderabbit"))
                  )]
                  | group_by(.context) | map(max_by(.updated_at))
                  | map(select(.state == "success"))
                  | length'
        )"
        if [ "${coderabbit_early_success_count:-0}" -gt 0 ]; then
          # SUCCESS status can appear while older CodeRabbit review threads stay unresolved
          # on the PR. Do not short-circuit to clean until GraphQL thread audit passes —
          # same pattern as the timeout SUCCESS fallback below.
          local cr_early_gate_rc
          coderabbit_thread_gate_clean "$pr_number" "$repo" "$bot_login" "$branch_name"
          cr_early_gate_rc=$?
          if [ "$cr_early_gate_rc" -eq 0 ]; then
            echo "INFO: CodeRabbit SUCCESS commit-status found for HEAD $head_sha before retry wait — treating PR as clean (coderabbit_status_success_fallback)" >&2
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
          if [ "$cr_early_gate_rc" -eq 1 ] || [ "$cr_early_gate_rc" -eq 2 ]; then
            return "$cr_early_gate_rc"
          fi
        fi
        echo "INFO: no SUCCESS commit status found — waiting ${coderabbit_rate_limit_wait}s before re-triggering" >&2
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
          # SUCCESS status can appear while older CodeRabbit review threads stay unresolved
          # on the PR. Do not short-circuit to clean until GraphQL thread audit passes.
          coderabbit_thread_gate_clean "$pr_number" "$repo" "$bot_login" "$branch_name"
          cr_success_gate_rc=$?
          if [ "$cr_success_gate_rc" -eq 0 ]; then
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
          if [ "$cr_success_gate_rc" -eq 1 ] || [ "$cr_success_gate_rc" -eq 2 ]; then
            return "$cr_success_gate_rc"
          fi
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
  coderabbit_thread_gate_clean "$pr_number" "$repo" "$bot_login" "$branch_name"
  cr_phase3_gate_rc=$?
  if [ "$cr_phase3_gate_rc" -ne 0 ]; then
    return "$cr_phase3_gate_rc"
  fi
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
  # pr-agent is excluded (returns empty): its blocking signal comes from review state,
  # not inline threads, so mapping it to "github-actions" would incorrectly attribute
  # threads from any other GHA workflow to PR-Agent.
  case "$1" in
    coderabbit)   printf 'coderabbitai\n' ;;
    devin)        printf 'devin-ai-integration\n' ;;
    greptile)     printf 'greptile-apps\n' ;;
    pr-agent)     printf '\n' ;;
    codex-github) printf '%s\n' "${CODEX_GITHUB_BOT_LOGIN:-codex-ai[bot]}" ;;
    *)            printf '\n' ;;
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
  #   $1    pr_number  - PR number (integer)
  #   $2    repo       - "owner/repo" slug
  #   $3... bot_logins - one or more bot login strings (e.g. "coderabbitai", "devin-ai-integration")
  #
  # Bot logins are passed as individual positional arguments (not space-separated)
  # to ensure safe iteration in the comparison loop without word splitting.
  #
  # Re-enable errexit within this function. When called from a command substitution
  # with set +e active in the parent (as in the thread gate), the subshell inherits
  # set +e. Without this explicit re-enablement, gh api graphql failures inside this
  # function would be silently ignored and the function would always return exit 0,
  # making the caller's error-handling code unreachable.
  set -e
  local pr_number="$1"
  local repo="$2"
  shift 2
  # Remaining positional args are bot login strings; store in an array for safe iteration.
  local -a bot_logins=("$@")

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
      # Fail-safe: returning exit code 2 (page-cap exceeded) tells the caller to BLOCK
      # the PR rather than degrade — threads past page 10 would be silently ignored,
      # so a very large PR could otherwise be marked ready-for-human-review despite
      # unresolved threads beyond the cap. Exit 3 (below) is for transient GraphQL
      # failures; callers must escalate (not degrade) on exit 3 to prevent RESULT=clean
      # when the thread audit could not be completed.
      echo "WARN: check_unresolved_threads: exceeded $max_pages pages for PR #$pr_number; cannot confirm all threads checked" >&2
      return 2
    fi

    local result
    if [ -n "$cursor" ]; then
      result="$(gh api graphql \
        -f query="$graphql_query" \
        -f owner="$owner" -f repo="$repo_name" -F pr="$pr_number" -f cursor="$cursor" \
        --jq '.data.repository.pullRequest.reviewThreads')" \
        || { echo "WARN: check_unresolved_threads: GraphQL query failed for PR #$pr_number" >&2; return 3; }
    else
      result="$(gh api graphql \
        -f query="$graphql_query" \
        -f owner="$owner" -f repo="$repo_name" -F pr="$pr_number" \
        --jq '.data.repository.pullRequest.reviewThreads')" \
        || { echo "WARN: check_unresolved_threads: GraphQL query failed for PR #$pr_number" >&2; return 3; }
    fi

    # Use jq -r (not -re) for boolean/nullable fields: jq -e exits non-zero when the
    # output value is false or null, which would misinterpret valid values like
    # hasNextPage=false or isResolved=false as errors. Rely on gh api's own exit code
    # (caught above) for real API failures; use jq -r only for data extraction.
    has_next_page="$(printf '%s\n' "$result" | jq -r '.pageInfo.hasNextPage')"
    cursor="$(printf '%s\n' "$result" | jq -r '.pageInfo.endCursor // empty')"

    local thread_json
    while IFS= read -r thread_json; do
      [ -z "${thread_json:-}" ] && continue

      local is_resolved author body
      is_resolved="$(printf '%s\n' "$thread_json" | jq -r '.isResolved')"
      author="$(printf '%s\n' "$thread_json" | jq -r '.comments.nodes[0].author.login // ""')"
      body="$(printf '%s\n' "$thread_json" | jq -r '.comments.nodes[0].body // ""')"

      # Only count threads authored by configured bot logins.
      # Bot logins from the GraphQL API do not include the [bot] suffix.
      local is_bot=0
      local bot_login
      for bot_login in "${bot_logins[@]}"; do
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
    pr-agent)
      run_pr_agent_review "$pr_number" "$branch_name" "$poll_interval" "$max_wait"
      ;;
    codex-github)
      run_codex_github_review "$pr_number" "$branch_name" "$poll_interval" "$max_wait"
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
poll_interval_explicit=0
max_wait=1200
max_wait_explicit=0
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
      poll_interval_explicit=1
      shift 2
      ;;
    --max-wait)
      max_wait="$2"
      max_wait_explicit=1
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

# Branch-type-aware timeout: spec/* and implementation-plan/* branches produce
# REASON=no_check_run immediately when Devin has no trigger condition (non-implementation
# branches). Waiting the full 1200-second default wastes orchestrator budget.
# Apply a short max_wait=60 / poll_interval=30 default when the caller did not pass
# --max-wait / --poll-interval explicitly. poll_interval must be less than max_wait
# so the per-loop timeout check can fire within the budget.
if [ "$max_wait_explicit" -eq 0 ]; then
  case "$branch_name" in
    spec/*|implementation-plan/*)
      max_wait=60
      if [ "$poll_interval_explicit" -eq 0 ]; then
        poll_interval=30
      fi
      ;;
  esac
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
  # Build the array of bot logins from the configured platforms.
  # Using an array (not a space-separated string) prevents Bash glob expansion of
  # bracket characters in "[bot]" strings during iteration.
  declare -a unresolved_bot_logins=()
  for _platform in "${platforms[@]}"; do
    _login="$(bot_login_for_platform "$_platform")"
    [ -n "$_login" ] && unresolved_bot_logins+=("$_login")
  done

  unresolved_thread_count=0
  if [ "${#unresolved_bot_logins[@]}" -gt 0 ]; then
    # Do NOT use 2>&1 — stderr (WARN/ERROR messages) must remain on stderr so that only
    # the integer count appears on stdout for clean capture into unresolved_thread_count.
    # Bot logins are passed as individual positional args to avoid glob expansion.
    # Retry up to THREAD_AUDIT_MAX_RETRIES times on transient GraphQL failures (exit 3)
    # before escalating. Never degrade to treating the audit as clean on failure.
    thread_audit_max_retries="$(thread_audit_max_retries_value)"
    thread_audit_attempt=0
    thread_check_output=""
    thread_check_status=0
    while true; do
      thread_audit_attempt=$((thread_audit_attempt + 1))
      set +e
      thread_check_output="$(check_unresolved_threads "$pr_number" "$(repo_slug)" "${unresolved_bot_logins[@]}")"
      thread_check_status=$?
      set -e
      if [ "$thread_check_status" -eq 3 ] && [ "$thread_audit_attempt" -le "$thread_audit_max_retries" ]; then
        echo "WARN: check_unresolved_threads GraphQL failure (aggregate gate, attempt $thread_audit_attempt/$thread_audit_max_retries) — retrying" >&2
        sleep 5
        continue
      fi
      break
    done
    if [ "$thread_check_status" -eq 2 ]; then
      # Exit 2 = page-cap exceeded. Escalate: the audit was incomplete so we cannot
      # confirm threads past page 10 are resolved. This is not a fixable finding —
      # sending it through the fixer loop is pointless. Hard-stop for human inspection.
      echo "WARN: check_unresolved_threads exceeded page cap — escalating for manual inspection" >&2
      aggregate_result="escalate"
      aggregate_reason="unresolved_thread_check_incomplete"
      unresolved_thread_count=-1
    elif [ "$thread_check_status" -ne 0 ]; then
      # Exit 3 after all retries (or any other non-zero) = GraphQL audit failure.
      # Escalate: we cannot confirm threads are resolved, so RESULT=clean must not be
      # emitted. Never degrade gracefully — a silent bypass of the thread audit can
      # allow PRs with unresolved review threads to be labeled ready-for-human-review.
      echo "ERROR: check_unresolved_threads failed (exit $thread_check_status, $thread_audit_attempt attempts / $thread_audit_max_retries retries) — escalating (thread audit required)" >&2
      aggregate_result="escalate"
      aggregate_reason="review_thread_audit_failed"
      unresolved_thread_count=-1
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

# --- Automated Reviewer Loop Summary comment ---
# Post a summary comment to the PR on terminal exit paths so the Step 8c
# hasReviewSummary check is satisfied automatically. The comment body matches
# the regex used by workflow-next-action.sh and Protocol 90 Step 5.1:
#   "Automated Reviewer Loop Summary|Reviewer Loop Summary|No blocking PR feedback"
# Only post on `clean` and `escalate` exits. `needs_fixes` exits are non-terminal
# from the orchestrator's perspective (it re-runs after each fixer push), so
# posting a summary on every needs_fixes exit would create duplicate comments.
# The orchestrator is responsible for posting a "max cycles reached" summary when
# it decides not to dispatch another fixer (cycle >= max_cycles).
# `skipped` exits (no platforms configured) also do not post per protocol spec.
_post_review_summary() {
  local result="$1"
  local reason="$2"
  local platform_list="$3"
  local blocking="$4"
  local suggestions="$5"

  if [ -z "$pr_number" ]; then
    return 0
  fi

  local result_line
  case "$result" in
    clean)
      if [ "$blocking" -eq 0 ] && [ "$suggestions" -eq 0 ]; then
        result_line="clean — no blocking findings"
      else
        result_line="clean"
      fi
      ;;
    escalate)
      result_line="escalated (${reason:-unknown})"
      ;;
    *)
      result_line="$result"
      ;;
  esac

  local comment_body
  comment_body="$(cat <<EOF
### Automated Reviewer Loop Summary

**Result:** ${result_line}
**Platforms:** ${platform_list:-none}
**Findings:** ${blocking} blocking, ${suggestions} suggestions

*Posted automatically by \`pr-review-loop.sh\`.*
EOF
)"

  # Suppress errors — a failed comment post should not change the exit code.
  # The script's primary contract is the key=value output and exit code.
  set +e
  gh pr comment "$pr_number" --body "$comment_body" >/dev/null 2>&1
  set -e
}

case "$aggregate_result" in
  clean)
    _post_review_summary "$aggregate_result" "$aggregate_reason" \
      "$(IFS=,; printf '%s' "${platforms[*]}")" \
      "$total_blocking_count" "$total_suggestion_count"
    exit 0
    ;;
  skipped)
    exit 0
    ;;
  needs_fixes)
    exit 1
    ;;
  escalate)
    _post_review_summary "$aggregate_result" "$aggregate_reason" \
      "$(IFS=,; printf '%s' "${platforms[*]}")" \
      "$total_blocking_count" "$total_suggestion_count"
    exit 2
    ;;
  *)
    exit "${aggregate_status:-2}"
    ;;
esac
