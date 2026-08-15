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
#                               Default: "chatgpt-codex-connector[bot]"
#                               Also overridable via CODEX_GITHUB_BOT_LOGIN env var.
#                               Verify the actual bot login from your GitHub App settings.
#   --poll-interval  <seconds>   Seconds between polling attempts. Default: 60
#   --max-wait       <seconds>   Maximum total wait time for bot response across
#                                all attempts. Default: 1800
#   --max-retriggers <count>     How many times to re-post the trigger after a timeout
#                                before giving up. Default: 1 (so up to 2 attempts total).
#                                Set to 0 to disable retriggering.
#
# Exit codes:
#   0 — APPROVED   (bot responded with no blocking findings)
#   1 — NEEDS_REVISION (bot responded with blocking findings)
#   2 — TIMED_OUT  (no bot response within max-wait; treat as unavailable under
#                   configured internal_reviewers_unavailable_policy)
#   3 — UNAVAILABLE (bot responded with review-capacity/quota exhaustion)
#
# Verdict parsing (three-path, blocking markers checked first per safe-fail):
#   1. Blocking markers present → NEEDS_REVISION (exit 1)
#      Markers (case-insensitive): "changes requested", "blocking issues:" (colon
#      required), "blocking finding", "blocking:", "must fix", "action required",
#      "required:", "❌"
#      Note: "blocking issues:" (with colon) disambiguates the list form from
#      "no blocking issues found"; bare "blocking" excluded (too broad).
#   2. Approval signals present → APPROVED (exit 0)
#      Signals (case-insensitive): "approved", "lgtm", "looks good",
#      "didn't find any major issues", or "no blocking issues" from a
#      submitted review pinned to the current head, or a root PR comment that
#      names the current head in a Reviewed commit marker. Other Codex root PR
#      comments and thumbs-up reactions are acknowledgements only; they are not
#      SHA-pinned review evidence and must not approve the PR by themselves.
#   3. Neither found (unrecognized format) → safe-fails to NEEDS_REVISION (exit 1)
#
# Response source detection (two sources polled each cycle):
#   - issues/{PR}/comments — plain PR comments; matches both BOT_LOGIN and
#     BOT_LOGIN_PLAIN (login without [bot] suffix). Codex posts "clean" results
#     here from the non-[bot] account (e.g. "chatgpt-codex-connector").
#   - pulls/{PR}/reviews   — GitHub Review objects; matches both logins. Codex
#     posts findings here from the [bot]-suffixed account. Only submitted
#     reviews whose commit_id starts with the current head SHA are considered.
#     The review body safe-fails to NEEDS_REVISION, which causes
#     pr-review-loop.sh to count unresolved inline threads.
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
BOT_LOGIN="${CODEX_GITHUB_BOT_LOGIN:-chatgpt-codex-connector[bot]}"
POLL_INTERVAL=60
MAX_WAIT=1800
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
if [ "$POLL_INTERVAL" -gt "$MAX_WAIT" ]; then
  POLL_INTERVAL="$MAX_WAIT"
fi
echo "INFO: Poll interval: ${POLL_INTERVAL}s, Max wait (total): ${MAX_WAIT}s"

# Derive plain bot login (without [bot] suffix) for matching PR-comment
# acknowledgements from the non-[bot] account (e.g. "chatgpt-codex-connector").
# Findings are posted as GitHub Reviews from the [bot]-suffixed account.
BOT_LOGIN_PLAIN="${BOT_LOGIN%\[bot\]}"
echo "INFO: Bot login (plain, for PR-comment matching): $BOT_LOGIN_PLAIN"

TRIGGER_COMMENT_ID=""

codex_trigger_approval_reaction_count() {
  local comment_id="$1"
  [ -z "$comment_id" ] && { printf '0\n'; return 0; }

  local reaction_tmpfile
  reaction_tmpfile=$(mktemp)
  if gh api "repos/$OWNER/$REPO/issues/comments/$comment_id/reactions" --paginate \
    | jq -sr --arg bot "$BOT_LOGIN" --arg bot_plain "$BOT_LOGIN_PLAIN" \
      '(add // []) | [.[] | select(.content == "+1" and (.user.login == $bot or .user.login == $bot_plain))] | length' \
    > "$reaction_tmpfile"; then
    cat "$reaction_tmpfile"
  else
    rm -f "$reaction_tmpfile"
    echo "ERROR: failed to fetch or parse Codex trigger reactions" >&2
    return 3
  fi
  rm -f "$reaction_tmpfile"
}

codex_inline_review_comment_count_since() {
  local trigger_time="$1"
  [ -z "$trigger_time" ] && { printf '0\n'; return 0; }

  local review_comment_tmpfile
  review_comment_tmpfile=$(mktemp)
  if gh api "repos/$OWNER/$REPO/pulls/$PR_NUMBER/comments" --paginate \
    | jq -sr --arg bot "$BOT_LOGIN" --arg bot_plain "$BOT_LOGIN_PLAIN" --arg trigger_time "$trigger_time" --arg sha "$CURRENT_SHA" \
      '(add // []) | [.[] | select((.user.login == $bot or .user.login == $bot_plain) and .created_at >= $trigger_time and ((.commit_id // "") | startswith($sha)))] | length' \
    > "$review_comment_tmpfile"; then
    cat "$review_comment_tmpfile"
  else
    rm -f "$review_comment_tmpfile"
    echo "ERROR: failed to fetch or parse Codex inline review comments" >&2
    return 3
  fi
  rm -f "$review_comment_tmpfile"
}

codex_response_is_usage_limit() {
  local response="$1"
  printf '%s\n' "$response" | grep -qiE "(reached[[:space:]]+your[[:space:]]+codex[[:space:]]+usage[[:space:]]+limits?|codex[[:space:]]+usage[[:space:]]+limits?[[:space:]]+for[[:space:]]+code[[:space:]]+reviews?|codex[[:space:]]+(github[[:space:]]+app[[:space:]]+)?(review[[:space:]]+)?(usage[[:space:]]+limit|quota|capacity)|codex[[:space:]]+review[[:space:]]+capacity[[:space:]]+(exhausted|unavailable|limited))"
}

codex_response_is_environment_error() {
  local response="$1"
  printf '%s\n' "$response" | grep -qiE "to[[:space:]]+use[[:space:]]+codex[[:space:]]+here,[[:space:]]+create[[:space:]]+an[[:space:]]+environment[[:space:]]+for[[:space:]]+this[[:space:]]+repo"
}

codex_response_reviews_current_head() {
  local response="$1"
  local reviewed_sha
  reviewed_sha=$(printf '%s\n' "$response" | sed -n 's/.*Reviewed commit:[^`]*`\([0-9a-fA-F]\{7,40\}\)`.*/\1/p' | tail -n 1)
  [ -n "$reviewed_sha" ] && { printf '%s\n' "$CURRENT_SHA" | grep -qi "^$reviewed_sha" || printf '%s\n' "$reviewed_sha" | grep -qi "^$CURRENT_SHA"; }
}

# Blocking/approval marker patterns, centralized so every classification site
# (main poll, async grace, async-final, async-reaction-final) uses the exact
# same rules. See "Verdict parsing" header comment for the rationale behind
# each marker.
CODEX_BLOCKING_PATTERN='(changes[[:space:]]+requested|blocking[[:space:]]+issues?[[:space:]]*:|blocking[[:space:]]+finding|blocking:|must[[:space:]]+fix|action[[:space:]]+required|required:|❌)'
CODEX_APPROVAL_PATTERN='(approved|lgtm|looks[[:space:]]+good|didn.t find[[:space:]]+any major[[:space:]]+issues|no[[:space:]]+blocking[[:space:]]+issues?)'

codex_response_is_blocking() {
  local body="$1"
  printf '%s\n' "$body" | grep -qiE "$CODEX_BLOCKING_PATTERN"
}

codex_response_is_approved() {
  local body="$1"
  printf '%s\n' "$body" | grep -qiE "$CODEX_APPROVAL_PATTERN"
}

# True when a response is NOT the clean-approval path — i.e. it is either
# explicitly blocking or an unrecognized format that the documented verdict
# classifier safe-fails to NEEDS_REVISION (see "Verdict parsing" header
# comment). Blocking is checked FIRST, matching the classifier's blocking-
# first priority: a response containing both an approval phrase and a
# blocking marker (e.g. "No blocking issues found. Must fix ...") is
# blocking, not approved. Used by the tie-break below so neither an
# unrecognized-format response nor a mixed blocking+approval response is
# silently outranked by a clean approval on a timestamp tie.
codex_response_requires_attention() {
  local body="$1"
  codex_response_is_blocking "$body" || ! codex_response_is_approved "$body"
}

# Decides whether CANDIDATE terminal ("review"-sourced) evidence should
# replace CURRENT terminal evidence. A strictly later candidate always wins.
# GitHub timestamps are second-resolution, so ties are possible; on an exact
# tie, evidence that is not a clean approval (blocking OR unrecognized
# format — anything the verdict classifier would not exit APPROVED for)
# must never be discarded in favor of an approved response, regardless of
# which side (submitted review vs SHA-pinned root comment) supplied it. This
# makes the tie-break symmetric: if the candidate requires attention and the
# current evidence is a clean approval, the candidate wins; if the current
# evidence requires attention and the candidate is a clean approval, the
# current evidence is kept.
codex_select_terminal_evidence() {
  local current_body="$1" current_time="$2"
  local candidate_body="$3" candidate_time="$4"
  [ -z "$current_time" ] && return 0
  if [ "$candidate_time" \> "$current_time" ]; then
    return 0
  fi
  if [ "$candidate_time" = "$current_time" ]; then
    if codex_response_requires_attention "$candidate_body" && ! codex_response_requires_attention "$current_body"; then
      return 0
    fi
  fi
  return 1
}

# Scans a JSON-lines file (one compact object per line, in ascending
# created_at/id order — as produced by the comment-poll jq queries below) of
# bot-authored root PR comments and separates SHA-pinned TERMINAL evidence
# (a "Reviewed commit" marker naming the current head) from the latest
# comment overall (ancillary: acknowledgement, environment-setup error, or
# other non-terminal text). Selecting the terminal comment independently from
# the latest comment prevents a later ancillary comment (e.g. a thumbs-up
# acknowledgement or a "waiting" note) from silently discarding an earlier
# SHA-pinned blocking root comment.
#
# An environment-setup-error comment is treated as the priority ancillary
# signal once seen: a later PLAIN comment (e.g. an acknowledgement) does not
# overwrite it, so an actionable setup failure is not silently lost to a
# no-information comment that happens to arrive later in the same fetch
# (fresh evidence from PR #1490 finding 3787786945). A LATER environment-
# error comment still updates it, keeping the most recent one. A SHA-pinned
# TERMINAL comment is never classified as an environment error even if its
# text happens to quote the setup sentence (e.g. a blocking finding about
# stale documentation that reproduces it verbatim) — terminal evidence is
# always genuine review content, not a bare setup-failure message (fresh
# evidence from PR #1490 finding 3787943163).
#
# Sets: COMMENT_TERMINAL_BODY, COMMENT_TERMINAL_TIME, COMMENT_LATEST_BODY,
# COMMENT_LATEST_TIME.
codex_scan_comment_evidence() {
  local comments_file="$1"
  COMMENT_TERMINAL_BODY=""
  COMMENT_TERMINAL_TIME=""
  COMMENT_LATEST_BODY=""
  COMMENT_LATEST_TIME=""
  local comment_latest_is_env_error=0
  local line created_at body is_env_error is_terminal
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    created_at=$(printf '%s' "$line" | jq -r '.created_at // empty')  # workflow-shell-guard: allow SH003 - $line is a compact JSON object already validated parseable by the preceding jq -sc call; empty is a normal absent-field case, not a failure
    body=$(printf '%s' "$line" | jq -r '.body // empty')  # workflow-shell-guard: allow SH003 - same pre-validated $line as above; empty body is not a failure
    is_terminal=0
    codex_response_reviews_current_head "$body" && is_terminal=1
    is_env_error=0
    if [ "$is_terminal" -eq 0 ]; then
      codex_response_is_environment_error "$body" && is_env_error=1
    fi
    if [ "$comment_latest_is_env_error" -eq 0 ] || [ "$is_env_error" -eq 1 ]; then
      COMMENT_LATEST_BODY="$body"
      COMMENT_LATEST_TIME="$created_at"
      comment_latest_is_env_error="$is_env_error"
    fi
    if [ "$is_terminal" -eq 1 ]; then
      COMMENT_TERMINAL_BODY="$body"
      COMMENT_TERMINAL_TIME="$created_at"
    fi
  done < "$comments_file"
}

# Combines comment-sourced evidence (terminal SHA-pinned root comment vs.
# latest ancillary comment, from codex_scan_comment_evidence) with
# review-sourced evidence (from the pulls/{PR}/reviews endpoint) into a
# single winning result. A SHA-pinned terminal comment and a genuine
# submitted review apply the not-a-clean-approval-first tie-break
# (codex_select_terminal_evidence): the strictly newer one wins, or on a
# tie the one that is not a clean approval wins.
#
# An ancillary comment that is specifically a recorded environment-setup
# error is treated as actionable evidence in its own right, not noise, and
# is checked independently of whichever of (terminal comment, review) won
# above — a SHA-pinned terminal comment or a review must not silently
# discard a same-or-newer environment-setup error just because it competed
# with a different evidence type (fresh evidence from PR #1490 finding
# 3787868727: the terminal-comment branch previously never considered the
# environment error at all). Only strictly newer terminal/review evidence
# supersedes it — EXCEPT when that terminal/review evidence is itself
# blocking: a blocking finding always wins outright and is never discarded
# by an environment-setup error regardless of timing, so an actionable
# finding can never be hidden behind an "unavailable" verdict (fresh
# evidence from PR #1490 finding 3787943162). A bare non-error ancillary
# comment (acknowledgement, "waiting" note) carries no information and
# never competes with anything.
#
# Sets: COMBINED_BODY, COMBINED_TIME, COMBINED_SOURCE ("review", "comment",
# or "" if no evidence at all). LABEL is used only for INFO logging.
codex_combine_terminal_evidence() {
  local label="$1"
  local comment_terminal_body="$2" comment_terminal_time="$3"
  local comment_latest_body="$4" comment_latest_time="$5"
  local review_body="$6" review_time="$7"

  COMBINED_BODY=""
  COMBINED_TIME=""
  COMBINED_SOURCE=""

  if [ -n "$comment_terminal_body" ]; then
    COMBINED_BODY="$comment_terminal_body"
    COMBINED_TIME="$comment_terminal_time"
    COMBINED_SOURCE="review"
    echo "INFO: $label detected via SHA-pinned PR comment"
  fi

  if [ -n "$review_body" ]; then
    if [ "$COMBINED_SOURCE" = "review" ]; then
      if codex_select_terminal_evidence "$COMBINED_BODY" "$COMBINED_TIME" "$review_body" "$review_time"; then
        COMBINED_BODY="$review_body"
        COMBINED_TIME="$review_time"
        COMBINED_SOURCE="review"
        echo "INFO: $label detected via PR reviews endpoint (supersedes SHA-pinned comment)"
      fi
    else
      COMBINED_BODY="$review_body"
      COMBINED_TIME="$review_time"
      COMBINED_SOURCE="review"
      echo "INFO: $label detected via PR reviews endpoint"
    fi
  fi

  if [ -z "$COMBINED_SOURCE" ] && [ -n "$comment_latest_body" ]; then
    # Neither a SHA-pinned terminal comment nor a review produced any
    # evidence: fall back to the latest bare ancillary comment (may be an
    # environment-setup error, an acknowledgement, or other non-terminal
    # text) so the outer verdict classifier still has something to inspect.
    COMBINED_BODY="$comment_latest_body"
    COMBINED_TIME="$comment_latest_time"
    COMBINED_SOURCE="comment"
  fi

  if [ -n "$comment_latest_body" ] && codex_response_is_environment_error "$comment_latest_body"; then
    if [ -n "$COMBINED_SOURCE" ] && codex_response_is_blocking "$COMBINED_BODY"; then
      # Blocking terminal/review evidence always wins outright — it is
      # never discarded by an environment-setup error, regardless of
      # timing, so an actionable finding can never be hidden behind an
      # "unavailable" verdict (fresh evidence from PR #1490 finding
      # 3787943162; Protocol 93 requires blocking evidence to never be
      # silently discarded).
      :
    elif [ -z "$COMBINED_TIME" ] || ! codex_select_terminal_evidence "$comment_latest_body" "$comment_latest_time" "$COMBINED_BODY" "$COMBINED_TIME"; then
      COMBINED_BODY="$comment_latest_body"
      COMBINED_TIME="$comment_latest_time"
      COMBINED_SOURCE="comment"
      echo "INFO: $label environment-setup error retained over non-newer terminal/review evidence"
    fi
  fi
}

codex_return_usage_limit() {
  echo "VERDICT: UNAVAILABLE — Codex GitHub review usage limit reached"
  echo "REASON=codex-github-usage-limit"
  echo "COMMENT_COUNT=0"
  echo "BLOCKING_COUNT=0"
  echo "SUGGESTION_COUNT=0"
  echo "---BEGIN BOT RESPONSE---"
  echo "$1"
  echo "---END BOT RESPONSE---"
  exit 3
}

codex_return_environment_error() {
  echo "VERDICT: TIMED_OUT — Codex GitHub review environment missing (treated as unavailable)"
  echo "REASON=codex-github-environment-missing"
  echo "COMMENT_COUNT=0"
  echo "BLOCKING_COUNT=0"
  echo "SUGGESTION_COUNT=0"
  echo "---BEGIN BOT RESPONSE---"
  echo "$1"
  echo "---END BOT RESPONSE---"
  exit 2
}

codex_return_reaction_without_review() {
  echo "VERDICT: TIMED_OUT — Codex thumbs-up reaction is not SHA-pinned review evidence (treated as unavailable)"
  echo "REASON=codex-github-reaction-without-review"
  echo "COMMENT_COUNT=0"
  echo "BLOCKING_COUNT=0"
  echo "SUGGESTION_COUNT=0"
  exit 2
}

codex_return_head_changed() {
  echo "VERDICT: TIMED_OUT — PR head changed while waiting for Codex review evidence (treated as unavailable)"
  echo "REASON=codex-github-head-changed"
  echo "COMMENT_COUNT=0"
  echo "BLOCKING_COUNT=0"
  echo "SUGGESTION_COUNT=0"
  exit 2
}

codex_require_current_head() {
  local latest_sha
  if ! latest_sha=$(gh pr view "$PR_NUMBER" --repo "$OWNER/$REPO" --json headRefOid --jq '.headRefOid' | head -c 100); then
    echo "ERROR: could not revalidate PR #$PR_NUMBER HEAD SHA" >&2
    echo "VERDICT: TIMED_OUT — could not revalidate PR HEAD SHA (treated as unavailable)"
    echo "REASON=codex-github-head-unavailable"
    exit 2
  fi
  latest_sha=$(printf '%s' "$latest_sha" | cut -c1-12)
  if [ -z "$latest_sha" ]; then
    echo "ERROR: could not revalidate PR #$PR_NUMBER HEAD SHA (empty result)" >&2
    echo "VERDICT: TIMED_OUT — could not revalidate PR HEAD SHA (treated as unavailable)"
    echo "REASON=codex-github-head-unavailable"
    exit 2
  fi
  if [ "$latest_sha" != "$CURRENT_SHA" ]; then
    echo "INFO: PR head changed during Codex polling (started at $CURRENT_SHA, now $latest_sha)"
    codex_return_head_changed
  fi
}

# ── Idempotency guard (BR-10) ─────────────────────────────────────────────────
# Check whether a trigger comment for the current commit SHA already exists.
# We look for a comment body containing BOTH the trigger phrase AND the SHA to
# avoid falsely matching bot review comments or human comments that happen to
# reference the commit SHA.

# Capture the idempotency check to a temp file to avoid SIGPIPE under pipefail.
# Use 'jq --arg' for safe variable binding — avoids jq injection if the trigger
# phrase or SHA contain jq-special characters (double quote, backslash).
# Use contains() not test() for SHA matching: contains() is a literal substring
# check, while test() interprets its argument as a regex (unanchored substring).
# Note: `]` must appear first in the bracket expression to be treated as literal.
IDEM_STDERR=$(mktemp)
IDEM_TMPFILE=$(mktemp)
if gh api "repos/$OWNER/$REPO/issues/$PR_NUMBER/comments" --paginate \
  2>"$IDEM_STDERR" \
  | jq -sc --arg sha "$CURRENT_SHA" --arg marker "review triggered by workflow runner" --arg bot "$BOT_LOGIN" --arg bot_plain "$BOT_LOGIN_PLAIN" \
    '[.[][] | select(.user.login != $bot and .user.login != $bot_plain) | select((.body | contains($sha)) and (.body | ascii_downcase | contains($marker)))] | sort_by(.created_at) | reverse | .[0] // empty | {id: .id, created_at: .created_at, body: .body}' \
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
  if ! TRIGGER_COMMENT_ID=$(printf '%s\n' "$TRIGGER_COMMENT_INFO" | jq -re '.id | tostring'); then
    echo "ERROR: existing trigger comment payload missing id" >&2
    echo "VERDICT: TIMED_OUT — malformed trigger comment payload (treated as unavailable)"
    exit 2
  fi
  if ! TRIGGER_TIME=$(printf '%s\n' "$TRIGGER_COMMENT_INFO" | jq -re '.created_at'); then
    echo "ERROR: existing trigger comment payload missing created_at" >&2
    echo "VERDICT: TIMED_OUT — malformed trigger comment payload (treated as unavailable)"
    exit 2
  fi
  if [ -n "$TRIGGER_TIME" ]; then
    echo "INFO: trigger comment already posted for commit $CURRENT_SHA (at $TRIGGER_TIME) — skipping duplicate post"
  fi
fi

# ── Post trigger comment (if no duplicate found) ──────────────────────────────

if [ -z "$TRIGGER_TIME" ]; then
  echo "INFO: posting trigger comment to PR #$PR_NUMBER..."
  # Use gh api --method POST to capture the GitHub-server-assigned created_at
  # timestamp. Using 'date -u' here would risk clock skew between the local
  # machine and GitHub's API server. SHA-pinned review filters use >= because
  # GitHub timestamps are second-resolution and bot responses can share the
  # trigger second.
  # Guard with 'if !' to emit TIMED_OUT (exit 2) on failure instead of letting
  # set -e exit with code 1 (NEEDS_REVISION) without a VERDICT line.
  if ! TRIGGER_RESPONSE=$(gh api "repos/$OWNER/$REPO/issues/$PR_NUMBER/comments" \
    --method POST \
    --raw-field body="$TRIGGER_PHRASE (review triggered by workflow runner, commit: $CURRENT_SHA)"); then
    echo "ERROR: failed to post trigger comment to PR #$PR_NUMBER" >&2
    echo "VERDICT: TIMED_OUT — failed to post trigger comment (treated as unavailable)"
    exit 2
  fi
  if ! TRIGGER_TIME=$(printf '%s\n' "$TRIGGER_RESPONSE" | jq -re '.created_at'); then
    echo "ERROR: trigger comment response missing created_at" >&2
    echo "VERDICT: TIMED_OUT — malformed trigger comment response (treated as unavailable)"
    exit 2
  fi
  if ! TRIGGER_COMMENT_ID=$(printf '%s\n' "$TRIGGER_RESPONSE" | jq -re '.id | tostring'); then
    echo "ERROR: trigger comment response missing id or created_at" >&2
    echo "VERDICT: TIMED_OUT — malformed trigger comment response (treated as unavailable)"
    exit 2
  fi
  echo "INFO: trigger comment posted at $TRIGGER_TIME (server-assigned timestamp)"
fi

# ── Poll for bot response (with retrigger support) ───────────────────────────
#
# Outer loop: we keep polling until the shared MAX_WAIT budget is exhausted.
# If the bot does not respond during an attempt, we re-post the trigger comment
# (up to MAX_RETRIGGERS times) and continue polling with the remaining budget.
# This handles the
# case where Codex silently drops the first @codex review request — in practice
# a re-post usually gets a response. After all attempts are exhausted, we exit
# with TIMED_OUT (treated as unavailable by the caller).

echo "INFO: polling for response from '$BOT_LOGIN' (trigger time: $TRIGGER_TIME)..."
echo "INFO: MAX_WAIT=${MAX_WAIT}s total; up to $((MAX_RETRIGGERS + 1)) attempt(s) (MAX_RETRIGGERS=$MAX_RETRIGGERS)"

RETRIGGER_COUNT=0
CONSECUTIVE_API_FAILURES=0
MAX_CONSECUTIVE_FAILURES=3
SEEN_ENVIRONMENT_ERROR=0
SEEN_ENVIRONMENT_RESPONSE=""
# Timestamp the environment-error evidence was observed at (the same
# COMBINED_TIME the response was classified from). Compared against fresh
# terminal evidence's own timestamp at each APPROVED exit site so a
# strictly newer clean review (e.g. after an operator fixes the Codex cloud
# environment mid-poll) can supersede a now-stale recorded failure, while a
# same-or-older approval still cannot silently override it — the same
# newest-wins-with-ties-favoring-non-clean rule applied to every other
# evidence type in this script.
SEEN_ENVIRONMENT_TIME=""
SEEN_APPROVAL_REACTION=0
# Outer retrigger loop. TOTAL_ELAPSED tracks the full shared wait budget.
# TRIGGER_TIME is updated to the retrigger comment's timestamp after each
# retrigger post, scoping the next inner poll to responses after that point.
TOTAL_ELAPSED=0
while true; do
  while [ "$TOTAL_ELAPSED" -lt "$MAX_WAIT" ]; do
  sleep "$POLL_INTERVAL"
  TOTAL_ELAPSED=$((TOTAL_ELAPSED + POLL_INTERVAL))

  echo "INFO: polling... elapsed ${TOTAL_ELAPSED}s / ${MAX_WAIT}s"

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
  BOT_RESPONSE=""
  BOT_RESPONSE_SOURCE=""
  if gh api "repos/$OWNER/$REPO/issues/$PR_NUMBER/comments" --paginate \
    2>"$POLL_STDERR" \
    | jq -sc --arg bot "$BOT_LOGIN" --arg bot_plain "$BOT_LOGIN_PLAIN" --arg trigger_time "$TRIGGER_TIME" --arg trigger_comment_id "$TRIGGER_COMMENT_ID" \
        '(add // []) | [.[] | select(.user.login == $bot or .user.login == $bot_plain) | select(.created_at > $trigger_time or (.created_at == $trigger_time and ((.id // 0 | tostring | tonumber) > ($trigger_comment_id | tonumber))))] | sort_by(.created_at, .id) | .[] | {created_at:(.created_at // ""), body:(.body // "")}' \
    > "$POLL_TMPFILE"; then
    # Scan ALL matching root comments (not just the latest) so a SHA-pinned
    # terminal comment (Reviewed commit marker) is not discarded in favor of
    # a later ancillary comment (e.g. an acknowledgement).
    codex_scan_comment_evidence "$POLL_TMPFILE"
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
  REVIEW_STDERR=$(mktemp)
  REVIEW_TMPFILE=$(mktemp)
  if gh api "repos/$OWNER/$REPO/pulls/$PR_NUMBER/reviews" --paginate \
    2>"$REVIEW_STDERR" \
    | jq -sr --arg bot "$BOT_LOGIN" --arg bot_plain "$BOT_LOGIN_PLAIN" --arg trigger_time "$TRIGGER_TIME" --arg sha "$CURRENT_SHA" \
        '(add // []) | [.[] | select((.user.login == $bot or .user.login == $bot_plain) and .submitted_at != null and .submitted_at >= $trigger_time and ((.commit_id // "") | startswith($sha)))] | sort_by(.submitted_at) | last | {created_at:(.submitted_at // ""), body:(.body // "")}' \
    > "$REVIEW_TMPFILE" 2>"$REVIEW_STDERR"; then
    # Truncation happens inside jq (codepoint slice), not via a piped `head`,
    # so a long body cannot trigger SIGPIPE on jq under `set -o pipefail`
    # (an external `| head -c N` pipe closes early on long output, and the
    # writer's resulting SIGPIPE would otherwise abort the whole script
    # before any VERDICT line is emitted).
    REVIEW_BODY=$(jq -r '(.body // empty) | .[0:5000]' "$REVIEW_TMPFILE")  # workflow-shell-guard: allow SH003 - reads a tmpfile already validated as parseable JSON by the preceding gh|jq call; empty body means no evidence yet, not a failure, and is checked downstream via [ -n ]
    REVIEW_TIME=$(jq -r '.created_at // empty' "$REVIEW_TMPFILE")  # workflow-shell-guard: allow SH003 - reads the same pre-validated tmpfile as the body extraction above; empty time is not a failure
  else
    REVIEW_ERR=$(cat "$REVIEW_STDERR")
    rm -f "$REVIEW_STDERR" "$REVIEW_TMPFILE"
    echo "WARNING: failed to fetch or parse Codex PR reviews: $REVIEW_ERR" >&2
    echo "VERDICT: TIMED_OUT — failed to fetch Codex PR reviews (treated as unavailable)"
    exit 2
  fi
  rm -f "$REVIEW_STDERR" "$REVIEW_TMPFILE"

  codex_combine_terminal_evidence "bot response" \
    "$COMMENT_TERMINAL_BODY" "$COMMENT_TERMINAL_TIME" \
    "$COMMENT_LATEST_BODY" "$COMMENT_LATEST_TIME" \
    "$REVIEW_BODY" "$REVIEW_TIME"
  BOT_RESPONSE="$COMBINED_BODY"
  BOT_RESPONSE_SOURCE="$COMBINED_SOURCE"
  # Truncate here (post-combine) — mirrors the prior per-source truncation but
  # applies uniformly regardless of which source won. Root-comment-sourced
  # bodies are not truncated at scan time (unlike review bodies, which are
  # already sliced to 5000 chars inside jq), so a body near GitHub's
  # per-comment size limit could still exceed a pipe buffer here. `jq -Rs`
  # slurps its entire stdin before producing any output, so the writer
  # (printf) is always fully drained and can never receive SIGPIPE, unlike
  # a piped `head -c N` which can close early on long input (fresh evidence
  # from PR #1490 finding 3787868733).
  BOT_RESPONSE=$(printf '%s' "$BOT_RESPONSE" | jq -Rrs '.[0:10000]')  # workflow-shell-guard: allow SH003 - jq -R treats input as raw text (not JSON), so it cannot fail on malformed content; a genuine jq internal failure still trips `set -e` since this is a bare assignment, which is the desired fail-closed behavior

  if ! INLINE_REVIEW_COMMENT_COUNT=$(codex_inline_review_comment_count_since "$TRIGGER_TIME"); then
    echo "VERDICT: TIMED_OUT — failed to fetch Codex inline review comments (treated as unavailable)"
    exit 2
  fi
  if [ "$INLINE_REVIEW_COMMENT_COUNT" -gt 0 ]; then
    codex_require_current_head
    echo "VERDICT: NEEDS_REVISION"
    echo "INFO: detected $INLINE_REVIEW_COMMENT_COUNT Codex inline review comment(s) after trigger"
    exit 1
  fi

  if ! APPROVAL_REACTION_COUNT=$(codex_trigger_approval_reaction_count "$TRIGGER_COMMENT_ID"); then
    echo "VERDICT: TIMED_OUT — failed to fetch Codex trigger reactions (treated as unavailable)"
    exit 2
  fi
  if [ -n "$BOT_RESPONSE" ]; then
    echo "INFO: bot response detected"
    codex_require_current_head

    # ── Verdict parsing ───────────────────────────────────────────────────────
    # Three-path classification (per spec BR-4 and implementation plan risk table).
    # Blocking markers are checked FIRST (safe-fail: a false NEEDS_REVISION that
    # triggers an unnecessary fix cycle is safer than a false APPROVED that
    # silently ignores blocking findings). The bare word "blocking" is excluded
    # because it is too broad; the phrases below are more targeted.
    #
    # 1. Blocking markers present → NEEDS_REVISION (exit 1)      [checked first]
    #    Blocking markers (case-insensitive): "changes requested",
    #    "blocking issues:" (colon required to distinguish from "no blocking issues
    #    found"), "blocking finding", "blocking:", "must fix", "action required",
    #    "required:", "❌"
    #
    # 2. Explicit approval signals present → APPROVED (exit 0)   [checked second]
    #    Approval signals: "approved", "lgtm", "looks good",
    #    "didn't find any major issues", or "no blocking issues" from a
    #    submitted review pinned to the current head, or a root PR comment that
    #    names the current head in a Reviewed commit marker. Other Codex root PR
    #    comments and thumbs-up reactions are unavailable, not clean.
    #
    # 3. Neither found (unrecognized response format) → NEEDS_REVISION (exit 1)
    #    Safe-fail: default to NEEDS_REVISION when the format is unrecognized to
    #    avoid incorrectly approving a response that is a rejection in an
    #    unexpected format (per spec risk mitigation for BR-4).
    #
    # Note on "blocking issues" disambiguation: the phrase "blocking issues" appears
    # in both blocking context ("blocking issues: 1. foo") and clean context ("no
    # blocking issues found"). Requiring a colon after "issues" targets the blocking
    # list form while leaving the clean form to match the APPROVED branch via
    # "no blocking issues". This avoids false positives without line-level filtering
    # (which would risk missing a genuine marker on the same line as a negation).

    if codex_response_is_usage_limit "$BOT_RESPONSE"; then
      codex_return_usage_limit "$BOT_RESPONSE"
    elif [ "$BOT_RESPONSE_SOURCE" = "comment" ] && codex_response_is_environment_error "$BOT_RESPONSE"; then
      SEEN_ENVIRONMENT_ERROR=1
      SEEN_ENVIRONMENT_RESPONSE="$BOT_RESPONSE"
      SEEN_ENVIRONMENT_TIME="$COMBINED_TIME"
      echo "INFO: Codex environment setup response detected; waiting for fresh current-head review evidence"
      continue
    elif [ "$BOT_RESPONSE_SOURCE" = "review" ] && codex_response_is_blocking "$BOT_RESPONSE"; then
      echo "VERDICT: NEEDS_REVISION"
      echo "---BEGIN BOT RESPONSE---"
      echo "$BOT_RESPONSE"
      echo "---END BOT RESPONSE---"
      exit 1
    elif [ "$BOT_RESPONSE_SOURCE" = "review" ] && codex_response_is_approved "$BOT_RESPONSE"; then
      if [ "$SEEN_ENVIRONMENT_ERROR" -eq 1 ] && ! [ "$COMBINED_TIME" \> "$SEEN_ENVIRONMENT_TIME" ]; then
        codex_return_environment_error "$SEEN_ENVIRONMENT_RESPONSE"
      fi
      echo "VERDICT: APPROVED"
      echo "---BEGIN BOT RESPONSE---"
      echo "$BOT_RESPONSE"
      echo "---END BOT RESPONSE---"
      exit 0
    elif echo "$BOT_RESPONSE" | grep -qi "If Codex has suggestions, it will comment; otherwise it will react with"; then
      echo "INFO: Codex acknowledgement detected; waiting for current-head review or inline review comments"
      continue
    elif [ "$BOT_RESPONSE_SOURCE" = "comment" ]; then
      echo "INFO: Codex root comment is not SHA-pinned terminal evidence; waiting for current-head review or inline comments"
      continue
    else
      echo "VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)"
      echo "---BEGIN BOT RESPONSE---"
      echo "$BOT_RESPONSE"
      echo "---END BOT RESPONSE---"
      exit 1
    fi
  fi

  if [ "$APPROVAL_REACTION_COUNT" -gt 0 ]; then
    echo "INFO: detected Codex thumbs-up reaction on trigger comment $TRIGGER_COMMENT_ID"
    echo "INFO: waiting for current-head review evidence before treating reaction as terminal"
    SEEN_APPROVAL_REACTION=1
    continue
  fi
  done  # end inner poll loop

  # Inner poll loop ended without a bot response — try to re-trigger if budget remains.
  if [ "$TOTAL_ELAPSED" -lt "$MAX_WAIT" ] && [ "$RETRIGGER_COUNT" -lt "$MAX_RETRIGGERS" ]; then
    RETRIGGER_COUNT=$((RETRIGGER_COUNT + 1))
    ATTEMPT_NUM=$((RETRIGGER_COUNT + 1))
    TOTAL_ATTEMPTS=$((MAX_RETRIGGERS + 1))
    echo "INFO: no response yet; re-triggering (attempt ${ATTEMPT_NUM}/${TOTAL_ATTEMPTS}, total elapsed ${TOTAL_ELAPSED}s/${MAX_WAIT}s)..."
    # --raw-field passes the body string as-is to the GitHub API without shell
    # re-interpretation, so special characters in TRIGGER_PHRASE are safe.
    if ! TRIGGER_RESPONSE=$(gh api "repos/$OWNER/$REPO/issues/$PR_NUMBER/comments" \
      --method POST \
      --raw-field body="$TRIGGER_PHRASE — retrigger ${RETRIGGER_COUNT}/${MAX_RETRIGGERS} after timeout (sha: $CURRENT_SHA)"); then
      echo "ERROR: failed to post retrigger comment to PR #$PR_NUMBER" >&2
      echo "VERDICT: TIMED_OUT — failed to post retrigger comment (treated as unavailable)"
      exit 2
    fi
    if ! TRIGGER_TIME=$(printf '%s\n' "$TRIGGER_RESPONSE" | jq -re '.created_at'); then
      echo "ERROR: retrigger comment response missing created_at" >&2
      echo "VERDICT: TIMED_OUT — malformed retrigger comment response (treated as unavailable)"
      exit 2
    fi
    if ! TRIGGER_COMMENT_ID=$(printf '%s\n' "$TRIGGER_RESPONSE" | jq -re '.id | tostring'); then
      echo "ERROR: retrigger comment response missing id or created_at" >&2
      echo "VERDICT: TIMED_OUT — malformed retrigger comment response (treated as unavailable)"
      exit 2
    fi
    echo "INFO: retrigger comment posted at $TRIGGER_TIME (TRIGGER_TIME updated)"
    continue
  else
    break
  fi
done  # end outer retrigger loop

# ── Async grace period ────────────────────────────────────────────────────────
# The Codex bot regularly posts its review asynchronously — AFTER the main poll
# window has already closed. Before declaring TIMED_OUT, post a single final
# async-arrival trigger and wait one extra POLL_INTERVAL to catch responses that
# arrived (or are about to arrive) just after the polling budget was exhausted.
# This is a lightweight one-shot check: it does not extend the full MAX_WAIT
# budget and does not add another iteration of the outer retrigger loop.

echo "INFO: poll budget exhausted; waiting ${POLL_INTERVAL}s for late async response..."

ASYNC_TRIGGER_COMMENT_ID=""
if [ "$MAX_RETRIGGERS" -gt 0 ]; then
  echo "INFO: posting async-arrival trigger comment..."
  if ! TRIGGER_RESPONSE=$(gh api "repos/$OWNER/$REPO/issues/$PR_NUMBER/comments" \
    --method POST \
    --raw-field body="$TRIGGER_PHRASE — async-arrival check after poll-window expiry (sha: $CURRENT_SHA)"); then
    echo "WARNING: failed to post async-arrival trigger comment; continuing with grace poll from existing trigger time" >&2
  else
    if ! ASYNC_TRIGGER_TIME=$(printf '%s\n' "$TRIGGER_RESPONSE" | jq -re '.created_at'); then
      echo "VERDICT: TIMED_OUT — malformed async trigger comment response (treated as unavailable)"
      exit 2
    fi
    if ! ASYNC_TRIGGER_COMMENT_ID=$(printf '%s\n' "$TRIGGER_RESPONSE" | jq -re '.id | tostring'); then
      echo "VERDICT: TIMED_OUT — malformed async trigger comment response (treated as unavailable)"
      exit 2
    fi
    echo "INFO: async-arrival trigger comment posted at $ASYNC_TRIGGER_TIME"
  fi
else
  echo "INFO: MAX_RETRIGGERS=0 — skipping async-arrival trigger comment; grace poll will use existing trigger time"
fi

echo "INFO: sleeping ${POLL_INTERVAL}s before async grace poll..."
sleep "$POLL_INTERVAL"

# Single grace poll: check both PR comments and PR reviews
ASYNC_BOT_RESPONSE=""
ASYNC_BOT_RESPONSE_SOURCE=""

if ! ASYNC_INLINE_REVIEW_COMMENT_COUNT=$(codex_inline_review_comment_count_since "$TRIGGER_TIME"); then
  echo "VERDICT: TIMED_OUT — failed to fetch Codex inline review comments during async grace period (treated as unavailable)"
  exit 2
fi
if [ "$ASYNC_INLINE_REVIEW_COMMENT_COUNT" -gt 0 ]; then
  codex_require_current_head
  echo "VERDICT: NEEDS_REVISION"
  echo "INFO: detected $ASYNC_INLINE_REVIEW_COMMENT_COUNT Codex inline review comment(s) during async grace period"
  exit 1
fi

if ! ASYNC_APPROVAL_REACTION_COUNT=$(codex_trigger_approval_reaction_count "$TRIGGER_COMMENT_ID"); then
  echo "VERDICT: TIMED_OUT — failed to fetch Codex trigger reactions during async grace period (treated as unavailable)"
  exit 2
fi
if [ -n "$ASYNC_TRIGGER_COMMENT_ID" ]; then
  if ! ASYNC_EXTRA_APPROVAL_REACTION_COUNT=$(codex_trigger_approval_reaction_count "$ASYNC_TRIGGER_COMMENT_ID"); then
    echo "VERDICT: TIMED_OUT — failed to fetch Codex async trigger reactions during async grace period (treated as unavailable)"
    exit 2
  fi
  ASYNC_APPROVAL_REACTION_COUNT=$((ASYNC_APPROVAL_REACTION_COUNT + ASYNC_EXTRA_APPROVAL_REACTION_COUNT))
fi
ASYNC_POLL_TMPFILE=$(mktemp)
if gh api "repos/$OWNER/$REPO/issues/$PR_NUMBER/comments" --paginate \
  2>/dev/null \
  | jq -sc --arg bot "$BOT_LOGIN" --arg bot_plain "$BOT_LOGIN_PLAIN" --arg trigger_time "$TRIGGER_TIME" --arg trigger_comment_id "$TRIGGER_COMMENT_ID" \
      '(add // []) | [.[] | select(.user.login == $bot or .user.login == $bot_plain) | select(.created_at > $trigger_time or (.created_at == $trigger_time and ((.id // 0 | tostring | tonumber) > ($trigger_comment_id | tonumber))))] | sort_by(.created_at, .id) | .[] | {created_at:(.created_at // ""), body:(.body // "")}' \
  > "$ASYNC_POLL_TMPFILE" 2>/dev/null; then
  codex_scan_comment_evidence "$ASYNC_POLL_TMPFILE"
  rm -f "$ASYNC_POLL_TMPFILE"
else
  rm -f "$ASYNC_POLL_TMPFILE"
  # Root comments are a terminal evidence source: a failed fetch here must be
  # treated as unavailable BEFORE any clean review evidence from the reviews
  # endpoint is accepted below (Finding #3 — fail closed, not fail open).
  echo "VERDICT: TIMED_OUT — failed to fetch Codex root comments during async grace period (treated as unavailable)"
  exit 2
fi

ASYNC_REVIEW_TMPFILE=$(mktemp)
if gh api "repos/$OWNER/$REPO/pulls/$PR_NUMBER/reviews" --paginate \
  2>/dev/null \
  | jq -sr --arg bot "$BOT_LOGIN" --arg bot_plain "$BOT_LOGIN_PLAIN" --arg trigger_time "$TRIGGER_TIME" --arg sha "$CURRENT_SHA" \
      '(add // []) | [.[] | select((.user.login == $bot or .user.login == $bot_plain) and .submitted_at != null and .submitted_at >= $trigger_time and ((.commit_id // "") | startswith($sha)))] | sort_by(.submitted_at) | last | {created_at:(.submitted_at // ""), body:(.body // "")}' \
  > "$ASYNC_REVIEW_TMPFILE" 2>/dev/null; then
  # Truncation happens inside jq (codepoint slice) to avoid SIGPIPE on jq
  # under `set -o pipefail` (see rationale above the main-loop equivalent).
  ASYNC_REVIEW_BODY=$(jq -r '(.body // empty) | .[0:5000]' "$ASYNC_REVIEW_TMPFILE")  # workflow-shell-guard: allow SH003 - reads a tmpfile already validated as parseable JSON by the preceding gh|jq call; empty body means no evidence yet, not a failure, and is checked downstream via [ -n ]
  ASYNC_REVIEW_TIME=$(jq -r '.created_at // empty' "$ASYNC_REVIEW_TMPFILE")  # workflow-shell-guard: allow SH003 - reads the same pre-validated tmpfile as the body extraction above; empty time is not a failure
else
  rm -f "$ASYNC_REVIEW_TMPFILE"
  echo "VERDICT: TIMED_OUT — failed to fetch Codex PR reviews during async grace period (treated as unavailable)"
  exit 2
fi
rm -f "$ASYNC_REVIEW_TMPFILE"

codex_combine_terminal_evidence "async-arrival bot response" \
  "$COMMENT_TERMINAL_BODY" "$COMMENT_TERMINAL_TIME" \
  "$COMMENT_LATEST_BODY" "$COMMENT_LATEST_TIME" \
  "$ASYNC_REVIEW_BODY" "$ASYNC_REVIEW_TIME"
ASYNC_BOT_RESPONSE="$COMBINED_BODY"
ASYNC_BOT_RESPONSE_SOURCE="$COMBINED_SOURCE"
# `jq -Rs` slurps its entire stdin before producing output, avoiding
# SIGPIPE on long root-comment-sourced bodies (see rationale above the
# main-loop equivalent).
ASYNC_BOT_RESPONSE=$(printf '%s' "$ASYNC_BOT_RESPONSE" | jq -Rrs '.[0:10000]')  # workflow-shell-guard: allow SH003 - jq -R treats input as raw text (not JSON), so it cannot fail on malformed content; a genuine jq internal failure still trips `set -e` since this is a bare assignment, which is the desired fail-closed behavior

if [ -n "$ASYNC_BOT_RESPONSE" ]; then
  echo "INFO: async-arrival bot response detected during grace period"
  codex_require_current_head

  # Apply the same three-path verdict parsing as the main poll loop.
  if codex_response_is_usage_limit "$ASYNC_BOT_RESPONSE"; then
    codex_return_usage_limit "$ASYNC_BOT_RESPONSE"
  elif [ "$ASYNC_BOT_RESPONSE_SOURCE" = "comment" ] && codex_response_is_environment_error "$ASYNC_BOT_RESPONSE"; then
    SEEN_ENVIRONMENT_ERROR=1
    SEEN_ENVIRONMENT_RESPONSE="$ASYNC_BOT_RESPONSE"
    SEEN_ENVIRONMENT_TIME="$COMBINED_TIME"
    echo "INFO: async-arrival Codex environment setup response detected without fresh review evidence"
  elif [ "$ASYNC_BOT_RESPONSE_SOURCE" = "review" ] && codex_response_is_blocking "$ASYNC_BOT_RESPONSE"; then
    echo "VERDICT: NEEDS_REVISION"
    echo "---BEGIN BOT RESPONSE---"
    echo "$ASYNC_BOT_RESPONSE"
    echo "---END BOT RESPONSE---"
    exit 1
  elif [ "$ASYNC_BOT_RESPONSE_SOURCE" = "review" ] && codex_response_is_approved "$ASYNC_BOT_RESPONSE"; then
    if [ "$SEEN_ENVIRONMENT_ERROR" -eq 1 ] && ! [ "$COMBINED_TIME" \> "$SEEN_ENVIRONMENT_TIME" ]; then
      codex_return_environment_error "$SEEN_ENVIRONMENT_RESPONSE"
    fi
    echo "VERDICT: APPROVED"
    echo "---BEGIN BOT RESPONSE---"
    echo "$ASYNC_BOT_RESPONSE"
    echo "---END BOT RESPONSE---"
    exit 0
  elif echo "$ASYNC_BOT_RESPONSE" | grep -qi "If Codex has suggestions, it will comment; otherwise it will react with"; then
    echo "INFO: async-arrival Codex acknowledgement detected without current-head review or inline comments"
    echo "INFO: waiting ${POLL_INTERVAL}s for final Codex async signal..."
    sleep "$POLL_INTERVAL"
    if ! ASYNC_INLINE_REVIEW_COMMENT_COUNT=$(codex_inline_review_comment_count_since "$TRIGGER_TIME"); then
      echo "VERDICT: TIMED_OUT — failed to fetch Codex inline review comments after async acknowledgement (treated as unavailable)"
      exit 2
    fi
    if [ "$ASYNC_INLINE_REVIEW_COMMENT_COUNT" -gt 0 ]; then
      codex_require_current_head
      echo "VERDICT: NEEDS_REVISION"
      echo "INFO: detected $ASYNC_INLINE_REVIEW_COMMENT_COUNT Codex inline review comment(s) after async acknowledgement"
      exit 1
	    fi
	    ASYNC_FINAL_BOT_RESPONSE=""
	    ASYNC_FINAL_BOT_RESPONSE_SOURCE=""
	    ASYNC_FINAL_POLL_TMPFILE=$(mktemp)
    if gh api "repos/$OWNER/$REPO/issues/$PR_NUMBER/comments" --paginate \
      2>/dev/null \
      | jq -sc --arg bot "$BOT_LOGIN" --arg bot_plain "$BOT_LOGIN_PLAIN" --arg trigger_time "$TRIGGER_TIME" --arg trigger_comment_id "$TRIGGER_COMMENT_ID" \
          '(add // []) | [.[] | select(.user.login == $bot or .user.login == $bot_plain) | select(.created_at > $trigger_time or (.created_at == $trigger_time and ((.id // 0 | tostring | tonumber) > ($trigger_comment_id | tonumber))))] | sort_by(.created_at, .id) | .[] | {created_at:(.created_at // ""), body:(.body // "")}' \
      > "$ASYNC_FINAL_POLL_TMPFILE" 2>/dev/null; then
      codex_scan_comment_evidence "$ASYNC_FINAL_POLL_TMPFILE"
      rm -f "$ASYNC_FINAL_POLL_TMPFILE"
    else
      rm -f "$ASYNC_FINAL_POLL_TMPFILE"
      # Fail closed (Finding #3): a failed root-comment fetch must not let a
      # clean review from the reviews endpoint be accepted below.
      echo "VERDICT: TIMED_OUT — failed to fetch Codex root comments after async acknowledgement (treated as unavailable)"
      exit 2
    fi

    ASYNC_FINAL_REVIEW_TMPFILE=$(mktemp)
    if gh api "repos/$OWNER/$REPO/pulls/$PR_NUMBER/reviews" --paginate \
      2>/dev/null \
      | jq -sr --arg bot "$BOT_LOGIN" --arg bot_plain "$BOT_LOGIN_PLAIN" --arg trigger_time "$TRIGGER_TIME" --arg sha "$CURRENT_SHA" \
          '(add // []) | [.[] | select((.user.login == $bot or .user.login == $bot_plain) and .submitted_at != null and .submitted_at >= $trigger_time and ((.commit_id // "") | startswith($sha)))] | sort_by(.submitted_at) | last | {created_at:(.submitted_at // ""), body:(.body // "")}' \
      > "$ASYNC_FINAL_REVIEW_TMPFILE" 2>/dev/null; then
      # Truncation happens inside jq (codepoint slice) to avoid SIGPIPE on
      # jq under `set -o pipefail` (see rationale above the main-loop
      # equivalent).
      ASYNC_FINAL_REVIEW_BODY=$(jq -r '(.body // empty) | .[0:5000]' "$ASYNC_FINAL_REVIEW_TMPFILE")  # workflow-shell-guard: allow SH003 - reads a tmpfile already validated as parseable JSON by the preceding gh|jq call; empty body means no evidence yet, not a failure, and is checked downstream via [ -n ]
      ASYNC_FINAL_REVIEW_TIME=$(jq -r '.created_at // empty' "$ASYNC_FINAL_REVIEW_TMPFILE")  # workflow-shell-guard: allow SH003 - reads the same pre-validated tmpfile as the body extraction above; empty time is not a failure
    else
      rm -f "$ASYNC_FINAL_REVIEW_TMPFILE"
      echo "VERDICT: TIMED_OUT — failed to fetch Codex PR reviews after async acknowledgement (treated as unavailable)"
      exit 2
    fi
    rm -f "$ASYNC_FINAL_REVIEW_TMPFILE"

    codex_combine_terminal_evidence "final async bot response" \
      "$COMMENT_TERMINAL_BODY" "$COMMENT_TERMINAL_TIME" \
      "$COMMENT_LATEST_BODY" "$COMMENT_LATEST_TIME" \
      "$ASYNC_FINAL_REVIEW_BODY" "$ASYNC_FINAL_REVIEW_TIME"
    ASYNC_FINAL_BOT_RESPONSE="$COMBINED_BODY"
    ASYNC_FINAL_BOT_RESPONSE_SOURCE="$COMBINED_SOURCE"
    # `jq -Rs` slurps its entire stdin before producing output, avoiding
    # SIGPIPE on long root-comment-sourced bodies (see rationale above the
    # main-loop equivalent).
    ASYNC_FINAL_BOT_RESPONSE=$(printf '%s' "$ASYNC_FINAL_BOT_RESPONSE" | jq -Rrs '.[0:10000]')  # workflow-shell-guard: allow SH003 - jq -R treats input as raw text (not JSON), so it cannot fail on malformed content; a genuine jq internal failure still trips `set -e` since this is a bare assignment, which is the desired fail-closed behavior

    if [ -n "$ASYNC_FINAL_BOT_RESPONSE" ]; then
      echo "INFO: final async bot response detected after acknowledgement wait"
      codex_require_current_head
      if codex_response_is_usage_limit "$ASYNC_FINAL_BOT_RESPONSE"; then
        codex_return_usage_limit "$ASYNC_FINAL_BOT_RESPONSE"
      elif [ "$ASYNC_FINAL_BOT_RESPONSE_SOURCE" = "comment" ] && codex_response_is_environment_error "$ASYNC_FINAL_BOT_RESPONSE"; then
        SEEN_ENVIRONMENT_ERROR=1
        SEEN_ENVIRONMENT_RESPONSE="$ASYNC_FINAL_BOT_RESPONSE"
        SEEN_ENVIRONMENT_TIME="$COMBINED_TIME"
        echo "INFO: final async Codex environment setup response detected without fresh review evidence"
      elif [ "$ASYNC_FINAL_BOT_RESPONSE_SOURCE" = "review" ] && codex_response_is_blocking "$ASYNC_FINAL_BOT_RESPONSE"; then
        echo "VERDICT: NEEDS_REVISION"
        echo "---BEGIN BOT RESPONSE---"
        echo "$ASYNC_FINAL_BOT_RESPONSE"
        echo "---END BOT RESPONSE---"
        exit 1
      elif [ "$ASYNC_FINAL_BOT_RESPONSE_SOURCE" = "review" ] && codex_response_is_approved "$ASYNC_FINAL_BOT_RESPONSE"; then
        if [ "$SEEN_ENVIRONMENT_ERROR" -eq 1 ] && ! [ "$COMBINED_TIME" \> "$SEEN_ENVIRONMENT_TIME" ]; then
          codex_return_environment_error "$SEEN_ENVIRONMENT_RESPONSE"
        fi
        echo "VERDICT: APPROVED"
        echo "---BEGIN BOT RESPONSE---"
        echo "$ASYNC_FINAL_BOT_RESPONSE"
        echo "---END BOT RESPONSE---"
        exit 0
      elif [ "$ASYNC_FINAL_BOT_RESPONSE_SOURCE" = "comment" ]; then
        echo "INFO: final async Codex root comment is not SHA-pinned terminal evidence"
      elif ! echo "$ASYNC_FINAL_BOT_RESPONSE" | grep -qi "If Codex has suggestions, it will comment; otherwise it will react with"; then
        echo "VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)"
        echo "---BEGIN BOT RESPONSE---"
        echo "$ASYNC_FINAL_BOT_RESPONSE"
        echo "---END BOT RESPONSE---"
        exit 1
      fi
    fi
    if ! ASYNC_APPROVAL_REACTION_COUNT=$(codex_trigger_approval_reaction_count "$TRIGGER_COMMENT_ID"); then
      echo "VERDICT: TIMED_OUT — failed to fetch Codex trigger reactions after async acknowledgement (treated as unavailable)"
      exit 2
    fi
    if [ -n "$ASYNC_TRIGGER_COMMENT_ID" ]; then
      if ! ASYNC_EXTRA_APPROVAL_REACTION_COUNT=$(codex_trigger_approval_reaction_count "$ASYNC_TRIGGER_COMMENT_ID"); then
        echo "VERDICT: TIMED_OUT — failed to fetch Codex async trigger reactions after async acknowledgement (treated as unavailable)"
        exit 2
      fi
      ASYNC_APPROVAL_REACTION_COUNT=$((ASYNC_APPROVAL_REACTION_COUNT + ASYNC_EXTRA_APPROVAL_REACTION_COUNT))
    fi
    if [ "$ASYNC_APPROVAL_REACTION_COUNT" -gt 0 ]; then
      echo "INFO: detected Codex thumbs-up reaction on trigger comment $TRIGGER_COMMENT_ID after async acknowledgement"
      if [ "$SEEN_ENVIRONMENT_ERROR" -eq 1 ]; then
        codex_return_environment_error "$SEEN_ENVIRONMENT_RESPONSE"
      fi
      codex_return_reaction_without_review
    fi
  elif [ "$ASYNC_BOT_RESPONSE_SOURCE" = "comment" ]; then
    echo "INFO: async-arrival Codex root comment is not SHA-pinned terminal evidence"
  else
    echo "VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)"
    echo "---BEGIN BOT RESPONSE---"
    echo "$ASYNC_BOT_RESPONSE"
    echo "---END BOT RESPONSE---"
    exit 1
  fi
fi

if [ "$ASYNC_APPROVAL_REACTION_COUNT" -gt 0 ]; then
  echo "INFO: detected Codex thumbs-up reaction on trigger comment $TRIGGER_COMMENT_ID during async grace period"
  echo "INFO: waiting ${POLL_INTERVAL}s for final Codex review evidence after async reaction..."
  sleep "$POLL_INTERVAL"
  if ! ASYNC_INLINE_REVIEW_COMMENT_COUNT=$(codex_inline_review_comment_count_since "$TRIGGER_TIME"); then
    echo "VERDICT: TIMED_OUT — failed to fetch Codex inline review comments after async reaction (treated as unavailable)"
    exit 2
  fi
  if [ "$ASYNC_INLINE_REVIEW_COMMENT_COUNT" -gt 0 ]; then
    codex_require_current_head
    echo "VERDICT: NEEDS_REVISION"
    echo "INFO: detected $ASYNC_INLINE_REVIEW_COMMENT_COUNT Codex inline review comment(s) after async reaction"
    exit 1
  fi

  ASYNC_REACTION_FINAL_BOT_RESPONSE=""
  ASYNC_REACTION_FINAL_BOT_RESPONSE_SOURCE=""
  ASYNC_REACTION_FINAL_POLL_TMPFILE=$(mktemp)
  if gh api "repos/$OWNER/$REPO/issues/$PR_NUMBER/comments" --paginate \
    2>/dev/null \
    | jq -sc --arg bot "$BOT_LOGIN" --arg bot_plain "$BOT_LOGIN_PLAIN" --arg trigger_time "$TRIGGER_TIME" --arg trigger_comment_id "$TRIGGER_COMMENT_ID" \
        '(add // []) | [.[] | select(.user.login == $bot or .user.login == $bot_plain) | select(.created_at > $trigger_time or (.created_at == $trigger_time and ((.id // 0 | tostring | tonumber) > ($trigger_comment_id | tonumber))))] | sort_by(.created_at, .id) | .[] | {created_at:(.created_at // ""), body:(.body // "")}' \
    > "$ASYNC_REACTION_FINAL_POLL_TMPFILE" 2>/dev/null; then
    codex_scan_comment_evidence "$ASYNC_REACTION_FINAL_POLL_TMPFILE"
    rm -f "$ASYNC_REACTION_FINAL_POLL_TMPFILE"
  else
    rm -f "$ASYNC_REACTION_FINAL_POLL_TMPFILE"
    # Fail closed (Finding #3): a failed root-comment fetch must not let a
    # clean review from the reviews endpoint be accepted below.
    echo "VERDICT: TIMED_OUT — failed to fetch Codex root comments after async reaction (treated as unavailable)"
    exit 2
  fi

  ASYNC_REACTION_FINAL_REVIEW_TMPFILE=$(mktemp)
  if gh api "repos/$OWNER/$REPO/pulls/$PR_NUMBER/reviews" --paginate \
    2>/dev/null \
    | jq -sr --arg bot "$BOT_LOGIN" --arg bot_plain "$BOT_LOGIN_PLAIN" --arg trigger_time "$TRIGGER_TIME" --arg sha "$CURRENT_SHA" \
        '(add // []) | [.[] | select((.user.login == $bot or .user.login == $bot_plain) and .submitted_at != null and .submitted_at >= $trigger_time and ((.commit_id // "") | startswith($sha)))] | sort_by(.submitted_at) | last | {created_at:(.submitted_at // ""), body:(.body // "")}' \
    > "$ASYNC_REACTION_FINAL_REVIEW_TMPFILE" 2>/dev/null; then
    # Truncation happens inside jq (codepoint slice) to avoid SIGPIPE on jq
    # under `set -o pipefail` (see rationale above the main-loop equivalent).
    ASYNC_REACTION_FINAL_REVIEW_BODY=$(jq -r '(.body // empty) | .[0:5000]' "$ASYNC_REACTION_FINAL_REVIEW_TMPFILE")  # workflow-shell-guard: allow SH003 - reads a tmpfile already validated as parseable JSON by the preceding gh|jq call; empty body means no evidence yet, not a failure, and is checked downstream via [ -n ]
    ASYNC_REACTION_FINAL_REVIEW_TIME=$(jq -r '.created_at // empty' "$ASYNC_REACTION_FINAL_REVIEW_TMPFILE")  # workflow-shell-guard: allow SH003 - reads the same pre-validated tmpfile as the body extraction above; empty time is not a failure
  else
    rm -f "$ASYNC_REACTION_FINAL_REVIEW_TMPFILE"
    echo "VERDICT: TIMED_OUT — failed to fetch Codex PR reviews after async reaction (treated as unavailable)"
    exit 2
  fi
  rm -f "$ASYNC_REACTION_FINAL_REVIEW_TMPFILE"

  codex_combine_terminal_evidence "final async reaction bot response" \
    "$COMMENT_TERMINAL_BODY" "$COMMENT_TERMINAL_TIME" \
    "$COMMENT_LATEST_BODY" "$COMMENT_LATEST_TIME" \
    "$ASYNC_REACTION_FINAL_REVIEW_BODY" "$ASYNC_REACTION_FINAL_REVIEW_TIME"
  ASYNC_REACTION_FINAL_BOT_RESPONSE="$COMBINED_BODY"
  ASYNC_REACTION_FINAL_BOT_RESPONSE_SOURCE="$COMBINED_SOURCE"
  # `jq -Rs` slurps its entire stdin before producing output, avoiding
  # SIGPIPE on long root-comment-sourced bodies (see rationale above the
  # main-loop equivalent).
  ASYNC_REACTION_FINAL_BOT_RESPONSE=$(printf '%s' "$ASYNC_REACTION_FINAL_BOT_RESPONSE" | jq -Rrs '.[0:10000]')  # workflow-shell-guard: allow SH003 - jq -R treats input as raw text (not JSON), so it cannot fail on malformed content; a genuine jq internal failure still trips `set -e` since this is a bare assignment, which is the desired fail-closed behavior

  if [ -n "$ASYNC_REACTION_FINAL_BOT_RESPONSE" ]; then
    codex_require_current_head
    if codex_response_is_usage_limit "$ASYNC_REACTION_FINAL_BOT_RESPONSE"; then
      codex_return_usage_limit "$ASYNC_REACTION_FINAL_BOT_RESPONSE"
    elif [ "$ASYNC_REACTION_FINAL_BOT_RESPONSE_SOURCE" = "comment" ] && codex_response_is_environment_error "$ASYNC_REACTION_FINAL_BOT_RESPONSE"; then
      SEEN_ENVIRONMENT_ERROR=1
      SEEN_ENVIRONMENT_RESPONSE="$ASYNC_REACTION_FINAL_BOT_RESPONSE"
      SEEN_ENVIRONMENT_TIME="$COMBINED_TIME"
      echo "INFO: final async reaction Codex environment setup response detected without fresh review evidence"
    elif [ "$ASYNC_REACTION_FINAL_BOT_RESPONSE_SOURCE" = "review" ] && codex_response_is_blocking "$ASYNC_REACTION_FINAL_BOT_RESPONSE"; then
      echo "VERDICT: NEEDS_REVISION"
      echo "---BEGIN BOT RESPONSE---"
      echo "$ASYNC_REACTION_FINAL_BOT_RESPONSE"
      echo "---END BOT RESPONSE---"
      exit 1
    elif [ "$ASYNC_REACTION_FINAL_BOT_RESPONSE_SOURCE" = "review" ] && codex_response_is_approved "$ASYNC_REACTION_FINAL_BOT_RESPONSE"; then
      if [ "$SEEN_ENVIRONMENT_ERROR" -eq 1 ] && ! [ "$COMBINED_TIME" \> "$SEEN_ENVIRONMENT_TIME" ]; then
        codex_return_environment_error "$SEEN_ENVIRONMENT_RESPONSE"
      fi
      echo "VERDICT: APPROVED"
      echo "---BEGIN BOT RESPONSE---"
      echo "$ASYNC_REACTION_FINAL_BOT_RESPONSE"
      echo "---END BOT RESPONSE---"
      exit 0
    elif [ "$ASYNC_REACTION_FINAL_BOT_RESPONSE_SOURCE" = "comment" ]; then
      echo "INFO: final async reaction Codex root comment is not SHA-pinned terminal evidence"
    elif ! echo "$ASYNC_REACTION_FINAL_BOT_RESPONSE" | grep -qi "If Codex has suggestions, it will comment; otherwise it will react with"; then
      echo "VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)"
      echo "---BEGIN BOT RESPONSE---"
      echo "$ASYNC_REACTION_FINAL_BOT_RESPONSE"
      echo "---END BOT RESPONSE---"
      exit 1
    fi
  fi
  if [ "$SEEN_ENVIRONMENT_ERROR" -eq 1 ]; then
    codex_return_environment_error "$SEEN_ENVIRONMENT_RESPONSE"
  fi
  codex_return_reaction_without_review
fi

if [ "$SEEN_ENVIRONMENT_ERROR" -eq 1 ]; then
  codex_return_environment_error "$SEEN_ENVIRONMENT_RESPONSE"
fi

if [ "$SEEN_APPROVAL_REACTION" -eq 1 ]; then
  codex_return_reaction_without_review
fi

echo "INFO: no bot response during async grace period"

# ── Timeout ───────────────────────────────────────────────────────────────────

TOTAL_ATTEMPTS=$((MAX_RETRIGGERS + 1))
echo "VERDICT: TIMED_OUT — no response from '$BOT_LOGIN' after ${TOTAL_ELAPSED}s (budget ${MAX_WAIT}s) across up to ${TOTAL_ATTEMPTS} attempt(s)"
echo "INFO: remediation — verify the Codex GitHub App is installed on $OWNER/$REPO."
echo "INFO: You can manually trigger the review by posting: $TRIGGER_PHRASE"
exit 2
