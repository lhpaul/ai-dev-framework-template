#!/usr/bin/env bash

set -euo pipefail

# Use BASH_SOURCE[0] so that SCRIPT_DIR resolves correctly even when this
# script is sourced by the test harness (in HARNESS_MODE=1).  When executed
# directly, BASH_SOURCE[0] is identical to $0.
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/development-workflow/workflow-lib.sh
source "$SCRIPT_DIR/workflow-lib.sh"

# Effective harness mode: only active when HARNESS_MODE=1 AND the script is
# sourced (BASH_SOURCE[0] != $0). When executed directly with HARNESS_MODE=1
# set in the environment, treat it as a normal run so the lock guard and all
# signal traps remain active and protect the real PR.
_HARNESS_MODE_EFFECTIVE=0
if [ "${HARNESS_MODE:-0}" -eq 1 ] && [ "${BASH_SOURCE[0]}" != "$0" ]; then
  _HARNESS_MODE_EFFECTIVE=1
fi

# In harness mode (sourced), skip the single-instance lock guard entirely.
# The guard is irrelevant when the script is sourced by the test harness
# (no real PR is being processed and no lock directory should be created).
if [ "$_HARNESS_MODE_EFFECTIVE" -ne 1 ]; then

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
_PR_CONFIG_TMPFILE=""
# PID of the current background child (sleep or gh api) started by
# _interruptible_sleep / _interruptible_gh.  The TERM/INT handlers kill this
# child before removing the lock so the signal fires promptly instead of waiting
# for the foreground command to return on its own.
CURRENT_CHILD_PID=""

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
    echo "  Lock file: $_LOCK_DIR" >&2
    echo "  If the process is dead (stale lock from a crash), recover with:" >&2
    echo "    ./scripts/development-workflow/pr-review-loop.sh unlock ${_PR_ARG:-<pr>}" >&2
    echo "  Or manually: rm -rf $_LOCK_DIR" >&2
    print_kv RESULT escalate
    print_kv REASON lock_contention
    print_kv LOCK_DIR "$_LOCK_DIR"
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
    echo "  Lock file: $_LOCK_DIR" >&2
    echo "  If the process is dead (stale lock from a crash), recover with:" >&2
    echo "    ./scripts/development-workflow/pr-review-loop.sh unlock ${_PR_ARG:-<pr>}" >&2
    echo "  Or manually: rm -rf $_LOCK_DIR" >&2
    print_kv RESULT escalate
    print_kv REASON lock_contention
    print_kv LOCK_DIR "$_LOCK_DIR"
    print_kv PR_NUMBER "${_PR_ARG:-}"
    exit 75
  fi
fi
trap '[ "$_OWN_LOCK" -eq 1 ] && rm -rf "$_LOCK_DIR"; [ -n "$_PR_CONFIG_TMPFILE" ] && rm -f "$_PR_CONFIG_TMPFILE"' EXIT
# SIGTERM/SIGINT handlers: kill the current background child (if any) so the
# handler fires promptly even while a foreground sleep or gh api call is
# running, then clean up the lock dir and re-raise the signal so the parent
# process sees the correct exit status (death-by-signal, not 0).
# The re-raise pattern (trap - SIG; kill -SIG $$) is required because bash
# normally translates signal death to exit code 128+N, which callers rely on
# to distinguish a killed process from a clean exit.
trap '[ -n "$CURRENT_CHILD_PID" ] && kill -TERM "$CURRENT_CHILD_PID" 2>/dev/null || true; [ "$_OWN_LOCK" -eq 1 ] && rm -rf "$_LOCK_DIR"; trap - TERM; kill -TERM "$$"' TERM
trap '[ -n "$CURRENT_CHILD_PID" ] && kill -TERM "$CURRENT_CHILD_PID" 2>/dev/null || true; [ "$_OWN_LOCK" -eq 1 ] && rm -rf "$_LOCK_DIR"; trap - INT;  kill -INT  "$$"' INT

fi  # end HARNESS_MODE guard (single-instance lock guard skipped in harness mode)

# ---------------------------------------------------------------------------
# _interruptible_sleep <seconds>
#
# Runs "sleep <seconds>" as a background job, records its PID in
# CURRENT_CHILD_PID, then waits for it.  Bash's built-in `wait` IS
# interruptible by signals (unlike a foreground `sleep`), so TERM/INT traps
# fire promptly.  The trap handler kills CURRENT_CHILD_PID before removing
# the lock, completing the prompt-cleanup chain.
# ---------------------------------------------------------------------------
_interruptible_sleep() {
  sleep "$1" &
  CURRENT_CHILD_PID=$!
  wait "$CURRENT_CHILD_PID" 2>/dev/null || true
  CURRENT_CHILD_PID=""
}

usage() {
  cat <<'EOF'
Usage: ./scripts/development-workflow/pr-review-loop.sh <pr-number> [--branch name] [--platform greptile] [--platform greptile,devin,pr-agent,coderabbit,codex-github,haystack] [--phase-after-clean coderabbit] [--pre-after-clean-only] [--poll-interval seconds] [--max-wait seconds] [--post-final-summary] [--compare]
       ./scripts/development-workflow/pr-review-loop.sh unlock <pr-number>

Runs the automated PR review loop for one or more platforms in sequence. Before
triggering a new review, each platform checks for existing blocking findings. If
any platform reports blocking findings, the script stops immediately and exits 1.
If a platform times out or escalates, the script exits 2. If all configured
platforms are clean or skipped, the script exits 0. If a second instance is
detected for the same PR number, the script emits RESULT=escalate with
REASON=lock_contention and exits 75 (EX_TEMPFAIL).

Subcommands:
  unlock <pr-number>
    Remove the stale lock directory for a PR whose previous run crashed without
    cleaning up. Safe to run when no review loop is actively running for that PR.
    Use this to recover autonomously when lock_contention is reported but the
    recorded PID is no longer alive.

    Example:
      ./scripts/development-workflow/pr-review-loop.sh unlock 123

    The lock directory path is /tmp/pr-review-loop-<pr>.lockdir. You can also
    remove it manually with: rm -rf /tmp/pr-review-loop-<pr>.lockdir

--post-final-summary:
  Post the "Automated Reviewer Loop Summary" comment even when the result is
  needs_fixes. Use this when the orchestrator has reached cycle >= max_cycles and
  will not dispatch another fixer — i.e. the run is terminal regardless of the
  script exit code. On clean and escalate exits the summary is always posted
  (this flag has no additional effect for those exits).

--compare:
  Run all configured platforms to completion regardless of individual verdicts
  (disables the short-circuit on the first blocking platform). After all platforms
  run, the overall exit code and RESULT are identical to what normal mode would
  produce: the first platform that would have blocked in config order governs.
  Per-platform verdicts are emitted as COMPARE_VERDICT_<n>_PLATFORM /
  COMPARE_VERDICT_<n>_RESULT key=value lines, and one row is appended to
  docs/workflow/retro-metrics-platforms.md. Intended for platform evaluation only —
  not for normal orchestration where early exit is desired.

--phase-after-clean:
  Mark one or more platforms as second-phase reviewers that should run only after
  earlier platforms are clean. This does not override normal platform order; it
  emits PHASE_AFTER_CLEAN_* key=value telemetry and annotates the summary so the
  value of the second-phase reviewer can be measured. When omitted, the script
  reads review.phase_after_clean from .ai-dev-workflow.yaml when present.

--pre-after-clean-only:
  Run only the configured platforms that are not listed in phase-after-clean.
  Use this for draft PR gates that must clear all pre-after-clean reviewers before
  converting the PR to non-draft and allowing after-clean reviewers to run.

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

Large-diff poll-window extension:
  CodeRabbit takes significantly longer to post its review on PRs with a large
  number of changed files (e.g., release PRs or sync-template PRs). When the
  caller did not pass --max-wait explicitly, the script fetches the PR's changed-
  files count and extends max_wait when it exceeds a threshold.

  Environment variables (both optional):
    LARGE_DIFF_THRESHOLD  — changed-files count above which the extension applies
                            (default: 50; must be a positive integer)
    LARGE_DIFF_MAX_WAIT   — extended max_wait in seconds for large-diff PRs
                            (default: 2400, i.e. 40 minutes; must be a positive integer)

  The extension is suppressed when --max-wait is passed explicitly. The emitted
  key=value output includes CHANGED_FILES_COUNT so callers can inspect the value.

Outputs stable key=value lines including:
  RESULT=clean|needs_fixes|needs_rerun|escalate|skipped
  PLATFORM_<n>_NAME / PLATFORM_<n>_RESULT
  REASON=lock_contention (when exit code is 75)
  CHANGED_FILES_COUNT=<n> (PR's changed-files count, or -1 when the fetch failed)
  LARGE_DIFF_EXTENDED=1 (present and set to 1 when max_wait was extended for a large-diff PR)
  REASON=late_review_threads (when post-clean recheck finds new unresolved threads)
  COMPARE_MODE=1 (when --compare is active)
  COMPARE_VERDICT_<n>_PLATFORM / COMPARE_VERDICT_<n>_RESULT (when --compare is active)
  PHASE_AFTER_CLEAN_ENABLED=0|1
  PHASE_AFTER_CLEAN_STARTED=0|1
  PHASE_AFTER_CLEAN_PLATFORM_LIST=<comma-separated platforms>
  PHASE_AFTER_CLEAN_FILTERED_OUT=<comma-separated platforms> (when configured phase platforms are absent from this invocation)
  PHASE_AFTER_CLEAN_GATE_RESULT=<result> (emitted only after the phase starts)
  PHASE_AFTER_CLEAN_SKIP_REASON=<result> (emitted when the phase never starts)
  PHASE_AFTER_CLEAN_NET_NEW_BLOCKER=0|1 (1 when a second-phase platform blocks)
  POST_CLEAN_RECHECK=0|1 (1 when the post-clean wait-and-recheck ran)
  LATE_THREADS_FOUND=<N> (count of newly-found unresolved threads; -1 on audit failure; 0 when POST_CLEAN_RECHECK=0)

Environment variables:
  POST_CLEAN_WAIT=<seconds>          Override the post-clean recheck wait (default: 30). Set to 0 to run immediately.
  SKIP_POST_CLEAN_RECHECK=1          Suppress the post-clean recheck. Set by callers re-dispatching after a prior
                                     late-thread fix cycle, so the corrective invocation does not recheck again.
  FALLBACK_THREAD_SETTLE_WAIT=<sec>  Seconds to wait before running the thread audit when using
                                     coderabbit_status_success_fallback (default: 60). CodeRabbit can set a
                                     SUCCESS commit status before finishing its async inline-thread posting; this
                                     wait lets those threads arrive so the audit does not produce a false-clean.
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

append_phase_after_clean_platforms() {
  local raw="$1"
  local entry
  IFS=',' read -r -a entries <<< "$raw"
  for entry in "${entries[@]}"; do
    entry="$(trim "$entry")"
    [ -n "$entry" ] && phase_after_clean_platforms+=("$entry")
  done
}

array_contains_value() {
  local needle="$1"
  shift
  local value
  for value in "$@"; do
    [ "$needle" = "$value" ] && return 0
  done
  return 1
}

is_phase_after_clean_platform() {
  local candidate="$1"
  array_contains_value "$candidate" "${phase_after_clean_platforms[@]:-}"
}

filter_pre_after_clean_platforms() {
  local configured_platform
  declare -a filtered=()
  for configured_platform in "${platforms[@]:-}"; do
    if ! is_phase_after_clean_platform "$configured_platform"; then
      filtered+=("$configured_platform")
    fi
  done
  if [ "${#filtered[@]}" -gt 0 ]; then
    platforms=("${filtered[@]}")
  else
    platforms=()
  fi
}

filter_phase_after_clean_platforms() {
  local phase_platform configured_platform matched
  declare -a filtered=()
  declare -a filtered_out=()
  for phase_platform in "${phase_after_clean_platforms[@]:-}"; do
    matched=0
    for configured_platform in "${platforms[@]:-}"; do
      if [ "$phase_platform" = "$configured_platform" ]; then
        filtered+=("$phase_platform")
        matched=1
        break
      fi
    done
    [ "$matched" -eq 0 ] && filtered_out+=("$phase_platform")
  done
  if [ "${#filtered[@]}" -gt 0 ]; then
    phase_after_clean_platforms=("${filtered[@]}")
  else
    phase_after_clean_platforms=()
  fi
  if [ "${#filtered_out[@]}" -gt 0 ]; then
    phase_after_clean_filtered_out="$(IFS=,; printf '%s' "${filtered_out[*]}")"
  else
    phase_after_clean_filtered_out=""
  fi
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

    _interruptible_sleep "$poll_interval"
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
  local bot_login="${CODEX_GITHUB_BOT_LOGIN:-chatgpt-codex-connector[bot]}"
  # REST API endpoints (e.g. /pulls/{n}/reviews, /issues/{n}/comments) return
  # bot logins WITH the "[bot]" suffix (e.g. "chatgpt-codex-connector[bot]").
  # GraphQL API returns bot logins WITHOUT the "[bot]" suffix
  # (e.g. "chatgpt-codex-connector"). Strip it here so check_unresolved_threads,
  # which queries GraphQL, compares against the correct login form.
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

run_claude_code_action_review() {
  local pr_number="$1"
  local branch_name="$2"
  local poll_interval="$3"
  local max_wait="$4"
  local platform="claude-code-action"
  local bot_login="${CLAUDE_CODE_ACTION_BOT_LOGIN:-claude[bot]}"
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

  # Phase 1: Check for existing unresolved review threads from the Claude Code Action bot
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

  # Phase 2: Dispatch the Claude Code Action workflow and wait for completion
  reviewer_script="$(workflow_repo_root)/scripts/development-workflow/claude-code-action-reviewer.sh"

  local owner repo_name
  owner="$(printf '%s\n' "$repo" | cut -d/ -f1)"
  repo_name="$(printf '%s\n' "$repo" | cut -d/ -f2)"

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
    --max-wait "$max_wait" >/dev/null 2>&1
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
    2)
      print_kv RESULT escalate
      print_kv REASON timeout
      print_kv PLATFORM "$platform"
      print_kv PR_NUMBER "$pr_number"
      print_kv BRANCH "$branch_name"
      print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
      return 2
      ;;
    *)
      print_kv RESULT escalate
      print_kv REASON unavailable
      print_kv PLATFORM "$platform"
      print_kv PR_NUMBER "$pr_number"
      print_kv BRANCH "$branch_name"
      print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
      return 2
      ;;
  esac
}

run_copilot_review() {
  # Requests GitHub Copilot as a reviewer via the GitHub Pulls API, polls the
  # pull-request reviews endpoint until Copilot posts its verdict, and maps the
  # review state to the standard exit-code contract:
  #   0 → RESULT=clean      (APPROVED or COMMENTED only)
  #   1 → RESULT=needs_fixes (CHANGES_REQUESTED)
  #   2 → RESULT=escalate   (timeout or Copilot feature unavailable)
  #
  # Env var override:
  #   COPILOT_BOT_LOGIN  — override the default bot login
  #                        (default: "copilot-pull-request-reviewer[bot]")
  local pr_number="$1"
  local branch_name="$2"
  local poll_interval="$3"
  local max_wait="$4"
  local platform="copilot"
  local bot_login="${COPILOT_BOT_LOGIN:-copilot-pull-request-reviewer[bot]}"
  local repo
  local elapsed=0
  local review_state=""

  require_gh
  cd_workflow_repo_root
  repo="$(repo_slug)"

  local owner repo_name
  owner="$(printf '%s\n' "$repo" | cut -d/ -f1)"
  repo_name="$(printf '%s\n' "$repo" | cut -d/ -f2)"

  # Step 1: Request Copilot as a reviewer (idempotent — GitHub silently
  # deduplicates reviewer requests if Copilot is already requested).
  set +e
  gh api "repos/$owner/$repo_name/pulls/$pr_number/requested_reviewers" \
    --method POST \
    --field 'reviewers[]=copilot' > /dev/null 2>&1
  local request_exit=$?
  set -e

  if [ "$request_exit" -ne 0 ]; then
    # Request failed — Copilot feature likely not enabled on this repository.
    print_kv RESULT escalate
    print_kv REASON unavailable
    print_kv PLATFORM "$platform"
    print_kv PR_NUMBER "$pr_number"
    print_kv BRANCH "$branch_name"
    print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
    return 2
  fi

  # Step 2: Poll the pull-request reviews endpoint until Copilot posts a review.
  local effective_poll_interval="$poll_interval"
  if [ "$effective_poll_interval" -gt "$max_wait" ]; then
    effective_poll_interval="$max_wait"
  fi
  [ "$effective_poll_interval" -le 0 ] && effective_poll_interval=1

  while [ "$elapsed" -lt "$max_wait" ]; do
    set +e
    review_state="$(gh api "repos/$owner/$repo_name/pulls/$pr_number/reviews" \
      --jq "[.[] | select(.user.login == \"$bot_login\")] | last | .state // empty" \
      2>/dev/null)"
    set -e

    case "$review_state" in
      APPROVED)
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
      CHANGES_REQUESTED)
        print_kv RESULT needs_fixes
        print_kv PLATFORM "$platform"
        print_kv PR_NUMBER "$pr_number"
        print_kv BRANCH "$branch_name"
        print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
        print_kv REASON changes_requested
        print_kv COMMENT_COUNT 1
        print_kv BLOCKING_COUNT 1
        print_kv SUGGESTION_COUNT 0
        return 1
        ;;
      COMMENTED)
        # Non-blocking comment only — treat as clean.
        print_kv RESULT clean
        print_kv PLATFORM "$platform"
        print_kv PR_NUMBER "$pr_number"
        print_kv BRANCH "$branch_name"
        print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
        print_kv COMMENT_COUNT 1
        print_kv BLOCKING_COUNT 0
        print_kv SUGGESTION_COUNT 1
        return 0
        ;;
    esac

    _interruptible_sleep "$effective_poll_interval"
    elapsed=$(( elapsed + effective_poll_interval ))
  done

  # Timeout — no review posted within max_wait.
  print_kv RESULT escalate
  print_kv REASON timeout
  print_kv PLATFORM "$platform"
  print_kv PR_NUMBER "$pr_number"
  print_kv BRANCH "$branch_name"
  print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
  return 2
}

run_haystack_review() {
  # Runs haystack-reviewer.sh for the given PR and maps its exit codes to the
  # standard pr-review-loop key-value output contract.
  #
  # Haystack triage runs synchronously (no polling loop required). The companion
  # script handles the timeout internally via a configurable env var or --timeout flag.
  #
  # Exit code mapping from haystack-reviewer.sh:
  #   0 → RESULT=clean    (no blocking findings)
  #   1 → RESULT=needs_fixes (one or more blocking findings)
  #   2 → RESULT=skipped / REASON=timeout → propagated as RESULT=escalate
  #   3 → RESULT=skipped / REASON=unavailable → propagated as RESULT=skipped
  local pr_number="$1"
  local branch_name="$2"
  # poll_interval and max_wait passed for interface consistency; haystack runs
  # synchronously so poll_interval is not used. max_wait is passed as --timeout.
  local poll_interval="$3"
  local max_wait="$4"
  local platform="haystack"
  local reviewer_script
  local script_exit=0
  local script_output=""
  local blocking_count=0
  local suggestion_count=0
  local comment_count=0

  require_gh
  cd_workflow_repo_root

  reviewer_script="$(workflow_repo_root)/scripts/development-workflow/haystack-reviewer.sh"

  local owner repo_name repo
  repo="$(repo_slug)"
  owner="$(printf '%s\n' "$repo" | cut -d/ -f1)"
  repo_name="$(printf '%s\n' "$repo" | cut -d/ -f2)"

  # Haystack runs synchronously; honor the caller-provided max_wait budget directly.
  # (No poll_interval floor needed — unlike polling-based reviewers, haystack triage
  # completes in a single invocation.)
  local effective_timeout
  effective_timeout="$max_wait"

  set +e
  script_output="$("$reviewer_script" "$pr_number" "$owner" "$repo_name" --timeout "$effective_timeout" 2>/dev/null)"
  script_exit=$?
  set -e

  # Parse output from the companion script (key=value lines on stdout).
  blocking_count="$(printf '%s\n' "$script_output" | grep '^BLOCKING_COUNT=' | cut -d= -f2 | head -1)"
  suggestion_count="$(printf '%s\n' "$script_output" | grep '^SUGGESTION_COUNT=' | cut -d= -f2 | head -1)"
  comment_count="$(printf '%s\n' "$script_output" | grep '^COMMENT_COUNT=' | cut -d= -f2 | head -1)"

  # Default to 0 if any field is missing.
  blocking_count="${blocking_count:-0}"
  suggestion_count="${suggestion_count:-0}"
  comment_count="${comment_count:-0}"

  case "$script_exit" in
    0)
      print_kv RESULT clean
      print_kv PLATFORM "$platform"
      print_kv PR_NUMBER "$pr_number"
      print_kv BRANCH "$branch_name"
      print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
      print_kv COMMENT_COUNT "$comment_count"
      print_kv BLOCKING_COUNT 0
      print_kv SUGGESTION_COUNT "$suggestion_count"
      return 0
      ;;
    1)
      # Ensure blocking_count >= 1 even if stdout parsing failed.
      [ "$blocking_count" -eq 0 ] && blocking_count=1
      print_kv RESULT needs_fixes
      print_kv PLATFORM "$platform"
      print_kv PR_NUMBER "$pr_number"
      print_kv BRANCH "$branch_name"
      print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
      print_kv REASON haystack_blocking_findings
      print_kv COMMENT_COUNT "$comment_count"
      print_kv BLOCKING_COUNT "$blocking_count"
      print_kv SUGGESTION_COUNT "$suggestion_count"
      return 1
      ;;
    2)
      print_kv RESULT escalate
      print_kv REASON timeout
      print_kv PLATFORM "$platform"
      print_kv PR_NUMBER "$pr_number"
      print_kv BRANCH "$branch_name"
      print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
      return 2
      ;;
    *)
      # Exit 3 (UNAVAILABLE) and any unexpected exit code → skipped.
      print_kv RESULT skipped
      print_kv REASON unavailable
      print_kv PLATFORM "$platform"
      print_kv PR_NUMBER "$pr_number"
      print_kv BRANCH "$branch_name"
      print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
      print_kv COMMENT_COUNT 0
      print_kv BLOCKING_COUNT 0
      print_kv SUGGESTION_COUNT 0
      return 0
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

    _interruptible_sleep "$poll_interval"
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
  #   Hard-blocker / security / compatibility labels → needs_fixes (case-insensitive):
  #     Critical, Must Fix, Breaking Change, Security Concern,
  #     API Change, Backward Compatibility
  #   All other labels → clean (advisory-only — PR-Agent uses a wide variety of
  #     quality/style labels that are non-blocking by nature)
  #   No labels parseable → needs_fixes (unreadable format — conservative)
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

  # Common helper: fetch the matching PR-Agent comment and return one of its fields.
  # Parameters: field (e.g. "body" or "html_url"), match_mode (optional, default "strict_sha").
  # Returns the empty string when no matching comment is found.
  _pr_agent_latest_comment_field() {
    local field="$1"
    local match_mode="${2:-strict_sha}"
    gh api "repos/$repo/issues/$pr_number/comments" --paginate \
      | jq -rs --arg bot "$bot_login" --arg sha "$head_sha" --arg since "$since_iso" \
               --arg mode "$match_mode" --arg field "$field" '
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
          | .[$field] // ""
        '
  }

  _pr_agent_latest_comment() {
    _pr_agent_latest_comment_field "body" "${1:-strict_sha}"
  }

  _pr_agent_latest_comment_url() {
    _pr_agent_latest_comment_field "html_url" "${1:-strict_sha}"
  }

  # Extract <strong>LABEL</strong> tokens from the "Recommended focus areas for
  # review" section of a PR-Agent comment body.
  # Returns newline-delimited label strings (empty when section is absent or
  # yields no tokens). Shared by _pr_agent_extract_advisory_labels and
  # _pr_agent_classify to avoid duplicating the awk/grep/sed pipeline.
  _pr_agent_extract_focus_labels() {
    local body="$1"
    if ! printf '%s\n' "$body" | grep -qF "Recommended focus areas for review"; then
      return
    fi
    printf '%s\n' "$body" \
      | awk '/Recommended focus areas for review/{found=1; next}
             found && /^[[:space:]]*(\*\*|<\/td>|<tr>)|^---$/{found=0}
             found{print}' \
      | grep -oE '<strong>[^<]+</strong>' \
      | sed 's|<strong>||g;s|</strong>||g;s|^[[:space:]]*||;s|[[:space:]]*$||' \
      || true
  }

  # Extract advisory (non-blocking) labels from a PR-Agent comment body.
  # Outputs labels pipe-delimited (|) for safe single-line transport through
  # print_kv. Only labels that are NOT in the hard-blocker set are returned.
  # Returns empty string when body has no "Recommended focus areas for review"
  # section, or when all labels are blocking (handled by _pr_agent_classify).
  _pr_agent_extract_advisory_labels() {
    local body="$1"
    local label label_lower advisory_labels=""
    local labels
    labels="$(_pr_agent_extract_focus_labels "$body")"
    if [ -n "$labels" ]; then
      while IFS= read -r label; do
        [ -z "$label" ] && continue
        label_lower="$(printf '%s' "$label" | tr '[:upper:]' '[:lower:]')"
        case "$label_lower" in
          critical|"must fix"|"breaking change"|"security concern"|"api change"|"backward compatibility")
            # Hard-blocker — skip; these are handled by _pr_agent_classify as needs_fixes.
            ;;
          *)
            if [ -n "$advisory_labels" ]; then
              advisory_labels="${advisory_labels}|${label}"
            else
              advisory_labels="$label"
            fi
            ;;
        esac
      done <<_PR_AGENT_ADVISORY_LABELS_
$labels
_PR_AGENT_ADVISORY_LABELS_
    fi
    printf '%s' "$advisory_labels"
  }

  # Returns pipe-delimited labels that match "possible issue" (case-insensitive).
  # Input:  pipe-delimited advisory labels string (e.g. "Possible Issue|Edge Case")
  # Output: pipe-delimited matching labels, or empty string.
  _extract_possible_issue_labels() {
    local advisory="$1"
    local result=""
    local label label_lower
    local _labels_normalized
    _labels_normalized="$(printf '%s' "$advisory" | tr '|' '\n')"
    while IFS= read -r label; do
      [ -z "$label" ] && continue
      # Trim leading and trailing whitespace before comparing (defensive — labels
      # from _pr_agent_extract_advisory_labels are already trimmed by sed, but
      # callers may pass labels with surrounding spaces).
      label="${label#"${label%%[![:space:]]*}"}"
      label="${label%"${label##*[![:space:]]}"}"
      [ -z "$label" ] && continue
      label_lower="$(printf '%s' "$label" | tr '[:upper:]' '[:lower:]')"
      if [ "$label_lower" = "possible issue" ]; then
        if [ -n "$result" ]; then
          result="${result}|${label}"
        else
          result="$label"
        fi
      fi
    done <<_EXTRACT_POSSIBLE_ISSUE_LABELS_
$_labels_normalized
_EXTRACT_POSSIBLE_ISSUE_LABELS_
    printf '%s' "$result"
  }

  # Evaluate "Possible Issue" advisory labels found in a PR-Agent clean result.
  # "Possible Issue" findings are always treated as acknowledged without dispatching
  # a code-reviewer agent. In practice these findings have never been real blockers
  # for this repo type; the dispatch loop caused fix-round spirals (issue #511 pattern).
  # Returns:
  #   0  — always (no "Possible Issue" label found, or finding acknowledged immediately)
  run_pr_agent_possible_issue_evaluation() {
    local advisory_labels="$1"  # pipe-delimited, already extracted from comment
    # comment_body ($2), pr_number_eval ($3), branch_name_eval ($4) unused — kept for
    # signature compatibility with the call site.

    local possible_issue_labels
    possible_issue_labels="$(_extract_possible_issue_labels "$advisory_labels")"

    # Short-circuit: no "Possible Issue" label present.
    if [ -z "$possible_issue_labels" ]; then
      return 0
    fi

    # Always acknowledge immediately — do not dispatch a code-reviewer agent.
    print_kv POSSIBLE_ISSUE_EVAL_OUTCOME "acknowledged"
    return 0
  }

  _pr_agent_classify() {
    local body="$1"
    local label label_lower labels
    if [ -z "$body" ]; then
      printf 'none'
    elif printf '%s\n' "$body" | grep -q "No major issues detected"; then
      printf 'clean'
    elif printf '%s\n' "$body" | grep -q "Recommended focus areas for review"; then
      # Inspect every bold label in the section to classify.
      # Labels are lowercased before matching (case-insensitive — PR-Agent
      # sometimes varies capitalisation across runs).
      #   - Hard-blocker / security / compatibility labels → needs_fixes immediately
      #     (critical, must fix, breaking change, security concern,
      #      api change, backward compatibility)
      #   - All other labels → non-blocking (advisory).
      #     PR-Agent uses a wide variety of quality labels (Race Condition, Logic Error,
      #     Inconsistent Error Handling, Performance Concern, Possible Issue, etc.)
      #     that are advisory in nature. Security-critical concerns are always
      #     labelled one of the hard-blocker patterns above by PR-Agent.
      #   - If no labels are parseable → needs_fixes (unreadable format — conservative)
      labels="$(_pr_agent_extract_focus_labels "$body")"
      if [ -z "$labels" ]; then
        # No finding-label tokens found — treat as unknown/unreadable, be conservative.
        printf 'needs_fixes'
        return
      fi
      while IFS= read -r label; do
        [ -z "$label" ] && continue
        # Normalize to lowercase for case-insensitive matching.
        # PR-Agent occasionally varies label capitalisation across runs.
        label_lower="$(printf '%s' "$label" | tr '[:upper:]' '[:lower:]')"
        case "$label_lower" in
          critical|"must fix"|"breaking change"|"security concern"|"api change"|"backward compatibility")
            # Hard-blocker or security/compatibility concern — block immediately.
            printf 'needs_fixes'
            return
            ;;
          *)
            # All other labels are treated as advisory-only (non-blocking).
            # PR-Agent uses a wide variety of quality/style labels (Race Condition,
            # Logic Error, Inconsistent Error Handling, Performance Concern, etc.)
            # that represent code-quality suggestions, not security/breaking issues.
            # Security-critical concerns are always separately labelled one of the
            # hard-blocker patterns above.
            ;;
        esac
      done <<_PR_AGENT_LABELS_
$labels
_PR_AGENT_LABELS_
      # No hard-blocker label was found — all labels are advisory.
      printf 'clean'
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
      local _advisory_labels _comment_url _advisory_entry _eval_status
      _advisory_labels="$(_pr_agent_extract_advisory_labels "$comment_body")"
      if [ -n "$_advisory_labels" ]; then
        _comment_url="$(_pr_agent_latest_comment_url strict_sha)"
        _advisory_entry="${_advisory_labels}@@@${_comment_url}"
      else
        _advisory_entry=""
      fi
      # Evaluate any "Possible Issue" advisory labels before emitting clean.
      _eval_status=0
      run_pr_agent_possible_issue_evaluation \
        "$_advisory_labels" "$comment_body" "$pr_number" "$branch_name" || _eval_status=$?
      if [ "$_eval_status" -eq 3 ]; then
        # Fix was pushed — signal to caller to re-run the loop on the new HEAD.
        print_kv RESULT needs_rerun
        print_kv PLATFORM "$platform"
        print_kv PR_NUMBER "$pr_number"
        print_kv BRANCH "$branch_name"
        print_kv REVIEW_COMMENT_ID ""
        print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
        print_kv COMMENT_COUNT 0
        print_kv BLOCKING_COUNT 0
        print_kv SUGGESTION_COUNT 0
        [ -n "$_advisory_entry" ] && print_kv ADVISORY_LABELS "$_advisory_entry"
        return 3
      fi
      print_kv RESULT clean
      print_kv PLATFORM "$platform"
      print_kv PR_NUMBER "$pr_number"
      print_kv BRANCH "$branch_name"
      print_kv REVIEW_COMMENT_ID ""
      print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
      print_kv COMMENT_COUNT 0
      print_kv BLOCKING_COUNT 0
      print_kv SUGGESTION_COUNT 0
      [ -n "$_advisory_entry" ] && print_kv ADVISORY_LABELS "$_advisory_entry"
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

    _interruptible_sleep "$poll_interval"
    elapsed=$((elapsed + poll_interval))
  done

  # --- Phase 3: Classify the comment body ---
  case "$verdict" in
    clean)
      local _advisory_labels _comment_url _advisory_entry _eval_status
      _advisory_labels="$(_pr_agent_extract_advisory_labels "$comment_body")"
      if [ -n "$_advisory_labels" ]; then
        _comment_url="$(_pr_agent_latest_comment_url recent_or_sha)"
        _advisory_entry="${_advisory_labels}@@@${_comment_url}"
      else
        _advisory_entry=""
      fi
      # Evaluate any "Possible Issue" advisory labels before emitting clean.
      _eval_status=0
      run_pr_agent_possible_issue_evaluation \
        "$_advisory_labels" "$comment_body" "$pr_number" "$branch_name" || _eval_status=$?
      if [ "$_eval_status" -eq 3 ]; then
        # Fix was pushed — signal to caller to re-run the loop on the new HEAD.
        print_kv RESULT needs_rerun
        print_kv PLATFORM "$platform"
        print_kv PR_NUMBER "$pr_number"
        print_kv BRANCH "$branch_name"
        print_kv REVIEW_COMMENT_ID ""
        print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
        print_kv COMMENT_COUNT 0
        print_kv BLOCKING_COUNT 0
        print_kv SUGGESTION_COUNT 0
        [ -n "$_advisory_entry" ] && print_kv ADVISORY_LABELS "$_advisory_entry"
        return 3
      fi
      print_kv RESULT clean
      print_kv PLATFORM "$platform"
      print_kv PR_NUMBER "$pr_number"
      print_kv BRANCH "$branch_name"
      print_kv REVIEW_COMMENT_ID ""
      print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
      print_kv COMMENT_COUNT 0
      print_kv BLOCKING_COUNT 0
      print_kv SUGGESTION_COUNT 0
      [ -n "$_advisory_entry" ] && print_kv ADVISORY_LABELS "$_advisory_entry"
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

check_unreplied_rest_comments() {
  # Count CodeRabbit root review comments that have received no human (non-bot) reply.
  # "Root" means in_reply_to_id == null (the original comment, not a reply).
  #
  # Unlike check_unresolved_threads (GraphQL reviewThreads), this uses the REST
  # pulls-comments endpoint which includes outside-diff comments (line == null /
  # "LNone" in the GitHub UI). These outside-diff comments never create proper
  # GitHub review threads and are therefore invisible to the GraphQL query, but
  # they appear in the GitHub PR page as unresolved findings that reviewers can see.
  #
  # A root comment is considered "replied" when at least one reply comment exists
  # whose author is NOT the CodeRabbit bot (i.e., a human or agent acknowledgment).
  # CodeRabbit's own auto-acknowledgment replies do not count.
  # Comments containing "✅ Addressed" in the body are also excluded (self-resolved).
  #
  # Root REST comments whose corresponding GraphQL review thread is already resolved
  # (isResolved=true) are also excluded. This prevents false-positive "unreplied"
  # counts when a reviewer resolves a thread via the GitHub UI without adding a reply:
  # the GraphQL isResolved flag reflects the true resolved state, so any REST comment
  # that belongs to an already-resolved thread must not block the review loop.
  # The caller supplies the set of resolved root comment database IDs via $4.
  #
  # Arguments:
  #   $1  pr_number              - PR number (integer)
  #   $2  repo                   - "owner/repo" slug
  #   $3  bot_login              - Full bot login including [bot] suffix (e.g. "coderabbitai[bot]")
  #                                REST API returns the full login; unlike GraphQL, no stripping needed.
  #   $4  resolved_ids_json      - (optional) JSON array of integer database IDs for root comments
  #                                whose GraphQL thread is already resolved (isResolved=true).
  #                                Pass "[]" or omit to skip this filter.
  #
  # Prints the count of unreplied root CodeRabbit comments on stdout.
  # Exit codes: 0 = success, 3 = REST API failure.
  local pr_number="$1"
  local repo="$2"
  local bot_login="$3"
  local resolved_ids_json="${4:-[]}"

  local result
  result="$(
    gh api "repos/$repo/pulls/$pr_number/comments" --paginate 2>/dev/null \
    | jq -s --arg bot "$bot_login" --argjson resolved_ids "$resolved_ids_json" '
        # gh api --paginate | jq -s produces [[page1_items], [page2_items], ...].
        # Use .[][] to flatten pages before selecting individual comment objects.
        #
        # Build the set of root-comment IDs that have received a human (non-bot) reply.
        # Exclude the primary bot login AND any other GitHub bot accounts (login ends with "[bot]").
        (
          [.[][] | select(
            .in_reply_to_id != null and
            .user.login != $bot and
            (.user.login | test("\\[bot\\]$") | not)
          ) | .in_reply_to_id] | unique
        ) as $human_replied_ids
        # Count root CR comments that have NOT been acknowledged by a human reply,
        # whose body does not self-resolve with "✅ Addressed", and whose GraphQL
        # review thread has not already been resolved (isResolved=true).
        | [.[][] | select(
            .user.login == $bot and
            .in_reply_to_id == null and
            ((.body // "") | test("✅ Addressed") | not)
          ) | select(
            .id as $id |
            ($human_replied_ids | index($id)) == null
          ) | select(
            .id as $id |
            ($resolved_ids | index($id)) == null
          )] | length
      '
  )" || {
    echo "WARN: check_unreplied_rest_comments: REST query failed for PR #$pr_number" >&2
    return 3
  }

  printf '%d\n' "${result:-0}"
}

auto_reply_unreplied_rest_comments() {
  # Post a brief acknowledgement reply to each unreplied CodeRabbit REST review
  # comment that has no corresponding resolved GraphQL thread (i.e., outside-diff
  # comments with no GraphQL thread representation).  Called by
  # coderabbit_thread_gate_clean after the GraphQL thread audit passes but the
  # REST supplement still reports unreplied outside-diff comments.  Replying
  # satisfies the check_unreplied_rest_comments gate so the loop can advance to
  # RESULT=clean without requiring manual intervention.
  #
  # Arguments:
  #   $1  pr_number              - PR number (integer)
  #   $2  repo                   - "owner/repo" slug
  #   $3  bot_login              - Full bot login including [bot] suffix
  #   $4  resolved_ids_json      - JSON array of already-resolved root comment IDs
  #
  # Prints the number of replies successfully posted on stdout.
  # Exit codes: 0 = all replies posted (or nothing to reply to),
  #             1 = one or more replies failed (partial — some may have been posted).
  local pr_number="$1"
  local repo="$2"
  local bot_login="$3"
  local resolved_ids_json="${4:-[]}"
  # This reply is an automated acknowledgement only — it does not assert that the
  # specific comment content was addressed. It is posted solely to satisfy the
  # check_unreplied_rest_comments gate for outside-diff comments that have no
  # corresponding GraphQL review thread and therefore cannot be resolved via the
  # normal thread-resolution mechanism. All GraphQL review threads have already
  # been verified resolved before this function is called.
  local reply_body="Acknowledged — outside-diff comment noted. All review threads for this PR have been resolved via the standard review process."

  # Fetch IDs of root CodeRabbit comments that need a reply (same filter logic
  # as check_unreplied_rest_comments, but returns IDs instead of a count).
  local unreplied_ids
  unreplied_ids="$(
    gh api "repos/$repo/pulls/$pr_number/comments" --paginate 2>/dev/null \
    | jq -s --arg bot "$bot_login" --argjson resolved_ids "$resolved_ids_json" '
        (
          [.[][] | select(
            .in_reply_to_id != null and
            .user.login != $bot and
            (.user.login | test("\\[bot\\]$") | not)
          ) | .in_reply_to_id] | unique
        ) as $human_replied_ids
        | [.[][] | select(
            .user.login == $bot and
            .in_reply_to_id == null and
            ((.body // "") | test("✅ Addressed") | not)
          ) | select(
            .id as $id |
            ($human_replied_ids | index($id)) == null
          ) | select(
            .id as $id |
            ($resolved_ids | index($id)) == null
          ) | .id]
      '
  )" || {
    echo "WARN: auto_reply_unreplied_rest_comments: REST query failed for PR #$pr_number" >&2
    return 1
  }

  local reply_count=0
  local fail_count=0
  local comment_id
  while IFS= read -r comment_id; do
    [ -z "$comment_id" ] && continue
    local reply_json
    reply_json="$(jq -n --arg body "$reply_body" '{"body": $body}')"
    if printf '%s' "$reply_json" \
         | gh api "repos/$repo/pulls/$pr_number/comments/$comment_id/replies" \
             --method POST \
             --input - \
             --silent > /dev/null 2>&1; then
      reply_count=$((reply_count + 1))
      echo "INFO: auto-replied to REST comment $comment_id on PR #$pr_number" >&2
    else
      fail_count=$((fail_count + 1))
      echo "WARN: auto_reply_unreplied_rest_comments: failed to reply to comment $comment_id on PR #$pr_number" >&2
    fi
  done < <(printf '%s\n' "$unreplied_ids" | jq -r '.[]')

  printf '%d\n' "$reply_count"
  [ "$fail_count" -eq 0 ]
}

get_resolved_thread_comment_ids() {
  # Fetch the database IDs of root comments from already-resolved GraphQL review
  # threads on a PR. These IDs are used by check_unreplied_rest_comments to skip
  # REST comments whose corresponding thread was resolved via the GitHub UI
  # (isResolved=true), even when no non-bot reply exists on that thread.
  #
  # A thread's "root comment" is its first comment; its databaseId matches the
  # REST pulls-comments API .id field, enabling cross-API correlation.
  #
  # Arguments:
  #   $1  pr_number      - PR number (integer)
  #   $2  repo           - "owner/repo" slug
  #   $3  graphql_bot_login - Bot login WITHOUT [bot] suffix (as returned by GraphQL API)
  #
  # Prints a compact JSON array of integer IDs on stdout, e.g. [123456, 789012].
  # Prints "[]" when no resolved threads exist or on any API failure (non-fatal).
  # Exit codes: always 0 (failures are non-fatal; caller receives "[]").
  local pr_number="$1"
  local repo="$2"
  local graphql_bot_login="$3"

  local owner repo_name
  owner="$(printf '%s\n' "$repo" | cut -d/ -f1)"
  repo_name="$(printf '%s\n' "$repo" | cut -d/ -f2)"

  # GraphQL query: paginate reviewThreads, fetch first comment databaseId per thread.
  # Select only resolved threads whose first comment was authored by the bot.
  local graphql_query
  graphql_query='query($owner:String!,$repo:String!,$pr:Int!,$cursor:String){repository(owner:$owner,name:$repo){pullRequest(number:$pr){reviewThreads(first:100,after:$cursor){pageInfo{hasNextPage endCursor}nodes{isResolved comments(first:1){nodes{databaseId author{login}}}}}}}}'

  local all_ids="[]"
  local cursor=""
  local has_next_page="true"
  local page=0
  local max_pages=10

  while [ "$has_next_page" = "true" ]; do
    page=$((page + 1))
    if [ "$page" -gt "$max_pages" ]; then
      echo "WARN: get_resolved_thread_comment_ids: exceeded $max_pages pages for PR #$pr_number — returning partial results" >&2
      break
    fi

    local result
    if [ -n "$cursor" ]; then
      result="$(gh api graphql \
        -f query="$graphql_query" \
        -f owner="$owner" -f repo="$repo_name" -F pr="$pr_number" -f cursor="$cursor" \
        --jq '.data.repository.pullRequest.reviewThreads' 2>/dev/null)" || {
        echo "WARN: get_resolved_thread_comment_ids: GraphQL query failed for PR #$pr_number — returning partial results" >&2
        break
      }
    else
      result="$(gh api graphql \
        -f query="$graphql_query" \
        -f owner="$owner" -f repo="$repo_name" -F pr="$pr_number" \
        --jq '.data.repository.pullRequest.reviewThreads' 2>/dev/null)" || {
        echo "WARN: get_resolved_thread_comment_ids: GraphQL query failed for PR #$pr_number — returning partial results" >&2
        break
      }
    fi

    has_next_page="$(printf '%s\n' "$result" | jq -r '.pageInfo.hasNextPage')"
    cursor="$(printf '%s\n' "$result" | jq -r '.pageInfo.endCursor // empty')"
    if [ "$has_next_page" = "true" ] && [ -z "$cursor" ]; then
      echo "WARN: get_resolved_thread_comment_ids: hasNextPage=true but endCursor is empty for PR #$pr_number — returning partial results" >&2
      break
    fi

    # Accumulate databaseIds of root comments from resolved bot-authored threads.
    local page_ids
    page_ids="$(printf '%s\n' "$result" \
      | jq --arg bot "$graphql_bot_login" '
          [.nodes[] |
            select(.isResolved == true) |
            select(.comments.nodes[0].author.login == $bot) |
            .comments.nodes[0].databaseId
          ]
        ')" || continue

    all_ids="$(printf '%s\n%s\n' "$all_ids" "$page_ids" \
      | jq -s 'add | unique')" || continue
  done

  printf '%s\n' "$all_ids"
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
  # REST API endpoints (e.g. /pulls/{n}/reviews, /issues/{n}/comments) return
  # bot logins WITH the "[bot]" suffix (e.g. "coderabbit-ai[bot]").
  # GraphQL API returns bot logins WITHOUT the "[bot]" suffix
  # (e.g. "coderabbit-ai"). Strip it here so check_unresolved_threads,
  # which queries GraphQL, compares against the correct login form.
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

  # --- Supplementary REST check for outside-diff comments ---
  # GraphQL reviewThreads only sees comments anchored to diff lines. CodeRabbit
  # sometimes posts comments on lines outside the PR diff (line == null); these
  # never create proper GitHub review threads and are invisible to the GraphQL
  # query above, but they ARE visible in the GitHub PR UI as unresolved findings.
  # Detect them via the REST pulls-comments endpoint and require a human reply
  # before allowing RESULT=clean.
  #
  # Fetch the database IDs of root comments from already-resolved GraphQL threads
  # so that check_unreplied_rest_comments can skip them. When a reviewer resolves
  # a thread via the GitHub UI (isResolved=true), the REST comment is still present
  # but the thread is already resolved — it must not block the review loop.
  local resolved_ids_json
  set +e
  resolved_ids_json="$(get_resolved_thread_comment_ids "$pr_number" "$repo" "$graphql_bot_login")"
  eval "$prev_errexit"
  resolved_ids_json="${resolved_ids_json:-[]}"

  local rest_unreplied_raw rest_check_st
  set +e
  rest_unreplied_raw="$(check_unreplied_rest_comments "$pr_number" "$repo" "$bot_login" "$resolved_ids_json")"
  rest_check_st=$?
  eval "$prev_errexit"

  if [ "$rest_check_st" -eq 0 ] && [ "${rest_unreplied_raw:-0}" -gt 0 ]; then
    # All GraphQL threads are resolved, but the REST supplement still sees
    # unreplied outside-diff comments.  Auto-reply to each one so the gate
    # can advance without requiring manual intervention.
    echo "INFO: ${rest_unreplied_raw} unreplied CodeRabbit REST comment(s) on PR #$pr_number — auto-replying" >&2
    local auto_reply_st auto_replied_count
    set +e
    auto_replied_count="$(auto_reply_unreplied_rest_comments "$pr_number" "$repo" "$bot_login" "$resolved_ids_json")"
    auto_reply_st=$?
    eval "$prev_errexit"
    echo "INFO: auto-replied to ${auto_replied_count:-0} REST comment(s) on PR #$pr_number" >&2

    if [ "$auto_reply_st" -ne 0 ]; then
      # One or more replies failed; fall back to needs_fixes so the agent can
      # address the remaining comments manually.
      echo "WARN: auto-reply failed for one or more REST comments on PR #$pr_number — returning needs_fixes" >&2
      print_kv RESULT needs_fixes
      print_kv REASON coderabbit_unreplied_rest_comments
      print_kv PLATFORM "$platform"
      print_kv PR_NUMBER "$pr_number"
      print_kv BRANCH "$branch_name"
      print_kv REVIEW_COMMENT_ID ""
      print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
      print_kv COMMENT_COUNT "${rest_unreplied_raw:-0}"
      print_kv BLOCKING_COUNT "${rest_unreplied_raw:-0}"
      print_kv SUGGESTION_COUNT 0
      print_kv UNRESOLVED_THREAD_COUNT "${rest_unreplied_raw:-0}"
      return 1
    fi
    # Re-validate the gate after auto-replies to confirm the count is now zero.
    # A partial success from auto_reply_unreplied_rest_comments (exit 0 but some
    # replies silently dropped) would otherwise cause a false clean return.
    local recheck_raw recheck_st
    set +e
    recheck_raw="$(check_unreplied_rest_comments "$pr_number" "$repo" "$bot_login" "$resolved_ids_json")"
    recheck_st=$?
    eval "$prev_errexit"
    if [ "$recheck_st" -ne 0 ]; then
      # Re-check REST query failed — cannot confirm gate is clean; treat as
      # needs_fixes so the agent re-inspects rather than claiming false clean.
      echo "WARN: REST re-check failed (exit $recheck_st) after auto-reply on PR #$pr_number — returning needs_fixes" >&2
      print_kv RESULT needs_fixes
      print_kv REASON coderabbit_unreplied_rest_comments
      print_kv PLATFORM "$platform"
      print_kv PR_NUMBER "$pr_number"
      print_kv BRANCH "$branch_name"
      print_kv REVIEW_COMMENT_ID ""
      print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
      print_kv COMMENT_COUNT "${rest_unreplied_raw:-0}"
      print_kv BLOCKING_COUNT "${rest_unreplied_raw:-0}"
      print_kv SUGGESTION_COUNT 0
      print_kv UNRESOLVED_THREAD_COUNT "${rest_unreplied_raw:-0}"
      return 1
    fi
    if [ "${recheck_raw:-0}" -gt 0 ]; then
      echo "WARN: ${recheck_raw} unreplied REST comment(s) remain after auto-reply on PR #$pr_number — returning needs_fixes" >&2
      print_kv RESULT needs_fixes
      print_kv REASON coderabbit_unreplied_rest_comments
      print_kv PLATFORM "$platform"
      print_kv PR_NUMBER "$pr_number"
      print_kv BRANCH "$branch_name"
      print_kv REVIEW_COMMENT_ID ""
      print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
      print_kv COMMENT_COUNT "${recheck_raw:-0}"
      print_kv BLOCKING_COUNT "${recheck_raw:-0}"
      print_kv SUGGESTION_COUNT 0
      print_kv UNRESOLVED_THREAD_COUNT "${recheck_raw:-0}"
      return 1
    fi
    # Gate confirmed clean after auto-replies — fall through to return 0.
  fi
  if [ "$rest_check_st" -ne 0 ]; then
    # REST failure is non-fatal: the GraphQL thread check already passed.
    # Log the warning and allow RESULT=clean to proceed.
    echo "WARN: check_unreplied_rest_comments failed (exit $rest_check_st) for PR #$pr_number — skipping outside-diff supplement" >&2
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

  # --- Phase 0: Detect and auto-resume CodeRabbit auto-pause before entering the poll loop ---
  # CodeRabbit auto-pauses after 3+ rapid pushes in quick succession and posts a
  # "Reviews paused" issue comment. When paused, it posts no review for the current HEAD,
  # so Phase 1 finds 0 blocking findings (trivially true) and Phase 2 times out with
  # RESULT=skipped/REASON=no_review (exit 0 — treated as clean by callers).
  #
  # Root cause of the Batch 52 incident (PR #650): the pause comment was posted BEFORE
  # the HEAD commit timestamp (since_iso), so the Phase 2 detection (which filters by
  # since_iso) never matched it. The script returned clean with CodeRabbit having not
  # reviewed the latest commit.
  #
  # Fix: inspect the MOST RECENT CodeRabbit issue comment on the PR without a since_iso
  # filter. If that latest comment contains a "Reviews paused" marker, CodeRabbit is still
  # in a paused state — post "@coderabbitai resume" immediately and reset since_iso so the
  # resulting review is captured. Set coderabbit_phase0_retrigger=1 so Phase 2 skips its
  # own pause-detection block and does not double-post.
  local coderabbit_phase0_retrigger=0
  local phase0_most_recent_body
  # Use -rs with add // [] to flatten all paginated pages into a single array
  # before sorting, so the "most recent" selection spans the entire comment history
  # rather than being limited to the last item on whichever page arrived last.
  phase0_most_recent_body="$(
    gh api "repos/$repo/issues/$pr_number/comments" --paginate \
      | jq -rs --arg bot "$bot_login" '
          add // []
          | map(select(.user.login == $bot))
          | sort_by(.created_at)
          | last
          | .body // ""
        '
  )"
  if printf '%s\n' "$phase0_most_recent_body" | grep -qi "reviews\? paused"; then
    echo "INFO: CodeRabbit is in auto-pause state (most recent CR comment is a pause banner) — posting @coderabbitai resume before entering poll loop" >&2
    local phase0_resume_since_iso
    # Capture the timestamp BEFORE posting so any same-second CodeRabbit response
    # is still within the detection window (queries use strict > $since_iso).
    phase0_resume_since_iso="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    if gh pr comment "$pr_number" --body "@coderabbitai resume" >/dev/null 2>&1; then
      coderabbit_phase0_retrigger=1
      since_iso="$phase0_resume_since_iso"
      echo "INFO: @coderabbitai resume posted; since_iso reset to $since_iso" >&2
    else
      # The resume post failed while CodeRabbit is still paused. If we proceed without
      # resetting since_iso, the timeout guard at the end of the poll loop may miss the
      # old pause banner (its timestamp predates since_iso) and fall through to a false-
      # clean RESULT=skipped/REASON=no_review. Escalate immediately instead.
      echo "ERROR: failed to post @coderabbitai resume for pre-existing pause banner — escalating to avoid false-clean no_review exit" >&2
      print_kv RESULT escalate
      print_kv REASON rate_limit_max_retries
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
  fi

  # --- Phase 2: Poll for CodeRabbit review completion ---
  # CodeRabbit signals completion by posting a COMMENTED review after the HEAD commit.
  # Unlike Devin, there are no check runs to monitor — we rely solely on the review.
  #
  local coderabbit_review_count=0
  local coderabbit_any_activity=0
  # Initialize retrigger flag from Phase 0 so Phase 2 does not double-post a resume.
  local coderabbit_retrigger_attempted=$coderabbit_phase0_retrigger
  local coderabbit_rate_limit_retries=0
  local coderabbit_rate_limit_max_retries="${CODERABBIT_RATE_LIMIT_MAX_RETRIES:-2}"
  local coderabbit_rate_limit_wait="${CODERABBIT_RATE_LIMIT_WAIT:-180}"
  local coderabbit_no_trigger_timeout="${CODERABBIT_NO_TRIGGER_TIMEOUT:-600}"
  local coderabbit_no_trigger_retriggers=0
  if ! [[ "$coderabbit_rate_limit_max_retries" =~ ^[0-9]+$ ]]; then
    echo "WARN: CODERABBIT_RATE_LIMIT_MAX_RETRIES must be a non-negative integer; defaulting to 2" >&2
    coderabbit_rate_limit_max_retries=2
  fi
  if ! [[ "$coderabbit_rate_limit_wait" =~ ^[0-9]+$ ]] || [ "$coderabbit_rate_limit_wait" -le 0 ]; then
    echo "WARN: CODERABBIT_RATE_LIMIT_WAIT must be a positive integer; defaulting to 180" >&2
    coderabbit_rate_limit_wait=180
  fi
  if ! [[ "$coderabbit_no_trigger_timeout" =~ ^[0-9]+$ ]] || [ "$coderabbit_no_trigger_timeout" -le 0 ]; then
    echo "WARN: CODERABBIT_NO_TRIGGER_TIMEOUT must be a positive integer; defaulting to 600" >&2
    coderabbit_no_trigger_timeout=600
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
    # Exclude "Reviews paused" comments (pause marker), "rate limit" comments (rate-limit
    # marker), and "Reviews resumed" acknowledgement comments — none of these represent a
    # completed review and must not trigger an early break from the poll loop.
    if [ "$coderabbit_any_activity" -eq 0 ]; then
      local activity_count
      activity_count="$(
        gh api "repos/$repo/issues/$pr_number/comments" --paginate \
          | jq -s --arg bot "$bot_login" --arg since "$since_iso" '
              [.[].[] | select(
                  .user.login == $bot and
                  .created_at > $since and
                  ((.body // "") | test("Reviews paused|review paused"; "i") | not) and
                  ((.body // "") | test("rate.?limit"; "i") | not) and
                  ((.body // "") | test("reviews resumed"; "i") | not)
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
    # "@coderabbitai resume" to resume the paused review. Only attempt once.
    if [ "$coderabbit_any_activity" -eq 0 ] && [ "$coderabbit_retrigger_attempted" -eq 0 ] && [ "$elapsed" -ge "$((max_wait / 2))" ]; then
      # Check if the most recent CodeRabbit bot comment created after since_iso contains
      # a "Reviews paused" marker. Use since_iso filter to avoid false positives from
      # historical pause banners from prior HEAD commits.
      local paused_count
      paused_count="$(
        gh api "repos/$repo/issues/$pr_number/comments" --paginate \
          | jq -s --arg bot "$bot_login" --arg since "$since_iso" '
              [.[].[] | select(
                  .user.login == $bot and
                  .created_at > $since and
                  ((.body // "") | test("Reviews paused|review paused"; "i"))
              )] | length
            '
      )"
      if [ "${paused_count:-0}" -gt 0 ]; then
        echo "INFO: CodeRabbit reviews are paused — posting @coderabbitai resume to trigger a fresh review" >&2
        if gh pr comment "$pr_number" --body "@coderabbitai resume" >/dev/null 2>&1; then
          coderabbit_retrigger_attempted=1
          # Reset the elapsed timer to give the retrigger time to complete.
          elapsed=0
        else
          echo "WARN: failed to post @coderabbitai resume — will not reset timer" >&2
          coderabbit_retrigger_attempted=1
        fi
        _interruptible_sleep "$poll_interval"
        elapsed=$((elapsed + poll_interval))
        continue
      fi
    fi

    # --- Auto-retrigger: detect CodeRabbit silent non-trigger after push ---
    # CodeRabbit sometimes does not auto-trigger after a push commit: no review
    # appears, no "Reviews paused" comment, and no rate-limit comment — CodeRabbit
    # simply stays silent. When no activity has been seen after
    # CODERABBIT_NO_TRIGGER_TIMEOUT seconds (default 600 s), post
    # "@coderabbitai review" to force a fresh review. Uses
    # CODERABBIT_RATE_LIMIT_MAX_RETRIES as the combined retrigger cap so callers
    # have a single knob for total retrigger attempts across both mechanisms.
    if [ "$coderabbit_any_activity" -eq 0 ] \
        && [ "$coderabbit_retrigger_attempted" -eq 0 ] \
        && [ "$coderabbit_no_trigger_retriggers" -lt "$coderabbit_rate_limit_max_retries" ] \
        && [ "$elapsed" -ge "$coderabbit_no_trigger_timeout" ]; then
      # Confirm neither the "paused" nor the "rate limit" comment is present —
      # those are handled by their own dedicated blocks above/below.
      local silent_no_paused_count
      silent_no_paused_count="$(
        gh api "repos/$repo/issues/$pr_number/comments" --paginate \
          | jq -s --arg bot "$bot_login" --arg since "$since_iso" '
              [.[].[] | select(
                  .user.login == $bot and
                  .created_at > $since and
                  (
                    ((.body // "") | test("Reviews paused|review paused"; "i")) or
                    ((.body // "") | test("rate.?limit"; "i"))
                  )
              )] | length
            '
      )"
      if [ "${silent_no_paused_count:-0}" -eq 0 ]; then
        coderabbit_no_trigger_retriggers=$((coderabbit_no_trigger_retriggers + 1))
        echo "INFO: CodeRabbit has not auto-triggered after ${elapsed}s (silent non-trigger, attempt ${coderabbit_no_trigger_retriggers}/${coderabbit_rate_limit_max_retries}) — posting @coderabbitai review" >&2
        if gh pr comment "$pr_number" --body "@coderabbitai review" >/dev/null 2>&1; then
          echo "INFO: @coderabbitai review trigger posted" >&2
        else
          echo "WARN: failed to post @coderabbitai review trigger for silent non-trigger" >&2
        fi
        # Reset the elapsed timer to give the retrigger a full polling window.
        elapsed=0
        _interruptible_sleep "$poll_interval"
        elapsed=$((elapsed + poll_interval))
        continue
      fi
    fi

    # --- Rate-limit detection: CodeRabbit posts a comment when it cannot review yet ---
    # When CodeRabbit is rate-limited it posts an issue comment containing "rate limit"
    # text. Detect this, wait, then post "@coderabbitai resume" to request CodeRabbit
    # to resume its review. Retried up to coderabbit_rate_limit_max_retries times.
    # When retries are exhausted, the timeout block below escalates instead of returning
    # a false-clean no_review result (see the incomplete-review guard before no_review exit).
    if [ "$coderabbit_any_activity" -eq 0 ] && [ "$coderabbit_rate_limit_retries" -lt "$coderabbit_rate_limit_max_retries" ]; then
      local rate_limit_comment_count
      rate_limit_comment_count="$(
        gh api "repos/$repo/issues/$pr_number/comments" --paginate \
          | jq -s --arg bot "$bot_login" --arg since "$since_iso" '
              [.[].[] | select(
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
          # Wait before the audit: CodeRabbit may set SUCCESS while still posting inline
          # threads asynchronously. FALLBACK_THREAD_SETTLE_WAIT (default 60s) gives those
          # threads time to arrive so the audit does not return a false-clean count.
          local fallback_settle_wait="${FALLBACK_THREAD_SETTLE_WAIT:-60}"
          if [ "$fallback_settle_wait" -gt 0 ]; then
            echo "INFO: coderabbit_status_success_fallback — waiting ${fallback_settle_wait}s for async threads to settle before thread audit" >&2
            _interruptible_sleep "$fallback_settle_wait"
          fi
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
        _interruptible_sleep "$coderabbit_rate_limit_wait"
        # Do NOT reset since_iso — keep the original HEAD-commit timestamp so any review
        # posted by CodeRabbit during or after the wait is still within the detection window.
        elapsed=0
        if gh pr comment "$pr_number" --body "@coderabbitai resume" >/dev/null 2>&1; then
          echo "INFO: posted @coderabbitai resume after rate-limit wait" >&2
        else
          echo "WARN: failed to post @coderabbitai resume after rate-limit wait" >&2
        fi
        _interruptible_sleep "$poll_interval"
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
          # Wait before the audit: CodeRabbit may set SUCCESS while still posting inline
          # threads asynchronously. FALLBACK_THREAD_SETTLE_WAIT (default 60s) gives those
          # threads time to arrive so the audit does not return a false-clean count.
          local fallback_settle_wait_timeout="${FALLBACK_THREAD_SETTLE_WAIT:-60}"
          if [ "$fallback_settle_wait_timeout" -gt 0 ]; then
            echo "INFO: coderabbit_status_success_fallback — waiting ${fallback_settle_wait_timeout}s for async threads to settle before thread audit" >&2
            _interruptible_sleep "$fallback_settle_wait_timeout"
          fi
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

        # --- Incomplete-review guard before no_review clean exit ---
        # If a CodeRabbit rate-limit comment OR a "Reviews paused" banner is still
        # active (posted or edited since since_iso), CodeRabbit has not completed
        # its review. Returning clean here would be a false-clean. Instead, escalate
        # so the caller knows CodeRabbit was still rate-limited or paused when the
        # poll window ended. This covers both the case where retries were exhausted
        # and the case where the poll window ended mid-retry (e.g. elapsed >= max_wait
        # before the retry could fire), and the case where only a pause banner
        # (without a rate-limit comment) caused the no-review outcome. Note: CodeRabbit
        # sometimes signals rate-limits by editing its existing walkthrough comment
        # rather than posting a new one, so we check both created_at and updated_at.
        local timeout_incomplete_count
        timeout_incomplete_count="$(
          gh api "repos/$repo/issues/$pr_number/comments" --paginate \
            | jq -s --arg bot "$bot_login" --arg since "$since_iso" '
                [.[].[] | select(
                    .user.login == $bot and
                    (.created_at > $since or .updated_at > $since) and
                    (
                      ((.body // "") | test("rate.?limit"; "i")) or
                      ((.body // "") | test("Reviews paused|review paused"; "i"))
                    )
                )] | length
              '
        )"
        if [ "${timeout_incomplete_count:-0}" -gt 0 ] || [ "$coderabbit_phase0_retrigger" -eq 1 ]; then
          echo "INFO: CodeRabbit rate-limit or pause still unresolved at timeout (incomplete_count=${timeout_incomplete_count:-0}, phase0_retrigger=$coderabbit_phase0_retrigger) — escalating instead of returning clean" >&2
          print_kv RESULT escalate
          print_kv REASON rate_limit_max_retries
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

    _interruptible_sleep "$poll_interval"
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
    codex-github)        printf '%s\n' "${CODEX_GITHUB_BOT_LOGIN:-chatgpt-codex-connector[bot]}" ;;
    claude-code-action)  printf '%s\n' "${CLAUDE_CODE_ACTION_BOT_LOGIN:-claude[bot]}" ;;
    copilot)             printf '%s\n' "${COPILOT_BOT_LOGIN:-copilot-pull-request-reviewer[bot]}" ;;
    haystack)            printf '\n' ;;
    *)                   printf '\n' ;;
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

    if [ "$has_next_page" = "true" ] && [ -z "$cursor" ]; then
      echo "WARN: check_unresolved_threads: hasNextPage=true but endCursor is empty for PR #$pr_number; cannot confirm all threads checked" >&2
      return 2
    fi
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
    claude-code-action)
      run_claude_code_action_review "$pr_number" "$branch_name" "$poll_interval" "$max_wait"
      ;;
    copilot)
      run_copilot_review "$pr_number" "$branch_name" "$poll_interval" "$max_wait"
      ;;
    haystack)
      run_haystack_review "$pr_number" "$branch_name" "$poll_interval" "$max_wait"
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

# --- Compare-mode helpers ---
# These functions are defined here (before the main execution block) so that
# the test harness can load them via HARNESS_MODE=1 sourcing without executing
# the argument-parsing and main-loop sections below.

# normalize_platform_verdict: map a raw platform result token to one of the five
# canonical compare-mode verdict values: clean, blocking, advisory, timed out, unavailable.
# $1 = platform_result token (e.g. clean, needs_fixes, skipped, escalate, needs_rerun)
# $2 = full platform output (key=value block; used to inspect REASON for timeout detection)
normalize_platform_verdict() {
  local result="$1"
  local output="${2:-}"
  local reason
  reason="$(kv_value_default REASON "$output" "")"
  case "$result" in
    clean)       printf 'clean' ;;
    needs_fixes) printf 'blocking' ;;
    advisory)    printf 'advisory' ;;
    skipped)     printf 'unavailable' ;;
    needs_rerun) printf 'blocking' ;;
    escalate)
      # Distinguish timeout from service-unavailable via REASON.
      case "$reason" in
        timeout|timed_out|max_wait_exceeded|no_response|rate_limit_max_retries)
          printf 'timed out' ;;
        *)
          printf 'unavailable' ;;
      esac
      ;;
    *)           printf 'unavailable' ;;
  esac
}

# append_compare_metrics_row: append one structured row to the platform metrics log.
# Called at the end of the platform loop when compare_mode=1.
# $1 = pr_number
# $2 = branch_name
# $3 = overall_result (the aggregate after all platforms ran)
# Remaining args: pairs of platform_name verdict_token (e.g. coderabbit blocking greptile clean)
append_compare_metrics_row() {
  local pr_number_arg="$1"
  local branch_name_arg="$2"
  local overall_result_arg="$3"
  shift 3

  local metrics_file
  metrics_file="$(workflow_repo_root)/docs/workflow/retro-metrics-platforms.md"

  # Derive branch type from the branch name prefix.
  local branch_type
  case "$branch_name_arg" in
    feature/*)            branch_type="feature" ;;
    fix/*)                branch_type="fix" ;;
    refactor/*)           branch_type="refactor" ;;
    hotfix/*)             branch_type="hotfix" ;;
    spec/*)               branch_type="spec" ;;
    implementation-plan/*) branch_type="plan" ;;
    *)                    branch_type="other" ;;
  esac

  # Collect pairs: platform_names and verdict_tokens in order.
  local -a platform_names=()
  local -a verdict_tokens=()
  while [ "$#" -ge 2 ]; do
    platform_names+=("$1")
    verdict_tokens+=("$2")
    shift 2
  done

  # Build dynamic platform-column headers from the current run's platform list.
  local header_platform_cols=""
  for _pname in "${platform_names[@]}"; do
    header_platform_cols="${header_platform_cols} ${_pname} |"
  done
  local separator_platform_cols=""
  for _pname in "${platform_names[@]}"; do
    separator_platform_cols="${separator_platform_cols}---|"
  done

  # Create the file with the full header when it does not yet exist.
  # If the file exists (e.g. pre-created with prose only) but has no table header
  # row yet (detected by absence of the "|---|" separator line), append the table
  # header rows so the Markdown table is valid before the first data row.
  if [ ! -f "$metrics_file" ]; then
    cat > "$metrics_file" <<METRICS_HEADER
# Platform Comparison Metrics Log

This file is append-only. One row is appended per compare-mode reviewer loop run.
Do not delete or rewrite existing rows. The "Block Was Real Bug?" column may be
filled in manually after a run when post-hoc analysis determines whether a
platform-exclusive blocking finding corresponded to a real code defect.

## Graduation Criteria

A platform may be considered safe for removal when, across 30 or more consecutive
compare-mode runs covering at least one run each of \`fix\`, \`feature\`, and \`refactor\`
branch types, it has zero platform-exclusive blocking findings (runs where that
platform blocked but at least one other configured platform was clean).

Fewer than 30 runs is always insufficient data for a graduation decision.

## Metrics Table

| PR | Branch Type |${header_platform_cols} Overall Result | Block Was Real Bug? |
|---|---|${separator_platform_cols}---|---|
METRICS_HEADER
  elif ! grep -q '^|---|' "$metrics_file" 2>/dev/null; then
    # File exists but has no table separator row — append the table header now.
    # Ensure there is a blank line before the table if the file has content.
    if [ -s "$metrics_file" ]; then
      printf '\n' >> "$metrics_file"
    fi
    printf '| PR | Branch Type |%s Overall Result | Block Was Real Bug? |\n' \
      "$header_platform_cols" >> "$metrics_file"
    printf '|---|---|%s---|---|\n' \
      "$separator_platform_cols" >> "$metrics_file"
  else
    # File exists and already has a table. Check whether the current platform
    # set matches the existing header. If not, insert a separator comment row
    # before appending the data row so human readers can see the config changed.
    # Detection: compare platform names (and order) by parsing the header row
    # above the last separator row. A count-only check misses platform renames
    # or reordering with the same count.
    # Column order: PR, Branch Type, <platforms...>, Overall Result, Block Was Real Bug?
    # Fixed columns = 4 (PR, Branch Type, Overall Result, Block Was Real Bug?)
    existing_sep_row="$(grep '^|---|' "$metrics_file" | tail -1)"
    existing_platform_col_count=$(printf '%s' "$existing_sep_row" | tr -cd '|' | wc -c | tr -d ' ')
    # pipe count = platform_cols + 4 fixed cols + 1 leading pipe → total pipes = platform_cols + 5
    existing_platform_count=$(( existing_platform_col_count - 5 ))
    current_platform_count="${#platform_names[@]}"
    # Parse platform names from the header row above the last separator row.
    existing_sep_line_num="$(grep -n '^|---|' "$metrics_file" | tail -1 | cut -d: -f1)"
    existing_header_row="$(sed -n "$(( existing_sep_line_num - 1 ))p" "$metrics_file")"
    # awk splits by |: field 1=empty, 2=PR, 3=Branch Type, 4..NF-3=platforms, NF-2=Overall Result, NF-1=Block Was Real Bug?, NF=empty
    existing_platform_str="$(printf '%s' "$existing_header_row" | awk -F'|' '{
      sep=""
      for (i = 4; i <= NF - 3; i++) {
        gsub(/^[ \t]+|[ \t]+$/, "", $i)
        printf "%s%s", sep, $i
        sep = ","
      }
    }')"
    current_platform_str="$(IFS=,; printf '%s' "${platform_names[*]}")"
    if [ "$current_platform_count" -ne "$existing_platform_count" ] || [ "$existing_platform_str" != "$current_platform_str" ]; then
      # Platform configuration changed: insert an annotation row (in the OLD layout
      # so it is a valid row for that table) then write a new header block for the
      # new layout so subsequent rows are correctly labeled.
      # Build blank cells matching the EXISTING header's column count.
      _sep_blank_cols=""
      _sep_i=0
      while [ "$_sep_i" -lt $(( existing_platform_count + 3 )) ]; do
        _sep_blank_cols="${_sep_blank_cols} |"
        _sep_i=$(( _sep_i + 1 ))
      done
      printf '| *(platforms changed: %s)* |%s\n' \
        "$(IFS=,; printf '%s' "${platform_names[*]}")" \
        "$_sep_blank_cols" \
        >> "$metrics_file"
      # New header block for the updated platform layout.
      printf '\n| PR | Branch Type |%s Overall Result | Block Was Real Bug? |\n' \
        "$header_platform_cols" >> "$metrics_file"
      printf '|---|---|%s---|---|\n' \
        "$separator_platform_cols" >> "$metrics_file"
    fi
  fi

  # Build the verdict columns for this row.
  local row_verdict_cols=""
  for _vtoken in "${verdict_tokens[@]}"; do
    row_verdict_cols="${row_verdict_cols} ${_vtoken} |"
  done

  # Append one row.
  printf '| #%s | %s |%s %s | |\n' \
    "$pr_number_arg" \
    "$branch_type" \
    "$row_verdict_cols" \
    "$overall_result_arg" \
    >> "$metrics_file"
}

# Skip the main execution block when sourced in test-harness mode.
# All function definitions above (including normalize_platform_verdict and
# append_compare_metrics_row) are loaded; only the argument-parsing and
# execution sections below are skipped.
[ "$_HARNESS_MODE_EFFECTIVE" -eq 1 ] && return 0 2>/dev/null || true

if [ "$#" -lt 1 ]; then
  usage >&2
  exit 64
fi

# --- unlock subcommand ---
# Handle before the lock guard so a crashed-process recovery can always proceed.
if [ "$1" = "unlock" ]; then
  if [ "$#" -lt 2 ] || [ -z "$2" ]; then
    echo "Usage: $0 unlock <pr-number>" >&2
    exit 64
  fi
  _UNLOCK_PR="$2"
  _UNLOCK_LOCK_DIR="/tmp/pr-review-loop-${_UNLOCK_PR}.lockdir"
  # Verify no live owner holds the lock before removing it.
  _UNLOCK_PID="$(cat "$_UNLOCK_LOCK_DIR/pid" 2>/dev/null || true)"
  _UNLOCK_CMD="$(cat "$_UNLOCK_LOCK_DIR/cmd" 2>/dev/null || true)"
  if [ -n "$_UNLOCK_PID" ] && kill -0 "$_UNLOCK_PID" 2>/dev/null && [ "$_UNLOCK_CMD" = "$(basename "$0")" ]; then
    echo "ERROR: A live pr-review-loop.sh process (PID $_UNLOCK_PID) currently holds the lock for PR #${_UNLOCK_PR}. Not removing a live lock." >&2
    echo "  Wait for the process to finish, or send it SIGTERM to stop it gracefully." >&2
    exit 1
  fi
  if [ -d "$_UNLOCK_LOCK_DIR" ]; then
    rm -rf "$_UNLOCK_LOCK_DIR"
    echo "OK: stale lock removed for PR #${_UNLOCK_PR} ($_UNLOCK_LOCK_DIR)."
    exit 0
  else
    echo "OK: no lock found for PR #${_UNLOCK_PR} ($_UNLOCK_LOCK_DIR). Nothing to remove."
    exit 0
  fi
fi

pr_number=""
branch_name=""
poll_interval=120
poll_interval_explicit=0
max_wait=1200
max_wait_explicit=0
post_final_summary=0
compare_mode=0
pre_after_clean_only=0
declare -a platforms=()
declare -a phase_after_clean_platforms=()
phase_after_clean_filtered_out=""

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
    --phase-after-clean)
      append_phase_after_clean_platforms "$2"
      shift 2
      ;;
    --pre-after-clean-only)
      pre_after_clean_only=1
      shift
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
    --post-final-summary)
      post_final_summary=1
      shift
      ;;
    --compare)
      compare_mode=1
      shift
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
  # Resolve config from the PR's target branch so platform coverage is
  # consistent regardless of the operator's local checkout state (#756).
  _pr_base="$(gh pr view "$pr_number" --json baseRefName --jq '.baseRefName' 2>/dev/null || true)"
  if [ -n "$_pr_base" ]; then
    _PR_CONFIG_TMPFILE="$(mktemp)"
    if ! git show "origin/${_pr_base}:.ai-dev-workflow.yaml" > "$_PR_CONFIG_TMPFILE" 2>/dev/null; then
      rm -f "$_PR_CONFIG_TMPFILE"
      _PR_CONFIG_TMPFILE=""
    fi
  fi
  config_file="${_PR_CONFIG_TMPFILE:-$(workflow_config_file)}"
  if [ -f "$config_file" ]; then
    while IFS= read -r line; do
      line="$(trim "$line")"
      [ -n "$line" ] && platforms+=("$line")
    done < <(workflow_config_review_platforms "$config_file")
  fi
fi

if [ "${#phase_after_clean_platforms[@]}" -eq 0 ]; then
  config_file="${config_file:-$(workflow_config_file)}"
  if [ -f "$config_file" ]; then
    while IFS= read -r line; do
      line="$(trim "$line")"
      [ -n "$line" ] && phase_after_clean_platforms+=("$line")
    done < <(workflow_config_review_phase_after_clean_platforms "$config_file")
  fi
fi

if [ "$pre_after_clean_only" -eq 1 ]; then
  filter_pre_after_clean_platforms
  # Do NOT call filter_phase_after_clean_platforms here: filter_pre_after_clean_platforms
  # already removed phase platforms from `platforms`, so a subsequent
  # filter_phase_after_clean_platforms call would find no matching entries and empty
  # phase_after_clean_platforms — losing the configured phase list and causing
  # PHASE_AFTER_CLEAN_PLATFORM_LIST telemetry to be blank (issue #693).
else
  filter_phase_after_clean_platforms
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

# Large-diff poll-window extension.
# CodeRabbit takes significantly longer to post its review on large-diff PRs
# (e.g. release PRs with hundreds of changed files). The default max_wait=1200 s
# was calibrated for typical feature PRs and is too short for large release diffs:
# during release v0.27.0 (PR #665, 185-file diff), the loop returned RESULT=clean
# before CodeRabbit finished posting 16 findings.
#
# When the caller did not pass --max-wait explicitly, fetch the PR's changed-files
# count and extend max_wait to LARGE_DIFF_MAX_WAIT (default 2400 s) when the count
# exceeds LARGE_DIFF_THRESHOLD (default 50 files). A case guard excludes spec/* and
# implementation-plan/* branches — those are already handled by the branch-type-aware
# timeout block above and must not have their 60-second budget overridden.
large_diff_threshold="${LARGE_DIFF_THRESHOLD:-50}"
large_diff_max_wait="${LARGE_DIFF_MAX_WAIT:-2400}"
if ! [[ "$large_diff_threshold" =~ ^[1-9][0-9]*$ ]]; then
  echo "WARN: LARGE_DIFF_THRESHOLD must be a positive integer; defaulting to 50" >&2
  large_diff_threshold=50
fi
if ! [[ "$large_diff_max_wait" =~ ^[1-9][0-9]*$ ]]; then
  echo "WARN: LARGE_DIFF_MAX_WAIT must be a positive integer; defaulting to 2400" >&2
  large_diff_max_wait=2400
fi
changed_files_count=-1
large_diff_extended=0
if [ "$max_wait_explicit" -eq 0 ]; then
  case "$branch_name" in
    spec/*|implementation-plan/*)
      # Already handled by the branch-type rule above — do not extend.
      ;;
    *)
      if [ -n "$pr_number" ] && [ "${#platforms[@]}" -gt 0 ]; then
        set +e
        changed_files_count="$(gh api "repos/$(repo_slug)/pulls/$pr_number" \
          --jq '.changed_files // -1' 2>/dev/null)"
        set -e
        if ! [[ "${changed_files_count:-}" =~ ^-?[0-9]+$ ]]; then
          echo "WARN: failed to fetch changed_files count for PR #$pr_number — skipping large-diff extension" >&2
          changed_files_count=-1
        fi
        if [ "$changed_files_count" -ge 0 ] && [ "$changed_files_count" -gt "$large_diff_threshold" ]; then
          if [ "$large_diff_max_wait" -gt "$max_wait" ]; then
            echo "INFO: PR #$pr_number has ${changed_files_count} changed files (threshold: ${large_diff_threshold}) — extending max_wait from ${max_wait}s to ${large_diff_max_wait}s for large-diff poll window" >&2
            max_wait="$large_diff_max_wait"
            large_diff_extended=1
          fi
        fi
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
aggregate_advisory_labels=""
declare -a compare_verdicts=()
# Per-platform result tokens for the PR summary comment.
# Each entry is "platform_name=display_token" (e.g. "haystack=unavailable").
declare -a platform_result_tokens=()
# Compare-mode: track the first blocking platform seen so later clean platforms
# do not overwrite the aggregate. These variables are set once and never reset.
compare_first_blocking_result=""
compare_first_blocking_reason=""
compare_first_blocking_output=""
compare_first_blocking_status=0
phase_after_clean_enabled=0
phase_after_clean_started=0
phase_after_clean_net_new_blocker=0
phase_after_clean_blocking_platform=""
phase_after_clean_gate_result="not_started"
phase_after_clean_skip_reason=""
if [ "${#phase_after_clean_platforms[@]}" -gt 0 ]; then
  phase_after_clean_enabled=1
fi

print_kv PR_NUMBER "$pr_number"
print_kv BRANCH "$branch_name"
print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
print_kv PLATFORM_COUNT "${#platforms[@]}"
# So callers can verify config was respected (e.g. no greptile when only devin is in .ai-dev-workflow.yaml)
print_kv PLATFORM_LIST "$(IFS=,; printf '%s' "${platforms[*]}")"
print_kv PRE_AFTER_CLEAN_ONLY "$pre_after_clean_only"
print_kv PHASE_AFTER_CLEAN_ENABLED "$phase_after_clean_enabled"
[ -n "$phase_after_clean_filtered_out" ] && \
  print_kv PHASE_AFTER_CLEAN_FILTERED_OUT "$phase_after_clean_filtered_out"
[ "$phase_after_clean_enabled" -eq 1 ] && \
  print_kv PHASE_AFTER_CLEAN_PLATFORM_LIST "$(IFS=,; printf '%s' "${phase_after_clean_platforms[*]}")"
print_kv CHANGED_FILES_COUNT "${changed_files_count:--1}"
[ "$large_diff_extended" -eq 1 ] && print_kv LARGE_DIFF_EXTENDED 1

for index in "${!platforms[@]}"; do
  platform_index=$((index + 1))
  platform_name="${platforms[$index]}"

  if [ "$phase_after_clean_enabled" -eq 1 ] \
      && [ "$phase_after_clean_started" -eq 0 ] \
      && is_phase_after_clean_platform "$platform_name"; then
    if [ "$compare_mode" -eq 0 ] || [ -z "$compare_first_blocking_result" ]; then
      phase_after_clean_started=1
      phase_after_clean_gate_result="clean"
    fi
  fi

  set +e
  platform_output="$(run_platform_review "$platform_name" "$pr_number" "$branch_name" "$poll_interval" "$max_wait")"
  platform_status=$?
  set -e

  platform_result="$(kv_value_default RESULT "$platform_output" skipped)"
  platform_comment_count="$(kv_value_default COMMENT_COUNT "$platform_output" 0)"
  platform_blocking_count="$(kv_value_default BLOCKING_COUNT "$platform_output" 0)"
  platform_suggestion_count="$(kv_value_default SUGGESTION_COUNT "$platform_output" 0)"
  platform_advisory_labels="$(kv_value_default ADVISORY_LABELS "$platform_output" "")"

  total_comment_count=$((total_comment_count + platform_comment_count))
  total_blocking_count=$((total_blocking_count + platform_blocking_count))
  total_suggestion_count=$((total_suggestion_count + platform_suggestion_count))
  if [ -n "$platform_advisory_labels" ]; then
    if [ -n "$aggregate_advisory_labels" ]; then
      aggregate_advisory_labels="${aggregate_advisory_labels}|||${platform_advisory_labels}"
    else
      aggregate_advisory_labels="$platform_advisory_labels"
    fi
  fi
  last_platform="$platform_name"

  print_kv "PLATFORM_${platform_index}_NAME" "$platform_name"
  print_kv "PLATFORM_${platform_index}_RESULT" "$platform_result"
  emit_prefixed_platform_output "$platform_index" "$platform_output"
  # Record a human-readable display token for the PR summary comment.
  _prt_reason="$(kv_value_default REASON "$platform_output" "")"
  case "$platform_result" in
    clean)      _prt_disp="clean" ;;
    skipped)
      if [ "$_prt_reason" = "unavailable" ] || [ "$_prt_reason" = "not_configured" ]; then
        _prt_disp="unavailable"
      else
        _prt_disp="skipped"
      fi
      ;;
    escalate)   _prt_disp="escalated (${_prt_reason:-unknown})" ;;
    needs_fixes) _prt_disp="needs_fixes" ;;
    *)           _prt_disp="$platform_result" ;;
  esac
  platform_result_tokens+=("${platform_name}:${_prt_disp}")
  unset _prt_reason _prt_disp

  # In compare mode, record a normalized verdict for each platform before
  # deciding whether to break. The normalized verdict captures clean / blocking /
  # advisory / timed out / unavailable regardless of the raw result token.
  if [ "$compare_mode" -eq 1 ]; then
    compare_verdicts+=("$platform_name" "$(normalize_platform_verdict "$platform_result" "$platform_output")")
  fi

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
      if [ "$phase_after_clean_enabled" -eq 1 ] \
          && [ "$phase_after_clean_started" -eq 1 ] \
          && is_phase_after_clean_platform "$platform_name"; then
        phase_after_clean_net_new_blocker=1
        phase_after_clean_blocking_platform="$platform_name"
      fi
      aggregate_result="$platform_result"
      aggregate_reason="$(kv_value_default REASON "$platform_output" "")"
      aggregate_output="$platform_output"
      aggregate_status=$platform_status
      if [ "$compare_mode" -eq 0 ]; then
        # Normal mode: short-circuit on first blocking platform.
        break
      fi
      # Compare mode: capture the first blocking state so later clean platforms
      # cannot overwrite the aggregate. Only the first blocking platform governs.
      if [ -z "$compare_first_blocking_result" ]; then
        compare_first_blocking_result="$platform_result"
        compare_first_blocking_reason="$aggregate_reason"
        compare_first_blocking_output="$platform_output"
        compare_first_blocking_status=$platform_status
      fi
      ;;
    needs_rerun)
      # PR-Agent "Possible Issue" evaluation: a fix was pushed; re-run the loop.
      # Propagate as needs_rerun (exit 3) so orchestrator callers distinguish
      # this from needs_fixes (fixer dispatch) and re-invoke on the new HEAD.
      aggregate_result="needs_rerun"
      aggregate_output="$platform_output"
      aggregate_status=$platform_status
      if [ "$compare_mode" -eq 0 ]; then
        break
      fi
      # Compare mode: record verdict and continue to remaining platforms.
      if [ -z "$compare_first_blocking_result" ]; then
        compare_first_blocking_result="needs_rerun"
        compare_first_blocking_reason=""
        compare_first_blocking_output="$platform_output"
        compare_first_blocking_status=$platform_status
      fi
      ;;
    *)
      aggregate_result="escalate"
      aggregate_reason="unknown-platform-result"
      aggregate_output="$platform_output"
      aggregate_status=2
      if [ "$compare_mode" -eq 0 ]; then
        break
      fi
      # Compare mode: capture first blocking state (unknown result treated as blocking).
      if [ -z "$compare_first_blocking_result" ]; then
        compare_first_blocking_result="escalate"
        compare_first_blocking_reason="unknown-platform-result"
        compare_first_blocking_output="$platform_output"
        compare_first_blocking_status=2
      fi
      ;;
  esac
done

# --- Automated Reviewer Loop Summary comment ---
# Post a summary comment to the PR on terminal exit paths so the Step 8c
# hasReviewSummary check is satisfied automatically. The comment body matches
# the regex used by workflow-next-action.sh and Protocol 90 Step 5.1:
#   "Automated Reviewer Loop Summary|Reviewer Loop Summary|No blocking PR feedback"
# Post on `clean` and `escalate` exits unconditionally. For `needs_fixes` exits,
# post only when --post-final-summary is set — i.e. when the orchestrator has
# determined this is the terminal run (cycle >= max_cycles) and will not dispatch
# another fixer regardless of the exit code. Posting on every `needs_fixes` exit
# would create duplicate comments per fix cycle.
# `skipped` exits (no platforms configured) also do not post per protocol spec.
_post_review_summary() {
  local result="$1"
  local reason="$2"
  local platform_list="$3"
  local blocking="$4"
  local suggestions="$5"
  local advisory_labels="${6:-}"
  local possible_issue_eval_outcome="${7:-}"
  local phase_enabled="${8:-0}"
  local phase_platform_list="${9:-}"
  local phase_started="${10:-0}"
  local phase_net_new_blocker="${11:-0}"
  local phase_blocking_platform="${12:-}"
  local pre_after_clean_only_mode="${13:-0}"

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
    needs_fixes)
      result_line="max cycles reached — ${blocking} blocking finding(s) unresolved"
      ;;
    escalate)
      result_line="escalated (${reason:-unknown})"
      ;;
    skipped)
      result_line="skipped — no platforms configured in review.platforms"
      ;;
    *)
      result_line="$result"
      ;;
  esac

  # Build the optional advisory findings section.
  # advisory_labels format: "<labels>@@@<url>" entries separated by "|||"
  # Each entry's labels are pipe-separated. Render each label as a list item,
  # linking to the PR-Agent comment URL when available.
  local advisory_section=""
  if [ -n "$advisory_labels" ]; then
    local _entry _labels _url _label
    advisory_section="

**Advisory findings (non-blocking):**"
    # Split entries by ||| separator using sed (IFS does not support multi-char
    # separators). Each entry has the form "<pipe-delimited labels>@@@<url>".
    local _entries_normalized
    _entries_normalized="$(printf '%s' "$advisory_labels" | sed 's/|||/\n/g')"
    while IFS= read -r _entry; do
      [ -z "$_entry" ] && continue
      _labels="${_entry%@@@*}"
      _url="${_entry##*@@@}"
      # Split pipe-delimited labels within this entry
      local _labels_normalized
      _labels_normalized="$(printf '%s' "$_labels" | tr '|' '\n')"
      while IFS= read -r _label; do
        [ -z "$_label" ] && continue
        if [ -n "$_url" ] && [ "$_url" != "$_labels" ]; then
          advisory_section="${advisory_section}
- ${_label} ([view comment](${_url}))"
        else
          advisory_section="${advisory_section}
- ${_label}"
        fi
      done <<_ADVISORY_LABEL_LINES_
$_labels_normalized
_ADVISORY_LABEL_LINES_
    done <<_ADVISORY_ENTRY_LINES_
$_entries_normalized
_ADVISORY_ENTRY_LINES_
    # Append "Possible Issue" evaluation outcome when available.
    if [ -n "$possible_issue_eval_outcome" ]; then
      local _eval_note
      case "$possible_issue_eval_outcome" in
        acknowledged)
          _eval_note="Auto-acknowledged: Possible Issue is advisory-only — loop proceeded clean"
          ;;
        fix_pushed)
          _eval_note="Evaluated by code-reviewer: fix pushed — loop re-ran on new HEAD"
          ;;
        unavailable)
          _eval_note="Evaluated by code-reviewer: unavailable — fell back to advisory-only (clean)"
          ;;
        *)
          _eval_note="Evaluated by code-reviewer: outcome=${possible_issue_eval_outcome}"
          ;;
      esac
      advisory_section="${advisory_section}
  _Possible Issue evaluation_: ${_eval_note}"
    fi
  fi

  # Step 7b regression-label assertion (clean path, implementation PRs only).
  # When the reviewer loop exits clean for a feature/fix/refactor/hotfix branch,
  # the next required step is Step 7b (apply ready-for-regression before Step 8).
  # Check whether the label is already present and append a warning to the summary
  # comment if it is missing. This makes the missing label visible to agents and
  # orchestrators that read the summary comment, without blocking the script's exit.
  # The check is best-effort: suppress all errors so a gh failure does not change
  # the script's exit code or prevent the summary comment from being posted.
  local regression_label_section=""
  if [ "$result" = "clean" ]; then
    case "${branch_name:-}" in
      feature/*|fix/*|refactor/*|hotfix/*)
        local _has_regression_label
        _has_regression_label="$(gh pr view "$pr_number" --json labels \
          --jq '[.labels[].name] | any(. == "ready-for-regression")' 2>/dev/null)" \
          || { echo "WARN: gh pr view failed for ready-for-regression check (PR ${pr_number}); label check skipped" >&2; _has_regression_label=""; }
        if [ "${_has_regression_label:-}" = "false" ]; then
          regression_label_section="

**Step 7b WARNING: \`ready-for-regression\` label is missing.** Apply it now before entering Step 8 (CI loop):
\`\`\`
gh pr edit ${pr_number} --add-label \"ready-for-regression\"
\`\`\`
Protocol 91 Step 7b requires this label on all \`${branch_name%%/*}/*\` PRs after Step 7 completes clean."
        fi
        ;;
    esac
  fi

  # Build optional compare-mode per-platform section.
  local compare_section=""
  if [ "$compare_mode" -eq 1 ] && [ "${#compare_verdicts[@]}" -gt 0 ]; then
    compare_section="

**Compare mode — per-platform verdicts:**"
    _idx=0
    while [ "$_idx" -lt "${#compare_verdicts[@]}" ]; do
      _cvname="${compare_verdicts[$_idx]}"
      _cvtoken="${compare_verdicts[$((_idx + 1))]}"
      compare_section="${compare_section}
- ${_cvname}: ${_cvtoken}"
      _idx=$((_idx + 2))
    done
    if [ "${_compare_metrics_appended:-0}" -eq 1 ]; then
      compare_section="${compare_section}

*Metrics row appended to \`docs/workflow/retro-metrics-platforms.md\`.*"
    fi
  fi

  local phase_section=""
  if [ "$phase_enabled" -eq 1 ]; then
    local _phase_value_line
    local _phase_subject="${phase_platform_list:-after-clean reviewer}"
    if [ "$phase_started" -eq 1 ]; then
      if [ "$phase_net_new_blocker" -eq 1 ]; then
        _phase_value_line="${_phase_subject} found a net-new blocker after the clean gate (${phase_blocking_platform:-unknown})."
      else
        _phase_value_line="No net-new blocker was found after the PR-Agent-clean gate."
      fi
    elif [ "$pre_after_clean_only_mode" -eq 1 ]; then
      _phase_value_line="After-clean phase was not run — invoked in pre-after-clean-only mode."
    else
      _phase_value_line="After-clean phase was not reached because an earlier platform did not exit clean."
    fi
    phase_section="

**After-clean reviewer phase:** ${_phase_value_line}
**After-clean platforms:** ${phase_platform_list:-none}"
  fi

  local comment_body
  comment_body="$(cat <<EOF
### Automated Reviewer Loop Summary

**Result:** ${result_line}
**Platforms:** ${platform_list:-none}
**Findings:** ${blocking} blocking, ${suggestions} suggestions${phase_section}${compare_section}${advisory_section}${regression_label_section}

*Posted automatically by \`pr-review-loop.sh\`.*
EOF
)"

  # Errors in the comment-posting block must not change the script's exit code or
  # prevent key=value output from reaching the caller. Log warnings to stderr so
  # failures are visible in CI logs without being fatal.
  set +e

  # Update-in-place: find an existing script-posted summary comment and edit it
  # rather than creating a new one. This prevents redundant intermediate summary
  # comments when the orchestrator invokes the script multiple times (e.g. once
  # per fix cycle). Only one "Automated Reviewer Loop Summary" comment should
  # ever exist on the PR timeline at a time.
  # The marker string "*Posted automatically by `pr-review-loop.sh`.*" is unique
  # to this script and is present in every comment it posts.
  local _existing_comment_id=""
  local _repo
  _repo="$(repo_slug 2>/dev/null)" \
    || { echo "WARN: repo_slug failed in _post_review_summary; will post new comment without update-in-place check" >&2; _repo=""; }
  if [ -n "$_repo" ]; then
    _existing_comment_id="$(
      gh api "repos/$_repo/issues/$pr_number/comments" --paginate 2>/dev/null \
        | jq -rs '
            add // []
            | [.[]
               | select(
                   (.body // "" | contains("### Automated Reviewer Loop Summary")) and
                   (.body // "" | contains("*Posted automatically by `pr-review-loop.sh`.*"))
                 )
              ]
            | sort_by(.created_at)
            | last
            | .id // empty
          '
    )" \
      || { echo "WARN: failed to fetch existing summary comments for PR ${pr_number}; will create a new comment" >&2; _existing_comment_id=""; }
  fi

  local _patch_payload
  _patch_payload="$(jq -n --arg body "$comment_body" '{body: $body}')"
  local _comment_posted=0
  if [ -n "$_existing_comment_id" ]; then
    # Edit the existing comment in place; fall back to creating a new comment
    # if the PATCH fails (e.g. comment was deleted or a transient API error).
    if gh api "repos/$_repo/issues/comments/$_existing_comment_id" \
        --method PATCH \
        --input - <<< "$_patch_payload" >/dev/null 2>&1; then
      _comment_posted=1
    else
      echo "WARN: failed to update existing summary comment ${_existing_comment_id} for PR ${pr_number}; falling back to create" >&2
    fi
  fi
  if [ "$_comment_posted" -eq 0 ]; then
    if ! gh pr comment "$pr_number" --body "$comment_body" >/dev/null 2>&1; then
      echo "WARN: failed to post reviewer loop summary comment for PR ${pr_number}" >&2
    fi
  fi

  set -e
}

if [ -z "$last_platform" ]; then
  print_kv RESULT skipped
  print_kv REASON not_configured
  print_kv PLATFORM ""
  print_kv COMMENT_COUNT 0
  print_kv BLOCKING_COUNT 0
  print_kv SUGGESTION_COUNT 0
  print_kv UNRESOLVED_THREAD_COUNT 0
  _post_review_summary "skipped" "not_configured" "none" "0" "0" "" "" "0" "" "0" "0" "" "0"
  exit 0
fi

# --- Compare mode: restore first-blocking aggregate, emit output, write metrics ---
# When compare mode is active, all platforms ran to completion. Later clean platforms
# may have overwritten aggregate_result after the first blocking platform set it.
# Restore the first-blocking state now to ensure the overall result is identical to
# what normal mode would have produced (BR-1: first blocking platform in config order
# governs).
if [ "$compare_mode" -eq 1 ] && [ "${#compare_verdicts[@]}" -gt 0 ]; then
  # Restore aggregate from the first blocking platform, if any.
  if [ -n "$compare_first_blocking_result" ]; then
    aggregate_result="$compare_first_blocking_result"
    aggregate_reason="$compare_first_blocking_reason"
    aggregate_output="$compare_first_blocking_output"
    aggregate_status=$compare_first_blocking_status
  fi
  # aggregate_result is now clean/skipped (if no platform blocked) or the result
  # of the first blocking platform in config order.

  # Emit compare-mode key=value output lines.
  print_kv COMPARE_MODE 1
  local_compare_index=0
  _idx=0
  while [ "$_idx" -lt "${#compare_verdicts[@]}" ]; do
    _cvname="${compare_verdicts[$_idx]}"
    _cvtoken="${compare_verdicts[$((_idx + 1))]}"
    local_compare_index=$((local_compare_index + 1))
    print_kv "COMPARE_VERDICT_${local_compare_index}_PLATFORM" "$_cvname"
    print_kv "COMPARE_VERDICT_${local_compare_index}_RESULT" "$_cvtoken"
    _idx=$((_idx + 2))
  done

fi

# --- Unresolved review thread gate ---
# When all platforms returned clean or skipped, check whether any bot-authored
# review threads remain unresolved before declaring the aggregate result clean.
# This catches Nitpick/Trivial/Minor severity threads that individual platform
# handlers do not classify as blocking but that still need explicit resolution.
# unresolved_bot_logins is declared here (outside the if-block) so the
# post-clean recheck below can safely reference it regardless of code path.
declare -a unresolved_bot_logins=()
if [ "$aggregate_result" = "clean" ] || [ "$aggregate_result" = "skipped" ]; then
  # Build the array of bot logins from the configured platforms.
  # Using an array (not a space-separated string) prevents Bash glob expansion of
  # bracket characters in "[bot]" strings during iteration.
  for _platform in "${platforms[@]}"; do
    _login="$(bot_login_for_platform "$_platform")"
    # REST API returns bot logins WITH the "[bot]" suffix; GraphQL API returns
    # them WITHOUT it. Strip it here so check_unresolved_threads, which queries
    # GraphQL, compares against the correct login form.
    # (e.g. "chatgpt-codex-connector[bot]" → "chatgpt-codex-connector")
    _login="${_login%\[bot\]}"
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
    if [ "$phase_after_clean_enabled" -eq 1 ] && [ "$phase_after_clean_started" -eq 1 ]; then
      phase_after_clean_net_new_blocker=1
      phase_after_clean_blocking_platform="${phase_after_clean_blocking_platform:-review_threads}"
    fi
    # Increment total_blocking_count so BLOCKING_COUNT reflects the unresolved threads.
    # No BLOCKING_N_* entries are emitted for thread findings — callers must use
    # REASON=unresolved_review_threads and UNRESOLVED_THREAD_COUNT to handle this case.
    total_blocking_count=$((total_blocking_count + unresolved_thread_count))
  fi
else
  print_kv UNRESOLVED_THREAD_COUNT 0
fi

# --- Post-clean recheck ---
# After the reviewer loop exits clean and the immediate thread gate passes,
# wait a short interval and re-query reviewThreads. This catches bot review
# threads (e.g. CodeRabbit) that are posted asynchronously and arrive after
# the platform handlers and thread gate have already completed. Without this
# recheck, Step 5.1 must catch these late threads — at the cost of a full
# reviewer-loop redispatch cycle. The recheck adds a single ~30-second wait
# in exchange for avoiding that more expensive recovery path.
#
# The recheck only runs when:
#   - aggregate_result is "clean" after the immediate thread gate
#   - compare_mode is not active (recheck is not meaningful in evaluation mode)
#   - SKIP_POST_CLEAN_RECHECK is not set to "1" (allows callers to suppress
#     on re-dispatch after a prior late-thread fix cycle, so the recheck does
#     not run again on the corrective invocation)
#
# Configurable via POST_CLEAN_WAIT env var (default: 30 seconds).
# Emits POST_CLEAN_RECHECK=1 when the wait-and-recheck runs, and
# LATE_THREADS_FOUND=<N> with the count of newly-discovered unresolved threads.
post_clean_wait="${POST_CLEAN_WAIT:-30}"
if [ "$aggregate_result" = "clean" ] \
    && [ "$compare_mode" -eq 0 ] \
    && [ "${SKIP_POST_CLEAN_RECHECK:-0}" != "1" ] \
    && [ "${#unresolved_bot_logins[@]}" -gt 0 ] \
    && [ -n "$pr_number" ]; then
  print_kv POST_CLEAN_RECHECK 1
  echo "INFO: post-clean recheck — waiting ${post_clean_wait}s for any late-arriving review threads" >&2
  _interruptible_sleep "$post_clean_wait"

  late_thread_count=0
  late_thread_check_output=""
  late_thread_check_status=0
  set +e
  late_thread_check_output="$(check_unresolved_threads "$pr_number" "$(repo_slug)" "${unresolved_bot_logins[@]}")"
  late_thread_check_status=$?
  set -e

  if [ "$late_thread_check_status" -eq 2 ]; then
    # Page-cap exceeded — cannot confirm all threads are resolved. Escalate.
    echo "WARN: post-clean recheck: check_unresolved_threads exceeded page cap — escalating" >&2
    aggregate_result="escalate"
    aggregate_reason="post_clean_recheck_thread_check_incomplete"
    late_thread_count=-1
  elif [ "$late_thread_check_status" -ne 0 ]; then
    # GraphQL failure — escalate rather than silently treating the recheck as clean.
    echo "WARN: post-clean recheck: check_unresolved_threads failed (exit $late_thread_check_status) — escalating" >&2
    aggregate_result="escalate"
    aggregate_reason="post_clean_recheck_thread_audit_failed"
    late_thread_count=-1
  else
    late_thread_count="$late_thread_check_output"
    if [ "$late_thread_count" -gt 0 ]; then
      echo "INFO: post-clean recheck — found $late_thread_count late unresolved thread(s); switching to needs_fixes" >&2
      aggregate_result="needs_fixes"
      aggregate_reason="late_review_threads"
      if [ "$phase_after_clean_enabled" -eq 1 ] && [ "$phase_after_clean_started" -eq 1 ]; then
        phase_after_clean_net_new_blocker=1
        phase_after_clean_blocking_platform="${phase_after_clean_blocking_platform:-late_review_threads}"
      fi
      total_blocking_count=$((total_blocking_count + late_thread_count))
    else
      echo "INFO: post-clean recheck — no late threads found; result remains clean" >&2
    fi
  fi
  print_kv LATE_THREADS_FOUND "$late_thread_count"
else
  print_kv POST_CLEAN_RECHECK 0
  # Emit LATE_THREADS_FOUND=0 on skipped paths so consumers can always rely on
  # the field being present, regardless of whether the recheck ran.
  print_kv LATE_THREADS_FOUND 0
fi

if [ "$phase_after_clean_enabled" -eq 1 ] && [ "$phase_after_clean_started" -eq 0 ]; then
  phase_after_clean_skip_reason="$aggregate_result"
fi
print_kv PHASE_AFTER_CLEAN_STARTED "$phase_after_clean_started"
if [ "$phase_after_clean_enabled" -eq 1 ]; then
  if [ "$phase_after_clean_started" -eq 1 ]; then
    print_kv PHASE_AFTER_CLEAN_GATE_RESULT "$phase_after_clean_gate_result"
  else
    print_kv PHASE_AFTER_CLEAN_SKIP_REASON "$phase_after_clean_skip_reason"
  fi
  print_kv PHASE_AFTER_CLEAN_NET_NEW_BLOCKER "$phase_after_clean_net_new_blocker"
  [ -n "$phase_after_clean_blocking_platform" ] && \
    print_kv PHASE_AFTER_CLEAN_BLOCKING_PLATFORM "$phase_after_clean_blocking_platform"
fi

# Append compare-mode metrics row after the thread gate so the recorded
# aggregate_result reflects the final settled value (thread audit may flip
# a platform-clean run to needs_fixes or escalate).
_compare_metrics_appended=0
if [ "$compare_mode" -eq 1 ] && [ "${#compare_verdicts[@]}" -gt 0 ]; then
  set +e
  _metrics_args=("$pr_number" "$branch_name" "$aggregate_result")
  _idx=0
  while [ "$_idx" -lt "${#compare_verdicts[@]}" ]; do
    _metrics_args+=("${compare_verdicts[$_idx]}" "${compare_verdicts[$((_idx + 1))]}")
    _idx=$((_idx + 2))
  done
  append_compare_metrics_row "${_metrics_args[@]}" 2>/dev/null && \
    _compare_metrics_appended=1 || \
    echo "WARN: append_compare_metrics_row failed — metrics row not written" >&2
  set -e
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


aggregate_possible_issue_eval_outcome="$(kv_value_default POSSIBLE_ISSUE_EVAL_OUTCOME "$aggregate_output" "")"
if [ "${#phase_after_clean_platforms[@]}" -gt 0 ]; then
  phase_after_clean_platform_list="$(IFS=,; printf '%s' "${phase_after_clean_platforms[*]}")"
else
  phase_after_clean_platform_list=""
fi

# Build per-platform result list for the PR summary comment.
# Format: "pr-agent (clean), haystack (unavailable), claude-code-action (escalated (timeout))"
_summary_platform_list=""
if [ "${#platform_result_tokens[@]}" -gt 0 ]; then
  for _sprt in "${platform_result_tokens[@]}"; do
    _spname="${_sprt%%:*}"
    _spdisp="${_sprt#*:}"
    [ -n "$_summary_platform_list" ] && _summary_platform_list="${_summary_platform_list}, "
    _summary_platform_list="${_summary_platform_list}${_spname} (${_spdisp})"
  done
fi
[ -z "$_summary_platform_list" ] && _summary_platform_list="none"

case "$aggregate_result" in
  clean)
    _post_review_summary "$aggregate_result" "$aggregate_reason" \
      "$_summary_platform_list" \
      "$total_blocking_count" "$total_suggestion_count" \
      "$aggregate_advisory_labels" \
      "$aggregate_possible_issue_eval_outcome" \
      "$phase_after_clean_enabled" "$phase_after_clean_platform_list" \
      "$phase_after_clean_started" "$phase_after_clean_net_new_blocker" \
      "$phase_after_clean_blocking_platform" "$pre_after_clean_only"
    exit 0
    ;;
  skipped)
    exit 0
    ;;
  needs_fixes)
    if [ "$post_final_summary" -eq 1 ]; then
      _post_review_summary "$aggregate_result" "$aggregate_reason" \
        "$_summary_platform_list" \
        "$total_blocking_count" "$total_suggestion_count" \
        "$aggregate_advisory_labels" \
        "$aggregate_possible_issue_eval_outcome" \
        "$phase_after_clean_enabled" "$phase_after_clean_platform_list" \
        "$phase_after_clean_started" "$phase_after_clean_net_new_blocker" \
        "$phase_after_clean_blocking_platform" "$pre_after_clean_only"
    fi
    exit 1
    ;;
  needs_rerun)
    # PR-Agent "Possible Issue" evaluation pushed a fix; orchestrator must
    # re-invoke the loop on the new HEAD. No summary comment is posted here —
    # the loop re-runs from the top and posts the summary on its terminal exit.
    # RESULT=needs_rerun is already emitted by the general print_kv block above.
    exit 3
    ;;
  escalate)
    _post_review_summary "$aggregate_result" "$aggregate_reason" \
      "$_summary_platform_list" \
      "$total_blocking_count" "$total_suggestion_count" \
      "$aggregate_advisory_labels" \
      "$aggregate_possible_issue_eval_outcome" \
      "$phase_after_clean_enabled" "$phase_after_clean_platform_list" \
      "$phase_after_clean_started" "$phase_after_clean_net_new_blocker" \
      "$phase_after_clean_blocking_platform" "$pre_after_clean_only"
    exit 2
    ;;
  *)
    exit "${aggregate_status:-2}"
    ;;
esac
