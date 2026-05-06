#!/usr/bin/env bash
# codex-github-reviewer.sh — Codex GitHub App reviewer path for Step 7a
#
# Implements the trigger/poll/parse loop for the Codex GitHub bot reviewer.
# Classifies as universally reachable: requires only gh CLI access (no Codex
# CLI runtime), so it works from Claude Code, Cursor, headless CI, and any
# context where `gh` is authenticated.
#
# Usage:
#   codex-github-reviewer.sh <pr_number> <owner> <repo> [options]
#
# Options:
#   --trigger-phrase <phrase>   Trigger phrase to post. Default: "@codex review"
#                               Also overridable via CODEX_GITHUB_TRIGGER_PHRASE env var.
#   --bot-login     <login>     GitHub login of the Codex bot account.
#                               Default: "codex-ai[bot]"
#                               Also overridable via CODEX_GITHUB_BOT_LOGIN env var.
#                               Verify the actual bot login from your GitHub App settings.
#   --poll-interval  <seconds>   Seconds between polling attempts. Default: 30
#   --max-wait       <seconds>   Maximum wait time per attempt for bot response. Default: 600
#   --max-retriggers <count>     How many times to re-post the trigger after a timeout
#                                before giving up. Default: 1 (so up to 2 attempts total).
#                                Set to 0 to disable retriggering.
#
# Exit codes:
#   0 — APPROVED   (bot responded with no blocking findings)
#   1 — NEEDS_REVISION (bot responded with blocking findings)
#   2 — TIMED_OUT  (no bot response within max-wait; treat as unavailable under
#                   configured internal_reviewers_unavailable_policy)
#
# Verdict parsing (three-path, blocking markers checked first per safe-fail):
#   1. Blocking markers present → NEEDS_REVISION (exit 1)
#      Markers (case-insensitive): "changes requested", "blocking issues/finding",
#      "blocking:", "must fix", "action required", "required:", "❌"
#      Note: bare "blocking" is excluded to avoid false positives on
#      "no blocking issues found" — use specific phrases instead.
#   2. Approval signals present → APPROVED (exit 0)
#      Signals (case-insensitive): "approved", "lgtm", "looks good",
#      "didn't find any major issues" (Codex-specific clean phrase)
#   3. Neither found (unrecognized format) → safe-fails to NEEDS_REVISION (exit 1)
#
# Response source detection (two sources polled each cycle):
#   - issues/{PR}/comments — plain PR comments; matches both BOT_LOGIN and
#     BOT_LOGIN_PLAIN (login without [bot] suffix). Codex posts "clean" results
#     here from the non-[bot] account (e.g. "chatgpt-codex-connector").
#   - pulls/{PR}/reviews   — GitHub Review objects; matches both logins. Codex
#     posts findings here from the [bot]-suffixed account. Polled as fallback
#     when no PR comment is found; review body safe-fails to NEEDS_REVISION,
#     which causes pr-review-loop.sh to count unresolved inline threads.
#
# Idempotency (BR-10):
#   Before posting a trigger comment, the script queries existing PR comments
#   for a trigger comment authored by a human/runner user (not the bot) that
#   contains the current commit SHA. If found, the trigger post is skipped and
#   polling proceeds from the existing trigger timestamp.

set -euo pipefail

# ── Argument parsing ──────────────────────────────────────────────────────────

if [ $# -lt 3 ]; then
  echo "Usage: $0 <pr_number> <owner> <repo> [--trigger-phrase <phrase>] [--bot-login <login>] [--poll-interval <seconds>] [--max-wait <seconds>] [--max-retriggers <count>]" >&2
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
TRIGGER_PHRASE="${CODEX_GITHUB_TRIGGER_PHRASE:-@codex review}"
BOT_LOGIN="${CODEX_GITHUB_BOT_LOGIN:-codex-ai[bot]}"
POLL_INTERVAL=30
MAX_WAIT=600
MAX_RETRIGGERS=1

while [ $# -gt 0 ]; do
  case "$1" in
    --trigger-phrase)
      if [ $# -lt 2 ]; then echo "ERROR: --trigger-phrase requires a value" >&2; exit 2; fi
      TRIGGER_PHRASE="$2"; shift 2;;
    --bot-login)
      if [ $# -lt 2 ]; then echo "ERROR: --bot-login requires a value" >&2; exit 2; fi
      BOT_LOGIN="$2"; shift 2;;
    --poll-interval)
      if [ $# -lt 2 ]; then echo "ERROR: --poll-interval requires a value" >&2; exit 2; fi
      POLL_INTERVAL="$2"; shift 2;;
    --max-wait)
      if [ $# -lt 2 ]; then echo "ERROR: --max-wait requires a value" >&2; exit 2; fi
      MAX_WAIT="$2"; shift 2;;
    --max-retriggers)
      if [ $# -lt 2 ]; then echo "ERROR: --max-retriggers requires a value" >&2; exit 2; fi
      MAX_RETRIGGERS="$2"; shift 2;;
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
# MAX_RETRIGGERS may be 0 (disable retriggering) but must be a non-negative integer.
case "$MAX_RETRIGGERS" in
  ''|*[!0-9]*)
    echo "ERROR: --max-retriggers value '$MAX_RETRIGGERS' is not a non-negative integer (must be >= 0)" >&2
    exit 2
    ;;
esac

# ── Pre-flight: verify gh CLI authentication ──────────────────────────────────

if ! gh auth status >/dev/null 2>&1; then
  echo "ERROR: gh CLI not authenticated. Run 'gh auth login' before using codex-github-reviewer.sh" >&2
  echo "VERDICT: TIMED_OUT — gh CLI authentication failed (treated as unavailable)"
  exit 2
fi

# ── Resolve current HEAD commit SHA ──────────────────────────────────────────
# Guard the assignment with 'if !' to prevent set -e from exiting with code 1
# (NEEDS_REVISION) before the empty-check guard below can emit the VERDICT line.

if ! CURRENT_SHA=$(gh pr view "$PR_NUMBER" --repo "$OWNER/$REPO" --json headRefOid --jq '.headRefOid' | head -c 100); then
  echo "ERROR: could not resolve PR #$PR_NUMBER HEAD SHA" >&2
  echo "VERDICT: TIMED_OUT — could not resolve PR HEAD SHA (treated as unavailable)"
  exit 2
fi
CURRENT_SHA=$(printf '%s' "$CURRENT_SHA" | cut -c1-12)
if [ -z "$CURRENT_SHA" ]; then
  echo "ERROR: could not resolve PR #$PR_NUMBER HEAD SHA (empty result)" >&2
  echo "VERDICT: TIMED_OUT — could not resolve PR HEAD SHA (treated as unavailable)"
  exit 2
fi

echo "INFO: PR #$PR_NUMBER HEAD commit: $CURRENT_SHA"
echo "INFO: Bot login: $BOT_LOGIN"
echo "INFO: Trigger phrase: $TRIGGER_PHRASE"
echo "INFO: Poll interval: ${POLL_INTERVAL}s, Max wait: ${MAX_WAIT}s"

# Derive plain bot login (without [bot] suffix) for matching PR-comment responses.
# Codex posts "clean" results as regular PR comments from the non-[bot] account
# (e.g. "chatgpt-codex-connector"), while findings are posted as GitHub Reviews
# from the [bot]-suffixed account (e.g. "chatgpt-codex-connector[bot]").
BOT_LOGIN_PLAIN="${BOT_LOGIN%\[bot\]}"
echo "INFO: Bot login (plain, for PR-comment matching): $BOT_LOGIN_PLAIN"

# ── Idempotency guard (BR-10) ─────────────────────────────────────────────────
# Check whether a trigger comment for the current commit SHA already exists.
# We look for a comment body containing BOTH the trigger phrase AND the SHA to
# avoid falsely matching bot review comments or human comments that happen to
# reference the commit SHA.

# Capture the idempotency check to a temp file to avoid SIGPIPE under pipefail.
# Use 'jq --arg' for safe variable binding — avoids jq injection if the trigger
# phrase or SHA contain jq-special characters (double quote, backslash).
# Note: `]` must appear first in the bracket expression to be treated as literal.
IDEM_STDERR=$(mktemp)
IDEM_TMPFILE=$(mktemp)
if gh api "repos/$OWNER/$REPO/issues/$PR_NUMBER/comments" --paginate \
  2>"$IDEM_STDERR" \
  | jq -r --arg sha "$CURRENT_SHA" --arg trigger "$TRIGGER_PHRASE" --arg bot "$BOT_LOGIN" --arg bot_plain "$BOT_LOGIN_PLAIN" \
    '.[] | select(.user.login != $bot and .user.login != $bot_plain) | select((.body | test($sha)) and (.body | ascii_downcase | contains($trigger | ascii_downcase))) | {id: .id, created_at: .created_at, body: .body}' \
  > "$IDEM_TMPFILE"; then
  TRIGGER_COMMENT_INFO=$(head -c 2000 "$IDEM_TMPFILE")
else
  IDEM_ERR=$(cat "$IDEM_STDERR")
  echo "WARNING: gh api failed in idempotency check (will proceed with trigger post as fallback): $IDEM_ERR" >&2
  TRIGGER_COMMENT_INFO=""
fi
rm -f "$IDEM_STDERR" "$IDEM_TMPFILE"

TRIGGER_TIME=""
if [ -n "$TRIGGER_COMMENT_INFO" ]; then
  # jq outputs pretty-printed JSON with a space after the colon: "created_at": "..."
  # Use ' *' to match zero or more spaces to handle both compact and pretty-print output.
  TRIGGER_TIME=$(echo "$TRIGGER_COMMENT_INFO" | grep -o '"created_at": *"[^"]*"' | head -1 | sed 's/"created_at": *"//;s/"//')
  if [ -n "$TRIGGER_TIME" ]; then
    echo "INFO: trigger comment already posted for commit $CURRENT_SHA (at $TRIGGER_TIME) — skipping duplicate post"
  fi
fi

# ── Post trigger comment (if no duplicate found) ──────────────────────────────

if [ -z "$TRIGGER_TIME" ]; then
  echo "INFO: posting trigger comment to PR #$PR_NUMBER..."
  # Use gh api --method POST to capture the GitHub-server-assigned created_at
  # timestamp. Using 'date -u' here would risk clock skew between the local
  # machine and GitHub's API server, causing bot responses to be silently
  # filtered out during polling (created_at > TRIGGER_TIME would be false).
  # Guard with 'if !' to emit TIMED_OUT (exit 2) on failure instead of letting
  # set -e exit with code 1 (NEEDS_REVISION) without a VERDICT line.
  if ! TRIGGER_TIME=$(gh api "repos/$OWNER/$REPO/issues/$PR_NUMBER/comments" \
    --method POST \
    --raw-field body="$TRIGGER_PHRASE (review triggered by workflow runner, commit: $CURRENT_SHA)" \
    --jq '.created_at'); then
    echo "ERROR: failed to post trigger comment to PR #$PR_NUMBER" >&2
    echo "VERDICT: TIMED_OUT — failed to post trigger comment (treated as unavailable)"
    exit 2
  fi
  echo "INFO: trigger comment posted at $TRIGGER_TIME (server-assigned timestamp)"
fi

# ── Poll for bot response (with retrigger support) ───────────────────────────
#
# Outer loop: each iteration is one full poll attempt of up to MAX_WAIT seconds.
# If the bot does not respond within MAX_WAIT, we re-post the trigger comment
# (up to MAX_RETRIGGERS times) and start a fresh inner poll. This handles the
# case where Codex silently drops the first @codex review request — in practice
# a re-post usually gets a response. After all attempts are exhausted, we exit
# with TIMED_OUT (treated as unavailable by the caller).

echo "INFO: polling for response from '$BOT_LOGIN' (trigger time: $TRIGGER_TIME)..."
echo "INFO: MAX_WAIT=${MAX_WAIT}s per attempt; up to $((MAX_RETRIGGERS + 1)) attempt(s) total (MAX_RETRIGGERS=$MAX_RETRIGGERS)"

RETRIGGER_COUNT=0
CONSECUTIVE_API_FAILURES=0
MAX_CONSECUTIVE_FAILURES=3
while true; do
ELAPSED=0
while [ "$ELAPSED" -lt "$MAX_WAIT" ]; do
  sleep "$POLL_INTERVAL"
  ELAPSED=$((ELAPSED + POLL_INTERVAL))

  echo "INFO: polling... elapsed ${ELAPSED}s / ${MAX_WAIT}s"

  # Query comments authored by the bot that appeared after the trigger comment timestamp.
  # The bot login may include "[bot]" suffix — use exact string match on user.login.
  # Write the full output to a temp file first to avoid SIGPIPE under pipefail:
  # piping directly to 'head -c N' causes gh api to receive SIGPIPE when head
  # closes its stdin early (when response > N bytes), which pipefail propagates
  # as a non-zero exit code — falsely triggering the API failure counter.
  # Use 'jq --arg' for safe variable binding — avoids jq injection if BOT_LOGIN
  # contains jq-special characters (e.g., double quote, backslash).
  POLL_STDERR=$(mktemp)
  POLL_TMPFILE=$(mktemp)
  if gh api "repos/$OWNER/$REPO/issues/$PR_NUMBER/comments" --paginate \
    2>"$POLL_STDERR" \
    | jq -r --arg bot "$BOT_LOGIN" --arg bot_plain "$BOT_LOGIN_PLAIN" --arg trigger_time "$TRIGGER_TIME" \
        '.[] | select(.user.login == $bot or .user.login == $bot_plain) | select(.created_at > $trigger_time) | .body' \
    > "$POLL_TMPFILE"; then
    # Truncate after successful API call — no SIGPIPE risk here
    BOT_RESPONSE=$(head -c 10000 "$POLL_TMPFILE")
    rm -f "$POLL_STDERR" "$POLL_TMPFILE"
    CONSECUTIVE_API_FAILURES=0
  else
    POLL_ERR=$(cat "$POLL_STDERR")
    rm -f "$POLL_STDERR" "$POLL_TMPFILE"
    CONSECUTIVE_API_FAILURES=$((CONSECUTIVE_API_FAILURES + 1))
    echo "WARNING: gh api failed during polling (attempt $CONSECUTIVE_API_FAILURES): $POLL_ERR" >&2
    if [ "$CONSECUTIVE_API_FAILURES" -ge "$MAX_CONSECUTIVE_FAILURES" ]; then
      echo "VERDICT: TIMED_OUT — gh api failed $CONSECUTIVE_API_FAILURES consecutive times. Last error: $POLL_ERR"
      echo "INFO: remediation — check gh CLI authentication, API rate limits, and network connectivity."
      exit 2
    fi
    continue
  fi

  # Also check PR reviews — Codex posts findings as a GitHub Review object
  # (via pulls/{PR}/reviews), not as a plain PR comment. Combining both sources
  # ensures we detect findings immediately instead of waiting for a timeout.
  if [ -z "$BOT_RESPONSE" ]; then
    REVIEW_TMPFILE=$(mktemp)
    if gh api "repos/$OWNER/$REPO/pulls/$PR_NUMBER/reviews" --paginate \
      2>/dev/null \
      | jq -r --arg bot "$BOT_LOGIN" --arg bot_plain "$BOT_LOGIN_PLAIN" --arg trigger_time "$TRIGGER_TIME" \
          '.[] | select((.user.login == $bot or .user.login == $bot_plain) and .submitted_at != null and .submitted_at > $trigger_time) | .body' \
      > "$REVIEW_TMPFILE" 2>/dev/null; then
      REVIEW_BODY=$(head -c 5000 "$REVIEW_TMPFILE")
      if [ -n "$REVIEW_BODY" ]; then
        BOT_RESPONSE="$REVIEW_BODY"
        echo "INFO: bot response detected via PR reviews endpoint"
      fi
    fi
    rm -f "$REVIEW_TMPFILE"
  fi

  if [ -n "$BOT_RESPONSE" ]; then
    echo "INFO: bot response detected"

    # ── Verdict parsing ───────────────────────────────────────────────────────
    # Three-path classification (per spec BR-4 and implementation plan risk table).
    # Blocking markers are checked FIRST (safe-fail: a false NEEDS_REVISION that
    # triggers an unnecessary fix cycle is safer than a false APPROVED that
    # silently ignores blocking findings). Note: even specific phrases like
    # "blocking issues" can still match within negated context ("No blocking
    # issues found"). This is an accepted safe-fail trade-off — the result is
    # an unnecessary fix cycle, not a missed rejection. The bare word "blocking"
    # is excluded because it is too broad; the phrases below are more targeted.
    #
    # 1. Blocking markers present → NEEDS_REVISION (exit 1)      [checked first]
    #    Blocking markers (case-insensitive): "changes requested",
    #    "blocking issues", "blocking finding", "blocking:", "must fix",
    #    "action required", "required:", "❌"
    #
    # 2. Explicit approval signals present → APPROVED (exit 0)   [checked second]
    #    Approval signals: "approved", "lgtm", "looks good",
    #    "didn't find any major issues" (Codex-specific clean phrase)
    #
    # 3. Neither found (unrecognized response format) → NEEDS_REVISION (exit 1)
    #    Safe-fail: default to NEEDS_REVISION when the format is unrecognized to
    #    avoid incorrectly approving a response that is a rejection in an
    #    unexpected format (per spec risk mitigation for BR-4).

    if echo "$BOT_RESPONSE" | grep -qiE "(changes[[:space:]]+requested|blocking[[:space:]]+issues?|blocking[[:space:]]+finding|blocking:|must[[:space:]]+fix|action[[:space:]]+required|required:|❌)"; then
      echo "VERDICT: NEEDS_REVISION"
      echo "---BEGIN BOT RESPONSE---"
      echo "$BOT_RESPONSE"
      echo "---END BOT RESPONSE---"
      exit 1
    elif echo "$BOT_RESPONSE" | grep -qiE "(approved|lgtm|looks[[:space:]]+good|didn.t find[[:space:]]+any major[[:space:]]+issues)"; then
      echo "VERDICT: APPROVED"
      echo "---BEGIN BOT RESPONSE---"
      echo "$BOT_RESPONSE"
      echo "---END BOT RESPONSE---"
      exit 0
    else
      echo "VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)"
      echo "---BEGIN BOT RESPONSE---"
      echo "$BOT_RESPONSE"
      echo "---END BOT RESPONSE---"
      exit 1
    fi
  fi
done

# Inner poll loop ended without a bot response — try to re-trigger if budget remains.
if [ "$RETRIGGER_COUNT" -lt "$MAX_RETRIGGERS" ]; then
  RETRIGGER_COUNT=$((RETRIGGER_COUNT + 1))
  ATTEMPT_NUM=$((RETRIGGER_COUNT + 1))
  TOTAL_ATTEMPTS=$((MAX_RETRIGGERS + 1))
  echo "INFO: no response after ${MAX_WAIT}s; re-triggering (attempt ${ATTEMPT_NUM}/${TOTAL_ATTEMPTS})..."
  # Refresh CURRENT_SHA in case the PR HEAD changed since the previous attempt.
  # CURRENT_SHA is set before the outer loop (at script start) but may be stale
  # if a new commit was pushed while we were waiting.
  CURRENT_SHA=$(gh pr view "$PR_NUMBER" --repo "$OWNER/$REPO" --json headRefOid \
    --jq '.headRefOid' 2>/dev/null | cut -c1-12 || printf '%s' "$CURRENT_SHA")
  if ! TRIGGER_TIME=$(gh api "repos/$OWNER/$REPO/issues/$PR_NUMBER/comments" \
    --method POST \
    --raw-field body="$TRIGGER_PHRASE (retrigger ${RETRIGGER_COUNT}/${MAX_RETRIGGERS} after timeout, commit: $CURRENT_SHA)" \
    --jq '.created_at'); then
    echo "ERROR: failed to post retrigger comment to PR #$PR_NUMBER" >&2
    echo "VERDICT: TIMED_OUT — failed to post retrigger comment (treated as unavailable)"
    exit 2
  fi
  echo "INFO: retrigger comment posted at $TRIGGER_TIME (server-assigned timestamp)"
  continue
else
  break
fi
done

# ── Timeout ───────────────────────────────────────────────────────────────────

TOTAL_ATTEMPTS=$((MAX_RETRIGGERS + 1))
echo "VERDICT: TIMED_OUT — no response from '$BOT_LOGIN' after ${TOTAL_ATTEMPTS} attempt(s) (${MAX_WAIT}s each)"
echo "INFO: remediation — verify the Codex GitHub App is installed on $OWNER/$REPO."
echo "INFO: You can manually trigger the review by posting: $TRIGGER_PHRASE"
exit 2
