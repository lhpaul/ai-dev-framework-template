#!/usr/bin/env bash
# claude-code-action-reviewer.sh — Claude Code Action reviewer path for Step 7a
#
# Implements the dispatch/poll/parse loop for the Claude Code Action GitHub App
# reviewer. Dispatches a workflow_dispatch event for the configured review workflow,
# polls for the resulting Actions run to complete, and inspects PR review threads
# to determine the final verdict.
#
# Classifies as universally reachable: requires only gh CLI access (no Claude Code
# CLI runtime), so it works from Claude Code, Cursor, headless CI, and any
# context where `gh` is authenticated.
#
# Usage:
#   claude-code-action-reviewer.sh <pr_number> <owner> <repo> [options]
#
# Options:
#   --workflow-file <name>   Filename of the GHA workflow to dispatch.
#                            Default: "claude-code-review.yml"
#                            Also overridable via CLAUDE_CODE_ACTION_WORKFLOW_FILE env var.
#   --bot-login     <login>  GitHub login of the Claude Code Action bot account.
#                            Default: "claude[bot]"
#                            Also overridable via CLAUDE_CODE_ACTION_BOT_LOGIN env var.
#   --poll-interval <secs>   Seconds between polling attempts. Default: 30
#   --max-wait      <secs>   Maximum total wait time for Actions run to complete.
#                            Default: 600
#
# Exit codes:
#   0 — APPROVED       (Actions run completed successfully, no new blocking review
#                       threads posted by the bot)
#   1 — NEEDS_REVISION (Actions run completed, bot posted new blocking review threads)
#   2 — TIMED_OUT      (Actions run did not complete within max-wait, dispatch failed,
#                       or workflow file absent; treat as unavailable under configured
#                       internal_reviewers_unavailable_policy)
#   3 — UNAVAILABLE    (workflow file absent or dispatch rejected — distinguishes from
#                       a true run timeout so callers can map to REASON=unavailable)

set -euo pipefail

# ── Argument parsing ──────────────────────────────────────────────────────────

if [ $# -lt 3 ]; then
  echo "Usage: $0 <pr_number> <owner> <repo> [--workflow-file <name>] [--bot-login <login>] [--poll-interval <seconds>] [--max-wait <seconds>]" >&2
  exit 2
fi

PR_NUMBER="$1"
OWNER="$2"
REPO="$3"
shift 3

# Validate positional arguments before interpolation into gh commands and API
# URLs (REVIEW.md: validate user-supplied input before interpolation).
case "$PR_NUMBER" in
  ''|0|*[!0-9]*)
    echo "ERROR: PR number '$PR_NUMBER' is not a valid positive integer" >&2
    exit 2
    ;;
esac
# GitHub owner and repo names consist of alphanumerics, hyphens, underscores,
# and dots. Reject empty values or values with other characters (including '/'
# which could redirect API paths).
case "$OWNER" in
  ''|*[!A-Za-z0-9._-]*)
    echo "ERROR: owner '$OWNER' contains invalid characters (expected alphanumerics, hyphens, underscores, dots)" >&2
    exit 2
    ;;
esac
case "$REPO" in
  ''|*[!A-Za-z0-9._-]*)
    echo "ERROR: repo '$REPO' contains invalid characters (expected alphanumerics, hyphens, underscores, dots)" >&2
    exit 2
    ;;
esac

# Defaults (overridable by flags or env vars)
WORKFLOW_FILE="${CLAUDE_CODE_ACTION_WORKFLOW_FILE:-claude-code-review.yml}"
BOT_LOGIN="${CLAUDE_CODE_ACTION_BOT_LOGIN:-claude[bot]}"
POLL_INTERVAL=30
MAX_WAIT=600

classify_claude_code_action_log() {
  local log_file="$1"

  if grep -Eqi 'Context prompt: NO PROMPT|Trigger result: false|No trigger found, skipping remaining steps|"prompt": ""' "$log_file"; then
    printf '%s\n' noop
    return 1
  fi

  if grep -Eqi 'Trigger result: true|Context prompt: .+' "$log_file" \
    && ! grep -Eqi 'Context prompt: NO PROMPT' "$log_file"; then
    printf '%s\n' ran
    return 0
  fi

  printf '%s\n' unknown
  return 2
}

while [ $# -gt 0 ]; do
  case "$1" in
    --workflow-file)
      if [ $# -lt 2 ]; then echo "ERROR: --workflow-file requires a value" >&2; exit 2; fi
      WORKFLOW_FILE="$2"; shift 2;;
    --bot-login)
      if [ $# -lt 2 ]; then echo "ERROR: --bot-login requires a value" >&2; exit 2; fi
      BOT_LOGIN="$2"; shift 2;;
    --poll-interval)
      if [ $# -lt 2 ]; then echo "ERROR: --poll-interval requires a value" >&2; exit 2; fi
      POLL_INTERVAL="$2"; shift 2;;
    --max-wait)
      if [ $# -lt 2 ]; then echo "ERROR: --max-wait requires a value" >&2; exit 2; fi
      MAX_WAIT="$2"; shift 2;;
    *)
      echo "ERROR: unknown option '$1'" >&2; exit 2;;
  esac
done

# ── Validate numeric options ──────────────────────────────────────────────────
# POLL_INTERVAL and MAX_WAIT are used in 'sleep' and arithmetic. Validate them
# here so a non-numeric value exits with code 2 (TIMED_OUT) instead of
# silently causing 'sleep' to fail under set -e with code 1 (NEEDS_REVISION).

case "$POLL_INTERVAL" in
  ''|0|*[!0-9]*)
    echo "ERROR: --poll-interval value '$POLL_INTERVAL' is not a positive integer (must be >= 1)" >&2
    exit 2
    ;;
esac
if [ "$POLL_INTERVAL" -gt 300 ]; then
  echo "ERROR: --poll-interval value '$POLL_INTERVAL' exceeds maximum of 300 seconds (5 minutes)" >&2
  exit 2
fi
case "$MAX_WAIT" in
  ''|0|*[!0-9]*)
    echo "ERROR: --max-wait value '$MAX_WAIT' is not a positive integer (must be >= 1)" >&2
    exit 2
    ;;
esac
if [ "$MAX_WAIT" -gt 3600 ]; then
  echo "ERROR: --max-wait value '$MAX_WAIT' exceeds maximum of 3600 seconds (1 hour)" >&2
  exit 2
fi

# ── Pre-flight: verify gh CLI authentication ──────────────────────────────────

if ! gh auth status >/dev/null 2>&1; then
  echo "ERROR: gh CLI not authenticated. Run 'gh auth login' before using claude-code-action-reviewer.sh" >&2
  echo "VERDICT: UNAVAILABLE — gh CLI authentication failed"
  exit 3
fi

# ── Resolve base branch and dispatch ref ─────────────────────────────────────
# BASE_REF is the PR's target branch (used for logging and context).
# DISPATCH_REF is always the repo's default branch: GitHub's workflow_dispatch
# API only serves workflows registered on the default branch. Dispatching
# against BASE_REF (e.g. 'develop') causes a permanent 404 when the workflow
# file is not yet on the default branch.

echo "INFO: resolving PR #$PR_NUMBER base branch..."
if ! BASE_REF=$(gh pr view "$PR_NUMBER" --repo "$OWNER/$REPO" --json baseRefName --jq '.baseRefName' 2>/dev/null); then
  echo "ERROR: could not resolve PR #$PR_NUMBER base branch" >&2
  echo "VERDICT: UNAVAILABLE — could not resolve PR base branch"
  exit 3
fi
if [ -z "$BASE_REF" ]; then
  echo "ERROR: could not resolve PR #$PR_NUMBER base branch (empty result)" >&2
  echo "VERDICT: UNAVAILABLE — could not resolve PR base branch (empty result)"
  exit 3
fi

DEFAULT_BRANCH=$(gh repo view "$OWNER/$REPO" --json defaultBranchRef --jq '.defaultBranchRef.name' 2>/dev/null) || true
if [ -z "$DEFAULT_BRANCH" ]; then
  DEFAULT_BRANCH="main"
fi
DISPATCH_REF="$DEFAULT_BRANCH"
echo "INFO: PR #$PR_NUMBER base branch: $BASE_REF (dispatch ref: $DISPATCH_REF)"
echo "INFO: dispatch ref: $DISPATCH_REF (GitHub workflow_dispatch requires the workflow on the default branch)"
echo "INFO: Workflow file: $WORKFLOW_FILE"
echo "INFO: Bot login: $BOT_LOGIN"
if [ "$POLL_INTERVAL" -gt "$MAX_WAIT" ]; then
  POLL_INTERVAL="$MAX_WAIT"
fi
echo "INFO: Poll interval: ${POLL_INTERVAL}s, Max wait (total): ${MAX_WAIT}s"

# Derive plain bot login (without [bot] suffix) for matching PR reviews.
BOT_LOGIN_PLAIN="${BOT_LOGIN%\[bot\]}"
echo "INFO: Bot login (plain, for review matching): $BOT_LOGIN_PLAIN"

# ── Record dispatch time (before dispatch to scope run polling) ───────────────
# Subtract a 10-second buffer from the local clock to guard against clock skew
# between the runner and GitHub's servers. GitHub Actions run created_at
# timestamps reflect the server clock; if the server clock lags behind ours,
# a run created_at value could be earlier than our local DISPATCH_TIME,
# causing the polling filter (.created_at >= $POLL_AFTER_TIME) to miss the run.
# Using a 10-second buffer ensures runs are matched even with moderate clock skew.

_DISPATCH_EPOCH=$(date -u +%s)
DISPATCH_TIME=$(date -u -r "$_DISPATCH_EPOCH" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || \
  date -u -d "@$_DISPATCH_EPOCH" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || \
  python3 -c "import datetime,sys; print(datetime.datetime.fromtimestamp(int(sys.argv[1]), datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'))" "$_DISPATCH_EPOCH")
_POLL_EPOCH=$((_DISPATCH_EPOCH - 10))
POLL_AFTER_TIME=$(date -u -r "$_POLL_EPOCH" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || \
  date -u -d "@$_POLL_EPOCH" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || \
  python3 -c "import datetime,sys; print(datetime.datetime.fromtimestamp(int(sys.argv[1]), datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'))" "$_POLL_EPOCH")
unset _DISPATCH_EPOCH _POLL_EPOCH
echo "INFO: dispatch time (pre-dispatch): $DISPATCH_TIME"
echo "INFO: poll filter time (with 10s clock-skew buffer): $POLL_AFTER_TIME"

# ── Phase 1: Dispatch workflow ────────────────────────────────────────────────
# Call workflow_dispatch with ref=DISPATCH_REF (default branch) and pr_number
# input. On failure:
#   - 404 / "workflow was not found" → exit 3 (UNAVAILABLE: file absent)
#   - other errors → exit 3 (UNAVAILABLE: dispatch failure)

echo "INFO: dispatching workflow '$WORKFLOW_FILE' on ref '$DISPATCH_REF' for PR #$PR_NUMBER..."

DISPATCH_STDERR=$(mktemp)
DISPATCH_STATUS=0
gh api "repos/$OWNER/$REPO/actions/workflows/$WORKFLOW_FILE/dispatches" \
  --method POST \
  --raw-field "ref=$DISPATCH_REF" \
  --raw-field "inputs[pr_number]=$PR_NUMBER" \
  2>"$DISPATCH_STDERR" || DISPATCH_STATUS=$?

if [ "$DISPATCH_STATUS" -ne 0 ]; then
  DISPATCH_ERR=$(cat "$DISPATCH_STDERR")
  rm -f "$DISPATCH_STDERR"
  echo "ERROR: workflow dispatch failed (exit $DISPATCH_STATUS): $DISPATCH_ERR" >&2
  # Distinguish 404 (workflow file absent / not found) from other errors
  if echo "$DISPATCH_ERR" | grep -qi "not found\|404\|workflow was not found"; then
    echo "VERDICT: UNAVAILABLE — workflow file '$WORKFLOW_FILE' not found on ref '$DISPATCH_REF'"
  else
    echo "VERDICT: UNAVAILABLE — workflow dispatch failed: $DISPATCH_ERR"
  fi
  exit 3
fi
rm -f "$DISPATCH_STDERR"

echo "INFO: workflow dispatch accepted (HTTP 204 — no body expected)"

# ── Phase 2: Poll for run completion ─────────────────────────────────────────
# Poll at POLL_INTERVAL intervals for a run matching WORKFLOW_FILE that was
# created at or after DISPATCH_TIME. Stop when the run reaches a terminal status.

echo "INFO: polling for workflow run created after $DISPATCH_TIME..."

TOTAL_ELAPSED=0
RUN_URL=""
RUN_CONCLUSION=""

while [ "$TOTAL_ELAPSED" -lt "$MAX_WAIT" ]; do
  echo "INFO: polling... elapsed ${TOTAL_ELAPSED}s / ${MAX_WAIT}s"

  # Query workflow runs filtered by event=workflow_dispatch. We look for the
  # most recent run matching our workflow file and created at or after
  # POLL_AFTER_TIME (dispatch time minus 10-second clock-skew buffer).
  #
  # PR-scoping via run-name (required for concurrent/parallel dispatch):
  #   The GitHub Actions Runs API always returns inputs: null regardless of what
  #   was passed at dispatch time (confirmed empirically via
  #   `gh api ".../actions/runs/<id>" --jq 'has("inputs")'` → false for all tested
  #   runs, including workflow_dispatch-triggered runs). Under concurrent dispatch,
  #   two PRs that trigger claude-code-review.yml within the same poll window both
  #   match the timestamp filter, so `sort_by | reverse | first` could select the
  #   wrong PR's run. To fix this, claude-code-review.yml sets
  #   `run-name: "Claude Code Review — PR #${{ inputs.pr_number }}"`, and GitHub
  #   populates that string into the .name field on Runs API objects. The filter
  #   below prefers name-scoped runs whose parsed "PR #<number>" token equals
  #   this PR number, and falls back to timestamp-only selection when the
  #   workflow has not yet been updated to include run-name (backward compatibility
  #   during the transition period after #808 is merged to the default branch).
  #   The timestamp filter remains as a secondary guard in the fallback path to
  #   exclude pre-dispatch runs. See issue #806 and #808.
  # Use a temp file to avoid SIGPIPE under pipefail.
  RUN_POLL_STDERR=$(mktemp)
  RUN_POLL_TMPFILE=$(mktemp)
  POLL_STATUS=0
  gh api --paginate "repos/$OWNER/$REPO/actions/runs?event=workflow_dispatch&per_page=100" \
    2>"$RUN_POLL_STDERR" \
    | jq -sr --arg wf "$WORKFLOW_FILE" --arg poll_after "$POLL_AFTER_TIME" \
        --arg pr "$PR_NUMBER" \
        '# Candidate set: workflow-file + timestamp match
         [.[] | .workflow_runs[]?] as $all |
         [$all[] | select((.path | endswith($wf)) and .created_at >= $poll_after)] as $candidates |
         # PR-scoping via run-name (#808): if any candidate has a "PR #N"-style name
         # (indicating the workflow uses run-name), require name match for THIS PR to
         # prevent selecting the wrong PR'\''s run under concurrent/parallel dispatch.
         # Fall back to all candidates when no run has the "PR #N" pattern — backward
         # compat with pre-#808 deployments where the workflow has no run-name yet.
         ([$candidates[] | select((.name // "") | capture("PR #(?<pr>[0-9]+)(?:[^0-9]|$)")?)] | length > 0) as $name_scoped |
         ($candidates | if $name_scoped then
           [.[] | select(((.name // "") | capture("PR #(?<pr>[0-9]+)(?:[^0-9]|$)")? | .pr) == $pr)]
         else . end) |
         sort_by(.created_at) | reverse | first |
         {status: .status, conclusion: .conclusion, html_url: .html_url, id: .id}' \
    > "$RUN_POLL_TMPFILE" 2>/dev/null || POLL_STATUS=$?

  if [ "$POLL_STATUS" -ne 0 ]; then
    POLL_ERR=$(cat "$RUN_POLL_STDERR")
    rm -f "$RUN_POLL_STDERR" "$RUN_POLL_TMPFILE"
    echo "WARNING: gh api failed during run polling: $POLL_ERR" >&2
    sleep "$POLL_INTERVAL"
    TOTAL_ELAPSED=$((TOTAL_ELAPSED + POLL_INTERVAL))
    continue
  fi
  rm -f "$RUN_POLL_STDERR"

  RUN_INFO=$(cat "$RUN_POLL_TMPFILE")
  rm -f "$RUN_POLL_TMPFILE"

  # jq outputs "null" when no matching run is found via `first` on empty array
  if [ -z "$RUN_INFO" ] || [ "$RUN_INFO" = "null" ]; then
    echo "INFO: no matching run found yet..."
    sleep "$POLL_INTERVAL"
    TOTAL_ELAPSED=$((TOTAL_ELAPSED + POLL_INTERVAL))
    continue
  fi

  RUN_STATUS=$(echo "$RUN_INFO" | jq -r '.status // empty')
  RUN_CONCLUSION=$(echo "$RUN_INFO" | jq -r '.conclusion // empty')
  RUN_URL=$(echo "$RUN_INFO" | jq -r '.html_url // empty')
  RUN_ID=$(echo "$RUN_INFO" | jq -r '.id // empty')

  echo "INFO: found run — id=$RUN_ID status=$RUN_STATUS conclusion=$RUN_CONCLUSION url=$RUN_URL"

  # GitHub Actions API uses `status` for run lifecycle (queued, in_progress,
  # completed) and `conclusion` for the terminal outcome (success, failure,
  # cancelled, etc.). Break only when status=completed; conclusion is read in
  # Phase 3 to determine the verdict.
  if [ "$RUN_STATUS" = "completed" ]; then
    break
  fi

  echo "INFO: run is still in progress (status=$RUN_STATUS), continuing to poll..."
  sleep "$POLL_INTERVAL"
  TOTAL_ELAPSED=$((TOTAL_ELAPSED + POLL_INTERVAL))
done

# ── Phase 3: Parse result ─────────────────────────────────────────────────────

if [ -z "$RUN_CONCLUSION" ] || [ "$RUN_CONCLUSION" = "null" ]; then
  echo "VERDICT: TIMED_OUT — no run completed within ${MAX_WAIT}s (run URL: ${RUN_URL:-unknown})"
  echo "INFO: remediation — verify the '$WORKFLOW_FILE' workflow is present and configured in $OWNER/$REPO."
  exit 2
fi

if [ "$RUN_CONCLUSION" != "success" ]; then
  echo "VERDICT: TIMED_OUT — run completed with conclusion '$RUN_CONCLUSION' (not 'success'): $RUN_URL"
  echo "INFO: remediation — check the Actions run log at $RUN_URL for details."
  exit 2
fi

echo "INFO: Actions run completed with conclusion=success: $RUN_URL"

# A successful Actions run is not proof that Claude actually reviewed the PR.
# claude-code-action exits successfully when no prompt/trigger is present, logging
# "No trigger found" and posting no review. Treat that as unavailable rather than
# clean so the reviewer loop does not bless no-op runs.
if [ -z "$RUN_ID" ] || [ "$RUN_ID" = "null" ]; then
  echo "VERDICT: UNAVAILABLE — run succeeded but no run id was available for log verification"
  exit 3
fi

RUN_LOG_STDERR=$(mktemp)
RUN_LOG_TMPFILE=$(mktemp)
RUN_LOG_STATUS=0
gh run view "$RUN_ID" --repo "$OWNER/$REPO" --log \
  >"$RUN_LOG_TMPFILE" 2>"$RUN_LOG_STDERR" || RUN_LOG_STATUS=$?

if [ "$RUN_LOG_STATUS" -ne 0 ]; then
  RUN_LOG_ERR=$(cat "$RUN_LOG_STDERR")
  rm -f "$RUN_LOG_STDERR" "$RUN_LOG_TMPFILE"
  echo "WARNING: could not fetch Actions run log (exit $RUN_LOG_STATUS): $RUN_LOG_ERR" >&2
  echo "VERDICT: UNAVAILABLE — run succeeded but log verification failed"
  exit 3
fi
rm -f "$RUN_LOG_STDERR"

LOG_CLASSIFICATION_STATUS=0
LOG_CLASSIFICATION="$(classify_claude_code_action_log "$RUN_LOG_TMPFILE")" || LOG_CLASSIFICATION_STATUS=$?
rm -f "$RUN_LOG_TMPFILE"

case "$LOG_CLASSIFICATION_STATUS" in
  0)
    echo "INFO: Claude Code Action log verification passed ($LOG_CLASSIFICATION)"
    ;;
  1)
    echo "VERDICT: UNAVAILABLE — Claude Code Action run completed without executing a review ($LOG_CLASSIFICATION)"
    exit 3
    ;;
  *)
    echo "VERDICT: UNAVAILABLE — Claude Code Action run log did not contain a positive execution marker ($LOG_CLASSIFICATION)"
    exit 3
    ;;
esac

# ── Phase 3 (continued): Check PR review threads ──────────────────────────────
# After a successful run, inspect PR reviews posted by the bot after dispatch_time.
# If any review has state=CHANGES_REQUESTED, exit 1 (NEEDS_REVISION).
# Otherwise exit 0 (APPROVED).

echo "INFO: checking PR #$PR_NUMBER reviews from '$BOT_LOGIN' posted after $DISPATCH_TIME..."

REVIEW_STDERR=$(mktemp)
REVIEW_TMPFILE=$(mktemp)
REVIEW_STATUS=0
gh api "repos/$OWNER/$REPO/pulls/$PR_NUMBER/reviews" --paginate \
  2>"$REVIEW_STDERR" \
  | jq -r --arg bot "$BOT_LOGIN" --arg bot_plain "$BOT_LOGIN_PLAIN" \
      --arg dispatch_time "$DISPATCH_TIME" \
      '[.[] | select((.user.login == $bot or .user.login == ($bot_plain + "[bot]")) and .submitted_at != null and .submitted_at >= $dispatch_time)] | length, (.[].state // empty)' \
  > "$REVIEW_TMPFILE" 2>/dev/null || REVIEW_STATUS=$?

if [ "$REVIEW_STATUS" -ne 0 ]; then
  REVIEW_ERR=$(cat "$REVIEW_STDERR")
  rm -f "$REVIEW_STDERR" "$REVIEW_TMPFILE"
  echo "WARNING: could not fetch PR reviews (exit $REVIEW_STATUS): $REVIEW_ERR" >&2
  echo "VERDICT: UNAVAILABLE — run succeeded but review fetch failed"
  exit 3
fi
rm -f "$REVIEW_STDERR"

REVIEW_OUTPUT=$(cat "$REVIEW_TMPFILE")
rm -f "$REVIEW_TMPFILE"

# Check whether any review has state CHANGES_REQUESTED
if echo "$REVIEW_OUTPUT" | grep -qi "CHANGES_REQUESTED"; then
  echo "VERDICT: NEEDS_REVISION — bot posted a review with state=CHANGES_REQUESTED after dispatch"
  exit 1
fi

echo "VERDICT: APPROVED — Actions run succeeded and no blocking review threads found"
exit 0
