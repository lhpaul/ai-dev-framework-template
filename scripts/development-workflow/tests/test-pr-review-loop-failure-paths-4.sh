#!/usr/bin/env bash
# test-pr-review-loop-failure-paths-4.sh — pr-review-loop.sh harness: Area 13
# (PR #801 failure paths), part 4 of 4.
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
#   Area 13: PR #801 reviewer-loop failure paths (part 4 of 4)
#
# Usage: bash scripts/development-workflow/tests/test-pr-review-loop-failure-paths-4.sh [--area <name>]... [--list-areas]
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
# Area 13 (continued): PR #801 reviewer-loop failure paths, part 4 of 4
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 13: PR #801 reviewer-loop failure paths (part 4 of 4) ==="

# Evidenced flavor token: ':tada:' (issue #1491 follow-up; approved by the bounded placeholder)
_codex_placeholder_tada_approved_mock_dir="$(mktemp -d)"
cat > "$_codex_placeholder_tada_approved_mock_dir/gh" <<'CODEX_PLACEHOLDER_TADA_APPROVED_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'fa00000041234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":704,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    jq -nc '[{id:754,created_at:"2026-01-01T00:00:01Z",user:{login:"chatgpt-codex-connector[bot]"},body:("Codex Review: Didn'\''t find any major issues. :tada: **Reviewed commit:** `fa0000004` <details> <summary>ℹ️ About Codex in GitHub</summary> <br/> [Your team has set up Codex to review pull requests in this repo](https://chatgpt.com/codex/cloud/settings/general). Reviews are triggered when you - Open a pull request for review - Mark a draft as ready - Comment \"@codex review\". If Codex has suggestions, it will comment; otherwise it will react with 👍. Codex can also answer questions or update the PR. Try commenting \"@codex address that feedback\". </details>")}]'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_PLACEHOLDER_TADA_APPROVED_GH
chmod +x "$_codex_placeholder_tada_approved_mock_dir/gh"

_codex_placeholder_tada_approved_output=""
_codex_placeholder_tada_approved_exit=0
PATH="$_codex_placeholder_tada_approved_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_placeholder_tada_approved_mock_dir/output.txt" 2>&1 || _codex_placeholder_tada_approved_exit=$?
_codex_placeholder_tada_approved_output="$(cat "$_codex_placeholder_tada_approved_mock_dir/output.txt")"
run_test "codex_placeholder_tada_approved_exit_clean" "0" "$_codex_placeholder_tada_approved_exit"
run_test "codex_placeholder_tada_approved_verdict" "VERDICT: APPROVED" \
  "$(printf '%s\n' "$_codex_placeholder_tada_approved_output" | grep "^VERDICT:")"
rm -rf "$_codex_placeholder_tada_approved_mock_dir"
unset _codex_placeholder_tada_approved_mock_dir _codex_placeholder_tada_approved_output _codex_placeholder_tada_approved_exit

# Evidenced flavor token: 'Another round soon, please!' (issue #1491 follow-up; approved by the bounded placeholder)
_codex_placeholder_another_round_soon_please_approved_mock_dir="$(mktemp -d)"
cat > "$_codex_placeholder_another_round_soon_please_approved_mock_dir/gh" <<'CODEX_PLACEHOLDER_ANOTHER_ROUND_SOON_PLEASE_APPROVED_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'fa00000051234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":705,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    jq -nc '[{id:755,created_at:"2026-01-01T00:00:01Z",user:{login:"chatgpt-codex-connector[bot]"},body:("Codex Review: Didn'\''t find any major issues. Another round soon, please! **Reviewed commit:** `fa0000005` <details> <summary>ℹ️ About Codex in GitHub</summary> <br/> [Your team has set up Codex to review pull requests in this repo](https://chatgpt.com/codex/cloud/settings/general). Reviews are triggered when you - Open a pull request for review - Mark a draft as ready - Comment \"@codex review\". If Codex has suggestions, it will comment; otherwise it will react with 👍. Codex can also answer questions or update the PR. Try commenting \"@codex address that feedback\". </details>")}]'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_PLACEHOLDER_ANOTHER_ROUND_SOON_PLEASE_APPROVED_GH
chmod +x "$_codex_placeholder_another_round_soon_please_approved_mock_dir/gh"

_codex_placeholder_another_round_soon_please_approved_output=""
_codex_placeholder_another_round_soon_please_approved_exit=0
PATH="$_codex_placeholder_another_round_soon_please_approved_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_placeholder_another_round_soon_please_approved_mock_dir/output.txt" 2>&1 || _codex_placeholder_another_round_soon_please_approved_exit=$?
_codex_placeholder_another_round_soon_please_approved_output="$(cat "$_codex_placeholder_another_round_soon_please_approved_mock_dir/output.txt")"
run_test "codex_placeholder_another_round_soon_please_approved_exit_clean" "0" "$_codex_placeholder_another_round_soon_please_approved_exit"
run_test "codex_placeholder_another_round_soon_please_approved_verdict" "VERDICT: APPROVED" \
  "$(printf '%s\n' "$_codex_placeholder_another_round_soon_please_approved_output" | grep "^VERDICT:")"
rm -rf "$_codex_placeholder_another_round_soon_please_approved_mock_dir"
unset _codex_placeholder_another_round_soon_please_approved_mock_dir _codex_placeholder_another_round_soon_please_approved_output _codex_placeholder_another_round_soon_please_approved_exit

# Evidenced flavor token: ':+1:' (issue #1491 follow-up; approved by the bounded placeholder)
_codex_placeholder_plus_one_approved_mock_dir="$(mktemp -d)"
cat > "$_codex_placeholder_plus_one_approved_mock_dir/gh" <<'CODEX_PLACEHOLDER_PLUS_ONE_APPROVED_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'fa00000061234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":706,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    jq -nc '[{id:756,created_at:"2026-01-01T00:00:01Z",user:{login:"chatgpt-codex-connector[bot]"},body:("Codex Review: Didn'\''t find any major issues. :+1: **Reviewed commit:** `fa0000006` <details> <summary>ℹ️ About Codex in GitHub</summary> <br/> [Your team has set up Codex to review pull requests in this repo](https://chatgpt.com/codex/cloud/settings/general). Reviews are triggered when you - Open a pull request for review - Mark a draft as ready - Comment \"@codex review\". If Codex has suggestions, it will comment; otherwise it will react with 👍. Codex can also answer questions or update the PR. Try commenting \"@codex address that feedback\". </details>")}]'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_PLACEHOLDER_PLUS_ONE_APPROVED_GH
chmod +x "$_codex_placeholder_plus_one_approved_mock_dir/gh"

_codex_placeholder_plus_one_approved_output=""
_codex_placeholder_plus_one_approved_exit=0
PATH="$_codex_placeholder_plus_one_approved_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_placeholder_plus_one_approved_mock_dir/output.txt" 2>&1 || _codex_placeholder_plus_one_approved_exit=$?
_codex_placeholder_plus_one_approved_output="$(cat "$_codex_placeholder_plus_one_approved_mock_dir/output.txt")"
run_test "codex_placeholder_plus_one_approved_exit_clean" "0" "$_codex_placeholder_plus_one_approved_exit"
run_test "codex_placeholder_plus_one_approved_verdict" "VERDICT: APPROVED" \
  "$(printf '%s\n' "$_codex_placeholder_plus_one_approved_output" | grep "^VERDICT:")"
rm -rf "$_codex_placeholder_plus_one_approved_mock_dir"
unset _codex_placeholder_plus_one_approved_mock_dir _codex_placeholder_plus_one_approved_output _codex_placeholder_plus_one_approved_exit

# Evidenced flavor token: 'Bravo.' (issue #1491 follow-up; approved by the bounded placeholder)
_codex_placeholder_bravo_approved_mock_dir="$(mktemp -d)"
cat > "$_codex_placeholder_bravo_approved_mock_dir/gh" <<'CODEX_PLACEHOLDER_BRAVO_APPROVED_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'fa00000071234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":707,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    jq -nc '[{id:757,created_at:"2026-01-01T00:00:01Z",user:{login:"chatgpt-codex-connector[bot]"},body:("Codex Review: Didn'\''t find any major issues. Bravo. **Reviewed commit:** `fa0000007` <details> <summary>ℹ️ About Codex in GitHub</summary> <br/> [Your team has set up Codex to review pull requests in this repo](https://chatgpt.com/codex/cloud/settings/general). Reviews are triggered when you - Open a pull request for review - Mark a draft as ready - Comment \"@codex review\". If Codex has suggestions, it will comment; otherwise it will react with 👍. Codex can also answer questions or update the PR. Try commenting \"@codex address that feedback\". </details>")}]'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_PLACEHOLDER_BRAVO_APPROVED_GH
chmod +x "$_codex_placeholder_bravo_approved_mock_dir/gh"

_codex_placeholder_bravo_approved_output=""
_codex_placeholder_bravo_approved_exit=0
PATH="$_codex_placeholder_bravo_approved_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_placeholder_bravo_approved_mock_dir/output.txt" 2>&1 || _codex_placeholder_bravo_approved_exit=$?
_codex_placeholder_bravo_approved_output="$(cat "$_codex_placeholder_bravo_approved_mock_dir/output.txt")"
run_test "codex_placeholder_bravo_approved_exit_clean" "0" "$_codex_placeholder_bravo_approved_exit"
run_test "codex_placeholder_bravo_approved_verdict" "VERDICT: APPROVED" \
  "$(printf '%s\n' "$_codex_placeholder_bravo_approved_output" | grep "^VERDICT:")"
rm -rf "$_codex_placeholder_bravo_approved_mock_dir"
unset _codex_placeholder_bravo_approved_mock_dir _codex_placeholder_bravo_approved_output _codex_placeholder_bravo_approved_exit

# Evidenced flavor token: 'Keep it up!' (issue #1491 follow-up; approved by the bounded placeholder)
_codex_placeholder_keep_it_up_approved_mock_dir="$(mktemp -d)"
cat > "$_codex_placeholder_keep_it_up_approved_mock_dir/gh" <<'CODEX_PLACEHOLDER_KEEP_IT_UP_APPROVED_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'fa00000081234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":708,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    jq -nc '[{id:758,created_at:"2026-01-01T00:00:01Z",user:{login:"chatgpt-codex-connector[bot]"},body:("Codex Review: Didn'\''t find any major issues. Keep it up! **Reviewed commit:** `fa0000008` <details> <summary>ℹ️ About Codex in GitHub</summary> <br/> [Your team has set up Codex to review pull requests in this repo](https://chatgpt.com/codex/cloud/settings/general). Reviews are triggered when you - Open a pull request for review - Mark a draft as ready - Comment \"@codex review\". If Codex has suggestions, it will comment; otherwise it will react with 👍. Codex can also answer questions or update the PR. Try commenting \"@codex address that feedback\". </details>")}]'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_PLACEHOLDER_KEEP_IT_UP_APPROVED_GH
chmod +x "$_codex_placeholder_keep_it_up_approved_mock_dir/gh"

_codex_placeholder_keep_it_up_approved_output=""
_codex_placeholder_keep_it_up_approved_exit=0
PATH="$_codex_placeholder_keep_it_up_approved_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_placeholder_keep_it_up_approved_mock_dir/output.txt" 2>&1 || _codex_placeholder_keep_it_up_approved_exit=$?
_codex_placeholder_keep_it_up_approved_output="$(cat "$_codex_placeholder_keep_it_up_approved_mock_dir/output.txt")"
run_test "codex_placeholder_keep_it_up_approved_exit_clean" "0" "$_codex_placeholder_keep_it_up_approved_exit"
run_test "codex_placeholder_keep_it_up_approved_verdict" "VERDICT: APPROVED" \
  "$(printf '%s\n' "$_codex_placeholder_keep_it_up_approved_output" | grep "^VERDICT:")"
rm -rf "$_codex_placeholder_keep_it_up_approved_mock_dir"
unset _codex_placeholder_keep_it_up_approved_mock_dir _codex_placeholder_keep_it_up_approved_output _codex_placeholder_keep_it_up_approved_exit

# Evidenced flavor token: 'Delightful!' (issue #1491 follow-up; approved by the bounded placeholder)
_codex_placeholder_delightful_approved_mock_dir="$(mktemp -d)"
cat > "$_codex_placeholder_delightful_approved_mock_dir/gh" <<'CODEX_PLACEHOLDER_DELIGHTFUL_APPROVED_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'fa00000091234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":709,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    jq -nc '[{id:759,created_at:"2026-01-01T00:00:01Z",user:{login:"chatgpt-codex-connector[bot]"},body:("Codex Review: Didn'\''t find any major issues. Delightful! **Reviewed commit:** `fa0000009` <details> <summary>ℹ️ About Codex in GitHub</summary> <br/> [Your team has set up Codex to review pull requests in this repo](https://chatgpt.com/codex/cloud/settings/general). Reviews are triggered when you - Open a pull request for review - Mark a draft as ready - Comment \"@codex review\". If Codex has suggestions, it will comment; otherwise it will react with 👍. Codex can also answer questions or update the PR. Try commenting \"@codex address that feedback\". </details>")}]'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_PLACEHOLDER_DELIGHTFUL_APPROVED_GH
chmod +x "$_codex_placeholder_delightful_approved_mock_dir/gh"

_codex_placeholder_delightful_approved_output=""
_codex_placeholder_delightful_approved_exit=0
PATH="$_codex_placeholder_delightful_approved_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_placeholder_delightful_approved_mock_dir/output.txt" 2>&1 || _codex_placeholder_delightful_approved_exit=$?
_codex_placeholder_delightful_approved_output="$(cat "$_codex_placeholder_delightful_approved_mock_dir/output.txt")"
run_test "codex_placeholder_delightful_approved_exit_clean" "0" "$_codex_placeholder_delightful_approved_exit"
run_test "codex_placeholder_delightful_approved_verdict" "VERDICT: APPROVED" \
  "$(printf '%s\n' "$_codex_placeholder_delightful_approved_output" | grep "^VERDICT:")"
rm -rf "$_codex_placeholder_delightful_approved_mock_dir"
unset _codex_placeholder_delightful_approved_mock_dir _codex_placeholder_delightful_approved_output _codex_placeholder_delightful_approved_exit

# Evidenced flavor token: 'Keep them coming!' (issue #1491 follow-up; approved by the bounded placeholder)
_codex_placeholder_keep_them_coming_approved_mock_dir="$(mktemp -d)"
cat > "$_codex_placeholder_keep_them_coming_approved_mock_dir/gh" <<'CODEX_PLACEHOLDER_KEEP_THEM_COMING_APPROVED_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'fa000000a1234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":710,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    jq -nc '[{id:760,created_at:"2026-01-01T00:00:01Z",user:{login:"chatgpt-codex-connector[bot]"},body:("Codex Review: Didn'\''t find any major issues. Keep them coming! **Reviewed commit:** `fa000000a` <details> <summary>ℹ️ About Codex in GitHub</summary> <br/> [Your team has set up Codex to review pull requests in this repo](https://chatgpt.com/codex/cloud/settings/general). Reviews are triggered when you - Open a pull request for review - Mark a draft as ready - Comment \"@codex review\". If Codex has suggestions, it will comment; otherwise it will react with 👍. Codex can also answer questions or update the PR. Try commenting \"@codex address that feedback\". </details>")}]'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_PLACEHOLDER_KEEP_THEM_COMING_APPROVED_GH
chmod +x "$_codex_placeholder_keep_them_coming_approved_mock_dir/gh"

_codex_placeholder_keep_them_coming_approved_output=""
_codex_placeholder_keep_them_coming_approved_exit=0
PATH="$_codex_placeholder_keep_them_coming_approved_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_placeholder_keep_them_coming_approved_mock_dir/output.txt" 2>&1 || _codex_placeholder_keep_them_coming_approved_exit=$?
_codex_placeholder_keep_them_coming_approved_output="$(cat "$_codex_placeholder_keep_them_coming_approved_mock_dir/output.txt")"
run_test "codex_placeholder_keep_them_coming_approved_exit_clean" "0" "$_codex_placeholder_keep_them_coming_approved_exit"
run_test "codex_placeholder_keep_them_coming_approved_verdict" "VERDICT: APPROVED" \
  "$(printf '%s\n' "$_codex_placeholder_keep_them_coming_approved_output" | grep "^VERDICT:")"
rm -rf "$_codex_placeholder_keep_them_coming_approved_mock_dir"
unset _codex_placeholder_keep_them_coming_approved_mock_dir _codex_placeholder_keep_them_coming_approved_output _codex_placeholder_keep_them_coming_approved_exit

# Evidenced flavor token: "Can't wait for the next one!" (issue #1491 follow-up; approved by the bounded placeholder)
_codex_placeholder_cant_wait_for_next_one_approved_mock_dir="$(mktemp -d)"
cat > "$_codex_placeholder_cant_wait_for_next_one_approved_mock_dir/gh" <<'CODEX_PLACEHOLDER_CANT_WAIT_FOR_NEXT_ONE_APPROVED_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'fa000000b1234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":711,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    jq -nc '[{id:761,created_at:"2026-01-01T00:00:01Z",user:{login:"chatgpt-codex-connector[bot]"},body:("Codex Review: Didn'\''t find any major issues. Can'\''t wait for the next one! **Reviewed commit:** `fa000000b` <details> <summary>ℹ️ About Codex in GitHub</summary> <br/> [Your team has set up Codex to review pull requests in this repo](https://chatgpt.com/codex/cloud/settings/general). Reviews are triggered when you - Open a pull request for review - Mark a draft as ready - Comment \"@codex review\". If Codex has suggestions, it will comment; otherwise it will react with 👍. Codex can also answer questions or update the PR. Try commenting \"@codex address that feedback\". </details>")}]'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_PLACEHOLDER_CANT_WAIT_FOR_NEXT_ONE_APPROVED_GH
chmod +x "$_codex_placeholder_cant_wait_for_next_one_approved_mock_dir/gh"

_codex_placeholder_cant_wait_for_next_one_approved_output=""
_codex_placeholder_cant_wait_for_next_one_approved_exit=0
PATH="$_codex_placeholder_cant_wait_for_next_one_approved_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_placeholder_cant_wait_for_next_one_approved_mock_dir/output.txt" 2>&1 || _codex_placeholder_cant_wait_for_next_one_approved_exit=$?
_codex_placeholder_cant_wait_for_next_one_approved_output="$(cat "$_codex_placeholder_cant_wait_for_next_one_approved_mock_dir/output.txt")"
run_test "codex_placeholder_cant_wait_for_next_one_approved_exit_clean" "0" "$_codex_placeholder_cant_wait_for_next_one_approved_exit"
run_test "codex_placeholder_cant_wait_for_next_one_approved_verdict" "VERDICT: APPROVED" \
  "$(printf '%s\n' "$_codex_placeholder_cant_wait_for_next_one_approved_output" | grep "^VERDICT:")"
rm -rf "$_codex_placeholder_cant_wait_for_next_one_approved_mock_dir"
unset _codex_placeholder_cant_wait_for_next_one_approved_mock_dir _codex_placeholder_cant_wait_for_next_one_approved_output _codex_placeholder_cant_wait_for_next_one_approved_exit

# Evidenced flavor token: 'More of your lovely PRs please.' (issue #1491 follow-up; approved by the bounded placeholder)
_codex_placeholder_more_lovely_prs_please_approved_mock_dir="$(mktemp -d)"
cat > "$_codex_placeholder_more_lovely_prs_please_approved_mock_dir/gh" <<'CODEX_PLACEHOLDER_MORE_LOVELY_PRS_PLEASE_APPROVED_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'fa000000c1234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":712,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    jq -nc '[{id:762,created_at:"2026-01-01T00:00:01Z",user:{login:"chatgpt-codex-connector[bot]"},body:("Codex Review: Didn'\''t find any major issues. More of your lovely PRs please. **Reviewed commit:** `fa000000c` <details> <summary>ℹ️ About Codex in GitHub</summary> <br/> [Your team has set up Codex to review pull requests in this repo](https://chatgpt.com/codex/cloud/settings/general). Reviews are triggered when you - Open a pull request for review - Mark a draft as ready - Comment \"@codex review\". If Codex has suggestions, it will comment; otherwise it will react with 👍. Codex can also answer questions or update the PR. Try commenting \"@codex address that feedback\". </details>")}]'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_PLACEHOLDER_MORE_LOVELY_PRS_PLEASE_APPROVED_GH
chmod +x "$_codex_placeholder_more_lovely_prs_please_approved_mock_dir/gh"

_codex_placeholder_more_lovely_prs_please_approved_output=""
_codex_placeholder_more_lovely_prs_please_approved_exit=0
PATH="$_codex_placeholder_more_lovely_prs_please_approved_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_placeholder_more_lovely_prs_please_approved_mock_dir/output.txt" 2>&1 || _codex_placeholder_more_lovely_prs_please_approved_exit=$?
_codex_placeholder_more_lovely_prs_please_approved_output="$(cat "$_codex_placeholder_more_lovely_prs_please_approved_mock_dir/output.txt")"
run_test "codex_placeholder_more_lovely_prs_please_approved_exit_clean" "0" "$_codex_placeholder_more_lovely_prs_please_approved_exit"
run_test "codex_placeholder_more_lovely_prs_please_approved_verdict" "VERDICT: APPROVED" \
  "$(printf '%s\n' "$_codex_placeholder_more_lovely_prs_please_approved_output" | grep "^VERDICT:")"
rm -rf "$_codex_placeholder_more_lovely_prs_please_approved_mock_dir"
unset _codex_placeholder_more_lovely_prs_please_approved_mock_dir _codex_placeholder_more_lovely_prs_please_approved_output _codex_placeholder_more_lovely_prs_please_approved_exit

# Evidenced flavor token: ":rocket:" — the real, live PR #1494 root comment
# capture (comment id 5333550055, 2026-08-18) that falsified the original
# single-literal assumption. Verbatim, including its real footer, matching
# codex_e1_real_pr1489_capture_approved's real-capture style.
_codex_placeholder_rocket_real_pr1494_capture_approved_mock_dir="$(mktemp -d)"
cat > "$_codex_placeholder_rocket_real_pr1494_capture_approved_mock_dir/gh" <<'CODEX_PLACEHOLDER_ROCKET_REAL_PR1494_CAPTURE_APPROVED_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'a2a20e7b4836cfb5d20b75e39e01447757434e34\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":799,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    jq -nc '[{id:798,created_at:"2026-01-01T00:00:01Z",user:{login:"chatgpt-codex-connector[bot]"},body:("Codex Review: Didn'\''t find any major issues. :rocket:

**Reviewed commit:** `a2a20e7b48`

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
CODEX_PLACEHOLDER_ROCKET_REAL_PR1494_CAPTURE_APPROVED_GH
chmod +x "$_codex_placeholder_rocket_real_pr1494_capture_approved_mock_dir/gh"

_codex_placeholder_rocket_real_pr1494_capture_approved_output=""
_codex_placeholder_rocket_real_pr1494_capture_approved_exit=0
PATH="$_codex_placeholder_rocket_real_pr1494_capture_approved_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_placeholder_rocket_real_pr1494_capture_approved_mock_dir/output.txt" 2>&1 || _codex_placeholder_rocket_real_pr1494_capture_approved_exit=$?
_codex_placeholder_rocket_real_pr1494_capture_approved_output="$(cat "$_codex_placeholder_rocket_real_pr1494_capture_approved_mock_dir/output.txt")"
run_test "codex_placeholder_rocket_real_pr1494_capture_approved_exit_clean" "0" "$_codex_placeholder_rocket_real_pr1494_capture_approved_exit"
run_test "codex_placeholder_rocket_real_pr1494_capture_approved_verdict" "VERDICT: APPROVED" \
  "$(printf '%s\n' "$_codex_placeholder_rocket_real_pr1494_capture_approved_output" | grep "^VERDICT:")"
rm -rf "$_codex_placeholder_rocket_real_pr1494_capture_approved_mock_dir"
unset _codex_placeholder_rocket_real_pr1494_capture_approved_mock_dir _codex_placeholder_rocket_real_pr1494_capture_approved_output _codex_placeholder_rocket_real_pr1494_capture_approved_exit

# Behavior change (the whole point of this correction): a previously
# unevidenced flavor phrase now APPROVES, because the flavor slot is a
# bounded placeholder, not a closed enumeration. Proves the design change
# directly rather than asserting it.
_codex_placeholder_unevidenced_flavor_now_approved_mock_dir="$(mktemp -d)"
cat > "$_codex_placeholder_unevidenced_flavor_now_approved_mock_dir/gh" <<'CODEX_PLACEHOLDER_UNEVIDENCED_FLAVOR_NOW_APPROVED_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'fa000000d1234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":713,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    jq -nc '[{id:763,created_at:"2026-01-01T00:00:01Z",user:{login:"chatgpt-codex-connector[bot]"},body:("Codex Review: Didn'\''t find any major issues. Fantastic job! **Reviewed commit:** `fa000000d` <details> <summary>ℹ️ About Codex in GitHub</summary> <br/> [Your team has set up Codex to review pull requests in this repo](https://chatgpt.com/codex/cloud/settings/general). Reviews are triggered when you - Open a pull request for review - Mark a draft as ready - Comment \"@codex review\". If Codex has suggestions, it will comment; otherwise it will react with 👍. Codex can also answer questions or update the PR. Try commenting \"@codex address that feedback\". </details>")}]'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_PLACEHOLDER_UNEVIDENCED_FLAVOR_NOW_APPROVED_GH
chmod +x "$_codex_placeholder_unevidenced_flavor_now_approved_mock_dir/gh"

_codex_placeholder_unevidenced_flavor_now_approved_output=""
_codex_placeholder_unevidenced_flavor_now_approved_exit=0
PATH="$_codex_placeholder_unevidenced_flavor_now_approved_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_placeholder_unevidenced_flavor_now_approved_mock_dir/output.txt" 2>&1 || _codex_placeholder_unevidenced_flavor_now_approved_exit=$?
_codex_placeholder_unevidenced_flavor_now_approved_output="$(cat "$_codex_placeholder_unevidenced_flavor_now_approved_mock_dir/output.txt")"
run_test "codex_placeholder_unevidenced_flavor_now_approved_exit_clean" "0" "$_codex_placeholder_unevidenced_flavor_now_approved_exit"
run_test "codex_placeholder_unevidenced_flavor_now_approved_verdict" "VERDICT: APPROVED" \
  "$(printf '%s\n' "$_codex_placeholder_unevidenced_flavor_now_approved_output" | grep "^VERDICT:")"
rm -rf "$_codex_placeholder_unevidenced_flavor_now_approved_mock_dir"
unset _codex_placeholder_unevidenced_flavor_now_approved_mock_dir _codex_placeholder_unevidenced_flavor_now_approved_output _codex_placeholder_unevidenced_flavor_now_approved_exit

# Boundary: a flavor slot of exactly 40 characters (the cap, inclusive)
# still APPROVES — confirms the upper bound is inclusive, not an off-by-one
# exclusion, matching the SHA field's own inclusive-upper-bound precedent
# (codex_e7_full_length_sha_approved).
_codex_placeholder_exactly_cap_length_approved_mock_dir="$(mktemp -d)"
cat > "$_codex_placeholder_exactly_cap_length_approved_mock_dir/gh" <<'CODEX_PLACEHOLDER_EXACTLY_CAP_LENGTH_APPROVED_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'fa000000e1234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":714,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    jq -nc '[{id:764,created_at:"2026-01-01T00:00:01Z",user:{login:"chatgpt-codex-connector[bot]"},body:("Codex Review: Didn'\''t find any major issues. xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx **Reviewed commit:** `fa000000e` <details> <summary>ℹ️ About Codex in GitHub</summary> <br/> [Your team has set up Codex to review pull requests in this repo](https://chatgpt.com/codex/cloud/settings/general). Reviews are triggered when you - Open a pull request for review - Mark a draft as ready - Comment \"@codex review\". If Codex has suggestions, it will comment; otherwise it will react with 👍. Codex can also answer questions or update the PR. Try commenting \"@codex address that feedback\". </details>")}]'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_PLACEHOLDER_EXACTLY_CAP_LENGTH_APPROVED_GH
chmod +x "$_codex_placeholder_exactly_cap_length_approved_mock_dir/gh"

_codex_placeholder_exactly_cap_length_approved_output=""
_codex_placeholder_exactly_cap_length_approved_exit=0
PATH="$_codex_placeholder_exactly_cap_length_approved_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_placeholder_exactly_cap_length_approved_mock_dir/output.txt" 2>&1 || _codex_placeholder_exactly_cap_length_approved_exit=$?
_codex_placeholder_exactly_cap_length_approved_output="$(cat "$_codex_placeholder_exactly_cap_length_approved_mock_dir/output.txt")"
run_test "codex_placeholder_exactly_cap_length_approved_exit_clean" "0" "$_codex_placeholder_exactly_cap_length_approved_exit"
run_test "codex_placeholder_exactly_cap_length_approved_verdict" "VERDICT: APPROVED" \
  "$(printf '%s\n' "$_codex_placeholder_exactly_cap_length_approved_output" | grep "^VERDICT:")"
rm -rf "$_codex_placeholder_exactly_cap_length_approved_mock_dir"
unset _codex_placeholder_exactly_cap_length_approved_mock_dir _codex_placeholder_exactly_cap_length_approved_output _codex_placeholder_exactly_cap_length_approved_exit

# Structure/length guard: a flavor slot of 41 characters (one past the cap)
# safe-fails. Confirms the length cap is enforced, not merely documented.
_codex_placeholder_exceeds_length_cap_not_approved_mock_dir="$(mktemp -d)"
cat > "$_codex_placeholder_exceeds_length_cap_not_approved_mock_dir/gh" <<'CODEX_PLACEHOLDER_EXCEEDS_LENGTH_CAP_NOT_APPROVED_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'fa000000f1234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":715,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    jq -nc '[{id:765,created_at:"2026-01-01T00:00:01Z",user:{login:"chatgpt-codex-connector[bot]"},body:("Codex Review: Didn'\''t find any major issues. xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx **Reviewed commit:** `fa000000f` <details> <summary>ℹ️ About Codex in GitHub</summary> <br/> [Your team has set up Codex to review pull requests in this repo](https://chatgpt.com/codex/cloud/settings/general). Reviews are triggered when you - Open a pull request for review - Mark a draft as ready - Comment \"@codex review\". If Codex has suggestions, it will comment; otherwise it will react with 👍. Codex can also answer questions or update the PR. Try commenting \"@codex address that feedback\". </details>")}]'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_PLACEHOLDER_EXCEEDS_LENGTH_CAP_NOT_APPROVED_GH
chmod +x "$_codex_placeholder_exceeds_length_cap_not_approved_mock_dir/gh"

_codex_placeholder_exceeds_length_cap_not_approved_output=""
_codex_placeholder_exceeds_length_cap_not_approved_exit=0
PATH="$_codex_placeholder_exceeds_length_cap_not_approved_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_placeholder_exceeds_length_cap_not_approved_mock_dir/output.txt" 2>&1 || _codex_placeholder_exceeds_length_cap_not_approved_exit=$?
_codex_placeholder_exceeds_length_cap_not_approved_output="$(cat "$_codex_placeholder_exceeds_length_cap_not_approved_mock_dir/output.txt")"
run_test "codex_placeholder_exceeds_length_cap_not_approved_exit_needs_revision" "2" "$_codex_placeholder_exceeds_length_cap_not_approved_exit"
run_test "codex_placeholder_exceeds_length_cap_not_approved_verdict" "VERDICT: ESCALATE — Codex terminal verdict matches neither an approved clean template nor the documented blocking markers" \
  "$(printf '%s\n' "$_codex_placeholder_exceeds_length_cap_not_approved_output" | grep "^VERDICT:")"
rm -rf "$_codex_placeholder_exceeds_length_cap_not_approved_mock_dir"
unset _codex_placeholder_exceeds_length_cap_not_approved_mock_dir _codex_placeholder_exceeds_length_cap_not_approved_output _codex_placeholder_exceeds_length_cap_not_approved_exit

# Structure guard: a flavor slot containing "*" safe-fails. Confirms the
# excluded-character set protects the literal "**Reviewed commit:**"
# bold-marker syntax immediately after this slot from being spoofed or
# absorbed by an overly permissive placeholder.
_codex_placeholder_asterisk_not_approved_mock_dir="$(mktemp -d)"
cat > "$_codex_placeholder_asterisk_not_approved_mock_dir/gh" <<'CODEX_PLACEHOLDER_ASTERISK_NOT_APPROVED_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'fa00000101234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":716,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    jq -nc '[{id:766,created_at:"2026-01-01T00:00:01Z",user:{login:"chatgpt-codex-connector[bot]"},body:("Codex Review: Didn'\''t find any major issues. Great **job** **Reviewed commit:** `fa0000010` <details> <summary>ℹ️ About Codex in GitHub</summary> <br/> [Your team has set up Codex to review pull requests in this repo](https://chatgpt.com/codex/cloud/settings/general). Reviews are triggered when you - Open a pull request for review - Mark a draft as ready - Comment \"@codex review\". If Codex has suggestions, it will comment; otherwise it will react with 👍. Codex can also answer questions or update the PR. Try commenting \"@codex address that feedback\". </details>")}]'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_PLACEHOLDER_ASTERISK_NOT_APPROVED_GH
chmod +x "$_codex_placeholder_asterisk_not_approved_mock_dir/gh"

_codex_placeholder_asterisk_not_approved_output=""
_codex_placeholder_asterisk_not_approved_exit=0
PATH="$_codex_placeholder_asterisk_not_approved_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_placeholder_asterisk_not_approved_mock_dir/output.txt" 2>&1 || _codex_placeholder_asterisk_not_approved_exit=$?
_codex_placeholder_asterisk_not_approved_output="$(cat "$_codex_placeholder_asterisk_not_approved_mock_dir/output.txt")"
run_test "codex_placeholder_asterisk_not_approved_exit_needs_revision" "2" "$_codex_placeholder_asterisk_not_approved_exit"
run_test "codex_placeholder_asterisk_not_approved_verdict" "VERDICT: ESCALATE — Codex terminal verdict matches neither an approved clean template nor the documented blocking markers" \
  "$(printf '%s\n' "$_codex_placeholder_asterisk_not_approved_output" | grep "^VERDICT:")"
rm -rf "$_codex_placeholder_asterisk_not_approved_mock_dir"
unset _codex_placeholder_asterisk_not_approved_mock_dir _codex_placeholder_asterisk_not_approved_output _codex_placeholder_asterisk_not_approved_exit

# Structure guard: a flavor slot containing a backtick safe-fails. Confirms
# the excluded-character set protects the backtick-delimited SHA field that
# immediately follows this slot.
_codex_placeholder_backtick_not_approved_mock_dir="$(mktemp -d)"
cat > "$_codex_placeholder_backtick_not_approved_mock_dir/gh" <<'CODEX_PLACEHOLDER_BACKTICK_NOT_APPROVED_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'fa00000111234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":717,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    jq -nc '[{id:767,created_at:"2026-01-01T00:00:01Z",user:{login:"chatgpt-codex-connector[bot]"},body:("Codex Review: Didn'\''t find any major issues. Nice `work` **Reviewed commit:** `fa0000011` <details> <summary>ℹ️ About Codex in GitHub</summary> <br/> [Your team has set up Codex to review pull requests in this repo](https://chatgpt.com/codex/cloud/settings/general). Reviews are triggered when you - Open a pull request for review - Mark a draft as ready - Comment \"@codex review\". If Codex has suggestions, it will comment; otherwise it will react with 👍. Codex can also answer questions or update the PR. Try commenting \"@codex address that feedback\". </details>")}]'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_PLACEHOLDER_BACKTICK_NOT_APPROVED_GH
chmod +x "$_codex_placeholder_backtick_not_approved_mock_dir/gh"

_codex_placeholder_backtick_not_approved_output=""
_codex_placeholder_backtick_not_approved_exit=0
PATH="$_codex_placeholder_backtick_not_approved_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_placeholder_backtick_not_approved_mock_dir/output.txt" 2>&1 || _codex_placeholder_backtick_not_approved_exit=$?
_codex_placeholder_backtick_not_approved_output="$(cat "$_codex_placeholder_backtick_not_approved_mock_dir/output.txt")"
run_test "codex_placeholder_backtick_not_approved_exit_needs_revision" "2" "$_codex_placeholder_backtick_not_approved_exit"
run_test "codex_placeholder_backtick_not_approved_verdict" "VERDICT: ESCALATE — Codex terminal verdict matches neither an approved clean template nor the documented blocking markers" \
  "$(printf '%s\n' "$_codex_placeholder_backtick_not_approved_output" | grep "^VERDICT:")"
rm -rf "$_codex_placeholder_backtick_not_approved_mock_dir"
unset _codex_placeholder_backtick_not_approved_mock_dir _codex_placeholder_backtick_not_approved_output _codex_placeholder_backtick_not_approved_exit

# Structure/length guard via a distinct injection vector: a paragraph break
# (blank line) inside the flavor position, followed by an extra sentence,
# safe-fails once whitespace normalization (Decision 1, unchanged) collapses
# the break to a single space and the flattened flavor text exceeds the
# 40-character cap. Proves the length cap still catches injected content
# smuggled in via a newline-separated paragraph, not only content appended
# on the same line.
_codex_placeholder_newline_separated_overflow_not_approved_mock_dir="$(mktemp -d)"
cat > "$_codex_placeholder_newline_separated_overflow_not_approved_mock_dir/gh" <<'CODEX_PLACEHOLDER_NEWLINE_SEPARATED_OVERFLOW_NOT_APPROVED_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'fa00000121234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":718,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    jq -nc '[{id:768,created_at:"2026-01-01T00:00:01Z",user:{login:"chatgpt-codex-connector[bot]"},body:("Codex Review: Didn'\''t find any major issues.

Rename the unsafe function immediately before merging this pull request please.

**Reviewed commit:** `fa0000012` <details> <summary>ℹ️ About Codex in GitHub</summary> <br/> [Your team has set up Codex to review pull requests in this repo](https://chatgpt.com/codex/cloud/settings/general). Reviews are triggered when you - Open a pull request for review - Mark a draft as ready - Comment \"@codex review\". If Codex has suggestions, it will comment; otherwise it will react with 👍. Codex can also answer questions or update the PR. Try commenting \"@codex address that feedback\". </details>")}]'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_PLACEHOLDER_NEWLINE_SEPARATED_OVERFLOW_NOT_APPROVED_GH
chmod +x "$_codex_placeholder_newline_separated_overflow_not_approved_mock_dir/gh"

_codex_placeholder_newline_separated_overflow_not_approved_output=""
_codex_placeholder_newline_separated_overflow_not_approved_exit=0
PATH="$_codex_placeholder_newline_separated_overflow_not_approved_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_placeholder_newline_separated_overflow_not_approved_mock_dir/output.txt" 2>&1 || _codex_placeholder_newline_separated_overflow_not_approved_exit=$?
_codex_placeholder_newline_separated_overflow_not_approved_output="$(cat "$_codex_placeholder_newline_separated_overflow_not_approved_mock_dir/output.txt")"
run_test "codex_placeholder_newline_separated_overflow_not_approved_exit_needs_revision" "2" "$_codex_placeholder_newline_separated_overflow_not_approved_exit"
run_test "codex_placeholder_newline_separated_overflow_not_approved_verdict" "VERDICT: ESCALATE — Codex terminal verdict matches neither an approved clean template nor the documented blocking markers" \
  "$(printf '%s\n' "$_codex_placeholder_newline_separated_overflow_not_approved_output" | grep "^VERDICT:")"
rm -rf "$_codex_placeholder_newline_separated_overflow_not_approved_mock_dir"
unset _codex_placeholder_newline_separated_overflow_not_approved_mock_dir _codex_placeholder_newline_separated_overflow_not_approved_output _codex_placeholder_newline_separated_overflow_not_approved_exit



# The single-instance lock is keyed by target repository AND PR number, so the
# lock directory name carries a repository component. These tests pass an
# explicit --repo so the key does not depend on the checkout's origin remote,
# and ask the script itself for the resulting path rather than reconstructing
# the naming scheme here — a test that hard-codes the scheme stops testing the
# script and starts testing its own copy of it.
_unlock_repo="lock-owner/lock-repo"

# _lock_dir_for_repo <pr> <repo-slug> — the lock path the script resolves for
# that pair, read out of `unlock`'s own report.
_lock_dir_for_repo() {
  "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh" unlock "$1" --repo "$2" \
    | sed -n 's/.*(\(\/tmp\/pr-review-loop-[^)]*\.lockdir\)).*/\1/p'
}

_unlock_pr="80213$$"
_unlock_lock_dir="$(_lock_dir_for_repo "$_unlock_pr" "$_unlock_repo")"
rm -rf "$_unlock_lock_dir"
mkdir -p "$_unlock_lock_dir/pid"
printf '%s\n' "pr-review-loop.sh" > "$_unlock_lock_dir/cmd"
_unlock_exit=0
_unlock_output="$("$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh" unlock "$_unlock_pr" --repo "$_unlock_repo" 2>&1)" || _unlock_exit=$?
run_test "unlock_unreadable_pid_exits_1" "1" "$_unlock_exit"
if printf '%s\n' "$_unlock_output" | grep -q "could not read lock PID"; then
  _unlock_error_seen="yes"
else
  _unlock_error_seen="no"
fi
run_test "unlock_unreadable_pid_error" "yes" "$_unlock_error_seen"
rm -rf "$_unlock_lock_dir"
unset _unlock_output _unlock_exit _unlock_error_seen

_unlock_pr="80313$$"
_unlock_lock_dir="$(_lock_dir_for_repo "$_unlock_pr" "$_unlock_repo")"
rm -rf "$_unlock_lock_dir"
mkdir -p "$_unlock_lock_dir/cmd"
printf '%s\n' "999999" > "$_unlock_lock_dir/pid"
_unlock_exit=0
_unlock_output="$("$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh" unlock "$_unlock_pr" --repo "$_unlock_repo" 2>&1)" || _unlock_exit=$?
run_test "unlock_unreadable_cmd_exits_1" "1" "$_unlock_exit"
if printf '%s\n' "$_unlock_output" | grep -q "could not read lock cmd"; then
  _unlock_error_seen="yes"
else
  _unlock_error_seen="no"
fi
run_test "unlock_unreadable_cmd_error" "yes" "$_unlock_error_seen"
rm -rf "$_unlock_lock_dir"
unset _unlock_pr _unlock_lock_dir _unlock_output _unlock_exit _unlock_error_seen

# --- Repository-scoped lock key regression coverage ---------------------------
# A live lock held for one repository's PR #N must not block a different
# repository's PR #N. Before the lock name carried a repository component, a
# live run for another checkout's PR #3 made this repository's PR #3 exit 75
# with REASON=lock_contention, and the recovery hint it printed would have
# deleted the other repository's in-flight lock.
_lockkey_pr="80413$$"
_lockkey_repo_a="lock-a-owner/lock-a-repo"
_lockkey_repo_b="lock-b-owner/lock-b-repo"
_lockkey_dir_a="$(_lock_dir_for_repo "$_lockkey_pr" "$_lockkey_repo_a")"
_lockkey_dir_b="$(_lock_dir_for_repo "$_lockkey_pr" "$_lockkey_repo_b")"
rm -rf "$_lockkey_dir_a" "$_lockkey_dir_b"
run_test "lock_dir_resolved_for_repo_a" "yes" \
  "$(case "$_lockkey_dir_a" in /tmp/pr-review-loop-*.lockdir) printf yes ;; *) printf no ;; esac)"
run_test "lock_dirs_differ_between_repos" "yes" \
  "$([ "$_lockkey_dir_a" != "$_lockkey_dir_b" ] && printf 'yes' || printf 'no')"

# The non-contending case runs past the guard into the script proper, which then
# tries to resolve the PR. Stub gh so the assertion stays offline and fast: what
# matters is only that the run was NOT refused at the lock guard.
_lockkey_mock_dir="$(mktemp -d)"
cat > "$_lockkey_mock_dir/gh" <<'LOCKKEY_GH'
#!/usr/bin/env bash
printf 'gh: stubbed for lock-key test\n' >&2
exit 1
LOCKKEY_GH
chmod +x "$_lockkey_mock_dir/gh"

# A live holder for repo A's PR: sleep in the background and record its PID with
# the cmd name the guard verifies, so the lock reads as live rather than stale.
sleep 120 &
_lockkey_live_pid=$!
mkdir -p "$_lockkey_dir_a"
printf '%s\n' "$_lockkey_live_pid" > "$_lockkey_dir_a/pid"
printf '%s\n' "pr-review-loop.sh" > "$_lockkey_dir_a/cmd"

# Same repository, same PR — must contend.
_lockkey_same_exit=0
_lockkey_same_output="$("$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh" "$_lockkey_pr" --repo "$_lockkey_repo_a" 2>&1)" || _lockkey_same_exit=$?
run_test "lock_same_repo_same_pr_contends_exit_75" "75" "$_lockkey_same_exit"
run_test "lock_same_repo_same_pr_reason" "REASON=lock_contention" \
  "$(printf '%s\n' "$_lockkey_same_output" | grep '^REASON=' | head -1)"
run_test "lock_same_repo_same_pr_lock_dir" "LOCK_DIR=$_lockkey_dir_a" \
  "$(printf '%s\n' "$_lockkey_same_output" | grep '^LOCK_DIR=' | head -1)"
# The recovery hint must name the repository, or following it would remove
# another repository's lock.
if printf '%s\n' "$_lockkey_same_output" | grep -q -- "unlock ${_lockkey_pr} --repo \"${_lockkey_repo_a}\""; then
  _lockkey_hint_seen="yes"
else
  _lockkey_hint_seen="no"
fi
run_test "lock_contention_hint_carries_repo" "yes" "$_lockkey_hint_seen"

# When the lock key comes from WORKFLOW_TARGET_GITHUB_REPO (no --repo on the
# command), the contention hint must echo that slug so a later shell cannot
# re-resolve via cwd origin and delete another repository's lock.
_lockenv_pr="80613$$"
_lockenv_repo="lock-env-owner/lock-env-repo"
_lockenv_dir="$(_lock_dir_for_repo "$_lockenv_pr" "$_lockenv_repo")"
rm -rf "$_lockenv_dir"
sleep 120 &
_lockenv_live_pid=$!
mkdir -p "$_lockenv_dir"
printf '%s\n' "$_lockenv_live_pid" > "$_lockenv_dir/pid"
printf '%s\n' "pr-review-loop.sh" > "$_lockenv_dir/cmd"
_lockenv_exit=0
_lockenv_output="$(WORKFLOW_TARGET_GITHUB_REPO="$_lockenv_repo" "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh" "$_lockenv_pr" 2>&1)" || _lockenv_exit=$?
run_test "lock_env_repo_same_pr_contends_exit_75" "75" "$_lockenv_exit"
if printf '%s\n' "$_lockenv_output" | grep -q -- "unlock ${_lockenv_pr} --repo \"${_lockenv_repo}\""; then
  _lockenv_hint_seen="yes"
else
  _lockenv_hint_seen="no"
fi
run_test "lock_contention_hint_carries_env_repo" "yes" "$_lockenv_hint_seen"
kill "$_lockenv_live_pid" 2>/dev/null || true
wait "$_lockenv_live_pid" 2>/dev/null || true
rm -rf "$_lockenv_dir"
unset _lockenv_pr _lockenv_repo _lockenv_dir _lockenv_live_pid _lockenv_exit _lockenv_output _lockenv_hint_seen

# Different repository, same PR number — must NOT contend. The run gets past the
# guard on its own lock; whatever it exits with afterwards, it must not be
# lock_contention, and it must not have taken repo A's lock dir.
_lockkey_other_exit=0
_lockkey_other_output="$(PATH="$_lockkey_mock_dir:$PATH" "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh" "$_lockkey_pr" --repo "$_lockkey_repo_b" 2>&1)" || _lockkey_other_exit=$?
if printf '%s\n' "$_lockkey_other_output" | grep -q "REASON=lock_contention"; then
  _lockkey_other_contended="yes"
else
  _lockkey_other_contended="no"
fi
run_test "lock_other_repo_same_pr_does_not_contend" "no" "$_lockkey_other_contended"
run_test "lock_other_repo_same_pr_exit_not_75" "no" "$([ "$_lockkey_other_exit" -eq 75 ] && printf 'yes' || printf 'no')"
# Repo A's live lock is untouched by repo B's run.
run_test "lock_other_repo_run_leaves_live_lock_intact" "yes" \
  "$([ -d "$_lockkey_dir_a" ] && printf 'yes' || printf 'no')"

kill "$_lockkey_live_pid" 2>/dev/null || true
wait "$_lockkey_live_pid" 2>/dev/null || true
rm -rf "$_lockkey_dir_a" "$_lockkey_dir_b" "$_lockkey_mock_dir"

# Sanitizing the slug is lossy on its own: '/' folds to '-', so
# `acme/widgets-core` and `acme-widgets/core` render the same label. Two
# distinct repositories sharing one lock is the very defect the repository
# component exists to remove, so the key must stay injective across that fold.
_lockfold_pr="80513$$"
_lockfold_dir_a="$(_lock_dir_for_repo "$_lockfold_pr" "acme/widgets-core")"
_lockfold_dir_b="$(_lock_dir_for_repo "$_lockfold_pr" "acme-widgets/core")"
run_test "lock_key_survives_slash_folding" "yes" \
  "$([ "$_lockfold_dir_a" != "$_lockfold_dir_b" ] && printf 'yes' || printf 'no')"
# The same slug must still resolve to the same lock on every invocation, or the
# guard stops excluding anything at all.
run_test "lock_key_is_stable_for_one_repo" "yes" \
  "$([ "$_lockfold_dir_a" = "$(_lock_dir_for_repo "$_lockfold_pr" "acme/widgets-core")" ] && printf 'yes' || printf 'no')"
unset _lockfold_pr _lockfold_dir_a _lockfold_dir_b

unset _lockkey_mock_dir _lockkey_pr _lockkey_repo_a _lockkey_repo_b _lockkey_dir_a _lockkey_dir_b \
  _lockkey_live_pid _lockkey_same_exit _lockkey_same_output _lockkey_other_exit \
  _lockkey_other_output _lockkey_other_contended _lockkey_hint_seen \
  _unlock_repo

_codex_overrides='
  cd_workflow_repo_root() { :; }
  repo_slug() { printf "owner/repo\n"; }
  require_gh() { :; }
  codex_review_thread_evidence_counts() { return 3; }
'
actual_output=""
actual_exit=0
actual_output="$(
  eval "$_codex_overrides"
  _ec=0
  run_codex_github_review "42" "fix/42-test" "1" "5" || _ec=$?
  printf 'EXIT=%s\n' "$_ec"
)"
actual_exit="$(printf '%s\n' "$actual_output" | grep "^EXIT=" | cut -d= -f2)"
run_test "codex_thread_check_failure_result" "RESULT=escalate" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "codex_thread_check_failure_reason" "REASON=thread-check-failed" \
  "$(printf '%s\n' "$actual_output" | grep "^REASON=")"
run_test "codex_thread_check_failure_exit_code" "2" "$actual_exit"
unset _codex_overrides actual_output actual_exit

_codex_usage_loop_tmp="$(mktemp -d)"
mkdir -p "$_codex_usage_loop_tmp/scripts/development-workflow"
cat > "$_codex_usage_loop_tmp/scripts/development-workflow/codex-github-reviewer.sh" <<'CODEX_USAGE_LOOP_REVIEWER'
#!/usr/bin/env bash
printf 'VERDICT: UNAVAILABLE — Codex GitHub review usage limit reached\n'
printf 'REASON=codex-github-usage-limit\n'
printf 'COMMENT_COUNT=0\n'
printf 'BLOCKING_COUNT=0\n'
printf 'SUGGESTION_COUNT=0\n'
exit 3
CODEX_USAGE_LOOP_REVIEWER
chmod +x "$_codex_usage_loop_tmp/scripts/development-workflow/codex-github-reviewer.sh"
_codex_overrides='
  cd_workflow_repo_root() { :; }
  repo_slug() { printf "owner/repo\n"; }
  require_gh() { :; }
  workflow_repo_root() { printf "%s\n" "$_codex_usage_loop_tmp"; }
  codex_review_thread_evidence_counts() { printf "0\t0\t0\n"; return 0; }
'
actual_output=""
actual_exit=0
actual_output="$(
  eval "$_codex_overrides"
  _ec=0
  run_codex_github_review "42" "fix/42-test" "1" "5" || _ec=$?
  printf 'EXIT=%s\n' "$_ec"
)"
actual_exit="$(printf '%s\n' "$actual_output" | grep "^EXIT=" | cut -d= -f2)"
run_test "codex_usage_limit_loop_result" "RESULT=escalate" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "codex_usage_limit_loop_reason" "REASON=codex-github-usage-limit" \
  "$(printf '%s\n' "$actual_output" | grep "^REASON=")"
run_test "codex_usage_limit_loop_platform" "PLATFORM=codex-github" \
  "$(printf '%s\n' "$actual_output" | grep "^PLATFORM=")"
run_test "codex_usage_limit_loop_comment_zero" "COMMENT_COUNT=0" \
  "$(printf '%s\n' "$actual_output" | grep "^COMMENT_COUNT=")"
run_test "codex_usage_limit_loop_blocking_zero" "BLOCKING_COUNT=0" \
  "$(printf '%s\n' "$actual_output" | grep "^BLOCKING_COUNT=")"
run_test "codex_usage_limit_loop_suggestion_zero" "SUGGESTION_COUNT=0" \
  "$(printf '%s\n' "$actual_output" | grep "^SUGGESTION_COUNT=")"
run_test "codex_usage_limit_loop_exit_code" "2" "$actual_exit"
rm -rf "$_codex_usage_loop_tmp"
unset _codex_usage_loop_tmp _codex_overrides actual_output actual_exit

_codex_pending_loop_tmp="$(mktemp -d)"
mkdir -p "$_codex_pending_loop_tmp/scripts/development-workflow"
cat > "$_codex_pending_loop_tmp/scripts/development-workflow/codex-github-reviewer.sh" <<'CODEX_PENDING_LOOP_REVIEWER'
#!/usr/bin/env bash
printf 'VERDICT: WAITING_ON_REVIEWER — current-head Codex review is still pending\n'
printf 'REASON=codex-github-review-pending\n'
printf 'PENDING_REVIEWER=codex-github\n'
printf 'PENDING_REVIEW_HEAD_SHA=abc123pending\n'
printf 'PENDING_REVIEW_TRIGGER_COMMENT_ID=901\n'
printf 'PENDING_REVIEW_TRIGGER_TIME=2026-01-01T00:00:00Z\n'
exit 4
CODEX_PENDING_LOOP_REVIEWER
chmod +x "$_codex_pending_loop_tmp/scripts/development-workflow/codex-github-reviewer.sh"
_codex_overrides='
  cd_workflow_repo_root() { :; }
  repo_slug() { printf "owner/repo\n"; }
  require_gh() { :; }
  workflow_repo_root() { printf "%s\n" "$_codex_pending_loop_tmp"; }
  codex_review_thread_evidence_counts() { printf "0\t0\t0\n"; return 0; }
'
actual_output=""
actual_exit=0
actual_output="$(
  eval "$_codex_overrides"
  _ec=0
  run_codex_github_review "42" "fix/42-test" "1" "5" || _ec=$?
  printf 'EXIT=%s\n' "$_ec"
)"
actual_exit="$(printf '%s\n' "$actual_output" | grep "^EXIT=" | cut -d= -f2)"
run_test "codex_pending_loop_result" "RESULT=waiting_on_reviewer" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "codex_pending_loop_reason" "REASON=codex-github-review-pending" \
  "$(printf '%s\n' "$actual_output" | grep "^REASON=")"
run_test "codex_pending_loop_trigger_id" "PENDING_REVIEW_TRIGGER_COMMENT_ID=901" \
  "$(printf '%s\n' "$actual_output" | grep "^PENDING_REVIEW_TRIGGER_COMMENT_ID=")"
run_test "codex_pending_loop_exit_code" "4" "$actual_exit"
rm -rf "$_codex_pending_loop_tmp"
unset _codex_pending_loop_tmp _codex_overrides actual_output actual_exit

# #1757 (Operational Visibility): the loop must read the companion's own
# REASON= for a hard-unavailable (exit 3) outcome instead of hardcoding the
# usage-limit code, so codex_return_account_not_connected's distinct reason
# is not mislabelled.
_codex_exit3_usage_tmp="$(mktemp -d)"
mkdir -p "$_codex_exit3_usage_tmp/scripts/development-workflow"
cat > "$_codex_exit3_usage_tmp/scripts/development-workflow/codex-github-reviewer.sh" <<'CODEX_EXIT3_USAGE_REVIEWER'
#!/usr/bin/env bash
printf 'VERDICT: UNAVAILABLE — Codex GitHub review usage limit reached\n'
printf 'REASON=codex-github-usage-limit\n'
exit 3
CODEX_EXIT3_USAGE_REVIEWER
chmod +x "$_codex_exit3_usage_tmp/scripts/development-workflow/codex-github-reviewer.sh"
_codex_overrides='
  cd_workflow_repo_root() { :; }
  repo_slug() { printf "owner/repo\n"; }
  require_gh() { :; }
  workflow_repo_root() { printf "%s\n" "$_codex_exit3_usage_tmp"; }
  codex_review_thread_evidence_counts() { printf "0\t0\t0\n"; return 0; }
'
actual_output="$(
  eval "$_codex_overrides"
  run_codex_github_review "42" "fix/42-test" "1" "5" || true
)"
run_test "codex_exit3_usage_limit_reason_preserved" "REASON=codex-github-usage-limit" \
  "$(printf '%s\n' "$actual_output" | grep "^REASON=")"
rm -rf "$_codex_exit3_usage_tmp"
unset _codex_exit3_usage_tmp _codex_overrides actual_output

_codex_exit3_notconnected_tmp="$(mktemp -d)"
mkdir -p "$_codex_exit3_notconnected_tmp/scripts/development-workflow"
cat > "$_codex_exit3_notconnected_tmp/scripts/development-workflow/codex-github-reviewer.sh" <<'CODEX_EXIT3_NOTCONNECTED_REVIEWER'
#!/usr/bin/env bash
printf 'VERDICT: UNAVAILABLE — Codex GitHub account is not connected for the triggering identity\n'
printf 'REASON=codex-github-account-not-connected\n'
exit 3
CODEX_EXIT3_NOTCONNECTED_REVIEWER
chmod +x "$_codex_exit3_notconnected_tmp/scripts/development-workflow/codex-github-reviewer.sh"
_codex_overrides='
  cd_workflow_repo_root() { :; }
  repo_slug() { printf "owner/repo\n"; }
  require_gh() { :; }
  workflow_repo_root() { printf "%s\n" "$_codex_exit3_notconnected_tmp"; }
  codex_review_thread_evidence_counts() { printf "0\t0\t0\n"; return 0; }
'
actual_output="$(
  eval "$_codex_overrides"
  run_codex_github_review "42" "fix/42-test" "1" "5" || true
)"
run_test "codex_exit3_account_not_connected_reason_preserved" "REASON=codex-github-account-not-connected" \
  "$(printf '%s\n' "$actual_output" | grep "^REASON=")"
rm -rf "$_codex_exit3_notconnected_tmp"
unset _codex_exit3_notconnected_tmp _codex_overrides actual_output

# #1757 (AC-1, AC-2, AC-8, AC-15) — primary regression: a resolved Codex
# finding must not count as a current blocker. The companion returns
# NEEDS_REVISION (exit 1, e.g. because its own pre-trigger classification
# still saw a visible-but-now-resolved comment), but a strict,
# applicability-aware recount confirms zero live-head Codex conversations
# remain unresolved. Before this fix, the shipped `unresolved_count=1` floor
# forced RESULT=needs_fixes/COMMENT_COUNT=1 regardless of the recount; the
# fix must request a fresh current-head review (waiting_on_reviewer /
# codex-github-review-pending) instead.
_codex_resolved_visible_tmp="$(mktemp -d)"
mkdir -p "$_codex_resolved_visible_tmp/scripts/development-workflow"
cat > "$_codex_resolved_visible_tmp/scripts/development-workflow/codex-github-reviewer.sh" <<'CODEX_RESOLVED_VISIBLE_REVIEWER'
#!/usr/bin/env bash
printf 'VERDICT: NEEDS_REVISION\n'
printf 'REVIEWED_HEAD=ffffffffffffffffffffffffffffffffffffffff\n'
exit 1
CODEX_RESOLVED_VISIBLE_REVIEWER
chmod +x "$_codex_resolved_visible_tmp/scripts/development-workflow/codex-github-reviewer.sh"
_codex_overrides='
  cd_workflow_repo_root() { :; }
  repo_slug() { printf "owner/repo\n"; }
  require_gh() { :; }
  workflow_repo_root() { printf "%s\n" "$_codex_resolved_visible_tmp"; }
  reviewer_loop_print_reviewed_head_from_unresolved_bot_threads() { :; }
  reviewer_loop_print_blocking_from_unresolved_bot_threads() { :; }
  codex_review_thread_evidence_counts() { printf "0\t0\t0\n"; return 0; }
  codex_current_head_changes_requested_blocker() { printf "0\n"; return 0; }
'
actual_output=""
actual_exit=0
actual_output="$(
  eval "$_codex_overrides"
  _ec=0
  run_codex_github_review "42" "fix/42-test" "1" "5" || _ec=$?
  printf 'EXIT=%s\n' "$_ec"
)"
actual_exit="$(printf '%s\n' "$actual_output" | grep "^EXIT=" | cut -d= -f2)"
run_test "codex_resolved_visible_finding_waits_after_revision_push_result" "RESULT=waiting_on_reviewer" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "codex_resolved_visible_finding_waits_after_revision_push_reason" "REASON=codex-github-review-pending" \
  "$(printf '%s\n' "$actual_output" | grep "^REASON=")"
run_test "codex_resolved_visible_finding_waits_after_revision_push_exit" "4" "$actual_exit"
rm -rf "$_codex_resolved_visible_tmp"
unset _codex_resolved_visible_tmp _codex_overrides actual_output actual_exit

# Bugbot regression (PR #1780, "CHANGES_REQUESTED remapped to wait"): the
# same zero-thread-recount shape as the case immediately above, but a
# live-head CHANGES_REQUESTED review IS active (a body-only review, or one
# whose own inline threads are all separately resolved). This must never be
# waved through to waiting_on_reviewer — GitHub's structured
# request-for-changes state is not a thread and is never cleared by
# resolving conversations (spec Business Rules 5/6).
_codex_changes_requested_not_waved_tmp="$(mktemp -d)"
mkdir -p "$_codex_changes_requested_not_waved_tmp/scripts/development-workflow"
cat > "$_codex_changes_requested_not_waved_tmp/scripts/development-workflow/codex-github-reviewer.sh" <<'CODEX_CHANGES_REQUESTED_NOT_WAVED_REVIEWER'
#!/usr/bin/env bash
printf 'VERDICT: NEEDS_REVISION\n'
printf 'REVIEWED_HEAD=ffffffffffffffffffffffffffffffffffffffff\n'
exit 1
CODEX_CHANGES_REQUESTED_NOT_WAVED_REVIEWER
chmod +x "$_codex_changes_requested_not_waved_tmp/scripts/development-workflow/codex-github-reviewer.sh"
_codex_overrides='
  cd_workflow_repo_root() { :; }
  repo_slug() { printf "owner/repo\n"; }
  require_gh() { :; }
  workflow_repo_root() { printf "%s\n" "$_codex_changes_requested_not_waved_tmp"; }
  reviewer_loop_print_reviewed_head_from_unresolved_bot_threads() { :; }
  reviewer_loop_print_blocking_from_unresolved_bot_threads() { :; }
  codex_review_thread_evidence_counts() { printf "0\t0\t0\n"; return 0; }
  codex_current_head_changes_requested_blocker() { printf "1\n"; return 0; }
'
actual_output=""
actual_exit=0
actual_output="$(
  eval "$_codex_overrides"
  _ec=0
  run_codex_github_review "42" "fix/42-test" "1" "5" || _ec=$?
  printf 'EXIT=%s\n' "$_ec"
)"
actual_exit="$(printf '%s\n' "$actual_output" | grep "^EXIT=" | cut -d= -f2)"
run_test "codex_changes_requested_not_waved_to_wait_result" "RESULT=needs_fixes" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "codex_changes_requested_not_waved_to_wait_reason" "REASON=unresolved_review_threads" \
  "$(printf '%s\n' "$actual_output" | grep "^REASON=")"
run_test "codex_changes_requested_not_waved_to_wait_comment_count" "COMMENT_COUNT=1" \
  "$(printf '%s\n' "$actual_output" | grep "^COMMENT_COUNT=")"
run_test "codex_changes_requested_not_waved_to_wait_blocking_count" "BLOCKING_COUNT=1" \
  "$(printf '%s\n' "$actual_output" | grep "^BLOCKING_COUNT=")"
run_test "codex_changes_requested_not_waved_to_wait_exit" "1" "$actual_exit"
rm -rf "$_codex_changes_requested_not_waved_tmp"
unset _codex_changes_requested_not_waved_tmp _codex_overrides actual_output actual_exit

# Negative counterpart: a genuinely unresolved live-head recount must still
# produce needs_fixes with the true count — the fix must not silently clear
# every exit-1 outcome.
_codex_still_unresolved_tmp="$(mktemp -d)"
mkdir -p "$_codex_still_unresolved_tmp/scripts/development-workflow"
cat > "$_codex_still_unresolved_tmp/scripts/development-workflow/codex-github-reviewer.sh" <<'CODEX_STILL_UNRESOLVED_REVIEWER'
#!/usr/bin/env bash
printf 'VERDICT: NEEDS_REVISION\n'
exit 1
CODEX_STILL_UNRESOLVED_REVIEWER
chmod +x "$_codex_still_unresolved_tmp/scripts/development-workflow/codex-github-reviewer.sh"
_codex_overrides='
  cd_workflow_repo_root() { :; }
  repo_slug() { printf "owner/repo\n"; }
  require_gh() { :; }
  workflow_repo_root() { printf "%s\n" "$_codex_still_unresolved_tmp"; }
  reviewer_loop_print_reviewed_head_from_unresolved_bot_threads() { :; }
  reviewer_loop_print_blocking_from_unresolved_bot_threads() { :; }
  codex_review_thread_evidence_counts() { printf "2\t0\t0\n"; return 0; }
'
actual_output="$(
  eval "$_codex_overrides"
  run_codex_github_review "42" "fix/42-test" "1" "5" || true
)"
run_test "codex_still_unresolved_after_revision_push_result" "RESULT=needs_fixes" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "codex_still_unresolved_after_revision_push_comment_count" "COMMENT_COUNT=2" \
  "$(printf '%s\n' "$actual_output" | grep "^COMMENT_COUNT=")"
rm -rf "$_codex_still_unresolved_tmp"
unset _codex_still_unresolved_tmp _codex_overrides actual_output

# Fail-closed counterpart: when the exit-1 recount itself cannot be
# completed, the loop must still report needs_fixes (COMMENT_COUNT=1) rather
# than silently clearing the pull request from indeterminate thread state.
_codex_recount_failure_tmp="$(mktemp -d)"
mkdir -p "$_codex_recount_failure_tmp/scripts/development-workflow"
cat > "$_codex_recount_failure_tmp/scripts/development-workflow/codex-github-reviewer.sh" <<'CODEX_RECOUNT_FAILURE_REVIEWER'
#!/usr/bin/env bash
printf 'VERDICT: NEEDS_REVISION\n'
exit 1
CODEX_RECOUNT_FAILURE_REVIEWER
chmod +x "$_codex_recount_failure_tmp/scripts/development-workflow/codex-github-reviewer.sh"
# Each invocation of codex_review_thread_evidence_counts runs inside its own
# command-substitution subshell (run_codex_github_review captures its stdout
# via `$(...)`), so a plain shell-variable counter cannot survive across the
# phase-1 call and the exit-1 recount call — it would reset every time. Use a
# file-based counter instead.
_codex_recount_call_file="$_codex_recount_failure_tmp/call-count"
printf '0\n' > "$_codex_recount_call_file"
_codex_overrides='
  cd_workflow_repo_root() { :; }
  repo_slug() { printf "owner/repo\n"; }
  require_gh() { :; }
  workflow_repo_root() { printf "%s\n" "$_codex_recount_failure_tmp"; }
  reviewer_loop_print_reviewed_head_from_unresolved_bot_threads() { :; }
  reviewer_loop_print_blocking_from_unresolved_bot_threads() { :; }
  codex_review_thread_evidence_counts() {
    local n
    n="$(cat "$_codex_recount_call_file")"
    n=$((n + 1))
    printf "%s\n" "$n" > "$_codex_recount_call_file"
    if [ "$n" -eq 1 ]; then printf "0\t0\t0\n"; return 0; fi
    return 3
  }
'
actual_output="$(
  eval "$_codex_overrides"
  run_codex_github_review "42" "fix/42-test" "1" "5" || true
)"
run_test "codex_recount_failure_fails_closed_result" "RESULT=needs_fixes" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "codex_recount_failure_fails_closed_comment_count" "COMMENT_COUNT=1" \
  "$(printf '%s\n' "$actual_output" | grep "^COMMENT_COUNT=")"
rm -rf "$_codex_recount_failure_tmp"
unset _codex_recount_failure_tmp _codex_overrides actual_output

_post_summary_source="$(awk '/^_post_review_summary\(\)/,/^}$/' \
  "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh")"
eval "$_post_summary_source"
# shellcheck disable=SC2329 # Invoked indirectly by the eval-loaded function.
repo_slug() { printf "owner/repo\n"; }
# shellcheck disable=SC2034 # Read by the eval-loaded _post_review_summary function.
compare_mode=0
# shellcheck disable=SC2034 # Read by the eval-loaded _post_review_summary function.
compare_verdicts=()
# shellcheck disable=SC2034 # Read by the eval-loaded _post_review_summary function.
platform_policy_status_notes=()
# shellcheck disable=SC2034 # Read by the eval-loaded _post_review_summary function.
pr_number=42
# shellcheck disable=SC2034 # Read by the eval-loaded _post_review_summary function.
branch_name="fix/42-summary"
MOCK_GH_COMMENTS_OUTPUT='[]'
export MOCK_GH_COMMENTS_OUTPUT

_summary_call_log="$(mktemp)"
export MOCK_GH_CALL_LOG="$_summary_call_log"
MOCK_GH_EXIT=0
export MOCK_GH_EXIT
_post_review_summary "escalate" "thread-check-failed" "codex-github" "0" "0"
_body_file="$(awk '/pr comment 42 --body-file / {print $NF}' "$_summary_call_log" | tail -n 1)"
if [ -n "$_body_file" ]; then
  _body_file_used="yes"
else
  _body_file_used="no"
fi
run_test "post_summary_uses_body_file" "yes" "$_body_file_used"
if [ -n "$_body_file" ] && [ ! -e "$_body_file" ]; then
  _body_file_removed="yes"
else
  _body_file_removed="no"
fi
run_test "post_summary_removes_body_file_on_success" "yes" "$_body_file_removed"
rm -f "$_summary_call_log"

_summary_call_log="$(mktemp)"
export MOCK_GH_CALL_LOG="$_summary_call_log"
MOCK_GH_EXIT=1
export MOCK_GH_EXIT
# _post_review_summary now returns non-zero when persistence genuinely
# fails (#1502 dual-cap follow-up) — guard the bare call with `|| true`
# since this test only cares about body-file cleanup, not the return code
# (that contract is covered separately by the persist-failure tests above).
_post_review_summary "escalate" "thread-check-failed" "codex-github" "0" "0" 2>/dev/null || true
_body_file="$(awk '/pr comment 42 --body-file / {print $NF}' "$_summary_call_log" | tail -n 1)"
if [ -n "$_body_file" ] && [ ! -e "$_body_file" ]; then
  _body_file_removed="yes"
else
  _body_file_removed="no"
fi
run_test "post_summary_removes_body_file_on_failure" "yes" "$_body_file_removed"
rm -f "$_summary_call_log"

MOCK_GH_EXIT=0
export MOCK_GH_EXIT
MOCK_GH_COMMENTS_OUTPUT='[]'
export MOCK_GH_COMMENTS_OUTPUT
_summary_call_log="$(mktemp)"
export MOCK_GH_CALL_LOG="$_summary_call_log"
_post_review_summary "needs_fixes" "haystack_blocking_findings" "pr-agent (clean), haystack (needs_fixes)" "2" "0"
_needs_fixes_create_calls="$(grep_count_or_zero 'pr comment 42 --body-file' "$_summary_call_log")"
_needs_fixes_patch_calls="$(grep_count_or_zero '--method PATCH' "$_summary_call_log")"
run_test "post_summary_needs_fixes_creates_when_missing" "1" "$_needs_fixes_create_calls"
run_test "post_summary_needs_fixes_missing_does_not_patch" "0" "$_needs_fixes_patch_calls"
rm -f "$_summary_call_log"

MOCK_GH_COMMENTS_OUTPUT="$(
  jq -nc --arg body $'### Automated Reviewer Loop Summary\n\n*Posted automatically by `pr-review-loop.sh`.*' \
    '[{id: 123, body: $body}]'
)"
export MOCK_GH_COMMENTS_OUTPUT
_summary_call_log="$(mktemp)"
export MOCK_GH_CALL_LOG="$_summary_call_log"
_post_review_summary "needs_fixes" "haystack_blocking_findings" "pr-agent (clean), haystack (needs_fixes)" "2" "0"
_needs_fixes_create_calls="$(grep_count_or_zero 'pr comment 42 --body-file' "$_summary_call_log")"
_needs_fixes_patch_calls="$(grep_count_or_zero '--method PATCH' "$_summary_call_log")"
run_test "post_summary_needs_fixes_repeated_no_duplicate" "0" "$_needs_fixes_create_calls"
run_test "post_summary_needs_fixes_repeated_updates_in_place" "1" "$_needs_fixes_patch_calls"
rm -f "$_summary_call_log"

unset MOCK_GH_CALL_LOG MOCK_GH_EXIT MOCK_GH_COMMENTS_OUTPUT
unset _post_summary_source _summary_call_log _body_file _body_file_used _body_file_removed
unset _needs_fixes_create_calls _needs_fixes_patch_calls
unset -f _post_review_summary repo_slug

# ---------------------------------------------------------------------------
# #1757 (AC-3, AC-4, AC-7, AC-9, AC-11, AC-12, AC-13, AC-14): full-decision-
# gate-matrix regression coverage for the marker well-formedness classifier,
# the finding-thread correlation contract, the cleared-findings wait, and
# the evidence-unavailable escalation. Area 13's `CODEX_GITHUB_PRE_TRIGGER_
# WAIT=0` export (see its own top-of-area comment) is still in effect, so
# every fixture below (except the two AC-13 trigger-less cases, which pass
# --pre-trigger-wait explicitly to override it) reaches the companion's
# main poll loop rather than the pre-trigger check.
# ---------------------------------------------------------------------------

# AC-11: a root comment carrying the `Reviewed commit` field with NO value
# escalates malformed; a root comment that never carries the field at all
# is acknowledgement evidence (the wait path), never escalated.
_codex_marker_field_empty_mock_dir="$(mktemp -d)"
cat > "$_codex_marker_field_empty_mock_dir/gh" <<'CODEX_MARKER_FIELD_EMPTY_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'e1e1e1e1234567890a\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":501,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"id":601,"created_at":"2026-01-01T00:00:01Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"Codex Review: Didn'\''t find any major issues. **Reviewed commit:** `` <details></details>"}]\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_MARKER_FIELD_EMPTY_GH
chmod +x "$_codex_marker_field_empty_mock_dir/gh"
_codex_marker_field_empty_output=""
_codex_marker_field_empty_exit=0
PATH="$_codex_marker_field_empty_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_marker_field_empty_mock_dir/output.txt" 2>&1 || _codex_marker_field_empty_exit=$?
_codex_marker_field_empty_output="$(cat "$_codex_marker_field_empty_mock_dir/output.txt")"
run_test "codex_marker_field_empty_escalates_malformed_exit" "2" "$_codex_marker_field_empty_exit"
run_test "codex_marker_field_empty_escalates_malformed_reason" "REASON=codex_current_verdict_malformed_revision_marker" \
  "$(printf '%s\n' "$_codex_marker_field_empty_output" | grep "^REASON=")"
rm -rf "$_codex_marker_field_empty_mock_dir"
unset _codex_marker_field_empty_mock_dir _codex_marker_field_empty_output _codex_marker_field_empty_exit

_codex_marker_field_absent_mock_dir="$(mktemp -d)"
cat > "$_codex_marker_field_absent_mock_dir/gh" <<'CODEX_MARKER_FIELD_ABSENT_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'e2e2e2e2234567890a\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":502,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"id":602,"created_at":"2026-01-01T00:00:01Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"Working on it, will report back shortly."}]\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_MARKER_FIELD_ABSENT_GH
chmod +x "$_codex_marker_field_absent_mock_dir/gh"
_codex_marker_field_absent_output=""
_codex_marker_field_absent_exit=0
PATH="$_codex_marker_field_absent_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_marker_field_absent_mock_dir/output.txt" 2>&1 || _codex_marker_field_absent_exit=$?
_codex_marker_field_absent_output="$(cat "$_codex_marker_field_absent_mock_dir/output.txt")"
# A non-terminal, non-reaction root comment is ancillary evidence: it never
# reaches SHA-pinned terminal classification, so the loop just keeps
# waiting for real evidence and exhausts its bounded poll/async-grace
# budget — waiting_on_reviewer / codex-github-review-pending (exit 4), not
# an escalation.
run_test "codex_marker_field_absent_is_acknowledgement_exit" "4" "$_codex_marker_field_absent_exit"
run_test "codex_marker_field_absent_is_acknowledgement_reason" "REASON=codex-github-review-pending" \
  "$(printf '%s\n' "$_codex_marker_field_absent_output" | grep "^REASON=")"
rm -rf "$_codex_marker_field_absent_mock_dir"
unset _codex_marker_field_absent_mock_dir _codex_marker_field_absent_output _codex_marker_field_absent_exit

# AC-3, AC-4: a syntactically unusable marker that is an interior-substring
# of the live head (appears inside it at a NONZERO offset — not a prefix)
# is malformed even though the token itself is valid hex and would
# otherwise resolve.
_codex_marker_interior_substring_mock_dir="$(mktemp -d)"
cat > "$_codex_marker_interior_substring_mock_dir/gh" <<'CODEX_MARKER_INTERIOR_SUBSTRING_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'aa11bb22cc33dd44ee55\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":503,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"id":603,"created_at":"2026-01-01T00:00:01Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"Codex Review: Didn'\''t find any major issues. **Reviewed commit:** `11bb22cc33` <details></details>"}]\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_MARKER_INTERIOR_SUBSTRING_GH
chmod +x "$_codex_marker_interior_substring_mock_dir/gh"
_codex_marker_interior_substring_output=""
_codex_marker_interior_substring_exit=0
PATH="$_codex_marker_interior_substring_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_marker_interior_substring_mock_dir/output.txt" 2>&1 || _codex_marker_interior_substring_exit=$?
_codex_marker_interior_substring_output="$(cat "$_codex_marker_interior_substring_mock_dir/output.txt")"
run_test "codex_marker_interior_substring_escalates_malformed_exit" "2" "$_codex_marker_interior_substring_exit"
run_test "codex_marker_interior_substring_escalates_malformed_reason" "REASON=codex_current_verdict_malformed_revision_marker" \
  "$(printf '%s\n' "$_codex_marker_interior_substring_output" | grep "^REASON=")"
rm -rf "$_codex_marker_interior_substring_mock_dir"
unset _codex_marker_interior_substring_mock_dir _codex_marker_interior_substring_output _codex_marker_interior_substring_exit

# AC-12: a well-formed marker naming the live head but authored BEFORE the
# live-head trigger fails the freshness boundary — neither acknowledgement
# nor clean evidence; the loop waits (codex-github-review-pending), it does
# not escalate malformed. The main-loop poll query already filters bot
# comments to `created_at > trigger_time` server-side, so a stale comment
# never reaches the companion's classification in the first place — the
# freshness boundary is proved by the ABSENCE of a VERDICT line (no
# terminal evidence reaches the poll loop) and the loop's own TIMED_OUT
# safe-fail once its bounded MAX_WAIT is exhausted, never a malformed-
# marker escalation.
_codex_marker_freshness_fails_mock_dir="$(mktemp -d)"
cat > "$_codex_marker_freshness_fails_mock_dir/gh" <<'CODEX_MARKER_FRESHNESS_FAILS_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'ff11ff22ff33ff44ff55\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":504,"created_at":"2026-01-01T00:00:05Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"id":604,"created_at":"2026-01-01T00:00:01Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"Codex Review: Didn'\''t find any major issues. **Reviewed commit:** `ff11ff22ff` <details></details>"}]\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_MARKER_FRESHNESS_FAILS_GH
chmod +x "$_codex_marker_freshness_fails_mock_dir/gh"
_codex_marker_freshness_fails_output=""
_codex_marker_freshness_fails_exit=0
PATH="$_codex_marker_freshness_fails_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_marker_freshness_fails_mock_dir/output.txt" 2>&1 || _codex_marker_freshness_fails_exit=$?
_codex_marker_freshness_fails_output="$(cat "$_codex_marker_freshness_fails_mock_dir/output.txt")"
# AC-12: neither acknowledgement nor clean nor escalated — the comment
# predates the trigger, so the server-side poll-query filter never even
# surfaces it as terminal evidence; the loop exhausts its bounded budget
# and waits (codex-github-review-pending, exit 4), it does not escalate.
run_test "codex_marker_freshness_fails_not_escalated_exit" "4" "$_codex_marker_freshness_fails_exit"
run_test "codex_marker_freshness_fails_not_malformed" "no" \
  "$(printf '%s\n' "$_codex_marker_freshness_fails_output" | grep -q 'codex_current_verdict_malformed_revision_marker' && echo yes || echo no)"
rm -rf "$_codex_marker_freshness_fails_mock_dir"
unset _codex_marker_freshness_fails_mock_dir _codex_marker_freshness_fails_output _codex_marker_freshness_fails_exit

# Business Rule 1 / AC-1, AC-2: direct coverage of
# codex_review_thread_evidence_counts()'s applicability filter (dismissed
# review exclusion, live-head commit-oid correlation). No pre-existing
# Area-13 fixture's mocked GraphQL response includes the
# `pullRequestReview` field at all, so every other test in this file drives
# this function with `$applicable` defaulted to always-true (the field
# missing) and never actually exercises the DISMISSED/stale-commit
# exclusion this item introduces — this is the literal fix for the bug
# this PR's title describes, and it was otherwise untested. Calls the real
# (non-stubbed) function directly, sourced into this process via the
# `HARNESS_MODE=1 source pr-review-loop.sh` at the top of this file, which
# itself sources codex-github-evidence-lib.sh.
_codex_evidence_applic_mock_dir="$(mktemp -d)"
cat > "$_codex_evidence_applic_mock_dir/gh" <<'CODEX_EVIDENCE_APPLIC_GH'
#!/usr/bin/env bash
case "$*" in
  *"api graphql"*)
    printf '%s\n' '{"data":{"repository":{"pullRequest":{"headRefOid":"1111111111111111111111111111111111111a","headRef":{"target":{"committedDate":"2026-01-01T00:00:00Z"}},"reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[{"isResolved":false,"isOutdated":false,"firstComment":{"nodes":[{"author":{"login":"chatgpt-codex-connector"},"body":"Dismissed-review finding","pullRequestReview":{"state":"DISMISSED","commit":{"oid":"1111111111111111111111111111111111111a"}}}]},"lastComment":{"nodes":[{"author":{"login":"chatgpt-codex-connector"},"createdAt":"2026-01-01T00:00:00Z"}]}},{"isResolved":false,"isOutdated":false,"firstComment":{"nodes":[{"author":{"login":"chatgpt-codex-connector"},"body":"Stale-head finding","pullRequestReview":{"state":"COMMENTED","commit":{"oid":"2222222222222222222222222222222222222b"}}}]},"lastComment":{"nodes":[{"author":{"login":"chatgpt-codex-connector"},"createdAt":"2026-01-01T00:00:00Z"}]}},{"isResolved":false,"isOutdated":false,"firstComment":{"nodes":[{"author":{"login":"chatgpt-codex-connector"},"body":"Live-head finding","pullRequestReview":{"state":"COMMENTED","commit":{"oid":"1111111111111111111111111111111111111a"}}}]},"lastComment":{"nodes":[{"author":{"login":"chatgpt-codex-connector"},"createdAt":"2026-01-01T00:00:00Z"}]}},{"isResolved":false,"isOutdated":false,"firstComment":{"nodes":[{"author":{"login":"chatgpt-codex-connector"},"body":"Unreadable-commit finding","pullRequestReview":{"state":"COMMENTED"}}]},"lastComment":{"nodes":[{"author":{"login":"chatgpt-codex-connector"},"createdAt":"2026-01-01T00:00:00Z"}]}}]}}}}}'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_EVIDENCE_APPLIC_GH
chmod +x "$_codex_evidence_applic_mock_dir/gh"
_codex_evidence_applic_output=""
_codex_evidence_applic_output="$(PATH="$_codex_evidence_applic_mock_dir:$PATH" codex_review_thread_evidence_counts "owner" "repo" "42" "chatgpt-codex-connector" "strict")"
# 4 threads: DISMISSED (excluded regardless of matching oid), stale-head
# commit mismatch (excluded), live-head commit match (counted), and a
# thread whose owning review carries no readable commit oid at all (fails
# closed toward still counting it, per the function's own contract).
run_test "codex_evidence_applicability_dismissed_and_stale_head_excluded_count" "2" \
  "$(printf '%s' "$_codex_evidence_applic_output" | cut -f1)"
run_test "codex_evidence_applicability_dismissed_and_stale_head_excluded_cleared" "0" \
  "$(printf '%s' "$_codex_evidence_applic_output" | cut -f2)"
rm -rf "$_codex_evidence_applic_mock_dir"
unset _codex_evidence_applic_mock_dir _codex_evidence_applic_output

# Mode contract (strict vs provisional vs unknown-mode-falls-back-to-strict):
# one applicable, unresolved thread whose LAST comment is a non-bot reply
# after the head commit's committedDate (the #1508 relaxation). Every other
# fixture that reaches this scenario stubs codex_review_thread_evidence_counts
# entirely, so the real mode-dispatch branch in the shared library (the
# `$mode == "provisional"` jq guard) was never itself proven to gate the
# relaxation.
_codex_evidence_mode_mock_dir="$(mktemp -d)"
cat > "$_codex_evidence_mode_mock_dir/gh" <<'CODEX_EVIDENCE_MODE_GH'
#!/usr/bin/env bash
case "$*" in
  *"api graphql"*)
    printf '%s\n' '{"data":{"repository":{"pullRequest":{"headRefOid":"3333333333333333333333333333333333333c","headRef":{"target":{"committedDate":"2026-01-01T00:00:00Z"}},"reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[{"isResolved":false,"isOutdated":false,"firstComment":{"nodes":[{"author":{"login":"chatgpt-codex-connector"},"body":"Blocking issue","pullRequestReview":{"state":"COMMENTED","commit":{"oid":"3333333333333333333333333333333333333c"}}}]},"lastComment":{"nodes":[{"author":{"login":"humanreview"},"createdAt":"2026-01-01T00:00:01Z"}]}}]}}}}}'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_EVIDENCE_MODE_GH
chmod +x "$_codex_evidence_mode_mock_dir/gh"
_codex_evidence_strict_output="$(PATH="$_codex_evidence_mode_mock_dir:$PATH" codex_review_thread_evidence_counts "owner" "repo" "42" "chatgpt-codex-connector" "strict")"
_codex_evidence_provisional_output="$(PATH="$_codex_evidence_mode_mock_dir:$PATH" codex_review_thread_evidence_counts "owner" "repo" "42" "chatgpt-codex-connector" "provisional")"
_codex_evidence_unknown_output="$(PATH="$_codex_evidence_mode_mock_dir:$PATH" codex_review_thread_evidence_counts "owner" "repo" "42" "chatgpt-codex-connector" "bogus-mode")"
run_test "codex_evidence_lib_strict_counts_replied_thread_as_unresolved" "1	0	0" "$_codex_evidence_strict_output"
run_test "codex_evidence_lib_provisional_preserves_relaxation" "1	0	1" "$_codex_evidence_provisional_output"
run_test "codex_evidence_lib_unknown_mode_falls_back_to_strict" "1	0	0" "$_codex_evidence_unknown_output"
rm -rf "$_codex_evidence_mode_mock_dir"
unset _codex_evidence_mode_mock_dir _codex_evidence_strict_output _codex_evidence_provisional_output _codex_evidence_unknown_output

# Bugbot follow-up (PR #1780, "CHANGES_REQUESTED remapped to wait"): direct
# coverage of codex_current_head_changes_requested_blocker() itself (real,
# non-stubbed function, sourced via the same HARNESS_MODE=1 source at the
# top of this file). Five cases: REST "[bot]"-suffixed login match, GraphQL
# plain-login match, no match (state/commit mismatch), head-SHA lookup
# failure (fail closed), and reviews-query failure (fail closed).
_codex_cr_blocker_bracket_mock_dir="$(mktemp -d)"
cat > "$_codex_cr_blocker_bracket_mock_dir/gh" <<'CODEX_CR_BLOCKER_BRACKET_GH'
#!/usr/bin/env bash
case "$*" in
  *"pr view"*headRefOid*)
    printf 'aaaa111122223333444455556666777788889999\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[{"id":901,"commit_id":"aaaa111122223333444455556666777788889999","state":"CHANGES_REQUESTED","user":{"login":"chatgpt-codex-connector[bot]"},"body":"See summary."}]\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_CR_BLOCKER_BRACKET_GH
chmod +x "$_codex_cr_blocker_bracket_mock_dir/gh"
_codex_cr_blocker_bracket_output="$(PATH="$_codex_cr_blocker_bracket_mock_dir:$PATH" \
  codex_current_head_changes_requested_blocker "owner" "repo" "42" "chatgpt-codex-connector[bot]" "chatgpt-codex-connector")"
run_test "codex_cr_blocker_matches_bracket_login" "1" "$_codex_cr_blocker_bracket_output"
rm -rf "$_codex_cr_blocker_bracket_mock_dir"
unset _codex_cr_blocker_bracket_mock_dir _codex_cr_blocker_bracket_output

_codex_cr_blocker_plain_mock_dir="$(mktemp -d)"
cat > "$_codex_cr_blocker_plain_mock_dir/gh" <<'CODEX_CR_BLOCKER_PLAIN_GH'
#!/usr/bin/env bash
case "$*" in
  *"pr view"*headRefOid*)
    printf 'bbbb111122223333444455556666777788889999\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[{"id":902,"commit_id":"bbbb111122223333444455556666777788889999","state":"CHANGES_REQUESTED","user":{"login":"chatgpt-codex-connector"},"body":"See summary."}]\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_CR_BLOCKER_PLAIN_GH
chmod +x "$_codex_cr_blocker_plain_mock_dir/gh"
_codex_cr_blocker_plain_output="$(PATH="$_codex_cr_blocker_plain_mock_dir:$PATH" \
  codex_current_head_changes_requested_blocker "owner" "repo" "42" "chatgpt-codex-connector[bot]" "chatgpt-codex-connector")"
run_test "codex_cr_blocker_matches_plain_login" "1" "$_codex_cr_blocker_plain_output"
rm -rf "$_codex_cr_blocker_plain_mock_dir"
unset _codex_cr_blocker_plain_mock_dir _codex_cr_blocker_plain_output

_codex_cr_blocker_no_match_mock_dir="$(mktemp -d)"
cat > "$_codex_cr_blocker_no_match_mock_dir/gh" <<'CODEX_CR_BLOCKER_NO_MATCH_GH'
#!/usr/bin/env bash
case "$*" in
  *"pr view"*headRefOid*)
    printf 'cccc111122223333444455556666777788889999\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[{"id":903,"commit_id":"stalecommit0000000000000000000000000000","state":"CHANGES_REQUESTED","user":{"login":"chatgpt-codex-connector[bot]"},"body":"Stale head review."},{"id":904,"commit_id":"cccc111122223333444455556666777788889999","state":"COMMENTED","user":{"login":"chatgpt-codex-connector[bot]"},"body":"Non-blocking comment."}]\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_CR_BLOCKER_NO_MATCH_GH
chmod +x "$_codex_cr_blocker_no_match_mock_dir/gh"
_codex_cr_blocker_no_match_output="$(PATH="$_codex_cr_blocker_no_match_mock_dir:$PATH" \
  codex_current_head_changes_requested_blocker "owner" "repo" "42" "chatgpt-codex-connector[bot]" "chatgpt-codex-connector")"
run_test "codex_cr_blocker_no_live_head_match_is_zero" "0" "$_codex_cr_blocker_no_match_output"
rm -rf "$_codex_cr_blocker_no_match_mock_dir"
unset _codex_cr_blocker_no_match_mock_dir _codex_cr_blocker_no_match_output

_codex_cr_blocker_head_fail_mock_dir="$(mktemp -d)"
cat > "$_codex_cr_blocker_head_fail_mock_dir/gh" <<'CODEX_CR_BLOCKER_HEAD_FAIL_GH'
#!/usr/bin/env bash
case "$*" in
  *"pr view"*headRefOid*)
    exit 1 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_CR_BLOCKER_HEAD_FAIL_GH
chmod +x "$_codex_cr_blocker_head_fail_mock_dir/gh"
_codex_cr_blocker_head_fail_output="$(PATH="$_codex_cr_blocker_head_fail_mock_dir:$PATH" \
  codex_current_head_changes_requested_blocker "owner" "repo" "42" "chatgpt-codex-connector[bot]" "chatgpt-codex-connector")"
run_test "codex_cr_blocker_head_sha_lookup_failure_fails_closed" "1" "$_codex_cr_blocker_head_fail_output"
rm -rf "$_codex_cr_blocker_head_fail_mock_dir"
unset _codex_cr_blocker_head_fail_mock_dir _codex_cr_blocker_head_fail_output

_codex_cr_blocker_reviews_fail_mock_dir="$(mktemp -d)"
cat > "$_codex_cr_blocker_reviews_fail_mock_dir/gh" <<'CODEX_CR_BLOCKER_REVIEWS_FAIL_GH'
#!/usr/bin/env bash
case "$*" in
  *"pr view"*headRefOid*)
    printf 'dddd111122223333444455556666777788889999\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf 'boom\n' >&2; exit 1 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_CR_BLOCKER_REVIEWS_FAIL_GH
chmod +x "$_codex_cr_blocker_reviews_fail_mock_dir/gh"
_codex_cr_blocker_reviews_fail_output="$(PATH="$_codex_cr_blocker_reviews_fail_mock_dir:$PATH" \
  codex_current_head_changes_requested_blocker "owner" "repo" "42" "chatgpt-codex-connector[bot]" "chatgpt-codex-connector")"
run_test "codex_cr_blocker_reviews_query_failure_fails_closed" "1" "$_codex_cr_blocker_reviews_fail_output"
rm -rf "$_codex_cr_blocker_reviews_fail_mock_dir"
unset _codex_cr_blocker_reviews_fail_mock_dir _codex_cr_blocker_reviews_fail_output

# Pass 2 defense-in-depth follow-up (PR #1780): a successful jq invocation
# always emits a plain integer today, so this path is not reachable through
# the real `jq` binary. This test forces it by shadowing `jq` on PATH with a
# stub that exits 0 but prints non-numeric output, proving the numeric
# sanitizer fails closed to "1" (not "0") when it cannot trust the parsed
# result, consistent with every other failure path in this function.
_codex_cr_blocker_malformed_jq_mock_dir="$(mktemp -d)"
cat > "$_codex_cr_blocker_malformed_jq_mock_dir/gh" <<'CODEX_CR_BLOCKER_MALFORMED_JQ_GH'
#!/usr/bin/env bash
case "$*" in
  *"pr view"*headRefOid*)
    printf 'eeee111122223333444455556666777788889999\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[{"id":905,"commit_id":"eeee111122223333444455556666777788889999","state":"CHANGES_REQUESTED","user":{"login":"chatgpt-codex-connector[bot]"},"body":"See summary."}]\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_CR_BLOCKER_MALFORMED_JQ_GH
chmod +x "$_codex_cr_blocker_malformed_jq_mock_dir/gh"
cat > "$_codex_cr_blocker_malformed_jq_mock_dir/jq" <<'CODEX_CR_BLOCKER_MALFORMED_JQ_JQ'
#!/usr/bin/env bash
# Drain stdin (this stub sits in a pipe) then emit non-numeric output with a
# clean exit, simulating an unexpected `jq` that does not fail loudly.
cat >/dev/null
printf 'not-a-number\n'
exit 0
CODEX_CR_BLOCKER_MALFORMED_JQ_JQ
chmod +x "$_codex_cr_blocker_malformed_jq_mock_dir/jq"
_codex_cr_blocker_malformed_jq_output="$(PATH="$_codex_cr_blocker_malformed_jq_mock_dir:$PATH" \
  codex_current_head_changes_requested_blocker "owner" "repo" "42" "chatgpt-codex-connector[bot]" "chatgpt-codex-connector")"
run_test "codex_cr_blocker_malformed_jq_output_fails_closed" "1" "$_codex_cr_blocker_malformed_jq_output"
rm -rf "$_codex_cr_blocker_malformed_jq_mock_dir"
unset _codex_cr_blocker_malformed_jq_mock_dir _codex_cr_blocker_malformed_jq_output

# AC-3/AC-4 abbreviated-token resolution contract: the two branches the
# implementation plan names explicitly ("Tests:
# codex_marker_remote_zero_match_malformed and
# codex_marker_unprovable_abbreviation, one per branch") but that no
# fixture in this file exercised — every existing codex_marker_* test
# above drives only the pure string-shape checks (empty/interior-substring)
# that need no git or gh call at all. Both call codex_marker_classify()
# directly against a disposable, otherwise-empty git repository so neither
# token can resolve locally.
_codex_marker_resolve_repo_dir="$(mktemp -d)"
# This harness's own PATH carries a global mock `git` (see MOCK_BIN above)
# that fails fast on anything but `rev-parse --git-common-dir`, so a real
# `git init`/`rev-parse --disambiguate` needs the pre-mock
# TEST_PR_REVIEW_LOOP_REAL_PATH, exactly like the Area-18 (#1562) tests that
# re-invoke this suite as a real subprocess.
PATH="$TEST_PR_REVIEW_LOOP_REAL_PATH" git -C "$_codex_marker_resolve_repo_dir" init -q
_codex_marker_resolve_head="1234567890123456789012345678901234567890"

# Full 40-hex token, no local match, GitHub REST proves non-existence (422)
# -> proven zero-match -> malformed, never evidence-unavailable.
_codex_marker_zero_match_mock_dir="$(mktemp -d)"
cat > "$_codex_marker_zero_match_mock_dir/gh" <<'CODEX_MARKER_ZERO_MATCH_GH'
#!/usr/bin/env bash
case "$*" in
  *"commits/"*)
    printf 'HTTP/2.0 422 Unprocessable Entity\r\n\r\n{"message":"No commit found for SHA: ..."}\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_MARKER_ZERO_MATCH_GH
chmod +x "$_codex_marker_zero_match_mock_dir/gh"
(
  PATH="$_codex_marker_zero_match_mock_dir:$TEST_PR_REVIEW_LOOP_REAL_PATH"
  codex_marker_classify "abababababababababababababababababababab" "$_codex_marker_resolve_head" "owner" "repo" "$_codex_marker_resolve_repo_dir"
  printf 'MARKER_CLASS=%s\n' "$MARKER_CLASS"
) > "$_codex_marker_zero_match_mock_dir/out.txt" 2>&1 || true
run_test "codex_marker_remote_zero_match_malformed" "MARKER_CLASS=malformed" \
  "$(grep '^MARKER_CLASS=' "$_codex_marker_zero_match_mock_dir/out.txt")"
rm -rf "$_codex_marker_zero_match_mock_dir"
unset _codex_marker_zero_match_mock_dir

# Abbreviated token, no local match, CODEX_GITHUB_MARKER_FETCH unset
# (default: the disclosed scope note's documented default-off behavior) ->
# neither source can prove or disprove it -> trusted at its already-
# computed string classification ("prefix", since it is an offset-zero
# prefix of the live head) rather than escalated to
# evidence_unavailable_codex_thread_state. This is the exact behavior the
# PR's disclosed scope note describes; without this test that description
# was unverified.
(
  unset CODEX_GITHUB_MARKER_FETCH
  PATH="$TEST_PR_REVIEW_LOOP_REAL_PATH"
  codex_marker_classify "1234567890" "$_codex_marker_resolve_head" "owner" "repo" "$_codex_marker_resolve_repo_dir"
  printf 'MARKER_CLASS=%s\n' "$MARKER_CLASS"
) > "$_codex_marker_resolve_repo_dir/unprovable_out.txt" 2>&1 || true
run_test "codex_marker_unprovable_abbreviation" "MARKER_CLASS=prefix" \
  "$(grep '^MARKER_CLASS=' "$_codex_marker_resolve_repo_dir/unprovable_out.txt")"
rm -rf "$_codex_marker_resolve_repo_dir"
unset _codex_marker_resolve_repo_dir _codex_marker_resolve_head

# AC-7, AC-9: a submitted review's inline finding IS correlated (matches
# the review's own pull_request_review_id and a live-head GraphQL thread)
# and that thread is unresolved — needs_fixes, proving the correlation
# contract does not over-escalate a genuinely well-formed finding.
_codex_review_inline_finding_correlates_mock_dir="$(mktemp -d)"
cat > "$_codex_review_inline_finding_correlates_mock_dir/gh" <<'CODEX_REVIEW_INLINE_FINDING_CORRELATES_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'cc11cc22cc33cc44cc55\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":505,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[{"id":701,"pull_request_review_id":801,"commit_id":"cc11cc22cc33cc44cc55","body":"Fix this off-by-one."}]\n'
    exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[{"id":801,"submitted_at":"2026-01-01T00:00:01Z","commit_id":"cc11cc22cc33cc44cc55","state":"CHANGES_REQUESTED","user":{"login":"chatgpt-codex-connector[bot]"},"body":"See inline comment."}]\n'
    exit 0 ;;
  *"api graphql"*"databaseId"*)
    printf '{"data":{"repository":{"pullRequest":{"reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[{"isResolved":false,"comments":{"nodes":[{"databaseId":701}]}}]}}}}}\n'
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
CODEX_REVIEW_INLINE_FINDING_CORRELATES_GH
chmod +x "$_codex_review_inline_finding_correlates_mock_dir/gh"
_codex_review_inline_finding_correlates_output=""
_codex_review_inline_finding_correlates_exit=0
PATH="$_codex_review_inline_finding_correlates_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_review_inline_finding_correlates_mock_dir/output.txt" 2>&1 || _codex_review_inline_finding_correlates_exit=$?
_codex_review_inline_finding_correlates_output="$(cat "$_codex_review_inline_finding_correlates_mock_dir/output.txt")"
run_test "codex_body_finding_own_review_comment_correlates_exit" "1" "$_codex_review_inline_finding_correlates_exit"
run_test "codex_body_finding_own_review_comment_correlates_verdict" "VERDICT: NEEDS_REVISION" \
  "$(printf '%s\n' "$_codex_review_inline_finding_correlates_output" | grep "^VERDICT:")"
rm -rf "$_codex_review_inline_finding_correlates_mock_dir"
unset _codex_review_inline_finding_correlates_mock_dir _codex_review_inline_finding_correlates_output _codex_review_inline_finding_correlates_exit

# AC-7, AC-9: the same shape, but the inline comment belongs to an
# UNRELATED review (a different pull_request_review_id, whose own thread is
# RESOLVED) — the head-wide comment index must never supply correlation for
# a different review's own findings; if it wrongly did, the resolved
# unrelated comment would clear R's findings and route to the
# cleared-findings wait instead of R's own CHANGES_REQUESTED structural
# blocker.
_codex_review_unrelated_comment_mock_dir="$(mktemp -d)"
cat > "$_codex_review_unrelated_comment_mock_dir/gh" <<'CODEX_REVIEW_UNRELATED_COMMENT_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'dd11dd22dd33dd44dd55\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":506,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[{"id":702,"pull_request_review_id":900,"commit_id":"dd11dd22dd33dd44dd55","body":"An unrelated earlier review'\''s own comment."}]\n'
    exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[{"id":802,"submitted_at":"2026-01-01T00:00:01Z","commit_id":"dd11dd22dd33dd44dd55","state":"CHANGES_REQUESTED","user":{"login":"chatgpt-codex-connector[bot]"},"body":"See inline comment."}]\n'
    exit 0 ;;
  *"api graphql"*"databaseId"*)
    printf '{"data":{"repository":{"pullRequest":{"reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[{"isResolved":true,"comments":{"nodes":[{"databaseId":702}]}}]}}}}}\n'
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
CODEX_REVIEW_UNRELATED_COMMENT_GH
chmod +x "$_codex_review_unrelated_comment_mock_dir/gh"
_codex_review_unrelated_comment_output=""
_codex_review_unrelated_comment_exit=0
PATH="$_codex_review_unrelated_comment_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_review_unrelated_comment_mock_dir/output.txt" 2>&1 || _codex_review_unrelated_comment_exit=$?
_codex_review_unrelated_comment_output="$(cat "$_codex_review_unrelated_comment_mock_dir/output.txt")"
# The unrelated review's own inline comment is marked RESOLVED. If the
# correlation join were incorrectly head-wide (not scoped to R's own
# pull_request_review_id), R would pick it up as one of its own findings,
# see it resolved, and reach the cleared-findings wait (exit 4). Correctly
# scoped, R has none of its own inline findings and no body finding, so its
# CHANGES_REQUESTED state alone is the actionable blocker: needs_fixes
# (exit 1) — proving the join runs on pull_request_review_id.
run_test "codex_body_finding_unrelated_review_comment_not_correlated_exit" "1" "$_codex_review_unrelated_comment_exit"
run_test "codex_body_finding_unrelated_review_comment_not_correlated_verdict" "VERDICT: NEEDS_REVISION" \
  "$(printf '%s\n' "$_codex_review_unrelated_comment_output" | grep "^VERDICT:")"
rm -rf "$_codex_review_unrelated_comment_mock_dir"
unset _codex_review_unrelated_comment_mock_dir _codex_review_unrelated_comment_output _codex_review_unrelated_comment_exit

# AC-8, AC-9: every one of R's own inline findings correlates AND is
# resolved, R's body carries no blocking assertion, and no other
# applicable current-head conversation is unresolved (strict count 0) —
# the cleared-findings wait: waiting_on_reviewer / codex-github-review-
# pending, never needs_fixes and never a correlation-missing escalation.
_codex_review_cleared_findings_wait_mock_dir="$(mktemp -d)"
cat > "$_codex_review_cleared_findings_wait_mock_dir/gh" <<'CODEX_REVIEW_CLEARED_FINDINGS_WAIT_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'ee11ee22ee33ee44ee55\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":507,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[{"id":703,"pull_request_review_id":803,"commit_id":"ee11ee22ee33ee44ee55","body":"Nit already fixed."}]\n'
    exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[{"id":803,"submitted_at":"2026-01-01T00:00:01Z","commit_id":"ee11ee22ee33ee44ee55","state":"COMMENTED","user":{"login":"chatgpt-codex-connector[bot]"},"body":"See inline comment for the nit."}]\n'
    exit 0 ;;
  *"api graphql"*"databaseId"*)
    printf '{"data":{"repository":{"pullRequest":{"reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[{"isResolved":true,"comments":{"nodes":[{"databaseId":703}]}}]}}}}}\n'
    exit 0 ;;
  *"api graphql"*"headRefOid"*)
    printf '{"data":{"repository":{"pullRequest":{"headRefOid":"ee11ee22ee33ee44ee55","headRef":{"target":{"committedDate":"2026-01-01T00:00:00Z"}},"reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[]}}}}}\n'
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
CODEX_REVIEW_CLEARED_FINDINGS_WAIT_GH
chmod +x "$_codex_review_cleared_findings_wait_mock_dir/gh"
_codex_review_cleared_findings_wait_output=""
_codex_review_cleared_findings_wait_exit=0
PATH="$_codex_review_cleared_findings_wait_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_review_cleared_findings_wait_mock_dir/output.txt" 2>&1 || _codex_review_cleared_findings_wait_exit=$?
_codex_review_cleared_findings_wait_output="$(cat "$_codex_review_cleared_findings_wait_mock_dir/output.txt")"
run_test "codex_review_cleared_findings_wait_exit" "4" "$_codex_review_cleared_findings_wait_exit"
run_test "codex_review_cleared_findings_wait_reason" "REASON=codex-github-review-pending" \
  "$(printf '%s\n' "$_codex_review_cleared_findings_wait_output" | grep "^REASON=")"
rm -rf "$_codex_review_cleared_findings_wait_mock_dir"
unset _codex_review_cleared_findings_wait_mock_dir _codex_review_cleared_findings_wait_output _codex_review_cleared_findings_wait_exit

# AC-14: the bounded finding-thread correlation query itself fails (the
# GraphQL reviewThreads call for R's own inline finding is unmocked) —
# escalate evidence_unavailable_codex_thread_state, never needs_fixes and
# never a silent clean.
_codex_evidence_unavailable_correlation_mock_dir="$(mktemp -d)"
cat > "$_codex_evidence_unavailable_correlation_mock_dir/gh" <<'CODEX_EVIDENCE_UNAVAILABLE_CORRELATION_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'bb11bb22bb33bb44bb55\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":508,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[{"id":704,"pull_request_review_id":804,"commit_id":"bb11bb22bb33bb44bb55","body":"Please fix this."}]\n'
    exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[{"id":804,"submitted_at":"2026-01-01T00:00:01Z","commit_id":"bb11bb22bb33bb44bb55","state":"CHANGES_REQUESTED","user":{"login":"chatgpt-codex-connector[bot]"},"body":"See inline comment."}]\n'
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
CODEX_EVIDENCE_UNAVAILABLE_CORRELATION_GH
chmod +x "$_codex_evidence_unavailable_correlation_mock_dir/gh"
_codex_evidence_unavailable_correlation_output=""
_codex_evidence_unavailable_correlation_exit=0
PATH="$_codex_evidence_unavailable_correlation_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_evidence_unavailable_correlation_mock_dir/output.txt" 2>&1 || _codex_evidence_unavailable_correlation_exit=$?
_codex_evidence_unavailable_correlation_output="$(cat "$_codex_evidence_unavailable_correlation_mock_dir/output.txt")"
run_test "codex_evidence_unavailable_escalates_exit" "2" "$_codex_evidence_unavailable_correlation_exit"
run_test "codex_evidence_unavailable_escalates_reason" "REASON=evidence_unavailable_codex_thread_state" \
  "$(printf '%s\n' "$_codex_evidence_unavailable_correlation_output" | grep "^REASON=")"
rm -rf "$_codex_evidence_unavailable_correlation_mock_dir"
unset _codex_evidence_unavailable_correlation_mock_dir _codex_evidence_unavailable_correlation_output _codex_evidence_unavailable_correlation_exit

# AC-7, AC-9 (mixed case): one submitted review carrying BOTH a correlated,
# unresolved inline finding AND a blocking assertion in its own body — the
# body finding has no thread identity, so it escalates correlation-missing
# regardless of the correlated inline finding, in both a COMMENTED and a
# CHANGES_REQUESTED review state.
for _codex_mixed_state in COMMENTED CHANGES_REQUESTED; do
  _codex_mixed_finding_mock_dir="$(mktemp -d)"
  cat > "$_codex_mixed_finding_mock_dir/gh" <<CODEX_MIXED_FINDING_GH
#!/usr/bin/env bash
case "\$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'af11af22af33af44af55\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":509,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[{"id":705,"pull_request_review_id":805,"commit_id":"af11af22af33af44af55","body":"Correlated inline finding."}]\n'
    exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[{"id":805,"submitted_at":"2026-01-01T00:00:01Z","commit_id":"af11af22af33af44af55","state":"${_codex_mixed_state}","user":{"login":"chatgpt-codex-connector[bot]"},"body":"Blocking: also see the top-level summary."}]\n'
    exit 0 ;;
  *"api graphql"*"databaseId"*)
    printf '{"data":{"repository":{"pullRequest":{"reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[{"isResolved":false,"comments":{"nodes":[{"databaseId":705}]}}]}}}}}\n'
    exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "\$*" >&2
    exit 64 ;;
esac
CODEX_MIXED_FINDING_GH
  chmod +x "$_codex_mixed_finding_mock_dir/gh"
  _codex_mixed_finding_output=""
  _codex_mixed_finding_exit=0
  PATH="$_codex_mixed_finding_mock_dir:$PATH" \
    "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
    42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
    >"$_codex_mixed_finding_mock_dir/output.txt" 2>&1 || _codex_mixed_finding_exit=$?
  _codex_mixed_finding_output="$(cat "$_codex_mixed_finding_mock_dir/output.txt")"
  run_test "codex_mixed_inline_and_body_finding_escalates_${_codex_mixed_state}_exit" "2" "$_codex_mixed_finding_exit"
  run_test "codex_mixed_inline_and_body_finding_escalates_${_codex_mixed_state}_reason" "REASON=codex_finding_thread_correlation_missing" \
    "$(printf '%s\n' "$_codex_mixed_finding_output" | grep "^REASON=")"
  rm -rf "$_codex_mixed_finding_mock_dir"
  unset _codex_mixed_finding_mock_dir _codex_mixed_finding_output _codex_mixed_finding_exit
done
unset _codex_mixed_state

# AC-7, AC-9: one dedicated case under this exact name (matrix spot check;
# also the target of a planted-violation proof) — an unrecognized terminal
# verdict escalates, distinguishing it from the blocking/approved paths.
_codex_unrecognized_spot_mock_dir="$(mktemp -d)"
cat > "$_codex_unrecognized_spot_mock_dir/gh" <<'CODEX_UNRECOGNIZED_SPOT_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'fa11fa22fa33fa44fa55\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":510,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[{"submitted_at":"2026-01-01T00:00:01Z","commit_id":"fa11fa22fa33fa44fa55","user":{"login":"chatgpt-codex-connector[bot]"},"body":"An ambiguous status update with no recognized marker."}]\n'
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
CODEX_UNRECOGNIZED_SPOT_GH
chmod +x "$_codex_unrecognized_spot_mock_dir/gh"
_codex_unrecognized_spot_output=""
_codex_unrecognized_spot_exit=0
PATH="$_codex_unrecognized_spot_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_unrecognized_spot_mock_dir/output.txt" 2>&1 || _codex_unrecognized_spot_exit=$?
_codex_unrecognized_spot_output="$(cat "$_codex_unrecognized_spot_mock_dir/output.txt")"
run_test "codex_unrecognized_verdict_escalates_exit" "2" "$_codex_unrecognized_spot_exit"
run_test "codex_unrecognized_verdict_escalates_reason" "REASON=codex_current_verdict_unrecognized" \
  "$(printf '%s\n' "$_codex_unrecognized_spot_output" | grep "^REASON=")"
rm -rf "$_codex_unrecognized_spot_mock_dir"
unset _codex_unrecognized_spot_mock_dir _codex_unrecognized_spot_output _codex_unrecognized_spot_exit

# AC-13: a trigger-less live head (--pre-trigger-wait overrides Area 13's
# CODEX_GITHUB_PRE_TRIGGER_WAIT=0 export) with a marker-pinned clean root
# comment for that head is clean, proving the trigger-less path still
# authorizes readiness with the window test in place (K1 non-regression).
_codex_triggerless_clean_mock_dir="$(mktemp -d)"
cat > "$_codex_triggerless_clean_mock_dir/gh" <<'CODEX_TRIGGERLESS_CLEAN_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'ca11ca22ca33ca44ca55\n'; exit 0 ;;
  *"pr view"*createdAt*)
    printf '2025-12-31T00:00:00Z\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    jq -nc '[{id:611,created_at:"2026-01-01T00:00:00Z",user:{login:"chatgpt-codex-connector[bot]"},body:("Codex Review: Didn'\''t find any major issues. Swish! **Reviewed commit:** `ca11ca22ca33ca44ca55` <details> <summary>ℹ️ About Codex in GitHub</summary> <br/> [Your team has set up Codex to review pull requests in this repo](https://chatgpt.com/codex/cloud/settings/general). Reviews are triggered when you - Open a pull request for review - Mark a draft as ready - Comment \"@codex review\". If Codex has suggestions, it will comment; otherwise it will react with 👍. Codex can also answer questions or update the PR. Try commenting \"@codex address that feedback\". </details>")}]'
    exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"api graphql"*)
    printf '{"data":{"repository":{"pullRequest":{"headRefOid":"ca11ca22ca33ca44ca55","headRef":{"target":{"committedDate":"2025-12-31T00:00:00Z"}},"reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[]}}}}}\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_TRIGGERLESS_CLEAN_GH
chmod +x "$_codex_triggerless_clean_mock_dir/gh"
_codex_triggerless_clean_output=""
_codex_triggerless_clean_exit=0
PATH="$_codex_triggerless_clean_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 --pre-trigger-wait 1 \
  >"$_codex_triggerless_clean_mock_dir/output.txt" 2>&1 || _codex_triggerless_clean_exit=$?
_codex_triggerless_clean_output="$(cat "$_codex_triggerless_clean_mock_dir/output.txt")"
run_test "codex_triggerless_marker_pinned_clean_exit" "0" "$_codex_triggerless_clean_exit"
run_test "codex_triggerless_marker_pinned_clean_verdict" "VERDICT: APPROVED" \
  "$(printf '%s\n' "$_codex_triggerless_clean_output" | grep "^VERDICT:")"
rm -rf "$_codex_triggerless_clean_mock_dir"
unset _codex_triggerless_clean_mock_dir _codex_triggerless_clean_output _codex_triggerless_clean_exit

# ---------------------------------------------------------------------------
# #1757 (AC-13, AC-14, spec Business Rule 9): live-head evidence-window
# OCCUPANCY GUARD regression coverage. A SHA can occupy the pull request's
# head position more than once (a revert, or a force-push back), and the
# spec requires every Codex root comment to belong to exactly one head's
# evidence window: a comment authored during a FIRST occupancy of SHA `A`
# must never authorize readiness during a SECOND occupancy of `A` with no
# review in between. Four fixtures below prove: (1) the comment-based
# occupancy-raising input alone, (2) the head_ref_force_pushed timeline
# event alone, (3) that a genuine fresh review for the new occupancy still
# passes ("the boundary proved in both directions"), and (4) the fail-
# closed escalation when the timeline itself cannot be read.
# ---------------------------------------------------------------------------

# codex_marker_sha_reuse_prior_occupancy_not_clean: head A triggered and
# reviewed clean (occupancy 1), then a comment naming a DIFFERENT SHA B
# (occupancy 1's own valid stale/prior-revision evidence) is authored after
# it, then the head is force-pushed back to A with no new trigger. The old
# clean comment naming A predates the boundary the occupancy guard raises
# from B's newer comment evidence alone (input 1 — no timeline event is
# even present in this fixture), so it must NOT authorize a second-
# occupancy clean: expect waiting_on_reviewer / codex-github-review-pending.
_codex_sha_reuse_comment_mock_dir="$(mktemp -d)"
cat > "$_codex_sha_reuse_comment_mock_dir/gh" <<'CODEX_SHA_REUSE_COMMENT_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'aaaa1111aaaa1111aaaa1111aaaa1111aaaa1111\n'; exit 0 ;;
  *"--method POST"*)
    printf 'ERROR=duplicate-trigger-post\n' >&2
    exit 64 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    jq -nc '[
      {id:7001,created_at:"2026-01-01T00:00:00Z",user:{login:"alice"},body:"@codex review (review triggered by workflow runner, commit: aaaa1111aaaa)"},
      {id:8001,created_at:"2026-01-01T00:05:00Z",user:{login:"chatgpt-codex-connector[bot]"},body:("Codex Review: Didn'\''t find any major issues. Swish! **Reviewed commit:** `aaaa1111aaaa1111aaaa` <details> <summary>ℹ️ About Codex in GitHub</summary> <br/> [Your team has set up Codex to review pull requests in this repo](https://chatgpt.com/codex/cloud/settings/general). Reviews are triggered when you - Open a pull request for review - Mark a draft as ready - Comment \"@codex review\". If Codex has suggestions, it will comment; otherwise it will react with 👍. Codex can also answer questions or update the PR. Try commenting \"@codex address that feedback\". </details>")},
      {id:8002,created_at:"2026-01-01T00:10:00Z",user:{login:"chatgpt-codex-connector[bot]"},body:("Codex Review: Didn'\''t find any major issues. Nice! **Reviewed commit:** `bbbb2222bbbb2222bbbb` <details> <summary>ℹ️ About Codex in GitHub</summary> <br/> [Your team has set up Codex to review pull requests in this repo](https://chatgpt.com/codex/cloud/settings/general). Reviews are triggered when you - Open a pull request for review - Mark a draft as ready - Comment \"@codex review\". If Codex has suggestions, it will comment; otherwise it will react with 👍. Codex can also answer questions or update the PR. Try commenting \"@codex address that feedback\". </details>")}
    ]'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_SHA_REUSE_COMMENT_GH
chmod +x "$_codex_sha_reuse_comment_mock_dir/gh"
_codex_sha_reuse_comment_exit=0
PATH="$_codex_sha_reuse_comment_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_sha_reuse_comment_mock_dir/output.txt" 2>&1 || _codex_sha_reuse_comment_exit=$?
_codex_sha_reuse_comment_output="$(cat "$_codex_sha_reuse_comment_mock_dir/output.txt")"
run_test "codex_marker_sha_reuse_prior_occupancy_not_clean_exit" "4" "$_codex_sha_reuse_comment_exit"
run_test "codex_marker_sha_reuse_prior_occupancy_not_clean_reason" "REASON=codex-github-review-pending" \
  "$(printf '%s\n' "$_codex_sha_reuse_comment_output" | grep "^REASON=")"
run_test "codex_marker_sha_reuse_prior_occupancy_not_clean_no_duplicate_post" "0" \
  "$(grep_count_or_zero 'duplicate-trigger-post' "$_codex_sha_reuse_comment_mock_dir/output.txt")"
rm -rf "$_codex_sha_reuse_comment_mock_dir"
unset _codex_sha_reuse_comment_mock_dir _codex_sha_reuse_comment_output _codex_sha_reuse_comment_exit

# codex_marker_sha_reuse_force_push_only_not_clean: the intervening head
# produced NO Codex evidence and NO trigger of its own — the only signal
# that the head moved is a head_ref_force_pushed timeline event newer than
# A's trigger (input 2). The event's own commit_id is deliberately set to
# the LIVE head (A) to prove the guard does not filter events by
# commit_id — see the implementation plan's "Do not filter these events by
# commit_id" note (an A -> B -> A force-push sequence's FINAL event always
# names the live head). Expect the same wait outcome as above.
_codex_sha_reuse_event_mock_dir="$(mktemp -d)"
cat > "$_codex_sha_reuse_event_mock_dir/gh" <<'CODEX_SHA_REUSE_EVENT_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'aaaa1111aaaa1111aaaa1111aaaa1111aaaa1111\n'; exit 0 ;;
  *"--method POST"*)
    printf 'ERROR=duplicate-trigger-post\n' >&2
    exit 64 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    jq -nc '[{event:"head_ref_force_pushed",created_at:"2026-01-01T00:15:00Z",commit_id:"aaaa1111aaaa1111aaaa1111aaaa1111aaaa1111"}]'
    exit 0 ;;
  *"issues/"*"/comments"*)
    jq -nc '[
      {id:7101,created_at:"2026-01-01T00:00:00Z",user:{login:"alice"},body:"@codex review (review triggered by workflow runner, commit: aaaa1111aaaa)"},
      {id:8101,created_at:"2026-01-01T00:05:00Z",user:{login:"chatgpt-codex-connector[bot]"},body:("Codex Review: Didn'\''t find any major issues. Swish! **Reviewed commit:** `aaaa1111aaaa1111aaaa` <details> <summary>ℹ️ About Codex in GitHub</summary> <br/> [Your team has set up Codex to review pull requests in this repo](https://chatgpt.com/codex/cloud/settings/general). Reviews are triggered when you - Open a pull request for review - Mark a draft as ready - Comment \"@codex review\". If Codex has suggestions, it will comment; otherwise it will react with 👍. Codex can also answer questions or update the PR. Try commenting \"@codex address that feedback\". </details>")}
    ]'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_SHA_REUSE_EVENT_GH
chmod +x "$_codex_sha_reuse_event_mock_dir/gh"
_codex_sha_reuse_event_exit=0
PATH="$_codex_sha_reuse_event_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_sha_reuse_event_mock_dir/output.txt" 2>&1 || _codex_sha_reuse_event_exit=$?
_codex_sha_reuse_event_output="$(cat "$_codex_sha_reuse_event_mock_dir/output.txt")"
run_test "codex_marker_sha_reuse_force_push_only_not_clean_exit" "4" "$_codex_sha_reuse_event_exit"
run_test "codex_marker_sha_reuse_force_push_only_not_clean_reason" "REASON=codex-github-review-pending" \
  "$(printf '%s\n' "$_codex_sha_reuse_event_output" | grep "^REASON=")"
rm -rf "$_codex_sha_reuse_event_mock_dir"
unset _codex_sha_reuse_event_mock_dir _codex_sha_reuse_event_output _codex_sha_reuse_event_exit

# codex_marker_sha_reuse_new_trigger_clean: "the boundary proved in both
# directions" — a genuinely fresh trigger for the second occupancy, with a
# NEW clean comment authored after both that trigger AND a
# head_ref_force_pushed event that lands between them, must still reach
# clean readiness. No non-bot trigger comment exists yet in this fixture
# (only the stale first-occupancy clean comment, itself already excluded
# by the ordinary post-trigger freshness filter), so the idempotency check
# finds nothing and posts a genuinely fresh trigger.
_codex_sha_reuse_new_trigger_mock_dir="$(mktemp -d)"
cat > "$_codex_sha_reuse_new_trigger_mock_dir/gh" <<'CODEX_SHA_REUSE_NEW_TRIGGER_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'aaaa1111aaaa1111aaaa1111aaaa1111aaaa1111\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":9201,"created_at":"2026-01-01T00:15:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    jq -nc '[{event:"head_ref_force_pushed",created_at:"2026-01-01T00:16:00Z",commit_id:"aaaa1111aaaa1111aaaa1111aaaa1111aaaa1111"}]'
    exit 0 ;;
  *"issues/"*"/comments"*)
    jq -nc '[
      {id:8201,created_at:"2026-01-01T00:05:00Z",user:{login:"chatgpt-codex-connector[bot]"},body:("Codex Review: Didn'\''t find any major issues. Swish! **Reviewed commit:** `aaaa1111aaaa1111aaaa` <details> <summary>ℹ️ About Codex in GitHub</summary> <br/> [Your team has set up Codex to review pull requests in this repo](https://chatgpt.com/codex/cloud/settings/general). Reviews are triggered when you - Open a pull request for review - Mark a draft as ready - Comment \"@codex review\". If Codex has suggestions, it will comment; otherwise it will react with 👍. Codex can also answer questions or update the PR. Try commenting \"@codex address that feedback\". </details>")},
      {id:9202,created_at:"2026-01-01T00:20:00Z",user:{login:"chatgpt-codex-connector[bot]"},body:("Codex Review: Didn'\''t find any major issues. Nice! **Reviewed commit:** `aaaa1111aaaa1111aaaa` <details> <summary>ℹ️ About Codex in GitHub</summary> <br/> [Your team has set up Codex to review pull requests in this repo](https://chatgpt.com/codex/cloud/settings/general). Reviews are triggered when you - Open a pull request for review - Mark a draft as ready - Comment \"@codex review\". If Codex has suggestions, it will comment; otherwise it will react with 👍. Codex can also answer questions or update the PR. Try commenting \"@codex address that feedback\". </details>")}
    ]'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_SHA_REUSE_NEW_TRIGGER_GH
chmod +x "$_codex_sha_reuse_new_trigger_mock_dir/gh"
_codex_sha_reuse_new_trigger_exit=0
PATH="$_codex_sha_reuse_new_trigger_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_sha_reuse_new_trigger_mock_dir/output.txt" 2>&1 || _codex_sha_reuse_new_trigger_exit=$?
_codex_sha_reuse_new_trigger_output="$(cat "$_codex_sha_reuse_new_trigger_mock_dir/output.txt")"
run_test "codex_marker_sha_reuse_new_trigger_clean_exit" "0" "$_codex_sha_reuse_new_trigger_exit"
run_test "codex_marker_sha_reuse_new_trigger_clean_verdict" "VERDICT: APPROVED" \
  "$(printf '%s\n' "$_codex_sha_reuse_new_trigger_output" | grep "^VERDICT:")"
rm -rf "$_codex_sha_reuse_new_trigger_mock_dir"
unset _codex_sha_reuse_new_trigger_mock_dir _codex_sha_reuse_new_trigger_output _codex_sha_reuse_new_trigger_exit

# codex_marker_boundary_unreadable: the occupancy guard's own timeline read
# fails (and fails again on its one retry) — this is the fail-closed
# "boundary unreadable" escalation (implementation plan: "A timeline read
# that fails or truncates after one retry is the boundary unreadable
# escalation... not a silent skip"), never a silent skip that would leave
# the window test unapplied. Expect the same fail-closed escalation code
# as every other #1757 evidence-unavailable case.
_codex_occupancy_boundary_unreadable_mock_dir="$(mktemp -d)"
cat > "$_codex_occupancy_boundary_unreadable_mock_dir/gh" <<'CODEX_OCCUPANCY_BOUNDARY_UNREADABLE_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'aaaa1111aaaa1111aaaa1111aaaa1111aaaa1111\n'; exit 0 ;;
  *"--method POST"*)
    printf 'ERROR=duplicate-trigger-post\n' >&2
    exit 64 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf 'ERROR=timeline-unavailable\n' >&2
    exit 64 ;;
  *"issues/"*"/comments"*)
    jq -nc '[{id:7301,created_at:"2026-01-01T00:00:00Z",user:{login:"alice"},body:"@codex review (review triggered by workflow runner, commit: aaaa1111aaaa)"}]'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_OCCUPANCY_BOUNDARY_UNREADABLE_GH
chmod +x "$_codex_occupancy_boundary_unreadable_mock_dir/gh"
_codex_occupancy_boundary_unreadable_exit=0
PATH="$_codex_occupancy_boundary_unreadable_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_occupancy_boundary_unreadable_mock_dir/output.txt" 2>&1 || _codex_occupancy_boundary_unreadable_exit=$?
_codex_occupancy_boundary_unreadable_output="$(cat "$_codex_occupancy_boundary_unreadable_mock_dir/output.txt")"
run_test "codex_marker_boundary_unreadable_exit" "2" "$_codex_occupancy_boundary_unreadable_exit"
run_test "codex_marker_boundary_unreadable_reason" "REASON=evidence_unavailable_codex_thread_state" \
  "$(printf '%s\n' "$_codex_occupancy_boundary_unreadable_output" | grep "^REASON=")"
rm -rf "$_codex_occupancy_boundary_unreadable_mock_dir"
unset _codex_occupancy_boundary_unreadable_mock_dir _codex_occupancy_boundary_unreadable_output _codex_occupancy_boundary_unreadable_exit

# Pass 1 follow-up (PR #1780, same class as codex_cr_blocker_malformed_jq_
# output_fails_closed above): a successful jq invocation over well-formed
# input always emits a plain integer for the occupancy guard's own
# unusable-event count, so this path is not reachable through the real `jq`
# binary today. This test forces it by shadowing `jq` on PATH with a stub
# that answers the guard's unusable-count filter with non-numeric output
# (exit 0) while delegating every other jq call to the real binary,
# proving codex_compute_occupancy_boundary's own numeric sanitizer fails
# closed (CODEX_OCCUPANCY_BOUNDARY_UNAVAILABLE=1) instead of letting an
# unsanitized `[ "$unusable_count" -gt 0 ]` integer-comparison error
# silently fall through as "no unusable event found" — spec Business Rule
# 9 requires this guard to fail closed on an unreadable boundary.
_codex_occ_boundary_malformed_real_jq="$(command -v jq)"
_codex_occ_boundary_malformed_mock_dir="$(mktemp -d)"
cat > "$_codex_occ_boundary_malformed_mock_dir/gh" <<'CODEX_OCC_BOUNDARY_MALFORMED_GH'
#!/usr/bin/env bash
case "$*" in
  *"issues/"*"/timeline"*)
    printf '[{"event":"head_ref_force_pushed","created_at":"2026-02-01T00:00:00Z"}]\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_OCC_BOUNDARY_MALFORMED_GH
chmod +x "$_codex_occ_boundary_malformed_mock_dir/gh"
cat > "$_codex_occ_boundary_malformed_mock_dir/jq" <<CODEX_OCC_BOUNDARY_MALFORMED_JQ
#!/usr/bin/env bash
case "\$*" in
  *"select(.created_at == null"*)
    cat >/dev/null
    printf 'not-a-number\n'
    exit 0 ;;
  *)
    exec "$_codex_occ_boundary_malformed_real_jq" "\$@" ;;
esac
CODEX_OCC_BOUNDARY_MALFORMED_JQ
chmod +x "$_codex_occ_boundary_malformed_mock_dir/jq"
CODEX_OCCUPANCY_BOUNDARY_UNAVAILABLE=0
PATH="$_codex_occ_boundary_malformed_mock_dir:$PATH" \
  codex_compute_occupancy_boundary "owner" "repo" "42" "2026-01-01T00:00:00Z"
run_test "codex_occupancy_boundary_malformed_jq_output_fails_closed" "1" "$CODEX_OCCUPANCY_BOUNDARY_UNAVAILABLE"
rm -rf "$_codex_occ_boundary_malformed_mock_dir"
unset _codex_occ_boundary_malformed_mock_dir _codex_occ_boundary_malformed_real_jq CODEX_OCCUPANCY_BOUNDARY_TIME CODEX_OCCUPANCY_BOUNDARY_UNAVAILABLE

# ---------------------------------------------------------------------------
# #1757 follow-up (AC-13, AC-14, spec Business Rule 9): the occupancy guard
# above was originally wired only into the four TRIGGERED live-head call
# sites. A Step 7a code review found — and reproduced against the
# unmodified script — that the TRIGGER-LESS pre-check path
# (codex_fetch_existing_current_head_evidence, the common case when Codex's
# GitHub App auto-reviews a push before this workflow ever posts its own
# trigger comment) had no occupancy protection at all: a stale
# marker-pinned clean comment for SHA A, a comment naming a different SHA B
# with real blocking findings (an intervening occupancy), and the live head
# reverted to A with no new trigger posted, was read as clean and returned
# VERDICT: APPROVED. The four fixtures below mirror the triggered-path
# coverage above for this path: (1) the exact reproduced scenario, (2) the
# force-push-only signal alone (no comment ever named the intervening SHA),
# (3) a genuine fresh clean case with the guard active but no real reuse —
# proving it is not over-eager, and (4) the fail-closed escalation when the
# occupancy guard's own timeline read cannot be established.
# ---------------------------------------------------------------------------

# codex_triggerless_sha_reuse_comment_not_approved: head A triggered and
# reviewed clean during a FIRST occupancy (comment id 9001), then a comment
# naming a DIFFERENT SHA B with real blocking findings (id 9002, occupancy
# 1's own valid prior-revision evidence) is authored after it, then the
# head is force-pushed back to A with no new trigger posted for THIS run —
# the trigger-less pre-check runs before any trigger exists. B's newer
# comment evidence alone (no timeline event is even present in this
# fixture) raises the occupancy boundary past A's stale first-occupancy
# comment, so the pre-check must find no terminal evidence, fall through to
# the ordinary idempotency/trigger-post path (no existing trigger for A
# exists either — comment 9001/9002 are both bot-authored, so the
# idempotency check's non-bot filter excludes them), post a fresh trigger,
# and time out waiting for a genuine review of this occupancy: never
# VERDICT: APPROVED.
_codex_triggerless_sha_reuse_comment_mock_dir="$(mktemp -d)"
cat > "$_codex_triggerless_sha_reuse_comment_mock_dir/gh" <<'CODEX_TRIGGERLESS_SHA_REUSE_COMMENT_GH'
#!/usr/bin/env bash
log="$MOCK_POST_LOG"
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'cccc5555cccc5555cccc5555cccc5555cccc5555\n'; exit 0 ;;
  *"pr view"*createdAt*)
    printf '2025-12-31T00:00:00Z\n'; exit 0 ;;
  *"--method POST"*)
    printf 'POST\n' >> "$log"
    printf '{"id":9401,"created_at":"2026-01-01T00:10:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    jq -nc '[
      {id:9001,created_at:"2026-01-01T00:00:00Z",user:{login:"chatgpt-codex-connector[bot]"},body:("Codex Review: Didn'\''t find any major issues. Swish! **Reviewed commit:** `cccc5555cccc5555cccc` <details> <summary>ℹ️ About Codex in GitHub</summary> <br/> [Your team has set up Codex to review pull requests in this repo](https://chatgpt.com/codex/cloud/settings/general). Reviews are triggered when you - Open a pull request for review - Mark a draft as ready - Comment \"@codex review\". If Codex has suggestions, it will comment; otherwise it will react with 👍. Codex can also answer questions or update the PR. Try commenting \"@codex address that feedback\". </details>")},
      {id:9002,created_at:"2026-01-01T00:05:00Z",user:{login:"chatgpt-codex-connector[bot]"},body:("Codex Review: Found a real bug that must be fixed. **Reviewed commit:** `dddd6666dddd6666dddd`")}
    ]'
    exit 0 ;;
  *"api graphql"*)
    printf '{"data":{"repository":{"pullRequest":{"headRefOid":"cccc5555cccc5555cccc5555cccc5555cccc5555","headRef":{"target":{"committedDate":"2026-01-01T00:00:00Z"}},"reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[]}}}}}\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_TRIGGERLESS_SHA_REUSE_COMMENT_GH
chmod +x "$_codex_triggerless_sha_reuse_comment_mock_dir/gh"
: > "$_codex_triggerless_sha_reuse_comment_mock_dir/posts.log"
_codex_triggerless_sha_reuse_comment_exit=0
MOCK_POST_LOG="$_codex_triggerless_sha_reuse_comment_mock_dir/posts.log" PATH="$_codex_triggerless_sha_reuse_comment_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 --pre-trigger-wait 1 \
  >"$_codex_triggerless_sha_reuse_comment_mock_dir/output.txt" 2>&1 || _codex_triggerless_sha_reuse_comment_exit=$?
_codex_triggerless_sha_reuse_comment_output="$(cat "$_codex_triggerless_sha_reuse_comment_mock_dir/output.txt")"
run_test "codex_triggerless_sha_reuse_comment_not_approved_exit" "4" "$_codex_triggerless_sha_reuse_comment_exit"
run_test "codex_triggerless_sha_reuse_comment_not_approved_reason" "REASON=codex-github-review-pending" \
  "$(printf '%s\n' "$_codex_triggerless_sha_reuse_comment_output" | grep "^REASON=")"
run_test "codex_triggerless_sha_reuse_comment_not_approved_no_approved_verdict" "0" \
  "$(grep_count_or_zero '^VERDICT: APPROVED' "$_codex_triggerless_sha_reuse_comment_mock_dir/output.txt")"
run_test "codex_triggerless_sha_reuse_comment_not_approved_posts_fresh_trigger" "1" \
  "$(wc -l < "$_codex_triggerless_sha_reuse_comment_mock_dir/posts.log" | tr -d ' ')"
rm -rf "$_codex_triggerless_sha_reuse_comment_mock_dir"
unset _codex_triggerless_sha_reuse_comment_mock_dir _codex_triggerless_sha_reuse_comment_output _codex_triggerless_sha_reuse_comment_exit

# codex_triggerless_sha_reuse_force_push_only_not_approved: the intervening
# head produced NO Codex evidence and NO trigger of its own — the only
# signal that the head moved is a head_ref_force_pushed timeline event
# newer than the sole clean comment for A. The event's own commit_id is
# deliberately set to the LIVE head (A) to prove the guard does not filter
# events by commit_id (an A -> B -> A force-push sequence's FINAL event
# always names the live head). Expect the same not-approved/pending
# outcome as above, proving SHA reuse is caught even with zero comment
# evidence about the intervening occupancy.
_codex_triggerless_sha_reuse_event_mock_dir="$(mktemp -d)"
cat > "$_codex_triggerless_sha_reuse_event_mock_dir/gh" <<'CODEX_TRIGGERLESS_SHA_REUSE_EVENT_GH'
#!/usr/bin/env bash
log="$MOCK_POST_LOG"
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'eeee7777eeee7777eeee7777eeee7777eeee7777\n'; exit 0 ;;
  *"pr view"*createdAt*)
    printf '2025-12-31T00:00:00Z\n'; exit 0 ;;
  *"--method POST"*)
    printf 'POST\n' >> "$log"
    printf '{"id":9402,"created_at":"2026-01-01T00:20:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    jq -nc '[{event:"head_ref_force_pushed",created_at:"2026-01-01T00:15:00Z",commit_id:"eeee7777eeee7777eeee7777eeee7777eeee7777"}]'
    exit 0 ;;
  *"issues/"*"/comments"*)
    jq -nc '[
      {id:9101,created_at:"2026-01-01T00:00:00Z",user:{login:"chatgpt-codex-connector[bot]"},body:("Codex Review: Didn'\''t find any major issues. Swish! **Reviewed commit:** `eeee7777eeee7777eeee` <details> <summary>ℹ️ About Codex in GitHub</summary> <br/> [Your team has set up Codex to review pull requests in this repo](https://chatgpt.com/codex/cloud/settings/general). Reviews are triggered when you - Open a pull request for review - Mark a draft as ready - Comment \"@codex review\". If Codex has suggestions, it will comment; otherwise it will react with 👍. Codex can also answer questions or update the PR. Try commenting \"@codex address that feedback\". </details>")}
    ]'
    exit 0 ;;
  *"api graphql"*)
    printf '{"data":{"repository":{"pullRequest":{"headRefOid":"eeee7777eeee7777eeee7777eeee7777eeee7777","headRef":{"target":{"committedDate":"2026-01-01T00:00:00Z"}},"reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[]}}}}}\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_TRIGGERLESS_SHA_REUSE_EVENT_GH
chmod +x "$_codex_triggerless_sha_reuse_event_mock_dir/gh"
: > "$_codex_triggerless_sha_reuse_event_mock_dir/posts.log"
_codex_triggerless_sha_reuse_event_exit=0
MOCK_POST_LOG="$_codex_triggerless_sha_reuse_event_mock_dir/posts.log" PATH="$_codex_triggerless_sha_reuse_event_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 --pre-trigger-wait 1 \
  >"$_codex_triggerless_sha_reuse_event_mock_dir/output.txt" 2>&1 || _codex_triggerless_sha_reuse_event_exit=$?
_codex_triggerless_sha_reuse_event_output="$(cat "$_codex_triggerless_sha_reuse_event_mock_dir/output.txt")"
run_test "codex_triggerless_sha_reuse_force_push_only_not_approved_exit" "4" "$_codex_triggerless_sha_reuse_event_exit"
run_test "codex_triggerless_sha_reuse_force_push_only_not_approved_reason" "REASON=codex-github-review-pending" \
  "$(printf '%s\n' "$_codex_triggerless_sha_reuse_event_output" | grep "^REASON=")"
run_test "codex_triggerless_sha_reuse_force_push_only_not_approved_no_approved_verdict" "0" \
  "$(grep_count_or_zero '^VERDICT: APPROVED' "$_codex_triggerless_sha_reuse_event_mock_dir/output.txt")"
rm -rf "$_codex_triggerless_sha_reuse_event_mock_dir"
unset _codex_triggerless_sha_reuse_event_mock_dir _codex_triggerless_sha_reuse_event_output _codex_triggerless_sha_reuse_event_exit

# codex_triggerless_genuine_fresh_clean_with_guard_active: an OLDER
# head_ref_force_pushed event predates the sole marker-pinned clean
# comment for the live head — the occupancy guard raises the boundary to
# the event's time, but the comment is still STRICTLY newer than it, so
# this is genuine current-occupancy evidence and must still authorize
# readiness. Proves the guard is not over-eager: an event's mere presence
# does not invalidate a review that already covers this same occupancy.
_codex_triggerless_genuine_fresh_clean_mock_dir="$(mktemp -d)"
cat > "$_codex_triggerless_genuine_fresh_clean_mock_dir/gh" <<'CODEX_TRIGGERLESS_GENUINE_FRESH_CLEAN_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'ffff8888ffff8888ffff8888ffff8888ffff8888\n'; exit 0 ;;
  *"pr view"*createdAt*)
    printf '2025-12-31T00:00:00Z\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    jq -nc '[{event:"head_ref_force_pushed",created_at:"2025-12-31T12:00:00Z",commit_id:"ffff8888ffff8888ffff8888ffff8888ffff8888"}]'
    exit 0 ;;
  *"issues/"*"/comments"*)
    jq -nc '[{id:9201,created_at:"2026-01-01T00:00:00Z",user:{login:"chatgpt-codex-connector[bot]"},body:("Codex Review: Didn'\''t find any major issues. Swish! **Reviewed commit:** `ffff8888ffff8888ffff` <details> <summary>ℹ️ About Codex in GitHub</summary> <br/> [Your team has set up Codex to review pull requests in this repo](https://chatgpt.com/codex/cloud/settings/general). Reviews are triggered when you - Open a pull request for review - Mark a draft as ready - Comment \"@codex review\". If Codex has suggestions, it will comment; otherwise it will react with 👍. Codex can also answer questions or update the PR. Try commenting \"@codex address that feedback\". </details>")}]'
    exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"api graphql"*)
    printf '{"data":{"repository":{"pullRequest":{"headRefOid":"ffff8888ffff8888ffff8888ffff8888ffff8888","headRef":{"target":{"committedDate":"2025-12-31T00:00:00Z"}},"reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[]}}}}}\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_TRIGGERLESS_GENUINE_FRESH_CLEAN_GH
chmod +x "$_codex_triggerless_genuine_fresh_clean_mock_dir/gh"
_codex_triggerless_genuine_fresh_clean_exit=0
PATH="$_codex_triggerless_genuine_fresh_clean_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 --pre-trigger-wait 1 \
  >"$_codex_triggerless_genuine_fresh_clean_mock_dir/output.txt" 2>&1 || _codex_triggerless_genuine_fresh_clean_exit=$?
_codex_triggerless_genuine_fresh_clean_output="$(cat "$_codex_triggerless_genuine_fresh_clean_mock_dir/output.txt")"
run_test "codex_triggerless_genuine_fresh_clean_with_guard_active_exit" "0" "$_codex_triggerless_genuine_fresh_clean_exit"
run_test "codex_triggerless_genuine_fresh_clean_with_guard_active_verdict" "VERDICT: APPROVED" \
  "$(printf '%s\n' "$_codex_triggerless_genuine_fresh_clean_output" | grep "^VERDICT:")"
rm -rf "$_codex_triggerless_genuine_fresh_clean_mock_dir"
unset _codex_triggerless_genuine_fresh_clean_mock_dir _codex_triggerless_genuine_fresh_clean_output _codex_triggerless_genuine_fresh_clean_exit

# codex_triggerless_boundary_unreadable: the trigger-less occupancy guard's
# own timeline read fails (and fails again on its one retry) BEFORE the
# pre-check ever reads a single comment — this is the fail-closed
# "boundary unreadable" escalation, never a silent skip that would leave
# the trigger-less window test unapplied. Expect the same fail-closed
# escalation code as the triggered-path equivalent above, and confirm no
# trigger was ever posted (the escalation must fire before that step).
_codex_triggerless_boundary_unreadable_mock_dir="$(mktemp -d)"
cat > "$_codex_triggerless_boundary_unreadable_mock_dir/gh" <<'CODEX_TRIGGERLESS_BOUNDARY_UNREADABLE_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf '0123abcd0123abcd0123abcd0123abcd0123abcd\n'; exit 0 ;;
  *"pr view"*createdAt*)
    printf '2025-12-31T00:00:00Z\n'; exit 0 ;;
  *"--method POST"*)
    printf 'ERROR=duplicate-trigger-post\n' >&2
    exit 64 ;;
  *"issues/"*"/timeline"*)
    printf 'ERROR=timeline-unavailable\n' >&2
    exit 64 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"api graphql"*)
    printf '{"data":{"repository":{"pullRequest":{"headRefOid":"0123abcd0123abcd0123abcd0123abcd0123abcd","headRef":{"target":{"committedDate":"2025-12-31T00:00:00Z"}},"reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[]}}}}}\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_TRIGGERLESS_BOUNDARY_UNREADABLE_GH
chmod +x "$_codex_triggerless_boundary_unreadable_mock_dir/gh"
_codex_triggerless_boundary_unreadable_exit=0
PATH="$_codex_triggerless_boundary_unreadable_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 --pre-trigger-wait 1 \
  >"$_codex_triggerless_boundary_unreadable_mock_dir/output.txt" 2>&1 || _codex_triggerless_boundary_unreadable_exit=$?
_codex_triggerless_boundary_unreadable_output="$(cat "$_codex_triggerless_boundary_unreadable_mock_dir/output.txt")"
run_test "codex_triggerless_boundary_unreadable_exit" "2" "$_codex_triggerless_boundary_unreadable_exit"
run_test "codex_triggerless_boundary_unreadable_reason" "REASON=evidence_unavailable_codex_thread_state" \
  "$(printf '%s\n' "$_codex_triggerless_boundary_unreadable_output" | grep "^REASON=")"
run_test "codex_triggerless_boundary_unreadable_no_duplicate_post" "0" \
  "$(grep_count_or_zero 'duplicate-trigger-post' "$_codex_triggerless_boundary_unreadable_mock_dir/output.txt")"
rm -rf "$_codex_triggerless_boundary_unreadable_mock_dir"
unset _codex_triggerless_boundary_unreadable_mock_dir _codex_triggerless_boundary_unreadable_output _codex_triggerless_boundary_unreadable_exit

# ---------------------------------------------------------------------------
# #1757 follow-up (BR-9): the trigger-less occupancy guard above closed the
# gap for ROOT-COMMENT evidence in codex_fetch_existing_current_head_evidence,
# but the SAME function also fetches SUBMITTED REVIEW evidence
# (`pulls/{pr}/reviews`) via a completely separate, unguarded query: it
# filtered only by commit_id == live head, with no floor on submitted_at at
# all. GitHub's Reviews endpoint returns every review ever submitted for the
# PR, including one submitted during an EARLIER occupancy of the same head
# SHA — a Step 7a code review reproduced this against the unmodified script:
# a clean APPROVED review for SHA A submitted during a first occupancy,
# followed by a head_ref_force_pushed timeline event (the intervening
# occupancy), with the head reverted back to A and no new review submitted
# for this second occupancy, still returned VERDICT: APPROVED — the same
# false-clean class BR-9 forbids, via review evidence instead of a comment.
# The four TRIGGERED review queries elsewhere in this script are already
# occupancy-safe by construction (`submitted_at >= $trigger_time`, and a
# trigger for the current occupancy always postdates any earlier occupancy's
# reviews); only this trigger-less pre-check lacked an equivalent floor.
# ---------------------------------------------------------------------------

# codex_triggerless_stale_review_reuse_not_approved: a clean APPROVED review
# for the live head SHA was submitted during a FIRST occupancy, then the head
# was force-pushed away and back (a head_ref_force_pushed event newer than
# that review) with no new review ever submitted for this SECOND occupancy.
# Must not be approved from the stale review alone.
_codex_triggerless_stale_review_mock_dir="$(mktemp -d)"
cat > "$_codex_triggerless_stale_review_mock_dir/gh" <<'CODEX_TRIGGERLESS_STALE_REVIEW_GH'
#!/usr/bin/env bash
log="$MOCK_POST_LOG"
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf '1111aaaa1111aaaa1111aaaa1111aaaa1111aaaa\n'; exit 0 ;;
  *"pr view"*createdAt*)
    printf '2025-12-31T00:00:00Z\n'; exit 0 ;;
  *"--method POST"*)
    printf 'POST\n' >> "$log"
    printf '{"id":9501,"created_at":"2026-01-01T00:20:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    jq -nc '[{submitted_at:"2026-01-01T00:00:00Z",commit_id:"1111aaaa1111aaaa1111aaaa1111aaaa1111aaaa",state:"APPROVED",user:{login:"chatgpt-codex-connector[bot]"},body:("Codex Review: Didn'\''t find any major issues. Swish! **Reviewed commit:** `1111aaaa1111` <details> <summary>ℹ️ About Codex in GitHub</summary> <br/> [Your team has set up Codex to review pull requests in this repo](https://chatgpt.com/codex/cloud/settings/general). Reviews are triggered when you - Open a pull request for review - Mark a draft as ready - Comment \"@codex review\". If Codex has suggestions, it will comment; otherwise it will react with 👍. Codex can also answer questions or update the PR. Try commenting \"@codex address that feedback\". </details>")}]'
    exit 0 ;;
  *"issues/"*"/timeline"*)
    jq -nc '[{event:"head_ref_force_pushed",created_at:"2026-01-01T00:15:00Z",commit_id:"1111aaaa1111aaaa1111aaaa1111aaaa1111aaaa"}]'
    exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"api graphql"*)
    printf '{"data":{"repository":{"pullRequest":{"headRefOid":"1111aaaa1111aaaa1111aaaa1111aaaa1111aaaa","headRef":{"target":{"committedDate":"2026-01-01T00:00:00Z"}},"reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[]}}}}}\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_TRIGGERLESS_STALE_REVIEW_GH
chmod +x "$_codex_triggerless_stale_review_mock_dir/gh"
: > "$_codex_triggerless_stale_review_mock_dir/posts.log"
_codex_triggerless_stale_review_exit=0
MOCK_POST_LOG="$_codex_triggerless_stale_review_mock_dir/posts.log" PATH="$_codex_triggerless_stale_review_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 --pre-trigger-wait 1 \
  >"$_codex_triggerless_stale_review_mock_dir/output.txt" 2>&1 || _codex_triggerless_stale_review_exit=$?
_codex_triggerless_stale_review_output="$(cat "$_codex_triggerless_stale_review_mock_dir/output.txt")"
run_test "codex_triggerless_stale_review_reuse_not_approved_exit" "4" "$_codex_triggerless_stale_review_exit"
run_test "codex_triggerless_stale_review_reuse_not_approved_reason" "REASON=codex-github-review-pending" \
  "$(printf '%s\n' "$_codex_triggerless_stale_review_output" | grep "^REASON=")"
run_test "codex_triggerless_stale_review_reuse_not_approved_no_approved_verdict" "0" \
  "$(grep_count_or_zero '^VERDICT: APPROVED' "$_codex_triggerless_stale_review_mock_dir/output.txt")"
run_test "codex_triggerless_stale_review_reuse_not_approved_posts_fresh_trigger" "1" \
  "$(wc -l < "$_codex_triggerless_stale_review_mock_dir/posts.log" | tr -d ' ')"
rm -rf "$_codex_triggerless_stale_review_mock_dir"
unset _codex_triggerless_stale_review_mock_dir _codex_triggerless_stale_review_output _codex_triggerless_stale_review_exit

# codex_triggerless_genuine_fresh_review_clean_still_works: a clean APPROVED
# review for the live head, submitted after PR creation, with NO intervening
# timeline event at all. Proves the new submitted_at floor is not over-eager
# — a genuine first-occupancy clean review must still authorize readiness.
_codex_triggerless_fresh_review_mock_dir="$(mktemp -d)"
cat > "$_codex_triggerless_fresh_review_mock_dir/gh" <<'CODEX_TRIGGERLESS_FRESH_REVIEW_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf '2222bbbb2222bbbb2222bbbb2222bbbb2222bbbb\n'; exit 0 ;;
  *"pr view"*createdAt*)
    printf '2025-12-31T00:00:00Z\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    jq -nc '[{submitted_at:"2026-01-01T00:00:00Z",commit_id:"2222bbbb2222bbbb2222bbbb2222bbbb2222bbbb",state:"APPROVED",user:{login:"chatgpt-codex-connector[bot]"},body:("Codex Review: Didn'\''t find any major issues. Swish! **Reviewed commit:** `2222bbbb2222` <details> <summary>ℹ️ About Codex in GitHub</summary> <br/> [Your team has set up Codex to review pull requests in this repo](https://chatgpt.com/codex/cloud/settings/general). Reviews are triggered when you - Open a pull request for review - Mark a draft as ready - Comment \"@codex review\". If Codex has suggestions, it will comment; otherwise it will react with 👍. Codex can also answer questions or update the PR. Try commenting \"@codex address that feedback\". </details>")}]'
    exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"api graphql"*)
    printf '{"data":{"repository":{"pullRequest":{"headRefOid":"2222bbbb2222bbbb2222bbbb2222bbbb2222bbbb","headRef":{"target":{"committedDate":"2026-01-01T00:00:00Z"}},"reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[]}}}}}\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_TRIGGERLESS_FRESH_REVIEW_GH
chmod +x "$_codex_triggerless_fresh_review_mock_dir/gh"
_codex_triggerless_fresh_review_exit=0
PATH="$_codex_triggerless_fresh_review_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 --pre-trigger-wait 1 \
  >"$_codex_triggerless_fresh_review_mock_dir/output.txt" 2>&1 || _codex_triggerless_fresh_review_exit=$?
_codex_triggerless_fresh_review_output="$(cat "$_codex_triggerless_fresh_review_mock_dir/output.txt")"
run_test "codex_triggerless_genuine_fresh_review_clean_still_works_exit" "0" "$_codex_triggerless_fresh_review_exit"
run_test "codex_triggerless_genuine_fresh_review_clean_still_works_verdict" "VERDICT: APPROVED" \
  "$(printf '%s\n' "$_codex_triggerless_fresh_review_output" | grep "^VERDICT:")"
rm -rf "$_codex_triggerless_fresh_review_mock_dir"
unset _codex_triggerless_fresh_review_mock_dir _codex_triggerless_fresh_review_output _codex_triggerless_fresh_review_exit

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "Tests: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
