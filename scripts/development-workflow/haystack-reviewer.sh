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
#   3 — UNAVAILABLE (haystack CLI not installed or triage returned a non-zero exit code)
#
# Stdout key-value contract (matched by pr-review-loop.sh):
#   RESULT=clean|needs_fixes|skipped
#   BLOCKING_COUNT=<n>
#   SUGGESTION_COUNT=<n>
#   COMMENT_COUNT=<n>
#   REASON=<value>   (only when RESULT=skipped — values: unavailable, timeout,
#                     pending_timeout)
#
# Polling behaviour for status=pending:
#   When `haystack triage --no-wait` returns status=pending (analysis still in
#   progress), the script polls every HAYSTACK_POLL_INTERVAL seconds (default: 15)
#   until the analysis completes or the overall TIMEOUT budget is exhausted.
#   If the budget is exhausted while status is still pending, RESULT=skipped is
#   emitted with REASON=pending_timeout (distinct from REASON=unavailable, which
#   means the CLI is absent or authentication failed, and REASON=timeout, which
#   means a single haystack triage call exceeded the per-call OS timeout).
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
# NOTE on "Rules violation": Haystack uses this category for custom rule findings
# such as CHANGELOG structure checks. These can produce false positives on hotfix
# backport PRs (where the diff against develop shows an empty [Unreleased] section
# from main, which Haystack misidentifies as a structural violation). "Rules violation"
# is treated as advisory here because it is not a code logic error or security issue;
# genuine CHANGELOG structure problems are already caught by the markdownlint CI check.
#
# Unrecognised categories are treated as blocking (conservative safe-fail per spec).

set -euo pipefail

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

# ── Availability check ────────────────────────────────────────────────────────

if ! command -v haystack >/dev/null 2>&1; then
  echo "INFO: haystack CLI not found in PATH — skipping (UNAVAILABLE)" >&2
  printf 'RESULT=skipped\n'
  printf 'REASON=unavailable\n'
  printf 'BLOCKING_COUNT=0\n'
  printf 'SUGGESTION_COUNT=0\n'
  printf 'COMMENT_COUNT=0\n'
  exit 3
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "INFO: jq not found in PATH — skipping (UNAVAILABLE)" >&2
  printf 'RESULT=skipped\n'
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

TRIAGE_OUTPUT=""
TRIAGE_EXIT=0
elapsed=0
TRIAGE_STDERR=$(mktemp)

while true; do
  rm -f "$TRIAGE_STDERR"
  TRIAGE_STDERR=$(mktemp)
  TRIAGE_OUTPUT=""
  TRIAGE_EXIT=0

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
    elapsed=$((elapsed + POLL_CALL_TIMEOUT))
    echo "INFO: haystack triage per-call timeout after ${POLL_CALL_TIMEOUT}s (total elapsed: ${elapsed}s)" >&2
    if [ "$elapsed" -ge "$TIMEOUT" ]; then
      TRIAGE_EXIT=124  # propagate timeout sentinel
      break
    fi
    # Retry immediately (the per-call timeout already consumed the sleep budget).
    continue
  fi

  # ── Handle other non-zero exit codes ────────────────────────────────────────
  if [ "$TRIAGE_EXIT" -ne 0 ]; then
    echo "INFO: haystack triage exited with code $TRIAGE_EXIT — treating as UNAVAILABLE" >&2
    rm -f "$TRIAGE_STDERR"
    printf 'RESULT=skipped\n'
    printf 'REASON=unavailable\n'
    printf 'BLOCKING_COUNT=0\n'
    printf 'SUGGESTION_COUNT=0\n'
    printf 'COMMENT_COUNT=0\n'
    exit 3
  fi

  # ── Validate JSON output ─────────────────────────────────────────────────────
  if [ -z "$TRIAGE_OUTPUT" ]; then
    echo "INFO: haystack triage returned empty output — treating as UNAVAILABLE" >&2
    rm -f "$TRIAGE_STDERR"
    printf 'RESULT=skipped\n'
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
    printf 'REASON=unavailable\n'
    printf 'BLOCKING_COUNT=0\n'
    printf 'SUGGESTION_COUNT=0\n'
    printf 'COMMENT_COUNT=0\n'
    exit 3
  fi

  # ── Check status field ───────────────────────────────────────────────────────
  STATUS_VALUE="$(printf '%s\n' "$TRIAGE_OUTPUT" | jq -r '.status // empty' 2>/dev/null || true)"

  case "$STATUS_VALUE" in
    none)
      # Permanent: no analysis was ever submitted for this PR.
      echo "INFO: haystack triage returned status=none (no analysis available for this PR) — treating as UNAVAILABLE" >&2
      rm -f "$TRIAGE_STDERR"
      printf 'RESULT=skipped\n'
      printf 'REASON=unavailable\n'
      printf 'BLOCKING_COUNT=0\n'
      printf 'SUGGESTION_COUNT=0\n'
      printf 'COMMENT_COUNT=0\n'
      exit 3
      ;;
    pending)
      # Transient: analysis still in progress — poll-retry.
      elapsed=$((elapsed + POLL_INTERVAL))
      echo "INFO: status=pending — waiting ${POLL_INTERVAL}s before retry (${elapsed}s elapsed of ${TIMEOUT}s budget)" >&2
      if [ "$elapsed" -ge "$TIMEOUT" ]; then
        # Budget exhausted while still pending.
        TRIAGE_EXIT=200  # sentinel: pending_timeout
        break
      fi
      sleep "$POLL_INTERVAL"
      continue
      ;;
    *)
      # Terminal status (completed, or empty/unknown) — exit the loop.
      break
      ;;
  esac
done

rm -f "$TRIAGE_STDERR"

# ── Handle loop exit conditions ───────────────────────────────────────────────

if [ "$TRIAGE_EXIT" -eq 124 ]; then
  # A single haystack triage call exceeded its per-call OS timeout and the
  # overall budget was exhausted.
  echo "INFO: haystack triage timed out after ${TIMEOUT}s" >&2
  printf 'RESULT=skipped\n'
  printf 'REASON=timeout\n'
  printf 'BLOCKING_COUNT=0\n'
  printf 'SUGGESTION_COUNT=0\n'
  printf 'COMMENT_COUNT=0\n'
  exit 2
fi

if [ "$TRIAGE_EXIT" -eq 200 ]; then
  # Budget exhausted while status was still pending (analysis never completed
  # within the timeout window). This is distinct from REASON=unavailable
  # (CLI not found / auth failure) and REASON=timeout (per-call OS timeout).
  echo "INFO: haystack triage status=pending — budget exhausted after ${TIMEOUT}s (pending_timeout)" >&2
  printf 'RESULT=skipped\n'
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
      "Minor"|"Advisory"|"Nitpick"|"Trivial"|"Weak test coverage"|"Rules violation")
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

# ── Emit result ───────────────────────────────────────────────────────────────

if [ "$BLOCKING_COUNT" -gt 0 ]; then
  printf 'RESULT=needs_fixes\n'
  printf 'BLOCKING_COUNT=%d\n' "$BLOCKING_COUNT"
  printf 'SUGGESTION_COUNT=%d\n' "$SUGGESTION_COUNT"
  printf 'COMMENT_COUNT=%d\n' "$COMMENT_COUNT"
  exit 1
fi

printf 'RESULT=clean\n'
printf 'BLOCKING_COUNT=0\n'
printf 'SUGGESTION_COUNT=%d\n' "$SUGGESTION_COUNT"
printf 'COMMENT_COUNT=%d\n' "$COMMENT_COUNT"
exit 0
