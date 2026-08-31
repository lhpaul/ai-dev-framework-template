#!/usr/bin/env bash
# haystack-reviewer.sh — Haystack triage CLI reviewer for Step 7 / Step 7a
#
# Wraps `haystack triage <PR> --json` and emits the standard companion-script
# key-value output contract consumed by pr-review-loop.sh.
#
# Usage:
#   haystack-reviewer.sh <pr_number> <owner> <repo> [--timeout <seconds>]
#
# Options:
#   --timeout <seconds>   Maximum seconds to wait for `haystack triage`. Default: 120.
#                         Also overridable via HAYSTACK_REVIEWER_TIMEOUT env var.
#                         The --timeout flag takes precedence over the env var.
#
# Exit codes:
#   0 — APPROVED   (no blocking findings)
#   1 — NEEDS_REVISION (one or more blocking findings)
#   2 — TIMED_OUT  (haystack triage did not return within the configured timeout)
#   3 — SKIPPED     (Haystack unavailable, unauthorized, or declined an
#                     oversized PR because of its analysis file limit)
#
# Stdout key-value contract (matched by pr-review-loop.sh):
#   RESULT=clean|needs_fixes|skipped
#   BLOCKING_COUNT=<n>
#   SUGGESTION_COUNT=<n>
#   COMMENT_COUNT=<n>
#   DISPLAY_RESULT=<value> (optional; used by pr-review-loop.sh summaries)
#   POLICY_REVIEW_REQUIRED=0|1 (optional; present when pr-status is available)
#   REASON=<value>   (only when RESULT=skipped — values: unavailable, timeout,
#                     pending_timeout, unauthorized, forbidden,
#                     analysis_skipped_file_limit)
#
# Polling behaviour for transient states (status=pending, status=error, etc.):
#   When `haystack triage --no-wait` returns ANY non-empty status value other
#   than "none" (e.g. status=pending, status=error, "Rating synthesis not
#   available"), the analysis is still in progress.  The script polls every
#   HAYSTACK_POLL_INTERVAL seconds (default: 15) until a genuinely completed
#   result is returned (no "status" field in the JSON) or the overall TIMEOUT
#   budget is exhausted.  A completed result is signalled by the ABSENCE of a
#   "status" field — this is the only condition under which RESULT=clean may be
#   emitted.  If the budget is exhausted while the analysis is still transient,
#   RESULT=skipped is emitted with REASON=pending_timeout (distinct from
#   REASON=unavailable, which means the CLI is absent or triage returned
#   status=none; REASON=unauthorized/forbidden for triage status=error with
#   message=HTTP 401/403 (surfaced immediately, not poll-retried);
#   and REASON=timeout, which means a single haystack triage call exceeded the
#   per-call OS timeout).
#
# Confirmed JSON schema (haystack triage <PR> --json as of 2026-05-25):
#   {
#     "owner": "<string>",
#     "repo": "<string>",
#     "prNumber": <integer>,
#     "rating": <integer>,
#     "autoFixerHandling": [...],
#     "autoFixerSkipped": [...],
#     "findings": [
#       {
#         "category": "<string>",   ← severity discriminator field
#         "summary": "<string>",
#         "detail": "<string>",
#         "agentFixPrompt": "<string>",
#         "source": null | <object>
#       }
#     ]
#   }
#
# Severity mapping (based on confirmed schema — .findings[].category):
#   Blocking:  "Logic error", "Critical", any unrecognised value (safe-fail)
#   Advisory:  "Major" (conservative — see note), "Minor", "Advisory",
#              "Nitpick", "Trivial", "Weak test coverage", "Rules violation"
#
# NOTE on "Major": The spec marks "Major" as blocking (conservative safe-fail).
# However, Haystack uses "Major" for findings like "Weak test coverage" that are
# important but do not represent logic errors or security issues. Per BR-2 of the
# spec, only "Logic error" and "Critical" are formally blocking; "Major" is treated
# as advisory here to avoid false-positive blocks on style/coverage findings.
# If your team wants "Major" to be blocking, set HAYSTACK_MAJOR_IS_BLOCKING=1.
#
# NOTE on "Rules violation": Haystack uses this category for custom rule
# findings such as CHANGELOG structure checks (rule:
# keep-single-unreleased-changelog-section). This can produce false positives
# around release-owned CHANGELOG edits:
#
#   1. Legacy regular PRs with correctly-formatted CHANGELOG entries under
#      [Unreleased] -> ### Fixed (or other subsections). Normal development PRs
#      now use changelog.d fragments, but older or downstream branches may still
#      carry direct CHANGELOG edits.
#
#   2. Hotfix backport PRs (where the diff against develop shows an empty [Unreleased]
#      section from main, which Haystack misidentifies as a structural violation).
#
# IMPORTANT for agents: When you see a "Rules violation" finding for CHANGELOG
# structure, do NOT attempt to restructure the CHANGELOG. The finding is a known
# false positive. The current format is correct; restructuring will introduce a
# real regression. See haystack-triage.md for the full guidance and dismissal procedure.
#
# "Rules violation" is treated as advisory here because it is not a code logic error
# or security issue; genuine CHANGELOG structure problems are caught by the
# markdownlint CI check and check-changelog-duplicate-headers.sh, which are not
# subject to the same diff-interpretation issue.
#
# Unrecognised categories are treated as blocking (conservative safe-fail per spec).

set -euo pipefail

# Emit REVIEWED_HEAD when the check/PR head was established (#1651).
emit_reviewed_head_if_known() {
  [ -n "${REVIEWED_HEAD_SHA:-}" ] || return 0
  printf 'REVIEWED_HEAD=%s\n' "$REVIEWED_HEAD_SHA"
}

# ── Argument parsing ──────────────────────────────────────────────────────────

if [ $# -lt 3 ]; then
  echo "Usage: $0 <pr_number> <owner> <repo> [--timeout <seconds>]" >&2
  exit 3
fi

PR_NUMBER="$1"
OWNER="$2"
REPO="$3"
shift 3

# Validate positional arguments before interpolation.
case "$PR_NUMBER" in
  ''|0|*[!0-9]*)
    echo "ERROR: PR number '$PR_NUMBER' is not a valid positive integer" >&2
    exit 3
    ;;
esac
case "$OWNER" in
  ''|*[!A-Za-z0-9._-]*)
    echo "ERROR: owner '$OWNER' contains invalid characters (expected alphanumerics, hyphens, underscores, dots)" >&2
    exit 3
    ;;
esac
case "$REPO" in
  ''|*[!A-Za-z0-9._-]*)
    echo "ERROR: repo '$REPO' contains invalid characters (expected alphanumerics, hyphens, underscores, dots)" >&2
    exit 3
    ;;
esac

# Parse optional flags
TIMEOUT="${HAYSTACK_REVIEWER_TIMEOUT:-120}"
POLL_INTERVAL="${HAYSTACK_POLL_INTERVAL:-15}"
PR_STATUS_CHECK="${HAYSTACK_PR_STATUS_CHECK:-1}"
CHECK_NAME="${HAYSTACK_CHECK_NAME:-Haystack / Review}"

# #1651: set only when a check run artifact is fetched (see fetch_haystack_check_run_json).
REVIEWED_HEAD_SHA=""

while [ $# -gt 0 ]; do
  case "$1" in
    --timeout)
      if [ $# -lt 2 ]; then echo "ERROR: --timeout requires a value" >&2; exit 3; fi
      TIMEOUT="$2"; shift 2;;
    *)
      echo "ERROR: unknown option '$1'" >&2; exit 3;;
  esac
done

# Validate timeout
case "$TIMEOUT" in
  ''|0|*[!0-9]*)
    echo "ERROR: --timeout value '$TIMEOUT' is not a positive integer (must be >= 1)" >&2
    exit 3
    ;;
esac

# Validate poll interval
case "$POLL_INTERVAL" in
  ''|0|*[!0-9]*)
    echo "ERROR: HAYSTACK_POLL_INTERVAL value '$POLL_INTERVAL' is not a positive integer (must be >= 1)" >&2
    exit 3
    ;;
esac

# ── GitHub App check-run fallback ─────────────────────────────────────────────

_classify_haystack_category() {
  local category="$1"
  case "$category" in
    "Logic error"|"Critical")
      printf 'blocking'
      ;;
    "Major")
      if [ "${HAYSTACK_MAJOR_IS_BLOCKING:-0}" = "1" ]; then
        printf 'blocking'
      else
        printf 'advisory'
      fi
      ;;
    "Minor"|"Advisory"|"Nitpick"|"Trivial"|"Weak test coverage"|"Rules violation"|"Code contract violation")
      printf 'advisory'
      ;;
    *)
      printf 'blocking'
      ;;
  esac
}

fetch_haystack_check_run_json() {
  command -v gh >/dev/null 2>&1 || return 1

  local head_sha=""
  local runs_json=""
  local check_json=""

  if ! head_sha="$(gh api "repos/${OWNER}/${REPO}/pulls/${PR_NUMBER}" --jq '.head.sha // empty' 2>/dev/null)"; then
    return 1
  fi
  [ -n "$head_sha" ] || return 1

  if ! runs_json="$(gh api --paginate --slurp "repos/${OWNER}/${REPO}/commits/${head_sha}/check-runs" 2>/dev/null)"; then
    return 1
  fi
  [ -n "$runs_json" ] || return 1

  if ! check_json="$(printf '%s\n' "$runs_json" | jq -c --arg name "$CHECK_NAME" '
    [
      if type == "array" then
        .[] | (.check_runs[]? // empty)
      else
        .check_runs[]? // empty
      end
    ]
    | map(select((.name // "") == $name))
    | sort_by(.started_at // .completed_at // "")
    | last // empty
  ' 2>/dev/null)"; then
    return 1
  fi
  [ -n "$check_json" ] || return 1

  REVIEWED_HEAD_SHA="$(printf '%s\n' "$check_json" | jq -r '.head_sha // .headSha // empty' 2>/dev/null)" || REVIEWED_HEAD_SHA=""

  printf '%s\n' "$check_json"
}

haystack_check_run_is_analysis_file_limit_skip() {
  local check_json="$1"
  local status=""
  local evidence=""

  if ! status="$(printf '%s\n' "$check_json" | jq -r '.status // ""' 2>/dev/null)"; then
    return 1
  fi
  case "$status" in
    completed|COMPLETED) ;;
    *) return 1 ;;
  esac

  if ! evidence="$(printf '%s\n' "$check_json" | jq -r '
    [(.output.title // ""), (.output.summary // "")]
    | join(" ")
    | ascii_downcase
    | gsub("[-_]"; " ")
    | gsub("[[:space:]]+"; " ")
  ' 2>/dev/null)"; then
    return 1
  fi

  # Require both an explicit over-limit relationship and a Haystack
  # analysis/file-limit subject. Generic action_required conclusions, generic
  # "Analysis Skipped" text, numeric file counts, and time-limit messages do
  # not satisfy this predicate.
  if [[ ! "$evidence" =~ (^|[^[:alnum:]_])(exceed|exceeds|exceeded|exceeding|over[[:space:]]+the[[:space:]]+limit|over[[:space:]]+haystack)([^[:alnum:]_]|$) ]]; then
    return 1
  fi

  case "$evidence" in
    *haystack\ analysis\ limit*|*haystack\ file\ limit*|*haystack\'s\ analysis\ limit*|*haystack\'s\ file\ limit*)
      return 0
      ;;
  esac

  return 1
}

emit_haystack_analysis_file_limit_skip_from_json() {
  local check_json="$1"
  local status=""
  local conclusion=""
  local details_url=""
  local title=""

  haystack_check_run_is_analysis_file_limit_skip "$check_json" || return 1

  status="$(printf '%s\n' "$check_json" | jq -r '.status // ""')"
  conclusion="$(printf '%s\n' "$check_json" | jq -r '.conclusion // ""')"
  details_url="$(printf '%s\n' "$check_json" | jq -r '.details_url // .detailsUrl // ""')"
  title="$(printf '%s\n' "$check_json" | jq -r '.output.title // ""')"

  printf 'RESULT=skipped\n'
emit_reviewed_head_if_known
  printf 'REASON=analysis_skipped_file_limit\n'
  printf 'DISPLAY_RESULT=skipped (analysis file limit)\n'
  printf 'BLOCKING_COUNT=0\n'
  printf 'SUGGESTION_COUNT=0\n'
  printf 'COMMENT_COUNT=0\n'
  printf 'CHECK_RUN_STATUS=%s\n' "$status"
  printf 'CHECK_RUN_CONCLUSION=%s\n' "$conclusion"
  [ -n "$title" ] && printf 'CHECK_RUN_TITLE=%s\n' "$title"
  [ -n "$details_url" ] && printf 'CHECK_RUN_URL=%s\n' "$details_url"
  return 0
}

emit_haystack_analysis_file_limit_skip_if_present() {
  local check_json=""

  if ! check_json="$(fetch_haystack_check_run_json)"; then
    return 1
  fi
  emit_haystack_analysis_file_limit_skip_from_json "$check_json"
}

emit_haystack_check_run_result() {
  local check_json=""
  local status=""
  local conclusion=""
  local details_url=""
  local summary=""
  local title=""
  local categories=""
  local category=""
  local classification=""
  local blocking_count=0
  local suggestion_count=0
  local comment_count=0
  local findings_count=""

  if ! check_json="$(fetch_haystack_check_run_json)"; then
    return 3
  fi

  if emit_haystack_analysis_file_limit_skip_from_json "$check_json"; then
    return 4
  fi

  status="$(printf '%s\n' "$check_json" | jq -r '.status // ""')"
  conclusion="$(printf '%s\n' "$check_json" | jq -r '.conclusion // ""')"
  details_url="$(printf '%s\n' "$check_json" | jq -r '.details_url // .detailsUrl // ""')"
  summary="$(printf '%s\n' "$check_json" | jq -r '.output.summary // ""')"
  title="$(printf '%s\n' "$check_json" | jq -r '.output.title // ""')"

  if [ "$status" != "completed" ] && [ "$status" != "COMPLETED" ]; then
    printf 'RESULT=skipped\n'
emit_reviewed_head_if_known
    printf 'REASON=pending_check_run\n'
    printf 'BLOCKING_COUNT=0\n'
    printf 'SUGGESTION_COUNT=0\n'
    printf 'COMMENT_COUNT=0\n'
    printf 'CHECK_RUN_STATUS=%s\n' "$status"
    printf 'CHECK_RUN_CONCLUSION=%s\n' "$conclusion"
    [ -n "$details_url" ] && printf 'CHECK_RUN_URL=%s\n' "$details_url"
    return 2
  fi

  categories="$(printf '%s\n' "$summary" | sed -n 's/^[[:space:]]*[-*][[:space:]][[:space:]]*//;s/^\*\*\[\([^]]*\)\]\*\*.*/\1/p')"
  if [ -n "$categories" ]; then
    while IFS= read -r category; do
      [ -z "${category:-}" ] && continue
      classification="$(_classify_haystack_category "$category")"
      case "$classification" in
        blocking) blocking_count=$((blocking_count + 1)) ;;
        *)        suggestion_count=$((suggestion_count + 1)) ;;
      esac
    done <<EOF
$categories
EOF
  fi
  comment_count=$((blocking_count + suggestion_count))

  findings_count="$(printf '%s\n' "$summary" | sed -n 's/^\*\*Findings:\*\* \([0-9][0-9]*\).*/\1/p' | head -n 1)"
  case "$findings_count" in
    ''|*[!0-9]*) findings_count="" ;;
  esac

  case "$conclusion" in
    success|SUCCESS|neutral|NEUTRAL|skipped|SKIPPED)
      printf 'RESULT=clean\n'
emit_reviewed_head_if_known
      printf 'BLOCKING_COUNT=0\n'
      printf 'SUGGESTION_COUNT=%d\n' "$suggestion_count"
      printf 'COMMENT_COUNT=%d\n' "$comment_count"
      printf 'CHECK_RUN_STATUS=%s\n' "$status"
      printf 'CHECK_RUN_CONCLUSION=%s\n' "$conclusion"
      [ -n "$title" ] && printf 'CHECK_RUN_TITLE=%s\n' "$title"
      [ -n "$details_url" ] && printf 'CHECK_RUN_URL=%s\n' "$details_url"
      return 0
      ;;
    failure|FAILURE|action_required|ACTION_REQUIRED|startup_failure|STARTUP_FAILURE)
      if [ "$comment_count" -eq 0 ] && [ "${findings_count:-unknown}" != "0" ]; then
        # The check run failed but did not expose parseable category lines. Fail
        # closed unless the summary explicitly reports zero findings.
        blocking_count=1
        comment_count=1
      fi
      if [ "$blocking_count" -gt 0 ]; then
        printf 'RESULT=needs_fixes\n'
emit_reviewed_head_if_known
        printf 'BLOCKING_COUNT=%d\n' "$blocking_count"
        printf 'SUGGESTION_COUNT=%d\n' "$suggestion_count"
        printf 'COMMENT_COUNT=%d\n' "$comment_count"
        printf 'CHECK_RUN_STATUS=%s\n' "$status"
        printf 'CHECK_RUN_CONCLUSION=%s\n' "$conclusion"
        [ -n "$title" ] && printf 'CHECK_RUN_TITLE=%s\n' "$title"
        [ -n "$details_url" ] && printf 'CHECK_RUN_URL=%s\n' "$details_url"
        return 1
      fi
      printf 'RESULT=clean\n'
emit_reviewed_head_if_known
      printf 'BLOCKING_COUNT=0\n'
      printf 'SUGGESTION_COUNT=%d\n' "$suggestion_count"
      printf 'COMMENT_COUNT=%d\n' "$comment_count"
      printf 'CHECK_RUN_STATUS=%s\n' "$status"
      printf 'CHECK_RUN_CONCLUSION=%s\n' "$conclusion"
      [ -n "$title" ] && printf 'CHECK_RUN_TITLE=%s\n' "$title"
      [ -n "$details_url" ] && printf 'CHECK_RUN_URL=%s\n' "$details_url"
      return 0
      ;;
    *)
      printf 'RESULT=skipped\n'
emit_reviewed_head_if_known
      printf 'REASON=check_run_%s\n' "${conclusion:-unknown}"
      printf 'BLOCKING_COUNT=0\n'
      printf 'SUGGESTION_COUNT=0\n'
      printf 'COMMENT_COUNT=0\n'
      printf 'CHECK_RUN_STATUS=%s\n' "$status"
      printf 'CHECK_RUN_CONCLUSION=%s\n' "$conclusion"
      [ -n "$details_url" ] && printf 'CHECK_RUN_URL=%s\n' "$details_url"
      return 2
      ;;
  esac
}

emit_check_run_fallback_or_skip() {
  local fallback_exit=0
  set +e
  emit_haystack_check_run_result
  fallback_exit=$?
  set -e
  [ "$fallback_exit" -eq 4 ] && exit 3
  [ "$fallback_exit" -ne 3 ] && exit "$fallback_exit"
  return 1
}

# ── Availability check ────────────────────────────────────────────────────────

if ! command -v haystack >/dev/null 2>&1; then
  echo "INFO: haystack CLI not found in PATH — trying GitHub App check-run fallback" >&2
  if emit_check_run_fallback_or_skip; then
    :
  fi
  echo "INFO: haystack CLI not found in PATH — skipping (UNAVAILABLE)" >&2
  printf 'RESULT=skipped\n'
emit_reviewed_head_if_known
  printf 'REASON=unavailable\n'
  printf 'BLOCKING_COUNT=0\n'
  printf 'SUGGESTION_COUNT=0\n'
  printf 'COMMENT_COUNT=0\n'
  exit 3
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "INFO: jq not found in PATH — skipping (UNAVAILABLE)" >&2
  printf 'RESULT=skipped\n'
emit_reviewed_head_if_known
  printf 'REASON=unavailable\n'
  printf 'BLOCKING_COUNT=0\n'
  printf 'SUGGESTION_COUNT=0\n'
  printf 'COMMENT_COUNT=0\n'
  exit 3
fi

echo "INFO: haystack CLI found: $(command -v haystack)" >&2
echo "INFO: poll-retry loop — polling every ${POLL_INTERVAL}s, overall timeout: ${TIMEOUT}s" >&2

# ── Poll-retry loop ───────────────────────────────────────────────────────────
#
# Each iteration calls `haystack triage ... --json --no-wait` (which returns
# immediately). If the JSON response carries status=pending, the loop sleeps
# POLL_INTERVAL seconds and retries until the analysis completes or the overall
# TIMEOUT budget is exhausted.
#
# POLL_CALL_TIMEOUT is the per-call timeout used to guard each individual
# invocation of `haystack triage` against a hung network call. It is capped to
# at most half the remaining budget so the loop always gets at least one retry
# after a timed-out call.

haystack_triage_auth_error_reason() {
  local triage_output="$1"
  local status message

  status="$(printf '%s\n' "$triage_output" | jq -r '.status // empty' 2>/dev/null)"
  status="${status:-}"
  [ "$status" != "error" ] && return 1
  message="$(printf '%s\n' "$triage_output" | jq -r '.message // empty' 2>/dev/null)"
  message="${message:-}"
  case "$message" in
    HTTP\ 401)
      printf 'unauthorized'
      return 0
      ;;
    HTTP\ 403)
      printf 'forbidden'
      return 0
      ;;
  esac
  return 1
}

TRIAGE_OUTPUT=""
TRIAGE_EXIT=0
elapsed=0
LOOP_START_TS="$(date +%s 2>/dev/null || printf '0')"
TRIAGE_STDERR=$(mktemp)

while true; do
  rm -f "$TRIAGE_STDERR"
  TRIAGE_STDERR=$(mktemp)
  TRIAGE_OUTPUT=""
  TRIAGE_EXIT=0

  # A completed current-head file-limit decline is a terminal, healthy
  # Haystack skip. Probe before every triage observation so a rerun does not
  # enter the extended polling window for analysis Haystack already declined.
  if emit_haystack_analysis_file_limit_skip_if_present; then
    rm -f "$TRIAGE_STDERR"
    exit 3
  fi

  # Compute actual elapsed seconds using wall-clock timestamps so the budget
  # tracking reflects real time, not just accumulated sleep intervals.
  NOW_TS="$(date +%s 2>/dev/null || printf '0')"
  if [ "$LOOP_START_TS" -gt 0 ] && [ "$NOW_TS" -ge "$LOOP_START_TS" ]; then
    elapsed=$((NOW_TS - LOOP_START_TS))
  fi

  # Per-call timeout: half of the remaining budget (minimum 1s).
  remaining=$((TIMEOUT - elapsed))
  if [ "$remaining" -le 0 ]; then
    # Budget exhausted before this iteration — handle below as pending_timeout.
    TRIAGE_EXIT=200  # sentinel: budget exhausted
    break
  fi
  POLL_CALL_TIMEOUT=$(( remaining / 2 ))
  [ "$POLL_CALL_TIMEOUT" -lt 1 ] && POLL_CALL_TIMEOUT=1

  echo "INFO: running: haystack triage ${OWNER}/${REPO}#${PR_NUMBER} --json --no-wait (elapsed: ${elapsed}s, per-call timeout: ${POLL_CALL_TIMEOUT}s)" >&2

  # Check for 'timeout' command availability (not always present on macOS without GNU coreutils).
  if command -v timeout >/dev/null 2>&1; then
    set +e
    TRIAGE_OUTPUT="$(timeout "$POLL_CALL_TIMEOUT" haystack triage "${OWNER}/${REPO}#${PR_NUMBER}" --json --no-wait 2>"$TRIAGE_STDERR")"
    TRIAGE_EXIT=$?
    set -e
  else
    # Fallback: background process + wait with a kill after POLL_CALL_TIMEOUT seconds.
    echo "INFO: 'timeout' command not available; using background-process fallback" >&2
    set +e
    haystack triage "${OWNER}/${REPO}#${PR_NUMBER}" --json --no-wait >"$TRIAGE_STDERR.stdout" 2>"$TRIAGE_STDERR" &
    TRIAGE_PID=$!
    poll_elapsed=0
    while kill -0 "$TRIAGE_PID" 2>/dev/null && [ "$poll_elapsed" -lt "$POLL_CALL_TIMEOUT" ]; do
      sleep 1
      poll_elapsed=$((poll_elapsed + 1))
    done
    if kill -0 "$TRIAGE_PID" 2>/dev/null; then
      kill "$TRIAGE_PID" 2>/dev/null || true
      wait "$TRIAGE_PID" 2>/dev/null || true
      TRIAGE_EXIT=124  # same as GNU timeout exit code on kill
    else
      wait "$TRIAGE_PID" 2>/dev/null
      TRIAGE_EXIT=$?
      TRIAGE_OUTPUT="$(cat "$TRIAGE_STDERR.stdout" 2>/dev/null || true)"
    fi
    set -e
    rm -f "$TRIAGE_STDERR.stdout"
  fi

  # Log stderr output for debugging.
  if [ -s "$TRIAGE_STDERR" ]; then
    echo "INFO: haystack triage stderr output:" >&2
    cat "$TRIAGE_STDERR" >&2
  fi

  # ── Handle per-call timeout ─────────────────────────────────────────────────
  if [ "$TRIAGE_EXIT" -eq 124 ]; then
    # Recompute elapsed from wall-clock before the next budget check.
    NOW_TS="$(date +%s 2>/dev/null || printf '0')"
    if [ "$LOOP_START_TS" -gt 0 ] && [ "$NOW_TS" -ge "$LOOP_START_TS" ]; then
      elapsed=$((NOW_TS - LOOP_START_TS))
    fi
    echo "INFO: haystack triage per-call timeout (total elapsed: ${elapsed}s)" >&2
    if [ "$elapsed" -ge "$TIMEOUT" ]; then
      TRIAGE_EXIT=124  # propagate timeout sentinel
      break
    fi
    # Retry immediately (the per-call timeout already consumed the sleep budget).
    continue
  fi

  # ── Handle other non-zero exit codes ────────────────────────────────────────
  #
  # Some versions of the haystack CLI return a non-zero exit code even when
  # stdout contains a valid completed-analysis JSON payload (e.g. a payload with
  # findings, or one where status=pending when analysis is still in progress).
  # Treating every non-zero exit as UNAVAILABLE silently drops completed results
  # and prevents the poll-retry loop from retrying pending analyses — the root
  # cause of issue #800 (Haystack reported unavailable while analysis completed
  # on the platform).
  #
  # Recovery strategy: when TRIAGE_EXIT is non-zero, inspect stdout before giving
  # up.  Three sub-cases:
  #   a) Empty or non-JSON output → genuine unavailability, exit UNAVAILABLE.
  #   b) Valid JSON with status=pending → transient; the CLI exited non-zero but
  #      the analysis is still running.  Fall through to the status-check block
  #      below so the poll-retry loop can sleep and retry (same path as exit 0 +
  #      pending).
  #   c) Valid JSON with a completed result (no status / unknown status) → the
  #      CLI exited non-zero but produced a usable result.  Log a warning (so the
  #      non-zero exit is not silent) and fall through to findings parsing.
  #   d) Valid JSON with status=none → permanent unavailability; fall through to
  #      the status-check block which handles this case.
  if [ "$TRIAGE_EXIT" -ne 0 ]; then
    echo "INFO: haystack triage exited with code $TRIAGE_EXIT — inspecting stdout before deciding outcome" >&2
    if [ -z "$TRIAGE_OUTPUT" ] || ! printf '%s\n' "$TRIAGE_OUTPUT" | jq -e . >/dev/null 2>&1; then
      # Sub-case (a): empty or invalid JSON → genuinely unavailable.
      echo "INFO: haystack triage non-zero exit AND empty/invalid stdout — treating as UNAVAILABLE" >&2
      rm -f "$TRIAGE_STDERR"
      printf 'RESULT=skipped\n'
emit_reviewed_head_if_known
      printf 'REASON=unavailable\n'
      printf 'BLOCKING_COUNT=0\n'
      printf 'SUGGESTION_COUNT=0\n'
      printf 'COMMENT_COUNT=0\n'
      exit 3
    fi
    # Sub-cases (b), (c), (d): stdout is valid JSON — fall through to status check
    # and findings parsing.  The status-check block below will handle pending,
    # none, and completed outcomes identically to the exit-0 path.
    echo "INFO: haystack triage non-zero exit (code $TRIAGE_EXIT) but stdout is valid JSON — proceeding to status/findings parsing (non-zero exit may be a haystack CLI version quirk)" >&2
  fi

  # ── Validate JSON output ─────────────────────────────────────────────────────
  if [ -z "$TRIAGE_OUTPUT" ]; then
    echo "INFO: haystack triage returned empty output — treating as UNAVAILABLE" >&2
    rm -f "$TRIAGE_STDERR"
    printf 'RESULT=skipped\n'
emit_reviewed_head_if_known
    printf 'REASON=unavailable\n'
    printf 'BLOCKING_COUNT=0\n'
    printf 'SUGGESTION_COUNT=0\n'
    printf 'COMMENT_COUNT=0\n'
    exit 3
  fi

  # Validate that TRIAGE_OUTPUT is well-formed JSON before parsing.
  if ! printf '%s\n' "$TRIAGE_OUTPUT" | jq -e . >/dev/null 2>&1; then
    echo "INFO: haystack triage returned invalid JSON — treating as UNAVAILABLE" >&2
    rm -f "$TRIAGE_STDERR"
    printf 'RESULT=skipped\n'
emit_reviewed_head_if_known
    printf 'REASON=unavailable\n'
    printf 'BLOCKING_COUNT=0\n'
    printf 'SUGGESTION_COUNT=0\n'
    printf 'COMMENT_COUNT=0\n'
    exit 3
  fi

  # ── Check status field ───────────────────────────────────────────────────────
  #
  # Empirical signal for a genuinely completed analysis (confirmed 2026-06-02):
  #   - COMPLETED:  the JSON has NO "status" field at all (.status // empty
  #                 returns empty string).  This is the only condition that
  #                 produces a usable findings payload.
  #   - TRANSIENT:  the JSON has a "status" field with any value (pending,
  #                 error, "Rating synthesis not available", or any other
  #                 non-null, non-"none" string).  These are still-synthesizing
  #                 states and must be retried.
  #   - PERMANENT:  status=none — no analysis was ever submitted for this PR.
  #
  # Mapping ANY non-empty, non-"none" status value to "completed" (the previous
  # *) catch-all behaviour) was the root cause of the Batch 71 false-clean bug:
  # status=error / "Rating synthesis not available" was treated as terminal,
  # findings parsing found zero findings, and RESULT=clean was emitted — silently
  # masking real findings that appeared on the web UI once synthesis finished.
  STATUS_VALUE="$(printf '%s\n' "$TRIAGE_OUTPUT" | jq -r '.status // empty' 2>/dev/null || true)"

  case "$STATUS_VALUE" in
    none)
      # Permanent: no analysis was ever submitted for this PR.
      echo "INFO: haystack triage returned status=none (no analysis available for this PR) — treating as UNAVAILABLE" >&2
      rm -f "$TRIAGE_STDERR"
      printf 'RESULT=skipped\n'
emit_reviewed_head_if_known
      printf 'REASON=unavailable\n'
      printf 'BLOCKING_COUNT=0\n'
      printf 'SUGGESTION_COUNT=0\n'
      printf 'COMMENT_COUNT=0\n'
      exit 3
      ;;
    "")
      # Empty status field = no "status" key in the JSON = genuinely completed
      # analysis.  Exit the loop and proceed to findings parsing.
      break
      ;;
    *)
      # Non-empty, non-"none" status value (e.g. "pending", "error",
      # "Rating synthesis not available", or any future transient state).
      # Authorization/API errors (HTTP 401/403) are permanent — fail fast.
      _auth_reason=""
      if _auth_reason="$(haystack_triage_auth_error_reason "$TRIAGE_OUTPUT")"; then
        _error_msg="$(printf '%s\n' "$TRIAGE_OUTPUT" | jq -r '.message // empty' 2>/dev/null)"
        _error_msg="${_error_msg:-unknown}"
        echo "INFO: haystack triage returned status=error with message=${_error_msg} — treating as ${_auth_reason} (not retrying)" >&2
        rm -f "$TRIAGE_STDERR"
        printf 'RESULT=skipped\n'
emit_reviewed_head_if_known
        printf 'REASON=%s\n' "$_auth_reason"
        printf 'BLOCKING_COUNT=0\n'
        printf 'SUGGESTION_COUNT=0\n'
        printf 'COMMENT_COUNT=0\n'
        exit 3
      fi
      # Treat other transient states as still synthesizing — poll-retry after POLL_INTERVAL.
      # NEVER map an unknown or error status to "clean"; only a genuinely
      # completed result (empty STATUS_VALUE above) may yield RESULT=clean.
      echo "INFO: status='${STATUS_VALUE}' — still synthesizing; waiting ${POLL_INTERVAL}s before retry (${elapsed}s elapsed of ${TIMEOUT}s budget)" >&2
      # The check run can become terminal while the triage request is in
      # flight. Probe again before sleeping so the skip is observed at this
      # standard polling boundary instead of burning the remaining timeout.
      if emit_haystack_analysis_file_limit_skip_if_present; then
        rm -f "$TRIAGE_STDERR"
        exit 3
      fi
      # Check budget BEFORE sleeping so we don't overshoot the timeout.
      if [ $((elapsed + POLL_INTERVAL)) -ge "$TIMEOUT" ]; then
        # Sleeping would exhaust the budget — exit now with pending_timeout.
        TRIAGE_EXIT=200  # sentinel: pending_timeout
        break
      fi
      sleep "$POLL_INTERVAL"
      # Wall-clock elapsed will be recomputed at the top of the next iteration.
      continue
      ;;
  esac
done

rm -f "$TRIAGE_STDERR"

# ── Handle loop exit conditions ───────────────────────────────────────────────

if [ "$TRIAGE_EXIT" -eq 124 ]; then
  # A single haystack triage call exceeded its per-call OS timeout and the
  # overall budget was exhausted.
  echo "INFO: haystack triage timed out after ${TIMEOUT}s" >&2
  echo "INFO: trying GitHub App check-run fallback after triage timeout" >&2
  if emit_check_run_fallback_or_skip; then
    :
  fi
  printf 'RESULT=skipped\n'
emit_reviewed_head_if_known
  printf 'REASON=timeout\n'
  printf 'BLOCKING_COUNT=0\n'
  printf 'SUGGESTION_COUNT=0\n'
  printf 'COMMENT_COUNT=0\n'
  exit 2
fi

if [ "$TRIAGE_EXIT" -eq 200 ]; then
  # Budget exhausted while the analysis was still in a transient state
  # (status=pending, status=error, "Rating synthesis not available", or any
  # other non-empty non-"none" status value) — analysis never produced a
  # completed result within the timeout window. This is distinct from
  # REASON=unavailable (CLI not found / auth failure) and REASON=timeout
  # (per-call OS timeout).
  echo "INFO: haystack triage transient state persisted — budget exhausted after ${TIMEOUT}s (pending_timeout)" >&2
  echo "INFO: trying GitHub App check-run fallback after pending_timeout" >&2
  if emit_check_run_fallback_or_skip; then
    :
  fi
  printf 'RESULT=skipped\n'
emit_reviewed_head_if_known
  printf 'REASON=pending_timeout\n'
  printf 'BLOCKING_COUNT=0\n'
  printf 'SUGGESTION_COUNT=0\n'
  printf 'COMMENT_COUNT=0\n'
  exit 2
fi

echo "INFO: haystack triage raw output:" >&2
printf '%s\n' "$TRIAGE_OUTPUT" >&2

# ── Parse findings by category ────────────────────────────────────────────────
#
# Confirmed schema: .findings[].category (not .findings[].severity)
# Blocking categories: "Logic error", "Critical"
# Advisory categories: "Minor", "Advisory", "Nitpick", "Trivial",
#                      "Weak test coverage", "Major" (see NOTE above)
# Unrecognised categories: blocking (safe-fail)

# Extract all finding categories as newline-separated list.
# Use '(.findings // [])[]' to avoid the jq-1.7.1-apple quirk where iterating
# '.findings[]' with a '// "fallback"' alternative fires once on an empty array,
# producing a spurious value. With '(.findings // [])[]', an empty/null .findings
# array produces zero output — no sentinel is emitted spuriously.
# Null/missing .category values are mapped to the sentinel "__UNKNOWN__" so they
# are treated as blocking (safe-fail) rather than silently dropped.
CATEGORIES="$(printf '%s\n' "$TRIAGE_OUTPUT" | jq -r '
  (.findings // [])[] |
  if (.category | type) == "string" and .category != "" then .category
  else "__UNKNOWN__"
  end
')"

BLOCKING_COUNT=0
SUGGESTION_COUNT=0

if [ -n "$CATEGORIES" ]; then
  while IFS= read -r category; do
    [ -z "${category:-}" ] && continue
    case "$category" in
      "Logic error"|"Critical")
        BLOCKING_COUNT=$((BLOCKING_COUNT + 1))
        ;;
      "Major")
        if [ "${HAYSTACK_MAJOR_IS_BLOCKING:-0}" = "1" ]; then
          BLOCKING_COUNT=$((BLOCKING_COUNT + 1))
        else
          SUGGESTION_COUNT=$((SUGGESTION_COUNT + 1))
        fi
        ;;
      "Minor"|"Advisory"|"Nitpick"|"Trivial"|"Weak test coverage"|"Rules violation"|"Code contract violation")
        SUGGESTION_COUNT=$((SUGGESTION_COUNT + 1))
        ;;
      "__UNKNOWN__"|*)
        # Null/missing or unrecognised category — safe-fail to blocking
        echo "INFO: unrecognised finding category '$category' — treating as blocking (safe-fail)" >&2
        BLOCKING_COUNT=$((BLOCKING_COUNT + 1))
        ;;
    esac
  done <<EOF
$CATEGORIES
EOF
fi

COMMENT_COUNT=$((BLOCKING_COUNT + SUGGESTION_COUNT))

echo "INFO: findings parsed — blocking: $BLOCKING_COUNT, advisory: $SUGGESTION_COUNT, total: $COMMENT_COUNT" >&2

# ── Parse review-policy verdict from haystack pr-status ──────────────────────
#
# haystack triage --json reports code-review findings, but policy verdicts live
# in haystack pr-status --json. Keep the verdict advisory for loop control while
# making it visible to humans in pr-review-loop.sh summaries.

POLICY_STATUS_AVAILABLE=0
POLICY_REVIEW_REQUIRED=0
POLICY_VERDICT=""
POLICY_ANALYSIS_STATUS=""
POLICY_BUCKET=""
POLICY_RATING=""
POLICY_HAS_REVIEWER=""
POLICY_NEEDS_HUMAN=""
POLICY_DISPOSITION="good-to-merge"

if [ "$PR_STATUS_CHECK" != "0" ]; then
  PR_STATUS_OUTPUT=""
  PR_STATUS_EXIT=0
  PR_STATUS_STDERR="$(mktemp)"
  PR_STATUS_TIMEOUT="$TIMEOUT"
  case "$PR_STATUS_TIMEOUT" in
    ''|0|*[!0-9]*)
      echo "ERROR: internal pr-status timeout '$PR_STATUS_TIMEOUT' is not a positive integer" >&2
      rm -f "$PR_STATUS_STDERR"
      exit 3
      ;;
  esac
  [ "$PR_STATUS_TIMEOUT" -gt 30 ] && PR_STATUS_TIMEOUT=30

  echo "INFO: running: haystack pr-status ${OWNER}/${REPO}#${PR_NUMBER} --json" >&2
  if command -v timeout >/dev/null 2>&1; then
    set +e
    PR_STATUS_OUTPUT="$(timeout "$PR_STATUS_TIMEOUT" haystack pr-status "${OWNER}/${REPO}#${PR_NUMBER}" --json 2>"$PR_STATUS_STDERR")"
    PR_STATUS_EXIT=$?
    set -e
  else
    echo "INFO: 'timeout' command not available; using pr-status background-process fallback" >&2
    set +e
    haystack pr-status "${OWNER}/${REPO}#${PR_NUMBER}" --json >"$PR_STATUS_STDERR.stdout" 2>"$PR_STATUS_STDERR" &
    PR_STATUS_PID=$!
    pr_status_elapsed=0
    while kill -0 "$PR_STATUS_PID" 2>/dev/null && [ "$pr_status_elapsed" -lt "$PR_STATUS_TIMEOUT" ]; do
      sleep 1
      pr_status_elapsed=$((pr_status_elapsed + 1))
    done
    if kill -0 "$PR_STATUS_PID" 2>/dev/null; then
      if ! kill "$PR_STATUS_PID" 2>/dev/null; then
        echo "WARN: failed to terminate timed-out haystack pr-status process $PR_STATUS_PID" >&2
      fi
      wait "$PR_STATUS_PID" 2>/dev/null
      pr_status_wait_exit=$?
      case "$pr_status_wait_exit" in
        0|130|137|143) ;;
        *)
          echo "WARN: haystack pr-status process $PR_STATUS_PID exited with status $pr_status_wait_exit after timeout cleanup" >&2
          ;;
      esac
      PR_STATUS_EXIT=124
    else
      wait "$PR_STATUS_PID" 2>/dev/null
      PR_STATUS_EXIT=$?
      if ! PR_STATUS_OUTPUT="$(cat "$PR_STATUS_STDERR.stdout" 2>/dev/null)"; then
        echo "WARN: failed to read haystack pr-status stdout capture" >&2
        PR_STATUS_OUTPUT=""
      fi
    fi
    set -e
    rm -f "$PR_STATUS_STDERR.stdout"
  fi

  if [ -s "$PR_STATUS_STDERR" ]; then
    echo "INFO: haystack pr-status stderr output:" >&2
    cat "$PR_STATUS_STDERR" >&2
  fi
  rm -f "$PR_STATUS_STDERR"

  if [ "$PR_STATUS_EXIT" -eq 0 ] && printf '%s\n' "$PR_STATUS_OUTPUT" | jq -e . >/dev/null 2>&1; then
    POLICY_PARSE_FAILED=0
    if ! POLICY_BUCKET="$(printf '%s\n' "$PR_STATUS_OUTPUT" | jq -r '.bucket // ""')"; then
      POLICY_PARSE_FAILED=1
    fi
    if ! POLICY_ANALYSIS_STATUS="$(printf '%s\n' "$PR_STATUS_OUTPUT" | jq -r '(.inputs.analysisStatus // .analysisStatus // "") | tostring')"; then
      POLICY_PARSE_FAILED=1
    fi
    if ! POLICY_VERDICT="$(printf '%s\n' "$PR_STATUS_OUTPUT" | jq -r '.inputs.analysisVerdict // .analysisVerdict // ""')"; then
      POLICY_PARSE_FAILED=1
    fi
    if ! POLICY_RATING="$(printf '%s\n' "$PR_STATUS_OUTPUT" | jq -r '(.inputs.haystackRating // .haystackRating // "") | tostring')"; then
      POLICY_PARSE_FAILED=1
    fi
    if ! POLICY_HAS_REVIEWER="$(printf '%s\n' "$PR_STATUS_OUTPUT" | jq -r 'if (.inputs? | type == "object" and has("hasReviewer")) then .inputs.hasReviewer elif has("hasReviewer") then .hasReviewer else "" end | tostring')"; then
      POLICY_PARSE_FAILED=1
    fi
    if ! POLICY_NEEDS_HUMAN="$(printf '%s\n' "$PR_STATUS_OUTPUT" | jq -r '(.inputs.needsHumanReview // .needsHumanReview // false) | tostring')"; then
      POLICY_PARSE_FAILED=1
    fi
    if [ "$POLICY_PARSE_FAILED" -eq 0 ]; then
      POLICY_STATUS_AVAILABLE=1
      case "$POLICY_VERDICT" in
        ''|pass|passed|clean|approved)
          POLICY_VERDICT_REQUIRES_REVIEW=0
          ;;
        *)
          POLICY_VERDICT_REQUIRES_REVIEW=1
          ;;
      esac
      if [ "$POLICY_NEEDS_HUMAN" = "true" ] || [ "$POLICY_VERDICT_REQUIRES_REVIEW" -eq 1 ]; then
        POLICY_REVIEW_REQUIRED=1
      fi
    else
      echo "ERROR: haystack pr-status field parse failed — failing closed" >&2
      printf 'RESULT=needs_fixes\n'
emit_reviewed_head_if_known
      printf 'REASON=policy_status_parse_failed\n'
      printf 'BLOCKING_COUNT=1\n'
      printf 'SUGGESTION_COUNT=%d\n' "$SUGGESTION_COUNT"
      printf 'COMMENT_COUNT=%d\n' "$((SUGGESTION_COUNT + 1))"
      printf 'POLICY_STATUS_AVAILABLE=0\n'
      printf 'POLICY_REVIEW_REQUIRED=0\n'
      printf 'POLICY_DISPOSITION=blocking\n'
      printf 'POLICY_ANALYSIS_STATUS=%s\n' "$POLICY_ANALYSIS_STATUS"
      printf 'POLICY_NEEDS_HUMAN=%s\n' "$POLICY_NEEDS_HUMAN"
      exit 1
    fi
  else
    echo "INFO: haystack pr-status unavailable or invalid — policy verdict not surfaced" >&2
  fi
fi

if [ "$BLOCKING_COUNT" -gt 0 ]; then
  POLICY_DISPOSITION="blocking"
elif [ "$POLICY_REVIEW_REQUIRED" -eq 1 ]; then
  POLICY_DISPOSITION="policy-human-review"
elif [ "$SUGGESTION_COUNT" -gt 0 ]; then
  POLICY_DISPOSITION="advisory-only"
else
  POLICY_DISPOSITION="good-to-merge"
fi

# ── Emit result ───────────────────────────────────────────────────────────────

if [ "$BLOCKING_COUNT" -gt 0 ]; then
  printf 'RESULT=needs_fixes\n'
emit_reviewed_head_if_known
  printf 'BLOCKING_COUNT=%d\n' "$BLOCKING_COUNT"
  printf 'SUGGESTION_COUNT=%d\n' "$SUGGESTION_COUNT"
  printf 'COMMENT_COUNT=%d\n' "$COMMENT_COUNT"
  printf 'POLICY_STATUS_AVAILABLE=%d\n' "$POLICY_STATUS_AVAILABLE"
  printf 'POLICY_REVIEW_REQUIRED=%d\n' "$POLICY_REVIEW_REQUIRED"
  printf 'POLICY_DISPOSITION=%s\n' "$POLICY_DISPOSITION"
  [ -n "$POLICY_VERDICT" ] && printf 'POLICY_VERDICT=%s\n' "$POLICY_VERDICT"
  printf 'POLICY_ANALYSIS_STATUS=%s\n' "$POLICY_ANALYSIS_STATUS"
  [ -n "$POLICY_BUCKET" ] && printf 'POLICY_BUCKET=%s\n' "$POLICY_BUCKET"
  [ -n "$POLICY_RATING" ] && printf 'POLICY_RATING=%s\n' "$POLICY_RATING"
  [ -n "$POLICY_HAS_REVIEWER" ] && printf 'POLICY_HAS_REVIEWER=%s\n' "$POLICY_HAS_REVIEWER"
  printf 'POLICY_NEEDS_HUMAN=%s\n' "$POLICY_NEEDS_HUMAN"
  exit 1
fi

printf 'RESULT=clean\n'
emit_reviewed_head_if_known
printf 'BLOCKING_COUNT=0\n'
printf 'SUGGESTION_COUNT=%d\n' "$SUGGESTION_COUNT"
printf 'COMMENT_COUNT=%d\n' "$COMMENT_COUNT"
printf 'POLICY_STATUS_AVAILABLE=%d\n' "$POLICY_STATUS_AVAILABLE"
printf 'POLICY_REVIEW_REQUIRED=%d\n' "$POLICY_REVIEW_REQUIRED"
printf 'POLICY_DISPOSITION=%s\n' "$POLICY_DISPOSITION"
[ -n "$POLICY_VERDICT" ] && printf 'POLICY_VERDICT=%s\n' "$POLICY_VERDICT"
printf 'POLICY_ANALYSIS_STATUS=%s\n' "$POLICY_ANALYSIS_STATUS"
[ -n "$POLICY_BUCKET" ] && printf 'POLICY_BUCKET=%s\n' "$POLICY_BUCKET"
[ -n "$POLICY_RATING" ] && printf 'POLICY_RATING=%s\n' "$POLICY_RATING"
[ -n "$POLICY_HAS_REVIEWER" ] && printf 'POLICY_HAS_REVIEWER=%s\n' "$POLICY_HAS_REVIEWER"
printf 'POLICY_NEEDS_HUMAN=%s\n' "$POLICY_NEEDS_HUMAN"
[ "$POLICY_REVIEW_REQUIRED" -eq 1 ] && printf 'DISPLAY_RESULT=needs-review: policy\n'
emit_reviewed_head_if_known
exit 0
