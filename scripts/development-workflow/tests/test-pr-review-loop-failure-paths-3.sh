#!/usr/bin/env bash
# test-pr-review-loop-failure-paths-3.sh — pr-review-loop.sh harness: Area 13
# (PR #801 failure paths), part 3 of 4.
# duration: 115
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
#   Area 13: PR #801 reviewer-loop failure paths (part 3 of 4)
#
# Usage: bash scripts/development-workflow/tests/test-pr-review-loop-failure-paths-3.sh [--area <name>]... [--list-areas]
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

# ---------------------------------------------------------------------------
# Area 13 (continued): PR #801 reviewer-loop failure paths, part 3 of 4
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 13: PR #801 reviewer-loop failure paths (part 3 of 4) ==="

# "did not"/"didn't" is DELIBERATELY excluded from the negation-word
# sweep above (see the comment above CODEX_NEGATION_WORDS): it already
# appears baked into CODEX_NEGATED_APPROVAL_TARGET_WORDS as part of the
# atomic phrase "didn't find any major issues" (itself a clean signal,
# not something to negate). Adding bare "didn.t" as a general negation
# word was verified during this sweep's own development to introduce a
# genuine false positive — caught and reverted before ever being
# committed — where a doubly-reinforced clean response ("Codex didn't
# find any major issues and looks good.") was misclassified as
# NEEDS_REVISION because "didn't" matched as a bare negation and reached
# the separate "looks good" target later in the same unpunctuated
# sentence. This test guards against that specific regression being
# silently reintroduced by a future negation-word addition.
#
# Retargeted and renamed for issue #1491's conservative-verdict-classifier
# redesign: this body does not reproduce CODEX_APPROVED_TEMPLATES' whole-
# body exact template (it has no "Swish!" sentence and no vendor footer),
# so it now correctly safe-fails to NEEDS_REVISION. CODEX_NEGATION_WORDS'
# "didn't"-exclusion property this scenario originally regression-tested
# is unaffected — CODEX_NEGATION_WORDS is kept unchanged (Decision 4) and
# still excludes "didn't" for the same reason, now guarding
# CODEX_MERGE_REFUSAL_PATTERN inside codex_response_is_blocking instead of
# the deleted negated-approval pattern. Renamed from "..._approved_..."
# per the plan's naming standing rule.
_codex_didnt_find_issues_and_looks_good_safe_fails_root_comment_mock_dir="$(mktemp -d)"
cat > "$_codex_didnt_find_issues_and_looks_good_safe_fails_root_comment_mock_dir/gh" <<'CODEX_DIDNT_FIND_ISSUES_AND_LOOKS_GOOD_SAFE_FAILS_ROOT_COMMENT_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'face99991234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":330,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"id":331,"created_at":"2026-01-01T00:00:01Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"Codex didn'"'"'t find any major issues and looks good.\\n\\n**Reviewed commit:** `face9999`"}]\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_DIDNT_FIND_ISSUES_AND_LOOKS_GOOD_SAFE_FAILS_ROOT_COMMENT_GH
chmod +x "$_codex_didnt_find_issues_and_looks_good_safe_fails_root_comment_mock_dir/gh"

_codex_didnt_find_issues_and_looks_good_safe_fails_root_comment_output=""
_codex_didnt_find_issues_and_looks_good_safe_fails_root_comment_exit=0
PATH="$_codex_didnt_find_issues_and_looks_good_safe_fails_root_comment_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_didnt_find_issues_and_looks_good_safe_fails_root_comment_mock_dir/output.txt" 2>&1 || _codex_didnt_find_issues_and_looks_good_safe_fails_root_comment_exit=$?
_codex_didnt_find_issues_and_looks_good_safe_fails_root_comment_output="$(cat "$_codex_didnt_find_issues_and_looks_good_safe_fails_root_comment_mock_dir/output.txt")"
run_test "codex_didnt_find_issues_and_looks_good_safe_fails_root_comment_exit_needs_revision" "2" "$_codex_didnt_find_issues_and_looks_good_safe_fails_root_comment_exit"
run_test "codex_didnt_find_issues_and_looks_good_safe_fails_root_comment_verdict" "VERDICT: ESCALATE — Codex terminal verdict matches neither an approved clean template nor the documented blocking markers" \
  "$(printf '%s\n' "$_codex_didnt_find_issues_and_looks_good_safe_fails_root_comment_output" | grep "^VERDICT:")"
rm -rf "$_codex_didnt_find_issues_and_looks_good_safe_fails_root_comment_mock_dir"
unset _codex_didnt_find_issues_and_looks_good_safe_fails_root_comment_mock_dir _codex_didnt_find_issues_and_looks_good_safe_fails_root_comment_output _codex_didnt_find_issues_and_looks_good_safe_fails_root_comment_exit

# codex_strip_quoted_spans handled straight-double-quotes, backticks, and
# blockquotes, but not single-quoted spans — the fourth quoting style
# found unprotected — so a review discussing a quoted clean phrase in
# single quotes (e.g. "The documented response 'No blocking issues
# found' is inaccurate and should be corrected") still matched and
# returned APPROVED (fresh evidence from PR #1490 finding 3793410331).
_codex_single_quoted_phrase_not_approved_root_comment_mock_dir="$(mktemp -d)"
cat > "$_codex_single_quoted_phrase_not_approved_root_comment_mock_dir/gh" <<'CODEX_SINGLE_QUOTED_PHRASE_NOT_APPROVED_ROOT_COMMENT_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'facade02331234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":304,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf "[{\"id\":305,\"created_at\":\"2026-01-01T00:00:01Z\",\"user\":{\"login\":\"chatgpt-codex-connector[bot]\"},\"body\":\"The documented response 'No blocking issues found' is inaccurate and should be corrected.\\\\n\\\\n**Reviewed commit:** \`facade02331\`\"}]\n"
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_SINGLE_QUOTED_PHRASE_NOT_APPROVED_ROOT_COMMENT_GH
chmod +x "$_codex_single_quoted_phrase_not_approved_root_comment_mock_dir/gh"

_codex_single_quoted_phrase_not_approved_root_comment_output=""
_codex_single_quoted_phrase_not_approved_root_comment_exit=0
PATH="$_codex_single_quoted_phrase_not_approved_root_comment_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_single_quoted_phrase_not_approved_root_comment_mock_dir/output.txt" 2>&1 || _codex_single_quoted_phrase_not_approved_root_comment_exit=$?
_codex_single_quoted_phrase_not_approved_root_comment_output="$(cat "$_codex_single_quoted_phrase_not_approved_root_comment_mock_dir/output.txt")"
run_test "codex_single_quoted_phrase_not_approved_root_comment_exit_needs_revision" "2" "$_codex_single_quoted_phrase_not_approved_root_comment_exit"
run_test "codex_single_quoted_phrase_not_approved_root_comment_verdict" "VERDICT: ESCALATE — Codex terminal verdict matches neither an approved clean template nor the documented blocking markers" \
  "$(printf '%s\n' "$_codex_single_quoted_phrase_not_approved_root_comment_output" | grep "^VERDICT:")"
rm -rf "$_codex_single_quoted_phrase_not_approved_root_comment_mock_dir"
unset _codex_single_quoted_phrase_not_approved_root_comment_mock_dir _codex_single_quoted_phrase_not_approved_root_comment_output _codex_single_quoted_phrase_not_approved_root_comment_exit

# Positive control for the single-quote stripping above: a bare
# `'[^']*'` pattern would also match the span between two UNRELATED
# apostrophes in contractions (e.g. the apostrophe in "isn't" and the
# apostrophe in "it's"), corrupting a genuinely clean review by deleting
# everything between them. The stricter whitespace/punctuation-boundary
# requirement must leave contractions untouched.
#
# Retargeted for issue #1491's conservative-verdict-classifier redesign:
# this body does not reproduce CODEX_APPROVED_TEMPLATES' whole-body exact
# template, so it now correctly safe-fails to NEEDS_REVISION. is_approved
# no longer calls codex_strip_quoted_spans at all (Decision 1), so this
# scenario no longer has a live approval-path mechanism to regression-test
# for contraction-mangling; codex_strip_quoted_spans itself is unchanged
# and still used by codex_response_is_blocking.
_codex_contraction_apostrophes_not_mangled_root_comment_mock_dir="$(mktemp -d)"
cat > "$_codex_contraction_apostrophes_not_mangled_root_comment_mock_dir/gh" <<'CODEX_CONTRACTION_APOSTROPHES_NOT_MANGLED_ROOT_COMMENT_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'facade02441234567890\n'; exit 0 ;;
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
    printf '[{"id":307,"created_at":"2026-01-01T00:00:01Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"It'\''s fine, doesn'\''t need changes. No blocking issues found.\\n\\n**Reviewed commit:** `facade02441`"}]\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_CONTRACTION_APOSTROPHES_NOT_MANGLED_ROOT_COMMENT_GH
chmod +x "$_codex_contraction_apostrophes_not_mangled_root_comment_mock_dir/gh"

_codex_contraction_apostrophes_not_mangled_root_comment_output=""
_codex_contraction_apostrophes_not_mangled_root_comment_exit=0
PATH="$_codex_contraction_apostrophes_not_mangled_root_comment_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_contraction_apostrophes_not_mangled_root_comment_mock_dir/output.txt" 2>&1 || _codex_contraction_apostrophes_not_mangled_root_comment_exit=$?
_codex_contraction_apostrophes_not_mangled_root_comment_output="$(cat "$_codex_contraction_apostrophes_not_mangled_root_comment_mock_dir/output.txt")"
run_test "codex_contraction_apostrophes_not_mangled_root_comment_exit_needs_revision" "2" "$_codex_contraction_apostrophes_not_mangled_root_comment_exit"
run_test "codex_contraction_apostrophes_not_mangled_root_comment_verdict" "VERDICT: ESCALATE — Codex terminal verdict matches neither an approved clean template nor the documented blocking markers" \
  "$(printf '%s\n' "$_codex_contraction_apostrophes_not_mangled_root_comment_output" | grep "^VERDICT:")"
rm -rf "$_codex_contraction_apostrophes_not_mangled_root_comment_mock_dir"
unset _codex_contraction_apostrophes_not_mangled_root_comment_mock_dir _codex_contraction_apostrophes_not_mangled_root_comment_output _codex_contraction_apostrophes_not_mangled_root_comment_exit

# codex_strip_quoted_spans' single-line sed substitutions can't strip a
# fenced Markdown code block (```...```): a fence marker line has no
# PAIRED backtick on the same line for the single-backtick-pair
# substitution to match, and the quoted content between the opening and
# closing fence spans arbitrarily many separate lines. A review quoting
# a clean signal inside a fenced block (e.g. "The documented output
# is:\n```text\nNo blocking issues found\n```\nThat output is
# inaccurate") was the fifth quoting style found unprotected, after
# straight-quote, backtick, blockquote, and single-quote (fresh evidence
# from PR #1490 finding 3793453010). codex_strip_quoted_spans now runs
# an awk pre-pass that strips entire fenced-code-block regions before
# the existing single-line substitutions.
_codex_fenced_code_block_phrase_not_approved_root_comment_mock_dir="$(mktemp -d)"
cat > "$_codex_fenced_code_block_phrase_not_approved_root_comment_mock_dir/gh" <<'CODEX_FENCED_CODE_BLOCK_PHRASE_NOT_APPROVED_ROOT_COMMENT_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'facade02551234567890\n'; exit 0 ;;
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
    jq -nc '[{id:309,created_at:"2026-01-01T00:00:01Z",user:{login:"chatgpt-codex-connector[bot]"},body:("The documented output is:\n```text\nNo blocking issues found\n```\nThat output is inaccurate.\n\n**Reviewed commit:** `facade02551`")}]'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_FENCED_CODE_BLOCK_PHRASE_NOT_APPROVED_ROOT_COMMENT_GH
chmod +x "$_codex_fenced_code_block_phrase_not_approved_root_comment_mock_dir/gh"

_codex_fenced_code_block_phrase_not_approved_root_comment_output=""
_codex_fenced_code_block_phrase_not_approved_root_comment_exit=0
PATH="$_codex_fenced_code_block_phrase_not_approved_root_comment_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_fenced_code_block_phrase_not_approved_root_comment_mock_dir/output.txt" 2>&1 || _codex_fenced_code_block_phrase_not_approved_root_comment_exit=$?
_codex_fenced_code_block_phrase_not_approved_root_comment_output="$(cat "$_codex_fenced_code_block_phrase_not_approved_root_comment_mock_dir/output.txt")"
run_test "codex_fenced_code_block_phrase_not_approved_root_comment_exit_needs_revision" "2" "$_codex_fenced_code_block_phrase_not_approved_root_comment_exit"
run_test "codex_fenced_code_block_phrase_not_approved_root_comment_verdict" "VERDICT: ESCALATE — Codex terminal verdict matches neither an approved clean template nor the documented blocking markers" \
  "$(printf '%s\n' "$_codex_fenced_code_block_phrase_not_approved_root_comment_output" | grep "^VERDICT:")"
rm -rf "$_codex_fenced_code_block_phrase_not_approved_root_comment_mock_dir"
unset _codex_fenced_code_block_phrase_not_approved_root_comment_mock_dir _codex_fenced_code_block_phrase_not_approved_root_comment_output _codex_fenced_code_block_phrase_not_approved_root_comment_exit

# The original fence-stripping awk pass toggled its "inside fence" state
# on ANY line with 3+ backticks, with no regard for the LENGTH of the
# opening delimiter. GitHub-flavored Markdown's actual fence semantics
# require a delimiter of AT LEAST the opening fence's length to close it
# — a longer outer fence (e.g. four backticks) can safely quote content
# that itself contains a shorter (three-backtick) fence. The naive
# implementation incorrectly closed on the inner three-backtick
# delimiter, re-exposing the rest of the outer-fenced content —
# including a quoted clean phrase — to classification (fresh evidence
# from PR #1490 finding 3793497787, a followup to 3793453010).
_codex_nested_fence_length_phrase_not_approved_root_comment_mock_dir="$(mktemp -d)"
cat > "$_codex_nested_fence_length_phrase_not_approved_root_comment_mock_dir/gh" <<'CODEX_NESTED_FENCE_LENGTH_PHRASE_NOT_APPROVED_ROOT_COMMENT_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'facade02661234567890\n'; exit 0 ;;
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
    jq -nc '[{id:311,created_at:"2026-01-01T00:00:01Z",user:{login:"chatgpt-codex-connector[bot]"},body:("Response was:\n````\nHere is an example:\n```\nNo blocking issues found\n```\nThat quoted output is inaccurate.\n````\nAfter the fence.\n\n**Reviewed commit:** `facade02661`")}]'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_NESTED_FENCE_LENGTH_PHRASE_NOT_APPROVED_ROOT_COMMENT_GH
chmod +x "$_codex_nested_fence_length_phrase_not_approved_root_comment_mock_dir/gh"

_codex_nested_fence_length_phrase_not_approved_root_comment_output=""
_codex_nested_fence_length_phrase_not_approved_root_comment_exit=0
PATH="$_codex_nested_fence_length_phrase_not_approved_root_comment_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_nested_fence_length_phrase_not_approved_root_comment_mock_dir/output.txt" 2>&1 || _codex_nested_fence_length_phrase_not_approved_root_comment_exit=$?
_codex_nested_fence_length_phrase_not_approved_root_comment_output="$(cat "$_codex_nested_fence_length_phrase_not_approved_root_comment_mock_dir/output.txt")"
run_test "codex_nested_fence_length_phrase_not_approved_root_comment_exit_needs_revision" "2" "$_codex_nested_fence_length_phrase_not_approved_root_comment_exit"
run_test "codex_nested_fence_length_phrase_not_approved_root_comment_verdict" "VERDICT: ESCALATE — Codex terminal verdict matches neither an approved clean template nor the documented blocking markers" \
  "$(printf '%s\n' "$_codex_nested_fence_length_phrase_not_approved_root_comment_output" | grep "^VERDICT:")"
rm -rf "$_codex_nested_fence_length_phrase_not_approved_root_comment_mock_dir"
unset _codex_nested_fence_length_phrase_not_approved_root_comment_mock_dir _codex_nested_fence_length_phrase_not_approved_root_comment_output _codex_nested_fence_length_phrase_not_approved_root_comment_exit

# The delimiter-length fix above checked LENGTH but not the GFM rule that
# a closing fence must be followed by nothing but optional whitespace: a
# line like ```` ```not-a-close ```` is, per GFM, a NEW opening fence with
# an info string, not a close, but a length-only check treated it as
# closing regardless — re-exposing everything after it, including a
# quoted clean phrase, to classification (fresh evidence from PR #1490
# finding following 3793497787/3793453010). This completes GFM's fence
# spec (open, length, close-only-whitespace) — the awk pass now requires
# nothing but whitespace after a would-be closing delimiter.
_codex_fence_close_requires_whitespace_only_root_comment_mock_dir="$(mktemp -d)"
cat > "$_codex_fence_close_requires_whitespace_only_root_comment_mock_dir/gh" <<'CODEX_FENCE_CLOSE_REQUIRES_WHITESPACE_ONLY_ROOT_COMMENT_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'facade02771234567890\n'; exit 0 ;;
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
    jq -nc '[{id:313,created_at:"2026-01-01T00:00:01Z",user:{login:"chatgpt-codex-connector[bot]"},body:("Response was:\n```text\nsome intro\n```not-a-close\nNo blocking issues found\n```\nThat quoted output is inaccurate.\n\n**Reviewed commit:** `facade02771`")}]'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_FENCE_CLOSE_REQUIRES_WHITESPACE_ONLY_ROOT_COMMENT_GH
chmod +x "$_codex_fence_close_requires_whitespace_only_root_comment_mock_dir/gh"

_codex_fence_close_requires_whitespace_only_root_comment_output=""
_codex_fence_close_requires_whitespace_only_root_comment_exit=0
PATH="$_codex_fence_close_requires_whitespace_only_root_comment_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_fence_close_requires_whitespace_only_root_comment_mock_dir/output.txt" 2>&1 || _codex_fence_close_requires_whitespace_only_root_comment_exit=$?
_codex_fence_close_requires_whitespace_only_root_comment_output="$(cat "$_codex_fence_close_requires_whitespace_only_root_comment_mock_dir/output.txt")"
run_test "codex_fence_close_requires_whitespace_only_root_comment_exit_needs_revision" "2" "$_codex_fence_close_requires_whitespace_only_root_comment_exit"
run_test "codex_fence_close_requires_whitespace_only_root_comment_verdict" "VERDICT: ESCALATE — Codex terminal verdict matches neither an approved clean template nor the documented blocking markers" \
  "$(printf '%s\n' "$_codex_fence_close_requires_whitespace_only_root_comment_output" | grep "^VERDICT:")"
rm -rf "$_codex_fence_close_requires_whitespace_only_root_comment_mock_dir"
unset _codex_fence_close_requires_whitespace_only_root_comment_mock_dir _codex_fence_close_requires_whitespace_only_root_comment_output _codex_fence_close_requires_whitespace_only_root_comment_exit

# Four consecutive rounds of precisely re-implementing GFM's fenced-code-
# block semantics (detect, length, close-only-whitespace) still missed
# GFM's entirely separate TILDE-delimited fence syntax (~~~...~~~), which
# a backtick-only implementation never recognized at all, so a quoted
# clean phrase inside a tilde fence stayed fully exposed to classification
# (fresh evidence from PR #1490 finding 3795661290). Per the project's
# explicit direction after this fourth round, codex_strip_quoted_spans no
# longer attempts precise fence parsing at all: codex_response_is_approved
# now treats the mere PRESENCE of a fence-opener marker (3+ consecutive
# backticks OR tildes) anywhere in the response as disqualifying for a
# clean verdict, closing this whole class of bug in one step rather than
# chasing the next undiscovered fence-syntax edge case.
_codex_tilde_fence_phrase_not_approved_root_comment_mock_dir="$(mktemp -d)"
cat > "$_codex_tilde_fence_phrase_not_approved_root_comment_mock_dir/gh" <<'CODEX_TILDE_FENCE_PHRASE_NOT_APPROVED_ROOT_COMMENT_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'facade02881234567890\n'; exit 0 ;;
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
    jq -nc '[{id:315,created_at:"2026-01-01T00:00:01Z",user:{login:"chatgpt-codex-connector[bot]"},body:("Response was:\n~~~text\nNo blocking issues found\n~~~\nThat quoted output is inaccurate.\n\n**Reviewed commit:** `facade02881`")}]'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_TILDE_FENCE_PHRASE_NOT_APPROVED_ROOT_COMMENT_GH
chmod +x "$_codex_tilde_fence_phrase_not_approved_root_comment_mock_dir/gh"

_codex_tilde_fence_phrase_not_approved_root_comment_output=""
_codex_tilde_fence_phrase_not_approved_root_comment_exit=0
PATH="$_codex_tilde_fence_phrase_not_approved_root_comment_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_tilde_fence_phrase_not_approved_root_comment_mock_dir/output.txt" 2>&1 || _codex_tilde_fence_phrase_not_approved_root_comment_exit=$?
_codex_tilde_fence_phrase_not_approved_root_comment_output="$(cat "$_codex_tilde_fence_phrase_not_approved_root_comment_mock_dir/output.txt")"
run_test "codex_tilde_fence_phrase_not_approved_root_comment_exit_needs_revision" "2" "$_codex_tilde_fence_phrase_not_approved_root_comment_exit"
run_test "codex_tilde_fence_phrase_not_approved_root_comment_verdict" "VERDICT: ESCALATE — Codex terminal verdict matches neither an approved clean template nor the documented blocking markers" \
  "$(printf '%s\n' "$_codex_tilde_fence_phrase_not_approved_root_comment_output" | grep "^VERDICT:")"
rm -rf "$_codex_tilde_fence_phrase_not_approved_root_comment_mock_dir"
unset _codex_tilde_fence_phrase_not_approved_root_comment_mock_dir _codex_tilde_fence_phrase_not_approved_root_comment_output _codex_tilde_fence_phrase_not_approved_root_comment_exit

# Positive control for the new fence-marker bail-out above: a single
# INLINE backtick PAIR on one line (e.g. referencing a filename), which is
# NOT a 3+-backtick fence marker, must still classify a genuinely clean
# review as APPROVED. Inline code references are extremely common in
# legitimate review comments and must not be swept up by the new
# conservative fence heuristic, which is deliberately scoped to
# multi-backtick/tilde FENCE markers only.
#
# Retargeted and renamed for issue #1491's conservative-verdict-classifier
# redesign: this body does not reproduce CODEX_APPROVED_TEMPLATES' whole-
# body exact template, so it now correctly safe-fails to NEEDS_REVISION.
# is_approved no longer calls codex_response_has_fence_marker at all
# (Decision 1), so this scenario no longer has a live approval-path
# mechanism to regression-test for inline-backtick-pair false rejection;
# codex_response_has_fence_marker itself is unchanged and still used by
# codex_response_is_usage_limit and codex_response_is_environment_error.
# Renamed from "...stays_approved_..." per the plan's naming standing
# rule.
_codex_inline_backtick_pair_safe_fails_root_comment_mock_dir="$(mktemp -d)"
cat > "$_codex_inline_backtick_pair_safe_fails_root_comment_mock_dir/gh" <<'CODEX_INLINE_BACKTICK_PAIR_SAFE_FAILS_ROOT_COMMENT_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'facade02991234567890\n'; exit 0 ;;
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
    printf '[{"id":317,"created_at":"2026-01-01T00:00:01Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"The fix looks good. See `foo.py:42` for a minor nit.\\n\\n**Reviewed commit:** `facade02991`"}]\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_INLINE_BACKTICK_PAIR_SAFE_FAILS_ROOT_COMMENT_GH
chmod +x "$_codex_inline_backtick_pair_safe_fails_root_comment_mock_dir/gh"

_codex_inline_backtick_pair_safe_fails_root_comment_output=""
_codex_inline_backtick_pair_safe_fails_root_comment_exit=0
PATH="$_codex_inline_backtick_pair_safe_fails_root_comment_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_inline_backtick_pair_safe_fails_root_comment_mock_dir/output.txt" 2>&1 || _codex_inline_backtick_pair_safe_fails_root_comment_exit=$?
_codex_inline_backtick_pair_safe_fails_root_comment_output="$(cat "$_codex_inline_backtick_pair_safe_fails_root_comment_mock_dir/output.txt")"
run_test "codex_inline_backtick_pair_safe_fails_root_comment_exit_needs_revision" "2" "$_codex_inline_backtick_pair_safe_fails_root_comment_exit"
run_test "codex_inline_backtick_pair_safe_fails_root_comment_verdict" "VERDICT: ESCALATE — Codex terminal verdict matches neither an approved clean template nor the documented blocking markers" \
  "$(printf '%s\n' "$_codex_inline_backtick_pair_safe_fails_root_comment_output" | grep "^VERDICT:")"
rm -rf "$_codex_inline_backtick_pair_safe_fails_root_comment_mock_dir"
unset _codex_inline_backtick_pair_safe_fails_root_comment_mock_dir _codex_inline_backtick_pair_safe_fails_root_comment_output _codex_inline_backtick_pair_safe_fails_root_comment_exit

# The fence-marker guard was added to codex_response_is_approved only,
# but codex_response_is_usage_limit's own callers (the 4 top-level
# verdict-parsing elif chains) were left unguarded — so a clean SHA-
# pinned review that quotes a REAL quota notice inside a fenced example
# (e.g. "No blocking issues found" followed by a ~~~ block containing
# "You have reached your Codex usage limits") still matched the
# usage-limit pattern on the unstripped fence content and returned
# UNAVAILABLE (exit 3) instead of the safe-fail NEEDS_REVISION a fenced
# response should produce (fresh evidence from PR #1490 finding
# 3796042503, a followup to 3795661290). The fence-marker guard is now
# embedded directly inside codex_response_has_fence_marker's callers
# (usage-limit, environment-error, blocking, approved) rather than at
# each call site, so every current and future caller benefits
# automatically — the exact lesson codex_response_is_blocking already
# taught for quote-stripping (finding 3793367887).
_codex_fenced_quota_example_not_unavailable_root_comment_mock_dir="$(mktemp -d)"
cat > "$_codex_fenced_quota_example_not_unavailable_root_comment_mock_dir/gh" <<'CODEX_FENCED_QUOTA_EXAMPLE_NOT_UNAVAILABLE_ROOT_COMMENT_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'facade03001234567890\n'; exit 0 ;;
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
    jq -nc '[{id:319,created_at:"2026-01-01T00:00:01Z",user:{login:"chatgpt-codex-connector[bot]"},body:("No blocking issues found\n~~~\nYou have reached your Codex usage limits.\n~~~\n\n**Reviewed commit:** `facade03001`")}]'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_FENCED_QUOTA_EXAMPLE_NOT_UNAVAILABLE_ROOT_COMMENT_GH
chmod +x "$_codex_fenced_quota_example_not_unavailable_root_comment_mock_dir/gh"

_codex_fenced_quota_example_not_unavailable_root_comment_output=""
_codex_fenced_quota_example_not_unavailable_root_comment_exit=0
PATH="$_codex_fenced_quota_example_not_unavailable_root_comment_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_fenced_quota_example_not_unavailable_root_comment_mock_dir/output.txt" 2>&1 || _codex_fenced_quota_example_not_unavailable_root_comment_exit=$?
_codex_fenced_quota_example_not_unavailable_root_comment_output="$(cat "$_codex_fenced_quota_example_not_unavailable_root_comment_mock_dir/output.txt")"
run_test "codex_fenced_quota_example_not_unavailable_root_comment_exit_needs_revision" "2" "$_codex_fenced_quota_example_not_unavailable_root_comment_exit"
run_test "codex_fenced_quota_example_not_unavailable_root_comment_verdict" "VERDICT: ESCALATE — Codex terminal verdict matches neither an approved clean template nor the documented blocking markers" \
  "$(printf '%s\n' "$_codex_fenced_quota_example_not_unavailable_root_comment_output" | grep "^VERDICT:")"
rm -rf "$_codex_fenced_quota_example_not_unavailable_root_comment_mock_dir"
unset _codex_fenced_quota_example_not_unavailable_root_comment_mock_dir _codex_fenced_quota_example_not_unavailable_root_comment_output _codex_fenced_quota_example_not_unavailable_root_comment_exit

# codex_response_priority ranked an ancillary environment-setup-error
# comment at the same "unrecognized format" tier (2) as a genuine but
# unrecognized-format submitted review, instead of at the lower
# availability tier (1) shared with usage-limit notices. Tied at the same
# timestamp, the setup-error comment then won the tie-break and replaced
# the review's safe-fail NEEDS_REVISION with an UNAVAILABLE-style
# codex-github-environment-missing verdict, silently discarding a review
# that could have been a real rejection (fresh evidence from PR #1490
# finding 3789722821). Fixture: an ancillary (non-SHA-pinned) environment-
# setup-error comment and an unrecognized-format submitted review, both
# timestamped identically.
_codex_env_error_vs_unrecognized_review_tie_mock_dir="$(mktemp -d)"
cat > "$_codex_env_error_vs_unrecognized_review_tie_mock_dir/gh" <<'CODEX_ENV_ERROR_VS_UNRECOGNIZED_REVIEW_TIE_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'facade004b1234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":254,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[{"submitted_at":"2026-01-01T00:00:01Z","commit_id":"facade004b1234567890","user":{"login":"chatgpt-codex-connector[bot]"},"body":"Reviewed the changes, nothing further to add at this time."}]\n'
    exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"id":255,"created_at":"2026-01-01T00:00:01Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"To use Codex here, create an environment for this repo."}]\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_ENV_ERROR_VS_UNRECOGNIZED_REVIEW_TIE_GH
chmod +x "$_codex_env_error_vs_unrecognized_review_tie_mock_dir/gh"

_codex_env_error_vs_unrecognized_review_tie_output=""
_codex_env_error_vs_unrecognized_review_tie_exit=0
PATH="$_codex_env_error_vs_unrecognized_review_tie_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_env_error_vs_unrecognized_review_tie_mock_dir/output.txt" 2>&1 || _codex_env_error_vs_unrecognized_review_tie_exit=$?
_codex_env_error_vs_unrecognized_review_tie_output="$(cat "$_codex_env_error_vs_unrecognized_review_tie_mock_dir/output.txt")"
run_test "codex_env_error_vs_unrecognized_review_tie_exit_needs_revision" "2" "$_codex_env_error_vs_unrecognized_review_tie_exit"
run_test "codex_env_error_vs_unrecognized_review_tie_verdict" "VERDICT: ESCALATE — Codex terminal verdict matches neither an approved clean template nor the documented blocking markers" \
  "$(printf '%s\n' "$_codex_env_error_vs_unrecognized_review_tie_output" | grep "^VERDICT:")"
run_test "codex_env_error_vs_unrecognized_review_tie_reason_not_env_missing" "" \
  "$(printf '%s\n' "$_codex_env_error_vs_unrecognized_review_tie_output" | grep "^REASON=codex-github-environment-missing")"
rm -rf "$_codex_env_error_vs_unrecognized_review_tie_mock_dir"
unset _codex_env_error_vs_unrecognized_review_tie_mock_dir _codex_env_error_vs_unrecognized_review_tie_output _codex_env_error_vs_unrecognized_review_tie_exit

_codex_review_query_failure_mock_dir="$(mktemp -d)"
cat > "$_codex_review_query_failure_mock_dir/gh" <<'CODEX_REVIEW_QUERY_FAILURE_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'abcreviewfail1234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":115,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf 'reviews unavailable\n' >&2
    exit 1 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_REVIEW_QUERY_FAILURE_GH
chmod +x "$_codex_review_query_failure_mock_dir/gh"

_codex_review_query_failure_output=""
_codex_review_query_failure_exit=0
PATH="$_codex_review_query_failure_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_review_query_failure_mock_dir/output.txt" 2>&1 || _codex_review_query_failure_exit=$?
_codex_review_query_failure_output="$(cat "$_codex_review_query_failure_mock_dir/output.txt")"
run_test "codex_review_query_failure_exit_unavailable" "2" "$_codex_review_query_failure_exit"
run_test "codex_review_query_failure_verdict" "VERDICT: TIMED_OUT — failed to fetch Codex PR reviews (treated as unavailable)" \
  "$(printf '%s\n' "$_codex_review_query_failure_output" | grep "^VERDICT:")"
rm -rf "$_codex_review_query_failure_mock_dir"
unset _codex_review_query_failure_mock_dir _codex_review_query_failure_output _codex_review_query_failure_exit

_codex_latest_review_mock_dir="$(mktemp -d)"
cat > "$_codex_latest_review_mock_dir/gh" <<'CODEX_LATEST_REVIEW_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'abclatestre1234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":111,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[{"submitted_at":"2026-01-01T00:00:01Z","commit_id":"abclatestre1234567890","user":{"login":"chatgpt-codex-connector[bot]"},"body":"Blocking issues: old finding."}]\n'
    jq -nc '[{submitted_at:"2026-01-01T00:00:02Z",commit_id:"abclatestre1234567890",user:{login:"chatgpt-codex-connector[bot]"},body:("Codex Review: Didn'\''t find any major issues. Swish! **Reviewed commit:** `eeeeeeeeee` <details> <summary>ℹ️ About Codex in GitHub</summary> <br/> [Your team has set up Codex to review pull requests in this repo](https://chatgpt.com/codex/cloud/settings/general). Reviews are triggered when you - Open a pull request for review - Mark a draft as ready - Comment \"@codex review\". If Codex has suggestions, it will comment; otherwise it will react with 👍. Codex can also answer questions or update the PR. Try commenting \"@codex address that feedback\". </details>")}]'
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
CODEX_LATEST_REVIEW_GH
chmod +x "$_codex_latest_review_mock_dir/gh"

_codex_latest_review_output=""
_codex_latest_review_exit=0
PATH="$_codex_latest_review_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_latest_review_mock_dir/output.txt" 2>&1 || _codex_latest_review_exit=$?
_codex_latest_review_output="$(cat "$_codex_latest_review_mock_dir/output.txt")"
run_test "codex_latest_current_review_exit_clean" "0" "$_codex_latest_review_exit"
run_test "codex_latest_current_review_approved" "VERDICT: APPROVED" \
  "$(printf '%s\n' "$_codex_latest_review_output" | grep "^VERDICT:")"
rm -rf "$_codex_latest_review_mock_dir"
unset _codex_latest_review_mock_dir _codex_latest_review_output _codex_latest_review_exit

_codex_stale_review_mock_dir="$(mktemp -d)"
cat > "$_codex_stale_review_mock_dir/gh" <<'CODEX_STALE_REVIEW_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'abcstale1234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":104,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[{"submitted_at":"2026-01-01T00:00:01Z","commit_id":"oldstale1234567890","user":{"login":"chatgpt-codex-connector[bot]"},"body":"No blocking issues found."}]\n'
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
CODEX_STALE_REVIEW_GH
chmod +x "$_codex_stale_review_mock_dir/gh"

_codex_stale_review_output=""
_codex_stale_review_exit=0
PATH="$_codex_stale_review_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_stale_review_mock_dir/output.txt" 2>&1 || _codex_stale_review_exit=$?
_codex_stale_review_output="$(cat "$_codex_stale_review_mock_dir/output.txt")"
run_test "codex_stale_review_exit_waiting" "4" "$_codex_stale_review_exit"
if printf '%s\n' "$_codex_stale_review_output" | grep -q "^VERDICT: APPROVED"; then
  _codex_stale_review_approved="yes"
else
  _codex_stale_review_approved="no"
fi
run_test "codex_stale_review_not_approved" "no" "$_codex_stale_review_approved"
rm -rf "$_codex_stale_review_mock_dir"
unset _codex_stale_review_mock_dir _codex_stale_review_output _codex_stale_review_exit _codex_stale_review_approved

_codex_stale_inline_mock_dir="$(mktemp -d)"
cat > "$_codex_stale_inline_mock_dir/gh" <<'CODEX_STALE_INLINE_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'abcinline1234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":112,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[{"created_at":"2026-01-01T00:00:01Z","commit_id":"oldinline1234567890","user":{"login":"chatgpt-codex-connector[bot]"},"body":"Blocking issue on old head."}]\n'
    exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_STALE_INLINE_GH
chmod +x "$_codex_stale_inline_mock_dir/gh"

_codex_stale_inline_output=""
_codex_stale_inline_exit=0
PATH="$_codex_stale_inline_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_stale_inline_mock_dir/output.txt" 2>&1 || _codex_stale_inline_exit=$?
_codex_stale_inline_output="$(cat "$_codex_stale_inline_mock_dir/output.txt")"
run_test "codex_stale_inline_exit_waiting" "4" "$_codex_stale_inline_exit"
if printf '%s\n' "$_codex_stale_inline_output" | grep -q "^VERDICT: NEEDS_REVISION"; then
  _codex_stale_inline_needs_revision="yes"
else
  _codex_stale_inline_needs_revision="no"
fi
run_test "codex_stale_inline_not_needs_revision" "no" "$_codex_stale_inline_needs_revision"
rm -rf "$_codex_stale_inline_mock_dir"
unset _codex_stale_inline_mock_dir _codex_stale_inline_output _codex_stale_inline_exit _codex_stale_inline_needs_revision

# #1789 T2.16 (plan D15, codex-github row): codex_inline_review_comment_count_since
# binds an inline review comment by original_commit_id. GitHub moves a review
# comment's commit_id to the newest head while the commented line is
# unchanged, so an older head's comment created after the trigger carries
# commit_id == the current head but original_commit_id == the older head; it
# is not counted and the companion does not return NEEDS_REVISION. A comment
# whose original_commit_id is the current head is counted.
_codex_drift_mock_dir="$(mktemp -d)"
cat > "$_codex_drift_mock_dir/gh" <<'CODEX_DRIFT_INLINE_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'abcd178900000000000000000000000000000001\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":113,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[{"created_at":"2026-01-01T00:00:01Z","commit_id":"abcd178900000000000000000000000000000001","original_commit_id":"%s","user":{"login":"chatgpt-codex-connector[bot]"},"body":"Blocking issue."}]\n' "$CODEX_DRIFT_ORIGINAL"
    exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_DRIFT_INLINE_GH
chmod +x "$_codex_drift_mock_dir/gh"
for _codex_drift_case in drifted bound; do
  if [ "$_codex_drift_case" = "drifted" ]; then
    _codex_drift_original="abcd178900000000000000000000000000000002"
  else
    _codex_drift_original="abcd178900000000000000000000000000000001"
  fi
  _codex_drift_exit=0
  CODEX_DRIFT_ORIGINAL="$_codex_drift_original" PATH="$_codex_drift_mock_dir:$PATH" \
    "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
    42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
    >"$_codex_drift_mock_dir/output.txt" 2>&1 || _codex_drift_exit=$?
  _codex_drift_verdict="$(grep -c '^VERDICT: NEEDS_REVISION' "$_codex_drift_mock_dir/output.txt" || true)"
  if [ "$_codex_drift_case" = "drifted" ]; then
    run_test "1789_T2.16_codex_drifted_inline_comment_not_counted_exit" "4" "$_codex_drift_exit"
    run_test "1789_T2.16_codex_drifted_inline_comment_not_needs_revision" "0" "$_codex_drift_verdict"
  else
    run_test "1789_T2.16_codex_bound_inline_comment_counted_needs_revision" "1|1" "${_codex_drift_verdict}|${_codex_drift_exit}"
  fi
done
rm -rf "$_codex_drift_mock_dir"
unset _codex_drift_mock_dir _codex_drift_case _codex_drift_original _codex_drift_exit _codex_drift_verdict

_codex_head_changed_mock_dir="$(mktemp -d)"
printf '0\n' > "$_codex_head_changed_mock_dir/head_calls"
cat > "$_codex_head_changed_mock_dir/gh" <<'CODEX_HEAD_CHANGED_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    calls_file="$(dirname "$0")/head_calls"
    calls="$(cat "$calls_file")"
    calls=$((calls + 1))
    printf '%s\n' "$calls" > "$calls_file"
    if [ "$calls" -eq 1 ]; then
      printf 'abcheadold1234567890\n'
    else
      printf 'abcheadnew1234567890\n'
    fi
    exit 0 ;;
  *"--method POST"*)
    printf '{"id":107,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[{"submitted_at":"2026-01-01T00:00:01Z","commit_id":"abcheadold1234567890","user":{"login":"chatgpt-codex-connector[bot]"},"body":"No blocking issues found."}]\n'
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
CODEX_HEAD_CHANGED_GH
chmod +x "$_codex_head_changed_mock_dir/gh"

_codex_head_changed_output=""
_codex_head_changed_exit=0
PATH="$_codex_head_changed_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_head_changed_mock_dir/output.txt" 2>&1 || _codex_head_changed_exit=$?
_codex_head_changed_output="$(cat "$_codex_head_changed_mock_dir/output.txt")"
run_test "codex_head_changed_exit_unavailable" "2" "$_codex_head_changed_exit"
run_test "codex_head_changed_reason" "REASON=codex-github-head-changed" \
  "$(printf '%s\n' "$_codex_head_changed_output" | grep "^REASON=")"
rm -rf "$_codex_head_changed_mock_dir"
unset _codex_head_changed_mock_dir _codex_head_changed_output _codex_head_changed_exit

_codex_environment_with_review_mock_dir="$(mktemp -d)"
cat > "$_codex_environment_with_review_mock_dir/gh" <<'CODEX_ENVIRONMENT_WITH_REVIEW_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'abcenvok1234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":108,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    jq -nc '[{submitted_at:"2026-01-01T00:00:02Z",commit_id:"abcenvok1234567890",user:{login:"chatgpt-codex-connector[bot]"},body:("Codex Review: Didn'\''t find any major issues. Swish! **Reviewed commit:** `ffffffffff` <details> <summary>ℹ️ About Codex in GitHub</summary> <br/> [Your team has set up Codex to review pull requests in this repo](https://chatgpt.com/codex/cloud/settings/general). Reviews are triggered when you - Open a pull request for review - Mark a draft as ready - Comment \"@codex review\". If Codex has suggestions, it will comment; otherwise it will react with 👍. Codex can also answer questions or update the PR. Try commenting \"@codex address that feedback\". </details>")}]'
    exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"id":207,"created_at":"2026-01-01T00:00:01Z","user":{"login":"chatgpt-codex-connector"},"body":"To use Codex here, create an environment for this repo."}]\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_ENVIRONMENT_WITH_REVIEW_GH
chmod +x "$_codex_environment_with_review_mock_dir/gh"

_codex_environment_with_review_output=""
_codex_environment_with_review_exit=0
PATH="$_codex_environment_with_review_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_environment_with_review_mock_dir/output.txt" 2>&1 || _codex_environment_with_review_exit=$?
_codex_environment_with_review_output="$(cat "$_codex_environment_with_review_mock_dir/output.txt")"
run_test "codex_environment_with_current_review_exit_clean" "0" "$_codex_environment_with_review_exit"
run_test "codex_environment_with_current_review_approved" "VERDICT: APPROVED" \
  "$(printf '%s\n' "$_codex_environment_with_review_output" | grep "^VERDICT:")"
rm -rf "$_codex_environment_with_review_mock_dir"
unset _codex_environment_with_review_mock_dir _codex_environment_with_review_output _codex_environment_with_review_exit

_codex_environment_then_clean_comment_mock_dir="$(mktemp -d)"
cat > "$_codex_environment_then_clean_comment_mock_dir/gh" <<'CODEX_ENVIRONMENT_THEN_CLEAN_COMMENT_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'abcenvcomment1234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":109,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"id":208,"created_at":"2026-01-01T00:00:01Z","user":{"login":"chatgpt-codex-connector"},"body":"To use Codex here, create an environment for this repo."}]\n'
    printf '[{"id":209,"created_at":"2026-01-01T00:00:02Z","user":{"login":"chatgpt-codex-connector"},"body":"No blocking issues found."}]\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_ENVIRONMENT_THEN_CLEAN_COMMENT_GH
chmod +x "$_codex_environment_then_clean_comment_mock_dir/gh"

_codex_environment_then_clean_comment_output=""
_codex_environment_then_clean_comment_exit=0
PATH="$_codex_environment_then_clean_comment_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_environment_then_clean_comment_mock_dir/output.txt" 2>&1 || _codex_environment_then_clean_comment_exit=$?
_codex_environment_then_clean_comment_output="$(cat "$_codex_environment_then_clean_comment_mock_dir/output.txt")"
run_test "codex_environment_then_clean_comment_exit_unavailable" "2" "$_codex_environment_then_clean_comment_exit"
if printf '%s\n' "$_codex_environment_then_clean_comment_output" | grep -q "^VERDICT: APPROVED"; then
  _codex_environment_then_clean_comment_approved="yes"
else
  _codex_environment_then_clean_comment_approved="no"
fi
run_test "codex_environment_then_clean_comment_not_approved" "no" "$_codex_environment_then_clean_comment_approved"
rm -rf "$_codex_environment_then_clean_comment_mock_dir"
unset _codex_environment_then_clean_comment_mock_dir _codex_environment_then_clean_comment_output _codex_environment_then_clean_comment_exit _codex_environment_then_clean_comment_approved

_codex_cloud_environment_finding_mock_dir="$(mktemp -d)"
cat > "$_codex_cloud_environment_finding_mock_dir/gh" <<'CODEX_CLOUD_ENVIRONMENT_FINDING_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'abccloudfinding1234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":113,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[{"submitted_at":"2026-01-01T00:00:01Z","commit_id":"abccloudfinding1234567890","user":{"login":"chatgpt-codex-connector[bot]"},"body":"Blocking issues: the Codex cloud environment is missing required secrets."}]\n'
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
CODEX_CLOUD_ENVIRONMENT_FINDING_GH
chmod +x "$_codex_cloud_environment_finding_mock_dir/gh"

_codex_cloud_environment_finding_output=""
_codex_cloud_environment_finding_exit=0
PATH="$_codex_cloud_environment_finding_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_cloud_environment_finding_mock_dir/output.txt" 2>&1 || _codex_cloud_environment_finding_exit=$?
_codex_cloud_environment_finding_output="$(cat "$_codex_cloud_environment_finding_mock_dir/output.txt")"
run_test "codex_cloud_environment_finding_exit_needs_revision" "2" "$_codex_cloud_environment_finding_exit"
run_test "codex_cloud_environment_finding_verdict" "VERDICT: ESCALATE — Codex finding has no stable review-thread identifier or no identifiable matching review-thread conversation" \
  "$(printf '%s\n' "$_codex_cloud_environment_finding_output" | grep "^VERDICT:")"
rm -rf "$_codex_cloud_environment_finding_mock_dir"
unset _codex_cloud_environment_finding_mock_dir _codex_cloud_environment_finding_output _codex_cloud_environment_finding_exit

_codex_environment_phrase_finding_mock_dir="$(mktemp -d)"
cat > "$_codex_environment_phrase_finding_mock_dir/gh" <<'CODEX_ENVIRONMENT_PHRASE_FINDING_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'abcenvphrase1234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":114,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[{"submitted_at":"2026-01-01T00:00:01Z","commit_id":"abcenvphrase1234567890","user":{"login":"chatgpt-codex-connector[bot]"},"body":"Must fix docs that tell users to create an environment for this repo."}]\n'
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
CODEX_ENVIRONMENT_PHRASE_FINDING_GH
chmod +x "$_codex_environment_phrase_finding_mock_dir/gh"

_codex_environment_phrase_finding_output=""
_codex_environment_phrase_finding_exit=0
PATH="$_codex_environment_phrase_finding_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_environment_phrase_finding_mock_dir/output.txt" 2>&1 || _codex_environment_phrase_finding_exit=$?
_codex_environment_phrase_finding_output="$(cat "$_codex_environment_phrase_finding_mock_dir/output.txt")"
run_test "codex_environment_phrase_finding_exit_needs_revision" "2" "$_codex_environment_phrase_finding_exit"
run_test "codex_environment_phrase_finding_verdict" "VERDICT: ESCALATE — Codex finding has no stable review-thread identifier or no identifiable matching review-thread conversation" \
  "$(printf '%s\n' "$_codex_environment_phrase_finding_output" | grep "^VERDICT:")"
rm -rf "$_codex_environment_phrase_finding_mock_dir"
unset _codex_environment_phrase_finding_mock_dir _codex_environment_phrase_finding_output _codex_environment_phrase_finding_exit

_codex_quoted_environment_finding_mock_dir="$(mktemp -d)"
cat > "$_codex_quoted_environment_finding_mock_dir/gh" <<'CODEX_QUOTED_ENVIRONMENT_FINDING_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'abcenvquote1234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":116,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[{"submitted_at":"2026-01-01T00:00:01Z","commit_id":"abcenvquote1234567890","user":{"login":"chatgpt-codex-connector[bot]"},"body":"Blocking issues: docs must not claim: To use Codex here, create an environment for this repo."}]\n'
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
CODEX_QUOTED_ENVIRONMENT_FINDING_GH
chmod +x "$_codex_quoted_environment_finding_mock_dir/gh"

_codex_quoted_environment_finding_output=""
_codex_quoted_environment_finding_exit=0
PATH="$_codex_quoted_environment_finding_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_quoted_environment_finding_mock_dir/output.txt" 2>&1 || _codex_quoted_environment_finding_exit=$?
_codex_quoted_environment_finding_output="$(cat "$_codex_quoted_environment_finding_mock_dir/output.txt")"
run_test "codex_quoted_environment_finding_exit_needs_revision" "2" "$_codex_quoted_environment_finding_exit"
run_test "codex_quoted_environment_finding_verdict" "VERDICT: ESCALATE — Codex finding has no stable review-thread identifier or no identifiable matching review-thread conversation" \
  "$(printf '%s\n' "$_codex_quoted_environment_finding_output" | grep "^VERDICT:")"
rm -rf "$_codex_quoted_environment_finding_mock_dir"
unset _codex_quoted_environment_finding_mock_dir _codex_quoted_environment_finding_output _codex_quoted_environment_finding_exit

_codex_final_ack_clean_comment_mock_dir="$(mktemp -d)"
printf '0\n' > "$_codex_final_ack_clean_comment_mock_dir/comment_calls"
cat > "$_codex_final_ack_clean_comment_mock_dir/gh" <<'CODEX_FINAL_ACK_CLEAN_COMMENT_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'abcfinalcomment1234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":110,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    calls_file="$(dirname "$0")/comment_calls"
    calls="$(cat "$calls_file")"
    calls=$((calls + 1))
    printf '%s\n' "$calls" > "$calls_file"
    if [ "$calls" -lt 3 ]; then
      printf '[{"id":210,"created_at":"2026-01-01T00:00:01Z","user":{"login":"chatgpt-codex-connector"},"body":"If Codex has suggestions, it will comment; otherwise it will react with thumbs up."}]\n'
    else
      printf '[{"id":210,"created_at":"2026-01-01T00:00:01Z","user":{"login":"chatgpt-codex-connector"},"body":"If Codex has suggestions, it will comment; otherwise it will react with thumbs up."},{"id":211,"created_at":"2026-01-01T00:00:02Z","user":{"login":"chatgpt-codex-connector"},"body":"No blocking issues found."}]\n'
    fi
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_FINAL_ACK_CLEAN_COMMENT_GH
chmod +x "$_codex_final_ack_clean_comment_mock_dir/gh"

_codex_final_ack_clean_comment_output=""
_codex_final_ack_clean_comment_exit=0
PATH="$_codex_final_ack_clean_comment_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_final_ack_clean_comment_mock_dir/output.txt" 2>&1 || _codex_final_ack_clean_comment_exit=$?
_codex_final_ack_clean_comment_output="$(cat "$_codex_final_ack_clean_comment_mock_dir/output.txt")"
run_test "codex_final_ack_clean_comment_exit_waiting" "4" "$_codex_final_ack_clean_comment_exit"
if printf '%s\n' "$_codex_final_ack_clean_comment_output" | grep -q "^VERDICT: APPROVED"; then
  _codex_final_ack_clean_comment_approved="yes"
else
  _codex_final_ack_clean_comment_approved="no"
fi
run_test "codex_final_ack_clean_comment_not_approved" "no" "$_codex_final_ack_clean_comment_approved"
rm -rf "$_codex_final_ack_clean_comment_mock_dir"
unset _codex_final_ack_clean_comment_mock_dir _codex_final_ack_clean_comment_output _codex_final_ack_clean_comment_exit _codex_final_ack_clean_comment_approved

_codex_environment_mock_dir="$(mktemp -d)"
cat > "$_codex_environment_mock_dir/gh" <<'CODEX_ENVIRONMENT_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'abcenv1234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":105,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"id":205,"created_at":"2026-01-01T00:00:01Z","user":{"login":"chatgpt-codex-connector"},"body":"To use Codex here, create an environment for this repo."}]\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_ENVIRONMENT_GH
chmod +x "$_codex_environment_mock_dir/gh"

_codex_environment_output=""
_codex_environment_exit=0
PATH="$_codex_environment_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_environment_mock_dir/output.txt" 2>&1 || _codex_environment_exit=$?
_codex_environment_output="$(cat "$_codex_environment_mock_dir/output.txt")"
run_test "codex_environment_missing_exit_unavailable" "2" "$_codex_environment_exit"
run_test "codex_environment_missing_reason" "REASON=codex-github-environment-missing" \
  "$(printf '%s\n' "$_codex_environment_output" | grep "^REASON=")"
rm -rf "$_codex_environment_mock_dir"
unset _codex_environment_mock_dir _codex_environment_output _codex_environment_exit

_codex_same_second_root_comment_mock_dir="$(mktemp -d)"
cat > "$_codex_same_second_root_comment_mock_dir/gh" <<'CODEX_SAME_SECOND_ROOT_COMMENT_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'abcsamesecond1234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":120,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"id":119,"created_at":"2026-01-01T00:00:00Z","user":{"login":"chatgpt-codex-connector"},"body":"Older same-second setup response."}]\n'
    printf '[{"id":121,"created_at":"2026-01-01T00:00:00Z","user":{"login":"chatgpt-codex-connector"},"body":"To use Codex here, create an environment for this repo."}]\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_SAME_SECOND_ROOT_COMMENT_GH
chmod +x "$_codex_same_second_root_comment_mock_dir/gh"

_codex_same_second_root_comment_output=""
_codex_same_second_root_comment_exit=0
PATH="$_codex_same_second_root_comment_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_same_second_root_comment_mock_dir/output.txt" 2>&1 || _codex_same_second_root_comment_exit=$?
_codex_same_second_root_comment_output="$(cat "$_codex_same_second_root_comment_mock_dir/output.txt")"
run_test "codex_same_second_root_comment_exit_unavailable" "2" "$_codex_same_second_root_comment_exit"
run_test "codex_same_second_root_comment_reason" "REASON=codex-github-environment-missing" \
  "$(printf '%s\n' "$_codex_same_second_root_comment_output" | grep "^REASON=")"
rm -rf "$_codex_same_second_root_comment_mock_dir"
unset _codex_same_second_root_comment_mock_dir _codex_same_second_root_comment_output _codex_same_second_root_comment_exit

# ---------------------------------------------------------------------------
# New scenarios for issue #1491's conservative-verdict-classifier
# implementation plan — Parser-risk addendum edge cases E1-E24 (E4 and E14
# already covered: E4 by the two Group APPROVED template-anchored members'
# distinct SHAs; E14 by the pre-existing codex_unapproved_prefix_root_comment
# above) — plus the four Decision-6 verdict-site near-miss scenarios.
# ---------------------------------------------------------------------------
# Parser-risk addendum E1 (issue #1491's implementation plan): the real
# captured PR #1489 root comment, in full, including its real <details>
# footer, verbatim. The anchor case for the classifier's primary
# real-response template.
_codex_e1_real_pr1489_capture_approved_mock_dir="$(mktemp -d)"
cat > "$_codex_e1_real_pr1489_capture_approved_mock_dir/gh" <<'CODEX_E1_REAL_PR1489_CAPTURE_APPROVED_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf '87aaefceff1234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":400,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    jq -nc '[{id:401,created_at:"2026-01-01T00:00:01Z",user:{login:"chatgpt-codex-connector[bot]"},body:("Codex Review: Didn'\''t find any major issues. Swish!

**Reviewed commit:** `87aaefceff`

<details> <summary>ℹ️ About Codex in GitHub</summary>
<br/>

[Your team has set up Codex to review pull requests in this repo](https://chatgpt.com/codex/cloud/settings/general). Reviews are triggered when you
- Open a pull request for review
- Mark a draft as ready
- Comment \"@codex review\".

If Codex has suggestions, it will comment; otherwise it will react with 👍.




Codex can also answer questions or update the PR. Try commenting \"@codex address that feedback\".
            
</details>
")}]'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_E1_REAL_PR1489_CAPTURE_APPROVED_GH
chmod +x "$_codex_e1_real_pr1489_capture_approved_mock_dir/gh"

_codex_e1_real_pr1489_capture_approved_output=""
_codex_e1_real_pr1489_capture_approved_exit=0
PATH="$_codex_e1_real_pr1489_capture_approved_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_e1_real_pr1489_capture_approved_mock_dir/output.txt" 2>&1 || _codex_e1_real_pr1489_capture_approved_exit=$?
_codex_e1_real_pr1489_capture_approved_output="$(cat "$_codex_e1_real_pr1489_capture_approved_mock_dir/output.txt")"
run_test "codex_e1_real_pr1489_capture_approved_exit_clean" "0" "$_codex_e1_real_pr1489_capture_approved_exit"
run_test "codex_e1_real_pr1489_capture_approved_verdict" "VERDICT: APPROVED" \
  "$(printf '%s\n' "$_codex_e1_real_pr1489_capture_approved_output" | grep "^VERDICT:")"
rm -rf "$_codex_e1_real_pr1489_capture_approved_mock_dir"
unset _codex_e1_real_pr1489_capture_approved_mock_dir _codex_e1_real_pr1489_capture_approved_output _codex_e1_real_pr1489_capture_approved_exit

# Parser-risk addendum E2 (issue #1491's implementation plan): a real
# captured PR #1490 review body, in full, verbatim. Confirms the generic
# review-submission wrapper — no clean-signal text — correctly never
# matches; verdict is driven by review `state`, not this function
# (Decision 3). Review-sourced: always terminal by construction.
_codex_e2_real_pr1490_review_not_approved_mock_dir="$(mktemp -d)"
cat > "$_codex_e2_real_pr1490_review_not_approved_mock_dir/gh" <<'CODEX_E2_REAL_PR1490_REVIEW_NOT_APPROVED_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'e2e2e2e2e2e2\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":401,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    jq -nc '[{submitted_at:"2026-01-01T00:00:01Z",commit_id:"e2e2e2e2e2e2",user:{login:"chatgpt-codex-connector[bot]"},state:"COMMENTED",body:("### 💡 Codex Review

Here are some automated review suggestions for this pull request.

**Reviewed commit:** `6b70f9b229`
    

<details> <summary>ℹ️ About Codex in GitHub</summary>
<br/>

[Your team has set up Codex to review pull requests in this repo](https://chatgpt.com/codex/cloud/settings/general). Reviews are triggered when you
- Open a pull request for review
- Mark a draft as ready
- Comment \"@codex review\".

If Codex has suggestions, it will comment; otherwise it will react with 👍.




Codex can also answer questions or update the PR. Try commenting \"@codex address that feedback\".
            
</details>")}]'
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
CODEX_E2_REAL_PR1490_REVIEW_NOT_APPROVED_GH
chmod +x "$_codex_e2_real_pr1490_review_not_approved_mock_dir/gh"

_codex_e2_real_pr1490_review_not_approved_output=""
_codex_e2_real_pr1490_review_not_approved_exit=0
PATH="$_codex_e2_real_pr1490_review_not_approved_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_e2_real_pr1490_review_not_approved_mock_dir/output.txt" 2>&1 || _codex_e2_real_pr1490_review_not_approved_exit=$?
_codex_e2_real_pr1490_review_not_approved_output="$(cat "$_codex_e2_real_pr1490_review_not_approved_mock_dir/output.txt")"
run_test "codex_e2_real_pr1490_review_not_approved_exit_needs_revision" "2" "$_codex_e2_real_pr1490_review_not_approved_exit"
run_test "codex_e2_real_pr1490_review_not_approved_verdict" "VERDICT: ESCALATE — Codex terminal verdict matches neither an approved clean template nor the documented blocking markers" \
  "$(printf '%s\n' "$_codex_e2_real_pr1490_review_not_approved_output" | grep "^VERDICT:")"
rm -rf "$_codex_e2_real_pr1490_review_not_approved_mock_dir"
unset _codex_e2_real_pr1490_review_not_approved_mock_dir _codex_e2_real_pr1490_review_not_approved_output _codex_e2_real_pr1490_review_not_approved_exit

# Parser-risk addendum E3 (issue #1491's implementation plan): the real
# template's opening sentence, Reviewed-commit marker, and complete real
# footer, but WITHOUT "Swish!". The template has no optional clauses —
# a response missing the evidenced flavor sentence does not reproduce it,
# however close it looks, including when the rest of the body (footer
# included) is otherwise exact.
_codex_e3_missing_swish_not_approved_mock_dir="$(mktemp -d)"
cat > "$_codex_e3_missing_swish_not_approved_mock_dir/gh" <<'CODEX_E3_MISSING_SWISH_NOT_APPROVED_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'e3e3e3e3e3e3\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":402,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    jq -nc '[{id:403,created_at:"2026-01-01T00:00:01Z",user:{login:"chatgpt-codex-connector[bot]"},body:("Codex Review: Didn'\''t find any major issues. **Reviewed commit:** `e3e3e3e3e3` <details> <summary>ℹ️ About Codex in GitHub</summary> <br/> [Your team has set up Codex to review pull requests in this repo](https://chatgpt.com/codex/cloud/settings/general). Reviews are triggered when you - Open a pull request for review - Mark a draft as ready - Comment \"@codex review\". If Codex has suggestions, it will comment; otherwise it will react with 👍. Codex can also answer questions or update the PR. Try commenting \"@codex address that feedback\". </details>")}]'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_E3_MISSING_SWISH_NOT_APPROVED_GH
chmod +x "$_codex_e3_missing_swish_not_approved_mock_dir/gh"

_codex_e3_missing_swish_not_approved_output=""
_codex_e3_missing_swish_not_approved_exit=0
PATH="$_codex_e3_missing_swish_not_approved_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_e3_missing_swish_not_approved_mock_dir/output.txt" 2>&1 || _codex_e3_missing_swish_not_approved_exit=$?
_codex_e3_missing_swish_not_approved_output="$(cat "$_codex_e3_missing_swish_not_approved_mock_dir/output.txt")"
run_test "codex_e3_missing_swish_not_approved_exit_needs_revision" "2" "$_codex_e3_missing_swish_not_approved_exit"
run_test "codex_e3_missing_swish_not_approved_verdict" "VERDICT: ESCALATE — Codex terminal verdict matches neither an approved clean template nor the documented blocking markers" \
  "$(printf '%s\n' "$_codex_e3_missing_swish_not_approved_output" | grep "^VERDICT:")"
rm -rf "$_codex_e3_missing_swish_not_approved_mock_dir"
unset _codex_e3_missing_swish_not_approved_mock_dir _codex_e3_missing_swish_not_approved_output _codex_e3_missing_swish_not_approved_exit

# Parser-risk addendum E5 (issue #1491's implementation plan): the real
# template with a 6-character SHA plus the complete real footer — below
# the {7,40} bound. Review-sourced: a malformed SHA never becomes
# terminal evidence via the root-comment extraction path, so this case
# is constructed as a review (pinned via the API's own commit_id field,
# independent of the body text) to isolate what the classifier itself
# does with the malformed value.
_codex_e5_short_sha_not_approved_mock_dir="$(mktemp -d)"
cat > "$_codex_e5_short_sha_not_approved_mock_dir/gh" <<'CODEX_E5_SHORT_SHA_NOT_APPROVED_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'e5e5e5e5e5e5\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":403,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    jq -nc '[{submitted_at:"2026-01-01T00:00:01Z",commit_id:"e5e5e5e5e5e5",user:{login:"chatgpt-codex-connector[bot]"},body:("Codex Review: Didn'\''t find any major issues. Swish! **Reviewed commit:** `abcdef` <details> <summary>ℹ️ About Codex in GitHub</summary> <br/> [Your team has set up Codex to review pull requests in this repo](https://chatgpt.com/codex/cloud/settings/general). Reviews are triggered when you - Open a pull request for review - Mark a draft as ready - Comment \"@codex review\". If Codex has suggestions, it will comment; otherwise it will react with 👍. Codex can also answer questions or update the PR. Try commenting \"@codex address that feedback\". </details>")}]'
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
CODEX_E5_SHORT_SHA_NOT_APPROVED_GH
chmod +x "$_codex_e5_short_sha_not_approved_mock_dir/gh"

_codex_e5_short_sha_not_approved_output=""
_codex_e5_short_sha_not_approved_exit=0
PATH="$_codex_e5_short_sha_not_approved_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_e5_short_sha_not_approved_mock_dir/output.txt" 2>&1 || _codex_e5_short_sha_not_approved_exit=$?
_codex_e5_short_sha_not_approved_output="$(cat "$_codex_e5_short_sha_not_approved_mock_dir/output.txt")"
run_test "codex_e5_short_sha_not_approved_exit_needs_revision" "2" "$_codex_e5_short_sha_not_approved_exit"
run_test "codex_e5_short_sha_not_approved_verdict" "VERDICT: ESCALATE — Codex terminal verdict matches neither an approved clean template nor the documented blocking markers" \
  "$(printf '%s\n' "$_codex_e5_short_sha_not_approved_output" | grep "^VERDICT:")"
rm -rf "$_codex_e5_short_sha_not_approved_mock_dir"
unset _codex_e5_short_sha_not_approved_mock_dir _codex_e5_short_sha_not_approved_output _codex_e5_short_sha_not_approved_exit

# Parser-risk addendum E6 (issue #1491's implementation plan): the real
# template with a 41-character SHA plus the complete real footer — above
# the {7,40} bound (one past a full SHA-1). Review-sourced, same reason
# as E5.
_codex_e6_oversized_sha_not_approved_mock_dir="$(mktemp -d)"
cat > "$_codex_e6_oversized_sha_not_approved_mock_dir/gh" <<'CODEX_E6_OVERSIZED_SHA_NOT_APPROVED_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'e6e6e6e6e6e6\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":404,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    jq -nc '[{submitted_at:"2026-01-01T00:00:01Z",commit_id:"e6e6e6e6e6e6",user:{login:"chatgpt-codex-connector[bot]"},body:("Codex Review: Didn'\''t find any major issues. Swish! **Reviewed commit:** `eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee` <details> <summary>ℹ️ About Codex in GitHub</summary> <br/> [Your team has set up Codex to review pull requests in this repo](https://chatgpt.com/codex/cloud/settings/general). Reviews are triggered when you - Open a pull request for review - Mark a draft as ready - Comment \"@codex review\". If Codex has suggestions, it will comment; otherwise it will react with 👍. Codex can also answer questions or update the PR. Try commenting \"@codex address that feedback\". </details>")}]'
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
CODEX_E6_OVERSIZED_SHA_NOT_APPROVED_GH
chmod +x "$_codex_e6_oversized_sha_not_approved_mock_dir/gh"

_codex_e6_oversized_sha_not_approved_output=""
_codex_e6_oversized_sha_not_approved_exit=0
PATH="$_codex_e6_oversized_sha_not_approved_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_e6_oversized_sha_not_approved_mock_dir/output.txt" 2>&1 || _codex_e6_oversized_sha_not_approved_exit=$?
_codex_e6_oversized_sha_not_approved_output="$(cat "$_codex_e6_oversized_sha_not_approved_mock_dir/output.txt")"
run_test "codex_e6_oversized_sha_not_approved_exit_needs_revision" "2" "$_codex_e6_oversized_sha_not_approved_exit"
run_test "codex_e6_oversized_sha_not_approved_verdict" "VERDICT: ESCALATE — Codex terminal verdict matches neither an approved clean template nor the documented blocking markers" \
  "$(printf '%s\n' "$_codex_e6_oversized_sha_not_approved_output" | grep "^VERDICT:")"
rm -rf "$_codex_e6_oversized_sha_not_approved_mock_dir"
unset _codex_e6_oversized_sha_not_approved_mock_dir _codex_e6_oversized_sha_not_approved_output _codex_e6_oversized_sha_not_approved_exit

# Parser-risk addendum E7 (issue #1491's implementation plan): the real
# template with a full-length (40-character) SHA plus the complete real
# footer. Confirms the upper bound is inclusive, not an off-by-one
# exclusion of legitimate full-length SHAs.
_codex_e7_full_length_sha_approved_mock_dir="$(mktemp -d)"
cat > "$_codex_e7_full_length_sha_approved_mock_dir/gh" <<'CODEX_E7_FULL_LENGTH_SHA_APPROVED_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'abababababababababababababababababababab\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":405,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    jq -nc '[{id:406,created_at:"2026-01-01T00:00:01Z",user:{login:"chatgpt-codex-connector[bot]"},body:("Codex Review: Didn'\''t find any major issues. Swish! **Reviewed commit:** `abababababababababababababababababababab` <details> <summary>ℹ️ About Codex in GitHub</summary> <br/> [Your team has set up Codex to review pull requests in this repo](https://chatgpt.com/codex/cloud/settings/general). Reviews are triggered when you - Open a pull request for review - Mark a draft as ready - Comment \"@codex review\". If Codex has suggestions, it will comment; otherwise it will react with 👍. Codex can also answer questions or update the PR. Try commenting \"@codex address that feedback\". </details>")}]'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_E7_FULL_LENGTH_SHA_APPROVED_GH
chmod +x "$_codex_e7_full_length_sha_approved_mock_dir/gh"

_codex_e7_full_length_sha_approved_output=""
_codex_e7_full_length_sha_approved_exit=0
PATH="$_codex_e7_full_length_sha_approved_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_e7_full_length_sha_approved_mock_dir/output.txt" 2>&1 || _codex_e7_full_length_sha_approved_exit=$?
_codex_e7_full_length_sha_approved_output="$(cat "$_codex_e7_full_length_sha_approved_mock_dir/output.txt")"
run_test "codex_e7_full_length_sha_approved_exit_clean" "0" "$_codex_e7_full_length_sha_approved_exit"
run_test "codex_e7_full_length_sha_approved_verdict" "VERDICT: APPROVED" \
  "$(printf '%s\n' "$_codex_e7_full_length_sha_approved_output" | grep "^VERDICT:")"
rm -rf "$_codex_e7_full_length_sha_approved_mock_dir"
unset _codex_e7_full_length_sha_approved_mock_dir _codex_e7_full_length_sha_approved_output _codex_e7_full_length_sha_approved_exit

# Parser-risk addendum E8 (issue #1491's implementation plan): the real
# template with a non-hex "SHA" plus the complete real footer. The
# placeholder accepts hex digits only. Review-sourced, same reason as E5.
_codex_e8_non_hex_sha_not_approved_mock_dir="$(mktemp -d)"
cat > "$_codex_e8_non_hex_sha_not_approved_mock_dir/gh" <<'CODEX_E8_NON_HEX_SHA_NOT_APPROVED_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'e8e8e8e8e8e8\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":406,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    jq -nc '[{submitted_at:"2026-01-01T00:00:01Z",commit_id:"e8e8e8e8e8e8",user:{login:"chatgpt-codex-connector[bot]"},body:("Codex Review: Didn'\''t find any major issues. Swish! **Reviewed commit:** `not-a-sha!` <details> <summary>ℹ️ About Codex in GitHub</summary> <br/> [Your team has set up Codex to review pull requests in this repo](https://chatgpt.com/codex/cloud/settings/general). Reviews are triggered when you - Open a pull request for review - Mark a draft as ready - Comment \"@codex review\". If Codex has suggestions, it will comment; otherwise it will react with 👍. Codex can also answer questions or update the PR. Try commenting \"@codex address that feedback\". </details>")}]'
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
CODEX_E8_NON_HEX_SHA_NOT_APPROVED_GH
chmod +x "$_codex_e8_non_hex_sha_not_approved_mock_dir/gh"

_codex_e8_non_hex_sha_not_approved_output=""
_codex_e8_non_hex_sha_not_approved_exit=0
PATH="$_codex_e8_non_hex_sha_not_approved_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_e8_non_hex_sha_not_approved_mock_dir/output.txt" 2>&1 || _codex_e8_non_hex_sha_not_approved_exit=$?
_codex_e8_non_hex_sha_not_approved_output="$(cat "$_codex_e8_non_hex_sha_not_approved_mock_dir/output.txt")"
run_test "codex_e8_non_hex_sha_not_approved_exit_needs_revision" "2" "$_codex_e8_non_hex_sha_not_approved_exit"
run_test "codex_e8_non_hex_sha_not_approved_verdict" "VERDICT: ESCALATE — Codex terminal verdict matches neither an approved clean template nor the documented blocking markers" \
  "$(printf '%s\n' "$_codex_e8_non_hex_sha_not_approved_output" | grep "^VERDICT:")"
rm -rf "$_codex_e8_non_hex_sha_not_approved_mock_dir"
unset _codex_e8_non_hex_sha_not_approved_mock_dir _codex_e8_non_hex_sha_not_approved_output _codex_e8_non_hex_sha_not_approved_exit

# Parser-risk addendum E9 (issue #1491's implementation plan): the real
# template plus complete real footer, with unrelated prose immediately
# BEFORE the verdict sentence. Exact match is whole-body, not a
# substring/prefix test — extra leading text breaks the match.
_codex_e9_leading_prose_not_approved_mock_dir="$(mktemp -d)"
cat > "$_codex_e9_leading_prose_not_approved_mock_dir/gh" <<'CODEX_E9_LEADING_PROSE_NOT_APPROVED_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'e9e9e9e9e9e9\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":407,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    jq -nc '[{id:408,created_at:"2026-01-01T00:00:01Z",user:{login:"chatgpt-codex-connector[bot]"},body:("FYI: Codex Review: Didn'\''t find any major issues. Swish! **Reviewed commit:** `e9e9e9e9e9` <details> <summary>ℹ️ About Codex in GitHub</summary> <br/> [Your team has set up Codex to review pull requests in this repo](https://chatgpt.com/codex/cloud/settings/general). Reviews are triggered when you - Open a pull request for review - Mark a draft as ready - Comment \"@codex review\". If Codex has suggestions, it will comment; otherwise it will react with 👍. Codex can also answer questions or update the PR. Try commenting \"@codex address that feedback\". </details>")}]'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_E9_LEADING_PROSE_NOT_APPROVED_GH
chmod +x "$_codex_e9_leading_prose_not_approved_mock_dir/gh"

_codex_e9_leading_prose_not_approved_output=""
_codex_e9_leading_prose_not_approved_exit=0
PATH="$_codex_e9_leading_prose_not_approved_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_e9_leading_prose_not_approved_mock_dir/output.txt" 2>&1 || _codex_e9_leading_prose_not_approved_exit=$?
_codex_e9_leading_prose_not_approved_output="$(cat "$_codex_e9_leading_prose_not_approved_mock_dir/output.txt")"
run_test "codex_e9_leading_prose_not_approved_exit_needs_revision" "2" "$_codex_e9_leading_prose_not_approved_exit"
run_test "codex_e9_leading_prose_not_approved_verdict" "VERDICT: ESCALATE — Codex terminal verdict matches neither an approved clean template nor the documented blocking markers" \
  "$(printf '%s\n' "$_codex_e9_leading_prose_not_approved_output" | grep "^VERDICT:")"
rm -rf "$_codex_e9_leading_prose_not_approved_mock_dir"
unset _codex_e9_leading_prose_not_approved_mock_dir _codex_e9_leading_prose_not_approved_output _codex_e9_leading_prose_not_approved_exit

# Parser-risk addendum E10 (issue #1491's implementation plan): the real
# template plus complete real footer, with unrelated prose immediately
# AFTER </details>. Confirms no trailing-clause exploit of any kind can
# reach APPROVED: any trailing content at all breaks the whole-body
# match, regardless of wording or how much of the footer precedes it.
_codex_e10_trailing_prose_not_approved_mock_dir="$(mktemp -d)"
cat > "$_codex_e10_trailing_prose_not_approved_mock_dir/gh" <<'CODEX_E10_TRAILING_PROSE_NOT_APPROVED_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'e1010101010a\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":408,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    jq -nc '[{id:409,created_at:"2026-01-01T00:00:01Z",user:{login:"chatgpt-codex-connector[bot]"},body:("Codex Review: Didn'\''t find any major issues. Swish! **Reviewed commit:** `e1010101010` <details> <summary>ℹ️ About Codex in GitHub</summary> <br/> [Your team has set up Codex to review pull requests in this repo](https://chatgpt.com/codex/cloud/settings/general). Reviews are triggered when you - Open a pull request for review - Mark a draft as ready - Comment \"@codex review\". If Codex has suggestions, it will comment; otherwise it will react with 👍. Codex can also answer questions or update the PR. Try commenting \"@codex address that feedback\". </details> Rename the unsafe function.")}]'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_E10_TRAILING_PROSE_NOT_APPROVED_GH
chmod +x "$_codex_e10_trailing_prose_not_approved_mock_dir/gh"

_codex_e10_trailing_prose_not_approved_output=""
_codex_e10_trailing_prose_not_approved_exit=0
PATH="$_codex_e10_trailing_prose_not_approved_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_e10_trailing_prose_not_approved_mock_dir/output.txt" 2>&1 || _codex_e10_trailing_prose_not_approved_exit=$?
_codex_e10_trailing_prose_not_approved_output="$(cat "$_codex_e10_trailing_prose_not_approved_mock_dir/output.txt")"
run_test "codex_e10_trailing_prose_not_approved_exit_needs_revision" "2" "$_codex_e10_trailing_prose_not_approved_exit"
run_test "codex_e10_trailing_prose_not_approved_verdict" "VERDICT: ESCALATE — Codex terminal verdict matches neither an approved clean template nor the documented blocking markers" \
  "$(printf '%s\n' "$_codex_e10_trailing_prose_not_approved_output" | grep "^VERDICT:")"
rm -rf "$_codex_e10_trailing_prose_not_approved_mock_dir"
unset _codex_e10_trailing_prose_not_approved_mock_dir _codex_e10_trailing_prose_not_approved_output _codex_e10_trailing_prose_not_approved_exit

# Parser-risk addendum E11 (issue #1491's implementation plan): the real
# template plus complete real footer, wrapped in a fenced code block.
# Confirms no dedicated fence-marker check is needed (Decision 1): the
# fence characters are literal extra text the template does not
# contain, so the match fails on its own.
_codex_e11_fenced_wrapper_not_approved_mock_dir="$(mktemp -d)"
cat > "$_codex_e11_fenced_wrapper_not_approved_mock_dir/gh" <<'CODEX_E11_FENCED_WRAPPER_NOT_APPROVED_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'e11e11e11e1\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":409,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    jq -nc '[{id:410,created_at:"2026-01-01T00:00:01Z",user:{login:"chatgpt-codex-connector[bot]"},body:("```
Codex Review: Didn'\''t find any major issues. Swish! **Reviewed commit:** `e11e11e11e` <details> <summary>ℹ️ About Codex in GitHub</summary> <br/> [Your team has set up Codex to review pull requests in this repo](https://chatgpt.com/codex/cloud/settings/general). Reviews are triggered when you - Open a pull request for review - Mark a draft as ready - Comment \"@codex review\". If Codex has suggestions, it will comment; otherwise it will react with 👍. Codex can also answer questions or update the PR. Try commenting \"@codex address that feedback\". </details>
```")}]'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_E11_FENCED_WRAPPER_NOT_APPROVED_GH
chmod +x "$_codex_e11_fenced_wrapper_not_approved_mock_dir/gh"

_codex_e11_fenced_wrapper_not_approved_output=""
_codex_e11_fenced_wrapper_not_approved_exit=0
PATH="$_codex_e11_fenced_wrapper_not_approved_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_e11_fenced_wrapper_not_approved_mock_dir/output.txt" 2>&1 || _codex_e11_fenced_wrapper_not_approved_exit=$?
_codex_e11_fenced_wrapper_not_approved_output="$(cat "$_codex_e11_fenced_wrapper_not_approved_mock_dir/output.txt")"
run_test "codex_e11_fenced_wrapper_not_approved_exit_needs_revision" "2" "$_codex_e11_fenced_wrapper_not_approved_exit"
run_test "codex_e11_fenced_wrapper_not_approved_verdict" "VERDICT: ESCALATE — Codex terminal verdict matches neither an approved clean template nor the documented blocking markers" \
  "$(printf '%s\n' "$_codex_e11_fenced_wrapper_not_approved_output" | grep "^VERDICT:")"
rm -rf "$_codex_e11_fenced_wrapper_not_approved_mock_dir"
unset _codex_e11_fenced_wrapper_not_approved_mock_dir _codex_e11_fenced_wrapper_not_approved_output _codex_e11_fenced_wrapper_not_approved_exit

# Parser-risk addendum E12 (issue #1491's implementation plan): the real
# template with extra/irregular whitespace (extra spaces, tabs, multiple
# blank lines, trailing spaces, extra whitespace around the footer).
# Confirms codex_normalize_whitespace provides exactly the permitted
# flexibility (Decision 1) and nothing more, across the entire body
# including the footer.
_codex_e12_irregular_whitespace_approved_mock_dir="$(mktemp -d)"
cat > "$_codex_e12_irregular_whitespace_approved_mock_dir/gh" <<'CODEX_E12_IRREGULAR_WHITESPACE_APPROVED_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'e12e12e12e1\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":410,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    jq -nc '[{id:411,created_at:"2026-01-01T00:00:01Z",user:{login:"chatgpt-codex-connector[bot]"},body:("  Codex Review:   Didn'\''t find any major issues.	 Swish!

**Reviewed commit:**  `e12e12e12e`  <details>   <summary>ℹ️ About Codex in GitHub</summary>


<br/>		[Your team has set up Codex to review pull requests in this repo](https://chatgpt.com/codex/cloud/settings/general).   Reviews are triggered when you
  - Open a pull request for review
  - Mark a draft as ready
  - Comment \"@codex review\".


If Codex has suggestions, it will comment; otherwise it will react with 👍.



Codex can also answer questions or update the PR.   Try commenting
\"@codex address that feedback\".   

</details>   ")}]'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_E12_IRREGULAR_WHITESPACE_APPROVED_GH
chmod +x "$_codex_e12_irregular_whitespace_approved_mock_dir/gh"

_codex_e12_irregular_whitespace_approved_output=""
_codex_e12_irregular_whitespace_approved_exit=0
PATH="$_codex_e12_irregular_whitespace_approved_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_e12_irregular_whitespace_approved_mock_dir/output.txt" 2>&1 || _codex_e12_irregular_whitespace_approved_exit=$?
_codex_e12_irregular_whitespace_approved_output="$(cat "$_codex_e12_irregular_whitespace_approved_mock_dir/output.txt")"
run_test "codex_e12_irregular_whitespace_approved_exit_clean" "0" "$_codex_e12_irregular_whitespace_approved_exit"
run_test "codex_e12_irregular_whitespace_approved_verdict" "VERDICT: APPROVED" \
  "$(printf '%s\n' "$_codex_e12_irregular_whitespace_approved_output" | grep "^VERDICT:")"
rm -rf "$_codex_e12_irregular_whitespace_approved_mock_dir"
unset _codex_e12_irregular_whitespace_approved_mock_dir _codex_e12_irregular_whitespace_approved_output _codex_e12_irregular_whitespace_approved_exit

# Parser-risk addendum E13 (issue #1491's implementation plan): the real
# template plus complete real footer, case-altered (lower-cased verdict
# sentence and footer text). Confirms there is no case-insensitive
# matching beyond what the captures themselves show (Decision 1),
# for the footer as much as for the verdict sentence. Review-sourced,
# same reason as E5 (a case-folded SHA is never extracted by the
# case-sensitive root-comment path).
_codex_e13_case_altered_not_approved_mock_dir="$(mktemp -d)"
cat > "$_codex_e13_case_altered_not_approved_mock_dir/gh" <<'CODEX_E13_CASE_ALTERED_NOT_APPROVED_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'e13e13e13e1\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":411,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    jq -nc '[{submitted_at:"2026-01-01T00:00:01Z",commit_id:"e13e13e13e1",user:{login:"chatgpt-codex-connector[bot]"},body:("codex review: didn'\''t find any major issues. swish! **reviewed commit:** `e13e13e13e` <details> <summary>ℹ️ about codex in github</summary> <br/> [your team has set up codex to review pull requests in this repo](https://chatgpt.com/codex/cloud/settings/general). reviews are triggered when you - open a pull request for review - mark a draft as ready - comment \"@codex review\". if codex has suggestions, it will comment; otherwise it will react with 👍. codex can also answer questions or update the pr. try commenting \"@codex address that feedback\". </details>")}]'
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
CODEX_E13_CASE_ALTERED_NOT_APPROVED_GH
chmod +x "$_codex_e13_case_altered_not_approved_mock_dir/gh"

_codex_e13_case_altered_not_approved_output=""
_codex_e13_case_altered_not_approved_exit=0
PATH="$_codex_e13_case_altered_not_approved_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_e13_case_altered_not_approved_mock_dir/output.txt" 2>&1 || _codex_e13_case_altered_not_approved_exit=$?
_codex_e13_case_altered_not_approved_output="$(cat "$_codex_e13_case_altered_not_approved_mock_dir/output.txt")"
run_test "codex_e13_case_altered_not_approved_exit_needs_revision" "2" "$_codex_e13_case_altered_not_approved_exit"
run_test "codex_e13_case_altered_not_approved_verdict" "VERDICT: ESCALATE — Codex terminal verdict matches neither an approved clean template nor the documented blocking markers" \
  "$(printf '%s\n' "$_codex_e13_case_altered_not_approved_output" | grep "^VERDICT:")"
rm -rf "$_codex_e13_case_altered_not_approved_mock_dir"
unset _codex_e13_case_altered_not_approved_mock_dir _codex_e13_case_altered_not_approved_output _codex_e13_case_altered_not_approved_exit

# Parser-risk addendum E15 (issue #1491's implementation plan): an
# underscore-variant boundary-lookalike construction — trivially
# rejected under this design because it is not a reproduction of any
# template.
_codex_e15_underscore_variant_not_approved_mock_dir="$(mktemp -d)"
cat > "$_codex_e15_underscore_variant_not_approved_mock_dir/gh" <<'CODEX_E15_UNDERSCORE_VARIANT_NOT_APPROVED_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'e15e15e15e1\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":412,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    jq -nc '[{id:413,created_at:"2026-01-01T00:00:01Z",user:{login:"chatgpt-codex-connector[bot]"},body:("This remains un_approved.

**Reviewed commit:** `e15e15e15e`")}]'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_E15_UNDERSCORE_VARIANT_NOT_APPROVED_GH
chmod +x "$_codex_e15_underscore_variant_not_approved_mock_dir/gh"

_codex_e15_underscore_variant_not_approved_output=""
_codex_e15_underscore_variant_not_approved_exit=0
PATH="$_codex_e15_underscore_variant_not_approved_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_e15_underscore_variant_not_approved_mock_dir/output.txt" 2>&1 || _codex_e15_underscore_variant_not_approved_exit=$?
_codex_e15_underscore_variant_not_approved_output="$(cat "$_codex_e15_underscore_variant_not_approved_mock_dir/output.txt")"
run_test "codex_e15_underscore_variant_not_approved_exit_needs_revision" "2" "$_codex_e15_underscore_variant_not_approved_exit"
run_test "codex_e15_underscore_variant_not_approved_verdict" "VERDICT: ESCALATE — Codex terminal verdict matches neither an approved clean template nor the documented blocking markers" \
  "$(printf '%s\n' "$_codex_e15_underscore_variant_not_approved_output" | grep "^VERDICT:")"
rm -rf "$_codex_e15_underscore_variant_not_approved_mock_dir"
unset _codex_e15_underscore_variant_not_approved_mock_dir _codex_e15_underscore_variant_not_approved_output _codex_e15_underscore_variant_not_approved_exit

# Parser-risk addendum E16 (issue #1491's implementation plan):
# disqualifier-list gap under an earlier design (Codex GitHub finding
# `3800167486`) — now genuinely closed, because it was never a
# reproduction of any template to begin with.
_codex_e16_disqualifier_gap_not_approved_mock_dir="$(mktemp -d)"
cat > "$_codex_e16_disqualifier_gap_not_approved_mock_dir/gh" <<'CODEX_E16_DISQUALIFIER_GAP_NOT_APPROVED_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'e16e16e16e1\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":413,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    jq -nc '[{id:414,created_at:"2026-01-01T00:00:01Z",user:{login:"chatgpt-codex-connector[bot]"},body:("Looks good. Remove the authentication check.

**Reviewed commit:** `e16e16e16e`")}]'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_E16_DISQUALIFIER_GAP_NOT_APPROVED_GH
chmod +x "$_codex_e16_disqualifier_gap_not_approved_mock_dir/gh"

_codex_e16_disqualifier_gap_not_approved_output=""
_codex_e16_disqualifier_gap_not_approved_exit=0
PATH="$_codex_e16_disqualifier_gap_not_approved_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_e16_disqualifier_gap_not_approved_mock_dir/output.txt" 2>&1 || _codex_e16_disqualifier_gap_not_approved_exit=$?
_codex_e16_disqualifier_gap_not_approved_output="$(cat "$_codex_e16_disqualifier_gap_not_approved_mock_dir/output.txt")"
run_test "codex_e16_disqualifier_gap_not_approved_exit_needs_revision" "2" "$_codex_e16_disqualifier_gap_not_approved_exit"
run_test "codex_e16_disqualifier_gap_not_approved_verdict" "VERDICT: ESCALATE — Codex terminal verdict matches neither an approved clean template nor the documented blocking markers" \
  "$(printf '%s\n' "$_codex_e16_disqualifier_gap_not_approved_output" | grep "^VERDICT:")"
rm -rf "$_codex_e16_disqualifier_gap_not_approved_mock_dir"
unset _codex_e16_disqualifier_gap_not_approved_mock_dir _codex_e16_disqualifier_gap_not_approved_output _codex_e16_disqualifier_gap_not_approved_exit

# Parser-risk addendum E17 (issue #1491's implementation plan): the
# residual gap an earlier zero-tolerance-grammar design disclosed but
# could not close — now genuinely closed, because it was never a
# reproduction of any template to begin with.
_codex_e17_zero_tolerance_gap_not_approved_mock_dir="$(mktemp -d)"
cat > "$_codex_e17_zero_tolerance_gap_not_approved_mock_dir/gh" <<'CODEX_E17_ZERO_TOLERANCE_GAP_NOT_APPROVED_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'e17e17e17e1\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":414,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    jq -nc '[{id:415,created_at:"2026-01-01T00:00:01Z",user:{login:"chatgpt-codex-connector[bot]"},body:("Approved. Revert.

**Reviewed commit:** `e17e17e17e`")}]'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_E17_ZERO_TOLERANCE_GAP_NOT_APPROVED_GH
chmod +x "$_codex_e17_zero_tolerance_gap_not_approved_mock_dir/gh"

_codex_e17_zero_tolerance_gap_not_approved_output=""
_codex_e17_zero_tolerance_gap_not_approved_exit=0
PATH="$_codex_e17_zero_tolerance_gap_not_approved_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_e17_zero_tolerance_gap_not_approved_mock_dir/output.txt" 2>&1 || _codex_e17_zero_tolerance_gap_not_approved_exit=$?
_codex_e17_zero_tolerance_gap_not_approved_output="$(cat "$_codex_e17_zero_tolerance_gap_not_approved_mock_dir/output.txt")"
run_test "codex_e17_zero_tolerance_gap_not_approved_exit_needs_revision" "2" "$_codex_e17_zero_tolerance_gap_not_approved_exit"
run_test "codex_e17_zero_tolerance_gap_not_approved_verdict" "VERDICT: ESCALATE — Codex terminal verdict matches neither an approved clean template nor the documented blocking markers" \
  "$(printf '%s\n' "$_codex_e17_zero_tolerance_gap_not_approved_output" | grep "^VERDICT:")"
rm -rf "$_codex_e17_zero_tolerance_gap_not_approved_mock_dir"
unset _codex_e17_zero_tolerance_gap_not_approved_mock_dir _codex_e17_zero_tolerance_gap_not_approved_output _codex_e17_zero_tolerance_gap_not_approved_exit

# Parser-risk addendum E18 (issue #1491's implementation plan):
# vendor-metadata-token gap under an earlier design (Codex GitHub
# finding `3803050745`) — now genuinely closed, because it was never a
# reproduction of any template to begin with.
_codex_e18_vendor_flavor_token_gap_not_approved_mock_dir="$(mktemp -d)"
cat > "$_codex_e18_vendor_flavor_token_gap_not_approved_mock_dir/gh" <<'CODEX_E18_VENDOR_FLAVOR_TOKEN_GAP_NOT_APPROVED_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'e18e18e18e1\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":415,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    jq -nc '[{id:416,created_at:"2026-01-01T00:00:01Z",user:{login:"chatgpt-codex-connector[bot]"},body:("Looks good. Commit this.

**Reviewed commit:** `e18e18e18e`")}]'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_E18_VENDOR_FLAVOR_TOKEN_GAP_NOT_APPROVED_GH
chmod +x "$_codex_e18_vendor_flavor_token_gap_not_approved_mock_dir/gh"

_codex_e18_vendor_flavor_token_gap_not_approved_output=""
_codex_e18_vendor_flavor_token_gap_not_approved_exit=0
PATH="$_codex_e18_vendor_flavor_token_gap_not_approved_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_e18_vendor_flavor_token_gap_not_approved_mock_dir/output.txt" 2>&1 || _codex_e18_vendor_flavor_token_gap_not_approved_exit=$?
_codex_e18_vendor_flavor_token_gap_not_approved_output="$(cat "$_codex_e18_vendor_flavor_token_gap_not_approved_mock_dir/output.txt")"
run_test "codex_e18_vendor_flavor_token_gap_not_approved_exit_needs_revision" "2" "$_codex_e18_vendor_flavor_token_gap_not_approved_exit"
run_test "codex_e18_vendor_flavor_token_gap_not_approved_verdict" "VERDICT: ESCALATE — Codex terminal verdict matches neither an approved clean template nor the documented blocking markers" \
  "$(printf '%s\n' "$_codex_e18_vendor_flavor_token_gap_not_approved_output" | grep "^VERDICT:")"
rm -rf "$_codex_e18_vendor_flavor_token_gap_not_approved_mock_dir"
unset _codex_e18_vendor_flavor_token_gap_not_approved_mock_dir _codex_e18_vendor_flavor_token_gap_not_approved_output _codex_e18_vendor_flavor_token_gap_not_approved_exit

# Parser-risk addendum E19 (issue #1491's implementation plan):
# over-broad footer-truncation-regex gap under an earlier design
# (Codex GitHub finding `3800167489`) — under this revision there is no
# truncation step at all to over-match; the body simply does not
# reproduce the one evidenced literal, regardless of what any
# <details>-shaped text inside it says. Includes an explicit
# **Reviewed commit:** marker (needed to reach terminal evidence).
_codex_e19_non_vendor_details_block_not_approved_mock_dir="$(mktemp -d)"
cat > "$_codex_e19_non_vendor_details_block_not_approved_mock_dir/gh" <<'CODEX_E19_NON_VENDOR_DETAILS_BLOCK_NOT_APPROVED_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'e19e19e19e1\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":416,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    jq -nc '[{id:417,created_at:"2026-01-01T00:00:01Z",user:{login:"chatgpt-codex-connector[bot]"},body:("Looks good. <details><summary>Notes</summary>Rename the unsafe function.</details>

**Reviewed commit:** `e19e19e19e`")}]'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_E19_NON_VENDOR_DETAILS_BLOCK_NOT_APPROVED_GH
chmod +x "$_codex_e19_non_vendor_details_block_not_approved_mock_dir/gh"

_codex_e19_non_vendor_details_block_not_approved_output=""
_codex_e19_non_vendor_details_block_not_approved_exit=0
PATH="$_codex_e19_non_vendor_details_block_not_approved_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_e19_non_vendor_details_block_not_approved_mock_dir/output.txt" 2>&1 || _codex_e19_non_vendor_details_block_not_approved_exit=$?
_codex_e19_non_vendor_details_block_not_approved_output="$(cat "$_codex_e19_non_vendor_details_block_not_approved_mock_dir/output.txt")"
run_test "codex_e19_non_vendor_details_block_not_approved_exit_needs_revision" "2" "$_codex_e19_non_vendor_details_block_not_approved_exit"
run_test "codex_e19_non_vendor_details_block_not_approved_verdict" "VERDICT: ESCALATE — Codex terminal verdict matches neither an approved clean template nor the documented blocking markers" \
  "$(printf '%s\n' "$_codex_e19_non_vendor_details_block_not_approved_output" | grep "^VERDICT:")"
rm -rf "$_codex_e19_non_vendor_details_block_not_approved_mock_dir"
unset _codex_e19_non_vendor_details_block_not_approved_mock_dir _codex_e19_non_vendor_details_block_not_approved_output _codex_e19_non_vendor_details_block_not_approved_exit

# Parser-risk addendum E20 (issue #1491's implementation plan):
# tag-name-flexible footer-truncation-regex gap under an earlier design
# (Codex GitHub finding `3803189273`) — same reason as E19: no
# truncation step left to apply a tag-name pattern to. Includes an
# explicit **Reviewed commit:** marker (needed to reach terminal
# evidence).
_codex_e20_tag_flexible_variant_not_approved_mock_dir="$(mktemp -d)"
cat > "$_codex_e20_tag_flexible_variant_not_approved_mock_dir/gh" <<'CODEX_E20_TAG_FLEXIBLE_VARIANT_NOT_APPROVED_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'e20e20e20e1\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":417,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    jq -nc '[{id:418,created_at:"2026-01-01T00:00:01Z",user:{login:"chatgpt-codex-connector[bot]"},body:("Looks good. <details-not-footer><summary-note>About Codex in GitHub</summary-note>Rename the unsafe function.</details-not-footer>

**Reviewed commit:** `e20e20e20e`")}]'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_E20_TAG_FLEXIBLE_VARIANT_NOT_APPROVED_GH
chmod +x "$_codex_e20_tag_flexible_variant_not_approved_mock_dir/gh"

_codex_e20_tag_flexible_variant_not_approved_output=""
_codex_e20_tag_flexible_variant_not_approved_exit=0
PATH="$_codex_e20_tag_flexible_variant_not_approved_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_e20_tag_flexible_variant_not_approved_mock_dir/output.txt" 2>&1 || _codex_e20_tag_flexible_variant_not_approved_exit=$?
_codex_e20_tag_flexible_variant_not_approved_output="$(cat "$_codex_e20_tag_flexible_variant_not_approved_mock_dir/output.txt")"
run_test "codex_e20_tag_flexible_variant_not_approved_exit_needs_revision" "2" "$_codex_e20_tag_flexible_variant_not_approved_exit"
run_test "codex_e20_tag_flexible_variant_not_approved_verdict" "VERDICT: ESCALATE — Codex terminal verdict matches neither an approved clean template nor the documented blocking markers" \
  "$(printf '%s\n' "$_codex_e20_tag_flexible_variant_not_approved_output" | grep "^VERDICT:")"
rm -rf "$_codex_e20_tag_flexible_variant_not_approved_mock_dir"
unset _codex_e20_tag_flexible_variant_not_approved_mock_dir _codex_e20_tag_flexible_variant_not_approved_output _codex_e20_tag_flexible_variant_not_approved_exit

# Parser-risk addendum E21 (issue #1491's implementation plan):
# filler-composed-hedge construction (Codex GitHub finding
# `3803306915`) that motivated the third design of this classifier —
# trivially rejected under this design because it is not a
# reproduction of any template.
_codex_e21_filler_composed_hedge_not_approved_mock_dir="$(mktemp -d)"
cat > "$_codex_e21_filler_composed_hedge_not_approved_mock_dir/gh" <<'CODEX_E21_FILLER_COMPOSED_HEDGE_NOT_APPROVED_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'e21e21e21e1\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":418,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    jq -nc '[{id:419,created_at:"2026-01-01T00:00:01Z",user:{login:"chatgpt-codex-connector[bot]"},body:("Looks good, or is it?

**Reviewed commit:** `e21e21e21e`")}]'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_E21_FILLER_COMPOSED_HEDGE_NOT_APPROVED_GH
chmod +x "$_codex_e21_filler_composed_hedge_not_approved_mock_dir/gh"

_codex_e21_filler_composed_hedge_not_approved_output=""
_codex_e21_filler_composed_hedge_not_approved_exit=0
PATH="$_codex_e21_filler_composed_hedge_not_approved_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_e21_filler_composed_hedge_not_approved_mock_dir/output.txt" 2>&1 || _codex_e21_filler_composed_hedge_not_approved_exit=$?
_codex_e21_filler_composed_hedge_not_approved_output="$(cat "$_codex_e21_filler_composed_hedge_not_approved_mock_dir/output.txt")"
run_test "codex_e21_filler_composed_hedge_not_approved_exit_needs_revision" "2" "$_codex_e21_filler_composed_hedge_not_approved_exit"
run_test "codex_e21_filler_composed_hedge_not_approved_verdict" "VERDICT: ESCALATE — Codex terminal verdict matches neither an approved clean template nor the documented blocking markers" \
  "$(printf '%s\n' "$_codex_e21_filler_composed_hedge_not_approved_output" | grep "^VERDICT:")"
rm -rf "$_codex_e21_filler_composed_hedge_not_approved_mock_dir"
unset _codex_e21_filler_composed_hedge_not_approved_mock_dir _codex_e21_filler_composed_hedge_not_approved_output _codex_e21_filler_composed_hedge_not_approved_exit

# Parser-risk addendum E22 (issue #1491's implementation plan): the real
# template plus complete real footer, with "This must not be merged."
# inserted inside the footer (immediately after </summary>). Under this
# revision, is_approved ALONE already returns NEEDS_REVISION for this
# body — inserting any text inside the footer breaks the whole-body
# exact match on its own. codex_response_is_blocking (unchanged,
# Decision 4) still runs first at every verdict site and still
# independently recognizes the refusal, so the COMPOSED verdict is
# still the more specific blocking branch (plain "VERDICT:
# NEEDS_REVISION", not the "(unrecognized...)" safe-fail suffix) — the
# structural relationship between is_approved and is_blocking
# described in Decision 4/5.
_codex_e22_refusal_inside_footer_blocking_mock_dir="$(mktemp -d)"
cat > "$_codex_e22_refusal_inside_footer_blocking_mock_dir/gh" <<'CODEX_E22_REFUSAL_INSIDE_FOOTER_BLOCKING_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'e22e22e22e1\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":419,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    jq -nc '[{id:420,created_at:"2026-01-01T00:00:01Z",user:{login:"chatgpt-codex-connector[bot]"},body:("Codex Review: Didn'\''t find any major issues. Swish! **Reviewed commit:** `e22e22e22e` <details> <summary>ℹ️ About Codex in GitHub</summary> This must not be merged. <br/> [Your team has set up Codex to review pull requests in this repo](https://chatgpt.com/codex/cloud/settings/general). Reviews are triggered when you - Open a pull request for review - Mark a draft as ready - Comment \"@codex review\". If Codex has suggestions, it will comment; otherwise it will react with 👍. Codex can also answer questions or update the PR. Try commenting \"@codex address that feedback\". </details>")}]'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_E22_REFUSAL_INSIDE_FOOTER_BLOCKING_GH
chmod +x "$_codex_e22_refusal_inside_footer_blocking_mock_dir/gh"

_codex_e22_refusal_inside_footer_blocking_output=""
_codex_e22_refusal_inside_footer_blocking_exit=0
PATH="$_codex_e22_refusal_inside_footer_blocking_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_e22_refusal_inside_footer_blocking_mock_dir/output.txt" 2>&1 || _codex_e22_refusal_inside_footer_blocking_exit=$?
_codex_e22_refusal_inside_footer_blocking_output="$(cat "$_codex_e22_refusal_inside_footer_blocking_mock_dir/output.txt")"
run_test "codex_e22_refusal_inside_footer_blocking_exit_needs_revision" "2" "$_codex_e22_refusal_inside_footer_blocking_exit"
run_test "codex_e22_refusal_inside_footer_blocking_verdict" "VERDICT: ESCALATE — Codex finding has no stable review-thread identifier or no identifiable matching review-thread conversation" \
  "$(printf '%s\n' "$_codex_e22_refusal_inside_footer_blocking_output" | grep "^VERDICT:")"
rm -rf "$_codex_e22_refusal_inside_footer_blocking_mock_dir"
unset _codex_e22_refusal_inside_footer_blocking_mock_dir _codex_e22_refusal_inside_footer_blocking_output _codex_e22_refusal_inside_footer_blocking_exit

# Parser-risk addendum E23 (issue #1491's implementation plan): the real
# template, followed by the footer's OPENING LINE ONLY (not its
# complete text), followed by "Rename the unsafe function." — the exact
# construction from Codex GitHub finding `3803545669` that motivated
# this revision. The required literal is the COMPLETE footer text, so a
# body carrying only its opening line does not reproduce that literal.
# The direct regression test for finding `3803545669`.
_codex_e23_footer_opening_line_only_not_approved_mock_dir="$(mktemp -d)"
cat > "$_codex_e23_footer_opening_line_only_not_approved_mock_dir/gh" <<'CODEX_E23_FOOTER_OPENING_LINE_ONLY_NOT_APPROVED_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'e23e23e23e1\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":420,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    jq -nc '[{id:421,created_at:"2026-01-01T00:00:01Z",user:{login:"chatgpt-codex-connector[bot]"},body:("Codex Review: Didn'\''t find any major issues. Swish! **Reviewed commit:** `e23e23e23e` <details> <summary>ℹ️ About Codex in GitHub</summary> Rename the unsafe function.")}]'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_E23_FOOTER_OPENING_LINE_ONLY_NOT_APPROVED_GH
chmod +x "$_codex_e23_footer_opening_line_only_not_approved_mock_dir/gh"

_codex_e23_footer_opening_line_only_not_approved_output=""
_codex_e23_footer_opening_line_only_not_approved_exit=0
PATH="$_codex_e23_footer_opening_line_only_not_approved_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_e23_footer_opening_line_only_not_approved_mock_dir/output.txt" 2>&1 || _codex_e23_footer_opening_line_only_not_approved_exit=$?
_codex_e23_footer_opening_line_only_not_approved_output="$(cat "$_codex_e23_footer_opening_line_only_not_approved_mock_dir/output.txt")"
run_test "codex_e23_footer_opening_line_only_not_approved_exit_needs_revision" "2" "$_codex_e23_footer_opening_line_only_not_approved_exit"
run_test "codex_e23_footer_opening_line_only_not_approved_verdict" "VERDICT: ESCALATE — Codex terminal verdict matches neither an approved clean template nor the documented blocking markers" \
  "$(printf '%s\n' "$_codex_e23_footer_opening_line_only_not_approved_output" | grep "^VERDICT:")"
rm -rf "$_codex_e23_footer_opening_line_only_not_approved_mock_dir"
unset _codex_e23_footer_opening_line_only_not_approved_mock_dir _codex_e23_footer_opening_line_only_not_approved_output _codex_e23_footer_opening_line_only_not_approved_exit

# Parser-risk addendum E24a (issue #1491's implementation plan): the
# real template plus complete real footer, with a single byte changed
# MID-SENTENCE inside the footer body ("this repo" -> "thXs repo").
# Confirms the entire footer is load-bearing for the match, not merely
# its opening line.
_codex_e24a_footer_byte_mutation_mid_sentence_not_approved_mock_dir="$(mktemp -d)"
cat > "$_codex_e24a_footer_byte_mutation_mid_sentence_not_approved_mock_dir/gh" <<'CODEX_E24A_FOOTER_BYTE_MUTATION_MID_SENTENCE_NOT_APPROVED_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'e24a24a24a1\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":421,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    jq -nc '[{id:422,created_at:"2026-01-01T00:00:01Z",user:{login:"chatgpt-codex-connector[bot]"},body:("Codex Review: Didn'\''t find any major issues. Swish! **Reviewed commit:** `e24a24a24a` <details> <summary>ℹ️ About Codex in GitHub</summary> <br/> [Your team has set up Codex to review pull requests in thXs repo](https://chatgpt.com/codex/cloud/settings/general). Reviews are triggered when you - Open a pull request for review - Mark a draft as ready - Comment \"@codex review\". If Codex has suggestions, it will comment; otherwise it will react with 👍. Codex can also answer questions or update the PR. Try commenting \"@codex address that feedback\". </details>")}]'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_E24A_FOOTER_BYTE_MUTATION_MID_SENTENCE_NOT_APPROVED_GH
chmod +x "$_codex_e24a_footer_byte_mutation_mid_sentence_not_approved_mock_dir/gh"

_codex_e24a_footer_byte_mutation_mid_sentence_not_approved_output=""
_codex_e24a_footer_byte_mutation_mid_sentence_not_approved_exit=0
PATH="$_codex_e24a_footer_byte_mutation_mid_sentence_not_approved_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_e24a_footer_byte_mutation_mid_sentence_not_approved_mock_dir/output.txt" 2>&1 || _codex_e24a_footer_byte_mutation_mid_sentence_not_approved_exit=$?
_codex_e24a_footer_byte_mutation_mid_sentence_not_approved_output="$(cat "$_codex_e24a_footer_byte_mutation_mid_sentence_not_approved_mock_dir/output.txt")"
run_test "codex_e24a_footer_byte_mutation_mid_sentence_not_approved_exit_needs_revision" "2" "$_codex_e24a_footer_byte_mutation_mid_sentence_not_approved_exit"
run_test "codex_e24a_footer_byte_mutation_mid_sentence_not_approved_verdict" "VERDICT: ESCALATE — Codex terminal verdict matches neither an approved clean template nor the documented blocking markers" \
  "$(printf '%s\n' "$_codex_e24a_footer_byte_mutation_mid_sentence_not_approved_output" | grep "^VERDICT:")"
rm -rf "$_codex_e24a_footer_byte_mutation_mid_sentence_not_approved_mock_dir"
unset _codex_e24a_footer_byte_mutation_mid_sentence_not_approved_mock_dir _codex_e24a_footer_byte_mutation_mid_sentence_not_approved_output _codex_e24a_footer_byte_mutation_mid_sentence_not_approved_exit

# Parser-risk addendum E24b (issue #1491's implementation plan): the
# real template plus complete real footer, with a single byte changed
# IMMEDIATELY BEFORE </details> (the final "." -> "!"). Confirms the
# footer's closing text is load-bearing, not just its opening line.
_codex_e24b_footer_byte_mutation_before_details_close_not_approved_mock_dir="$(mktemp -d)"
cat > "$_codex_e24b_footer_byte_mutation_before_details_close_not_approved_mock_dir/gh" <<'CODEX_E24B_FOOTER_BYTE_MUTATION_BEFORE_DETAILS_CLOSE_NOT_APPROVED_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'e24b24b24b1\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":422,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    jq -nc '[{id:423,created_at:"2026-01-01T00:00:01Z",user:{login:"chatgpt-codex-connector[bot]"},body:("Codex Review: Didn'\''t find any major issues. Swish! **Reviewed commit:** `e24b24b24b` <details> <summary>ℹ️ About Codex in GitHub</summary> <br/> [Your team has set up Codex to review pull requests in this repo](https://chatgpt.com/codex/cloud/settings/general). Reviews are triggered when you - Open a pull request for review - Mark a draft as ready - Comment \"@codex review\". If Codex has suggestions, it will comment; otherwise it will react with 👍. Codex can also answer questions or update the PR. Try commenting \"@codex address that feedback\"! </details>")}]'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_E24B_FOOTER_BYTE_MUTATION_BEFORE_DETAILS_CLOSE_NOT_APPROVED_GH
chmod +x "$_codex_e24b_footer_byte_mutation_before_details_close_not_approved_mock_dir/gh"

_codex_e24b_footer_byte_mutation_before_details_close_not_approved_output=""
_codex_e24b_footer_byte_mutation_before_details_close_not_approved_exit=0
PATH="$_codex_e24b_footer_byte_mutation_before_details_close_not_approved_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_e24b_footer_byte_mutation_before_details_close_not_approved_mock_dir/output.txt" 2>&1 || _codex_e24b_footer_byte_mutation_before_details_close_not_approved_exit=$?
_codex_e24b_footer_byte_mutation_before_details_close_not_approved_output="$(cat "$_codex_e24b_footer_byte_mutation_before_details_close_not_approved_mock_dir/output.txt")"
run_test "codex_e24b_footer_byte_mutation_before_details_close_not_approved_exit_needs_revision" "2" "$_codex_e24b_footer_byte_mutation_before_details_close_not_approved_exit"
run_test "codex_e24b_footer_byte_mutation_before_details_close_not_approved_verdict" "VERDICT: ESCALATE — Codex terminal verdict matches neither an approved clean template nor the documented blocking markers" \
  "$(printf '%s\n' "$_codex_e24b_footer_byte_mutation_before_details_close_not_approved_output" | grep "^VERDICT:")"
rm -rf "$_codex_e24b_footer_byte_mutation_before_details_close_not_approved_mock_dir"
unset _codex_e24b_footer_byte_mutation_before_details_close_not_approved_mock_dir _codex_e24b_footer_byte_mutation_before_details_close_not_approved_output _codex_e24b_footer_byte_mutation_before_details_close_not_approved_exit

# Parser-risk addendum E24c (issue #1491's implementation plan): the
# real template plus complete real footer, with a single byte changed
# INSIDE the settings URL ("general" -> "genera1"). Confirms the
# footer's URL text is load-bearing, not just its opening line.
_codex_e24c_footer_byte_mutation_in_url_not_approved_mock_dir="$(mktemp -d)"
cat > "$_codex_e24c_footer_byte_mutation_in_url_not_approved_mock_dir/gh" <<'CODEX_E24C_FOOTER_BYTE_MUTATION_IN_URL_NOT_APPROVED_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'e24c24c24c1\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":423,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    jq -nc '[{id:424,created_at:"2026-01-01T00:00:01Z",user:{login:"chatgpt-codex-connector[bot]"},body:("Codex Review: Didn'\''t find any major issues. Swish! **Reviewed commit:** `e24c24c24c` <details> <summary>ℹ️ About Codex in GitHub</summary> <br/> [Your team has set up Codex to review pull requests in this repo](https://chatgpt.com/codex/cloud/settings/genera1). Reviews are triggered when you - Open a pull request for review - Mark a draft as ready - Comment \"@codex review\". If Codex has suggestions, it will comment; otherwise it will react with 👍. Codex can also answer questions or update the PR. Try commenting \"@codex address that feedback\". </details>")}]'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_E24C_FOOTER_BYTE_MUTATION_IN_URL_NOT_APPROVED_GH
chmod +x "$_codex_e24c_footer_byte_mutation_in_url_not_approved_mock_dir/gh"

_codex_e24c_footer_byte_mutation_in_url_not_approved_output=""
_codex_e24c_footer_byte_mutation_in_url_not_approved_exit=0
PATH="$_codex_e24c_footer_byte_mutation_in_url_not_approved_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_e24c_footer_byte_mutation_in_url_not_approved_mock_dir/output.txt" 2>&1 || _codex_e24c_footer_byte_mutation_in_url_not_approved_exit=$?
_codex_e24c_footer_byte_mutation_in_url_not_approved_output="$(cat "$_codex_e24c_footer_byte_mutation_in_url_not_approved_mock_dir/output.txt")"
run_test "codex_e24c_footer_byte_mutation_in_url_not_approved_exit_needs_revision" "2" "$_codex_e24c_footer_byte_mutation_in_url_not_approved_exit"
run_test "codex_e24c_footer_byte_mutation_in_url_not_approved_verdict" "VERDICT: ESCALATE — Codex terminal verdict matches neither an approved clean template nor the documented blocking markers" \
  "$(printf '%s\n' "$_codex_e24c_footer_byte_mutation_in_url_not_approved_output" | grep "^VERDICT:")"
rm -rf "$_codex_e24c_footer_byte_mutation_in_url_not_approved_mock_dir"
unset _codex_e24c_footer_byte_mutation_in_url_not_approved_mock_dir _codex_e24c_footer_byte_mutation_in_url_not_approved_output _codex_e24c_footer_byte_mutation_in_url_not_approved_exit
# Decision-6 verdict-site near-miss #1 of 4 (issue #1491's implementation
# plan, Codex GitHub finding `3805277351`, P2): the E3 near-miss body
# (missing "Swish!", complete real footer, SHA-pinned) present on the
# first poll. Resolves at the MAIN-LOOP verdict site. NEEDS_REVISION,
# exit 1 — never VERDICT: TIMED_OUT. Each of the four Decision-6
# verdict-site gates must be exercised by its own scenario, not inferred
# from the others: a missing/mistyped gate at any one site still lets
# this construction pass if it resolves at a different site.
_codex_footer_near_miss_main_loop_safe_fails_mock_dir="$(mktemp -d)"
printf '0\n' > "$_codex_footer_near_miss_main_loop_safe_fails_mock_dir/comment_calls"
cat > "$_codex_footer_near_miss_main_loop_safe_fails_mock_dir/gh" <<'CODEX_FOOTER_NEAR_MISS_MAIN_LOOP_SAFE_FAILS_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'face0000011234567\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":450,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    calls_file="$(dirname "$0")/comment_calls"
    calls="$(cat "$calls_file")"
    calls=$((calls + 1))
    printf '%s\n' "$calls" > "$calls_file"
    # Call 1 is the pre-trigger dedup check (stays empty). Call 2 is the
    # main poll loop's own bot-response check -- this is the ONLY call
    # that returns the near-miss body, so this scenario genuinely
    # isolates the main-loop verdict site: if main-loop's own gate is
    # broken, no LATER site (async-arrival, async-final) ever sees this
    # body again to independently rescue the correct verdict, since
    # calls 3+ return empty and the run legitimately times out instead
    # (issue #1491 implementation plan follow-up, PR #1494 review
    # finding 3808305143: the original construction returned the
    # near-miss body on every call, which let a still-correct
    # async-arrival gate silently rescue a broken main-loop gate).
    if [ "$calls" -eq 2 ]; then
      jq -nc '[{id:451,created_at:"2026-01-01T00:00:01Z",user:{login:"chatgpt-codex-connector[bot]"},body:("Codex Review: Didn'\''t find any major issues. **Reviewed commit:** `face000001` <details> <summary>ℹ️ About Codex in GitHub</summary> <br/> [Your team has set up Codex to review pull requests in this repo](https://chatgpt.com/codex/cloud/settings/general). Reviews are triggered when you - Open a pull request for review - Mark a draft as ready - Comment \"@codex review\". If Codex has suggestions, it will comment; otherwise it will react with 👍. Codex can also answer questions or update the PR. Try commenting \"@codex address that feedback\". </details>")}]'
    else
      printf '[]\n'
    fi
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_FOOTER_NEAR_MISS_MAIN_LOOP_SAFE_FAILS_GH
chmod +x "$_codex_footer_near_miss_main_loop_safe_fails_mock_dir/gh"

_codex_footer_near_miss_main_loop_safe_fails_output=""
_codex_footer_near_miss_main_loop_safe_fails_exit=0
PATH="$_codex_footer_near_miss_main_loop_safe_fails_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_footer_near_miss_main_loop_safe_fails_mock_dir/output.txt" 2>&1 || _codex_footer_near_miss_main_loop_safe_fails_exit=$?
_codex_footer_near_miss_main_loop_safe_fails_output="$(cat "$_codex_footer_near_miss_main_loop_safe_fails_mock_dir/output.txt")"
run_test "codex_footer_near_miss_main_loop_safe_fails_exit_needs_revision" "2" "$_codex_footer_near_miss_main_loop_safe_fails_exit"
run_test "codex_footer_near_miss_main_loop_safe_fails_verdict" "VERDICT: ESCALATE — Codex terminal verdict matches neither an approved clean template nor the documented blocking markers" \
  "$(printf '%s\n' "$_codex_footer_near_miss_main_loop_safe_fails_output" | grep "^VERDICT:")"
if printf '%s\n' "$_codex_footer_near_miss_main_loop_safe_fails_output" | grep -q "^INFO: bot response detected"; then
  _codex_footer_near_miss_main_loop_safe_fails_site="main_loop"
else
  _codex_footer_near_miss_main_loop_safe_fails_site="other"
fi
run_test "codex_footer_near_miss_main_loop_safe_fails_resolves_at_main_loop" "main_loop" "$_codex_footer_near_miss_main_loop_safe_fails_site"
rm -rf "$_codex_footer_near_miss_main_loop_safe_fails_mock_dir"
unset _codex_footer_near_miss_main_loop_safe_fails_mock_dir _codex_footer_near_miss_main_loop_safe_fails_output _codex_footer_near_miss_main_loop_safe_fails_exit _codex_footer_near_miss_main_loop_safe_fails_site
# Decision-6 verdict-site near-miss #2 of 4 (issue #1491's implementation
# plan, Codex GitHub finding `3805277351`, P2): the main poll loop's own
# comment fetches return empty for its entire budget; the near-miss body
# appears only on the single async-grace poll that follows. Resolves at
# the ASYNC-ARRIVAL verdict site. NEEDS_REVISION, exit 1 — never
# VERDICT: TIMED_OUT.
_codex_footer_near_miss_async_arrival_safe_fails_mock_dir="$(mktemp -d)"
printf '0\n' > "$_codex_footer_near_miss_async_arrival_safe_fails_mock_dir/comment_calls"
cat > "$_codex_footer_near_miss_async_arrival_safe_fails_mock_dir/gh" <<'CODEX_FOOTER_NEAR_MISS_ASYNC_ARRIVAL_SAFE_FAILS_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'face0000021234567\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":460,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    calls_file="$(dirname "$0")/comment_calls"
    calls="$(cat "$calls_file")"
    calls=$((calls + 1))
    printf '%s\n' "$calls" > "$calls_file"
    # Calls 1-2 are the pre-trigger dedup check and the main poll-loop's
    # bot-response check; both stay empty so execution falls through to
    # the async-arrival grace poll (call 3), which returns the near-miss
    # body directly as SHA-pinned terminal evidence. Calls 4+ return
    # empty, so this scenario genuinely isolates the async-arrival
    # verdict site rather than letting a later site (async-final)
    # independently rediscover the same body and rescue a broken
    # async-arrival gate (issue #1491 implementation plan follow-up,
    # PR #1494 review finding 3808305143).
    if [ "$calls" -eq 3 ]; then
      jq -nc '[{id:461,created_at:"2026-01-01T00:00:01Z",user:{login:"chatgpt-codex-connector[bot]"},body:("Codex Review: Didn'\''t find any major issues. **Reviewed commit:** `face000002` <details> <summary>ℹ️ About Codex in GitHub</summary> <br/> [Your team has set up Codex to review pull requests in this repo](https://chatgpt.com/codex/cloud/settings/general). Reviews are triggered when you - Open a pull request for review - Mark a draft as ready - Comment \"@codex review\". If Codex has suggestions, it will comment; otherwise it will react with 👍. Codex can also answer questions or update the PR. Try commenting \"@codex address that feedback\". </details>")}]'
    else
      printf '[]\n'
    fi
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_FOOTER_NEAR_MISS_ASYNC_ARRIVAL_SAFE_FAILS_GH
chmod +x "$_codex_footer_near_miss_async_arrival_safe_fails_mock_dir/gh"

_codex_footer_near_miss_async_arrival_safe_fails_output=""
_codex_footer_near_miss_async_arrival_safe_fails_exit=0
PATH="$_codex_footer_near_miss_async_arrival_safe_fails_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_footer_near_miss_async_arrival_safe_fails_mock_dir/output.txt" 2>&1 || _codex_footer_near_miss_async_arrival_safe_fails_exit=$?
_codex_footer_near_miss_async_arrival_safe_fails_output="$(cat "$_codex_footer_near_miss_async_arrival_safe_fails_mock_dir/output.txt")"
run_test "codex_footer_near_miss_async_arrival_safe_fails_exit_needs_revision" "2" "$_codex_footer_near_miss_async_arrival_safe_fails_exit"
run_test "codex_footer_near_miss_async_arrival_safe_fails_verdict" "VERDICT: ESCALATE — Codex terminal verdict matches neither an approved clean template nor the documented blocking markers" \
  "$(printf '%s\n' "$_codex_footer_near_miss_async_arrival_safe_fails_output" | grep "^VERDICT:")"
if printf '%s\n' "$_codex_footer_near_miss_async_arrival_safe_fails_output" | grep -q "^INFO: async-arrival bot response detected during grace period"; then
  _codex_footer_near_miss_async_arrival_safe_fails_site="async_arrival"
else
  _codex_footer_near_miss_async_arrival_safe_fails_site="other"
fi
run_test "codex_footer_near_miss_async_arrival_safe_fails_resolves_at_async_arrival" "async_arrival" "$_codex_footer_near_miss_async_arrival_safe_fails_site"
rm -rf "$_codex_footer_near_miss_async_arrival_safe_fails_mock_dir"
unset _codex_footer_near_miss_async_arrival_safe_fails_mock_dir _codex_footer_near_miss_async_arrival_safe_fails_output _codex_footer_near_miss_async_arrival_safe_fails_exit _codex_footer_near_miss_async_arrival_safe_fails_site
# Decision-6 verdict-site near-miss #3 of 4 (issue #1491's implementation
# plan, Codex GitHub finding `3805277351`, P2): the main poll loop returns
# empty; the first async-grace poll finds only a bare acknowledgement
# comment (the footer's acknowledgement sentence alone, no
# **Reviewed commit:** marker — non-terminal, so it cannot resolve the
# verdict on its own); this triggers the one-shot sleep-and-recheck, and
# the near-miss body appears only on that second check. Resolves at the
# ASYNC-FINAL verdict site. NEEDS_REVISION, exit 1 — never
# VERDICT: TIMED_OUT.
_codex_footer_near_miss_async_final_safe_fails_mock_dir="$(mktemp -d)"
printf '0\n' > "$_codex_footer_near_miss_async_final_safe_fails_mock_dir/comment_calls"
cat > "$_codex_footer_near_miss_async_final_safe_fails_mock_dir/gh" <<'CODEX_FOOTER_NEAR_MISS_ASYNC_FINAL_SAFE_FAILS_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'face0000031234567\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":470,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    calls_file="$(dirname "$0")/comment_calls"
    calls="$(cat "$calls_file")"
    calls=$((calls + 1))
    printf '%s\n' "$calls" > "$calls_file"
    # Calls 1-2 are the pre-trigger dedup check and the main poll-loop's
    # bot-response check; both stay empty. Call 3 is the async-arrival
    # grace poll: a bare, non-terminal acknowledgement comment (gated on
    # source != "review", Decision 6, so it correctly triggers the
    # sleep-and-recheck instead of safe-failing here). Call 4+ is the
    # async-final re-poll: the near-miss body, SHA-pinned terminal
    # evidence that does not reproduce CODEX_APPROVED_TEMPLATES.
    if [ "$calls" -ge 4 ]; then
      jq -nc '[{id:471,created_at:"2026-01-01T00:00:02Z",user:{login:"chatgpt-codex-connector[bot]"},body:("Codex Review: Didn'\''t find any major issues. **Reviewed commit:** `face000003` <details> <summary>ℹ️ About Codex in GitHub</summary> <br/> [Your team has set up Codex to review pull requests in this repo](https://chatgpt.com/codex/cloud/settings/general). Reviews are triggered when you - Open a pull request for review - Mark a draft as ready - Comment \"@codex review\". If Codex has suggestions, it will comment; otherwise it will react with 👍. Codex can also answer questions or update the PR. Try commenting \"@codex address that feedback\". </details>")}]'
    elif [ "$calls" -eq 3 ]; then
      jq -nc '[{id:472,created_at:"2026-01-01T00:00:01Z",user:{login:"chatgpt-codex-connector[bot]"},body:("If Codex has suggestions, it will comment; otherwise it will react with 👍. Codex can also answer questions or update the PR. Try commenting \"@codex address that feedback\".")}]'
    else
      printf '[]\n'
    fi
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_FOOTER_NEAR_MISS_ASYNC_FINAL_SAFE_FAILS_GH
chmod +x "$_codex_footer_near_miss_async_final_safe_fails_mock_dir/gh"

_codex_footer_near_miss_async_final_safe_fails_output=""
_codex_footer_near_miss_async_final_safe_fails_exit=0
PATH="$_codex_footer_near_miss_async_final_safe_fails_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_footer_near_miss_async_final_safe_fails_mock_dir/output.txt" 2>&1 || _codex_footer_near_miss_async_final_safe_fails_exit=$?
_codex_footer_near_miss_async_final_safe_fails_output="$(cat "$_codex_footer_near_miss_async_final_safe_fails_mock_dir/output.txt")"
run_test "codex_footer_near_miss_async_final_safe_fails_exit_needs_revision" "2" "$_codex_footer_near_miss_async_final_safe_fails_exit"
run_test "codex_footer_near_miss_async_final_safe_fails_verdict" "VERDICT: ESCALATE — Codex terminal verdict matches neither an approved clean template nor the documented blocking markers" \
  "$(printf '%s\n' "$_codex_footer_near_miss_async_final_safe_fails_output" | grep "^VERDICT:")"
if printf '%s\n' "$_codex_footer_near_miss_async_final_safe_fails_output" | grep -q "^INFO: final async bot response detected after acknowledgement wait"; then
  _codex_footer_near_miss_async_final_safe_fails_site="async_final"
else
  _codex_footer_near_miss_async_final_safe_fails_site="other"
fi
run_test "codex_footer_near_miss_async_final_safe_fails_resolves_at_async_final" "async_final" "$_codex_footer_near_miss_async_final_safe_fails_site"
rm -rf "$_codex_footer_near_miss_async_final_safe_fails_mock_dir"
unset _codex_footer_near_miss_async_final_safe_fails_mock_dir _codex_footer_near_miss_async_final_safe_fails_output _codex_footer_near_miss_async_final_safe_fails_exit _codex_footer_near_miss_async_final_safe_fails_site
# Decision-6 verdict-site near-miss #4 of 4 (issue #1491's implementation
# plan, Codex GitHub finding `3805277351`, P2): a thumbs-up reaction is
# present on the trigger comment from the first poll onward, and every
# comment fetch returns empty until the final check that follows the
# reaction-triggered sleep, where the near-miss body appears (as a
# current-head review, mirroring codex_async_reaction_then_late_review's
# proven mock sequencing for this same site's positive path). Resolves at
# the ASYNC-REACTION-FINAL verdict site — this scenario is the negative-
# path counterpart to codex_async_reaction_then_late_review (Group
# APPROVED). NEEDS_REVISION, exit 1 — never VERDICT: TIMED_OUT.
_codex_footer_near_miss_async_reaction_final_safe_fails_mock_dir="$(mktemp -d)"
printf '0\n' > "$_codex_footer_near_miss_async_reaction_final_safe_fails_mock_dir/review_calls"
cat > "$_codex_footer_near_miss_async_reaction_final_safe_fails_mock_dir/gh" <<'CODEX_FOOTER_NEAR_MISS_ASYNC_REACTION_FINAL_SAFE_FAILS_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'face0000041234567\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":480,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[{"content":"+1","user":{"login":"chatgpt-codex-connector[bot]"}}]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    calls_file="$(dirname "$0")/review_calls"
    calls="$(cat "$calls_file")"
    calls=$((calls + 1))
    printf '%s\n' "$calls" > "$calls_file"
    if [ "$calls" -ge 3 ]; then
      jq -nc '[{submitted_at:"2026-01-01T00:00:01Z",commit_id:"face0000041234567",user:{login:"chatgpt-codex-connector[bot]"},body:("Codex Review: Didn'\''t find any major issues. **Reviewed commit:** `face000004` <details> <summary>ℹ️ About Codex in GitHub</summary> <br/> [Your team has set up Codex to review pull requests in this repo](https://chatgpt.com/codex/cloud/settings/general). Reviews are triggered when you - Open a pull request for review - Mark a draft as ready - Comment \"@codex review\". If Codex has suggestions, it will comment; otherwise it will react with 👍. Codex can also answer questions or update the PR. Try commenting \"@codex address that feedback\". </details>")}]'
    else
      printf '[]\n'
    fi
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
CODEX_FOOTER_NEAR_MISS_ASYNC_REACTION_FINAL_SAFE_FAILS_GH
chmod +x "$_codex_footer_near_miss_async_reaction_final_safe_fails_mock_dir/gh"

_codex_footer_near_miss_async_reaction_final_safe_fails_output=""
_codex_footer_near_miss_async_reaction_final_safe_fails_exit=0
PATH="$_codex_footer_near_miss_async_reaction_final_safe_fails_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_footer_near_miss_async_reaction_final_safe_fails_mock_dir/output.txt" 2>&1 || _codex_footer_near_miss_async_reaction_final_safe_fails_exit=$?
_codex_footer_near_miss_async_reaction_final_safe_fails_output="$(cat "$_codex_footer_near_miss_async_reaction_final_safe_fails_mock_dir/output.txt")"
run_test "codex_footer_near_miss_async_reaction_final_safe_fails_exit_needs_revision" "2" "$_codex_footer_near_miss_async_reaction_final_safe_fails_exit"
run_test "codex_footer_near_miss_async_reaction_final_safe_fails_verdict" "VERDICT: ESCALATE — Codex terminal verdict matches neither an approved clean template nor the documented blocking markers" \
  "$(printf '%s\n' "$_codex_footer_near_miss_async_reaction_final_safe_fails_output" | grep "^VERDICT:")"
if printf '%s\n' "$_codex_footer_near_miss_async_reaction_final_safe_fails_output" | grep -q "^INFO: final async reaction bot response detected via PR reviews endpoint"; then
  _codex_footer_near_miss_async_reaction_final_safe_fails_site="async_reaction_final"
else
  _codex_footer_near_miss_async_reaction_final_safe_fails_site="other"
fi
run_test "codex_footer_near_miss_async_reaction_final_safe_fails_resolves_at_async_reaction_final" "async_reaction_final" "$_codex_footer_near_miss_async_reaction_final_safe_fails_site"
rm -rf "$_codex_footer_near_miss_async_reaction_final_safe_fails_mock_dir"
unset _codex_footer_near_miss_async_reaction_final_safe_fails_mock_dir _codex_footer_near_miss_async_reaction_final_safe_fails_output _codex_footer_near_miss_async_reaction_final_safe_fails_exit _codex_footer_near_miss_async_reaction_final_safe_fails_site


# ---------------------------------------------------------------------------
# Bounded flavor-slot placeholder (issue #1491 follow-up, second correction).
# The first correction (a 14-token literal alternation) was itself replaced
# before merge: 14 distinct tokens from under 50 samples — single words,
# full sentences, GitHub emoji shortcodes, inconsistent trailing punctuation
# — is LLM-generated variety, not a fixed vocabulary, and enumerating it
# would not converge (issue #1491's original complaint reappearing on a new
# axis). CODEX_APPROVED_TEMPLATES' flavor slot is now the single bounded
# placeholder `[^*`[:cntrl:]]{1,40}` — see the production script's own
# comment above CODEX_APPROVED_TEMPLATES and the implementation plan's
# Decision 2 second addendum for the full derivation of both the length
# cap and the excluded-character set. codex_e1_real_pr1489_capture_approved
# above already covers "Swish!" end to end and is unchanged; this block
# covers the remaining evidenced tokens plus the placeholder's own
# structure/length guards.
# ---------------------------------------------------------------------------
# Evidenced flavor token: 'Nice work!' (issue #1491 follow-up; approved by the bounded placeholder)
_codex_placeholder_nice_work_approved_mock_dir="$(mktemp -d)"
cat > "$_codex_placeholder_nice_work_approved_mock_dir/gh" <<'CODEX_PLACEHOLDER_NICE_WORK_APPROVED_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'fa00000011234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":701,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    jq -nc '[{id:751,created_at:"2026-01-01T00:00:01Z",user:{login:"chatgpt-codex-connector[bot]"},body:("Codex Review: Didn'\''t find any major issues. Nice work! **Reviewed commit:** `fa0000001` <details> <summary>ℹ️ About Codex in GitHub</summary> <br/> [Your team has set up Codex to review pull requests in this repo](https://chatgpt.com/codex/cloud/settings/general). Reviews are triggered when you - Open a pull request for review - Mark a draft as ready - Comment \"@codex review\". If Codex has suggestions, it will comment; otherwise it will react with 👍. Codex can also answer questions or update the PR. Try commenting \"@codex address that feedback\". </details>")}]'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_PLACEHOLDER_NICE_WORK_APPROVED_GH
chmod +x "$_codex_placeholder_nice_work_approved_mock_dir/gh"

_codex_placeholder_nice_work_approved_output=""
_codex_placeholder_nice_work_approved_exit=0
PATH="$_codex_placeholder_nice_work_approved_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_placeholder_nice_work_approved_mock_dir/output.txt" 2>&1 || _codex_placeholder_nice_work_approved_exit=$?
_codex_placeholder_nice_work_approved_output="$(cat "$_codex_placeholder_nice_work_approved_mock_dir/output.txt")"
run_test "codex_placeholder_nice_work_approved_exit_clean" "0" "$_codex_placeholder_nice_work_approved_exit"
run_test "codex_placeholder_nice_work_approved_verdict" "VERDICT: APPROVED" \
  "$(printf '%s\n' "$_codex_placeholder_nice_work_approved_output" | grep "^VERDICT:")"
rm -rf "$_codex_placeholder_nice_work_approved_mock_dir"
unset _codex_placeholder_nice_work_approved_mock_dir _codex_placeholder_nice_work_approved_output _codex_placeholder_nice_work_approved_exit

# Evidenced flavor token: "Chef's kiss." (issue #1491 follow-up; approved by the bounded placeholder)
_codex_placeholder_chefs_kiss_approved_mock_dir="$(mktemp -d)"
cat > "$_codex_placeholder_chefs_kiss_approved_mock_dir/gh" <<'CODEX_PLACEHOLDER_CHEFS_KISS_APPROVED_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'fa00000021234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":702,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    jq -nc '[{id:752,created_at:"2026-01-01T00:00:01Z",user:{login:"chatgpt-codex-connector[bot]"},body:("Codex Review: Didn'\''t find any major issues. Chef'\''s kiss. **Reviewed commit:** `fa0000002` <details> <summary>ℹ️ About Codex in GitHub</summary> <br/> [Your team has set up Codex to review pull requests in this repo](https://chatgpt.com/codex/cloud/settings/general). Reviews are triggered when you - Open a pull request for review - Mark a draft as ready - Comment \"@codex review\". If Codex has suggestions, it will comment; otherwise it will react with 👍. Codex can also answer questions or update the PR. Try commenting \"@codex address that feedback\". </details>")}]'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_PLACEHOLDER_CHEFS_KISS_APPROVED_GH
chmod +x "$_codex_placeholder_chefs_kiss_approved_mock_dir/gh"

_codex_placeholder_chefs_kiss_approved_output=""
_codex_placeholder_chefs_kiss_approved_exit=0
PATH="$_codex_placeholder_chefs_kiss_approved_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_placeholder_chefs_kiss_approved_mock_dir/output.txt" 2>&1 || _codex_placeholder_chefs_kiss_approved_exit=$?
_codex_placeholder_chefs_kiss_approved_output="$(cat "$_codex_placeholder_chefs_kiss_approved_mock_dir/output.txt")"
run_test "codex_placeholder_chefs_kiss_approved_exit_clean" "0" "$_codex_placeholder_chefs_kiss_approved_exit"
run_test "codex_placeholder_chefs_kiss_approved_verdict" "VERDICT: APPROVED" \
  "$(printf '%s\n' "$_codex_placeholder_chefs_kiss_approved_output" | grep "^VERDICT:")"
rm -rf "$_codex_placeholder_chefs_kiss_approved_mock_dir"
unset _codex_placeholder_chefs_kiss_approved_mock_dir _codex_placeholder_chefs_kiss_approved_output _codex_placeholder_chefs_kiss_approved_exit

# Evidenced flavor token: "You're on a roll." (issue #1491 follow-up; approved by the bounded placeholder)
_codex_placeholder_youre_on_a_roll_approved_mock_dir="$(mktemp -d)"
cat > "$_codex_placeholder_youre_on_a_roll_approved_mock_dir/gh" <<'CODEX_PLACEHOLDER_YOURE_ON_A_ROLL_APPROVED_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'fa00000031234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":703,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    jq -nc '[{id:753,created_at:"2026-01-01T00:00:01Z",user:{login:"chatgpt-codex-connector[bot]"},body:("Codex Review: Didn'\''t find any major issues. You'\''re on a roll. **Reviewed commit:** `fa0000003` <details> <summary>ℹ️ About Codex in GitHub</summary> <br/> [Your team has set up Codex to review pull requests in this repo](https://chatgpt.com/codex/cloud/settings/general). Reviews are triggered when you - Open a pull request for review - Mark a draft as ready - Comment \"@codex review\". If Codex has suggestions, it will comment; otherwise it will react with 👍. Codex can also answer questions or update the PR. Try commenting \"@codex address that feedback\". </details>")}]'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_PLACEHOLDER_YOURE_ON_A_ROLL_APPROVED_GH
chmod +x "$_codex_placeholder_youre_on_a_roll_approved_mock_dir/gh"

_codex_placeholder_youre_on_a_roll_approved_output=""
_codex_placeholder_youre_on_a_roll_approved_exit=0
PATH="$_codex_placeholder_youre_on_a_roll_approved_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_placeholder_youre_on_a_roll_approved_mock_dir/output.txt" 2>&1 || _codex_placeholder_youre_on_a_roll_approved_exit=$?
_codex_placeholder_youre_on_a_roll_approved_output="$(cat "$_codex_placeholder_youre_on_a_roll_approved_mock_dir/output.txt")"
run_test "codex_placeholder_youre_on_a_roll_approved_exit_clean" "0" "$_codex_placeholder_youre_on_a_roll_approved_exit"
run_test "codex_placeholder_youre_on_a_roll_approved_verdict" "VERDICT: APPROVED" \
  "$(printf '%s\n' "$_codex_placeholder_youre_on_a_roll_approved_output" | grep "^VERDICT:")"
rm -rf "$_codex_placeholder_youre_on_a_roll_approved_mock_dir"
unset _codex_placeholder_youre_on_a_roll_approved_mock_dir _codex_placeholder_youre_on_a_roll_approved_output _codex_placeholder_youre_on_a_roll_approved_exit

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "Tests: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
