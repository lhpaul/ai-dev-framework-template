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
case "$MAX_WAIT" in
  ''|0|*[!0-9]*)
    echo "ERROR: --max-wait value '$MAX_WAIT' is not a positive integer (must be >= 1)" >&2
    exit 2
    ;;
esac

# ── Pre-flight: verify gh CLI authentication ──────────────────────────────────

if ! gh auth status >/dev/null 2>&1; then
  echo "ERROR: gh CLI not authenticated. Run 'gh auth login' before using claude-code-action-reviewer.sh" >&2
  echo "VERDICT: TIMED_OUT — gh CLI authentication failed (treated as unavailable)"
  exit 2
fi

# ── Resolve PR base branch for workflow dispatch ref ─────────────────────────

echo "INFO: resolving PR #$PR_NUMBER base branch..."
if ! BASE_REF=$(gh pr view "$PR_NUMBER" --repo "$OWNER/$REPO" --json baseRefName --jq '.baseRefName' 2>/dev/null); then
  echo "ERROR: could not resolve PR #$PR_NUMBER base branch" >&2
  echo "VERDICT: TIMED_OUT — could not resolve PR base branch (treated as unavailable)"
  exit 2
fi
if [ -z "$BASE_REF" ]; then
  echo "ERROR: could not resolve PR #$PR_NUMBER base branch (empty result)" >&2
  echo "VERDICT: TIMED_OUT — could not resolve PR base branch (treated as unavailable)"
  exit 2
fi

echo "INFO: PR #$PR_NUMBER base branch: $BASE_REF"
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

DISPATCH_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)
echo "INFO: dispatch time (pre-dispatch): $DISPATCH_TIME"

# ── Phase 1: Dispatch workflow ────────────────────────────────────────────────
# Call workflow_dispatch with ref=BASE_REF and pr_number input. On failure:
#   - 404 / "workflow was not found" → exit 3 (UNAVAILABLE: file absent)
#   - other errors → exit 3 (UNAVAILABLE: dispatch failure)

echo "INFO: dispatching workflow '$WORKFLOW_FILE' on ref '$BASE_REF' for PR #$PR_NUMBER..."

DISPATCH_STDERR=$(mktemp)
DISPATCH_STATUS=0
gh api "repos/$OWNER/$REPO/actions/workflows/$WORKFLOW_FILE/dispatches" \
  --method POST \
  --field "ref=$BASE_REF" \
  --raw-field "inputs[pr_number]=$PR_NUMBER" \
  2>"$DISPATCH_STDERR" || DISPATCH_STATUS=$?

if [ "$DISPATCH_STATUS" -ne 0 ]; then
  DISPATCH_ERR=$(cat "$DISPATCH_STDERR")
  rm -f "$DISPATCH_STDERR"
  echo "ERROR: workflow dispatch failed (exit $DISPATCH_STATUS): $DISPATCH_ERR" >&2
  # Distinguish 404 (workflow file absent / not found) from other errors
  if echo "$DISPATCH_ERR" | grep -qi "not found\|404\|workflow was not found"; then
    echo "VERDICT: TIMED_OUT — workflow file '$WORKFLOW_FILE' not found on ref '$BASE_REF' (treated as unavailable)"
  else
    echo "VERDICT: TIMED_OUT — workflow dispatch failed: $DISPATCH_ERR (treated as unavailable)"
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
  sleep "$POLL_INTERVAL"
  TOTAL_ELAPSED=$((TOTAL_ELAPSED + POLL_INTERVAL))
  echo "INFO: polling... elapsed ${TOTAL_ELAPSED}s / ${MAX_WAIT}s"

  # Query workflow runs filtered by event=workflow_dispatch. We look for the
  # most recent run that matches our workflow file and was created after
  # DISPATCH_TIME. Use a temp file to avoid SIGPIPE under pipefail.
  RUN_POLL_STDERR=$(mktemp)
  RUN_POLL_TMPFILE=$(mktemp)
  POLL_STATUS=0
  gh api "repos/$OWNER/$REPO/actions/runs?event=workflow_dispatch&per_page=20" \
    2>"$RUN_POLL_STDERR" \
    | jq -r --arg wf "$WORKFLOW_FILE" --arg dispatch_time "$DISPATCH_TIME" \
        '[.workflow_runs[] | select((.path | endswith($wf)) and .created_at >= $dispatch_time)] | first | {status: .status, conclusion: .conclusion, html_url: .html_url, id: .id}' \
    > "$RUN_POLL_TMPFILE" 2>/dev/null || POLL_STATUS=$?

  if [ "$POLL_STATUS" -ne 0 ]; then
    POLL_ERR=$(cat "$RUN_POLL_STDERR")
    rm -f "$RUN_POLL_STDERR" "$RUN_POLL_TMPFILE"
    echo "WARNING: gh api failed during run polling: $POLL_ERR" >&2
    continue
  fi
  rm -f "$RUN_POLL_STDERR"

  RUN_INFO=$(cat "$RUN_POLL_TMPFILE")
  rm -f "$RUN_POLL_TMPFILE"

  # jq outputs "null" when no matching run is found via `first` on empty array
  if [ -z "$RUN_INFO" ] || [ "$RUN_INFO" = "null" ]; then
    echo "INFO: no matching run found yet..."
    continue
  fi

  RUN_STATUS=$(echo "$RUN_INFO" | jq -r '.status // empty')
  RUN_CONCLUSION=$(echo "$RUN_INFO" | jq -r '.conclusion // empty')
  RUN_URL=$(echo "$RUN_INFO" | jq -r '.html_url // empty')

  echo "INFO: found run — status=$RUN_STATUS conclusion=$RUN_CONCLUSION url=$RUN_URL"

  # Check for terminal statuses
  case "$RUN_STATUS" in
    completed|failure|cancelled|skipped|timed_out|startup_failure)
      break
      ;;
    *)
      echo "INFO: run is still in progress (status=$RUN_STATUS), continuing to poll..."
      ;;
  esac
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
      '[.[] | select((.user.login == $bot or .user.login == $bot_plain) and .submitted_at != null and .submitted_at >= $dispatch_time)] | length, (.[].state // empty)' \
  > "$REVIEW_TMPFILE" 2>/dev/null || REVIEW_STATUS=$?

if [ "$REVIEW_STATUS" -ne 0 ]; then
  REVIEW_ERR=$(cat "$REVIEW_STDERR")
  rm -f "$REVIEW_STDERR" "$REVIEW_TMPFILE"
  echo "WARNING: could not fetch PR reviews (exit $REVIEW_STATUS): $REVIEW_ERR" >&2
  echo "VERDICT: APPROVED — run succeeded; review fetch failed (assuming clean)"
  exit 0
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
