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
#   --pre-trigger-wait <seconds> Seconds to wait for existing current-head Codex
#                                evidence before posting a trigger. Default: 60
#                                Set to 0 to skip the pre-trigger check.
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
#   2. Whole-body exact template match → APPROVED (exit 0)
#      The entire, untruncated response — whitespace-normalized, nothing
#      truncated or discarded — must reproduce, character for character, one
#      of the small set of clean-response templates in
#      CODEX_APPROVED_TEMPLATES (captured verbatim from real Codex responses,
#      each including the complete vendor <details> "About Codex in GitHub"
#      footer). There is no vocabulary list, no grammar, and no
#      case-insensitive or punctuation-tolerant matching — see
#      codex_response_is_approved below and issue #1491's implementation plan
#      (Decisions 1, 2, 5) for the full rationale. Only a submitted review
#      pinned to the current head, or a root PR comment that names the
#      current head in a Reviewed commit marker (terminal evidence), is ever
#      tested against this match. Other Codex root PR comments and
#      thumbs-up reactions are acknowledgements only; they are not SHA-pinned
#      review evidence and must not approve the PR by themselves.
#   3. Neither found, and evidence is terminal → safe-fails to NEEDS_REVISION
#      (exit 1). A bare acknowledgement comment on NON-terminal evidence
#      instead causes the poll loop to keep waiting for real evidence — this
#      wait is gated on the evidence being non-terminal (Decision 6), so a
#      footer-bearing near-miss on genuinely terminal evidence always
#      safe-fails rather than being misrouted to a wait/timeout.
#
# Response source detection (two sources polled each cycle):
#   - issues/{PR}/comments — plain PR comments; matches both BOT_LOGIN and
#     BOT_LOGIN_PLAIN (login without [bot] suffix). Codex posts "clean" results
#     here from the non-[bot] account (e.g. "chatgpt-codex-connector").
#   - pulls/{PR}/reviews   — GitHub Review objects; matches both logins. Codex
#     posts findings here from the [bot]-suffixed account. Only submitted
#     reviews whose commit_id exactly matches the full current head SHA are
#     considered.
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
  echo "Usage: $0 <pr_number> <owner> <repo> [--trigger-phrase <phrase>] [--bot-login <login>] [--poll-interval <seconds>] [--max-wait <seconds>] [--pre-trigger-wait <seconds>] [--max-retriggers <count>]" >&2
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
PRE_TRIGGER_WAIT="${CODEX_GITHUB_PRE_TRIGGER_WAIT:-60}"
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
    --pre-trigger-wait)
      if [ $# -lt 2 ]; then echo "ERROR: --pre-trigger-wait requires a value" >&2; exit 2; fi
      PRE_TRIGGER_WAIT="$2"; shift 2;;
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
# PRE_TRIGGER_WAIT may be 0 (skip the pre-trigger check) but must be non-negative.
case "$PRE_TRIGGER_WAIT" in
  ''|*[!0-9]*)
    echo "ERROR: --pre-trigger-wait value '$PRE_TRIGGER_WAIT' is not a non-negative integer (must be >= 0)" >&2
    exit 2
    ;;
esac
PRE_TRIGGER_WAIT=$((10#$PRE_TRIGGER_WAIT))
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

if ! CURRENT_SHA_FULL=$(gh pr view "$PR_NUMBER" --repo "$OWNER/$REPO" --json headRefOid --jq '.headRefOid' | head -c 100); then
  echo "ERROR: could not resolve PR #$PR_NUMBER HEAD SHA" >&2
  echo "VERDICT: TIMED_OUT — could not resolve PR HEAD SHA (treated as unavailable)"
  exit 2
fi
CURRENT_SHA_FULL=$(printf '%s' "$CURRENT_SHA_FULL" | tr -d '\n' | cut -c1-40)
CURRENT_SHA=$(printf '%s' "$CURRENT_SHA_FULL" | cut -c1-12)
if [ -z "$CURRENT_SHA_FULL" ]; then
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
echo "INFO: Pre-trigger wait: ${PRE_TRIGGER_WAIT}s"

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
    | jq -sr --arg bot "$BOT_LOGIN" --arg bot_plain "$BOT_LOGIN_PLAIN" --arg trigger_time "$trigger_time" --arg sha "$CURRENT_SHA_FULL" \
      '(add // []) | [.[] | select((.user.login == $bot or .user.login == $bot_plain) and .created_at >= $trigger_time and ((.commit_id // "") == $sha))] | length' \
    > "$review_comment_tmpfile"; then
    cat "$review_comment_tmpfile"
  else
    rm -f "$review_comment_tmpfile"
    echo "ERROR: failed to fetch or parse Codex inline review comments" >&2
    return 3
  fi
  rm -f "$review_comment_tmpfile"
}

codex_unresolved_review_thread_count() {
  local thread_tmpfile thread_stderr cursor page max_pages count page_count has_next end_cursor
  thread_tmpfile=$(mktemp)
  thread_stderr=$(mktemp)
  cursor=""
  page=0
  max_pages=20
  count=0
  while :; do
    page=$((page + 1))
    if [ "$page" -gt "$max_pages" ]; then
      rm -f "$thread_tmpfile" "$thread_stderr"
      echo "ERROR: existing Codex review thread scan exceeded $max_pages pages" >&2
      return 3
    fi
    : > "$thread_stderr"
    if ! gh api graphql \
      -f owner="$OWNER" \
      -f repo="$REPO" \
      -F number="$PR_NUMBER" \
      -f cursor="$cursor" \
      -f query='query($owner:String!, $repo:String!, $number:Int!, $cursor:String) {
        repository(owner:$owner, name:$repo) {
          pullRequest(number:$number) {
            headRef {
              target {
                ... on Commit { committedDate }
              }
            }
            reviewThreads(first:100, after:$cursor) {
              pageInfo { hasNextPage endCursor }
              nodes {
                isResolved
                isOutdated
                firstComment: comments(first:1) {
                  nodes {
                    author { login }
                  }
                }
                lastComment: comments(last:1) {
                  nodes {
                    author { login }
                    createdAt
                  }
                }
              }
            }
          }
        }
      }' 2>"$thread_stderr" \
      | jq -r --arg bot "$BOT_LOGIN" --arg bot_plain "$BOT_LOGIN_PLAIN" '
          .data.repository.pullRequest as $pr
          | ($pr.headRef.target.committedDate // "") as $head_date
          | ($pr.reviewThreads.pageInfo.hasNextPage // false) as $has_next
          | ($pr.reviewThreads.pageInfo.endCursor // "") as $end_cursor
          | ([
              $pr.reviewThreads.nodes[]?
              | (.firstComment.nodes[0].author.login // "") as $first_author
              | (.lastComment.nodes[0].author.login // "") as $last_author
              | (.lastComment.nodes[0].createdAt // "") as $last_created
              | select((.isResolved // false) == false)
              | select((.isOutdated // false) == false)
              | select($first_author == $bot or $first_author == $bot_plain)
              | select((($head_date != "") and ($last_author != $bot) and ($last_author != $bot_plain) and ($last_created > $head_date)) | not)
            ] | length) as $count
          | [$count, $has_next, $end_cursor] | @tsv' \
      > "$thread_tmpfile"; then
      local thread_err
      thread_err=$(cat "$thread_stderr")
      rm -f "$thread_tmpfile" "$thread_stderr"
      echo "ERROR: failed to fetch or parse existing Codex review threads: $thread_err" >&2
      return 3
    fi
    IFS=$'\t' read -r page_count has_next end_cursor < "$thread_tmpfile"
    count=$((count + page_count))
    if [ "$has_next" != "true" ]; then
      break
    fi
    if [ -z "$end_cursor" ]; then
      rm -f "$thread_tmpfile" "$thread_stderr"
      echo "ERROR: existing Codex review thread scan had hasNextPage=true without endCursor" >&2
      return 3
    fi
    cursor="$end_cursor"
  done
  printf '%s\n' "$count"
  rm -f "$thread_tmpfile" "$thread_stderr"
}

# All classification helpers below match against the response via a
# here-string (`<<<`), not a piped `printf`. A here-string is written to a
# temp file/buffer by the shell BEFORE the command starts reading, so a
# `grep -q` match that closes its input early (as soon as it finds a
# match, per POSIX/GNU semantics) can never cause the writer side to
# receive SIGPIPE — unlike `printf | grep -q`, where an early match on a
# response large enough to require multiple pipe writes can SIGPIPE the
# still-writing printf. This matters once classification runs on the
# FULL, untruncated response (see BOT_RESPONSE_FULL below) rather than a
# pre-truncated copy.

# Returns true if the response contains a fence-opener marker (2+
# consecutive backticks, or 3+ consecutive tildes) ANYWHERE. Used by
# codex_response_is_usage_limit and codex_response_is_environment_error
# below as a conservative guard (no longer by codex_response_is_approved,
# which — since issue #1491's conservative-verdict-classifier redesign,
# Decision 1 — is a whole-body exact-template match with no fence-presence
# check of its own; a fence character inside the body is just extra text
# that already breaks the exact match): a genuine SHA-pinned clean review
# can QUOTE example text inside a fenced block (e.g. demonstrating what a
# usage-limit notice looks like) without that text being a genuine
# assertion, and after 5 rounds of precisely parsing GFM's fence-open/
# close semantics repeatedly surfaced the next undiscovered edge case
# (see codex_strip_quoted_spans below), the project's chosen direction is
# to stop trying to determine what's inside vs. outside a fence and
# instead treat the mere PRESENCE of a fence marker as disqualifying for
# any of these positive/actionable classifications. This was initially
# added only to codex_response_is_approved, but the SAME ambiguity
# applies equally to usage-limit and environment-error detection — a
# fenced example that merely QUOTES quota/setup-error wording must not
# trigger an actual UNAVAILABLE verdict for an otherwise clean review
# (fresh evidence from PR #1490 finding 3796042503, a followup to
# 3795661290: the fence guard was added to codex_response_is_approved
# alone, but codex_response_is_usage_limit's own callers were unguarded,
# so fenced quota text still triggered a false UNAVAILABLE for a clean
# review). Embedding this check INSIDE each shared classifier — rather
# than requiring every call site to remember to apply it — is deliberate:
# scattering the guard across call sites is exactly the pattern that
# produced this gap in the first place (codex_response_is_blocking
# learned the same lesson earlier for quote-stripping, PR #1490 finding
# 3793367887).
#
# The backtick threshold was lowered from 3+ to 2+ after
# codex_strip_quoted_spans' naive `[^\`]*` backtick-pair regex was found
# to mishandle CommonMark's actual delimiter-run matching: a code span
# CAN be delimited by a run of 2+ backticks (not just a single pair), and
# the opening/closing runs must be equal length — but the naive regex
# treats an adjacent 2-backtick run as two separate EMPTY single-backtick
# pairs (each backtick immediately "closes" against its neighbor with
# zero content between), stripping only the empty delimiter pairs
# themselves and leaving the actual enclosed content fully exposed (e.g.
# a double-backtick-quoted `` `` No blocking issues found `` `` survived
# stripping intact and matched CODEX_APPROVAL_PATTERN, fresh evidence
# from PR #1490 finding 3798756834). Rather than write CommonMark-
# compliant delimiter-run matching in regex (not realistically
# expressible as a plain substitution), a 2+-backtick run now disqualifies
# the same way a 3+ run always has — single backtick PAIRS (exactly one
# backtick on each side, still extremely common in genuinely clean review
# comments) are unaffected and still get precise stripping via
# codex_strip_quoted_spans. Tildes are NOT lowered to 2+: GFM only uses
# tildes for FENCED code blocks (3+ required), never for inline code
# spans, so a lower tilde threshold would have no corresponding real gap
# to close.
codex_response_has_fence_marker() {
  local response="$1"
  grep -qE '(`{2,}|~{3,})' <<< "$response"
}

codex_response_is_usage_limit() {
  local response="$1"
  if codex_response_has_fence_marker "$response"; then
    return 1
  fi
  # The third alternative previously matched ANY "codex ... usage
  # limit/quota/capacity" substring with no requirement for accompanying
  # exhaustion/unavailability wording, so a clean submitted review merely
  # discussing this PR's own usage-limit-detection code (e.g. "No blocking
  # issues found. The Codex usage limit handling looks correct.") was
  # itself misclassified as a usage-limit notice (fresh evidence from PR
  # #1490 finding 3789928781). It now requires an exhaustion/unavailability
  # word directly after the noun, mirroring the structure already used by
  # the fourth alternative ("capacity exhausted/unavailable/limited"). The
  # second alternative ("codex usage limits for code reviews") had the
  # exact same unguarded-mention gap — e.g. "No blocking issues found. The
  # docs correctly explain Codex usage limits for code reviews." — missed
  # in the first pass since only the third alternative was narrowed then;
  # it now requires an exhaustion word after "code reviews" too (fresh
  # evidence from PR #1490 finding 3789958776, a followup to 3789928781).
  # The real "reached your ... limits for code reviews" phrasing remains
  # covered by the first alternative regardless of this narrowing.
  grep -qiE "(reached[[:space:]]+your[[:space:]]+codex[[:space:]]+usage[[:space:]]+limits?|codex[[:space:]]+usage[[:space:]]+limits?[[:space:]]+for[[:space:]]+code[[:space:]]+reviews?[[:space:]]+(reached|exceeded|exhausted|hit|unavailable|limited)|codex[[:space:]]+(github[[:space:]]+app[[:space:]]+)?(review[[:space:]]+)?(usage[[:space:]]+limit|quota|capacity)[[:space:]]+(reached|exceeded|exhausted|hit|unavailable|limited)|codex[[:space:]]+review[[:space:]]+capacity[[:space:]]+(exhausted|unavailable|limited))" <<< "$response"
}

codex_response_is_environment_error() {
  local response="$1"
  if codex_response_has_fence_marker "$response"; then
    return 1
  fi
  grep -qiE "to[[:space:]]+use[[:space:]]+codex[[:space:]]+here,[[:space:]]+create[[:space:]]+an[[:space:]]+environment[[:space:]]+for[[:space:]]+this[[:space:]]+repo" <<< "$response"
}

# codex_response_is_account_not_connected <response>
# The Codex GitHub App refuses with an account-connection prompt when the
# triggering GitHub identity has no linked Codex account (Codex attributes
# reviews per triggering identity, so an org-wide install can work for one
# developer and refuse for another). That is reviewer unavailability, not a
# code-review finding (#1522) — without this it fell to the safe-fail
# NEEDS_REVISION path and reported a blocking finding with nothing to fix.
# Fence-guarded and quote-stripped by the caller, like the usage-limit check,
# so a review that merely quotes the refusal text is not misclassified.
codex_response_is_account_not_connected() {
  local response="$1"
  if codex_response_has_fence_marker "$response"; then
    return 1
  fi
  grep -qiE "to[[:space:]]+use[[:space:]]+codex[[:space:]]+here,[[:space:]]+(\[)?create[[:space:]]+a[[:space:]]+codex[[:space:]]+account[[:space:]]+and[[:space:]]+connect" <<< "$response"
}

codex_response_reviews_current_head() {
  local response="$1"
  local reviewed_sha
  reviewed_sha=$(sed -n 's/.*Reviewed commit:[^`]*`\([0-9a-fA-F]\{7,40\}\)`.*/\1/p' <<< "$response" | tail -n 1)
  [ -n "$reviewed_sha" ] && { grep -qi "^$reviewed_sha" <<< "$CURRENT_SHA" || grep -qi "^$CURRENT_SHA" <<< "$reviewed_sha"; }
}

# Blocking/approval marker patterns, centralized so every classification site
# (main poll, async grace, async-final, async-reaction-final) uses the exact
# same rules. See "Verdict parsing" header comment for the rationale behind
# each marker.
#
# Explicit merge-refusal verdicts (e.g. "should not be merged", "do not
# merge", "cannot be merged") are a separate signal the negated-approval
# mechanism below (CODEX_NEGATED_APPROVAL_PATTERN) cannot catch: that
# mechanism only fires when a negation word is followed by one of a
# fixed list of approval-vocabulary target words (approve[ds]?, lgtm,
# looks good, etc.) within the same sentence, but a response like "This
# looks good at first glance, but this should not be merged until tests
# pass." negates "merged" — a word outside that target list entirely —
# so the negated-approval check never matches and the earlier "looks
# good" phrase alone wins, returning APPROVED. This was FIRST fixed by
# manually enumerating one phrasing at a time directly in
# CODEX_BLOCKING_PATTERN — "(should|must) not be merged" (fresh evidence
# from PR #1490 finding 3798880969), then "do not merge"/"don't merge"
# (finding 3798999561) — and each fix immediately surfaced the next
# unenumerated synonym ("cannot be merged", finding 3799159335),
# confirming this is the SAME kind of open-ended-vocabulary problem
# CODEX_NEGATED_APPROVAL_PATTERN already solved by construction rather
# than by enumeration. CODEX_MERGE_REFUSAL_PATTERN below reuses
# CODEX_NEGATION_WORDS (defined further down) the same way
# CODEX_NEGATED_APPROVAL_PATTERN does, against a "merge(d)" target,
# so any negation word already known to this file — including future
# additions to CODEX_NEGATION_WORDS — automatically covers merge
# refusals too, without needing its own one-off enumeration. Checked
# here, in CODEX_BLOCKING_PATTERN (evaluated first in the
# verdict-parsing chain, before approval), an explicit refusal to merge
# is recognized as blocking outright regardless of what an earlier
# hedge phrase in the same response says.
CODEX_BLOCKING_PATTERN='(changes[[:space:]]+requested|blocking[[:space:]]+issues?[[:space:]]*:|blocking[[:space:]]+finding|blocking:|must[[:space:]]+fix|action[[:space:]]+required|required:|❌)'
# CODEX_APPROVAL_PATTERN, CODEX_NEGATED_APPROVAL_TARGET_WORDS, and
# CODEX_NEGATED_APPROVAL_PATTERN (the open-ended approval-vocabulary and
# negated-approval-vocabulary enumerations that used to live here) are
# deleted outright, not narrowed further — issue #1491's implementation
# plan (Decisions 1, 2) replaces this entire class of open-ended-vocabulary
# matching with codex_response_is_approved's whole-body exact-template
# match below, which has no vocabulary of its own to enumerate gaps in.
# CODEX_NEGATION_WORDS (below) is kept — CODEX_MERGE_REFUSAL_PATTERN, part
# of CODEX_BLOCKING_PATTERN above, still depends on it, and
# codex_response_is_blocking's failure direction (a false negative there
# is unsafe) means it keeps its own block-list unchanged (Decision 4).
# Proactive sweep of the remaining common English negation forms not yet
# covered (was/were/would/has/have/had, contracted and space-separated),
# added in one pass after four consecutive findings each surfaced one
# more missing modal-verb negation one at a time (don't, should/mustn't,
# and finally wouldn't — fresh evidence from PR #1490 finding 3799391883
# — prompted this sweep rather than continuing to fix them one at a
# time). "did not"/"didn't" is DELIBERATELY excluded despite being an
# equally common negation form: "didn't find any major issues" is itself
# a clean-signal phrase, not something to negate, so folding bare
# "didn.t" into this list would make CODEX_MERGE_REFUSAL_PATTERN below
# false-positive-match a genuinely clean, unpunctuated sentence like
# "Codex didn't find any major issues that would block this from being
# merged." (the "didn't" and "merge" fall in the same clause, with no
# sentence terminator or comma between them to stop the match). This
# exclusion originally protected the now-deleted negated-approval
# pattern (issue #1491's implementation plan, Decision 2: the
# open-ended approval/negated-approval vocabulary this constant used to
# feed was replaced by codex_response_is_approved's whole-body
# exact-template match) — it is kept here because CODEX_NEGATION_WORDS'
# one remaining consumer, CODEX_MERGE_REFUSAL_PATTERN, has the exact
# same "didn't find any major issues" adjacency risk. Caught and
# reverted during this sweep's own verification before ever being
# committed; left undocumented here it would be an easy trap for a
# future sweep to re-introduce.
CODEX_NEGATION_WORDS='(not|isn.t|is[[:space:]]+not|are[[:space:]]+not|aren.t|was[[:space:]]+not|wasn.t|were[[:space:]]+not|weren.t|cannot|can.t|could[[:space:]]+not|couldn.t|will[[:space:]]+not|won.t|would[[:space:]]+not|wouldn.t|does[[:space:]]+not|doesn.t|do[[:space:]]+not|don.t|has[[:space:]]+not|hasn.t|have[[:space:]]+not|haven.t|had[[:space:]]+not|hadn.t|should[[:space:]]+not|shouldn.t|must[[:space:]]+not|mustn.t|never|unable[[:space:]]+to)'
# Any CODEX_NEGATION_WORDS alternative, followed within the same clause
# by "merge"/"merged" (with or without an intervening "be"), is treated
# as an explicit merge-refusal verdict — see the comment above
# CODEX_BLOCKING_PATTERN for why this is built by reusing the negation
# vocabulary rather than enumerating merge-refusal phrasings one at a
# time. Appended to CODEX_BLOCKING_PATTERN below (not folded into its
# own literal above) because it depends on CODEX_NEGATION_WORDS, which
# must be defined first.
CODEX_MERGE_REFUSAL_PATTERN="${CODEX_NEGATION_WORDS}[^.!?;,]*(be[[:space:]]+)?merged?"
CODEX_BLOCKING_PATTERN="${CODEX_BLOCKING_PATTERN%)}|${CODEX_MERGE_REFUSAL_PATTERN})"

# Strips quoted spans — text between a pair of straight double-quotes
# ("...") AND text between a pair of backticks (`...`, Markdown inline
# code) — used by codex_response_is_blocking below (no longer by
# codex_response_is_approved, which — since issue #1491's
# conservative-verdict-classifier redesign, Decision 1 — is a whole-body
# exact-template match with no quote-stripping step of its own), never
# applied to the body before codex_response_reviews_current_
# head's SHA extraction (which itself relies on backtick-delimited
# `Reviewed commit:` markers and must see the original, unstripped body).
# A SHA-pinned review can QUOTE a clean OR blocking phrase, in either
# quoting style, while discussing (not asserting) it — e.g. `The
# documented bot response "No blocking issues found" is inaccurate` or
# `No blocking issues found. The tests correctly cover the "must fix"
# marker.` — and CODEX_APPROVAL_PATTERN, CODEX_NEGATED_APPROVAL_PATTERN,
# and CODEX_BLOCKING_PATTERN's substring matches can't distinguish
# quotation/discussion of a phrase from an assertion of it (fresh
# evidence from PR #1490 findings 3790122058 and 3793219190 —
# straight-quote and backtick-quote versions of the approval gap —
# 3793219192, which found that only the POSITIVE check was quote-stripped
# and a quoted REJECTION phrase still tripped the NEGATION check on the
# unstripped body — and 3793367887, which found that
# codex_response_is_blocking wasn't quote-stripped at all, so a quoted
# blocker token in an otherwise clean review still rejected it). Also
# strips GitHub-flavored Markdown blockquote LINES (a line starting with
# `>`, optionally indented): a review discussing a quoted clean phrase via
# blockquote syntax rather than straight/backtick quotes was likewise
# unprotected (fresh evidence from PR #1490 finding 3793367885). Also
# strips single-quoted spans ('...') — the fourth quoting style found
# unprotected after straight-quote, backtick, and blockquote (fresh
# evidence from PR #1490 finding 3793410331). Single quotes need a
# stricter boundary than the other three styles: a bare `'[^']*'` would
# also match the space between two UNRELATED apostrophes in contractions
# (e.g. "isn't approved, but it's fine" — a naive strip would treat the
# apostrophe in "isn't" and the apostrophe in "it's" as an opening/closing
# pair and delete everything between them, including "approved"). The
# opening quote is required to be preceded by whitespace-or-start-of-line
# and the closing quote by whitespace/punctuation-or-end, which a
# contraction's apostrophe never satisfies (the letters on both sides of
# it are word characters, not whitespace), so genuine quotation is
# distinguished from an apostrophe embedded in a word.
#
# Fenced Markdown code blocks (```...``` or ~~~...~~~) are deliberately
# NOT precisely parsed here, unlike the single-line constructs above.
# Four consecutive rounds of chasing GitHub-flavored Markdown's fence
# semantics — detecting a fence at all, tracking the opening delimiter's
# LENGTH (a longer outer fence can safely contain a shorter inner one),
# requiring a closing delimiter to be followed by nothing but whitespace,
# and finally discovering GFM's entirely separate TILDE-delimited fence
# syntax that a backtick-only implementation missed altogether — kept
# producing one more undiscovered edge case each round (PR #1490 findings
# 3793453010, 3793497787, a closing-validity followup, and 3795661290).
# Rather than continue precisely re-implementing GFM's fence grammar one
# construct at a time, codex_response_has_fence_marker above (used by
# codex_response_is_usage_limit and codex_response_is_environment_error;
# no longer by codex_response_is_approved as of issue #1491's
# conservative-verdict-classifier redesign, Decision 1) now treats the
# mere PRESENCE of a fence-opener marker (3+ consecutive backticks or
# tildes) ANYWHERE in the response as disqualifying, without attempting
# to determine where it opens or closes. This is a deliberate, explicit
# tradeoff: a small amount of
# false-NEEDS_REVISION risk (a genuinely clean response that happens to
# include an example code fence) in exchange for closing the entire class
# of "quoted/fenced clean phrase misread as an assertion" bug in one
# step, rather than the
# previous direction of chasing precision at the cost of repeated
# false-APPROVED gaps. Single/inline backticks (a PAIR on one line, not a
# 3+-run) are unaffected by this and still get the precise, stable
# stripping below — only multi-backtick/tilde FENCE markers trigger the
# conservative bail-out, since inline code references (e.g. `` `foo.py` ``)
# are extremely common in genuinely clean review comments and haven't
# shown this same repeated-edge-case pattern.
codex_strip_quoted_spans() {
  local body="$1"
  local sq="'"
  # Blockquote lines are deleted first, line-oriented, by definition — a
  # GFM blockquote marker only means anything at the start of a line.
  local no_blockquotes
  no_blockquotes=$(sed -E '/^[[:space:]]*>/d' <<< "$body")
  # Double-quote, single-quote, AND backtick code-span pairs can all
  # legitimately span a newline: a bot can quote multi-line text inside
  # one straight-quote pair (e.g. `The documented response "\nNo blocking
  # issues found\n" is inaccurate`), and — corrected here — CommonMark/GFM
  # inline code spans are NOT line-bound the way this function previously
  # assumed; a code span's contents can include line endings, which are
  # normalized to spaces in the rendered output (the earlier "an inline
  # code span never crosses a line" comment on the backtick pass was
  # simply wrong, per fresh evidence from PR #1490 finding 3798665086 —
  # only FENCED, triple-backtick blocks have line-anchored open/close
  # semantics; that is a different construct from a single/paired-backtick
  # inline code span). sed's substitution operates per-line by default
  # (each line is its own pattern space), so any of these three pair
  # styles split across two lines was never stripped at all, letting the
  # quoted/coded clean phrase reach classification unstripped and return
  # APPROVED (fresh evidence from PR #1490 findings 3797334339 and
  # 3798665086). Newlines are swapped for a control-character placeholder
  # before all three substitutions — collapsing the body to one sed
  # "line" so `[^"]*`/`[^\`]*`/`[^']*` can match across what were
  # originally separate lines — then restored immediately after.
  #
  # The single-quote pattern's boundary alternatives ((^|[[:space:]]) and
  # ([[:space:].,;:!?]|$)) also need the placeholder added explicitly: a
  # single-quoted span occupying an ENTIRE original line by itself (e.g.
  # `The documented response is:` / `'No blocking issues found'` / `That
  # claim is inaccurate` across three lines) has the placeholder — not
  # real whitespace and not true start/end-of-string — immediately before
  # and after the quote once flattened, so neither boundary alternative
  # matched and the span survived unstripped (fresh evidence from PR
  # #1490 finding 3798665078). The placeholder itself is a legitimate
  # word-break in the original text (it stands in for a real newline), so
  # treating it as an additional boundary character is correct, not a
  # workaround.
  local nl_placeholder=$'\x01'
  local flattened stripped
  flattened=$(printf '%s' "$no_blockquotes" | tr '\n' "$nl_placeholder")
  stripped=$(sed -E "s/\"[^\"]*\"//g; s/\`[^\`]*\`//g; s/(^|[[:space:]]|${nl_placeholder})${sq}[^${sq}]*${sq}([[:space:].,;:!?]|${nl_placeholder}|\$)/\\1\\2/g" <<< "$flattened")
  printf '%s' "$stripped" | tr "$nl_placeholder" '\n'
}

codex_response_is_blocking() {
  local body="$1"
  # UNLIKE the other three classifiers, this one deliberately does NOT
  # bail out on codex_response_has_fence_marker: a false NEGATIVE here is
  # NOT safe the way it is for usage-limit/environment-error/approved. A
  # genuinely asserted blocking finding OUTSIDE a fence, in a review that
  # also happens to contain an unrelated fenced code example elsewhere,
  # must still be detected — Protocol 93 requires blocking terminal/
  # review evidence to always win outright over other evidence (e.g. a
  # same-fetch usage-limit notice), and codex_combine_terminal_evidence's
  # "blocking always wins" check depends on this function correctly
  # reporting TRUE for such a review. Bailing out here on fence presence
  # briefly broke that invariant: a real blocker got silently overridden
  # by a later ancillary notice because is_blocking incorrectly reported
  # FALSE (fresh evidence from PR #1490 finding 3796396399, a regression
  # introduced by finding 3796042503's "apply the guard everywhere for
  # consistency" fix — consistency across all four classifiers was the
  # wrong call for this one, since a blocking false-negative and an
  # approval/quota false-positive are not symmetric risks). A blocking
  # false POSITIVE on quoted/fenced text remains safe on its own (it only
  # pushes toward NEEDS_REVISION), so no fence guard is needed here for
  # that direction either — codex_strip_quoted_spans' straight-quote/
  # backtick-pair/blockquote/single-quote stripping is enough.
  #
  # codex_strip_not_only_idiom is also applied here now: CODEX_BLOCKING_
  # PATTERN's generalized merge-refusal alternative
  # (CODEX_MERGE_REFUSAL_PATTERN) reuses CODEX_NEGATION_WORDS' bare "not"
  # alternative the same way CODEX_NEGATED_APPROVAL_PATTERN does, so it
  # inherits the exact same "not only X" affirmative-idiom
  # misclassification that motivated codex_strip_not_only_idiom in the
  # first place — a clean response like "This is not only safe to merge
  # but looks good" has "not" followed by "merge" within the same clause
  # and was misread as a merge refusal, returning NEEDS_REVISION for a
  # genuinely clean review (fresh evidence from PR #1490 finding
  # 3799277922). This is a false POSITIVE (pushes toward the safe
  # NEEDS_REVISION direction, never toward incorrectly APPROVED), unlike
  # every other gap fixed in this function, but is still worth closing
  # since needlessly blocking a clean review triggers an unnecessary fix
  # cycle.
  local normalized_body
  normalized_body=$(codex_strip_not_only_idiom "$(codex_strip_quoted_spans "$body")")
  grep -qiE "$CODEX_BLOCKING_PATTERN" <<< "$normalized_body"
}

# Strips the "not only X" idiom — used by codex_response_is_blocking
# below (originally added for the old codex_response_is_approved only;
# no longer called there since issue #1491's conservative-verdict-
# classifier redesign, Decision 1, replaced that function with a
# whole-body exact-template match that performs no prose normalization
# of any kind — see codex_response_is_blocking's own comment for why the
# blocking classifier needed this idiom-stripping too once its
# merge-refusal pattern started reusing CODEX_NEGATION_WORDS' bare "not"
# alternative). "Not only X, (but) Y" is
# an AFFIRMATIVE intensifier construction (BOTH X and Y are being
# asserted, not negated: "Not only does this look good, it is approved"
# means both "looks good" and "is approved" hold), not a negation of X,
# so CODEX_NEGATION_WORDS' bare "not" alternative — which has no way to
# distinguish this idiom from a genuine negation — misclassified it as
# negated (fresh evidence from PR #1490 finding 3793299512). Stripped
# entirely (not just skipped) so the leftover "not" cannot accidentally
# trigger a match against some OTHER target word later in the same
# clause. Every letter is bracket-expanded for both cases (rather than
# relying on sed's `I` substitution flag, whose support varies across sed
# implementations), since the original [Nn]ot/[Oo]nly form only covered
# Title-Case and lowercase, not a fully uppercase emphasis form like "NOT
# ONLY" (fresh evidence from PR #1490 finding 3793330278, a followup to
# 3793299512).
codex_strip_not_only_idiom() {
  local body="$1"
  sed -E 's/[Nn][Oo][Tt][[:space:]]+[Oo][Nn][Ll][Yy]//g' <<< "$body"
}

# Collapses every run of whitespace (spaces, tabs, newlines, carriage
# returns — including blank lines between paragraphs) to a single space,
# then trims leading/trailing whitespace. This is the ONLY step performed
# before matching in codex_response_is_approved below, and the ONLY
# permitted flexibility in template matching (issue #1491's
# conservative-verdict-classifier implementation plan, Decision 1) — no
# case folding, no optional clauses, no punctuation tolerance, no
# synonym alternation, and no truncation of any kind. `tr` first converts
# every whitespace class this function cares about to a literal space
# (BSD tr does not support `\s`, hence the explicit newline/tab/
# carriage-return class), then `tr -s ' '` squeezes runs of spaces to
# one; `sed` trims the two remaining edges.
codex_normalize_whitespace() {
  local text
  text=$(tr '\n\t\r' '   ' <<< "$1" | tr -s ' ')
  sed -E 's/^ //; s/ $//' <<< "$text"
}

# Exact captured clean-response template, covering the ENTIRE body —
# verdict sentence AND the complete vendor "About Codex in GitHub"
# footer, with no truncation step anywhere in codex_response_is_approved
# below. This closes Codex GitHub finding `3803545669` (issue #1491's
# implementation plan, Decisions 1 and 5): a prior design truncated the
# body at the footer's opening line and matched only the visible
# portion, trusting every byte after that line, unseen; a body reading
# the approved template + the footer's opening line only + an actual
# instruction (e.g. "Rename the unsafe function.") matched the visible
# portion exactly and would have been misclassified APPROVED under that
# design. There is no discarded byte range left for that construction
# (or any construction) to hide in — the entire body, first character to
# last, must be part of this one literal.
#
# This template has exactly TWO bounded placeholders, both anchored at a
# fixed position between exact literal text on either side, never a
# general wildcard:
#
# 1. The commit SHA, bound to git's own documented abbreviated-to-full
#    SHA-1 hex-length range (`[0-9a-f]{7,40}`) — NOT to the single
#    length any one capture happens to show.
# 2. The "flavor" slot immediately after "Didn't find any major issues. "
#    — see the dedicated comment block below for its full history and
#    bound derivation (issue #1491's implementation plan, Decision 2
#    Addendum).
#
# No other field is a placeholder, anywhere in the verdict sentence or
# the footer. Extending either placeholder's bound, or adding a whole new
# template, requires a live capture of the new evidence and the same
# review discipline the deleted CODEX_APPROVAL_PATTERN once required —
# these are the ONLY levers that can widen the approval surface, and
# reintroducing any truncation step before matching is explicitly
# forbidden (Decision 2/5).
#
# The footer portion of this literal was verified byte-identical (modulo
# one API-transport-only trailing newline that whitespace normalization
# already absorbs) across every real capture available at implementation
# time — the PR #1489 root-comment capture and every PR #1490/#1492
# review-body capture — so it contributes zero placeholders of its own.
#
# The apostrophe in "Didn't" is a literal straight ASCII apostrophe, NOT
# a regex wildcard — do not replace it with `.` if this pattern is
# edited; a wildcard there would silently widen the match to any
# character, which is exactly the kind of unreviewed widening this
# design forbids.
#
# The "flavor" slot's placeholder, `[^*`[:cntrl:]]{1,40}`, and why it
# replaced a 14-token literal alternation (issue #1491's implementation
# plan, Decision 2 second addendum — supersedes the first addendum's
# enumeration approach):
#
# History: this template originally hardcoded the single literal
# "Swish!" here. This repository's own PR #1494 falsified that
# assumption on its first real-traffic exercise — its Codex review used
# ":rocket:" instead and safe-failed. A repository-history sweep then
# found 14 distinct evidenced tokens, not the 1-2 anticipated — single
# words, full sentences, GitHub emoji shortcodes, inconsistent trailing
# punctuation. That diversity, discovered from fewer than 50 samples, is
# LLM-generated variety, not a fixed vocabulary: enumerating it would not
# converge, reopening issue #1491's original complaint (an open-ended
# enumeration that keeps finding one more case) on a new axis, just as
# every disqualifier/vocabulary design earlier in this plan's history
# already failed to converge for the same structural reason. Attempting a
# 14-token alternation shipped briefly, then was replaced by this bounded
# placeholder before merge, once that pattern became clear.
#
# Bound derivation: `{1,40}` — 40 is the longest evidenced token's length
# (31 characters, "More of your lovely PRs please.") rounded up to the
# nearest 10 with modest headroom, wide enough to admit a somewhat longer
# genuine flavor phrase without being large enough to admit multi-sentence
# injected content. `[^*`[:cntrl:]]` excludes only the characters that
# could let this slot swallow adjacent template structure: `*` (protects
# the literal `**Reviewed commit:**` bold-marker syntax immediately
# after this slot), backtick (protects the backtick-delimited SHA field
# that follows), and every control character including newline/carriage
# return (defense in depth — whitespace normalization, Decision 1,
# already guarantees no raw control character survives to this point,
# but the exclusion is kept explicit rather than relying solely on that
# guarantee). No apostrophe, colon, comma, period, exclamation mark, or
# plain space is excluded — every one of those appears in at least one
# evidenced token and the slot must keep admitting ordinary punctuation.
#
# Residual risk, stated plainly rather than claimed away: this is now a
# genuine (bounded) placeholder, not a literal — a false `APPROVED` is
# possible if Codex ever asserts "Didn't find any major issues." and then
# places an actual directive inside this 40-character slot while still
# reproducing the exact, complete footer verbatim afterward. This
# requires self-contradictory vendor output (a clean verdict immediately
# followed by an instruction, inside one otherwise-genuine response) and
# is treated as an accepted, disclosed trade — see Decision 2 second
# addendum and Risks & Mitigations for the full accounting — not a zero-
# risk claim.
CODEX_APPROVED_TEMPLATES=(
  '^Codex Review: Didn'"'"'t find any major issues\. [^*`[:cntrl:]]{1,40} \*\*Reviewed commit:\*\* `[0-9a-f]{7,40}` <details> <summary>ℹ️ About Codex in GitHub</summary> <br/> \[Your team has set up Codex to review pull requests in this repo\]\(https://chatgpt\.com/codex/cloud/settings/general\)\. Reviews are triggered when you - Open a pull request for review - Mark a draft as ready - Comment "@codex review"\. If Codex has suggestions, it will comment; otherwise it will react with 👍\. Codex can also answer questions or update the PR\. Try commenting "@codex address that feedback"\. </details>$'
)

# `APPROVED` requires the ENTIRE, untruncated response — whitespace-
# normalized, nothing else changed — to reproduce one of
# CODEX_APPROVED_TEMPLATES exactly (issue #1491's conservative-verdict-
# classifier implementation plan, Decision 1). There is no
# fence-marker check, no quoted-span stripping, no "not only" idiom
# stripping, and no vocabulary/negation/grammar scan in this function —
# each of those existed to compensate for a parsing layer that no longer
# exists; a stray fence marker, a quoted span, or off-position content
# is now just "extra text that breaks the exact match," and the match
# already rejects it without a dedicated check. No stderr diagnostic is
# emitted on a non-match: under exact-template matching there is exactly
# one reason a response fails to approve (it does not reproduce an
# evidenced template), so a diagnostic distinguishing "no reason" would
# not be useful and would reintroduce a fuzzy-matching concept this
# design deliberately does not have.
codex_response_is_approved() {
  local body="$1" normalized template
  normalized=$(codex_normalize_whitespace "$body")
  for template in "${CODEX_APPROVED_TEMPLATES[@]}"; do
    if grep -qE "$template" <<< "$normalized"; then
      return 0
    fi
  done
  return 1
}

# Ranks a response into one of four priority tiers, highest wins on a
# timestamp tie (see codex_select_terminal_evidence and
# codex_select_review_evidence below). Checked in this exact order so a
# response matching multiple patterns resolves to its most severe tier:
#
#   3 — blocking: an actual finding. Must never be hidden regardless of
#       what else the response says (e.g. "No blocking issues found.
#       Must fix ..." is blocking, not approved).
#   2 — unrecognized format: neither blocking, usage-limit, nor approved.
#       The documented verdict classifier safe-fails this to
#       NEEDS_REVISION (see "Verdict parsing" header comment) because it
#       could be a disguised rejection in an unexpected format. Ranked
#       ABOVE usage-limit: a permissive unavailable-policy consumer could
#       treat a usage-limit UNAVAILABLE more leniently than an explicit
#       NEEDS_REVISION, so an ambiguous response must not be silently
#       demoted behind a mere availability notice (fresh evidence from PR
#       #1490 finding 3789597796).
#   1 — usage-limit / environment error: two distinct "review was
#       unavailable" notices, ranked at the same lower availability tier.
#       Codex hit its review quota, OR the repo has no Codex environment
#       configured. A response containing both an approval phrase and
#       usage-limit wording (e.g. "No blocking issues could be evaluated
#       because you have reached your Codex usage limits") is a
#       usage-limit notice, not approved (fresh evidence from PR #1490
#       finding 3789555934). An ancillary environment-setup-error comment
#       must rank here too, not at the unrecognized-format tier: tied
#       against a genuine (if unrecognized-format) review, an
#       environment-setup error is a weaker, merely-informational
#       availability notice and must not silently replace the review's
#       safe-fail NEEDS_REVISION with an UNAVAILABLE-style
#       codex-github-environment-missing verdict (fresh evidence from PR
#       #1490 finding 3789722821).
#   0 — clean approval: the only tier that produces APPROVED.
#
# A single binary requires-attention flag is not enough: two tied
# responses that are BOTH "not a clean approval" (e.g. a usage-limit root
# comment and a blocking submitted review, or a usage-limit response and
# an unrecognized-format response) need their own internal ranking, not
# just a tie that keeps whichever was evaluated first (fresh evidence
# from PR #1490 finding 3789521036).
codex_response_priority() {
  local body="$1"
  local state="${2:-}"
  # A structurally CHANGES_REQUESTED review ranks at the blocking tier
  # regardless of its body text, mirroring the verdict-parsing chain's own
  # CHANGES_REQUESTED short-circuit. Without this, two current-head
  # reviews tied at the same second — one genuinely clean, one
  # CHANGES_REQUESTED but whose body ALSO happens to contain an approval
  # phrase like "Looks good" — both scored priority 0 from body text
  # alone, so whichever the API happened to return first won the tie
  # (since this scan only replaces the selection on a STRICTLY greater
  # priority): if the clean review was returned first, the
  # CHANGES_REQUESTED review's state was silently discarded and never
  # even reached the caller's CHANGES_REQUESTED check, producing a false
  # APPROVED (fresh evidence from PR #1490 finding 3796982553).
  if [ "$state" = "CHANGES_REQUESTED" ] || codex_response_is_blocking "$body"; then
    printf '3\n'
  elif codex_response_is_usage_limit "$body" || codex_response_is_environment_error "$body" || codex_response_is_account_not_connected "$body"; then
    printf '1\n'
  elif codex_response_is_approved "$body"; then
    printf '0\n'
  else
    printf '2\n'
  fi
}

# Decides whether CANDIDATE terminal ("review"-sourced) evidence should
# replace CURRENT terminal evidence. A strictly later candidate always
# wins. GitHub timestamps are second-resolution, so ties are possible; on
# an exact tie, the strictly higher-priority response wins
# (codex_response_priority) regardless of which side (submitted review vs
# SHA-pinned root comment) supplied it, and regardless of which side is
# CURRENT vs. candidate. A tie in priority keeps CURRENT (arbitrary but
# stable — both sides are equivalent for verdict purposes at that tier).
#
# Optional 5th/6th args (current_state/candidate_state) carry GitHub's
# structured review state for whichever side is review-sourced (empty for
# a SHA-pinned root comment, which has no review state). Without these,
# a same-second tie between a clean-looking root comment and a
# CHANGES_REQUESTED review whose body ALSO reads clean (e.g. "Looks good
# overall, but see inline comments") scored both sides priority 0 from
# body text alone, so the already-selected comment won the tie and the
# review's CHANGES_REQUESTED state was discarded (fresh evidence from PR
# #1490 finding 3797160202, a followup to 3796982553 that fixed this
# exact class of gap for the review-vs-review tie-break in
# codex_select_review_evidence but missed this separate comment-vs-review
# tie-break, which has its own priority calculation).
codex_select_terminal_evidence() {
  local current_body="$1" current_time="$2"
  local candidate_body="$3" candidate_time="$4"
  local current_state="${5:-}" candidate_state="${6:-}"
  [ -z "$current_time" ] && return 0
  if [ "$candidate_time" \> "$current_time" ]; then
    return 0
  fi
  if [ "$candidate_time" = "$current_time" ]; then
    local candidate_priority current_priority
    candidate_priority=$(codex_response_priority "$candidate_body" "$candidate_state")
    current_priority=$(codex_response_priority "$current_body" "$current_state")
    if [ "$candidate_priority" -gt "$current_priority" ]; then
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
# An ACTIONABLE ancillary comment — either an environment-setup error or a
# usage-limit notice — is treated as the priority ancillary signal once
# seen: a later PLAIN comment (e.g. an acknowledgement) does not overwrite
# it, so an actionable failure is not silently lost to a no-information
# comment that happens to arrive later in the same fetch (fresh evidence
# from PR #1490 finding 3787786945, generalized in finding 3788008327 to
# also cover usage-limit comments — the same evidence-loss pattern applied
# to both classifiers, not just environment errors). A LATER actionable
# comment still updates it, keeping the most recent one. A SHA-pinned
# TERMINAL comment is never classified as either an environment error or a
# usage-limit notice, even if its text happens to quote that wording (e.g.
# a blocking finding about stale documentation that reproduces it
# verbatim) — terminal evidence is always genuine review content, not a
# bare failure message (fresh evidence from PR #1490 finding 3787943163).
# When TWO terminal comments share a timestamp, the not-a-clean-approval-
# first tie-break (codex_select_terminal_evidence) decides which one is
# tracked, so a later clean terminal comment cannot silently discard an
# earlier blocking one submitted in the same second (fresh evidence from
# PR #1490 finding 3788078189).
#
# Sets: COMMENT_TERMINAL_BODY, COMMENT_TERMINAL_TIME, COMMENT_LATEST_BODY,
# COMMENT_LATEST_TIME, COMMENT_LATEST_IS_TERMINAL.
codex_scan_comment_evidence() {
  local comments_file="$1"
  COMMENT_TERMINAL_BODY=""
  COMMENT_TERMINAL_TIME=""
  COMMENT_LATEST_BODY=""
  COMMENT_LATEST_TIME=""
  # Tracks whether the comment currently held in COMMENT_LATEST_BODY is
  # ITSELF the SHA-pinned terminal comment (as opposed to a genuinely
  # separate ancillary comment). codex_combine_terminal_evidence uses this
  # to skip re-classifying a terminal comment as an ancillary
  # environment-error/usage-limit notice just because its own finding
  # text happens to quote that wording (fresh evidence from PR #1490
  # finding 3790023143 — a case not caught by the existing "terminal
  # comment never routed through the environment-error classifier"
  # protection, since that protection only covers the terminal-vs-review
  # combine path, not this separate ancillary-override check).
  COMMENT_LATEST_IS_TERMINAL=0
  local comment_latest_is_actionable=0
  # Tracks whether the CURRENTLY tracked ancillary comment is specifically
  # a usage-limit notice (as opposed to a merely-actionable environment-
  # error). Once a usage-limit notice is tracked, only ANOTHER usage-limit
  # notice may replace it — a later environment-setup error in the same
  # fetch must never silently discard it, since codex_combine_terminal_
  # evidence's immediate-termination handling for usage-limit only
  # protects it there, after this scan has already produced its single
  # COMMENT_LATEST_BODY; discarding it here means that downstream
  # protection never gets a chance to apply (fresh evidence from PR #1490
  # finding 3790092216, a followup to 3790062091/3789928786/3789992794).
  local comment_latest_is_usage_limit=0
  local line created_at body is_actionable is_terminal is_usage_limit should_update
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    created_at=$(printf '%s' "$line" | jq -r '.created_at // empty')  # workflow-shell-guard: allow SH003 - $line is a compact JSON object already validated parseable by the preceding jq -sc call; empty is a normal absent-field case, not a failure
    body=$(printf '%s' "$line" | jq -r '.body // empty')  # workflow-shell-guard: allow SH003 - same pre-validated $line as above; empty body is not a failure
    is_terminal=0
    codex_response_reviews_current_head "$body" && is_terminal=1
    is_actionable=0
    is_usage_limit=0
    if [ "$is_terminal" -eq 0 ]; then
      codex_response_is_usage_limit "$body" && is_usage_limit=1
      if [ "$is_usage_limit" -eq 1 ] || codex_response_is_environment_error "$body" || codex_response_is_account_not_connected "$body"; then
        is_actionable=1
      fi
    fi
    should_update=0
    if [ "$comment_latest_is_actionable" -eq 0 ]; then
      should_update=1
    elif [ "$comment_latest_is_usage_limit" -eq 1 ]; then
      [ "$is_usage_limit" -eq 1 ] && should_update=1
    elif [ "$is_actionable" -eq 1 ]; then
      should_update=1
    fi
    if [ "$should_update" -eq 1 ]; then
      COMMENT_LATEST_BODY="$body"
      COMMENT_LATEST_TIME="$created_at"
      COMMENT_LATEST_IS_TERMINAL="$is_terminal"
      comment_latest_is_actionable="$is_actionable"
      comment_latest_is_usage_limit="$is_usage_limit"
    fi
    if [ "$is_terminal" -eq 1 ]; then
      # Apply the same not-a-clean-approval-first tie-break used for
      # submitted reviews when TWO terminal comments share a timestamp:
      # an unconditional overwrite would let a later clean comment
      # silently discard an earlier blocking one submitted in the same
      # second (fresh evidence from PR #1490 finding 3788078189).
      if codex_select_terminal_evidence "$COMMENT_TERMINAL_BODY" "$COMMENT_TERMINAL_TIME" "$body" "$created_at"; then
        COMMENT_TERMINAL_BODY="$body"
        COMMENT_TERMINAL_TIME="$created_at"
      fi
    fi
  done < "$comments_file"
}

# Scans a JSON-lines file (one compact object per line) of current-head
# submitted reviews that are ALL TIED at the globally latest submitted_at
# timestamp (produced by the review-poll jq queries below, which select
# every review sharing the max timestamp rather than collapsing to one via
# `sort_by | last`). GitHub timestamps are second-resolution, so multiple
# reviews genuinely CAN tie; picking an arbitrary one by array order could
# silently discard a more severe response in favor of a less severe one
# submitted in the same second (fresh evidence from PR #1490 findings
# 3788008326, 3789477520, and 3789597796). Tracks the highest-priority
# tied review via codex_response_priority (blocking > unrecognized format
# > usage-limit > clean approval) rather than stopping at the first match
# for a single binary tier — a scan that only distinguishes "requires
# attention" from "clean" cannot correctly rank two tied responses that
# are both "requires attention" but at different severities.
# Sets: SELECTED_REVIEW_BODY, SELECTED_REVIEW_TIME, SELECTED_REVIEW_STATE.
# SELECTED_REVIEW_STATE is GitHub's own structured review state
# (APPROVED/CHANGES_REQUESTED/COMMENTED/PENDING/DISMISSED, or empty if
# the reviews-endpoint jq query behind $reviews_file predates this field
# — a legacy caller passing an older tmpfile format degrades to empty
# state rather than failing) — see codex_combine_terminal_evidence for
# why this is threaded separately from body-text classification.
codex_select_review_evidence() {
  local reviews_file="$1"
  SELECTED_REVIEW_BODY=""
  SELECTED_REVIEW_TIME=""
  SELECTED_REVIEW_STATE=""
  # Presence is tracked via an explicit found-flag, not by checking
  # whether the selected body string is non-empty — a winning review's
  # body can legitimately be empty (see
  # codex_combine_terminal_evidence's review_time-based presence check
  # above), so inferring "not yet found" from string emptiness would
  # reintroduce that exact bug here.
  local have_selection=0
  local best_priority=-1
  local line created_at body state priority
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    created_at=$(printf '%s' "$line" | jq -r '.created_at // empty')  # workflow-shell-guard: allow SH003 - $line is a compact JSON object already validated parseable by the preceding jq -sc call; empty is a normal absent-field case, not a failure
    body=$(printf '%s' "$line" | jq -r '.body // empty')  # workflow-shell-guard: allow SH003 - same pre-validated $line as above; empty body is not a failure
    state=$(printf '%s' "$line" | jq -r '.state // empty')  # workflow-shell-guard: allow SH003 - same pre-validated $line as above; empty state is not a failure
    priority=$(codex_response_priority "$body" "$state")
    if [ "$have_selection" -eq 0 ] || [ "$priority" -gt "$best_priority" ]; then
      SELECTED_REVIEW_BODY="$body"
      SELECTED_REVIEW_TIME="$created_at"
      SELECTED_REVIEW_STATE="$state"
      best_priority="$priority"
      have_selection=1
    fi
  done < "$reviews_file"
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
# or "" if no evidence at all), COMBINED_REVIEW_STATE. LABEL is used only
# for INFO logging. COMMENT_LATEST_IS_TERMINAL (8th arg) gates the
# ancillary-override check below: it must never fire when the "latest
# ancillary comment" IS actually the terminal comment itself, not a
# genuinely separate ancillary one (see the comment above that check).
#
# COMBINED_REVIEW_STATE carries GitHub's own structured review state
# (e.g. CHANGES_REQUESTED) for the caller's verdict-parsing chain to
# check ahead of/alongside free-text classification — relying solely on
# body-text parsing (codex_response_is_blocking/is_approved) let a
# submitted review with state CHANGES_REQUESTED but ambiguous or
# clean-sounding body wording ("Looks good overall, but see the note
# below.") fall through to the unrecognized-format safe-fail or even a
# false APPROVED instead of being recognized as blocking on GitHub's own
# authoritative signal (fresh evidence from PR #1490 finding 3796396391).
# It is set ONLY when review_body/review_time (the actual submitted
# review, from the reviews endpoint) is the winning evidence — never when
# a SHA-pinned terminal COMMENT wins instead (comments have no review
# state) or when an ancillary comment later overrides the winner below.
codex_combine_terminal_evidence() {
  local label="$1"
  local comment_terminal_body="$2" comment_terminal_time="$3"
  local comment_latest_body="$4" comment_latest_time="$5"
  local review_body="$6" review_time="$7"
  local comment_latest_is_terminal="$8"
  local review_state="$9"

  COMBINED_BODY=""
  COMBINED_TIME=""
  COMBINED_SOURCE=""
  COMBINED_REVIEW_STATE=""

  if [ -n "$comment_terminal_body" ]; then
    COMBINED_BODY="$comment_terminal_body"
    COMBINED_TIME="$comment_terminal_time"
    COMBINED_SOURCE="review"
    echo "INFO: $label detected via SHA-pinned PR comment"
  fi

  # Presence is checked via review_time, not review_body: a genuine
  # selected review is guaranteed a non-empty submitted_at by the
  # review-poll jq queries' filter, but its body CAN legitimately be
  # empty. Checking review_body would treat an empty-bodied tied review
  # as absent, letting a clean terminal comment win the tie-break by
  # default even though codex_response_priority correctly ranks an empty
  # body as an unrecognized response (priority 2) requiring attention
  # (fresh evidence from PR #1490 finding 3788118857).
  if [ -n "$review_time" ]; then
    if [ "$COMBINED_SOURCE" = "review" ]; then
      # CURRENT here is always the SHA-pinned terminal comment (no review
      # state of its own) — this branch only runs when COMBINED_SOURCE
      # was just set to "review" by the terminal-comment block above, so
      # CANDIDATE's review_state is the only side with a real state.
      if codex_select_terminal_evidence "$COMBINED_BODY" "$COMBINED_TIME" "$review_body" "$review_time" "" "$review_state"; then
        COMBINED_BODY="$review_body"
        COMBINED_TIME="$review_time"
        COMBINED_SOURCE="review"
        COMBINED_REVIEW_STATE="$review_state"
        echo "INFO: $label detected via PR reviews endpoint (supersedes SHA-pinned comment)"
      fi
    else
      COMBINED_BODY="$review_body"
      COMBINED_TIME="$review_time"
      COMBINED_SOURCE="review"
      COMBINED_REVIEW_STATE="$review_state"
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

  # comment_latest_is_terminal must be 0 (a genuinely separate ancillary
  # comment, not the terminal comment itself) before applying this
  # override: when a clean SHA-pinned terminal comment/review's OWN
  # finding text happens to quote or discuss environment-error/usage-limit
  # wording (e.g. reviewing this file's own detection code, or flagging
  # stale docs that describe the setup message), codex_scan_comment_evidence
  # can end up tracking that SAME terminal comment as COMMENT_LATEST_BODY
  # (there being no other, genuinely ancillary comment). Without this
  # guard, re-running the environment-error/usage-limit classifier on that
  # text here reclassified a clean terminal review as an ancillary setup
  # failure and downgraded APPROVED to codex-github-environment-missing —
  # a case the "terminal comment never routed through the environment-error
  # classifier" guarantee elsewhere in this function did NOT cover, since
  # that guarantee only applies to the terminal-vs-review combine path
  # above, not this separate ancillary-override check (fresh evidence from
  # PR #1490 finding 3790023143).
  # Usage-limit and environment-error are handled as two SEPARATE checks,
  # not one shared condition, because they have different retention
  # semantics (documented in docs/workflow/development-workflow/
  # integrations/codex-github.md and protocols/93-automated-reviewer-loop-
  # protocol.md): an environment-setup error is retained through the poll
  # window and can be superseded by strictly newer terminal/review
  # evidence, but a usage-limit notice terminates the invocation
  # IMMEDIATELY upon detection (codex_return_usage_limit exits before any
  # further polling can happen) and is never superseded — including by a
  # clean review returned in the SAME fetch. The previous shared
  # newest-wins comparison let a same-fetch review that happened to have a
  # later timestamp silently discard the usage-limit notice before it ever
  # reached codex_return_usage_limit, contradicting the documented
  # immediate-termination contract (fresh evidence from PR #1490 finding
  # 3790062091, a followup to 3789928786/3789992794).
  if [ "$comment_latest_is_terminal" -eq 0 ] && [ -n "$comment_latest_body" ] && codex_response_is_usage_limit "$comment_latest_body"; then
    if [ -n "$COMBINED_SOURCE" ] && { [ "$COMBINED_REVIEW_STATE" = "CHANGES_REQUESTED" ] || codex_response_is_blocking "$COMBINED_BODY"; }; then
      # Blocking terminal/review evidence always wins outright — it is
      # never discarded by a usage-limit notice, regardless of timing, so
      # an actionable finding can never be hidden behind an "unavailable"
      # verdict (fresh evidence from PR #1490 finding 3787943162; Protocol
      # 93 requires blocking evidence to never be silently discarded). A
      # winning review's own CHANGES_REQUESTED state counts as blocking
      # here too, alongside free-text detection, so a same-fetch
      # usage-limit notice can't silently override a structurally
      # blocking review whose body text happens to be ambiguous (fresh
      # evidence from PR #1490 finding 3796396391).
      :
    else
      COMBINED_BODY="$comment_latest_body"
      COMBINED_TIME="$comment_latest_time"
      COMBINED_SOURCE="comment"
      COMBINED_REVIEW_STATE=""
      echo "INFO: $label usage-limit notice takes immediate precedence over terminal/review evidence, including same-fetch evidence"
    fi
  elif [ "$comment_latest_is_terminal" -eq 0 ] && [ -n "$comment_latest_body" ] && codex_response_is_account_not_connected "$comment_latest_body"; then
    if [ -n "$COMBINED_SOURCE" ] && { [ "$COMBINED_REVIEW_STATE" = "CHANGES_REQUESTED" ] || codex_response_is_blocking "$COMBINED_BODY"; }; then
      # Same contract as the usage-limit block above: blocking evidence is
      # never discarded by an unavailability notice (CodeRabbit on PR #1586).
      :
    else
      COMBINED_BODY="$comment_latest_body"
      COMBINED_TIME="$comment_latest_time"
      COMBINED_SOURCE="comment"
      COMBINED_REVIEW_STATE=""
      echo "INFO: $label account-connection refusal takes immediate precedence over terminal/review evidence, including same-fetch evidence"
    fi
  elif [ "$comment_latest_is_terminal" -eq 0 ] && [ -n "$comment_latest_body" ] && codex_response_is_environment_error "$comment_latest_body"; then
    if [ -n "$COMBINED_SOURCE" ] && { [ "$COMBINED_REVIEW_STATE" = "CHANGES_REQUESTED" ] || codex_response_is_blocking "$COMBINED_BODY"; }; then
      # Blocking terminal/review evidence always wins outright — it is
      # never discarded by an environment-setup error, regardless of
      # timing, so an actionable finding can never be hidden behind an
      # "unavailable" verdict (fresh evidence from PR #1490 finding
      # 3787943162; Protocol 93 requires blocking evidence to never be
      # silently discarded). A winning review's own CHANGES_REQUESTED
      # state counts as blocking here too (fresh evidence from PR #1490
      # finding 3796396391).
      :
    elif [ -z "$COMBINED_TIME" ] || ! codex_select_terminal_evidence "$comment_latest_body" "$comment_latest_time" "$COMBINED_BODY" "$COMBINED_TIME" "" "$COMBINED_REVIEW_STATE"; then
      COMBINED_BODY="$comment_latest_body"
      COMBINED_TIME="$comment_latest_time"
      COMBINED_SOURCE="comment"
      COMBINED_REVIEW_STATE=""
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

codex_return_account_not_connected() {
  echo "VERDICT: UNAVAILABLE — Codex GitHub account is not connected for the triggering identity"
  echo "REASON=codex-github-account-not-connected"
  echo "COMMENT_COUNT=0"
  echo "BLOCKING_COUNT=0"
  echo "SUGGESTION_COUNT=0"
  echo "---BEGIN BOT RESPONSE---"
  echo "$1"
  echo "---END BOT RESPONSE---"
  exit 3
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
  local latest_sha latest_sha_full
  if ! latest_sha_full=$(gh pr view "$PR_NUMBER" --repo "$OWNER/$REPO" --json headRefOid --jq '.headRefOid' | head -c 100); then
    echo "ERROR: could not revalidate PR #$PR_NUMBER HEAD SHA" >&2
    echo "VERDICT: TIMED_OUT — could not revalidate PR HEAD SHA (treated as unavailable)"
    echo "REASON=codex-github-head-unavailable"
    exit 2
  fi
  latest_sha_full=$(printf '%s' "$latest_sha_full" | tr -d '\n' | cut -c1-40)
  latest_sha=$(printf '%s' "$latest_sha_full" | cut -c1-12)
  if [ -z "$latest_sha_full" ]; then
    echo "ERROR: could not revalidate PR #$PR_NUMBER HEAD SHA (empty result)" >&2
    echo "VERDICT: TIMED_OUT — could not revalidate PR HEAD SHA (treated as unavailable)"
    echo "REASON=codex-github-head-unavailable"
    exit 2
  fi
  if [ "$latest_sha_full" != "$CURRENT_SHA_FULL" ]; then
    echo "INFO: PR head changed during Codex polling (started at $CURRENT_SHA, now $latest_sha)"
    codex_return_head_changed
  fi
}

codex_fetch_existing_current_head_evidence() {
  local existing_comments_stderr existing_comments_tmpfile
  existing_comments_stderr=$(mktemp)
  existing_comments_tmpfile=$(mktemp)
  COMMENT_TERMINAL_BODY=""
  COMMENT_TERMINAL_TIME=""
  COMMENT_LATEST_BODY=""
  COMMENT_LATEST_TIME=""
  COMMENT_LATEST_IS_TERMINAL=0
  if gh api "repos/$OWNER/$REPO/issues/$PR_NUMBER/comments" --paginate \
    2>"$existing_comments_stderr" \
    | jq -sc --arg bot "$BOT_LOGIN" --arg bot_plain "$BOT_LOGIN_PLAIN" \
        '(add // []) | [.[] | select(.user.login == $bot or .user.login == $bot_plain)] | sort_by(.created_at, .id) | .[] | {created_at:(.created_at // ""), body:(.body // "")}' \
    > "$existing_comments_tmpfile"; then
    codex_scan_comment_evidence "$existing_comments_tmpfile"
  else
    local existing_comments_err
    existing_comments_err=$(cat "$existing_comments_stderr")
    rm -f "$existing_comments_stderr" "$existing_comments_tmpfile"
    echo "WARNING: failed to fetch existing Codex root comments before trigger: $existing_comments_err" >&2
    return 2
  fi
  rm -f "$existing_comments_stderr" "$existing_comments_tmpfile"

  local existing_reviews_stderr existing_reviews_tmpfile
  existing_reviews_stderr=$(mktemp)
  existing_reviews_tmpfile=$(mktemp)
  EXISTING_REVIEW_BODY=""
  EXISTING_REVIEW_TIME=""
  EXISTING_REVIEW_STATE=""
  if gh api "repos/$OWNER/$REPO/pulls/$PR_NUMBER/reviews" --paginate \
    2>"$existing_reviews_stderr" \
    | jq -sc --arg bot "$BOT_LOGIN" --arg bot_plain "$BOT_LOGIN_PLAIN" --arg sha "$CURRENT_SHA_FULL" \
        '(add // []) | [.[] | select((.user.login == $bot or .user.login == $bot_plain) and .submitted_at != null and ((.commit_id // "") == $sha) and ((.state // "") != "DISMISSED"))] | if length == 0 then empty else (map(.submitted_at) | max) as $latest | .[] | select(.submitted_at == $latest) | {created_at:(.submitted_at // ""), body:(.body // ""), state:(.state // "")} end' \
    > "$existing_reviews_tmpfile"; then
    codex_select_review_evidence "$existing_reviews_tmpfile"
    EXISTING_REVIEW_BODY="$SELECTED_REVIEW_BODY"
    EXISTING_REVIEW_TIME="$SELECTED_REVIEW_TIME"
    EXISTING_REVIEW_STATE="$SELECTED_REVIEW_STATE"
  else
    local existing_reviews_err
    existing_reviews_err=$(cat "$existing_reviews_stderr")
    rm -f "$existing_reviews_stderr" "$existing_reviews_tmpfile"
    echo "WARNING: failed to fetch existing Codex PR reviews before trigger: $existing_reviews_err" >&2
    return 2
  fi
  rm -f "$existing_reviews_stderr" "$existing_reviews_tmpfile"

  codex_combine_terminal_evidence "existing current-head Codex evidence" \
    "$COMMENT_TERMINAL_BODY" "$COMMENT_TERMINAL_TIME" \
    "" "" \
    "$EXISTING_REVIEW_BODY" "$EXISTING_REVIEW_TIME" 0 "$EXISTING_REVIEW_STATE"
  EXISTING_BOT_RESPONSE="$COMBINED_BODY"
  EXISTING_BOT_RESPONSE_SOURCE="$COMBINED_SOURCE"
  EXISTING_BOT_RESPONSE_TIME="$COMBINED_TIME"
  EXISTING_BOT_RESPONSE_REVIEW_STATE="$COMBINED_REVIEW_STATE"
  return 0
}

codex_classify_existing_current_head_evidence() {
  local unresolved_thread_count response_display fetch_status
  if ! unresolved_thread_count=$(codex_unresolved_review_thread_count); then
    echo "WARNING: failed to fetch existing Codex review threads before trigger" >&2
    echo "VERDICT: TIMED_OUT — could not fetch existing Codex thread state before trigger (treated as unavailable)"
    exit 2
  fi
  if [ "$unresolved_thread_count" -gt 0 ]; then
    codex_require_current_head
    echo "INFO: existing current-head Codex evidence detected; no trigger comment will be posted"
    echo "VERDICT: NEEDS_REVISION"
    echo "INFO: detected $unresolved_thread_count existing unresolved Codex review thread(s)"
    exit 1
  fi

  set +e
  codex_fetch_existing_current_head_evidence
  fetch_status=$?
  set -e
  if [ "$fetch_status" -eq 2 ]; then
    echo "VERDICT: TIMED_OUT — could not fetch existing Codex evidence before trigger (treated as unavailable)"
    exit 2
  fi
  if [ "$fetch_status" -ne 0 ]; then
    return 1
  fi
  [ -n "$EXISTING_BOT_RESPONSE_TIME" ] || return 1

  echo "INFO: existing current-head Codex evidence detected; no trigger comment will be posted"
  codex_require_current_head
  response_display=$(printf '%s' "$EXISTING_BOT_RESPONSE" | jq -Rrs '.[0:10000]')  # workflow-shell-guard: allow SH003 - jq reads raw text for display truncation only.

  if [ "$EXISTING_BOT_RESPONSE_SOURCE" = "review" ] && { [ "$EXISTING_BOT_RESPONSE_REVIEW_STATE" = "CHANGES_REQUESTED" ] || codex_response_is_blocking "$EXISTING_BOT_RESPONSE"; }; then
    echo "VERDICT: NEEDS_REVISION"
    echo "---BEGIN BOT RESPONSE---"
    echo "$response_display"
    echo "---END BOT RESPONSE---"
    exit 1
  elif codex_response_is_usage_limit "$(codex_strip_quoted_spans "$EXISTING_BOT_RESPONSE")"; then
    codex_return_usage_limit "$response_display"
  elif codex_response_is_account_not_connected "$(codex_strip_quoted_spans "$EXISTING_BOT_RESPONSE")"; then
    codex_return_account_not_connected "$response_display"
  elif [ "$EXISTING_BOT_RESPONSE_SOURCE" = "review" ] && codex_response_is_approved "$EXISTING_BOT_RESPONSE"; then
    echo "VERDICT: APPROVED"
    echo "---BEGIN BOT RESPONSE---"
    echo "$response_display"
    echo "---END BOT RESPONSE---"
    exit 0
  else
    echo "VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)"
    echo "---BEGIN BOT RESPONSE---"
    echo "$response_display"
    echo "---END BOT RESPONSE---"
    exit 1
  fi
}

codex_wait_for_existing_current_head_evidence() {
  local elapsed=0 sleep_for remaining
  if [ "$PRE_TRIGGER_WAIT" -eq 0 ]; then
    echo "INFO: pre-trigger existing-evidence check disabled"
    return 0
  fi
  echo "INFO: checking for existing current-head Codex review evidence before posting trigger (max ${PRE_TRIGGER_WAIT}s)"
  while :; do
    codex_classify_existing_current_head_evidence || true
    if [ "$elapsed" -ge "$PRE_TRIGGER_WAIT" ]; then
      echo "INFO: no existing current-head Codex evidence found before trigger window elapsed"
      return 0
    fi
    remaining=$((PRE_TRIGGER_WAIT - elapsed))
    sleep_for="$POLL_INTERVAL"
    if [ "$sleep_for" -gt "$remaining" ]; then
      sleep_for="$remaining"
    fi
    echo "INFO: no existing current-head Codex evidence yet; waiting ${sleep_for}s before posting trigger"
    sleep "$sleep_for"
    elapsed=$((elapsed + sleep_for))
  done
}

codex_wait_for_existing_current_head_evidence

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
    # Recovery after an unavailability reply (#1526). The guard keys only on
    # the head SHA, so once Codex answered a trigger with a usage-limit or
    # account-connection refusal, every later run for that same commit found
    # the old trigger, skipped posting, and re-read the stale refusal — the
    # commit could never be reviewed again without a new push. If the bot's
    # newest reply after that trigger is a refusal (not a review), treat the
    # trigger as spent and post a fresh one.
    CODEX_LAST_REPLY=""
    if CODEX_LAST_REPLY=$(gh api "repos/$OWNER/$REPO/issues/$PR_NUMBER/comments" --paginate 2>/dev/null \
      | jq -sr --arg bot "$BOT_LOGIN" --arg bot_plain "$BOT_LOGIN_PLAIN" --arg since "$TRIGGER_TIME" \
        '[.[][] | select((.user.login == $bot or .user.login == $bot_plain) and .created_at >= $since)]
         | sort_by(.created_at) | last | .body // ""'); then
      if [ -n "$CODEX_LAST_REPLY" ] && \
        { codex_response_is_usage_limit "$(codex_strip_quoted_spans "$CODEX_LAST_REPLY")" || \
          codex_response_is_account_not_connected "$(codex_strip_quoted_spans "$CODEX_LAST_REPLY")" || \
          codex_response_is_environment_error "$(codex_strip_quoted_spans "$CODEX_LAST_REPLY")"; }; then
        echo "INFO: previous trigger for commit $CURRENT_SHA was answered with a reviewer-unavailability refusal — re-triggering so a restored quota/connection can review this commit"
        TRIGGER_TIME=""
        TRIGGER_COMMENT_ID=""
      fi
    else
      echo "WARNING: could not read bot replies to check whether the existing trigger was refused; keeping the existing trigger" >&2
    fi
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
  # A review with state DISMISSED is excluded here rather than merely
  # deprioritized: GitHub itself no longer treats a dismissed review as
  # active evidence, but this script's selection was still choosing it on
  # an idempotent rerun — the SHA/timestamp filters above have no reason
  # to exclude it (dismissal doesn't change commit_id or submitted_at),
  # so a dismissed review's now-stale body text (e.g. "No blocking issues
  # found", recorded before it was dismissed) could still win the
  # tie-break and be classified as fresh terminal approval evidence
  # (fresh evidence from PR #1490 finding 3796982554). Filtering it out at
  # the source, rather than only gating the approval branch downstream,
  # also prevents a dismissed review's state or body from winning
  # codex_select_review_evidence's priority tie-break for ANY verdict, not
  # just approval.
  REVIEW_STDERR=$(mktemp)
  REVIEW_TMPFILE=$(mktemp)
  if gh api "repos/$OWNER/$REPO/pulls/$PR_NUMBER/reviews" --paginate \
    2>"$REVIEW_STDERR" \
    | jq -sc --arg bot "$BOT_LOGIN" --arg bot_plain "$BOT_LOGIN_PLAIN" --arg trigger_time "$TRIGGER_TIME" --arg sha "$CURRENT_SHA_FULL" \
        '(add // []) | [.[] | select((.user.login == $bot or .user.login == $bot_plain) and .submitted_at != null and .submitted_at >= $trigger_time and ((.commit_id // "") == $sha) and ((.state // "") != "DISMISSED"))] | if length == 0 then empty else (map(.submitted_at) | max) as $latest | .[] | select(.submitted_at == $latest) | {created_at:(.submitted_at // ""), body:(.body // ""), state:(.state // "")} end' \
    > "$REVIEW_TMPFILE" 2>"$REVIEW_STDERR"; then
    # Selects every review tied at the latest submitted_at timestamp (not
    # just one via sort_by | last) and picks the one requiring attention if
    # any do, so a blocking review is never discarded in favor of a clean
    # one that happens to share the same second-resolution timestamp
    # (fresh evidence from PR #1490 finding 3788008326). The body is NOT
    # sliced here — classification must see the complete review body (fresh
    # evidence from PR #1490 finding 3789679344: slicing here loses content
    # past the cutoff before BOT_RESPONSE_FULL is ever set, defeating the
    # classify-full/truncate-only-for-display contract below). No SIGPIPE
    # risk: jq redirects to a temp file (`>`), not to a piped consumer that
    # could early-close its read end.
    codex_select_review_evidence "$REVIEW_TMPFILE"
    REVIEW_BODY="$SELECTED_REVIEW_BODY"
    REVIEW_TIME="$SELECTED_REVIEW_TIME"
    REVIEW_STATE="$SELECTED_REVIEW_STATE"
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
    "$REVIEW_BODY" "$REVIEW_TIME" "$COMMENT_LATEST_IS_TERMINAL" "$REVIEW_STATE"
  BOT_RESPONSE="$COMBINED_BODY"
  BOT_RESPONSE_SOURCE="$COMBINED_SOURCE"
  # Captured immediately after combine, before any intervening call could
  # touch COMBINED_TIME, so presence can be checked below without relying
  # on BOT_RESPONSE's body being non-empty (fresh evidence from PR #1490
  # finding 3788164224: a bodyless-but-selected review must still enter
  # verdict parsing and hit the unrecognized-format safe-fail instead of
  # being treated as "no response at all").
  BOT_RESPONSE_TIME="$COMBINED_TIME"
  # Captured alongside COMBINED_TIME for the same reason — GitHub's
  # structured review state, non-empty only when the winning evidence is
  # an actual submitted review (not a SHA-pinned terminal comment, which
  # has no review state).
  BOT_RESPONSE_REVIEW_STATE="$COMBINED_REVIEW_STATE"
  # BOT_RESPONSE_FULL (untruncated) is what every classifier below matches
  # against — a truncated copy could cut off a blocking marker that
  # appears after the cutoff in a long root comment, letting the response
  # fall through to an approval or unavailable verdict while a real
  # finding sits just past the cut point (fresh evidence from PR #1490
  # finding 3789634709). BOT_RESPONSE itself is truncated below and used
  # ONLY for the "---BEGIN/END BOT RESPONSE---" display in the script's
  # own output, never for classification.
  BOT_RESPONSE_FULL="$BOT_RESPONSE"
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
  if [ -n "$BOT_RESPONSE_TIME" ]; then
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
    # 2. Whole-body exact template match → APPROVED (exit 0)   [checked second,
    #    terminal (source == "review") evidence only]
    #    The entire, untruncated response body — whitespace-normalized,
    #    nothing truncated or discarded — must reproduce one of the
    #    templates in CODEX_APPROVED_TEMPLATES exactly (see
    #    codex_response_is_approved above and issue #1491's implementation
    #    plan, Decisions 1/2/5). There is no vocabulary list, no grammar,
    #    and no punctuation/case tolerance. Other Codex root PR comments
    #    and thumbs-up reactions are unavailable, not clean.
    #
    # 3. Neither found, and evidence is terminal → NEEDS_REVISION (exit 1)
    #    Safe-fail: default to NEEDS_REVISION when a terminal response's
    #    format is unrecognized, to avoid incorrectly approving a response
    #    that is a rejection in an unexpected format (per spec risk
    #    mitigation for BR-4). The acknowledgement branch immediately below
    #    is gated on the evidence being NON-terminal (source != "review",
    #    issue #1491's implementation plan, Decision 6), so a
    #    footer-bearing near-miss on terminal evidence always reaches this
    #    safe-fail rather than being misrouted to a wait/timeout.
    #
    # Note on "blocking issues" disambiguation: the phrase "blocking issues" appears
    # in both blocking context ("blocking issues: 1. foo") and clean context ("no
    # blocking issues found"). Requiring a colon after "issues" targets the blocking
    # list form while leaving the clean form to match the APPROVED branch via
    # "no blocking issues". This avoids false positives without line-level filtering
    # (which would risk missing a genuine marker on the same line as a negation).

    if [ "$BOT_RESPONSE_SOURCE" = "review" ] && { [ "$BOT_RESPONSE_REVIEW_STATE" = "CHANGES_REQUESTED" ] || codex_response_is_blocking "$BOT_RESPONSE_FULL"; }; then
      # Blocking is checked first, ahead of usage-limit: a terminal/review
      # finding whose text happens to mention "usage limit" as part of an
      # actionable finding (e.g. flagging stale docs that describe it) must
      # not be misrouted to an unavailable verdict before the blocking
      # classifier runs (fresh evidence from PR #1490 finding 3788078191).
      # A submitted review's own CHANGES_REQUESTED state short-circuits
      # straight to blocking here, ahead of free-text classification, so a
      # review GitHub itself marked as requesting changes is never
      # misclassified from its body wording alone (fresh evidence from PR
      # #1490 finding 3796396391).
      echo "VERDICT: NEEDS_REVISION"
      echo "---BEGIN BOT RESPONSE---"
      echo "$BOT_RESPONSE"
      echo "---END BOT RESPONSE---"
      exit 1
    elif codex_response_is_usage_limit "$(codex_strip_quoted_spans "$BOT_RESPONSE_FULL")"; then
      # Quote-stripped before checking: unlike the environment-error
      # check below (already safe — it's gated on source == "comment",
      # and a terminal SHA-pinned review always has source == "review" by
      # construction), this check has no source gate, since a genuine
      # usage-limit notice CAN legitimately arrive via the reviews
      # endpoint too. A clean terminal review that merely QUOTES an
      # actual quota message (e.g. "No blocking issues found. The docs
      # accurately quote: You have reached your Codex usage limits.")
      # was still reclassified as UNAVAILABLE without this stripping
      # (fresh evidence from PR #1490 finding 3793259351, a followup to
      # 3790122058/3793219190/3793219192).
      codex_return_usage_limit "$BOT_RESPONSE"
    elif codex_response_is_account_not_connected "$(codex_strip_quoted_spans "$BOT_RESPONSE_FULL")"; then
      # Same shape as the usage-limit branch: no source gate (the refusal can
      # arrive as a comment or a review) and quote-stripped first (#1522).
      codex_return_account_not_connected "$BOT_RESPONSE"
    elif [ "$BOT_RESPONSE_SOURCE" = "comment" ] && codex_response_is_environment_error "$BOT_RESPONSE_FULL"; then
      SEEN_ENVIRONMENT_ERROR=1
      SEEN_ENVIRONMENT_RESPONSE="$BOT_RESPONSE"
      SEEN_ENVIRONMENT_TIME="$COMBINED_TIME"
      echo "INFO: Codex environment setup response detected; waiting for fresh current-head review evidence"
      continue
    elif [ "$BOT_RESPONSE_SOURCE" = "review" ] && codex_response_is_approved "$BOT_RESPONSE_FULL"; then
      if [ "$SEEN_ENVIRONMENT_ERROR" -eq 1 ] && ! [ "$COMBINED_TIME" \> "$SEEN_ENVIRONMENT_TIME" ]; then
        codex_return_environment_error "$SEEN_ENVIRONMENT_RESPONSE"
      fi
      echo "VERDICT: APPROVED"
      echo "---BEGIN BOT RESPONSE---"
      echo "$BOT_RESPONSE"
      echo "---END BOT RESPONSE---"
      exit 0
    elif [ "$BOT_RESPONSE_SOURCE" != "review" ] && grep -qi "If Codex has suggestions, it will comment; otherwise it will react with" <<< "$BOT_RESPONSE_FULL"; then
      # Gated on non-terminal evidence (source != "review") — issue #1491's
      # implementation plan, Decision 6. Without this gate, a genuine Codex
      # response that carries the real footer but does not exactly match
      # CODEX_APPROVED_TEMPLATES also matches this acknowledgement text
      # (the footer's opening line), and terminal evidence would be
      # misrouted here (wait for more evidence) instead of the documented
      # NEEDS_REVISION safe-fail below, eventually timing out. A bare,
      # non-terminal acknowledgement-only comment can never have
      # source == "review" in the first place (codex_response_reviews_
      # current_head requires an extractable Reviewed-commit SHA), so this
      # narrowing removes only the one case (terminal evidence) this
      # branch was never meant to catch.
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
  | jq -sc --arg bot "$BOT_LOGIN" --arg bot_plain "$BOT_LOGIN_PLAIN" --arg trigger_time "$TRIGGER_TIME" --arg sha "$CURRENT_SHA_FULL" \
      '(add // []) | [.[] | select((.user.login == $bot or .user.login == $bot_plain) and .submitted_at != null and .submitted_at >= $trigger_time and ((.commit_id // "") == $sha) and ((.state // "") != "DISMISSED"))] | if length == 0 then empty else (map(.submitted_at) | max) as $latest | .[] | select(.submitted_at == $latest) | {created_at:(.submitted_at // ""), body:(.body // ""), state:(.state // "")} end' \
  > "$ASYNC_REVIEW_TMPFILE" 2>/dev/null; then
  # Selects every review tied at the latest timestamp and picks the one
  # requiring attention, if any (see rationale above the main-loop
  # equivalent). The body is NOT sliced here — see the main-loop comment
  # above for why classification needs the complete body (PR #1490 finding
  # 3789679344) and why this is still SIGPIPE-safe.
  codex_select_review_evidence "$ASYNC_REVIEW_TMPFILE"
  ASYNC_REVIEW_BODY="$SELECTED_REVIEW_BODY"
  ASYNC_REVIEW_TIME="$SELECTED_REVIEW_TIME"
  ASYNC_REVIEW_STATE="$SELECTED_REVIEW_STATE"
else
  rm -f "$ASYNC_REVIEW_TMPFILE"
  echo "VERDICT: TIMED_OUT — failed to fetch Codex PR reviews during async grace period (treated as unavailable)"
  exit 2
fi
rm -f "$ASYNC_REVIEW_TMPFILE"

codex_combine_terminal_evidence "async-arrival bot response" \
  "$COMMENT_TERMINAL_BODY" "$COMMENT_TERMINAL_TIME" \
  "$COMMENT_LATEST_BODY" "$COMMENT_LATEST_TIME" \
  "$ASYNC_REVIEW_BODY" "$ASYNC_REVIEW_TIME" "$COMMENT_LATEST_IS_TERMINAL" "$ASYNC_REVIEW_STATE"
ASYNC_BOT_RESPONSE="$COMBINED_BODY"
ASYNC_BOT_RESPONSE_SOURCE="$COMBINED_SOURCE"
# Captured before any intervening call could touch COMBINED_TIME (see
# rationale above the main-loop equivalent).
ASYNC_BOT_RESPONSE_TIME="$COMBINED_TIME"
# See rationale above the main-loop equivalent (BOT_RESPONSE_REVIEW_STATE).
ASYNC_BOT_RESPONSE_REVIEW_STATE="$COMBINED_REVIEW_STATE"
# Untruncated copy used for classification below (see rationale above the
# main-loop equivalent — a truncated copy could cut off a blocking marker
# in a long root comment).
ASYNC_BOT_RESPONSE_FULL="$ASYNC_BOT_RESPONSE"
# `jq -Rs` slurps its entire stdin before producing output, avoiding
# SIGPIPE on long root-comment-sourced bodies (see rationale above the
# main-loop equivalent).
ASYNC_BOT_RESPONSE=$(printf '%s' "$ASYNC_BOT_RESPONSE" | jq -Rrs '.[0:10000]')  # workflow-shell-guard: allow SH003 - jq -R treats input as raw text (not JSON), so it cannot fail on malformed content; a genuine jq internal failure still trips `set -e` since this is a bare assignment, which is the desired fail-closed behavior

if [ -n "$ASYNC_BOT_RESPONSE_TIME" ]; then
  echo "INFO: async-arrival bot response detected during grace period"
  codex_require_current_head

  # Apply the same three-path verdict parsing as the main poll loop.
  # Blocking is checked first, ahead of usage-limit (see rationale above
  # the main-loop equivalent).
  if [ "$ASYNC_BOT_RESPONSE_SOURCE" = "review" ] && { [ "$ASYNC_BOT_RESPONSE_REVIEW_STATE" = "CHANGES_REQUESTED" ] || codex_response_is_blocking "$ASYNC_BOT_RESPONSE_FULL"; }; then
    echo "VERDICT: NEEDS_REVISION"
    echo "---BEGIN BOT RESPONSE---"
    echo "$ASYNC_BOT_RESPONSE"
    echo "---END BOT RESPONSE---"
    exit 1
  elif codex_response_is_usage_limit "$(codex_strip_quoted_spans "$ASYNC_BOT_RESPONSE_FULL")"; then
    # Quote-stripped before checking — see the main-loop equivalent above
    # for the rationale (PR #1490 finding 3793259351).
    codex_return_usage_limit "$ASYNC_BOT_RESPONSE"
  elif codex_response_is_account_not_connected "$(codex_strip_quoted_spans "$ASYNC_BOT_RESPONSE_FULL")"; then
    # Same shape as the usage-limit branch above (#1522).
    codex_return_account_not_connected "$ASYNC_BOT_RESPONSE"
  elif [ "$ASYNC_BOT_RESPONSE_SOURCE" = "comment" ] && codex_response_is_environment_error "$ASYNC_BOT_RESPONSE_FULL"; then
    SEEN_ENVIRONMENT_ERROR=1
    SEEN_ENVIRONMENT_RESPONSE="$ASYNC_BOT_RESPONSE"
    SEEN_ENVIRONMENT_TIME="$COMBINED_TIME"
    echo "INFO: async-arrival Codex environment setup response detected without fresh review evidence"
  elif [ "$ASYNC_BOT_RESPONSE_SOURCE" = "review" ] && codex_response_is_approved "$ASYNC_BOT_RESPONSE_FULL"; then
    if [ "$SEEN_ENVIRONMENT_ERROR" -eq 1 ] && ! [ "$COMBINED_TIME" \> "$SEEN_ENVIRONMENT_TIME" ]; then
      codex_return_environment_error "$SEEN_ENVIRONMENT_RESPONSE"
    fi
    echo "VERDICT: APPROVED"
    echo "---BEGIN BOT RESPONSE---"
    echo "$ASYNC_BOT_RESPONSE"
    echo "---END BOT RESPONSE---"
    exit 0
  elif [ "$ASYNC_BOT_RESPONSE_SOURCE" != "review" ] && grep -qi "If Codex has suggestions, it will comment; otherwise it will react with" <<< "$ASYNC_BOT_RESPONSE_FULL"; then
    # Gated on non-terminal evidence — see the main-loop equivalent above
    # for the rationale (issue #1491's implementation plan, Decision 6).
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
      | jq -sc --arg bot "$BOT_LOGIN" --arg bot_plain "$BOT_LOGIN_PLAIN" --arg trigger_time "$TRIGGER_TIME" --arg sha "$CURRENT_SHA_FULL" \
          '(add // []) | [.[] | select((.user.login == $bot or .user.login == $bot_plain) and .submitted_at != null and .submitted_at >= $trigger_time and ((.commit_id // "") == $sha) and ((.state // "") != "DISMISSED"))] | if length == 0 then empty else (map(.submitted_at) | max) as $latest | .[] | select(.submitted_at == $latest) | {created_at:(.submitted_at // ""), body:(.body // ""), state:(.state // "")} end' \
      > "$ASYNC_FINAL_REVIEW_TMPFILE" 2>/dev/null; then
      # Selects every review tied at the latest timestamp and picks the one
      # requiring attention, if any (see rationale above the main-loop
      # equivalent). The body is NOT sliced here — see the main-loop
      # comment above for why classification needs the complete body (PR
      # #1490 finding 3789679344) and why this is still SIGPIPE-safe.
      codex_select_review_evidence "$ASYNC_FINAL_REVIEW_TMPFILE"
      ASYNC_FINAL_REVIEW_BODY="$SELECTED_REVIEW_BODY"
      ASYNC_FINAL_REVIEW_TIME="$SELECTED_REVIEW_TIME"
      ASYNC_FINAL_REVIEW_STATE="$SELECTED_REVIEW_STATE"
    else
      rm -f "$ASYNC_FINAL_REVIEW_TMPFILE"
      echo "VERDICT: TIMED_OUT — failed to fetch Codex PR reviews after async acknowledgement (treated as unavailable)"
      exit 2
    fi
    rm -f "$ASYNC_FINAL_REVIEW_TMPFILE"

    codex_combine_terminal_evidence "final async bot response" \
      "$COMMENT_TERMINAL_BODY" "$COMMENT_TERMINAL_TIME" \
      "$COMMENT_LATEST_BODY" "$COMMENT_LATEST_TIME" \
      "$ASYNC_FINAL_REVIEW_BODY" "$ASYNC_FINAL_REVIEW_TIME" "$COMMENT_LATEST_IS_TERMINAL" "$ASYNC_FINAL_REVIEW_STATE"
    ASYNC_FINAL_BOT_RESPONSE="$COMBINED_BODY"
    ASYNC_FINAL_BOT_RESPONSE_SOURCE="$COMBINED_SOURCE"
    # Captured before any intervening call could touch COMBINED_TIME (see
    # rationale above the main-loop equivalent).
    ASYNC_FINAL_BOT_RESPONSE_TIME="$COMBINED_TIME"
    # See rationale above the main-loop equivalent (BOT_RESPONSE_REVIEW_STATE).
    ASYNC_FINAL_BOT_RESPONSE_REVIEW_STATE="$COMBINED_REVIEW_STATE"
    # Untruncated copy used for classification below (see rationale above
    # the main-loop equivalent).
    ASYNC_FINAL_BOT_RESPONSE_FULL="$ASYNC_FINAL_BOT_RESPONSE"
    # `jq -Rs` slurps its entire stdin before producing output, avoiding
    # SIGPIPE on long root-comment-sourced bodies (see rationale above the
    # main-loop equivalent).
    ASYNC_FINAL_BOT_RESPONSE=$(printf '%s' "$ASYNC_FINAL_BOT_RESPONSE" | jq -Rrs '.[0:10000]')  # workflow-shell-guard: allow SH003 - jq -R treats input as raw text (not JSON), so it cannot fail on malformed content; a genuine jq internal failure still trips `set -e` since this is a bare assignment, which is the desired fail-closed behavior

    if [ -n "$ASYNC_FINAL_BOT_RESPONSE_TIME" ]; then
      echo "INFO: final async bot response detected after acknowledgement wait"
      codex_require_current_head
      # Blocking is checked first, ahead of usage-limit (see rationale
      # above the main-loop equivalent).
      if [ "$ASYNC_FINAL_BOT_RESPONSE_SOURCE" = "review" ] && { [ "$ASYNC_FINAL_BOT_RESPONSE_REVIEW_STATE" = "CHANGES_REQUESTED" ] || codex_response_is_blocking "$ASYNC_FINAL_BOT_RESPONSE_FULL"; }; then
        echo "VERDICT: NEEDS_REVISION"
        echo "---BEGIN BOT RESPONSE---"
        echo "$ASYNC_FINAL_BOT_RESPONSE"
        echo "---END BOT RESPONSE---"
        exit 1
      elif codex_response_is_usage_limit "$(codex_strip_quoted_spans "$ASYNC_FINAL_BOT_RESPONSE_FULL")"; then
        # Quote-stripped before checking — see the main-loop equivalent
        # above for the rationale (PR #1490 finding 3793259351).
        codex_return_usage_limit "$ASYNC_FINAL_BOT_RESPONSE"
      elif codex_response_is_account_not_connected "$(codex_strip_quoted_spans "$ASYNC_FINAL_BOT_RESPONSE_FULL")"; then
        # Same shape as the usage-limit branch above (#1522).
        codex_return_account_not_connected "$ASYNC_FINAL_BOT_RESPONSE"
      elif [ "$ASYNC_FINAL_BOT_RESPONSE_SOURCE" = "comment" ] && codex_response_is_environment_error "$ASYNC_FINAL_BOT_RESPONSE_FULL"; then
        SEEN_ENVIRONMENT_ERROR=1
        SEEN_ENVIRONMENT_RESPONSE="$ASYNC_FINAL_BOT_RESPONSE"
        SEEN_ENVIRONMENT_TIME="$COMBINED_TIME"
        echo "INFO: final async Codex environment setup response detected without fresh review evidence"
      elif [ "$ASYNC_FINAL_BOT_RESPONSE_SOURCE" = "review" ] && codex_response_is_approved "$ASYNC_FINAL_BOT_RESPONSE_FULL"; then
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
      elif [ "$ASYNC_FINAL_BOT_RESPONSE_SOURCE" = "review" ] || ! grep -qi "If Codex has suggestions, it will comment; otherwise it will react with" <<< "$ASYNC_FINAL_BOT_RESPONSE_FULL"; then
        # Gated on terminal evidence (source == "review") — issue #1491's
        # implementation plan, Decision 6. This branch is only reachable
        # for review-sourced (terminal) bodies to begin with (a bare
        # non-terminal comment is already caught by the `source ==
        # "comment"` branch immediately above), so the added
        # `[ SOURCE = "review" ]` condition makes this safe-fail
        # unconditional for every body that reaches this elif: without it,
        # a genuine terminal response carrying the real footer but not
        # exactly matching CODEX_APPROVED_TEMPLATES would silently fall
        # through to "wait" (no branch taken) instead of the documented
        # NEEDS_REVISION safe-fail, eventually timing out.
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
    | jq -sc --arg bot "$BOT_LOGIN" --arg bot_plain "$BOT_LOGIN_PLAIN" --arg trigger_time "$TRIGGER_TIME" --arg sha "$CURRENT_SHA_FULL" \
        '(add // []) | [.[] | select((.user.login == $bot or .user.login == $bot_plain) and .submitted_at != null and .submitted_at >= $trigger_time and ((.commit_id // "") == $sha) and ((.state // "") != "DISMISSED"))] | if length == 0 then empty else (map(.submitted_at) | max) as $latest | .[] | select(.submitted_at == $latest) | {created_at:(.submitted_at // ""), body:(.body // ""), state:(.state // "")} end' \
    > "$ASYNC_REACTION_FINAL_REVIEW_TMPFILE" 2>/dev/null; then
    # Selects every review tied at the latest timestamp and picks the one
    # requiring attention, if any (see rationale above the main-loop
    # equivalent). The body is NOT sliced here — see the main-loop comment
    # above for why classification needs the complete body (PR #1490
    # finding 3789679344) and why this is still SIGPIPE-safe.
    codex_select_review_evidence "$ASYNC_REACTION_FINAL_REVIEW_TMPFILE"
    ASYNC_REACTION_FINAL_REVIEW_BODY="$SELECTED_REVIEW_BODY"
    ASYNC_REACTION_FINAL_REVIEW_TIME="$SELECTED_REVIEW_TIME"
    ASYNC_REACTION_FINAL_REVIEW_STATE="$SELECTED_REVIEW_STATE"
  else
    rm -f "$ASYNC_REACTION_FINAL_REVIEW_TMPFILE"
    echo "VERDICT: TIMED_OUT — failed to fetch Codex PR reviews after async reaction (treated as unavailable)"
    exit 2
  fi
  rm -f "$ASYNC_REACTION_FINAL_REVIEW_TMPFILE"

  codex_combine_terminal_evidence "final async reaction bot response" \
    "$COMMENT_TERMINAL_BODY" "$COMMENT_TERMINAL_TIME" \
    "$COMMENT_LATEST_BODY" "$COMMENT_LATEST_TIME" \
    "$ASYNC_REACTION_FINAL_REVIEW_BODY" "$ASYNC_REACTION_FINAL_REVIEW_TIME" "$COMMENT_LATEST_IS_TERMINAL" "$ASYNC_REACTION_FINAL_REVIEW_STATE"
  ASYNC_REACTION_FINAL_BOT_RESPONSE="$COMBINED_BODY"
  ASYNC_REACTION_FINAL_BOT_RESPONSE_SOURCE="$COMBINED_SOURCE"
  # Captured before any intervening call could touch COMBINED_TIME (see
  # rationale above the main-loop equivalent).
  ASYNC_REACTION_FINAL_BOT_RESPONSE_TIME="$COMBINED_TIME"
  # See rationale above the main-loop equivalent (BOT_RESPONSE_REVIEW_STATE).
  ASYNC_REACTION_FINAL_BOT_RESPONSE_REVIEW_STATE="$COMBINED_REVIEW_STATE"
  # Untruncated copy used for classification below (see rationale above
  # the main-loop equivalent).
  ASYNC_REACTION_FINAL_BOT_RESPONSE_FULL="$ASYNC_REACTION_FINAL_BOT_RESPONSE"
  # `jq -Rs` slurps its entire stdin before producing output, avoiding
  # SIGPIPE on long root-comment-sourced bodies (see rationale above the
  # main-loop equivalent).
  ASYNC_REACTION_FINAL_BOT_RESPONSE=$(printf '%s' "$ASYNC_REACTION_FINAL_BOT_RESPONSE" | jq -Rrs '.[0:10000]')  # workflow-shell-guard: allow SH003 - jq -R treats input as raw text (not JSON), so it cannot fail on malformed content; a genuine jq internal failure still trips `set -e` since this is a bare assignment, which is the desired fail-closed behavior

  if [ -n "$ASYNC_REACTION_FINAL_BOT_RESPONSE_TIME" ]; then
    codex_require_current_head
    # Blocking is checked first, ahead of usage-limit (see rationale above
    # the main-loop equivalent).
    if [ "$ASYNC_REACTION_FINAL_BOT_RESPONSE_SOURCE" = "review" ] && { [ "$ASYNC_REACTION_FINAL_BOT_RESPONSE_REVIEW_STATE" = "CHANGES_REQUESTED" ] || codex_response_is_blocking "$ASYNC_REACTION_FINAL_BOT_RESPONSE_FULL"; }; then
      echo "VERDICT: NEEDS_REVISION"
      echo "---BEGIN BOT RESPONSE---"
      echo "$ASYNC_REACTION_FINAL_BOT_RESPONSE"
      echo "---END BOT RESPONSE---"
      exit 1
    elif codex_response_is_usage_limit "$(codex_strip_quoted_spans "$ASYNC_REACTION_FINAL_BOT_RESPONSE_FULL")"; then
      # Quote-stripped before checking — see the main-loop equivalent
      # above for the rationale (PR #1490 finding 3793259351).
      codex_return_usage_limit "$ASYNC_REACTION_FINAL_BOT_RESPONSE"
    elif codex_response_is_account_not_connected "$(codex_strip_quoted_spans "$ASYNC_REACTION_FINAL_BOT_RESPONSE_FULL")"; then
      # Same shape as the usage-limit branch above (#1522).
      codex_return_account_not_connected "$ASYNC_REACTION_FINAL_BOT_RESPONSE"
    elif [ "$ASYNC_REACTION_FINAL_BOT_RESPONSE_SOURCE" = "comment" ] && codex_response_is_environment_error "$ASYNC_REACTION_FINAL_BOT_RESPONSE_FULL"; then
      SEEN_ENVIRONMENT_ERROR=1
      SEEN_ENVIRONMENT_RESPONSE="$ASYNC_REACTION_FINAL_BOT_RESPONSE"
      SEEN_ENVIRONMENT_TIME="$COMBINED_TIME"
      echo "INFO: final async reaction Codex environment setup response detected without fresh review evidence"
    elif [ "$ASYNC_REACTION_FINAL_BOT_RESPONSE_SOURCE" = "review" ] && codex_response_is_approved "$ASYNC_REACTION_FINAL_BOT_RESPONSE_FULL"; then
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
    elif [ "$ASYNC_REACTION_FINAL_BOT_RESPONSE_SOURCE" = "review" ] || ! grep -qi "If Codex has suggestions, it will comment; otherwise it will react with" <<< "$ASYNC_REACTION_FINAL_BOT_RESPONSE_FULL"; then
      # Gated on terminal evidence (source == "review") — see the
      # async-final equivalent above for the rationale (issue #1491's
      # implementation plan, Decision 6).
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
