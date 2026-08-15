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
codex_response_is_usage_limit() {
  local response="$1"
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
  grep -qiE "to[[:space:]]+use[[:space:]]+codex[[:space:]]+here,[[:space:]]+create[[:space:]]+an[[:space:]]+environment[[:space:]]+for[[:space:]]+this[[:space:]]+repo" <<< "$response"
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
CODEX_BLOCKING_PATTERN='(changes[[:space:]]+requested|blocking[[:space:]]+issues?[[:space:]]*:|blocking[[:space:]]+finding|blocking:|must[[:space:]]+fix|action[[:space:]]+required|required:|❌)'
# \b word boundaries around the positive approval words: without them,
# "approved" as a bare substring matched inside prefixed negative forms
# like "unapproved" or "disapproved" (no space/word-break before
# "approved" in either), so a current-head response saying "This change
# remains unapproved" was still classified APPROVED instead of falling
# through to the documented safe-fail (fresh evidence from PR #1490
# finding 3789851555 — a followup to finding 3789722818, whose fix only
# handled SPACE-separated negations like "not approved"; \b closes the
# concatenated-negation-prefix gap that a space-only negation check
# cannot). Verified portable across BSD grep (macOS default), GNU grep,
# and ugrep — all treat \b as a GNU-style word-boundary extension in -E
# mode.
CODEX_APPROVAL_PATTERN='(\bapproved\b|\blgtm\b|\blooks[[:space:]]+good\b|didn.t find[[:space:]]+any major[[:space:]]+issues|no[[:space:]]+blocking[[:space:]]+issues?)'
# Negated forms of the approval phrases above. CODEX_APPROVAL_PATTERN's
# alternatives are unbounded substring matches, so a rejecting response
# like "This change is not approved" matched them unconditionally and was
# classified APPROVED instead of falling through to the documented
# unrecognized-format safe-fail. Checked BEFORE the positive approval
# pattern in codex_response_is_approved so a negated approval phrase can
# never be reported as approved.
#
# This went through several rounds of narrowly-scoped fixes (PR #1490
# findings 3789722818, 3789851555, 3789878264, 3789904716, 3789958775):
# require a negation word directly adjacent to the approval word, then
# tolerate a concatenated prefix ("unapproved"), then Markdown emphasis
# markers wedged in the middle ("**not** approved"), then a BOUNDED
# window of up to 3 intervening qualifier words ("not YET approved").
# Each fix narrowed one specific adjacency assumption and Codex found the
# next one, up to and including the bounded-window fix itself: 5
# intervening words ("I cannot confidently confirm that there are no
# blocking issues") exceeded the {0,3} bound (fresh evidence from PR
# #1490 finding 3789992792) — the reviewer's own stated remediation was
# "avoid relying on a bounded filler-word count".
#
# [^.!?]* (any character except a sentence terminator, UNBOUNDED) between
# the negation word and the approval word closes this whole class of gap
# at once: it matches a negation and an approval word co-occurring
# anywhere within the same sentence, regardless of how much text sits
# between them or how it's formatted (Markdown markers included, since
# they aren't excluded by the character class), while a period/!/?
# between them correctly prevents an unrelated LATER sentence's approval
# phrase from being treated as negated by an EARLIER sentence's negation
# word (e.g. "The variable name is not great. No blocking issues found."
# still classifies as approved).
#
# The target alternation had "approved" but not the bare verb "approve",
# so "I cannot approve this change" wasn't recognized (PR #1490 finding
# 3790023141). This is a forward negation-THEN-approval match: "cannot"
# precedes "approve" in that sentence, so adding the bare verb to the
# target list is sufficient on its own — no reverse-order (approval-word
# ... negation-word) alternative is needed. An earlier version of this
# fix DID add a reverse-order alternative, reasoning that "looks good"
# preceded "cannot" in the same example; that reverse check was over-
# broad in practice — it matched ANY later negation word in the same
# sentence regardless of what the negation actually referred to, so a
# genuinely clean response like "Looks good overall; tests were not run."
# (the negation refers to the unrelated "tests were not run" clause, not
# to the approval) was incorrectly flagged as negated (PR #1490 finding
# 3790062089). The reverse-order alternative has been removed; the
# forward-only match plus the bare-verb addition covers the original
# "cannot approve" case without this false-positive class.
CODEX_NEGATED_APPROVAL_TARGET_WORDS='(approve[ds]?|lgtm|look(s|ing)?[[:space:]]+good|no[[:space:]]+blocking[[:space:]]+issues?|didn.t find[[:space:]]+any major[[:space:]]+issues)'
CODEX_NEGATION_WORDS='(not|isn.t|is[[:space:]]+not|are[[:space:]]+not|aren.t|cannot|can.t|could[[:space:]]+not|couldn.t|will[[:space:]]+not|won.t|does[[:space:]]+not|doesn.t|never)'
CODEX_NEGATED_APPROVAL_PATTERN="${CODEX_NEGATION_WORDS}[^.!?]*${CODEX_NEGATED_APPROVAL_TARGET_WORDS}"

codex_response_is_blocking() {
  local body="$1"
  grep -qiE "$CODEX_BLOCKING_PATTERN" <<< "$body"
}

codex_response_is_approved() {
  local body="$1"
  if grep -qiE "$CODEX_NEGATED_APPROVAL_PATTERN" <<< "$body"; then
    return 1
  fi
  grep -qiE "$CODEX_APPROVAL_PATTERN" <<< "$body"
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
  if codex_response_is_blocking "$body"; then
    printf '3\n'
  elif codex_response_is_usage_limit "$body" || codex_response_is_environment_error "$body"; then
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
codex_select_terminal_evidence() {
  local current_body="$1" current_time="$2"
  local candidate_body="$3" candidate_time="$4"
  [ -z "$current_time" ] && return 0
  if [ "$candidate_time" \> "$current_time" ]; then
    return 0
  fi
  if [ "$candidate_time" = "$current_time" ]; then
    local candidate_priority current_priority
    candidate_priority=$(codex_response_priority "$candidate_body")
    current_priority=$(codex_response_priority "$current_body")
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
      if [ "$is_usage_limit" -eq 1 ] || codex_response_is_environment_error "$body"; then
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
# Sets: SELECTED_REVIEW_BODY, SELECTED_REVIEW_TIME.
codex_select_review_evidence() {
  local reviews_file="$1"
  SELECTED_REVIEW_BODY=""
  SELECTED_REVIEW_TIME=""
  # Presence is tracked via an explicit found-flag, not by checking
  # whether the selected body string is non-empty — a winning review's
  # body can legitimately be empty (see
  # codex_combine_terminal_evidence's review_time-based presence check
  # above), so inferring "not yet found" from string emptiness would
  # reintroduce that exact bug here.
  local have_selection=0
  local best_priority=-1
  local line created_at body priority
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    created_at=$(printf '%s' "$line" | jq -r '.created_at // empty')  # workflow-shell-guard: allow SH003 - $line is a compact JSON object already validated parseable by the preceding jq -sc call; empty is a normal absent-field case, not a failure
    body=$(printf '%s' "$line" | jq -r '.body // empty')  # workflow-shell-guard: allow SH003 - same pre-validated $line as above; empty body is not a failure
    priority=$(codex_response_priority "$body")
    if [ "$have_selection" -eq 0 ] || [ "$priority" -gt "$best_priority" ]; then
      SELECTED_REVIEW_BODY="$body"
      SELECTED_REVIEW_TIME="$created_at"
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
# or "" if no evidence at all). LABEL is used only for INFO logging.
# COMMENT_LATEST_IS_TERMINAL (8th arg) gates the ancillary-override check
# below: it must never fire when the "latest ancillary comment" IS
# actually the terminal comment itself, not a genuinely separate ancillary
# one (see the comment above that check).
codex_combine_terminal_evidence() {
  local label="$1"
  local comment_terminal_body="$2" comment_terminal_time="$3"
  local comment_latest_body="$4" comment_latest_time="$5"
  local review_body="$6" review_time="$7"
  local comment_latest_is_terminal="$8"

  COMBINED_BODY=""
  COMBINED_TIME=""
  COMBINED_SOURCE=""

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
    if [ -n "$COMBINED_SOURCE" ] && codex_response_is_blocking "$COMBINED_BODY"; then
      # Blocking terminal/review evidence always wins outright — it is
      # never discarded by a usage-limit notice, regardless of timing, so
      # an actionable finding can never be hidden behind an "unavailable"
      # verdict (fresh evidence from PR #1490 finding 3787943162; Protocol
      # 93 requires blocking evidence to never be silently discarded).
      :
    else
      COMBINED_BODY="$comment_latest_body"
      COMBINED_TIME="$comment_latest_time"
      COMBINED_SOURCE="comment"
      echo "INFO: $label usage-limit notice takes immediate precedence over terminal/review evidence, including same-fetch evidence"
    fi
  elif [ "$comment_latest_is_terminal" -eq 0 ] && [ -n "$comment_latest_body" ] && codex_response_is_environment_error "$comment_latest_body"; then
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
    | jq -sc --arg bot "$BOT_LOGIN" --arg bot_plain "$BOT_LOGIN_PLAIN" --arg trigger_time "$TRIGGER_TIME" --arg sha "$CURRENT_SHA" \
        '(add // []) | [.[] | select((.user.login == $bot or .user.login == $bot_plain) and .submitted_at != null and .submitted_at >= $trigger_time and ((.commit_id // "") | startswith($sha)))] | if length == 0 then empty else (map(.submitted_at) | max) as $latest | .[] | select(.submitted_at == $latest) | {created_at:(.submitted_at // ""), body:(.body // "")} end' \
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
    "$REVIEW_BODY" "$REVIEW_TIME" "$COMMENT_LATEST_IS_TERMINAL"
  BOT_RESPONSE="$COMBINED_BODY"
  BOT_RESPONSE_SOURCE="$COMBINED_SOURCE"
  # Captured immediately after combine, before any intervening call could
  # touch COMBINED_TIME, so presence can be checked below without relying
  # on BOT_RESPONSE's body being non-empty (fresh evidence from PR #1490
  # finding 3788164224: a bodyless-but-selected review must still enter
  # verdict parsing and hit the unrecognized-format safe-fail instead of
  # being treated as "no response at all").
  BOT_RESPONSE_TIME="$COMBINED_TIME"
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

    if [ "$BOT_RESPONSE_SOURCE" = "review" ] && codex_response_is_blocking "$BOT_RESPONSE_FULL"; then
      # Blocking is checked first, ahead of usage-limit: a terminal/review
      # finding whose text happens to mention "usage limit" as part of an
      # actionable finding (e.g. flagging stale docs that describe it) must
      # not be misrouted to an unavailable verdict before the blocking
      # classifier runs (fresh evidence from PR #1490 finding 3788078191).
      echo "VERDICT: NEEDS_REVISION"
      echo "---BEGIN BOT RESPONSE---"
      echo "$BOT_RESPONSE"
      echo "---END BOT RESPONSE---"
      exit 1
    elif codex_response_is_usage_limit "$BOT_RESPONSE_FULL"; then
      codex_return_usage_limit "$BOT_RESPONSE"
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
    elif grep -qi "If Codex has suggestions, it will comment; otherwise it will react with" <<< "$BOT_RESPONSE_FULL"; then
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
  | jq -sc --arg bot "$BOT_LOGIN" --arg bot_plain "$BOT_LOGIN_PLAIN" --arg trigger_time "$TRIGGER_TIME" --arg sha "$CURRENT_SHA" \
      '(add // []) | [.[] | select((.user.login == $bot or .user.login == $bot_plain) and .submitted_at != null and .submitted_at >= $trigger_time and ((.commit_id // "") | startswith($sha)))] | if length == 0 then empty else (map(.submitted_at) | max) as $latest | .[] | select(.submitted_at == $latest) | {created_at:(.submitted_at // ""), body:(.body // "")} end' \
  > "$ASYNC_REVIEW_TMPFILE" 2>/dev/null; then
  # Selects every review tied at the latest timestamp and picks the one
  # requiring attention, if any (see rationale above the main-loop
  # equivalent). The body is NOT sliced here — see the main-loop comment
  # above for why classification needs the complete body (PR #1490 finding
  # 3789679344) and why this is still SIGPIPE-safe.
  codex_select_review_evidence "$ASYNC_REVIEW_TMPFILE"
  ASYNC_REVIEW_BODY="$SELECTED_REVIEW_BODY"
  ASYNC_REVIEW_TIME="$SELECTED_REVIEW_TIME"
else
  rm -f "$ASYNC_REVIEW_TMPFILE"
  echo "VERDICT: TIMED_OUT — failed to fetch Codex PR reviews during async grace period (treated as unavailable)"
  exit 2
fi
rm -f "$ASYNC_REVIEW_TMPFILE"

codex_combine_terminal_evidence "async-arrival bot response" \
  "$COMMENT_TERMINAL_BODY" "$COMMENT_TERMINAL_TIME" \
  "$COMMENT_LATEST_BODY" "$COMMENT_LATEST_TIME" \
  "$ASYNC_REVIEW_BODY" "$ASYNC_REVIEW_TIME" "$COMMENT_LATEST_IS_TERMINAL"
ASYNC_BOT_RESPONSE="$COMBINED_BODY"
ASYNC_BOT_RESPONSE_SOURCE="$COMBINED_SOURCE"
# Captured before any intervening call could touch COMBINED_TIME (see
# rationale above the main-loop equivalent).
ASYNC_BOT_RESPONSE_TIME="$COMBINED_TIME"
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
  if [ "$ASYNC_BOT_RESPONSE_SOURCE" = "review" ] && codex_response_is_blocking "$ASYNC_BOT_RESPONSE_FULL"; then
    echo "VERDICT: NEEDS_REVISION"
    echo "---BEGIN BOT RESPONSE---"
    echo "$ASYNC_BOT_RESPONSE"
    echo "---END BOT RESPONSE---"
    exit 1
  elif codex_response_is_usage_limit "$ASYNC_BOT_RESPONSE_FULL"; then
    codex_return_usage_limit "$ASYNC_BOT_RESPONSE"
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
  elif grep -qi "If Codex has suggestions, it will comment; otherwise it will react with" <<< "$ASYNC_BOT_RESPONSE_FULL"; then
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
      | jq -sc --arg bot "$BOT_LOGIN" --arg bot_plain "$BOT_LOGIN_PLAIN" --arg trigger_time "$TRIGGER_TIME" --arg sha "$CURRENT_SHA" \
          '(add // []) | [.[] | select((.user.login == $bot or .user.login == $bot_plain) and .submitted_at != null and .submitted_at >= $trigger_time and ((.commit_id // "") | startswith($sha)))] | if length == 0 then empty else (map(.submitted_at) | max) as $latest | .[] | select(.submitted_at == $latest) | {created_at:(.submitted_at // ""), body:(.body // "")} end' \
      > "$ASYNC_FINAL_REVIEW_TMPFILE" 2>/dev/null; then
      # Selects every review tied at the latest timestamp and picks the one
      # requiring attention, if any (see rationale above the main-loop
      # equivalent). The body is NOT sliced here — see the main-loop
      # comment above for why classification needs the complete body (PR
      # #1490 finding 3789679344) and why this is still SIGPIPE-safe.
      codex_select_review_evidence "$ASYNC_FINAL_REVIEW_TMPFILE"
      ASYNC_FINAL_REVIEW_BODY="$SELECTED_REVIEW_BODY"
      ASYNC_FINAL_REVIEW_TIME="$SELECTED_REVIEW_TIME"
    else
      rm -f "$ASYNC_FINAL_REVIEW_TMPFILE"
      echo "VERDICT: TIMED_OUT — failed to fetch Codex PR reviews after async acknowledgement (treated as unavailable)"
      exit 2
    fi
    rm -f "$ASYNC_FINAL_REVIEW_TMPFILE"

    codex_combine_terminal_evidence "final async bot response" \
      "$COMMENT_TERMINAL_BODY" "$COMMENT_TERMINAL_TIME" \
      "$COMMENT_LATEST_BODY" "$COMMENT_LATEST_TIME" \
      "$ASYNC_FINAL_REVIEW_BODY" "$ASYNC_FINAL_REVIEW_TIME" "$COMMENT_LATEST_IS_TERMINAL"
    ASYNC_FINAL_BOT_RESPONSE="$COMBINED_BODY"
    ASYNC_FINAL_BOT_RESPONSE_SOURCE="$COMBINED_SOURCE"
    # Captured before any intervening call could touch COMBINED_TIME (see
    # rationale above the main-loop equivalent).
    ASYNC_FINAL_BOT_RESPONSE_TIME="$COMBINED_TIME"
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
      if [ "$ASYNC_FINAL_BOT_RESPONSE_SOURCE" = "review" ] && codex_response_is_blocking "$ASYNC_FINAL_BOT_RESPONSE_FULL"; then
        echo "VERDICT: NEEDS_REVISION"
        echo "---BEGIN BOT RESPONSE---"
        echo "$ASYNC_FINAL_BOT_RESPONSE"
        echo "---END BOT RESPONSE---"
        exit 1
      elif codex_response_is_usage_limit "$ASYNC_FINAL_BOT_RESPONSE_FULL"; then
        codex_return_usage_limit "$ASYNC_FINAL_BOT_RESPONSE"
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
      elif ! grep -qi "If Codex has suggestions, it will comment; otherwise it will react with" <<< "$ASYNC_FINAL_BOT_RESPONSE_FULL"; then
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
    | jq -sc --arg bot "$BOT_LOGIN" --arg bot_plain "$BOT_LOGIN_PLAIN" --arg trigger_time "$TRIGGER_TIME" --arg sha "$CURRENT_SHA" \
        '(add // []) | [.[] | select((.user.login == $bot or .user.login == $bot_plain) and .submitted_at != null and .submitted_at >= $trigger_time and ((.commit_id // "") | startswith($sha)))] | if length == 0 then empty else (map(.submitted_at) | max) as $latest | .[] | select(.submitted_at == $latest) | {created_at:(.submitted_at // ""), body:(.body // "")} end' \
    > "$ASYNC_REACTION_FINAL_REVIEW_TMPFILE" 2>/dev/null; then
    # Selects every review tied at the latest timestamp and picks the one
    # requiring attention, if any (see rationale above the main-loop
    # equivalent). The body is NOT sliced here — see the main-loop comment
    # above for why classification needs the complete body (PR #1490
    # finding 3789679344) and why this is still SIGPIPE-safe.
    codex_select_review_evidence "$ASYNC_REACTION_FINAL_REVIEW_TMPFILE"
    ASYNC_REACTION_FINAL_REVIEW_BODY="$SELECTED_REVIEW_BODY"
    ASYNC_REACTION_FINAL_REVIEW_TIME="$SELECTED_REVIEW_TIME"
  else
    rm -f "$ASYNC_REACTION_FINAL_REVIEW_TMPFILE"
    echo "VERDICT: TIMED_OUT — failed to fetch Codex PR reviews after async reaction (treated as unavailable)"
    exit 2
  fi
  rm -f "$ASYNC_REACTION_FINAL_REVIEW_TMPFILE"

  codex_combine_terminal_evidence "final async reaction bot response" \
    "$COMMENT_TERMINAL_BODY" "$COMMENT_TERMINAL_TIME" \
    "$COMMENT_LATEST_BODY" "$COMMENT_LATEST_TIME" \
    "$ASYNC_REACTION_FINAL_REVIEW_BODY" "$ASYNC_REACTION_FINAL_REVIEW_TIME" "$COMMENT_LATEST_IS_TERMINAL"
  ASYNC_REACTION_FINAL_BOT_RESPONSE="$COMBINED_BODY"
  ASYNC_REACTION_FINAL_BOT_RESPONSE_SOURCE="$COMBINED_SOURCE"
  # Captured before any intervening call could touch COMBINED_TIME (see
  # rationale above the main-loop equivalent).
  ASYNC_REACTION_FINAL_BOT_RESPONSE_TIME="$COMBINED_TIME"
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
    if [ "$ASYNC_REACTION_FINAL_BOT_RESPONSE_SOURCE" = "review" ] && codex_response_is_blocking "$ASYNC_REACTION_FINAL_BOT_RESPONSE_FULL"; then
      echo "VERDICT: NEEDS_REVISION"
      echo "---BEGIN BOT RESPONSE---"
      echo "$ASYNC_REACTION_FINAL_BOT_RESPONSE"
      echo "---END BOT RESPONSE---"
      exit 1
    elif codex_response_is_usage_limit "$ASYNC_REACTION_FINAL_BOT_RESPONSE_FULL"; then
      codex_return_usage_limit "$ASYNC_REACTION_FINAL_BOT_RESPONSE"
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
    elif ! grep -qi "If Codex has suggestions, it will comment; otherwise it will react with" <<< "$ASYNC_REACTION_FINAL_BOT_RESPONSE_FULL"; then
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
