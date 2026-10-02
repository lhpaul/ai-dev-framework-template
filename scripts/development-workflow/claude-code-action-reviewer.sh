#!/usr/bin/env bash
# claude-code-action-reviewer.sh — Claude Code Action reviewer path for Step 7a
#
# Implements the dispatch/poll/parse loop for the Claude Code Action GitHub App
# reviewer. Dispatches a workflow_dispatch event for the configured review workflow,
# polls for the resulting Actions run to complete, and inspects PR review threads
# to determine the final verdict.
#
# This hosted-service reviewer is assessed at runtime from its repository
# prerequisite; it needs no local Claude CLI runtime, so no driving runner is
# inherently barred.
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
#   --adopt-run-id  <id>     Re-wait adoption (#1789, plan D11): poll this
#                            recorded workflow run instead of dispatching a new
#                            one. Requires --adopt-requested-at. The run is
#                            adopted only when actions/runs/<id> reads back with
#                            that id, a path ending with the workflow file, and
#                            a "PR #<n>" run name naming this PR; otherwise the
#                            companion prints a WARN and dispatches normally.
#   --adopt-requested-at <iso8601>
#                            The recorded request time of the adopted run
#                            (YYYY-MM-DDTHH:MM:SSZ). It becomes DISPATCH_TIME,
#                            so the review fetch keeps the original
#                            `.submitted_at >= DISPATCH_TIME` boundary.
#   --head-sha <sha>         Current-revision binding (#1789, plan D15): the
#                            full 40-hex PR head the loop read. When given, a
#                            bot review counts only when its commit_id equals
#                            this head (GitHub fixes a review's commit_id at
#                            submission), in addition to the DISPATCH_TIME
#                            boundary, so a review on another revision is never
#                            this head's verdict. Without it, today's count is
#                            kept.
#
# Exit codes:
#   0 — APPROVED       (Actions run completed successfully, no new blocking review
#                       threads posted by the bot)
#   1 — NEEDS_REVISION (Actions run completed, bot posted new blocking review threads)
#   2 — FAILED         (Actions run completed with a conclusion other than 'success',
#                       or invalid arguments; pr-review-loop.sh maps this to
#                       RESULT=escalate / REASON=claude_code_action_run_failed)
#   3 — UNAVAILABLE    (workflow file absent, dispatch rejected by the API, a
#                       dispatch response without an integer workflow_run_id,
#                       the run did not execute a review, or the bound run could
#                       not be read while polling: a 401/403 refusal, a 404, or
#                       no successful read on any poll — callers map to
#                       REASON=unavailable; never clean, never No verdict yet)
#   4 — NO_VERDICT_YET (the dispatched run did not complete within max-wait: the
#                       reviewer has not answered yet; pr-review-loop.sh maps this
#                       to RESULT=waiting_on_reviewer / REASON=reviewer-no-verdict-yet,
#                       not a failure — #1789)
#
# Run binding (#1789, plan D15 Claude dispatch rule): the dispatch is sent with
# return_run_details=true and the run is bound to THIS request only by the
# workflow_run_id GitHub returns for it; only actions/runs/<workflow_run_id> is
# polled. No run list is searched and no timestamp, run name, or head_sha is
# used to pick a run. Machine-readable dispatch lines on stdout:
#   DISPATCH_RESULT=accepted            the response carried workflow_run_id
#   DISPATCH_WORKFLOW_RUN_ID=<id>       printed with DISPATCH_RESULT=accepted
#   DISPATCH_RESULT=workflow_not_found  the API rejected the dispatch as 404 /
#                                       not found (exit 3)
#   DISPATCH_RESULT=rejected            the API rejected the dispatch for any
#                                       other reason (exit 3)
#   DISPATCH_RESULT=no_workflow_run_id  the dispatch was accepted but the
#                                       response (for example an empty 204) had
#                                       no integer workflow_run_id (exit 3)
#   DISPATCH_RESULT=adopted             --adopt-run-id named a run that passed
#                                       the adoption checks; nothing dispatched
#
# Request record (#1789, plan D12), printed once the run is bound (dispatched
# or adopted), on every later exit path:
#   REVIEW_REQUESTED_AT=<iso8601>       DISPATCH_TIME (the recorded requested_at
#                                       when a run was adopted)
#   REVIEW_REQUEST_REF=<run id>         the bound workflow run id

set -euo pipefail

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

verify_claude_code_action_run_log() {
  local run_id="$1"
  local owner="$2"
  local repo="$3"
  local run_log_stderr run_log_tmpfile run_log_status run_log_err
  local log_classification log_classification_status

  if [ -z "$run_id" ] || [ "$run_id" = "null" ]; then
    echo "VERDICT: UNAVAILABLE — run succeeded but no run id was available for log verification"
    return 3
  fi

  run_log_stderr="$(mktemp)" || {
    echo "VERDICT: UNAVAILABLE — could not create temp file for Actions log stderr" >&2
    return 3
  }
  run_log_tmpfile="$(mktemp)" || {
    rm -f "$run_log_stderr"
    echo "VERDICT: UNAVAILABLE — could not create temp file for Actions run log" >&2
    return 3
  }
  run_log_status=0
  gh run view "$run_id" --repo "$owner/$repo" --log \
    >"$run_log_tmpfile" 2>"$run_log_stderr" || run_log_status=$?

  if [ "$run_log_status" -ne 0 ]; then
    run_log_err=$(cat "$run_log_stderr")
    rm -f "$run_log_stderr" "$run_log_tmpfile"
    echo "WARNING: could not fetch Actions run log (exit $run_log_status): $run_log_err" >&2
    echo "VERDICT: UNAVAILABLE — run succeeded but log verification failed"
    return 3
  fi
  rm -f "$run_log_stderr"

  log_classification_status=0
  log_classification="$(classify_claude_code_action_log "$run_log_tmpfile")" || log_classification_status=$?
  rm -f "$run_log_tmpfile"

  case "$log_classification_status" in
    0)
      echo "INFO: Claude Code Action log verification passed ($log_classification)"
      return 0
      ;;
    1)
      echo "VERDICT: UNAVAILABLE — Claude Code Action run completed without executing a review ($log_classification)"
      return 3
      ;;
    *)
      echo "VERDICT: UNAVAILABLE — Claude Code Action run log did not contain a positive execution marker ($log_classification)"
      return 3
      ;;
  esac
}

# claude_code_action_classify_poll_error <gh-stderr-text>
#
# #1789 (spec BR 2): classify a failed read of actions/runs/<id> from gh's
# error output. Prints one of:
#   transient  rate limit (primary or secondary), 5xx, network, or no/unknown
#              error text - keep polling
#   denied     401/403 authorization or permission refusal - positive failure
#              evidence
#   gone       404 / not found for the bound run id - positive failure evidence
# A 403 that is a rate limit is transient, so rate-limit text is checked first.
# Always returns 0.
claude_code_action_classify_poll_error() {
  local err="${1:-}"
  if printf '%s' "$err" | grep -qiE 'rate limit|abuse detection|retry-after'; then
    echo transient
  elif printf '%s' "$err" | grep -qiE 'HTTP 40[13]|forbidden|unauthorized|bad credentials|resource not accessible|requires authentication'; then
    echo denied
  elif printf '%s' "$err" | grep -qiE 'HTTP 404|not found'; then
    echo gone
  else
    echo transient
  fi
}

# claude_code_action_dispatch_run_id <response_file>
#
# #1789 (plan D15 Claude dispatch rule): print the workflow_run_id from a
# workflow_dispatch response body (sent with return_run_details=true), or
# nothing when the body is empty (HTTP 204), not JSON, not an object, or holds
# no positive integer workflow_run_id. Always returns 0; the caller treats an
# empty result as "the run cannot be bound to this request".
claude_code_action_dispatch_run_id() {
  local response_file="${1:-}"
  local run_id=""

  [ -n "$response_file" ] && [ -s "$response_file" ] || return 0
  run_id="$(jq -r '
    if type == "object"
       and ((.workflow_run_id | type) == "number")
       and (.workflow_run_id > 0)
       and (.workflow_run_id == (.workflow_run_id | floor))
    then (.workflow_run_id | tostring)
    else empty end' "$response_file" 2>/dev/null)" || run_id=""
  case "$run_id" in
    ''|*[!0-9]*) return 0 ;;
  esac
  printf '%s\n' "$run_id"
}

if [ "${CLAUDE_CODE_ACTION_REVIEWER_LIBRARY_MODE:-0}" = "1" ]; then
  return 0 2>/dev/null || exit 0
fi

# ── Argument parsing ──────────────────────────────────────────────────────────

if [ $# -lt 3 ]; then
  echo "Usage: $0 <pr_number> <owner> <repo> [--workflow-file <name>] [--bot-login <login>] [--poll-interval <seconds>] [--max-wait <seconds>] [--adopt-run-id <id> --adopt-requested-at <iso8601>] [--head-sha <sha>]" >&2
  exit 2
fi

ADOPT_RUN_ID=""
ADOPT_REQUESTED_AT=""
HEAD_SHA=""

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
    --adopt-run-id)
      if [ $# -lt 2 ]; then echo "ERROR: --adopt-run-id requires a value" >&2; exit 2; fi
      ADOPT_RUN_ID="$2"; shift 2;;
    --adopt-requested-at)
      if [ $# -lt 2 ]; then echo "ERROR: --adopt-requested-at requires a value" >&2; exit 2; fi
      ADOPT_REQUESTED_AT="$2"; shift 2;;
    --head-sha)
      if [ $# -lt 2 ]; then echo "ERROR: --head-sha requires a value" >&2; exit 2; fi
      HEAD_SHA="$2"; shift 2;;
    *)
      echo "ERROR: unknown option '$1'" >&2; exit 2;;
  esac
done

# Adoption flags (#1789, plan D11) come together or not at all.
if [ -n "$ADOPT_RUN_ID" ] || [ -n "$ADOPT_REQUESTED_AT" ]; then
  if [ -z "$ADOPT_RUN_ID" ] || [ -z "$ADOPT_REQUESTED_AT" ]; then
    echo "ERROR: --adopt-run-id and --adopt-requested-at must be given together" >&2
    exit 2
  fi
  case "$ADOPT_RUN_ID" in
    0|*[!0-9]*)
      echo "ERROR: --adopt-run-id value '$ADOPT_RUN_ID' is not a positive integer" >&2
      exit 2
      ;;
  esac
  if ! [[ "$ADOPT_REQUESTED_AT" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
    echo "ERROR: --adopt-requested-at value '$ADOPT_REQUESTED_AT' is not an ISO-8601 UTC time (YYYY-MM-DDTHH:MM:SSZ)" >&2
    exit 2
  fi
fi

# --head-sha (#1789, plan D15) must be a full 40-hex commit SHA: it is compared
# with each review's commit_id, so a short or malformed value would silently
# discard every review.
if [ -n "$HEAD_SHA" ]; then
  if ! [[ "$HEAD_SHA" =~ ^[0-9a-fA-F]{40}$ ]]; then
    echo "ERROR: --head-sha value '$HEAD_SHA' is not a full 40-hex commit SHA" >&2
    exit 2
  fi
  HEAD_SHA="$(printf '%s' "$HEAD_SHA" | tr '[:upper:]' '[:lower:]')"
fi

# ── Validate numeric options ──────────────────────────────────────────────────
# POLL_INTERVAL and MAX_WAIT are used in 'sleep' and arithmetic. Validate them
# here so a non-numeric value exits with code 2 (FAILED) instead of
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

# ── Record dispatch time (before dispatch) ────────────────────────────────────
# DISPATCH_TIME bounds which bot reviews count (Phase 3). It no longer selects
# the run: the run is bound by the workflow_run_id the dispatch returns (#1789,
# plan D15 Claude dispatch rule).

_DISPATCH_EPOCH=$(date -u +%s)
DISPATCH_TIME=$(date -u -r "$_DISPATCH_EPOCH" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || \
  date -u -d "@$_DISPATCH_EPOCH" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || \
  python3 -c "import datetime,sys; print(datetime.datetime.fromtimestamp(int(sys.argv[1]), datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'))" "$_DISPATCH_EPOCH")
unset _DISPATCH_EPOCH
echo "INFO: dispatch time (pre-dispatch): $DISPATCH_TIME"

# ── Re-wait adoption (#1789, plan D11) ───────────────────────────────────────
# With --adopt-run-id, the loop hands over the run this loop recorded for the
# current head and run id. Adopt it only when it reads back as that run, from
# this workflow file, for this PR; then skip the dispatch, poll only that run,
# and keep the original review boundary by using the recorded request time as
# DISPATCH_TIME. Never search runs by created_at. A run that cannot be read or
# fails a check is not adopted: WARN and dispatch normally.
ADOPTED=0
RUN_ID=""
if [ -n "$ADOPT_RUN_ID" ]; then
  ADOPT_STATUS=0
  ADOPT_INFO=""
  ADOPT_INFO="$(gh api "repos/$OWNER/$REPO/actions/runs/$ADOPT_RUN_ID" 2>/dev/null \
    | jq -c --arg id "$ADOPT_RUN_ID" --arg wf "$WORKFLOW_FILE" --arg pr "$PR_NUMBER" '
        if type == "object" and ((.id // "") | tostring) == $id then
          {
            path_ok: (((.path // "") | tostring) as $p
                      | def wfmatch: . == $wf or endswith("/" + $wf);
                        ($p | wfmatch)
                        or ([$p | match("@"; "g").offset]
                            | any(. as $i | $p[0:$i] | wfmatch))),
            # The PR-specific run title is in display_title; name may hold
            # only the workflow name. Accept the PR number from either.
            pr_ok: ([.display_title, .name]
                    | map(select(. != null) | tostring
                          | capture("PR #(?<pr>[0-9]+)(?:[^0-9]|$)")? | .pr)
                    | any(. == $pr))
          }
        else error("response is not workflow run " + $id) end' 2>/dev/null)" || ADOPT_STATUS=$?
  if [ "$ADOPT_STATUS" -ne 0 ] || [ -z "$ADOPT_INFO" ]; then
    echo "WARN: recorded Claude Code Action run $ADOPT_RUN_ID could not be read; not adopting it — dispatching a new review" >&2
  elif [ "$(printf '%s' "$ADOPT_INFO" | jq -r '.path_ok')" != "true" ]; then
    echo "WARN: recorded Claude Code Action run $ADOPT_RUN_ID is not a '$WORKFLOW_FILE' run; not adopting it — dispatching a new review" >&2
  elif [ "$(printf '%s' "$ADOPT_INFO" | jq -r '.pr_ok')" != "true" ]; then
    echo "WARN: recorded Claude Code Action run $ADOPT_RUN_ID is not named for PR #$PR_NUMBER; not adopting it — dispatching a new review" >&2
  else
    ADOPTED=1
    RUN_ID="$ADOPT_RUN_ID"
    DISPATCH_TIME="$ADOPT_REQUESTED_AT"
    echo "DISPATCH_RESULT=adopted"
    echo "DISPATCH_WORKFLOW_RUN_ID=$RUN_ID"
    echo "INFO: adopted the recorded workflow run id $RUN_ID (requested at $DISPATCH_TIME); no new dispatch"
  fi
  unset ADOPT_STATUS ADOPT_INFO
fi

# ── Phase 1: Dispatch workflow ────────────────────────────────────────────────
# Call workflow_dispatch with ref=DISPATCH_REF (default branch), the pr_number
# input, and return_run_details=true (sent as JSON true), so GitHub answers 200
# with the new run's workflow_run_id instead of an empty 204. On failure:
#   - 404 / "workflow was not found" → exit 3 (UNAVAILABLE: file absent)
#   - other API rejections → exit 3 (UNAVAILABLE: dispatch failure)
#   - accepted but no integer workflow_run_id in the response → exit 3
#     (UNAVAILABLE: the run cannot be bound to this request; the time-window
#     run search is never used as a fallback)

# Fresh dispatch only when no recorded run was adopted above.
if [ "$ADOPTED" -eq 0 ]; then
echo "INFO: dispatching workflow '$WORKFLOW_FILE' on ref '$DISPATCH_REF' for PR #$PR_NUMBER..."

DISPATCH_STDERR=$(mktemp)
DISPATCH_RESPONSE=$(mktemp)
DISPATCH_STATUS=0
gh api "repos/$OWNER/$REPO/actions/workflows/$WORKFLOW_FILE/dispatches" \
  --method POST \
  --raw-field "ref=$DISPATCH_REF" \
  --raw-field "inputs[pr_number]=$PR_NUMBER" \
  --field "return_run_details=true" \
  >"$DISPATCH_RESPONSE" 2>"$DISPATCH_STDERR" || DISPATCH_STATUS=$?

if [ "$DISPATCH_STATUS" -ne 0 ]; then
  DISPATCH_ERR=$(cat "$DISPATCH_STDERR")
  rm -f "$DISPATCH_STDERR" "$DISPATCH_RESPONSE"
  echo "ERROR: workflow dispatch failed (exit $DISPATCH_STATUS): $DISPATCH_ERR" >&2
  # Distinguish 404 (workflow file absent / not found) from other errors
  if echo "$DISPATCH_ERR" | grep -qi "not found\|404\|workflow was not found"; then
    echo "DISPATCH_RESULT=workflow_not_found"
    echo "VERDICT: UNAVAILABLE — workflow file '$WORKFLOW_FILE' not found on ref '$DISPATCH_REF'"
  else
    echo "DISPATCH_RESULT=rejected"
    echo "VERDICT: UNAVAILABLE — workflow dispatch failed: $DISPATCH_ERR"
  fi
  exit 3
fi
rm -f "$DISPATCH_STDERR"

RUN_ID="$(claude_code_action_dispatch_run_id "$DISPATCH_RESPONSE")"
if [ -z "$RUN_ID" ]; then
  if [ -s "$DISPATCH_RESPONSE" ]; then
    echo "WARNING: dispatch response body had no integer workflow_run_id: $(head -c 300 "$DISPATCH_RESPONSE" | tr '\n' ' ')" >&2
  else
    echo "WARNING: dispatch response body was empty (HTTP 204 without run details)" >&2
  fi
  rm -f "$DISPATCH_RESPONSE"
  echo "DISPATCH_RESULT=no_workflow_run_id"
  echo "VERDICT: UNAVAILABLE — dispatch response carried no workflow_run_id; the run cannot be bound to this request"
  exit 3
fi
rm -f "$DISPATCH_RESPONSE"

echo "DISPATCH_RESULT=accepted"
echo "DISPATCH_WORKFLOW_RUN_ID=$RUN_ID"
echo "INFO: workflow dispatch accepted; bound to workflow run id $RUN_ID"
fi  # end: ADOPTED -eq 0 (fresh dispatch)

# #1789 (plan D12): the request this run answers — the dispatch (or the
# adopted recorded request) and the bound run id. Printed once, here, so every
# later exit path carries it.
echo "REVIEW_REQUESTED_AT=$DISPATCH_TIME"
echo "REVIEW_REQUEST_REF=$RUN_ID"

# ── Phase 2: Poll the dispatched run until it completes ──────────────────────
# Poll only actions/runs/<RUN_ID> at POLL_INTERVAL intervals until it reaches
# status=completed or the budget ends. No run list is searched: a run another
# dispatch created (for example an earlier dispatch for a previous head, inside
# any time window) can never be read as this request's answer.

echo "INFO: polling workflow run $RUN_ID..."

TOTAL_ELAPSED=0
RUN_URL=""
RUN_STATUS=""
RUN_CONCLUSION=""
POLL_READ_OK=0
POLL_READ_FAILED=0
POLL_LAST_ERR=""

while [ "$TOTAL_ELAPSED" -lt "$MAX_WAIT" ]; do
  echo "INFO: polling... elapsed ${TOTAL_ELAPSED}s / ${MAX_WAIT}s"

  # Use a temp file to avoid SIGPIPE under pipefail.
  RUN_POLL_STDERR=$(mktemp)
  RUN_POLL_TMPFILE=$(mktemp)
  POLL_STATUS=0
  gh api "repos/$OWNER/$REPO/actions/runs/$RUN_ID" \
    2>"$RUN_POLL_STDERR" \
    | jq -c --arg id "$RUN_ID" \
        'if type == "object" and ((.id // "") | tostring) == $id
         then {status: .status, conclusion: .conclusion, html_url: .html_url, id: .id}
         else error("response is not workflow run " + $id) end' \
    > "$RUN_POLL_TMPFILE" 2>/dev/null || POLL_STATUS=$?

  if [ "$POLL_STATUS" -ne 0 ]; then
    POLL_ERR=$(cat "$RUN_POLL_STDERR")
    rm -f "$RUN_POLL_STDERR" "$RUN_POLL_TMPFILE"
    echo "WARNING: could not read workflow run $RUN_ID during polling: ${POLL_ERR:-unreadable response}" >&2
    # #1789 (spec BR 2): only positive evidence makes a reviewer failed. A
    # permission refusal (401/403) or a missing bound run (404) is that
    # evidence, so it is unavailable (exit 3), never No verdict yet. A
    # transient failure (5xx, network, rate limit) keeps polling.
    case "$(claude_code_action_classify_poll_error "$POLL_ERR")" in
      denied)
        echo "POLL_RESULT=read_denied"
        echo "VERDICT: UNAVAILABLE — workflow run $RUN_ID could not be read: authorization or permission refused (${POLL_ERR})"
        exit 3
        ;;
      gone)
        echo "POLL_RESULT=run_not_found"
        echo "VERDICT: UNAVAILABLE — bound workflow run $RUN_ID was not found (${POLL_ERR})"
        exit 3
        ;;
    esac
    POLL_READ_FAILED=$((POLL_READ_FAILED + 1))
    POLL_LAST_ERR="${POLL_ERR:-unreadable response}"
    sleep "$POLL_INTERVAL"
    TOTAL_ELAPSED=$((TOTAL_ELAPSED + POLL_INTERVAL))
    continue
  fi
  rm -f "$RUN_POLL_STDERR"

  RUN_INFO=$(cat "$RUN_POLL_TMPFILE")
  rm -f "$RUN_POLL_TMPFILE"
  POLL_READ_OK=$((POLL_READ_OK + 1))

  if [ -z "$RUN_INFO" ]; then
    echo "INFO: workflow run $RUN_ID not readable yet..."
    sleep "$POLL_INTERVAL"
    TOTAL_ELAPSED=$((TOTAL_ELAPSED + POLL_INTERVAL))
    continue
  fi

  RUN_STATUS=$(echo "$RUN_INFO" | jq -r '.status // empty')
  RUN_CONCLUSION=$(echo "$RUN_INFO" | jq -r '.conclusion // empty')
  RUN_URL=$(echo "$RUN_INFO" | jq -r '.html_url // empty')

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

if [ "$RUN_STATUS" != "completed" ]; then
  # #1789 (plan D8 Claude row): the budget ran out before any run completed.
  # No verdict yet, not a failure - but only when the run was actually seen.
  # If every read of the bound run failed (transient errors for the whole
  # budget), the reviewer was unreachable: that is positive evidence under
  # spec BR 2, so fail closed (exit 3) instead of reporting "no failure".
  if [ "$POLL_READ_OK" -eq 0 ] && [ "$POLL_READ_FAILED" -gt 0 ]; then
    echo "POLL_RESULT=run_unreadable"
    echo "VERDICT: UNAVAILABLE — workflow run $RUN_ID could not be read on any of $POLL_READ_FAILED polls within ${MAX_WAIT}s (last error: $POLL_LAST_ERR)"
    exit 3
  fi
  echo "VERDICT: NO_VERDICT_YET — no run completed within ${MAX_WAIT}s (run URL: ${RUN_URL:-unknown})"
  echo "INFO: re-run the reviewer loop later on the same revision; if the run never completes, verify the '$WORKFLOW_FILE' workflow is present and configured in $OWNER/$REPO."
  exit 4
fi

if [ -z "$RUN_CONCLUSION" ] || [ "$RUN_CONCLUSION" = "null" ]; then
  echo "VERDICT: FAILED — run completed without a conclusion (run URL: ${RUN_URL:-unknown})"
  echo "INFO: remediation — check the Actions run log at ${RUN_URL:-the run page} for details."
  exit 2
fi

if [ "$RUN_CONCLUSION" != "success" ]; then
  echo "VERDICT: FAILED — run completed with conclusion '$RUN_CONCLUSION' (not 'success'): $RUN_URL"
  echo "INFO: remediation — check the Actions run log at $RUN_URL for details."
  exit 2
fi

echo "INFO: Actions run completed with conclusion=success: $RUN_URL"

# A successful Actions run is not proof that Claude actually reviewed the PR.
# claude-code-action exits successfully when no prompt/trigger is present, logging
# "No trigger found" and posting no review. Treat that as unavailable rather than
# clean so the reviewer loop does not bless no-op runs.
verify_claude_code_action_run_log "$RUN_ID" "$OWNER" "$REPO" || exit $?

# ── Phase 3 (continued): Check PR review threads ──────────────────────────────
# After a successful run, inspect PR reviews posted by the bot after dispatch_time.
# If any review has state=CHANGES_REQUESTED, exit 1 (NEEDS_REVISION).
# Otherwise exit 0 (APPROVED).

echo "INFO: checking PR #$PR_NUMBER reviews from '$BOT_LOGIN' posted after $DISPATCH_TIME${HEAD_SHA:+ on commit $HEAD_SHA}..."

REVIEW_STDERR=$(mktemp)
REVIEW_TMPFILE=$(mktemp)
REVIEW_STATUS=0
gh api "repos/$OWNER/$REPO/pulls/$PR_NUMBER/reviews" --paginate \
  2>"$REVIEW_STDERR" \
  | jq -r --arg bot "$BOT_LOGIN" --arg bot_plain "$BOT_LOGIN_PLAIN" \
      --arg dispatch_time "$DISPATCH_TIME" --arg head_sha "$HEAD_SHA" \
      '[.[] | select((.user.login == $bot or .user.login == ($bot_plain + "[bot]")) and .submitted_at != null and .submitted_at >= $dispatch_time)
            | select($head_sha == "" or (((.commit_id // "") | ascii_downcase) == $head_sha))] | length, (.[].state // empty)' \
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
