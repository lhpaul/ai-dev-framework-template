#!/usr/bin/env bash
# shellcheck disable=SC2034
# test-pr-review-loop-failure-paths-2.sh — pr-review-loop.sh harness: Area 13
# (PR #801 failure paths), part 2 of 4.
# duration: 95
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
#   test-pr-review-loop-staged-gates.sh
#   test-pr-review-loop-no-verdict-yet.sh
#
# Areas in this suite:
#   Area 13: PR #801 reviewer-loop failure paths (part 2 of 4)
#
# Usage: bash scripts/development-workflow/tests/test-pr-review-loop-failure-paths-2.sh [--area <name>]... [--list-areas]
# No external tooling required beyond bash, git, and jq (git only locates the
# repository root at startup; mock gh commands replace all network calls).
#
# Exit code: 0 if all tests pass, 1 if any test fails, 2 on a usage error.
#
# SC2034 is disabled for the whole file (line 2). Most assignments here set
# pr-review-loop.sh globals that the functions under test read; ShellCheck does
# not follow that source, so it sees every one as unused. When the harness was
# a single file the warning stayed quiet only because some other area happened
# to read the same name — coincidence, not analysis.

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

# ---------------------------------------------------------------------------
# Area 13 (continued): PR #801 reviewer-loop failure paths, part 2 of 4
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 13: PR #801 reviewer-loop failure paths (part 2 of 4) ==="

# Reproduces Codex finding on PR #1490 (P1, comment id 3788118857): when
# the latest timestamp contains a bodyless submitted review tied with a
# clean SHA-pinned terminal comment, codex_combine_terminal_evidence's
# presence check `[ -n "$review_body" ]` treated the empty-bodied review as
# absent, so the clean terminal comment won by default and the script
# returned APPROVED — even though codex_response_requires_attention
# correctly classifies an empty body as unrecognized/requires-attention.
# Presence is now checked via review_time (guaranteed non-empty for any
# selected review by the poll query's filter), not review_body. Fixture:
# clean terminal comment, clean submitted review, and an empty submitted
# review, all tied at the same timestamp -> expect NOT APPROVED (the empty
# review participates in the tie-break and the script does not silently
# approve).
_codex_bodyless_tied_review_not_approved_mock_dir="$(mktemp -d)"
cat > "$_codex_bodyless_tied_review_not_approved_mock_dir/gh" <<'CODEX_BODYLESS_TIED_REVIEW_NOT_APPROVED_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'c0ffee001234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":200,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[{"submitted_at":"2026-01-01T00:00:01Z","commit_id":"c0ffee001234567890","user":{"login":"chatgpt-codex-connector[bot]"},"body":"No blocking issues found."},{"submitted_at":"2026-01-01T00:00:01Z","commit_id":"c0ffee001234567890","user":{"login":"chatgpt-codex-connector[bot]"},"body":""}]\n'
    exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"id":310,"created_at":"2026-01-01T00:00:01Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"Codex Review: Didn'\''t find any major issues.\\n\\n**Reviewed commit:** `c0ffee001234`"}]\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_BODYLESS_TIED_REVIEW_NOT_APPROVED_GH
chmod +x "$_codex_bodyless_tied_review_not_approved_mock_dir/gh"

_codex_bodyless_tied_review_not_approved_output=""
_codex_bodyless_tied_review_not_approved_exit=0
PATH="$_codex_bodyless_tied_review_not_approved_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_bodyless_tied_review_not_approved_mock_dir/output.txt" 2>&1 || _codex_bodyless_tied_review_not_approved_exit=$?
_codex_bodyless_tied_review_not_approved_output="$(cat "$_codex_bodyless_tied_review_not_approved_mock_dir/output.txt")"
run_test "codex_bodyless_tied_review_not_approved_verdict_not_approved" "0" \
  "$(printf '%s\n' "$_codex_bodyless_tied_review_not_approved_output" | grep -c "^VERDICT: APPROVED$" || true)"
rm -rf "$_codex_bodyless_tied_review_not_approved_mock_dir"
unset _codex_bodyless_tied_review_not_approved_mock_dir _codex_bodyless_tied_review_not_approved_output _codex_bodyless_tied_review_not_approved_exit

# Reproduces Codex finding on PR #1490 (P1, comment id 3788164224): the
# prior bodyless-tied-review fix made COMBINED_SOURCE/COMBINED_TIME record
# an empty-bodied review's presence, but the main-loop and async verdict
# paths still gated the "if -n $BOT_RESPONSE" verdict-parsing entry on the
# BODY being non-empty, so a bodyless winning review fell through to
# TIMED_OUT — a permissive-unavailable-policy consumer could treat that
# more leniently than the documented unrecognized-response safe-fail
# NEEDS_REVISION. Verdict-parsing entry is now gated on
# BOT_RESPONSE_TIME (captured from COMBINED_TIME right after combine)
# instead of BOT_RESPONSE body content. Same fixture as
# codex_bodyless_tied_review_not_approved, but asserts the exact expected
# verdict rather than only "not APPROVED".
_codex_bodyless_tied_review_needs_revision_mock_dir="$(mktemp -d)"
cat > "$_codex_bodyless_tied_review_needs_revision_mock_dir/gh" <<'CODEX_BODYLESS_TIED_REVIEW_NEEDS_REVISION_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'c0ffee001234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":200,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[{"submitted_at":"2026-01-01T00:00:01Z","commit_id":"c0ffee001234567890","user":{"login":"chatgpt-codex-connector[bot]"},"body":"No blocking issues found."},{"submitted_at":"2026-01-01T00:00:01Z","commit_id":"c0ffee001234567890","user":{"login":"chatgpt-codex-connector[bot]"},"body":""}]\n'
    exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"id":310,"created_at":"2026-01-01T00:00:01Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"Codex Review: Didn'\''t find any major issues.\\n\\n**Reviewed commit:** `c0ffee001234`"}]\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_BODYLESS_TIED_REVIEW_NEEDS_REVISION_GH
chmod +x "$_codex_bodyless_tied_review_needs_revision_mock_dir/gh"

_codex_bodyless_tied_review_needs_revision_output=""
_codex_bodyless_tied_review_needs_revision_exit=0
PATH="$_codex_bodyless_tied_review_needs_revision_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_bodyless_tied_review_needs_revision_mock_dir/output.txt" 2>&1 || _codex_bodyless_tied_review_needs_revision_exit=$?
_codex_bodyless_tied_review_needs_revision_output="$(cat "$_codex_bodyless_tied_review_needs_revision_mock_dir/output.txt")"
run_test "codex_bodyless_tied_review_needs_revision_exit" "2" "$_codex_bodyless_tied_review_needs_revision_exit"
run_test "codex_bodyless_tied_review_needs_revision_verdict" "VERDICT: ESCALATE — Codex terminal verdict matches neither an approved clean template nor the documented blocking markers" \
  "$(printf '%s\n' "$_codex_bodyless_tied_review_needs_revision_output" | grep "^VERDICT:")"
rm -rf "$_codex_bodyless_tied_review_needs_revision_mock_dir"
unset _codex_bodyless_tied_review_needs_revision_mock_dir _codex_bodyless_tied_review_needs_revision_output _codex_bodyless_tied_review_needs_revision_exit

# Reproduces Codex finding on PR #1490 (P1, comment id 3789477520):
# codex_select_review_evidence's scan stopped at the FIRST tied review
# that merely "requires attention" (which includes non-blocking types
# like usage-limit text), so a usage-limit review returned before a
# blocking review in the same tied timestamp silently discarded the
# blocker and the script emitted UNAVAILABLE instead of NEEDS_REVISION.
# Blocking is now scanned and prioritized independently of other
# attention-requiring types. Fixture: usage-limit review first in the
# array, blocking review second, both tied at the same timestamp.
_codex_tied_reviews_blocking_beats_usage_limit_mock_dir="$(mktemp -d)"
cat > "$_codex_tied_reviews_blocking_beats_usage_limit_mock_dir/gh" <<'CODEX_TIED_REVIEWS_BLOCKING_BEATS_USAGE_LIMIT_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'deadc0de1234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":210,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[{"submitted_at":"2026-01-01T00:00:01Z","commit_id":"deadc0de1234567890","user":{"login":"chatgpt-codex-connector[bot]"},"body":"You have reached your Codex usage limits for code reviews."},{"submitted_at":"2026-01-01T00:00:01Z","commit_id":"deadc0de1234567890","user":{"login":"chatgpt-codex-connector[bot]"},"body":"Blocking issues: must fix the null check."}]\n'
    exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_TIED_REVIEWS_BLOCKING_BEATS_USAGE_LIMIT_GH
chmod +x "$_codex_tied_reviews_blocking_beats_usage_limit_mock_dir/gh"

_codex_tied_reviews_blocking_beats_usage_limit_output=""
_codex_tied_reviews_blocking_beats_usage_limit_exit=0
PATH="$_codex_tied_reviews_blocking_beats_usage_limit_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_tied_reviews_blocking_beats_usage_limit_mock_dir/output.txt" 2>&1 || _codex_tied_reviews_blocking_beats_usage_limit_exit=$?
_codex_tied_reviews_blocking_beats_usage_limit_output="$(cat "$_codex_tied_reviews_blocking_beats_usage_limit_mock_dir/output.txt")"
run_test "codex_tied_reviews_blocking_beats_usage_limit_exit_needs_revision" "2" "$_codex_tied_reviews_blocking_beats_usage_limit_exit"
run_test "codex_tied_reviews_blocking_beats_usage_limit_verdict" "VERDICT: ESCALATE — Codex finding has no stable review-thread identifier or no identifiable matching review-thread conversation" \
  "$(printf '%s\n' "$_codex_tied_reviews_blocking_beats_usage_limit_output" | grep "^VERDICT:")"
rm -rf "$_codex_tied_reviews_blocking_beats_usage_limit_mock_dir"
unset _codex_tied_reviews_blocking_beats_usage_limit_mock_dir _codex_tied_reviews_blocking_beats_usage_limit_output _codex_tied_reviews_blocking_beats_usage_limit_exit

# Reproduces Codex finding on PR #1490 (P1, comment id 3789521036): the
# shared codex_select_terminal_evidence tie-break only checked the binary
# requires-attention distinction, so two tied responses that are BOTH
# "requires attention" (a usage-limit root comment and a blocking
# submitted review) kept whichever was CURRENT even when the candidate was
# strictly more severe (blocking). The prior d149 fix addressed only
# codex_select_review_evidence's own review-vs-review scan; this shared
# selector (used for terminal-comment-vs-review and terminal-comment-vs-
# terminal-comment ties) now checks blocking first. Fixture: a SHA-pinned
# terminal root comment reporting a usage limit, tied with a submitted
# blocking review, no acknowledgement.
_codex_terminal_usage_limit_vs_blocking_review_mock_dir="$(mktemp -d)"
cat > "$_codex_terminal_usage_limit_vs_blocking_review_mock_dir/gh" <<'CODEX_TERMINAL_USAGE_LIMIT_VS_BLOCKING_REVIEW_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'facade001234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":220,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[{"submitted_at":"2026-01-01T00:00:01Z","commit_id":"facade001234567890","user":{"login":"chatgpt-codex-connector[bot]"},"body":"Blocking issues: must fix the null check."}]\n'
    exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"id":320,"created_at":"2026-01-01T00:00:01Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"You have reached your Codex usage limits for code reviews.\\n\\n**Reviewed commit:** `facade001234`"}]\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_TERMINAL_USAGE_LIMIT_VS_BLOCKING_REVIEW_GH
chmod +x "$_codex_terminal_usage_limit_vs_blocking_review_mock_dir/gh"

_codex_terminal_usage_limit_vs_blocking_review_output=""
_codex_terminal_usage_limit_vs_blocking_review_exit=0
PATH="$_codex_terminal_usage_limit_vs_blocking_review_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_terminal_usage_limit_vs_blocking_review_mock_dir/output.txt" 2>&1 || _codex_terminal_usage_limit_vs_blocking_review_exit=$?
_codex_terminal_usage_limit_vs_blocking_review_output="$(cat "$_codex_terminal_usage_limit_vs_blocking_review_mock_dir/output.txt")"
run_test "codex_terminal_usage_limit_vs_blocking_review_exit_needs_revision" "2" "$_codex_terminal_usage_limit_vs_blocking_review_exit"
run_test "codex_terminal_usage_limit_vs_blocking_review_verdict" "VERDICT: ESCALATE — Codex finding has no stable review-thread identifier or no identifiable matching review-thread conversation" \
  "$(printf '%s\n' "$_codex_terminal_usage_limit_vs_blocking_review_output" | grep "^VERDICT:")"
rm -rf "$_codex_terminal_usage_limit_vs_blocking_review_mock_dir"
unset _codex_terminal_usage_limit_vs_blocking_review_mock_dir _codex_terminal_usage_limit_vs_blocking_review_output _codex_terminal_usage_limit_vs_blocking_review_exit

# Same finding (3789521036), second reproduction scenario explicitly
# called out in the finding text: "the same loss occurs between two tied
# root responses". Two SHA-pinned terminal root comments tied at the same
# timestamp — one reporting a usage limit, one blocking — no submitted
# review at all.
_codex_two_tied_terminal_comments_usage_limit_vs_blocking_mock_dir="$(mktemp -d)"
cat > "$_codex_two_tied_terminal_comments_usage_limit_vs_blocking_mock_dir/gh" <<'CODEX_TWO_TIED_TERMINAL_COMMENTS_USAGE_LIMIT_VS_BLOCKING_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'ba5eba1112345678\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":221,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"id":330,"created_at":"2026-01-01T00:00:01Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"You have reached your Codex usage limits for code reviews.\\n\\n**Reviewed commit:** `ba5eba111234`"},{"id":331,"created_at":"2026-01-01T00:00:01Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"Blocking issues: must fix the null check.\\n\\n**Reviewed commit:** `ba5eba111234`"}]\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_TWO_TIED_TERMINAL_COMMENTS_USAGE_LIMIT_VS_BLOCKING_GH
chmod +x "$_codex_two_tied_terminal_comments_usage_limit_vs_blocking_mock_dir/gh"

_codex_two_tied_terminal_comments_usage_limit_vs_blocking_output=""
_codex_two_tied_terminal_comments_usage_limit_vs_blocking_exit=0
PATH="$_codex_two_tied_terminal_comments_usage_limit_vs_blocking_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_two_tied_terminal_comments_usage_limit_vs_blocking_mock_dir/output.txt" 2>&1 || _codex_two_tied_terminal_comments_usage_limit_vs_blocking_exit=$?
_codex_two_tied_terminal_comments_usage_limit_vs_blocking_output="$(cat "$_codex_two_tied_terminal_comments_usage_limit_vs_blocking_mock_dir/output.txt")"
run_test "codex_two_tied_terminal_comments_usage_limit_vs_blocking_exit_needs_revision" "2" "$_codex_two_tied_terminal_comments_usage_limit_vs_blocking_exit"
run_test "codex_two_tied_terminal_comments_usage_limit_vs_blocking_verdict" "VERDICT: ESCALATE — Codex finding has no stable review-thread identifier or no identifiable matching review-thread conversation" \
  "$(printf '%s\n' "$_codex_two_tied_terminal_comments_usage_limit_vs_blocking_output" | grep "^VERDICT:")"
rm -rf "$_codex_two_tied_terminal_comments_usage_limit_vs_blocking_mock_dir"
unset _codex_two_tied_terminal_comments_usage_limit_vs_blocking_mock_dir _codex_two_tied_terminal_comments_usage_limit_vs_blocking_output _codex_two_tied_terminal_comments_usage_limit_vs_blocking_exit

# Reproduces Codex finding on PR #1490 (P1, comment id 3789555934): the
# earlier mixed-blocking-and-approval fix to codex_response_requires_attention
# checked only codex_response_is_blocking alongside is_approved, leaving the
# analogous mixed-usage-limit-and-approval case unguarded. A usage-limit
# response that ALSO contains an approval phrase (e.g. "No blocking issues
# could be evaluated because you have reached your Codex usage limits")
# matched the approval pattern and was classified as NOT requiring
# attention, so codex_select_review_evidence kept a tied clean review
# instead, returning APPROVED instead of UNAVAILABLE. requires_attention
# now also checks codex_response_is_usage_limit. Fixture: clean review
# first in the array, mixed usage-limit+approval review second, both tied.
#
# The clean review's body must reproduce a real CODEX_APPROVED_TEMPLATES
# entry (issue #1491's conservative-verdict-classifier implementation
# plan): codex_response_priority ranks an unrecognized body (2) ABOVE
# usage-limit (1), so once this fixture's clean-review body stopped
# reproducing a template it would rank as "unrecognized" and win the tie
# against the usage-limit review by coincidence of tier ordering, not
# because the usage-limit review was correctly classified — silently
# absorbing the exact regression this scenario exists to catch (the same
# failure mode Codex GitHub finding `3805611400` identified for
# codex_usage_limit_topic_mention_not_quota's competing fixture).
_codex_tied_usage_limit_with_approval_phrase_mock_dir="$(mktemp -d)"
cat > "$_codex_tied_usage_limit_with_approval_phrase_mock_dir/gh" <<'CODEX_TIED_USAGE_LIMIT_WITH_APPROVAL_PHRASE_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'feedc0de1234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":230,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    jq -nc '[{submitted_at:"2026-01-01T00:00:01Z",commit_id:"feedc0de1234567890",user:{login:"chatgpt-codex-connector[bot]"},body:("Codex Review: Didn'\''t find any major issues. Swish! **Reviewed commit:** `2222222222` <details> <summary>ℹ️ About Codex in GitHub</summary> <br/> [Your team has set up Codex to review pull requests in this repo](https://chatgpt.com/codex/cloud/settings/general). Reviews are triggered when you - Open a pull request for review - Mark a draft as ready - Comment \"@codex review\". If Codex has suggestions, it will comment; otherwise it will react with 👍. Codex can also answer questions or update the PR. Try commenting \"@codex address that feedback\". </details>")},{submitted_at:"2026-01-01T00:00:01Z",commit_id:"feedc0de1234567890",user:{login:"chatgpt-codex-connector[bot]"},body:"No blocking issues could be evaluated because you have reached your Codex usage limits."}]'
    exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_TIED_USAGE_LIMIT_WITH_APPROVAL_PHRASE_GH
chmod +x "$_codex_tied_usage_limit_with_approval_phrase_mock_dir/gh"

_codex_tied_usage_limit_with_approval_phrase_output=""
_codex_tied_usage_limit_with_approval_phrase_exit=0
PATH="$_codex_tied_usage_limit_with_approval_phrase_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_tied_usage_limit_with_approval_phrase_mock_dir/output.txt" 2>&1 || _codex_tied_usage_limit_with_approval_phrase_exit=$?
_codex_tied_usage_limit_with_approval_phrase_output="$(cat "$_codex_tied_usage_limit_with_approval_phrase_mock_dir/output.txt")"
run_test "codex_tied_usage_limit_with_approval_phrase_exit_unavailable" "3" "$_codex_tied_usage_limit_with_approval_phrase_exit"
run_test "codex_tied_usage_limit_with_approval_phrase_verdict" "VERDICT: UNAVAILABLE — Codex GitHub review usage limit reached" \
  "$(printf '%s\n' "$_codex_tied_usage_limit_with_approval_phrase_output" | grep "^VERDICT:")"
rm -rf "$_codex_tied_usage_limit_with_approval_phrase_mock_dir"
unset _codex_tied_usage_limit_with_approval_phrase_mock_dir _codex_tied_usage_limit_with_approval_phrase_output _codex_tied_usage_limit_with_approval_phrase_exit

# Reproduces Codex finding on PR #1490 (P1, comment id 3789597796): the
# binary requires-attention distinction put usage-limit and unrecognized-
# format responses into the same generic "attention" tier, so scanning
# stopped at whichever one was seen first — a usage-limit response
# (matching an approval phrase too) returned before a genuinely
# unrecognized-format response silently retained the usage-limit response,
# emitting UNAVAILABLE instead of the documented unrecognized-response
# NEEDS_REVISION safe-fail. A permissive unavailable policy could
# therefore hide a potentially rejecting response. codex_response_priority
# now ranks unrecognized-format (2) above usage-limit (1) explicitly.
# Fixture: usage-limit+approval-phrase review first in the array,
# genuinely unrecognized-format review second, both tied.
_codex_tied_usage_limit_then_unrecognized_mock_dir="$(mktemp -d)"
cat > "$_codex_tied_usage_limit_then_unrecognized_mock_dir/gh" <<'CODEX_TIED_USAGE_LIMIT_THEN_UNRECOGNIZED_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'a1a1a1a1234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":240,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[{"submitted_at":"2026-01-01T00:00:01Z","commit_id":"a1a1a1a1234567890","user":{"login":"chatgpt-codex-connector[bot]"},"body":"No blocking issues could be evaluated because you have reached your Codex usage limits."},{"submitted_at":"2026-01-01T00:00:01Z","commit_id":"a1a1a1a1234567890","user":{"login":"chatgpt-codex-connector[bot]"},"body":"Something ambiguous happened here."}]\n'
    exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_TIED_USAGE_LIMIT_THEN_UNRECOGNIZED_GH
chmod +x "$_codex_tied_usage_limit_then_unrecognized_mock_dir/gh"

_codex_tied_usage_limit_then_unrecognized_output=""
_codex_tied_usage_limit_then_unrecognized_exit=0
PATH="$_codex_tied_usage_limit_then_unrecognized_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_tied_usage_limit_then_unrecognized_mock_dir/output.txt" 2>&1 || _codex_tied_usage_limit_then_unrecognized_exit=$?
_codex_tied_usage_limit_then_unrecognized_output="$(cat "$_codex_tied_usage_limit_then_unrecognized_mock_dir/output.txt")"
run_test "codex_tied_usage_limit_then_unrecognized_exit" "2" "$_codex_tied_usage_limit_then_unrecognized_exit"
run_test "codex_tied_usage_limit_then_unrecognized_verdict" "VERDICT: ESCALATE — Codex terminal verdict matches neither an approved clean template nor the documented blocking markers" \
  "$(printf '%s\n' "$_codex_tied_usage_limit_then_unrecognized_output" | grep "^VERDICT:")"
rm -rf "$_codex_tied_usage_limit_then_unrecognized_mock_dir"
unset _codex_tied_usage_limit_then_unrecognized_mock_dir _codex_tied_usage_limit_then_unrecognized_output _codex_tied_usage_limit_then_unrecognized_exit

# Reproduces Codex finding on PR #1490 (P1, comment id 3789634709): the
# post-combine truncation to 10000 chars ran BEFORE the verdict-parsing
# classification checks, so a SHA-pinned root review exceeding 10000
# characters with an approval phrase before the cutoff and a blocking
# marker after it had its blocker silently cut off, classifying the
# truncated (approval-only) text as APPROVED. Classification now runs
# against BOT_RESPONSE_FULL (untruncated); BOT_RESPONSE (truncated) is
# used only for the script's own "---BEGIN/END BOT RESPONSE---" display.
# Fixture: a 15000+ char root comment with a clean approval phrase near
# the start and a blocking marker well past the 10000-char cutoff.
_codex_long_root_review_blocker_past_cutoff_mock_dir="$(mktemp -d)"
cat > "$_codex_long_root_review_blocker_past_cutoff_mock_dir/gh" <<'CODEX_LONG_ROOT_REVIEW_BLOCKER_PAST_CUTOFF_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'deadface1234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":250,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    jq -nc '[{id:340,created_at:"2026-01-01T00:00:01Z",user:{login:"chatgpt-codex-connector[bot]"},body:("No blocking issues found.\n\n" + ("x" * 15000) + "\n\nBlocking issues: must fix the leak past the cutoff.\n\n**Reviewed commit:** `deadface1234`")}]'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_LONG_ROOT_REVIEW_BLOCKER_PAST_CUTOFF_GH
chmod +x "$_codex_long_root_review_blocker_past_cutoff_mock_dir/gh"

_codex_long_root_review_blocker_past_cutoff_output=""
_codex_long_root_review_blocker_past_cutoff_exit=0
PATH="$_codex_long_root_review_blocker_past_cutoff_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_long_root_review_blocker_past_cutoff_mock_dir/output.txt" 2>&1 || _codex_long_root_review_blocker_past_cutoff_exit=$?
_codex_long_root_review_blocker_past_cutoff_output="$(cat "$_codex_long_root_review_blocker_past_cutoff_mock_dir/output.txt")"
run_test "codex_long_root_review_blocker_past_cutoff_exit_needs_revision" "2" "$_codex_long_root_review_blocker_past_cutoff_exit"
run_test "codex_long_root_review_blocker_past_cutoff_verdict" "VERDICT: ESCALATE — Codex finding has no stable review-thread identifier or no identifiable matching review-thread conversation" \
  "$(printf '%s\n' "$_codex_long_root_review_blocker_past_cutoff_output" | grep "^VERDICT:")"
rm -rf "$_codex_long_root_review_blocker_past_cutoff_mock_dir"
unset _codex_long_root_review_blocker_past_cutoff_mock_dir _codex_long_root_review_blocker_past_cutoff_output _codex_long_root_review_blocker_past_cutoff_exit

# Same class of bug as codex_long_root_review_blocker_past_cutoff, but one
# layer further upstream: the reviews-endpoint jq QUERY itself used to slice
# the body to 5000 chars (`.[0:5000]`) before the result ever reached
# BOT_RESPONSE_FULL, so a submitted review with an approval phrase before
# the cutoff and a blocking marker past it was misclassified as APPROVED
# even though the shell-level classify-full/truncate-only-for-display fix
# was already in place (fresh evidence from PR #1490 finding 3789679344).
# Fixture: a single submitted review whose body is a clean "no blocking
# issues found" phrase followed by 5000+ chars of padding and then a
# blocking marker.
_codex_long_review_blocker_past_query_cutoff_mock_dir="$(mktemp -d)"
cat > "$_codex_long_review_blocker_past_query_cutoff_mock_dir/gh" <<'CODEX_LONG_REVIEW_BLOCKER_PAST_QUERY_CUTOFF_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'facade001234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":251,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    jq -nc '[{submitted_at:"2026-01-01T00:00:01Z",commit_id:"facade001234567890",user:{login:"chatgpt-codex-connector[bot]"},body:("No blocking issues found.\n\n" + ("x" * 5200) + "\n\nBlocking issues: must fix the leak past the query-level cutoff.")}]'
    exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_LONG_REVIEW_BLOCKER_PAST_QUERY_CUTOFF_GH
chmod +x "$_codex_long_review_blocker_past_query_cutoff_mock_dir/gh"

_codex_long_review_blocker_past_query_cutoff_output=""
_codex_long_review_blocker_past_query_cutoff_exit=0
PATH="$_codex_long_review_blocker_past_query_cutoff_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_long_review_blocker_past_query_cutoff_mock_dir/output.txt" 2>&1 || _codex_long_review_blocker_past_query_cutoff_exit=$?
_codex_long_review_blocker_past_query_cutoff_output="$(cat "$_codex_long_review_blocker_past_query_cutoff_mock_dir/output.txt")"
run_test "codex_long_review_blocker_past_query_cutoff_exit_needs_revision" "2" "$_codex_long_review_blocker_past_query_cutoff_exit"
run_test "codex_long_review_blocker_past_query_cutoff_verdict" "VERDICT: ESCALATE — Codex finding has no stable review-thread identifier or no identifiable matching review-thread conversation" \
  "$(printf '%s\n' "$_codex_long_review_blocker_past_query_cutoff_output" | grep "^VERDICT:")"
rm -rf "$_codex_long_review_blocker_past_query_cutoff_mock_dir"
unset _codex_long_review_blocker_past_query_cutoff_mock_dir _codex_long_review_blocker_past_query_cutoff_output _codex_long_review_blocker_past_query_cutoff_exit

# CODEX_APPROVAL_PATTERN's "approved" alternative is an unbounded substring
# match, so a SHA-pinned terminal response REJECTING the change by saying
# "This change is not approved" used to match it unconditionally and get
# reported as APPROVED instead of falling through to the documented
# unrecognized-format safe-fail (fresh evidence from PR #1490 finding
# 3789722818).
_codex_negated_approval_root_comment_mock_dir="$(mktemp -d)"
cat > "$_codex_negated_approval_root_comment_mock_dir/gh" <<'CODEX_NEGATED_APPROVAL_ROOT_COMMENT_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'facade003a1234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":252,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"id":253,"created_at":"2026-01-01T00:00:01Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"This change is not approved. Needs more work before it can ship.\\n\\n**Reviewed commit:** `facade003a`"}]\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_NEGATED_APPROVAL_ROOT_COMMENT_GH
chmod +x "$_codex_negated_approval_root_comment_mock_dir/gh"

_codex_negated_approval_root_comment_output=""
_codex_negated_approval_root_comment_exit=0
PATH="$_codex_negated_approval_root_comment_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_negated_approval_root_comment_mock_dir/output.txt" 2>&1 || _codex_negated_approval_root_comment_exit=$?
_codex_negated_approval_root_comment_output="$(cat "$_codex_negated_approval_root_comment_mock_dir/output.txt")"
run_test "codex_negated_approval_root_comment_exit_needs_revision" "2" "$_codex_negated_approval_root_comment_exit"
run_test "codex_negated_approval_root_comment_verdict" "VERDICT: ESCALATE — Codex terminal verdict matches neither an approved clean template nor the documented blocking markers" \
  "$(printf '%s\n' "$_codex_negated_approval_root_comment_output" | grep "^VERDICT:")"
rm -rf "$_codex_negated_approval_root_comment_mock_dir"
unset _codex_negated_approval_root_comment_mock_dir _codex_negated_approval_root_comment_output _codex_negated_approval_root_comment_exit

# Followup to codex_negated_approval_root_comment: CODEX_NEGATED_APPROVAL_
# PATTERN only catches SPACE-separated negations ("not approved"). A
# CONCATENATED negation prefix like "unapproved" or "disapproved" still
# matched the bare "approved" substring in CODEX_APPROVAL_PATTERN, so a
# current-head response saying "This change remains unapproved" was still
# classified APPROVED (fresh evidence from PR #1490 finding 3789851555).
# CODEX_APPROVAL_PATTERN's positive alternatives now require \b word
# boundaries, which "un"/"a" and "dis"/"a" do not form.
_codex_unapproved_prefix_root_comment_mock_dir="$(mktemp -d)"
cat > "$_codex_unapproved_prefix_root_comment_mock_dir/gh" <<'CODEX_UNAPPROVED_PREFIX_ROOT_COMMENT_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'facade005c1234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":256,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"id":257,"created_at":"2026-01-01T00:00:01Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"This change remains unapproved pending further work.\\n\\n**Reviewed commit:** `facade005c`"}]\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_UNAPPROVED_PREFIX_ROOT_COMMENT_GH
chmod +x "$_codex_unapproved_prefix_root_comment_mock_dir/gh"

_codex_unapproved_prefix_root_comment_output=""
_codex_unapproved_prefix_root_comment_exit=0
PATH="$_codex_unapproved_prefix_root_comment_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_unapproved_prefix_root_comment_mock_dir/output.txt" 2>&1 || _codex_unapproved_prefix_root_comment_exit=$?
_codex_unapproved_prefix_root_comment_output="$(cat "$_codex_unapproved_prefix_root_comment_mock_dir/output.txt")"
run_test "codex_unapproved_prefix_root_comment_exit_needs_revision" "2" "$_codex_unapproved_prefix_root_comment_exit"
run_test "codex_unapproved_prefix_root_comment_verdict" "VERDICT: ESCALATE — Codex terminal verdict matches neither an approved clean template nor the documented blocking markers" \
  "$(printf '%s\n' "$_codex_unapproved_prefix_root_comment_output" | grep "^VERDICT:")"
rm -rf "$_codex_unapproved_prefix_root_comment_mock_dir"
unset _codex_unapproved_prefix_root_comment_mock_dir _codex_unapproved_prefix_root_comment_output _codex_unapproved_prefix_root_comment_exit

# Followup to codex_negated_approval_root_comment/codex_unapproved_prefix_
# root_comment: CODEX_NEGATED_APPROVAL_PATTERN required an unbroken
# [[:space:]]+ directly between the negation word and the approval word,
# so GitHub's rendered Markdown bold ("This change is **not** approved")
# — whose raw text has "**" wedged between "not" and the following
# space — did not match, and the bare \bapproved\b in
# CODEX_APPROVAL_PATTERN still did, misclassifying the rejection as
# APPROVED (fresh evidence from PR #1490 finding 3789878264).
# CODEX_NEGATED_APPROVAL_PATTERN now tolerates optional Markdown emphasis
# markers between the negation and approval words.
_codex_markdown_negated_approval_root_comment_mock_dir="$(mktemp -d)"
cat > "$_codex_markdown_negated_approval_root_comment_mock_dir/gh" <<'CODEX_MARKDOWN_NEGATED_APPROVAL_ROOT_COMMENT_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'facade006d1234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":258,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"id":259,"created_at":"2026-01-01T00:00:01Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"This change is **not** approved. Needs more work.\\n\\n**Reviewed commit:** `facade006d`"}]\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_MARKDOWN_NEGATED_APPROVAL_ROOT_COMMENT_GH
chmod +x "$_codex_markdown_negated_approval_root_comment_mock_dir/gh"

_codex_markdown_negated_approval_root_comment_output=""
_codex_markdown_negated_approval_root_comment_exit=0
PATH="$_codex_markdown_negated_approval_root_comment_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_markdown_negated_approval_root_comment_mock_dir/output.txt" 2>&1 || _codex_markdown_negated_approval_root_comment_exit=$?
_codex_markdown_negated_approval_root_comment_output="$(cat "$_codex_markdown_negated_approval_root_comment_mock_dir/output.txt")"
run_test "codex_markdown_negated_approval_root_comment_exit_needs_revision" "2" "$_codex_markdown_negated_approval_root_comment_exit"
run_test "codex_markdown_negated_approval_root_comment_verdict" "VERDICT: ESCALATE — Codex terminal verdict matches neither an approved clean template nor the documented blocking markers" \
  "$(printf '%s\n' "$_codex_markdown_negated_approval_root_comment_output" | grep "^VERDICT:")"
rm -rf "$_codex_markdown_negated_approval_root_comment_mock_dir"
unset _codex_markdown_negated_approval_root_comment_mock_dir _codex_markdown_negated_approval_root_comment_output _codex_markdown_negated_approval_root_comment_exit

# Followup to the space-separated/concatenated-prefix/Markdown-wrapped
# negation fixes above: a qualifier word interrupting the negation and
# the approval word (e.g. "This change is not YET approved") still
# missed the old rigid negation-immediately-adjacent-to-approval
# requirement (fresh evidence from PR #1490 finding 3789904716).
# CODEX_NEGATED_APPROVAL_PATTERN now tolerates up to 3 intervening
# qualifier words.
_codex_qualifier_negated_approval_root_comment_mock_dir="$(mktemp -d)"
cat > "$_codex_qualifier_negated_approval_root_comment_mock_dir/gh" <<'CODEX_QUALIFIER_NEGATED_APPROVAL_ROOT_COMMENT_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'facade007e1234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":260,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"id":261,"created_at":"2026-01-01T00:00:01Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"This change is not yet approved. Needs more work.\\n\\n**Reviewed commit:** `facade007e`"}]\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_QUALIFIER_NEGATED_APPROVAL_ROOT_COMMENT_GH
chmod +x "$_codex_qualifier_negated_approval_root_comment_mock_dir/gh"

_codex_qualifier_negated_approval_root_comment_output=""
_codex_qualifier_negated_approval_root_comment_exit=0
PATH="$_codex_qualifier_negated_approval_root_comment_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_qualifier_negated_approval_root_comment_mock_dir/output.txt" 2>&1 || _codex_qualifier_negated_approval_root_comment_exit=$?
_codex_qualifier_negated_approval_root_comment_output="$(cat "$_codex_qualifier_negated_approval_root_comment_mock_dir/output.txt")"
run_test "codex_qualifier_negated_approval_root_comment_exit_needs_revision" "2" "$_codex_qualifier_negated_approval_root_comment_exit"
run_test "codex_qualifier_negated_approval_root_comment_verdict" "VERDICT: ESCALATE — Codex terminal verdict matches neither an approved clean template nor the documented blocking markers" \
  "$(printf '%s\n' "$_codex_qualifier_negated_approval_root_comment_output" | grep "^VERDICT:")"
rm -rf "$_codex_qualifier_negated_approval_root_comment_mock_dir"
unset _codex_qualifier_negated_approval_root_comment_mock_dir _codex_qualifier_negated_approval_root_comment_output _codex_qualifier_negated_approval_root_comment_exit

# codex_response_is_usage_limit's broad "codex ... usage limit/quota/
# capacity" alternative matched ANY mention of those words, with no
# requirement for accompanying exhaustion/unavailability language. A
# clean submitted review merely discussing this PR's own usage-limit-
# detection code (e.g. "No blocking issues found. The Codex usage limit
# handling looks correct.") was itself misclassified as a usage-limit
# notice — priority 1 instead of the correct clean-approval priority 0.
# Tied against a clean SHA-pinned terminal comment (priority 0), the
# higher (buggy) priority won the tie-break, and the unconditional
# (non-source-gated) usage-limit check in the verdict classifier then
# emitted UNAVAILABLE instead of APPROVED for an actually-clean PR (fresh
# evidence from PR #1490 finding 3789928781). The alternative now
# requires an exhaustion/unavailability word directly after the noun.
#
# Retargeted for issue #1491's conservative-verdict-classifier redesign
# (Codex GitHub finding `3805611400`, P2): the review's own body still
# does not reproduce CODEX_APPROVED_TEMPLATES (it never did — this
# scenario relies on codex_response_priority ranking an unrecognized body
# ABOVE usage-limit, priority 2 vs 1, so the review correctly wins the tie
# and the composed verdict now safe-fails to NEEDS_REVISION instead of
# APPROVED). The competing SHA-pinned ROOT COMMENT body, however, is
# updated to the exact new template (not merely left as-is): if it were
# left at its old "No blocking issues found." vocabulary body, it would
# also collapse to the same unrecognized priority tier (2) as the review,
# and the tie would then be decided by array order rather than by whether
# the review's usage-limit-topic-mention is correctly classified —
# silently absorbing the exact regression this scenario exists to catch.
# Keeping the root comment as a real template (priority 0) preserves the
# scenario's actual test: the review (priority 2, correctly NOT
# usage-limit) still wins the tie over the clean root comment
# (priority 0), and the composed verdict safe-fails on the review's own
# unrecognized wording — never misrouted to UNAVAILABLE.
_codex_usage_limit_topic_mention_not_quota_mock_dir="$(mktemp -d)"
cat > "$_codex_usage_limit_topic_mention_not_quota_mock_dir/gh" <<'CODEX_USAGE_LIMIT_TOPIC_MENTION_NOT_QUOTA_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'facade008f1234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":262,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[{"submitted_at":"2026-01-01T00:00:01Z","commit_id":"facade008f1234567890","user":{"login":"chatgpt-codex-connector[bot]"},"body":"No blocking issues found. The Codex usage limit handling looks correct."}]\n'
    exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    jq -nc '[{id:263,created_at:"2026-01-01T00:00:01Z",user:{login:"chatgpt-codex-connector[bot]"},body:("Codex Review: Didn'\''t find any major issues. Swish! **Reviewed commit:** `facade008f` <details> <summary>ℹ️ About Codex in GitHub</summary> <br/> [Your team has set up Codex to review pull requests in this repo](https://chatgpt.com/codex/cloud/settings/general). Reviews are triggered when you - Open a pull request for review - Mark a draft as ready - Comment \"@codex review\". If Codex has suggestions, it will comment; otherwise it will react with 👍. Codex can also answer questions or update the PR. Try commenting \"@codex address that feedback\". </details>")}]'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_USAGE_LIMIT_TOPIC_MENTION_NOT_QUOTA_GH
chmod +x "$_codex_usage_limit_topic_mention_not_quota_mock_dir/gh"

_codex_usage_limit_topic_mention_not_quota_output=""
_codex_usage_limit_topic_mention_not_quota_exit=0
PATH="$_codex_usage_limit_topic_mention_not_quota_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_usage_limit_topic_mention_not_quota_mock_dir/output.txt" 2>&1 || _codex_usage_limit_topic_mention_not_quota_exit=$?
_codex_usage_limit_topic_mention_not_quota_output="$(cat "$_codex_usage_limit_topic_mention_not_quota_mock_dir/output.txt")"
run_test "codex_usage_limit_topic_mention_not_quota_exit_needs_revision" "2" "$_codex_usage_limit_topic_mention_not_quota_exit"
run_test "codex_usage_limit_topic_mention_not_quota_verdict" "VERDICT: ESCALATE — Codex terminal verdict matches neither an approved clean template nor the documented blocking markers" \
  "$(printf '%s\n' "$_codex_usage_limit_topic_mention_not_quota_output" | grep "^VERDICT:")"
rm -rf "$_codex_usage_limit_topic_mention_not_quota_mock_dir"
unset _codex_usage_limit_topic_mention_not_quota_mock_dir _codex_usage_limit_topic_mention_not_quota_output _codex_usage_limit_topic_mention_not_quota_exit

# CODEX_NEGATED_APPROVAL_PATTERN's target alternation only covered
# "approved"/"lgtm"/"looks good", not "no blocking issues"/"didn't find
# any major issues" — those are approval SIGNALS in CODEX_APPROVAL_PATTERN
# too, but were left unguarded. A hedged/uncertain response like "I
# cannot confirm there are no blocking issues" still matched "no blocking
# issues" and was classified APPROVED instead of the documented
# unrecognized-format safe-fail (fresh evidence from PR #1490 finding
# 3789958775).
_codex_negated_no_blocking_issues_root_comment_mock_dir="$(mktemp -d)"
cat > "$_codex_negated_no_blocking_issues_root_comment_mock_dir/gh" <<'CODEX_NEGATED_NO_BLOCKING_ISSUES_ROOT_COMMENT_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'facade00911234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":264,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"id":265,"created_at":"2026-01-01T00:00:01Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"I cannot confirm there are no blocking issues. Needs deeper review.\\n\\n**Reviewed commit:** `facade0091`"}]\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_NEGATED_NO_BLOCKING_ISSUES_ROOT_COMMENT_GH
chmod +x "$_codex_negated_no_blocking_issues_root_comment_mock_dir/gh"

_codex_negated_no_blocking_issues_root_comment_output=""
_codex_negated_no_blocking_issues_root_comment_exit=0
PATH="$_codex_negated_no_blocking_issues_root_comment_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_negated_no_blocking_issues_root_comment_mock_dir/output.txt" 2>&1 || _codex_negated_no_blocking_issues_root_comment_exit=$?
_codex_negated_no_blocking_issues_root_comment_output="$(cat "$_codex_negated_no_blocking_issues_root_comment_mock_dir/output.txt")"
run_test "codex_negated_no_blocking_issues_root_comment_exit_needs_revision" "2" "$_codex_negated_no_blocking_issues_root_comment_exit"
run_test "codex_negated_no_blocking_issues_root_comment_verdict" "VERDICT: ESCALATE — Codex terminal verdict matches neither an approved clean template nor the documented blocking markers" \
  "$(printf '%s\n' "$_codex_negated_no_blocking_issues_root_comment_output" | grep "^VERDICT:")"
rm -rf "$_codex_negated_no_blocking_issues_root_comment_mock_dir"
unset _codex_negated_no_blocking_issues_root_comment_mock_dir _codex_negated_no_blocking_issues_root_comment_output _codex_negated_no_blocking_issues_root_comment_exit

# codex_response_is_usage_limit's second alternative ("codex usage limits
# for code reviews") had the exact same unguarded-mention gap as the
# third alternative fixed just above — missed in that first pass since
# only the third alternative was narrowed. A clean review merely
# discussing the phrase in the context of docs (e.g. "No blocking issues
# found. The docs correctly explain Codex usage limits for code
# reviews.") was itself misclassified as a usage-limit notice (fresh
# evidence from PR #1490 finding 3789958776).
#
# Retargeted for issue #1491's conservative-verdict-classifier redesign:
# this body does not reproduce CODEX_APPROVED_TEMPLATES' whole-body exact
# template, so it now correctly safe-fails to NEEDS_REVISION. This is a
# single-evidence-source fixture (no competing tied evidence), so the
# retarget is a plain disposition change — is_usage_limit's own guard
# (unaffected by this plan) is still what is under test here.
_codex_usage_limit_code_reviews_phrase_mention_mock_dir="$(mktemp -d)"
cat > "$_codex_usage_limit_code_reviews_phrase_mention_mock_dir/gh" <<'CODEX_USAGE_LIMIT_CODE_REVIEWS_PHRASE_MENTION_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'facade00aa1234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":266,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"id":267,"created_at":"2026-01-01T00:00:01Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"No blocking issues found. The docs correctly explain Codex usage limits for code reviews.\\n\\n**Reviewed commit:** `facade00aa`"}]\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_USAGE_LIMIT_CODE_REVIEWS_PHRASE_MENTION_GH
chmod +x "$_codex_usage_limit_code_reviews_phrase_mention_mock_dir/gh"

_codex_usage_limit_code_reviews_phrase_mention_output=""
_codex_usage_limit_code_reviews_phrase_mention_exit=0
PATH="$_codex_usage_limit_code_reviews_phrase_mention_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_usage_limit_code_reviews_phrase_mention_mock_dir/output.txt" 2>&1 || _codex_usage_limit_code_reviews_phrase_mention_exit=$?
_codex_usage_limit_code_reviews_phrase_mention_output="$(cat "$_codex_usage_limit_code_reviews_phrase_mention_mock_dir/output.txt")"
run_test "codex_usage_limit_code_reviews_phrase_mention_exit_needs_revision" "2" "$_codex_usage_limit_code_reviews_phrase_mention_exit"
run_test "codex_usage_limit_code_reviews_phrase_mention_verdict" "VERDICT: ESCALATE — Codex terminal verdict matches neither an approved clean template nor the documented blocking markers" \
  "$(printf '%s\n' "$_codex_usage_limit_code_reviews_phrase_mention_output" | grep "^VERDICT:")"
rm -rf "$_codex_usage_limit_code_reviews_phrase_mention_mock_dir"
unset _codex_usage_limit_code_reviews_phrase_mention_mock_dir _codex_usage_limit_code_reviews_phrase_mention_output _codex_usage_limit_code_reviews_phrase_mention_exit

# CODEX_NEGATED_APPROVAL_PATTERN's bounded {0,3} filler-word window (added
# for finding 3789904716) was itself proven insufficient: 5 intervening
# words exceed the bound, so the negation went undetected while the
# approval alternative still matched (fresh evidence from PR #1490
# finding 3789992792). Replaced with an unbounded same-sentence scope
# ([^.!?]*) — this is the reviewer's own stated remediation ("avoid
# relying on a bounded filler-word count").
_codex_negation_beyond_bounded_window_root_comment_mock_dir="$(mktemp -d)"
cat > "$_codex_negation_beyond_bounded_window_root_comment_mock_dir/gh" <<'CODEX_NEGATION_BEYOND_BOUNDED_WINDOW_ROOT_COMMENT_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'facade00bb1234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":268,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"id":269,"created_at":"2026-01-01T00:00:01Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"I cannot confidently confirm that there are no blocking issues.\\n\\n**Reviewed commit:** `facade00bb`"}]\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_NEGATION_BEYOND_BOUNDED_WINDOW_ROOT_COMMENT_GH
chmod +x "$_codex_negation_beyond_bounded_window_root_comment_mock_dir/gh"

_codex_negation_beyond_bounded_window_root_comment_output=""
_codex_negation_beyond_bounded_window_root_comment_exit=0
PATH="$_codex_negation_beyond_bounded_window_root_comment_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_negation_beyond_bounded_window_root_comment_mock_dir/output.txt" 2>&1 || _codex_negation_beyond_bounded_window_root_comment_exit=$?
_codex_negation_beyond_bounded_window_root_comment_output="$(cat "$_codex_negation_beyond_bounded_window_root_comment_mock_dir/output.txt")"
run_test "codex_negation_beyond_bounded_window_root_comment_exit_needs_revision" "2" "$_codex_negation_beyond_bounded_window_root_comment_exit"
run_test "codex_negation_beyond_bounded_window_root_comment_verdict" "VERDICT: ESCALATE — Codex terminal verdict matches neither an approved clean template nor the documented blocking markers" \
  "$(printf '%s\n' "$_codex_negation_beyond_bounded_window_root_comment_output" | grep "^VERDICT:")"
rm -rf "$_codex_negation_beyond_bounded_window_root_comment_mock_dir"
unset _codex_negation_beyond_bounded_window_root_comment_mock_dir _codex_negation_beyond_bounded_window_root_comment_output _codex_negation_beyond_bounded_window_root_comment_exit

# Positive control for the unbounded [^.!?]* negation scope above: a
# negation word in one sentence must NOT suppress a clean approval phrase
# in a later, unrelated sentence — the sentence-terminator exclusion in
# the character class is what keeps the unbounded window from
# over-matching across sentence boundaries.
#
# Retargeted for issue #1491's conservative-verdict-classifier redesign:
# this body does not reproduce CODEX_APPROVED_TEMPLATES' whole-body exact
# template, so it now correctly safe-fails to NEEDS_REVISION regardless of
# the (now-deleted) negation-leak mechanism this scenario originally
# regression-tested; the construction remains valid coverage confirming it
# is trivially rejected under the new design.
_codex_negation_prior_sentence_does_not_leak_root_comment_mock_dir="$(mktemp -d)"
cat > "$_codex_negation_prior_sentence_does_not_leak_root_comment_mock_dir/gh" <<'CODEX_NEGATION_PRIOR_SENTENCE_DOES_NOT_LEAK_ROOT_COMMENT_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'facade00cc1234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":270,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"id":271,"created_at":"2026-01-01T00:00:01Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"The variable name is not great. No blocking issues found.\\n\\n**Reviewed commit:** `facade00cc`"}]\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_NEGATION_PRIOR_SENTENCE_DOES_NOT_LEAK_ROOT_COMMENT_GH
chmod +x "$_codex_negation_prior_sentence_does_not_leak_root_comment_mock_dir/gh"

_codex_negation_prior_sentence_does_not_leak_root_comment_output=""
_codex_negation_prior_sentence_does_not_leak_root_comment_exit=0
PATH="$_codex_negation_prior_sentence_does_not_leak_root_comment_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_negation_prior_sentence_does_not_leak_root_comment_mock_dir/output.txt" 2>&1 || _codex_negation_prior_sentence_does_not_leak_root_comment_exit=$?
_codex_negation_prior_sentence_does_not_leak_root_comment_output="$(cat "$_codex_negation_prior_sentence_does_not_leak_root_comment_mock_dir/output.txt")"
run_test "codex_negation_prior_sentence_does_not_leak_root_comment_exit_needs_revision" "2" "$_codex_negation_prior_sentence_does_not_leak_root_comment_exit"
run_test "codex_negation_prior_sentence_does_not_leak_root_comment_verdict" "VERDICT: ESCALATE — Codex terminal verdict matches neither an approved clean template nor the documented blocking markers" \
  "$(printf '%s\n' "$_codex_negation_prior_sentence_does_not_leak_root_comment_output" | grep "^VERDICT:")"
rm -rf "$_codex_negation_prior_sentence_does_not_leak_root_comment_mock_dir"
unset _codex_negation_prior_sentence_does_not_leak_root_comment_mock_dir _codex_negation_prior_sentence_does_not_leak_root_comment_output _codex_negation_prior_sentence_does_not_leak_root_comment_exit

# Two more negation gaps surfaced once the pattern was unbounded: (a) the
# target alternation had "approved" but not the bare verb "approve", and
# (b) the pattern only checked negation-THEN-approval order, so an
# approval phrase appearing BEFORE the negation in the same sentence
# ("This looks good at first glance, but I cannot approve this change")
# wasn't caught (fresh evidence from PR #1490 finding 3790023141). Both
# alternation orders are now checked, and the target list includes the
# bare verb.
_codex_negation_reverse_order_cannot_approve_root_comment_mock_dir="$(mktemp -d)"
cat > "$_codex_negation_reverse_order_cannot_approve_root_comment_mock_dir/gh" <<'CODEX_NEGATION_REVERSE_ORDER_CANNOT_APPROVE_ROOT_COMMENT_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'facade00dd1234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":272,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"id":273,"created_at":"2026-01-01T00:00:01Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"This looks good at first glance, but I cannot approve this change.\\n\\n**Reviewed commit:** `facade00dd`"}]\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_NEGATION_REVERSE_ORDER_CANNOT_APPROVE_ROOT_COMMENT_GH
chmod +x "$_codex_negation_reverse_order_cannot_approve_root_comment_mock_dir/gh"

_codex_negation_reverse_order_cannot_approve_root_comment_output=""
_codex_negation_reverse_order_cannot_approve_root_comment_exit=0
PATH="$_codex_negation_reverse_order_cannot_approve_root_comment_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_negation_reverse_order_cannot_approve_root_comment_mock_dir/output.txt" 2>&1 || _codex_negation_reverse_order_cannot_approve_root_comment_exit=$?
_codex_negation_reverse_order_cannot_approve_root_comment_output="$(cat "$_codex_negation_reverse_order_cannot_approve_root_comment_mock_dir/output.txt")"
run_test "codex_negation_reverse_order_cannot_approve_root_comment_exit_needs_revision" "2" "$_codex_negation_reverse_order_cannot_approve_root_comment_exit"
run_test "codex_negation_reverse_order_cannot_approve_root_comment_verdict" "VERDICT: ESCALATE — Codex terminal verdict matches neither an approved clean template nor the documented blocking markers" \
  "$(printf '%s\n' "$_codex_negation_reverse_order_cannot_approve_root_comment_output" | grep "^VERDICT:")"
rm -rf "$_codex_negation_reverse_order_cannot_approve_root_comment_mock_dir"
unset _codex_negation_reverse_order_cannot_approve_root_comment_mock_dir _codex_negation_reverse_order_cannot_approve_root_comment_output _codex_negation_reverse_order_cannot_approve_root_comment_exit

# codex_scan_comment_evidence tracked COMMENT_LATEST_BODY without
# recording whether it was the SAME comment as COMMENT_TERMINAL_BODY. When
# the only comment is a clean SHA-pinned terminal review whose OWN finding
# text happens to quote the environment-setup message (e.g. flagging that
# docs accurately quote it), codex_combine_terminal_evidence's ancillary
# environment-error/usage-limit override re-classified that SAME terminal
# comment as if it were a genuinely separate ancillary setup-failure
# notice, downgrading APPROVED to codex-github-environment-missing (fresh
# evidence from PR #1490 finding 3790023143). COMMENT_LATEST_IS_TERMINAL
# now gates that override so it never fires on the terminal comment itself.
#
# Retargeted for issue #1491's conservative-verdict-classifier redesign:
# this body does not reproduce CODEX_APPROVED_TEMPLATES' whole-body exact
# template, so it now correctly safe-fails to NEEDS_REVISION instead of
# APPROVED. The property this scenario actually tests — that the terminal
# comment is never re-classified as a separate ancillary environment-error
# notice — is unaffected: COMMENT_LATEST_IS_TERMINAL's gate is independent
# of codex_response_is_approved and still correctly prevents the downgrade
# to codex-github-environment-missing.
_codex_terminal_comment_quotes_env_error_not_ancillary_mock_dir="$(mktemp -d)"
cat > "$_codex_terminal_comment_quotes_env_error_not_ancillary_mock_dir/gh" <<'CODEX_TERMINAL_COMMENT_QUOTES_ENV_ERROR_NOT_ANCILLARY_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'facade00ee1234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":274,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"id":275,"created_at":"2026-01-01T00:00:01Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"No blocking issues found. The docs accurately quote: To use Codex here, create an environment for this repo.\\n\\n**Reviewed commit:** `facade00ee`"}]\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_TERMINAL_COMMENT_QUOTES_ENV_ERROR_NOT_ANCILLARY_GH
chmod +x "$_codex_terminal_comment_quotes_env_error_not_ancillary_mock_dir/gh"

_codex_terminal_comment_quotes_env_error_not_ancillary_output=""
_codex_terminal_comment_quotes_env_error_not_ancillary_exit=0
PATH="$_codex_terminal_comment_quotes_env_error_not_ancillary_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_terminal_comment_quotes_env_error_not_ancillary_mock_dir/output.txt" 2>&1 || _codex_terminal_comment_quotes_env_error_not_ancillary_exit=$?
_codex_terminal_comment_quotes_env_error_not_ancillary_output="$(cat "$_codex_terminal_comment_quotes_env_error_not_ancillary_mock_dir/output.txt")"
run_test "codex_terminal_comment_quotes_env_error_not_ancillary_exit_needs_revision" "2" "$_codex_terminal_comment_quotes_env_error_not_ancillary_exit"
run_test "codex_terminal_comment_quotes_env_error_not_ancillary_verdict" "VERDICT: ESCALATE — Codex terminal verdict matches neither an approved clean template nor the documented blocking markers" \
  "$(printf '%s\n' "$_codex_terminal_comment_quotes_env_error_not_ancillary_output" | grep "^VERDICT:")"
rm -rf "$_codex_terminal_comment_quotes_env_error_not_ancillary_mock_dir"
unset _codex_terminal_comment_quotes_env_error_not_ancillary_mock_dir _codex_terminal_comment_quotes_env_error_not_ancillary_output _codex_terminal_comment_quotes_env_error_not_ancillary_exit

# Positive control for the reverse-order negation alternative that was
# added for finding 3790023141 and then REMOVED for being over-broad: it
# matched ANY later negation word in the same sentence regardless of what
# it actually negated, so a genuinely clean response like "Looks good
# overall; tests were not run." (the "not" refers to the unrelated "tests
# were not run" clause, not to the approval) was incorrectly flagged as
# negated and returned NEEDS_REVISION instead of APPROVED (fresh evidence
# from PR #1490 finding 3790062089).
#
# Retargeted and renamed for issue #1491's conservative-verdict-classifier
# redesign: this body does not reproduce CODEX_APPROVED_TEMPLATES' whole-
# body exact template, so it now correctly safe-fails to NEEDS_REVISION —
# the (now-deleted) reverse-order negation mechanism this scenario
# originally regression-tested no longer exists to have a gap in. Renamed
# from "...stays_approved_..." per the plan's naming standing rule (a
# scenario name must never assert the opposite of its expectation).
_codex_unrelated_later_negation_safe_fails_root_comment_mock_dir="$(mktemp -d)"
cat > "$_codex_unrelated_later_negation_safe_fails_root_comment_mock_dir/gh" <<'CODEX_UNRELATED_LATER_NEGATION_SAFE_FAILS_ROOT_COMMENT_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'facade00ff1234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":276,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"id":277,"created_at":"2026-01-01T00:00:01Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"Looks good overall; tests were not run.\\n\\n**Reviewed commit:** `facade00ff`"}]\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_UNRELATED_LATER_NEGATION_SAFE_FAILS_ROOT_COMMENT_GH
chmod +x "$_codex_unrelated_later_negation_safe_fails_root_comment_mock_dir/gh"

_codex_unrelated_later_negation_safe_fails_root_comment_output=""
_codex_unrelated_later_negation_safe_fails_root_comment_exit=0
PATH="$_codex_unrelated_later_negation_safe_fails_root_comment_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_unrelated_later_negation_safe_fails_root_comment_mock_dir/output.txt" 2>&1 || _codex_unrelated_later_negation_safe_fails_root_comment_exit=$?
_codex_unrelated_later_negation_safe_fails_root_comment_output="$(cat "$_codex_unrelated_later_negation_safe_fails_root_comment_mock_dir/output.txt")"
run_test "codex_unrelated_later_negation_safe_fails_root_comment_exit_needs_revision" "2" "$_codex_unrelated_later_negation_safe_fails_root_comment_exit"
run_test "codex_unrelated_later_negation_safe_fails_root_comment_verdict" "VERDICT: ESCALATE — Codex terminal verdict matches neither an approved clean template nor the documented blocking markers" \
  "$(printf '%s\n' "$_codex_unrelated_later_negation_safe_fails_root_comment_output" | grep "^VERDICT:")"
rm -rf "$_codex_unrelated_later_negation_safe_fails_root_comment_mock_dir"
unset _codex_unrelated_later_negation_safe_fails_root_comment_mock_dir _codex_unrelated_later_negation_safe_fails_root_comment_output _codex_unrelated_later_negation_safe_fails_root_comment_exit

# codex_combine_terminal_evidence previously applied the SAME newest-wins
# comparison to a usage-limit ancillary comment as it does to an
# environment-setup error, so a clean current-head review returned in the
# SAME fetch as (and strictly newer than) a usage-limit notice let the
# review win, and the quota body never reached codex_return_usage_limit —
# contradicting the documented immediate-termination contract for
# usage-limit (fresh evidence from PR #1490 finding 3790062091). Fixture:
# an ancillary (non-terminal) usage-limit comment at T1 and a clean
# current-head review at T2 > T1, both in the same poll fetch.
_codex_usage_limit_beats_same_fetch_newer_review_mock_dir="$(mktemp -d)"
cat > "$_codex_usage_limit_beats_same_fetch_newer_review_mock_dir/gh" <<'CODEX_USAGE_LIMIT_BEATS_SAME_FETCH_NEWER_REVIEW_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'facade01001234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":278,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[{"submitted_at":"2026-01-01T00:00:02Z","commit_id":"facade01001234567890","user":{"login":"chatgpt-codex-connector[bot]"},"body":"No blocking issues found."}]\n'
    exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"id":279,"created_at":"2026-01-01T00:00:01Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"You have reached your Codex usage limits for code reviews."}]\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_USAGE_LIMIT_BEATS_SAME_FETCH_NEWER_REVIEW_GH
chmod +x "$_codex_usage_limit_beats_same_fetch_newer_review_mock_dir/gh"

_codex_usage_limit_beats_same_fetch_newer_review_output=""
_codex_usage_limit_beats_same_fetch_newer_review_exit=0
PATH="$_codex_usage_limit_beats_same_fetch_newer_review_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_usage_limit_beats_same_fetch_newer_review_mock_dir/output.txt" 2>&1 || _codex_usage_limit_beats_same_fetch_newer_review_exit=$?
_codex_usage_limit_beats_same_fetch_newer_review_output="$(cat "$_codex_usage_limit_beats_same_fetch_newer_review_mock_dir/output.txt")"
run_test "codex_usage_limit_beats_same_fetch_newer_review_exit_unavailable" "3" "$_codex_usage_limit_beats_same_fetch_newer_review_exit"
run_test "codex_usage_limit_beats_same_fetch_newer_review_verdict" "VERDICT: UNAVAILABLE — Codex GitHub review usage limit reached" \
  "$(printf '%s\n' "$_codex_usage_limit_beats_same_fetch_newer_review_output" | grep "^VERDICT:")"
rm -rf "$_codex_usage_limit_beats_same_fetch_newer_review_mock_dir"
unset _codex_usage_limit_beats_same_fetch_newer_review_mock_dir _codex_usage_limit_beats_same_fetch_newer_review_output _codex_usage_limit_beats_same_fetch_newer_review_exit

# Followup to codex_usage_limit_beats_same_fetch_newer_review: the earlier
# fix only protected usage-limit precedence INSIDE
# codex_combine_terminal_evidence, but codex_scan_comment_evidence's
# upstream tracking could already discard a usage-limit comment in favor
# of a LATER environment-error comment within the SAME fetch, before
# combine_terminal_evidence is ever reached — both set is_actionable=1,
# so the unconditional overwrite let the later setup-error body replace
# the quota body (fresh evidence from PR #1490 finding 3790092216).
# Fixture: an ancillary usage-limit comment at T1 followed by an
# ancillary environment-error comment at T2 > T1, in the same fetch.
_codex_usage_limit_survives_later_env_error_same_fetch_mock_dir="$(mktemp -d)"
cat > "$_codex_usage_limit_survives_later_env_error_same_fetch_mock_dir/gh" <<'CODEX_USAGE_LIMIT_SURVIVES_LATER_ENV_ERROR_SAME_FETCH_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'facade01111234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":280,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"id":281,"created_at":"2026-01-01T00:00:01Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"You have reached your Codex usage limits for code reviews."},{"id":282,"created_at":"2026-01-01T00:00:02Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"To use Codex here, create an environment for this repo."}]\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_USAGE_LIMIT_SURVIVES_LATER_ENV_ERROR_SAME_FETCH_GH
chmod +x "$_codex_usage_limit_survives_later_env_error_same_fetch_mock_dir/gh"

_codex_usage_limit_survives_later_env_error_same_fetch_output=""
_codex_usage_limit_survives_later_env_error_same_fetch_exit=0
PATH="$_codex_usage_limit_survives_later_env_error_same_fetch_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_usage_limit_survives_later_env_error_same_fetch_mock_dir/output.txt" 2>&1 || _codex_usage_limit_survives_later_env_error_same_fetch_exit=$?
_codex_usage_limit_survives_later_env_error_same_fetch_output="$(cat "$_codex_usage_limit_survives_later_env_error_same_fetch_mock_dir/output.txt")"
run_test "codex_usage_limit_survives_later_env_error_same_fetch_exit_unavailable" "3" "$_codex_usage_limit_survives_later_env_error_same_fetch_exit"
run_test "codex_usage_limit_survives_later_env_error_same_fetch_verdict" "VERDICT: UNAVAILABLE — Codex GitHub review usage limit reached" \
  "$(printf '%s\n' "$_codex_usage_limit_survives_later_env_error_same_fetch_output" | grep "^VERDICT:")"
rm -rf "$_codex_usage_limit_survives_later_env_error_same_fetch_mock_dir"
unset _codex_usage_limit_survives_later_env_error_same_fetch_mock_dir _codex_usage_limit_survives_later_env_error_same_fetch_output _codex_usage_limit_survives_later_env_error_same_fetch_exit

# CODEX_APPROVAL_PATTERN's substring match can't distinguish quotation/
# discussion of a clean phrase from an actual assertion of it: a
# SHA-pinned review that REJECTS text while QUOTING a clean signal (e.g.
# `The documented bot response "No blocking issues found" is inaccurate
# and should be corrected`) still matched and returned APPROVED instead
# of the documented unrecognized-format safe-fail (fresh evidence from PR
# #1490 finding 3790122058). codex_response_is_approved now strips
# quoted spans before matching.
_codex_quoted_clean_phrase_not_approved_root_comment_mock_dir="$(mktemp -d)"
cat > "$_codex_quoted_clean_phrase_not_approved_root_comment_mock_dir/gh" <<'CODEX_QUOTED_CLEAN_PHRASE_NOT_APPROVED_ROOT_COMMENT_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'facade01221234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":283,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    jq -nc '[{id:284,created_at:"2026-01-01T00:00:01Z",user:{login:"chatgpt-codex-connector[bot]"},body:("The documented bot response \"No blocking issues found\" is inaccurate and should be corrected.\n\n**Reviewed commit:** `facade01221`")}]'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_QUOTED_CLEAN_PHRASE_NOT_APPROVED_ROOT_COMMENT_GH
chmod +x "$_codex_quoted_clean_phrase_not_approved_root_comment_mock_dir/gh"

_codex_quoted_clean_phrase_not_approved_root_comment_output=""
_codex_quoted_clean_phrase_not_approved_root_comment_exit=0
PATH="$_codex_quoted_clean_phrase_not_approved_root_comment_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_quoted_clean_phrase_not_approved_root_comment_mock_dir/output.txt" 2>&1 || _codex_quoted_clean_phrase_not_approved_root_comment_exit=$?
_codex_quoted_clean_phrase_not_approved_root_comment_output="$(cat "$_codex_quoted_clean_phrase_not_approved_root_comment_mock_dir/output.txt")"
run_test "codex_quoted_clean_phrase_not_approved_root_comment_exit_needs_revision" "2" "$_codex_quoted_clean_phrase_not_approved_root_comment_exit"
run_test "codex_quoted_clean_phrase_not_approved_root_comment_verdict" "VERDICT: ESCALATE — Codex terminal verdict matches neither an approved clean template nor the documented blocking markers" \
  "$(printf '%s\n' "$_codex_quoted_clean_phrase_not_approved_root_comment_output" | grep "^VERDICT:")"
rm -rf "$_codex_quoted_clean_phrase_not_approved_root_comment_mock_dir"
unset _codex_quoted_clean_phrase_not_approved_root_comment_mock_dir _codex_quoted_clean_phrase_not_approved_root_comment_output _codex_quoted_clean_phrase_not_approved_root_comment_exit

# The [^.!?]* negation span only excluded sentence terminators, not
# clause separators, so an unrelated negation in an earlier semicolon-
# joined clause of the same sentence still spanned into a later, unrelated
# clean clause (e.g. "Tests are not required for this documentation-only
# change; looks good") and was incorrectly flagged as negated (fresh
# evidence from PR #1490 finding 3790122061). The character class now
# also excludes `;`.
#
# Retargeted for issue #1491's conservative-verdict-classifier redesign:
# this body does not reproduce CODEX_APPROVED_TEMPLATES' whole-body exact
# template, so it now correctly safe-fails to NEEDS_REVISION regardless of
# the (now-deleted) semicolon-scoping mechanism this scenario originally
# regression-tested.
_codex_semicolon_scoped_negation_root_comment_mock_dir="$(mktemp -d)"
cat > "$_codex_semicolon_scoped_negation_root_comment_mock_dir/gh" <<'CODEX_SEMICOLON_SCOPED_NEGATION_ROOT_COMMENT_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'facade01331234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":285,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"id":286,"created_at":"2026-01-01T00:00:01Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"Tests are not required for this documentation-only change; looks good.\\n\\n**Reviewed commit:** `facade01331`"}]\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_SEMICOLON_SCOPED_NEGATION_ROOT_COMMENT_GH
chmod +x "$_codex_semicolon_scoped_negation_root_comment_mock_dir/gh"

_codex_semicolon_scoped_negation_root_comment_output=""
_codex_semicolon_scoped_negation_root_comment_exit=0
PATH="$_codex_semicolon_scoped_negation_root_comment_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_semicolon_scoped_negation_root_comment_mock_dir/output.txt" 2>&1 || _codex_semicolon_scoped_negation_root_comment_exit=$?
_codex_semicolon_scoped_negation_root_comment_output="$(cat "$_codex_semicolon_scoped_negation_root_comment_mock_dir/output.txt")"
run_test "codex_semicolon_scoped_negation_root_comment_exit_needs_revision" "2" "$_codex_semicolon_scoped_negation_root_comment_exit"
run_test "codex_semicolon_scoped_negation_root_comment_verdict" "VERDICT: ESCALATE — Codex terminal verdict matches neither an approved clean template nor the documented blocking markers" \
  "$(printf '%s\n' "$_codex_semicolon_scoped_negation_root_comment_output" | grep "^VERDICT:")"
rm -rf "$_codex_semicolon_scoped_negation_root_comment_mock_dir"
unset _codex_semicolon_scoped_negation_root_comment_mock_dir _codex_semicolon_scoped_negation_root_comment_output _codex_semicolon_scoped_negation_root_comment_exit

# codex_response_is_approved only stripped straight-double-quoted spans,
# not backtick-quoted (Markdown inline code) ones, so a review that
# quotes a clean phrase using backticks instead of straight quotes (e.g.
# "The documented response `No blocking issues found` is inaccurate")
# still matched and returned APPROVED (fresh evidence from PR #1490
# finding 3793219190, a followup to 3790122058). The shared
# codex_strip_quoted_spans helper now strips both quoting styles.
_codex_backtick_quoted_phrase_not_approved_root_comment_mock_dir="$(mktemp -d)"
cat > "$_codex_backtick_quoted_phrase_not_approved_root_comment_mock_dir/gh" <<'CODEX_BACKTICK_QUOTED_PHRASE_NOT_APPROVED_ROOT_COMMENT_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'facade01441234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":287,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"id":288,"created_at":"2026-01-01T00:00:01Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"The documented response `No blocking issues found` is inaccurate and should be corrected.\\n\\n**Reviewed commit:** `facade01441`"}]\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_BACKTICK_QUOTED_PHRASE_NOT_APPROVED_ROOT_COMMENT_GH
chmod +x "$_codex_backtick_quoted_phrase_not_approved_root_comment_mock_dir/gh"

_codex_backtick_quoted_phrase_not_approved_root_comment_output=""
_codex_backtick_quoted_phrase_not_approved_root_comment_exit=0
PATH="$_codex_backtick_quoted_phrase_not_approved_root_comment_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_backtick_quoted_phrase_not_approved_root_comment_mock_dir/output.txt" 2>&1 || _codex_backtick_quoted_phrase_not_approved_root_comment_exit=$?
_codex_backtick_quoted_phrase_not_approved_root_comment_output="$(cat "$_codex_backtick_quoted_phrase_not_approved_root_comment_mock_dir/output.txt")"
run_test "codex_backtick_quoted_phrase_not_approved_root_comment_exit_needs_revision" "2" "$_codex_backtick_quoted_phrase_not_approved_root_comment_exit"
run_test "codex_backtick_quoted_phrase_not_approved_root_comment_verdict" "VERDICT: ESCALATE — Codex terminal verdict matches neither an approved clean template nor the documented blocking markers" \
  "$(printf '%s\n' "$_codex_backtick_quoted_phrase_not_approved_root_comment_output" | grep "^VERDICT:")"
rm -rf "$_codex_backtick_quoted_phrase_not_approved_root_comment_mock_dir"
unset _codex_backtick_quoted_phrase_not_approved_root_comment_mock_dir _codex_backtick_quoted_phrase_not_approved_root_comment_output _codex_backtick_quoted_phrase_not_approved_root_comment_exit

# codex_response_is_approved only quote-stripped before the POSITIVE
# CODEX_APPROVAL_PATTERN check, not before the NEGATED_APPROVAL_PATTERN
# check that runs first — so an otherwise-clean response that quotes a
# rejection phrase from elsewhere (e.g. test/documentation text), such as
# `No blocking issues found. The tests cover "This change is not
# approved".`, still tripped the negation check on the unstripped body
# and safe-failed to NEEDS_REVISION even though the actual review verdict
# was clean (fresh evidence from PR #1490 finding 3793219192).
# codex_response_is_approved now strips quoted spans ONCE, before running
# either check.
#
# Retargeted for issue #1491's conservative-verdict-classifier redesign:
# this body does not reproduce CODEX_APPROVED_TEMPLATES' whole-body exact
# template, so it now correctly safe-fails to NEEDS_REVISION regardless of
# the (now-deleted) quote-stripping-order mechanism this scenario
# originally regression-tested for the approval path (codex_strip_quoted_
# spans itself is unchanged, and is_approved no longer calls it at all).
_codex_quoted_rejection_in_clean_review_root_comment_mock_dir="$(mktemp -d)"
cat > "$_codex_quoted_rejection_in_clean_review_root_comment_mock_dir/gh" <<'CODEX_QUOTED_REJECTION_IN_CLEAN_REVIEW_ROOT_COMMENT_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'facade01551234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":289,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    jq -nc '[{id:290,created_at:"2026-01-01T00:00:01Z",user:{login:"chatgpt-codex-connector[bot]"},body:("No blocking issues found. The tests cover \"This change is not approved\".\n\n**Reviewed commit:** `facade01551`")}]'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_QUOTED_REJECTION_IN_CLEAN_REVIEW_ROOT_COMMENT_GH
chmod +x "$_codex_quoted_rejection_in_clean_review_root_comment_mock_dir/gh"

_codex_quoted_rejection_in_clean_review_root_comment_output=""
_codex_quoted_rejection_in_clean_review_root_comment_exit=0
PATH="$_codex_quoted_rejection_in_clean_review_root_comment_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_quoted_rejection_in_clean_review_root_comment_mock_dir/output.txt" 2>&1 || _codex_quoted_rejection_in_clean_review_root_comment_exit=$?
_codex_quoted_rejection_in_clean_review_root_comment_output="$(cat "$_codex_quoted_rejection_in_clean_review_root_comment_mock_dir/output.txt")"
run_test "codex_quoted_rejection_in_clean_review_root_comment_exit_needs_revision" "2" "$_codex_quoted_rejection_in_clean_review_root_comment_exit"
run_test "codex_quoted_rejection_in_clean_review_root_comment_verdict" "VERDICT: ESCALATE — Codex terminal verdict matches neither an approved clean template nor the documented blocking markers" \
  "$(printf '%s\n' "$_codex_quoted_rejection_in_clean_review_root_comment_output" | grep "^VERDICT:")"
rm -rf "$_codex_quoted_rejection_in_clean_review_root_comment_mock_dir"
unset _codex_quoted_rejection_in_clean_review_root_comment_mock_dir _codex_quoted_rejection_in_clean_review_root_comment_output _codex_quoted_rejection_in_clean_review_root_comment_exit

# Followup to codex_semicolon_scoped_negation_root_comment: the semicolon-
# only exclusion still let a comma-joined clause cross ("Tests are not
# required, but looks good") the same way the original unbounded span
# crossed the semicolon (fresh evidence from PR #1490 finding
# 3793219193). The character class now also excludes `,`.
#
# Retargeted for issue #1491's conservative-verdict-classifier redesign:
# this body does not reproduce CODEX_APPROVED_TEMPLATES' whole-body exact
# template, so it now correctly safe-fails to NEEDS_REVISION regardless of
# the (now-deleted) comma-scoping mechanism this scenario originally
# regression-tested.
_codex_comma_scoped_negation_root_comment_mock_dir="$(mktemp -d)"
cat > "$_codex_comma_scoped_negation_root_comment_mock_dir/gh" <<'CODEX_COMMA_SCOPED_NEGATION_ROOT_COMMENT_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'facade01661234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":291,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"id":292,"created_at":"2026-01-01T00:00:01Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"Tests are not required, but looks good.\\n\\n**Reviewed commit:** `facade01661`"}]\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_COMMA_SCOPED_NEGATION_ROOT_COMMENT_GH
chmod +x "$_codex_comma_scoped_negation_root_comment_mock_dir/gh"

_codex_comma_scoped_negation_root_comment_output=""
_codex_comma_scoped_negation_root_comment_exit=0
PATH="$_codex_comma_scoped_negation_root_comment_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_comma_scoped_negation_root_comment_mock_dir/output.txt" 2>&1 || _codex_comma_scoped_negation_root_comment_exit=$?
_codex_comma_scoped_negation_root_comment_output="$(cat "$_codex_comma_scoped_negation_root_comment_mock_dir/output.txt")"
run_test "codex_comma_scoped_negation_root_comment_exit_needs_revision" "2" "$_codex_comma_scoped_negation_root_comment_exit"
run_test "codex_comma_scoped_negation_root_comment_verdict" "VERDICT: ESCALATE — Codex terminal verdict matches neither an approved clean template nor the documented blocking markers" \
  "$(printf '%s\n' "$_codex_comma_scoped_negation_root_comment_output" | grep "^VERDICT:")"
rm -rf "$_codex_comma_scoped_negation_root_comment_mock_dir"
unset _codex_comma_scoped_negation_root_comment_mock_dir _codex_comma_scoped_negation_root_comment_output _codex_comma_scoped_negation_root_comment_exit

# The top-level verdict-parsing elif chain's usage-limit check has no
# source gate (unlike the environment-error check, already safe because
# it's gated on source == "comment", and a terminal SHA-pinned review
# always has source == "review" by construction) and was not
# quote-stripped, so a clean terminal review that merely QUOTES an actual
# quota message (e.g. "No blocking issues found. The docs accurately
# quote: You have reached your Codex usage limits.") was reclassified as
# UNAVAILABLE instead of APPROVED — a case COMMENT_LATEST_IS_TERMINAL
# does not cover, since that guard only protects the ancillary-evidence
# combination stage, not this separate final verdict check (fresh
# evidence from PR #1490 finding 3793259351).
#
# Retargeted for issue #1491's conservative-verdict-classifier redesign:
# this body does not reproduce CODEX_APPROVED_TEMPLATES' whole-body exact
# template, so it now correctly safe-fails to NEEDS_REVISION. The property
# this scenario actually tests — that the quoted quota message does not
# trigger a false UNAVAILABLE — is unaffected: codex_response_is_usage_
# limit is still called on the quote-stripped body at this verdict site
# (unchanged by this plan), so the quoted quota wording is still correctly
# never treated as a genuine usage-limit notice.
_codex_terminal_review_quotes_quota_message_mock_dir="$(mktemp -d)"
cat > "$_codex_terminal_review_quotes_quota_message_mock_dir/gh" <<'CODEX_TERMINAL_REVIEW_QUOTES_QUOTA_MESSAGE_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'facade01771234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":293,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"id":294,"created_at":"2026-01-01T00:00:01Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"No blocking issues found. The docs accurately quote: `You have reached your Codex usage limits.`\\n\\n**Reviewed commit:** `facade01771`"}]\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_TERMINAL_REVIEW_QUOTES_QUOTA_MESSAGE_GH
chmod +x "$_codex_terminal_review_quotes_quota_message_mock_dir/gh"

_codex_terminal_review_quotes_quota_message_output=""
_codex_terminal_review_quotes_quota_message_exit=0
PATH="$_codex_terminal_review_quotes_quota_message_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_terminal_review_quotes_quota_message_mock_dir/output.txt" 2>&1 || _codex_terminal_review_quotes_quota_message_exit=$?
_codex_terminal_review_quotes_quota_message_output="$(cat "$_codex_terminal_review_quotes_quota_message_mock_dir/output.txt")"
run_test "codex_terminal_review_quotes_quota_message_exit_needs_revision" "2" "$_codex_terminal_review_quotes_quota_message_exit"
run_test "codex_terminal_review_quotes_quota_message_verdict" "VERDICT: ESCALATE — Codex terminal verdict matches neither an approved clean template nor the documented blocking markers" \
  "$(printf '%s\n' "$_codex_terminal_review_quotes_quota_message_output" | grep "^VERDICT:")"
rm -rf "$_codex_terminal_review_quotes_quota_message_mock_dir"
unset _codex_terminal_review_quotes_quota_message_mock_dir _codex_terminal_review_quotes_quota_message_output _codex_terminal_review_quotes_quota_message_exit

# "Not only X, (but) Y" is an AFFIRMATIVE intensifier construction (BOTH
# X and Y are being asserted, not negated), not a negation of X, so
# CODEX_NEGATION_WORDS' bare "not" alternative — which has no way to
# distinguish this idiom from a genuine negation — misclassified "Not
# only does this look good, it is approved" as negated even though both
# phrases are affirmative (fresh evidence from PR #1490 finding
# 3793299512). codex_response_is_approved now strips the "not only" idiom
# before running the negation check.
#
# Retargeted and renamed for issue #1491's conservative-verdict-classifier
# redesign: this body does not reproduce CODEX_APPROVED_TEMPLATES' whole-
# body exact template, so it now correctly safe-fails to NEEDS_REVISION.
# codex_strip_not_only_idiom itself is unchanged, but is_approved no
# longer calls it (only codex_response_is_blocking does, Decision 4) — the
# idiom-stripping-before-negation-check mechanism this scenario originally
# regression-tested no longer applies to the approval path. Renamed from
# "...stays_approved_..." per the plan's naming standing rule.
_codex_not_only_idiom_safe_fails_root_comment_mock_dir="$(mktemp -d)"
cat > "$_codex_not_only_idiom_safe_fails_root_comment_mock_dir/gh" <<'CODEX_NOT_ONLY_IDIOM_SAFE_FAILS_ROOT_COMMENT_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'facade01881234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":295,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"id":296,"created_at":"2026-01-01T00:00:01Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"Not only does this look good, it is approved.\\n\\n**Reviewed commit:** `facade01881`"}]\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_NOT_ONLY_IDIOM_SAFE_FAILS_ROOT_COMMENT_GH
chmod +x "$_codex_not_only_idiom_safe_fails_root_comment_mock_dir/gh"

_codex_not_only_idiom_safe_fails_root_comment_output=""
_codex_not_only_idiom_safe_fails_root_comment_exit=0
PATH="$_codex_not_only_idiom_safe_fails_root_comment_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_not_only_idiom_safe_fails_root_comment_mock_dir/output.txt" 2>&1 || _codex_not_only_idiom_safe_fails_root_comment_exit=$?
_codex_not_only_idiom_safe_fails_root_comment_output="$(cat "$_codex_not_only_idiom_safe_fails_root_comment_mock_dir/output.txt")"
run_test "codex_not_only_idiom_safe_fails_root_comment_exit_needs_revision" "2" "$_codex_not_only_idiom_safe_fails_root_comment_exit"
run_test "codex_not_only_idiom_safe_fails_root_comment_verdict" "VERDICT: ESCALATE — Codex terminal verdict matches neither an approved clean template nor the documented blocking markers" \
  "$(printf '%s\n' "$_codex_not_only_idiom_safe_fails_root_comment_output" | grep "^VERDICT:")"
rm -rf "$_codex_not_only_idiom_safe_fails_root_comment_mock_dir"
unset _codex_not_only_idiom_safe_fails_root_comment_mock_dir _codex_not_only_idiom_safe_fails_root_comment_output _codex_not_only_idiom_safe_fails_root_comment_exit

# codex_strip_not_only_idiom's [Nn]ot/[Oo]nly form only covered Title-Case
# and lowercase, not a fully uppercase emphasis form like "NOT ONLY does
# this look good, it is approved" (fresh evidence from PR #1490 finding
# 3793330278, a followup to 3793299512). Every letter is now
# bracket-expanded for both cases.
#
# Retargeted and renamed for issue #1491's conservative-verdict-classifier
# redesign: this body does not reproduce CODEX_APPROVED_TEMPLATES' whole-
# body exact template, so it now correctly safe-fails to NEEDS_REVISION,
# for the same reason as codex_not_only_idiom_safe_fails_root_comment
# above. Renamed from "...stays_approved_..." per the plan's naming
# standing rule.
_codex_not_only_idiom_uppercase_safe_fails_root_comment_mock_dir="$(mktemp -d)"
cat > "$_codex_not_only_idiom_uppercase_safe_fails_root_comment_mock_dir/gh" <<'CODEX_NOT_ONLY_IDIOM_UPPERCASE_SAFE_FAILS_ROOT_COMMENT_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'facade01991234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":297,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"id":298,"created_at":"2026-01-01T00:00:01Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"NOT ONLY does this look good, it is approved.\\n\\n**Reviewed commit:** `facade01991`"}]\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_NOT_ONLY_IDIOM_UPPERCASE_SAFE_FAILS_ROOT_COMMENT_GH
chmod +x "$_codex_not_only_idiom_uppercase_safe_fails_root_comment_mock_dir/gh"

_codex_not_only_idiom_uppercase_safe_fails_root_comment_output=""
_codex_not_only_idiom_uppercase_safe_fails_root_comment_exit=0
PATH="$_codex_not_only_idiom_uppercase_safe_fails_root_comment_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_not_only_idiom_uppercase_safe_fails_root_comment_mock_dir/output.txt" 2>&1 || _codex_not_only_idiom_uppercase_safe_fails_root_comment_exit=$?
_codex_not_only_idiom_uppercase_safe_fails_root_comment_output="$(cat "$_codex_not_only_idiom_uppercase_safe_fails_root_comment_mock_dir/output.txt")"
run_test "codex_not_only_idiom_uppercase_safe_fails_root_comment_exit_needs_revision" "2" "$_codex_not_only_idiom_uppercase_safe_fails_root_comment_exit"
run_test "codex_not_only_idiom_uppercase_safe_fails_root_comment_verdict" "VERDICT: ESCALATE — Codex terminal verdict matches neither an approved clean template nor the documented blocking markers" \
  "$(printf '%s\n' "$_codex_not_only_idiom_uppercase_safe_fails_root_comment_output" | grep "^VERDICT:")"
rm -rf "$_codex_not_only_idiom_uppercase_safe_fails_root_comment_mock_dir"
unset _codex_not_only_idiom_uppercase_safe_fails_root_comment_mock_dir _codex_not_only_idiom_uppercase_safe_fails_root_comment_output _codex_not_only_idiom_uppercase_safe_fails_root_comment_exit

# "unable to" wasn't in CODEX_NEGATION_WORDS at all, so "I am unable to
# approve this change" wasn't recognized as a rejection while an earlier
# "looks good" in the same sentence still matched (fresh evidence from PR
# #1490 finding 3793367883, same class of gap as "cannot approve" fixed
# for finding 3790023141, just a different inability phrase).
_codex_unable_to_approve_root_comment_mock_dir="$(mktemp -d)"
cat > "$_codex_unable_to_approve_root_comment_mock_dir/gh" <<'CODEX_UNABLE_TO_APPROVE_ROOT_COMMENT_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'facade02001234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":299,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"id":300,"created_at":"2026-01-01T00:00:01Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"This looks good at first glance, but I am unable to approve this change.\\n\\n**Reviewed commit:** `facade02001`"}]\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_UNABLE_TO_APPROVE_ROOT_COMMENT_GH
chmod +x "$_codex_unable_to_approve_root_comment_mock_dir/gh"

_codex_unable_to_approve_root_comment_output=""
_codex_unable_to_approve_root_comment_exit=0
PATH="$_codex_unable_to_approve_root_comment_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_unable_to_approve_root_comment_mock_dir/output.txt" 2>&1 || _codex_unable_to_approve_root_comment_exit=$?
_codex_unable_to_approve_root_comment_output="$(cat "$_codex_unable_to_approve_root_comment_mock_dir/output.txt")"
run_test "codex_unable_to_approve_root_comment_exit_needs_revision" "2" "$_codex_unable_to_approve_root_comment_exit"
run_test "codex_unable_to_approve_root_comment_verdict" "VERDICT: ESCALATE — Codex terminal verdict matches neither an approved clean template nor the documented blocking markers" \
  "$(printf '%s\n' "$_codex_unable_to_approve_root_comment_output" | grep "^VERDICT:")"
rm -rf "$_codex_unable_to_approve_root_comment_mock_dir"
unset _codex_unable_to_approve_root_comment_mock_dir _codex_unable_to_approve_root_comment_output _codex_unable_to_approve_root_comment_exit

# codex_strip_quoted_spans only stripped straight-double-quoted and
# backtick-quoted spans, not GitHub-flavored Markdown blockquote lines
# (a line starting with `>`), so a review discussing a quoted clean
# phrase via blockquote syntax (e.g. "The documentation claims:\n> No
# blocking issues found\nThat claim is inaccurate") still matched and
# returned APPROVED (fresh evidence from PR #1490 finding 3793367885).
# codex_strip_quoted_spans now also deletes blockquote lines.
_codex_blockquoted_clean_phrase_not_approved_root_comment_mock_dir="$(mktemp -d)"
cat > "$_codex_blockquoted_clean_phrase_not_approved_root_comment_mock_dir/gh" <<'CODEX_BLOCKQUOTED_CLEAN_PHRASE_NOT_APPROVED_ROOT_COMMENT_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'facade02111234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":301,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    jq -nc '[{id:302,created_at:"2026-01-01T00:00:01Z",user:{login:"chatgpt-codex-connector[bot]"},body:("The documentation claims:\n> No blocking issues found\nThat claim is inaccurate.\n\n**Reviewed commit:** `facade02111`")}]'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_BLOCKQUOTED_CLEAN_PHRASE_NOT_APPROVED_ROOT_COMMENT_GH
chmod +x "$_codex_blockquoted_clean_phrase_not_approved_root_comment_mock_dir/gh"

_codex_blockquoted_clean_phrase_not_approved_root_comment_output=""
_codex_blockquoted_clean_phrase_not_approved_root_comment_exit=0
PATH="$_codex_blockquoted_clean_phrase_not_approved_root_comment_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_blockquoted_clean_phrase_not_approved_root_comment_mock_dir/output.txt" 2>&1 || _codex_blockquoted_clean_phrase_not_approved_root_comment_exit=$?
_codex_blockquoted_clean_phrase_not_approved_root_comment_output="$(cat "$_codex_blockquoted_clean_phrase_not_approved_root_comment_mock_dir/output.txt")"
run_test "codex_blockquoted_clean_phrase_not_approved_root_comment_exit_needs_revision" "2" "$_codex_blockquoted_clean_phrase_not_approved_root_comment_exit"
run_test "codex_blockquoted_clean_phrase_not_approved_root_comment_verdict" "VERDICT: ESCALATE — Codex terminal verdict matches neither an approved clean template nor the documented blocking markers" \
  "$(printf '%s\n' "$_codex_blockquoted_clean_phrase_not_approved_root_comment_output" | grep "^VERDICT:")"
rm -rf "$_codex_blockquoted_clean_phrase_not_approved_root_comment_mock_dir"
unset _codex_blockquoted_clean_phrase_not_approved_root_comment_mock_dir _codex_blockquoted_clean_phrase_not_approved_root_comment_output _codex_blockquoted_clean_phrase_not_approved_root_comment_exit

# codex_response_is_blocking was never quote-stripped at all — only the
# approval/negation checks were — so a quoted blocker token in an
# otherwise clean review (e.g. "No blocking issues found. The tests
# correctly cover the `must fix` marker.") still matched
# CODEX_BLOCKING_PATTERN's "must fix" alternative and returned
# NEEDS_REVISION for an actually-clean review (fresh evidence from PR
# #1490 finding 3793367887). codex_response_is_blocking now shares the
# same codex_strip_quoted_spans normalization as the approval checks.
#
# Retargeted and renamed for issue #1491's conservative-verdict-classifier
# redesign: this body does not reproduce CODEX_APPROVED_TEMPLATES' whole-
# body exact template, so it now correctly safe-fails to NEEDS_REVISION.
# The property this scenario actually tests — that the quoted "must fix"
# token does not cause a false blocking verdict — is unaffected:
# codex_response_is_blocking (Decision 4, unchanged) still quote-strips
# before matching and still correctly does not classify this body as
# blocking; the composed verdict now reaches the unrecognized-format
# safe-fail instead of APPROVED, never the blocking branch. Renamed from
# "...stays_approved_..." per the plan's naming standing rule.
_codex_quoted_blocker_token_safe_fails_root_comment_mock_dir="$(mktemp -d)"
cat > "$_codex_quoted_blocker_token_safe_fails_root_comment_mock_dir/gh" <<'CODEX_QUOTED_BLOCKER_TOKEN_SAFE_FAILS_ROOT_COMMENT_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'facade02221234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":303,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[{"submitted_at":"2026-01-01T00:00:01Z","commit_id":"facade02221234567890","user":{"login":"chatgpt-codex-connector[bot]"},"body":"No blocking issues found. The tests correctly cover the `must fix` marker."}]\n'
    exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_QUOTED_BLOCKER_TOKEN_SAFE_FAILS_ROOT_COMMENT_GH
chmod +x "$_codex_quoted_blocker_token_safe_fails_root_comment_mock_dir/gh"

_codex_quoted_blocker_token_safe_fails_root_comment_output=""
_codex_quoted_blocker_token_safe_fails_root_comment_exit=0
PATH="$_codex_quoted_blocker_token_safe_fails_root_comment_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_quoted_blocker_token_safe_fails_root_comment_mock_dir/output.txt" 2>&1 || _codex_quoted_blocker_token_safe_fails_root_comment_exit=$?
_codex_quoted_blocker_token_safe_fails_root_comment_output="$(cat "$_codex_quoted_blocker_token_safe_fails_root_comment_mock_dir/output.txt")"
run_test "codex_quoted_blocker_token_safe_fails_root_comment_exit_needs_revision" "2" "$_codex_quoted_blocker_token_safe_fails_root_comment_exit"
run_test "codex_quoted_blocker_token_safe_fails_root_comment_verdict" "VERDICT: ESCALATE — Codex terminal verdict matches neither an approved clean template nor the documented blocking markers" \
  "$(printf '%s\n' "$_codex_quoted_blocker_token_safe_fails_root_comment_output" | grep "^VERDICT:")"
rm -rf "$_codex_quoted_blocker_token_safe_fails_root_comment_mock_dir"
unset _codex_quoted_blocker_token_safe_fails_root_comment_mock_dir _codex_quoted_blocker_token_safe_fails_root_comment_output _codex_quoted_blocker_token_safe_fails_root_comment_exit

# codex_response_is_blocking briefly gained the same fence-marker bail-out
# used by is_usage_limit/is_environment_error/is_approved (applied "for
# consistency" while fixing finding 3796042503), but that guard is unsafe
# specifically for this classifier: a genuinely asserted blocking finding
# OUTSIDE a fence, in a review that also happens to contain an unrelated
# fenced code example elsewhere, must still be detected — Protocol 93's
# "blocking always wins" invariant depends on is_blocking correctly
# reporting TRUE for such a review, and bailing out on fence presence let
# a real blocker fall through to the unrecognized-format safe-fail instead
# of being reported as a detected blocking finding (fresh evidence from PR
# #1490 finding 3796396399, a regression introduced by 3796042503's fix).
# is_blocking must keep detecting a real blocker even when the review also
# contains an unrelated fenced example, unlike the other three classifiers.
_codex_fenced_example_outside_blocker_stays_blocking_root_comment_mock_dir="$(mktemp -d)"
cat > "$_codex_fenced_example_outside_blocker_stays_blocking_root_comment_mock_dir/gh" <<'CODEX_FENCED_EXAMPLE_OUTSIDE_BLOCKER_STAYS_BLOCKING_ROOT_COMMENT_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'facade02221234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":303,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[{"submitted_at":"2026-01-01T00:00:01Z","commit_id":"facade02221234567890","user":{"login":"chatgpt-codex-connector[bot]"},"body":"This must fix the validation error before merge.\\n\\nExample:\\n```\\nfoo();\\n```"}]\n'
    exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_FENCED_EXAMPLE_OUTSIDE_BLOCKER_STAYS_BLOCKING_ROOT_COMMENT_GH
chmod +x "$_codex_fenced_example_outside_blocker_stays_blocking_root_comment_mock_dir/gh"

_codex_fenced_example_outside_blocker_stays_blocking_root_comment_output=""
_codex_fenced_example_outside_blocker_stays_blocking_root_comment_exit=0
PATH="$_codex_fenced_example_outside_blocker_stays_blocking_root_comment_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_fenced_example_outside_blocker_stays_blocking_root_comment_mock_dir/output.txt" 2>&1 || _codex_fenced_example_outside_blocker_stays_blocking_root_comment_exit=$?
_codex_fenced_example_outside_blocker_stays_blocking_root_comment_output="$(cat "$_codex_fenced_example_outside_blocker_stays_blocking_root_comment_mock_dir/output.txt")"
run_test "codex_fenced_example_outside_blocker_stays_blocking_root_comment_exit_needs_revision" "2" "$_codex_fenced_example_outside_blocker_stays_blocking_root_comment_exit"
run_test "codex_fenced_example_outside_blocker_stays_blocking_root_comment_verdict" "VERDICT: ESCALATE — Codex finding has no stable review-thread identifier or no identifiable matching review-thread conversation" \
  "$(printf '%s\n' "$_codex_fenced_example_outside_blocker_stays_blocking_root_comment_output" | grep "^VERDICT:")"
rm -rf "$_codex_fenced_example_outside_blocker_stays_blocking_root_comment_mock_dir"
unset _codex_fenced_example_outside_blocker_stays_blocking_root_comment_mock_dir _codex_fenced_example_outside_blocker_stays_blocking_root_comment_output _codex_fenced_example_outside_blocker_stays_blocking_root_comment_exit

# The reviewer script relied entirely on free-text body parsing
# (codex_response_is_blocking/is_approved) and never consulted GitHub's
# own structured review `state` field (APPROVED/CHANGES_REQUESTED/
# COMMENTED/PENDING/DISMISSED), even though the reviews-endpoint response
# carries it directly. A submitted review with state CHANGES_REQUESTED
# but a clean-sounding or ambiguous body ("Looks good overall, but see
# the note below.") fell through to the unrecognized-format safe-fail
# instead of being recognized as blocking on GitHub's own authoritative
# signal (fresh evidence from PR #1490 finding 3796396391).
# codex_combine_terminal_evidence now threads the review's state through
# as COMBINED_REVIEW_STATE, and the verdict-parsing chain short-circuits
# to blocking whenever a winning review's state is CHANGES_REQUESTED,
# ahead of free-text classification.
_codex_changes_requested_state_forces_blocking_root_comment_mock_dir="$(mktemp -d)"
cat > "$_codex_changes_requested_state_forces_blocking_root_comment_mock_dir/gh" <<'CODEX_CHANGES_REQUESTED_STATE_FORCES_BLOCKING_ROOT_COMMENT_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'facade02221234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":303,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[{"submitted_at":"2026-01-01T00:00:01Z","commit_id":"facade02221234567890","state":"CHANGES_REQUESTED","user":{"login":"chatgpt-codex-connector[bot]"},"body":"Looks good overall, but see the note below."}]\n'
    exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_CHANGES_REQUESTED_STATE_FORCES_BLOCKING_ROOT_COMMENT_GH
chmod +x "$_codex_changes_requested_state_forces_blocking_root_comment_mock_dir/gh"

_codex_changes_requested_state_forces_blocking_root_comment_output=""
_codex_changes_requested_state_forces_blocking_root_comment_exit=0
PATH="$_codex_changes_requested_state_forces_blocking_root_comment_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_changes_requested_state_forces_blocking_root_comment_mock_dir/output.txt" 2>&1 || _codex_changes_requested_state_forces_blocking_root_comment_exit=$?
_codex_changes_requested_state_forces_blocking_root_comment_output="$(cat "$_codex_changes_requested_state_forces_blocking_root_comment_mock_dir/output.txt")"
run_test "codex_changes_requested_state_forces_blocking_root_comment_exit_needs_revision" "1" "$_codex_changes_requested_state_forces_blocking_root_comment_exit"
run_test "codex_changes_requested_state_forces_blocking_root_comment_verdict" "VERDICT: NEEDS_REVISION" \
  "$(printf '%s\n' "$_codex_changes_requested_state_forces_blocking_root_comment_output" | grep "^VERDICT:")"
rm -rf "$_codex_changes_requested_state_forces_blocking_root_comment_mock_dir"
unset _codex_changes_requested_state_forces_blocking_root_comment_mock_dir _codex_changes_requested_state_forces_blocking_root_comment_output _codex_changes_requested_state_forces_blocking_root_comment_exit

# codex_select_review_evidence's tie-break ranked tied current-head reviews
# via codex_response_priority(body) alone, which had no notion of the
# extracted `state` field. Two reviews tied at the same second — a clean
# one and a CHANGES_REQUESTED one whose body ALSO happens to contain an
# approval phrase like "Looks good" — both scored priority 0 from body
# text, so whichever the API returned FIRST kept the selection (only a
# STRICTLY greater priority replaces it): the clean review is returned
# first here, so without the fix the CHANGES_REQUESTED review's state was
# silently discarded and the run returned APPROVED (fresh evidence from
# PR #1490 finding 3796982553). codex_response_priority now also treats
# state CHANGES_REQUESTED as blocking-tier, so the tied CHANGES_REQUESTED
# review wins regardless of array order.
_codex_tied_changes_requested_wins_priority_tie_root_comment_mock_dir="$(mktemp -d)"
cat > "$_codex_tied_changes_requested_wins_priority_tie_root_comment_mock_dir/gh" <<'CODEX_TIED_CHANGES_REQUESTED_WINS_PRIORITY_TIE_ROOT_COMMENT_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'facade02221234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":303,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[{"submitted_at":"2026-01-01T00:00:01Z","commit_id":"facade02221234567890","state":"COMMENTED","user":{"login":"chatgpt-codex-connector[bot]"},"body":"Looks good overall."},{"submitted_at":"2026-01-01T00:00:01Z","commit_id":"facade02221234567890","state":"CHANGES_REQUESTED","user":{"login":"chatgpt-codex-connector[bot]"},"body":"Looks good overall, but see inline comments."}]\n'
    exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_TIED_CHANGES_REQUESTED_WINS_PRIORITY_TIE_ROOT_COMMENT_GH
chmod +x "$_codex_tied_changes_requested_wins_priority_tie_root_comment_mock_dir/gh"

_codex_tied_changes_requested_wins_priority_tie_root_comment_output=""
_codex_tied_changes_requested_wins_priority_tie_root_comment_exit=0
PATH="$_codex_tied_changes_requested_wins_priority_tie_root_comment_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_tied_changes_requested_wins_priority_tie_root_comment_mock_dir/output.txt" 2>&1 || _codex_tied_changes_requested_wins_priority_tie_root_comment_exit=$?
_codex_tied_changes_requested_wins_priority_tie_root_comment_output="$(cat "$_codex_tied_changes_requested_wins_priority_tie_root_comment_mock_dir/output.txt")"
run_test "codex_tied_changes_requested_wins_priority_tie_root_comment_exit_needs_revision" "1" "$_codex_tied_changes_requested_wins_priority_tie_root_comment_exit"
run_test "codex_tied_changes_requested_wins_priority_tie_root_comment_verdict" "VERDICT: NEEDS_REVISION" \
  "$(printf '%s\n' "$_codex_tied_changes_requested_wins_priority_tie_root_comment_output" | grep "^VERDICT:")"
rm -rf "$_codex_tied_changes_requested_wins_priority_tie_root_comment_mock_dir"
unset _codex_tied_changes_requested_wins_priority_tie_root_comment_mock_dir _codex_tied_changes_requested_wins_priority_tie_root_comment_output _codex_tied_changes_requested_wins_priority_tie_root_comment_exit

# A review with state DISMISSED still matched the SHA/bot/timestamp
# filters (dismissal doesn't change commit_id or submitted_at), so its
# now-stale body text (recorded before it was dismissed) could still be
# selected as fresh terminal approval evidence on an idempotent rerun —
# GitHub itself no longer treats a dismissed review as active (fresh
# evidence from PR #1490 finding 3796982554). The reviews-endpoint jq
# queries now exclude state DISMISSED entirely, so with no other
# evidence, the run must fail closed to TIMED_OUT rather than APPROVED.
_codex_dismissed_review_excluded_root_comment_mock_dir="$(mktemp -d)"
cat > "$_codex_dismissed_review_excluded_root_comment_mock_dir/gh" <<'CODEX_DISMISSED_REVIEW_EXCLUDED_ROOT_COMMENT_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'facade02221234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":303,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[{"submitted_at":"2026-01-01T00:00:01Z","commit_id":"facade02221234567890","state":"DISMISSED","user":{"login":"chatgpt-codex-connector[bot]"},"body":"No blocking issues found."}]\n'
    exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_DISMISSED_REVIEW_EXCLUDED_ROOT_COMMENT_GH
chmod +x "$_codex_dismissed_review_excluded_root_comment_mock_dir/gh"

_codex_dismissed_review_excluded_root_comment_output=""
_codex_dismissed_review_excluded_root_comment_exit=0
PATH="$_codex_dismissed_review_excluded_root_comment_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_dismissed_review_excluded_root_comment_mock_dir/output.txt" 2>&1 || _codex_dismissed_review_excluded_root_comment_exit=$?
_codex_dismissed_review_excluded_root_comment_output="$(cat "$_codex_dismissed_review_excluded_root_comment_mock_dir/output.txt")"
run_test "codex_dismissed_review_excluded_root_comment_exit_waiting" "4" "$_codex_dismissed_review_excluded_root_comment_exit"
run_test "codex_dismissed_review_excluded_root_comment_verdict_not_approved" "WAITING_ON_REVIEWER" \
  "$(printf '%s\n' "$_codex_dismissed_review_excluded_root_comment_output" | grep -oE 'VERDICT: (WAITING_ON_REVIEWER|APPROVED)' | grep -oE 'WAITING_ON_REVIEWER|APPROVED')"
rm -rf "$_codex_dismissed_review_excluded_root_comment_mock_dir"
unset _codex_dismissed_review_excluded_root_comment_mock_dir _codex_dismissed_review_excluded_root_comment_output _codex_dismissed_review_excluded_root_comment_exit

# codex_select_review_evidence's tie-break (finding 3796982553) was fixed
# to treat a tied CHANGES_REQUESTED review as blocking-tier regardless of
# body text, but that fix only covers the review-vs-review tie-break. The
# SEPARATE comment-vs-review tie-break in codex_select_terminal_evidence
# (used when a SHA-pinned terminal root comment and a current-head review
# share the same second-resolution timestamp) still called
# codex_response_priority with body text only, with no state parameter at
# all. A clean-looking SHA-pinned root comment ("No blocking issues
# found.") and a same-timestamp CHANGES_REQUESTED review whose body ALSO
# reads clean ("Looks good overall, but see inline comments.") both
# scored priority 0 from body text, and since the comment is always
# CURRENT in this comparison (set by the terminal-comment block before
# the review is ever considered), the review never outranked it — the
# review's CHANGES_REQUESTED state was discarded and the run returned
# APPROVED (fresh evidence from PR #1490 finding 3797160202, a followup
# to 3796982553 that fixed the review-vs-review tie-break but missed this
# separate comment-vs-review one). codex_select_terminal_evidence now
# accepts current/candidate state params and passes the review's state
# through, so a same-timestamp CHANGES_REQUESTED review beats a
# clean-looking root comment regardless of which source is "current".
_codex_tied_changes_requested_review_beats_clean_root_comment_mock_dir="$(mktemp -d)"
cat > "$_codex_tied_changes_requested_review_beats_clean_root_comment_mock_dir/gh" <<'CODEX_TIED_CHANGES_REQUESTED_REVIEW_BEATS_CLEAN_ROOT_COMMENT_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'beef00001234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":304,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[{"submitted_at":"2026-01-01T00:00:01Z","commit_id":"beef00001234567890","state":"CHANGES_REQUESTED","user":{"login":"chatgpt-codex-connector[bot]"},"body":"Looks good overall, but see inline comments."}]\n'
    exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"id":230,"created_at":"2026-01-01T00:00:01Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"No blocking issues found.\\n\\n**Reviewed commit:** `beef0000`"}]\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_TIED_CHANGES_REQUESTED_REVIEW_BEATS_CLEAN_ROOT_COMMENT_GH
chmod +x "$_codex_tied_changes_requested_review_beats_clean_root_comment_mock_dir/gh"

_codex_tied_changes_requested_review_beats_clean_root_comment_output=""
_codex_tied_changes_requested_review_beats_clean_root_comment_exit=0
PATH="$_codex_tied_changes_requested_review_beats_clean_root_comment_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_tied_changes_requested_review_beats_clean_root_comment_mock_dir/output.txt" 2>&1 || _codex_tied_changes_requested_review_beats_clean_root_comment_exit=$?
_codex_tied_changes_requested_review_beats_clean_root_comment_output="$(cat "$_codex_tied_changes_requested_review_beats_clean_root_comment_mock_dir/output.txt")"
run_test "codex_tied_changes_requested_review_beats_clean_root_comment_exit_needs_revision" "1" "$_codex_tied_changes_requested_review_beats_clean_root_comment_exit"
run_test "codex_tied_changes_requested_review_beats_clean_root_comment_verdict" "VERDICT: NEEDS_REVISION" \
  "$(printf '%s\n' "$_codex_tied_changes_requested_review_beats_clean_root_comment_output" | grep "^VERDICT:")"
rm -rf "$_codex_tied_changes_requested_review_beats_clean_root_comment_mock_dir"
unset _codex_tied_changes_requested_review_beats_clean_root_comment_mock_dir _codex_tied_changes_requested_review_beats_clean_root_comment_output _codex_tied_changes_requested_review_beats_clean_root_comment_exit

# codex_strip_quoted_spans' double-quote stripping ran inside a single sed
# invocation, which operates per-line by default (each line is its own
# pattern space) — a straight-double-quote pair that spans a newline (e.g.
# `The documented response "` / `No blocking issues found` / `" is
# inaccurate` across three lines) was never stripped at all, since the
# opening and closing quote are in different sed pattern spaces. The
# quoted clean phrase reached classification unstripped and matched
# CODEX_APPROVAL_PATTERN's "no blocking issues" alternative, returning
# APPROVED instead of the documented unrecognized-format safe-fail (fresh
# evidence from PR #1490 finding 3797334339, a multi-line followup to the
# same-line case already covered by codex_quoted_clean_phrase_not_
# approved_root_comment above). codex_strip_quoted_spans now flattens
# newlines to a placeholder before the double-/single-quote stripping
# passes (restoring them immediately after, before the line-oriented
# backtick pass), so a quote pair can be stripped regardless of how many
# original lines it spans.
_codex_multiline_quoted_clean_phrase_not_approved_root_comment_mock_dir="$(mktemp -d)"
cat > "$_codex_multiline_quoted_clean_phrase_not_approved_root_comment_mock_dir/gh" <<'CODEX_MULTILINE_QUOTED_CLEAN_PHRASE_NOT_APPROVED_ROOT_COMMENT_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'beef00001234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":306,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    jq -nc '[{id:307,created_at:"2026-01-01T00:00:01Z",user:{login:"chatgpt-codex-connector[bot]"},body:("The documented response \"\nNo blocking issues found\n\" is inaccurate and should be corrected.\n\n**Reviewed commit:** `beef0000`")}]'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_MULTILINE_QUOTED_CLEAN_PHRASE_NOT_APPROVED_ROOT_COMMENT_GH
chmod +x "$_codex_multiline_quoted_clean_phrase_not_approved_root_comment_mock_dir/gh"

_codex_multiline_quoted_clean_phrase_not_approved_root_comment_output=""
_codex_multiline_quoted_clean_phrase_not_approved_root_comment_exit=0
PATH="$_codex_multiline_quoted_clean_phrase_not_approved_root_comment_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_multiline_quoted_clean_phrase_not_approved_root_comment_mock_dir/output.txt" 2>&1 || _codex_multiline_quoted_clean_phrase_not_approved_root_comment_exit=$?
_codex_multiline_quoted_clean_phrase_not_approved_root_comment_output="$(cat "$_codex_multiline_quoted_clean_phrase_not_approved_root_comment_mock_dir/output.txt")"
run_test "codex_multiline_quoted_clean_phrase_not_approved_root_comment_exit_needs_revision" "2" "$_codex_multiline_quoted_clean_phrase_not_approved_root_comment_exit"
run_test "codex_multiline_quoted_clean_phrase_not_approved_root_comment_verdict" "VERDICT: ESCALATE — Codex terminal verdict matches neither an approved clean template nor the documented blocking markers" \
  "$(printf '%s\n' "$_codex_multiline_quoted_clean_phrase_not_approved_root_comment_output" | grep "^VERDICT:")"
rm -rf "$_codex_multiline_quoted_clean_phrase_not_approved_root_comment_mock_dir"
unset _codex_multiline_quoted_clean_phrase_not_approved_root_comment_mock_dir _codex_multiline_quoted_clean_phrase_not_approved_root_comment_output _codex_multiline_quoted_clean_phrase_not_approved_root_comment_exit

# The newline-flattening fix above (codex_multiline_quoted_clean_phrase_
# not_approved_root_comment) had its own boundary gap: the single-quote
# pattern's boundary alternatives ((^|[[:space:]]) and
# ([[:space:].,;:!?]|$)) didn't include the placeholder character, so a
# single-quoted span occupying an ENTIRE original line by itself (e.g.
# "The documented response is:" / "'No blocking issues found'" / "That
# claim is inaccurate" across three lines) has the placeholder — not real
# whitespace, not true start/end-of-string — immediately before/after the
# quote once flattened, so neither boundary matched and the span survived
# unstripped, returning APPROVED (fresh evidence from PR #1490 finding
# 3798665078). codex_strip_quoted_spans now includes the placeholder as
# an additional valid boundary character for the single-quote pattern.
_codex_multiline_single_quoted_whole_line_not_approved_root_comment_mock_dir="$(mktemp -d)"
cat > "$_codex_multiline_single_quoted_whole_line_not_approved_root_comment_mock_dir/gh" <<'CODEX_MULTILINE_SINGLE_QUOTED_WHOLE_LINE_NOT_APPROVED_ROOT_COMMENT_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'dead00001234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":308,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    jq -nc '[{id:309,created_at:"2026-01-01T00:00:01Z",user:{login:"chatgpt-codex-connector[bot]"},body:("The documented response is:\n'"'"'No blocking issues found'"'"'\nThat claim is inaccurate.\n\n**Reviewed commit:** `dead0000`")}]'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_MULTILINE_SINGLE_QUOTED_WHOLE_LINE_NOT_APPROVED_ROOT_COMMENT_GH
chmod +x "$_codex_multiline_single_quoted_whole_line_not_approved_root_comment_mock_dir/gh"

_codex_multiline_single_quoted_whole_line_not_approved_root_comment_output=""
_codex_multiline_single_quoted_whole_line_not_approved_root_comment_exit=0
PATH="$_codex_multiline_single_quoted_whole_line_not_approved_root_comment_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_multiline_single_quoted_whole_line_not_approved_root_comment_mock_dir/output.txt" 2>&1 || _codex_multiline_single_quoted_whole_line_not_approved_root_comment_exit=$?
_codex_multiline_single_quoted_whole_line_not_approved_root_comment_output="$(cat "$_codex_multiline_single_quoted_whole_line_not_approved_root_comment_mock_dir/output.txt")"
run_test "codex_multiline_single_quoted_whole_line_not_approved_root_comment_exit_needs_revision" "2" "$_codex_multiline_single_quoted_whole_line_not_approved_root_comment_exit"
run_test "codex_multiline_single_quoted_whole_line_not_approved_root_comment_verdict" "VERDICT: ESCALATE — Codex terminal verdict matches neither an approved clean template nor the documented blocking markers" \
  "$(printf '%s\n' "$_codex_multiline_single_quoted_whole_line_not_approved_root_comment_output" | grep "^VERDICT:")"
rm -rf "$_codex_multiline_single_quoted_whole_line_not_approved_root_comment_mock_dir"
unset _codex_multiline_single_quoted_whole_line_not_approved_root_comment_mock_dir _codex_multiline_single_quoted_whole_line_not_approved_root_comment_output _codex_multiline_single_quoted_whole_line_not_approved_root_comment_exit

# codex_strip_quoted_spans deliberately kept backtick-pair stripping
# line-oriented, reasoning that GFM inline code spans never cross a line
# — that reasoning was WRONG. CommonMark/GFM inline code spans CAN
# legitimately span multiple lines (line endings inside a code span are
# normalized to spaces in the rendered output); only FENCED
# (triple-backtick) code blocks have line-anchored open/close semantics,
# a different construct. A single-backtick code span split across lines
# (e.g. "The documented response `" / "No blocking issues found" / "` is
# inaccurate") was never stripped, letting the coded clean phrase reach
# classification unstripped and return APPROVED (fresh evidence from PR
# #1490 finding 3798665086). Backtick-pair stripping now runs on the same
# newline-flattened body as the double-/single-quote passes.
_codex_multiline_backtick_span_not_approved_root_comment_mock_dir="$(mktemp -d)"
cat > "$_codex_multiline_backtick_span_not_approved_root_comment_mock_dir/gh" <<'CODEX_MULTILINE_BACKTICK_SPAN_NOT_APPROVED_ROOT_COMMENT_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'beef11121234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":310,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    jq -nc '[{id:311,created_at:"2026-01-01T00:00:01Z",user:{login:"chatgpt-codex-connector[bot]"},body:("The documented response `\nNo blocking issues found\n` is inaccurate and should be corrected.\n\n**Reviewed commit:** `beef1112`")}]'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_MULTILINE_BACKTICK_SPAN_NOT_APPROVED_ROOT_COMMENT_GH
chmod +x "$_codex_multiline_backtick_span_not_approved_root_comment_mock_dir/gh"

_codex_multiline_backtick_span_not_approved_root_comment_output=""
_codex_multiline_backtick_span_not_approved_root_comment_exit=0
PATH="$_codex_multiline_backtick_span_not_approved_root_comment_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_multiline_backtick_span_not_approved_root_comment_mock_dir/output.txt" 2>&1 || _codex_multiline_backtick_span_not_approved_root_comment_exit=$?
_codex_multiline_backtick_span_not_approved_root_comment_output="$(cat "$_codex_multiline_backtick_span_not_approved_root_comment_mock_dir/output.txt")"
run_test "codex_multiline_backtick_span_not_approved_root_comment_exit_needs_revision" "2" "$_codex_multiline_backtick_span_not_approved_root_comment_exit"
run_test "codex_multiline_backtick_span_not_approved_root_comment_verdict" "VERDICT: ESCALATE — Codex terminal verdict matches neither an approved clean template nor the documented blocking markers" \
  "$(printf '%s\n' "$_codex_multiline_backtick_span_not_approved_root_comment_output" | grep "^VERDICT:")"
rm -rf "$_codex_multiline_backtick_span_not_approved_root_comment_mock_dir"
unset _codex_multiline_backtick_span_not_approved_root_comment_mock_dir _codex_multiline_backtick_span_not_approved_root_comment_output _codex_multiline_backtick_span_not_approved_root_comment_exit

# CODEX_NEGATION_WORDS was missing "don't"/"do not" entirely — only the
# third-person singular form ("does not"/"doesn't") was covered, not the
# base form. A response like "This looks good at first glance, but I
# don't approve this change." had the negation word absent from the
# alternation, so the earlier positive phrase ("looks good") won and the
# response was classified APPROVED instead of falling through to the
# negated-approval check (fresh evidence from PR #1490 finding
# 3798756826). "don't"/"do not" is now included alongside every other
# verb's contracted and space-separated forms.
_codex_dont_approve_not_approved_root_comment_mock_dir="$(mktemp -d)"
cat > "$_codex_dont_approve_not_approved_root_comment_mock_dir/gh" <<'CODEX_DONT_APPROVE_NOT_APPROVED_ROOT_COMMENT_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'face00001234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":312,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    jq -nc '[{id:313,created_at:"2026-01-01T00:00:01Z",user:{login:"chatgpt-codex-connector[bot]"},body:("This looks good at first glance, but I don'"'"'t approve this change.\n\n**Reviewed commit:** `face0000`")}]'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_DONT_APPROVE_NOT_APPROVED_ROOT_COMMENT_GH
chmod +x "$_codex_dont_approve_not_approved_root_comment_mock_dir/gh"

_codex_dont_approve_not_approved_root_comment_output=""
_codex_dont_approve_not_approved_root_comment_exit=0
PATH="$_codex_dont_approve_not_approved_root_comment_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_dont_approve_not_approved_root_comment_mock_dir/output.txt" 2>&1 || _codex_dont_approve_not_approved_root_comment_exit=$?
_codex_dont_approve_not_approved_root_comment_output="$(cat "$_codex_dont_approve_not_approved_root_comment_mock_dir/output.txt")"
run_test "codex_dont_approve_not_approved_root_comment_exit_needs_revision" "2" "$_codex_dont_approve_not_approved_root_comment_exit"
run_test "codex_dont_approve_not_approved_root_comment_verdict" "VERDICT: ESCALATE — Codex terminal verdict matches neither an approved clean template nor the documented blocking markers" \
  "$(printf '%s\n' "$_codex_dont_approve_not_approved_root_comment_output" | grep "^VERDICT:")"
rm -rf "$_codex_dont_approve_not_approved_root_comment_mock_dir"
unset _codex_dont_approve_not_approved_root_comment_mock_dir _codex_dont_approve_not_approved_root_comment_output _codex_dont_approve_not_approved_root_comment_exit

# codex_strip_quoted_spans' backtick-pair regex (`[^\`]*\`) mishandles
# CommonMark's actual code-span delimiter-run matching: a code span CAN
# be delimited by a run of 2+ backticks (not just a single pair), and the
# naive regex treats an adjacent 2-backtick run as two separate EMPTY
# single-backtick pairs (each backtick immediately "closes" against its
# neighbor with zero content between), stripping only the empty delimiter
# markers and leaving the actual enclosed content fully exposed — e.g. a
# double-backtick-quoted `` `` No blocking issues found `` `` survived
# stripping intact and matched CODEX_APPROVAL_PATTERN, returning APPROVED
# (fresh evidence from PR #1490 finding 3798756834).
# codex_response_has_fence_marker's backtick threshold is now 2+ (was
# 3+), so a 2+-backtick run disqualifies the same way a 3+ run always
# has; single backtick PAIRS are unaffected and still get precise
# stripping.
_codex_double_backtick_span_not_approved_root_comment_mock_dir="$(mktemp -d)"
cat > "$_codex_double_backtick_span_not_approved_root_comment_mock_dir/gh" <<'CODEX_DOUBLE_BACKTICK_SPAN_NOT_APPROVED_ROOT_COMMENT_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'face11121234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":314,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    jq -nc '[{id:315,created_at:"2026-01-01T00:00:01Z",user:{login:"chatgpt-codex-connector[bot]"},body:("The documented response ``No blocking issues found`` is inaccurate and should be corrected.\n\n**Reviewed commit:** `face1112`")}]'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_DOUBLE_BACKTICK_SPAN_NOT_APPROVED_ROOT_COMMENT_GH
chmod +x "$_codex_double_backtick_span_not_approved_root_comment_mock_dir/gh"

_codex_double_backtick_span_not_approved_root_comment_output=""
_codex_double_backtick_span_not_approved_root_comment_exit=0
PATH="$_codex_double_backtick_span_not_approved_root_comment_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_double_backtick_span_not_approved_root_comment_mock_dir/output.txt" 2>&1 || _codex_double_backtick_span_not_approved_root_comment_exit=$?
_codex_double_backtick_span_not_approved_root_comment_output="$(cat "$_codex_double_backtick_span_not_approved_root_comment_mock_dir/output.txt")"
run_test "codex_double_backtick_span_not_approved_root_comment_exit_needs_revision" "2" "$_codex_double_backtick_span_not_approved_root_comment_exit"
run_test "codex_double_backtick_span_not_approved_root_comment_verdict" "VERDICT: ESCALATE — Codex terminal verdict matches neither an approved clean template nor the documented blocking markers" \
  "$(printf '%s\n' "$_codex_double_backtick_span_not_approved_root_comment_output" | grep "^VERDICT:")"
rm -rf "$_codex_double_backtick_span_not_approved_root_comment_mock_dir"
unset _codex_double_backtick_span_not_approved_root_comment_mock_dir _codex_double_backtick_span_not_approved_root_comment_output _codex_double_backtick_span_not_approved_root_comment_exit

# The negated-approval mechanism (CODEX_NEGATED_APPROVAL_PATTERN) only
# fires when a negation word is followed by one of a fixed list of
# approval-vocabulary target words (approve[ds]?, lgtm, looks good, etc.)
# within the same sentence. A response like "This looks good at first
# glance, but this should not be merged until tests pass." negates
# "merged" — a word outside that target list entirely — so the
# negated-approval check never matches, and the earlier "looks good"
# phrase alone wins, returning APPROVED (fresh evidence from PR #1490
# finding 3798880969, a followup to the "don't approve" fix that closed
# the adjacent-to-an-approval-word case but not this direct-merge-refusal
# case). CODEX_BLOCKING_PATTERN now recognizes an explicit
# should/must-not-be-merged verdict outright, checked before approval in
# the verdict-parsing chain.
_codex_should_not_be_merged_blocking_root_comment_mock_dir="$(mktemp -d)"
cat > "$_codex_should_not_be_merged_blocking_root_comment_mock_dir/gh" <<'CODEX_SHOULD_NOT_BE_MERGED_BLOCKING_ROOT_COMMENT_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'face22221234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":316,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"id":317,"created_at":"2026-01-01T00:00:01Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"This looks good at first glance, but this should not be merged until tests pass.\\n\\n**Reviewed commit:** `face2222`"}]\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_SHOULD_NOT_BE_MERGED_BLOCKING_ROOT_COMMENT_GH
chmod +x "$_codex_should_not_be_merged_blocking_root_comment_mock_dir/gh"

_codex_should_not_be_merged_blocking_root_comment_output=""
_codex_should_not_be_merged_blocking_root_comment_exit=0
PATH="$_codex_should_not_be_merged_blocking_root_comment_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_should_not_be_merged_blocking_root_comment_mock_dir/output.txt" 2>&1 || _codex_should_not_be_merged_blocking_root_comment_exit=$?
_codex_should_not_be_merged_blocking_root_comment_output="$(cat "$_codex_should_not_be_merged_blocking_root_comment_mock_dir/output.txt")"
run_test "codex_should_not_be_merged_blocking_root_comment_exit_needs_revision" "2" "$_codex_should_not_be_merged_blocking_root_comment_exit"
run_test "codex_should_not_be_merged_blocking_root_comment_verdict" "VERDICT: ESCALATE — Codex finding has no stable review-thread identifier or no identifiable matching review-thread conversation" \
  "$(printf '%s\n' "$_codex_should_not_be_merged_blocking_root_comment_output" | grep "^VERDICT:")"
rm -rf "$_codex_should_not_be_merged_blocking_root_comment_mock_dir"
unset _codex_should_not_be_merged_blocking_root_comment_mock_dir _codex_should_not_be_merged_blocking_root_comment_output _codex_should_not_be_merged_blocking_root_comment_exit

# The should/must-not-be-merged fix above only covered the PASSIVE form;
# the IMPERATIVE form ("do not merge"/"don't merge") is a separate,
# common phrasing that the same gap applies to for the identical reason
# — "merge" isn't in CODEX_NEGATED_APPROVAL_TARGET_WORDS either, and
# unlike the passive form's "not be merged", the imperative form's
# negation word isn't even adjacent to an approval-vocabulary word at
# all. A response like "This looks good at first glance, but do not
# merge until tests pass" still returned APPROVED (fresh evidence from PR
# #1490 finding 3798999561, a followup to the passive-form fix).
_codex_do_not_merge_blocking_root_comment_mock_dir="$(mktemp -d)"
cat > "$_codex_do_not_merge_blocking_root_comment_mock_dir/gh" <<'CODEX_DO_NOT_MERGE_BLOCKING_ROOT_COMMENT_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'face33331234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":318,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"id":319,"created_at":"2026-01-01T00:00:01Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"This looks good at first glance, but do not merge until tests pass.\\n\\n**Reviewed commit:** `face3333`"}]\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_DO_NOT_MERGE_BLOCKING_ROOT_COMMENT_GH
chmod +x "$_codex_do_not_merge_blocking_root_comment_mock_dir/gh"

_codex_do_not_merge_blocking_root_comment_output=""
_codex_do_not_merge_blocking_root_comment_exit=0
PATH="$_codex_do_not_merge_blocking_root_comment_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_do_not_merge_blocking_root_comment_mock_dir/output.txt" 2>&1 || _codex_do_not_merge_blocking_root_comment_exit=$?
_codex_do_not_merge_blocking_root_comment_output="$(cat "$_codex_do_not_merge_blocking_root_comment_mock_dir/output.txt")"
run_test "codex_do_not_merge_blocking_root_comment_exit_needs_revision" "2" "$_codex_do_not_merge_blocking_root_comment_exit"
run_test "codex_do_not_merge_blocking_root_comment_verdict" "VERDICT: ESCALATE — Codex finding has no stable review-thread identifier or no identifiable matching review-thread conversation" \
  "$(printf '%s\n' "$_codex_do_not_merge_blocking_root_comment_output" | grep "^VERDICT:")"
rm -rf "$_codex_do_not_merge_blocking_root_comment_mock_dir"
unset _codex_do_not_merge_blocking_root_comment_mock_dir _codex_do_not_merge_blocking_root_comment_output _codex_do_not_merge_blocking_root_comment_exit

# Manually enumerating merge-refusal phrasings one at a time in
# CODEX_BLOCKING_PATTERN ("should/must not be merged", then "do not
# merge"/"don't merge") kept surfacing the next unenumerated synonym —
# "cannot be merged" was the third sibling finding in a row (fresh
# evidence from PR #1490 finding 3799159335, a followup to 3798999561
# and 3798880969). Rather than add yet another one-off alternative,
# CODEX_BLOCKING_PATTERN now includes a generalized
# CODEX_MERGE_REFUSAL_PATTERN built from the existing CODEX_NEGATION_WORDS
# list (the same construction CODEX_NEGATED_APPROVAL_PATTERN already
# uses), so any negation word already known to this file — including
# future additions — automatically covers merge refusals too, without
# needing its own enumeration round-trip.
_codex_cannot_be_merged_blocking_root_comment_mock_dir="$(mktemp -d)"
cat > "$_codex_cannot_be_merged_blocking_root_comment_mock_dir/gh" <<'CODEX_CANNOT_BE_MERGED_BLOCKING_ROOT_COMMENT_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'face44441234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":320,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"id":321,"created_at":"2026-01-01T00:00:01Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"This looks good at first glance, but this cannot be merged until tests pass.\\n\\n**Reviewed commit:** `face4444`"}]\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_CANNOT_BE_MERGED_BLOCKING_ROOT_COMMENT_GH
chmod +x "$_codex_cannot_be_merged_blocking_root_comment_mock_dir/gh"

_codex_cannot_be_merged_blocking_root_comment_output=""
_codex_cannot_be_merged_blocking_root_comment_exit=0
PATH="$_codex_cannot_be_merged_blocking_root_comment_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_cannot_be_merged_blocking_root_comment_mock_dir/output.txt" 2>&1 || _codex_cannot_be_merged_blocking_root_comment_exit=$?
_codex_cannot_be_merged_blocking_root_comment_output="$(cat "$_codex_cannot_be_merged_blocking_root_comment_mock_dir/output.txt")"
run_test "codex_cannot_be_merged_blocking_root_comment_exit_needs_revision" "2" "$_codex_cannot_be_merged_blocking_root_comment_exit"
run_test "codex_cannot_be_merged_blocking_root_comment_verdict" "VERDICT: ESCALATE — Codex finding has no stable review-thread identifier or no identifiable matching review-thread conversation" \
  "$(printf '%s\n' "$_codex_cannot_be_merged_blocking_root_comment_output" | grep "^VERDICT:")"
rm -rf "$_codex_cannot_be_merged_blocking_root_comment_mock_dir"
unset _codex_cannot_be_merged_blocking_root_comment_mock_dir _codex_cannot_be_merged_blocking_root_comment_output _codex_cannot_be_merged_blocking_root_comment_exit

# The generalized CODEX_MERGE_REFUSAL_PATTERN reuses CODEX_NEGATION_WORDS'
# bare "not" alternative combined with an unbounded (except for
# sentence/clause terminators) span before "merge(d)" — the same
# clause-scoping already used by CODEX_NEGATED_APPROVAL_PATTERN protects
# against an unrelated EARLIER negation in a different clause being
# misread as targeting a LATER, unrelated mention of "merge": a genuinely
# clean review that discusses an unrelated negation before a separate
# instruction to merge must still classify as approved.
#
# Retargeted and renamed for issue #1491's conservative-verdict-classifier
# redesign: this body does not reproduce CODEX_APPROVED_TEMPLATES' whole-
# body exact template, so it now correctly safe-fails to NEEDS_REVISION.
# The property this scenario actually tests — that the unrelated earlier
# negation does not cause a false merge-refusal blocking verdict — is
# unaffected: CODEX_MERGE_REFUSAL_PATTERN and codex_response_is_blocking
# (Decision 4, unchanged) still correctly do not classify this body as
# blocking; the composed verdict now reaches the unrecognized-format
# safe-fail instead of APPROVED, never the blocking branch. Renamed from
# "...stays_approved_..." per the plan's naming standing rule.
_codex_unrelated_negation_before_merge_safe_fails_root_comment_mock_dir="$(mktemp -d)"
cat > "$_codex_unrelated_negation_before_merge_safe_fails_root_comment_mock_dir/gh" <<'CODEX_UNRELATED_NEGATION_BEFORE_MERGE_SAFE_FAILS_ROOT_COMMENT_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'face55551234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":322,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"id":323,"created_at":"2026-01-01T00:00:01Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"This is not a blocker; looks good, please merge.\\n\\n**Reviewed commit:** `face5555`"}]\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_UNRELATED_NEGATION_BEFORE_MERGE_SAFE_FAILS_ROOT_COMMENT_GH
chmod +x "$_codex_unrelated_negation_before_merge_safe_fails_root_comment_mock_dir/gh"

_codex_unrelated_negation_before_merge_safe_fails_root_comment_output=""
_codex_unrelated_negation_before_merge_safe_fails_root_comment_exit=0
PATH="$_codex_unrelated_negation_before_merge_safe_fails_root_comment_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_unrelated_negation_before_merge_safe_fails_root_comment_mock_dir/output.txt" 2>&1 || _codex_unrelated_negation_before_merge_safe_fails_root_comment_exit=$?
_codex_unrelated_negation_before_merge_safe_fails_root_comment_output="$(cat "$_codex_unrelated_negation_before_merge_safe_fails_root_comment_mock_dir/output.txt")"
run_test "codex_unrelated_negation_before_merge_safe_fails_root_comment_exit_needs_revision" "2" "$_codex_unrelated_negation_before_merge_safe_fails_root_comment_exit"
run_test "codex_unrelated_negation_before_merge_safe_fails_root_comment_verdict" "VERDICT: ESCALATE — Codex terminal verdict matches neither an approved clean template nor the documented blocking markers" \
  "$(printf '%s\n' "$_codex_unrelated_negation_before_merge_safe_fails_root_comment_output" | grep "^VERDICT:")"
rm -rf "$_codex_unrelated_negation_before_merge_safe_fails_root_comment_mock_dir"
unset _codex_unrelated_negation_before_merge_safe_fails_root_comment_mock_dir _codex_unrelated_negation_before_merge_safe_fails_root_comment_output _codex_unrelated_negation_before_merge_safe_fails_root_comment_exit

# CODEX_NEGATION_WORDS was missing "shouldn't"/"should not" and
# "mustn't"/"must not" entirely, so neither the generalized
# merge-refusal pattern nor the negated-approval pattern recognized a
# response like "This looks good at first glance, but this shouldn't be
# merged until tests pass" as a rejection, and the earlier "looks good"
# phrase alone won, returning APPROVED (fresh evidence from PR #1490
# finding 3799277919, a followup to the "cannot be merged" fix).
# "should not"/"shouldn't" and "must not"/"mustn't" are now included in
# CODEX_NEGATION_WORDS, automatically fixing both the merge-refusal and
# negated-approval checks at once (the whole point of generalizing
# merge-refusal detection to reuse this shared word list).
_codex_shouldnt_be_merged_blocking_root_comment_mock_dir="$(mktemp -d)"
cat > "$_codex_shouldnt_be_merged_blocking_root_comment_mock_dir/gh" <<'CODEX_SHOULDNT_BE_MERGED_BLOCKING_ROOT_COMMENT_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'face66661234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":324,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"id":325,"created_at":"2026-01-01T00:00:01Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"This looks good at first glance, but this shouldn'"'"'t be merged until tests pass.\\n\\n**Reviewed commit:** `face6666`"}]\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_SHOULDNT_BE_MERGED_BLOCKING_ROOT_COMMENT_GH
chmod +x "$_codex_shouldnt_be_merged_blocking_root_comment_mock_dir/gh"

_codex_shouldnt_be_merged_blocking_root_comment_output=""
_codex_shouldnt_be_merged_blocking_root_comment_exit=0
PATH="$_codex_shouldnt_be_merged_blocking_root_comment_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_shouldnt_be_merged_blocking_root_comment_mock_dir/output.txt" 2>&1 || _codex_shouldnt_be_merged_blocking_root_comment_exit=$?
_codex_shouldnt_be_merged_blocking_root_comment_output="$(cat "$_codex_shouldnt_be_merged_blocking_root_comment_mock_dir/output.txt")"
run_test "codex_shouldnt_be_merged_blocking_root_comment_exit_needs_revision" "2" "$_codex_shouldnt_be_merged_blocking_root_comment_exit"
run_test "codex_shouldnt_be_merged_blocking_root_comment_verdict" "VERDICT: ESCALATE — Codex finding has no stable review-thread identifier or no identifiable matching review-thread conversation" \
  "$(printf '%s\n' "$_codex_shouldnt_be_merged_blocking_root_comment_output" | grep "^VERDICT:")"
rm -rf "$_codex_shouldnt_be_merged_blocking_root_comment_mock_dir"
unset _codex_shouldnt_be_merged_blocking_root_comment_mock_dir _codex_shouldnt_be_merged_blocking_root_comment_output _codex_shouldnt_be_merged_blocking_root_comment_exit

# CODEX_BLOCKING_PATTERN's generalized merge-refusal alternative
# (CODEX_MERGE_REFUSAL_PATTERN) reuses CODEX_NEGATION_WORDS' bare "not"
# alternative the same way CODEX_NEGATED_APPROVAL_PATTERN does, so it
# inherited the exact same "not only X" affirmative-idiom
# misclassification that motivated codex_strip_not_only_idiom in the
# first place — "not only" is an intensifier, not a negation, but a
# clean response like "This is not only safe to merge but looks good"
# had "not" followed by "merge" within the same clause and was misread
# as a merge refusal, returning NEEDS_REVISION for a genuinely clean
# review (fresh evidence from PR #1490 finding 3799277922).
# codex_response_is_blocking now applies codex_strip_not_only_idiom the
# same way codex_response_is_approved already does.
#
# Retargeted and renamed for issue #1491's conservative-verdict-classifier
# redesign: this body does not reproduce CODEX_APPROVED_TEMPLATES' whole-
# body exact template, so it now correctly safe-fails to NEEDS_REVISION.
# This scenario's real coverage — that codex_strip_not_only_idiom's call
# inside codex_response_is_blocking is load-bearing (Decision 4) and still
# correctly prevents this "not only ... merge" idiom from being misread as
# a merge refusal — is unaffected: is_blocking is unchanged by this plan
# and codex_strip_not_only_idiom keeps both its definition and its one
# real call site there. The composed verdict now reaches the
# unrecognized-format safe-fail instead of APPROVED, never the blocking
# branch. Renamed from "...stays_approved_..." per the plan's naming
# standing rule.
_codex_not_only_safe_to_merge_safe_fails_root_comment_mock_dir="$(mktemp -d)"
cat > "$_codex_not_only_safe_to_merge_safe_fails_root_comment_mock_dir/gh" <<'CODEX_NOT_ONLY_SAFE_TO_MERGE_SAFE_FAILS_ROOT_COMMENT_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'face77771234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":326,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"id":327,"created_at":"2026-01-01T00:00:01Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"This is not only safe to merge but looks good.\\n\\n**Reviewed commit:** `face7777`"}]\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_NOT_ONLY_SAFE_TO_MERGE_SAFE_FAILS_ROOT_COMMENT_GH
chmod +x "$_codex_not_only_safe_to_merge_safe_fails_root_comment_mock_dir/gh"

_codex_not_only_safe_to_merge_safe_fails_root_comment_output=""
_codex_not_only_safe_to_merge_safe_fails_root_comment_exit=0
PATH="$_codex_not_only_safe_to_merge_safe_fails_root_comment_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_not_only_safe_to_merge_safe_fails_root_comment_mock_dir/output.txt" 2>&1 || _codex_not_only_safe_to_merge_safe_fails_root_comment_exit=$?
_codex_not_only_safe_to_merge_safe_fails_root_comment_output="$(cat "$_codex_not_only_safe_to_merge_safe_fails_root_comment_mock_dir/output.txt")"
run_test "codex_not_only_safe_to_merge_safe_fails_root_comment_exit_needs_revision" "2" "$_codex_not_only_safe_to_merge_safe_fails_root_comment_exit"
run_test "codex_not_only_safe_to_merge_safe_fails_root_comment_verdict" "VERDICT: ESCALATE — Codex terminal verdict matches neither an approved clean template nor the documented blocking markers" \
  "$(printf '%s\n' "$_codex_not_only_safe_to_merge_safe_fails_root_comment_output" | grep "^VERDICT:")"
rm -rf "$_codex_not_only_safe_to_merge_safe_fails_root_comment_mock_dir"
unset _codex_not_only_safe_to_merge_safe_fails_root_comment_mock_dir _codex_not_only_safe_to_merge_safe_fails_root_comment_output _codex_not_only_safe_to_merge_safe_fails_root_comment_exit

# CODEX_NEGATION_WORDS was missing "would not"/"wouldn't" — the fourth
# consecutive missing-negation-word finding (don't, should/mustn't, now
# wouldn't), which prompted a proactive sweep of the remaining common
# English negation forms (was/were/would/has/have/had, contracted and
# space-separated) in one pass rather than continuing to fix them one at
# a time (fresh evidence from PR #1490 finding 3799391883).
_codex_wouldnt_approve_not_approved_root_comment_mock_dir="$(mktemp -d)"
cat > "$_codex_wouldnt_approve_not_approved_root_comment_mock_dir/gh" <<'CODEX_WOULDNT_APPROVE_NOT_APPROVED_ROOT_COMMENT_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'face88881234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":328,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"id":329,"created_at":"2026-01-01T00:00:01Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"This looks good at first glance, but I wouldn'"'"'t approve this change.\\n\\n**Reviewed commit:** `face8888`"}]\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_WOULDNT_APPROVE_NOT_APPROVED_ROOT_COMMENT_GH
chmod +x "$_codex_wouldnt_approve_not_approved_root_comment_mock_dir/gh"

_codex_wouldnt_approve_not_approved_root_comment_output=""
_codex_wouldnt_approve_not_approved_root_comment_exit=0
PATH="$_codex_wouldnt_approve_not_approved_root_comment_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_wouldnt_approve_not_approved_root_comment_mock_dir/output.txt" 2>&1 || _codex_wouldnt_approve_not_approved_root_comment_exit=$?
_codex_wouldnt_approve_not_approved_root_comment_output="$(cat "$_codex_wouldnt_approve_not_approved_root_comment_mock_dir/output.txt")"
run_test "codex_wouldnt_approve_not_approved_root_comment_exit_needs_revision" "2" "$_codex_wouldnt_approve_not_approved_root_comment_exit"
run_test "codex_wouldnt_approve_not_approved_root_comment_verdict" "VERDICT: ESCALATE — Codex terminal verdict matches neither an approved clean template nor the documented blocking markers" \
  "$(printf '%s\n' "$_codex_wouldnt_approve_not_approved_root_comment_output" | grep "^VERDICT:")"
rm -rf "$_codex_wouldnt_approve_not_approved_root_comment_mock_dir"
unset _codex_wouldnt_approve_not_approved_root_comment_mock_dir _codex_wouldnt_approve_not_approved_root_comment_output _codex_wouldnt_approve_not_approved_root_comment_exit

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "Tests: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
