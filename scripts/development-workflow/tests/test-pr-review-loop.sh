#!/usr/bin/env bash
# test-pr-review-loop.sh — Self-contained test harness for pr-review-loop.sh.
#
# Exercises five highest-risk logic areas:
#   1. normalize_platform_verdict (verdict normalization / mapping)
#   2. check_unreplied_rest_comments (bot-account exclusion, reply detection)
#   3. append_compare_metrics_row (compare-mode platform config change detection)
#   4. Lock cleanup on SIGTERM (signal trap removes lockdir before exit)
#   5. draft/ready lifecycle config parsing and membership detection
#
# Usage: bash scripts/development-workflow/tests/test-pr-review-loop.sh
# No external tooling required beyond bash and git (git is used only to locate
# the repository root at startup; mock gh commands replace all network calls).
#
# Exit code: 0 if all tests pass, 1 if any test fails.

set -euo pipefail

# ---------------------------------------------------------------------------
# Locate repository root (works inside worktrees and normal checkouts).
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
# Locate repo root from the script's directory.
# Use --show-toplevel so the path resolves to the current worktree root
# (correct when the harness runs inside a linked worktree).
REPO_ROOT="$(cd "$SCRIPT_DIR" && git rev-parse --show-toplevel)"

# ---------------------------------------------------------------------------
# Mock PATH setup — create a temp dir with stub commands for gh and git.
# Each mock reads its output from an environment variable set by the test case.
# ---------------------------------------------------------------------------
MOCK_BIN="$(mktemp -d)"
_METRICS_TMP=""
_METRICS_DIR=""
_CONFIG_DIR=""

# Single EXIT trap: normalise SIGPIPE exit code (141 -> 0) and clean up temp
# directories. A second trap would override this one, losing the 141 guard.
_harness_exit() {
  local status=$?
  rm -rf "$MOCK_BIN"
  [ -n "${_METRICS_DIR:-}" ] && rm -rf "$_METRICS_DIR"
  [ -n "${_CONFIG_DIR:-}" ] && rm -rf "$_CONFIG_DIR"
  case "$status" in
    141) exit 0 ;;
    *)   exit "$status" ;;
  esac
}
trap _harness_exit EXIT

# Mock gh: prints $MOCK_GH_OUTPUT and exits with $MOCK_GH_EXIT (default 0).
# When MOCK_GH_CALL_LOG is set to a file path, each invocation appends its
# arguments to that file (one line per call, space-separated).
# When MOCK_GH_POST_EXIT is set, POST calls exit with that code instead of
# MOCK_GH_EXIT.  This allows tests to simulate reply-post failures independently
# of the initial comment-list read.
cat > "$MOCK_BIN/gh" <<'MOCK_GH'
#!/usr/bin/env bash
# Log call arguments when requested.
if [ -n "${MOCK_GH_CALL_LOG:-}" ]; then
  printf '%s\n' "$*" >> "$MOCK_GH_CALL_LOG"
fi
# Differentiate call types.
case "$*" in
  *"pr ready"*)
    printf '%s\n' "${MOCK_GH_READY_OUTPUT:-{}}"
    exit "${MOCK_GH_READY_EXIT:-${MOCK_GH_EXIT:-0}}"
    ;;
  *"label view"*)
    printf '%s\n' "${MOCK_GH_LABEL_VIEW_OUTPUT:-${MOCK_GH_OUTPUT:-{}}}"
    exit "${MOCK_GH_LABEL_VIEW_EXIT:-${MOCK_GH_EXIT:-0}}"
    ;;
  *"label create"*)
    printf '%s\n' "${MOCK_GH_LABEL_CREATE_OUTPUT:-${MOCK_GH_OUTPUT:-{}}}"
    exit "${MOCK_GH_LABEL_CREATE_EXIT:-${MOCK_GH_EXIT:-0}}"
    ;;
  *"pr edit"*)
    printf '%s\n' "${MOCK_GH_PR_EDIT_OUTPUT:-${MOCK_GH_OUTPUT:-{}}}"
    exit "${MOCK_GH_PR_EDIT_EXIT:-${MOCK_GH_EXIT:-0}}"
    ;;
  *"--method POST"*)
    printf '%s\n' "${MOCK_GH_POST_OUTPUT:-{}}"
    exit "${MOCK_GH_POST_EXIT:-${MOCK_GH_EXIT:-0}}"
    ;;
  # gh pr view --json headRefOid — used by run_copilot_review to resolve head SHA.
  # Tests set MOCK_GH_HEAD_SHA to control the returned value; default empty string
  # triggers the head-sha-unavailable escalation path.
  *"headRefOid"*)
    printf '%s\n' "${MOCK_GH_HEAD_SHA:-}"
    exit "${MOCK_GH_EXIT:-0}"
    ;;
  # gh api repos/.../issues/.../comments — used by restore_regression_label_if_missing
  # to check for prior reviewer-loop summary comments (Area 11 summary-comment gate).
  # Tests set MOCK_GH_COMMENTS_OUTPUT to control the returned JSON; defaults to an
  # empty JSON array (no comments — loop has never run). Tests set
  # MOCK_GH_COMMENTS_EXIT to simulate an API failure independently of MOCK_GH_EXIT.
  *"issues/"*"/comments"*)
    printf '%s\n' "${MOCK_GH_COMMENTS_OUTPUT:-[]}"
    exit "${MOCK_GH_COMMENTS_EXIT:-${MOCK_GH_EXIT:-0}}"
    ;;
  *)
    printf '%s\n' "${MOCK_GH_OUTPUT:-[]}"
    exit "${MOCK_GH_EXIT:-0}"
    ;;
esac
MOCK_GH
chmod +x "$MOCK_BIN/gh"

# Mock git: used by workflow_repo_root inside workflow-lib.sh; for the harness
# it never needs to run real git (REPO_ROOT is resolved before the mock is placed).
# Pass through to the real git for any call that happens before PATH override.
cat > "$MOCK_BIN/git" <<'MOCK_GIT'
#!/usr/bin/env bash
# Return the configured repo root when rev-parse --git-common-dir is requested.
# For all other git calls, fail fast so unintended git dependencies are explicit.
case "${*}" in
  *"rev-parse"*"--git-common-dir"*)
    printf '%s/.git\n' "${MOCK_REPO_ROOT:-.}"
    ;;
  *)
    printf 'unexpected git invocation in harness: git %s\n' "$*" >&2
    exit 64
    ;;
esac
MOCK_GIT
chmod +x "$MOCK_BIN/git"

export PATH="$MOCK_BIN:$PATH"

# ---------------------------------------------------------------------------
# Source pr-review-loop.sh in HARNESS_MODE.
# This loads all function definitions but skips:
#   - The single-instance lock guard
#   - The main argument-parsing and execution block
# workflow-lib.sh is sourced transitively inside pr-review-loop.sh.
# ---------------------------------------------------------------------------
# Set MOCK_REPO_ROOT so the mock git returns the correct path.
export MOCK_REPO_ROOT="$REPO_ROOT"

# Override workflow_repo_root AFTER sourcing so it returns a controlled path.
# The real workflow-lib.sh defines it relative to the script directory; in the
# harness we need it to point to REPO_ROOT (for functions that read config files)
# or to a temp directory (for append_compare_metrics_row which writes a file).
# We redefine it after sourcing below.

# shellcheck source=scripts/development-workflow/pr-review-loop.sh
HARNESS_MODE=1 source "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh"

# ---------------------------------------------------------------------------
# Override functions that touch the filesystem or network in the areas under test.
# ---------------------------------------------------------------------------

# workflow_repo_root is redefined per-test for Area 3 (compare metrics).
# Default: point to REPO_ROOT for everything else.
workflow_repo_root() {
  printf '%s\n' "${HARNESS_REPO_ROOT:-$REPO_ROOT}"
}

# ---------------------------------------------------------------------------
# Test framework — minimal pass/fail counter and assertion helper.
# ---------------------------------------------------------------------------
PASS_COUNT=0
FAIL_COUNT=0

run_test() {
  local name="$1"
  local expected="$2"
  local actual="$3"
  if [ "$actual" = "$expected" ]; then
    echo "PASS: $name"
    PASS_COUNT=$(( PASS_COUNT + 1 ))
  else
    echo "FAIL: $name — expected '${expected}', got '${actual}'"
    FAIL_COUNT=$(( FAIL_COUNT + 1 ))
  fi
}

# ---------------------------------------------------------------------------
# Area 0: draft/ready lifecycle config parsing
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 0: draft/ready lifecycle config parsing ==="

_CONFIG_DIR="$(mktemp -d)"
cat > "$_CONFIG_DIR/.ai-dev-workflow.yaml" <<'YAML'
schema_version: 2

review:
  on_draft:
    runner:
      # Default Codex runner.
      - codex
    github:

      - pr-agent
  on_ready:
    github:
      - haystack
YAML

draft_runner_parsed="$(workflow_config_review_on_draft_runner "$_CONFIG_DIR/.ai-dev-workflow.yaml" | paste -sd ',' -)"
draft_github_parsed="$(workflow_config_review_on_draft_github "$_CONFIG_DIR/.ai-dev-workflow.yaml" | paste -sd ',' -)"
ready_github_parsed="$(workflow_config_review_on_ready_github "$_CONFIG_DIR/.ai-dev-workflow.yaml" | paste -sd ',' -)"
all_github_parsed="$(workflow_config_review_platforms "$_CONFIG_DIR/.ai-dev-workflow.yaml" | paste -sd ',' -)"
phase_after_clean_parsed="$(workflow_config_review_phase_after_clean_platforms "$_CONFIG_DIR/.ai-dev-workflow.yaml" | paste -sd ',' -)"
run_test "review_on_draft_runner_parser" "codex" "$draft_runner_parsed"
run_test "review_on_draft_github_parser" "pr-agent" "$draft_github_parsed"
run_test "review_on_ready_github_parser" "haystack" "$ready_github_parsed"
run_test "review_lifecycle_combined_platforms" "pr-agent,haystack" "$all_github_parsed"
run_test "phase_after_clean_compat_maps_ready_github" "haystack" "$phase_after_clean_parsed"

cat > "$_CONFIG_DIR/.ai-dev-workflow-legacy.yaml" <<'YAML'
schema_version: 1

review:
  platforms:
    - pr-agent
    - haystack
  phase_after_clean:
    - haystack
  internal_reviewers:
    - codex
YAML

legacy_draft_runner="$(workflow_config_review_on_draft_runner "$_CONFIG_DIR/.ai-dev-workflow-legacy.yaml" | paste -sd ',' -)"
legacy_draft_github="$(workflow_config_review_on_draft_github "$_CONFIG_DIR/.ai-dev-workflow-legacy.yaml" | paste -sd ',' -)"
legacy_ready_github="$(workflow_config_review_on_ready_github "$_CONFIG_DIR/.ai-dev-workflow-legacy.yaml" | paste -sd ',' -)"
legacy_all_github="$(workflow_config_review_platforms "$_CONFIG_DIR/.ai-dev-workflow-legacy.yaml" | paste -sd ',' -)"
run_test "legacy_internal_reviewers_mapping" "codex" "$legacy_draft_runner"
run_test "legacy_platforms_phase_draft_mapping" "pr-agent" "$legacy_draft_github"
run_test "legacy_platforms_phase_ready_mapping" "haystack" "$legacy_ready_github"
run_test "legacy_platforms_phase_combined_mapping" "pr-agent,haystack" "$legacy_all_github"

cat > "$_CONFIG_DIR/.ai-dev-workflow-legacy-platforms-only.yaml" <<'YAML'
schema_version: 1

review:
  platforms: [pr-agent, haystack]
YAML

legacy_platforms_only_ready="$(workflow_config_review_on_ready_github "$_CONFIG_DIR/.ai-dev-workflow-legacy-platforms-only.yaml" | paste -sd ',' -)"
run_test "legacy_platforms_without_phase_mapping" "pr-agent,haystack" "$legacy_platforms_only_ready"

cat > "$_CONFIG_DIR/.ai-dev-workflow-mixed.yaml" <<'YAML'
schema_version: 2

review:
  on_draft:
    runner: [codex]
    github: [pr-agent]
  on_ready:
    github: [haystack]
  internal_reviewers: [claude]
  platforms: [greptile, coderabbit]
  phase_after_clean: [coderabbit]
YAML

mixed_runner="$(workflow_config_review_on_draft_runner "$_CONFIG_DIR/.ai-dev-workflow-mixed.yaml" | paste -sd ',' -)"
mixed_draft_github="$(workflow_config_review_on_draft_github "$_CONFIG_DIR/.ai-dev-workflow-mixed.yaml" | paste -sd ',' -)"
mixed_ready_github="$(workflow_config_review_on_ready_github "$_CONFIG_DIR/.ai-dev-workflow-mixed.yaml" | paste -sd ',' -)"
mixed_all_github="$(workflow_config_review_platforms "$_CONFIG_DIR/.ai-dev-workflow-mixed.yaml" | paste -sd ',' -)"
run_test "mixed_new_legacy_runner_prefers_new" "codex" "$mixed_runner"
run_test "mixed_new_legacy_draft_prefers_new" "pr-agent" "$mixed_draft_github"
run_test "mixed_new_legacy_ready_prefers_new" "haystack" "$mixed_ready_github"
run_test "mixed_new_legacy_combined_prefers_new" "pr-agent,haystack" "$mixed_all_github"

cat > "$_CONFIG_DIR/.ai-dev-workflow-duplicates.yaml" <<'YAML'
schema_version: 2

review:
  on_draft:
    runner: [codex]
    github: [pr-agent, haystack]
  on_ready:
    github: [haystack]
YAML

duplicate_warning="$(emit_review_lifecycle_duplicate_warnings "$_CONFIG_DIR/.ai-dev-workflow-duplicates.yaml" 2>&1 || true)"
case "$duplicate_warning" in
  *'reviewer "haystack" in more than one bucket'*) duplicate_detected=yes ;;
  *) duplicate_detected=no ;;
esac
run_test "duplicate_lifecycle_reviewer_warning" "yes" "$duplicate_detected"

declare -a phase_after_clean_platforms=()
append_phase_after_clean_platforms "coderabbit, pr-agent"
if is_phase_after_clean_platform "coderabbit" && is_phase_after_clean_platform "pr-agent"; then
  phase_membership="yes"
else
  phase_membership="no"
fi
run_test "phase_after_clean_membership" "yes" "$phase_membership"

declare -a phase_after_clean_platforms=("coderabbit")
declare -a platforms=("pr-agent")
phase_after_clean_filtered_out=""
filter_phase_after_clean_platforms
run_test "phase_after_clean_filters_absent_platform" "0" "${#phase_after_clean_platforms[@]}"
run_test "phase_after_clean_filtered_out_records_absent_platform" "coderabbit" "$phase_after_clean_filtered_out"

declare -a phase_after_clean_platforms=("coderabbit")
declare -a platforms=("pr-agent" "coderabbit")
filter_pre_after_clean_platforms
run_test "pre_after_clean_only_filters_phase_platform" "pr-agent" "${platforms[0]}"
run_test "pre_after_clean_only_platform_count" "1" "${#platforms[@]}"

declare -a phase_after_clean_platforms=("haystack")
declare -a platforms=("pr-agent" "haystack")
filter_pre_after_clean_platforms
run_test "draft_github_only_filters_ready_reviewers" "pr-agent" "${platforms[0]}"

# ---------------------------------------------------------------------------
# Area 0b: doc branch timeout defaults
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 0b: doc branch timeout defaults ==="

unset PR_REVIEW_LOOP_DOC_MAX_WAIT
run_test "doc_branch_default_max_wait" "180" "$(doc_branch_default_max_wait)"

PR_REVIEW_LOOP_DOC_MAX_WAIT=240
export PR_REVIEW_LOOP_DOC_MAX_WAIT
run_test "doc_branch_env_override_max_wait" "240" "$(doc_branch_default_max_wait)"

PR_REVIEW_LOOP_DOC_MAX_WAIT=abc
export PR_REVIEW_LOOP_DOC_MAX_WAIT
_doc_timeout_output="$(doc_branch_default_max_wait 2>/dev/null)"
run_test "doc_branch_invalid_env_falls_back" "180" "$_doc_timeout_output"

run_test "doc_branch_poll_interval_default" "30" "$(doc_branch_default_poll_interval 180)"
run_test "doc_branch_poll_interval_equal_clamps" "15" "$(doc_branch_default_poll_interval 30)"
run_test "doc_branch_poll_interval_greater_clamps" "10" "$(doc_branch_default_poll_interval 20)"

unset PR_REVIEW_LOOP_DOC_MAX_WAIT _doc_timeout_output

# ---------------------------------------------------------------------------
# Area 1: normalize_platform_verdict
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 1: normalize_platform_verdict ==="

actual="$(normalize_platform_verdict "clean" "")"
run_test "verdict_clean" "clean" "$actual"

actual="$(normalize_platform_verdict "needs_fixes" "")"
run_test "verdict_needs_fixes" "blocking" "$actual"

actual="$(normalize_platform_verdict "advisory" "")"
run_test "verdict_advisory" "advisory" "$actual"

actual="$(normalize_platform_verdict "skipped" "")"
run_test "verdict_skipped" "unavailable" "$actual"

actual="$(normalize_platform_verdict "needs_rerun" "")"
run_test "verdict_needs_rerun" "blocking" "$actual"

actual="$(normalize_platform_verdict "escalate" "REASON=timeout")"
run_test "verdict_escalate_timeout" "timed out" "$actual"

actual="$(normalize_platform_verdict "escalate" "REASON=timed_out")"
run_test "verdict_escalate_timed_out" "timed out" "$actual"

actual="$(normalize_platform_verdict "escalate" "REASON=max_wait_exceeded")"
run_test "verdict_escalate_max_wait" "timed out" "$actual"

actual="$(normalize_platform_verdict "escalate" "REASON=no_response")"
run_test "verdict_escalate_no_response" "timed out" "$actual"

actual="$(normalize_platform_verdict "escalate" "REASON=rate_limit_max_retries")"
run_test "verdict_escalate_rate_limit_max_retries" "timed out" "$actual"

actual="$(normalize_platform_verdict "escalate" "REASON=pending_timeout")"
run_test "verdict_escalate_pending_timeout" "timed out" "$actual"

actual="$(normalize_platform_verdict "escalate" "REASON=service_error")"
run_test "verdict_escalate_unknown" "unavailable" "$actual"

actual="$(normalize_platform_verdict "something_else" "")"
run_test "verdict_unknown_token" "unavailable" "$actual"

# ---------------------------------------------------------------------------
# Area 2: check_unreplied_rest_comments
#
# gh api --paginate writes one JSON array per page as separate documents.
# jq -s wraps multiple documents into an array of arrays: [[page1_items], ...].
# For single-page mocks, output one JSON array; jq -s wraps it to [[...items...]].
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 2: check_unreplied_rest_comments ==="

# test: no comments at all
export MOCK_GH_OUTPUT='[]'
actual="$(check_unreplied_rest_comments "1" "owner/repo" "coderabbitai[bot]" "[]")"
run_test "rest_no_comments" "0" "$actual"

# test: one root comment from bot, no replies
export MOCK_GH_OUTPUT='[{"id":10,"in_reply_to_id":null,"user":{"login":"coderabbitai[bot]"},"body":"Finding X"}]'
actual="$(check_unreplied_rest_comments "1" "owner/repo" "coderabbitai[bot]" "[]")"
run_test "rest_single_bot_root_unreplied" "1" "$actual"

# test: bot root comment with one human reply
export MOCK_GH_OUTPUT='[{"id":10,"in_reply_to_id":null,"user":{"login":"coderabbitai[bot]"},"body":"Finding X"},{"id":11,"in_reply_to_id":10,"user":{"login":"humanuser"},"body":"Acknowledged"}]'
actual="$(check_unreplied_rest_comments "1" "owner/repo" "coderabbitai[bot]" "[]")"
run_test "rest_bot_root_with_human_reply" "0" "$actual"

# test: bot root comment with bot-only reply (bot replies do not count as acknowledgment)
export MOCK_GH_OUTPUT='[{"id":10,"in_reply_to_id":null,"user":{"login":"coderabbitai[bot]"},"body":"Finding X"},{"id":11,"in_reply_to_id":10,"user":{"login":"someother[bot]"},"body":"Auto-ack"}]'
actual="$(check_unreplied_rest_comments "1" "owner/repo" "coderabbitai[bot]" "[]")"
run_test "rest_bot_root_with_bot_reply_only" "1" "$actual"

# test: root comment body contains "✅ Addressed" — self-resolved, excluded
export MOCK_GH_OUTPUT='[{"id":10,"in_reply_to_id":null,"user":{"login":"coderabbitai[bot]"},"body":"✅ Addressed — no action needed"}]'
actual="$(check_unreplied_rest_comments "1" "owner/repo" "coderabbitai[bot]" "[]")"
run_test "rest_addressed_marker" "0" "$actual"

# test: root comment whose GraphQL thread is already resolved (id in resolved_ids)
export MOCK_GH_OUTPUT='[{"id":10,"in_reply_to_id":null,"user":{"login":"coderabbitai[bot]"},"body":"Finding X"}]'
actual="$(check_unreplied_rest_comments "1" "owner/repo" "coderabbitai[bot]" "[10]")"
run_test "rest_resolved_id_excluded" "0" "$actual"

# test: root comment from non-bot human user — not counted (only bot roots are tracked)
export MOCK_GH_OUTPUT='[{"id":10,"in_reply_to_id":null,"user":{"login":"humanuser"},"body":"Human comment"}]'
actual="$(check_unreplied_rest_comments "1" "owner/repo" "coderabbitai[bot]" "[]")"
run_test "rest_human_comment_ignored" "0" "$actual"

# test: three bot root comments, one with human reply — expect count 2
export MOCK_GH_OUTPUT='[
  {"id":10,"in_reply_to_id":null,"user":{"login":"coderabbitai[bot]"},"body":"Finding A"},
  {"id":11,"in_reply_to_id":null,"user":{"login":"coderabbitai[bot]"},"body":"Finding B"},
  {"id":12,"in_reply_to_id":null,"user":{"login":"coderabbitai[bot]"},"body":"Finding C"},
  {"id":13,"in_reply_to_id":11,"user":{"login":"humanuser"},"body":"Acknowledged B"}
]'
actual="$(check_unreplied_rest_comments "1" "owner/repo" "coderabbitai[bot]" "[]")"
run_test "rest_multiple_bot_comments_partial_replied" "2" "$actual"

# ---------------------------------------------------------------------------
# Area 3: append_compare_metrics_row — platform config change detection
#
# workflow_repo_root is overridden to return a temp directory per test.
# The metrics file is at <repo_root>/docs/workflow/retro-metrics-platforms.md.
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 3: append_compare_metrics_row (platform config detection) ==="

# Helper: create a fresh temp directory for each Area 3 test.
# The metrics file lives at $tmpdir/docs/workflow/retro-metrics-platforms.md.
_setup_metrics_dir() {
  if [ -n "${_METRICS_DIR:-}" ]; then
    rm -rf "$_METRICS_DIR"
  fi
  _METRICS_DIR="$(mktemp -d)"
  mkdir -p "$_METRICS_DIR/docs/workflow"
  export HARNESS_REPO_ROOT="$_METRICS_DIR"
  _METRICS_TMP="$_METRICS_DIR/docs/workflow/retro-metrics-platforms.md"
}

# Helper: count data rows in the metrics file (lines starting with "| #").
# grep -c exits 1 when count is 0, so capture exit code separately.
_count_data_rows() {
  local n
  n="$(grep -c '^| #' "$_METRICS_TMP" 2>/dev/null)" || n="0"
  printf '%s\n' "$n"
}

# Helper: check whether a separator comment row exists (lines containing
# "*(platforms changed:").
# Returns 0 if no separator, 1+ if separator found.
_has_separator_row() {
  local n
  n="$(grep -c '(platforms changed:' "$_METRICS_TMP" 2>/dev/null)" || n="0"
  printf '%s\n' "$n"
}

# test: file does not exist — should be created with header and one data row
_setup_metrics_dir
append_compare_metrics_row "42" "fix/some-branch" "clean" "coderabbit" "clean"
if [ -f "$_METRICS_TMP" ]; then
  data_rows="$(_count_data_rows)"
  run_test "compare_no_existing_file" "1" "$data_rows"
else
  run_test "compare_no_existing_file" "file_exists" "file_missing"
fi

# test: same platform set and order — no separator comment row
_setup_metrics_dir
# Create initial state with coderabbit
append_compare_metrics_row "10" "fix/first" "clean" "coderabbit" "clean"
# Append second row with same platform
append_compare_metrics_row "11" "fix/second" "blocking" "coderabbit" "blocking"
sep_count="$(_has_separator_row)"
data_rows="$(_count_data_rows)"
run_test "compare_same_platform_set_no_separator" "0" "$sep_count"
run_test "compare_same_platform_set_two_rows" "2" "$data_rows"

# test: platform added — existing file has fewer platforms; should insert separator
_setup_metrics_dir
# Create initial state with one platform
append_compare_metrics_row "10" "fix/first" "clean" "coderabbit" "clean"
# Append with two platforms now
append_compare_metrics_row "11" "fix/second" "clean" "coderabbit" "clean" "pr-agent" "clean"
sep_count="$(_has_separator_row)"
run_test "compare_platform_added" "1" "$sep_count"

# test: same platform count but different order — should insert separator
_setup_metrics_dir
append_compare_metrics_row "10" "fix/first" "clean" "coderabbit" "clean" "pr-agent" "clean"
# Reversed order
append_compare_metrics_row "11" "fix/second" "clean" "pr-agent" "clean" "coderabbit" "clean"
sep_count="$(_has_separator_row)"
run_test "compare_platform_reordered" "1" "$sep_count"

# test: same platform count but renamed — should insert separator
_setup_metrics_dir
append_compare_metrics_row "10" "fix/first" "clean" "coderabbit" "clean"
# Different platform name (renamed)
append_compare_metrics_row "11" "fix/second" "clean" "pr-agent" "clean"
sep_count="$(_has_separator_row)"
run_test "compare_platform_renamed" "1" "$sep_count"

# ---------------------------------------------------------------------------
# Area 4: lock cleanup on SIGTERM
#
# This test verifies that the TERM signal trap in the lock guard section removes
# the lockdir before the process exits — specifically when the script is blocked
# inside _interruptible_sleep (a background sleep + wait pattern), which is the
# actual blocking pattern used in all polling loops.
#
# The previous test used "sleep 3600 & wait" directly in the wrapper.  That
# already uses the interruptible pattern, but it did NOT test the CURRENT_CHILD_PID
# kill-child step that the production code now uses to interrupt a running child
# before the wait returns.  This updated test reproduces the full
# _interruptible_sleep helper (including CURRENT_CHILD_PID tracking) so that the
# TERM handler's "kill -TERM $CURRENT_CHILD_PID" path is exercised.
#
# SIGINT is not testable via kill -INT on a background subprocess because bash
# sets SIGINT disposition to SIG_IGN for background processes (POSIX behaviour).
# The SIGINT trap is still valuable for interactive invocations (Ctrl+C) — it is
# verified by inspection rather than subprocess signalling.
#
# A self-contained wrapper script is used instead of invoking pr-review-loop.sh
# directly because the full script requires workflow-lib.sh functions and a
# valid git/gh context that are not available in the test environment.
# The lock guard section itself is small and stable; testing it in isolation
# avoids mocking the entire script ecosystem while still validating the traps.
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 4: lock cleanup on SIGTERM ==="

# Helper: spin up a subprocess that acquires a lockdir then blocks inside
# _interruptible_sleep (foreground blocking via background child + wait),
# send SIGTERM to the outer process, and verify the lockdir is removed.
_run_sigterm_lock_test() {
  local pr_num="9997${RANDOM}"
  local lock_dir="/tmp/pr-review-loop-${pr_num}.lockdir"
  rm -rf "$lock_dir"

  # Self-contained wrapper: reproduces the lock guard + CURRENT_CHILD_PID-aware
  # signal traps from pr-review-loop.sh, then calls _interruptible_sleep to
  # simulate the foreground-blocking polling-loop scenario that was the root
  # cause of #615.
  local wrapper
  # Use XXXXXX at the end (macOS mktemp requires Xs at the end of the template).
  wrapper="$(mktemp /tmp/pr-review-loop-lock-test.XXXXXX)"
  # Build with printf to avoid heredoc quoting issues with embedded variables.
  printf '#!/usr/bin/env bash\n'                                                          > "$wrapper"
  printf 'set -euo pipefail\n'                                                           >> "$wrapper"
  printf '_LOCK_DIR="%s"\n'                   "$lock_dir"                               >> "$wrapper"
  printf '_OWN_LOCK=0\n'                                                                 >> "$wrapper"
  printf 'CURRENT_CHILD_PID=""\n'                                                        >> "$wrapper"
  printf 'if mkdir "$_LOCK_DIR" 2>/dev/null; then\n'                                    >> "$wrapper"
  printf '  printf '"'"'%%d\\n'"'"' "$$"           > "$_LOCK_DIR/pid"\n'               >> "$wrapper"
  printf '  printf '"'"'%%s\\n'"'"' "test-locker"  > "$_LOCK_DIR/cmd"\n'               >> "$wrapper"
  printf '  _OWN_LOCK=1\n'                                                               >> "$wrapper"
  printf 'fi\n'                                                                           >> "$wrapper"
  printf 'trap '"'"'[ "$_OWN_LOCK" -eq 1 ] && rm -rf "$_LOCK_DIR"'"'"' EXIT\n'         >> "$wrapper"
  # Updated TERM/INT traps: kill the background child (CURRENT_CHILD_PID) before
  # removing the lock — mirrors the production trap handlers added to fix #615.
  printf 'trap '"'"'[ -n "$CURRENT_CHILD_PID" ] && kill -TERM "$CURRENT_CHILD_PID" 2>/dev/null || true; [ "$_OWN_LOCK" -eq 1 ] && rm -rf "$_LOCK_DIR"; trap - TERM; kill -TERM "$$"'"'"' TERM\n' >> "$wrapper"
  printf 'trap '"'"'[ -n "$CURRENT_CHILD_PID" ] && kill -TERM "$CURRENT_CHILD_PID" 2>/dev/null || true; [ "$_OWN_LOCK" -eq 1 ] && rm -rf "$_LOCK_DIR"; trap - INT;  kill -INT  "$$"'"'"' INT\n'  >> "$wrapper"
  # Reproduce _interruptible_sleep: start sleep as a background job so that
  # (a) CURRENT_CHILD_PID is set (exercising the kill-child path in the trap), and
  # (b) wait IS interruptible by signals (bash fires traps between commands during wait).
  printf '_interruptible_sleep() { sleep "$1" & CURRENT_CHILD_PID=$!; wait "$CURRENT_CHILD_PID" 2>/dev/null || true; CURRENT_CHILD_PID=""; }\n' >> "$wrapper"
  printf '_interruptible_sleep 3600\n'                                                   >> "$wrapper"
  chmod +x "$wrapper"

  bash "$wrapper" &
  local sub_pid=$!

  # Wait for the lock dir to appear (up to 3 s, polling every 0.1 s).
  local waited=0
  while [ ! -d "$lock_dir" ] && [ "$waited" -lt 30 ]; do
    sleep 0.1
    waited=$((waited + 1))
  done

  if [ ! -d "$lock_dir" ]; then
    run_test "sigterm_lock_acquired" "lock_dir_present" "lock_dir_absent"
    wait "$sub_pid" 2>/dev/null || true
    rm -f "$wrapper"
    return
  fi
  run_test "sigterm_lock_acquired" "lock_dir_present" "lock_dir_present"

  # Send SIGTERM and wait for the subprocess to exit (up to 3 s).
  kill -TERM "$sub_pid" 2>/dev/null || true
  local kill_waited=0
  while kill -0 "$sub_pid" 2>/dev/null && [ "$kill_waited" -lt 30 ]; do
    sleep 0.1
    kill_waited=$((kill_waited + 1))
  done
  wait "$sub_pid" 2>/dev/null || true

  if [ -d "$lock_dir" ]; then
    run_test "sigterm_lock_cleaned" "lock_dir_absent" "lock_dir_present"
    rm -rf "$lock_dir"
  else
    run_test "sigterm_lock_cleaned" "lock_dir_absent" "lock_dir_absent"
  fi

  rm -f "$wrapper"
}

_run_sigterm_lock_test

# Verify that the INT trap is registered (code inspection — SIGINT cannot be
# tested via kill -INT on a background subprocess because bash resets SIGINT
# to SIG_IGN for background processes per POSIX).
int_trap_present="$(grep -c 'kill -INT.*\$\$' \
  "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh" 2>/dev/null || true)"
if [ "${int_trap_present:-0}" -gt 0 ]; then
  run_test "sigint_trap_registered" "present" "present"
else
  run_test "sigint_trap_registered" "present" "absent"
fi

# ---------------------------------------------------------------------------
# Area 5: auto_reply_unreplied_rest_comments
#
# Tests that the function posts replies to unreplied CodeRabbit REST comments
# and returns the correct count / exit code.
# Uses MOCK_GH_CALL_LOG to verify the POST endpoint is called for each
# unreplied comment, and MOCK_GH_POST_EXIT to simulate API failures.
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 5: auto_reply_unreplied_rest_comments ==="

# Reset POST-related mock vars between tests.
unset MOCK_GH_POST_EXIT MOCK_GH_POST_OUTPUT MOCK_GH_CALL_LOG

# test: no unreplied comments — nothing to reply to, exit 0, count 0
export MOCK_GH_OUTPUT='[]'
actual="$(auto_reply_unreplied_rest_comments "1" "owner/repo" "coderabbitai[bot]" "[]")"
run_test "auto_reply_no_comments" "0" "$actual"

# test: one unreplied bot comment — should post one reply, return count 1
_call_log="$(mktemp)"
export MOCK_GH_CALL_LOG="$_call_log"
export MOCK_GH_OUTPUT='[{"id":10,"in_reply_to_id":null,"user":{"login":"coderabbitai[bot]"},"body":"Finding X"}]'
actual="$(auto_reply_unreplied_rest_comments "1" "owner/repo" "coderabbitai[bot]" "[]")"
run_test "auto_reply_single_comment_count" "1" "$actual"
post_calls="$(grep -c -- '--method POST' "$_call_log" 2>/dev/null || true)"
run_test "auto_reply_single_comment_post_called" "1" "$post_calls"
rm -f "$_call_log"
unset MOCK_GH_CALL_LOG

# test: two unreplied bot comments — should post two replies, return count 2
_call_log="$(mktemp)"
export MOCK_GH_CALL_LOG="$_call_log"
export MOCK_GH_OUTPUT='[
  {"id":10,"in_reply_to_id":null,"user":{"login":"coderabbitai[bot]"},"body":"Finding A"},
  {"id":11,"in_reply_to_id":null,"user":{"login":"coderabbitai[bot]"},"body":"Finding B"}
]'
actual="$(auto_reply_unreplied_rest_comments "1" "owner/repo" "coderabbitai[bot]" "[]")"
run_test "auto_reply_two_comments_count" "2" "$actual"
post_calls="$(grep -c -- '--method POST' "$_call_log" 2>/dev/null || true)"
run_test "auto_reply_two_comments_posts" "2" "$post_calls"
rm -f "$_call_log"
unset MOCK_GH_CALL_LOG

# test: unreplied comment already in resolved_ids — should be skipped, count 0
export MOCK_GH_OUTPUT='[{"id":10,"in_reply_to_id":null,"user":{"login":"coderabbitai[bot]"},"body":"Finding X"}]'
actual="$(auto_reply_unreplied_rest_comments "1" "owner/repo" "coderabbitai[bot]" "[10]")"
run_test "auto_reply_resolved_id_skipped" "0" "$actual"

# test: comment already replied to by a human — should be skipped, count 0
export MOCK_GH_OUTPUT='[
  {"id":10,"in_reply_to_id":null,"user":{"login":"coderabbitai[bot]"},"body":"Finding X"},
  {"id":11,"in_reply_to_id":10,"user":{"login":"humanuser"},"body":"Ack"}
]'
actual="$(auto_reply_unreplied_rest_comments "1" "owner/repo" "coderabbitai[bot]" "[]")"
run_test "auto_reply_already_replied_skipped" "0" "$actual"

# test: POST API failure — function should return exit code 1
export MOCK_GH_OUTPUT='[{"id":10,"in_reply_to_id":null,"user":{"login":"coderabbitai[bot]"},"body":"Finding X"}]'
export MOCK_GH_POST_EXIT=1
actual_exit=0
auto_reply_unreplied_rest_comments "1" "owner/repo" "coderabbitai[bot]" "[]" > /dev/null 2>&1 || actual_exit=$?
run_test "auto_reply_post_failure_exit_code" "1" "$actual_exit"
unset MOCK_GH_POST_EXIT

# ---------------------------------------------------------------------------
# Area 6: check_unresolved_threads
#
# Tests that the function counts unresolved bot-authored review threads correctly
# via the GraphQL API mock. The mock gh command returns MOCK_GH_OUTPUT for all
# non-POST calls. check_unresolved_threads calls `gh api graphql ... --jq ...`
# which outputs the filtered JSON directly (not the raw gh output). Because the
# mock gh does not run the --jq filter, we set MOCK_GH_OUTPUT to the pre-filtered
# JSON that the real GraphQL query would return after --jq.
#
# Important: GitHub's GraphQL API returns author.login WITHOUT the "[bot]" suffix
# (e.g. "coderabbitai", not "coderabbitai[bot]"). The aggregate gate strips the
# "[bot]" suffix from bot_login_for_platform() output before adding to
# unresolved_bot_logins, so check_unresolved_threads always receives login strings
# without the "[bot]" suffix. All test cases below use sanitized login strings.
#
# Note: the post-clean recheck logic (POST_CLEAN_RECHECK / LATE_THREADS_FOUND)
# lives in the main execution block which is skipped by HARNESS_MODE=1. Those
# code paths call check_unresolved_threads (tested here) and _interruptible_sleep
# (a trivial sleep wrapper). Their integration is validated by the reviewer loop
# end-to-end run in CI.
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 6: check_unresolved_threads ==="

unset MOCK_GH_POST_EXIT MOCK_GH_POST_OUTPUT MOCK_GH_CALL_LOG

# test: no review threads — count should be 0
export MOCK_GH_OUTPUT='{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[]}'
actual="$(check_unresolved_threads "1" "owner/repo" "coderabbitai")"
run_test "unresolved_threads_none" "0" "$actual"

# test: one unresolved bot thread — count should be 1
# GraphQL author.login is "coderabbitai" (no "[bot]" suffix — stripped by caller)
export MOCK_GH_OUTPUT='{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[{"id":"RT1","isResolved":false,"comments":{"nodes":[{"author":{"login":"coderabbitai"},"body":"Blocking issue"}]}}]}'
actual="$(check_unresolved_threads "1" "owner/repo" "coderabbitai")"
run_test "unresolved_threads_one_bot" "1" "$actual"

# test: one resolved bot thread — count should be 0
export MOCK_GH_OUTPUT='{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[{"id":"RT1","isResolved":true,"comments":{"nodes":[{"author":{"login":"coderabbitai"},"body":"Blocking issue"}]}}]}'
actual="$(check_unresolved_threads "1" "owner/repo" "coderabbitai")"
run_test "unresolved_threads_resolved_skipped" "0" "$actual"

# test: bot thread with "✅ Addressed" in body — count should be 0
export MOCK_GH_OUTPUT='{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[{"id":"RT1","isResolved":false,"comments":{"nodes":[{"author":{"login":"coderabbitai"},"body":"✅ Addressed — fixed in latest commit"}]}}]}'
actual="$(check_unresolved_threads "1" "owner/repo" "coderabbitai")"
run_test "unresolved_threads_addressed_body_skipped" "0" "$actual"

# test: human-authored thread unresolved — count should be 0 (bot-only filter)
export MOCK_GH_OUTPUT='{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[{"id":"RT1","isResolved":false,"comments":{"nodes":[{"author":{"login":"humanreview"},"body":"Please change this"}]}}]}'
actual="$(check_unresolved_threads "1" "owner/repo" "coderabbitai")"
run_test "unresolved_threads_human_ignored" "0" "$actual"

# test: two bot threads, one resolved, one not — count should be 1
export MOCK_GH_OUTPUT='{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[{"id":"RT1","isResolved":true,"comments":{"nodes":[{"author":{"login":"coderabbitai"},"body":"First finding"}]}},{"id":"RT2","isResolved":false,"comments":{"nodes":[{"author":{"login":"coderabbitai"},"body":"Second finding"}]}}]}'
actual="$(check_unresolved_threads "1" "owner/repo" "coderabbitai")"
run_test "unresolved_threads_mixed_resolved" "1" "$actual"

# test: [bot]-suffix login NOT matched (gate strips suffix; bare login is required)
# Passing "coderabbitai[bot]" should NOT match GraphQL "coderabbitai" — returns 0.
export MOCK_GH_OUTPUT='{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[{"id":"RT1","isResolved":false,"comments":{"nodes":[{"author":{"login":"coderabbitai"},"body":"Blocking issue"}]}}]}'
actual="$(check_unresolved_threads "1" "owner/repo" "coderabbitai[bot]")"
run_test "unresolved_threads_bot_suffix_no_match" "0" "$actual"

# test: GraphQL API failure (exit 1 from gh) — function should return exit 3
export MOCK_GH_EXIT=1
actual_exit=0
check_unresolved_threads "1" "owner/repo" "coderabbitai" > /dev/null 2>&1 || actual_exit=$?
run_test "unresolved_threads_graphql_failure_exit3" "3" "$actual_exit"
unset MOCK_GH_EXIT

# ---------------------------------------------------------------------------
# Area 7: bot_login_for_platform — copilot platform
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 7: bot_login_for_platform — copilot ==="

unset COPILOT_BOT_LOGIN

actual="$(bot_login_for_platform "copilot")"
run_test "copilot_bot_login_default" "copilot-pull-request-reviewer[bot]" "$actual"

export COPILOT_BOT_LOGIN="custom-copilot-bot[bot]"
actual="$(bot_login_for_platform "copilot")"
run_test "copilot_bot_login_env_override" "custom-copilot-bot[bot]" "$actual"
unset COPILOT_BOT_LOGIN

# ---------------------------------------------------------------------------
# Area 8: run_copilot_review() — exit-code and key-value output contract (AC-8)
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 8: run_copilot_review — clean / needs_fixes / escalate ==="

# Helper overrides used across all Area 8 tests.
# cd_workflow_repo_root: no-op (no real directory change needed in harness).
# repo_slug: returns a fixed owner/repo slug so gh URL is deterministic.
# require_gh: no-op (mock gh already present on PATH).
_copilot_overrides='
  cd_workflow_repo_root() { :; }
  repo_slug() { printf "owner/repo\n"; }
  require_gh() { :; }
'

# Test 8.1: clean path — Copilot posts APPROVED review
# POST (reviewer request) succeeds; GET (reviews poll) returns a JSON array of
# review objects. run_copilot_review pipes gh output through jq, so MOCK_GH_OUTPUT
# must be a valid JSON array. MOCK_GH_HEAD_SHA is set so the SHA-filtered path is
# exercised and commit_id in the review matches.
# Use || to capture exit code safely when run_copilot_review may call set -e internally.
export MOCK_GH_POST_OUTPUT='{}'
export MOCK_GH_HEAD_SHA='abc123sha'
export MOCK_GH_OUTPUT='[{"user":{"login":"copilot-pull-request-reviewer[bot]"},"state":"APPROVED","commit_id":"abc123sha"}]'
unset COPILOT_BOT_LOGIN
actual_output=""
actual_exit=0
actual_output="$(
  eval "$_copilot_overrides"
  _ec=0
  run_copilot_review "42" "feature/42-test" "1" "5" || _ec=$?
  printf 'EXIT=%s\n' "$_ec"
)"
actual_exit="$(printf '%s\n' "$actual_output" | grep "^EXIT=" | cut -d= -f2)"
run_test "copilot_clean_result" "RESULT=clean" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "copilot_clean_blocking_count" "BLOCKING_COUNT=0" \
  "$(printf '%s\n' "$actual_output" | grep "^BLOCKING_COUNT=")"
run_test "copilot_clean_exit_code" "0" "$actual_exit"

# Test 8.2: needs_fixes path — Copilot posts CHANGES_REQUESTED review.
# The mock review includes an id (456) so the review-comments API call is
# exercised. The mock gh returns the same MOCK_GH_OUTPUT for all GET calls,
# so the review-comments endpoint returns one element (the review object) —
# length=1. BLOCKING_COUNT should equal 1 (the actual inline count).
export MOCK_GH_POST_OUTPUT='{}'
export MOCK_GH_HEAD_SHA='abc123sha'
export MOCK_GH_OUTPUT='[{"id":456,"user":{"login":"copilot-pull-request-reviewer[bot]"},"state":"CHANGES_REQUESTED","commit_id":"abc123sha"}]'
unset COPILOT_BOT_LOGIN
actual_output=""
actual_exit=0
actual_output="$(
  eval "$_copilot_overrides"
  _ec=0
  run_copilot_review "42" "feature/42-test" "1" "5" || _ec=$?
  printf 'EXIT=%s\n' "$_ec"
)"
actual_exit="$(printf '%s\n' "$actual_output" | grep "^EXIT=" | cut -d= -f2)"
run_test "copilot_needs_fixes_result" "RESULT=needs_fixes" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "copilot_needs_fixes_blocking_count" "BLOCKING_COUNT=1" \
  "$(printf '%s\n' "$actual_output" | grep "^BLOCKING_COUNT=")"
run_test "copilot_needs_fixes_exit_code" "1" "$actual_exit"

# Test 8.3: escalate (timeout) path — no review posted within max_wait
# POST succeeds; GET returns empty array (no reviews yet); max_wait=0 so the
# while loop body never executes and execution falls through to the timeout block.
# MOCK_GH_HEAD_SHA is set so the SHA check passes and the timeout block is reached.
export MOCK_GH_POST_OUTPUT='{}'
export MOCK_GH_HEAD_SHA='abc123sha'
export MOCK_GH_OUTPUT='[]'
unset COPILOT_BOT_LOGIN
actual_output=""
actual_exit=0
actual_output="$(
  eval "$_copilot_overrides"
  _ec=0
  run_copilot_review "42" "feature/42-test" "1" "0" || _ec=$?
  printf 'EXIT=%s\n' "$_ec"
)"
actual_exit="$(printf '%s\n' "$actual_output" | grep "^EXIT=" | cut -d= -f2)"
run_test "copilot_timeout_result" "RESULT=escalate" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "copilot_timeout_reason" "REASON=timeout" \
  "$(printf '%s\n' "$actual_output" | grep "^REASON=")"
run_test "copilot_timeout_exit_code" "2" "$actual_exit"

# Test 8.4: escalate (unavailable) path — reviewer request API call fails
# POST fails (non-zero exit); function must return RESULT=escalate REASON=unavailable.
# MOCK_GH_HEAD_SHA is set so the SHA check passes and the POST failure path is reached.
export MOCK_GH_POST_EXIT=1
export MOCK_GH_HEAD_SHA='abc123sha'
export MOCK_GH_OUTPUT=''
unset COPILOT_BOT_LOGIN
actual_output=""
actual_exit=0
actual_output="$(
  eval "$_copilot_overrides"
  _ec=0
  run_copilot_review "42" "feature/42-test" "1" "5" || _ec=$?
  printf 'EXIT=%s\n' "$_ec"
)"
actual_exit="$(printf '%s\n' "$actual_output" | grep "^EXIT=" | cut -d= -f2)"
run_test "copilot_unavailable_result" "RESULT=escalate" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "copilot_unavailable_reason" "REASON=unavailable" \
  "$(printf '%s\n' "$actual_output" | grep "^REASON=")"
run_test "copilot_unavailable_exit_code" "2" "$actual_exit"
unset MOCK_GH_POST_EXIT
export MOCK_GH_OUTPUT='[]'

# Test 8.5: clean path — Copilot posts COMMENTED review (non-blocking comment)
# COMMENTED is treated as clean (exit 0), BLOCKING_COUNT=0, SUGGESTION_COUNT=1.
export MOCK_GH_POST_OUTPUT='{}'
export MOCK_GH_HEAD_SHA='abc123sha'
export MOCK_GH_OUTPUT='[{"user":{"login":"copilot-pull-request-reviewer[bot]"},"state":"COMMENTED","commit_id":"abc123sha"}]'
unset COPILOT_BOT_LOGIN
actual_output=""
actual_exit=0
actual_output="$(
  eval "$_copilot_overrides"
  _ec=0
  run_copilot_review "42" "feature/42-test" "1" "5" || _ec=$?
  printf 'EXIT=%s\n' "$_ec"
)"
actual_exit="$(printf '%s\n' "$actual_output" | grep "^EXIT=" | cut -d= -f2)"
run_test "copilot_commented_result" "RESULT=clean" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "copilot_commented_blocking_count" "BLOCKING_COUNT=0" \
  "$(printf '%s\n' "$actual_output" | grep "^BLOCKING_COUNT=")"
run_test "copilot_commented_suggestion_count" "SUGGESTION_COUNT=1" \
  "$(printf '%s\n' "$actual_output" | grep "^SUGGESTION_COUNT=")"
run_test "copilot_commented_exit_code" "0" "$actual_exit"
export MOCK_GH_OUTPUT='[]'

# Test 8.6: zero poll interval guard — effective_poll_interval must be floored to 1
# A poll_interval of 0 would cause elapsed to never increment, hanging forever.
# The guard clamps it to 1. Test verifies the function completes (doesn't hang)
# when poll_interval=0, by returning on the first poll with an APPROVED state.
export MOCK_GH_POST_OUTPUT='{}'
export MOCK_GH_HEAD_SHA='abc123sha'
export MOCK_GH_OUTPUT='[{"user":{"login":"copilot-pull-request-reviewer[bot]"},"state":"APPROVED","commit_id":"abc123sha"}]'
unset COPILOT_BOT_LOGIN
actual_output=""
actual_exit=0
actual_output="$(
  eval "$_copilot_overrides"
  _ec=0
  run_copilot_review "42" "feature/42-test" "0" "5" || _ec=$?
  printf 'EXIT=%s\n' "$_ec"
)"
actual_exit="$(printf '%s\n' "$actual_output" | grep "^EXIT=" | cut -d= -f2)"
run_test "copilot_zero_poll_interval_completes" "RESULT=clean" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "copilot_zero_poll_interval_exit_code" "0" "$actual_exit"
export MOCK_GH_OUTPUT='[]'

# Test 8.7: escalate (head-sha-unavailable) path — headRefOid lookup returns empty
# When head_sha is empty the function must escalate immediately rather than
# falling back to an unscoped review query that could match stale verdicts.
unset MOCK_GH_HEAD_SHA
export MOCK_GH_POST_OUTPUT='{}'
unset COPILOT_BOT_LOGIN
actual_output=""
actual_exit=0
actual_output="$(
  eval "$_copilot_overrides"
  _ec=0
  run_copilot_review "42" "feature/42-test" "1" "5" || _ec=$?
  printf 'EXIT=%s\n' "$_ec"
)"
actual_exit="$(printf '%s\n' "$actual_output" | grep "^EXIT=" | cut -d= -f2)"
run_test "copilot_head_sha_unavailable_result" "RESULT=escalate" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "copilot_head_sha_unavailable_reason" "REASON=head-sha-unavailable" \
  "$(printf '%s\n' "$actual_output" | grep "^REASON=")"
run_test "copilot_head_sha_unavailable_exit_code" "2" "$actual_exit"

# ---------------------------------------------------------------------------
# Area 9: haystack platform
#
# Tests that bot_login_for_platform returns "" for haystack (no GitHub review
# threads are posted by the Haystack CLI in this MVP), and that run_platform_review
# routes to run_haystack_review for the haystack platform.
#
# run_haystack_review itself calls haystack-reviewer.sh which requires the
# haystack CLI binary. Full integration is validated by the smoke test runbook
# at docs/testing/workflow/720-haystack-triage-review-platform.smoke-test.md.
# These unit tests cover only the routing and bot-login layers.
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 9: haystack platform ==="

unset MOCK_GH_POST_EXIT MOCK_GH_POST_OUTPUT MOCK_GH_CALL_LOG MOCK_GH_EXIT

# test: bot_login_for_platform returns "" for haystack
actual="$(bot_login_for_platform haystack)"
run_test "bot_login_for_platform_haystack" "" "$actual"

# test: bot_login_for_platform still returns "" for unknown platforms
actual="$(bot_login_for_platform unknown-platform-xyz)"
run_test "bot_login_for_platform_unknown_still_empty" "" "$actual"

# test: run_platform_review routes "haystack" to run_haystack_review
_haystack_dispatch_called=0
run_haystack_review() { _haystack_dispatch_called=1; }
run_platform_review "haystack" "999" "feature/test" "30" "120" >/dev/null 2>&1 || true
run_test "run_platform_review_routes_to_run_haystack_review" "1" "$_haystack_dispatch_called"
unset -f run_haystack_review
unset _haystack_dispatch_called

# test: legacy ensure_pr_ready_for_after_clean wrapper converts draft PRs before ready-phase reviewers
_call_log="$(mktemp)"
export MOCK_GH_CALL_LOG="$_call_log"
MOCK_GH_OUTPUT="true"
MOCK_GH_EXIT=0
export MOCK_GH_OUTPUT MOCK_GH_EXIT
ensure_pr_ready_for_after_clean "999" >/dev/null 2>&1
ready_calls="$(grep -c -- 'pr ready 999' "$_call_log" 2>/dev/null || true)"
run_test "after_clean_ready_converts_draft_pr" "1" "$ready_calls"
rm -f "$_call_log"
unset MOCK_GH_CALL_LOG MOCK_GH_OUTPUT MOCK_GH_EXIT ready_calls

# test: ensure_pr_ready_for_after_clean leaves non-draft PRs unchanged
_call_log="$(mktemp)"
export MOCK_GH_CALL_LOG="$_call_log"
MOCK_GH_OUTPUT="false"
MOCK_GH_EXIT=0
export MOCK_GH_OUTPUT MOCK_GH_EXIT
ensure_pr_ready_for_after_clean "999" >/dev/null 2>&1
ready_calls="$(grep -c -- 'pr ready 999' "$_call_log" 2>/dev/null || true)"
run_test "after_clean_ready_skips_non_draft_pr" "0" "$ready_calls"
rm -f "$_call_log"
unset MOCK_GH_CALL_LOG MOCK_GH_OUTPUT MOCK_GH_EXIT ready_calls

# test: ensure_pr_ready_for_after_clean fails closed when draft state cannot be read
MOCK_GH_OUTPUT=""
MOCK_GH_EXIT=1
export MOCK_GH_OUTPUT MOCK_GH_EXIT
set +e
ensure_pr_ready_for_after_clean "999" >/dev/null 2>&1
ready_status=$?
set -e
run_test "after_clean_ready_fails_closed_on_state_error" "2" "$ready_status"
unset MOCK_GH_OUTPUT MOCK_GH_EXIT ready_status

# test: ensure_pr_ready_for_after_clean fails closed when gh pr ready fails
MOCK_GH_OUTPUT="true"
MOCK_GH_EXIT=0
MOCK_GH_READY_EXIT=1
export MOCK_GH_OUTPUT MOCK_GH_EXIT MOCK_GH_READY_EXIT
set +e
ensure_pr_ready_for_after_clean "999" >/dev/null 2>&1
ready_status=$?
set -e
run_test "after_clean_ready_fails_closed_on_ready_error" "2" "$ready_status"
unset MOCK_GH_OUTPUT MOCK_GH_EXIT MOCK_GH_READY_EXIT ready_status

# ---------------------------------------------------------------------------
# Area 10: per-platform result tokens in summary comment (#755)
#
# Tests that:
#   (a) _summary_platform_list is built correctly from platform_result_tokens.
#   (b) _post_review_summary renders the correct result_line for result="skipped".
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 10: per-platform result tokens in summary comment ==="

# Test 10.1: _summary_platform_list format from platform_result_tokens
_test_tokens=("pr-agent:clean" "haystack:unavailable" "claude-code-action:escalated (timeout)")
_test_spl=""
for _sprt in "${_test_tokens[@]:-}"; do
  _spname="${_sprt%%:*}"; _spdisp="${_sprt#*:}"
  [ -n "$_test_spl" ] && _test_spl="${_test_spl}, "
  _test_spl="${_test_spl}${_spname} (${_spdisp})"
done
[ -z "$_test_spl" ] && _test_spl="none"
run_test "summary_platform_list_format" \
  "pr-agent (clean), haystack (unavailable), claude-code-action (escalated (timeout))" \
  "$_test_spl"
unset _test_tokens _test_spl _sprt _spname _spdisp

# Test 10.1b: display override allows Haystack policy verdicts to avoid reading as clean
_platform_output='RESULT=clean
DISPLAY_RESULT=needs-review: policy
POLICY_REVIEW_REQUIRED=1'
_prt_display_override="$(kv_value_default DISPLAY_RESULT "$_platform_output" "")"
if [ -n "$_prt_display_override" ]; then
  _prt_disp="$_prt_display_override"
else
  _prt_disp="clean"
fi
run_test "summary_platform_display_override" "needs-review: policy" "$_prt_disp"
run_test "policy_review_compare_verdict" "advisory" "$(normalize_platform_verdict clean "$_platform_output")"
run_test "policy_review_does_not_override_needs_fixes" "blocking" "$(normalize_platform_verdict needs_fixes "$_platform_output")"
run_test "policy_review_does_not_override_skipped" "unavailable" "$(normalize_platform_verdict skipped "$_platform_output")"
unset _platform_output _prt_display_override _prt_disp

# Test 10.1c: policy metadata is rendered as an explicit handoff note.
_platform_name="haystack"
_platform_output='RESULT=clean
POLICY_STATUS_AVAILABLE=1
POLICY_BUCKET=needs-assignment
POLICY_NEEDS_HUMAN=true
POLICY_DISPOSITION=policy-human-review
POLICY_VERDICT=needs-review
POLICY_ANALYSIS_STATUS=ready
POLICY_RATING=5
POLICY_HAS_REVIEWER=false'
_policy_note="${_platform_name}:"
_policy_bucket="$(kv_value_default POLICY_BUCKET "$_platform_output" "")"
_policy_needs_human="$(kv_value_default POLICY_NEEDS_HUMAN "$_platform_output" "")"
_policy_disposition="$(kv_value_default POLICY_DISPOSITION "$_platform_output" "")"
_policy_verdict="$(kv_value_default POLICY_VERDICT "$_platform_output" "")"
_policy_analysis_status="$(kv_value_default POLICY_ANALYSIS_STATUS "$_platform_output" "")"
_policy_rating="$(kv_value_default POLICY_RATING "$_platform_output" "")"
_policy_has_reviewer="$(kv_value_default POLICY_HAS_REVIEWER "$_platform_output" "")"
[ -n "$_policy_bucket" ] && _policy_note="${_policy_note} bucket=${_policy_bucket};"
[ -n "$_policy_needs_human" ] && _policy_note="${_policy_note} needsHumanReview=${_policy_needs_human};"
[ -n "$_policy_disposition" ] && _policy_note="${_policy_note} disposition=${_policy_disposition};"
[ -n "$_policy_verdict" ] && _policy_note="${_policy_note} verdict=${_policy_verdict};"
[ -n "$_policy_analysis_status" ] && _policy_note="${_policy_note} analysisStatus=${_policy_analysis_status};"
[ -n "$_policy_rating" ] && _policy_note="${_policy_note} rating=${_policy_rating};"
[ -n "$_policy_has_reviewer" ] && _policy_note="${_policy_note} hasReviewer=${_policy_has_reviewer};"
run_test "summary_policy_status_note" \
  "haystack: bucket=needs-assignment; needsHumanReview=true; disposition=policy-human-review; verdict=needs-review; analysisStatus=ready; rating=5; hasReviewer=false;" \
  "$_policy_note"
unset _platform_name _platform_output _policy_note _policy_bucket
unset _policy_needs_human _policy_disposition _policy_verdict
unset _policy_analysis_status _policy_rating _policy_has_reviewer

# Test 10.2: _summary_platform_list is "none" when token list is empty
_test_tokens=()
_test_spl=""
if [ "${#_test_tokens[@]}" -gt 0 ]; then
  for _sprt in "${_test_tokens[@]}"; do
    _spname="${_sprt%%:*}"; _spdisp="${_sprt#*:}"
    [ -n "$_test_spl" ] && _test_spl="${_test_spl}, "
    _test_spl="${_test_spl}${_spname} (${_spdisp})"
  done
fi
[ -z "$_test_spl" ] && _test_spl="none"
run_test "summary_platform_list_empty_tokens" "none" "$_test_spl"
unset _test_tokens _test_spl _sprt _spname _spdisp

# Test 10.3: _post_review_summary source contains the skipped result_line constant.
# _post_review_summary is defined after the HARNESS_MODE return point and cannot
# be called directly from the test harness; verify the string constant in the source
# so any accidental change to the wording is caught.
if grep -qF 'result_line="skipped — no GitHub reviewers configured in review.on_draft.github or review.on_ready.github"' \
    "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh" 2>/dev/null; then
  _skipped_constant_count=1
else
  _skipped_constant_count=0
fi
run_test "summary_result_line_skipped" "1" "$_skipped_constant_count"
unset _skipped_constant_count

# Test 10.4: _post_review_summary source renders policy-status details.
if grep -qF '**Review policy status:**' \
    "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh" \
    && grep -qF 'platform_policy_status_notes' \
      "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh"; then
  _policy_status_summary_count=1
else
  _policy_status_summary_count=0
fi
run_test "summary_policy_status_section" "1" "$_policy_status_summary_count"
unset _policy_status_summary_count

# ---------------------------------------------------------------------------
# Area 11: Step 7b regression-label auto-restore (Option C, issue #805)
#
# restore_regression_label_if_missing() is defined before the HARNESS_MODE
# return point and is therefore callable directly from the test harness.
# These tests exercise the actual function (not source-string grep) so that
# runtime regressions — e.g. a mis-scoped case branch, a missing label
# check, or a silent gh failure — are detected.
#
# The mock gh stub (already on PATH) is driven by:
#   MOCK_GH_OUTPUT       — `gh pr view` label-check result ("true"/"false")
#   MOCK_GH_COMMENTS_OUTPUT — `gh api .../comments` result (JSON array; controls
#                             summary-comment gate)
#   MOCK_GH_CALL_LOG     — records every `gh pr edit --add-label` call
#   MOCK_GH_EXIT         — controls whether gh exits with an error (all calls)
#   MOCK_GH_COMMENTS_EXIT — controls whether the comments API call exits with
#                           an error independently of MOCK_GH_EXIT
#
# Summary-comment gate (issue #805 Haystack finding):
#   label missing + summary PRESENT → restore IS called
#   label missing + summary ABSENT  → restore NOT called
#   comments API fails              → fail-open: restore IS called + WARN emitted
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 11: regression-label auto-restore (Option C, issue #805) ==="

# Reset mock vars from earlier areas.
unset MOCK_GH_POST_EXIT MOCK_GH_POST_OUTPUT MOCK_GH_CALL_LOG MOCK_GH_EXIT
unset MOCK_GH_COMMENTS_OUTPUT MOCK_GH_COMMENTS_EXIT

# JSON payload used by tests that require a summary comment to be "present".
_SUMMARY_COMMENT_JSON='[{"id":1,"body":"### Automated Reviewer Loop Summary\nAll platforms clean."}]'

# Test 11.1: label absent + summary comment PRESENT on an implementation branch
# → gh pr edit IS called (the #805 scenario: loop ran before, label was dropped
# by a push, restore is correct).
_call_log_11="$(mktemp)"
export MOCK_GH_OUTPUT="false"
export MOCK_GH_COMMENTS_OUTPUT="$_SUMMARY_COMMENT_JSON"
export MOCK_GH_CALL_LOG="$_call_log_11"
restore_regression_label_if_missing "42" "fix/42-my-fix" 2>/dev/null
_edit_calls="$(grep -c -- '--add-label' "$_call_log_11" 2>/dev/null)" || _edit_calls="0"
run_test "restore_label_absent_summary_present_calls_gh_edit" "1" "$_edit_calls"
rm -f "$_call_log_11"
unset MOCK_GH_CALL_LOG MOCK_GH_COMMENTS_OUTPUT

# Test 11.2: label already present on an implementation branch → NO gh pr edit.
# MOCK_GH_OUTPUT is "true" (label present); summary-comment gate is not reached.
_call_log_11="$(mktemp)"
export MOCK_GH_OUTPUT="true"
export MOCK_GH_CALL_LOG="$_call_log_11"
restore_regression_label_if_missing "42" "feature/42-my-feature" 2>/dev/null
_edit_calls="$(grep -c -- '--add-label' "$_call_log_11" 2>/dev/null)" || _edit_calls="0"
run_test "restore_label_already_present_no_gh_edit" "0" "$_edit_calls"
rm -f "$_call_log_11"
unset MOCK_GH_CALL_LOG

# Test 11.3: non-implementation branch (spec/) → NO gh pr edit regardless of
# label state or summary-comment presence.
_call_log_11="$(mktemp)"
export MOCK_GH_OUTPUT="false"
export MOCK_GH_COMMENTS_OUTPUT="$_SUMMARY_COMMENT_JSON"
export MOCK_GH_CALL_LOG="$_call_log_11"
restore_regression_label_if_missing "42" "spec/42-my-spec" 2>/dev/null
_edit_calls="$(grep -c -- '--add-label' "$_call_log_11" 2>/dev/null)" || _edit_calls="0"
run_test "restore_label_non_impl_branch_no_gh_edit" "0" "$_edit_calls"
rm -f "$_call_log_11"
unset MOCK_GH_CALL_LOG MOCK_GH_COMMENTS_OUTPUT

# Test 11.4: gh pr view failure (API error) → function returns 0 (fail-open),
# gh pr edit is NOT called (no false re-apply on unknown label state).
# Note: MOCK_GH_EXIT=1 affects the label-check `gh pr view` call; the function
# returns early before reaching the summary-comment gate.
_call_log_11="$(mktemp)"
export MOCK_GH_EXIT=1
export MOCK_GH_CALL_LOG="$_call_log_11"
_restore_exit=0
restore_regression_label_if_missing "42" "fix/42-api-fail" 2>/dev/null || _restore_exit=$?
run_test "restore_label_gh_view_fail_returns_0" "0" "$_restore_exit"
_edit_calls="$(grep -c -- '--add-label' "$_call_log_11" 2>/dev/null)" || _edit_calls="0"
run_test "restore_label_gh_view_fail_no_gh_edit" "0" "$_edit_calls"
rm -f "$_call_log_11"
unset MOCK_GH_CALL_LOG MOCK_GH_EXIT

# Test 11.5: hotfix/* branch + label absent + summary comment PRESENT
# → gh pr edit called (hotfix is an implementation branch; must be in scope).
_call_log_11="$(mktemp)"
export MOCK_GH_OUTPUT="false"
export MOCK_GH_COMMENTS_OUTPUT="$_SUMMARY_COMMENT_JSON"
export MOCK_GH_CALL_LOG="$_call_log_11"
restore_regression_label_if_missing "99" "hotfix/99-critical" 2>/dev/null
_edit_calls="$(grep -c -- '--add-label' "$_call_log_11" 2>/dev/null)" || _edit_calls="0"
run_test "restore_label_hotfix_branch_calls_gh_edit" "1" "$_edit_calls"
rm -f "$_call_log_11"
unset MOCK_GH_CALL_LOG MOCK_GH_COMMENTS_OUTPUT

# Test 11.6: restore function is defined before the HARNESS_MODE return point
# (source-level ordering check — ensures the function remains testable after
# future refactors move it).
_restore_fn_line="$(grep -n 'restore_regression_label_if_missing()' \
  "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh" 2>/dev/null \
  | head -1 | cut -d: -f1)"
_harness_return_line="$(grep -n '_HARNESS_MODE_EFFECTIVE.*return 0' \
  "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh" 2>/dev/null \
  | head -1 | cut -d: -f1)"
if [ -n "$_restore_fn_line" ] && [ -n "$_harness_return_line" ] \
    && [ "$_restore_fn_line" -lt "$_harness_return_line" ]; then
  _fn_ordering_ok="yes"
else
  _fn_ordering_ok="no"
fi
run_test "restore_fn_defined_before_harness_return" "yes" "$_fn_ordering_ok"
unset _restore_fn_line _harness_return_line _fn_ordering_ok

# Test 11.7: label absent + summary comment ABSENT → gh pr edit NOT called.
# This is the normal initial state (loop has never run) or the window in which
# a human intentional removal is unambiguous. The restore must be suppressed.
_call_log_11="$(mktemp)"
export MOCK_GH_OUTPUT="false"
export MOCK_GH_COMMENTS_OUTPUT="[]"
export MOCK_GH_CALL_LOG="$_call_log_11"
restore_regression_label_if_missing "42" "fix/42-no-summary" 2>/dev/null
_edit_calls="$(grep -c -- '--add-label' "$_call_log_11" 2>/dev/null)" || _edit_calls="0"
run_test "restore_label_absent_summary_absent_no_gh_edit" "0" "$_edit_calls"
rm -f "$_call_log_11"
unset MOCK_GH_CALL_LOG MOCK_GH_COMMENTS_OUTPUT

# Test 11.8: label absent + comments API failure → fail-open: gh pr edit IS called
# and a WARN is emitted. Rationale: the #805 regression (label silently dropped
# after loop ran) is the higher-frequency real-world failure; when we cannot
# determine whether the loop ran, restoring is the safer choice.
_call_log_11="$(mktemp)"
export MOCK_GH_OUTPUT="false"
export MOCK_GH_COMMENTS_EXIT=1
export MOCK_GH_CALL_LOG="$_call_log_11"
_warn_output="$(restore_regression_label_if_missing "42" "fix/42-comments-fail" 2>&1)"
_edit_calls="$(grep -c -- '--add-label' "$_call_log_11" 2>/dev/null)" || _edit_calls="0"
run_test "restore_label_comments_api_fail_failopen_calls_gh_edit" "1" "$_edit_calls"
# Verify WARN is emitted (not silent).
if printf '%s\n' "$_warn_output" | grep -q "WARN"; then
  _warn_emitted="yes"
else
  _warn_emitted="no"
fi
run_test "restore_label_comments_api_fail_warn_emitted" "yes" "$_warn_emitted"
rm -f "$_call_log_11"
unset MOCK_GH_CALL_LOG MOCK_GH_COMMENTS_EXIT _warn_output

# Reset mock state.
export MOCK_GH_OUTPUT='[]'
unset MOCK_GH_EXIT MOCK_GH_COMMENTS_OUTPUT MOCK_GH_COMMENTS_EXIT
unset _SUMMARY_COMMENT_JSON

# ---------------------------------------------------------------------------
# Area 12: reviewer-failed label sync (issue #804)
#
# reviewer_failed_label_required_for_result(), ensure_reviewer_failed_label_exists(),
# and sync_reviewer_failed_label() are defined before the HARNESS_MODE return point
# and are therefore callable directly from the test harness.
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 12: reviewer-failed label sync (issue #804) ==="

_reviewer_failed_required() {
  if reviewer_failed_label_required_for_result "$1" "${2:-}"; then
    printf 'yes'
  else
    printf 'no'
  fi
}

run_test "reviewer_failed_escalate_timeout" "yes" "$(_reviewer_failed_required escalate timeout)"
run_test "reviewer_failed_escalate_empty_reason" "yes" "$(_reviewer_failed_required escalate '')"
run_test "reviewer_failed_escalate_pending_timeout" "yes" "$(_reviewer_failed_required escalate pending_timeout)"
run_test "reviewer_failed_skipped_unavailable" "yes" "$(_reviewer_failed_required skipped unavailable)"
run_test "reviewer_failed_skipped_thread_check_failed" "yes" "$(_reviewer_failed_required skipped thread-check-failed)"
run_test "reviewer_failed_skipped_not_configured" "no" "$(_reviewer_failed_required skipped not_configured)"
run_test "reviewer_failed_clean_no" "no" "$(_reviewer_failed_required clean timeout)"
run_test "reviewer_failed_needs_fixes_no" "no" "$(_reviewer_failed_required needs_fixes '')"
run_test "reviewer_failed_needs_rerun_no" "no" "$(_reviewer_failed_required needs_rerun '')"

_rf_accumulated=0
if reviewer_failed_label_required_for_result clean ""; then
  _rf_accumulated=1
fi
if reviewer_failed_label_required_for_result skipped unavailable; then
  _rf_accumulated=1
fi
if reviewer_failed_label_required_for_result clean ""; then
  _rf_accumulated=1
fi
run_test "reviewer_failed_accumulator_or" "1" "$_rf_accumulated"
unset _rf_accumulated

unset MOCK_GH_CALL_LOG MOCK_GH_EXIT MOCK_GH_LABEL_VIEW_EXIT MOCK_GH_LABEL_CREATE_EXIT MOCK_GH_PR_EDIT_EXIT

_call_log_12="$(mktemp)"
export MOCK_GH_CALL_LOG="$_call_log_12"
export MOCK_GH_LABEL_VIEW_EXIT=1
sync_reviewer_failed_label "42" "1" 2>/dev/null
_create_calls="$(grep -c -- 'label create reviewer-failed' "$_call_log_12" 2>/dev/null)" || _create_calls="0"
_add_calls="$(grep -c -- 'pr edit 42 --add-label reviewer-failed' "$_call_log_12" 2>/dev/null)" || _add_calls="0"
run_test "reviewer_failed_required_creates_missing_label" "1" "$_create_calls"
run_test "reviewer_failed_required_adds_label" "1" "$_add_calls"
rm -f "$_call_log_12"
unset MOCK_GH_CALL_LOG MOCK_GH_LABEL_VIEW_EXIT

_call_log_12="$(mktemp)"
export MOCK_GH_CALL_LOG="$_call_log_12"
export MOCK_GH_LABEL_VIEW_EXIT=0
sync_reviewer_failed_label "42" "1" 2>/dev/null
_create_calls="$(grep -c -- 'label create reviewer-failed' "$_call_log_12" 2>/dev/null)" || _create_calls="0"
_add_calls="$(grep -c -- 'pr edit 42 --add-label reviewer-failed' "$_call_log_12" 2>/dev/null)" || _add_calls="0"
run_test "reviewer_failed_existing_label_no_create" "0" "$_create_calls"
run_test "reviewer_failed_existing_label_adds_label" "1" "$_add_calls"
rm -f "$_call_log_12"
unset MOCK_GH_CALL_LOG MOCK_GH_LABEL_VIEW_EXIT

_call_log_12="$(mktemp)"
export MOCK_GH_CALL_LOG="$_call_log_12"
export MOCK_GH_OUTPUT='reviewer-failed'
sync_reviewer_failed_label "42" "0" 2>/dev/null
_remove_calls="$(grep -c -- 'pr edit 42 --remove-label reviewer-failed' "$_call_log_12" 2>/dev/null)" || _remove_calls="0"
run_test "reviewer_failed_not_required_removes_present_label" "1" "$_remove_calls"
rm -f "$_call_log_12"
unset MOCK_GH_CALL_LOG MOCK_GH_OUTPUT

_call_log_12="$(mktemp)"
export MOCK_GH_CALL_LOG="$_call_log_12"
export MOCK_GH_OUTPUT='some-other-label'
sync_reviewer_failed_label "42" "0" 2>/dev/null
_remove_calls="$(grep -c -- 'pr edit 42 --remove-label reviewer-failed' "$_call_log_12" 2>/dev/null)" || _remove_calls="0"
run_test "reviewer_failed_not_required_absent_noop" "0" "$_remove_calls"
rm -f "$_call_log_12"
unset MOCK_GH_CALL_LOG MOCK_GH_OUTPUT

_call_log_12="$(mktemp)"
export MOCK_GH_CALL_LOG="$_call_log_12"
export MOCK_GH_EXIT=1
export MOCK_GH_PR_EDIT_EXIT=0
sync_reviewer_failed_label "42" "0" 2>/dev/null
_remove_calls="$(grep -c -- 'pr edit 42 --remove-label reviewer-failed' "$_call_log_12" 2>/dev/null)" || _remove_calls="0"
run_test "reviewer_failed_not_required_view_failure_attempts_remove" "1" "$_remove_calls"
rm -f "$_call_log_12"
unset MOCK_GH_CALL_LOG MOCK_GH_EXIT MOCK_GH_PR_EDIT_EXIT

_call_log_12="$(mktemp)"
export MOCK_GH_CALL_LOG="$_call_log_12"
export MOCK_GH_LABEL_VIEW_EXIT=1
export MOCK_GH_LABEL_CREATE_EXIT=1
_sync_exit=0
_warn_output="$(sync_reviewer_failed_label "42" "1" 2>&1)" || _sync_exit=$?
_add_calls="$(grep -c -- 'pr edit 42 --add-label reviewer-failed' "$_call_log_12" 2>/dev/null)" || _add_calls="0"
run_test "reviewer_failed_create_failure_returns_0" "0" "$_sync_exit"
run_test "reviewer_failed_create_failure_still_attempts_add" "1" "$_add_calls"
if printf '%s\n' "$_warn_output" | grep -q "WARN"; then
  _warn_emitted="yes"
else
  _warn_emitted="no"
fi
run_test "reviewer_failed_create_failure_warns" "yes" "$_warn_emitted"
rm -f "$_call_log_12"
unset MOCK_GH_CALL_LOG MOCK_GH_LABEL_VIEW_EXIT MOCK_GH_LABEL_CREATE_EXIT _warn_output _sync_exit

_call_log_12="$(mktemp)"
export MOCK_GH_CALL_LOG="$_call_log_12"
sync_reviewer_failed_label "42" "1" 2>/dev/null
_ready_label_mentions="$(grep -c -- 'ready-for-human-review' "$_call_log_12" 2>/dev/null)" || _ready_label_mentions="0"
run_test "reviewer_failed_does_not_touch_ready_label" "0" "$_ready_label_mentions"
rm -f "$_call_log_12"
unset MOCK_GH_CALL_LOG

_reviewer_failed_fn_line="$(grep -n 'reviewer_failed_label_required_for_result()' \
  "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh" 2>/dev/null \
  | head -1 | cut -d: -f1)"
_sync_fn_line="$(grep -n 'sync_reviewer_failed_label()' \
  "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh" 2>/dev/null \
  | head -1 | cut -d: -f1)"
_harness_return_line="$(grep -n '_HARNESS_MODE_EFFECTIVE.*return 0' \
  "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh" 2>/dev/null \
  | head -1 | cut -d: -f1)"
if [ -n "$_reviewer_failed_fn_line" ] && [ -n "$_sync_fn_line" ] \
    && [ -n "$_harness_return_line" ] \
    && [ "$_reviewer_failed_fn_line" -lt "$_harness_return_line" ] \
    && [ "$_sync_fn_line" -lt "$_harness_return_line" ]; then
  _reviewer_failed_ordering_ok="yes"
else
  _reviewer_failed_ordering_ok="no"
fi
run_test "reviewer_failed_helpers_before_harness_return" "yes" "$_reviewer_failed_ordering_ok"
unset _reviewer_failed_required _reviewer_failed_fn_line _sync_fn_line _harness_return_line _reviewer_failed_ordering_ok
unset MOCK_GH_EXIT MOCK_GH_LABEL_VIEW_EXIT MOCK_GH_LABEL_CREATE_EXIT MOCK_GH_PR_EDIT_EXIT

# ---------------------------------------------------------------------------
# Area 13: PR #801 follow-up coverage for reviewer-loop failure paths
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 13: PR #801 reviewer-loop failure paths ==="

export MOCK_GH_OUTPUT='{
  "pageInfo": {"hasNextPage": false, "endCursor": null},
  "nodes": [
    {
      "id": "thread-outdated",
      "isResolved": false,
      "isOutdated": true,
      "comments": {
        "nodes": [
          {
            "author": {"login": "chatgpt-codex-connector"},
            "body": "stale Codex finding"
          }
        ]
      }
    },
    {
      "id": "thread-active",
      "isResolved": false,
      "isOutdated": false,
      "comments": {
        "nodes": [
          {
            "author": {"login": "chatgpt-codex-connector"},
            "body": "active Codex finding"
          }
        ]
      }
    }
  ]
}'
run_test "codex_thread_audit_ignores_outdated" "1" \
  "$(check_unresolved_threads "42" "owner/repo" "chatgpt-codex-connector")"
export MOCK_GH_OUTPUT='{
  "pageInfo": {"hasNextPage": false, "endCursor": null},
  "nodes": [
    {
      "id": "thread-outdated",
      "isResolved": false,
      "isOutdated": true,
      "comments": {
        "nodes": [
          {
            "author": {"login": "chatgpt-codex-connector"},
            "body": "stale Codex finding"
          }
        ]
      }
    }
  ]
}'
run_test "codex_thread_audit_all_outdated_clean" "0" \
  "$(check_unresolved_threads "42" "owner/repo" "chatgpt-codex-connector")"
unset MOCK_GH_OUTPUT
if grep -q "Codex acknowledgement detected; waiting for thumbs-up reaction or inline review comments" \
    "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh"; then
  _codex_ack_wait_signal="yes"
else
  _codex_ack_wait_signal="no"
fi
run_test "codex_reviewer_ack_wait_signal" "yes" "$_codex_ack_wait_signal"
unset _codex_ack_wait_signal

_unlock_pr="80213$$"
_unlock_lock_dir="/tmp/pr-review-loop-${_unlock_pr}.lockdir"
rm -rf "$_unlock_lock_dir"
mkdir -p "$_unlock_lock_dir/pid"
printf '%s\n' "pr-review-loop.sh" > "$_unlock_lock_dir/cmd"
_unlock_exit=0
_unlock_output="$("$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh" unlock "$_unlock_pr" 2>&1)" || _unlock_exit=$?
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
_unlock_lock_dir="/tmp/pr-review-loop-${_unlock_pr}.lockdir"
rm -rf "$_unlock_lock_dir"
mkdir -p "$_unlock_lock_dir/cmd"
printf '%s\n' "999999" > "$_unlock_lock_dir/pid"
_unlock_exit=0
_unlock_output="$("$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh" unlock "$_unlock_pr" 2>&1)" || _unlock_exit=$?
run_test "unlock_unreadable_cmd_exits_1" "1" "$_unlock_exit"
if printf '%s\n' "$_unlock_output" | grep -q "could not read lock cmd"; then
  _unlock_error_seen="yes"
else
  _unlock_error_seen="no"
fi
run_test "unlock_unreadable_cmd_error" "yes" "$_unlock_error_seen"
rm -rf "$_unlock_lock_dir"
unset _unlock_pr _unlock_lock_dir _unlock_output _unlock_exit _unlock_error_seen

_codex_overrides='
  cd_workflow_repo_root() { :; }
  repo_slug() { printf "owner/repo\n"; }
  require_gh() { :; }
  check_unresolved_threads() { return 3; }
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
_post_review_summary "escalate" "thread-check-failed" "codex-github" "0" "0" 2>/dev/null
_body_file="$(awk '/pr comment 42 --body-file / {print $NF}' "$_summary_call_log" | tail -n 1)"
if [ -n "$_body_file" ] && [ ! -e "$_body_file" ]; then
  _body_file_removed="yes"
else
  _body_file_removed="no"
fi
run_test "post_summary_removes_body_file_on_failure" "yes" "$_body_file_removed"
rm -f "$_summary_call_log"
unset MOCK_GH_CALL_LOG MOCK_GH_EXIT MOCK_GH_COMMENTS_OUTPUT
unset _post_summary_source _summary_call_log _body_file _body_file_used _body_file_removed
unset -f _post_review_summary repo_slug

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "Tests: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
