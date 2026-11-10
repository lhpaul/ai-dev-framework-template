#!/usr/bin/env bash
# test-pr-review-loop-coderabbit-refusal.sh — pr-review-loop.sh harness: the
# CodeRabbit "Already reviewed the last commit" refusal recovery (#1591).
# duration: 240
# covers: scripts/development-workflow/pr-review-loop.sh
# covers: scripts/development-workflow/tests/lib/pr-review-loop-harness.sh
# covers: docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md
#
# The pr-review-loop.sh harness is split across these suites (#1876), which
# share their preamble — snapshot re-exec, --area filter, gh/git mocks, the
# HARNESS_MODE source of pr-review-loop.sh, and the run_test helpers — through
# tests/lib/pr-review-loop-harness.sh:
#
#   test-pr-review-loop.sh
#   test-pr-review-loop-cycles-labels.sh
#   test-pr-review-loop-failure-paths-1.sh
#   test-pr-review-loop-failure-paths-2.sh
#   test-pr-review-loop-failure-paths-3.sh
#   test-pr-review-loop-failure-paths-4.sh
#   test-pr-review-loop-release-bugbot.sh
#   test-pr-review-loop-pr-agent-coderabbit.sh
#   test-pr-review-loop-coderabbit-refusal.sh
#   test-pr-review-loop-staged-gates.sh
#   test-pr-review-loop-no-verdict-yet.sh
#
# Areas in this suite:
#   Area 1591: CodeRabbit 'Already reviewed the last commit' refusal (issue #1591)
#
# Usage: bash scripts/development-workflow/tests/test-pr-review-loop-coderabbit-refusal.sh [--area <name>]... [--list-areas]
# No external tooling required beyond bash, git, and jq (git only locates the
# repository root at startup; mock gh commands replace all network calls).
#
# Exit code: 0 if all tests pass, 1 if any test fails, 2 on a usage error.
#
# Many assignments here set pr-review-loop.sh globals that the functions under
# test read. ShellCheck does not follow that source, so each such assignment
# carries its own `# shellcheck disable=SC2034` with the reason inline.

set -euo pipefail

# Resolve the shared harness from the checked-in suite path. Inside a snapshot
# run $0 is a temp copy, so TEST_PR_REVIEW_LOOP_ORIGIN (set by the harness on
# re-exec, or by hand for an out-of-tree copy) takes precedence.
_prl_harness="$(dirname -- "${TEST_PR_REVIEW_LOOP_ORIGIN:-$0}")/lib/pr-review-loop-harness.sh"
if [ ! -f "$_prl_harness" ]; then
  echo "ERROR: shared harness not found: $_prl_harness" >&2
  echo "  Run the checked-in suite, or set TEST_PR_REVIEW_LOOP_ORIGIN to its path." >&2
  exit 2
fi
# shellcheck source=scripts/development-workflow/tests/lib/pr-review-loop-harness.sh
source "$_prl_harness" "$@"
unset _prl_harness

# Carried state. In the single-file harness, Area 13 exported this for every
# later area; keep the suites that held those areas running under the same
# environment so the split changes where tests live, not what they exercise.
export CODEX_GITHUB_PRE_TRIGGER_WAIT=0

# Carried state: Area 15 (test-pr-review-loop-release-bugbot.sh) left this
# exported for every later area in the single-file harness.
export MOCK_GH_OUTPUT='[]'

# ---------------------------------------------------------------------------
echo "=== Area 1591: CodeRabbit 'Already reviewed the last commit' refusal (issue #1591) ==="

# Fixture: the refusal body as fetched from PR #1588 on 2026-08-24T03:41:09Z
# (quoted in issue #1591). It is the real text, including the HTML marker and
# the mid-sentence line wrap — the visible sentence and the marker differ, and a
# hand-written fixture silently matches nothing.
_1591_refusal_body='<!-- CodeRabbit review command invocation: eda08424-098f-4422-b2c0-25f396a239de -->
⚠️ Action not completed
Already reviewed the last commit. Use `@coderabbitai full review` to rerun a
review of the entire changeset'
# The quota refusal shares the "Action not completed" wrapper but is a different
# state (issue #1591, comment 2). It must NOT be answered with a full review.
# No stated window: a stated one makes the loop wait that long, defeating the bounded run.
_1591_quota_body='<!-- CodeRabbit review command invocation: 6a1c0d2e-0000-4000-8000-000000000000 -->
⚠️ Action not completed
Review rate limited.'

# _1591_run <label> <comment-body> <comment-created> <max-retries> <dynamic> [max-wait]
# Runs the real run_coderabbit_review poll loop against a scripted gh whose
# issue-comments endpoint returns CodeRabbit comments with the given body.
#   dynamic=0: one comment, id 1000.
#   dynamic=1: one MORE comment (a fresh id) per `full review` the loop has
#              posted so far, modelling a vendor that answers every trigger with
#              a new refusal. All carry <comment-created>, which the tests pin
#              BEFORE any trigger the loop posts: a reply created in the same
#              second as (or before) the loop's recorded trigger time must still
#              be answered, so deduplication cannot depend on timestamps.
# The chosen directory is left in _1591_last_dir.
_1591_run() {
  local body="$2" created="$3" retries="$4" dynamic="$5" max_wait="${6:-4}"
  local dir
  dir="$(mktemp -d)"
  printf '%s' "$body" > "$dir/body.txt"
  export _1591_DIR="$dir" _1591_CREATED="$created" _1591_DYNAMIC="$dynamic" _1591_EXTRA_BODY="${_1591_EXTRA:-}" _1591_QUOTA_AFTER="${_1591_QUOTA:-0}" _1591_QUOTA_POLLS="${_1591_QUOTA_POLLS_N:-999999}" _1591_HOLD_POLLS="${_1591_HOLD_N:-}" _1591_OLDER_REFUSAL="${_1591_OLDER:-0}" _1591_QUOTA_FROM="${_1591_QFROM:-0}"
  cat > "$dir/gh" <<'CR_GH_1591'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$_1591_DIR/calls.log"
case "$*" in
  "auth status") exit 0 ;;
  *"repo view"*"nameWithOwner"*) printf 'owner/repo\n'; exit 0 ;;
  *"pulls/42 --jq .head.sha"*) printf 'sha1591\n'; exit 0 ;;
  *"commits/sha1591 --jq .commit.committer.date"*) printf '2000-01-01T00:00:00Z\n'; exit 0 ;;
  *"pr comment 42"*)
    # _1591_FAIL_FIRST=1: the first full-review POST fails (transient error).
    if [ "${_1591_FAIL_ALL:-0}" = 1 ]; then exit 1; fi
    if [ "${_1591_FAIL_FIRST:-0}" = 1 ] \
        && [ "$(grep -c 'pr comment 42 --body @coderabbitai full review' "$_1591_DIR/calls.log")" -le 1 ]; then
      exit 1
    fi
    exit 0 ;;
  *"issues/42/comments"*)
    n=0
    if [ "$_1591_DYNAMIC" = 1 ]; then
      n="$(grep -c 'pr comment 42 --body @coderabbitai full review' "$_1591_DIR/calls.log" || true)"
    fi
    # _1591_QUOTA_AFTER=1: once a full review has been posted, CodeRabbit answers it
    # with a live quota refusal created "now".
    q=""
    # _1591_QUOTA_POLLS=N: the refusal is served for the first N comment reads after
    # the full review, then the quota "expires" (the comment disappears).
    if [ "${_1591_QUOTA_AFTER:-0}" = 1 ] \
        && [ "$(grep -c 'pr comment 42 --body @coderabbitai full review' "$_1591_DIR/calls.log")" -ge 1 ] \
        && [ "$(awk '/pr comment 42 --body @coderabbitai full review/{f=1; next} f && /issues\/42\/comments/{c++} END{print c+0}' "$_1591_DIR/calls.log")" -le "${_1591_QUOTA_POLLS:-999999}" ] \
        && [ "$(awk '/pr comment 42 --body @coderabbitai full review/{f=1; next} f && /issues\/42\/comments/{c++} END{print c+0}' "$_1591_DIR/calls.log")" -ge "${_1591_QUOTA_FROM:-0}" ]; then
      q="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    fi
    # _1591_HOLD_POLLS=K: a live quota refusal is served for the first K comment
    # reads (the loop records a hold), then it expires and a walkthrough arrives.
    xb="${_1591_EXTRA_BODY:-}"
    if [ -n "${_1591_HOLD_POLLS:-}" ]; then
      reads="$(grep -c 'issues/42/comments' "$_1591_DIR/calls.log")"
      if [ "$reads" -le "$_1591_HOLD_POLLS" ]; then
        q="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
        xb=""
      else
        xb="## Walkthrough
CodeRabbit summary of the changes in this pull request."
      fi
    fi
    # _1591_OLDER_REFUSAL=1: an earlier refusal (e.g. of a previous plain trigger) is
    # still on the PR next to the newest one.
    older=""
    [ "${_1591_OLDER_REFUSAL:-0}" = 1 ] && older="2000-01-01T12:00:00Z"
    # same: the older refusal (smaller id) shares the newest one's created_at second.
    [ "${_1591_OLDER_REFUSAL:-0}" = same ] && older="$_1591_CREATED"
    jq -n --rawfile b "$_1591_DIR/body.txt" --arg c "$_1591_CREATED" --argjson n "${n:-0}" --arg x "$xb" --arg q "$q" --arg o "$older" \
      '[range(0; $n + 1) | {id: (1000 + .), user: {login: "coderabbitai[bot]"}, created_at: $c, updated_at: $c, body: $b}]
       + (if $x == "" then [] else [{id: 1, user: {login: "coderabbitai[bot]"}, created_at: $c, updated_at: $c, body: $x}] end)
       + (if $o == "" then [] else [{id: 5, user: {login: "coderabbitai[bot]"}, created_at: $o, updated_at: $o, body: $b}] end)
       + (if $q == "" then [] else [{id: 2, user: {login: "coderabbitai[bot]"}, created_at: $q, updated_at: $q, body: "⚠️ Action not completed\nReview rate limited."}] end)'
    exit 0 ;;
  *"api graphql"*)
    printf '{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[]}\n'; exit 0 ;;
  *) printf '[]\n'; exit 0 ;;
esac
CR_GH_1591
  chmod +x "$dir/gh"
  PATH="$dir:$PATH" CODERABBIT_NO_TRIGGER_TIMEOUT=999 CODERABBIT_RATE_LIMIT_MAX_RETRIES="$retries" \
    CODERABBIT_RATE_LIMIT_WAIT=1 CODERABBIT_RATE_LIMIT_MIN_WAIT=1 \
    run_coderabbit_review "42" "fix/42-test" "1" "$max_wait" >"$dir/stdout.log" 2>"$dir/stderr.log" || true
  _1591_last_dir="$dir"
  unset _1591_DIR _1591_CREATED _1591_DYNAMIC _1591_EXTRA_BODY _1591_QUOTA_AFTER _1591_QUOTA_POLLS _1591_HOLD_POLLS _1591_OLDER_REFUSAL _1591_QUOTA_FROM
}
_1591_count() { grep_count_or_zero "$1" "$2"; }
_1591_full='pr comment 42 --body @coderabbitai full review'

# After the mock head commit (2000-01-01) and before any trigger the loop posts.
_1591_before_trigger='2000-01-02T00:00:00Z'

# AC-1 / AC-2: the refusal is not activity, and answering it posts `full review`.
# One refusal that stays on the PR is answered once, not once per poll.
_1591_run answered "$_1591_refusal_body" "$_1591_before_trigger" 3 0
_1591_answered_dir="$_1591_last_dir"
run_test "1591_refusal_posts_full_review_exactly_once" "1" \
  "$(_1591_count "$_1591_full" "$_1591_answered_dir/calls.log")"
run_test "1591_refusal_logs_the_full_review_path" "yes" \
  "$([ "$(_1591_count "Already reviewed the last commit' for a head with no bound review" "$_1591_answered_dir/stderr.log")" -ge 1 ] && echo yes || echo no)"
run_test "1591_refusal_counts_as_a_trigger_attempt" "CODERABBIT_TRIGGER_ATTEMPTS=1" \
  "$(grep '^CODERABBIT_TRIGGER_ATTEMPTS=' "$_1591_answered_dir/stdout.log" | tail -n 1)"
run_test "1591_refusal_queried_issue_comments" "yes" \
  "$([ "$(_1591_count 'issues/42/comments' "$_1591_answered_dir/calls.log")" -ge 1 ] && echo yes || echo no)"

# Realistic ordering (reviewer finding): each full review draws a NEW refusal
# whose created_at is not after the loop's recorded trigger time. All of them
# must be answered up to the cap; a timestamp comparison would stop after one.
_1591_run capped "$_1591_refusal_body" "$_1591_before_trigger" 2 1 8
_1591_capped_dir="$_1591_last_dir"
run_test "1591_cap_bounds_full_review_posts_to_two" "2" \
  "$(_1591_count "$_1591_full" "$_1591_capped_dir/calls.log")"
_1591_run capped3 "$_1591_refusal_body" "$_1591_before_trigger" 3 1 10
_1591_capped3_dir="$_1591_last_dir"
run_test "1591_cap_of_three_posts_three" "3" \
  "$(_1591_count "$_1591_full" "$_1591_capped3_dir/calls.log")"

# A transient POST failure must not spend the cap (reviewer finding): with cap 1
# the first POST fails, the refusal stays unanswered, and the retry on the next
# poll succeeds — two attempts, one accepted.
export _1591_FAIL_FIRST=1
_1591_run failpost "$_1591_refusal_body" "$_1591_before_trigger" 1 0 8
_1591_failpost_dir="$_1591_last_dir"
unset _1591_FAIL_FIRST
run_test "1591_failed_post_does_not_spend_the_cap" "2" \
  "$(_1591_count "$_1591_full" "$_1591_failpost_dir/calls.log")"
run_test "1591_failed_post_then_retry_counts_one_accepted_trigger" "CODERABBIT_TRIGGER_ATTEMPTS=1" \
  "$(grep '^CODERABBIT_TRIGGER_ATTEMPTS=' "$_1591_failpost_dir/stdout.log" | tail -n 1)"

# A persistently failing POST must still end at max_wait (not loop forever):
# the run returns, and the posts are bounded by max_wait / poll interval.
export _1591_FAIL_ALL=1
_1591_run failall "$_1591_refusal_body" "$_1591_before_trigger" 3 0 8
_1591_failall_dir="$_1591_last_dir"
unset _1591_FAIL_ALL
run_test "1591_persistent_failed_post_is_bounded_by_max_wait" "yes" \
  "$([ "$(_1591_count "$_1591_full" "$_1591_failall_dir/calls.log")" -le 8 ] && echo yes || echo no)"

# A CodeRabbit walkthrough comment (generic activity, no commit binding) next to
# an unanswered refusal must not suppress the recovery (reviewer finding): the
# generic-activity flag does not mean a verdict is bound to the head.
_1591_EXTRA='## Walkthrough
CodeRabbit summary of the changes in this pull request.'
_1591_run walkthrough "$_1591_refusal_body" "$_1591_before_trigger" 1 0 8
unset _1591_EXTRA
_1591_walkthrough_dir="$_1591_last_dir"
run_test "1591_walkthrough_activity_does_not_suppress_the_recovery" "1" \
  "$(_1591_count "$_1591_full" "$_1591_walkthrough_dir/calls.log")"

# A refusal next to a LIVE rate limit is held, not answered (the #1597 rule
# applied to the new retrigger): exercises the refusal_blocked path itself, not
# only the matcher.
_1591_EXTRA='⚠️ Action not completed
Review rate limited.'
_1591_run held "$_1591_refusal_body" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" 1 0 3
unset _1591_EXTRA
_1591_held_dir="$_1591_last_dir"
run_test "1591_live_rate_limit_holds_the_refusal_retrigger" "0" \
  "$(_1591_count 'full review' "$_1591_held_dir/calls.log")"
run_test "1591_live_rate_limit_hold_is_logged" "yes" \
  "$([ "$(_1591_count 'holding the full-review retrigger until it elapses' "$_1591_held_dir/stderr.log")" -ge 1 ] && echo yes || echo no)"

# A quota-refused full review gives its slot back even when a walkthrough comment
# has set the generic-activity flag (reviewer finding): the refund must not live
# only inside the rate-limit block, which that flag gates off.
_1591_EXTRA='## Walkthrough
CodeRabbit summary of the changes in this pull request.'
_1591_QUOTA=1
_1591_run refund "$_1591_refusal_body" "$_1591_before_trigger" 1 0 8
unset _1591_EXTRA _1591_QUOTA
_1591_refund_dir="$_1591_last_dir"
run_test "1591_quota_refused_full_review_refund_survives_walkthrough_activity" "yes" \
  "$([ "$(_1591_count 'refunding its refusal slot' "$_1591_refund_dir/stderr.log")" -ge 1 ] && echo yes || echo no)"
run_test "1591_refunded_full_review_is_posted_once_while_the_limit_is_live" "1" \
  "$(_1591_count "$_1591_full" "$_1591_refund_dir/calls.log")"

# After the quota returns, the refused full review is asked for again even with a
# walkthrough present (reviewer finding): the refusal it answered is pending
# again, and with cap 1 the refunded slot allows exactly one more post.
_1591_EXTRA='## Walkthrough
CodeRabbit summary of the changes in this pull request.'
_1591_QUOTA=1
_1591_QUOTA_POLLS_N=2
_1591_run reask "$_1591_refusal_body" "$_1591_before_trigger" 1 0 12
unset _1591_EXTRA _1591_QUOTA _1591_QUOTA_POLLS_N
_1591_reask_dir="$_1591_last_dir"
run_test "1591_refusal_is_asked_again_after_the_quota_returns" "2" \
  "$(_1591_count "$_1591_full" "$_1591_reask_dir/calls.log")"

# A hold the loop recorded earlier must not disable the recovery once a walkthrough
# has set the generic-activity flag and the quota has expired (reviewer finding):
# the quota is revalidated live, not read from the historical hold flag.
_1591_HOLD_N=6
_1591_run holdthenwalk "$_1591_refusal_body" "$_1591_before_trigger" 1 0 15
unset _1591_HOLD_N
_1591_holdthenwalk_dir="$_1591_last_dir"
run_test "1591_recovery_survives_a_recorded_hold_then_walkthrough" "1" \
  "$(_1591_count "$_1591_full" "$_1591_holdthenwalk_dir/calls.log")"

# Two refusals on the PR (an older one from an earlier plain trigger, a newer one):
# one full review covers both, so the older one must not draw a second full review.
_1591_OLDER=1
_1591_run twoold "$_1591_refusal_body" "$_1591_before_trigger" 3 0 8
unset _1591_OLDER
_1591_twoold_dir="$_1591_last_dir"
run_test "1591_an_older_refusal_does_not_draw_a_second_full_review" "1" \
  "$(_1591_count "$_1591_full" "$_1591_twoold_dir/calls.log")"

# Same-second tie (reviewer finding): the older refusal shares the newest one's
# created_at second, and only its smaller comment id orders it first.
_1591_OLDER=same
_1591_run twosame "$_1591_refusal_body" "$_1591_before_trigger" 3 0 8
unset _1591_OLDER
_1591_twosame_dir="$_1591_last_dir"
run_test "1591_a_same_second_older_refusal_does_not_draw_a_second_full_review" "1" \
  "$(_1591_count "$_1591_full" "$_1591_twosame_dir/calls.log")"

# The quota reply is visible for exactly ONE comment read after the full review,
# at different positions, so it can be seen by the dedicated refund block or only
# by the later rate-limit block - and it has expired by the time that block's wait
# ends (reviewer finding). Wherever a lookup OBSERVED the reply, the refusal must
# be re-opened and asked again (two full reviews with cap 1). A position where no
# lookup read it (e.g. only the activity probe, which ignores rate-limit text) is
# not a refund case and is not asserted on, but both positions below must have
# been observed so the test cannot pass vacuously.
_1591_win_verdicts=""
_1591_win_dirs=()
for _1591_k in 3 5; do
  _1591_QUOTA=1
  _1591_QFROM="$_1591_k"
  _1591_QUOTA_POLLS_N="$_1591_k"
  _1591_run "window$_1591_k" "$_1591_refusal_body" "$_1591_before_trigger" 1 0 12
  unset _1591_QUOTA _1591_QFROM _1591_QUOTA_POLLS_N
  _1591_win_dirs+=("$_1591_last_dir")
  _1591_win_observed="$(_1591_count 'refunding its refusal slot' "$_1591_last_dir/stderr.log")"
  _1591_win_posts="$(_1591_count "$_1591_full" "$_1591_last_dir/calls.log")"
  if [ "$_1591_win_observed" -ge 1 ] && [ "$_1591_win_posts" -eq 2 ]; then
    _1591_win_verdicts="${_1591_win_verdicts:+$_1591_win_verdicts }observed-and-reasked"
  else
    _1591_win_verdicts="${_1591_win_verdicts:+$_1591_win_verdicts }observed=${_1591_win_observed}-posts=${_1591_win_posts}"
  fi
done
run_test "1591_a_quota_reply_seen_at_either_position_still_reopens_the_refusal" "observed-and-reasked observed-and-reasked" "$_1591_win_verdicts"

# AC-3 (c): cap 0 posts nothing.
_1591_run zerocap "$_1591_refusal_body" "$_1591_before_trigger" 0 1
_1591_zerocap_dir="$_1591_last_dir"
run_test "1591_cap_zero_posts_no_full_review" "0" \
  "$(_1591_count 'full review' "$_1591_zerocap_dir/calls.log")"

# AC-1 (a): the refusal must not read as review activity. Compare the cap-0
# outcome (retrigger disabled) with the same comment treated as activity
# (pattern disabled for this run only): the verdict must differ, or the
# exclusion is doing nothing.
_1591_real_re="$CODERABBIT_ALREADY_REVIEWED_RE"
# shellcheck disable=SC2034  # read by pr-review-loop.sh
CODERABBIT_ALREADY_REVIEWED_RE='matches-nothing-1591'
_1591_run mutated0 "$_1591_refusal_body" "$_1591_before_trigger" 0 1
_1591_mutated0_dir="$_1591_last_dir"
# shellcheck disable=SC2034  # read by pr-review-loop.sh
CODERABBIT_ALREADY_REVIEWED_RE="$_1591_real_re"
run_test "1591_refusal_not_activity_changes_the_verdict" "differs" \
  "$(cmp -s "$_1591_zerocap_dir/stdout.log" "$_1591_mutated0_dir/stdout.log" && echo same || echo differs)"

# A refusal older than the head commit (mock committer date 2000-01-01) belongs
# to an earlier head and is not answered.
_1591_run stale "$_1591_refusal_body" "1999-01-01T00:00:00Z" 3 1
_1591_stale_dir="$_1591_last_dir"
run_test "1591_refusal_older_than_head_is_not_answered" "0" \
  "$(_1591_count 'full review' "$_1591_stale_dir/calls.log")"

# The quota refusal shares the wrapper but must never be answered with a full
# review (keying on the wrapper would spend a review during a live limit).
# Created "now" so the limit is live; mirrors the #1597 live-limit fixture above.
_1591_run quota "$_1591_quota_body" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" 1 0 3
_1591_quota_dir="$_1591_last_dir"
run_test "1591_quota_refusal_is_not_answered_with_full_review" "0" \
  "$(_1591_count 'full review' "$_1591_quota_dir/calls.log")"

rm -rf "$_1591_answered_dir" "$_1591_capped_dir" "$_1591_capped3_dir" "$_1591_failpost_dir" "$_1591_walkthrough_dir" "$_1591_held_dir" "$_1591_refund_dir" "$_1591_reask_dir" "$_1591_holdthenwalk_dir" "$_1591_twoold_dir" "$_1591_twosame_dir" "$_1591_zerocap_dir" "$_1591_mutated0_dir" "$_1591_stale_dir" "$_1591_quota_dir" ${_1591_win_dirs[@]+"${_1591_win_dirs[@]}"}
unset -f _1591_run _1591_count
unset _1591_last_dir _1591_refusal_body _1591_quota_body _1591_before_trigger _1591_full _1591_real_re \
  _1591_answered_dir _1591_capped_dir _1591_capped3_dir _1591_failpost_dir _1591_walkthrough_dir _1591_held_dir _1591_refund_dir _1591_reask_dir _1591_holdthenwalk_dir _1591_twoold_dir _1591_twosame_dir _1591_zerocap_dir _1591_mutated0_dir _1591_stale_dir _1591_quota_dir

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "Tests: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
